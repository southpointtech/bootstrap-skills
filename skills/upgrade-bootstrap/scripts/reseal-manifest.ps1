# Re-seals the project manifest after an upgrade.
# Usage: pwsh -File reseal-manifest.ps1 -ProjectDir <path> -CanonicalScaffold <path to the installed assets\scaffold>
# Per-file base rule:
#   current == canonical            -> base = canonical (reconciled)
#   current != canonical, has base  -> base = previous base (customized: stays detectable)
#   current != canonical, no base   -> base = current (legacy: seed)
#   file absent in project          -> not recorded (user skipped it)
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
Write-Host "Project manifest re-sealed: version $($canon.version), $($files.Count) files"
