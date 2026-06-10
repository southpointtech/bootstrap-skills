# Deploya las skills de este repo a ~/.claude/skills/ (instalación que usa Claude Code).
# Borra la versión instalada primero para no dejar archivos huérfanos de versiones previas.
$ErrorActionPreference = "Stop"
$repoSkills = Join-Path $PSScriptRoot "..\skills"
$installed = Join-Path $env:USERPROFILE ".claude\skills"

# Regenerar el manifest canónico de cada skill bootstrap antes de deployar,
# para que el scaffold instalado siempre lleve hashes actualizados.
foreach ($bs in (Get-ChildItem $repoSkills -Directory | Where-Object Name -like "bootstrap-*-project")) {
    & (Join-Path $PSScriptRoot "gen-manifest.ps1") -SkillDir $bs.FullName
}

foreach ($skill in (Get-ChildItem $repoSkills -Directory)) {
    $dest = Join-Path $installed $skill.Name
    if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
    Copy-Item $skill.FullName $dest -Recurse
    $n = @(Get-ChildItem $dest -Recurse -File -Force).Count
    Write-Host "Deployada: $($skill.Name) ($n archivos)"
}
Write-Host "Listo. Las skills quedan activas en la próxima sesión de Claude Code."
