# Clasifica los archivos del proyecto contra el scaffold canónico (merge-base de 3 hashes).
# Uso: pwsh -File compare-scaffold.ps1 -ProjectDir <ruta> -CanonicalScaffold <ruta a assets\scaffold instalado>
# Emite JSON a stdout: { hasProjectManifest, canonicalVersion, variant, missing[], outdated[], customized[], orphan[], uptodate[] }
param(
    [Parameter(Mandatory)][string]$ProjectDir,
    [Parameter(Mandatory)][string]$CanonicalScaffold
)
$ErrorActionPreference = "Stop"

function Get-Hash($path) { if (Test-Path $path) { (Get-FileHash $path -Algorithm SHA256).Hash.ToLower() } else { $null } }

$canonManifestPath = Join-Path $CanonicalScaffold ".bootstrap-manifest.json"
if (-not (Test-Path $canonManifestPath)) { throw "Scaffold canónico sin manifest: $canonManifestPath" }
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
    $actual = Get-Hash (Join-Path $ProjectDir $rel)
    if ($null -eq $actual)        { $missing += $rel; continue }
    if ($actual -eq $canonHash)   { $uptodate += $rel; continue }
    if ($hasProjManifest -and $projBase.ContainsKey($rel)) {
        $base = $projBase[$rel]
        if ($actual -eq $base) { $outdated += $rel }                                   # no tocado; canónico avanzó
        else { $customized += [ordered]@{ file = $rel; threeWay = ($canonHash -ne $base) } }  # tocado
    } else {
        $customized += [ordered]@{ file = $rel; threeWay = $true }                      # sin base: diferente, decide el usuario
    }
}

# Huérfanos: solo determinables con manifest del proyecto (sabemos qué pertenecía al scaffold).
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
