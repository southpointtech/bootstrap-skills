#!/usr/bin/env python3
"""Regraba (o verifica) el par congelado del issue 19: la victima y sus dos bloques de drift.

Los tres `.txt` de al lado son FIXTURE CONGELADO del self-test de
`tools/recover-skill-bases.py`. El colapso de `autojunk` vive en el PAR concreto —el mismo
cuerpo con otro drift no se cae, y el mismo drift contra otro cuerpo tampoco—, asi que un test
que leyera los `SKILL.md` vivos dejaria de ser rojo el dia que alguien edite una skill, sin que
nadie lo note. Por eso se congelan, y por eso este script no corre en la suite: existe para
dejar escrito COMO se cortaron, en vez de que los numeros salgan de un `python -c` perdido.

Por default no escribe nada: recorta de nuevo desde el arbol de skills y reporta si lo que sale
sigue siendo byte a byte lo congelado. Con `--write` pisa los `.txt`.

    py tests/fixtures/autojunk-par.gen.py            # reporta
    py tests/fixtures/autojunk-par.gen.py --write    # regraba

El recorte: se toman LINEAS ENTERAS del principio del cuerpo de la skill fuente hasta llegar al
10 % del largo del cuerpo de la victima, y se cierra con `\n` — o sea "alguien le agrego una
seccion corta arriba", que es la forma normal de editar un SKILL.md.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import os
import sys

AQUI = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(AQUI))
SKILLS_DIR = os.path.join(REPO, "skills", "bootstrap-ai-project", "assets", "scaffold",
                          ".agents", "skills")
VICTIMA = "setup-matt-pocock-skills"
PORCENTAJE = 0.10
# (archivo congelado, skill de la que sale, modo). `cuerpo` congela el cuerpo entero;
# `recorte` congela el bloque que se prepende. `autojunk-una-linea.txt` es el cuerpo de
# `zoom-out`, que tiene UNA sola linea: el caso donde la metrica por lineas es binaria.
FUENTES = [("autojunk-victima.txt", VICTIMA, "cuerpo"),
           ("autojunk-una-linea.txt", "zoom-out", "cuerpo"),
           ("autojunk-drift-colapsa.txt", "grill-with-docs", "recorte"),
           ("autojunk-drift-control.txt", "triage", "recorte")]


def _body_of():
    """`body_of` de la herramienta, no una reimplementacion: el corte tiene que ser el mismo."""
    ruta = os.path.join(REPO, "tools", "recover-skill-bases.py")
    spec = importlib.util.spec_from_file_location("_rsb_para_fixture", ruta)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod.body_of


def cuerpo(body_of, skills_dir, nombre):
    with open(os.path.join(skills_dir, nombre, "SKILL.md"), "rb") as f:
        return body_of(f.read().decode("utf-8"))


def recorte(fuente, objetivo):
    """Lineas enteras del principio de `fuente` hasta pasar `objetivo` caracteres, cerrado en \\n."""
    acc = ""
    for linea in fuente.splitlines(keepends=True):
        if len(acc) >= objetivo:
            break
        acc += linea
    return acc if acc.endswith("\n") else acc + "\n"


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--skills-dir", default=SKILLS_DIR)
    ap.add_argument("--write", action="store_true", help="pisa los .txt congelados")
    args = ap.parse_args(argv)

    body_of = _body_of()
    victima = cuerpo(body_of, args.skills_dir, VICTIMA)
    objetivo = len(victima) * PORCENTAJE

    distintos = 0
    for archivo, skill, modo in FUENTES:
        fuente = victima if skill == VICTIMA else cuerpo(body_of, args.skills_dir, skill)
        texto = fuente if modo == "cuerpo" else recorte(fuente, objetivo)
        destino = os.path.join(AQUI, archivo)
        # Los .txt se comparan NORMALIZADOS a LF, igual que los lee el self-test: con
        # `core.autocrlf=true` el checkout los deja en CRLF y una comparacion cruda diria
        # "cambio" por un fin de linea.
        try:
            with open(destino, "rb") as f:
                congelado = f.read().decode("utf-8").replace("\r\n", "\n")
        except OSError:
            congelado = None
        igual = congelado == texto
        distintos += 0 if igual else 1
        print("%-28s chars=%5d lineas=%4d sha1=%s  %s"
              % (archivo, len(texto), len(texto.splitlines()),
                 hashlib.sha1(texto.encode("utf-8")).hexdigest()[:12],
                 "igual al congelado" if igual else
                 ("NO EXISTE" if congelado is None else "DISTINTO del congelado")))
        if args.write:
            tmp = destino + ".nuevo"
            with open(tmp, "w", encoding="utf-8", newline="") as f:
                f.write(texto)
            os.replace(tmp, destino)

    if args.write:
        print("\nEscritos los %d archivos." % len(FUENTES))
    elif distintos:
        print("\n%d de %d difieren: el arbol de skills se edito desde que se congelo el par."
              % (distintos, len(FUENTES)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
