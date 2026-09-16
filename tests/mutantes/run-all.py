"""Correr: PYTHONIOENCODING=utf-8 python tests/mutantes/run-all.py

Aplica mutantes a tests/run-all.ps1 sobre copias y corre tests/run-all.tests.ps1 contra cada una."""
import shutil, subprocess, sys, tempfile
from pathlib import Path

WT = Path(__file__).resolve().parents[2]
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
    # Del foco de mutación del review-loop (turno 1): sobrevivían a la suite de los casos A-H.
    "M9-sin-throw-de-git-status": ("if ($p.ExitCode -ne 0) { throw", "if ($false) { throw"),
    "M10-sin-desaparecio": ('ForEach-Object { "desapareció: $_" }', "Where-Object { $false }"),
    "M11-sin-untracked-all": ("'--untracked-files=all', ", ""),
    "M12-sin-z": (", '-z') {", ") {"),
    "M13-exit-negativo-no-es-rojo": ("$rojas = @($resultados | Where-Object { $_.Exit -ne 0 })", "$rojas = @($resultados | Where-Object { $_.Exit -gt 0 })"),
    "M14-filtro-ancho": ("-Filter '*.tests.ps1'", "-Filter '*.ps1'"),
    "M15-clave-sin-xy": ('$estado["$xy $ruta"]', '$estado["$ruta"]'),
    "M16-git-en-cp850": ("[Text.UTF8Encoding]::new($false)", "[Text.Encoding]::GetEncoding(850)"),
}

vivos = []
base = Path(tempfile.mkdtemp(prefix="mut-run-all-"))
try:
    for nombre, (viejo, nuevo) in MUTANTES.items():
        if src.count(viejo) != 1:
            print(f"{nombre}: el ancla aparece {src.count(viejo)} veces, no se aplica"); vivos.append(nombre); continue
        d = base / nombre / "tests"
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
finally:
    # Un pwsh ausente, un Ctrl-C o un copytree que falla no dejan el temporal en %TEMP%.
    shutil.rmtree(base, ignore_errors=True)
print(f"{len(MUTANTES) - len(vivos)} de {len(MUTANTES)} mutantes muertos")
sys.exit(1 if vivos else 0)
