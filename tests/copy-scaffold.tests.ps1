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
# Lee un archivo que solo existe si la feature anduvo. Con $ErrorActionPreference = "Stop" un
# Get-Content sobre un path ausente es error TERMINANTE: aborta la corrida entera en vez de sumar
# un FAIL, y los bloques siguientes no se ejecutan. Devolver $null deja que el Assert falle donde
# corresponde y la corrida siga.
function Get-IfAny([string]$path) {
  if (Test-Path -LiteralPath $path -PathType Leaf) { return (Get-Content -LiteralPath $path -Raw) }
  return $null
}
# Todos los workspaces de esta corrida cuelgan de un único directorio con PID + GUID. Antes se
# borraba `cs-test-*` de todo el TEMP compartido, lo que mataba los fixtures de cualquier corrida
# concurrente — pasó de verdad con los reviewers en paralelo del review-loop de este repo.
$script:runRoot = Join-Path ([IO.Path]::GetTempPath()) ("cs-run-$PID-" + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($script:runRoot) | Out-Null
function New-Proj([string]$suffix = "") {
  $t = Join-Path $script:runRoot ("cs-test-" + [guid]::NewGuid().ToString('N') + $suffix)
  [IO.Directory]::CreateDirectory($t) | Out-Null
  return $t
}
function Invoke-Copy($proj) {
  & pwsh -NoProfile -File $scriptP -SkillDir $skillP -ProjectDir $proj | Out-Null
  Assert ($LASTEXITCODE -eq 0) "copy-scaffold salió con exit code 0"
}

# 1. Destino vacío: aterriza completo, sin anidamientos, gitignore.txt renombrado
$t = New-Proj
Invoke-Copy $t
# Contra el scaffold, no contra un literal: un número acá envejece la próxima vez que entra una skill
$skillDirs = (Get-ChildItem "$skillP\assets\scaffold\.agents\skills" -Directory).Count
Assert ((Get-ChildItem "$t\.agents\skills" -Directory).Count -eq $skillDirs) "destino vacío: .agents/skills tiene las $skillDirs skills del scaffold"
$cmdFiles = (Get-ChildItem "$skillP\assets\scaffold\.claude\commands" -File).Count
Assert ((Get-ChildItem "$t\.claude\commands" -File).Count -eq $cmdFiles) "destino vacío: .claude/commands tiene los $cmdFiles comandos del scaffold"
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

# 4. Conflicto de archivo: el scaffold pisa (semántica deliberada del Step 2; el original queda
#    en .bootstrap-backup/, que es de donde el Step 0b lo toma)
$t = New-Proj
"claude viejo" | Set-Content "$t\CLAUDE.md" -Encoding UTF8
(Get-Item "$t\CLAUDE.md").Attributes = 'ReadOnly'
Invoke-Copy $t
Assert ((Get-Content "$t\CLAUDE.md" -Raw) -match "AI Operating Rules") "CLAUDE.md preexistente (incluso read-only) es reemplazado por el canónico"
Remove-Item -Recurse -Force $t

# 5. Paths con corchetes (wildcards de PowerShell) se tratan como literales
# Con un archivo propio en conflicto, para que la rama de respaldo también se ejercite con
# corchetes en el path y no solo la copia sobre destino vacío.
$t = New-Proj "[v2]"
"reglas propias" | Set-Content -LiteralPath "$t\.gitignore" -Encoding UTF8
Invoke-Copy $t
Assert (Test-Path -LiteralPath "$t\CLAUDE.md") "proyecto con corchetes en el path: la copia aterriza igual"
Assert (Test-Path -LiteralPath "$t\.gitignore") "proyecto con corchetes: .gitignore presente"
Assert ((Get-IfAny "$t\.bootstrap-backup\.gitignore").Trim() -eq "reglas propias") "proyecto con corchetes: el respaldo también funciona"
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
Assert ((Get-IfAny "$t\.bootstrap-backup\.gitignore").Trim() -eq "reglas propias del proyecto") "el archivo propio pisado queda respaldado con su contenido original"
$gi = @($r.overwritten | Where-Object { $_.file -eq ".gitignore" })
Assert ($gi.Count -eq 1) "el reporte declara .gitignore como overwritten"
Assert ($gi[0].backup -eq ".bootstrap-backup/.gitignore") "el reporte dice dónde quedó el respaldo"
Assert ((Get-Content "$t\.gitignore" -Raw) -eq (Get-Content "$skillP\assets\scaffold\gitignore.txt" -Raw)) "el destino quedó con el contenido del scaffold"
Assert (@($r.created | Where-Object { $_ -eq ".gitignore" }).Count -eq 0) "un archivo pisado NO se declara además como creado"
Remove-Item -Recurse -Force $t

# 7. Respeta la estructura de paths dentro del respaldo
$t = New-Proj
New-Item -ItemType Directory -Path "$t\docs\agents" -Force | Out-Null
"tracker propio" | Set-Content "$t\docs\agents\issue-tracker.md" -Encoding UTF8
$r = Invoke-CopyJson $t
Assert ((Get-IfAny "$t\.bootstrap-backup\docs\agents\issue-tracker.md").Trim() -eq "tracker propio") "el respaldo respeta la estructura de directorios"
$it = @($r.overwritten | Where-Object { $_.file -eq "docs/agents/issue-tracker.md" })
Assert ($it.Count -eq 1) "el reporte usa separador / en los paths"
# El campo `backup` es el contrato con el Step 0b: si se aplana al nombre suelto, apunta a un
# archivo inexistente y dos archivos con el mismo leaf name colisionan. El assert del bloque 6 no
# lo cubre porque .gitignore vive en la raíz, donde el path completo y el leaf coinciden.
Assert ($it[0].backup -eq ".bootstrap-backup/docs/agents/issue-tracker.md") "el reporte declara el backup con el subpath completo"
Assert (Test-Path -LiteralPath (Join-Path $t ($it[0].backup -replace '/', '\')) -PathType Leaf) "el backup declarado existe en disco"
Remove-Item -Recurse -Force $t

# 8. Diferencia SOLO de fin de línea: no es un archivo pisado (bug autocrlf)
# En Profitability App, 2 de 6 "diferencias" eran CRLF vs LF con contenido idéntico.
# El fixture escribe las DOS formas explícitamente en vez de derivarlas del checkout: si el repo
# se clona con autocrlf=false el árbol ya está en LF, el -replace sería no-op y el test pasaría
# igual con la normalización rota.
$t = New-Proj
$canonLf = ([IO.File]::ReadAllText("$skillP\assets\scaffold\docs\agents\triage-labels.md")) -replace "`r`n", "`n"
New-Item -ItemType Directory -Path "$t\docs\agents" -Force | Out-Null
[IO.File]::WriteAllText("$t\docs\agents\triage-labels.md", $canonLf)
$r = Invoke-CopyJson $t
Assert (@($r.overwritten | Where-Object { $_.file -like "*triage-labels*" }).Count -eq 0) "diferencia solo de EOL (destino LF) NO se reporta como pisada"
Assert (-not (Test-Path "$t\.bootstrap-backup\docs\agents\triage-labels.md")) "diferencia solo de EOL NO genera respaldo"
Remove-Item -Recurse -Force $t

# 8b. La misma comparación, con el destino en CRLF — cubre el caso inverso sin depender del checkout
$t = New-Proj
New-Item -ItemType Directory -Path "$t\docs\agents" -Force | Out-Null
[IO.File]::WriteAllText("$t\docs\agents\triage-labels.md", ($canonLf -replace "`n", "`r`n"))
$r = Invoke-CopyJson $t
Assert (@($r.overwritten | Where-Object { $_.file -like "*triage-labels*" }).Count -eq 0) "diferencia solo de EOL (destino CRLF) NO se reporta como pisada"
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
$gi2 = @($r.overwritten | Where-Object { $_.file -eq ".gitignore" })
Assert ($gi2.Count -eq 1) "segunda corrida: el archivo editado se vuelve a declarar pisado"
Assert ((Get-IfAny "$t\.bootstrap-backup\.gitignore").Trim() -eq "el original de verdad") "segunda corrida: el respaldo conserva el original, no la edición posterior"
# El respaldo más viejo se conserva, pero la edición posterior TAMPOCO puede perderse: se guarda
# al lado, y el `backup` del reporte apunta a lo que se acaba de pisar, no al original viejo.
# Sin esto el JSON promete una copia que no contiene lo destruido (p. ej. el .gitignore ya
# mergeado en el Step D se pierde y el reporte manda a la versión pre-merge).
Assert ((Get-IfAny (Join-Path $t ($gi2[0].backup -replace '/', '\'))).Trim() -eq "edicion posterior al bootstrap") "segunda corrida: el backup declarado contiene lo que se acaba de pisar"
Assert (@($r.overwritten).Count -eq 1) "segunda corrida: los 51 archivos ya idénticos no se declaran pisados"
Remove-Item -Recurse -Force $t

# 11. Un archivo propio que el scaffold no toca queda intacto, no se respalda y no se declara
# Con un conflicto presente, para que .bootstrap-backup/ exista de verdad: si no, el assert de
# ausencia pasa solo porque el directorio no existe y no mide nada.
$t = New-Proj
"nota" | Set-Content "$t\NOTAS.md" -Encoding UTF8
"reglas propias" | Set-Content "$t\.gitignore" -Encoding UTF8
$r = Invoke-CopyJson $t
Assert (Test-Path "$t\.bootstrap-backup\.gitignore") "el escenario tiene un conflicto real (el directorio de respaldo existe)"
Assert ((Get-Content "$t\NOTAS.md" -Raw).Trim() -eq "nota") "archivo ajeno al scaffold queda intacto"
Assert (-not (Test-Path "$t\.bootstrap-backup\NOTAS.md")) "archivo ajeno al scaffold no se respalda"
Assert (@($r.overwritten | Where-Object { $_.file -eq "NOTAS.md" }).Count -eq 0) "archivo ajeno al scaffold no se declara pisado"
Assert (@($r.created | Where-Object { $_ -eq "NOTAS.md" }).Count -eq 0) "archivo ajeno al scaffold no se declara creado"
Remove-Item -Recurse -Force $t

# 13. Mismo largo en bytes, contenido distinto — ejercita la comparación byte a byte
# Sin este caso el early-return por longitud tapa el loop: TODOS los demás fixtures usan contenidos
# cortos contra archivos de scaffold largos, así que el loop nunca decide nada y se lo puede romper
# entero sin que la suite se entere (mutante M8 sobrevivió). El modo de falla es el de Profitability:
# el archivo se pisa igual, pero sin respaldo y sin declararse.
$t = New-Proj
$canonTl = [IO.File]::ReadAllBytes("$skillP\assets\scaffold\docs\agents\triage-labels.md")
$mismoLargo = [byte[]]::new($canonTl.Length)
for ($i = 0; $i -lt $canonTl.Length; $i++) { $mismoLargo[$i] = 65 }   # mismo largo, todo 'A'
New-Item -ItemType Directory -Path "$t\docs\agents" -Force | Out-Null
[IO.File]::WriteAllBytes("$t\docs\agents\triage-labels.md", $mismoLargo)
$r = Invoke-CopyJson $t
Assert (@($r.overwritten | Where-Object { $_.file -eq "docs/agents/triage-labels.md" }).Count -eq 1) "mismo largo y distinto contenido SÍ se declara pisado"
Assert ((Get-IfAny "$t\.bootstrap-backup\docs\agents\triage-labels.md") -ne $null) "mismo largo y distinto contenido SÍ se respalda"
Remove-Item -Recurse -Force $t

# 14. Diferencia SOLO de BOM: es un cambio real, no ruido de EOL
# Decodificar a texto para comparar hace que el BOM se descarte y que dos binarios distintos
# colapsen al mismo U+FFFD; ambos casos se pisarían en silencio. La comparación normaliza EOL
# sobre los BYTES, así que un BOM cuenta como diferencia.
$t = New-Proj
New-Item -ItemType Directory -Path "$t\docs\agents" -Force | Out-Null
$bom = [byte[]](0xEF,0xBB,0xBF) + $canonTl
[IO.File]::WriteAllBytes("$t\docs\agents\triage-labels.md", $bom)
$r = Invoke-CopyJson $t
Assert (@($r.overwritten | Where-Object { $_.file -eq "docs/agents/triage-labels.md" }).Count -eq 1) "diferencia de BOM se declara pisada"
Assert ((Get-IfAny "$t\.bootstrap-backup\docs\agents\triage-labels.md") -ne $null) "diferencia de BOM genera respaldo"
Remove-Item -Recurse -Force $t

# Nota: el caso "dos binarios distintos colapsan al mismo U+FFFD" no se puede cubrir acá — exige
# que AMBOS archivos tengan bytes inválidos, y los 52 del scaffold son texto válido. El bloque 14
# (BOM) ejercita la misma causa raíz —comparar decodificando en vez de comparar bytes— y sí muerde.

# 12. Espejado byte-idéntico entre las TRES skills
$hp = (Get-FileHash $scriptP -Algorithm SHA256).Hash
$hs = (Get-FileHash $scriptS -Algorithm SHA256).Hash
$ha = (Get-FileHash $scriptA -Algorithm SHA256).Hash
Assert ($hp -eq $hs) "copy-scaffold.ps1 espejado byte-idéntico (personal == southpoint)"
Assert ($hp -eq $ha) "copy-scaffold.ps1 espejado byte-idéntico (personal == ai-project)"

# Sin rastros de testeo (regla del repo): se borra SOLO lo de esta corrida, nunca el TEMP ajeno
if (Test-Path -LiteralPath $script:runRoot) { Remove-Item -LiteralPath $script:runRoot -Recurse -Force -ErrorAction SilentlyContinue }

if ($script:failures -eq 0) { Write-Host "TODOS LOS TESTS PASARON"; exit 0 }
else { Write-Host "$($script:failures) test(s) FALLARON"; exit 1 }
