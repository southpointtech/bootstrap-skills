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

# Envejece una raíz de fixture en las DOS marcas. El helper decide por una sola, pero fijar ambas
# mantiene el fixture honesto si esa decisión cambia: si sólo se fijara la que el helper mira, el
# test pasaría por construcción en vez de por comportamiento.
function Set-EdadDeRaiz([string]$path, [datetime]$cuando) {
  $i = Get-Item -LiteralPath $path -Force
  $i.CreationTime  = $cuando
  $i.LastWriteTime = $cuando
}

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
#
# El vocabulario son TODAS las formas de llegar a la raíz de %TEMP%, no las dos que las suites
# usaban: medido, el predicado anterior veía 2 de 6. Las que faltaban no eran exóticas —
# `"$env:TEMP\x"` es la forma más idiomática del caso directorio, y GetTempFileName /
# New-TemporaryFile dejan ARCHIVOS sueltos, que es exactamente la mitad del problema que este
# slice arregla (los 34 `wscfg-*.json` de apply-env) y la que hizo fallar el primer intento manual.
$script:ApisDeTemp = @('GetTempPath', 'GetTempFileName', 'New-TemporaryFile')

function Get-UsosDeTempDirecto([string]$path) {
  $tokens = $null; $errs = $null
  [void][System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errs)
  # Aplanado: un string interpolado llega como UN token cuyo .Text es el literal entero, con los
  # tokens de adentro colgando en .NestedTokens. Sin descender, `"$env:TEMP\ws"` es invisible —
  # el token es la cadena completa con las comillas, así que no iguala ni matchea nada.
  $planos = [System.Collections.Generic.List[object]]::new()
  $pila   = [System.Collections.Generic.Stack[object]]::new()
  foreach ($t in $tokens) { $pila.Push($t) }
  while ($pila.Count -gt 0) {
    $t = $pila.Pop()
    $planos.Add($t)
    if ($t.NestedTokens) { foreach ($n in $t.NestedTokens) { $pila.Push($n) } }
  }
  return @($planos | Where-Object {
    # `-ne 'Comment'` es redundante hoy —el .Text de un comentario es el comentario entero, que
    # empieza con `#`, así que no puede igualar un nombre de API ni matchear el regex anclado— y se
    # conserva sólo por si algún día el predicado se afloja a un -match sin anclar. No es la razón
    # por la que las menciones en prosa no cuentan: eso lo dan la igualdad exacta y las anclas.
    $_.Kind -ne 'Comment' -and (
      $_.Text -in $script:ApisDeTemp -or $_.Text -match '^\$\{?env:(TEMP|TMP)\}?$'
    )
  })
}

# A0. El detector, contra un fixture con TODAS las formas de llegar a la raíz de %TEMP%.
# Sin esto el lint se probaba solo contra las dos grafías que las suites ya usaban, y las otras
# cuatro pasaban en verde: `"$env:TEMP\x"` (la más idiomática para el caso de directorio) y
# New-TemporaryFile / GetTempFileName (que dejan ARCHIVOS sueltos, que es la mitad del problema
# que este slice arregla). Medido: el predicado anterior veía 2 de 6.
$formas = @(
  @{ codigo = '$a = [IO.Path]::GetTempPath()';                nombre = '[IO.Path]::GetTempPath()' }
  @{ codigo = '$b = "$env:TEMP\x"';                           nombre = 'interpolado "$env:TEMP\x"' }
  @{ codigo = '$c = Join-Path $env:TMP "y"';                  nombre = '$env:TMP' }
  @{ codigo = '$d = New-TemporaryFile';                       nombre = 'New-TemporaryFile' }
  @{ codigo = '$e = [IO.Path]::GetTempFileName()';            nombre = '[IO.Path]::GetTempFileName()' }
  @{ codigo = '$f = "$([IO.Path]::GetTempPath())z"';          nombre = 'GetTempPath dentro de un string' }
  @{ codigo = '$g = ${env:TEMP}';                             nombre = '${env:TEMP}' }
)
foreach ($f in $formas) {
  # Un archivo por forma: juntas, una sola detección taparía a las otras seis.
  $fx = New-TestTempPath $script:runRoot "forma" ".ps1"
  $f.codigo | Set-Content $fx -Encoding UTF8
  Assert ((Get-UsosDeTempDirecto $fx).Count -ge 1) "el detector ve la forma: $($f.nombre)"
}
# Control negativo: sin él, un detector que devuelve "todo" pasaría las siete de arriba.
$fxLimpio = New-TestTempPath $script:runRoot "limpio" ".ps1"
@'
# un comentario que menciona GetTempPath y $env:TEMP en prosa
$patron = 'GetTempPath'
$ruta = Join-Path $script:runRoot "ws"
'@ | Set-Content $fxLimpio -Encoding UTF8
Assert ((Get-UsosDeTempDirecto $fxLimpio).Count -eq 0) "el detector NO ve menciones en comentarios ni en literales de string"

# Cuenta invocaciones REALES de un comando, por el parser: los tokens de comando/argumento con ese
# texto, sin comentarios ni cuerpos de string. Contar con [regex]::Matches sobre el archivo cuenta
# también las menciones en prosa y en here-strings — medido, esta misma suite daba 10 apariciones
# de `Remove-TestRunRoot` de las cuales la mayoría eran comentarios y el texto del probe, así que
# borrarle la limpieza final la dejaba en 9 y el piso de 2 seguía pasando en verde.
function Get-InvocacionesDe([string]$path, [string]$comando) {
  $tokens = $null; $errs = $null
  [void][System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errs)
  return @($tokens | Where-Object { $_.Kind -ne 'Comment' -and $_.Text -eq $comando })
}

# ¿El archivo dot-sourcea ese path, o solo lo menciona? El parser distingue el operador `.` seguido
# del path de una mención en un comentario: un `-match` sobre el texto crudo los confunde, y
# `copy-scaffold.tests.ps1` ya nombra el helper en un comentario — con el chequeo anterior se podía
# reemplazar el dot-source por una redefinición local sin filtro de edad, dejar el comentario, y el
# assert cuyo mensaje dice "en vez de redefinirlo" pasaba igual.
function Test-DotSourceaA([string]$path, [string]$fragmento) {
  $tokens = $null; $errs = $null
  [void][System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errs)
  # Variables asignadas a algo que nombra el helper, para reconocer la forma `$lib = ...` + `. $lib`
  # que usa esta misma suite (necesita el path después, para el probe de la parte C).
  $varsConElPath = @{}
  for ($i = 0; $i -lt $tokens.Count - 2; $i++) {
    if ($tokens[$i].Kind -ne 'Variable' -or $tokens[$i + 1].Kind -ne 'Equals') { continue }
    for ($j = $i + 2; $j -lt $tokens.Count -and $tokens[$j].Kind -ne 'NewLine'; $j++) {
      if ($tokens[$j].Text -match $fragmento) { $varsConElPath[$tokens[$i].Text] = $true; break }
    }
  }
  for ($i = 0; $i -lt $tokens.Count - 1; $i++) {
    if ($tokens[$i].Kind -ne 'Dot') { continue }
    # Un `Dot` es dot-source sólo al principio de un comando; el acceso a miembro (`$o.FullName`)
    # produce el MISMO Kind, y sin este filtro un `$algo.$lib` cualquiera contaría como dot-source.
    $previo = if ($i -eq 0) { $null } else { $tokens[$i - 1].Kind }
    if ($null -ne $previo -and $previo -notin @('NewLine', 'Semi', 'LCurly')) { continue }
    # El argumento puede ser el path suelto, un (Join-Path ...) o una variable: alcanza con que el
    # fragmento —o una variable que lo contiene— aparezca antes del fin de línea.
    for ($j = $i + 1; $j -lt $tokens.Count -and $tokens[$j].Kind -ne 'NewLine'; $j++) {
      if ($tokens[$j].Text -match $fragmento) { return $true }
      if ($varsConElPath.ContainsKey($tokens[$j].Text)) { return $true }
    }
  }
  return $false
}

$suites = @(Get-ChildItem $PSScriptRoot -Filter "*.tests.ps1" -File)
# Contra el piso conocido: sin esto, un glob que no matchea nada deja el foreach vacío y las
# aserciones de abajo "pasan" sin haber leído un solo archivo.
Assert ($suites.Count -ge 15) "el lint ve las suites del repo (encontradas: $($suites.Count))"

$conHelper = 0
foreach ($s in $suites) {
  $sueltos = Get-UsosDeTempDirecto $s.FullName
  Assert ($sueltos.Count -eq 0) "$($s.Name): no construye temporales en la raíz de %TEMP% (usos directos: $($sueltos.Count))"

  if ((Get-InvocacionesDe $s.FullName 'New-TestRunRoot').Count -gt 0) {
    $conHelper++
    Assert (Test-DotSourceaA $s.FullName 'lib[\\/]temp-workspace\.ps1') `
      "$($s.Name): dot-sourcea el helper en vez de redefinirlo"
    # El trap se escribe en UNA línea y siempre igual, para que esto lo pueda verificar exacto:
    # un regex laxo sobre un bloque multilínea acepta un trap que atrapa y no borra.
    $txt = Get-Content $s.FullName -Raw
    Assert ($txt -match '(?m)^\s*trap\s*\{\s*Remove-TestRunRoot\s+\$script:runRoot\s*;\s*break\s*\}\s*$') `
      "$($s.Name): declara el trap de una línea que borra la raíz en el camino de aborto"
    # Dos invocaciones: la del trap y la del final. El trap solo no alcanza — cubre el aborto, no la
    # salida normal.
    $cleanups = Get-InvocacionesDe $s.FullName 'Remove-TestRunRoot'
    Assert ($cleanups.Count -ge 2) `
      "$($s.Name): además del trap, borra la raíz al terminar (invocaciones: $($cleanups.Count))"
  }
}

# Piso del set que se chequea, no sólo del set que se lee. Todo lo de arriba vive dentro del `if`,
# así que una suite que deja de usar el helper sale del conjunto verificado EN SILENCIO: sin este
# assert, revertir cualquiera de las ocho migraciones no pone nada en rojo. Ocho es el número que
# el slice migró; sube si se migra otra, y baja sólo borrando una suite a propósito.
Assert ($conHelper -ge 8) "al menos 8 suites siguen usando el helper (usándolo: $conHelper)"

# El helper es el único lugar donde resolver la raíz de %TEMP% es legítimo, y tiene que seguir
# haciéndolo: si alguien lo vacía, el lint de arriba pasa en verde sobre un repo que ya no recolecta
# nada. Un lint cuya única forma de fallar es que alguien agregue código no es una red.
Assert ((Get-UsosDeTempDirecto $lib).Count -ge 1) "el helper sí resuelve la raíz de %TEMP% (es el único que puede)"

# ---------------------------------------------------------------------------
# B. El helper recolecta huérfanos POR EDAD, no por glob incondicional
# ---------------------------------------------------------------------------
# Este es el assert que más muerde: en este repo las corridas concurrentes son la norma (el
# review-loop lanza reviewers en paralelo) y un glob incondicional les borra los fixtures en pleno
# uso. Ya pasó de verdad.
#
# El prefijo es FIJO, no lleva GUID. Con un GUID por corrida, un aborto entre la creación de estos
# fixtures y su limpieza los dejaba en la raíz de %TEMP% bajo un prefijo que ningún glob futuro
# alcanza: irreclamables para siempre, en la suite que existe justamente para que no haya rastros.
# Con el prefijo fijo, la propia recolección por edad del helper los junta en la próxima corrida.
# El PID en el nombre es lo que separa dos corridas concurrentes de esta misma suite.
#
# El temp se deriva de la raíz que el helper ya creó, no de GetTempPath(): esta suite se lintea a
# sí misma, y una excepción tallada para ella es justo el agujero por el que se cuela la próxima.
$temp   = Split-Path $script:runRoot -Parent
$pref   = "thygage"
$viejo  = Join-Path $temp "$pref-run-$PID-viejo"
$fresco = Join-Path $temp "$pref-run-$PID-fresco"
$rootB  = $null
try {
  [IO.Directory]::CreateDirectory($viejo)  | Out-Null
  [IO.Directory]::CreateDirectory($fresco) | Out-Null
  $fixture = Join-Path $fresco "fixture-en-uso.txt"
  "una corrida concurrente está usando esto" | Set-Content $fixture -Encoding UTF8
  # Dos edades REALISTAS, no "viejo" contra "recién creado". Con el fresco a cero segundos, el
  # assert sólo probaba que el umbral es mayor que cero: medido, un umbral de `AddSeconds(-5)`
  # pasaba estos cuatro asserts y aun así destruía una corrida concurrente de 30 segundos, que es
  # exactamente el desastre que este bloque dice prevenir. Con el fresco a dos horas, el assert
  # fija el umbral en algún lugar útil.
  Set-EdadDeRaiz $viejo  (Get-Date).AddDays(-2)
  Set-EdadDeRaiz $fresco (Get-Date).AddHours(-2)

  $rootB = New-TestRunRoot $pref
  Assert (Test-Path -LiteralPath $rootB) "New-TestRunRoot crea la raíz de la corrida"
  Assert ($rootB -like (Join-Path $temp "$pref-run-$PID-*")) "la raíz lleva el prefijo y el PID de la corrida"
  Assert (-not (Test-Path -LiteralPath $viejo)) "recolecta la raíz huérfana de hace más de un día"
  Assert (Test-Path -LiteralPath $fixture) "NO toca la raíz de una corrida concurrente de 2 horas"
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
  # Los paths van como ARGUMENTOS, no interpolados dentro del código del probe: interpolarlos en un
  # literal de PowerShell rompe con un apóstrofe en el path (un usuario `O'Brien` hace que %TEMP%
  # tenga uno), y el probe se vuelve un error de sintaxis que se lee como "el trap no funcionó".
  @"
param([string]`$Lib, [string]`$Marca)
`$ErrorActionPreference = "Stop"
. `$Lib
`$script:runRoot = New-TestRunRoot 'thygtrap'
$lineaTrap
`$script:runRoot | Set-Content -LiteralPath `$Marca -Encoding UTF8
throw 'aborto simulado'
Remove-TestRunRoot `$script:runRoot
"@ | Set-Content $probe -Encoding UTF8
  & pwsh -NoProfile -File $probe -Lib $lib -Marca $marca 2>&1 | Out-Null
  $codigo = $LASTEXITCODE
  # Cadena vacía y no una excepción cuando el probe no llegó a escribir: con `Get-Content` a secas
  # y $ErrorActionPreference=Stop, un probe que ni arranca hacía ABORTAR esta suite en la línea de
  # lectura, así que el assert de la línea siguiente —el que existe para reportar justamente eso—
  # no podía fallar nunca; era decorativo.
  $raiz = if (Test-Path -LiteralPath $marca) { (Get-Content -LiteralPath $marca -Raw).Trim() } else { '' }
  return @{ raiz = $raiz; exit = $codigo }
}

$conTrap = Invoke-Probe $true
Assert ($conTrap.raiz -ne '') "C1: el probe con trap llegó a crear su raíz (el escenario es real)"
# El probe SIEMPRE aborta con un throw; si saliera 0, no probó el camino de aborto.
Assert ($conTrap.exit -ne 0) "C1: el probe abortó de verdad (exit $($conTrap.exit))"
Assert (-not (Test-Path -LiteralPath $conTrap.raiz)) "C1: el trap borra la raíz cuando la suite aborta"

$sinTrap = Invoke-Probe $false
Assert ($sinTrap.raiz -ne '') "C2: el probe sin trap llegó a crear su raíz"
Assert ($sinTrap.exit -ne 0) "C2: el probe sin trap también abortó de verdad (exit $($sinTrap.exit))"
Assert (Test-Path -LiteralPath $sinTrap.raiz) "C2 (control negativo): sin el trap la raíz SOBREVIVE al aborto"
Remove-TestRunRoot $sinTrap.raiz

# ---------------------------------------------------------------------------
# D. Los workspaces y los paths cuelgan de la raíz, no de %TEMP%
# ---------------------------------------------------------------------------
# Si colgaran de %TEMP%, el borrado único del final no se los llevaría y volveríamos al problema
# original con el helper puesto.
$ws = New-TestWorkspace $script:runRoot "caso"
# Sin TrimEnd: Join-Path nunca deja separador al final, así que recortarlo no arreglaba nada y sí
# habría ACEPTADO en silencio una raíz futura que sí lo trajera.
Assert ((Split-Path $ws -Parent) -eq $script:runRoot) "New-TestWorkspace cuelga de la raíz de la corrida"
Assert (Test-Path -LiteralPath $ws) "New-TestWorkspace crea el directorio"
$ws2 = New-TestWorkspace $script:runRoot "caso"
Assert ($ws2 -ne $ws) "dos workspaces del mismo nombre no colisionan"

$p = New-TestTempPath $script:runRoot "cfg" ".json"
Assert ((Split-Path $p -Parent) -eq $script:runRoot) "New-TestTempPath cuelga de la raíz de la corrida"
Assert ($p -like "*.json") "New-TestTempPath respeta la extensión"
Assert (-not (Test-Path -LiteralPath $p)) "New-TestTempPath NO crea el archivo (hay casos que necesitan que falte)"

# Con corchetes: el caso de review-loop-trigger. New-Item los interpretaría como wildcard.
$wsCorchetes = New-TestWorkspace $script:runRoot "rlt-[test]"
Assert (Test-Path -LiteralPath $wsCorchetes) "un workspace con corchetes en el nombre se crea igual"

Remove-TestRunRoot $script:runRoot

Write-Host ""
if ($script:failures -gt 0) { Write-Host "$($script:failures) test(s) FALLARON"; exit 1 } else { Write-Host "TODOS LOS TESTS PASARON"; exit 0 }
