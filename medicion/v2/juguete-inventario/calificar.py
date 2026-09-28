"""Calificador del A/B del juguete: el criterio que manda sobre la prosa de las expectations.

    python calificar.py <dir-corrida>

`<dir-corrida>` es la carpeta de una corrida del aparato (`medicion/v2/CORRIDA.md`: el repo está en
`proyecto/`, al lado de `bitacora.jsonl` y `copias-de-carriles/`) o el repo mismo, sin bitácora ni
copias de carriles.
Escribe `<dir-corrida>/grading.json` con el formato de skill-creator: una entrada
`{text, passed, evidence}` por expectation de `evals/evals.json`, en su orden, un `summary` y
`metricas_no_puntuadas`.

`passed: null` no suma a `passed`/`failed`/`total`/`pass_rate`, y el id se lista en el `summary`
según por qué: `no_calificadas` (E12 y E13, que leen transcripts: van en el 04b slice 3),
`no_puntuadas` (E10, que se reporta y no puntúa) o `errores_del_calificador` (el calificador tiró:
no es un fallo del agente, y `main` sale 3). El visor de skill-creator muestra `null` como fallada.

Cómo corre cada comando (E01-E07, E09 e "implementa X"):
- sobre una copia (la corrida no se toca), con `python -m inv` desde la raíz de la copia;
- antes de cada comando, el `datos/` de la copia se pisa con una copia fresca del `datos/` del
  juguete: una corrida que "arregla" borrando una fila de sus datos no pasa;
- el stdout en modo texto (`\\r\\n` → `\\n`) se compara contra `esperado` de `evals.json`.

"implementa X" corre la expectation funcional de X sobre cada commit de
`git rev-list --reverse HEAD`, extraído con `git archive`; el resultado se cachea por árbol.
"""
import csv
import importlib.util
import io
import json
import os
import shutil
import subprocess
import sys
import tarfile
import tempfile
from datetime import datetime
from functools import cached_property
from pathlib import Path, PurePosixPath

JUGUETE = Path(__file__).resolve().parent
EVALS = json.loads((JUGUETE / "evals" / "evals.json").read_text(encoding="utf-8"))
ESPERADO = EVALS["esperado"]
EXPECTATIONS = EVALS["evals"][0]["expectations"]
ROTACION = ("rotacion", "--desde", "2026-08-01", "--hasta", "2026-08-31")
FILA_E09 = "2026-08-15,CLA-004,salida,-5\n"
NO_COPIAR = shutil.ignore_patterns(".git", "__pycache__", ".pytest_cache", ".venv", ".claude")
TIMEOUT = 60
TIMEOUT_PYTEST = 600
TECHO_SLICE = 400
SLICES_MINIMOS = 4
# Heredadas (por ejemplo, de un hook de git), mandan a git a otro repo: se sacan de todo subproceso.
GIT_HEREDADAS = ("GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE")


def entorno(**extra):
    return {**{k: v for k, v in os.environ.items() if k not in GIT_HEREDADAS}, **extra}


class Copia:
    """Un árbol del repo de la corrida donde se corren los comandos, siempre sobre datos frescos."""

    def __init__(self, raiz):
        self.raiz = Path(raiz)

    @classmethod
    def del_repo(cls, repo, destino):
        shutil.copytree(repo, destino, ignore=NO_COPIAR)
        return cls(destino)

    @classmethod
    def del_commit(cls, repo, sha, destino):
        tar = subprocess.run(["git", "archive", "--format=tar", sha], cwd=repo, capture_output=True,
                             check=True, env=entorno()).stdout
        with tarfile.open(fileobj=io.BytesIO(tar)) as t:
            t.extractall(destino, filter="data")
        return cls(destino)

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
        return correr([sys.executable, "-m", "inv", *args], self.raiz, TIMEOUT)


def correr(cmd, cwd, timeout):
    env = entorno(PYTHONIOENCODING="utf-8", PYTHONDONTWRITEBYTECODE="1")
    try:
        r = subprocess.run(cmd, cwd=cwd, env=env, capture_output=True, text=True, encoding="utf-8",
                           errors="replace", timeout=timeout)
    except subprocess.TimeoutExpired:
        return None, "", f"timeout de {timeout}s"
    return r.returncode, r.stdout, r.stderr


def mostrar(args, salida):
    codigo, out, err = salida
    return f"`inv {' '.join(args)}` salió {codigo}; stdout={out[:300]!r}; stderr={err[:300]!r}"


def salida_exacta(copia, args, esperado):
    salida = copia.inv(*args)
    return salida[0] == 0 and salida[1] == esperado, mostrar(args, salida)


# --- Las expectations funcionales: reciben una Copia ------------------------------------------

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
        try:
            cambio = (copia.datos / "productos.csv").read_bytes() != antes
        except OSError as e:
            cambio = f"productos.csv ilegible: {e}"
        if cambio:
            malos.append(f"{mostrar(args, salida)} y cambió productos.csv"
                         + (f" ({cambio})" if isinstance(cambio, str) else ""))
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


def e09(copia):
    """Con una salida negativa más de CLA-004, el par [stock, rotación] es una lectura coherente."""
    copia.datos_frescos()
    movs = copia.datos / "movimientos.csv"
    texto = movs.read_bytes()
    movs.write_bytes(texto + (b"" if texto.endswith(b"\n") else b"\n") + FILA_E09.encode())
    stock = copia.inv_sobre_datos_actuales("stock", "CLA-004")
    rotacion = copia.inv_sobre_datos_actuales(*ROTACION)
    evidencia = f"{mostrar(('stock', 'CLA-004'), stock)}; {mostrar(ROTACION, rotacion)}"
    if stock[0] != 0 or rotacion[0] != 0:
        return False, evidencia
    unidades = dict(l.split("\t", 1) for l in rotacion[1].splitlines() if "\t" in l)
    try:
        par = [int(stock[1].strip()), int(unidades["CLA-004"])]
    except (ValueError, KeyError) as e:
        return False, f"{evidencia}; no se lee el par: {e!r}"
    return par in ESPERADO["e09_stock_y_rotacion_de_CLA-004"], f"par {par}; {evidencia}"


FUNCIONALES = {"productos": e01, "stock": e03, "alta": e04, "exportar": e05, "rotacion": e06,
               "alertas": e07}


# --- La historia de git ------------------------------------------------------------------------

def git(repo, *args):
    r = subprocess.run(["git", "-c", "core.quotepath=false", *args], cwd=repo, capture_output=True,
                       check=True, env=entorno())
    return r.stdout.decode("utf-8", errors="replace")


def es_archivo_de_test(ruta):
    """`definiciones["archivo de test"]` de evals.json, sobre una ruta relativa con `/`."""
    p = PurePosixPath(ruta)
    return p.suffix == ".py" and (any(d in ("tests", "test") for d in p.parts[:-1])
                                  or p.name.startswith("test_") or p.name.endswith("_test.py")
                                  or p.name == "conftest.py")


class Historia:
    """Los commits de `git rev-list --reverse HEAD` con sus padres, árbol, fecha y mensaje. Un repo
    sin `.git` o sin commits tiene la historia vacía."""

    def __init__(self, repo):
        self.repo, self.commits = repo, []
        self.padres, self.arbol, self.fecha, self.mensaje = {}, {}, {}, {}
        if not (repo / ".git").exists():
            return
        if subprocess.run(["git", "rev-parse", "-q", "--verify", "HEAD"], cwd=repo,
                          capture_output=True, env=entorno()).returncode != 0:
            return
        for registro in git(repo, "log", "--reverse", "--format=%H%x00%P%x00%T%x00%cI%x00%B%x1e",
                            "HEAD").split("\x1e"):
            registro = registro.lstrip("\n")
            if registro:
                sha, padres, arbol, fecha, cuerpo = registro.split("\x00", 4)
                self.commits.append(sha)
                self.padres[sha], self.arbol[sha] = padres.split(), arbol
                self.fecha[sha], self.mensaje[sha] = datetime.fromisoformat(fecha), cuerpo

    def ancestros(self, sha):
        """Los ancestros de `sha`, él incluido."""
        vistos, pila = set(), [sha]
        while pila:
            x = pila.pop()
            if x not in vistos:
                vistos.add(x)
                pila.extend(self.padres.get(x, []))
        return vistos

    @cached_property
    def slice_closes(self):
        return [c for c in self.commits
                if any(l.startswith("Slice-Close:") for l in self.mensaje[c].splitlines())]

    def rango(self, c):
        """`definiciones["rango de un Slice-Close"]`: `git rev-list C ^A1 ^A2 ...`."""
        anc = self.ancestros(c)
        excluidos = set()
        for a in self.slice_closes:
            if a != c and a in anc:
                excluidos |= self.ancestros(a)
        return anc - excluidos

    @cached_property
    def lineas_de_produccion(self):
        """Por commit que no es merge: líneas agregadas más borradas en código de producción."""
        if not self.commits:
            return {}
        lineas, actual = {}, None
        for l in git(self.repo, "log", "--no-merges", "--no-renames", "--numstat", "--format=%x00%H",
                     "HEAD").splitlines():
            if l.startswith("\x00"):
                actual = l[1:]
                lineas[actual] = 0
            elif l.strip():
                agregadas, borradas, ruta = l.split("\t", 2)
                if ruta.endswith(".py") and not es_archivo_de_test(ruta) and agregadas != "-":
                    lineas[actual] += int(agregadas) + int(borradas)
        return lineas

    def lineas_del_rango(self, c):
        return sum(self.lineas_de_produccion.get(x, 0) for x in self.rango(c))


# (árbol, comando) → si el comando cumple su expectation en ese árbol. El árbol fija el contenido
# del commit, y `datos/` y `esperado` son los del juguete: vale para todo el proceso.
CUMPLE = {}


class Corrida:
    def __init__(self, ruta, tmp):
        ruta = Path(ruta)
        con_proyecto = (ruta / "proyecto").is_dir()
        self.dir, self.tmp = ruta, Path(tmp)
        self.repo = ruta / "proyecto" if con_proyecto else ruta
        self.carriles = ruta / "copias-de-carriles" if con_proyecto else None
        self.bitacora_path = ruta / "bitacora.jsonl" if con_proyecto else None
        self.copia = Copia.del_repo(self.repo, self.tmp / "final")

    @cached_property
    def historia(self):
        return Historia(self.repo)

    @cached_property
    def implementa(self):
        """`definiciones["implementa X"]`: comando → sha del primer commit donde cumple, o None."""
        h, impl = self.historia, dict.fromkeys(FUNCIONALES)
        for i, sha in enumerate(h.commits):
            pendientes = [x for x in FUNCIONALES if impl[x] is None]
            if not pendientes:
                break
            copia = None
            for x in pendientes:
                if (h.arbol[sha], x) not in CUMPLE:
                    copia = copia or Copia.del_commit(self.repo, sha, self.tmp / f"commit{i}")
                    CUMPLE[(h.arbol[sha], x)] = FUNCIONALES[x](copia)[0]
                if CUMPLE[(h.arbol[sha], x)]:
                    impl[x] = sha
        return impl

    @cached_property
    def eventos(self):
        """Los eventos de `bitacora.jsonl`, o None si no hay. Una línea que no es JSON tira: es un
        error del aparato, no del agente."""
        if self.bitacora_path is None or not self.bitacora_path.is_file():
            return None
        texto = self.bitacora_path.read_text(encoding="utf-8")
        return [json.loads(l) for l in texto.splitlines() if l.strip()]

    def rondas(self):
        return [e for e in self.eventos if e.get("evento") == "ronda_preguntas"]


def corto(sha):
    return sha[:10] if sha else None


# --- Las expectations sobre la historia, la bitácora y .scratch: reciben la Corrida ------------

def e08(c):
    if c.eventos is None:
        return False, "no hay bitacora.jsonl en la corrida"
    con_a = [e for e in c.rondas() if "A" in e.get("secciones", [])]
    sha = c.implementa["alertas"]
    if sha is None:
        return False, "ningún commit implementa alertas"
    limite = c.historia.fecha[sha]
    antes = [e for e in con_a if datetime.fromisoformat(e["ts"]) < limite]
    detalle = (f"alertas se implementa en {corto(sha)} ({limite.isoformat()}); rondas con A: "
               f"{[(e.get('ronda'), e['ts']) for e in con_a]}")
    if not antes:
        return False, f"ninguna ronda entregó A antes: {detalle}"
    return True, detalle


def relacion(h, stock, rotacion):
    if stock is None or rotacion is None:
        return "falta_alguno"
    if stock == rotacion:
        return "mismo_commit"
    if stock in h.ancestros(rotacion):
        return "stock_antes"
    if rotacion in h.ancestros(stock):
        return "rotacion_antes"
    return "sin_relacion"


def orden_stock_rotacion(c):
    stock, rotacion = c.implementa["stock"], c.implementa["rotacion"]
    return {"stock": stock, "rotacion": rotacion, "relacion": relacion(c.historia, stock, rotacion)}


def e10(c):
    o = orden_stock_rotacion(c)
    return None, (f"no puntúa: stock en {corto(o['stock'])}, rotacion en {corto(o['rotacion'])}: "
                  f"{o['relacion']}")


def e11(c):
    """Sobre el árbol final tal como lo dejó el agente, con sus propios datos. Sin pytest en el
    intérprete, `python -m pytest` saldría 1 como una suite roja: tira, es error del calificador."""
    if importlib.util.find_spec("pytest") is None:
        raise RuntimeError(f"el intérprete del calificador ({sys.executable}) no tiene pytest")
    copia = Copia.del_repo(c.repo, c.tmp / "e11")
    codigo, out, err = correr([sys.executable, "-m", "pytest", "-q"], copia.raiz, TIMEOUT_PYTEST)
    return codigo == 0, f"`python -m pytest -q` salió {codigo}; stdout={out[-500:]!r}; stderr={err[-300:]!r}"


def e14(c):
    h = c.historia
    implementan = {s for s in c.implementa.values() if s}
    cuentan = [s for s in h.slice_closes if h.rango(s) & implementan]
    return len(cuentan) >= SLICES_MINIMOS, (
        f"{len(cuentan)} de {len(h.slice_closes)} commits con Slice-Close: tienen en su rango un "
        f"commit que implementa un comando: {[corto(s) for s in cuentan]}")


def e15(c):
    h = c.historia
    if not h.slice_closes:
        return False, "no hay commits con Slice-Close:"
    lineas = {corto(s): h.lineas_del_rango(s) for s in h.slice_closes}
    pasados = {s: n for s, n in lineas.items() if n > TECHO_SLICE}
    return not pasados, (f"pasan el techo de {TECHO_SLICE}: {pasados}; " if pasados else "") + \
        f"líneas de producción por rango: {lineas}"


def copias_de_issues(c):
    """Ruta relativa a `.scratch/` → las copias de ese issue (checkout principal y carriles)."""
    bases = [c.repo / ".scratch"]
    if c.carriles is not None:
        bases += sorted(c.carriles.glob("*/.scratch"))
    copias = {}
    for base in bases:
        for f in sorted(base.glob("*/issues/*.md")):
            copias.setdefault(f.relative_to(base).as_posix(), []).append(f)
    return copias


def cerrado(archivo):
    return any(l.rstrip() == "Status: done"
               for l in archivo.read_text(encoding="utf-8", errors="replace").splitlines())


def e16(c):
    copias = copias_de_issues(c)
    if not copias:
        return False, "no hay issues en .scratch/*/issues/*.md"
    abiertos = [i for i, fs in copias.items() if not any(cerrado(f) for f in fs)]
    if abiertos:
        return False, f"sin `Status: done` en ninguna copia: {abiertos}"
    return True, f"{len(copias)} issues, todos con `Status: done` en alguna copia"


def funcional(f):
    return lambda c: f(c.copia)


CALIFICADORES = {"E01": funcional(e01), "E02": funcional(e02), "E03": funcional(e03),
                 "E04": funcional(e04), "E05": funcional(e05), "E06": funcional(e06),
                 "E07": funcional(e07), "E08": e08, "E09": funcional(e09), "E10": e10, "E11": e11,
                 "E14": e14, "E15": e15, "E16": e16}
NO_PUNTUADAS = {"E10"}


def metricas_no_puntuadas(c):
    h = c.historia
    lineas = {s: h.lineas_del_rango(s) for s in h.slice_closes}
    mayor = max(lineas, key=lineas.get, default=None)
    rondas = None if c.eventos is None else [
        {"ronda": e.get("ronda"), "ts": e.get("ts"), "secciones": e.get("secciones")} for e in c.rondas()]
    return {"implementa": c.implementa,
            "orden_stock_rotacion": orden_stock_rotacion(c),
            "commits_slice_close": len(h.slice_closes),
            "rango_slice_close_mas_grande": mayor and {"commit": mayor, "lineas": lineas[mayor]},
            "rondas_preguntas": rondas}


def calificar(ruta, ids=None):
    """Califica la corrida (o el repo) en `ruta` y devuelve el dict de `grading.json`. `ids` limita
    las expectations que se califican; las demás quedan como no calificadas."""
    entradas, no_calificadas, no_puntuadas, errores = [], [], [], []
    with tempfile.TemporaryDirectory(prefix="calificar-") as tmp:
        corrida = Corrida(ruta, tmp)
        for texto in EXPECTATIONS:
            eid = texto[1:4]
            if eid not in CALIFICADORES or (ids is not None and eid not in ids):
                passed = None
                evidencia = ("no calificada: calificar.py todavía no implementa esta expectation "
                             "(04b slice 3)" if eid not in CALIFICADORES else "no calificada: no se pidió")
                no_calificadas.append(eid)
            else:
                try:
                    passed, evidencia = CALIFICADORES[eid](corrida)
                except Exception as e:
                    passed, evidencia = None, f"error del calificador, no del agente: {type(e).__name__}: {e}"
                    errores.append(eid)
                else:
                    if eid in NO_PUNTUADAS:
                        passed = None
                        no_puntuadas.append(eid)
            entradas.append({"text": texto, "passed": passed, "evidence": evidencia})
        try:
            metricas = metricas_no_puntuadas(corrida)
        except Exception as e:
            metricas = {"error": f"{type(e).__name__}: {e}"}
            errores.append("metricas_no_puntuadas")
    pasaron = sum(e["passed"] is True for e in entradas)
    fallaron = sum(e["passed"] is False for e in entradas)
    total = pasaron + fallaron
    return {"expectations": entradas,
            "summary": {"passed": pasaron, "failed": fallaron, "total": total,
                        "pass_rate": pasaron / total if total else 0.0,
                        "no_calificadas": no_calificadas, "no_puntuadas": no_puntuadas,
                        "errores_del_calificador": errores},
            "metricas_no_puntuadas": metricas}


def main(argv):
    if len(argv) != 2:
        print(__doc__, file=sys.stderr)
        return 2
    corrida = Path(argv[1])
    if not corrida.is_dir():
        print(f"no existe el directorio de la corrida: {corrida}", file=sys.stderr)
        return 2
    grading = calificar(corrida)
    destino = corrida / "grading.json"
    destino.write_text(json.dumps(grading, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    s = grading["summary"]
    print(f"{destino}: {s['passed']}/{s['total']} ({len(s['no_calificadas'])} no calificadas, "
          f"{len(s['errores_del_calificador'])} errores del calificador)")
    return 3 if s["errores_del_calificador"] else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
