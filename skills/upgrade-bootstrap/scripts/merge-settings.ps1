# Integra (idempotente) el hook review-loop-trigger en el settings.json del proyecto, sin
# pisar la config previa. Si el proyecto no tiene settings.json, copia el canónico entero.
# Uso: pwsh -File merge-settings.ps1 -ProjectSettings <ruta> -CanonicalSettings <ruta>
param(
    [Parameter(Mandatory)][string]$ProjectSettings,
    [Parameter(Mandatory)][string]$CanonicalSettings
)
$ErrorActionPreference = "Stop"

if (-not (Test-Path $ProjectSettings)) {
    New-Item -ItemType Directory -Force (Split-Path $ProjectSettings -Parent) | Out-Null
    Copy-Item $CanonicalSettings $ProjectSettings -Force
    Write-Host "settings.json no existia: copiado el canonico."
    exit 0
}

$canon = Get-Content $CanonicalSettings -Raw | ConvertFrom-Json -AsHashtable
$proj  = Get-Content $ProjectSettings  -Raw | ConvertFrom-Json -AsHashtable
if ($null -eq $proj)        { $proj = @{} }
if (-not $proj.ContainsKey('hooks'))            { $proj['hooks'] = @{} }
if (-not $proj.hooks.ContainsKey('PostToolUse')) { $proj.hooks['PostToolUse'] = @() }

function Has-Trigger($entries) {
    foreach ($e in @($entries)) {
        foreach ($h in @($e.hooks)) {
            if ($h.command -and ($h.command -match 'review-loop-trigger')) { return $true }
        }
    }
    return $false
}

if (Has-Trigger $proj.hooks.PostToolUse) {
    Write-Host "Hook review-loop-trigger ya presente: nada que hacer (idempotente)."
    exit 0
}

# Agregar solo las entradas canonicas que traen el hook review-loop-trigger
$toAdd = @()
foreach ($e in @($canon.hooks.PostToolUse)) {
    if (Has-Trigger @($e)) { $toAdd += $e }
}
$proj.hooks['PostToolUse'] = @($proj.hooks.PostToolUse) + $toAdd
$proj | ConvertTo-Json -Depth 12 | Set-Content $ProjectSettings -Encoding UTF8
Write-Host "Hook review-loop-trigger agregado al settings.json del proyecto ($($toAdd.Count) entrada/s)."
