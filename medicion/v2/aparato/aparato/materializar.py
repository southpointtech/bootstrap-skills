"""Materializar un brazo: el scaffold personal tal como estaba en su ref, más lo que ve el agente.

Una corrida es `<raiz>/<brazo>-<AAAAMMDDTHHMMSSZ>/` con:
- `proyecto/`        el directorio donde trabaja el agente (scaffold + `enunciado.md` + `datos/`)
- `skill-en-ref/`    la skill extraída del ref con `git archive` (para auditar qué se copió)
- `copy-scaffold.json` lo que reportó el `copy-scaffold.ps1` de ese ref
- `bitacora.jsonl`   append-only, un evento por línea, cada uno con `ts` UTC ISO

Nunca borra nada: si la carpeta de la corrida ya existe, falla.
"""
import io
import json
import shutil
import subprocess
import tarfile
from datetime import datetime, timezone
from pathlib import Path

SKILL = "skills/bootstrap-personal-project"
JUGUETE = Path(__file__).resolve().parents[2] / "juguete-inventario"
# Lo único del juguete que ve el agente; `cliente/`, `evals/`, `oraculo.py` y `README.md` no.
PARA_EL_AGENTE = ("enunciado.md", "datos")


class VersionIncorrecta(Exception):
    def __init__(self, brazo, esperada, obtenida):
        super().__init__(
            f"{brazo}: el .bootstrap-manifest.json materializado dice version "
            f"{obtenida!r}, se esperaba {esperada!r}"
        )
        self.esperada, self.obtenida = esperada, obtenida


def _ahora_utc():
    return datetime.now(timezone.utc)


def _correr(args, cwd=None):
    """Corre un proceso y devuelve stdout como UTF-8; si falla, tira con su stderr."""
    r = subprocess.run(args, cwd=cwd, capture_output=True)
    if r.returncode != 0:
        err = r.stderr.decode("utf-8", errors="replace")
        raise RuntimeError(f"{args[0]} salió con {r.returncode}: {err}")
    return r.stdout


def _repo():
    raiz = _correr(["git", "-C", str(Path(__file__).parent), "rev-parse", "--show-toplevel"])
    return Path(raiz.decode("utf-8").strip())


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
    sha = _correr(
        ["git", "-C", str(repo), "rev-parse", "--verify", f"{brazo.ref}^{{commit}}"]
    ).decode("utf-8").strip()

    inicio = ahora().astimezone(timezone.utc)
    raiz.mkdir(parents=True, exist_ok=True)
    corrida = raiz / f"{brazo.nombre}-{inicio:%Y%m%dT%H%M%SZ}"
    corrida.mkdir()  # FileExistsError si ya estaba: nunca se pisa una corrida
    bitacora = Bitacora(corrida / "bitacora.jsonl", ahora)
    bitacora.registrar(
        "corrida_abierta", brazo=brazo.nombre, ref=brazo.ref, sha=sha, modo=brazo.modo
    )

    # La skill tal como estaba en el ref, sin checkout: git archive del sha ya resuelto.
    extraida = corrida / "skill-en-ref"
    tar = _correr(["git", "-C", str(repo), "archive", "--format=tar", sha, SKILL])
    with tarfile.open(fileobj=io.BytesIO(tar)) as t:
        t.extractall(extraida, filter="data")
    skill = extraida / SKILL

    proyecto = corrida / "proyecto"
    proyecto.mkdir()
    reporte = _correr([
        "pwsh", "-NoProfile", "-File", str(skill / "scripts" / "copy-scaffold.ps1"),
        "-SkillDir", str(skill), "-ProjectDir", str(proyecto),
    ])
    (corrida / "copy-scaffold.json").write_bytes(reporte)

    for nombre in PARA_EL_AGENTE:
        origen = Path(juguete) / nombre
        if origen.is_dir():
            shutil.copytree(origen, proyecto / nombre)
        else:
            shutil.copy2(origen, proyecto / nombre)

    manifest = json.loads((proyecto / ".bootstrap-manifest.json").read_text(encoding="utf-8-sig"))
    version = manifest.get("version")
    if version != brazo.version:
        bitacora.registrar(
            "version_incorrecta", ref=brazo.ref, sha=sha, esperada=brazo.version, obtenida=version
        )
        raise VersionIncorrecta(brazo.nombre, brazo.version, version)

    bitacora.registrar(
        "materializado", brazo=brazo.nombre, ref=brazo.ref, sha=sha, version=version
    )
    return corrida
