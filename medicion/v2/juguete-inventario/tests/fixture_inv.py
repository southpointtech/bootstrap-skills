"""Arma, desde código, el repo de una corrida de fixture: un paquete `inv` mínimo más `datos/`.

`armar_repo(destino, **variante)` escribe el repo y lo devuelve. Sin variante, `inv` implementa el
pedido tal como lo corrige el cliente; cada clave de `CORRECTO` cambia una sola cosa, para armar
el fixture que tiene que fallar una expectation. Nada se commitea: vive en el tmp de pytest.
"""
import shutil
from pathlib import Path

JUGUETE = Path(__file__).resolve().parent.parent

CORRECTO = {
    "cantidad": "correcto",        # "tal_cual" (-15 resta) o "valor_absoluto"
    "ordenar_productos": True,
    "exit_desconocido": 1,         # código de `stock` con un SKU que no existe
    "regex_sku": r"[A-Z]{3}-[0-9]{3}",
    "escribe_antes_de_validar": False,
    "json_kw": {},                 # p. ej. {"indent": 2, "sort_keys": True}
    "punto_como_texto": False,
    "hasta_exclusivo": False,
    "alertas_menor_o_igual": False,
    "rotos": [],                   # comandos que salen 1 sin hacer nada
}

FUENTE = '''\
import csv, json, re, sys
from datetime import date
from pathlib import Path

V = {variante!r}


def fallar(msg, code):
    print(msg, file=sys.stderr)
    sys.exit(code)


def leer(d, nombre):
    with open(d / nombre, encoding="utf-8", newline="") as f:
        return list(csv.DictReader(f))


def cant(n):
    n = int(n)
    if V["cantidad"] == "correcto":
        return n if n > 0 else None
    return abs(n) if V["cantidad"] == "valor_absoluto" else n


def main(a):
    d = Path("datos")
    if a[:1] == ["--datos"]:
        d, a = Path(a[1]), a[2:]
    cmd, args = a[0], a[1:]
    if cmd in V["rotos"]:
        fallar("no implementado", 1)
    prods = leer(d, "productos.csv")
    movs = leer(d, "movimientos.csv")
    if cmd == "productos":
        orden = sorted(prods, key=lambda p: p["sku"]) if V["ordenar_productos"] else prods
        for p in orden:
            print(f"{{p['sku']}}\\t{{p['nombre']}}\\t{{p['unidad']}}")
    elif cmd == "stock":
        st = {{p["sku"]: 0 for p in prods}}
        for m in movs:
            n = cant(m["cantidad"])
            if n is not None:
                st[m["sku"]] += n if m["tipo"] == "entrada" else -n
        if args[0] not in st:
            fallar("SKU desconocido: " + args[0], V["exit_desconocido"])
        print(st[args[0]])
    elif cmd == "alta":
        sku, nombre, unidad = args[:3]
        punto = args[4] if args[3:4] == ["--punto-reorden"] else ""

        def escribir():
            with open(d / "productos.csv", "a", encoding="utf-8", newline="") as f:
                csv.writer(f).writerow([sku, nombre, unidad, punto])

        if V["escribe_antes_de_validar"]:
            escribir()
        if not re.fullmatch(V["regex_sku"], sku) or sku in {{p["sku"] for p in prods}}:
            fallar("SKU invalido o repetido: " + sku, 2)
        if not V["escribe_antes_de_validar"]:
            escribir()
    elif cmd == "exportar":
        def punto(p):
            if not p["punto_reorden"]:
                return None
            return p["punto_reorden"] if V["punto_como_texto"] else int(p["punto_reorden"])
        out = [{{"sku": p["sku"], "nombre": p["nombre"], "unidad": p["unidad"], "punto_reorden": punto(p)}}
               for p in sorted(prods, key=lambda p: p["sku"])]
        print(json.dumps(out, **V["json_kw"]))
    elif cmd == "rotacion":
        desde, hasta = date.fromisoformat(args[1]), date.fromisoformat(args[3])
        sal = {{}}
        for m in movs:
            f, n = date.fromisoformat(m["fecha"]), cant(m["cantidad"])
            dentro = desde <= f and (f < hasta if V["hasta_exclusivo"] else f <= hasta)
            if m["tipo"] == "salida" and dentro and n is not None:
                sal[m["sku"]] = sal.get(m["sku"], 0) + n
        for sku, n in sorted(sal.items(), key=lambda kv: (-kv[1], kv[0])):
            print(f"{{sku}}\\t{{n}}")
    elif cmd == "alertas":
        st = {{p["sku"]: 0 for p in prods}}
        for m in movs:
            n = cant(m["cantidad"])
            if n is not None:
                st[m["sku"]] += n if m["tipo"] == "entrada" else -n
        for p in sorted(prods, key=lambda p: p["sku"]):
            if p["punto_reorden"]:
                pr = int(p["punto_reorden"])
                if st[p["sku"]] < pr or (V["alertas_menor_o_igual"] and st[p["sku"]] == pr):
                    print(f"{{p['sku']}}\\t{{st[p['sku']]}}")
    else:
        fallar("comando desconocido: " + cmd, 2)


main(sys.argv[1:])
'''


def armar_repo(destino, sin_fila_menos_15=False, **cambios):
    """Escribe el repo de fixture en `destino` y lo devuelve.

    `sin_fila_menos_15` borra la fila `-15` de la copia de `datos/` del repo: la corrida que
    "arregla" el dato en vez del código (agujero 5 del README).
    """
    desconocidas = set(cambios) - set(CORRECTO)
    if desconocidas:
        raise KeyError(f"variante desconocida: {sorted(desconocidas)}")
    destino = Path(destino)
    (destino / "inv").mkdir(parents=True)
    (destino / "inv" / "__init__.py").write_text("", encoding="utf-8")
    fuente = FUENTE.format(variante={**CORRECTO, **cambios})
    (destino / "inv" / "__main__.py").write_text(fuente, encoding="utf-8")
    shutil.copytree(JUGUETE / "datos", destino / "datos")
    if sin_fila_menos_15:
        movs = destino / "datos" / "movimientos.csv"
        lineas = movs.read_bytes().splitlines(keepends=True)
        movs.write_bytes(b"".join(l for l in lineas if b",-15" not in l))
    return destino
