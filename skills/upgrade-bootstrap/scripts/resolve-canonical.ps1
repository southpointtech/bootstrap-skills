# Resolves which installed bootstrap skill a project's canonical scaffold comes from.
# Usage: pwsh -File resolve-canonical.ps1 -ProjectDir <path> [-SkillsRoot <path, default ~/.claude/skills>] [-Skill <name>]
# Emits JSON to stdout: { skill, scaffold, generatedFrom, resolvedBy, variantSwitch, candidates[] }
# and exits 0, or writes a message and exits 1 when it cannot decide.
#
# Rule:
#   - the manifest's generatedFrom names a skill installed with a scaffold -> that one ("manifest")
#   - otherwise (not installed, or no manifest: legacy project), exactly one bootstrap-*-project skill
#     with a scaffold is installed -> that one ("only-installed"). This is the project bootstrapped
#     with one variant and upgraded on a machine that only has another (a shared copy of the skills):
#     the manifest's bases still classify every file, and the reseal rewrites generatedFrom. It is
#     reported as variantSwitch = true: those bases belong to the OTHER variant, so an untouched file
#     that differs from the canonical may differ by variant (CLAUDE.md, the issue-tracker doc, the
#     workflow doc) and not by an upstream update, and the two cannot be told apart without the
#     original variant installed. The SKILL puts such files to the user one by one instead of
#     overwriting them as "outdated".
#   - several or none installed -> exit 1 listing them, so the agent asks instead of guessing, and
#     re-runs with -Skill <the user's answer>: that skill is taken ("user"), and variantSwitch is
#     true when the manifest named a different one, for the same reason as above.
# A candidate is <SkillsRoot>/bootstrap-*-project with assets/scaffold/.bootstrap-manifest.json: a
# bootstrap-* folder without one is not a bootstrap of this family.
param(
    [Parameter(Mandatory)][string]$ProjectDir,
    [string]$SkillsRoot = (Join-Path $HOME ".claude" "skills"),
    [string]$Skill
)
$ErrorActionPreference = "Stop"

function Get-Scaffold($skillName) {
    $scaffold = Join-Path $SkillsRoot $skillName "assets" "scaffold"
    if (Test-Path -LiteralPath (Join-Path $scaffold ".bootstrap-manifest.json")) { $scaffold } else { $null }
}

$generatedFrom = $null
$projManifestPath = Join-Path $ProjectDir ".bootstrap-manifest.json"
if (Test-Path -LiteralPath $projManifestPath) {
    $generatedFrom = (Get-Content -LiteralPath $projManifestPath -Raw | ConvertFrom-Json).generatedFrom
}

$candidates = @()
if (Test-Path -LiteralPath $SkillsRoot) {
    $candidates = @(Get-ChildItem -LiteralPath $SkillsRoot -Directory |
        Where-Object { $_.Name -like "bootstrap-*-project" -and (Get-Scaffold $_.Name) } |
        Sort-Object Name | ForEach-Object { $_.Name })
}

$chosen = $null; $resolvedBy = $null
if ($Skill) {
    if (-not (Get-Scaffold $Skill)) {
        Write-Error -ErrorAction Continue "'$Skill' is not installed with a scaffold under $SkillsRoot (candidates: $($candidates -join ', '))."
        exit 1
    }
    $chosen = $Skill; $resolvedBy = "user"
} elseif ($generatedFrom -and (Get-Scaffold $generatedFrom)) {
    $chosen = $generatedFrom; $resolvedBy = "manifest"
} elseif ($candidates.Count -eq 1) {
    $chosen = $candidates[0]; $resolvedBy = "only-installed"
} else {
    $why = if ($generatedFrom) { "The project manifest names '$generatedFrom', which is not installed under $SkillsRoot" }
           else                { "The project has no .bootstrap-manifest.json (legacy)" }
    $have = if ($candidates.Count) { "installed candidates: $($candidates -join ', ')" }
            else                   { "no bootstrap-*-project skill with a scaffold is installed under $SkillsRoot" }
    Write-Error -ErrorAction Continue "$why, and $have. Cannot choose the canonical scaffold: ask the user which skill the project belongs to."
    exit 1
}

[ordered]@{
    skill         = $chosen
    scaffold      = (Get-Scaffold $chosen)
    generatedFrom = $generatedFrom
    resolvedBy    = $resolvedBy
    variantSwitch = ([bool]$generatedFrom -and $chosen -ne $generatedFrom)
    candidates    = $candidates
} | ConvertTo-Json -Depth 3
