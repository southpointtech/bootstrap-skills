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

# Envejece una raíz de fixture. Las dos marcas se fijan POR SEPARADO a propósito: la versión
# anterior ponía la misma fecha en ambas "para que el fixture no dependa de cuál mira el helper", y
# el efecto era el contrario — con ambas iguales, `CreationTime` y `LastWriteTime` se comportan
# idéntico y la elección entre las dos no se puede medir con ningún umbral. Medido: revertir el
# helper a `CreationTime` pasaba la suite entera en verde.
function Set-EdadDeRaiz {
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][datetime]$Creacion,
    [Parameter(Mandatory)][datetime]$Escritura
  )
  $i = Get-Item -LiteralPath $Path -Force
  $i.CreationTime  = $Creacion
  $i.LastWriteTime = $Escritura
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
# El vocabulario cubre las formas que estas suites usan o podrían usar sin esfuerzo, no todas las
# imaginables: medido, el predicado anterior veía 1 de las 7 del fixture de abajo. Las que faltaban
# no eran exóticas — `"$env:TEMP\x"` es la forma más idiomática del caso directorio, y
# GetTempFileName / New-TemporaryFile dejan ARCHIVOS sueltos, que es la mitad del problema que este
# trabajo arregla (los 34 `wscfg-*.json` de apply-env) y la que hizo fallar el primer intento manual.
#
# Lo que NO ve, a sabiendas: `[Environment]::GetEnvironmentVariable('TEMP')`, `Get-Item Env:TEMP`,
# un path armado desde `$env:LOCALAPPDATA`, y —la que más importa— cualquier cosa adentro de un
# string NO interpolado, incluido el código que estas suites le pasan a un `pwsh` hijo. Un script
# hijo es invisible para este lint.
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

# A0. El detector, contra un fixture con las formas que se le exigen reconocer.
# Sin esto el lint se probaba solo contra la grafía que las suites ya usaban: medido, el predicado
# anterior veía 1 de estas 7.
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
Assert ((Get-UsosDeTempDirecto $fxLimpio).Count -eq 0) "el detector NO ve menciones en comentarios ni en literales sin interpolar"

# Estos tres chequeos van por el ÁRBOL (AST), no por la lista de tokens. La razón es la misma que
# llevó de grep a tokens, un escalón más arriba: las tres propiedades son estructurales —dónde está
# la limpieza, de qué scriptblock cuelga el trap, qué comando lleva el operador de dot-source— y
# la lista de tokens no tiene forma de expresarlas. Medido, la versión por tokens dejaba pasar:
# un `trap` declarado DENTRO de una función (o sea muerto, que es contra lo que advierte el propio
# helper); un dot-source falso donde el path venía en el comentario del final de la línea; y el
# borrado de la limpieza final en las dos suites que tienen una tercera invocación.
function Get-AstDe([string]$path) {
  $t = $null; $e = $null
  return [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$t, [ref]$e)
}

# ¿Cuelga este nodo de una función o de un scriptblock anidado, en vez del cuerpo del archivo?
function Test-Anidado($nodo) {
  $p = $nodo.Parent
  while ($null -ne $p) {
    if ($p -is [System.Management.Automation.Language.FunctionDefinitionAst] -or
        $p -is [System.Management.Automation.Language.ScriptBlockExpressionAst]) { return $true }
    $p = $p.Parent
  }
  return $false
}

# La limpieza del final tiene que estar en el CUERPO del script, no adentro de un `if`, un `try`,
# una función ni el propio trap: "borra la raíz al terminar" es una afirmación sobre la POSICIÓN,
# y un piso de apariciones no la puede expresar. Medido dos veces: contando, `review-marker` (3
# invocaciones tras agregarle la limpieza del `exit`) y `temp-hygiene` (6) quedaban por encima del
# piso aunque se les borrara la limpieza final, así que el arreglo de una fuga había desarmado la
# red que la cubría.
function Test-LimpiezaAlTerminar([string]$path, [string]$comando, [string]$argumento) {
  $ast = Get-AstDe $path
  $cmds = @($ast.FindAll({
    param($n)
    $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq $comando
  }, $true))
  foreach ($c in $cmds) {
    # Tiene que borrar LA RAÍZ DE LA CORRIDA, no cualquier cosa: medido, sin este filtro alcanzaba
    # con que la suite tuviera en algún lado un `Remove-TestRunRoot` de otro path —la parte C de
    # esta misma suite limpia la raíz de su probe— y borrarle la limpieza de verdad pasaba en verde.
    if ($c.CommandElements.Count -lt 2 -or $c.CommandElements[1].Extent.Text -ne $argumento) { continue }
    if (Test-Anidado $c) { continue }
    $p = $c.Parent; $condicional = $false
    while ($null -ne $p) {
      if ($p -is [System.Management.Automation.Language.IfStatementAst] -or
          $p -is [System.Management.Automation.Language.TryStatementAst] -or
          $p -is [System.Management.Automation.Language.TrapStatementAst] -or
          $p -is [System.Management.Automation.Language.LoopStatementAst]) { $condicional = $true; break }
      $p = $p.Parent
    }
    if (-not $condicional) { return $true }
  }
  return $false
}

# El trap tiene que colgar del cuerpo del ARCHIVO y borrar la raíz. Uno declarado dentro de una
# función sólo atrapa lo de esa función: está muerto, y el regex de texto lo aceptaba igual porque
# sólo miraba que la línea empezara con `trap`.
function Test-TrapDeScript([string]$path, [string]$comando) {
  $ast = Get-AstDe $path
  $traps = @($ast.FindAll({
    param($n) $n -is [System.Management.Automation.Language.TrapStatementAst]
  }, $true))
  foreach ($t in $traps) {
    if (Test-Anidado $t) { continue }
    $borra = @($t.Body.FindAll({
      param($n)
      $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq $comando
    }, $true))
    if ($borra.Count -gt 0) { return $true }
  }
  return $false
}

# ¿El archivo dot-sourcea ese path, o solo lo menciona? Con el AST el operador de dot-source es un
# atributo del comando (`InvocationOperator`), y el Extent del comando TERMINA donde termina el
# comando: un comentario al final de la línea queda afuera. La versión por tokens escaneaba hasta
# el fin de línea y por eso aceptaba `. .\otro.ps1  # ex lib\temp-workspace.ps1` — con lo cual se
# podía dot-sourcear un stub que reintroducía el glob incondicional y el assert seguía verde.
function Test-DotSourceaA([string]$path, [string]$fragmento) {
  $ast = Get-AstDe $path
  $ds = @($ast.FindAll({
    param($n)
    $n -is [System.Management.Automation.Language.CommandAst] -and $n.InvocationOperator -eq 'Dot'
  }, $true))
  if ($ds.Count -eq 0) { return $false }
  # Variables asignadas a algo que nombra el helper, para la forma `$lib = ...` + `. $lib` que usa
  # esta misma suite (necesita el path después, para el probe de la parte C).
  $varsConElPath = @{}
  foreach ($a in @($ast.FindAll({
    param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst]
  }, $true))) {
    if ($a.Right.Extent.Text -match $fragmento) { $varsConElPath[$a.Left.Extent.Text] = $true }
  }
  foreach ($c in $ds) {
    if ($c.Extent.Text -match $fragmento) { return $true }
    foreach ($e in $c.CommandElements) {
      if ($varsConElPath.ContainsKey($e.Extent.Text)) { return $true }
    }
  }
  return $false
}

$suites = @(Get-ChildItem -LiteralPath $PSScriptRoot -Filter "*.tests.ps1" -File)
# Contra el piso conocido: sin esto, un glob que no matchea nada deja el foreach vacío y las
# aserciones de abajo "pasan" sin haber leído un solo archivo.
Assert ($suites.Count -ge 15) "el lint ve las suites del repo (encontradas: $($suites.Count))"

# Todo lo que hay bajo tests/lib/ además del helper. Era un punto ciego: el glob de arriba es sólo
# `*.tests.ps1` y no recursivo, así que un stub puesto ahí podía crear temporales en la raíz de
# %TEMP% —con el glob incondicional y todo— sin que nada lo mirara, y encima una suite podía
# dot-sourcearlo. Medido: ese fue un mutante que sobrevivió.
$auxiliares = @(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot "lib") -Filter "*.ps1" -File -Recurse |
  Where-Object { $_.Name -ne "temp-workspace.ps1" })
foreach ($a in $auxiliares) {
  $u = Get-UsosDeTempDirecto $a.FullName
  Assert ($u.Count -eq 0) "lib/$($a.Name): no construye temporales en la raíz de %TEMP% (usos directos: $($u.Count))"
}

$conHelper = 0
foreach ($s in $suites) {
  $sueltos = Get-UsosDeTempDirecto $s.FullName
  Assert ($sueltos.Count -eq 0) "$($s.Name): no construye temporales en la raíz de %TEMP% (usos directos: $($sueltos.Count))"

  $usa = @((Get-AstDe $s.FullName).FindAll({
    param($n)
    $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'New-TestRunRoot'
  }, $true))
  if ($usa.Count -gt 0) {
    $conHelper++
    Assert (Test-DotSourceaA $s.FullName 'lib[\\/]temp-workspace\.ps1') `
      "$($s.Name): dot-sourcea el helper en vez de redefinirlo"
    Assert (Test-TrapDeScript $s.FullName 'Remove-TestRunRoot') `
      "$($s.Name): el trap que borra la raíz cuelga del cuerpo del script (no de una función)"
    Assert (Test-LimpiezaAlTerminar $s.FullName 'Remove-TestRunRoot' '$script:runRoot') `
      "$($s.Name): además del trap, borra la raíz al terminar, en el cuerpo del script"
  }
}

# Piso del set que se chequea, no sólo del set que se lee. Todo lo de arriba vive dentro del `if`,
# así que una suite que deja de usar el helper sale del conjunto verificado EN SILENCIO.
# NUEVE, no ocho: son las ocho migraciones MÁS esta misma suite, que también usa el helper. Con el
# piso en ocho quedaba un lugar de sobra y revertir una migración pasaba en verde — el assert no
# alcanzaba para lo que su propio comentario decía que existía.
Assert ($conHelper -ge 9) "las 8 suites migradas + esta siguen usando el helper (usándolo: $conHelper)"

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
#
# El costo: dos corridas concurrentes de esta suite COMPARTEN el prefijo, y el colector globea
# `<prefijo>-run-*` sin mirar el PID, así que una puede borrarle el `$viejo` a la otra antes de que
# ésta llegue a su propio New-TestRunRoot. Eso daría un verde de más, no un rojo de más — el
# `$fresco` y la `$larga` nunca caen por edad. Se midieron 28 corridas concurrentes sin un solo
# fallo ni residuo; se acepta a cambio de que los fixtures sean reclamables.
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
  Set-EdadDeRaiz -Path $viejo  -Creacion (Get-Date).AddDays(-2)  -Escritura (Get-Date).AddDays(-2)
  Set-EdadDeRaiz -Path $fresco -Creacion (Get-Date).AddHours(-2) -Escritura (Get-Date).AddHours(-2)
  # La corrida LARGA: arrancó hace tres días pero escribió recién. Es el caso que separa las dos
  # marcas — con `CreationTime` el helper le borra los fixtures en pleno uso, con `LastWriteTime`
  # no. Sin este fixture, revertir el helper a `CreationTime` pasaba la suite en verde: el cambio
  # principal de todo este trabajo estaba sin test.
  $larga = Join-Path $temp "$pref-run-$PID-larga"
  [IO.Directory]::CreateDirectory($larga) | Out-Null
  $fixtureLargo = Join-Path $larga "fixture-de-corrida-larga.txt"
  "una corrida de tres días que sigue escribiendo" | Set-Content -LiteralPath $fixtureLargo -Encoding UTF8
  Set-EdadDeRaiz -Path $larga -Creacion (Get-Date).AddDays(-3) -Escritura (Get-Date).AddMinutes(-1)

  $rootB = New-TestRunRoot $pref
  Assert (Test-Path -LiteralPath $rootB) "New-TestRunRoot crea la raíz de la corrida"
  Assert ($rootB -like (Join-Path $temp "$pref-run-$PID-*")) "la raíz lleva el prefijo y el PID de la corrida"
  Assert (-not (Test-Path -LiteralPath $viejo)) "recolecta la raíz huérfana de hace más de un día"
  Assert (Test-Path -LiteralPath $fixture) "NO toca la raíz de una corrida concurrente de 2 horas"
  Assert (Test-Path -LiteralPath $fixtureLargo) "NO toca una corrida VIVA de 3 días que escribió recién (LastWriteTime, no CreationTime)"
} finally {
  Remove-TestRunRoot $rootB
  Remove-TestRunRoot $viejo
  Remove-TestRunRoot $fresco
  Remove-TestRunRoot $larga
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
