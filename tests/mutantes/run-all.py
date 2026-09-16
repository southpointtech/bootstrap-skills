"""Correr: PYTHONIOENCODING=utf-8 python tests/mutantes/run-all.py

Aplica mutantes a tests/run-all.ps1 sobre copias y corre tests/run-all.tests.ps1 contra cada una."""
import shutil, subprocess, sys, tempfile
from pathlib import Path

WT = Path(__file__).resolve().parents[2]
BASE = Path(tempfile.mkdtemp(prefix="mut-run-all-"))
src = (WT / "tests" / "run-all.ps1").read_text(encoding="utf-8")

MUTANTES = {
    "M1-exit0-siempre": ("if ($rojas.Count -gt 0 -or $cambios.Count -gt 0) {", "if ($false) {"),
    "M2-sin-chequeo-de-arbol": ("$cambios = @(\n", "$cambios = @()\n$null = @(\n"),
    "M3-sin-hash": ("$antes[$_] -ne $despues[$_]", "$false"),
    "M4-en-serie": ("ForEach-Object -ThrottleLimit $ThrottleLimit -Parallel {", "ForEach-Object -ThrottleLimit 1 -Parallel {"),
    "M5-sin-guarda-de-vacio": ("if ($suites.Count -eq 0) {", "if ($false) {"),
    "M6-sin-stderr": ("-File $_.FullName 2>&1 |", "-File $_.FullName 2>$null |"),
    "M7-no-imprime-la-salida": ("  Write-Host $r.Salida\n", "\n"),
    "M8-throttle-ignorado-con-1": ("[ValidateRange(1, 64)][int]$ThrottleLimit = 4\n)", "[ValidateRange(1, 64)][int]$ThrottleLimit = 4\n)\n$ThrottleLimit = 4"),
}

vivos = []
for nombre, (viejo, nuevo) in MUTANTES.items():
    if src.count(viejo) != 1:
        print(f"{nombre}: el ancla aparece {src.count(viejo)} veces, no se aplica"); vivos.append(nombre); continue
    d = BASE / nombre / "tests"
    shutil.copytree(WT / "tests" / "lib", d / "lib")
    shutil.copy(WT / "tests" / "run-all.tests.ps1", d)
    (d / "run-all.ps1").write_text(src.replace(viejo, nuevo), encoding="utf-8")
    p = subprocess.run(["pwsh", "-NoProfile", "-File", str(d / "run-all.tests.ps1")],
                       capture_output=True, text=True, encoding="utf-8", errors="replace")
    fails = [l for l in p.stdout.splitlines() if l.startswith("FAIL:")]
    estado = "MUERTO" if p.returncode != 0 else "SOBREVIVE"
    if p.returncode == 0:
        vivos.append(nombre)
    print(f"{nombre}: {estado} (exit {p.returncode}, {len(fails)} FAIL)")
    for l in fails:
        print("   ", l)
shutil.rmtree(BASE)
print(f"{len(MUTANTES) - len(vivos)} de {len(MUTANTES)} mutantes muertos")
sys.exit(1 if vivos else 0)
