"""Oráculo del juguete: calcula, desde `datos/` y el pedido, la salida correcta de cada comando.

De acá salen los literales de `evals/evals.json` (`esperado`); no se escriben a mano. Implementa el
pedido de `enunciado.md` más la respuesta del cliente (`cliente/respuestas.md`) sobre "stock bajo".

    python oraculo.py              imprime lo esperado de cada comando
    python oraculo.py --verificar  compara con evals/evals.json; sale 1 si difieren
"""
import csv
import json
import re
import sys
from datetime import date
from pathlib import Path

AQUI = Path(__file__).parent


def productos(datos):
    with open(datos / "productos.csv", encoding="utf-8", newline="") as f:
        filas = list(csv.DictReader(f))
    return sorted(filas, key=lambda p: p["sku"])


def movimientos(datos, skus):
    """Filas válidas y avisos `movimientos.csv:<línea>: <motivo>` de las inválidas."""
    validos, avisos = [], []
    with open(datos / "movimientos.csv", encoding="utf-8", newline="") as f:
        for linea, m in enumerate(csv.DictReader(f), start=2):
            motivo = None
            try:
                fecha = date.fromisoformat(m["fecha"])
            except ValueError:
                motivo = "fecha inválida"
            if m["tipo"] not in ("entrada", "salida"):
                motivo = "tipo desconocido"
            elif not re.fullmatch(r"[0-9]+", m["cantidad"]) or int(m["cantidad"]) <= 0:
                motivo = "cantidad no positiva"
            elif m["sku"] not in skus:
                motivo = "sku desconocido"
            if motivo:
                avisos.append(f"movimientos.csv:{linea}: {motivo}")
                continue
            validos.append((fecha, m["sku"], m["tipo"], int(m["cantidad"])))
    return validos, avisos


def esperado(datos):
    prods = productos(datos)
    skus = {p["sku"] for p in prods}
    movs, avisos = movimientos(datos, skus)
    stock = {s: 0 for s in skus}
    for _, sku, tipo, n in movs:
        stock[sku] += n if tipo == "entrada" else -n
    desde, hasta = date(2026, 8, 1), date(2026, 8, 31)
    salidas = {}
    for fecha, sku, tipo, n in movs:
        if tipo == "salida" and desde <= fecha <= hasta:
            salidas[sku] = salidas.get(sku, 0) + n
    rotacion = sorted(salidas.items(), key=lambda kv: (-kv[1], kv[0]))
    bajos = [p["sku"] for p in prods if p["punto_reorden"] and stock[p["sku"]] < int(p["punto_reorden"])]
    return {
        "avisos_de_carga": avisos,
        "productos": "".join(f"{p['sku']}\t{p['nombre']}\t{p['unidad']}\n" for p in prods),
        "stock": {s: stock[s] for s in sorted(skus)},
        "exportar": [
            {"sku": p["sku"], "nombre": p["nombre"], "unidad": p["unidad"],
             "punto_reorden": int(p["punto_reorden"]) if p["punto_reorden"] else None}
            for p in prods
        ],
        "rotacion 2026-08-01 2026-08-31": "".join(f"{s}\t{n}\n" for s, n in rotacion),
        "alertas": "".join(f"{s}\t{stock[s]}\n" for s in bajos),
    }


def main(argv):
    calculado = esperado(AQUI / "datos")
    if argv[1:] == ["--verificar"]:
        congelado = json.loads((AQUI / "evals" / "evals.json").read_text(encoding="utf-8"))["esperado"]
        if congelado != calculado:
            print("DIFIERE: evals.json no coincide con el oráculo", file=sys.stderr)
            print(json.dumps(calculado, ensure_ascii=False, indent=2), file=sys.stderr)
            return 1
        print("ok: evals.json coincide con el oráculo")
        return 0
    print(json.dumps(calculado, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
