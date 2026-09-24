import json
import subprocess
import sys
from pathlib import Path

import pytest

from aparato import brazos
from aparato.__main__ import main

APARATO = Path(__file__).resolve().parents[1]


def test_python_m_aparato_materializa_y_devuelve_la_carpeta(tmp_path):
    r = subprocess.run(
        [sys.executable, "-m", "aparato", "materializar", "--brazo", "v1-serie",
         "--raiz", str(tmp_path)],
        cwd=APARATO, capture_output=True,
    )
    assert r.returncode == 0, r.stderr.decode("utf-8", errors="replace")
    corrida = Path(r.stdout.decode("utf-8").strip())
    assert corrida.parent == tmp_path
    manifest = json.loads(
        (corrida / "proyecto" / ".bootstrap-manifest.json").read_text(encoding="utf-8")
    )
    assert manifest["version"] == "2026-09-11+567c77a"


def test_raiz_es_obligatoria():
    with pytest.raises(SystemExit) as exc:
        main(["materializar", "--brazo", "v1-serie"])
    assert exc.value.code != 0


def test_brazo_desconocido_falla():
    with pytest.raises(SystemExit) as exc:
        main(["materializar", "--brazo", "v3-nada", "--raiz", "x"])
    assert exc.value.code != 0


def test_version_equivocada_sale_distinto_de_cero_y_lo_dice(tmp_path, monkeypatch, capsys):
    trucho = brazos.Brazo("v2-serie", "v2.1.0", "2099-01-01+deadbee", "serie")
    monkeypatch.setitem(brazos.BRAZOS, "v2-serie", trucho)

    codigo = main(["materializar", "--brazo", "v2-serie", "--raiz", str(tmp_path)])

    assert codigo != 0
    err = capsys.readouterr().err
    assert "2099-01-01+deadbee" in err and "2026-09-23+3b3d849" in err
