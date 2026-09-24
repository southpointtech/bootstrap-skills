"""CLI del aparato.

    python -m aparato materializar --brazo <nombre> --raiz <dir>
    python -m aparato correr --brazo <nombre> --raiz <dir> [--claude <exe>] [--tope-rondas N]
                             [--sondeo SEG] [--credencial <ruta>]

Los dos imprimen en stdout (UTF-8) la carpeta de la corrida; `correr` la imprime apenas la
materializa, antes de lanzar al agente. Salen con 1, con una línea `error: <Tipo>: ...` y sin
traceback, si el `version` materializado no es el esperado del brazo, si la `--raiz` cae dentro
del repo, si falla git o el `copy-scaffold.ps1` del ref, si falta un ejecutable, si el manifest
materializado no existe, no es JSON o no es un objeto, si el tar del ref está roto o, en
`correr`, si una sesión de claude sale distinto de 0. `correr` sale con 0 si la corrida cierra
`completa` y con 3 si cierra por `tope_rondas`.
"""
import argparse
import shutil
import sys
import tarfile

from . import brazos, correr
from .materializar import VersionIncorrecta, materializar

SALIDA = {"completa": 0, "tope_rondas": 3}


def _imprimir(corrida):
    sys.stdout.buffer.write((str(corrida) + "\n").encode("utf-8"))
    sys.stdout.flush()


def _comando_claude(valor):
    # Un `.py` (el claude falso de los tests) corre con este mismo Python.
    if valor.endswith(".py"):
        return [sys.executable, valor]
    return [shutil.which(valor) or valor]


def main(argv=None):
    p = argparse.ArgumentParser(prog="python -m aparato")
    sub = p.add_subparsers(dest="comando", required=True)
    m = sub.add_parser("materializar", help="materializa un brazo y abre su corrida")
    c = sub.add_parser("correr", help="materializa un brazo y lanza al agente hasta cerrar")
    for s in (m, c):
        s.add_argument("--brazo", required=True, choices=sorted(brazos.BRAZOS))
        s.add_argument("--raiz", required=True, help="carpeta bajo la que se crea la corrida")
    c.add_argument("--claude", default="claude", help="ejecutable de claude (default: el del PATH)")
    c.add_argument("--tope-rondas", type=int, default=correr.TOPE_RONDAS,
                   help="rondas de preguntas respondidas antes de cerrar por tope")
    c.add_argument("--sondeo", type=float, default=correr.SONDEO,
                   help="segundos entre dos miradas a los worktrees de carril")
    c.add_argument("--credencial", default=str(correr.CREDENCIAL),
                   help="credencial que se copia a la config de la corrida")
    args = p.parse_args(argv)

    brazo = brazos.BRAZOS[args.brazo]
    try:
        corrida = materializar(brazo, args.raiz)
        _imprimir(corrida)
        if args.comando == "correr":
            motivo = correr.lanzar(
                corrida, brazo, claude=_comando_claude(args.claude),
                tope_rondas=args.tope_rondas, sondeo=args.sondeo, credencial=args.credencial,
            )
            return SALIDA[motivo]
    # OSError cubre FileExistsError y FileNotFoundError; ValueError, JSONDecodeError y
    # RaizDentroDelRepo; RuntimeError, SesionFallida.
    except (VersionIncorrecta, RuntimeError, OSError, ValueError, tarfile.TarError) as e:
        print(f"error: {type(e).__name__}: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
