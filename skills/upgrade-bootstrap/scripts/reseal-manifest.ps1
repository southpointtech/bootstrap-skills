# Re-seals the project manifest after an upgrade.
# Usage: pwsh -File reseal-manifest.ps1 -ProjectDir <path> -CanonicalScaffold <path to the installed assets\scaffold> [-VariantSwitch]
# Per-file base rule ("matches" = Test-Sealed below: the same content, line endings aside):
#   current matches canonical                -> base = canonical (reconciled)
#   has a base, current still matches it     -> base = current normalized hash (untouched; converts
#                                               a legacy raw base)
#   has a base, current does not match it    -> base = previous base, as-is (customized: stays detectable)
#   no base, project had no manifest         -> base = current normalized hash (legacy: seed)
#   no base, project had a manifest          -> not recorded (the project's own file: stays customized)
#   file absent in project                   -> not recorded (user skipped it)
# With -VariantSwitch (resolve-canonical.ps1 reported the manifest's bases belong to another variant),
# a file that has a base and does not match the canonical is not recorded either, whether it still
# matches that base or not: re-sealing it as "untouched" would make the next upgrade, now reading the
# new variant from generatedFrom, see it as outdated and overwrite what the user chose to keep.
# Left out, it stays customized (no base with a manifest present) and is put to the user each time.
param(
    [Parameter(Mandatory)][string]$ProjectDir,
    [Parameter(Mandatory)][string]$CanonicalScaffold,
    [switch]$VariantSwitch
)
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "normalized-hash.ps1")
# Get-Hashes and Test-Sealed (the manifest matching rule, legacy raw bases included) live in
# normalized-hash.ps1, next to this script.

$canon = Get-Content (Join-Path $CanonicalScaffold ".bootstrap-manifest.json") -Raw | ConvertFrom-Json
$projManifestPath = Join-Path $ProjectDir ".bootstrap-manifest.json"
$oldBase = @{}
$hadManifest = Test-Path $projManifestPath
if ($hadManifest) {
    (Get-Content $projManifestPath -Raw | ConvertFrom-Json).files.PSObject.Properties | ForEach-Object { $oldBase[$_.Name] = $_.Value }
}

$files = [ordered]@{}
foreach ($p in ($canon.files.PSObject.Properties | Sort-Object Name)) {
    $rel = $p.Name; $canonHash = $p.Value
    $actual = Get-Hashes (Join-Path $ProjectDir $rel)
    if ($null -eq $actual) { continue }
    if (Test-Sealed $actual $canonHash) { $files[$rel] = $canonHash }
    elseif ($oldBase.ContainsKey($rel)) {
        if ($VariantSwitch) { continue }   # the base is the other variant's: see the header
        # Untouched since its base: re-seal the same content with the normalized hash. Touched: keep
        # the old base as-is, so the file stays customized; seeding it with the current hash would
        # make the next upgrade see the user's edit as untouched and overwrite it.
        if (Test-Sealed $actual $oldBase[$rel]) { $files[$rel] = $actual.n }
        else                                    { $files[$rel] = $oldBase[$rel] }
    }
    # No base and different from canonical. Without a manifest this is a first adoption: seed. With
    # one, the file is the project's own (it existed before the canonical added it): seeding it would
    # make the next upgrade see it as untouched and overwrite it, so leave it out and keep it customized.
    elseif (-not $hadManifest)           { $files[$rel] = $actual.n }
}

$manifest = [ordered]@{
    variant       = $canon.variant
    generatedFrom = $canon.generatedFrom
    version       = $canon.version
    files         = $files
}
$manifest | ConvertTo-Json -Depth 5 | Set-Content $projManifestPath -Encoding UTF8
Write-Host "Project manifest re-sealed: version $($canon.version), $($files.Count) files"
