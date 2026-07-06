# Idempotently merges the canonical hooks (review-loop-trigger, alignment-gate, and any
# future addition) into the project's settings.json, without clobbering the existing config.
# If the project has no settings.json, copies the canonical one whole.
# Usage: pwsh -File merge-settings.ps1 -ProjectSettings <path> -CanonicalSettings <path>
param(
    [Parameter(Mandatory)][string]$ProjectSettings,
    [Parameter(Mandatory)][string]$CanonicalSettings
)
$ErrorActionPreference = "Stop"

if (-not (Test-Path $ProjectSettings)) {
    New-Item -ItemType Directory -Force (Split-Path $ProjectSettings -Parent) | Out-Null
    Copy-Item $CanonicalSettings $ProjectSettings -Force
    Write-Host "settings.json did not exist: canonical copied."
    exit 0
}

try { $canon = Get-Content $CanonicalSettings -Raw | ConvertFrom-Json -AsHashtable }
catch { throw "canonical settings.json is not valid JSON: $CanonicalSettings" }
try { $proj  = Get-Content $ProjectSettings  -Raw | ConvertFrom-Json -AsHashtable }
catch { throw "project settings.json is not valid JSON: $ProjectSettings" }
if ($null -eq $proj) { $proj = @{} }
if (-not $proj.ContainsKey('hooks')) { $proj['hooks'] = @{} }
if ($null -eq $canon.hooks) { Write-Host "Canonical settings.json has no hooks: nothing to do."; exit 0 }

# Signature of a hook entry: the concatenation of its hooks' commands.
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
    Write-Host "Hooks merged into the project settings.json: $added new entry/ies."
} else {
    Write-Host "All canonical hooks already present: nothing to do (idempotent)."
}
exit 0
