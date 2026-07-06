# install.ps1 — installs the skills into ~/.claude/skills (removing previous versions first,
# so no orphan files survive from older versions).
$ErrorActionPreference = "Stop"
$src  = Join-Path $PSScriptRoot "skills"
$dest = Join-Path $HOME ".claude" "skills"
if (-not (Test-Path $src)) { throw "skills/ directory not found next to install.ps1" }
[IO.Directory]::CreateDirectory($dest) | Out-Null
foreach ($skill in (Get-ChildItem $src -Directory)) {
    $target = Join-Path $dest $skill.Name
    if (Test-Path $target) { Remove-Item $target -Recurse -Force }
    Copy-Item $skill.FullName $target -Recurse
    $n = @(Get-ChildItem $target -Recurse -File -Force).Count
    Write-Host "Installed: $($skill.Name) ($n files)"
}
Write-Host "Done. The skills become active in your next Claude Code session."
