# Integra (idempotente) los hooks canonicos (review-loop-trigger, alignment-gate, y cualquier
# otro que se agregue a futuro) en el settings.json del proyecto, sin pisar la config previa.
# Si el proyecto no tiene settings.json, copia el canónico entero.
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

try { $canon = Get-Content $CanonicalSettings -Raw | ConvertFrom-Json -AsHashtable }
catch { throw "settings.json canonico no es JSON valido: $CanonicalSettings" }
try { $proj  = Get-Content $ProjectSettings  -Raw | ConvertFrom-Json -AsHashtable }
catch { throw "settings.json del proyecto no es JSON valido: $ProjectSettings" }
if ($null -eq $proj) { $proj = @{} }
if (-not $proj.ContainsKey('hooks')) { $proj['hooks'] = @{} }
if ($null -eq $canon.hooks) { Write-Host "El settings.json canonico no tiene hooks: nada que hacer."; exit 0 }

# Firma de una entrada de hook: la concatenacion de los command de sus hooks.
function Get-Sig($entry) { (@($entry.hooks) | ForEach-Object { $_.command }) -join '|' }

$added = 0
foreach ($event in @($canon.hooks.Keys)) {
    if (-not $proj.hooks.ContainsKey($event)) { $proj.hooks[$event] = @() }
    $present = @($proj.hooks[$event]) | ForEach-Object { Get-Sig $_ }
    foreach ($entry in @($canon.hooks[$event])) {
        if ((Get-Sig $entry) -notin $present) {
            $proj.hooks[$event] = @($proj.hooks[$event]) + $entry
            $present += (Get-Sig $entry)
            $added++
        }
    }
}
if ($added -gt 0) {
    $proj | ConvertTo-Json -Depth 12 | Set-Content $ProjectSettings -Encoding UTF8
    Write-Host "Hooks integrados al settings.json del proyecto: $added entrada/s nueva/s."
} else {
    Write-Host "Todos los hooks canonicos ya presentes: nada que hacer (idempotente)."
}
exit 0
