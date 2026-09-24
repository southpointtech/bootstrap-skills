"""Oráculo del juguete: calcula, desde `datos/`, la salida correcta de cada comando.

De acá salen los literales de `evals/evals.json` (`esperado`); no se escriben a mano. Implementa el
pedido de `enunciado.md` más las respuestas del cliente (`cliente/respuestas.md`): "stock bajo" es
estrictamente menor que el punto de reorden, y una fila con cantidad cero o negativa no se cuenta.

    python oraculo.py               imprime lo esperado de cada comando
    python oraculo.py --verificar   compara con evals/evals.json; sale 1 si difieren
    python oraculo.py --discriminar sale 1 si una interpretación equivocada da lo mismo que la correcta
"""
import csv
import json
import sys
from datetime import date
from pathlib import Path

AQUI = Path(__file__).parent
DESDE, HASTA = date(2026, 8, 1), date(2026, 8, 31)
CLAVE_ROTACION = f"rotacion {DESDE} {HASTA}"
# E09: una salida negativa más de CLA-004 en agosto, que stock y rotacion tienen que tratar igual.
# Pasa cualquiera de las tres lecturas coherentes (descartarla, tal cual, valor absoluto): E09 mide
# coherencia, no si el modelo es compartido (decisión del dueño del repo, 2026-09-24).
FILA_EXTRA_E09 = ("2026-08-15", "CLA-004", "salida", "-5")


def productos(datos):
    with open(datos / "productos.csv", encoding="utf-8", newline="") as f:
        return sorted(csv.DictReader(f), key=lambda p: p["sku"])


def movimientos(datos, extra=()):
    with open(datos / "movimientos.csv", encoding="utf-8", newline="") as f:
        filas = [(m["fecha"], m["sku"], m["tipo"], m["cantidad"]) for m in csv.DictReader(f)]
    return [(date.fromisoformat(d), s, t, int(n)) for d, s, t, n in filas + list(extra)]


def aplicable(n, modo):
    """La cantidad que cuenta según el modo, o None si la fila no se aplica."""
    if modo == "correcto":
        return n if n > 0 else None
    return abs(n) if modo == "valor_absoluto" else n  # "tal_cual"


def stock(prods, movs, modo="correcto"):
    total = {p["sku"]: 0 for p in prods}
    for _, sku, tipo, n in movs:
        n = aplicable(n, modo)
        if n is not None:
            total[sku] += n if tipo == "entrada" else -n
    return total


def rotacion(movs, modo="correcto", desde_incl=True, hasta_incl=True, empate_por_sku=True):
    salidas = {}
    for fecha, sku, tipo, n in movs:
        dentro = (DESDE <= fecha if desde_incl else DESDE < fecha) and (fecha <= HASTA if hasta_incl else fecha < HASTA)
        n = aplicable(n, modo)
        if tipo == "salida" and dentro and n is not None:
            salidas[sku] = salidas.get(sku, 0) + n
    orden = sorted(salidas.items(), key=lambda kv: kv[0], reverse=not empate_por_sku)
    orden.sort(key=lambda kv: -kv[1])
    return "".join(f"{s}\t{n}\n" for s, n in orden)


def alertas(prods, st, bajo):
    return "".join(f"{p['sku']}\t{st[p['sku']]}\n" for p in prods if bajo(p, st[p["sku"]]))


def punto(p):
    return int(p["punto_reorden"]) if p["punto_reorden"] else None


def menor_que_punto(p, s):
    return punto(p) is not None and s < punto(p)


def esperado(datos):
    prods, movs = productos(datos), movimientos(datos)
    st = stock(prods, movs)
    movs_e09 = movimientos(datos, [FILA_EXTRA_E09])
    rot_e09 = dict(l.split("\t") for l in rotacion(movs_e09).splitlines())
    rot_e09_tal_cual = dict(l.split("\t") for l in rotacion(movs_e09, "tal_cual").splitlines())
    rot_e09_abs = dict(l.split("\t") for l in rotacion(movs_e09, "valor_absoluto").splitlines())
    return {
        "productos": "".join(f"{p['sku']}\t{p['nombre']}\t{p['unidad']}\n" for p in prods),
        "stock": {s: st[s] for s in sorted(st)},
        "exportar": [{"sku": p["sku"], "nombre": p["nombre"], "unidad": p["unidad"],
                      "punto_reorden": punto(p)} for p in prods],
        CLAVE_ROTACION: rotacion(movs),
        "alertas": alertas(prods, st, menor_que_punto),
        "e09_stock_y_rotacion_de_CLA-004": [
            [stock(prods, movs_e09)["CLA-004"], int(rot_e09["CLA-004"])],
            [stock(prods, movs_e09, "tal_cual")["CLA-004"], int(rot_e09_tal_cual["CLA-004"])],
            [stock(prods, movs_e09, "valor_absoluto")["CLA-004"], int(rot_e09_abs["CLA-004"])],
        ],
    }


def interpretaciones_equivocadas(datos):
    """(campo de `esperado`, nombre, valor) de cada lectura equivocada que una fricción tiene que separar."""
    prods, movs = productos(datos), movimientos(datos)
    st = stock(prods, movs)
    for modo in ("tal_cual", "valor_absoluto"):
        yield "stock", f"stock {modo}", {**st, "TOR-001": stock(prods, movs, modo)["TOR-001"]}
        yield CLAVE_ROTACION, f"rotacion {modo}", rotacion(movs, modo)
    yield CLAVE_ROTACION, "rotacion con desde exclusivo", rotacion(movs, desde_incl=False)
    yield CLAVE_ROTACION, "rotacion con hasta exclusivo", rotacion(movs, hasta_incl=False)
    yield CLAVE_ROTACION, "rotacion con empate al revés", rotacion(movs, empate_por_sku=False)
    yield "alertas", "alertas con <=", alertas(prods, st, lambda p, s: punto(p) is not None and s <= punto(p))
    yield "alertas", "alertas con umbral fijo 10", alertas(prods, st, lambda p, s: s < 10)


def main(argv):
    datos = AQUI / "datos"
    calculado = esperado(datos)
    if argv[1:] == []:
        print(json.dumps(calculado, ensure_ascii=False, indent=2))
        return 0
    if argv[1:] == ["--verificar"]:
        congelado = json.loads((AQUI / "evals" / "evals.json").read_text(encoding="utf-8"))["esperado"]
        if congelado != calculado:
            print("DIFIERE: evals.json no coincide con el oráculo", file=sys.stderr)
            print(json.dumps(calculado, ensure_ascii=False, indent=2), file=sys.stderr)
            return 1
        print("ok: evals.json coincide con el oráculo")
        return 0
    if argv[1:] == ["--discriminar"]:
        iguales = [n for campo, n, v in interpretaciones_equivocadas(datos) if v == calculado[campo]]
        for n in iguales:
            print(f"NO DISCRIMINA: {n} da lo mismo que la interpretación correcta", file=sys.stderr)
        if not iguales:
            print("ok: cada interpretación equivocada da otra salida")
        return 1 if iguales else 0
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
