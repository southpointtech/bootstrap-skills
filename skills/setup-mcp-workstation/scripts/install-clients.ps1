# install-clients.ps1 — instala/verifica los clientes machine-level de Southpoint.
# DOMO: el repo oficial (DomoApps/domo-mcp-server) NO es un paquete pip — es clonar-y-ejecutar.
#       Se clona a $DomoHome, se instalan sus dependencias (pip install -r requirements.txt) y se
#       setea DOMO_MCP_HOME=$DomoHome (env var de usuario) para que el catalogo MCP resuelva PYTHONPATH.
# Playwright: solo los browsers (chromium) a nivel maquina.
# Uso: pwsh -NoProfile -File install-clients.ps1 [-DomoRepoUrl <url>] [-DomoHome <dir>] [-GitCmd git] [-PythonCmd python] [-NpxCmd npx] [-DryRun]
[CmdletBinding()]
param(
  [string]$DomoRepoUrl = "https://github.com/DomoApps/domo-mcp-server.git",
  [string]$DomoHome    = (Join-Path $env:USERPROFILE ".claude\domo-mcp-server"),
  [string]$GitCmd = "git",
  [string]$PythonCmd = "python",
  [string]$NpxCmd = "npx",
  [switch]$DryRun
)
$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $false  # exits no-cero de git/pip/npx no abortan: los manejamos via $LASTEXITCODE

$installed       = New-Object System.Collections.Generic.List[string]
$skipped         = New-Object System.Collections.Generic.List[string]
$prereqsMissing  = New-Object System.Collections.Generic.List[string]
$commands        = New-Object System.Collections.Generic.List[string]

function Have($cmd) { [bool](Get-Command $cmd -ErrorAction SilentlyContinue) }

# --- DOMO: clonar el repo oficial (no es un paquete pip) + instalar sus dependencias ---
$haveGit = Have $GitCmd
$havePy  = Have $PythonCmd
if ($haveGit -and $havePy) {
  $req = Join-Path $DomoHome "requirements.txt"
  if (Test-Path $DomoHome) { $cloneCmd = "$GitCmd -C `"$DomoHome`" pull --ff-only" }
  else                     { $cloneCmd = "$GitCmd clone $DomoRepoUrl `"$DomoHome`"" }
  $pipCmd = "$PythonCmd -m pip install --upgrade -r `"$req`""
  $commands.Add($cloneCmd)
  $commands.Add($pipCmd)
  if (-not $DryRun) {
    if (Test-Path $DomoHome) { & $GitCmd -C $DomoHome pull --ff-only } else { & $GitCmd clone $DomoRepoUrl $DomoHome }
    if ($LASTEXITCODE -ne 0 -and -not (Test-Path $req)) {
      $prereqsMissing.Add("clone de domo-mcp-server fallo: $cloneCmd")
    } else {
      & $PythonCmd -m pip install --upgrade -r $req
      if ($LASTEXITCODE -ne 0) {
        $prereqsMissing.Add("pip install de las dependencias de domo fallo: $pipCmd")
      } else {
        [Environment]::SetEnvironmentVariable("DOMO_MCP_HOME", $DomoHome, 'User')
        $installed.Add("domo (clone + deps; DOMO_MCP_HOME seteado)")
      }
    }
  } else {
    $installed.Add("domo (clone + deps)")
  }
} else {
  $skipped.Add("domo")
  if (-not $haveGit) { $prereqsMissing.Add("Git no encontrado en PATH (comando '$GitCmd'): instala Git y re-corre la skill.") }
  if (-not $havePy)  { $prereqsMissing.Add("Python no encontrado en PATH (comando '$PythonCmd'): instalalo y re-corre la skill.") }
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
  domoHome       = $DomoHome
  installed      = @($installed)
  skipped        = @($skipped)
  prereqsMissing = @($prereqsMissing)
  commands       = @($commands)
} | ConvertTo-Json -Depth 5
