# review-marker.ps1 — the review marker: how far the last review run got on this branch.
# Single place that knows how a marker is set, persisted and resolved.
#
#   -Action get      -> the stored marker for this branch, or empty if there is none
#   -Action range    -> what to hand `git diff`: the stored marker when it still resolves,
#                       otherwise the slice base. Emits the marker BARE, not `<marker>..HEAD`:
#                       the two-dot form only covers commits and would drop uncommitted work,
#                       which is exactly what `git stash create` exists to capture. The contract
#                       is `git diff <what range prints>`.
#   -Action advance  -> cuts a new marker with `git stash create` (falls back to HEAD when the
#                       tree is clean), persists it per branch and prints it
#
# State lives in the git directory (.git/review-loop-state.json) under `marker:<branch>` keys,
# so it never shows up in the slice diff and never gets committed. Git forbids ':' in branch
# names, so these keys cannot collide with the trigger hook's dedupe entries in the same file.
# Any non-applicable path (not a git repo, detached HEAD) ends in silent, empty exit 0.
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][ValidateSet("get", "range", "advance")][string]$Action,
  [string]$RepoDir
)
$ErrorActionPreference = "SilentlyContinue"

$dir = if ($RepoDir) { $RepoDir } else { (Get-Location).Path }
if (-not (Test-Path -LiteralPath $dir)) { exit 0 }

$gitDir = (git -C $dir rev-parse --git-dir 2>$null)
if (-not $gitDir) { exit 0 }                          # not a git repo
if (-not [IO.Path]::IsPathRooted($gitDir)) { $gitDir = Join-Path $dir $gitDir }

$branch = (git -C $dir rev-parse --abbrev-ref HEAD 2>$null)
if (-not $branch -or $branch -eq "HEAD") { exit 0 }   # detached HEAD: the caller decides

$statePath = Join-Path $gitDir "review-loop-state.json"
$key = "marker:$branch"

function Read-State {
  $s = @{}
  if (Test-Path -LiteralPath $statePath) {
    try {
      (Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json).PSObject.Properties |
        ForEach-Object { $s[$_.Name] = $_.Value }
    } catch { $s = @{} }
  }
  return $s
}

# Base of the slice: the merge-base against the base branch. Do NOT hardcode main.
function Get-SliceBase {
  $base = $null
  $head = (git -C $dir symbolic-ref --short refs/remotes/origin/HEAD 2>$null)
  if ($head) { $base = ($head -replace '^origin/', '') }
  if (-not $base) {
    foreach ($cand in @("main", "master", "develop")) {
      if ($cand -eq $branch) { continue }
      git -C $dir rev-parse --verify --quiet $cand 2>$null | Out-Null
      if ($LASTEXITCODE -eq 0) { $base = $cand; break }
    }
  }
  if (-not $base -or $base -eq $branch) { return $null }
  $mb = (git -C $dir merge-base $base HEAD 2>$null)
  if ($mb) { return ([string]$mb).Trim() }
  return $null
}

switch ($Action) {

  "get" {
    $sha = (Read-State)[$key]
    if ($sha) { Write-Output $sha }
    exit 0
  }

  "range" {
    # A stored marker is only usable while its object still resolves: `git stash create` objects
    # are unreachable, so an aggressive `git gc` can prune one. Falling back to the slice base
    # means the default failure mode is reviewing too much, never too little.
    $sha = (Read-State)[$key]
    if ($sha) {
      git -C $dir cat-file -e "$sha^{commit}" 2>$null
      if ($LASTEXITCODE -ne 0) { $sha = $null }
    }
    if (-not $sha) { $sha = Get-SliceBase }
    if (-not $sha) { exit 0 }
    # Nothing new since the marker: emit nothing, so the caller closes without a review run
    # instead of making up a range.
    git -C $dir diff --quiet $sha 2>$null
    if ($LASTEXITCODE -eq 0) { exit 0 }
    Write-Output $sha
    exit 0
  }

  "advance" {
    # `git stash create` builds a commit object from the current tree WITHOUT committing,
    # switching branches or touching the working tree — and it includes uncommitted changes.
    # It prints nothing when there is nothing to stash, hence the HEAD fallback.
    $sha = (git -C $dir stash create 2>$null)
    if ($sha) { $sha = ([string]$sha).Trim() }
    if (-not $sha) { $sha = (git -C $dir rev-parse HEAD 2>$null) }
    if (-not $sha) { exit 0 }                         # repo with no commits yet
    $sha = ([string]$sha).Trim()

    $state = Read-State
    $state[$key] = $sha
    ([pscustomobject]$state) | ConvertTo-Json | Set-Content -LiteralPath $statePath -Encoding UTF8
    Write-Output $sha
    exit 0
  }
}
