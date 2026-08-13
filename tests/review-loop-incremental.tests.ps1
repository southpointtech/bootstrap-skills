# tests/review-loop-incremental.tests.ps1 — runner sin Pester.
# Correr: pwsh -NoProfile -File tests/review-loop-incremental.tests.ps1
#
# El loop revisa el DELTA SIN REVISAR, no el rango completo de la rama en cada turno. Eso lo
# sostiene el marcador de revisión (.claude/scripts/review-marker.ps1) y solo sirve si las
# instrucciones del loop realmente lo usan: fijarlo antes del primer turno, pedirle el rango en
# cada corrida de review y avanzarlo al cerrar el turno. Además, los fixes que el propio loop
# escribe tienen que arrancar por un test que falle sin el fix (RED): 59 de 235 reportes de turno
# atribuían sus hallazgos a los fixes del turno anterior.
# Contrato verificado sobre las CUATRO copias: las 3 skills bootstrap y la copia de este repo.
$ErrorActionPreference = "Stop"
$repo = Split-Path $PSScriptRoot -Parent
$script:failures = 0
function Assert($cond, $msg) {
  if ($cond) { Write-Host "ok:   $msg" } else { Write-Host "FAIL: $msg"; $script:failures++ }
}

# Las 4 raíces que tienen que llevar el marcador y el loop idénticos.
$roots = @()
foreach ($s in (Get-ChildItem (Join-Path $repo "skills") -Directory | Where-Object Name -like "bootstrap-*-project")) {
  $roots += [pscustomobject]@{ Name = $s.Name; Path = (Join-Path $s.FullName "assets\scaffold") }
}
$roots += [pscustomobject]@{ Name = "repo"; Path = $repo }

Assert ($roots.Count -eq 4) "hay 4 copias del scaffold a verificar ($($roots.Count))"

foreach ($r in $roots) {
  # 1. El script del marcador existe en la copia.
  $script = Join-Path $r.Path ".claude\scripts\review-marker.ps1"
  Assert (Test-Path -LiteralPath $script) "$($r.Name): existe .claude/scripts/review-marker.ps1"

  # 2. Las instrucciones del loop usan los tres verbos y exigen RED.
  $files = @(
    (Join-Path $r.Path ".claude\commands\review-loop.md"),
    (Join-Path $r.Path ".agents\skills\review-loop\SKILL.md")
  )
  foreach ($f in $files) {
    $rel = $f.Substring($r.Path.Length).TrimStart('\') -replace '\\', '/'
    if (-not (Test-Path -LiteralPath $f)) { Assert $false "$($r.Name): existe $rel"; continue }
    $txt = [IO.File]::ReadAllText($f)

    Assert ($txt -match 'review-marker\.ps1')            "$($r.Name): $rel usa el marcador de revisión"
    Assert ($txt -match '-Action\s+advance')             "$($r.Name): $rel avanza el marcador"
    Assert ($txt -match '-Action\s+range')               "$($r.Name): $rel pide el rango al marcador"
    # El delta vacío cierra el loop en vez de inventarse un rango.
    Assert ($txt -match '(?i)empty')                     "$($r.Name): $rel define qué hacer con el rango vacío"
    # RED obligatorio: el fix arranca por un test que falla sin el fix.
    Assert ($txt -match '(?i)\bfails? without the fix\b') "$($r.Name): $rel exige RED en los fixes del loop"
  }
}

if ($script:failures -eq 0) { Write-Host "TODOS LOS TESTS PASARON"; exit 0 }
else { Write-Host "$($script:failures) test(s) FALLARON"; exit 1 }
