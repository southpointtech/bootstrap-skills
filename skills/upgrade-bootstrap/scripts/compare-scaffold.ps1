# Classifies the project's files against the canonical scaffold (3-hash merge-base).
# Usage: pwsh -File compare-scaffold.ps1 -ProjectDir <path> -CanonicalScaffold <path to the installed assets\scaffold>
# Emits JSON to stdout: { hasProjectManifest, canonicalVersion, variant, missing[], outdated[], customized[], orphan[], uptodate[] }
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
# touched file as untouched. Keep this block identical in reseal-manifest.ps1.
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

$canonManifestPath = Join-Path $CanonicalScaffold ".bootstrap-manifest.json"
if (-not (Test-Path $canonManifestPath)) { throw "Canonical scaffold has no manifest: $canonManifestPath" }
$canon = Get-Content $canonManifestPath -Raw | ConvertFrom-Json

$projManifestPath = Join-Path $ProjectDir ".bootstrap-manifest.json"
$hasProjManifest = Test-Path $projManifestPath
$projBase = @{}
if ($hasProjManifest) {
    (Get-Content $projManifestPath -Raw | ConvertFrom-Json).files.PSObject.Properties | ForEach-Object { $projBase[$_.Name] = $_.Value }
}

$missing = @(); $outdated = @(); $customized = @(); $uptodate = @()
foreach ($p in $canon.files.PSObject.Properties) {
    $rel = $p.Name; $canonHash = $p.Value
    $actual = Get-Hashes (Join-Path $ProjectDir $rel)
    if ($null -eq $actual)                 { $missing += $rel; continue }
    if (Test-Sealed $actual $canonHash)    { $uptodate += $rel; continue }
    if ($hasProjManifest -and $projBase.ContainsKey($rel)) {
        $base = $projBase[$rel]
        if (Test-Sealed $actual $base) { $outdated += $rel }                           # untouched; canonical moved forward
        else { $customized += [ordered]@{ file = $rel; threeWay = ($canonHash -ne $base) } }  # touched
    } else {
        $customized += [ordered]@{ file = $rel; threeWay = $true }                      # no base: differs, user decides
    }
}

# Orphans: only determinable with the project manifest (we know what belonged to the scaffold).
$orphan = @()
if ($hasProjManifest) {
    $canonNames = $canon.files.PSObject.Properties.Name
    foreach ($k in $projBase.Keys) {
        if (($canonNames -notcontains $k) -and (Test-Path (Join-Path $ProjectDir $k))) { $orphan += $k }
    }
}

[ordered]@{
    hasProjectManifest = $hasProjManifest
    canonicalVersion   = $canon.version
    variant            = $canon.variant
    missing            = $missing
    outdated           = $outdated
    customized         = $customized
    orphan             = $orphan
    uptodate           = $uptodate
} | ConvertTo-Json -Depth 6
