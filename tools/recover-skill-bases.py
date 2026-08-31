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
        end = t.find("\n---", 3)
        if end != -1:
            nl = t.find("\n", end + 1)
            t = t[nl + 1:] if nl != -1 else ""
    return t.strip()


def similarity(a, b):
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
    """Lee muchos blobs de una sola pasada con `cat-file --batch`."""
    if not oids:
        return {}
    raw = _git_bytes(upstream, "cat-file", "--batch",
                     stdin=("\n".join(oids) + "\n").encode("ascii"))
    contents = {}
    i = 0
    for oid in oids:
        j = raw.index(b"\n", i)
        size = int(raw[i:j].split()[2])
        contents[oid] = raw[j + 1:j + 1 + size]
        i = j + 1 + size + 1          # +1 por el \n que cierra cada objeto
    return contents


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
    """
    sep = "\x01"
    raw = _git(upstream, "log", "--all", "--full-history",
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

def recover(upstream, skills_dir, names, threshold):
    upstream = os.path.abspath(upstream)
    head = _git(upstream, "rev-parse", "HEAD").strip()

    candidates = _skill_blobs(upstream)
    contents = _read_blobs(upstream, [oid for oid, _ in candidates])
    bodies = {oid: body_of(blob.decode("utf-8", "replace")) for oid, blob in contents.items()}
    rev_list_path = {oid: path for oid, path in candidates}

    intro, renames = _history(upstream)
    paths_by_blob = {blob: {e["path"] for e in entries} for blob, entries in intro.items()}

    head_paths = {p for p in _git(upstream, "ls-tree", "-r", "--name-only", "HEAD").splitlines()
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
            entry["upstreamRelation"] = "never-upstream"
            entry["base"] = None
            entry["bestSimilarity"] = round(best_ratio, 4)
            entry["note"] = ("ninguna version historica de upstream supera el umbral de %.2f: "
                             "esta skill nunca salio de upstream" % threshold)
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
            entry["base"]["tiedCandidates"] = [
                {"blob": oid,
                 "upstreamPath": e["path"] if e else (rev_list_path.get(oid) or "?"),
                 "commit": e["commit"] if e else None,
                 "commitDate": e["date"] if e else None,
                 "commitSubject": e["subject"] if e else None}
                for _, oid, e in ranked[1:]]
            entry["base"]["tieNote"] = (
                "%d blobs distintos empatan en %.4f de similitud (mismo cuerpo, distinto "
                "frontmatter). La base elegida es la aparicion mas vieja del contenido."
                % (len(ranked), best_ratio))

        uh = _head_path(path, head_paths, renames)
        if uh["status"] == "gone":
            if head_bodies is None:
                head_oids = {}
                for p in sorted(head_paths):
                    head_oids[p] = _git(upstream, "rev-parse", "HEAD:" + p).strip()
                hb = _read_blobs(upstream, sorted(set(head_oids.values())))
                head_bodies = {p: body_of(hb[o].decode("utf-8", "replace"))
                               for p, o in head_oids.items()}
            succ = sorted(((similarity(bodies[best_oid], b), p)
                           for p, b in head_bodies.items()), reverse=True)[:3]
            uh["unconfirmedSuccessorCandidates"] = [
                {"path": p, "similarity": round(r, 4)} for r, p in succ]
            uh["note"] = ("el path no existe en el HEAD de upstream y git no detecta renombre. "
                          "Los candidatos de abajo NO son bases: son pistas para que un humano "
                          "decida si hay sucesor (ver ADR-0006).")
        entry["upstreamHead"] = uh
        # "fork propio" nombraba dos cosas distintas: la skill que nunca fue de upstream y
        # la que vino de upstream y upstream borro (ADR-0006). Son conjuntos disjuntos.
        entry["upstreamRelation"] = "orphaned" if uh["status"] == "gone" else "in-upstream-head"
        results.append(entry)

    return {
        "tool": "tools/recover-skill-bases.py",
        "generatedAt": datetime.datetime.now(datetime.timezone.utc)
                               .replace(microsecond=0).isoformat().replace("+00:00", "Z"),
        "doNotEditByHand": ("salida generada; es la entrada del lockfile de skills. "
                            "Para cambiarla, volve a correr la herramienta."),
        "method": {
            "similarity": "difflib.SequenceMatcher(None, a, b).ratio()",
            "comparedOn": "cuerpo del SKILL.md sin frontmatter, fines de linea normalizados a LF, extremos recortados",
            "searchSpace": "todos los blobs */SKILL.md alcanzables en la historia publicada de upstream",
            "tieBreak": ("ante empate de ratio entre blobs distintos, la aparicion mas vieja "
                         "del contenido por commit time, en cualquier path; a igual segundo, "
                         "el commit mas viejo del log"),
            "threshold": threshold,
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
    commit("commit 1: alpha v1, ghost, twin v1, drift, merged, near", _D1)

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

    # segundo blob con EL MISMO cuerpo: upstream solo retoco la description. Es el patron
    # de drift de ADR-0005 y es el que hace que el empate de ratio sea real. Su fecha esta
    # en -12:00 a proposito: el empate entre blobs tambien tiene que resolverse por
    # instante y no por el ISO como string.
    write("skills/twin/SKILL.md", fm("twin", "segunda descripcion, mismo cuerpo") + t["TWIN"])
    commit("commit 6: twin cambia solo la description", _D6)

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
        ("drift", fm("drift", "drift propio") + t["DRIFT_LOCAL"]),
        ("ghost", fm("ghost", "la que upstream borro") + t["GHOST"]),
        ("merged", fm("merged", "nuestra copia") + t["MERGED_Z"]),
        ("near", fm("near", "nuestra copia") + t["NEAR_LOCAL"]),
        ("ours", fm("ours", "nunca salio de upstream") + t["OURS"]),
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

    tmp = tempfile.mkdtemp(prefix="recover-skill-bases-selftest-")
    try:
        up, local = _build_fixture(tmp)
        report = recover(up, local, None, 0.60)
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
              lambda: (0.60 < (d(by, "drift", "similarity") or 0) < 1.0,
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
              lambda: (d(report, "summary", "recovered") == 6,
                       (d(report, "summary", "recovered"), sorted(
                           s["name"] for s in report["skills"]
                           if s.get("status") == "recovered"))))

        # --- ghost: upstream la borro --------------------------------------------------
        check("ghost: base recuperada igual (upstream la borro, pero existio)",
              lambda: (d(by, "ghost", "status") == "recovered" and
                       d(by, "ghost", "similarity") == 1.0,
                       (d(by, "ghost", "status"), d(by, "ghost", "similarity"))))
        check("ghost: sin correspondencia en el HEAD de upstream",
              lambda: (d(by, "ghost", "upstreamHead", "status") == "gone",
                       d(by, "ghost", "upstreamHead")))
        check("ghost: relacion con upstream = huerfana (vino de upstream y ya no esta)",
              lambda: (d(by, "ghost", "upstreamRelation") == "orphaned",
                       d(by, "ghost", "upstreamRelation")))
        check("ghost: 3 candidatos a sucesor (el HEAD tiene mas de 3 skills)",
              lambda: (len(d(by, "ghost", "upstreamHead",
                             "unconfirmedSuccessorCandidates") or []) == 3,
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
              lambda: (0.0 < (d(by, "ours", "bestSimilarity") or 0.0) < 0.60,
                       d(by, "ours", "bestSimilarity")))
        check("ours: relacion con upstream = nunca fue de upstream",
              lambda: (d(by, "ours", "upstreamRelation") == "never-upstream",
                       d(by, "ours", "upstreamRelation")))

        # --- near / exactBodyMatches ----------------------------------------------------
        check("near: la similitud redondeada da 1.0 pero el cuerpo NO es identico",
              lambda: (d(by, "near", "similarity") == 1.0, d(by, "near", "similarity")))
        check("exactBodyMatches cuenta cuerpos identicos, no similitudes redondeadas",
              lambda: (d(report, "summary", "exactBodyMatches") == 5,
                       d(report, "summary", "exactBodyMatches")))

        # --- latin-1 ---------------------------------------------------------------------
        check("un SKILL.md que no es utf-8 no voltea la corrida",
              lambda: ("latin" in by, sorted(by)))

        # --- reporte ---------------------------------------------------------------------
        check("recorre las 9 skills del fixture",
              lambda: (len(report["skills"]) == 9, len(report["skills"])))
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
                  recover(up, local, ["alpha", "no-existe", "tampoco-existe"], 0.60))))

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
            if os.name == "nt":
                # la primera letra de unidad libre: fabricada en runtime, no hardcodeada
                libre = next((c for c in "ZYXWVU"
                              if not os.path.exists(c + ":" + os.sep)), None)
                if libre is None:
                    # `check` no imprime el detalle cuando pasa, asi que sin este aviso el caso
                    # se auto-excluiria en silencio y el conteo seguiria diciendo que corrio.
                    print("  aviso: ZYXWVU estan todas montadas, el caso de la raiz no se "
                          "ejercito en esta maquina")
                    return True, "caso no ejercitable"
                motivo = _out_no_escribible(os.path.join(libre + ":" + os.sep, "nada", "r.json"))
                return (motivo or "").startswith("raiz-inexistente:"), (libre, motivo)
            # en POSIX no hay forma de fabricar una raiz ausente —el walk-up siempre termina
            # en `/`, que existe—, asi que lo verificable es que la rama NO se dispare.
            motivo = _out_no_escribible("/nada/de/esto/existe/r.json")
            return not (motivo or "").startswith("raiz-inexistente:"), motivo

        check("una raiz que no existe se rechaza por su propio motivo", _raiz_inexistente)

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
        # dice "la escritura fallo"; un bug de programacion o un Ctrl-C no son eso. Un `os.close`
        # de mas sobre un fd ya cerrado convertia cualquiera de los dos en EBADF —que si es
        # OSError— y los tragaba, ademas de pisar el mensaje de un ENOSPC real.
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


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--upstream-clone", help="clon de upstream ya existente (evita la red)")
    ap.add_argument("--upstream-url", default=UPSTREAM_URL)
    ap.add_argument("--skills-dir", default=DEFAULT_SKILLS_DIR)
    ap.add_argument("--skill", action="append", dest="skills")
    ap.add_argument("--out", default=DEFAULT_OUT)
    ap.add_argument("--threshold", type=float, default=0.60)
    ap.add_argument("--stdout", action="store_true")
    ap.add_argument("--self-test", action="store_true")
    args = ap.parse_args(argv)

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

    report = recover(clone, args.skills_dir, args.skills, args.threshold)
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
