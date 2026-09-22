# Re-seals the project manifest after an upgrade.
# Usage: pwsh -File reseal-manifest.ps1 -ProjectDir <path> -CanonicalScaffold <path to the installed assets\scaffold>
# Per-file base rule ("matches" = Test-Sealed below: the same content, line endings aside):
#   current matches canonical                -> base = canonical (reconciled)
#   has a base, current still matches it     -> base = current normalized hash (untouched; converts
#                                               a legacy raw base)
#   has a base, current does not match it    -> base = previous base, as-is (customized: stays detectable)
#   no base                                  -> base = current normalized hash (legacy: seed)
#   file absent in project                   -> not recorded (user skipped it)
param(
    [Parameter(Mandatory)][string]$ProjectDir,
    [Parameter(Mandatory)][string]$CanonicalScaffold
)
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "normalized-hash.ps1")
# Get-Hashes and Test-Sealed (the manifest matching rule, legacy raw bases included) live in
# normalized-hash.ps1, next to this script.

$canon = Get-Content (Join-Path $CanonicalScaffold ".bootstrap-manifest.json") -Raw | ConvertFrom-Json
$projManifestPath = Join-Path $ProjectDir ".bootstrap-manifest.json"
$oldBase = @{}
if (Test-Path $projManifestPath) {
    (Get-Content $projManifestPath -Raw | ConvertFrom-Json).files.PSObject.Properties | ForEach-Object { $oldBase[$_.Name] = $_.Value }
}

$files = [ordered]@{}
foreach ($p in ($canon.files.PSObject.Properties | Sort-Object Name)) {
    $rel = $p.Name; $canonHash = $p.Value
    $actual = Get-Hashes (Join-Path $ProjectDir $rel)
    if ($null -eq $actual) { continue }
    if (Test-Sealed $actual $canonHash) { $files[$rel] = $canonHash }
    elseif ($oldBase.ContainsKey($rel)) {
        # Untouched since its base: re-seal the same content with the normalized hash. Touched: keep
        # the old base as-is, so the file stays customized; seeding it with the current hash would
        # make the next upgrade see the user's edit as untouched and overwrite it.
        if (Test-Sealed $actual $oldBase[$rel]) { $files[$rel] = $actual.n }
        else                                    { $files[$rel] = $oldBase[$rel] }
    }
    else                                 { $files[$rel] = $actual.n }
}

$manifest = [ordered]@{
    variant       = $canon.variant
    generatedFrom = $canon.generatedFrom
    version       = $canon.version
    files         = $files
}
$manifest | ConvertTo-Json -Depth 5 | Set-Content $projManifestPath -Encoding UTF8
Write-Host "Project manifest re-sealed: version $($canon.version), $($files.Count) files"
