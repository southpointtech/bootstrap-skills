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
# Canonical manifests are sealed with the normalized hash (line endings unified to LF). Project
# manifests sealed before that hold RAW hashes of whatever bytes the checkout had, so a sealed hash
# matches a file if it equals any of: its normalized hash, its raw hash, or the hash of its content
# with every line ending written as CRLF (a raw base sealed from a CRLF checkout, for a file that is
# LF now). Each one means the same content with at most the line endings changed, so none can mark a
# touched file as untouched. Keep this block identical in compare-scaffold.ps1.
function Get-CrlfHash($path) {
    $l1 = [Text.Encoding]::GetEncoding(28591)   # byte-exact, like normalized-hash.ps1
    $s = $l1.GetString([IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $path).ProviderPath))
    $s = (($s -replace "`r`n", "`n") -replace "`r", "`n") -replace "`n", "`r`n"
    $sha = [Security.Cryptography.SHA256]::Create()
    try { [BitConverter]::ToString($sha.ComputeHash($l1.GetBytes($s))).Replace('-', '').ToLowerInvariant() } finally { $sha.Dispose() }
}
function Get-Hashes($path) {
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    @{ n = Get-NormalizedHash -Path $path; r = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLower()
       c = Get-CrlfHash $path }
}
function Test-Sealed($h, $sealed) { ($sealed -eq $h.n) -or ($sealed -eq $h.r) -or ($sealed -eq $h.c) }

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
