# tests/copy-scaffold.tests.ps1 — runner sin Pester. Correr: pwsh -NoProfile -File tests/copy-scaffold.tests.ps1
# Fixtures determinísticos (directorios temporales) para copy-scaffold.ps1: la copia del Step 2
# debe mergear en directorios preexistentes del proyecto (regresión docs/docs del self-bootstrap 2026-06-23).
$ErrorActionPreference = "Stop"
$repo    = Split-Path $PSScriptRoot -Parent
$scriptP = Join-Path $repo "skills/bootstrap-personal-project/scripts/copy-scaffold.ps1"
$scriptS = Join-Path $repo "skills/bootstrap-southpoint-project/scripts/copy-scaffold.ps1"
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
Assert ((Get-ChildItem "$t\.agents\skills" -Directory).Count -eq 10) "destino vacío: .agents/skills tiene 10 skills"
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
Invoke-Copy $t
Assert ((Get-Content "$t\CLAUDE.md" -Raw) -match "AI Operating Rules") "CLAUDE.md preexistente es reemplazado por el canónico"
Remove-Item -Recurse -Force $t

# 5. Paths con corchetes (wildcards de PowerShell) se tratan como literales
$t = New-Proj "[v2]"
Invoke-Copy $t
Assert (Test-Path -LiteralPath "$t\CLAUDE.md") "proyecto con corchetes en el path: la copia aterriza igual"
Assert (Test-Path -LiteralPath "$t\.gitignore") "proyecto con corchetes: .gitignore presente"
Remove-Item -LiteralPath $t -Recurse -Force

# 6. Espejado byte-idéntico entre las dos skills
$hp = (Get-FileHash $scriptP -Algorithm SHA256).Hash
$hs = (Get-FileHash $scriptS -Algorithm SHA256).Hash
Assert ($hp -eq $hs) "copy-scaffold.ps1 espejado byte-idéntico (personal == southpoint)"

if ($script:failures -eq 0) { Write-Host "TODOS LOS TESTS PASARON"; exit 0 }
else { Write-Host "$($script:failures) test(s) FALLARON"; exit 1 }
