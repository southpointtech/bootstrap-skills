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
#   -Action base     -> the slice base (a merge-base commit), for the trigger hook to delegate to
#                       when its own named-branch lookup fails. Same exit contract as `range`:
#                       0 + a ref when resolvable, 2 + no output when no base can be determined.
#
# Exit codes are part of the contract, because "nothing new to review" and "I cannot tell" must
# never look the same to the caller — a caller that conflates them closes the loop reporting a
# slice clean that no reviewer ever read. For `-Action range`:
#
#   0 + a ref     -> review `git diff <ref>` (plus untracked files, which git diff never shows)
#   0 + no output -> there is genuinely no unreviewed delta; closing the loop is correct
#   2 + no output -> not applicable / undeterminable (not a git repo, detached HEAD, no commits,
#                    no resolvable slice base). The caller decides; it must NOT close the loop.
#
# For `get` and `advance`, exit 2 means the same "not applicable", but `0 + no output` from `get`
# only means "no marker stored yet" — the normal state of a first turn, never a reason to close.
#
# State lives in the git directory (.git/review-loop-state.json) under `marker:<branch>` keys,
# so it never shows up in the slice diff and never gets committed. Git forbids ':' in branch
# names, so these keys cannot collide with the trigger hook's dedupe entries in the same file.
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][ValidateSet("get", "range", "advance", "base")][string]$Action,
  [string]$RepoDir
)
$ErrorActionPreference = "SilentlyContinue"

# git writes UTF-8 and PowerShell decodes child output with Console::OutputEncoding, so EVERY git
# call whose output can carry a path needs this — not just `ls-files`, which is the only one that
# used to have it. A child `pwsh` with stdout redirected (exactly how the trigger hook invokes this
# script) does not inherit the parent's 65001 and reports an OEM code page instead, so this cannot
# be left to the environment. Under a non-ASCII path (`C:\Users\Martín\…`) `rev-parse
# --show-toplevel` came back mangled: $dir stopped being a repo, $statePath pointed at a directory
# that does not exist, and all THREE actions exited 2 — `advance` never advancing, the marker never
# persisting, and the loop re-reviewing the whole branch every turn with nothing to say so.
# Set once and not restored: this script always runs as a short-lived child process.
try { [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false) } catch { }

$dir = if ($RepoDir) { $RepoDir } else { (Get-Location).Path }
if (-not (Test-Path -LiteralPath $dir)) { exit 2 }

$gitDir = (git -C $dir rev-parse --git-dir 2>$null)
if (-not $gitDir) { exit 2 }                          # not a git repo
if (-not [IO.Path]::IsPathRooted($gitDir)) { $gitDir = Join-Path $dir $gitDir }
# From here on everything works from the REPO ROOT. `ls-files` lists only the cwd's subtree and
# emits paths relative to it, so run from a subdirectory (a monorepo session opened in `app/`) the
# untracked fingerprint was recorded on a different base than the trigger hook reads it on — the
# hook anchors to the root — and neither side ever matched again.
$top = (git -C $dir rev-parse --show-toplevel 2>$null)
if ($top) { $dir = $top }

$branch = (git -C $dir rev-parse --abbrev-ref HEAD 2>$null)
if (-not $branch -or $branch -eq "HEAD") { exit 2 }   # detached HEAD: the caller decides

$statePath = Join-Path $gitDir "review-loop-state.json"
$key = "marker:$branch"

# The state file crosses shells: one turn may run under pwsh 7 and the next under Windows
# PowerShell 5.1 (a hook, a hand-run command). Their defaults disagree — `Set-Content -Encoding
# UTF8` omits the BOM on 7 and writes it on 5.1, and `Get-Content -Raw` on 5.1 decodes a BOM-less
# file with the ANSI code page. An accented untracked path then reads back as mojibake, its
# fingerprint never matches again, and the range stays non-empty forever: that branch can no longer
# close the loop on "nothing new". The .NET calls below are explicit UTF-8 (with BOM detection on
# read) in every PowerShell edition.
# $script:stateCorrupt records that the file EXISTED but did not parse, so `advance` can quarantine
# it before overwriting instead of silently dropping every OTHER branch's marker/untracked keys and
# the hook's dedupe entries — the same `.bad` recovery the trigger hook already performs on its side.
$script:stateCorrupt = $false
function Read-State {
  $s = @{}
  $script:stateCorrupt = $false
  if (Test-Path -LiteralPath $statePath) {
    try {
      ([IO.File]::ReadAllText($statePath) | ConvertFrom-Json).PSObject.Properties |
        ForEach-Object { $s[$_.Name] = $_.Value }
    } catch { $s = @{}; $script:stateCorrupt = $true }
  }
  return $s
}

function Resolve-Commit([string]$ref) {
  if (-not $ref) { return $false }
  git -C $dir rev-parse --verify --quiet "$ref^{commit}" 2>$null | Out-Null
  return ($LASTEXITCODE -eq 0)
}

# Base of the slice: the merge-base against the base branch. Do NOT hardcode main.
# Remote-tracking refs are used AS IS (`merge-base origin/main HEAD` works fine). Stripping the
# `origin/` prefix — as an earlier version did — yields a local name that need not exist: in a
# single-branch clone or a `gh pr checkout` there is an `origin/main` but no local `main`, the
# merge-base then fails, and the whole slice goes unreviewed.
# Named base branches, in the order they should be trusted. Every one of these is a plausible base,
# so among them the NEAREST merge-base is the right pick: on `develop` with unpushed commits the
# base is `origin/develop`, and those commits stay inside the range.
function Get-NamedBases {
  $named = @()
  $head = (git -C $dir symbolic-ref --short refs/remotes/origin/HEAD 2>$null)
  if ($head) { $named += ([string]$head).Trim() }
  foreach ($n in @("main", "master", "develop")) { $named += $n; $named += "origin/$n" }
  return @($named | Where-Object { $_ -ne $branch -and (Resolve-Commit $_) })
}

# Every other ref, for repos whose base is `trunk`, `dev`, `release`… These are NOT plausible bases:
# most of them are siblings. `origin/HEAD` shortens to plain `origin`, so the exclusion is done on
# the full ref name.
function Get-OtherRefs {
  return @(git -C $dir for-each-ref --format="%(refname)|%(refname:short)" refs/heads refs/remotes 2>$null |
           Where-Object { $_ -and -not ($_ -match '/HEAD\|') } |
           ForEach-Object { ($_ -split '\|', 2)[1] } |
           Where-Object { $_ -and $_ -ne $branch -and $_ -ne "origin/$branch" })
}

# The base of the slice.
#
# A merge-base equal to HEAD is a legitimate answer, not a failure — it means this branch has no
# committed delta against that candidate, which is the situation on the base branch itself.
# `git diff HEAD` then reviews the uncommitted work, and a clean tree yields an empty range that
# closes the loop. Returning $null (no candidate at all) is the honest "I cannot tell": emitting
# HEAD there would hide a feature branch's own commits behind an exit 0.
function Get-SliceBase {
  $named = Get-NamedBases
  if ($named) {
    $head = (git -C $dir rev-parse HEAD 2>$null)
    $head = if ($head) { ([string]$head).Trim() } else { $null }
    $best = $null
    $bestDist = [int]::MaxValue
    $headResolved = $false
    foreach ($c in $named) {
      $mb = (git -C $dir merge-base $c HEAD 2>$null)
      if (-not $mb) { continue }
      $mb = ([string]$mb).Trim()
      # A candidate that already CONTAINS HEAD scores distance 0, so on a nearest-wins comparison it
      # beats every other candidate and collapses the base to HEAD — after which `git diff HEAD`
      # hides every commit of the slice behind an exit 0, the signal the caller reads as "range is
      # sound". It takes nothing exotic: merge the branch into `develop` and keep working on it.
      # HEAD survives as the LAST resort (that is the base-branch case, where it is the right
      # answer), but it never outranks a candidate that still has committed delta against HEAD.
      if ($head -and $mb -eq $head) { $headResolved = $true; continue }
      $d = (git -C $dir rev-list --count "$mb..HEAD" 2>$null)
      # A failed count must never score as the nearest candidate and win the minimum.
      $d = if ($d) { [int]([string]$d).Trim() } else { [int]::MaxValue }
      if ($d -lt $bestDist) { $bestDist = $d; $best = $mb }
    }
    if ($best) { return $best }
    if ($headResolved) { return $head }
  }

  # Among arbitrary refs the answer is the FARTHEST common ancestor, not the nearest: a branch cut
  # from the middle of this slice (a `wip` backup, a worktree, an upstream pushed under another
  # name) is always nearer than the real base, and picking it drops the slice's earlier commits
  # from the range while still reporting exit 0. `merge-base --octopus` gives that ancestor for the
  # whole set in a single call, which also keeps a repo with hundreds of refs from paying three git
  # processes per ref on every turn.
  $others = Get-OtherRefs
  if (-not $others) { return $null }
  $mb = (git -C $dir merge-base --octopus @($others) HEAD 2>$null)
  if ($mb) { return ([string]$mb).Trim() }

  # Unrelated histories make the octopus fail: fall back to the farthest pairwise merge-base.
  $best = $null
  $bestDist = -1
  foreach ($c in $others) {
    $m = (git -C $dir merge-base $c HEAD 2>$null)
    if (-not $m) { continue }
    $m = ([string]$m).Trim()
    $d = (git -C $dir rev-list --count "$m..HEAD" 2>$null)
    $d = if ($d) { [int]([string]$d).Trim() } else { -1 }
    if ($d -gt $bestDist) { $bestDist = $d; $best = $m }
  }
  return $best
}

# Untracked files are delta too, and `git diff` never shows them. The loop's own fix step orders
# writing a test that fails before the fix, and a brand-new test file is untracked by default:
# without counting it, the range comes back empty and the fix ships unreviewed.
#
# What counts is untracked *since the marker*, not "any untracked file at all": `git stash create`
# cannot capture untracked files, so `advance` can never consume them. Asking the absolute question
# leaves the range non-empty forever — the loop can then never close on "nothing new", and hands
# the reviewer the same stray files every turn. Hence the snapshot taken at `advance`.
function Get-UntrackedList {
  # A non-ASCII path gets mangled here in two separate ways, and both end the same: the path does
  # not exist on disk, its hash stays empty, and later edits to that file are invisible to the next
  # turn. In a Spanish-speaking codebase `ñandú.txt` is a routine filename. The decoding half is
  # handled once at the top of the script; what is left is git's own quoting:
  # `ls-files` C-quotes the name ("\303\261andu.txt") unless core.quotepath is off.
  $paths = @(git -C $dir -c core.quotepath=false ls-files --others --exclude-standard 2>$null |
             Where-Object { $_ })
  $out = @()
  foreach ($p in ($paths | Sort-Object)) {
    $full = Join-Path $dir $p
    $h = ""
    if (Test-Path -LiteralPath $full -PathType Leaf) {
      try { $h = (Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash } catch { $h = "" }
    }
    $out += ("{0}|{1}" -f $p, $h)                     # content too: an edited stray file is delta
  }
  return $out
}
function Test-NewUntracked($seen) {
  $now = Get-UntrackedList
  if (-not $now) { return $false }
  $set = @{}
  foreach ($e in @($seen)) { if ($e) { $set[[string]$e] = $true } }
  foreach ($e in $now) { if (-not $set.ContainsKey($e)) { return $true } }
  return $false
}

switch ($Action) {

  "get" {
    $sha = (Read-State)[$key]
    if ($sha) { Write-Output $sha }
    exit 0
  }

  "base" {
    # The base of the slice, for the trigger hook to DELEGATE base resolution to when its own
    # named-branch lookup (main/master/develop/origin-HEAD) comes up empty — a repo whose base is
    # `trunk`, `dev`, `release`. Same resolver as `range` (Get-SliceBase), so the hook stops being
    # the asymmetric half that goes silent on those repos and drops a declared slice close.
    # Same exit contract: a resolvable ref, or exit 2 + nothing when no base can be determined — so
    # the caller never reads "no base" as "nothing to review". Emits a commit (the merge-base), which
    # the hook uses only as a diff endpoint, never as a branch-name guard.
    $b = Get-SliceBase
    if (-not $b) { exit 2 }
    Write-Output $b
    exit 0
  }

  "range" {
    # A stored marker is only usable while its object still resolves: `git stash create` objects
    # are unreachable, so an aggressive `git gc` can prune one. Falling back to the slice base
    # means the default failure mode is reviewing too much, never too little.
    $state = Read-State
    $sha = $state[$key]
    $seen = $null
    if ($sha -and -not (Resolve-Commit $sha)) { $sha = $null }
    if ($sha) { $seen = $state["untracked:$branch"] }  # only meaningful while its marker lives
    # No marker: fall back to the base of the slice. When not even that resolves (a repo with a
    # single branch and nothing to compare against), say so — the caller reviews the working tree
    # or the branch range, but never gets a confident range that hides commits.
    if (-not $sha) { $sha = Get-SliceBase }
    if (-not $sha) { exit 2 }
    # Nothing new since the marker: emit nothing, so the caller closes without a review run
    # instead of making up a range.
    git -C $dir diff --quiet $sha 2>$null
    if (($LASTEXITCODE -eq 0) -and -not (Test-NewUntracked $seen)) { exit 0 }
    Write-Output $sha
    exit 0
  }

  "advance" {
    # `git stash create` builds a commit object from the current tree WITHOUT committing,
    # switching branches or touching the working tree — and it includes uncommitted changes.
    # It prints nothing when there is nothing to stash, hence the HEAD fallback.
    #
    # It can also FAIL and still print: during an unresolved merge it writes "<file>: needs
    # merge" to STDOUT and exits non-zero. Both the exit code and the shape of the output are
    # checked, or that line gets persisted as the marker and the branch's incrementality is
    # silently lost.
    $out = (git -C $dir stash create 2>$null)
    $code = $LASTEXITCODE
    $sha = $null
    if ($code -eq 0 -and $out) {
      $cand = ((@($out) | Where-Object { $_ } | Select-Object -Last 1) | Out-String).Trim()
      if ($cand -match '^[0-9a-f]{40}$') { $sha = $cand }
    }
    if (-not $sha) {
      $h = (git -C $dir rev-parse HEAD 2>$null)
      if ($h) { $h = ([string]$h).Trim() }
      if ($h -match '^[0-9a-f]{40}$') { $sha = $h }
    }
    if (-not $sha) { exit 2 }                         # repo with no commits yet

    $state = Read-State
    # An unreadable state parsed to @{}: overwriting it now would erase every OTHER branch's
    # marker/untracked keys and the hook's dedupe entries with no trace. Move it aside first, so the
    # keys stay recoverable — the same `.bad` quarantine the trigger hook does before it writes.
    # If the move itself fails (most likely the file held open mid-write, since that write is not
    # atomic), leave the file ALONE and skip persisting rather than clobber what could not be backed
    # up: not advancing means the next turn reviews too much, which is the safe direction. The marker
    # is still printed so the caller sees the cut point.
    $writable = $true
    if ($script:stateCorrupt -and (Test-Path -LiteralPath $statePath)) {
      try { Move-Item -LiteralPath $statePath -Destination "$statePath.bad" -Force -ErrorAction Stop }
      catch { $writable = $false }
    }
    $state[$key] = $sha
    # The marker's commit object cannot hold untracked files, so they are recorded beside it.
    # Without this, every later turn would see them as new delta forever.
    $state["untracked:$branch"] = @(Get-UntrackedList)
    if ($writable) {
      # UTF-8 without BOM, written the same way by every PowerShell edition — see Read-State.
      $json = ([pscustomobject]$state) | ConvertTo-Json
      [IO.File]::WriteAllText($statePath, $json, [Text.UTF8Encoding]::new($false))
    }
    Write-Output $sha
    exit 0
  }
}
