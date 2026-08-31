# tests/copy-scaffold.tests.ps1 — runner sin Pester. Correr: pwsh -NoProfile -File tests/copy-scaffold.tests.ps1
# Fixtures determinísticos (directorios temporales) para copy-scaffold.ps1: la copia del Step 2
# debe mergear en directorios preexistentes del proyecto (regresión docs/docs del self-bootstrap 2026-06-23).
$ErrorActionPreference = "Stop"
$repo    = Split-Path $PSScriptRoot -Parent
$scriptP = Join-Path $repo "skills/bootstrap-personal-project/scripts/copy-scaffold.ps1"
$scriptS = Join-Path $repo "skills/bootstrap-southpoint-project/scripts/copy-scaffold.ps1"
$scriptA = Join-Path $repo "skills/bootstrap-ai-project/scripts/copy-scaffold.ps1"
$skillP  = Join-Path $repo "skills/bootstrap-personal-project"
$script:failures = 0

function Assert($cond, $msg) {
  if ($cond) { Write-Host "ok:   $msg" } else { Write-Host "FAIL: $msg"; $script:failures++ }
}
function New-Proj([string]$suffix = "") {
  $t = Join-Path ([IO.Path]::GetTempPath()) ("cs-test-" + [guid]::NewGuid().ToString('N') + $suffix)
  [IO.Directory]::CreateDirectory($t) | Out-Null
  return $t
}
function Invoke-Copy($proj) {
  & pwsh -NoProfile -File $scriptP -SkillDir $skillP -ProjectDir $proj | Out-Null
  Assert ($LASTEXITCODE -eq 0) "copy-scaffold salió con exit code 0"
}

# Workspaces huérfanos de corridas anteriores abortadas (regla del repo: sin rastros de testeo)
Get-ChildItem ([IO.Path]::GetTempPath()) -Directory -Filter "cs-test-*" | Remove-Item -Recurse -Force

# 1. Destino vacío: aterriza completo, sin anidamientos, gitignore.txt renombrado
$t = New-Proj
Invoke-Copy $t
Assert ((Get-ChildItem "$t\.agents\skills" -Directory).Count -eq 11) "destino vacío: .agents/skills tiene 11 skills"
Assert (-not (Test-Path "$t\.agents\.agents") -and -not (Test-Path "$t\.claude\.claude")) "destino vacío: sin .agents/.agents ni .claude/.claude"
Assert ((Test-Path "$t\.gitignore") -and -not (Test-Path "$t\gitignore.txt")) "gitignore.txt aterriza como .gitignore"
$srcGi = Get-Content "$skillP\assets\scaffold\gitignore.txt" -Raw
$dstGi = Get-Content "$t\.gitignore" -Raw
Assert ($srcGi -eq $dstGi) ".gitignore con contenido idéntico al de assets"
$srcCount = (Get-ChildItem "$skillP\assets\scaffold" -Recurse -File -Force).Count
$dstCount = (Get-ChildItem $t -Recurse -File -Force).Count
Assert ($srcCount -eq $dstCount) "misma cantidad de archivos que el scaffold ($srcCount)"
Remove-Item -Recurse -Force $t

# 2. Regresión principal: docs/ y docs/agents/ preexistentes -> merge, no anidamiento
$t = New-Proj
New-Item -ItemType Directory -Path "$t\docs\agents" -Force | Out-Null
"contenido propio" | Set-Content "$t\docs\HISTORIA.md" -Encoding UTF8
"nota propia"      | Set-Content "$t\docs\agents\nota-propia.md" -Encoding UTF8
Invoke-Copy $t
Assert (-not (Test-Path "$t\docs\docs")) "docs/ preexistente: NO se anida docs/docs"
Assert (-not (Test-Path "$t\docs\agents\agents")) "docs/agents/ preexistente: NO se anida agents/agents"
Assert ((Get-Content "$t\docs\HISTORIA.md" -Raw).Trim() -eq "contenido propio") "archivo propio en docs/ queda intacto"
Assert ((Get-Content "$t\docs\agents\nota-propia.md" -Raw).Trim() -eq "nota propia") "archivo propio en docs/agents/ queda intacto"
Assert (Test-Path "$t\docs\ai-workflow\AI_DEVELOPMENT_WORKFLOW.md") "el contenido del scaffold se mergeó en docs/"
Assert (Test-Path "$t\docs\agents\issue-tracker.md") "el contenido del scaffold se mergeó en docs/agents/"
Remove-Item -Recurse -Force $t

# 3. Dot-dirs preexistentes (.claude/) también mergean sin anidar
$t = New-Proj
New-Item -ItemType Directory -Path "$t\.claude" -Force | Out-Null
"{}" | Set-Content "$t\.claude\settings.local.json" -Encoding UTF8
Invoke-Copy $t
Assert (-not (Test-Path "$t\.claude\.claude")) ".claude/ preexistente: NO se anida .claude/.claude"
Assert (Test-Path "$t\.claude\settings.local.json") "archivo propio en .claude/ queda intacto"
Assert (Test-Path "$t\.claude\hooks\review-loop-trigger.ps1") "el contenido del scaffold se mergeó en .claude/"
Remove-Item -Recurse -Force $t

# 4. Conflicto de archivo: el scaffold pisa (semántica del Step 2; en adopción el original ya está stasheado)
$t = New-Proj
"claude viejo" | Set-Content "$t\CLAUDE.md" -Encoding UTF8
(Get-Item "$t\CLAUDE.md").Attributes = 'ReadOnly'
Invoke-Copy $t
Assert ((Get-Content "$t\CLAUDE.md" -Raw) -match "AI Operating Rules") "CLAUDE.md preexistente (incluso read-only) es reemplazado por el canónico"
Remove-Item -Recurse -Force $t

# 5. Paths con corchetes (wildcards de PowerShell) se tratan como literales
$t = New-Proj "[v2]"
Invoke-Copy $t
Assert (Test-Path -LiteralPath "$t\CLAUDE.md") "proyecto con corchetes en el path: la copia aterriza igual"
Assert (Test-Path -LiteralPath "$t\.gitignore") "proyecto con corchetes: .gitignore presente"
Remove-Item -LiteralPath $t -Recurse -Force

# --- Respaldo de archivos propios (pisar no es perder) -------------------------------
# El script pisa (test 4), pero antes respalda todo archivo propio que difiere y lo declara
# en un reporte JSON. Regresión: el bootstrap de Profitability App (2026-08-31) se llevó
# puestas las reglas ~$* y SESSION_HANDOFF.md del .gitignore del proyecto, sin avisar.
function Invoke-CopyJson($proj) {
  $out = & pwsh -NoProfile -File $scriptP -SkillDir $skillP -ProjectDir $proj
  Assert ($LASTEXITCODE -eq 0) "copy-scaffold salió con exit code 0"
  return ($out | ConvertFrom-Json)
}

# 6. Archivo propio que difiere: se pisa, pero queda respaldado y declarado
$t = New-Proj
"reglas propias del proyecto" | Set-Content "$t\.gitignore" -Encoding UTF8
$r = Invoke-CopyJson $t
Assert ((Get-Content "$t\.bootstrap-backup\.gitignore" -Raw).Trim() -eq "reglas propias del proyecto") "el archivo propio pisado queda respaldado con su contenido original"
$gi = @($r.overwritten | Where-Object { $_.file -eq ".gitignore" })
Assert ($gi.Count -eq 1) "el reporte declara .gitignore como overwritten"
Assert ($gi[0].backup -eq ".bootstrap-backup/.gitignore") "el reporte dice dónde quedó el respaldo"
Assert ((Get-Content "$t\.gitignore" -Raw) -eq (Get-Content "$skillP\assets\scaffold\gitignore.txt" -Raw)) "el destino quedó con el contenido del scaffold"
Remove-Item -Recurse -Force $t

# 7. Respeta la estructura de paths dentro del respaldo
$t = New-Proj
New-Item -ItemType Directory -Path "$t\docs\agents" -Force | Out-Null
"tracker propio" | Set-Content "$t\docs\agents\issue-tracker.md" -Encoding UTF8
$r = Invoke-CopyJson $t
Assert ((Get-Content "$t\.bootstrap-backup\docs\agents\issue-tracker.md" -Raw).Trim() -eq "tracker propio") "el respaldo respeta la estructura de directorios"
Assert (@($r.overwritten | Where-Object { $_.file -eq "docs/agents/issue-tracker.md" }).Count -eq 1) "el reporte usa separador / en los paths"
Remove-Item -Recurse -Force $t

# 8. Diferencia SOLO de fin de línea: no es un archivo pisado (bug autocrlf)
# En Profitability App, 2 de 6 "diferencias" eran CRLF vs LF con contenido idéntico.
$t = New-Proj
$canon = Get-Content "$skillP\assets\scaffold\docs\agents\triage-labels.md" -Raw
New-Item -ItemType Directory -Path "$t\docs\agents" -Force | Out-Null
[IO.File]::WriteAllText("$t\docs\agents\triage-labels.md", ($canon -replace "`r`n", "`n"))
$r = Invoke-CopyJson $t
Assert (@($r.overwritten | Where-Object { $_.file -like "*triage-labels*" }).Count -eq 0) "diferencia solo de EOL NO se reporta como pisada"
Assert (-not (Test-Path "$t\.bootstrap-backup\docs\agents\triage-labels.md")) "diferencia solo de EOL NO genera respaldo"
Remove-Item -Recurse -Force $t

# 9. Destino vacío: no se crea el directorio de respaldo ni se declara nada
$t = New-Proj
$r = Invoke-CopyJson $t
Assert (-not (Test-Path "$t\.bootstrap-backup")) "destino vacío: no se crea .bootstrap-backup/"
Assert (@($r.overwritten).Count -eq 0) "destino vacío: nada declarado como pisado"
Assert (@($r.created).Count -eq (Get-ChildItem "$skillP\assets\scaffold" -Recurse -File -Force).Count) "destino vacío: todos los archivos se declaran como creados"
Remove-Item -Recurse -Force $t

# 10. Segunda corrida sobre un archivo editado: el respaldo original NO se pisa
# Ojo con el escenario: si entre las dos corridas no se toca nada, el destino ya es idéntico
# al scaffold y la segunda corrida no respalda nada — el test pasaría sin ejercitar el guard.
# Hay que editar el archivo en el medio para que la segunda corrida vuelva a querer respaldar.
$t = New-Proj
"el original de verdad" | Set-Content "$t\.gitignore" -Encoding UTF8
Invoke-CopyJson $t | Out-Null
"edicion posterior al bootstrap" | Set-Content "$t\.gitignore" -Encoding UTF8
$r = Invoke-CopyJson $t
Assert (@($r.overwritten | Where-Object { $_.file -eq ".gitignore" }).Count -eq 1) "segunda corrida: el archivo editado se vuelve a declarar pisado"
Assert ((Get-Content "$t\.bootstrap-backup\.gitignore" -Raw).Trim() -eq "el original de verdad") "segunda corrida: el respaldo conserva el original, no la edición posterior"
Remove-Item -Recurse -Force $t

# 11. Un archivo propio que el scaffold no toca queda intacto y no se respalda
$t = New-Proj
"nota" | Set-Content "$t\NOTAS.md" -Encoding UTF8
$r = Invoke-CopyJson $t
Assert ((Get-Content "$t\NOTAS.md" -Raw).Trim() -eq "nota") "archivo ajeno al scaffold queda intacto"
Assert (-not (Test-Path "$t\.bootstrap-backup\NOTAS.md")) "archivo ajeno al scaffold no se respalda"
Remove-Item -Recurse -Force $t

# 12. Espejado byte-idéntico entre las TRES skills
$hp = (Get-FileHash $scriptP -Algorithm SHA256).Hash
$hs = (Get-FileHash $scriptS -Algorithm SHA256).Hash
$ha = (Get-FileHash $scriptA -Algorithm SHA256).Hash
Assert ($hp -eq $hs) "copy-scaffold.ps1 espejado byte-idéntico (personal == southpoint)"
Assert ($hp -eq $ha) "copy-scaffold.ps1 espejado byte-idéntico (personal == ai-project)"

if ($script:failures -eq 0) { Write-Host "TODOS LOS TESTS PASARON"; exit 0 }
else { Write-Host "$($script:failures) test(s) FALLARON"; exit 1 }
