# gen-mcp-json.ps1 — genera el .mcp.json del proyecto a partir del catalogo MCP del area (PERSONAL).
# Uso: pwsh -NoProfile -File gen-mcp-json.ps1 -ProjectDir <ruta> -Servers firebase,zoho-personal [-Force]
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$ProjectDir,
  [string[]]$Servers = @(),
  [switch]$Force
)
$ErrorActionPreference = "Stop"

$Catalog = [ordered]@{
  "firebase" = [ordered]@{
    config          = [ordered]@{ type = "stdio"; command = "npx"; args = @("-y","firebase-tools@latest","experimental:mcp") }
    requiredEnvVars = @()
    prereqs         = @("firebase login (una vez)")
  }
  "zoho-personal" = [ordered]@{
    config          = [ordered]@{ type = "http"; url = '${ZOHO_PERSONAL_MCP_URL}' }
    requiredEnvVars = @("ZOHO_PERSONAL_MCP_URL")
    prereqs         = @()
  }
  "github" = [ordered]@{
    config          = [ordered]@{ type = "stdio"; command = "docker"; args = @("run","-i","--rm","-e","GITHUB_PERSONAL_ACCESS_TOKEN","ghcr.io/github/github-mcp-server"); env = [ordered]@{ GITHUB_PERSONAL_ACCESS_TOKEN = '${GITHUB_PERSONAL_ACCESS_TOKEN}' } }
    requiredEnvVars = @("GITHUB_PERSONAL_ACCESS_TOKEN")
    prereqs         = @("Docker Desktop corriendo")
  }
}

if (-not (Test-Path $ProjectDir)) { throw "No existe ProjectDir: $ProjectDir" }

# -File puede entregar "-Servers a,b" como un unico string "a,b": separar por coma nosotros.
$selected = @($Servers | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" })

if ($selected.Count -eq 0) {
  [pscustomobject]@{ written = $false; reason = "no servers selected" } | ConvertTo-Json -Compress
  return
}

$target = Join-Path $ProjectDir ".mcp.json"

$serverMap = [ordered]@{}
$envVars = New-Object System.Collections.Generic.List[string]
$prereqs = New-Object System.Collections.Generic.List[string]
foreach ($key in $Catalog.Keys) {
  if ($selected -contains $key) {
    $serverMap[$key] = $Catalog[$key].config
    foreach ($e in $Catalog[$key].requiredEnvVars) { if (-not $envVars.Contains($e)) { $envVars.Add($e) } }
    foreach ($p in $Catalog[$key].prereqs)         { if (-not $prereqs.Contains($p)) { $prereqs.Add($p) } }
  }
}

$doc = [ordered]@{ mcpServers = $serverMap }
$doc | ConvertTo-Json -Depth 10 | Set-Content -Path $target -Encoding UTF8

[pscustomobject]@{
  written         = $true
  path            = $target
  servers         = @($serverMap.Keys)
  requiredEnvVars = @($envVars)
  prereqs         = @($prereqs)
} | ConvertTo-Json -Depth 5
