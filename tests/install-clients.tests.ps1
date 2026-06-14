# tests/install-clients.tests.ps1 — runner sin Pester. Correr: pwsh -NoProfile -File tests/install-clients.tests.ps1
$ErrorActionPreference = "Stop"
$repo   = Split-Path $PSScriptRoot -Parent
$script = Join-Path $repo "skills/setup-mcp-workstation/scripts/install-clients.ps1"
$script:failures = 0
function Assert($cond, $msg) {
  if ($cond) { Write-Host "ok:   $msg" } else { Write-Host "FAIL: $msg"; $script:failures++ }
}

# --- ambos presentes (pwsh siempre existe -> lo usamos como stand-in de python y npx) ---
$out = & pwsh -NoProfile -File $script -DomoPipSource "domo-pkg-test" -PythonCmd "pwsh" -NpxCmd "pwsh" -DryRun 2>$null
Assert ($LASTEXITCODE -eq 0) "ambos: exit 0"
$sum = $out | Out-String | ConvertFrom-Json
$cmds = ($sum.commands -join " || ")
Assert ($cmds -match "domo-pkg-test") "ambos: el comando pip referencia el paquete domo"
Assert ($cmds -match "pip install")   "ambos: corre pip install"
Assert ($cmds -match "playwright install chromium") "ambos: instala chromium de playwright"
Assert (@($sum.prereqsMissing).Count -eq 0) "ambos: sin prereqs faltantes"

# --- python ausente -> reporta prereq, no aborta ---
$out2 = & pwsh -NoProfile -File $script -PythonCmd "no-existe-python-xyz" -NpxCmd "pwsh" -DryRun 2>$null
Assert ($LASTEXITCODE -eq 0) "sin python: exit 0 (no aborta)"
$sum2 = $out2 | Out-String | ConvertFrom-Json
Assert (($sum2.prereqsMissing -join " ") -match "[Pp]ython") "sin python: reporta Python faltante"
Assert (($sum2.commands -join " ") -notmatch "pip install") "sin python: NO intenta pip"
Assert (($sum2.commands -join " ") -match "playwright") "sin python: igual sigue con playwright"

# --- npx ausente -> reporta prereq de node ---
$out3 = & pwsh -NoProfile -File $script -PythonCmd "pwsh" -NpxCmd "no-existe-npx-xyz" -DryRun 2>$null
Assert ($LASTEXITCODE -eq 0) "sin npx: exit 0"
$sum3 = $out3 | Out-String | ConvertFrom-Json
Assert (($sum3.prereqsMissing -join " ") -match "[Nn]ode") "sin npx: reporta Node/npx faltante"

Write-Host ""
if ($script:failures -gt 0) { Write-Host "$($script:failures) test(s) FALLARON"; exit 1 } else { Write-Host "TODOS LOS TESTS PASARON"; exit 0 }
