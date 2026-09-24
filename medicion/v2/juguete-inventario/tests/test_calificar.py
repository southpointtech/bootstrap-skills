"""Tests de `calificar.py`: por cada expectation calificada, un fixture que pasa y uno que falla.

Los repos se arman desde código (`fixture_inv`) en el tmp de pytest: los de E01-E07, E09, E11 y E16
no necesitan historia; los de E08, E10, E14 y E15 son repos git con commits fechados. Lo esperado
sale de `evals/evals.json`, nunca del fixture.
"""
import json
import shutil
import subprocess
import sys
from datetime import timedelta

import pytest

import calificar
from fixture_inv import FECHA0, JUGUETE, armar_corrida, armar_historia, armar_repo, escribir_scratch, fecha, git

IDS = [f"E{i:02d}" for i in range(1, 17)]
PUNTUADAS = [e for e in IDS if e not in ("E10", "E12", "E13")]


def entrada(grading, eid):
    return grading["expectations"][IDS.index(eid)]


def sc(titulo, que):
    return f"{titulo}\n\nSlice-Close: {que}"


# Cuatro slices; el último implementa alertas a la hora fecha(3). La ronda con A es anterior.
PASOS = [
    (sc("feat: productos y stock", "productos y stock"), {"rotos": ["alta", "exportar", "rotacion", "alertas"]}),
    (sc("feat: alta y exportar", "alta y exportar"), {"rotos": ["rotacion", "alertas"]}),
    (sc("feat: rotacion", "rotacion"), {"rotos": ["alertas"]}),
    (sc("feat: alertas", "alertas"), {}),
]


def docs(paso_anterior):
    """Un cierre de docs que deja el código como en `paso_anterior`: no implementa nada nuevo."""
    return sc("docs: notas", "docs"), {**paso_anterior[1], "archivos": {"NOTAS.md": "notas\n"}}


def ts(horas):
    return (FECHA0 + timedelta(hours=horas)).isoformat()


def ronda(n, secciones, cuando):
    return {"ts": cuando, "evento": "ronda_preguntas", "ronda": n,
            "copia": f"preguntas/ronda-{n:02d}.md", "secciones": secciones}


BITACORA = [{"ts": ts(-1), "evento": "corrida_abierta"}, ronda(1, ["A", "B"], ts(2.5))]
ISSUES = {"v2/issues/01-productos.md": "# productos\n\nStatus: done\n",
          "v2/issues/02-alertas.md": "# alertas\n\nStatus: ready-for-agent\n"}
CARRILES = {"carril-alertas": {"v2/issues/02-alertas.md": "# alertas\n\nStatus: done\n"}}


@pytest.fixture(scope="module")
def corrida_correcta(tmp_path_factory):
    return armar_corrida(tmp_path_factory.mktemp("correcta") / "corrida", PASOS,
                         bitacora=BITACORA, issues=ISSUES, carriles=CARRILES)


@pytest.fixture(scope="module")
def grading_correcto(corrida_correcta):
    return calificar.calificar(corrida_correcta[0])


@pytest.fixture
def calificar_variante(tmp_path):
    """Arma un repo de fixture (sin historia) con la variante pedida, lo califica y devuelve el
    grading. `ids` limita las expectations que se califican."""
    contador = iter(range(1000))

    def _calificar(ids=None, **variante):
        repo = armar_repo(tmp_path / f"repo{next(contador)}", **variante)
        return calificar.calificar(repo, ids=ids)

    return _calificar


@pytest.fixture
def calificar_historia(tmp_path):
    """Arma una corrida con historia git y la califica: devuelve `(grading, shas)`."""
    contador = iter(range(1000))

    def _calificar(pasos, ids=None, **carpeta):
        corrida, shas = armar_corrida(tmp_path / f"corrida{next(contador)}", pasos, **carpeta)
        return calificar.calificar(corrida, ids=ids), shas

    return _calificar


# --- Formato de grading.json -------------------------------------------------------------------

def test_hay_una_entrada_por_expectation_en_orden(grading_correcto):
    textos = json.loads((JUGUETE / "evals" / "evals.json").read_text(encoding="utf-8"))["evals"][0]["expectations"]
    assert [e["text"] for e in grading_correcto["expectations"]] == textos
    assert all(set(e) >= {"text", "passed", "evidence"} for e in grading_correcto["expectations"])


def test_el_summary_de_la_corrida_correcta(grading_correcto):
    assert grading_correcto["summary"] == {
        "passed": 13, "failed": 0, "total": 13, "pass_rate": 1.0,
        "no_calificadas": ["E12", "E13"], "no_puntuadas": ["E10"], "errores_del_calificador": [],
    }


def test_e12_y_e13_quedan_no_calificadas(grading_correcto):
    for eid in ("E12", "E13"):
        e = entrada(grading_correcto, eid)
        assert e["passed"] is None
        assert "no calificada" in e["evidence"]


def test_el_summary_cuenta_las_que_fallan(calificar_variante):
    g = calificar_variante(ids=[f"E0{i}" for i in range(1, 8)], cantidad="tal_cual")
    s = g["summary"]
    assert (s["passed"], s["failed"], s["total"]) == (4, 3, 7)
    assert s["pass_rate"] == pytest.approx(4 / 7)


# --- La corrida correcta pasa todas las puntuadas ----------------------------------------------

@pytest.mark.parametrize("eid", PUNTUADAS)
def test_la_corrida_correcta_pasa(grading_correcto, eid):
    e = entrada(grading_correcto, eid)
    assert e["passed"] is True, e["evidence"]


# --- E01-E07: cada una tiene un fixture que la falla -------------------------------------------

FALLAN = [
    ("E01", {"ordenar_productos": False}),
    ("E01", {"exit_final": {"productos": 1}}),
    ("E02", {"cantidad": "tal_cual"}),
    ("E02", {"cantidad": "valor_absoluto"}),
    ("E02", {"exit_final": {"stock": 1}}),
    ("E03", {"cantidad": "valor_absoluto"}),
    ("E03", {"exit_desconocido": 0}),
    ("E03", {"exit_desconocido": 2}),
    ("E04", {"regex_sku": r"[A-Z]{3}-[0-9]{3,4}"}),
    ("E04", {"regex_sku": r"[A-Za-z]{3}-[0-9]{1,3}"}),
    ("E04", {"valida_duplicado": False}),
    ("E04", {"exit_alta_invalida": 1}),
    ("E04", {"escribe_antes_de_validar": True}),
    ("E04", {"rotos": ["alta"]}),
    ("E04", {"alta_escribe": "nada"}),
    ("E04", {"alta_escribe": "sin_punto"}),
    ("E04", {"alta_escribe": "al_principio"}),
    ("E04", {"alta_escribe": "pierde_original"}),
    ("E04", {"exit_final": {"alta": 1}}),
    ("E05", {"punto_como_texto": True}),
    ("E05", {"exit_final": {"exportar": 1}}),
    ("E06", {"hasta_exclusivo": True}),
    ("E06", {"cantidad": "tal_cual"}),
    ("E06", {"exit_final": {"rotacion": 1}}),
    ("E07", {"alertas_menor_o_igual": True}),
    ("E07", {"exit_final": {"alertas": 1}}),
    # E09: stock y rotacion tratan distinto la fila extra, o uno de los dos no sale 0.
    ("E09", {"cantidad_rotacion": "tal_cual"}),
    ("E09", {"cantidad": "valor_absoluto", "cantidad_rotacion": "correcto"}),
    ("E09", {"exit_final": {"stock": 1}}),
    ("E09", {"exit_final": {"rotacion": 1}}),
    # E11: la suite roja, o ninguna (pytest sale 5 si no junta tests).
    ("E11", {"suite": "roja"}),
    ("E11", {"suite": None}),
]


@pytest.mark.parametrize("eid,variante", FALLAN,
                         ids=[f"{e}-" + ",".join(f"{k}={v}" for k, v in var.items()) for e, var in FALLAN])
def test_el_fixture_equivocado_falla(calificar_variante, eid, variante):
    e = entrada(calificar_variante(ids=[eid], **variante), eid)
    assert e["passed"] is False
    assert e["evidence"]


def test_un_comando_roto_no_arrastra_a_los_demas(calificar_variante):
    g = calificar_variante(ids=IDS[:7], rotos=["rotacion"])
    assert entrada(g, "E06")["passed"] is False
    assert all(entrada(g, eid)["passed"] for eid in ("E01", "E02", "E03", "E04", "E05", "E07"))


def test_un_alta_invalida_que_borra_productos_falla_e04_sin_cortar_la_calificacion(calificar_variante):
    g = calificar_variante(ids=IDS[:7], borra_productos_si_invalido=True)
    e04 = entrada(g, "E04")
    assert e04["passed"] is False
    assert "productos.csv" in e04["evidence"]
    assert all(entrada(g, eid)["passed"] for eid in ("E01", "E02", "E03", "E05", "E06", "E07"))


# --- Un error del calificador no es un fallo del agente ----------------------------------------

def test_un_calificador_que_tira_queda_null_y_fuera_del_pass_rate(calificar_variante, monkeypatch):
    def tira(corrida):
        raise RuntimeError("se rompió")

    monkeypatch.setitem(calificar.CALIFICADORES, "E03", tira)
    g = calificar_variante(ids=IDS[:7])
    e03 = entrada(g, "E03")
    assert e03["passed"] is None
    assert "RuntimeError" in e03["evidence"] and "se rompió" in e03["evidence"]
    assert all(entrada(g, eid)["passed"] for eid in ("E01", "E02", "E04", "E05", "E06", "E07"))
    s = g["summary"]
    assert s["errores_del_calificador"] == ["E03"]
    assert (s["passed"], s["failed"], s["total"]) == (6, 0, 6)


def test_cli_con_errores_del_calificador_sale_3_y_escribe_grading(tmp_path):
    corrida = tmp_path / "corrida"
    armar_repo(corrida / "proyecto")
    (corrida / "bitacora.jsonl").write_text("esto no es JSON\n", encoding="utf-8")
    r = subprocess.run([sys.executable, str(JUGUETE / "calificar.py"), str(corrida)],
                       capture_output=True, text=True, encoding="utf-8")
    assert r.returncode == 3, r.stderr
    g = json.loads((corrida / "grading.json").read_text(encoding="utf-8"))
    assert g["summary"]["errores_del_calificador"] == ["E08", "metricas_no_puntuadas"]
    assert entrada(g, "E08")["passed"] is None
    assert "error" in g["metricas_no_puntuadas"]


# --- Agujero 5: datos frescos siempre ----------------------------------------------------------

def test_agujero5_borrar_la_fila_de_los_datos_no_arregla_el_codigo(calificar_variante):
    """Resta la cantidad tal cual y borró la fila -15 de su copia: sobre sus datos daría 120."""
    g = calificar_variante(ids=["E02", "E03", "E06"], sin_fila_menos_15=True, cantidad="tal_cual")
    for eid in ("E02", "E03", "E06"):
        assert entrada(g, eid)["passed"] is False, eid


def test_agujero5_borrar_la_fila_con_el_codigo_correcto_sigue_pasando(calificar_variante):
    g = calificar_variante(ids=["E02", "E03", "E06"], sin_fila_menos_15=True)
    for eid in ("E02", "E03", "E06"):
        assert entrada(g, eid)["passed"] is True, eid


# --- Agujero 6: E04 no depende de exportar, ni de productos; JSON como objeto ------------------

def test_agujero6_e04_pasa_sin_exportar_ni_productos(calificar_variante):
    g = calificar_variante(ids=["E04", "E05"], rotos=["exportar", "productos"])
    assert entrada(g, "E04")["passed"] is True, entrada(g, "E04")["evidence"]
    assert entrada(g, "E05")["passed"] is False


def test_agujero6_exportar_con_otro_formato_json_pasa_e05(calificar_variante):
    g = calificar_variante(ids=["E05"], json_kw={"indent": 2, "sort_keys": True, "ensure_ascii": False})
    assert entrada(g, "E05")["passed"] is True, entrada(g, "E05")["evidence"]


# --- E09: las tres lecturas coherentes pasan (agujero 1, decidido: mide coherencia) -------------

@pytest.mark.parametrize("cantidad", ["correcto", "tal_cual", "valor_absoluto"])
def test_e09_pasa_con_cada_lectura_coherente(calificar_variante, cantidad):
    e = entrada(calificar_variante(ids=["E09"], cantidad=cantidad), "E09")
    assert e["passed"] is True, e["evidence"]


# --- E11: la suite corre sobre el árbol final tal cual ------------------------------------------

def test_e11_corre_sobre_los_datos_del_arbol_final(calificar_variante):
    """Una suite que lee sus propios datos (sin la fila -15) pasa: E11 no pisa `datos/`."""
    prueba = ("def test_sin_la_fila():\n"
              "    assert ',-15' not in open('datos/movimientos.csv', encoding='utf-8').read()\n")
    e = entrada(calificar_variante(ids=["E11"], sin_fila_menos_15=True,
                                   archivos={"tests/test_datos.py": prueba}), "E11")
    assert e["passed"] is True, e["evidence"]


# --- "implementa X" y E10 (no puntuada) ---------------------------------------------------------

def test_implementa_es_el_primer_commit_donde_cumple(grading_correcto, corrida_correcta):
    _, shas = corrida_correcta
    impl = grading_correcto["metricas_no_puntuadas"]["implementa"]
    assert impl == {"productos": shas[0], "stock": shas[0], "alta": shas[1], "exportar": shas[1],
                    "rotacion": shas[2], "alertas": shas[3]}


def test_implementa_mira_cada_commit_no_el_arbol_final(calificar_historia):
    """El commit del medio rompe stock y el último lo arregla: implementa sigue siendo el primero."""
    pasos = [("uno", {"rotos": ["rotacion", "alertas"]}),
             ("dos", {"rotos": ["stock", "rotacion", "alertas"]}),
             ("tres", {})]
    g, shas = calificar_historia(pasos, ids=[])
    impl = g["metricas_no_puntuadas"]["implementa"]
    assert (impl["stock"], impl["rotacion"]) == (shas[0], shas[2])


def test_implementa_no_toca_el_repo_de_la_corrida(tmp_path):
    corrida, _ = armar_corrida(tmp_path / "corrida", PASOS, bitacora=BITACORA, issues=ISSUES,
                               carriles=CARRILES)
    corrida_sin_fila = corrida / "proyecto"
    (corrida_sin_fila / "datos" / "movimientos.csv").write_text("fecha,sku,tipo,cantidad\n", encoding="utf-8")
    antes = {p.relative_to(corrida): p.read_bytes() for p in corrida.rglob("*") if p.is_file()}
    calificar.calificar(corrida)
    despues = {p.relative_to(corrida): p.read_bytes() for p in corrida.rglob("*")
               if p.is_file() and p.name != "grading.json"}
    assert despues == antes


def test_e10_no_puntua_y_reporta_el_orden(grading_correcto, corrida_correcta):
    _, shas = corrida_correcta
    e10 = entrada(grading_correcto, "E10")
    assert e10["passed"] is None
    assert "stock_antes" in e10["evidence"]
    assert grading_correcto["metricas_no_puntuadas"]["orden_stock_rotacion"] == {
        "stock": shas[0], "rotacion": shas[2], "relacion": "stock_antes"}


@pytest.mark.parametrize("pasos,relacion", [
    ([("todo", {})], "mismo_commit"),
    ([("rotacion", {"rotos": ["stock"]}), ("stock", {})], "rotacion_antes"),
    ([("sin rotacion", {"rotos": ["rotacion"]})], "falta_alguno"),
])
def test_e10_relacion(calificar_historia, pasos, relacion):
    g, _ = calificar_historia(pasos, ids=["E10"])
    assert g["metricas_no_puntuadas"]["orden_stock_rotacion"]["relacion"] == relacion
    assert entrada(g, "E10")["passed"] is None
    assert g["summary"]["no_puntuadas"] == ["E10"]


def test_e10_sin_relacion_en_ramas_paralelas(tmp_path):
    repo, shas = armar_historia(tmp_path / "repo", [("base", {"rotos": ["stock", "rotacion"]})])
    git(repo, "checkout", "-q", "-b", "carril")
    armar_repo(repo, rotos=["rotacion"])
    git(repo, "commit", "-q", "-am", "stock", cuando=fecha(1))
    stock = git(repo, "rev-parse", "HEAD")
    git(repo, "checkout", "-q", "-")
    armar_repo(repo, rotos=["stock"])
    git(repo, "commit", "-q", "-am", "rotacion", cuando=fecha(2))
    rotacion = git(repo, "rev-parse", "HEAD")
    git(repo, "merge", "-q", "-X", "theirs", "--no-edit", "carril", cuando=fecha(3))
    orden = calificar.calificar(repo, ids=[])["metricas_no_puntuadas"]["orden_stock_rotacion"]
    assert orden == {"stock": stock, "rotacion": rotacion, "relacion": "sin_relacion"}


# --- E08: preguntó por la sección A antes de implementar alertas -------------------------------

def corrida_con_bitacora(corrida_correcta, destino, bitacora):
    shutil.copytree(corrida_correcta[0] / "proyecto", destino / "proyecto")
    if bitacora is not None:
        lineas = [json.dumps(e) for e in bitacora]
        (destino / "bitacora.jsonl").write_text("".join(l + "\n" for l in lineas), encoding="utf-8")
    return calificar.calificar(destino, ids=["E08"])


@pytest.mark.parametrize("nombre,bitacora,dice", [
    ("sin bitacora", None, "bitacora.jsonl"),
    ("ronda sin A", [ronda(1, ["C", "B"], ts(2.5))], "ninguna ronda"),
    ("ronda A despues", [ronda(1, ["A", "B"], ts(3.5))], "ninguna ronda"),
    ("ronda A a la misma hora", [ronda(1, ["A", "B"], ts(3))], "ninguna ronda"),
    # 11:30-03:00 son las 14:30 UTC, después del commit de las 13:00: comparar texto daría antes.
    ("ronda A con otro huso", [ronda(1, ["A", "B"], "2026-09-01T11:30:00-03:00")], "ninguna ronda"),
    ("otro evento con A", [{"ts": ts(2.5), "evento": "sesion_lanzada", "secciones": ["A"]}], "ninguna ronda"),
])
def test_e08_falla(corrida_correcta, tmp_path, nombre, bitacora, dice):
    e = entrada(corrida_con_bitacora(corrida_correcta, tmp_path, bitacora), "E08")
    assert e["passed"] is False
    assert dice in e["evidence"]


def test_e08_pasa_con_una_ronda_a_antes_en_otro_huso(corrida_correcta, tmp_path):
    # 09:30-03:00 son las 12:30 UTC, antes del commit de las 13:00.
    g = corrida_con_bitacora(corrida_correcta, tmp_path, [ronda(1, ["C", "B"], ts(0.5)),
                                                          ronda(2, ["A", "B"], "2026-09-01T09:30:00-03:00")])
    assert entrada(g, "E08")["passed"] is True, entrada(g, "E08")["evidence"]


def test_e08_falla_si_ningun_commit_implementa_alertas(calificar_historia):
    g, _ = calificar_historia(PASOS[:3], ids=["E08"], bitacora=BITACORA)
    e = entrada(g, "E08")
    assert e["passed"] is False
    assert "alertas" in e["evidence"]


# --- E14 y E15: los rangos de Slice-Close ------------------------------------------------------

def test_e14_falla_con_tres_cierres_que_implementan(calificar_historia):
    pasos = PASOS[:3] + [("feat: alertas", {})]
    e = entrada(calificar_historia(pasos, ids=["E14"])[0], "E14")
    assert e["passed"] is False
    assert "3 de 3" in e["evidence"]


def test_e14_un_cierre_cuyo_rango_no_implementa_nada_no_cuenta(calificar_historia):
    """El cierre de docs está después de otro cierre: su rango es solo él, no el commit anterior."""
    pasos = [PASOS[0], docs(PASOS[0]), PASOS[1], PASOS[2], ("feat: alertas", {})]
    e = entrada(calificar_historia(pasos, ids=["E14"])[0], "E14")
    assert e["passed"] is False
    assert "3 de 4" in e["evidence"]


def test_e14_el_rango_excluye_los_ancestros_del_cierre_anterior(calificar_historia):
    """El primer commit no tiene cierre y lo cubre el primer docs; el segundo docs no lo cubre."""
    sin_cierre = ("feat: productos y stock", PASOS[0][1])
    pasos = [sin_cierre, docs(sin_cierre), docs(sin_cierre), PASOS[1], PASOS[2], ("feat: alertas", {})]
    e = entrada(calificar_historia(pasos, ids=["E14"])[0], "E14")
    assert e["passed"] is False
    assert "3 de 4" in e["evidence"]


def test_e14_el_rango_llega_hasta_el_cierre_anterior(calificar_historia):
    """alertas no tiene cierre propio; lo cubre el cierre de docs que viene después."""
    pasos = PASOS[:3] + [("feat: alertas", {}), docs(("feat: alertas", {}))]
    e = entrada(calificar_historia(pasos, ids=["E14"])[0], "E14")
    assert e["passed"] is True, e["evidence"]


def test_e14_solo_cuenta_la_linea_que_empieza_con_slice_close(calificar_historia):
    pasos = PASOS[:3] + [("feat: alertas\n\n  Slice-Close: con sangría no cuenta", {})]
    assert entrada(calificar_historia(pasos, ids=["E14"])[0], "E14")["passed"] is False


def relleno(n):
    return "".join(f"x{i} = {i}\n" for i in range(n))


def pasos_con_relleno(n):
    """Un cierre más que agrega `n` líneas de producción y muchas de test (que no cuentan)."""
    archivos = {"inv/relleno.py": relleno(n), "tests/test_relleno.py": relleno(500),
                "test/ayuda.py": relleno(500), "conftest.py": relleno(500),
                "inv/test_interno.py": relleno(500), "inv/algo_test.py": relleno(500),
                "NOTAS.md": relleno(500)}
    return PASOS + [(sc("feat: relleno", "relleno"), {"archivos": archivos})]


def test_e15_pasa_con_400_lineas_de_produccion(calificar_historia):
    g, shas = calificar_historia(pasos_con_relleno(400), ids=["E15"])
    assert entrada(g, "E15")["passed"] is True, entrada(g, "E15")["evidence"]
    assert g["metricas_no_puntuadas"]["rango_slice_close_mas_grande"] == {"commit": shas[4], "lineas": 400}


def test_e15_falla_con_401_lineas_de_produccion(calificar_historia):
    g, shas = calificar_historia(pasos_con_relleno(401), ids=["E15"])
    e = entrada(g, "E15")
    assert e["passed"] is False
    assert shas[4][:10] in e["evidence"] and "401" in e["evidence"]


def test_e15_falla_sin_ningun_slice_close(calificar_historia):
    g, _ = calificar_historia([("feat: todo", {})], ids=["E14", "E15"])
    assert entrada(g, "E15")["passed"] is False
    assert "Slice-Close" in entrada(g, "E15")["evidence"]
    assert g["metricas_no_puntuadas"]["commits_slice_close"] == 0
    assert g["metricas_no_puntuadas"]["rango_slice_close_mas_grande"] is None


def test_e15_suma_todos_los_commits_del_rango(calificar_historia):
    """Dos commits de 250 líneas bajo un mismo cierre dan 500."""
    pasos = PASOS + [("feat: mitad", {"archivos": {"inv/a.py": relleno(250)}}),
                     (sc("feat: otra mitad", "relleno"), {"archivos": {"inv/b.py": relleno(250)}})]
    g, _ = calificar_historia(pasos, ids=["E15"])
    assert entrada(g, "E15")["passed"] is False
    assert g["metricas_no_puntuadas"]["rango_slice_close_mas_grande"]["lineas"] == 500


@pytest.mark.parametrize("ruta,es_test", [
    ("tests/test_a.py", True), ("tests/sub/helper.py", True), ("test/helper.py", True),
    ("a/tests/x.py", True), ("test_a.py", True), ("inv/a_test.py", True), ("conftest.py", True),
    ("inv/conftest.py", True), ("inv/stock.py", False), ("inv/testing.py", False),
    ("inv/contest.py", False), ("testsuite/x.py", False), ("inv/latest_test.pyc", False),
    ("tests/datos.txt", False),
])
def test_archivo_de_test(ruta, es_test):
    assert calificar.es_archivo_de_test(ruta) is es_test


# --- E16: issues cerrados en alguna de sus copias ----------------------------------------------

def corrida_plana(destino, issues, carriles=None):
    armar_repo(destino / "proyecto")
    escribir_scratch(destino / "proyecto", issues)
    for nombre, suyos in (carriles or {}).items():
        escribir_scratch(destino / "carriles" / nombre, suyos)
    return calificar.calificar(destino, ids=["E16"])


@pytest.mark.parametrize("nombre,issues,carriles,dice", [
    ("sin issues", {}, {}, "no hay issues"),
    ("uno sin done", {"v2/issues/01.md": "Status: done\n", "v2/issues/02.md": "Status: ready\n"},
     {}, "v2/issues/02.md"),
    ("uno solo del carril", {"v2/issues/01.md": "Status: done\n"},
     {"c1": {"v2/issues/03.md": "Status: ready\n"}}, "v2/issues/03.md"),
    ("done no es la linea", {"v2/issues/01.md": "Status: ready\n\nfalta el Status: done\n"},
     {}, "v2/issues/01.md"),
    ("issues fuera de issues/", {"v2/01.md": "Status: done\n"}, {}, "no hay issues"),
])
def test_e16_falla(tmp_path, nombre, issues, carriles, dice):
    e = entrada(corrida_plana(tmp_path / "corrida", issues, carriles), "E16")
    assert e["passed"] is False
    assert dice in e["evidence"]


def test_e16_pasa_si_la_copia_del_carril_esta_cerrada(tmp_path):
    issues = {"v2/issues/01.md": "Status: done\n", "v2/issues/02.md": "Status: ready\n"}
    carriles = {"c1": {"v2/issues/02.md": "Status: done\n"}, "c2": {"otro/issues/09.md": "Status: done\n"}}
    e = entrada(corrida_plana(tmp_path / "corrida", issues, carriles), "E16")
    assert e["passed"] is True, e["evidence"]


# --- Métricas no puntuadas ---------------------------------------------------------------------

def test_metricas_de_la_corrida_correcta(grading_correcto, corrida_correcta):
    corrida, shas = corrida_correcta
    m = grading_correcto["metricas_no_puntuadas"]
    assert m["commits_slice_close"] == 4
    lineas_main = len((corrida / "proyecto" / "inv" / "__main__.py").read_text(encoding="utf-8").splitlines())
    assert m["rango_slice_close_mas_grande"] == {"commit": shas[0], "lineas": lineas_main}
    assert m["rondas_preguntas"] == [{"ronda": 1, "ts": ts(2.5), "secciones": ["A", "B"]}]


def test_metricas_sin_bitacora_ni_historia(calificar_variante):
    m = calificar_variante(ids=[])["metricas_no_puntuadas"]
    assert m["rondas_preguntas"] is None
    assert m["commits_slice_close"] == 0
    assert set(m["implementa"].values()) == {None}


# --- CLI ---------------------------------------------------------------------------------------

def test_cli_escribe_grading_json_en_la_corrida(tmp_path):
    corrida = tmp_path / "corrida"
    armar_repo(corrida / "proyecto")
    r = subprocess.run([sys.executable, str(JUGUETE / "calificar.py"), str(corrida)],
                       capture_output=True, text=True, encoding="utf-8")
    assert r.returncode == 0, r.stderr
    g = json.loads((corrida / "grading.json").read_text(encoding="utf-8"))
    # Sin historia, bitácora ni issues: pasan E01-E07, E09 y E11; fallan E08, E14, E15 y E16.
    assert (g["summary"]["passed"], g["summary"]["total"]) == (9, 13)
    assert not (corrida / "proyecto" / "grading.json").exists()


def test_cli_acepta_el_repo_directo(tmp_path):
    repo = armar_repo(tmp_path / "repo")
    r = subprocess.run([sys.executable, str(JUGUETE / "calificar.py"), str(repo)],
                       capture_output=True, text=True, encoding="utf-8")
    assert r.returncode == 0, r.stderr
    assert json.loads((repo / "grading.json").read_text(encoding="utf-8"))["summary"]["total"] == 13


def test_cli_sale_2_si_el_directorio_no_existe(tmp_path):
    r = subprocess.run([sys.executable, str(JUGUETE / "calificar.py"), str(tmp_path / "no-hay")],
                       capture_output=True, text=True, encoding="utf-8")
    assert r.returncode == 2
    assert "no-hay" in r.stderr
