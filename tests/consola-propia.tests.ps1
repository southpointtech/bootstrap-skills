# tests/consola-propia.tests.ps1 — runner sin Pester. Correr: pwsh -NoProfile -File tests/consola-propia.tests.ps1
# La librería `tests/lib/consola-propia.ps1` (issue 15): corre un script en SU PROPIA consola, con la
# code page del caso adentro, y con `-ConSonda` informa qué encoding hereda el proceso que arranque
# DESPUÉS del script. Las suites que la usan afirman propiedades del script bajo prueba; esta afirma
# las de la librería misma, que son las que hacen que aquéllas signifiquen algo.
$ErrorActionPreference = "Stop"
$script:failures = 0
. (Join-Path $PSScriptRoot "lib\temp-workspace.ps1")
. (Join-Path $PSScriptRoot "lib\consola-propia.ps1")
$script:runRoot = New-TestRunRoot "cpropia"
trap { Remove-TestRunRoot $script:runRoot; break }

function Assert($cond, $msg) {
  if ($cond) { Write-Host "ok:   $msg" } else { Write-Host "FAIL: $msg"; $script:failures++ }
}

# La ÚNICA forma honesta de leer la code page que hereda un proceso: arrancar uno y preguntarle.
# `chcp.com` informa la de la consola, que no es lo mismo (medido el 2026-09-20: después de un hijo
# que fija 850, `chcp` sigue diciendo 65001 y el proceso siguiente arranca en 850), y
# `[Console]::OutputEncoding` de este proceso está cacheado desde que arrancó.
function Get-CpHeredada {
  ((& pwsh -NoProfile -Command "[Console]::OutputEncoding.CodePage") | Out-String).Trim()
}

# Un script de un solo uso, para no depender de ningún producto en los casos de la librería.
function New-Script([string]$cuerpo) {
  $p = New-TestTempPath $script:runRoot "cp-script" ".ps1"
  [IO.File]::WriteAllText($p, $cuerpo, [Text.UTF8Encoding]::new($false))
  return $p
}

# --- La consola de la SUITE queda como estaba: es la propiedad que da sentido a todo lo demás ---
# Sin esto, cambiar `-WindowStyle Hidden` por `-NoNewWindow` en el helper (o sea, que el hijo use la
# consola de la suite) deja verdes a los tres asserts de `cpSonda` de las otras suites y contamina a
# todas las que corran en paralelo: exactamente el bug del issue 15, reintroducido en el helper que
# lo arregla. MEDIDO así antes de escribir esto.
$cpAntes = Get-CpHeredada
# Control positivo: si el caso usara la code page que la consola ya tiene, el assert sería vacío en
# esa máquina. Se elige una que NO sea la de acá (y una consola nueva arranca en 850 en esta
# máquina, así que el caso no es teórico), y se verifica que la elección haya servido.
$cpDelCaso = if ($cpAntes -eq "850") { 437 } else { 850 }
Assert ("$cpDelCaso" -ne $cpAntes) "control positivo: el caso usa una code page ($cpDelCaso) distinta de la de la suite ($cpAntes)"
$eco = New-Script "'eco'`n"
$r = Invoke-EnConsolaPropia -RunRoot $script:runRoot -Script $eco -Cp $cpDelCaso -ConSonda
$cpDespues = Get-CpHeredada
Assert ($r.cpSonda -eq $cpDelCaso) "adentro de su consola el hijo ve la code page del caso (la sonda vio $($r.cpSonda))"
Assert ($cpDespues -eq $cpAntes) `
  "la consola de la suite queda como estaba: $cpAntes antes, $cpDespues después (el hijo corrió en $cpDelCaso)"

# --- El stderr vuelve legible: lo emite el hijo con la code page del caso, no en UTF-8 ---
# La cabecera prometía "decodificado acá y no por la code page de nadie", y valía sólo para stdout,
# que los dos scripts de hub-sync escriben en bytes UTF-8 a mano. El stderr lo codifica el hijo con
# la consola, así que leerlo como UTF-8 devuelve U+FFFD en cada acentuada — justo en el mensaje de
# falla de los casos que corren en 850, que es cuando hace falta leerlo.
$conError = New-Script "[Console]::Error.WriteLine('años y ñandú')`nexit 3`n"
$r = Invoke-EnConsolaPropia -RunRoot $script:runRoot -Script $conError -Cp 850
Assert ($r.exit -eq 3) "el exit code del hijo llega tal cual (fue $($r.exit))"
Assert ($r.err -ceq "años y ñandú") "el stderr del hijo vuelve legible, no con U+FFFD (fue '$($r.err)')"

# --- Lo que la code page del caso NO puede transportar se declara, no se promete ---
# cp850 no tiene em dash: el hijo lo pierde al CODIFICAR, antes de que exista un decoder. Que el
# límite tenga un caso es lo que impide prometer en la cabecera algo que el helper no puede dar.
$conRaya = New-Script "[Console]::Error.WriteLine('un ' + [char]0x2014 + ' raya')`n"
$r = Invoke-EnConsolaPropia -RunRoot $script:runRoot -Script $conRaya -Cp 850
Assert ($r.err -notmatch [char]0x2014) "lo que cp850 no puede codificar no vuelve (el em dash se pierde en el hijo): '$($r.err)'"

# --- Sin -ConSonda no se paga la sonda, y se ve que no se pagó ---
$r = Invoke-EnConsolaPropia -RunRoot $script:runRoot -Script $eco -Cp 850
Assert ($null -eq $r.cpSonda) "sin -ConSonda no hay sonda (fue '$($r.cpSonda)')"
Assert ($r.out -ceq "eco") "el stdout del hijo llega íntegro (fue '$($r.out)')"

Remove-TestRunRoot $script:runRoot
if ($script:failures -eq 0) { Write-Host "TODOS LOS TESTS PASARON"; exit 0 }
else { Write-Host "$($script:failures) test(s) FALLARON"; exit 1 }
