# copy-scaffold.ps1 — copies assets\scaffold\ into the project file by file, merging into
# pre-existing directories. Never copies a directory as a unit: Copy-Item -Recurse onto an
# existing destination nests (docs -> docs\docs, .agents -> .agents\.agents) instead of merging.
# Paths are always literal (-LiteralPath / .NET APIs): a project with brackets in its name
# (app[v2]) breaks cmdlets that interpret wildcards.
# gitignore.txt lands as .gitignore (named that way in assets so the skill repo does not
# treat it as its own ignore file). This mapping must match tools/gen-manifest.ps1:
# the paths landing here are the keys of the .bootstrap-manifest.json consumed by upgrade-bootstrap.
#
# The scaffold still wins every conflict (adoption mode depends on landing the canonical
# CLAUDE.md), but a project file it overwrites is copied to .bootstrap-backup\ first and
# declared on stdout as JSON: { created[], overwritten[{file, backup}] }. Overwriting is not
# losing, and the caller no longer has to hash the tree itself to find out what it cost.
# Usage: pwsh -NoProfile -File copy-scaffold.ps1 -SkillDir <this skill's dir> -ProjectDir <project root>
param(
  [Parameter(Mandatory)][string]$SkillDir,
  [Parameter(Mandatory)][string]$ProjectDir
)
$ErrorActionPreference = "Stop"

$scaffold = Join-Path $SkillDir "assets\scaffold"
if (-not (Test-Path -LiteralPath $scaffold -PathType Container))   { throw "Scaffold not found: $scaffold" }
if (-not (Test-Path -LiteralPath $ProjectDir -PathType Container)) { throw "Project dir not found: $ProjectDir" }
$scaffold   = (Resolve-Path -LiteralPath $scaffold).Path
$ProjectDir = (Resolve-Path -LiteralPath $ProjectDir).Path
$backupRoot = Join-Path $ProjectDir ".bootstrap-backup"

# Same bytes, or same bytes once CRLF is normalized to LF. A file that differs only in line
# endings is core.autocrlf noise, not a change worth backing up: in the Profitability App
# bootstrap that noise was 2 of 6 apparent differences.
# The normalization is done on the BYTES, never by decoding to text. Decoding compares equal in
# two cases that are real changes: a UTF-8 BOM is dropped by the decoder, and any two invalid
# bytes both decode to U+FFFD — either would be overwritten with no backup and no report entry,
# which is the exact silent loss this backup exists to prevent.
function Test-BytesEqual([byte[]]$x, [byte[]]$y) {
  if ($x.Length -ne $y.Length) { return $false }
  for ($i = 0; $i -lt $x.Length; $i++) { if ($x[$i] -ne $y[$i]) { return $false } }
  return $true
}
function Remove-CrBeforeLf([byte[]]$b) {
  $out = [Collections.Generic.List[byte]]::new($b.Length)
  for ($i = 0; $i -lt $b.Length; $i++) {
    if ($b[$i] -eq 13 -and ($i + 1) -lt $b.Length -and $b[$i + 1] -eq 10) { continue }
    $out.Add($b[$i])
  }
  return $out.ToArray()
}
function Test-SameContent([string]$a, [string]$b) {
  $ba = [IO.File]::ReadAllBytes($a)
  $bb = [IO.File]::ReadAllBytes($b)
  if (Test-BytesEqual $ba $bb) { return $true }
  return (Test-BytesEqual (Remove-CrBeforeLf $ba) (Remove-CrBeforeLf $bb))
}

$created     = [Collections.ArrayList]::new()
$overwritten = [Collections.ArrayList]::new()

Get-ChildItem -LiteralPath $scaffold -Recurse -File -Force | ForEach-Object {
  $rel = [IO.Path]::GetRelativePath($scaffold, $_.FullName)
  if ($rel -eq "gitignore.txt") { $rel = ".gitignore" }
  $dest = Join-Path $ProjectDir $rel
  [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($dest)) | Out-Null

  if ([IO.File]::Exists($dest)) {
    if (-not (Test-SameContent $dest $_.FullName)) {
      $bak = Join-Path $backupRoot $rel
      # A backup from an earlier run is never replaced: the oldest copy is the real original.
      # But the file being overwritten right now cannot be dropped either — on a second run it is
      # whatever the project changed since (a .gitignore merged during adoption, say) — so it goes
      # alongside as `.2`, `.3`, and the reported `backup` names the copy that actually holds it.
      # Reporting the older path here would promise a backup that does not contain what was lost.
      if ([IO.File]::Exists($bak)) {
        $n = 2
        while ([IO.File]::Exists("$bak.$n")) { $n++ }
        $bak = "$bak.$n"
      }
      [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($bak)) | Out-Null
      [IO.File]::Copy($dest, $bak, $false)
      [void]$overwritten.Add([ordered]@{
        file   = ($rel -replace '\\', '/')
        backup = ([IO.Path]::GetRelativePath($ProjectDir, $bak) -replace '\\', '/')
      })
    }
  } else {
    [void]$created.Add(($rel -replace '\\', '/'))
  }

  # File.Copy with overwrite cannot clobber read-only/hidden destinations (Copy-Item -Force could)
  if ([IO.File]::Exists($dest)) { [IO.File]::SetAttributes($dest, 'Normal') }
  [IO.File]::Copy($_.FullName, $dest, $true)
}

[ordered]@{
  created     = @($created)
  overwritten = @($overwritten)
} | ConvertTo-Json -Depth 5
