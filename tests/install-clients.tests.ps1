# tests/install-clients.tests.ps1 — runner sin Pester. Correr: pwsh -NoProfile -File tests/install-clients.tests.ps1
# DOMO se instala clonando el repo oficial (no es un paquete pip): git clone + pip install -r requirements.txt + DOMO_MCP_HOME.
$ErrorActionPreference = "Stop"
$repo   = Split-Path $PSScriptRoot -Parent
$script = Join-Path $repo "skills/setup-mcp-workstation/scripts/install-clients.ps1"
$script:failures = 0
function Assert($cond, $msg) {
  if ($cond) { Write-Host "ok:   $msg" } else { Write-Host "FAIL: $msg"; $script:failures++ }
}

# --- todos los prereqs presentes (pwsh siempre existe -> stand-in de git/python/npx) ---
$out = & pwsh -NoProfile -File $script -GitCmd "pwsh" -PythonCmd "pwsh" -NpxCmd "pwsh" -DryRun 2>$null
Assert ($LASTEXITCODE -eq 0) "todos: exit 0"
$sum = $out | Out-String | ConvertFrom-Json
$cmds = ($sum.commands -join " || ")
Assert ($cmds -match "domo-mcp-server") "todos: referencia el repo oficial de domo (clone o pull)"
Assert ($cmds -match "clone|pull")       "todos: corre git clone o pull"
Assert ($cmds -match "requirements\.txt") "todos: instala dependencias por requirements.txt"
Assert ($cmds -match "pip install")       "todos: usa pip install"
Assert ($cmds -match "playwright install chromium") "todos: instala chromium de playwright"
Assert (@($sum.prereqsMissing).Count -eq 0) "todos: sin prereqs faltantes"
Assert ([bool]$sum.domoHome) "todos: reporta domoHome (destino del clone)"

# --- git ausente -> reporta prereq, no aborta, NO intenta clonar, igual sigue con playwright ---
$out2 = & pwsh -NoProfile -File $script -GitCmd "no-existe-git-xyz" -PythonCmd "pwsh" -NpxCmd "pwsh" -DryRun 2>$null
Assert ($LASTEXITCODE -eq 0) "sin git: exit 0 (no aborta)"
$sum2 = $out2 | Out-String | ConvertFrom-Json
Assert (($sum2.prereqsMissing -join " ") -match "[Gg]it") "sin git: reporta Git faltante"
Assert (($sum2.commands -join " ") -notmatch "clone") "sin git: NO intenta clonar"
Assert (($sum2.commands -join " ") -match "playwright") "sin git: igual sigue con playwright"

# --- python ausente -> reporta prereq de python, NO intenta pip ---
$out3 = & pwsh -NoProfile -File $script -GitCmd "pwsh" -PythonCmd "no-existe-python-xyz" -NpxCmd "pwsh" -DryRun 2>$null
Assert ($LASTEXITCODE -eq 0) "sin python: exit 0"
$sum3 = $out3 | Out-String | ConvertFrom-Json
Assert (($sum3.prereqsMissing -join " ") -match "[Pp]ython") "sin python: reporta Python faltante"
Assert (($sum3.commands -join " ") -notmatch "pip install") "sin python: NO intenta pip"

# --- npx ausente -> reporta prereq de node ---
$out4 = & pwsh -NoProfile -File $script -GitCmd "pwsh" -PythonCmd "pwsh" -NpxCmd "no-existe-npx-xyz" -DryRun 2>$null
Assert ($LASTEXITCODE -eq 0) "sin npx: exit 0"
$sum4 = $out4 | Out-String | ConvertFrom-Json
Assert (($sum4.prereqsMissing -join " ") -match "[Nn]ode") "sin npx: reporta Node/npx faltante"

Write-Host ""
if ($script:failures -gt 0) { Write-Host "$($script:failures) test(s) FALLARON"; exit 1 } else { Write-Host "TODOS LOS TESTS PASARON"; exit 0 }
