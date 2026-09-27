"""`correr` contra un `claude` falso (`claude_falso.py`): nunca el real, nunca la red, y nunca la
credencial real (`credencial=` apunta a un archivo falso)."""
import hashlib
import json
import sys
from pathlib import Path

import pytest

from aparato import brazos
from aparato import materializar as mat
from aparato.__main__ import main
from aparato.correr import SesionFallida, Sondeo, lanzar, respuesta_del_cliente
from aparato.materializar import materializar

from test_fallas import FALSO, JUGUETE, SCRIPT_OK, T0, _eventos, _repo_falso

FALSO_BIN = Path(__file__).with_name("claude_falso.py")
CLAUDE = [sys.executable, str(FALSO_BIN)]
EVALS = json.loads((JUGUETE / "evals" / "evals.json").read_text(encoding="utf-8"))
PROMPT = EVALS["evals"][0]["prompt"]
RESPUESTAS = (JUGUETE / "cliente" / "respuestas.md").read_text(encoding="utf-8")


def _seccion(letra):
    return RESPUESTAS.split(f"\n## {letra}\n", 1)[1].split("\n## ", 1)[0].strip()


@pytest.fixture
def entorno(tmp_path, monkeypatch):
    """Una corrida materializada (brazo falso, modo olas), una credencial falsa y un guion."""
    repo = _repo_falso(tmp_path, SCRIPT_OK)
    corrida = materializar(FALSO, tmp_path / "corridas", repo=repo, ahora=lambda: T0)
    cred = tmp_path / "credencial-falsa.json"
    cred.write_text('{"token": "falso-no-es-un-secreto"}', encoding="utf-8")
    guion = tmp_path / "guion" / "guion.json"
    guion.parent.mkdir()
    monkeypatch.setenv("GUION_FALSO", str(guion))

    class E:
        pass

    e = E()
    e.corrida, e.cred, e.guion, e.repo = corrida, cred, guion, repo

    def correr(pasos, **kw):
        guion.write_text(json.dumps(pasos, ensure_ascii=False), encoding="utf-8")
        kw.setdefault("sondeo", 0.05)
        return lanzar(corrida, FALSO, claude=CLAUDE, credencial=cred, **kw)

    def llamadas():
        ruta = guion.parent / "llamadas.jsonl"
        if not ruta.exists():
            return []
        return [json.loads(l) for l in ruta.read_text(encoding="utf-8").splitlines()]

    e.correr, e.llamadas = correr, llamadas
    return e


def _nuevos(corrida):
    """Los eventos de `correr`: lo que viene después de `materializado`."""
    eventos = _eventos(corrida)
    i = [x["evento"] for x in eventos].index("materializado")
    return eventos[i + 1:]


# --- una sesión sin preguntas ------------------------------------------------------------------

def test_sin_preguntas_la_corrida_cierra_completa(entorno, monkeypatch):
    monkeypatch.setenv("CLAUDE_EFFORT", "max")  # lo de la sesión que lanza no le llega al agente
    motivo = entorno.correr([{"session_id": "s1"}])

    assert motivo == "completa"
    ev = _nuevos(entorno.corrida)
    assert [(x["evento"], x.get("sesion"), x.get("session_id")) for x in ev] == [
        ("sesion_lanzada", 1, None), ("sesion_terminada", 1, "s1"), ("corrida_cerrada", None, None),
    ]
    assert ev[1]["exit_code"] == 0
    assert ev[-1]["motivo"] == "completa" and "error" not in ev[-1]

    (llamada,) = entorno.llamadas()
    argv = llamada["argv"]
    assert "-p" in argv and "--dangerously-skip-permissions" in argv
    assert argv[argv.index("--model") + 1] == "claude-opus-5-5"
    assert "--resume" not in argv and "--continue" not in argv
    assert Path(llamada["cwd"]) == (entorno.corrida / "proyecto").resolve()
    assert Path(llamada["config_dir"]) == entorno.corrida / "config"
    assert llamada["config"] == [".credentials.json"]
    assert llamada["credencial_sha256"] == hashlib.sha256(entorno.cred.read_bytes()).hexdigest()
    assert llamada["claude_env"] == ["CLAUDE_CONFIG_DIR"]
    assert llamada["prompt"] == PROMPT + "\n\n" + brazos.FRASE_MODO["olas"]


def test_las_frases_del_modo_son_las_del_contrato():
    assert brazos.FRASE_MODO == {
        "serie": "Trabajá un slice por vez, sin carriles ni worktrees paralelos.",
        "olas": "Trabajá por olas de carriles en paralelo, como indica "
                "`docs/ai-workflow/PARALELISMO.md`.",
    }


# --- la credencial -----------------------------------------------------------------------------

def test_la_credencial_se_borra_al_terminar(entorno):
    entorno.correr([{"session_id": "s1"}])
    assert not (entorno.corrida / "config" / ".credentials.json").exists()
    assert entorno.cred.exists()  # el origen no se toca


def test_la_credencial_se_borra_aunque_la_sesion_falle(entorno):
    with pytest.raises(SesionFallida, match="7"):
        entorno.correr([{"session_id": "s1", "exit": 7}])

    assert not (entorno.corrida / "config" / ".credentials.json").exists()
    ev = _nuevos(entorno.corrida)
    assert ev[-2]["exit_code"] == 7
    assert ev[-1]["evento"] == "corrida_cerrada" and ev[-1]["motivo"] == "error"
    assert ev[-1]["error"].startswith("SesionFallida: ")


def test_la_credencial_se_borra_aunque_falte_el_ejecutable(entorno):
    with pytest.raises(FileNotFoundError):
        lanzar(entorno.corrida, FALSO, claude=[str(entorno.corrida / "no-existe.exe")],
               credencial=entorno.cred, sondeo=0.05)

    assert not (entorno.corrida / "config" / ".credentials.json").exists()
    assert _nuevos(entorno.corrida)[-1]["error"].startswith("FileNotFoundError: ")


def test_sin_credencial_de_origen_no_se_lanza(entorno, tmp_path):
    with pytest.raises(FileNotFoundError):
        lanzar(entorno.corrida, FALSO, claude=CLAUDE, credencial=tmp_path / "no-hay.json",
               sondeo=0.05)

    assert entorno.llamadas() == []
    assert [x["evento"] for x in _nuevos(entorno.corrida)] == ["corrida_cerrada"]


# --- las rondas de preguntas -------------------------------------------------------------------

PREGUNTA_A_Y_C = "¿Qué cuenta como stock BAJO? ¿Y la fila de TOR-001?\r\n"


def test_una_ronda_copia_rutea_borra_y_relanza_con_resume(entorno):
    motivo = entorno.correr([{"session_id": "s1", "preguntas": PREGUNTA_A_Y_C},
                             {"session_id": "s1"}])

    assert motivo == "completa"
    copia = entorno.corrida / "preguntas" / "ronda-01.md"
    assert copia.read_bytes() == PREGUNTA_A_Y_C.encode("utf-8")
    assert not (entorno.corrida / "proyecto" / "PREGUNTAS.md").exists()

    ev = _nuevos(entorno.corrida)
    assert [x["evento"] for x in ev] == [
        "sesion_lanzada", "sesion_terminada", "ronda_preguntas",
        "sesion_lanzada", "sesion_terminada", "corrida_cerrada",
    ]
    ronda = ev[2]
    assert (ronda["ronda"], ronda["copia"], ronda["secciones"]) == (
        1, "preguntas/ronda-01.md", ["A", "C", "B"])
    assert (ev[3]["sesion"], ev[3]["session_id"]) == (2, "s1")

    primera, segunda = entorno.llamadas()
    assert segunda["argv"][segunda["argv"].index("--resume") + 1] == "s1"
    assert not segunda["habia_preguntas"]
    assert segunda["prompt"] == "\n\n".join([_seccion("A"), _seccion("C"), _seccion("B")])


def test_sin_session_id_se_relanza_con_continue(entorno):
    entorno.correr([{"session_id": "", "preguntas": "¿formato?"}, {"session_id": "s2"}])

    _, segunda = entorno.llamadas()
    assert "--continue" in segunda["argv"] and "--resume" not in segunda["argv"]


def test_una_sesion_sin_session_id_conserva_el_anterior(entorno):
    entorno.correr([{"session_id": "s1", "preguntas": "¿formato?"},
                    {"session_id": "", "preguntas": "¿formato?"}, {"session_id": "s1"}])

    tercera = entorno.llamadas()[2]["argv"]
    assert tercera[tercera.index("--resume") + 1] == "s1"


def test_un_session_id_nuevo_reemplaza_al_anterior(entorno):
    entorno.correr([{"session_id": "s1", "preguntas": "¿formato?"},
                    {"session_id": "s2", "preguntas": "¿formato?"}, {"session_id": "s2"}])

    tercera = entorno.llamadas()[2]["argv"]
    assert tercera[tercera.index("--resume") + 1] == "s2"


@pytest.mark.parametrize("texto, secciones", [
    ("¿Qué formato de salida querés?", ["B"]),
    ("¿Cuál es el umbral?", ["A", "B"]),
    ("¿Una cantidad negativa es válida?", ["C", "B"]),
    ("¿Qué pasa con -15 y con el MÍNIMO?", ["A", "C", "B"]),
])
def test_ruteo_de_la_respuesta(texto, secciones):
    obtenidas, respuesta = respuesta_del_cliente(texto, JUGUETE)
    assert obtenidas == secciones
    assert respuesta == "\n\n".join(_seccion(s) for s in secciones)


def test_tope_de_rondas_cierra_la_corrida(entorno):
    motivo = entorno.correr([{"session_id": "s1", "preguntas": "¿formato?"}], tope_rondas=1)

    assert motivo == "tope_rondas"
    assert len(entorno.llamadas()) == 2
    ev = _nuevos(entorno.corrida)
    assert [x["ronda"] for x in ev if x["evento"] == "ronda_preguntas"] == [1]
    assert ev[-1] == {**ev[-1], "evento": "corrida_cerrada", "motivo": "tope_rondas"}
    # La pregunta que no se respondió queda en `proyecto/` para auditar.
    assert (entorno.corrida / "proyecto" / "PREGUNTAS.md").exists()


# --- transcripts y carriles --------------------------------------------------------------------

def test_se_copian_todos_los_transcripts_crudos(entorno):
    entorno.correr([{"session_id": "s1", "preguntas": "¿formato?"},
                    {"session_id": "s1", "worktree": "carril-a", "espera": 0.3}])

    projects = entorno.corrida / "config" / "projects"
    origen = {p.relative_to(projects).as_posix(): p.read_bytes() for p in projects.rglob("*.jsonl")}
    transcripts = entorno.corrida / "transcripts"
    copia = {p.relative_to(transcripts).as_posix(): p.read_bytes()
             for p in transcripts.rglob("*.jsonl")}
    assert copia == origen
    nombres = {Path(k).name for k in copia}
    assert {"s1.jsonl", "agent-1.jsonl", "agent-2.jsonl", "carril.jsonl"} <= nombres


def test_se_conserva_el_scratch_de_un_carril_que_el_agente_borro(entorno):
    # El principal también tiene `.scratch/`, y no es un carril.
    (entorno.corrida / "proyecto" / ".scratch").mkdir()
    (entorno.corrida / "proyecto" / ".scratch" / "principal.md").write_text("x", encoding="utf-8")
    entorno.correr([{"session_id": "s1", "worktree": "carril-a", "espera": 1.0}])

    assert not (entorno.corrida / "proyecto" / ".claude" / "worktrees" / "carril-a").exists()
    copia = entorno.corrida / "carriles" / "carril-a" / ".scratch" / "issues" / "01.md"
    assert copia.read_text(encoding="utf-8") == "Status: done\n"
    assert sorted(p.name for p in (entorno.corrida / "carriles").iterdir()) == ["carril-a"]


def test_sin_carriles_no_hay_carpeta_carriles(entorno):
    entorno.correr([{"session_id": "s1"}])
    assert not (entorno.corrida / "carriles").exists()


def test_dos_carriles_vivos_a_la_vez_se_conservan_los_dos(entorno):
    entorno.correr([{"session_id": "s1", "worktree": ["carril-a", "carril-b"], "espera": 1.0}])

    carriles = entorno.corrida / "carriles"
    assert sorted(p.name for p in carriles.iterdir()) == ["carril-a", "carril-b"]
    for nombre in ("carril-a", "carril-b"):
        issue = carriles / nombre / ".scratch" / "issues" / "01.md"
        assert issue.read_text(encoding="utf-8") == "Status: done\n"


def test_una_copia_nueva_reemplaza_a_la_vieja(entorno):
    entorno.correr([{"session_id": "s1", "worktree": "carril-a", "espera": 0.5,
                     "estados": ["Status: in-progress\n", "Status: done\n"]}])

    carpeta = entorno.corrida / "carriles" / "carril-a"
    issue = carpeta / ".scratch" / "issues" / "01.md"
    assert issue.read_text(encoding="utf-8") == "Status: done\n"
    assert sorted(p.name for p in carpeta.iterdir()) == [".scratch"]  # sin `.scratch.nueva`


def test_una_falla_del_sondeo_no_mata_el_hilo(entorno, monkeypatch):
    # En Windows, un archivo tomado hace fallar el reemplazo de la copia; el próximo sondeo reintenta.
    original, fallas = Sondeo._copiar, []

    def copiar(self, nombre, scratch):
        if not fallas:
            fallas.append(nombre)
            raise PermissionError("archivo tomado")
        original(self, nombre, scratch)

    monkeypatch.setattr(Sondeo, "_copiar", copiar)
    motivo = entorno.correr([{"session_id": "s1", "worktree": "carril-a", "espera": 1.0}])

    assert motivo == "completa" and fallas == ["carril-a"]
    issue = entorno.corrida / "carriles" / "carril-a" / ".scratch" / "issues" / "01.md"
    assert issue.read_text(encoding="utf-8") == "Status: done\n"


def test_una_falla_del_sondeo_final_no_cambia_el_motivo(entorno, monkeypatch):
    def copiar(self, nombre, scratch):
        raise PermissionError("archivo tomado")

    monkeypatch.setattr(Sondeo, "_copiar", copiar)
    motivo = entorno.correr([{"session_id": "s1", "worktree": "carril-a", "espera": 0.2,
                              "queda": True}])

    assert motivo == "completa"
    assert _nuevos(entorno.corrida)[-1] == {**_nuevos(entorno.corrida)[-1],
                                            "evento": "corrida_cerrada", "motivo": "completa"}


def test_se_copian_los_transcripts_aunque_la_sesion_falle(entorno):
    with pytest.raises(SesionFallida):
        entorno.correr([{"session_id": "s1", "exit": 7}])

    transcripts = entorno.corrida / "transcripts"
    assert {p.name for p in transcripts.rglob("*.jsonl")} == {"s1.jsonl", "agent-1.jsonl"}


# --- el CLI ------------------------------------------------------------------------------------

def test_cli_correr_materializa_lanza_y_devuelve_la_carpeta(entorno, tmp_path, monkeypatch, capsys):
    monkeypatch.setattr(mat, "_repo", lambda: entorno.repo)
    monkeypatch.setitem(brazos.BRAZOS, "v2-olas", FALSO)
    entorno.guion.write_text(json.dumps([{"session_id": "s1"}]), encoding="utf-8")

    codigo = main(["correr", "--brazo", "v2-olas", "--raiz", str(tmp_path / "cli"),
                   "--claude", str(FALSO_BIN), "--credencial", str(entorno.cred),
                   "--tope-rondas", "2", "--sondeo", "0.05"])

    assert codigo == 0
    corrida = Path(capsys.readouterr().out.strip())
    assert corrida.parent == tmp_path / "cli"
    assert _eventos(corrida)[-1]["motivo"] == "completa"


def test_cli_correr_con_sesion_fallida_sale_con_1_sin_traceback(entorno, tmp_path, monkeypatch,
                                                                capsys):
    monkeypatch.setattr(mat, "_repo", lambda: entorno.repo)
    monkeypatch.setitem(brazos.BRAZOS, "v2-olas", FALSO)
    entorno.guion.write_text(json.dumps([{"session_id": "s1", "exit": 5}]), encoding="utf-8")

    codigo = main(["correr", "--brazo", "v2-olas", "--raiz", str(tmp_path / "cli"),
                   "--claude", str(FALSO_BIN), "--credencial", str(entorno.cred),
                   "--sondeo", "0.05"])

    salida = capsys.readouterr()
    assert codigo == 1
    assert salida.err.startswith("error: SesionFallida: ") and "Traceback" not in salida.err
    assert Path(salida.out.strip()).parent == tmp_path / "cli"  # la carpeta sale igual
    assert "falso-no-es-un-secreto" not in salida.err + salida.out
