# retire-session-handoff.ps1 — removes the inherited SESSION_HANDOFF.md (project root and docs/) once the
# agent has migrated its latest block to the ephemeral handoff in the OS temp dir. The migration is the
# agent's job and happens BEFORE this runs; this script only takes the files out.
#
# A tracked file leaves with `git rm` (staged, never committed: the user reviews and commits), backed up
# first when it has uncommitted edits; an untracked or ignored one is moved to .bootstrap-backup\. A file
# whose staged version differs from both HEAD and the one on disk makes the whole run refuse, touching
# nothing. -Check runs only that refusal check and changes nothing: the agent runs it before migrating,
# so a refusal never comes after the migration already rotated the handoff's `.prev`.
# Without -Check, prints JSON on stdout:
# { removed[], backedUp[{file, backup}] }. With no handoff files it prints both empty and exits 0.
# Usage: pwsh -NoProfile -File retire-session-handoff.ps1 -ProjectDir <project root> [-Check]
param(
  [Parameter(Mandatory)][string]$ProjectDir,
  [switch]$Check
)
$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $ProjectDir -PathType Container)) { throw "Project dir not found: $ProjectDir" }
$ProjectDir = (Resolve-Path -LiteralPath $ProjectDir).Path

$backupRoot = Join-Path $ProjectDir ".bootstrap-backup"
$removed  = [Collections.ArrayList]::new()
$backedUp = [Collections.ArrayList]::new()

# Copies the file into .bootstrap-backup\ under the same relative path, numbered `.2`, `.3` when an
# earlier backup already sits there — the same scheme as copy-scaffold.ps1 (ADR-0007): the oldest copy
# is never replaced, and the reported `backup` names the copy that actually holds this file.
function Save-Backup([string]$rel) {
  $src = Join-Path $ProjectDir $rel
  $bak = Join-Path $backupRoot $rel
  if ([IO.File]::Exists($bak)) {
    $n = 2
    while ([IO.File]::Exists("$bak.$n")) { $n++ }
    $bak = "$bak.$n"
  }
  [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($bak)) | Out-Null
  [IO.File]::Copy($src, $bak, $false)
  [void]$backedUp.Add([ordered]@{
    file   = $rel
    backup = ([IO.Path]::GetRelativePath($ProjectDir, $bak) -replace '\\', '/')
  })
}

$candidates = @("SESSION_HANDOFF.md", "docs/SESSION_HANDOFF.md") |
  Where-Object { [IO.File]::Exists((Join-Path $ProjectDir $_)) }
$tracked = @{}
foreach ($rel in $candidates) {
  & git -C $ProjectDir ls-files --error-unmatch -- $rel 2>$null | Out-Null
  $tracked[$rel] = ($LASTEXITCODE -eq 0)
}

# A staged version that differs from both HEAD and the file on disk lives only in the index: the backup
# below copies the disk, and `git rm -f` would drop the index. Refuse before touching anything, for both
# files, so a refusal never leaves a retirement half done.
foreach ($rel in $candidates) {
  if (-not $tracked[$rel]) { continue }
  & git -C $ProjectDir diff --quiet -- $rel            # index vs disk
  $vsDisk = $LASTEXITCODE
  & git -C $ProjectDir diff --cached --quiet -- $rel   # HEAD vs index
  $vsHead = $LASTEXITCODE
  if ($vsDisk -gt 1 -or $vsHead -gt 1) { throw "git diff failed for $rel" }
  if ($vsDisk -eq 1 -and $vsHead -eq 1) {
    throw "$rel has staged changes that differ from the file on disk; commit, unstage or restore them first. Nothing was retired."
  }
}
if ($Check) { exit 0 }

foreach ($rel in $candidates) {
  if ($tracked[$rel]) {
    # Tracked, but with content HEAD does not have (edited, or staged and never committed): `git rm`
    # refuses it, and `git rm -f` alone would lose exactly the part nobody committed. Back it up first;
    # the check above guarantees that no version lives only in the index: each is in HEAD or on disk.
    $dirty = @(& git -C $ProjectDir status --porcelain -- $rel)
    if ($LASTEXITCODE -ne 0) { throw "git status failed for $rel" }
    if ($dirty.Count -gt 0) {
      Save-Backup $rel
      & git -C $ProjectDir rm -q -f -- $rel | Out-Null
    } else {
      & git -C $ProjectDir rm -q -- $rel | Out-Null
    }
    if ($LASTEXITCODE -ne 0) { throw "git rm failed for $rel" }
    [void]$removed.Add($rel)
  } else {
    # Untracked or ignored (or no git repo at all): git cannot bring it back, so it is moved aside.
    Save-Backup $rel
    [IO.File]::Delete((Join-Path $ProjectDir $rel))
  }
}

[ordered]@{
  removed  = @($removed)
  backedUp = @($backedUp)
} | ConvertTo-Json -Depth 5
