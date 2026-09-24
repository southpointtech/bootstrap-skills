import json
import subprocess
import sys
from pathlib import Path

import pytest

from aparato import brazos
from aparato import materializar as mat
from aparato.__main__ import main

from test_fallas import FALSO, SCRIPT_MANIFEST_CORRUPTO, SCRIPT_OK, _repo_falso

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
    assert exc.value.code == 2


def test_brazo_desconocido_falla():
    with pytest.raises(SystemExit) as exc:
        main(["materializar", "--brazo", "v3-nada", "--raiz", "x"])
    assert exc.value.code == 2


def test_version_equivocada_sale_distinto_de_cero_y_lo_dice(tmp_path, monkeypatch, capsys):
    trucho = brazos.Brazo("v2-serie", "v2.1.0", "2099-01-01+deadbee", "serie")
    monkeypatch.setitem(brazos.BRAZOS, "v2-serie", trucho)

    codigo = main(["materializar", "--brazo", "v2-serie", "--raiz", str(tmp_path)])

    assert codigo == 1
    err = capsys.readouterr().err
    assert "2099-01-01+deadbee" in err and "2026-09-23+3b3d849" in err


def _falla_controlada(capsys, argv, *textos):
    codigo = main(argv)
    err = capsys.readouterr().err
    assert codigo == 1
    assert err.startswith("error: ") and "Traceback" not in err
    for t in textos:
        assert t in err, (t, err)


def test_exe_ausente_sale_con_1_y_mensaje(tmp_path, monkeypatch, capsys):
    monkeypatch.setattr(mat, "GIT", "git-que-no-existe")
    _falla_controlada(capsys, ["materializar", "--brazo", "v1-serie", "--raiz", str(tmp_path)],
                      "git-que-no-existe")


def test_manifest_corrupto_sale_con_1_y_mensaje(tmp_path, monkeypatch, capsys):
    repo = _repo_falso(tmp_path, SCRIPT_MANIFEST_CORRUPTO)
    monkeypatch.setattr(mat, "_repo", lambda: repo)
    monkeypatch.setitem(brazos.BRAZOS, "v2-olas", FALSO)
    _falla_controlada(capsys, ["materializar", "--brazo", "v2-olas",
                               "--raiz", str(tmp_path / "corridas")], "JSONDecodeError")


def test_ref_inexistente_sale_con_1_y_mensaje(tmp_path, monkeypatch, capsys):
    monkeypatch.setitem(brazos.BRAZOS, "v2-olas",
                        brazos.Brazo("v2-olas", "no-existe-este-ref", "v", "olas"))
    _falla_controlada(capsys, ["materializar", "--brazo", "v2-olas", "--raiz", str(tmp_path)],
                      "no-existe-este-ref")


def test_raiz_dentro_del_repo_sale_con_1_y_mensaje(tmp_path, monkeypatch, capsys):
    # Contra un repo falso: si la guarda se rompe, la corrida cae en tmp_path y no en este repo.
    repo = _repo_falso(tmp_path, SCRIPT_OK)
    monkeypatch.setattr(mat, "_repo", lambda: repo)
    monkeypatch.setitem(brazos.BRAZOS, "v2-olas", FALSO)
    _falla_controlada(capsys, ["materializar", "--brazo", "v2-olas",
                               "--raiz", str(repo / "corridas")], "RaizDentroDelRepo")
    assert not (repo / "corridas").exists()


def test_tar_corrupto_sale_con_1_sin_traceback(tmp_path, monkeypatch, capsys):
    repo = _repo_falso(tmp_path, SCRIPT_OK)
    monkeypatch.setattr(mat, "_repo", lambda: repo)
    monkeypatch.setitem(brazos.BRAZOS, "v2-olas", FALSO)
    original = mat._correr
    monkeypatch.setattr(mat, "_correr", lambda args, cwd=None:
                        b"esto no es un tar" if "archive" in args else original(args, cwd=cwd))
    _falla_controlada(capsys, ["materializar", "--brazo", "v2-olas",
                               "--raiz", str(tmp_path / "corridas")], "ReadError")


def test_manifest_lista_sale_con_1_sin_traceback(tmp_path, monkeypatch, capsys):
    from test_fallas import SCRIPT_MANIFEST_LISTA
    repo = _repo_falso(tmp_path, SCRIPT_MANIFEST_LISTA)
    monkeypatch.setattr(mat, "_repo", lambda: repo)
    monkeypatch.setitem(brazos.BRAZOS, "v2-olas", FALSO)
    _falla_controlada(capsys, ["materializar", "--brazo", "v2-olas",
                               "--raiz", str(tmp_path / "corridas")], "ValueError")
