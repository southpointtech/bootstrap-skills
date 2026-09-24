"""CLI del aparato: `python -m aparato materializar --brazo <nombre> --raiz <dir>`.

Imprime en stdout (UTF-8) la carpeta de la corrida. Sale con 1, con una línea `error: <Tipo>: ...`
y sin traceback, si el `version` materializado no es el esperado del brazo, si la `--raiz` cae
dentro del repo, si falla git o el `copy-scaffold.ps1` del ref, si falta un ejecutable o si el
manifest materializado no existe o no es JSON.
"""
import argparse
import sys

from . import brazos
from .materializar import VersionIncorrecta, materializar


def main(argv=None):
    p = argparse.ArgumentParser(prog="python -m aparato")
    sub = p.add_subparsers(dest="comando", required=True)
    m = sub.add_parser("materializar", help="materializa un brazo y abre su corrida")
    m.add_argument("--brazo", required=True, choices=sorted(brazos.BRAZOS))
    m.add_argument("--raiz", required=True, help="carpeta bajo la que se crea la corrida")
    args = p.parse_args(argv)

    try:
        corrida = materializar(brazos.BRAZOS[args.brazo], args.raiz)
    # OSError cubre FileExistsError y FileNotFoundError; ValueError, JSONDecodeError y
    # RaizDentroDelRepo.
    except (VersionIncorrecta, RuntimeError, OSError, ValueError) as e:
        print(f"error: {type(e).__name__}: {e}", file=sys.stderr)
        return 1
    sys.stdout.buffer.write((str(corrida) + "\n").encode("utf-8"))
    sys.stdout.flush()
    return 0


if __name__ == "__main__":
    sys.exit(main())
