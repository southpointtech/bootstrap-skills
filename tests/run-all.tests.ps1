# tests/run-all.tests.ps1 — runner sin Pester. Correr: pwsh -NoProfile -File tests/run-all.tests.ps1
#
# Prueba el runner de la suite (tests/run-all.ps1) contra suites de juguete, nunca contra las reales:
# cada caso arma su propio directorio de suites y su propio repo git en la raíz temporal de la corrida.
$ErrorActionPreference = "Stop"
$runner = Join-Path $PSScriptRoot "run-all.ps1"
$script:failures = 0
. (Join-Path $PSScriptRoot "lib\temp-workspace.ps1")
$script:runRoot = New-TestRunRoot "runall"
trap { Remove-TestRunRoot $script:runRoot; break }

function Assert($cond, $msg) {
  if ($cond) { Write-Host "ok:   $msg" } else { Write-Host "FAIL: $msg"; $script:failures++ }
}

# Un caso = un directorio de suites + un repo git limpio donde el runner mide si algo lo ensució.
function New-Caso([string]$nombre, [switch]$SinRepo) {
  $raiz = New-TestWorkspace $script:runRoot $nombre
  $suites = Join-Path $raiz "suites"
  $repo = Join-Path $raiz "repo"
  [IO.Directory]::CreateDirectory($suites) | Out-Null
  [IO.Directory]::CreateDirectory($repo) | Out-Null
  if (-not $SinRepo) { git -C $repo init -q 2>&1 | Out-Null }
  @{ suites = $suites; repo = $repo }
}
function Add-Suite($caso, [string]$nombre, [string]$codigo) {
  $codigo | Set-Content -LiteralPath (Join-Path $caso.suites "$nombre.tests.ps1") -Encoding UTF8
}
function Invoke-Runner($caso, [string[]]$extra = @()) {
  $out = & pwsh -NoProfile -File $runner -Path $caso.suites -RepoRoot $caso.repo @extra 2>&1
  @{ exit = $LASTEXITCODE; out = ($out | Out-String) }
}

$suiteVerde = @'
Write-Host "ok:   algo"
exit 0
'@
# Tres líneas marcadas, una de ellas por stderr y la última justo antes del exit: "la salida
# completa" se verifica por sus dos puntas y por el canal de error, no por una sola línea.
$suiteRoja = @'
Write-Host "PRIMERA-LINEA-ROJA"
[Console]::Error.WriteLine("LINEA-DE-STDERR-ROJA")
Write-Host "ULTIMA-LINEA-ROJA"
exit 1
'@

# --- A. todo verde: exit 0 y un renglón por archivo ---
$c = New-Caso "verde"
Add-Suite $c "uno" $suiteVerde
Add-Suite $c "dos" $suiteVerde
$r = Invoke-Runner $c
Assert ($r.exit -eq 0) "A: todo verde da exit 0 (dio $($r.exit))"
Assert ($r.out -match '(?m)^PASS\s+uno\.tests\.ps1') "A: reporta uno.tests.ps1 como PASS"
Assert ($r.out -match '(?m)^PASS\s+dos\.tests\.ps1') "A: reporta dos.tests.ps1 como PASS"
# La salida de una suite verde no se vuelca: sólo se imprime completa la de las que fallan.
Assert ($r.out -notmatch 'ok:   algo') "A: no vuelca la salida de las suites verdes"

# --- B. una roja entre verdes: exit != 0, se nombra y se ve su salida completa ---
$c = New-Caso "roja"
Add-Suite $c "buena" $suiteVerde
Add-Suite $c "mala" $suiteRoja
$r = Invoke-Runner $c
Assert ($r.exit -ne 0) "B: una suite roja da exit != 0 (dio $($r.exit))"
Assert ($r.out -match '(?m)^FAIL\s+mala\.tests\.ps1') "B: reporta mala.tests.ps1 como FAIL"
Assert ($r.out -match '(?m)^PASS\s+buena\.tests\.ps1') "B: la verde sigue reportada como PASS"
Assert ($r.out -notmatch '(?m)^FAIL\s+buena') "B: no culpa a la suite verde"
# La salida va identificada: las tres marcas están DENTRO del bloque que lleva el nombre del
# archivo, no sueltas en cualquier lugar del reporte.
$bloque = [regex]::Match($r.out, '(?s)===== mala\.tests\.ps1 .*?===== fin mala\.tests\.ps1')
Assert $bloque.Success "B: la salida de la roja va en un bloque con su nombre"
foreach ($marca in 'PRIMERA-LINEA-ROJA', 'LINEA-DE-STDERR-ROJA', 'ULTIMA-LINEA-ROJA') {
  Assert ($bloque.Value -match $marca) "B: el bloque de mala.tests.ps1 incluye $marca"
}

# --- C. una suite que aborta con throw (sin exit explícito) también es roja ---
$c = New-Caso "throw"
Add-Suite $c "revienta" "`$ErrorActionPreference = 'Stop'`nthrow 'EXPLOTO-LA-SUITE'"
$r = Invoke-Runner $c
Assert ($r.exit -ne 0) "C: una suite que tira throw da exit != 0 (dio $($r.exit))"
Assert ($r.out -match '(?m)^FAIL\s+revienta\.tests\.ps1') "C: la reporta como FAIL"
Assert ($r.out -match 'EXPLOTO-LA-SUITE') "C: se ve el error del throw"

# --- D. ninguna suite: rojo, no un verde vacuo ---
$c = New-Caso "vacio"
$r = Invoke-Runner $c
Assert ($r.exit -ne 0) "D: un directorio sin suites da exit != 0 (dio $($r.exit))"

# --- E. una suite que ensucia el árbol: rojo, y nombra el archivo ---
$c = New-Caso "ensucia"
Add-Suite $c "sucia" @"
Set-Content -LiteralPath '$(Join-Path $c.repo 'basura-del-test.txt')' -Value 'x'
exit 0
"@
$r = Invoke-Runner $c
Assert ($r.exit -ne 0) "E: una suite verde que ensucia el repo da exit != 0 (dio $($r.exit))"
Assert ($r.out -match 'basura-del-test\.txt') "E: el reporte nombra el archivo que apareció"

# --- F. un archivo que YA estaba sucio y la suite lo vuelve a tocar: también es rojo ---
# `git status` dice lo mismo antes y después ("??"); sólo el contenido delata el cambio.
$c = New-Caso "resucia"
$previo = Join-Path $c.repo 'ya-sucio.txt'
Set-Content -LiteralPath $previo -Value 'antes'
Add-Suite $c "retoca" @"
Set-Content -LiteralPath '$previo' -Value 'despues'
exit 0
"@
$r = Invoke-Runner $c
Assert ($r.exit -ne 0) "F: re-modificar un archivo ya sucio da exit != 0 (dio $($r.exit))"
Assert ($r.out -match 'ya-sucio\.txt') "F: el reporte nombra el archivo re-modificado"

# --- G. un árbol que ya estaba sucio y nadie toca: verde (se compara, no se exige limpio) ---
$c = New-Caso "sucio-quieto"
Set-Content -LiteralPath (Join-Path $c.repo 'residuo-ajeno.txt') -Value 'de otra sesion'
Add-Suite $c "quieta" $suiteVerde
$r = Invoke-Runner $c
Assert ($r.exit -eq 0) "G: suciedad previa que nadie toca no es rojo (dio $($r.exit))"

# --- H. las suites corren EN PARALELO ---
# Cada una espera a ver la marca de arranque de la otra. En serie, la primera espera sola hasta su
# timeout y sale con 1; en paralelo las dos se ven. Es determinista, no una carrera de relojes.
$c = New-Caso "paralelo"
$marcas = New-TestWorkspace $script:runRoot "marcas"
foreach ($par in @(@('izq', 'der'), @('der', 'izq'))) {
  $yo, $otro = $par
  Add-Suite $c $yo @"
New-Item -ItemType File -Path '$(Join-Path $marcas $yo)' | Out-Null
`$limite = (Get-Date).AddSeconds(20)
while (-not (Test-Path '$(Join-Path $marcas $otro)')) {
  if ((Get-Date) -gt `$limite) { Write-Host 'NO-VI-A-$otro'; exit 1 }
  Start-Sleep -Milliseconds 100
}
exit 0
"@
}
$r = Invoke-Runner $c
Assert ($r.exit -eq 0) "H: dos suites que se esperan mutuamente terminan verdes (dio $($r.exit))"

# Control positivo: con un solo carril el mismo par TIENE que fallar. Sin esto, H pasaría también
# con un runner que ignora el paralelismo.
Get-ChildItem -LiteralPath $marcas -File | Remove-Item -Force
$r = Invoke-Runner $c @('-ThrottleLimit', '1')
Assert ($r.exit -ne 0) "H: con -ThrottleLimit 1 el mismo par falla (dio $($r.exit))"
Assert ($r.out -match 'NO-VI-A-') "H: y falla por no ver a la otra suite, no por otra cosa"

# --- I. una suite que BORRA un archivo que ya estaba sucio: rojo por "desapareció" ---
# Es la única de las tres ramas de la comparación que no produce una clave nueva ni un hash nuevo.
$c = New-Caso "borra"
$previo = Join-Path $c.repo 'ya-estaba.txt'
Set-Content -LiteralPath $previo -Value 'residuo'
Add-Suite $c "borradora" "Remove-Item -LiteralPath '$previo'`nexit 0"
$r = Invoke-Runner $c
Assert ($r.exit -ne 0) "I: borrar un archivo ya sucio da exit != 0 (dio $($r.exit))"
# `\S*` y no la letra acentuada: la salida del hijo se decodifica con la codificación de la consola.
Assert ($r.out -match '(?m)^\s+desapareci\S*:\s+\?\? ya-estaba\.txt') "I: el reporte lo da como desaparecido"

# --- J. un repo que no es repo: rojo, no un chequeo de árbol que compara dos vacíos ---
$c = New-Caso "sin-repo" -SinRepo
Add-Suite $c "quieta" $suiteVerde
$r = Invoke-Runner $c
Assert ($r.exit -ne 0) "J: un -RepoRoot que no es repo git da exit != 0 (dio $($r.exit))"
Assert ($r.out -match 'git status fall') "J: y dice que falló git status"

# --- K. un archivo nuevo DENTRO de un directorio que ya estaba sin trackear ---
# Sin --untracked-files=all, git lista sólo `?? sucio/`, que no es un archivo, y el agregado no se ve.
$c = New-Caso "dir-sucio"
[IO.Directory]::CreateDirectory((Join-Path $c.repo 'sucio')) | Out-Null
Set-Content -LiteralPath (Join-Path $c.repo 'sucio\viejo.txt') -Value 'residuo'
Add-Suite $c "agrega" "Set-Content -LiteralPath '$(Join-Path $c.repo 'sucio\nuevo.txt')' -Value 'x'`nexit 0"
$r = Invoke-Runner $c
Assert ($r.exit -ne 0) "K: un archivo nuevo en un directorio ya sucio da exit != 0 (dio $($r.exit))"
Assert ($r.out -match 'sucio/nuevo\.txt') "K: el reporte nombra sucio/nuevo.txt"

# --- L. re-escribir un archivo ya sucio cuyo nombre lleva espacio y acento, entre dos sucios ---
# El espacio lo entrecomilla git sin -z; el acento llega deformado si la salida de git se decodifica
# con la codificación de la consola (en esta máquina, ibm850). En los dos casos el hash queda '-'
# antes y después, y la re-escritura pasa en verde. El segundo archivo sucio existe para que haya
# más de una entrada que separar.
$c = New-Caso "acento"
$previo = Join-Path $c.repo 'decisión final.md'
Set-Content -LiteralPath $previo -Value 'antes'
Set-Content -LiteralPath (Join-Path $c.repo 'otro.txt') -Value 'quieto'
Add-Suite $c "retoca" "Set-Content -LiteralPath '$previo' -Value 'despues'`nexit 0"
$r = Invoke-Runner $c
Assert ($r.exit -ne 0) "L: re-escribir un archivo ya sucio con espacio y acento da exit != 0 (dio $($r.exit))"
Assert ($r.out -match 'final\.md') "L: el reporte nombra el archivo"
Assert ($r.out -notmatch 'otro\.txt') "L: y no culpa al otro archivo sucio, que nadie tocó"

# --- M. un exit NEGATIVO también es rojo (un crash nativo sale así) ---
$c = New-Caso "exit-negativo"
Add-Suite $c "crash" "exit -1"
$r = Invoke-Runner $c
Assert ($r.exit -ne 0) "M: una suite con exit -1 da exit != 0 (dio $($r.exit))"
Assert ($r.out -match '1 suites, 1 rojas') "M: y la cuenta como roja"

# --- N. sólo corren los *.tests.ps1: un .ps1 cualquiera al lado no es una suite ---
# En el repo real el propio runner vive al lado de las suites.
$c = New-Caso "filtro"
Add-Suite $c "unica" $suiteVerde
"Write-Host 'NO-SOY-SUITE'`nexit 1" | Set-Content -LiteralPath (Join-Path $c.suites 'helper.ps1') -Encoding UTF8
$r = Invoke-Runner $c
Assert ($r.exit -eq 0) "N: un .ps1 que no es suite no se corre (dio $($r.exit))"
Assert ($r.out -match '1 suites, 0 rojas') "N: la cuenta tiene una sola suite"

# --- O. cambiar el ESTADO git de un archivo sin cambiar su contenido: rojo ---
# `?? f` pasa a `A  f` con el mismo hash; sólo la parte XY de la clave lo delata.
$c = New-Caso "stagea"
$previo = Join-Path $c.repo 'para-stagear.txt'
Set-Content -LiteralPath $previo -Value 'igual'
Add-Suite $c "stageadora" "git -C '$($c.repo)' add para-stagear.txt`nexit 0"
$r = Invoke-Runner $c
Assert ($r.exit -ne 0) "O: stagear un archivo ya sucio da exit != 0 (dio $($r.exit))"
Assert ($r.out -match '(?m)^\s+apareci\S*:\s+A\s+para-stagear\.txt') "O: el reporte muestra la entrada nueva"

Remove-TestRunRoot $script:runRoot

Write-Host ""
if ($script:failures -gt 0) { Write-Host "$($script:failures) test(s) FALLARON"; exit 1 } else { Write-Host "TODOS LOS TESTS PASARON"; exit 0 }
