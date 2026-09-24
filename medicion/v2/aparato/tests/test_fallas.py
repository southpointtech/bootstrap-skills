"""El aparato contra un repo falso: cada paso después del `mkdir` puede fallar y la corrida tiene
que quedar cerrada con un evento terminal; el juguete queda registrado por su huella; `proyecto/`
es un repo de git con un commit inicial; y la `--raiz` no puede caer dentro del repo.
"""
import json
import shutil
import subprocess
from datetime import datetime, timezone
from pathlib import Path

import pytest

from aparato import materializar as mat
from aparato.brazos import Brazo
from aparato.materializar import (
    RaizDentroDelRepo, VersionIncorrecta, huella_juguete, materializar,
)

JUGUETE = Path(__file__).resolve().parents[2] / "juguete-inventario"
T0 = datetime(2026, 9, 24, 12, 0, 0, tzinfo=timezone.utc)
T1 = datetime(2026, 9, 24, 12, 0, 1, tzinfo=timezone.utc)
FALSO = Brazo("falso-olas", "HEAD", "falso+1", "olas")

SCRIPT_OK = """param([string]$SkillDir, [string]$ProjectDir)
Set-Content -LiteralPath (Join-Path $ProjectDir '.bootstrap-manifest.json') -Value '{"version":"falso+1"}' -Encoding utf8
Set-Content -LiteralPath (Join-Path $ProjectDir 'CLAUDE.md') -Value 'reglas' -Encoding utf8
'{"created":[],"overwritten":[]}'
"""
SCRIPT_FALLA = """param([string]$SkillDir, [string]$ProjectDir)
[Console]::Error.WriteLine('copy-scaffold roto a proposito')
exit 3
"""
SCRIPT_SIN_MANIFEST = """param([string]$SkillDir, [string]$ProjectDir)
'{"created":[],"overwritten":[]}'
"""
SCRIPT_MANIFEST_CORRUPTO = """param([string]$SkillDir, [string]$ProjectDir)
Set-Content -LiteralPath (Join-Path $ProjectDir '.bootstrap-manifest.json') -Value '{no es json' -Encoding utf8
'{"created":[],"overwritten":[]}'
"""


def _git(repo, *args):
    return subprocess.run(
        ["git", "-C", str(repo), "-c", "user.name=t", "-c", "user.email=t@invalid",
         "-c", "commit.gpgsign=false", *args],
        capture_output=True, check=True,
    ).stdout.decode("utf-8").strip()


def _commitear_script(repo, script):
    scripts = repo / "skills" / "bootstrap-personal-project" / "scripts"
    scripts.mkdir(parents=True, exist_ok=True)
    (scripts / "copy-scaffold.ps1").write_text(script, encoding="utf-8")
    _git(repo, "add", "-A")
    _git(repo, "commit", "-q", "--no-verify", "-m", "script")


def _repo_falso(tmp_path, script):
    repo = tmp_path / "repo"
    repo.mkdir()
    _git(repo, "init", "-q")
    _commitear_script(repo, script)
    return repo


def _eventos(corrida):
    lineas = (corrida / "bitacora.jsonl").read_text(encoding="utf-8").splitlines()
    return [json.loads(l) for l in lineas]


def _corridas(raiz):
    return sorted(p for p in raiz.iterdir() if p.is_dir())


# --- 3. append-only: la secuencia completa de eventos ------------------------------------------

def test_la_bitacora_guarda_la_secuencia_completa(tmp_path):
    repo = _repo_falso(tmp_path, SCRIPT_OK)
    corrida = materializar(FALSO, tmp_path / "corridas", repo=repo, ahora=lambda: T0)

    assert [e["evento"] for e in _eventos(corrida)] == ["corrida_abierta", "materializado"]


# --- 4. corrida_abierta y su modo ----------------------------------------------------------------

def test_corrida_abierta_registra_brazo_ref_sha_y_modo(tmp_path):
    repo = _repo_falso(tmp_path, SCRIPT_OK)
    corrida = materializar(FALSO, tmp_path / "corridas", repo=repo, ahora=lambda: T0)

    abierta = _eventos(corrida)[0]
    assert abierta["evento"] == "corrida_abierta"
    assert (abierta["brazo"], abierta["ref"], abierta["modo"]) == ("falso-olas", "HEAD", "olas")
    assert abierta["sha"] == _git(repo, "rev-parse", "HEAD")
    assert abierta["ts"] == T0.isoformat()


# --- 1. falla después del mkdir: evento terminal, y se relanza sin pisar -----------------------

@pytest.mark.parametrize("script, paso, excepcion", [
    (SCRIPT_FALLA, "copy_scaffold", RuntimeError),
    (SCRIPT_SIN_MANIFEST, "leer_manifest", FileNotFoundError),
    (SCRIPT_MANIFEST_CORRUPTO, "leer_manifest", json.JSONDecodeError),
], ids=["copy-scaffold-falla", "sin-manifest", "manifest-corrupto"])
def test_una_falla_despues_del_mkdir_cierra_la_corrida(tmp_path, script, paso, excepcion):
    repo = _repo_falso(tmp_path, script)
    raiz = tmp_path / "corridas"

    with pytest.raises(excepcion):
        materializar(FALSO, raiz, repo=repo, ahora=lambda: T0)

    (corrida,) = _corridas(raiz)
    eventos = _eventos(corrida)
    assert [e["evento"] for e in eventos] == ["corrida_abierta", "materializacion_fallida"]
    fallida = eventos[-1]
    assert (fallida["brazo"], fallida["paso"]) == ("falso-olas", paso)
    assert fallida["error"].startswith(excepcion.__name__ + ":")


def test_git_archive_que_falla_cierra_la_corrida(tmp_path, monkeypatch):
    repo = _repo_falso(tmp_path, SCRIPT_OK)
    monkeypatch.setattr(mat, "SKILL", "skills/no-existe")

    with pytest.raises(RuntimeError):
        materializar(FALSO, tmp_path / "corridas", repo=repo, ahora=lambda: T0)

    (corrida,) = _corridas(tmp_path / "corridas")
    assert _eventos(corrida)[-1]["paso"] == "git_archive"


def test_pwsh_ausente_cierra_la_corrida(tmp_path, monkeypatch):
    repo = _repo_falso(tmp_path, SCRIPT_OK)
    monkeypatch.setattr(mat, "PWSH", "pwsh-que-no-existe")

    with pytest.raises(FileNotFoundError):
        materializar(FALSO, tmp_path / "corridas", repo=repo, ahora=lambda: T0)

    (corrida,) = _corridas(tmp_path / "corridas")
    fallida = _eventos(corrida)[-1]
    assert (fallida["evento"], fallida["paso"]) == ("materializacion_fallida", "copy_scaffold")


def test_se_relanza_sin_pisar_la_corrida_fallida(tmp_path):
    repo = _repo_falso(tmp_path, SCRIPT_FALLA)
    raiz = tmp_path / "corridas"
    with pytest.raises(RuntimeError):
        materializar(FALSO, raiz, repo=repo, ahora=lambda: T0)
    (fallida,) = _corridas(raiz)
    antes = (fallida / "bitacora.jsonl").read_bytes()

    _commitear_script(repo, SCRIPT_OK)
    buena = materializar(FALSO, raiz, repo=repo, ahora=lambda: T1)

    assert _corridas(raiz) == sorted([fallida, buena])
    assert (fallida / "bitacora.jsonl").read_bytes() == antes
    assert _eventos(buena)[-1]["evento"] == "materializado"


def test_version_incorrecta_nombra_el_brazo_y_no_agrega_fallida(tmp_path):
    repo = _repo_falso(tmp_path, SCRIPT_OK)
    trucho = Brazo("falso-olas", "HEAD", "otra+2", "olas")

    with pytest.raises(VersionIncorrecta):
        materializar(trucho, tmp_path / "corridas", repo=repo, ahora=lambda: T0)

    (corrida,) = _corridas(tmp_path / "corridas")
    eventos = _eventos(corrida)
    assert [e["evento"] for e in eventos] == ["corrida_abierta", "version_incorrecta"]
    assert eventos[-1]["brazo"] == "falso-olas"


# --- 5. ref inexistente: falla antes de crear nada ---------------------------------------------

def test_ref_inexistente_falla_sin_crear_la_corrida(tmp_path):
    repo = _repo_falso(tmp_path, SCRIPT_OK)
    raiz = tmp_path / "corridas"

    with pytest.raises(RuntimeError, match="no-existe-este-ref"):
        materializar(Brazo("x", "no-existe-este-ref", "v", "serie"), raiz, repo=repo)

    assert not raiz.exists() or _corridas(raiz) == []


# --- 2. la huella del juguete ------------------------------------------------------------------

def test_materializado_registra_la_huella_del_juguete_copiado(tmp_path):
    repo = _repo_falso(tmp_path, SCRIPT_OK)
    corrida = materializar(FALSO, tmp_path / "corridas", repo=repo, ahora=lambda: T0)

    huella = _eventos(corrida)[-1]["juguete_sha256"]
    assert len(huella) == 64 and int(huella, 16) >= 0
    assert huella == huella_juguete(corrida / "proyecto")
    assert huella == huella_juguete(JUGUETE)


def test_la_huella_cambia_si_cambia_un_byte_del_juguete(tmp_path):
    repo = _repo_falso(tmp_path, SCRIPT_OK)
    copia = tmp_path / "juguete"
    shutil.copytree(JUGUETE, copia)
    base = materializar(FALSO, tmp_path / "a", repo=repo, juguete=copia, ahora=lambda: T0)

    with open(copia / "datos" / "productos.csv", "ab") as f:
        f.write(b"\n")
    otra = materializar(FALSO, tmp_path / "b", repo=repo, juguete=copia, ahora=lambda: T0)

    assert _eventos(base)[-1]["juguete_sha256"] != _eventos(otra)[-1]["juguete_sha256"]


def test_la_huella_cambia_si_se_renombra_un_archivo(tmp_path):
    copia = tmp_path / "juguete"
    shutil.copytree(JUGUETE, copia)
    antes = huella_juguete(copia)
    (copia / "datos" / "productos.csv").rename(copia / "datos" / "productos2.csv")

    assert huella_juguete(copia) != antes


def test_la_huella_solo_mira_lo_que_ve_el_agente(tmp_path):
    copia = tmp_path / "juguete"
    shutil.copytree(JUGUETE, copia)
    antes = huella_juguete(copia)
    (copia / "README.md").write_text("otra cosa", encoding="utf-8")

    assert huella_juguete(copia) == antes


# --- 6. proyecto/ es un repo con un commit inicial ---------------------------------------------

def test_proyecto_es_un_repo_con_todo_en_el_commit_inicial(tmp_path):
    repo = _repo_falso(tmp_path, SCRIPT_OK)
    corrida = materializar(FALSO, tmp_path / "corridas", repo=repo, ahora=lambda: T0)
    proyecto = corrida / "proyecto"

    assert Path(_git(proyecto, "rev-parse", "--show-toplevel")) == proyecto.resolve()
    assert _git(proyecto, "rev-list", "--count", "HEAD") == "1"
    assert _git(proyecto, "status", "--porcelain") == ""
    rastreados = set(_git(proyecto, "ls-files").splitlines())
    assert {"CLAUDE.md", ".bootstrap-manifest.json", "enunciado.md",
            "datos/productos.csv", "datos/movimientos.csv"} <= rastreados
    assert _eventos(corrida)[-1]["commit_inicial"] == _git(proyecto, "rev-parse", "HEAD")
    # La identidad del commit inicial no queda en la config del repo: el agente commitea con la suya.
    assert subprocess.run(
        ["git", "-C", str(proyecto), "config", "--local", "--get", "user.name"],
        capture_output=True,
    ).returncode == 1


# --- 7. la raíz no puede caer dentro del repo --------------------------------------------------

@pytest.mark.parametrize("sub", ["", "corridas", "a/b"])
def test_raiz_dentro_del_repo_se_rechaza_sin_crear_nada(tmp_path, sub):
    repo = _repo_falso(tmp_path, SCRIPT_OK)
    raiz = repo / sub if sub else repo
    antes = sorted(p.name for p in repo.iterdir())

    with pytest.raises(RaizDentroDelRepo):
        materializar(FALSO, raiz, repo=repo, ahora=lambda: T0)

    assert sorted(p.name for p in repo.iterdir()) == antes


def test_raiz_dentro_del_repo_se_rechaza_aunque_cambien_las_mayusculas(tmp_path):
    repo = _repo_falso(tmp_path, SCRIPT_OK)
    otra_caja = Path(str(repo).upper()) / "corridas"
    if not otra_caja.parent.exists():
        pytest.skip("el sistema de archivos distingue mayúsculas")

    with pytest.raises(RaizDentroDelRepo):
        materializar(FALSO, otra_caja, repo=repo, ahora=lambda: T0)


def test_raiz_hermana_con_el_mismo_prefijo_no_se_rechaza(tmp_path):
    repo = _repo_falso(tmp_path, SCRIPT_OK)
    corrida = materializar(FALSO, tmp_path / "repo-corridas", repo=repo, ahora=lambda: T0)
    assert corrida.parent == tmp_path / "repo-corridas"


# --- slice 3: los pasos copiar_juguete y git_init, y los Lows del slice 2 -----------------------

def test_juguete_incompleto_cierra_la_corrida_en_copiar_juguete(tmp_path):
    repo = _repo_falso(tmp_path, SCRIPT_OK)
    incompleto = tmp_path / "juguete"
    incompleto.mkdir()
    shutil.copy2(JUGUETE / "enunciado.md", incompleto / "enunciado.md")  # sin datos/

    with pytest.raises(FileNotFoundError):
        materializar(FALSO, tmp_path / "corridas", repo=repo, juguete=incompleto, ahora=lambda: T0)

    (corrida,) = _corridas(tmp_path / "corridas")
    fallida = _eventos(corrida)[-1]
    assert (fallida["evento"], fallida["paso"]) == ("materializacion_fallida", "copiar_juguete")
    assert (fallida["ref"], fallida["sha"]) == ("HEAD", _git(repo, "rev-parse", "HEAD"))


def test_git_init_que_falla_cierra_la_corrida_en_git_init(tmp_path, monkeypatch):
    repo = _repo_falso(tmp_path, SCRIPT_OK)
    original = mat._correr

    def _correr(args, cwd=None):
        if "init" in args:
            raise RuntimeError("git init roto a proposito")
        return original(args, cwd=cwd)

    monkeypatch.setattr(mat, "_correr", _correr)
    with pytest.raises(RuntimeError, match="init roto"):
        materializar(FALSO, tmp_path / "corridas", repo=repo, ahora=lambda: T0)

    (corrida,) = _corridas(tmp_path / "corridas")
    fallida = _eventos(corrida)[-1]
    assert (fallida["evento"], fallida["paso"]) == ("materializacion_fallida", "git_init")


SCRIPT_MANIFEST_LISTA = """param([string]$SkillDir, [string]$ProjectDir)
Set-Content -LiteralPath (Join-Path $ProjectDir '.bootstrap-manifest.json') -Value '[]' -Encoding utf8
'{"created":[],"overwritten":[]}'
"""
SCRIPT_MANIFEST_NULL = SCRIPT_MANIFEST_LISTA.replace("'[]'", "'null'")


@pytest.mark.parametrize("script", [SCRIPT_MANIFEST_LISTA, SCRIPT_MANIFEST_NULL],
                         ids=["lista", "null"])
def test_manifest_que_no_es_objeto_es_value_error(tmp_path, script):
    repo = _repo_falso(tmp_path, script)

    with pytest.raises(ValueError, match="no es un objeto"):
        materializar(FALSO, tmp_path / "corridas", repo=repo, ahora=lambda: T0)

    (corrida,) = _corridas(tmp_path / "corridas")
    assert _eventos(corrida)[-1]["paso"] == "leer_manifest"


def test_git_dir_heredado_no_desvia_los_commits(tmp_path, monkeypatch):
    repo = _repo_falso(tmp_path, SCRIPT_OK)
    (tmp_path / "ajeno").mkdir()
    ajeno = _repo_falso(tmp_path / "ajeno", SCRIPT_OK)
    antes = _git(ajeno, "rev-list", "--count", "HEAD")
    monkeypatch.setenv("GIT_DIR", str(ajeno / ".git"))
    monkeypatch.setenv("GIT_WORK_TREE", str(ajeno))
    monkeypatch.setenv("GIT_INDEX_FILE", str(ajeno / ".git" / "index"))

    corrida = materializar(FALSO, tmp_path / "corridas", repo=repo, ahora=lambda: T0)

    for v in ("GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE"):
        monkeypatch.delenv(v)
    assert _git(ajeno, "rev-list", "--count", "HEAD") == antes
    assert _eventos(corrida)[0]["sha"] == _git(repo, "rev-parse", "HEAD")
    assert _git(corrida / "proyecto", "rev-list", "--count", "HEAD") == "1"


def test_si_falla_registrar_la_falla_no_se_pierde_la_excepcion_original(tmp_path, monkeypatch):
    repo = _repo_falso(tmp_path, SCRIPT_FALLA)
    original = mat.Bitacora.registrar

    def registrar(self, evento, **campos):
        if evento == "materializacion_fallida":
            raise OSError("disco lleno a proposito")
        return original(self, evento, **campos)

    monkeypatch.setattr(mat.Bitacora, "registrar", registrar)
    with pytest.raises(RuntimeError, match="copy-scaffold roto") as exc:
        materializar(FALSO, tmp_path / "corridas", repo=repo, ahora=lambda: T0)
    assert any("disco lleno" in n for n in getattr(exc.value, "__notes__", []))
