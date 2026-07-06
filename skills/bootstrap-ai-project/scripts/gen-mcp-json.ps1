# gen-mcp-json.ps1 — generates the project's .mcp.json from this skill's MCP catalog.
# Usage: pwsh -NoProfile -File gen-mcp-json.ps1 -ProjectDir <path> -Servers firebase,github [-Force]
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
    prereqs         = @("firebase login (once)")
  }
  "github" = [ordered]@{
    config          = [ordered]@{ type = "stdio"; command = "docker"; args = @("run","-i","--rm","-e","GITHUB_PERSONAL_ACCESS_TOKEN","ghcr.io/github/github-mcp-server"); env = [ordered]@{ GITHUB_PERSONAL_ACCESS_TOKEN = '${GITHUB_PERSONAL_TOKEN}' } }
    requiredEnvVars = @("GITHUB_PERSONAL_TOKEN")
    prereqs         = @("Docker Desktop running")
  }
}

if (-not (Test-Path $ProjectDir)) { throw "ProjectDir not found: $ProjectDir" }

# -File may deliver "-Servers a,b" as a single "a,b" string: split on commas ourselves.
$selected = @($Servers | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" })

foreach ($s in $selected) {
  if (-not $Catalog.Contains($s)) {
    throw "Unknown server: '$s'. Valid: $(($Catalog.Keys) -join ', ')"
  }
}

if ($selected.Count -eq 0) {
  [pscustomobject]@{ written = $false; reason = "no servers selected" } | ConvertTo-Json -Compress
  return
}

$target = Join-Path $ProjectDir ".mcp.json"

if ((Test-Path $target) -and -not $Force) {
  throw ".mcp.json already exists in $ProjectDir (use -Force to overwrite)"
}

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
