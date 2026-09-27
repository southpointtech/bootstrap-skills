"""`correr` contra un `claude` falso (`claude_falso.py`): nunca el real, nunca la red, y nunca la
credencial real (`credencial=` apunta a un archivo falso)."""
import hashlib
import json
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

from aparato import brazos
from aparato import correr as correr_mod
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


# --- `_copiar`: el swap con renames no deja ventana de pérdida (B1) ----------------------------

def test_copiar_dos_veces_deja_solo_el_segundo_contenido(tmp_path):
    destino = tmp_path / "destino"
    scratch1, scratch2 = tmp_path / "scratch1", tmp_path / "scratch2"
    scratch1.mkdir()
    (scratch1 / "a.md").write_text("primero", encoding="utf-8")
    scratch2.mkdir()
    (scratch2 / "a.md").write_text("segundo", encoding="utf-8")

    s = Sondeo(tmp_path, destino, 0.05)
    s._copiar("carril-x", scratch1)
    s._copiar("carril-x", scratch2)

    carpeta = destino / "carril-x"
    assert (carpeta / ".scratch" / "a.md").read_text(encoding="utf-8") == "segundo"
    assert sorted(p.name for p in carpeta.iterdir()) == [".scratch"]  # sin nueva ni vieja


def test_copiar_con_vieja_sobrante_no_impide_la_copia_siguiente(tmp_path):
    destino = tmp_path / "destino"
    carpeta = destino / "carril-x"
    vigente = carpeta / ".scratch"
    vigente.mkdir(parents=True)
    (vigente / "a.md").write_text("anterior", encoding="utf-8")
    vieja = carpeta / ".scratch.vieja"
    vieja.mkdir()
    (vieja / "basura.md").write_text("basura de un intento previo", encoding="utf-8")

    scratch = tmp_path / "scratch"
    scratch.mkdir()
    (scratch / "a.md").write_text("nuevo", encoding="utf-8")

    s = Sondeo(tmp_path, destino, 0.05)
    s._copiar("carril-x", scratch)

    assert (vigente / "a.md").read_text(encoding="utf-8") == "nuevo"
    assert not vieja.exists()
    assert not (carpeta / ".scratch.nueva").exists()


def test_copiar_si_falla_el_primer_rename_sobrevive_la_copia_anterior(tmp_path, monkeypatch):
    destino = tmp_path / "destino"
    scratch1, scratch2 = tmp_path / "scratch1", tmp_path / "scratch2"
    scratch1.mkdir()
    (scratch1 / "a.md").write_text("anterior", encoding="utf-8")
    scratch2.mkdir()
    (scratch2 / "a.md").write_text("nuevo", encoding="utf-8")

    s = Sondeo(tmp_path, destino, 0.05)
    s._copiar("carril-x", scratch1)  # deja `vigente` con "anterior"

    carpeta = destino / "carril-x"
    vigente = carpeta / ".scratch"
    contenido_previo = (vigente / "a.md").read_bytes()

    real_rename = Path.rename

    def rename_falla(self, target):
        if self == vigente:  # el primer rename: `vigente` -> `.scratch.vieja`
            raise PermissionError("archivo tomado")
        return real_rename(self, target)

    monkeypatch.setattr(Path, "rename", rename_falla)

    with pytest.raises(PermissionError):
        s._copiar("carril-x", scratch2)

    assert (vigente / "a.md").read_bytes() == contenido_previo
    assert not (carpeta / ".scratch.nueva").exists()
    assert not (carpeta / ".scratch.vieja").exists()


def test_copiar_si_falla_el_segundo_rename_hace_rollback(tmp_path, monkeypatch):
    destino = tmp_path / "destino"
    scratch1, scratch2 = tmp_path / "scratch1", tmp_path / "scratch2"
    scratch1.mkdir()
    (scratch1 / "a.md").write_text("anterior", encoding="utf-8")
    scratch2.mkdir()
    (scratch2 / "a.md").write_text("nuevo", encoding="utf-8")

    s = Sondeo(tmp_path, destino, 0.05)
    s._copiar("carril-x", scratch1)  # deja `vigente` con "anterior"

    carpeta = destino / "carril-x"
    vigente = carpeta / ".scratch"
    contenido_previo = (vigente / "a.md").read_bytes()

    real_rename = Path.rename

    def rename_falla(self, target):
        if self.name == ".scratch.nueva":  # el segundo rename: `.scratch.nueva` -> `vigente`
            raise PermissionError("archivo tomado")
        return real_rename(self, target)

    monkeypatch.setattr(Path, "rename", rename_falla)

    with pytest.raises(PermissionError):
        s._copiar("carril-x", scratch2)

    assert (vigente / "a.md").read_bytes() == contenido_previo
    assert not (carpeta / ".scratch.vieja").exists()  # el rollback la deja en `vigente`
    # `.scratch.nueva` queda tirada: el próximo `_copiar` la limpia al arrancar (rmtree inicial).


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


@pytest.mark.parametrize("falla", ["carril-a", "carril-b"])
def test_la_falla_de_un_carril_no_impide_copiar_el_otro(entorno, monkeypatch, falla):
    # Mutante `continue` -> `break` en `sondear`: si el que falla es el primero en el orden de
    # `git worktree list` (acá, orden de creación: carril-a, carril-b), `break` corta el `for`
    # antes de llegar al otro carril en cada sondeo, y ese otro nunca queda copiado.
    original = Sondeo._copiar

    def copiar(self, nombre, scratch):
        if nombre == falla:
            raise PermissionError("archivo tomado")
        original(self, nombre, scratch)

    monkeypatch.setattr(Sondeo, "_copiar", copiar)
    ok = "carril-b" if falla == "carril-a" else "carril-a"
    motivo = entorno.correr([{"session_id": "s1", "worktree": ["carril-a", "carril-b"],
                              "espera": 0.5, "queda": True}])

    assert motivo == "completa"
    issue = entorno.corrida / "carriles" / ok / ".scratch" / "issues" / "01.md"
    assert issue.read_text(encoding="utf-8") == "Status: done\n"


# --- el evento `carril_sin_copia` (B2) ----------------------------------------------------------

def _agregar_worktree_con_scratch(proyecto, nombre, estado="Status: done\n"):
    """Crea un worktree de verdad en `proyecto` (como haría el agente) con un `.scratch/` ya
    poblado, para testear `Sondeo.sondear()` sin depender de `claude_falso` ni de tiempos reales."""
    wt = proyecto / ".claude" / "worktrees" / nombre
    subprocess.run(["git", "-C", str(proyecto), "worktree", "add", "-q", "-b", nombre, str(wt)],
                   check=True, capture_output=True)
    (wt / ".scratch" / "issues").mkdir(parents=True)
    (wt / ".scratch" / "issues" / "01.md").write_text(estado, encoding="utf-8")
    return wt


def test_carril_sin_copia_sin_copia_previa(entorno, monkeypatch):
    def copiar(self, nombre, scratch):
        raise PermissionError("archivo tomado")

    monkeypatch.setattr(Sondeo, "_copiar", copiar)
    # `sondeo=10` (mayor que la corrida entera): el hilo nunca despierta antes del `_parar.set()`
    # de `__exit__`, así que el único intento es el sondeo final, determinístico.
    motivo = entorno.correr([{"session_id": "s1", "worktree": "carril-a", "espera": 0.2,
                              "queda": True}], sondeo=10)

    assert motivo == "completa"
    ev = _nuevos(entorno.corrida)
    (evento,) = [x for x in ev if x["evento"] == "carril_sin_copia"]
    assert evento == {**evento, "carril": "carril-a", "copia_anterior": False}
    assert evento["error"].startswith("PermissionError: archivo tomado")
    assert ev[-1] == {**ev[-1], "evento": "corrida_cerrada", "motivo": "completa"}
    assert ev.index(evento) < ev.index(ev[-1])  # antes de `corrida_cerrada`


def test_carril_sin_copia_copia_anterior_true_si_hubo_una_copia_buena(entorno, monkeypatch):
    # Determinístico (sin hilo, sin timing): dos `sondear()` sincrónicos. El primero copia bien
    # (con el `_copiar` real); recién después se hace fallar el `_copiar`, así que el que falla es
    # el sondeo final, como describe la brief ("se copió bien y después falla en el sondeo final").
    proyecto = entorno.corrida / "proyecto"
    _agregar_worktree_con_scratch(proyecto, "carril-a")
    s = Sondeo(proyecto, entorno.corrida / "carriles", intervalo=999)

    s.sondear()  # la copia sale bien
    assert s.carriles_sin_copia() == []

    def copiar_falla(self, nombre, scratch):
        raise PermissionError("archivo tomado")

    monkeypatch.setattr(Sondeo, "_copiar", copiar_falla)
    s.sondear()  # el sondeo final falla

    assert s.carriles_sin_copia() == [
        ("carril-a", "PermissionError: archivo tomado", True),
    ]
    assert (entorno.corrida / "carriles" / "carril-a" / ".scratch").is_dir()  # la 1ª copia sigue


def test_sin_evento_si_el_ultimo_intento_copio_bien(entorno, monkeypatch):
    # Determinístico: falla el primer `sondear()`, sale bien el segundo (sin hilo, sin timing).
    proyecto = entorno.corrida / "proyecto"
    _agregar_worktree_con_scratch(proyecto, "carril-a")
    original, llamadas = Sondeo._copiar, []

    def copiar(self, nombre, scratch):
        llamadas.append(nombre)
        if len(llamadas) == 1:
            raise PermissionError("archivo tomado")  # el primer intento falla
        return original(self, nombre, scratch)  # el segundo sale bien

    monkeypatch.setattr(Sondeo, "_copiar", copiar)
    s = Sondeo(proyecto, entorno.corrida / "carriles", intervalo=999)

    s.sondear()  # falla
    assert s.carriles_sin_copia() == [("carril-a", "PermissionError: archivo tomado", False)]
    s.sondear()  # sale bien: limpia el fallo

    assert len(llamadas) == 2
    assert s.carriles_sin_copia() == []


def test_carril_sin_copia_aparece_aunque_el_agente_ya_borro_el_carril(entorno, monkeypatch):
    # Determinístico: el carril falla mientras vive, se borra, y un sondeo posterior (que ya no
    # lo ve en `git worktree list`) no lo toca ni le borra el fallo guardado.
    proyecto = entorno.corrida / "proyecto"
    wt = _agregar_worktree_con_scratch(proyecto, "carril-a")

    def copiar(self, nombre, scratch):
        raise PermissionError("archivo tomado")

    monkeypatch.setattr(Sondeo, "_copiar", copiar)
    s = Sondeo(proyecto, entorno.corrida / "carriles", intervalo=999)
    s.sondear()  # el carril todavía vive: falla y queda en memoria

    subprocess.run(["git", "-C", str(proyecto), "worktree", "remove", "--force", str(wt)],
                   check=True, capture_output=True)
    s.sondear()  # ya no aparece en `git worktree list`: no se reintenta ni se limpia

    assert s.carriles_sin_copia() == [("carril-a", "PermissionError: archivo tomado", False)]


def test_carril_sin_copia_cuando_copytree_falla_de_verdad(entorno, monkeypatch):
    # No reemplaza `_copiar`: hace fallar `shutil.copytree` en serio, el error más probable en la
    # práctica (un archivo tomado en Windows). Antes de este fix, `_copiar` lo atrapaba y volvía
    # sin tirar, y `sondear` lo contaba como éxito (Important #2 del review).
    def copytree_falla(*a, **kw):
        raise PermissionError("archivo tomado")

    monkeypatch.setattr(shutil, "copytree", copytree_falla)
    motivo = entorno.correr([{"session_id": "s1", "worktree": "carril-a", "espera": 0.2,
                              "queda": True}], sondeo=10)

    assert motivo == "completa"
    ev = _nuevos(entorno.corrida)
    (evento,) = [x for x in ev if x["evento"] == "carril_sin_copia"]
    assert evento == {**evento, "carril": "carril-a", "copia_anterior": False}
    assert evento["error"].startswith("PermissionError: archivo tomado")
    carpeta = entorno.corrida / "carriles" / "carril-a"
    assert not (carpeta / ".scratch").exists() and not (carpeta / ".scratch.nueva").exists()


def test_carril_sin_copia_no_se_duplica_si_falla_copiar_los_transcripts(entorno, monkeypatch):
    def copiar(self, nombre, scratch):
        raise PermissionError("archivo tomado")

    monkeypatch.setattr(Sondeo, "_copiar", copiar)

    def transcripts_falla(config, destino):
        raise RuntimeError("copiar transcripts roto a propósito")

    monkeypatch.setattr(correr_mod, "_copiar_transcripts", transcripts_falla)

    with pytest.raises(RuntimeError, match="copiar transcripts roto"):
        entorno.correr([{"session_id": "s1", "worktree": "carril-a", "espera": 0.2,
                         "queda": True}], sondeo=10)

    ev = _nuevos(entorno.corrida)
    sin_copia = [x for x in ev if x["evento"] == "carril_sin_copia"]
    assert len(sin_copia) == 1  # no duplicado por el `except` del camino de error
    assert sin_copia[0] == {**sin_copia[0], "carril": "carril-a"}
    assert ev[-1] == {**ev[-1], "evento": "corrida_cerrada", "motivo": "error"}
    assert ev[-1]["error"].startswith("RuntimeError: copiar transcripts roto")


def test_dos_carriles_sin_copia_salen_en_orden_de_nombre(entorno, monkeypatch):
    def copiar(self, nombre, scratch):
        raise PermissionError("archivo tomado")

    monkeypatch.setattr(Sondeo, "_copiar", copiar)
    motivo = entorno.correr([{"session_id": "s1", "worktree": ["carril-b", "carril-a"],
                              "espera": 0.3, "queda": True}], sondeo=10)

    assert motivo == "completa"
    ev = _nuevos(entorno.corrida)
    nombres = [x["carril"] for x in ev if x["evento"] == "carril_sin_copia"]
    assert nombres == ["carril-a", "carril-b"]


def test_si_falla_escribir_carril_sin_copia_no_cambia_el_motivo(entorno, monkeypatch):
    def copiar(self, nombre, scratch):
        raise PermissionError("archivo tomado")

    monkeypatch.setattr(Sondeo, "_copiar", copiar)
    original_registrar = mat.Bitacora.registrar

    def registrar(self, evento, **campos):
        if evento == "carril_sin_copia":
            raise OSError("disco lleno a propósito")
        return original_registrar(self, evento, **campos)

    monkeypatch.setattr(mat.Bitacora, "registrar", registrar)
    motivo = entorno.correr([{"session_id": "s1", "worktree": "carril-a", "espera": 0.2,
                              "queda": True}], sondeo=10)

    assert motivo == "completa"
    ev = _nuevos(entorno.corrida)
    assert [x["evento"] for x in ev if x["evento"] == "carril_sin_copia"] == []  # no se escribió
    assert ev[-1] == {**ev[-1], "evento": "corrida_cerrada", "motivo": "completa"}


def test_si_falla_escribir_carril_sin_copia_en_el_error_no_tapa_la_excepcion_original(
        entorno, monkeypatch):
    def copiar(self, nombre, scratch):
        raise PermissionError("archivo tomado")

    monkeypatch.setattr(Sondeo, "_copiar", copiar)
    original_registrar = mat.Bitacora.registrar

    def registrar(self, evento, **campos):
        if evento == "carril_sin_copia":
            raise OSError("disco lleno a propósito")
        return original_registrar(self, evento, **campos)

    monkeypatch.setattr(mat.Bitacora, "registrar", registrar)

    with pytest.raises(SesionFallida, match="7") as exc:
        entorno.correr([{"session_id": "s1", "worktree": "carril-a", "espera": 0.2,
                         "queda": True, "exit": 7}], sondeo=10)

    assert any("carril_sin_copia" in n and "disco lleno" in n
              for n in getattr(exc.value, "__notes__", []))
    ev = _nuevos(entorno.corrida)
    assert [x["evento"] for x in ev if x["evento"] == "carril_sin_copia"] == []  # no se escribió
    assert ev[-1] == {**ev[-1], "evento": "corrida_cerrada", "motivo": "error"}
    assert ev[-1]["error"].startswith("SesionFallida: ")  # la original, no tapada


def test_una_excepcion_que_no_es_oserror_en_copiar_no_se_traga(entorno, monkeypatch):
    def copiar(self, nombre, scratch):
        raise ValueError("no es OSError, a propósito")

    monkeypatch.setattr(Sondeo, "_copiar", copiar)

    with pytest.raises(ValueError, match="no es OSError"):
        entorno.correr([{"session_id": "s1", "worktree": "carril-a", "espera": 0.2,
                         "queda": True}], sondeo=10)

    ev = _nuevos(entorno.corrida)
    assert [x["evento"] for x in ev if x["evento"] == "carril_sin_copia"] == []
    assert ev[-1] == {**ev[-1], "evento": "corrida_cerrada", "motivo": "error"}
    assert ev[-1]["error"].startswith("ValueError: ")


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
