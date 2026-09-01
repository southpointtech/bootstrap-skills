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
# Lee un archivo que solo existe si la feature anduvo. Un Get-Content sobre un path ausente es
# error TERMINANTE: aborta la corrida entera en vez de sumar un FAIL, y los bloques siguientes no
# se ejecutan. Devuelve cadena vacía, NUNCA $null: `$null.Trim()` también es terminante —
# independiente de $ErrorActionPreference— así que devolver $null solo movería el crash al call
# site. Un archivo existente pero vacío también da $null con -Raw, y cae en el mismo caso.
function Get-IfAny([string]$path) {
  if (Test-Path -LiteralPath $path -PathType Leaf) {
    $c = Get-Content -LiteralPath $path -Raw
    if ($null -eq $c) { return '' }
    return $c
  }
  return ''
}
# El patrón de la raíz por corrida nació acá y ahora vive en tests/lib/temp-workspace.ps1, que lo
# comparten las ocho suites que crean temporales: la razón entera (raíz única + trap + recolección
# por edad, y por qué las tres partes hacen falta) está documentada en ese archivo, y
# tests/temp-hygiene.tests.ps1 verifica que ninguna suite lo esquive.
. (Join-Path $PSScriptRoot "lib\temp-workspace.ps1")
$script:runRoot = New-TestRunRoot "cs"
trap { Remove-TestRunRoot $script:runRoot; break }
function New-Proj([string]$suffix = "") {
  return (New-TestWorkspace $script:runRoot ("cs-test" + $suffix))
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
#    en .bootstrap-backup/, de donde el Step 0b lo toma si no hay ya un docs/agents/legacy-claude.md)
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

# 8/8b. Diferencia SOLO de fin de línea: no es un archivo pisado (bug autocrlf)
# En Profitability App, 2 de 6 "diferencias" eran CRLF vs LF con contenido idéntico.
# Se prueban las dos formas (destino en LF y destino en CRLF) porque cuál de las dos ejercita la
# normalización depende del checkout: en un árbol CRLF muerde la variante LF y la CRLF es una
# copia byte-idéntica, y al revés en un árbol LF. El par garantiza que UNA muerda; el guard de
# precondición de cada bloque dice cuál, en vez de dejar pasar un test vacuo sin avisar.
$canonTlPath = "$skillP\assets\scaffold\docs\agents\triage-labels.md"
$canonBytes  = [IO.File]::ReadAllBytes($canonTlPath)
$canonLf     = ([IO.File]::ReadAllText($canonTlPath)) -replace "`r`n", "`n"
$script:eolEjercitada = $false
foreach ($variante in @(
    @{ nombre = "LF";   texto = $canonLf },
    @{ nombre = "CRLF"; texto = ($canonLf -replace "`n", "`r`n") })) {
  $t = New-Proj
  New-Item -ItemType Directory -Path "$t\docs\agents" -Force | Out-Null
  [IO.File]::WriteAllText("$t\docs\agents\triage-labels.md", $variante.texto)
  # Precondición: si el fixture salió byte-idéntico al canónico, este bloque NO ejercita la
  # normalización (sale por la comparación de bytes) y su verde no significa nada. No es un
  # fallo — es la variante que en este checkout no aplica —, pero tiene que decirse.
  $distinto = -not ([Linq.Enumerable]::SequenceEqual($canonBytes, [IO.File]::ReadAllBytes("$t\docs\agents\triage-labels.md")))
  if ($distinto) { $script:eolEjercitada = $true }
  $r = Invoke-CopyJson $t
  Assert (@($r.overwritten | Where-Object { $_.file -like "*triage-labels*" }).Count -eq 0) "diferencia solo de EOL (destino $($variante.nombre)) NO se reporta como pisada"
  Assert (-not (Test-Path "$t\.bootstrap-backup\docs\agents\triage-labels.md")) "diferencia solo de EOL (destino $($variante.nombre)) NO genera respaldo"
  if ($distinto) { Write-Host "      (la variante $($variante.nombre) es la que ejercita la normalización en este checkout)" }
  Remove-Item -Recurse -Force $t
}
# Al menos una de las dos variantes tiene que haber diferido del canónico EN DISCO, o el par entero
# es vacuo: las dos habrían salido por la comparación de bytes sin tocar la normalización. Se mide
# lo que el bucle escribió, no una reconstrucción de los bytes esperados.
Assert $script:eolEjercitada "alguna de las dos variantes de EOL difiere del canónico en disco (el par no es vacuo)"

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
Assert (@($r.overwritten).Count -eq 1) "segunda corrida: solo el archivo editado se declara pisado, los ya idénticos no"
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
Remove-Item -Recurse -Force $t

# 12. Mismo largo en bytes, contenido distinto — ejercita la comparación byte a byte
# Sin este caso el early-return por longitud tapa el loop: TODOS los demás fixtures usan contenidos
# cortos contra archivos de scaffold largos, así que el loop nunca decide nada y se lo puede romper
# entero sin que la suite se entere (mutante M8 sobrevivió). El modo de falla es el de Profitability:
# el archivo se pisa igual, pero sin respaldo y sin declararse.
$t = New-Proj
$canonTl = [IO.File]::ReadAllBytes($canonTlPath)   # se relee: heredar una variable de otro bloque
                                                   # hace que su ausencia dé un array vacío y el
                                                   # caso pase sin medir nada
$mismoLargo = [byte[]]::new($canonTl.Length)
for ($i = 0; $i -lt $canonTl.Length; $i++) { $mismoLargo[$i] = 65 }   # mismo largo, todo 'A'
New-Item -ItemType Directory -Path "$t\docs\agents" -Force | Out-Null
[IO.File]::WriteAllBytes("$t\docs\agents\triage-labels.md", $mismoLargo)
# Se mide el ARCHIVO EN DISCO contra el canónico, no el array recién dimensionado: comparar
# `$mismoLargo.Length` con `$canonTl.Length` es cierto por construcción, y encima `$null.Length`
# da 0, así que un canónico ilegible daría un fixture vacío y un `ok:` vacuo.
$largoFixture = (Get-Item -LiteralPath "$t\docs\agents\triage-labels.md").Length
Assert ($largoFixture -gt 0 -and $largoFixture -eq (Get-Item -LiteralPath $canonTlPath).Length) "el fixture en disco tiene el mismo largo que el canónico (si no, sale por el early-return y no mide nada)"
$r = Invoke-CopyJson $t
Assert (@($r.overwritten | Where-Object { $_.file -eq "docs/agents/triage-labels.md" }).Count -eq 1) "mismo largo y distinto contenido SÍ se declara pisado"
Assert ((Get-IfAny "$t\.bootstrap-backup\docs\agents\triage-labels.md") -ne '') "mismo largo y distinto contenido SÍ se respalda"
Remove-Item -Recurse -Force $t

# 13. Diferencia SOLO de BOM: es un cambio real, no ruido de EOL
# Decodificar a texto para comparar hace que el BOM se descarte y que dos binarios distintos
# colapsen al mismo U+FFFD; ambos casos se pisarían en silencio. La comparación normaliza EOL
# sobre los BYTES, así que un BOM cuenta como diferencia.
$t = New-Proj
New-Item -ItemType Directory -Path "$t\docs\agents" -Force | Out-Null
$canonTl = [IO.File]::ReadAllBytes($canonTlPath)   # se relee por la misma razón que el bloque 12:
                                                   # heredarlo de ahí ata este caso a que aquél no
                                                   # se mueva ni se borre
$bom = [byte[]](0xEF,0xBB,0xBF) + $canonTl
[IO.File]::WriteAllBytes("$t\docs\agents\triage-labels.md", $bom)
# Este bloque nunca llega al loop byte a byte —el fixture mide canónico+3, así que las dos pasadas de
# `Test-BytesEqual` salen por largo (medido)—; lo que ejercita es que el script NO decodifique, porque
# decodificando el BOM se descarta y este caso pasaría inadvertido. Con un canónico vacío el fixture
# serían 3 bytes sueltos y ya no habría BOM que medir: el bloque fallaría igual, pero por el assert
# del respaldo (3 bytes BOM-only se leen como string vacío), mandando a buscar el bug al lugar
# equivocado. De ahí el `-gt 3`, que es la mitad que importa: sin él la comparación con `+ 3` es
# cierta por construcción y el guard no puede fallar nunca. Mismo descuido que `4ff2c9f` arregló en
# el bloque 12.
$largoBom = (Get-Item -LiteralPath "$t\docs\agents\triage-labels.md").Length
Assert ($largoBom -gt 3 -and $largoBom -eq (Get-Item -LiteralPath $canonTlPath).Length + 3) "el fixture del BOM es el canónico no vacío + 3 bytes (si no, mide largo y no BOM)"
$r = Invoke-CopyJson $t
Assert (@($r.overwritten | Where-Object { $_.file -eq "docs/agents/triage-labels.md" }).Count -eq 1) "diferencia de BOM se declara pisada"
Assert ((Get-IfAny "$t\.bootstrap-backup\docs\agents\triage-labels.md") -ne '') "diferencia de BOM genera respaldo"
Remove-Item -Recurse -Force $t

# Nota: el caso "dos binarios distintos colapsan al mismo U+FFFD" no se puede cubrir acá — exige
# que AMBOS archivos tengan bytes inválidos, y los 52 del scaffold son texto válido. El bloque 13
# (BOM) ejercita la misma causa raíz —comparar decodificando en vez de comparar bytes— y sí muerde.

# 14. Espejado byte-idéntico entre las TRES skills
$hp = (Get-FileHash $scriptP -Algorithm SHA256).Hash
$hs = (Get-FileHash $scriptS -Algorithm SHA256).Hash
$ha = (Get-FileHash $scriptA -Algorithm SHA256).Hash
Assert ($hp -eq $hs) "copy-scaffold.ps1 espejado byte-idéntico (personal == southpoint)"
Assert ($hp -eq $ha) "copy-scaffold.ps1 espejado byte-idéntico (personal == ai-project)"

# Sin rastros de testeo (regla del repo): se borra SOLO lo de esta corrida, nunca el TEMP ajeno
Remove-TestRunRoot $script:runRoot

if ($script:failures -eq 0) { Write-Host "TODOS LOS TESTS PASARON"; exit 0 }
else { Write-Host "$($script:failures) test(s) FALLARON"; exit 1 }
