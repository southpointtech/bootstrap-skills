# install-clients.ps1 — instala/verifica los clientes machine-level de Southpoint: DOMO (pip) y Playwright (browsers).
# Uso: pwsh -NoProfile -File install-clients.ps1 [-DomoPipSource <pkg>] [-PythonCmd python] [-NpxCmd npx] [-DryRun]
[CmdletBinding()]
param(
  [string]$DomoPipSource = "domo-mcp",   # <-- REEMPLAZAR por el paquete/fuente real antes del deploy
  [string]$PythonCmd = "python",
  [string]$NpxCmd = "npx",
  [switch]$DryRun
)
$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $false  # exits no-cero de pip/npx no abortan: los manejamos via $LASTEXITCODE

$installed       = New-Object System.Collections.Generic.List[string]
$skipped         = New-Object System.Collections.Generic.List[string]
$prereqsMissing  = New-Object System.Collections.Generic.List[string]
$commands        = New-Object System.Collections.Generic.List[string]

function Have($cmd) { [bool](Get-Command $cmd -ErrorAction SilentlyContinue) }

# --- DOMO via pip ---
if (Have $PythonCmd) {
  $cmd = "$PythonCmd -m pip install --upgrade $DomoPipSource"
  $commands.Add($cmd)
  if (-not $DryRun) { & $PythonCmd -m pip install --upgrade $DomoPipSource; if ($LASTEXITCODE -ne 0) { $prereqsMissing.Add("pip install de domo fallo: $cmd") } else { $installed.Add("domo ($DomoPipSource)") } }
  else { $installed.Add("domo ($DomoPipSource)") }
} else {
  $skipped.Add("domo")
  $prereqsMissing.Add("Python no encontrado en PATH (comando '$PythonCmd'): instalalo y re-corre la skill.")
}

# --- Playwright browsers (chromium) ---
if (Have $NpxCmd) {
  $cmd = "$NpxCmd --yes playwright install chromium"
  $commands.Add($cmd)
  if (-not $DryRun) { & $NpxCmd --yes playwright install chromium; if ($LASTEXITCODE -ne 0) { $prereqsMissing.Add("playwright install fallo: $cmd") } else { $installed.Add("playwright (chromium)") } }
  else { $installed.Add("playwright (chromium)") }
} else {
  $skipped.Add("playwright")
  $prereqsMissing.Add("Node/npx no encontrado en PATH (comando '$NpxCmd'): instala Node y re-corre la skill.")
}

[pscustomobject]@{
  dryRun         = [bool]$DryRun
  installed      = @($installed)
  skipped        = @($skipped)
  prereqsMissing = @($prereqsMissing)
  commands       = @($commands)
} | ConvertTo-Json -Depth 5
