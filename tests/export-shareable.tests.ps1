# tests/export-shareable.tests.ps1 — runner sin Pester. Correr: pwsh -NoProfile -File tests/export-shareable.tests.ps1
# El export al repo público debe: copiar limpio las 2 skills + README + install.ps1,
# y abortar (exit != 0) si el árbol exportado contiene un marcador de fuga.
$ErrorActionPreference = "Stop"
$repo   = Split-Path $PSScriptRoot -Parent
$script = Join-Path $repo "tools/export-shareable.ps1"
$script:failures = 0
. (Join-Path $PSScriptRoot "lib\temp-workspace.ps1")
# La recolección de huérfanos de esta suite era un `Remove-Item` por glob INCONDICIONAL sobre la raíz
# de %TEMP%: le borraba los fixtures en pleno uso a cualquier corrida concurrente, y en este repo las
# corridas concurrentes son la norma (el review-loop lanza reviewers en paralelo). New-TestRunRoot
# recolecta por edad y solo lo que tiene más de un día.
$script:runRoot = New-TestRunRoot "export-test"
trap { Remove-TestRunRoot $script:runRoot; break }

function Assert($cond, $msg) {
  if ($cond) { Write-Host "ok:   $msg" } else { Write-Host "FAIL: $msg"; $script:failures++ }
}
function NewClone {
  $d = New-TestWorkspace $script:runRoot "export-test"
  git -C $d init -b main --quiet
  $d
}

# 1. Happy path: estructura completa en el clon
$t = NewClone
& pwsh -NoProfile -File $script -PublicRepoDir $t | Out-Null
Assert ($LASTEXITCODE -eq 0) "export happy: exit 0"
Assert (Test-Path "$t\README.md") "export: README.md presente"
Assert (Test-Path "$t\install.ps1") "export: install.ps1 presente"
Assert (Test-Path "$t\skills\bootstrap-ai-project\SKILL.md") "export: bootstrap-ai-project presente"
Assert (Test-Path "$t\skills\upgrade-bootstrap\SKILL.md") "export: upgrade-bootstrap presente"
$manifest = Get-Content "$t\skills\bootstrap-ai-project\assets\scaffold\.bootstrap-manifest.json" -Raw | ConvertFrom-Json
Assert ($manifest.generatedFrom -eq "bootstrap-ai-project") "export: manifest generatedFrom correcto"

# 2. Re-export sobre clon sucio: borra huérfanos dentro de skills/
"orphan" | Set-Content "$t\skills\bootstrap-ai-project\HUERFANO.txt"
& pwsh -NoProfile -File $script -PublicRepoDir $t | Out-Null
Assert ($LASTEXITCODE -eq 0) "re-export: exit 0"
Assert (-not (Test-Path "$t\skills\bootstrap-ai-project\HUERFANO.txt")) "re-export: huérfano eliminado (copia limpia)"
Remove-Item -Recurse -Force $t

# 3. Gate anti-fuga: marcador inyectado en el payload -> aborta
$t2 = NewClone
$leakSrc = Join-Path $repo "skills\bootstrap-ai-project\LEAK-TEST.md"
"contact MartinDele703 for details" | Set-Content $leakSrc
try {
  & pwsh -NoProfile -File $script -PublicRepoDir $t2 2>&1 | Out-Null
  Assert ($LASTEXITCODE -ne 0) "gate: export con marcador inyectado aborta (exit != 0)"
} finally {
  Remove-Item $leakSrc -Force
}
Remove-Item -Recurse -Force $t2

# 4. No es un clon git -> aborta
# Sin NewClone a propósito: este caso necesita el directorio SIN `git init`.
$t3 = New-TestWorkspace $script:runRoot "export-test"
& pwsh -NoProfile -File $script -PublicRepoDir $t3 2>&1 | Out-Null
Assert ($LASTEXITCODE -ne 0) "PublicRepoDir sin .git: aborta"
Remove-Item -Recurse -Force $t3

Remove-TestRunRoot $script:runRoot

if ($script:failures -eq 0) { Write-Host "TODOS LOS TESTS PASARON"; exit 0 }
else { Write-Host "$($script:failures) test(s) FALLARON"; exit 1 }
