# Deploya las skills de este repo a ~/.claude/skills/ (instalación que usa Claude Code).
# Borra la versión instalada primero para no dejar archivos huérfanos de versiones previas.
$ErrorActionPreference = "Stop"
$repoSkills = Join-Path $PSScriptRoot "..\skills"
$installed = Join-Path $env:USERPROFILE ".claude\skills"

foreach ($skill in (Get-ChildItem $repoSkills -Directory)) {
    $dest = Join-Path $installed $skill.Name
    if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
    Copy-Item $skill.FullName $dest -Recurse
    $n = @(Get-ChildItem $dest -Recurse -File -Force).Count
    Write-Host "Deployada: $($skill.Name) ($n archivos)"
}
Write-Host "Listo. Las skills quedan activas en la próxima sesión de Claude Code."
