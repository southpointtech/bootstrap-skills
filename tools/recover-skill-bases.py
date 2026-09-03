#!/usr/bin/env python3
"""Recupera, por similitud, la base de merge de cada skill externa del scaffold.

Ver docs/agents/recuperar-base-de-skills.md para el cómo y el porqué.
"""
from __future__ import annotations

import argparse
import datetime
import difflib
import json
import os
import re
import subprocess
import sys
import tempfile


# --------------------------------------------------------------------------- #
# Primitivas de git
# --------------------------------------------------------------------------- #

def _git(repo, *args):
    """Corre git en `repo` y devuelve stdout como texto."""
    return _git_bytes(repo, *args).decode("utf-8", "replace")


def _git_bytes(repo, *args, stdin=None):
    p = subprocess.run(["git", "-C", repo, *args], input=stdin,
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if p.returncode != 0:
        raise RuntimeError("git %s falló (%d): %s"
                           % (" ".join(args), p.returncode,
                              p.stderr.decode("utf-8", "replace").strip()))
    return p.stdout


def is_git_repo(path):
    """¿`path` es la RAÍZ de un repo de git? Vale bare, worktree y clon normal.

    Mirar si existe un `.git` que sea *directorio* deja afuera los clones bare (no tienen
    `.git`) y los worktrees (ahí `.git` es un archivo). Se lo preguntamos a git.

    Preguntar solamente no alcanza: `git rev-parse` **sube por el árbol**, así que cualquier
    carpeta de adentro de un repo contesta que sí. Un `--upstream-clone` mal tipeado que caiga
    adentro de este repo lo tomaría por el clon de upstream, encontraría nuestros propios
    `*/SKILL.md` y emitiría bases con similitud 1.0 citando commits nuestros — veneno para el
    lockfile, y silencioso. Por eso se compara contra la raíz que git reporta.
    """
    if not os.path.isdir(path):
        return False
    try:
        bare = _git(path, "rev-parse", "--is-bare-repository").strip() == "true"
        # en un bare la raíz es el git dir; en uno normal, la del árbol de trabajo
        root = _git(path, "rev-parse",
                    "--absolute-git-dir" if bare else "--show-toplevel").strip()
    except (RuntimeError, OSError):
        return False
    return bool(root) and os.path.realpath(root) == os.path.realpath(path)


def origin_url(repo):
    """La URL real del remoto `origin` del clon, o None si no tiene."""
    try:
        return _git(repo, "config", "--get", "remote.origin.url").strip() or None
    except RuntimeError:
        return None


def _repo_rel(path):
    """Ruta relativa al repo si cae adentro; si no, la absoluta.

    `os.path.relpath` revienta con `ValueError` cuando los paths están en unidades
    distintas, y cuando no revienta devuelve una ristra de `..` sin sentido para un
    directorio que no está bajo el repo.
    """
    ap = os.path.abspath(path)
    try:
        rel = os.path.relpath(ap, REPO)
    except ValueError:
        return ap.replace(os.sep, "/")
    if rel == os.pardir or rel.startswith(os.pardir + os.sep):
        return ap.replace(os.sep, "/")
    return rel.replace(os.sep, "/")


# --------------------------------------------------------------------------- #
# Cuerpo sin frontmatter
# --------------------------------------------------------------------------- #

# Cierra el frontmatter la primera línea posterior a la apertura que sea `---` sola.
#
# Buscar `\n---` pelado NO sirve: casa también `\n----` y `\n--- texto`, corta en la línea
# equivocada y deja el cierre real adentro del cuerpo — el bug que este patrón reemplaza.
#
# Los espacios y tabs DESPUÉS de los tres guiones tampoco cuentan, y esa mitad importa igual:
# exigir `\n---\n` exacto hace que un cierre `---␣` (invisible al leer) se lea como "no hay
# cierre", y entonces el frontmatter entero entra al cuerpo. Acá eso mueve un número en
# silencio, no un hash ruidoso. Medido el 2026-09-03 sobre las skills locales, ensuciando el
# cierre con UN espacio y leyendo ese documento con el lector estricto, contra el cuerpo
# limpio: `zoom-out` da 0.4009 y `grill-me` 0.5551, los dos **abajo del umbral de 0.60**, o sea
# que saldrían `unmatched` por un espacio. (Un `.strip()` de más o de menos al construir el
# lado sucio mueve el cuarto decimal: estos son con el `.strip()` de `body_of` en los dos
# lados.) Hoy no lo dispara nadie —0 de los 413 blobs de upstream y 0 de los 49 `SKILL.md`
# locales cierran con whitespace— así que esto es una red, no un arreglo de algo que falla.
#
# `\Z` cubre el cierre en la última línea sin salto final: ahí el cuerpo queda vacío.
#
# Por qué NO es la misma regla que `tools/normalized-hash.ps1 -Scope Body`, aunque el
# delimitador sí lo sea: aquel exige `\n---\n` sin tolerar whitespace (allá un byte de más es
# drift real y se ve), y además NO saca el BOM antes de mirar la apertura, así que un
# documento con BOM no recorta nada — medido: su `-Scope Body` devuelve el hash del archivo
# entero. Acá el BOM se saca primero. Delimitador parecido, alcance distinto.
_CIERRE_FRONTMATTER = re.compile(r"\n---[ \t]*(?:\n|\Z)")


def body_of(text):
    """Cuerpo de un SKILL.md: sin frontmatter, con fines de línea LF y extremos recortados.

    El drift propio de estas skills vive casi todo en la `description`, así que la
    similitud se mide sobre el cuerpo (ADR-0005). La normalización de fines de línea
    es obligatoria: nuestra copia está en CRLF y los blobs de upstream en LF.
    """
    t = text.replace("\r\n", "\n").replace("\r", "\n")
    if t and ord(t[0]) == 0xFEFF:          # BOM
        t = t[1:]
    if t.startswith("---\n"):
        m = _CIERRE_FRONTMATTER.search(t, 3)
        # Sin linea de cierre no hay frontmatter: el cuerpo es todo el contenido.
        t = t[m.end():] if m else t
    return t.strip()


def similarity(a, b):
    """Ratio de `SequenceMatcher` sobre los dos cuerpos, con el `autojunk` de la libreria.

    `autojunk` viene activo por default y se dispara por el largo de la SEGUNDA secuencia:
    cuando `len(b) >= 200`, los elementos que aparecen en mas de `len(b)//100 + 1` posiciones
    de `b` se marcan "populares" y salen del indice, asi que no pueden SEMBRAR un match
    (uno ya sembrado si se extiende sobre ellos: un cuerpo contra si mismo sigue dando 1.0).
    Sobre markdown comparado caracter a caracter, "popular" son las letras comunes.

    Como `b` es el blob de upstream, el heuristico se dispara en casi TODA comparacion del
    corpus, no solo en los cuerpos largos. Medido el 2026-08-31 sobre las skills locales:
    `zoom-out` (169 B) contra `slice-review` da 0.0020 con autojunk y 0.0086 sin el (4,2x),
    y al revés —`slice-review` contra `zoom-out`, donde `b` tiene 169 elementos y no llega
    a 200— da 0.0083 con y sin el heuristico. La asimetria ES la firma de que depende de `b`.

    El efecto sobre el REPORTE es mas chico, pero lo que esta medido tiene borde: apagarlo
    movio el numero publicado y el blob elegido de `review-loop` y `slice-review` (0.0308 y
    0.0202 medidos el 2026-08-28 con autojunk; 0.1305 y 0.1101 el 2026-08-31 sin el, contra
    otro blob). De las otras nueve, las dos con drift dan el mismo ratio contra su base con
    y sin el (`tdd` 0.8450, `to-issues` 0.9466, re-medidos el 2026-09-03; iguales a los seis
    decimales en los dos casos). El `tdd` publicado antes era 0.8625, medido el 2026-08-31,
    y ya no se reproduce: `87f11fe` edito el cuerpo local DESPUES de esa medicion. No lo movio
    el arreglo del delimitador de frontmatter de `body_of` — con la version vieja y la nueva
    el cuerpo de las once skills es identico, y el ratio de `tdd` da 0.844958 con las dos.
    O sea que este numero envejece con cada edicion del scaffold. Y las siete restantes
    publican 1.0. Dos limites de eso, para no leerlo de mas: el 1.0 es el ratio REDONDEADO
    (`exactBodyMatches` es el campo que habla de cuerpos identicos) y no se verifico que
    ningun otro de los 413 blobs las supere con el heuristico apagado. O sea "solo esas dos cambian" vale para el numero contra su
    base, no para toda la busqueda. Ningun veredicto cambia: los cuatro numeros de las dos
    sin match estan lejos del umbral de 0.60.

    No se apaga por costo medido el 2026-08-31: `autojunk=False` lleva la corrida de ~98 s a
    ~2.500-3.500 s. Cambiar la metrica (tokenizar por linea) es el issue 19.

    El ratio con el que se ELIGE la base no pasa por aca: se calcula en `_best_blobs`, que
    llama a `SequenceMatcher` directo para poder usar las cotas baratas. Esta funcion tiene
    un solo call site de produccion —los `unconfirmedSuccessorCandidates`—, y ese numero
    tambien se publica. Lo de arriba vale igual para las dos llamadas: misma libreria, mismo
    default.
    """
    return difflib.SequenceMatcher(None, a, b).ratio()


# --------------------------------------------------------------------------- #
# Inventario de upstream
# --------------------------------------------------------------------------- #

def _skill_blobs(upstream):
    """Todos los blobs `*/SKILL.md` alcanzables en la historia publicada de upstream.

    `rev-list --objects --all` recorre todos los objetos alcanzables desde todas las
    refs; cada blob aparece una vez, con el path en el que se lo encontró primero.
    """
    out = []
    for line in _git(upstream, "rev-list", "--objects", "--all").splitlines():
        oid, _, path = line.partition(" ")
        if path.endswith("SKILL.md"):
            out.append((oid, path))
    return out


def _read_blobs(upstream, oids):
    """Lee muchos blobs de una sola pasada con `cat-file --batch`.

    Un oid que el repo no puede entregar vuelve como `<oid> missing`: dos campos, sin contenido
    y sin el `\\n` que cierra a los demas. `split()[2]` levantaba ahi un `IndexError` que no
    nombraba ni el oid ni la causa, y se llevaba puesta la corrida entera.

    Cuando aparece ese header, medido el 2026-09-03 con git 2.53:

      - un oid que el repo directamente no tiene (fabricado, o podado): `missing`, exit 0;
      - un clon parcial (`--filter=blob:none`) con `GIT_NO_LAZY_FETCH=1`: `missing`, exit 0;
      - un clon parcial SIN esa variable y con el promisor inalcanzable: git **no** llega a
        imprimir `missing` — intenta el fetch, falla, y sale con **exit 128**. Ahi levanta
        `_git_bytes`, antes que nada de esta funcion. O sea: el guard de abajo NO es la red de
        ese caso, y decir lo contrario seria falso.

    El ausente simplemente NO entra al dict: leer no es donde se decide que hacer con lo que
    falta. Quien pide decide — `_exigir_blobs` para el corpus de candidatos, saltear para las
    pistas de sucesor.
    """
    if not oids:
        return {}
    raw = _git_bytes(upstream, "cat-file", "--batch",
                     stdin=("\n".join(oids) + "\n").encode("ascii"))
    return _parse_batch(raw, oids)


def _parse_batch(raw, oids):
    """Parsea la salida cruda de `cat-file --batch` contra los oids que se pidieron.

    Separada de `_read_blobs` para poder alimentarla con bytes FABRICADOS: un batch cortado a
    la mitad, o un header con un payload que corra el desplazamiento, no salen de git pidiendo
    normal, y sin esta costura esas ramas serian codigo sin test.

    Contrato de entrada: `oids` son los oids **resueltos**, 40 hex en minuscula, que es lo que
    git eco-a en cada header. Un oid abreviado o en mayuscula NO cumple —git eco-a igual el
    resuelto— y el guard de abajo lo corta. Los dos call-sites de produccion cumplen: salen de
    `rev-list --objects --all` y de `rev-parse HEAD:<path>`.
    """
    contents = {}
    i = 0
    for procesados, oid in enumerate(oids):
        # Un batch que se corta antes de tiempo levantaba `ValueError` pelado desde `index`, que
        # NO es `RuntimeError`: se escapaba del handler de `main` y volvia a salir como traceback
        # con exit 1 — exactamente lo que el exit 5 vino a sacar. Misma familia que el header
        # desincronizado, mismo tratamiento.
        j = raw.find(b"\n", i)
        if j == -1:
            raise RuntimeError(
                "`cat-file --batch` devolvio una salida truncada: se esperaba la cabecera de %s "
                "y no hay ninguna linea mas. Procesados %d de %d objetos."
                # La posicion del loop, no `oids.index(oid)`: `index` devuelve la PRIMERA
                # aparicion, asi que con un oid repetido el mensaje miente hacia atras.
                % (oid, procesados, len(oids)))
        cabecera = raw[i:j].split()
        # Cada header arranca con el oid RESUELTO (40 hex minuscula), asi que compararlo contra
        # el que pedimos es gratis y ancla el recorrido: si un header arrastrara una linea de
        # payload, el desplazamiento se correria y los blobs quedarian atribuidos al oid
        # EQUIVOCADO. Esa es la mentira silenciosa que `_exigir_blobs` no puede atrapar —todos
        # los oids figurarian presentes—, y es peor que cortar la corrida.
        # Ojo con el reves: como git eco-a el RESUELTO y no lo que se le mando, pedir un oid
        # abreviado o en mayuscula tambien dispara este guard. Es el contrato de entrada del
        # docstring, no un bug; los dos call-sites de produccion pasan 40 hex minuscula.
        if not cabecera or cabecera[0] != oid.encode("ascii"):
            raise RuntimeError(
                "`cat-file --batch` se desincronizo: para el oid %s devolvio la cabecera %r. "
                "El recorrido no puede seguir sin atribuir contenidos al oid equivocado."
                % (oid, raw[i:j][:120]))
        # `<oid> missing` y `<oid> ambiguous` son headers de dos campos (verificados los dos con
        # git 2.53; `ambiguous` no se alcanza acá, porque todos los oids vienen de `rev-list` /
        # `rev-parse` con sus 40 hex completos). Cualquier otro header de menos de tres campos
        # cae igual acá: no hay contenido que saltear, se avanza solo la linea.
        if len(cabecera) < 3:
            i = j + 1
            continue
        # `int()` sobre un tercer campo que no es un numero levanta `ValueError`, que NO es
        # `RuntimeError` y por lo tanto se escapa del handler de `main` y vuelve a dar exit 1
        # con traceback. Igual que el corte de mas arriba; el guard del `size` de abajo es de
        # otra clase —ese no explotaba, devolvia contenido truncado en silencio.
        if not cabecera[2].isdigit():
            raise RuntimeError(
                "`cat-file --batch` devolvio un tamaño que no es un numero para %s: %r."
                % (oid, cabecera[2][:40]))
        size = int(cabecera[2])
        # Un `size` que se pasa del largo de `raw` truncaria el contenido en silencio, y con un
        # solo oid no hay iteracion siguiente que lo note.
        if j + 1 + size > len(raw):
            raise RuntimeError(
                "`cat-file --batch` anuncio %d bytes para %s y la salida tiene %d: esta "
                "truncada." % (size, oid, len(raw) - (j + 1)))
        contents[oid] = raw[j + 1:j + 1 + size]
        i = j + 1 + size + 1          # +1 por el \n que cierra cada objeto
    return contents


def _exigir_blobs(contents, oids, contexto):
    """Aborta si el batch no devolvio alguno de los blobs pedidos.

    Que la lectura no explote no alcanza para el corpus de candidatos: con un blob de menos
    se elige OTRA base, o ninguna, y la skill se publica como fork propio sin que nada lo
    diga. Un reporte que miente en silencio es peor que una corrida que se corta.
    """
    faltan = [o for o in oids if o not in contents]
    if faltan:
        # El detalle se trunca a tres, y se DICE que se trunca: sin el "y N mas", una lista de
        # tres se lee como la lista completa. `contexto` nombra QUE corpus vino incompleto —hoy
        # lo llama un solo caller (el de candidatos), porque el de las pistas de sucesor
        # deliberadamente degrada en vez de exigir; el parametro existe para que el mensaje
        # oriente, no para distinguir dos llamadas que existan hoy.
        detalle = ", ".join(faltan[:3])
        if len(faltan) > 3:
            detalle += " y %d mas" % (len(faltan) - 3)
        raise RuntimeError(
            "upstream no devolvio %d de los %d blobs pedidos (%s): %s. El repo no los tiene: "
            "puede estar incompleto o podado, o ser un clon parcial (--filter=blob:none), que "
            "lista los oids sin tener los blobs. Traelos con `git fetch` o cloná entero."
            % (len(faltan), len(oids), contexto, detalle))


def _history(upstream):
    """(introducciones, renombres) leídas de un único recorrido del log.

    - introducciones: blob -> [{commit, epoch, date, subject, path, seq}, ...], TODAS las
      apariciones del blob, en cualquier path. Elegir sobre el par (blob, path) de un solo
      path esconde las apariciones más viejas del mismo contenido en otro path.
    - renombres: path viejo -> {paths nuevos}

    El orden por instante se lee de `%ct` (epoch), no de `%cI`: el ISO lleva el offset
    local, así que comparado como string ordena por reloj de pared. Un repo con commits
    de husos distintos —los de la web de GitHub son siempre `+00:00`— se ordena mal.

    `git log` emite del más nuevo al más viejo, así que una posición mayor es un commit
    más viejo. Eso desempata los instantes iguales al segundo, que existen y si no se
    desempatan hacen elegir la aparición más nueva en vez de la primera.

    Los tres knobs que deciden cómo se lee esta salida se **fijan acá**, no se heredan.
    `--raw` respeta `diff.renames` y `diff.renameLimit` del repo y del usuario, así que era
    la máquina que corre la herramienta la que decidía si el renombre se veía o no. Con
    `diff.renames=false` el log no emite una sola `R`, `renames` queda vacío, y una skill
    viva en el HEAD de upstream sale clasificada como si upstream la hubiera borrado.
    `renameLimit=0` es "sin límite": con un presupuesto chico git saltea la detección
    inexacta —la de los renombres CON edición— y avisa por stderr, y ése es justamente el
    caso de las skills que upstream renombró mientras las editaba.

    El tercero es `core.quotePath`, y su **default (`true`) ya es el valor peligroso**: no
    hace falta que nadie configure mal nada. Con él, todo path que tenga un byte no ASCII
    sale C-quoteado (`"skills/caf\\303\\251/SKILL.md"`, comillas incluidas). Acá el path
    quoteado no se pierde —el pathspec `-- '*SKILL.md'` lo aplica git antes de quotear— pero
    entra a `renames` y a `intro` con una forma que no matchea contra `head_paths`, que sale
    de `ls-tree`. En `recover()` la misma opción muerde por otra puerta: ahí sí hay un filtro
    `endswith("SKILL.md")` que no reconoce la forma quoteada y tira la skill del inventario.
    Distinto mecanismo, mismo desenlace, y los dos medidos. `rev-list --objects` no aplica
    `quotePath`, así que sin fijarlo las dos vistas del mismo path ni siquiera coinciden.

    Solo renombres, no copias: con `diff.renames=true` git nunca emite `C`, así que el
    manejo de `C` de abajo hoy es inalcanzable. **No es neutral**: esa rama mete el par de
    una copia en `renames`, o sea trata una copia como si fuera un renombre, y `_head_path`
    seguiría esa arista hasta el destino de la copia — inventando un sucesor, que en esta
    herramienta es siempre decisión humana (los candidatos se emiten como pistas, nunca
    como base). Se conserva sólo porque hoy no se alcanza, y no por configuración: el `-c`
    de acá **pisa** cualquier `diff.renames=copies` del repo o del usuario, así que llegar a
    esa rama exige editar esta misma línea. Quien la edite tiene que revisarla antes.
    """
    sep = "\x01"
    raw = _git(upstream, "-c", "diff.renames=true", "-c", "diff.renameLimit=0",
               "-c", "core.quotepath=false",
               "log", "--all", "--full-history",
               "--format=%s%%H\x1f%%ct\x1f%%cI\x1f%%s" % sep,
               "--raw", "--no-abbrev", "--", "*SKILL.md")
    intro, renames = {}, {}
    commit = epoch = date = subject = None
    seq = -1
    for line in raw.splitlines():
        if line.startswith(sep):
            commit, epoch, date, subject = line[1:].split("\x1f", 3)
            epoch = int(epoch)
            seq += 1
        elif line.startswith(":"):
            fields = line.split("\t")
            meta = fields[0].split()
            new_sha, status = meta[3], meta[4]
            path = fields[-1]                      # en R/C el path nuevo es el último
            if status[0] in ("R", "C") and len(fields) >= 3:
                renames.setdefault(fields[1], set()).add(fields[2])
            if status[0] in ("A", "M", "T", "R", "C"):
                intro.setdefault(new_sha, []).append(
                    {"commit": commit, "epoch": epoch, "date": date,
                     "subject": subject, "path": path, "seq": seq})
    return intro, renames


def _intro_key(e):
    """Orden entre apariciones: instante, después commit más viejo del log, después path.

    Único lugar donde se decide qué aparición es más vieja. Estaba escrito dos veces —una
    para elegir dentro de un blob y otra para elegir entre blobs empatados— y la segunda
    copia se podía romper sin que nada la mordiera.
    """
    return (e["epoch"], -e["seq"], e["path"])


def _oldest_intro(entries):
    """La aparición más vieja de un blob: menor instante y, a igual instante, commit más viejo."""
    if not entries:
        return None
    return min(entries, key=_intro_key)


def _best_blobs(mine, bodies):
    """(mejor ratio, [blobs empatados en ese ratio]).

    El empate NO es una rareza: medido el 2026-08-28 sobre `mattpocock/skills`, 34 de los
    373 cuerpos distintos existen en más de un blob (74 de 413 blobs), porque upstream
    retoca la `description` sin tocar el cuerpo. Quedarse con el primero que aparece elige
    el blob más nuevo, que es el orden en que los emite `rev-list`.
    """
    best, tied = 0.0, []
    for oid, other in bodies.items():
        sm = difflib.SequenceMatcher(None, mine, other)
        # cotas baratas: si el techo no llega al mejor actual, ni calculamos el ratio.
        # La comparación es estricta a propósito: un techo IGUAL al mejor puede empatar.
        if sm.real_quick_ratio() < best or sm.quick_ratio() < best:
            continue
        r = sm.ratio()
        if r > best:
            best, tied = r, [oid]
        elif r == best and tied:
            tied.append(oid)
    return best, tied


def _head_path(path, head_paths, renames):
    """Dónde vive hoy ese path en upstream: el mismo, uno renombrado, o ninguno."""
    if path in head_paths:
        return {"status": "present", "path": path}
    # BFS sobre la cadena de renombres registrada por git commit a commit.
    frontier, seen = [(path, [])], {path}
    while frontier:
        cur, chain = frontier.pop(0)
        for nxt in sorted(renames.get(cur, ())):
            if nxt in seen:
                continue
            seen.add(nxt)
            step = chain + [nxt]
            if nxt in head_paths:
                return {"status": "renamed", "path": nxt, "renameChain": [path] + step}
            frontier.append((nxt, step))
    return {"status": "gone", "path": None}


# --------------------------------------------------------------------------- #
# Recuperación
# --------------------------------------------------------------------------- #

# Umbral por default de la similitud de cuerpo. Vive aca y no en el `add_argument` para
# que el self-test ejercite EL default del CLI y no un literal paralelo que puede derivar.
DEFAULT_THRESHOLD = 0.60


def recover(upstream, skills_dir, names, threshold):
    upstream = os.path.abspath(upstream)
    head = _git(upstream, "rev-parse", "HEAD").strip()

    candidates = _skill_blobs(upstream)
    oids_candidatos = [oid for oid, _ in candidates]
    contents = _read_blobs(upstream, oids_candidatos)
    # El corpus contra el que se mide TODA similitud: incompleto, el reporte sale mintiendo.
    _exigir_blobs(contents, oids_candidatos, "candidatos de base")
    bodies = {oid: body_of(blob.decode("utf-8", "replace")) for oid, blob in contents.items()}
    rev_list_path = {oid: path for oid, path in candidates}

    intro, renames = _history(upstream)
    paths_by_blob = {blob: {e["path"] for e in entries} for blob, entries in intro.items()}

    # `core.quotepath=false` por el mismo motivo que en `_history`: con el default (`true`)
    # git C-quotea todo path con un byte no ASCII, el filtro de abajo no lo reconoce como
    # `SKILL.md`, y la skill desaparece de `head_paths` — o sea sale como si upstream la
    # hubiera borrado, estando viva.
    head_paths = {p for p in _git(upstream, "-c", "core.quotepath=false",
                                  "ls-tree", "-r", "--name-only", "HEAD").splitlines()
                  if p.endswith("SKILL.md")}
    head_bodies = None                              # se calcula solo si hace falta

    if names:
        wanted = list(names)
    else:
        wanted = sorted(d for d in os.listdir(skills_dir)
                        if os.path.isfile(os.path.join(skills_dir, d, "SKILL.md")))

    results = []
    raw_similarity = {}                             # sin redondear: el resumen lo necesita
    for name in wanted:
        local = os.path.join(skills_dir, name, "SKILL.md")
        if not os.path.isfile(local):
            results.append({"name": name, "status": "missing-locally", "localPath": None})
            continue
        with open(local, "rb") as f:
            # mismo criterio que los blobs de upstream: un SKILL.md que no es utf-8
            # se degrada, no voltea la corrida entera
            mine = body_of(f.read().decode("utf-8", "replace"))

        best_ratio, tied = _best_blobs(mine, bodies)

        entry = {"name": name, "localPath": _repo_rel(local)}
        if not tied or best_ratio < threshold:
            entry["status"] = "unmatched"
            # El valor nombra lo MEDIDO y nada mas: que ningun blob supere el umbral no
            # prueba que la skill nunca haya salido de upstream. Un cuerpo reescrito lo
            # bastante cae por debajo igual: medido el 2026-08-31, con drift prependido a
            # un cuerpo real el mismo par pasa de 0.7800 a 0.0842 (el issue 19 ataca esa
            # metrica, pero su repro es otro y esta por reescribirse). Quien lo lea como
            # "fork propio" esta decidiendo, no leyendo.
            entry["upstreamRelation"] = "no-match-above-threshold"
            entry["base"] = None
            entry["bestSimilarity"] = round(best_ratio, 4)
            entry["note"] = ("ninguna version historica de upstream supera el umbral de %.2f "
                             "de similitud de cuerpo. Eso es todo lo medido: no prueba que la "
                             "skill nunca haya salido de upstream" % threshold)
            results.append(entry)
            raw_similarity[name] = best_ratio
            continue

        # De todos los blobs empatados en el mejor ratio, y de TODAS sus apariciones en
        # cualquier path, la base es la aparición más vieja del contenido. Los blobs sin
        # ninguna introducción registrada (los que solo salen de un merge) van al final.
        ranked = []
        for oid in tied:
            e = _oldest_intro(intro.get(oid))
            key = (0,) + _intro_key(e) + (oid,) if e else (1, 0, 0, "", oid)
            ranked.append((key, oid, e))
        ranked.sort(key=lambda t: t[0])
        _, best_oid, first = ranked[0]

        path = first["path"] if first else (rev_list_path.get(best_oid) or "?")
        commit = first["commit"] if first else None
        date = first["date"] if first else None
        subject = first["subject"] if first else None

        raw_similarity[name] = best_ratio
        entry["similarity"] = round(best_ratio, 4)
        entry["base"] = {
            "blob": best_oid,
            "upstreamPath": path,
            "commit": commit,
            "commitDate": date,
            "commitSubject": subject,
        }
        if commit is None:
            # el criterio de aceptación pide commit fechado: sin él no está recuperada
            entry["status"] = "unresolved-commit"
            entry["note"] = ("el blob no aparece introducido por ningun commit del log "
                             "(caso tipico: solo existe como resolucion de un merge). "
                             "Hay base candidata pero no hay commit fechado que citar.")
        else:
            entry["status"] = "recovered"

        other_paths = sorted(paths_by_blob.get(best_oid, set()) - {path})
        if other_paths:
            entry["base"]["alsoSeenAtPaths"] = other_paths

        if len(ranked) > 1:
            # el empate se expone: quien decide el lockfile tiene que verlo, no confiar
            # en que la herramienta desempato bien
            #
            # Y se dice de QUE es el empate. `_best_blobs` agrupa por ratio, no por
            # contenido: el caso frecuente es que upstream haya retocado solo el
            # frontmatter (mismo cuerpo en dos blobs), pero dos cuerpos DISTINTOS pueden
            # dar el mismo ratio contra el nuestro, y ahi elegir mal cambia el merge de
            # tres vias. Se compara antes de afirmarlo, en vez de suponerlo.
            same_body = all(bodies[oid] == bodies[best_oid] for _, oid, _ in ranked)
            entry["base"]["tieOnIdenticalBodies"] = same_body
            entry["base"]["tiedCandidates"] = [
                {"blob": oid,
                 "upstreamPath": e["path"] if e else (rev_list_path.get(oid) or "?"),
                 "commit": e["commit"] if e else None,
                 "commitDate": e["date"] if e else None,
                 "commitSubject": e["subject"] if e else None}
                for _, oid, e in ranked[1:]]
            # La nota dice lo COMPARADO y nada mas. Dos precisiones que costaron un
            # hallazgo cada una: (a) `same_body` compara el cuerpo YA normalizado por
            # `body_of` (sin frontmatter, CRLF a LF, extremos recortados), asi que "distinto
            # frontmatter" seria atribuir una causa no medida — la diferencia entre los dos
            # blobs puede estar en el BOM o en los fines de linea; (b) `same_body` es un
            # `all()`, asi que su `False` significa "no todos iguales", no "todos distintos":
            # con tres blobs empatados dos pueden compartir cuerpo.
            entry["base"]["tieNote"] = (
                "%d blobs distintos empatan en %.4f de similitud (%s). La base elegida es "
                "la aparicion mas vieja del contenido."
                % (len(ranked), best_ratio,
                   "sus cuerpos son identicos tras normalizar: lo que difiere entre los "
                   "blobs esta fuera del cuerpo normalizado — frontmatter, BOM, fines de "
                   "linea o whitespace en los extremos; cual de esos, no se midio"
                   if same_body else
                   "al menos dos de los cuerpos empatados difieren entre si: el empate es "
                   "de ratio, no de contenido. Cual es la base la decide un humano"))

        uh = _head_path(path, head_paths, renames)
        if uh["status"] == "gone":
            if head_bodies is None:
                head_oids = {}
                for p in sorted(head_paths):
                    head_oids[p] = _git(upstream, "rev-parse", "HEAD:" + p).strip()
                hb = _read_blobs(upstream, sorted(set(head_oids.values())))
                # Acá NO se exige el corpus completo, al reves que arriba: estos candidatos
                # son pistas para que un humano decida si hay sucesor, no bases. Un path que
                # no se pudo leer sale de las pistas y no aborta la recuperacion entera.
                #
                # Limitacion ACEPTADA, no olvidada: el reporte no distingue un candidato que
                # se descarto por ilegible de uno que simplemente no entro al top-3 —
                # `unconfirmedSuccessorCandidates` es una lista mas corta y nada mas. Se
                # decidio no agregarle un campo porque el esquema del reporte lo consume el
                # lockfile del issue 05b y cambiarlo es decision de ESE slice, no de este.
                # Queda declarado acá y en `docs/agents/recuperar-base-de-skills.md`.
                head_bodies = {p: body_of(hb[o].decode("utf-8", "replace"))
                               for p, o in head_oids.items() if o in hb}
            succ = sorted(((similarity(bodies[best_oid], b), p)
                           for p, b in head_bodies.items()), reverse=True)[:3]
            uh["unconfirmedSuccessorCandidates"] = [
                {"path": p, "similarity": round(r, 4)} for r, p in succ]
            uh["note"] = ("el path no existe en el HEAD de upstream y git no detecta renombre. "
                          "Los candidatos de abajo NO son bases: son pistas para que un humano "
                          "decida si hay sucesor. La de `to-issues` vive en ADR-0006.")
        entry["upstreamHead"] = uh
        # "fork propio" nombraba dos cosas distintas: la que no tiene ningun blob sobre el
        # umbral y la que si tiene base pero su path ya no esta en el HEAD. Son conjuntos
        # disjuntos, y el split es decision de esta herramienta: ADR-0006 NO lo hace — su
        # unico uso del termino es llamar "fork propio" a `zoom-out`, o sea al segundo caso
        # solo. Los dos valores nombran lo medido y no el veredicto: "fork propio" lo firma
        # un humano en el lockfile, mirando esto. `orphaned` no se usa: el glosario de
        # CONTEXT.md lo lista como termino a evitar.
        entry["upstreamRelation"] = ("gone-from-upstream-head" if uh["status"] == "gone"
                                     else "in-upstream-head")
        results.append(entry)

    return {
        "tool": "tools/recover-skill-bases.py",
        "generatedAt": datetime.datetime.now(datetime.timezone.utc)
                               .replace(microsecond=0).isoformat().replace("+00:00", "Z"),
        "doNotEditByHand": ("salida generada; es la entrada del lockfile de skills. "
                            "Para cambiarla, volve a correr la herramienta."),
        "method": {
            "similarity": ("difflib.SequenceMatcher(None, mine, other).ratio(), con "
                           "autojunk activo (default de la libreria). Se dispara con el "
                           "largo del blob de upstream (>= 200 elementos), o sea en casi "
                           "toda comparacion, y deprime el ratio; medido, mueve el numero "
                           "publicado y el blob elegido de las dos skills sin match "
                           "verdadero. Ver docs/agents/recuperar-base-de-skills.md"),
            "comparedOn": "cuerpo del SKILL.md sin frontmatter, fines de linea normalizados a LF, extremos recortados",
            "searchSpace": "todos los blobs */SKILL.md alcanzables en la historia publicada de upstream",
            "tieBreak": ("ante empate de ratio entre blobs distintos, la aparicion mas vieja "
                         "del contenido por commit time, en cualquier path; a igual segundo, "
                         "el commit mas viejo del log. `base.tieOnIdenticalBodies` dice si "
                         "TODOS los cuerpos empatados son identicos; en false, al menos dos "
                         "difieren"),
            "threshold": threshold,
            # El contrato NO es uniforme y el consumidor no tiene por que descubrirlo a los
            # golpes: una entrada `unmatched` no trae `similarity` ni `upstreamHead` —trae
            # `bestSimilarity`, que es otra cosa: la mejor similitud VISTA, por debajo del
            # umbral—, y `missing-locally` no trae ni relacion con upstream. Medido sobre la
            # salida real del 2026-08-28: 2 de las 11 skills son `unmatched`, el 18 %.
            # El self-test compara esto contra las claves que cada entrada emite de verdad,
            # asi que agregar o sacar un campo sin tocar aca sale en rojo.
            "fieldsByStatus": {
                "recovered": ["name", "localPath", "status", "upstreamRelation",
                              "similarity", "base", "upstreamHead"],
                "unresolved-commit": ["name", "localPath", "status", "upstreamRelation",
                                      "similarity", "base", "upstreamHead", "note"],
                "unmatched": ["name", "localPath", "status", "upstreamRelation",
                              "base", "bestSimilarity", "note"],
                "missing-locally": ["name", "localPath", "status"],
            },
        },
        "upstream": {
            "url": origin_url(upstream),
            "clone": upstream.replace(os.sep, "/"),
            "head": head,
            "skillBlobsScanned": len(candidates),
        },
        "localSkillsDir": _repo_rel(skills_dir),
        "skills": results,
        "summary": {
            "recovered": sum(1 for s in results if s.get("status") == "recovered"),
            "unresolvedCommit": sum(1 for s in results
                                    if s.get("status") == "unresolved-commit"),
            "unmatched": sum(1 for s in results if s.get("status") == "unmatched"),
            # solo puede salir de un `--skill` mal escrito: sin `--skill`, la lista se arma
            # filtrando los que tienen SKILL.md. Se cuenta igual: un estado que no aparece en
            # el resumen es un estado que nadie mira.
            "missingLocally": sum(1 for s in results if s.get("status") == "missing-locally"),
            # sobre el ratio crudo: round(0.99996, 4) es 1.0 y no es un cuerpo identico
            "exactBodyMatches": sum(1 for r in raw_similarity.values() if r == 1.0),
            "tiedBestSimilarity": sum(1 for s in results
                                      if (s.get("base") or {}).get("tiedCandidates")),
            # de los empates, los que NO son "upstream retoco el frontmatter": cuerpos
            # distintos con el mismo ratio. Son los unicos que piden decision humana.
            "tiedOnDifferentBodies": sum(
                1 for s in results
                if (s.get("base") or {}).get("tieOnIdenticalBodies") is False),
            "goneFromUpstreamHead": sum(1 for s in results
                                        if s.get("upstreamHead", {}).get("status") == "gone"),
        },
    }


# --------------------------------------------------------------------------- #
# Self-test offline (fixture sintético, sin red)
# --------------------------------------------------------------------------- #

FIXTURE_ORIGIN = "https://example.invalid/fixture-upstream.git"

# Fechas FIJAS del fixture. Sin esto, el guard del desempate solo se ejercita cuando
# dos commits caen por casualidad en el mismo segundo (medido: el mutante sobrevivía
# 7 de 20 corridas), y el orden por instante nunca se distingue del orden por string.
_D1 = "2026-03-01 10:00:00 +0000"          # commit 1
_D2 = "2026-03-02 10:00:00 +0000"
_D3 = _D1                                  # commit 3: MISMO segundo que el commit 1
_D4 = "2026-03-04 10:00:00 +0000"
_D5 = "2026-03-05 10:00:00 +0000"
_D6 = "2026-02-28 23:00:00 -1200"           # = 2026-03-01T11:00Z: una hora DESPUES que _D1,
                                            #   pero su ISO ordena antes como string
_D_TZ_SIDE = "2026-03-09 22:30:00 +0200"   # = 2026-03-09T20:30Z  (el MAS VIEJO en instante)
_D_TZ_MAIN = "2026-03-09 21:00:00 +0000"   # = 2026-03-09T21:00Z  (30 min mas tarde, pero
                                           #   como string "…21:00:00+00:00" ordena ANTES)
_D_REDIT = "2026-03-06 10:00:00 +0000"     # dos renombres CON edicion, en un solo commit
# Colision de ratio. La variante MAS VIEJA es `collb`, cuyo path ordena DESPUES: si el
# desempate se hiciera por path en vez de por instante, ganaria `colla` y el check lo ve.
_D_COLL_VIEJA = "2026-03-07 10:00:00 +0000"   # collb
_D_COLL_NUEVA = "2026-03-08 10:00:00 +0000"   # colla, un dia despues
_D_M1 = "2026-03-12 10:00:00 +0000"
_D_M2 = "2026-03-13 10:00:00 +0000"
_D_M3 = "2026-03-14 10:00:00 +0000"


def _fixture_texts():
    def block(prefix, n):
        return "".join("%s %d.\n" % (prefix, i) for i in range(1, n + 1))

    def fm(name, desc):
        return "---\nname: %s\ndescription: %s\n---\n\n" % (name, desc)

    t = {}
    t["ALPHA"] = block("Paso del cuerpo original de alpha, renglon", 29)
    t["ALPHA_V2"] = t["ALPHA"].replace(
        "renglon 5.", "renglon 5 REESCRITO por upstream despues de la base.")
    t["ALPHA_V3"] = t["ALPHA"].replace(
        "renglon 7.", "renglon 7 reescrito de nuevo, y van dos.")
    t["GHOST"] = block("Linea de una skill que upstream borro, numero", 29)
    t["TWIN"] = block("Renglon del cuerpo gemelo, identico en dos blobs, numero", 29)
    t["TZ"] = block("Renglon de la skill con fechas de husos distintos, numero", 29)
    t["DRIFT_UP"] = block("Punto del cuerpo de drift segun upstream, numero", 29)
    t["DRIFT_LOCAL"] = (t["DRIFT_UP"]
                        .replace("numero 3.",
                                 "numero 3, reescrito de este lado con otro largo distinto.")
                        .replace("numero 11.", "numero 11, tambien.")
                        .replace("numero 19.", "numero 19, y cierra."))
    t["MERGED_BASE"] = block("Paso del cuerpo de merged antes de las dos ramas, numero", 29)
    t["MERGED_X"] = t["MERGED_BASE"].replace("numero 4.", "numero 4 segun la rama lateral.")
    t["MERGED_Y"] = t["MERGED_BASE"].replace("numero 4.", "numero 4 segun main.")
    t["MERGED_Z"] = t["MERGED_BASE"].replace("numero 4.",
                                             "numero 4 resuelto a mano en el merge.")
    # cuerpo largo con UNA sola diferencia: la similitud real no es 1.0 pero redondeada
    # a 4 decimales da 1.0. Sirve para que exactBodyMatches no cuente redondeos.
    t["NEAR_UP"] = block("Renglon largo de la skill casi identica, numero", 800)
    t["NEAR_LOCAL"] = t["NEAR_UP"].replace("numero 400.", "numero 400!")
    # Renombre CON edicion: upstream mueve el archivo y lo retoca en el MISMO commit, asi
    # que git no lo puede casar por hash y lo registra como `R0xx` en vez de `R100`. Es la
    # unica forma de renombre que gasta presupuesto de deteccion inexacta, o sea la unica
    # que `diff.renameLimit` puede hacer desaparecer. Medido en la historia real de
    # `mattpocock/skills` (`6654f6b`): 13 lineas `R<100`, de las cuales **5** tocan la
    # ascendencia de 4 skills nuestras — `to-prd` con dos (`R065 write-a-prd -> to-prd` y
    # `R078 to-prd -> to-spec`, donde `to-spec` es el nombre de UPSTREAM, no una skill
    # nuestra), mas `R061 prd-to-issues -> to-issues`, `R099 domain-model ->
    # grill-with-docs` y `R053 github-triage -> triage`. No es un caso de borde: es el
    # patron por el que upstream renombra justamente estas skills.
    #
    # Son DOS renombres en el mismo commit, no uno, y eso no es adorno: git compara la
    # matriz de candidatos contra el limite, asi que con un solo par borrado/agregado la
    # matriz es 1x1, NO supera `renameLimit=1` y la deteccion corre igual — el check de
    # `renameLimit` queda vacuo. Lo asserta el guard
    # `_el_fixture_ejercita_el_limite`, que es reproducible hoy: sacando `rpar` de
    # `commit 5b` ese guard falla con `(['R084'], ['R084'])`, o sea el renombre se sigue
    # detectando CON el limite puesto.
    t["REDIT"] = block("Renglon de la skill que upstream renombro editando, numero", 29)
    t["REDIT_V2"] = (t["REDIT"]
                     .replace("numero 2.", "numero 2, tocado en el mismo commit del renombre.")
                     .replace("numero 9.", "numero 9, tambien tocado ahi.")
                     .replace("numero 17.", "numero 17, y este igual."))
    t["RPAR"] = block("Renglon del segundo renombre con edicion del mismo commit, numero", 29)
    t["RPAR_V2"] = (t["RPAR"]
                    .replace("numero 4.", "numero 4, retocado junto con el renombre.")
                    .replace("numero 13.", "numero 13, y este tambien."))
    # Una skill cuyo PATH en upstream lleva un acento. `core.quotePath` viene en `true` por
    # default, y con eso `ls-tree --name-only` y `log --raw` emiten el path C-quoteado
    # ("skills/caf\303\251/SKILL.md", con comillas), mientras `rev-list --objects` lo emite
    # crudo. El filtro `endswith("SKILL.md")` no matchea la forma quoteada, la skill
    # desaparece de `head_paths` y sale clasificada como si upstream la hubiera borrado: el
    # MISMO modo de falla que `diff.renames`, por otro knob heredado del entorno. En un repo
    # en castellano un path acentuado no es exotico.
    t["ACENTO"] = block("Renglon de la skill con acento en el path, numero", 29)
    # Dos cuerpos DISTINTOS que empatan en el MISMO ratio contra nuestra copia. `_best_blobs`
    # agrupa por ratio, no por contenido, asi que este empate entra por la misma rama que el
    # de `twin` —donde el cuerpo si es identico y solo cambia el frontmatter— y la nota de
    # empate no puede afirmar "mismo cuerpo" sin haberlo comparado. Medido contra el fixture
    # que quedo: los dos dan 0.9913985345651481 contra COLL_LOCAL —sobre el umbral de 0.60—
    # y A != B. El numero no vive solo en este comentario: lo fija el check
    # `los dos cuerpos de la colision empatan en el ratio crudo medido`, porque un valor con
    # etiqueta "medido" que ningun test toca es justamente lo que este slice vino a sacar.
    t["COLL_LOCAL"] = block("Renglon del cuerpo que colisiona en ratio, numero", 29)
    t["COLL_A"] = t["COLL_LOCAL"].replace("numero 3.",
                                          "numero 3, variante A de la colision.")
    t["COLL_B"] = t["COLL_LOCAL"].replace("numero 3.",
                                          "numero 3, variante B de la colision.")
    t["OURS"] = block("Nada de esto salio de upstream, linea", 29)
    t["fm"] = fm
    return t


def _build_fixture(tmp):
    """Arma el repo de upstream sintético y el árbol de skills locales."""
    import subprocess

    t = _fixture_texts()
    fm = t["fm"]
    up = os.path.join(tmp, "upstream")
    os.makedirs(up)

    def g(*a, **kw):
        date = kw.pop("date", None)
        check = kw.pop("check", True)
        env = dict(os.environ)
        if date:
            env["GIT_AUTHOR_DATE"] = date
            env["GIT_COMMITTER_DATE"] = date
        return subprocess.run(["git", "-C", up, *a], check=check, env=env,
                              stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    def write(rel, text):
        p = os.path.join(up, rel.replace("/", os.sep))
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, "w", encoding="utf-8", newline="\n") as f:
            f.write(text)

    def commit(msg, date):
        g("add", "-A")
        g("commit", "-m", msg, date=date)

    subprocess.run(["git", "-c", "init.defaultBranch=main", "init", up], check=True,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    g("config", "user.email", "selftest@example.invalid")
    g("config", "user.name", "selftest")
    g("config", "commit.gpgsign", "false")
    g("remote", "add", "origin", FIXTURE_ORIGIN)

    write("skills/a/SKILL.md", fm("a", "upstream original") + t["ALPHA"])
    write("skills/ghost/SKILL.md", fm("ghost", "la que upstream borro") + t["GHOST"])
    write("skills/twin/SKILL.md", fm("twin", "primera descripcion") + t["TWIN"])
    write("skills/drift/SKILL.md", fm("drift", "con drift propio") + t["DRIFT_UP"])
    write("skills/merged/SKILL.md", fm("merged", "antes de las ramas") + t["MERGED_BASE"])
    write("skills/near/SKILL.md", fm("near", "casi identica") + t["NEAR_UP"])
    write("skills/redit/SKILL.md", fm("redit", "antes del renombre con edicion") + t["REDIT"])
    write("skills/rpar/SKILL.md", fm("rpar", "el par del renombre con edicion") + t["RPAR"])
    write("skills/caf\xe9/SKILL.md", fm("cafe", "con acento en el path") + t["ACENTO"])
    commit("commit 1: alpha v1, ghost, twin v1, drift, merged, near, redit, rpar, cafe", _D1)

    write("skills/a/SKILL.md", fm("a", "upstream original") + t["ALPHA_V2"])
    os.remove(os.path.join(up, "skills", "ghost", "SKILL.md"))
    commit("commit 2: alpha v2, borra ghost", _D2)

    # el mismo blob v1 vuelve a aparecer: la base es la PRIMERA aparicion. El commit 3
    # cae en el MISMO segundo que el commit 1, asi que solo el desempate por commit mas
    # viejo del log evita elegir la reaparicion.
    write("skills/a/SKILL.md", fm("a", "upstream original") + t["ALPHA"])
    commit("commit 3: alpha vuelve a v1", _D3)

    write("skills/a/SKILL.md", fm("a", "upstream original") + t["ALPHA_V3"])
    commit("commit 4: alpha v3", _D4)

    os.makedirs(os.path.join(up, "skills", "a2"))
    os.replace(os.path.join(up, "skills", "a", "SKILL.md"),
               os.path.join(up, "skills", "a2", "SKILL.md"))
    commit("commit 5: renombra a -> a2", _D5)

    # Dos renombres CON edicion en un solo commit: git los registra `R0xx`, no `R100`,
    # porque el contenido cambio. `commit 5` (a -> a2) es exacto y git lo casa por hash
    # aunque la deteccion inexacta este apagada, asi que NO sirve para probar
    # `diff.renameLimit`. Van dos y no uno para que la matriz de candidatos supere el
    # limite: ver el comentario de REDIT en _fixture_texts.
    os.makedirs(os.path.join(up, "skills", "redit2"))
    os.remove(os.path.join(up, "skills", "redit", "SKILL.md"))
    write("skills/redit2/SKILL.md",
          fm("redit", "despues del renombre con edicion") + t["REDIT_V2"])
    os.makedirs(os.path.join(up, "skills", "rpar2"))
    os.remove(os.path.join(up, "skills", "rpar", "SKILL.md"))
    write("skills/rpar2/SKILL.md",
          fm("rpar", "el par, tambien renombrado y editado") + t["RPAR_V2"])
    commit("commit 5b: renombra redit -> redit2 y rpar -> rpar2, editando los cuerpos",
           _D_REDIT)

    # segundo blob con EL MISMO cuerpo: upstream solo retoco la description. Es el patron
    # de drift de ADR-0005 y es el que hace que el empate de ratio sea real. Su fecha esta
    # en -12:00 a proposito: el empate entre blobs tambien tiene que resolverse por
    # instante y no por el ISO como string.
    write("skills/twin/SKILL.md", fm("twin", "segunda descripcion, mismo cuerpo") + t["TWIN"])
    commit("commit 6: twin cambia solo la description", _D6)

    # dos blobs con cuerpos DISTINTOS que empatan en el mismo ratio contra nuestra copia.
    # La mas vieja es `collb`, y su path ordena DESPUES que el de `colla`: asi el check de la
    # base distingue el desempate por instante del desempate por path, que con las dos reglas
    # eligiendo lo mismo no probaba nada.
    write("skills/collb/SKILL.md", fm("collide", "variante B") + t["COLL_B"])
    commit("commit 7: collb, la variante MAS VIEJA en instante", _D_COLL_VIEJA)
    write("skills/colla/SKILL.md", fm("collide", "variante A") + t["COLL_A"])
    commit("commit 8: colla, la mas nueva, pero la primera por orden de path",
           _D_COLL_NUEVA)

    # mismo blob en dos ramas y dos paths, con husos distintos: el instante mas viejo es
    # el de la rama lateral, pero su %cI ordena DESPUES por ser +02:00.
    g("switch", "-c", "tzbranch")
    write("skills/tz/SKILL.md", fm("tz", "en la rama lateral") + t["TZ"])
    commit("tz side: la aparicion mas vieja en instante real", _D_TZ_SIDE)
    g("switch", "main")
    write("skills/tzmain/SKILL.md", fm("tz", "en la rama lateral") + t["TZ"])
    commit("tz main: la misma, media hora mas tarde", _D_TZ_MAIN)

    # blob que solo existe como resolucion de un merge: git log --raw no lo introduce
    # en ningun commit, asi que no hay commit fechado que reportar.
    g("switch", "-c", "mbranch")
    write("skills/merged/SKILL.md", fm("merged", "rama lateral") + t["MERGED_X"])
    commit("merge side: merged X", _D_M1)
    g("switch", "main")
    write("skills/merged/SKILL.md", fm("merged", "main") + t["MERGED_Y"])
    commit("merge main: merged Y", _D_M2)
    g("merge", "--no-commit", "mbranch", check=False)
    write("skills/merged/SKILL.md", fm("merged", "resuelto en el merge") + t["MERGED_Z"])
    g("add", "-A")
    g("commit", "-m", "merge: resolucion a mano", date=_D_M3)

    local = os.path.join(tmp, "local")
    for name, text in [
        ("alpha", fm("alpha", "drift propio en el frontmatter") + t["ALPHA"]),
        ("collide", fm("collide", "nuestra copia, sin ninguna de las dos variantes")
                    + t["COLL_LOCAL"]),
        ("drift", fm("drift", "drift propio") + t["DRIFT_LOCAL"]),
        ("ghost", fm("ghost", "la que upstream borro") + t["GHOST"]),
        ("merged", fm("merged", "nuestra copia") + t["MERGED_Z"]),
        ("near", fm("near", "nuestra copia") + t["NEAR_LOCAL"]),
        ("ours", fm("ours", "nunca salio de upstream") + t["OURS"]),
        ("redit", fm("redit", "nuestra copia, del cuerpo de antes del renombre") + t["REDIT"]),
        ("cafe", fm("cafe", "nuestra copia de la del path acentuado") + t["ACENTO"]),
        ("twin", fm("twin", "tercera description, mismo cuerpo") + t["TWIN"]),
        ("tz", fm("tz", "nuestra copia") + t["TZ"]),
    ]:
        d = os.path.join(local, name)
        os.makedirs(d)
        with open(os.path.join(d, "SKILL.md"), "w", encoding="utf-8", newline="\r\n") as f:
            f.write(text)

    # un directorio de skill SIN SKILL.md. Es la forma que distingue "existe la carpeta" de
    # "existe la skill": el guard de `--skill` tiene que rechazarlo igual que a un nombre que
    # no existe, o el reporte todo-ceros vuelve a escribirse encima del `--out` bueno.
    os.makedirs(os.path.join(local, "carpeta-sin-skill"))

    # un SKILL.md que NO es utf-8: no puede voltear la corrida entera
    d = os.path.join(local, "latin")
    os.makedirs(d)
    with open(os.path.join(d, "SKILL.md"), "wb") as f:
        f.write(("---\nname: latin\n---\n\n" +
                 "Acentos en latin-1: cami\xf3n, ma\xf1ana, r\xe9gimen.\n" * 12)
                .encode("latin-1"))

    return up, local


def self_test():
    import shutil
    import subprocess
    import tempfile

    # medido contra este fixture: el ratio crudo es 0.9785325216276834. A 3 decimales
    # daria 0.979, a 2 daria 0.98 y a 1 daria 1.0, asi que exigir los 4 decimales es lo
    # que mata a cualquier mutante que recorte la precision de la similitud.
    DRIFT_EXPECTED = 0.9785
    # el mismo ratio SIN redondear: es el unico valor con el que se puede asertar la
    # frontera del umbral (que la comparacion sea `<` y no `<=`).
    DRIFT_RAW = 0.9785325216276834

    _T = _fixture_texts()          # los mismos textos con los que se arma el fixture

    tmp = tempfile.mkdtemp(prefix="recover-skill-bases-selftest-")
    try:
        up, local = _build_fixture(tmp)
        report = recover(up, local, None, DEFAULT_THRESHOLD)
        by = {s["name"]: s for s in report["skills"]}

        checks, fails = [], []

        def check(label, fn):
            checks.append(label)
            try:
                cond, got = fn()
            except Exception as exc:            # una regresion temprana no puede esconder
                cond, got = False, "EXCEPCION %r" % (exc,)   # las aserciones que siguen
            if cond:
                print("  ok   %s" % label)
            else:
                print("  FAIL %s -> %r" % (label, got))
                fails.append(label)

        def _por_nombre(rep, nombre):
            for e in rep["skills"]:
                if e["name"] == nombre:
                    return e
            return None

        def d(obj, *keys):
            for k in keys:
                if not isinstance(obj, dict):
                    return None
                obj = obj.get(k)
            return obj

        # --- alpha: base = primera aparicion, empate de fecha al segundo -------------
        check("alpha: status recovered",
              lambda: (d(by, "alpha", "status") == "recovered", d(by, "alpha", "status")))
        check("alpha: similitud 1.0 (ni frontmatter ni CRLF cuentan)",
              lambda: (d(by, "alpha", "similarity") == 1.0, d(by, "alpha", "similarity")))
        check("alpha: path historico skills/a/SKILL.md",
              lambda: (d(by, "alpha", "base", "upstreamPath") == "skills/a/SKILL.md",
                       d(by, "alpha", "base", "upstreamPath")))
        check("alpha: commit base = el que introdujo v1 (commit 1), no la reaparicion",
              lambda: ((d(by, "alpha", "base", "commitSubject") or "").startswith("commit 1"),
                       d(by, "alpha", "base", "commitSubject")))
        check("alpha: blob de 40 hex",
              lambda: (len(d(by, "alpha", "base", "blob") or "") == 40,
                       d(by, "alpha", "base", "blob")))
        check("alpha: fecha del commit no vacia",
              lambda: (bool(d(by, "alpha", "base", "commitDate")),
                       d(by, "alpha", "base", "commitDate")))
        check("alpha: HEAD de upstream la tiene renombrada a skills/a2/SKILL.md",
              lambda: (d(by, "alpha", "upstreamHead", "status") == "renamed" and
                       d(by, "alpha", "upstreamHead", "path") == "skills/a2/SKILL.md",
                       d(by, "alpha", "upstreamHead")))
        check("alpha: relacion con upstream = vive en el HEAD",
              lambda: (d(by, "alpha", "upstreamRelation") == "in-upstream-head",
                       d(by, "alpha", "upstreamRelation")))

        # --- twin: dos blobs distintos con el mismo cuerpo ---------------------------
        check("twin: similitud 1.0",
              lambda: (d(by, "twin", "similarity") == 1.0, d(by, "twin", "similarity")))
        check("twin: base = el blob VIEJO EN INSTANTE (commit 1), no el del commit 6 en -12:00",
              lambda: ((d(by, "twin", "base", "commitSubject") or "").startswith("commit 1"),
                       d(by, "twin", "base", "commitSubject")))
        check("twin: la salida expone el empate (1 candidato empatado)",
              lambda: (len(d(by, "twin", "base", "tiedCandidates") or []) == 1,
                       d(by, "twin", "base", "tiedCandidates")))
        check("twin: el candidato empatado es el del commit 6, con su blob y su fecha",
              lambda: ((lambda c: bool(c) and
                        (c[0].get("commitSubject") or "").startswith("commit 6") and
                        len(c[0].get("blob") or "") == 40 and
                        c[0].get("blob") != d(by, "twin", "base", "blob") and
                        bool(c[0].get("commitDate")))(
                           d(by, "twin", "base", "tiedCandidates") or []),
                       d(by, "twin", "base", "tiedCandidates")))

        check("twin: el empate es de cuerpo identico, y la nota lo dice",
              lambda: (d(by, "twin", "base", "tieOnIdenticalBodies") is True and
                       "identicos tras normalizar" in (d(by, "twin", "base", "tieNote") or ""),
                       (d(by, "twin", "base", "tieOnIdenticalBodies"),
                        d(by, "twin", "base", "tieNote"))))

        # --- collide: empate de RATIO entre cuerpos DISTINTOS -------------------------
        # `_best_blobs` agrupa por ratio. Cuando el empate no es de contenido, decir "mismo
        # cuerpo, distinto frontmatter" es una afirmacion falsa en el artefacto que alimenta
        # el lockfile: son dos versiones distintas y elegir mal cambia el merge de tres vias.
        check("collide: dos blobs empatan en el mejor ratio",
              lambda: (len(d(by, "collide", "base", "tiedCandidates") or []) == 1,
                       d(by, "collide", "base", "tiedCandidates")))
        check("collide: el ratio empatado es el medido (0.9914), sobre el umbral y < 1.0",
              lambda: ((lambda r: r == 0.9914 and
                        (d(report, "method", "threshold") or 1) < r < 1.0)(
                           d(by, "collide", "similarity")),
                       (d(by, "collide", "similarity"), d(report, "method", "threshold"))))
        check("los dos cuerpos de la colision empatan en el ratio crudo medido, y difieren",
              lambda: ((lambda a, b: a == b == 0.9913985345651481 and
                        body_of(_T["COLL_A"]) != body_of(_T["COLL_B"]))(
                           similarity(body_of(_T["COLL_LOCAL"]), body_of(_T["COLL_A"])),
                           similarity(body_of(_T["COLL_LOCAL"]), body_of(_T["COLL_B"]))),
                       (similarity(body_of(_T["COLL_LOCAL"]), body_of(_T["COLL_A"])),
                        similarity(body_of(_T["COLL_LOCAL"]), body_of(_T["COLL_B"])))))
        check("collide: los dos cuerpos empatados NO son iguales, y la salida lo dice",
              lambda: (d(by, "collide", "base", "tieOnIdenticalBodies") is False,
                       d(by, "collide", "base", "tieOnIdenticalBodies")))
        # positivo y negativo: que DIGA que difieren, y que no diga lo contrario. Un
        # `not in` solo pasa con cualquier reformulacion, incluida una nota vacia.
        check("collide: la nota del empate dice que los cuerpos difieren, y no lo contrario",
              lambda: ((lambda n: "al menos dos de los cuerpos empatados difieren" in n and
                        "identicos tras normalizar" not in n)(
                           d(by, "collide", "base", "tieNote") or ""),
                       d(by, "collide", "base", "tieNote")))
        # el path de la base es lo que muerde: `skills/collb/` ordena DESPUES que
        # `skills/colla/`, asi que un desempate por path elegiria la otra.
        check("collide: la base es la mas vieja en instante, no la primera por path",
              lambda: (d(by, "collide", "base", "upstreamPath") == "skills/collb/SKILL.md" and
                       (d(by, "collide", "base", "commitSubject") or "").startswith("commit 7:"),
                       (d(by, "collide", "base", "upstreamPath"),
                        d(by, "collide", "base", "commitSubject"))))
        # los tres contadores juntos: el resumen es lo que mira un humano al sellar el
        # lockfile, y hasta aca solo uno de los tres estaba asertado.
        check("el resumen cuenta los empates, los que NO son de cuerpo identico, y los "
              "ausentes del HEAD",
              lambda: (d(report, "summary", "tiedOnDifferentBodies") == 1 and
                       d(report, "summary", "tiedBestSimilarity") == 2 and
                       d(report, "summary", "goneFromUpstreamHead") == 2,
                       d(report, "summary")))

        # --- tz: mismo blob en dos paths, husos distintos ----------------------------
        check("tz: base = la aparicion mas vieja EN INSTANTE (rama lateral, +02:00)",
              lambda: ((d(by, "tz", "base", "commitSubject") or "").startswith("tz side"),
                       d(by, "tz", "base", "commitSubject")))
        check("tz: el path reportado es el historico de esa aparicion",
              lambda: (d(by, "tz", "base", "upstreamPath") == "skills/tz/SKILL.md",
                       d(by, "tz", "base", "upstreamPath")))
        check("tz: el otro path del mismo blob queda listado",
              lambda: ("skills/tzmain/SKILL.md" in
                       (d(by, "tz", "base", "alsoSeenAtPaths") or []),
                       d(by, "tz", "base", "alsoSeenAtPaths")))

        # --- drift: similitud parcial real -------------------------------------------
        check("drift: base recuperada",
              lambda: (d(by, "drift", "status") == "recovered", d(by, "drift", "status")))
        check("drift: similitud parcial, estrictamente entre el umbral y 1.0",
              lambda: (DEFAULT_THRESHOLD < (d(by, "drift", "similarity") or 0) < 1.0,
                       d(by, "drift", "similarity")))
        check("drift: similitud con 4 decimales de precision (mata el redondeo)",
              lambda: (DRIFT_EXPECTED is not None and
                       d(by, "drift", "similarity") == DRIFT_EXPECTED,
                       d(by, "drift", "similarity")))

        # --- merged: blob introducido solo por un merge -------------------------------
        check("merged: sin commit fechado no se reporta como recuperada",
              lambda: (d(by, "merged", "status") == "unresolved-commit",
                       d(by, "merged", "status")))
        check("merged: igual deja el blob a la vista",
              lambda: (len(d(by, "merged", "base", "blob") or "") == 40,
                       d(by, "merged", "base", "blob")))
        check("merged: el resumen NO la cuenta entre las recuperadas",
              lambda: ((lambda rec: "merged" not in rec and len(rec) == 9 and
                        d(report, "summary", "recovered") == 9)(
                           sorted(e["name"] for e in report["skills"]
                                  if e.get("status") == "recovered")),
                       (d(report, "summary", "recovered"), sorted(
                           e["name"] for e in report["skills"]
                           if e.get("status") == "recovered"))))

        # --- ghost: upstream la borro --------------------------------------------------
        check("ghost: base recuperada igual (upstream la borro, pero existio)",
              lambda: (d(by, "ghost", "status") == "recovered" and
                       d(by, "ghost", "similarity") == 1.0,
                       (d(by, "ghost", "status"), d(by, "ghost", "similarity"))))
        check("ghost: sin correspondencia en el HEAD de upstream",
              lambda: (d(by, "ghost", "upstreamHead", "status") == "gone",
                       d(by, "ghost", "upstreamHead")))
        check("ghost: relacion con upstream = ausente del HEAD (vino de upstream y ya no esta)",
              lambda: (d(by, "ghost", "upstreamRelation") == "gone-from-upstream-head",
                       d(by, "ghost", "upstreamRelation")))
        check("ghost: 3 candidatos a sucesor (el HEAD tiene mas de 3 skills)",
              lambda: (len(d(by, "ghost", "upstreamHead",
                             "unconfirmedSuccessorCandidates") or []) == 3,
                       d(by, "ghost", "upstreamHead", "unconfirmedSuccessorCandidates")))
        # F18: `similarity()` es el UNICO lugar donde se usa `ratio()` fuera de
        # `_best_blobs`, y sin aserción de valor el mutante `ratio()` -> `quick_ratio()`
        # sobrevivia: las cotas baratas sobrevaluan y no son el contrato. Medido sobre este
        # fixture: con `ratio()` el mejor candidato da 0.2607; con `quick_ratio()` da 0.8304
        # y ademas cambia cual es (otro path), o sea el reporte diria otra cosa.
        check("ghost: la similitud del mejor candidato es la de ratio(), no una cota barata",
              lambda: ((lambda c: bool(c) and c[0]["similarity"] == 0.2607)(
                           d(by, "ghost", "upstreamHead",
                             "unconfirmedSuccessorCandidates") or []),
                       d(by, "ghost", "upstreamHead", "unconfirmedSuccessorCandidates")))
        check("ghost: ningun candidato a sucesor llega al umbral (no son bases)",
              lambda: ((lambda c, u: bool(c) and all(x["similarity"] < u for x in c))(
                           d(by, "ghost", "upstreamHead",
                             "unconfirmedSuccessorCandidates") or [],
                           d(report, "method", "threshold")),
                       d(by, "ghost", "upstreamHead", "unconfirmedSuccessorCandidates")))
        check("ghost: los candidatos vienen ordenados de mayor a menor similitud",
              lambda: ((lambda c: [x["similarity"] for x in c] ==
                        sorted((x["similarity"] for x in c), reverse=True) and len(c) > 1)(
                           d(by, "ghost", "upstreamHead",
                             "unconfirmedSuccessorCandidates") or []),
                       d(by, "ghost", "upstreamHead", "unconfirmedSuccessorCandidates")))

        # --- ours: nunca fue de upstream -----------------------------------------------
        check("ours: sin base (no se inventa una de similitud baja)",
              lambda: (d(by, "ours", "status") == "unmatched", d(by, "ours", "status")))
        check("ours: no emite base", lambda: (d(by, "ours", "base") is None,
                                              d(by, "ours", "base")))
        check("ours: la mejor similitud vista es > 0 y < umbral (acotada por las dos puntas)",
              lambda: (0.0 < (d(by, "ours", "bestSimilarity") or 0.0) < DEFAULT_THRESHOLD,
                       d(by, "ours", "bestSimilarity")))
        check("ours: relacion con upstream = nada supera el umbral (no 'nunca fue de upstream')",
              lambda: (d(by, "ours", "upstreamRelation") == "no-match-above-threshold",
                       d(by, "ours", "upstreamRelation")))
        check("ours: la nota no afirma que la skill nunca salio de upstream",
              lambda: ((lambda n: bool(n) and "nunca salio de upstream" not in n)(
                           d(by, "ours", "note")), d(by, "ours", "note")))

        # --- el contrato condicional de campos --------------------------------------------
        # `method.fieldsByStatus` es una afirmacion sobre la propia salida, o sea justo lo
        # que no se escribe sin verificar. Se compara por igualdad de conjuntos: agregar un
        # campo y no declararlo tambien tiene que salir en rojo, no solo sacarlo.
        def _viola_contrato(rep):
            contrato = ((rep.get("method") or {}).get("fieldsByStatus") or {})
            mal = []
            for s in rep["skills"]:
                esperado = contrato.get(s["status"])
                if esperado is None:
                    mal.append((s["name"], s["status"], "status sin contrato"))
                elif set(s) != set(esperado):
                    mal.append((s["name"], s["status"],
                                {"faltan": sorted(set(esperado) - set(s)),
                                 "sobran": sorted(set(s) - set(esperado))}))
            return mal

        # una sola corrida, y el diagnostico distingue las dos formas de fallar: si el
        # reporte dejara de emitir `missing-locally`, imprimir la lista de violaciones daria
        # `[]`, que se lee como "el contrato esta bien" — la trampa de reportar contra una
        # lista vacia, que en este repo ya mordio una vez.
        # Las corridas extra de `recover` van DENTRO de los lambdas: hoisteadas al bloque,
        # una excepcion abortaba el self-test entero —sin linea de resumen y sin ninguno de
        # los checks que siguen— en vez de contarse como un FAIL aislado.
        #
        # Lo que evita pagar la corrida dos veces —el motivo por el que se habian hoisteado—
        # es la forma `(lambda e: (cond, got))(_rep(...))`: una sola evaluacion que alimenta
        # la condicion y el diagnostico. NO hay memo: las tres claves son distintas, asi que
        # un cache daria 3 misses y 0 hits, y decir que ahorra algo seria falso.
        def _rep(nombres, thr):
            return recover(up, local, nombres, thr)
        check("cada entrada emite exactamente los campos que declara method.fieldsByStatus",
              lambda: (not _viola_contrato(report), _viola_contrato(report)))
        check("el contrato tambien vale para missing-locally, que no sale por el CLI",
              lambda: ((lambda r: (not _viola_contrato(r) and
                                   any(e["status"] == "missing-locally" for e in r["skills"]),
                                   {"violaciones": _viola_contrato(r),
                                    "status vistos": [e["status"] for e in r["skills"]]}))(
                           _rep(["alpha", "no-existe"], DEFAULT_THRESHOLD))))
        check("unmatched no promete similarity ni upstreamHead: emite bestSimilarity",
              lambda: ((lambda c: c and "similarity" not in c and "upstreamHead" not in c
                        and "bestSimilarity" in c)(
                           d(report, "method", "fieldsByStatus", "unmatched")),
                       d(report, "method", "fieldsByStatus", "unmatched")))

        # --- el umbral: su default y su frontera -----------------------------------------
        # El self-test corria con un literal `0.60` propio, asi que el default del CLI no lo
        # ejercitaba nadie: se podia cambiar y quedaba verde. Y la comparacion es `<`, o sea
        # el ratio IGUAL al umbral entra; un mutante `<=` lo saca sin que nada lo agarre.
        check("el umbral que ejercita el self-test ES el default del CLI",
              lambda: (_build_parser().parse_args([]).threshold == DEFAULT_THRESHOLD ==
                       d(report, "method", "threshold"),
                       (_build_parser().parse_args([]).threshold, DEFAULT_THRESHOLD,
                        d(report, "method", "threshold"))))
        # El VALOR del default, no solo su cableado: con la igualdad de arriba sola, la
        # constante se podia mover a cualquier lado de la banda (0, 0.97] y el self-test
        # seguia verde, porque los ratios del fixture estan agrupados lejos de ahi.
        check("el default publicado del umbral es 0.60",
              lambda: (DEFAULT_THRESHOLD == 0.60 and d(report, "method", "threshold") == 0.60,
                       (DEFAULT_THRESHOLD, d(report, "method", "threshold"))))
        # Y que DRIFT_RAW siga siendo EL ratio del fixture: si deriva —alguien lo retipea con
        # menos digitos, o un texto del fixture se mueve— los dos checks de abajo siguen
        # verdes pero dejan de ser la frontera, y el mutante `<=` revive en silencio.
        check("DRIFT_RAW es el ratio crudo que el fixture produce hoy",
              lambda: (similarity(body_of(_T["DRIFT_LOCAL"]),
                                  body_of(_T["DRIFT_UP"])) == DRIFT_RAW,
                       similarity(body_of(_T["DRIFT_LOCAL"]), body_of(_T["DRIFT_UP"]))))
        # el lookup es POR NOMBRE, no `skills[0]`: si `recover` regresionara ignorando
        # `names`, la lista arranca por `alpha` —que es `recovered`— y este check pasaria
        # espurio.
        check("frontera del umbral: el ratio IGUAL al umbral se acepta como base",
              lambda: ((lambda e: ((e or {}).get("status") == "recovered",
                                   e or "drift no esta en el reporte"))(
                           _por_nombre(_rep(["drift"], DRIFT_RAW), "drift"))))
        check("frontera del umbral: un pelo por encima ya no alcanza",
              lambda: ((lambda e: ((e or {}).get("status") == "unmatched" and
                                   (e or {}).get("upstreamRelation") ==
                                   "no-match-above-threshold",
                                   # el `got` lleva los DOS campos que mira la condicion:
                                   # con solo el status, un fallo por `upstreamRelation`
                                   # imprimia 'unmatched' y se leia como correcto
                                   {"status": (e or {}).get("status"),
                                    "upstreamRelation": (e or {}).get("upstreamRelation")}))(
                           _por_nombre(_rep(["drift"], DRIFT_RAW + 1e-9), "drift"))))

        # --- near / exactBodyMatches ----------------------------------------------------
        check("near: la similitud redondeada da 1.0 pero el cuerpo NO es identico",
              lambda: (d(by, "near", "similarity") == 1.0, d(by, "near", "similarity")))
        check("exactBodyMatches cuenta cuerpos identicos, no similitudes redondeadas",
              lambda: (d(report, "summary", "exactBodyMatches") == 7,
                       d(report, "summary", "exactBodyMatches")))

        # F14: la invariante `git rev-parse <commit>:<upstreamPath> == base.blob`. Como
        # corroboracion de que la base es la correcta es tautologica —se cumple igual con
        # una base equivocada, porque `commit` y `path` salen del MISMO registro de
        # `--raw`—, y con la deteccion de renombres apagada tampoco se cae: medido sobre
        # este fixture, con `diff.renames=false` el renombre se parte en D+A, el A queda en
        # el path nuevo del mismo commit y los 22 registros siguen round-tripeando.
        # Lo que si guarda, medido con su mutante: que el path publicado sea el de ESA
        # aparicion y no otro del mismo blob (publicar `rev_list_path` lo rompe), y que el
        # path viaje sin C-quotear. Va con un conteo porque sin el la lista vacia pasa.
        def _invariante_commit_path():
            malos, verificadas = [], 0
            for e in report["skills"]:
                base = e.get("base") or {}
                if not base.get("commit"):
                    continue
                oid = _git(up, "rev-parse",
                           "%s:%s" % (base["commit"], base["upstreamPath"])).strip()
                verificadas += 1
                if oid != base["blob"]:
                    malos.append((e["name"], base["upstreamPath"], oid, base["blob"]))
            # el contador se incrementa DENTRO del bucle, contando `rev-parse` hechos, y no
            # sobre el reporte: contando el reporte, un bucle que saltea todo deja `malos`
            # vacio y el conteo en 9 igual — el guard pasaba sin haber verificado nada
            # (mutante visto sobrevivir). Y el `got` no puede decir "9 verificadas" cuando
            # lo que falla es justamente el conteo.
            return (not malos and verificadas == 9,
                    {"mismatches": malos, "basesVerificadas": verificadas})

        check("las 9 bases con commit publicado existen en su commit y su path",
              _invariante_commit_path)

        # --- latin-1 ---------------------------------------------------------------------
        check("un SKILL.md que no es utf-8 no voltea la corrida",
              lambda: ("latin" in by, sorted(by)))

        # --- reporte ---------------------------------------------------------------------
        check("recorre las 12 skills del fixture",
              lambda: (len(report["skills"]) == 12, len(report["skills"])))
        check("registra el HEAD de upstream",
              lambda: (len(d(report, "upstream", "head") or "") == 40,
                       d(report, "upstream", "head")))
        check("la url reportada es la del clon, no una constante",
              lambda: (d(report, "upstream", "url") == FIXTURE_ORIGIN,
                       d(report, "upstream", "url")))
        check("localPath no se vuelve una ruta relativa sin sentido fuera del repo",
              lambda: ((lambda p: bool(p) and not p.startswith("../") and ".." not in p)(
                           d(by, "alpha", "localPath")), d(by, "alpha", "localPath")))

        # --- clon bare / worktree -----------------------------------------------------
        bare = os.path.join(tmp, "bare.git")
        subprocess.run(["git", "clone", "--quiet", "--bare", up, bare], check=True,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        plain = os.path.join(tmp, "no-es-repo")
        os.makedirs(plain)
        check("acepta un clon bare (no exige un .git que sea directorio)",
              lambda: (is_git_repo(bare) is True, is_git_repo(bare)))
        check("sigue rechazando un directorio que no es repo",
              lambda: (is_git_repo(plain) is False, is_git_repo(plain)))
        # `git rev-parse` sube por el arbol: sin comparar contra la raiz, CUALQUIER carpeta
        # adentro de un repo pasa por clon. Un `--upstream-clone` mal tipeado que caiga
        # adentro de ESTE repo lo analiza a el, encuentra sus propios `*/SKILL.md` (mas de cien
        # blobs, y suben con cada commit que toca uno) y emite bases con similitud 1.0 citando
        # commits nuestros.
        sub = os.path.join(up, "skills")
        check("rechaza un subdirectorio de un repo (el clon es la raiz, no algo adentro)",
              lambda: (is_git_repo(sub) is False, is_git_repo(sub)))
        bare_sub = os.path.join(bare, "refs")
        check("rechaza un subdirectorio de un clon bare",
              lambda: (is_git_repo(bare_sub) is False, is_git_repo(bare_sub)))

        # --- CLI: `--out` sin directorio ------------------------------------------------
        # `os.path.dirname("salida.json")` es "", y `os.makedirs("")` revienta. Reventaba
        # DESPUES de los ~90 s de recuperacion, con el reporte ya en memoria: se perdia todo.
        def _out_sin_directorio():
            prev = os.getcwd()
            d = os.path.join(tmp, "cwd-out")
            os.makedirs(d, exist_ok=True)
            try:
                os.chdir(d)
                rc = main(["--upstream-clone", up, "--skills-dir", local,
                           "--out", "salida.json"])
            finally:
                os.chdir(prev)
            escrito = os.path.isfile(os.path.join(d, "salida.json"))
            return (rc == 0 and escrito), (rc, escrito)

        check("--out sin directorio escribe en el cwd en vez de reventar",
              _out_sin_directorio)

        # --- CLI: un `--skill` que no existe localmente ----------------------------------
        # Era el peor de los silenciosos: un typo daba un reporte todo-ceros, lo ESCRIBIA
        # encima del bueno, imprimia "Escrito:" y salia 0. El lockfile se sella con eso.
        # DOS faltantes y UNA presente: con un solo faltante el contador es degenerado —
        # el fixture da 1 tanto contando `== "missing-locally"` como `!=`, asi que cualquier
        # predicado pasaba. Con 2 y 1 los dos lados quedan separados.
        check("missing-locally se cuenta en el resumen, y cuenta LOS QUE FALTAN",
              lambda: ((lambda r: (r["summary"].get("missingLocally") == 2,
                                   r["summary"].get("missingLocally")))(
                  recover(up, local, ["alpha", "no-existe", "tampoco-existe"],
                          DEFAULT_THRESHOLD))))

        def _pisar(nombre_skill, extra=()):
            """Corre `main` con `--out` sobre un reporte que ya existe y devuelve (rc, texto, err)."""
            import io
            import contextlib
            d = os.path.join(tmp, "no-pisar")
            os.makedirs(d, exist_ok=True)
            dest = os.path.join(d, "bueno.json")
            with open(dest, "w", encoding="utf-8") as f:
                f.write('{"reporte": "el bueno, sellado a mano"}\n')
            err = io.StringIO()
            with contextlib.redirect_stderr(err):
                rc = main(["--upstream-clone", up, "--skills-dir", local,
                           "--skill", nombre_skill, "--out", dest, *extra])
            with open(dest, encoding="utf-8") as f:
                sigue = f.read()
            return rc, sigue, err.getvalue()

        check("un --skill inexistente falla y NO pisa el reporte que ya estaba",
              lambda: ((lambda t: (t[0] == 2 and "el bueno" in t[1], (t[0], t[1][:50])))(
                  _pisar("no-existe"))))
        # el `return 2` sin el mensaje deja al usuario sin saber QUE nombre fallo ni DONDE se
        # busco: es la misma falla silenciosa, mudada del reporte a stderr.
        check("y dice por stderr que nombre falto y en que directorio busco",
              lambda: ((lambda t: ("no-existe" in t[2] and local in t[2], t[2][:120]))(
                  _pisar("no-existe"))))
        # una CARPETA sin SKILL.md no es una skill: si el guard mira el directorio en vez del
        # archivo, este caso lo atraviesa y el reporte todo-ceros pisa el `--out` bueno.
        check("una carpeta sin SKILL.md se rechaza igual que un nombre inexistente",
              lambda: ((lambda t: (t[0] == 2 and "el bueno" in t[1], (t[0], t[1][:50])))(
                  _pisar("carpeta-sin-skill"))))
        # el lado positivo: sin el, un guard que rechaza TODO (`if True`) pasa en verde y el
        # modo `--skill` queda roto para siempre sin que nada lo note.
        # se parsea el JSON en vez de buscar la subcadena `"name": "alpha"`: esa forma dependia
        # del espacio que mete indent=2, y un cambio de `separators` la volvia roja sin que
        # nada estuviera roto.
        # `.get("skills", [])` y no `["skills"]`: con la clave ausente el KeyError se comía el
        # diagnóstico justo en el caso en que el check falla, que es cuando hace falta verlo.
        check("un --skill VALIDO sigue corriendo y produce solo ese reporte",
              lambda: ((lambda t: ((lambda nombres: (t[0] == 0 and nombres == ["alpha"],
                                                     (t[0], nombres)))(
                  [s.get("name") for s in json.loads(t[1]).get("skills", [])])))(
                      _pisar("alpha"))))

        # --- CLI: las otras formas de `--out`, y `--skills-dir` --------------------------
        # Todas reventaban en el `open()` final, con el reporte ya calculado. El pre-flight las
        # ataja antes de trabajar; se asserta el MOTIVO y no solo el exit code, porque desde
        # afuera se ven igual y el usuario necesita saber cual le toco.
        #
        # El motivo se ancla en un token con guiones (`destino-ocupado:`) y NO en una palabra
        # suelta: el mensaje imprime la ruta con %r, asi que assertar "directorio" lo satisfacia
        # el NOMBRE del fixture y no el motivo — intercambiar los motivos entre si dejaba las
        # dos aserciones en verde. Los fixtures se llaman neutro por la misma razon.
        def _out_rechazado(valor):
            import io
            import contextlib
            err = io.StringIO()
            with contextlib.redirect_stderr(err):
                rc = main(["--upstream-clone", up, "--skills-dir", local, "--out", valor])
            return rc, err.getvalue()

        dir_existente = os.path.join(tmp, "destino-a")
        os.makedirs(dir_existente, exist_ok=True)
        check("--out que apunta a una carpeta existente se rechaza antes de trabajar",
              lambda: ((lambda t: (t[0] == 2 and "destino-ocupado:" in t[1], t))(
                  _out_rechazado(dir_existente))))

        archivo = os.path.join(tmp, "destino-b")
        with open(archivo, "w", encoding="utf-8") as f:
            f.write("contenido cualquiera\n")
        check("--out con un componente intermedio que es archivo se rechaza antes de trabajar",
              lambda: ((lambda t: (t[0] == 2 and "componente-archivo:" in t[1], t))(
                  _out_rechazado(os.path.join(archivo, "adentro.json")))))

        check("--out vacio se rechaza antes de trabajar",
              lambda: ((lambda t: (t[0] == 2 and "ruta-vacia:" in t[1], t))(_out_rechazado(""))))

        check("--out terminado en separador se rechaza antes de trabajar",
              lambda: ((lambda t: (t[0] == 2 and "termina-en-separador:" in t[1], t))(
                  _out_rechazado(os.path.join(tmp, "destino-c") + os.sep))))

        def _skills_dir_inexistente():
            import io
            import contextlib
            err = io.StringIO()
            with contextlib.redirect_stderr(err):
                rc = main(["--upstream-clone", up,
                           "--skills-dir", os.path.join(tmp, "no-existe-este-dir"),
                           "--stdout"])
            return (rc == 2 and "directorio de skills" in err.getvalue()), (rc, err.getvalue()[:80])

        check("un --skills-dir inexistente se rechaza antes de recuperar",
              _skills_dir_inexistente)

        # "antes de CLONAR" es una propiedad aparte, y con `--upstream-clone` es inobservable:
        # mover el guard despues del bloque de clonado dejaba el check anterior en verde. Se
        # ejercita sin clon, con una URL inalcanzable: si el guard corriera despues, la corrida
        # intentaria clonar `example.invalid` y el mensaje de clonado aparecería en stderr.
        def _no_llega_a_clonar():
            import io
            import contextlib
            err = io.StringIO()
            with contextlib.redirect_stderr(err):
                rc = main(["--upstream-url", "https://example.invalid/no-existe.git",
                           "--skills-dir", os.path.join(tmp, "no-existe-este-dir"),
                           "--stdout"])
            salida = err.getvalue()
            return (rc == 2 and "Clonando" not in salida), (rc, salida[:120])

        check("y se rechaza ANTES de clonar: no se intenta la red siquiera",
              _no_llega_a_clonar)

        # Cuando el clon SI se intenta y falla, el temporal que se creo para recibirlo no puede
        # quedar tirado: antes quedaba un mkdtemp vacio en TEMP por cada corrida sin red, y la
        # herramienta escupia el traceback crudo en vez de un mensaje.
        def _clon_fallido_no_deja_huerfano():
            import io
            import contextlib
            # Una ruta LOCAL inexistente, no una URL: `git clone` falla igual de rapido y por el
            # mismo camino, pero sin DNS, sin proxy y sin poder despertar al credential manager.
            # Con `https://example.invalid/...` el self-test dejaba de ser offline —contra lo que
            # afirman su propio doc y su runner— y en una maquina con DNS que resuelve todo, o
            # detras de un proxy que pide credenciales, podia colgarse esperando input.
            url_muerta = os.path.join(tmp, "no-existe-este-repo")
            creados = []
            real_mkdtemp = tempfile.mkdtemp

            def espia(*a, **k):
                d = real_mkdtemp(*a, **k)
                creados.append(d)
                return d

            err = io.StringIO()
            tempfile.mkdtemp = espia
            try:
                with contextlib.redirect_stderr(err):
                    rc = main(["--upstream-url", url_muerta,
                               "--skills-dir", local, "--stdout"])
            finally:
                tempfile.mkdtemp = real_mkdtemp
            salida = err.getvalue()
            # se mira EL clon de esta corrida, no un glob de todo `pocock-skills-*`: con el glob,
            # otro proceso que creara uno en la misma ventana ponia el caso en rojo culpandonos.
            quedaron = [d for d in creados if os.path.isdir(d)]
            return (rc == 4 and "No se pudo clonar" in salida and not quedaron), \
                   (rc, salida[-90:], creados, quedaron)

        check("un clon que falla sale con su propio codigo y no deja el temporal tirado",
              _clon_fallido_no_deja_huerfano)

        # Este caso se asserta contra la FUNCION y no contra `main()`: pasarle una raiz que
        # resulte existir hace que la herramienta ESCRIBA ahi (se reprodujo creando el reporte
        # adentro de la raiz, que en una maquina con `Z:` mapeada a un share de red seria
        # escribir en el share; y en POSIX, un directorio llamado `Z:` en el cwd del runner).
        # Un test no escribe fuera de su fixture ni depende de como este montada la maquina.
        def _raiz_inexistente():
            # La raiz ausente se SIMULA parcheando `os.path.exists` para ese unico path, en vez
            # de salir a buscar una letra de unidad libre. Buscarla ataba el caso a como este
            # montada la maquina: con las seis candidatas mapeadas —un escenario real, y el
            # mismo que motiva la rama— el caso se auto-excluia y el mutante que BORRA la rama
            # pasaba en verde. Ademas asi corre igual en Windows y en POSIX, donde no hay forma
            # de fabricar una raiz que no exista.
            raiz = ("Q:" + os.sep) if os.name == "nt" else os.sep
            ruta = os.path.join(raiz, "nada", "r.json")
            real_exists = os.path.exists
            objetivo = os.path.abspath(raiz)

            def exists_salvo_la_raiz(p):
                return False if os.path.abspath(p) == objetivo else real_exists(p)

            os.path.exists = exists_salvo_la_raiz
            try:
                motivo = _out_no_escribible(ruta)
            finally:
                os.path.exists = real_exists
            return (motivo or "").startswith("raiz-inexistente:"), motivo

        # Este caso simula la raiz ausente parcheando `os.path.exists`, no buscando una letra
        # de unidad libre. Por eso NO depende de como este montada la maquina ni del sistema
        # operativo: en POSIX el walk-up termina en `/`, el parche lo hace inexistente, y se
        # ejercita la misma rama positiva que en Windows. O sea que la asercion vale
        # incondicionalmente en las dos plataformas, y el mutante que borra la rama muere.
        # (El comentario anterior hablaba de "tres ramas" y de auto-exclusion: describia la
        # implementacion por letra de unidad, que `3e175b0` reemplazo.)
        check("la raiz inexistente se rechaza, en cualquier plataforma", _raiz_inexistente)

        # El exit 3 es la ultima puerta por la que se pierde trabajo: la recuperacion salio bien
        # pero la escritura fallo igual. Se fuerza haciendo fallar el `os.replace`, que es el unico
        # punto donde el temporal YA se escribio: un `--out` con un caracter invalido reventaba en
        # el `open()` del temporal, asi que ni el `.tmp` ni la limpieza ni el `replace` llegaban a
        # correr y el assert de "no quedo .tmp" pasaba por vacuidad (ademas de depender de que el
        # nombre fuera invalido en Windows, o sea rojo espurio en Linux).
        def _falla_al_reemplazar():
            import io
            import contextlib
            d = os.path.join(tmp, "destino-d")
            os.makedirs(d, exist_ok=True)
            dest = os.path.join(d, "bueno.json")
            with open(dest, "w", encoding="utf-8") as f:
                f.write('{"reporte": "el bueno, sellado a mano"}\n')

            real = os.replace
            visto = []

            def revienta(a, b):
                visto.append(a)                 # el nombre del temporal que se iba a renombrar
                raise OSError(28, "sin espacio (simulado)")

            out, err = io.StringIO(), io.StringIO()
            os.replace = revienta
            try:
                with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
                    # dos corridas: la segunda es la que permite comparar los dos nombres de
                    # temporal y exigir que sean distintos, no solo distintos de uno puntual
                    rc = main(["--upstream-clone", up, "--skills-dir", local,
                               "--skill", "alpha", "--out", dest])
                    main(["--upstream-clone", up, "--skills-dir", local,
                          "--skill", "alpha", "--out", dest])
            finally:
                os.replace = real

            texto = out.getvalue()
            with open(dest, encoding="utf-8") as f:
                quedo = f.read()
            # nada mas que el reporte bueno: ni un temporal abandonado al lado
            sobrantes = [n for n in os.listdir(d) if n != "bueno.json"]
            # el temporal tiene que tener nombre VARIABLE, no uno fijo: con un nombre fijo dos
            # corridas con el mismo --out se pisan el temporal entre si. Se asserta la forma y no
            # un nombre puntual —`!= dest + ".tmp"` lo cumplia cualquier otro fijo, como
            # `.recover.tmp`, que tiene exactamente el mismo problema—: dos corridas seguidas
            # tienen que dar nombres distintos.
            unico = (len(visto) >= 2 and visto[0] != visto[1]
                     and os.path.dirname(visto[0]) == d)
            return (rc == 3 and '"skills"' in texto and "el bueno" in quedo
                    and not sobrantes and unico), \
                   (rc, len(texto), quedo[:40], sobrantes, visto)

        check("si la escritura falla, el reporte sale por stdout con exit 3, el destino queda "
              "INTACTO y no queda temporal",
              _falla_al_reemplazar)

        # Una excepcion que NO es OSError tiene que PROPAGARSE, no volverse un exit 3. El exit 3
        # dice "la escritura fallo"; un bug de programacion o un Ctrl-C no son eso.
        #
        # Ojo con lo que este caso cubre y lo que no: inyecta en `os.replace`, que estaba
        # FUERA del `try` interno tambien en la version con el doble-close, asi que este
        # check NO muerde ese bug. Medido: restaurando el doble-close, este check y el de
        # Ctrl-C quedan en VERDE y solo cae `_motivo_real_si_falla_el_write` (un solo fail; el conteo total sube con cada check
        # nuevo, asi que no se fija aca).
        # De los tres efectos que el fix documenta —Ctrl-C vuelto OSError, un bug de
        # programacion disfrazado de "fallo el disco", y un ENOSPC reportado como EBADF—
        # el unico con test es el tercero. Cubrir los otros dos pide inyectar el
        # ValueError/KeyboardInterrupt DENTRO del `f.write`, no en `os.replace`.
        def _no_traga_lo_que_no_es_de_escritura():
            import io
            import contextlib
            d = os.path.join(tmp, "destino-e")
            os.makedirs(d, exist_ok=True)
            real = os.replace

            def revienta_raro(a, b):
                raise ValueError("bug de programacion (simulado)")

            os.replace = revienta_raro
            try:
                with contextlib.redirect_stdout(io.StringIO()), \
                     contextlib.redirect_stderr(io.StringIO()):
                    main(["--upstream-clone", up, "--skills-dir", local, "--skill", "alpha",
                          "--out", os.path.join(d, "r.json")])
                return False, "el ValueError se trago y devolvio un codigo de salida"
            except ValueError:
                return True, "propago"
            except BaseException as exc:
                return False, "lo convirtio en %r" % (exc,)
            finally:
                os.replace = real

        check("una excepcion que no es de escritura se propaga, no se disfraza de exit 3",
              _no_traga_lo_que_no_es_de_escritura)

        # Y cuando la falla ocurre DENTRO del write —el caso realista: el buffer recien se vacia
        # al cerrar, con el disco lleno o la ruta de red caida— el motivo reportado tiene que ser
        # el real. Un `os.close` de mas sobre el fd que el `with` ya cerro tiraba EBADF adentro
        # del handler y pisaba el error original con "Bad file descriptor".
        def _motivo_real_si_falla_el_write():
            import io
            import contextlib
            d = os.path.join(tmp, "destino-f")
            os.makedirs(d, exist_ok=True)
            real_fdopen = os.fdopen

            def fdopen_que_falla_al_escribir(fd, *a, **k):
                real = real_fdopen(fd, *a, **k)

                class Envuelto:
                    def __enter__(self_):
                        return self_

                    def __exit__(self_, *e):
                        real.close()          # el `with` cierra el fd, como en la vida real
                        return False

                    def write(self_, _s):
                        raise OSError(28, "sin espacio en disco (simulado)")

                return Envuelto()

            out, err = io.StringIO(), io.StringIO()
            os.fdopen = fdopen_que_falla_al_escribir
            try:
                with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
                    rc = main(["--upstream-clone", up, "--skills-dir", local, "--skill", "alpha",
                               "--out", os.path.join(d, "r.json")])
            finally:
                os.fdopen = real_fdopen
            salida = err.getvalue()
            return (rc == 3 and "sin espacio" in salida
                    and "Bad file descriptor" not in salida), (rc, salida[:110])

        check("si el write falla, el motivo reportado es el real y no un EBADF de un close de mas",
              _motivo_real_si_falla_el_write)

        # La limpieza del temporal vive en un `finally` y no en el `except OSError` porque un
        # Ctrl-C no es OSError. Eso estaba escrito como justificacion y no lo probaba nadie: con
        # la limpieza en el `except`, las dos versiones se comportan igual ante un OSError, que
        # era el unico caso ejercitado. Aca se interrumpe de verdad.
        def _ctrl_c_no_deja_temporal():
            import io
            import contextlib
            d = os.path.join(tmp, "destino-g")
            os.makedirs(d, exist_ok=True)
            real = os.replace

            def interrumpe(a, b):
                raise KeyboardInterrupt()

            os.replace = interrumpe
            try:
                with contextlib.redirect_stdout(io.StringIO()), \
                     contextlib.redirect_stderr(io.StringIO()):
                    main(["--upstream-clone", up, "--skills-dir", local, "--skill", "alpha",
                          "--out", os.path.join(d, "r.json")])
                propago = False
            except KeyboardInterrupt:
                propago = True
            finally:
                os.replace = real
            sobrantes = [n for n in os.listdir(d)]
            # el Ctrl-C tiene que PROPAGARSE (no volverse un exit code) y no dejar basura
            return (propago and not sobrantes), (propago, sobrantes)

        check("un Ctrl-C durante la escritura propaga y no deja el temporal tirado",
              _ctrl_c_no_deja_temporal)

        # --- la deteccion de renombres no puede depender de la config del entorno -------
        # `git log --raw` respeta `diff.renames` y `diff.renameLimit` del repo y del
        # usuario, asi que era la maquina la que decidia si el renombre se veia. Con
        # `diff.renames=false` el log no emite una sola `R` y una skill VIVA en el HEAD de
        # upstream sale clasificada como si upstream la hubiera borrado. Medido contra el
        # clon real de `mattpocock/skills` (`6654f6b`): con `diff.renames=false` se rompen
        # `grill-me` y `to-prd`; con `diff.renameLimit=1` se rompe solo `to-prd`, cuya
        # cadena tiene un eslabon `R078`, mientras que la de `grill-me` es de renombres
        # exactos que git casa por hash antes de mirar el limite. Las bases NO se mueven en
        # ninguno de los dos casos: lo que se rompe es la clasificacion, que es justo lo
        # que sella el lockfile.
        def _con_config(clave, valor, fn):
            leer = subprocess.run(["git", "-C", up, "config", "--get", clave],
                                  stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
            previo = leer.stdout.decode().strip() if leer.returncode == 0 else None
            subprocess.run(["git", "-C", up, "config", clave, valor], check=True,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            try:
                return fn()
            finally:
                if previo is None:
                    subprocess.run(["git", "-C", up, "config", "--unset", clave],
                                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                else:
                    subprocess.run(["git", "-C", up, "config", clave, previo], check=True,
                                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

        def _clasifica(nombre, destino, clave=None, valor=None, estado="renamed"):
            """Clasificacion de UNA skill, opcionalmente bajo una config hostil de git.

            `estado` es "renamed" para las que upstream movio y "present" para las que
            siguen en su path: es la unica diferencia entre los dos casos, asi que va de
            parametro en vez de duplicar el cuerpo entero.
            """
            def corre():
                return recover(up, local, [nombre], DEFAULT_THRESHOLD)
            r = _con_config(clave, valor, corre) if clave else corre()
            e = r["skills"][0]
            return ((d(e, "upstreamHead", "status") == estado
                     and d(e, "upstreamHead", "path") == destino
                     and e.get("upstreamRelation") == "in-upstream-head"),
                    (d(e, "upstreamHead", "status"), d(e, "upstreamHead", "path"),
                     e.get("upstreamRelation")))

        check("diff.renames=false del entorno no cambia la clasificacion de alpha",
              lambda: _clasifica("alpha", "skills/a2/SKILL.md", "diff.renames", "false"))

        # El renombre CON edicion es el unico que la deteccion inexacta puede perder, y por
        # eso el unico que `diff.renameLimit` puede romper: `alpha` no sirve, su renombre es
        # exacto y git lo casa por hash aunque la deteccion inexacta este apagada del todo.
        check("un renombre CON edicion (R<100) se sigue hasta el path de hoy",
              lambda: _clasifica("redit", "skills/redit2/SKILL.md"))
        check("diff.renameLimit=1 del entorno no pierde el renombre con edicion",
              lambda: _clasifica("redit", "skills/redit2/SKILL.md", "diff.renameLimit", "1"))

        # Guard de la PRECONDICION del check de arriba, y no es ceremonia: ese check solo
        # muerde mientras `commit 5b` tenga DOS pares de renombre, porque git compara la
        # matriz de candidatos contra el limite y con un solo par la matriz es 1x1, no
        # supera `renameLimit=1` y la deteccion corre igual. `rpar` no tiene copia local, o
        # sea que ninguna otra asercion lo toca: sacarlo de `_build_fixture` por "no se usa"
        # devolveria el check a ser vacuo EN SILENCIO. Este guard lo vuelve ruidoso — asserta
        # que con el limite en 1 la deteccion efectivamente se degrada: el renombre deja de
        # verse como `R` y el path viejo pasa a `D`. Se asserta contra el `D` y no contra
        # una lista vacia a proposito — una lista vacia tambien es lo que sale si el comando
        # falla, y el guard pasaria por el motivo equivocado.
        def _el_fixture_ejercita_el_limite():
            def raw(*cfg):
                p = subprocess.run(["git", "-C", up, *cfg, "log", "--all", "--full-history",
                                    "--raw", "--no-abbrev", "--format=", "--", "*SKILL.md"],
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                # Sin esto, un git que revienta devuelve stdout vacio -> cero renombres, que
                # es INDISTINGUIBLE de "la deteccion se degrado". El guard pasaria por el
                # motivo equivocado: exactamente el modo de falla que viene a tapar.
                if p.returncode != 0:
                    raise RuntimeError("git log del fixture fallo (%d): %s"
                                       % (p.returncode,
                                          p.stderr.decode("utf-8", "replace").strip()))
                return p.stdout.decode("utf-8", "replace")
            def estados_de_redit(texto):
                # `--raw`: ":<modo> <modo> <sha> <sha> <status>\t<path>[\t<path2>]".
                # El status va separado por ESPACIO del resto del meta y por TAB del path,
                # asi que se lo saca parseando, no buscando substrings. En una linea `R`,
                # `campos[1]` es el path VIEJO, que es el que se quiere filtrar.
                # Devuelve TODOS los estados de ese path, no solo los `R`: la forma
                # degradada es un `D`, y assertar contra ella es lo que distingue "la
                # deteccion se degrado" de "el comando no devolvio nada".
                out = []
                for l in texto.splitlines():
                    if not l.startswith(":"):
                        continue
                    campos = l.split("\t")
                    if campos[1:2] == ["skills/redit/SKILL.md"]:
                        out.append(campos[0].split()[-1])
                return out
            sin_limite = estados_de_redit(
                raw("-c", "diff.renames=true", "-c", "diff.renameLimit=0"))
            con_limite = estados_de_redit(
                raw("-c", "diff.renames=true", "-c", "diff.renameLimit=1"))
            # El path aparece DOS veces en el log: el `A` del `commit 1` que lo creo y, mas
            # nuevo, el `commit 5b` que lo mueve. `git log` emite del mas nuevo al mas
            # viejo, asi que el estado del renombre va primero y el `A` cierra la lista.
            #
            # Sin limite el renombre con edicion se ve `R0xx` (un `R100` seria exacto, lo
            # casaria el hash y no probaria nada). Con el limite en 1 git ya no lo casa y el
            # path viejo pasa a `D`. Se asserta la lista COMPLETA, y no la ausencia de `R`,
            # porque una lista vacia es tambien lo que sale si el comando no devuelve nada:
            # asi el guard no puede pasar por el motivo equivocado.
            con_edicion = [e for e in sin_limite if re.fullmatch(r"R0\d\d", e)]
            return (len(con_edicion) == 1 and sin_limite[1:] == ["A"]
                    and con_limite == ["D", "A"],
                    (sin_limite, con_limite))

        check("el fixture puede ejercitar renameLimit: R0xx sin limite, y se degrada con 1",
              _el_fixture_ejercita_el_limite)

        # `core.quotePath` es el TERCER knob heredado del entorno con el mismo efecto, y su
        # default (`true`) ya es el valor peligroso: no hace falta que nadie lo configure mal.
        # Una skill viva en el HEAD de upstream, en un path con un acento, sale clasificada
        # como borrada porque el path llega C-quoteado y el filtro `endswith("SKILL.md")` no
        # lo reconoce. Se asserta con el default puesto explicitamente, para que el caso se
        # ejercite aunque la maquina que corre tenga `false` en su config global.
        check("core.quotepath=true (el default) no rompe un path acentuado de upstream",
              lambda: _clasifica("cafe", "skills/caf\xe9/SKILL.md",
                                 "core.quotepath", "true", estado="present"))

        # --- el delimitador del frontmatter es una linea `---` sola ---------------------
        # Buscar `\n---` pelado casa tambien `\n----` y `\n--- texto`. Cuando eso pasa
        # DENTRO del frontmatter, el corte se hace en la linea equivocada y el cierre real
        # queda adentro del cuerpo: dos cuerpos que solo difieren en el frontmatter dejan de
        # dar 1.0 y la skill sale con drift que no tiene. `normalized-hash.ps1` nunca tuvo
        # este bug —nacio en `b9c8a8e` con el patron ya anclado—, asi que lo suyo es evitarlo,
        # no haberlo corregido. Y la regla no es identica: alla el whitespace tras los guiones
        # NO se tolera y el BOM no se saca (ver el comentario de `_CIERRE_FRONTMATTER`).
        check("body_of: una linea `--- texto` del frontmatter no lo cierra",
              lambda: (body_of("---\nname: x\n--- ojo\n---\nCUERPO\n") == "CUERPO",
                       body_of("---\nname: x\n--- ojo\n---\nCUERPO\n")))
        check("body_of: una linea `----` del frontmatter no lo cierra",
              lambda: (body_of("---\nname: x\n----\n---\nCUERPO\n") == "CUERPO",
                       body_of("---\nname: x\n----\n---\nCUERPO\n")))
        check("body_of: un `----` del CUERPO se conserva (el corte no se aplica dos veces)",
              lambda: (body_of("---\nname: x\n---\nCUERPO\n----\nmas\n") == "CUERPO\n----\nmas",
                       body_of("---\nname: x\n---\nCUERPO\n----\nmas\n")))
        # Las dos ramas que no son "cerro con salto de los dos lados", que un mutante que
        # borre cualquiera de las dos deja pasar si no se las asserta por separado.
        check("body_of: frontmatter cerrado en la ultima linea, sin salto final -> cuerpo vacio",
              lambda: (body_of("---\nname: x\n---") == "", body_of("---\nname: x\n---")))
        check("body_of: sin frontmatter (no arranca con `---`) el cuerpo es todo el texto",
              lambda: (body_of("hola\n---\nno soy fm\n") == "hola\n---\nno soy fm",
                       body_of("hola\n---\nno soy fm\n")))
        check("body_of: el caso sano sigue dando el cuerpo",
              lambda: (body_of("---\nname: x\n---\nCUERPO\n") == "CUERPO",
                       body_of("---\nname: x\n---\nCUERPO\n")))
        # El whitespace tras los guiones es INVISIBLE al leer, y exigir `\n---\n` exacto lo
        # convertia en "no hay cierre": el frontmatter entero se iba al cuerpo y el ratio se
        # desplomaba en silencio (0.4009 para `zoom-out`, bajo el umbral de 0.60; el numero y
        # como se midio estan en el comentario de `_CIERRE_FRONTMATTER`).
        check("body_of: un cierre `---` con espacios finales cierra igual",
              lambda: (body_of("---\nname: x\n---   \nCUERPO\n") == "CUERPO",
                       body_of("---\nname: x\n---   \nCUERPO\n")))
        check("body_of: un cierre `---` con tab final cierra igual",
              lambda: (body_of("---\nname: x\n---\t\nCUERPO\n") == "CUERPO",
                       body_of("---\nname: x\n---\t\nCUERPO\n")))
        # La APERTURA tambien tiene que ser una linea `---` sola: sin esto, `----` abre.
        check("body_of: `----` NO abre frontmatter (la apertura tambien es exacta)",
              lambda: (body_of("----\nx\n---\ny\n") == "----\nx\n---\ny",
                       body_of("----\nx\n---\ny\n")))
        # La tercera rama: abre y NO cierra nunca. El cuerpo es todo, no vacio.
        check("body_of: un frontmatter abierto y jamas cerrado no recorta nada",
              lambda: (body_of("---\nname: x\nCUERPO\n") == "---\nname: x\nCUERPO",
                       body_of("---\nname: x\nCUERPO\n")))
        check("body_of: frontmatter vacio (`---` y `---` pegados) recorta bien",
              lambda: (body_of("---\n---\nCUERPO\n") == "CUERPO",
                       body_of("---\n---\nCUERPO\n")))
        # El BOM se saca ANTES de mirar la apertura. Es justo la propiedad que el comentario de
        # `_CIERRE_FRONTMATTER` usa para distinguirse de `normalized-hash.ps1` (que no lo saca,
        # y por eso con BOM no recorta nada), y no la cubria nadie: borrar el strip del BOM
        # pasaba en verde.
        check("body_of: un BOM adelante no impide reconocer el frontmatter",
              lambda: (body_of("﻿---\nname: x\n---\nCUERPO\n") == "CUERPO",
                       body_of("﻿---\nname: x\n---\nCUERPO\n")))

        # --- un blob que upstream no entrega sale del batch como `<oid> missing` --------
        # Dos campos, sin contenido y sin el `\n` de cierre. `split()[2]` explotaba con un
        # IndexError que no nombraba ni el oid ni la causa, y se llevaba puesta la corrida
        # entera. El fixture lo ejercita con un oid fabricado, que es una de las formas
        # medidas de producir ese header; las tres estan en el docstring de `_read_blobs`.
        _oid_real = _skill_blobs(up)[0][0]
        _oid_falta = "0" * 39 + "1"

        check("_read_blobs: un oid ausente no explota y no entra al dict",
              lambda: (_oid_falta not in _read_blobs(up, [_oid_falta, _oid_real]),
                       sorted(_read_blobs(up, [_oid_falta, _oid_real]))))
        # Los bytes ESPERADOS se leen de git aparte, con `cat-file blob`, no con la funcion que
        # se esta probando. Compararla contra si misma (`_read_blobs(...) == _read_blobs(...)`)
        # dejaba pasar cualquier corrupcion uniforme: medido, truncar el blob en un byte
        # (`raw[j+1:j+size]`) sobrevivia entero a las 94 aserciones, porque el `.strip()` de
        # `body_of` se come el `\n` sobrante en las dos direcciones.
        _esperado = _git_bytes(up, "cat-file", "blob", _oid_real)

        check("_read_blobs: el contenido es byte a byte el del blob (ancla externa)",
              lambda: (_read_blobs(up, [_oid_real])[_oid_real] == _esperado,
                       (len(_read_blobs(up, [_oid_real])[_oid_real]), len(_esperado))))
        # El ausente corre el desplazamiento de todo lo que sigue. Se prueban las tres
        # posiciones, porque cada una rompe distinto: al principio, en el medio (con un blob
        # bueno de cada lado) y al final.
        check("_read_blobs: con el ausente PRIMERO, el que sigue se lee entero",
              lambda: (_read_blobs(up, [_oid_falta, _oid_real]).get(_oid_real) == _esperado,
                       len(_read_blobs(up, [_oid_falta, _oid_real]).get(_oid_real) or b"")))
        check("_read_blobs: con el ausente en el MEDIO, los dos buenos se leen enteros",
              lambda: (_read_blobs(up, [_oid_real, _oid_falta, _oid_real]).get(_oid_real)
                       == _esperado,
                       len(_read_blobs(up, [_oid_real, _oid_falta,
                                            _oid_real]).get(_oid_real) or b"")))
        check("_read_blobs: con el ausente al FINAL, el anterior se lee entero",
              lambda: (_read_blobs(up, [_oid_real, _oid_falta]).get(_oid_real) == _esperado,
                       len(_read_blobs(up, [_oid_real, _oid_falta]).get(_oid_real) or b"")))
        check("_read_blobs: todos ausentes devuelve un dict vacio, sin explotar",
              lambda: (_read_blobs(up, [_oid_falta]) == {}, _read_blobs(up, [_oid_falta])))
        # El corto de entrada. Assertar solo el `{}` NO alcanza: sin el corto, `cat-file
        # --batch` con stdin vacio devuelve `b" missing\n"` y el parseo de una lista vacia
        # tambien da `{}`, asi que el check pasaba igual. Lo que hay que observar es que git
        # no se llame, y para eso se cuenta la llamada.
        def _sin_oids_no_llama_a_git():
            real = _git_bytes
            llamadas = []

            def espia(*a, **k):
                llamadas.append(a)
                return real(*a, **k)

            globals()["_git_bytes"] = espia
            try:
                got = _read_blobs(up, [])
            finally:
                globals()["_git_bytes"] = real
            return (got == {} and not llamadas, (got, len(llamadas)))

        check("_read_blobs: sin oids devuelve vacio SIN llamar a git", _sin_oids_no_llama_a_git)

        # El ancla del recorrido: si el header no es el del oid pedido, el batch se
        # desincronizo y seguir atribuiria contenidos al oid equivocado.
        def _corta_si_se_desincroniza():
            # Bytes FABRICADOS: git nunca devuelve un header con otro oid, asi que este caso
            # solo se puede montar sobre `_parse_batch`. Es la forma que tendria la salida si
            # un header desconocido arrastrara una linea de payload y corriera el recorrido.
            raw = b"aaa blob 3\nXYZ\nOTRO blob 3\nZZZ\n"
            try:
                _parse_batch(raw, ["aaa", "bbb"])
                return False, "no levanto"
            except RuntimeError as exc:
                return "desincronizo" in str(exc), str(exc)[:120]

        check("_parse_batch: un header que no corresponde al oid pedido corta la corrida",
              _corta_si_se_desincroniza)

        def _corta_con_oid_abreviado():
            # La misma desincronizacion, pero provocada con git DE VERDAD: git eco-a el oid
            # resuelto, asi que pedir uno abreviado devuelve un header que no coincide. Es el
            # contrato de entrada de `_parse_batch` (40 hex minuscula) puesto a prueba.
            try:
                _read_blobs(up, [_oid_real[:8]])
                return False, "no levanto"
            except RuntimeError as exc:
                return "desincronizo" in str(exc), str(exc)[:120]

        check("_read_blobs: un oid abreviado no se acepta en silencio (git eco-a el resuelto)",
              _corta_con_oid_abreviado)

        def _levanta(raw, oids):
            try:
                return "OK:%r" % (_parse_batch(raw, oids),)
            except RuntimeError as exc:
                return "RuntimeError: %s" % exc
            except Exception as exc:              # un ValueError pelado se escapa del handler
                return "OTRA: %r" % (exc,)        # de `main` y vuelve a dar exit 1

        # Los dos casos van dirigidos a que SIN el guard la funcion NO levante: si se eligen
        # entradas donde igual salta el guard de desincronizacion, el check queda en verde
        # aunque se borre lo que dice cubrir (medido: pasaba).
        check("_parse_batch: un batch cortado antes de la cabecera se declara truncado",
              lambda: ("truncada" in _levanta(b"aaa blob 3", ["aaa"]),
                       _levanta(b"aaa blob 3", ["aaa"])[:110]))
        check("_parse_batch: un `size` mas grande que la salida se declara truncado",
              lambda: ("truncada" in _levanta(b"aaa blob 99\nXY\n", ["aaa"]),
                       _levanta(b"aaa blob 99\nXY\n", ["aaa"])[:110]))
        # El BORDE del guard, que es donde vive el off-by-one: `b"aaa blob 3\nXY\n"` tiene 3
        # bytes despues de la cabecera (`XY\n`), asi que size 3 es lo maximo legitimo y size 4
        # ya se pasa por uno. Sin un caso pegado al borde, correr el guard un byte pasa en
        # verde y deja entrar justo la lectura de mas que el guard existe para frenar.
        check("_parse_batch: el `size` maximo que entra en la salida se acepta",
              lambda: (_levanta(b"aaa blob 3\nXY\n", ["aaa"]) == "OK:{'aaa': b'XY\\n'}",
                       _levanta(b"aaa blob 3\nXY\n", ["aaa"])[:110]))
        check("_parse_batch: un `size` que se pasa por UN byte ya se declara truncado",
              lambda: ("truncada" in _levanta(b"aaa blob 4\nXY\n", ["aaa"]),
                       _levanta(b"aaa blob 4\nXY\n", ["aaa"])[:110]))
        # `int()` sobre un tamaño no numerico levantaba `ValueError`, que se escapa del handler
        # de `main`. El check de abajo afirma un universal ("ninguna salida rara"), asi que
        # este caso tiene que estar entre sus fixtures, no solo aca.
        check("_parse_batch: un tamaño que no es numero se declara, no explota",
              lambda: ("no es un numero" in _levanta(b"aaa blob xyz\nXYZ\n", ["aaa"]),
                       _levanta(b"aaa blob xyz\nXYZ\n", ["aaa"])[:110]))
        # Con UN solo oid, para que el guard del tamaño sea lo unico que puede frenarlo. Con dos
        # el check tambien se pone rojo, pero por otro motivo —salta antes el guard de
        # desincronizacion—, y entonces deja de DEMOSTRAR lo que dice: que sin el guard un size
        # negativo devuelve `b""` en silencio (`raw[12:11]`), la peor de las salidas.
        check("_parse_batch: un tamaño negativo se declara, no devuelve vacio en silencio",
              lambda: ("no es un numero" in _levanta(b"aaa blob -1\nXY\n", ["aaa"]),
                       _levanta(b"aaa blob -1\nXY\n", ["aaa"])[:110]))
        # El conteo del mensaje de truncado, en sus DOS formas de mentir. Con un `missing`
        # adelante, porque contar `len(contents)` los excluia. Y con un oid REPETIDO, porque
        # `oids.index(oid)` devuelve la primera aparicion y miente hacia atras: con oids todos
        # distintos ese mutante es indistinguible del codigo bueno y sobrevive.
        check("_parse_batch: el mensaje de truncado dice cuantos objetos alcanzo a procesar",
              lambda: ("Procesados 2 de 3" in _levanta(b"aaa missing\nbbb blob 1\nZ\n",
                                                       ["aaa", "bbb", "ccc"])
                       and "Procesados 1 de 2" in _levanta(b"aaa blob 1\nZ\n", ["aaa", "aaa"]),
                       (_levanta(b"aaa missing\nbbb blob 1\nZ\n", ["aaa", "bbb", "ccc"])[:120],
                        _levanta(b"aaa blob 1\nZ\n", ["aaa", "aaa"])[:120])))
        # Y ninguna de esas formas puede salir como excepcion de otra familia: `ValueError` no
        # es `RuntimeError`, no lo agarra el handler de `main`, y vuelve a dar exit 1 con
        # traceback — que es justo lo que el exit 5 vino a sacar.
        check("_parse_batch: ninguna salida rara escapa como excepcion que `main` no atrapa",
              lambda: (all(not _levanta(r, ["aaa", "bbb"]).startswith("OTRA")
                           for r in (b"", b"aaa blob 3\nXYZ\n", b"aaa missing",
                                     b"aaa blob 99\nXY\n", b"aaa", b"aaa blob xyz\nXYZ\n",
                                     b"aaa blob -1\nXYZ\n", b"aaa blob \nXYZ\n")),
                       [(r, _levanta(r, ["aaa", "bbb"])[:60])
                        for r in (b"", b"aaa blob 3\nXYZ\n", b"aaa missing",
                                  b"aaa blob 99\nXY\n", b"aaa", b"aaa blob xyz\nXYZ\n",
                                  b"aaa blob -1\nXYZ\n", b"aaa blob \nXYZ\n")]))
        # El desplazamiento del camino NORMAL, medido sin depender de `_exigir_blobs`: antes,
        # romper `i = j + 1 + size + 1` solo lo delataba el guard levantando durante el setup
        # de otro check, o sea que la red era el guard y no un test.
        check("_parse_batch: dos blobs seguidos se separan en el byte exacto",
              lambda: (_parse_batch(b"aaa blob 3\nXYZ\nbbb blob 2\nQW\n", ["aaa", "bbb"])
                       == {"aaa": b"XYZ", "bbb": b"QW"},
                       _parse_batch(b"aaa blob 3\nXYZ\nbbb blob 2\nQW\n", ["aaa", "bbb"])))
        # El contenido lleva `\n` adentro a proposito: el recorrido tiene que avanzar por el
        # `size` del header, nunca buscando el proximo salto de linea.
        check("_parse_batch: un contenido con `\\n` adentro no corta el objeto antes de tiempo",
              lambda: (_parse_batch(b"aaa blob 5\nA\nB\r\n\nbbb blob 1\nZ\n", ["aaa", "bbb"])
                       == {"aaa": b"A\nB\r\n", "bbb": b"Z"},
                       _parse_batch(b"aaa blob 5\nA\nB\r\n\nbbb blob 1\nZ\n", ["aaa", "bbb"])))
        check("_parse_batch: un contenido vacio (size 0) se lee como vacio, no se saltea",
              lambda: (_parse_batch(b"aaa blob 0\n\nbbb blob 1\nZ\n", ["aaa", "bbb"])
                       == {"aaa": b"", "bbb": b"Z"},
                       _parse_batch(b"aaa blob 0\n\nbbb blob 1\nZ\n", ["aaa", "bbb"])))

        # Que no explote NO alcanza: un candidato que se pierde en silencio cambia la base
        # elegida y publica un "fork propio" que nadie midio. El corpus exige estar completo.
        def _exige_y_nombra():
            try:
                _exigir_blobs({_oid_real: b"x"}, [_oid_real, _oid_falta], "candidatos")
                return False, "no levanto"
            except RuntimeError as exc:
                return _oid_falta in str(exc), str(exc)

        check("_exigir_blobs: aborta nombrando el oid que falta", _exige_y_nombra)
        check("_exigir_blobs: con todos presentes no levanta",
              lambda: (_exigir_blobs({_oid_real: b"x"}, [_oid_real], "candidatos") is None,
                       "no levanto"))

        def _mensaje_de_faltantes(pedidos, presentes=0, contexto="candidatos de base"):
            """Mensaje de `_exigir_blobs` con `pedidos` oids, de los cuales `presentes` estan."""
            oids = ["%040d" % n for n in range(pedidos)]
            contents = {o: b"x" for o in oids[:presentes]}
            try:
                _exigir_blobs(contents, oids, contexto)
                return "no levanto"
            except RuntimeError as exc:
                return str(exc)

        # El conteo tiene que ser FALTANTES sobre PEDIDOS, y por eso el caso de prueba tiene
        # los dos numeros DISTINTOS: con 5 de 5, un mensaje que imprima dos veces los pedidos
        # es indistinguible del correcto, y el mutante pasa en verde. Medido: pasaba.
        check("_exigir_blobs: el mensaje cuenta faltantes sobre pedidos, no dos veces lo mismo",
              lambda: ("3 de los 5 blobs" in _mensaje_de_faltantes(5, presentes=2),
                       _mensaje_de_faltantes(5, presentes=2)[:90]))
        # El detalle se trunca a 3, y decirlo es parte del contrato. No alcanza con mirar el
        # sufijo: el sufijo se calcula aparte, asi que un truncado a 1 seguia diciendo "y 2
        # mas" y el check pasaba igual. Hay que contar los oids que REALMENTE se listaron.
        def _listados(pedidos, presentes=0):
            """Cuantos de los oids faltantes aparecen ENTEROS en el mensaje."""
            msg = _mensaje_de_faltantes(pedidos, presentes)
            return sum(1 for n in range(presentes, pedidos) if ("%040d" % n) in msg)

        check("_exigir_blobs: con mas de 3 faltantes lista exactamente 3 y declara el resto",
              lambda: (_listados(5) == 3 and "y 2 mas" in _mensaje_de_faltantes(5),
                       (_listados(5), _mensaje_de_faltantes(5)[:150])))
        # El ancla es el conteo, no un `not in` sobre la prosa: buscar la palabra "mas" suelta
        # se pondria rojo el dia que el mensaje diga "demasiado" o "masivo", sin que haya
        # ninguna regresion. El sufijo se busca completo y solo por eso.
        check("_exigir_blobs: con 3 o menos los lista todos y NO inventa un `y N mas`",
              lambda: (_listados(2) == 2 and "y 0 mas" not in _mensaje_de_faltantes(2)
                       and " mas." not in _mensaje_de_faltantes(2),
                       (_listados(2), _mensaje_de_faltantes(2)[:150])))
        # `contexto` es el parametro que dice QUE corpus vino incompleto. Sin este check,
        # reemplazarlo por una constante pasaba en verde.
        check("_exigir_blobs: el mensaje nombra el contexto que le pasaron",
              lambda: ("pistas de sucesor" in _mensaje_de_faltantes(
                           1, contexto="pistas de sucesor"),
                       _mensaje_de_faltantes(1, contexto="pistas de sucesor")[:90]))

        # --- las DOS politicas, ejercitadas dentro de `recover()` -----------------------
        # Lo que el slice decide es cual caller exige y cual degrada, y eso no lo tocaba
        # ningun check: borrar la llamada a `_exigir_blobs` del corpus, o el `if o in hb` de
        # las pistas, dejaba las 94 aserciones en verde. Los dos checks de abajo mutilan la
        # lectura de blobs a proposito y miran que `recover()` reaccione distinto segun quien
        # pidio.
        def _recover_con_lectura_mutilada(omitir_en_llamada):
            """`recover()` omitiendo un blob en la llamada N a `_read_blobs`.

            Devuelve `(reporte, estado)`. `estado` importa: si la llamada N nunca ocurre, la
            mutilacion no se aplico y cualquier assert sobre el reporte pasa por el motivo
            equivocado. El caller tiene que mirarlo.
            """
            real = _read_blobs
            estado = {"n": 0, "aplicada": False, "quitados": 0}

            def falso(upstream, oids):
                estado["n"] += 1
                got = real(upstream, oids)
                if estado["n"] == omitir_en_llamada and got:
                    # Se vacia la lectura entera, no un blob suelto: las pistas se publican
                    # como un top-3, asi que sacar UNO lo tapa el cuarto candidato y el
                    # reporte queda igual — el check pasaba sin observar nada (medido: 6
                    # pistas antes y 6 despues).
                    estado["quitados"] = len(got)
                    got.clear()
                    estado["aplicada"] = True
                return got

            globals()["_read_blobs"] = falso
            try:
                return recover(up, local, None, DEFAULT_THRESHOLD), estado
            finally:
                globals()["_read_blobs"] = real

        def _corpus_incompleto_aborta():
            try:
                _recover_con_lectura_mutilada(1)
                return False, "recover() siguio con el corpus incompleto"
            except RuntimeError as exc:
                # Que aborte no alcanza: tiene que decir QUE corpus, o el mensaje no orienta.
                return "candidatos de base" in str(exc), str(exc)[:110]

        check("recover: un corpus de candidatos incompleto corta la corrida, y lo dice",
              _corpus_incompleto_aborta)

        def _candidatos_de_sucesor(rep):
            """Todos los paths de pista de sucesor que publica el reporte."""
            paths = []
            for s in rep["skills"]:
                uh = s.get("upstreamHead") or {}
                for c in uh.get("unconfirmedSuccessorCandidates") or []:
                    paths.append(c["path"])
            return paths

        def _pistas_incompletas_degradan():
            # La segunda llamada a `_read_blobs` es la de los blobs del HEAD (las pistas de
            # sucesor). Ahi la politica es la contraria: se saltea el path ilegible y la
            # recuperacion sigue.
            #
            # El ancla NO puede ser "hay skills gone": eso lo calcula `_head_path`, que ni mira
            # los blobs, asi que era verdadero tambien sin mutilar y el check pasaba aunque la
            # mutilacion no se aplicara. Lo que hay que observar es que el path ilegible
            # DESAPARECIO de las pistas publicadas — y que la mutilacion efectivamente ocurrio.
            limpio, _ = _recover_con_lectura_mutilada(0)      # 0 = ninguna llamada, control
            mutilado, estado = _recover_con_lectura_mutilada(2)
            antes, despues = _candidatos_de_sucesor(limpio), _candidatos_de_sucesor(mutilado)
            # Las tres puntas: la mutilacion ocurrio, sin ella hay pistas, y con ella el
            # reporte sale igual pero SIN las pistas que no se pudieron leer.
            return (estado["aplicada"] and antes and not despues,
                    {"aplicada": estado["aplicada"], "llamadas": estado["n"],
                     "pistas antes": len(antes), "pistas despues": len(despues)})

        check("recover: una pista ilegible sale de las pistas y NO corta la corrida",
              _pistas_incompletas_degradan)

        def _abort_de_recuperacion_sale_con_5():
            """El CLI ante una recuperacion que aborta: exit 5, mensaje por stderr, sin escribir.

            Los exits 2, 3 y 4 ya se ejercitan por `main([...])`; el 5 era lo unico que el CLI
            gano sin cobertura, y el doc le dedica una fila de la tabla de codigos. Se fuerza
            haciendo levantar a `recover`, que es la unica puerta que el handler cubre.
            """
            import io

            # El destino se pre-crea con un centinela y se verifica que SOBREVIVA. Mirar que un
            # archivo que nunca existio siga sin existir tambien caza a un `main` que escribe
            # igual (medido), pero no ve la otra mitad: pisar o truncar un reporte bueno.
            destino = os.path.join(tmp, "reporte-que-ya-estaba.json")
            with open(destino, "w", encoding="utf-8") as f:
                f.write('{"centinela": true}')
            real = recover

            def revienta(*a, **k):
                raise RuntimeError("upstream no devolvio 3 de los 9 blobs pedidos (simulado)")

            globals()["recover"] = revienta
            err = io.StringIO()
            real_stderr = sys.stderr
            sys.stderr = err
            try:
                rc = main(["--upstream-clone", up, "--skills-dir", local, "--out", destino])
            finally:
                sys.stderr = real_stderr
                globals()["recover"] = real
            quedo = open(destino, encoding="utf-8").read()
            return (rc == 5 and "simulado" in err.getvalue()
                    and quedo == '{"centinela": true}',
                    {"rc": rc, "stderr": err.getvalue()[:80], "destino": quedo[:40]})

        check("CLI: una recuperacion abortada sale con exit 5, lo dice por stderr y no escribe",
              _abort_de_recuperacion_sale_con_5)

        print("\nSELF-TEST: %d ok, %d fail (de %d)"
              % (len(checks) - len(fails), len(fails), len(checks)))
        return 1 if fails else 0
    finally:
        import stat

        def rw(func, path, _):
            os.chmod(path, stat.S_IWRITE)
            func(path)

        shutil.rmtree(tmp, onerror=rw)


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_SKILLS_DIR = os.path.join(
    REPO, "skills", "bootstrap-ai-project", "assets", "scaffold", ".agents", "skills")
DEFAULT_OUT = os.path.join(REPO, ".scratch", "bootstrap-v2", "skill-bases.json")
UPSTREAM_URL = "https://github.com/mattpocock/skills.git"


def _umask_actual():
    """El umask del proceso. Solo se puede leer poniéndolo, así que se restaura enseguida."""
    m = os.umask(0)
    os.umask(m)
    return m


def _out_no_escribible(out):
    """Por qué `--out` no se va a poder escribir, o None si se puede. Se corre ANTES de trabajar.

    Devuelve el motivo en texto en vez de un booleano: el usuario que se equivocó de ruta
    necesita saber cuál de las tres formas le tocó, y las tres se ven igual desde afuera.
    """
    if not out or not out.strip():
        return "ruta-vacia: no se paso ningun nombre de archivo"
    # `abspath` strippea el separador final, así que `C:\x\sub\` se vería como un archivo
    # llamado `sub` y pasaría el pre-flight para morir recién en el `open()`.
    if out.rstrip().endswith(("/", "\\")):
        return "termina-en-separador: es un nombre de directorio, no de archivo"
    ap_out = os.path.abspath(out)
    if os.path.isdir(ap_out):
        return "destino-ocupado: ya existe y es una carpeta"
    # un componente intermedio que es un archivo hace fallar el makedirs, no el open
    cur = os.path.dirname(ap_out)
    while cur and not os.path.exists(cur):
        padre = os.path.dirname(cur)
        if padre == cur:
            break
        cur = padre
    if cur and not os.path.exists(cur):
        # el while cortó en una raíz que no existe: una unidad no montada, un UNC inalcanzable
        return "raiz-inexistente: no existe %r" % cur
    if cur and not os.path.isdir(cur):
        return "componente-archivo: %r del camino no es una carpeta" % cur
    return None


def _build_parser():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--upstream-clone", help="clon de upstream ya existente (evita la red)")
    ap.add_argument("--upstream-url", default=UPSTREAM_URL)
    ap.add_argument("--skills-dir", default=DEFAULT_SKILLS_DIR)
    ap.add_argument("--skill", action="append", dest="skills")
    ap.add_argument("--out", default=DEFAULT_OUT)
    ap.add_argument("--threshold", type=float, default=DEFAULT_THRESHOLD)
    ap.add_argument("--stdout", action="store_true")
    ap.add_argument("--self-test", action="store_true")
    return ap


def main(argv=None):
    args = _build_parser().parse_args(argv)

    if args.self_test:
        return self_test()

    # Todo lo que se puede validar se valida ANTES de clonar y de la recuperación (medida
    # entre 81 s y 98 s con el clon ya hecho): un error de invocación tiene que costar un
    # mensaje, no una corrida entera terminada en un reporte todo-ceros escrito encima del
    # bueno. Las tres puertas por las que se perdía trabajo son las tres de acá.
    if not os.path.isdir(args.skills_dir):
        print("No existe el directorio de skills: %s" % args.skills_dir, file=sys.stderr)
        return 2

    if args.skills:
        faltan = [n for n in args.skills
                  if not os.path.isfile(os.path.join(args.skills_dir, n, "SKILL.md"))]
        if faltan:
            print("No existe(n) localmente: %s\nBuscadas en: %s"
                  % (", ".join(faltan), args.skills_dir), file=sys.stderr)
            return 2

    # `--out` tiene más formas de fallar que el dirname vacío, y todas fallaban en el `open()`
    # final, con el reporte ya calculado: una ruta vacía, una que apunta a un directorio que
    # ya existe, y una donde un componente intermedio es un archivo.
    if not args.stdout:
        problema = _out_no_escribible(args.out)
        if problema:
            print("No se puede escribir --out %r: %s" % (args.out, problema), file=sys.stderr)
            return 2

    clone = args.upstream_clone
    if clone and not is_git_repo(clone):
        print("No es un clon de git: %s" % clone, file=sys.stderr)
        return 2
    if not clone:
        clone = tempfile.mkdtemp(prefix="pocock-skills-")
        print("Clonando %s (requiere red)..." % args.upstream_url, file=sys.stderr)
        # el clon debe traer toda la historia: la base vive en blobs viejos, no en el HEAD
        try:
            subprocess.run(["git", "clone", "--quiet", args.upstream_url, clone], check=True)
        except (subprocess.CalledProcessError, OSError) as exc:
            # sin esto, una corrida sin red dejaba el temporal vacío en TEMP y escupía el
            # traceback crudo. El clon queda solo si SIRVE para reusar con --upstream-clone.
            import shutil
            shutil.rmtree(clone, ignore_errors=True)
            print("No se pudo clonar %s: %s" % (args.upstream_url, exc), file=sys.stderr)
            # código propio, no el 2 de "error de invocación": para quien llama, "lo tipeaste
            # mal" no se reintenta y "no hay red" sí.
            return 4
        print("Clon: %s (reusalo con --upstream-clone)" % clone, file=sys.stderr)

    # La recuperación aborta con `RuntimeError` cuando git falla (`_git_bytes`) o cuando el
    # corpus vino incompleto (`_exigir_blobs`). Sin este `except` salía como traceback crudo y
    # con **exit 1**, que ya está tomado: la tabla de códigos del doc declara el 1 como "solo
    # con --self-test: alguna aserción falló", así que quien llama no podía distinguir un test
    # roto de un upstream incompleto. El 5 es propio, y va aparte del 4 ("no se pudo clonar")
    # porque acá el clon existe y responde: lo que falta es contenido adentro.
    try:
        report = recover(clone, args.skills_dir, args.skills, args.threshold)
    except RuntimeError as exc:
        print("No se pudo recuperar contra %s: %s" % (clone, exc), file=sys.stderr)
        return 5
    text = json.dumps(report, indent=2, ensure_ascii=False) + "\n"
    if args.stdout:
        sys.stdout.write(text)
    else:
        # `abspath` primero: el dirname de un `--out` relativo sin directorio ("salida.json")
        # es "", y `os.makedirs("")` revienta con el reporte ya calculado.
        # Se escribe a un temporal al lado y se renombra encima. `open(dest, "w")` TRUNCA antes
        # de escribir: si la falla llega durante el write o el close —disco lleno, ruta de red
        # que se cae, que son justo los casos de la red de abajo— el reporte bueno que estaba
        # ahí queda destruido y reemplazado por JSON parcial. `os.replace` es atómico en el
        # mismo volumen, así que el destino o tiene el reporte viejo entero o el nuevo entero.
        destino = os.path.abspath(args.out)
        tmp_out = None
        try:
            os.makedirs(os.path.dirname(destino), exist_ok=True)
            # nombre único, no `destino + ".tmp"`: dos corridas con el mismo `--out` compartían
            # ese nombre fijo y una truncaba el temporal de la otra a mitad de escritura.
            fd, tmp_out = tempfile.mkstemp(dir=os.path.dirname(destino),
                                           prefix=".recover-", suffix=".tmp")
            # El try envuelve SOLO el `fdopen`, que es lo único que puede dejar el fd sin dueño.
            # Envolver también el `write` era un doble-close: si el `fdopen` salió bien, el `with`
            # ya cerró el fd, y el `os.close` de más tiraba EBADF ADENTRO del handler — así que el
            # `raise` no llegaba a correr y EBADF reemplazaba a la excepción original. Efecto
            # medido: un Ctrl-C se convertía en OSError y quedaba capturado abajo (exit 3), un
            # bug de programación se enmascaraba como "falló el disco", y un ENOSPC real
            # reportaba "Bad file descriptor" — justo el diagnóstico para el que existe el exit 3.
            try:
                f = os.fdopen(fd, "w", encoding="utf-8", newline="\n")
            except BaseException:
                os.close(fd)
                raise
            with f:
                f.write(text)
            # `mkstemp` crea en 0600. Sin esto, el reporte quedaría ilegible para otro usuario o
            # para CI. `os.replace` intercambia inodos, así que el modo del destino preexistente
            # se pisa en cualquier caso: lo que elige esta línea es con qué se pisa, y elige lo
            # mismo que habría creado un `open()` común.
            if os.name != "nt":
                os.chmod(tmp_out, 0o666 & ~_umask_actual())
            os.replace(tmp_out, destino)
        except OSError as exc:
            # Red final: el pre-flight cubre las formas conocidas, pero un permiso, un disco
            # lleno o una ruta de red caída aparecen recién acá, con la recuperación ya hecha.
            # Escupir el reporte por stdout cuesta un redirect; perderlo cuesta la corrida.
            print("No se pudo escribir %s (%s). El reporte va por stdout para no perderlo."
                  % (args.out, exc), file=sys.stderr)
            sys.stdout.write(text)
            return 3
        finally:
            # `finally` y no el `except`: un Ctrl-C entre el mkstemp y el replace no es OSError,
            # y dejaba un `.recover-*.tmp` nuevo en el directorio de salida por cada interrupción.
            # Si el replace salió bien, `tmp_out` ya no existe y esto no hace nada.
            try:
                if tmp_out and os.path.isfile(tmp_out):
                    os.remove(tmp_out)
            except OSError:
                pass
        print("Escrito: %s" % args.out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
