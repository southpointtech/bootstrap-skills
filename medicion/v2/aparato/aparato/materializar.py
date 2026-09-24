"""Materializar un brazo: el scaffold personal tal como estaba en su ref, más lo que ve el agente.

Una corrida es `<raiz>/<brazo>-<AAAAMMDDTHHMMSSZ>/` con:
- `proyecto/`        el directorio donde trabaja el agente (scaffold + `enunciado.md` + `datos/`),
                     un repo de git con un solo commit inicial que lo contiene todo
- `skill-en-ref/`    la skill extraída del ref con `git archive` (para auditar qué se copió)
- `copy-scaffold.json` lo que reportó el `copy-scaffold.ps1` de ese ref
- `bitacora.jsonl`   append-only, un evento por línea, cada uno con `ts` UTC ISO

Nunca borra nada: si la carpeta de la corrida ya existe, falla. Una corrida abierta se cierra con
un evento terminal (`materializado`, `version_incorrecta` o `materializacion_fallida`), salvo que
el proceso muera sin llegar a escribirlo.
"""
import hashlib
import io
import json
import os
import shutil
import subprocess
import tarfile
from datetime import datetime, timezone
from pathlib import Path

SKILL = "skills/bootstrap-personal-project"
JUGUETE = Path(__file__).resolve().parents[2] / "juguete-inventario"
# Lo único del juguete que ve el agente; `cliente/`, `evals/`, `oraculo.py` y `README.md` no.
PARA_EL_AGENTE = ("enunciado.md", "datos")
GIT, PWSH = "git", "pwsh"
# El commit inicial de `proyecto/` se firma con esta identidad pasada por `-c`: no queda en la
# config del repo, así que los commits del agente salen con la identidad de la máquina.
IDENTIDAD_INICIAL = ("-c", "user.name=aparato", "-c", "user.email=aparato@invalid",
                     "-c", "commit.gpgsign=false")


class VersionIncorrecta(Exception):
    def __init__(self, brazo, esperada, obtenida):
        super().__init__(
            f"{brazo}: el .bootstrap-manifest.json materializado dice version "
            f"{obtenida!r}, se esperaba {esperada!r}"
        )
        self.esperada, self.obtenida = esperada, obtenida


class RaizDentroDelRepo(ValueError):
    def __init__(self, raiz, repo):
        super().__init__(
            f"--raiz {raiz} está dentro del repo {repo}: la corrida tiene que vivir fuera de él"
        )


def _ahora_utc():
    return datetime.now(timezone.utc)


def _correr(args, cwd=None):
    """Corre un proceso y devuelve stdout; si sale distinto de 0, tira con el comando y su stderr."""
    try:
        r = subprocess.run(args, cwd=cwd, capture_output=True)
    except FileNotFoundError as e:
        raise FileNotFoundError(f"no se encontró el ejecutable {args[0]!r} en el PATH") from e
    if r.returncode != 0:
        err = r.stderr.decode("utf-8", errors="replace")
        raise RuntimeError(f"{' '.join(map(str, args))} salió con {r.returncode}: {err}")
    return r.stdout


def _repo():
    raiz = _correr([GIT, "-C", str(Path(__file__).parent), "rev-parse", "--show-toplevel"])
    return Path(raiz.decode("utf-8").strip())


def _dentro_de(ruta, repo):
    r = os.path.normcase(os.path.realpath(ruta))
    p = os.path.normcase(os.path.realpath(repo))
    try:
        return os.path.commonpath([r, p]) == p
    except ValueError:  # distinta unidad en Windows
        return False


def huella_juguete(carpeta):
    """sha256 de lo que ve el agente (`PARA_EL_AGENTE`) bajo `carpeta`.

    Por cada archivo, en orden de ruta relativa POSIX: `ruta\\0sha256-hex-del-contenido\\n`; la
    huella es el sha256 de esa lista. Da lo mismo sobre el juguete que sobre `proyecto/` recién
    copiado, y cambia si cambia un byte o un nombre.
    """
    carpeta = Path(carpeta)
    archivos = []
    for nombre in PARA_EL_AGENTE:
        origen = carpeta / nombre
        if not origen.exists():
            raise FileNotFoundError(origen)
        archivos += [origen] if origen.is_file() else [p for p in origen.rglob("*") if p.is_file()]
    h = hashlib.sha256()
    for rel, p in sorted((p.relative_to(carpeta).as_posix(), p) for p in archivos):
        h.update(f"{rel}\0{hashlib.sha256(p.read_bytes()).hexdigest()}\n".encode("utf-8"))
    return h.hexdigest()


class Bitacora:
    def __init__(self, ruta, ahora):
        self.ruta, self.ahora = ruta, ahora

    def registrar(self, evento, **campos):
        ts = self.ahora().astimezone(timezone.utc).isoformat()
        linea = json.dumps({"ts": ts, "evento": evento, **campos}, ensure_ascii=False)
        with open(self.ruta, "a", encoding="utf-8", newline="\n") as f:
            f.write(linea + "\n")


def materializar(brazo, raiz, *, repo=None, juguete=JUGUETE, ahora=_ahora_utc):
    """Abre una corrida de `brazo` bajo `raiz` y devuelve su carpeta."""
    repo = Path(repo) if repo else _repo()
    raiz = Path(raiz)
    if _dentro_de(raiz, repo):
        raise RaizDentroDelRepo(raiz, repo)
    sha = _correr(
        [GIT, "-C", str(repo), "rev-parse", "--verify", f"{brazo.ref}^{{commit}}"]
    ).decode("utf-8").strip()

    inicio = ahora().astimezone(timezone.utc)
    raiz.mkdir(parents=True, exist_ok=True)
    corrida = raiz / f"{brazo.nombre}-{inicio:%Y%m%dT%H%M%SZ}"
    corrida.mkdir()  # FileExistsError si ya estaba: nunca se pisa una corrida
    bitacora = Bitacora(corrida / "bitacora.jsonl", ahora)
    bitacora.registrar(
        "corrida_abierta", brazo=brazo.nombre, ref=brazo.ref, sha=sha, modo=brazo.modo
    )

    paso = "git_archive"
    try:
        # La skill tal como estaba en el ref, sin checkout: git archive del sha ya resuelto.
        extraida = corrida / "skill-en-ref"
        tar = _correr([GIT, "-C", str(repo), "archive", "--format=tar", sha, SKILL])
        with tarfile.open(fileobj=io.BytesIO(tar)) as t:
            t.extractall(extraida, filter="data")
        skill = extraida / SKILL

        paso = "copy_scaffold"
        proyecto = corrida / "proyecto"
        proyecto.mkdir()
        reporte = _correr([
            PWSH, "-NoProfile", "-File", str(skill / "scripts" / "copy-scaffold.ps1"),
            "-SkillDir", str(skill), "-ProjectDir", str(proyecto),
        ])
        (corrida / "copy-scaffold.json").write_bytes(reporte)

        paso = "copiar_juguete"
        for nombre in PARA_EL_AGENTE:
            origen = Path(juguete) / nombre
            if origen.is_dir():
                shutil.copytree(origen, proyecto / nombre)
            else:
                shutil.copy2(origen, proyecto / nombre)
        huella = huella_juguete(proyecto)

        paso = "leer_manifest"
        manifest = json.loads(
            (proyecto / ".bootstrap-manifest.json").read_text(encoding="utf-8-sig")
        )
        version = manifest.get("version")
        if version != brazo.version:
            bitacora.registrar(
                "version_incorrecta", brazo=brazo.nombre, ref=brazo.ref, sha=sha,
                esperada=brazo.version, obtenida=version,
            )
            raise VersionIncorrecta(brazo.nombre, brazo.version, version)

        paso = "git_init"
        g = [GIT, "-C", str(proyecto)]
        _correr([*g, "init", "-q", "-b", "main"])
        _correr([*g, "add", "-A"])
        _correr([*g, *IDENTIDAD_INICIAL, "commit", "-q", "--no-verify", "-m",
                 f"estado inicial: scaffold de {brazo.nombre} ({brazo.ref} = {sha}) + juguete"])
        commit_inicial = _correr([*g, "rev-parse", "HEAD"]).decode("utf-8").strip()
    except VersionIncorrecta:
        raise
    except BaseException as e:
        bitacora.registrar(
            "materializacion_fallida", brazo=brazo.nombre, ref=brazo.ref, sha=sha,
            paso=paso, error=f"{type(e).__name__}: {e}",
        )
        raise

    bitacora.registrar(
        "materializado", brazo=brazo.nombre, ref=brazo.ref, sha=sha, version=version,
        juguete_sha256=huella, commit_inicial=commit_inicial,
    )
    return corrida
