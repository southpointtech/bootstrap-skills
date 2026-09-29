"""Copia filtrada de un snapshot de claude-analytics: solo los subagentes de este repo.

    python filtrar.py <dir-del-snapshot> <dir-de-salida>

Escribe `<salida>/bs-main/agents.jsonl` (cwd dentro del árbol principal) y
`<salida>/bs-todos/agents.jsonl` (árbol principal + carriles + el worktree de la v2).
Descarta los subagentes con `t0` anterior a INICIO: antes de esa fecha la doctrina del
repo no era todavía la del scaffold `2026-09-11`, que es el brazo "antes".
"""
import json
import os
import sys
from datetime import datetime, timezone

INICIO = datetime(2026, 9, 11, 22, 52, 59, tzinfo=timezone.utc)  # f7ae28f, scaffold 2026-09-11

MAIN = r"c:\repos\personal\bootstrap skills"
TODOS = (MAIN, r"c:\repos\personal\carriles\bootstrap skills", r"c:\repos\personal\bootstrap-skills-bootstrap-v2")
CONJUNTOS = {"bs-main": (MAIN,), "bs-todos": TODOS}


def dentro(cwd, raices):
    c = (cwd or "").lower().rstrip("\\")
    return any(c == r or c.startswith(r + "\\") for r in raices)


def t0(r):
    try:
        return datetime.fromisoformat(r["t0"].replace("Z", "+00:00"))
    except (KeyError, TypeError, ValueError):
        return None


def main(snapshot, salida):
    filas = {k: [] for k in CONJUNTOS}
    total = sin_fecha = 0
    viejas = {k: 0 for k in CONJUNTOS}
    with open(os.path.join(snapshot, "agents.jsonl"), encoding="utf-8") as f:
        for linea in f:
            total += 1
            r = json.loads(linea)
            t = t0(r)
            for k, raices in CONJUNTOS.items():
                if not dentro(r.get("cwd"), raices):
                    continue
                if t is None:
                    sin_fecha += 1
                elif t < INICIO:
                    viejas[k] += 1
                    continue
                filas[k].append(linea)
    for k, ls in filas.items():
        d = os.path.join(salida, k)
        os.makedirs(d, exist_ok=True)
        with open(os.path.join(d, "agents.jsonl"), "w", encoding="utf-8", newline="") as f:
            f.writelines(ls)
        print(f"{k}: {len(ls)} subagentes (descartados por t0 < inicio: {viejas[k]})")
    print(f"snapshot: {total} subagentes; sin fecha dentro del repo: {sin_fecha}")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
