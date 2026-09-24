"""Calificador del A/B del juguete: el criterio que manda sobre la prosa de las expectations.

    python calificar.py <dir-corrida>

`<dir-corrida>` es la carpeta de una corrida del aparato (el repo está en `proyecto/`) o el repo
mismo. Escribe `<dir-corrida>/grading.json` con el formato de skill-creator: una entrada
`{text, passed, evidence}` por expectation de `evals/evals.json`, en su orden, y un `summary`.

Este slice (04b, slice 1) califica E01-E07. E08-E16 van con `passed: null` y quedan fuera de
`passed`/`failed`/`total`/`pass_rate`; sus ids se listan en `summary.no_calificadas`.

Cómo corre cada comando:
- sobre una copia del repo (la corrida no se toca), con `python -m inv` desde la raíz de la copia;
- antes de cada comando, el `datos/` de la copia se pisa con una copia fresca del `datos/` del
  juguete: una corrida que "arregla" borrando una fila de sus datos no pasa;
- stdout y stderr en modo texto (`\\r\\n` → `\\n`), comparados contra `esperado` de `evals.json`.
"""
import csv
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

JUGUETE = Path(__file__).resolve().parent
EVALS = json.loads((JUGUETE / "evals" / "evals.json").read_text(encoding="utf-8"))
ESPERADO = EVALS["esperado"]
EXPECTATIONS = EVALS["evals"][0]["expectations"]
ROTACION = ("rotacion", "--desde", "2026-08-01", "--hasta", "2026-08-31")
NO_COPIAR = shutil.ignore_patterns(".git", "__pycache__", ".pytest_cache", ".venv", ".claude")
TIMEOUT = 60


class Copia:
    """Una copia del repo de la corrida donde se corren los comandos, siempre sobre datos frescos."""

    def __init__(self, repo, tmp):
        self.raiz = Path(tmp) / "repo"
        shutil.copytree(repo, self.raiz, ignore=NO_COPIAR)

    @property
    def datos(self):
        return self.raiz / "datos"

    def datos_frescos(self):
        if self.datos.is_dir():
            shutil.rmtree(self.datos)
        elif self.datos.exists():
            self.datos.unlink()
        shutil.copytree(JUGUETE / "datos", self.datos)

    def inv(self, *args):
        """Pisa `datos/` con los del juguete y corre `python -m inv <args>`: (código, stdout, stderr)."""
        self.datos_frescos()
        return self.inv_sobre_datos_actuales(*args)

    def inv_sobre_datos_actuales(self, *args):
        env = {**os.environ, "PYTHONIOENCODING": "utf-8", "PYTHONDONTWRITEBYTECODE": "1"}
        try:
            r = subprocess.run([sys.executable, "-m", "inv", *args], cwd=self.raiz, env=env,
                               capture_output=True, text=True, encoding="utf-8", errors="replace",
                               timeout=TIMEOUT)
        except subprocess.TimeoutExpired:
            return None, "", f"timeout de {TIMEOUT}s"
        return r.returncode, r.stdout, r.stderr


def mostrar(args, salida):
    codigo, out, err = salida
    return f"`inv {' '.join(args)}` salió {codigo}; stdout={out[:300]!r}; stderr={err[:300]!r}"


def salida_exacta(copia, args, esperado):
    salida = copia.inv(*args)
    return salida[0] == 0 and salida[1] == esperado, mostrar(args, salida)


def e01(copia):
    return salida_exacta(copia, ("productos",), ESPERADO["productos"])


def e02(copia):
    return salida_exacta(copia, ("stock", "TOR-001"), "120\n")


def e03(copia):
    malos = []
    for sku, n in ESPERADO["stock"].items():
        ok, evidencia = salida_exacta(copia, ("stock", sku), f"{n}\n")
        if not ok:
            malos.append(evidencia)
    desconocido = copia.inv("stock", "NOP-999")
    if desconocido[0] != 1:
        malos.append(mostrar(("stock", "NOP-999"), desconocido) + " (se esperaba 1)")
    return not malos, "; ".join(malos) or "los seis SKUs dan su stock y NOP-999 sale 1"


def filas_productos(copia):
    with open(copia.datos / "productos.csv", encoding="utf-8", newline="") as f:
        return [dict(fila) for fila in csv.DictReader(f)]


def e04(copia):
    """El efecto de `alta` se mira en `productos.csv` de la copia, no con `productos` ni `exportar`:
    así E04 no depende de otro slice de la misma ola."""
    malos = []
    alta = ("alta", "XYZ-007", "Tapa", "unidad", "--punto-reorden", "5")
    copia.datos_frescos()
    originales = filas_productos(copia)
    salida = copia.inv_sobre_datos_actuales(*alta)
    nueva = {"sku": "XYZ-007", "nombre": "Tapa", "unidad": "unidad", "punto_reorden": "5"}
    if salida[0] != 0:
        malos.append(mostrar(alta, salida) + " (se esperaba 0)")
    else:
        try:
            despues = filas_productos(copia)
        except (OSError, csv.Error, UnicodeDecodeError) as e:
            despues = f"ilegible: {e}"
        if despues != originales + [nueva]:
            malos.append(f"tras {mostrar(alta, salida)}, productos.csv no es el original más "
                         f"{nueva} al final: {despues}")
    for args in (("alta", "xyz-7", "Tapa", "unidad"), ("alta", "ABC-1234", "Tapa", "unidad"),
                 ("alta", "TOR-001", "Otro", "unidad")):
        copia.datos_frescos()
        antes = (copia.datos / "productos.csv").read_bytes()
        salida = copia.inv_sobre_datos_actuales(*args)
        if salida[0] != 2:
            malos.append(mostrar(args, salida) + " (se esperaba 2)")
        if (copia.datos / "productos.csv").read_bytes() != antes:
            malos.append(f"{mostrar(args, salida)} y cambió productos.csv")
    return not malos, "; ".join(malos) or "el alta válida agrega la fila y las tres inválidas salen 2 sin tocar el archivo"


def e05(copia):
    salida = copia.inv("exportar")
    try:
        objeto = json.loads(salida[1])
    except ValueError as e:
        return False, f"{mostrar(('exportar',), salida)}; no es JSON: {e}"
    return salida[0] == 0 and objeto == ESPERADO["exportar"], mostrar(("exportar",), salida)


def e06(copia):
    return salida_exacta(copia, ROTACION, ESPERADO["rotacion 2026-08-01 2026-08-31"])


def e07(copia):
    return salida_exacta(copia, ("alertas",), ESPERADO["alertas"])


CALIFICADORES = {"E01": e01, "E02": e02, "E03": e03, "E04": e04, "E05": e05, "E06": e06, "E07": e07}


def calificar(repo):
    """Califica el repo de una corrida y devuelve el dict de `grading.json`."""
    entradas, no_calificadas = [], []
    with tempfile.TemporaryDirectory(prefix="calificar-") as tmp:
        copia = Copia(repo, tmp)
        for texto in EXPECTATIONS:
            eid = texto[1:4]
            if eid in CALIFICADORES:
                passed, evidencia = CALIFICADORES[eid](copia)
            else:
                passed, evidencia = None, "no calificada: calificar.py todavía no implementa esta expectation (04b slice 1)"
                no_calificadas.append(eid)
            entradas.append({"text": texto, "passed": passed, "evidence": evidencia})
    pasaron = sum(e["passed"] is True for e in entradas)
    fallaron = sum(e["passed"] is False for e in entradas)
    total = pasaron + fallaron
    return {"expectations": entradas,
            "summary": {"passed": pasaron, "failed": fallaron, "total": total,
                        "pass_rate": pasaron / total if total else 0.0,
                        "no_calificadas": no_calificadas}}


def main(argv):
    if len(argv) != 2:
        print(__doc__, file=sys.stderr)
        return 2
    corrida = Path(argv[1])
    if not corrida.is_dir():
        print(f"no existe el directorio de la corrida: {corrida}", file=sys.stderr)
        return 2
    repo = corrida / "proyecto" if (corrida / "proyecto").is_dir() else corrida
    grading = calificar(repo)
    destino = corrida / "grading.json"
    destino.write_text(json.dumps(grading, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    s = grading["summary"]
    print(f"{destino}: {s['passed']}/{s['total']} ({len(s['no_calificadas'])} no calificadas)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
