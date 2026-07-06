# copy-scaffold.ps1 — copies assets\scaffold\ into the project file by file, merging into
# pre-existing directories. Never copies a directory as a unit: Copy-Item -Recurse onto an
# existing destination nests (docs -> docs\docs, .agents -> .agents\.agents) instead of merging.
# Paths are always literal (-LiteralPath / .NET APIs): a project with brackets in its name
# (app[v2]) breaks cmdlets that interpret wildcards.
# gitignore.txt lands as .gitignore (named that way in assets so the skill repo does not
# treat it as its own ignore file). This mapping must match tools/gen-manifest.ps1:
# the paths landing here are the keys of the .bootstrap-manifest.json consumed by upgrade-bootstrap.
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

Get-ChildItem -LiteralPath $scaffold -Recurse -File -Force | ForEach-Object {
  $rel = [IO.Path]::GetRelativePath($scaffold, $_.FullName)
  if ($rel -eq "gitignore.txt") { $rel = ".gitignore" }
  $dest = Join-Path $ProjectDir $rel
  [IO.Directory]::CreateDirectory((Split-Path $dest -Parent)) | Out-Null
  # File.Copy with overwrite cannot clobber read-only/hidden destinations (Copy-Item -Force could)
  if ([IO.File]::Exists($dest)) { [IO.File]::SetAttributes($dest, 'Normal') }
  [IO.File]::Copy($_.FullName, $dest, $true)
}
