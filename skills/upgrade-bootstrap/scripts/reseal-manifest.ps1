# Re-sella el manifest del proyecto tras un upgrade.
# Uso: pwsh -File reseal-manifest.ps1 -ProjectDir <ruta> -CanonicalScaffold <ruta a assets\scaffold instalado>
# Regla de base por archivo:
#   actual == canónico            -> base = canónico (reconciliado)
#   actual != canónico, hay base  -> base = base previa (personalizado: sigue detectable)
#   actual != canónico, sin base  -> base = actual (legacy: sembrar)
#   archivo ausente en proyecto   -> no se registra (el usuario lo saltó)
param(
    [Parameter(Mandatory)][string]$ProjectDir,
    [Parameter(Mandatory)][string]$CanonicalScaffold
)
$ErrorActionPreference = "Stop"
function Get-Hash($path) { if (Test-Path $path) { (Get-FileHash $path -Algorithm SHA256).Hash.ToLower() } else { $null } }

$canon = Get-Content (Join-Path $CanonicalScaffold ".bootstrap-manifest.json") -Raw | ConvertFrom-Json
$projManifestPath = Join-Path $ProjectDir ".bootstrap-manifest.json"
$oldBase = @{}
if (Test-Path $projManifestPath) {
    (Get-Content $projManifestPath -Raw | ConvertFrom-Json).files.PSObject.Properties | ForEach-Object { $oldBase[$_.Name] = $_.Value }
}

$files = [ordered]@{}
foreach ($p in ($canon.files.PSObject.Properties | Sort-Object Name)) {
    $rel = $p.Name; $canonHash = $p.Value
    $actual = Get-Hash (Join-Path $ProjectDir $rel)
    if ($null -eq $actual) { continue }
    if ($actual -eq $canonHash)        { $files[$rel] = $canonHash }
    elseif ($oldBase.ContainsKey($rel)) { $files[$rel] = $oldBase[$rel] }
    else                                { $files[$rel] = $actual }
}

$manifest = [ordered]@{
    variant       = $canon.variant
    generatedFrom = $canon.generatedFrom
    version       = $canon.version
    files         = $files
}
$manifest | ConvertTo-Json -Depth 5 | Set-Content $projManifestPath -Encoding UTF8
Write-Host "Manifest del proyecto re-sellado: version $($canon.version), $($files.Count) archivos"
