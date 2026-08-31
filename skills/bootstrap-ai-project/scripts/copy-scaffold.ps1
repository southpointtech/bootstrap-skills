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
# bootstrap that noise was 2 of 6 apparent differences. Text is read only to compare, never
# to write, so a binary file is safe here — it just fails both checks and counts as different.
function Test-SameContent([string]$a, [string]$b) {
  $ba = [IO.File]::ReadAllBytes($a)
  $bb = [IO.File]::ReadAllBytes($b)
  if ($ba.Length -eq $bb.Length) {
    $identical = $true
    for ($i = 0; $i -lt $ba.Length; $i++) { if ($ba[$i] -ne $bb[$i]) { $identical = $false; break } }
    if ($identical) { return $true }
  }
  try {
    return (([IO.File]::ReadAllText($a) -replace "`r`n", "`n") -eq ([IO.File]::ReadAllText($b) -replace "`r`n", "`n"))
  } catch { return $false }
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
      # A backup from an earlier run is never replaced: the oldest copy is the real original,
      # and a second run would otherwise "back up" the scaffold the first one just landed.
      if (-not [IO.File]::Exists($bak)) {
        [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($bak)) | Out-Null
        [IO.File]::Copy($dest, $bak, $false)
      }
      [void]$overwritten.Add([ordered]@{
        file   = ($rel -replace '\\', '/')
        backup = ((Join-Path ".bootstrap-backup" $rel) -replace '\\', '/')
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
