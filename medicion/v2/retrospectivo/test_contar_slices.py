"""contar_slices cuenta un cierre aunque `Slice-Close` no esté en el último párrafo del mensaje."""
import os
import subprocess

import contar_slices


def _commit(repo, mensaje, fecha):
    env = dict(os.environ, GIT_AUTHOR_DATE=fecha, GIT_COMMITTER_DATE=fecha)
    subprocess.run(["git", "-C", repo, "commit", "-q", "--allow-empty", "-m", mensaje], check=True, env=env)


def test_slice_close_arriba_de_la_atribucion(tmp_path, capsys):
    repo = str(tmp_path / "repo")
    subprocess.run(["git", "init", "-q", repo], check=True)
    subprocess.run(["git", "-C", repo, "config", "user.name", "t"], check=True)
    subprocess.run(["git", "-C", repo, "config", "user.email", "t@t"], check=True)
    # Forma real de este repo: el trailer va arriba del bloque de atribución, separado por una
    # línea en blanco, así que el parser de trailers de git no lo ve.
    _commit(repo, "feat: uno\n\nSlice-Close: x — uno\nReview-Rigor: light\n\nCo-Authored-By: a <a@a>", "2026-09-15T12:00:00Z")
    _commit(repo, "feat: dos\n\nSlice-Close: x — dos", "2026-09-25T12:00:00Z")
    agents = tmp_path / "agents.jsonl"
    agents.write_text('{"t0": "2026-09-15T12:00:00Z", "outTok": 10}\n', encoding="utf-8")

    contar_slices.main(repo, str(agents), "2026-09-21T18:47:24Z", "2026-09-27T17:53:00Z")

    salida = capsys.readouterr().out
    assert "antes: slices cerrados 1 (standard 0, light 1)" in salida
    assert "desde: slices cerrados 1 (standard 1, light 0)" in salida


def test_un_rebase_no_cambia_el_brazo_del_slice(tmp_path, capsys):
    repo = str(tmp_path / "repo")
    subprocess.run(["git", "init", "-q", repo], check=True)
    subprocess.run(["git", "-C", repo, "config", "user.name", "t"], check=True)
    subprocess.run(["git", "-C", repo, "config", "user.email", "t@t"], check=True)
    # Escrito antes del borde y rebaseado después: el slice es del "antes", como sus subagentes.
    env = dict(os.environ, GIT_AUTHOR_DATE="2026-09-19T12:00:00Z", GIT_COMMITTER_DATE="2026-09-23T13:44:00Z")
    subprocess.run(["git", "-C", repo, "commit", "-q", "--allow-empty", "-m", "feat: x\n\nSlice-Close: x"], check=True, env=env)
    agents = tmp_path / "agents.jsonl"
    agents.write_text('{"t0": "2026-09-19T12:00:00Z", "outTok": 10}\n', encoding="utf-8")

    contar_slices.main(repo, str(agents), "2026-09-21T18:47:24Z", "2026-09-27T17:53:00Z")

    assert "antes: slices cerrados 1 " in capsys.readouterr().out
