"""Costo por slice cerrado, por brazo: métricas que no dependen del formato del reporte.

    python contar_slices.py <repo> <agents.jsonl filtrado> <borde ISO> <fin ISO>

Del git de <repo> (todas las ramas, commits deduplicados por subject porque los carriles
se integran por cherry-pick y el mismo commit aparece con dos hashes) cuenta, por fecha
de committer entre INICIO y <fin>: los commits con trailer `Slice-Close`, su
`Review-Rigor` y los commits cuyo subject nombra un "turno" del review-loop. Del
agents.jsonl, subagentes y `outTok` por brazo según su `t0`.
"""
import collections
import json
import subprocess
import sys
from datetime import datetime, timezone

INICIO = "2026-09-11T22:52:59Z"  # f7ae28f, scaffold 2026-09-11 (igual que filtrar.py)
FMT = "%H%x1f%cI%x1f%s%x1f%(trailers:key=Slice-Close,valueonly,separator=;)%x1f%(trailers:key=Review-Rigor,valueonly,separator=;)%x1e"


def fecha(s):
    return datetime.fromisoformat(s.replace("Z", "+00:00"))


def main(repo, agents, borde_iso, fin_iso):
    borde = fecha(borde_iso)
    salida = subprocess.run(
        ["git", "-C", repo, "log", "--all", f"--since={INICIO}", f"--until={fin_iso}", f"--format={FMT}"],
        capture_output=True, check=True, encoding="utf-8",
    ).stdout
    c = collections.Counter()
    vistos = set()
    for rec in salida.split("\x1e"):
        rec = rec.strip("\n")
        if not rec:
            continue
        _, d, subject, slice_close, rigor = rec.split("\x1f")
        if subject in vistos:
            continue
        vistos.add(subject)
        brazo = "antes" if fecha(d) < borde else "desde"
        c[(brazo, "commits")] += 1
        if slice_close.strip():
            c[(brazo, "slice-close")] += 1
            c[(brazo, "rigor-" + (rigor.strip() or "standard"))] += 1
        if "turno" in subject.lower():
            c[(brazo, "commits-turno")] += 1
    n = collections.Counter()
    tok = collections.Counter()
    with open(agents, encoding="utf-8") as f:
        for linea in f:
            r = json.loads(linea)
            brazo = "antes" if fecha(r["t0"]) < borde else "desde"
            n[brazo] += 1
            tok[brazo] += r["outTok"]
    for brazo in ("antes", "desde"):
        sc = c[(brazo, "slice-close")]
        print(
            f"{brazo}: slices cerrados {sc} (standard {c[(brazo, 'rigor-standard')]}, light {c[(brazo, 'rigor-light')]}); "
            f"commits {c[(brazo, 'commits')]}; commits de turno {c[(brazo, 'commits-turno')]}; "
            f"subagentes {n[brazo]}; outTok {tok[brazo]}"
        )
        if sc:
            print(
                f"  por slice cerrado: {c[(brazo, 'commits-turno')] / sc:.1f} commits de turno, "
                f"{n[brazo] / sc:.1f} subagentes, {tok[brazo] / sc:,.0f} outTok de subagentes"
            )


if __name__ == "__main__":
    if len(sys.argv) != 5:
        sys.exit(__doc__)
    main(*sys.argv[1:])
