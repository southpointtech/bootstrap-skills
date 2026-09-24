import json
import subprocess
from datetime import datetime, timezone
from pathlib import Path

import pytest

from aparato.brazos import BRAZOS, Brazo
from aparato.materializar import VersionIncorrecta, materializar

REPO = Path(__file__).resolve().parents[4]


def _git(*args):
    return subprocess.run(
        ["git", "-C", str(REPO), *args], capture_output=True, check=True
    ).stdout.decode("utf-8").strip()


def _reloj(*instantes):
    it = iter(instantes)
    return lambda: next(it)


T0 = datetime(2026, 9, 24, 12, 0, 0, tzinfo=timezone.utc)
T1 = datetime(2026, 9, 24, 12, 0, 1, tzinfo=timezone.utc)


def _eventos(corrida):
    lineas = (corrida / "bitacora.jsonl").read_text(encoding="utf-8").splitlines()
    return [json.loads(l) for l in lineas]


@pytest.mark.parametrize("nombre", ["v1-serie", "v2-serie"])
def test_materializa_el_ref_real_y_su_version(tmp_path, nombre):
    brazo = BRAZOS[nombre]
    assert _git("cat-file", "-t", brazo.ref) in ("commit", "tag")

    corrida = materializar(brazo, tmp_path, ahora=lambda: T0)

    assert corrida.parent == tmp_path
    assert corrida.name.startswith(nombre) and "20260924T120000Z" in corrida.name
    proyecto = corrida / "proyecto"
    manifest = json.loads((proyecto / ".bootstrap-manifest.json").read_text(encoding="utf-8"))
    assert manifest["version"] == brazo.version
    assert manifest["variant"] == "personal"
    assert (proyecto / "CLAUDE.md").is_file()
    assert (proyecto / ".gitignore").is_file()

    evento = [e for e in _eventos(corrida) if e["evento"] == "materializado"]
    assert len(evento) == 1
    e = evento[0]
    assert e["ref"] == brazo.ref
    assert e["sha"] == _git("rev-parse", brazo.ref + "^{commit}")
    assert e["version"] == brazo.version
    assert e["brazo"] == nombre
    assert datetime.fromisoformat(e["ts"]).utcoffset().total_seconds() == 0


def test_el_agente_recibe_enunciado_y_datos_y_nada_mas_del_juguete(tmp_path):
    juguete = REPO / "medicion" / "v2" / "juguete-inventario"
    corrida = materializar(BRAZOS["v2-serie"], tmp_path, ahora=lambda: T0)
    proyecto = corrida / "proyecto"

    assert (proyecto / "enunciado.md").read_bytes() == (juguete / "enunciado.md").read_bytes()
    for csv in (juguete / "datos").iterdir():
        assert (proyecto / "datos" / csv.name).read_bytes() == csv.read_bytes()
    for oculto in ("cliente", "evals", "oraculo.py", "README.md"):
        assert not (proyecto / oculto).exists(), oculto


def test_version_equivocada_falla_nombrando_esperada_y_obtenida(tmp_path):
    trucho = Brazo("v2-serie", "v2.1.0", "2099-01-01+deadbee", "serie")

    with pytest.raises(VersionIncorrecta) as exc:
        materializar(trucho, tmp_path, ahora=lambda: T0)

    assert "2099-01-01+deadbee" in str(exc.value)
    assert "2026-09-23+3b3d849" in str(exc.value)
    (corrida,) = tmp_path.iterdir()
    ultimo = _eventos(corrida)[-1]
    assert ultimo["evento"] == "version_incorrecta"
    assert (ultimo["esperada"], ultimo["obtenida"]) == ("2099-01-01+deadbee", "2026-09-23+3b3d849")


def test_carpeta_existente_falla_y_no_toca_la_previa(tmp_path):
    brazo = BRAZOS["v1-serie"]
    primera = materializar(brazo, tmp_path, ahora=lambda: T0)
    antes = (primera / "bitacora.jsonl").read_bytes()

    with pytest.raises(FileExistsError):
        materializar(brazo, tmp_path, ahora=lambda: T0)

    assert (primera / "bitacora.jsonl").read_bytes() == antes
    segunda = materializar(brazo, tmp_path, ahora=lambda: T1)
    assert primera.is_dir() and segunda.is_dir() and primera != segunda
