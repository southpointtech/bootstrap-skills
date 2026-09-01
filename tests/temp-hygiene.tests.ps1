# tests/temp-hygiene.tests.ps1 — runner sin Pester. Correr: pwsh -NoProfile -File tests/temp-hygiene.tests.ps1
#
# La regla del repo dice que cualquier rastro de testeo se borra al terminar, y no se cumplía: 62
# rastros medidos en %TEMP% el 2026-08-31, 106 el 2026-09-01. Se intentó arreglar tres veces a mano
# y las tres fallaron por mirar demasiado poco (contar solo directorios y no ver los archivos;
# borrar un nombre exacto y no ver a sus quince hermanos). Mientras la causa raíz esté en las
# suites, cualquier barrido manual vuelve a fallar.
#
# Esta suite es la red que hace que no vuelva: verifica ESTÁTICAMENTE que ninguna suite cree
# temporales por afuera de tests/lib/temp-workspace.ps1, y DINÁMICAMENTE que el helper haga las dos
# cosas no obvias que le dan sentido (recolectar por edad y sobrevivir a un aborto).
$ErrorActionPreference = "Stop"
$lib = Join-Path $PSScriptRoot "lib\temp-workspace.ps1"
. $lib
$script:failures = 0
function Assert($cond, $msg) {
  if ($cond) { Write-Host "ok:   $msg" } else { Write-Host "FAIL: $msg"; $script:failures++ }
}

$script:runRoot = New-TestRunRoot "thyg"
trap { Remove-TestRunRoot $script:runRoot; break }

# ---------------------------------------------------------------------------
# A. Lint: ninguna suite toca la raíz de %TEMP% por su cuenta
# ---------------------------------------------------------------------------
# El criterio es de AUSENCIA total, no "que lo use bien": decidir estáticamente si un
# `Join-Path (GetTempPath()) ...` termina creando algo no es viable, y una regla con excepciones es
# una regla que la próxima suite esquiva sin querer. Todo pasa por el helper, sin excepciones.
#
# Se cuentan SÍMBOLOS, no texto, y por el parser de PowerShell — no por regex sobre el archivo. Dos
# razones medidas, las dos sobre esta misma suite: (a) un grep contaba las menciones en los
# comentarios que explican la regla, y (b) se contaba a sí misma al leer el patrón que usa para
# buscar. Recortar comentarios con regex sería parsear código con regex, que en este repo ya está
# documentado como pozo. El parser los devuelve como tokens aparte y el problema desaparece.
function Get-UsosDeTempDirecto([string]$path) {
  $tokens = $null; $errs = $null
  [void][System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errs)
  return @($tokens | Where-Object {
    $_.Kind -ne 'Comment' -and (
      $_.Text -eq 'GetTempPath' -or $_.Text -match '^\$env:TEMP$'
    )
  })
}

$suites = @(Get-ChildItem $PSScriptRoot -Filter "*.tests.ps1" -File)
# Contra el piso conocido: sin esto, un glob que no matchea nada deja el foreach vacío y las 30
# aserciones de abajo "pasan" sin haber leído un solo archivo.
Assert ($suites.Count -ge 15) "el lint ve las suites del repo (encontradas: $($suites.Count))"

foreach ($s in $suites) {
  $txt = Get-Content $s.FullName -Raw
  $sueltos = Get-UsosDeTempDirecto $s.FullName
  Assert ($sueltos.Count -eq 0) "$($s.Name): no construye temporales en la raíz de %TEMP% (usos directos: $($sueltos.Count))"

  if ($txt -match 'New-TestRunRoot') {
    Assert ($txt -match 'lib[\\/]temp-workspace\.ps1') `
      "$($s.Name): dot-sourcea el helper en vez de redefinirlo"
    # El trap se escribe en UNA línea y siempre igual, para que esto lo pueda verificar exacto:
    # un regex laxo sobre un bloque multilínea acepta un trap que atrapa y no borra.
    Assert ($txt -match '(?m)^\s*trap\s*\{\s*Remove-TestRunRoot\s+\$script:runRoot\s*;\s*break\s*\}\s*$') `
      "$($s.Name): declara el trap de una línea que borra la raíz en el camino de aborto"
    # Dos apariciones: la del trap y la del final. El trap solo no alcanza — cubre el aborto, no la
    # salida normal.
    $cleanups = @([regex]::Matches($txt, 'Remove-TestRunRoot'))
    Assert ($cleanups.Count -ge 2) `
      "$($s.Name): además del trap, borra la raíz al terminar (apariciones: $($cleanups.Count))"
  }
}

# El helper es el único lugar donde resolver la raíz de %TEMP% es legítimo, y tiene que seguir
# haciéndolo: si alguien lo vacía, el lint de arriba pasa en verde sobre un repo que ya no recolecta
# nada. Un lint cuya única forma de fallar es que alguien agregue código no es una red.
Assert ((Get-UsosDeTempDirecto $lib).Count -ge 1) "el helper sí resuelve la raíz de %TEMP% (es el único que puede)"

# ---------------------------------------------------------------------------
# B. El helper recolecta huérfanos POR EDAD, no por glob incondicional
# ---------------------------------------------------------------------------
# Este es el assert que más muerde: en este repo las corridas concurrentes son la norma (el
# review-loop lanza reviewers en paralelo) y un glob incondicional les borra los fixtures en pleno
# uso. Ya pasó de verdad. El prefijo lleva un GUID para no chocar con otra corrida de esta misma
# suite.
# El temp se deriva de la raíz que el helper ya creó, no de GetTempPath(): esta suite se lintea a
# sí misma, y una excepción tallada para ella es justo el agujero por el que se cuela la próxima.
$temp   = Split-Path $script:runRoot -Parent
$pref   = "thygage" + [guid]::NewGuid().ToString('N').Substring(0, 8)
$viejo  = Join-Path $temp "$pref-run-99999-viejo"
$fresco = Join-Path $temp "$pref-run-99998-fresco"
[IO.Directory]::CreateDirectory($viejo)  | Out-Null
[IO.Directory]::CreateDirectory($fresco) | Out-Null
$fixture = Join-Path $fresco "fixture-en-uso.txt"
"una corrida concurrente está usando esto" | Set-Content $fixture -Encoding UTF8
(Get-Item $viejo).CreationTime = (Get-Date).AddDays(-2)

$rootB = New-TestRunRoot $pref
try {
  Assert (Test-Path -LiteralPath $rootB) "New-TestRunRoot crea la raíz de la corrida"
  Assert ($rootB -like (Join-Path $temp "$pref-run-$PID-*")) "la raíz lleva el prefijo y el PID de la corrida"
  Assert (-not (Test-Path -LiteralPath $viejo)) "recolecta la raíz huérfana de hace más de un día"
  Assert (Test-Path -LiteralPath $fixture) "NO toca la raíz fresca de una corrida concurrente"
} finally {
  Remove-TestRunRoot $rootB
  Remove-TestRunRoot $viejo
  Remove-TestRunRoot $fresco
}

# ---------------------------------------------------------------------------
# C. El trap sobrevive a un aborto — con control negativo
# ---------------------------------------------------------------------------
# Sin el control negativo esto no prueba nada: si la raíz se borrara sola por cualquier motivo, el
# assert de C1 pasaría con el trap muerto. C2 corre el MISMO probe sin la línea del trap y exige
# que la raíz sobreviva; solo entonces C1 mide el trap y no otra cosa.
function Invoke-Probe([bool]$conTrap) {
  $marca = New-TestTempPath $script:runRoot "marca" ".txt"
  $probe = New-TestTempPath $script:runRoot "probe" ".ps1"
  $lineaTrap = if ($conTrap) { 'trap { Remove-TestRunRoot $script:runRoot; break }' } else { '' }
  @"
`$ErrorActionPreference = "Stop"
. '$lib'
`$script:runRoot = New-TestRunRoot 'thygtrap'
$lineaTrap
`$script:runRoot | Set-Content '$marca' -Encoding UTF8
throw 'aborto simulado'
Remove-TestRunRoot `$script:runRoot
"@ | Set-Content $probe -Encoding UTF8
  & pwsh -NoProfile -File $probe 2>&1 | Out-Null
  return (Get-Content $marca -Raw).Trim()
}

$creadaConTrap = Invoke-Probe $true
Assert ($creadaConTrap -ne '') "C1: el probe con trap llegó a crear su raíz (el escenario es real)"
Assert (-not (Test-Path -LiteralPath $creadaConTrap)) "C1: el trap borra la raíz cuando la suite aborta"

$creadaSinTrap = Invoke-Probe $false
Assert ($creadaSinTrap -ne '') "C2: el probe sin trap llegó a crear su raíz"
Assert (Test-Path -LiteralPath $creadaSinTrap) "C2 (control negativo): sin el trap la raíz SOBREVIVE al aborto"
Remove-TestRunRoot $creadaSinTrap

# ---------------------------------------------------------------------------
# D. Los workspaces y los paths cuelgan de la raíz, no de %TEMP%
# ---------------------------------------------------------------------------
# Si colgaran de %TEMP%, el borrado único del final no se los llevaría y volveríamos al problema
# original con el helper puesto.
$ws = New-TestWorkspace $script:runRoot "caso"
Assert ((Split-Path $ws -Parent) -eq $script:runRoot.TrimEnd('\')) "New-TestWorkspace cuelga de la raíz de la corrida"
Assert (Test-Path -LiteralPath $ws) "New-TestWorkspace crea el directorio"
$ws2 = New-TestWorkspace $script:runRoot "caso"
Assert ($ws2 -ne $ws) "dos workspaces del mismo nombre no colisionan"

$p = New-TestTempPath $script:runRoot "cfg" ".json"
Assert ((Split-Path $p -Parent) -eq $script:runRoot.TrimEnd('\')) "New-TestTempPath cuelga de la raíz de la corrida"
Assert ($p -like "*.json") "New-TestTempPath respeta la extensión"
Assert (-not (Test-Path -LiteralPath $p)) "New-TestTempPath NO crea el archivo (hay casos que necesitan que falte)"

# Con corchetes: el caso de review-loop-trigger. New-Item los interpretaría como wildcard.
$wsCorchetes = New-TestWorkspace $script:runRoot "rlt-[test]"
Assert (Test-Path -LiteralPath $wsCorchetes) "un workspace con corchetes en el nombre se crea igual"

Remove-TestRunRoot $script:runRoot

Write-Host ""
if ($script:failures -gt 0) { Write-Host "$($script:failures) test(s) FALLARON"; exit 1 } else { Write-Host "TODOS LOS TESTS PASARON"; exit 0 }
