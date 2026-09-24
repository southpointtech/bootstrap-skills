"""Tests de `calificar.py`: por cada expectation E01-E07, un repo de fixture que pasa y uno que falla.

Los repos se arman desde código (`fixture_inv.armar_repo`) en el tmp de pytest. Lo esperado sale de
`evals/evals.json`, nunca del fixture.
"""
import json
import subprocess
import sys

import pytest

import calificar
from fixture_inv import JUGUETE, armar_repo

IDS = [f"E{i:02d}" for i in range(1, 17)]


def entrada(grading, eid):
    return grading["expectations"][IDS.index(eid)]


@pytest.fixture
def calificar_variante(tmp_path):
    """Arma un repo de fixture con la variante pedida, lo califica y devuelve el grading."""
    contador = iter(range(1000))

    def _calificar(**variante):
        repo = armar_repo(tmp_path / f"repo{next(contador)}", **variante)
        return calificar.calificar(repo)

    return _calificar


@pytest.fixture(scope="module")
def grading_correcto(tmp_path_factory):
    return calificar.calificar(armar_repo(tmp_path_factory.mktemp("correcto") / "repo"))


# --- Formato de grading.json -------------------------------------------------------------------

def test_hay_una_entrada_por_expectation_en_orden(grading_correcto):
    textos = json.loads((JUGUETE / "evals" / "evals.json").read_text(encoding="utf-8"))["evals"][0]["expectations"]
    assert [e["text"] for e in grading_correcto["expectations"]] == textos
    assert all(set(e) >= {"text", "passed", "evidence"} for e in grading_correcto["expectations"])


def test_e08_a_e16_no_calificadas_no_suman_al_pass_rate(grading_correcto):
    for eid in IDS[7:]:
        e = entrada(grading_correcto, eid)
        assert e["passed"] is None
        assert "no calificada" in e["evidence"]
    assert grading_correcto["summary"] == {
        "passed": 7, "failed": 0, "total": 7, "pass_rate": 1.0,
        "no_calificadas": IDS[7:],
    }


def test_el_summary_cuenta_las_que_fallan(calificar_variante):
    g = calificar_variante(cantidad="tal_cual")
    s = g["summary"]
    assert (s["passed"], s["failed"], s["total"]) == (4, 3, 7)
    assert s["pass_rate"] == pytest.approx(4 / 7)


# --- El correcto pasa E01-E07 --------------------------------------------------------------------

@pytest.mark.parametrize("eid", IDS[:7])
def test_el_fixture_correcto_pasa(grading_correcto, eid):
    e = entrada(grading_correcto, eid)
    assert e["passed"] is True, e["evidence"]


# --- Cada expectation tiene un fixture que la falla --------------------------------------------

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
    ("E05", {"punto_como_texto": True}),
    ("E05", {"exit_final": {"exportar": 1}}),
    ("E06", {"hasta_exclusivo": True}),
    ("E06", {"cantidad": "tal_cual"}),
    ("E06", {"exit_final": {"rotacion": 1}}),
    ("E07", {"alertas_menor_o_igual": True}),
    ("E07", {"exit_final": {"alertas": 1}}),
]


@pytest.mark.parametrize("eid,variante", FALLAN,
                         ids=[f"{e}-" + ",".join(f"{k}={v}" for k, v in var.items()) for e, var in FALLAN])
def test_el_fixture_equivocado_falla(calificar_variante, eid, variante):
    e = entrada(calificar_variante(**variante), eid)
    assert e["passed"] is False
    assert e["evidence"]


def test_un_comando_roto_no_arrastra_a_los_demas(calificar_variante):
    g = calificar_variante(rotos=["rotacion"])
    assert entrada(g, "E06")["passed"] is False
    assert all(entrada(g, eid)["passed"] for eid in ("E01", "E02", "E03", "E04", "E05", "E07"))


def test_un_alta_invalida_que_borra_productos_falla_e04_sin_cortar_la_calificacion(calificar_variante):
    g = calificar_variante(borra_productos_si_invalido=True)
    e04 = entrada(g, "E04")
    assert e04["passed"] is False
    assert "productos.csv" in e04["evidence"]
    assert all(entrada(g, eid)["passed"] for eid in ("E01", "E02", "E03", "E05", "E06", "E07"))


def test_un_calificador_que_tira_falla_su_expectation_y_sigue(calificar_variante, monkeypatch):
    def tira(copia):
        raise RuntimeError("se rompió")

    monkeypatch.setitem(calificar.CALIFICADORES, "E03", tira)
    g = calificar_variante()
    e03 = entrada(g, "E03")
    assert e03["passed"] is False
    assert "RuntimeError" in e03["evidence"] and "se rompió" in e03["evidence"]
    assert all(entrada(g, eid)["passed"] for eid in ("E01", "E02", "E04", "E05", "E06", "E07"))


# --- Agujero 5: datos frescos siempre ----------------------------------------------------------

def test_agujero5_borrar_la_fila_de_los_datos_no_arregla_el_codigo(calificar_variante):
    """Resta la cantidad tal cual y borró la fila -15 de su copia: sobre sus datos daría 120."""
    g = calificar_variante(sin_fila_menos_15=True, cantidad="tal_cual")
    for eid in ("E02", "E03", "E06"):
        assert entrada(g, eid)["passed"] is False, eid


def test_agujero5_borrar_la_fila_con_el_codigo_correcto_sigue_pasando(calificar_variante):
    g = calificar_variante(sin_fila_menos_15=True)
    for eid in ("E02", "E03", "E06"):
        assert entrada(g, eid)["passed"] is True, eid


# --- Agujero 6: E04 no depende de exportar, ni de productos; JSON como objeto ------------------

def test_agujero6_e04_pasa_sin_exportar_ni_productos(calificar_variante):
    g = calificar_variante(rotos=["exportar", "productos"])
    assert entrada(g, "E04")["passed"] is True, entrada(g, "E04")["evidence"]
    assert entrada(g, "E05")["passed"] is False


def test_agujero6_exportar_con_otro_formato_json_pasa_e05(calificar_variante):
    g = calificar_variante(json_kw={"indent": 2, "sort_keys": True, "ensure_ascii": False})
    assert entrada(g, "E05")["passed"] is True, entrada(g, "E05")["evidence"]


# --- No muta la corrida ------------------------------------------------------------------------

def test_no_muta_el_repo_de_la_corrida(tmp_path):
    # Con los datos de la corrida distintos de los frescos, calificar en el lugar los pisaría.
    repo = armar_repo(tmp_path / "repo", sin_fila_menos_15=True)
    antes = {p.relative_to(repo): p.read_bytes() for p in repo.rglob("*") if p.is_file()}
    calificar.calificar(repo)
    despues = {p.relative_to(repo): p.read_bytes() for p in repo.rglob("*") if p.is_file()}
    assert despues == antes


# --- CLI ---------------------------------------------------------------------------------------

def test_cli_escribe_grading_json_en_la_corrida(tmp_path):
    corrida = tmp_path / "corrida"
    armar_repo(corrida / "proyecto")
    r = subprocess.run([sys.executable, str(JUGUETE / "calificar.py"), str(corrida)],
                       capture_output=True, text=True, encoding="utf-8")
    assert r.returncode == 0, r.stderr
    g = json.loads((corrida / "grading.json").read_text(encoding="utf-8"))
    assert g["summary"]["passed"] == 7
    assert not (corrida / "proyecto" / "grading.json").exists()


def test_cli_acepta_el_repo_directo(tmp_path):
    repo = armar_repo(tmp_path / "repo")
    r = subprocess.run([sys.executable, str(JUGUETE / "calificar.py"), str(repo)],
                       capture_output=True, text=True, encoding="utf-8")
    assert r.returncode == 0, r.stderr
    assert json.loads((repo / "grading.json").read_text(encoding="utf-8"))["summary"]["total"] == 7


def test_cli_sale_2_si_el_directorio_no_existe(tmp_path):
    r = subprocess.run([sys.executable, str(JUGUETE / "calificar.py"), str(tmp_path / "no-hay")],
                       capture_output=True, text=True, encoding="utf-8")
    assert r.returncode == 2
    assert "no-hay" in r.stderr
