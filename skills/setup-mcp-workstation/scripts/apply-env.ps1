# apply-env.ps1 — aplica las credenciales del workstation como env vars persistentes de usuario.
# Uso: pwsh -NoProfile -File apply-env.ps1 -ConfigPath <archivo.json> [-DryRun]
# NUNCA imprime valores de tokens: el resumen JSON lleva solo nombres de variables y estado.
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$ConfigPath,
  [switch]$DryRun
)
$ErrorActionPreference = "Stop"

if (-not (Test-Path $ConfigPath)) { throw "No existe el archivo de config: $ConfigPath" }

try { $cfg = Get-Content $ConfigPath -Raw | ConvertFrom-Json } catch { throw "Config JSON malformado: $ConfigPath" }

# Mapa: env var -> valor desde el config (con la ruta del campo para el mensaje de error)
$map = [ordered]@{
  "SOUTHPOINT_GIT_NAME"     = @{ value = $cfg.git.name;     field = "git.name" }
  "SOUTHPOINT_GIT_EMAIL"    = @{ value = $cfg.git.email;    field = "git.email" }
  "DOMO_SOUTHPOINT_TOKEN"   = @{ value = $cfg.domo.token;   field = "domo.token" }
  "ZOHO_SOUTHPOINT_MCP_URL" = @{ value = $cfg.zoho.mcpUrl;  field = "zoho.mcpUrl" }
}

foreach ($k in $map.Keys) {
  $v = $map[$k].value
  if ([string]::IsNullOrWhiteSpace([string]$v)) { throw "Falta el campo '$($map[$k].field)' en $ConfigPath" }
}

$vars = New-Object System.Collections.Generic.List[object]
foreach ($k in $map.Keys) {
  $new = [string]$map[$k].value
  $cur = [Environment]::GetEnvironmentVariable($k, 'User')
  $status = if ($cur -eq $new) { "unchanged" } else { "set" }
  if (-not $DryRun) { [Environment]::SetEnvironmentVariable($k, $new, 'User') }
  $vars.Add([ordered]@{ name = $k; status = $status })
}

[pscustomobject]@{
  applied = (-not $DryRun)
  dryRun  = [bool]$DryRun
  vars    = $vars.ToArray()
} | ConvertTo-Json -Depth 5
