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
# un path armado desde `$env:LOCALAPPDATA`, y —la que más importa— el código de un `pwsh` hijo.
# Lo único visible de un hijo es lo que el PADRE interpola (`$env:TEMP` sin escapar, o un
# `$( ... )` que el aplanado de NestedTokens alcanza); el texto que el hijo ejecuta, venga en un
# here-string o escrito a un archivo, es opaco. La distinción no es comillas dobles contra
# literal: es interpolado-por-el-padre contra no.
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

# ¿Cuelga este nodo de una FUNCIÓN, y sólo de una función? Es más estrecho que `Test-Anidado` a
# propósito, y la diferencia es la que importa: `Test-Anidado` también cuenta los
# `ScriptBlockExpressionAst`, pero un scriptblock no abre scope por sí solo — `ForEach-Object` y
# `Where-Object` ejecutan el suyo en el scope del llamador (medido), así que lo que se asigne ahí
# adentro sí afecta al script. Una función sí abre scope. Usar el predicado ancho para decidir
# "esta asignación no cuenta" abría la reasignación a un stub metida en un pipe.
function Test-DentroDeUnaFuncion($nodo) {
  $p = $nodo.Parent
  while ($null -ne $p) {
    if ($p -is [System.Management.Automation.Language.FunctionDefinitionAst]) { return $true }
    $p = $p.Parent
  }
  return $false
}

# ¿Cuelga este nodo de algo que pueda no ejecutarse? Es la otra mitad de "está en el cuerpo del
# script": `Test-Anidado` descarta funciones y scriptblocks, esto descarta las ramas.
# Vive en su propia función porque la usan TRES chequeos (la limpieza final, el dot-source del helper
# y la asignación de su variable). Estaba escrita inline en uno solo; duplicar la lista de cinco
# tipos en tres lugares es garantía de que uno se quede corto sin que nadie lo note.
# `switch` va explícito: no deriva de LoopStatementAst ni de IfStatementAst (sí de
# LabeledStatementAst, junto con los loops), así que sin nombrarlo algo metido en una rama de switch
# contaba como incondicional. Los loops sí quedan cubiertos por su base común.
function Test-BajoCondicion($nodo) {
  $p = $nodo.Parent
  while ($null -ne $p) {
    if ($p -is [System.Management.Automation.Language.IfStatementAst] -or
        $p -is [System.Management.Automation.Language.TryStatementAst] -or
        $p -is [System.Management.Automation.Language.TrapStatementAst] -or
        $p -is [System.Management.Automation.Language.SwitchStatementAst] -or
        $p -is [System.Management.Automation.Language.PipelineChainAst] -or
        $p -is [System.Management.Automation.Language.LoopStatementAst]) { return $true }
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
# ¿Este comando recibe ese argumento? Mirar `CommandElements[1]` a secas rechazaba la forma con
# parámetro nombrado (`Remove-TestRunRoot -Root $script:runRoot`), que es legítima —el parámetro se
# llama Root— y habría dado un rojo sobre código correcto, que es como se termina aflojando un
# chequeo. Se recorren todos los elementos y se ignoran los que son nombres de parámetro.
function Test-ArgumentoEs($cmd, [string]$argumento) {
  $els = @($cmd.CommandElements)
  for ($i = 1; $i -lt $els.Count; $i++) {
    if ($els[$i] -is [System.Management.Automation.Language.CommandParameterAst]) {
      # `-Root <valor>`: el valor puede venir pegado (`-Root:$x`) o como el elemento siguiente.
      if ($els[$i].ParameterName -ne 'Root') { continue }
      if ($null -ne $els[$i].Argument) { return ($els[$i].Argument.Extent.Text -eq $argumento) }
      if ($i + 1 -lt $els.Count) { return ($els[$i + 1].Extent.Text -eq $argumento) }
      return $false
    }
    # El PRIMER argumento posicional y ninguno más: aceptar la raíz en cualquier posición dejaba
    # pasar `Remove-TestRunRoot $otra $script:runRoot`, que borra $otra y manda la raíz a $args sin
    # decir nada (la función no tiene CmdletBinding, así que el extra no da error).
    return ($els[$i].Extent.Text -eq $argumento)
  }
  return $false
}

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
    if (-not (Test-ArgumentoEs $c $argumento)) { continue }
    if (Test-Anidado $c) { continue }
    if (-not (Test-BajoCondicion $c)) { return $true }
  }
  return $false
}

# El trap tiene que colgar del cuerpo del ARCHIVO, borrar LA RAÍZ como sentencia directa, y
# terminar en `break`. Las tres condiciones son necesarias y cada una tapó un agujero distinto:
#
# - Del cuerpo del script: uno declarado dentro de una función sólo atrapa lo de esa función, está
#   muerto, y el regex de texto lo aceptaba porque sólo miraba que la línea empezara con `trap`.
# - Sentencia directa y con `$script:runRoot`: buscar el comando en cualquier profundidad aceptaba
#   `trap { if ($false) { Remove-TestRunRoot ... } }` y un trap que borra OTRA raíz.
# - `break` al final: es lo que RELANZA el error. Con `continue` el trap se lo traga y la ejecución
#   sigue en la sentencia siguiente, así que —medido, mismo error inyectado, cambiando sólo esa
#   palabra— la suite termina con exit 0 y "TODOS LOS TESTS PASARON" después de haber abortado.
#   El regex del turno 1 exigía el `break` textualmente y esto lo había perdido: es la única
#   condición acá que no es sobre la limpieza sino sobre no mentir el resultado.
function Test-TrapDeScript([string]$path, [string]$comando, [string]$argumento) {
  $ast = Get-AstDe $path
  $traps = @($ast.FindAll({
    param($n) $n -is [System.Management.Automation.Language.TrapStatementAst]
  }, $true)) | Where-Object {
    # Hijo DIRECTO del cuerpo del archivo, no "en algún lado que no sea una función".
    # `Test-Anidado` no alcanza acá: sólo busca funciones y scriptblocks, así que aceptaba un trap
    # metido en un `if`/`try`/loop de nivel de script — y ésos no se disparan (medido: ninguno
    # atrapó un error posterior). El chequeo de la limpieza, en la misma función, sí lo verificaba;
    # el del trap quedaba estrictamente más débil que su hermano.
    $_.Parent -is [System.Management.Automation.Language.NamedBlockAst] -and $_.Parent.Parent -eq $ast
  } | Sort-Object { $_.Extent.StartOffset }
  # SÓLO el primero. Medido: con dos traps en el mismo scope corre el que está declarado primero y
  # su `break` relanza, así que el segundo no llega a ejecutarse nunca. Iterando todos, alcanzaba
  # con poner un `trap { break }` ANTES del bueno para dejarlo muerto y pasar igual.
  foreach ($t in @($traps | Select-Object -First 1)) {
    $sts = @($t.Body.Statements)
    if ($sts.Count -eq 0) { continue }
    if (-not ($sts[-1] -is [System.Management.Automation.Language.BreakStatementAst])) { continue }
    $borra = $false
    foreach ($s in $sts) {
      # Sólo un nivel: la sentencia del trap, no algo escondido dentro de un if.
      if ($s -isnot [System.Management.Automation.Language.PipelineAst]) { continue }
      foreach ($e in $s.PipelineElements) {
        if ($e -isnot [System.Management.Automation.Language.CommandAst]) { continue }
        if ($e.GetCommandName() -ne $comando) { continue }
        if (Test-ArgumentoEs $e $argumento) { $borra = $true }
      }
    }
    if ($borra) { return $true }
  }
  return $false
}

# ¿El archivo importa el helper, y SÓLO de una de las dos formas que el repo usa?
#
# Esto es un conjunto CERRADO a propósito, y es el cambio de instrumento del 2026-09-02. La versión
# anterior era un detector ABIERTO —"¿hay algún dot-source cuyo objeto se PAREZCA a
# `lib/temp-workspace.ps1`?"— y todo detector abierto de este archivo fue evadido dentro de un
# turno: grep → tokens → AST, cada escalón documentado arriba en sus propios comentarios. El patrón
# no era casualidad: mientras el criterio sea "algo que se le parezca", siempre queda una grafía más.
#
# Las CINCO que seguían vivas, MEDIDAS contra el detector anterior antes de escribir esto: un stub
# en `tests/fake/lib/temp-workspace.ps1` (la subcadena no estaba anclada, y ese directorio además
# quedaba fuera del lint); un dot-source canónico seguido de otro a un stub; el dot-source metido
# dentro de un `if`; la variable de la forma 2 reasignada a un stub después de asignarla bien; y la
# variable asignada directamente a un literal ajeno. Las cinco pasaban en verde y las cinco están
# abajo como fixture.
#
# ⚠️ LO QUE ESTO **NO** LOGRA, y hay que decirlo porque la primera versión de este comentario
# afirmaba lo contrario: el conjunto cerrado **no elimina** el espacio de evasión, lo achica. Un
# review encontró SEIS grafías nuevas en un solo turno, todas verificadas ejecutando el predicado
# (ver la lista del borde declarado, más abajo). La razón es de fondo: acá se sigue aproximando
# ESTÁTICAMENTE una pregunta de identidad —"¿lo que quedó en scope es el helper de verdad?"— y esa
# pregunta sólo se responde exacto en runtime. La respuesta exacta va en un slice aparte.
#
# Las dos formas, verificadas por AST sobre el árbol el 2026-09-02:
#   1. `. (Join-Path $PSScriptRoot "lib\temp-workspace.ps1")`            — las 8 suites migradas
#   2. `$lib = Join-Path $PSScriptRoot "lib\temp-workspace.ps1"` + `. $lib` — sólo esta suite, que
#      necesita el path después para el probe de la parte C.
#
# Costo aceptado: una forma nueva legítima da rojo y hay que agregarla acá a mano. Es exactamente el
# rojo que se quiere cuando alguien cambia cómo se importa el helper. Contra conocido: mover `lib/`
# de lugar rompe las nueve suites a la vez.

# `Join-Path $PSScriptRoot "<relativo>"`, exacto: tres elementos, la raíz es $PSScriptRoot y el
# relativo es un literal que iguala. Nada de matchear el texto del Extent — matchear es justo lo que
# dejaba pasar `Join-Path $PSScriptRoot "fake\lib\temp-workspace.ps1"`.
function Test-JoinPathCanonico($nodo, [string]$relativo) {
  if ($nodo -isnot [System.Management.Automation.Language.CommandAst]) { return $false }
  if ($nodo.GetCommandName() -ne 'Join-Path') { return $false }
  $els = @($nodo.CommandElements)
  if ($els.Count -ne 3) { return $false }
  $raiz = $els[1]
  if ($raiz -isnot [System.Management.Automation.Language.VariableExpressionAst]) { return $false }
  if ($raiz.VariablePath.UserPath -ne 'PSScriptRoot') { return $false }
  $rel = $els[2]
  if ($rel -isnot [System.Management.Automation.Language.StringConstantExpressionAst]) { return $false }
  # Se normaliza SÓLO el separador: `lib/temp-workspace.ps1` es el mismo archivo y darle rojo sería
  # ruido. El resto del path no se normaliza ni se recorta, así que `fake\lib\...` no iguala.
  return ($rel.Value.Replace('/', '\') -eq $relativo)
}

# `(expr)` → la expresión de adentro, o $null si el paréntesis no envuelve exactamente una.
function Get-DentroDelParen($nodo) {
  if ($nodo -isnot [System.Management.Automation.Language.ParenExpressionAst]) { return $null }
  $p = $nodo.Pipeline
  if ($p -isnot [System.Management.Automation.Language.PipelineAst]) { return $null }
  $els = @($p.PipelineElements)
  if ($els.Count -ne 1) { return $null }
  return $els[0]
}

# La forma 2: la variable se asigna UNA sola vez, en el cuerpo del script, sin condición, con la
# forma canónica, y ANTES del dot-source. "Una sola vez" es lo que cierra la reasignación a un stub:
# con dos asignaciones la que vale es la última, y el predicado anterior se conformaba con que
# alguna nombrara el helper.
function Test-VariableCanonica($ast, [string]$nombre, [string]$relativo, [int]$offsetDelDotSource) {
  $asigs = @($ast.FindAll({
    param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst]
  }, $true) | Where-Object {
    $_.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and
    $_.Left.VariablePath.UserPath -eq $nombre -and
    # El filtro posicional va ANTES de contar, no después. Contando primero, una función auxiliar
    # con una variable local homónima —`function f { $lib = 1 }`, inofensiva porque vive en otro
    # scope— subía el conteo a dos y ponía la suite en ROJO sin que hubiera nada mal. Medido.
    #
    # SÓLO funciones, y no `Test-Anidado`. `Test-Anidado` también descarta los
    # `ScriptBlockExpressionAst`, y un scriptblock NO es un scope nuevo: `ForEach-Object` y
    # `Where-Object` ejecutan el suyo en el scope del llamador, así que una asignación ahí adentro
    # PISA la variable del script. Medido: usar `Test-Anidado` acá cerraba el falso rojo y abría a
    # cambio la reasignación a un stub envuelta en un pipe — un falso negativo, que es peor.
    # `& { $lib = ... }` sí es scope hijo y no pisa, pero acá cuenta igual: sobre-aproximar hacia el
    # rojo sobre código que nadie escribe es el lado correcto del error.
    -not (Test-DentroDeUnaFuncion $_)
  })
  if ($asigs.Count -ne 1) { return $false }
  $a = $asigs[0]
  # Comparación por texto y no contra [TokenKind]::Equals: `Equals` es además un método estático
  # heredado de System.Object, así que `::Equals` es ambiguo y resuelve al método.
  if ("$($a.Operator)" -ne 'Equals') { return $false }
  # No se re-chequea `Test-Anidado` acá: el filtro de arriba ya descartó las anidadas, así que
  # sería una línea que no puede ejecutarse. `Test-BajoCondicion` sí hace falta — una asignación
  # dentro de un `if` de nivel de script no está anidada y sí puede no ejecutarse.
  if (Test-BajoCondicion $a) { return $false }
  # Asignar DESPUÉS del dot-source no importa para lo que se importó, pero sí delata un archivo que
  # juega con la variable; y sin este orden, `. $lib` seguido de la única asignación pasaría.
  if ($a.Extent.StartOffset -ge $offsetDelDotSource) { return $false }
  if ($a.Right -isnot [System.Management.Automation.Language.PipelineAst]) { return $false }
  $els = @($a.Right.PipelineElements)
  if ($els.Count -ne 1) { return $false }
  return (Test-JoinPathCanonico $els[0] $relativo)
}

function Test-ImportaElHelper([string]$path, [string]$relativo) {
  $ast = Get-AstDe $path
  $ds = @($ast.FindAll({
    param($n)
    $n -is [System.Management.Automation.Language.CommandAst] -and $n.InvocationOperator -eq 'Dot'
  }, $true))
  if ($ds.Count -eq 0) { return $false }
  # TODOS los dot-sources del archivo, no "al menos uno". Con "al menos uno" la evasión es poner el
  # canónico y un stub abajo: medido contra el predicado anterior, pasaba en verde.
  foreach ($c in $ds) {
    # Mismas dos condiciones de posición que ya se les exigen al trap y a la limpieza final. Un
    # dot-source dentro de un `if` pasaba: el helper podía no llegar a importarse nunca.
    if (Test-Anidado $c) { return $false }
    if (Test-BajoCondicion $c) { return $false }
    $obj = $c.CommandElements[0]
    if ($null -eq $obj) { return $false }
    $interno = Get-DentroDelParen $obj
    if ($null -ne $interno -and (Test-JoinPathCanonico $interno $relativo)) { continue }
    if ($obj -is [System.Management.Automation.Language.VariableExpressionAst] -and
        (Test-VariableCanonica $ast $obj.VariablePath.UserPath $relativo $c.Extent.StartOffset)) { continue }
    return $false
  }
  return $true
}

# Los cuatro nombres del helper. Redefinir cualquiera después de importarlo es LA evasión que le
# queda al conjunto cerrado: el lint de arriba prohíbe tocar la raíz de %TEMP% directamente, así que
# para filtrar hay que pasar por el helper — y reemplazarlo localmente es la única forma de hacerlo
# sin escribir ninguna de las APIs que se vigilan.
#
# ---------------------------------------------------------------------------
# EL BORDE DECLARADO: lo que estos lints NO ven, verificado grafía por grafía
# ---------------------------------------------------------------------------
# Esta lista está MEDIDA, no imaginada: cada línea se ejecutó contra los predicados de este archivo
# el 2026-09-02. La versión anterior de este párrafo nombraba `& { function ... }` como evasión y
# NO lo es —el scriptblock corre en un scope hijo y la redefinición muere con él, verificado—,
# mientras omitía las seis que sí lo son. Un borde mal declarado es peor que no declararlo: manda a
# buscar donde no hay y deja de mirar donde sí.
#
# Reemplazan la VARIABLE que se dot-sourcea (los tres pasan en verde):
#   - `foreach ($lib in @('C:\stub.ps1')) { }` — el `foreach` deja la variable con el último valor
#     iterado y no es un `AssignmentStatementAst`, así que no lo cuenta nada.
#   - `Set-Variable -Name lib -Value 'C:\stub.ps1'` — tampoco es una asignación en el AST.
#   - `$script:lib = 'C:\stub.ps1'` — en el cuerpo del script `$script:lib` ES `$lib`, pero su
#     `UserPath` es `script:lib`, así que el conteo de asignaciones no lo ve.
#
# Reemplazan la RAÍZ del path (pasa en verde):
#   - `$PSScriptRoot = 'C:\fake'` antes del dot-source. `$PSScriptRoot` no es de sólo lectura, y el
#     predicado sólo mira que el nodo se LLAME así. Rompe la forma 1, que es la que usan las ocho.
#
# Reemplazan las FUNCIONES después de importarlas:
#   - `function global:New-TestRunRoot { }` / `script:` / `local:` — el `Name` del AST se guarda con
#     el prefijo de scope, así que no iguala ningún nombre de la lista.
#   - `Set-Item function:\New-TestRunRoot {...}` y `New-Item -Path function:` — no son
#     `FunctionDefinitionAst`.
#   - `Import-Module <stub.psm1>` desde FUERA de `tests/`. Dentro de `tests/` el barrido recursivo
#     ya mira los `.psm1`, pero `Import-Module` no es un dot-source y el conjunto cerrado no lo ve.
#
# No se persiguen una por una a propósito: perseguir grafías es el juego que este archivo ya perdió
# cinco veces. El chequeo de IDENTIDAD en runtime de la PARTE F —correr la suite y comparar
# `(Get-Command X).ScriptBlock.File` contra el archivo del helper— es inmune a la FORMA de la evasión
# (mide la identidad real en vez de aproximarla), así que caza cualquiera de estas grafías que esté
# PRESENTE en una suite que el probe corre. Pero cubre las cinco suites baratas (la misma lista que la
# parte E); las tres caras y esta misma suite siguen sólo con el estático de acá por costo, así que el
# estático de abajo NO es redundante: es la única red sobre esas cuatro. El borde de estas grafías se
# ACHICA —de "escapan a toda detección" a "escapan sólo al estático, y la parte F las caza sobre las
# cinco baratas"—, no desaparece. Qué grafías EJECUTA F como control y cuáles cubre por deducción está
# detallado en la parte F (F2), sin afirmar "las seis por ejecución".
$script:FuncionesDelHelper = @('New-TestRunRoot', 'Remove-TestRunRoot', 'New-TestWorkspace', 'New-TestTempPath')

function Get-RedefinicionesDelHelper([string]$path) {
  $ast = Get-AstDe $path
  return @($ast.FindAll({
    param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst]
  }, $true) | Where-Object { $_.Name -in $script:FuncionesDelHelper })
}

# A0b. Los predicados nuevos, contra fixtures que tienen que RECHAZAR. Sin estos controles, un
# `Test-ImportaElHelper` que devuelva siempre $true pasa el lint entero en verde — que es justo el
# modo de falla que este archivo persigue.
#
# El criterio de cada caso negativo es MECÁNICO, no histórico: **existe porque sin él se puede
# borrar una línea del predicado y la suite queda verde**. Eso es verificable corriendo el mutante
# correspondiente, y es lo único que se afirma acá.
#
# Deliberadamente NO se clasifica cada caso por su historia ("éste era un agujero del predicado
# viejo", "éste es sólo cobertura"). Dos versiones de este párrafo intentaron esa clasificación y
# las dos salieron con la atribución cambiada — la segunda decía que ocho de estos casos no eran
# agujeros del predicado anterior, y el predicado anterior los aceptaba a todos menos uno. En este
# repo los errores de atribución en prosa de procedimiento son el modo de falla recurrente, y lo
# que los cierra no es redactar mejor: es no afirmar lo que no se mide. La historia de cada caso
# está en `git log`, que no se desactualiza.
$casosDeImport = @(
  @{ ok = $true;  n = 'la forma 1 canónica';                          codigo = '. (Join-Path $PSScriptRoot "lib\temp-workspace.ps1")' }
  @{ ok = $true;  n = 'la forma 2 canónica (asignar y dot-sourcear)'; codigo = "`$lib = Join-Path `$PSScriptRoot `"lib\temp-workspace.ps1`"`n. `$lib" }
  @{ ok = $true;  n = 'la forma 1 con separador /';                   codigo = '. (Join-Path $PSScriptRoot "lib/temp-workspace.ps1")' }
  @{ ok = $false; n = 'un stub en fake/lib (la subcadena sin anclar)'; codigo = '. (Join-Path $PSScriptRoot "fake\lib\temp-workspace.ps1")' }
  @{ ok = $false; n = 'el canónico MÁS un stub abajo';                codigo = ". (Join-Path `$PSScriptRoot `"lib\temp-workspace.ps1`")`n. (Join-Path `$PSScriptRoot `"stub.ps1`")" }
  @{ ok = $false; n = 'el dot-source metido dentro de un if';         codigo = "if (`$true) { . (Join-Path `$PSScriptRoot `"lib\temp-workspace.ps1`") }" }
  # Una rama por cada tipo que `Test-BajoCondicion` enumera. Sin una por tipo, borrarle ese tipo a
  # la lista deja la suite verde: medido, el mutante que borraba `SwitchStatementAst` sobrevivía.
  # Cada fixture dispara exactamente un tipo (medido), pero la correspondencia NO es uno a uno: son
  # siete fixtures para seis tipos, porque `&&` y `||` disparan los dos `PipelineChainAst`.
  @{ ok = $false; n = 'el dot-source dentro de un switch';            codigo = "switch (1) { 1 { . (Join-Path `$PSScriptRoot `"lib\temp-workspace.ps1`") } }" }
  @{ ok = $false; n = 'el dot-source dentro de un try';               codigo = "try { . (Join-Path `$PSScriptRoot `"lib\temp-workspace.ps1`") } catch { }" }
  @{ ok = $false; n = 'el dot-source dentro de un foreach';           codigo = "foreach (`$i in 1..1) { . (Join-Path `$PSScriptRoot `"lib\temp-workspace.ps1`") }" }
  @{ ok = $false; n = 'el dot-source dentro de un trap';              codigo = "trap { . (Join-Path `$PSScriptRoot `"lib\temp-workspace.ps1`"); break }`n`$x = 1" }
  # `&&` y `||` son ejecución condicional igual que un `if`, y viven en su propio nodo
  # (`PipelineChainAst`) que la lista no tenía. Medido: el dot-source de la derecha de un `&&` no
  # se ejecuta si la izquierda falla, y pasaba como incondicional. El agujero era peor en
  # `Test-LimpiezaAlTerminar`, donde `<algo> && Remove-TestRunRoot $script:runRoot` contaba como
  # limpieza final garantizada.
  # Sobre-aproxima: `Test-BajoCondicion` sube por `Parent` y no distingue el lado de la cadena, así
  # que el operando IZQUIERDO —que sí se ejecuta siempre— también cuenta como condicional. Da rojo
  # sobre `Remove-TestRunRoot $script:runRoot && <algo>`, que sería correcto. Hoy no molesta a
  # nadie (ninguna suite usa `&&`/`||` en código, sólo dentro de strings) y el error va hacia el
  # rojo, que es el lado seguro. Los dos fixtures de abajo cubren el lado derecho.
  @{ ok = $false; n = 'el dot-source a la derecha de un &&';          codigo = "`$true && . (Join-Path `$PSScriptRoot `"lib\temp-workspace.ps1`")" }
  @{ ok = $false; n = 'el dot-source a la derecha de un ||';          codigo = "`$false || . (Join-Path `$PSScriptRoot `"lib\temp-workspace.ps1`")" }
  # Un dot-source dentro de una función importa el helper al scope de ESA función, así que las
  # cuatro funciones no existen para el resto de la suite (y si nadie la llama, no se importa
  # nada). `Test-Anidado` es lo único que lo ataja: sin este caso, borrar esa guarda pasaba en
  # verde. El fixture llama a la función a propósito — el motivo del rojo es el scope, no la falta
  # de llamada.
  @{ ok = $false; n = 'el dot-source dentro de una función';          codigo = "function Setup { . (Join-Path `$PSScriptRoot `"lib\temp-workspace.ps1`") }`nSetup" }
  # `Join-Path` de PS7 acepta `-AdditionalChildPath`: con cuatro elementos, `$els[2]` sigue siendo
  # el relativo canónico pero el path resuelto es otro archivo. Sin este caso, aflojar el
  # `$els.Count -ne 3` a `-lt 3` pasaba en verde.
  @{ ok = $false; n = 'Join-Path con un segmento de más';             codigo = '. (Join-Path $PSScriptRoot "lib\temp-workspace.ps1" "..\stub.ps1")' }
  # El caso legítimo que NO puede dar rojo: una función auxiliar con una variable local que se llama
  # igual. Medido: el conteo de asignaciones las contaba y ponía la suite en rojo sin nada malo.
  @{ ok = $true;  n = 'una variable local homónima en una función';   codigo = "`$lib = Join-Path `$PSScriptRoot `"lib\temp-workspace.ps1`"`nfunction f { `$lib = 1 }`n. `$lib" }
  # Un scriptblock NO es un scope nuevo: `ForEach-Object` y `Where-Object` ejecutan el suyo en el
  # scope del llamador, así que una asignación ahí adentro PISA la variable del script. Medido.
  # Estos dos casos existen porque un fix anterior los abrió: al descartar las asignaciones
  # "anidadas" para cerrar el falso rojo de la función, se descartaron también las de scriptblock,
  # y la reasignación a un stub envuelta en un pipe pasó a verde. Cambiar un falso positivo por un
  # falso negativo es peor que el bug original.
  @{ ok = $false; n = 'la variable reasignada dentro de ForEach-Object'; codigo = "`$lib = Join-Path `$PSScriptRoot `"lib\temp-workspace.ps1`"`n1..1 | ForEach-Object { `$lib = 'C:\stub.ps1' }`n. `$lib" }
  @{ ok = $false; n = 'la variable reasignada dentro de Where-Object';   codigo = "`$lib = Join-Path `$PSScriptRoot `"lib\temp-workspace.ps1`"`n@(1) | Where-Object { `$lib = 'C:\stub.ps1'; `$true } | Out-Null`n. `$lib" }
  # La guarda de orden: dot-sourcear ANTES de la única asignación. Sin este caso, borrarla pasaba
  # en verde. Que además reviente en runtime (la variable está vacía) no es excusa para que el
  # lint lo acepte: el lint es lo que se lee para saber qué está permitido.
  @{ ok = $false; n = 'el dot-source ANTES de la asignación';         codigo = ". `$lib`n`$lib = Join-Path `$PSScriptRoot `"lib\temp-workspace.ps1`"" }
  @{ ok = $false; n = 'la variable reasignada a un stub';             codigo = "`$lib = Join-Path `$PSScriptRoot `"lib\temp-workspace.ps1`"`n`$lib = Join-Path `$PSScriptRoot `"stub.ps1`"`n. `$lib" }
  @{ ok = $false; n = 'la variable asignada a un literal ajeno';      codigo = "`$lib = `"C:\otro\lib\temp-workspace.ps1`"`n. `$lib" }
  # La forma 2 apuntando a un stub, hermana exacta del caso de la forma 1. El caso de arriba NO la
  # cubre: corta antes, en el chequeo de que el lado derecho sea un pipeline, así que la llamada a
  # `Test-JoinPathCanonico` desde `Test-VariableCanonica` quedaba sin ningún test — medido,
  # devolver `$true` ahí sobrevivía la suite entera.
  @{ ok = $false; n = 'la forma 2 apuntando a un stub en fake/lib';   codigo = "`$lib = Join-Path `$PSScriptRoot `"fake\lib\temp-workspace.ps1`"`n. `$lib" }
  # La mitad "scriptblock" de `Test-Anidado`, del lado del dot-source. Sin estos dos, cambiarlo por
  # `Test-DentroDeUnaFuncion` acá pasaba en verde — y `& { . (Join-Path …) }` importa el helper a un
  # scope hijo, o sea que las cuatro funciones no quedan disponibles para la suite.
  @{ ok = $false; n = 'el dot-source dentro de un ForEach-Object'; codigo = "1..1 | ForEach-Object { . (Join-Path `$PSScriptRoot `"lib\temp-workspace.ps1`") }" }
  @{ ok = $false; n = 'el dot-source dentro de un & { }';         codigo = "& { . (Join-Path `$PSScriptRoot `"lib\temp-workspace.ps1`") }" }
  # El `Join-Path` canónico a la vista, pero el pipeline devuelve OTRA cosa. Sin estos dos, aflojar
  # el "un solo elemento de pipeline" a `-lt 1` aceptaba dot-sourcear un stub con el path bueno
  # escrito al lado. Uno por cada forma de import.
  @{ ok = $false; n = 'forma 1 con un pipeline que devuelve otra cosa'; codigo = ". (Join-Path `$PSScriptRoot `"lib\temp-workspace.ps1`" | ForEach-Object { 'C:\stub.ps1' })" }
  @{ ok = $false; n = 'forma 2 con un pipeline que devuelve otra cosa'; codigo = "`$lib = Join-Path `$PSScriptRoot `"lib\temp-workspace.ps1`" | ForEach-Object { 'C:\stub.ps1' }`n. `$lib" }
  @{ ok = $false; n = 'un archivo sin ningún dot-source';             codigo = '$x = 1' }
)
# Piso, y por CLASE: la lista es el único control de que `Test-ImportaElHelper` no devuelve siempre
# lo mismo. Sin negativos, un predicado que acepta todo pasa; sin positivos, uno que rechaza todo
# también. Contar el total no distingue ninguno de los dos casos.
$acepta = @($casosDeImport | Where-Object { $_.ok })
$rechaza = @($casosDeImport | Where-Object { -not $_.ok })
Assert ($acepta.Count -ge 3) "hay casos que el conjunto cerrado debe ACEPTAR (hay: $($acepta.Count))"
Assert ($rechaza.Count -ge 10) "hay casos que debe RECHAZAR (hay: $($rechaza.Count))"
# Y por MEMBRESÍA, no sólo por cantidad: con el piso solo, borrar los siete fixtures de rama dejaba
# `$rechaza.Count` en 11 — todavía por encima del piso de 10, así que todo verde— y revivía los
# mutantes que esos fixtures matan.
# Cada nombre de esta lista clava una rama concreta del predicado; si borrás un fixture, esto dice
# CUÁL falta en vez de dejar pasar un conteo que sigue alcanzando.
$ramasExigidas = @(
  'el dot-source metido dentro de un if'
  'el dot-source dentro de un switch'
  'el dot-source dentro de un try'
  'el dot-source dentro de un foreach'
  'el dot-source dentro de un trap'
  'el dot-source a la derecha de un &&'
  'el dot-source a la derecha de un ||'
  'el dot-source dentro de una función'
  'Join-Path con un segmento de más'
  'el dot-source ANTES de la asignación'
  'la variable reasignada dentro de ForEach-Object'
  'la variable reasignada dentro de Where-Object'
  'la variable reasignada a un stub'
  'la variable asignada a un literal ajeno'
  'la forma 2 apuntando a un stub en fake/lib'
  'un stub en fake/lib (la subcadena sin anclar)'
  'un archivo sin ningún dot-source'
  # Éste es estructuralmente único: es el ÚNICO fixture del conjunto con dos dot-sources, así que
  # es el único que puede matar el mutante "alcanza con que ALGÚN dot-source sea canónico" — que
  # es la diferencia entre el conjunto cerrado y un detector abierto. Sin pinnearlo, borrarlo
  # dejaba el conteo por encima del piso y el mutante revivía en verde. Medido.
  'el canónico MÁS un stub abajo'
)
$nombresDeCaso = @($casosDeImport | ForEach-Object { $_.n })
$ramasFaltantes = @($ramasExigidas | Where-Object { $_ -notin $nombresDeCaso })
Assert ($ramasFaltantes.Count -eq 0) "están todos los fixtures de rama (faltan: $($ramasFaltantes -join ' | '))"
# Y que el fixture nombrado siga SIENDO un intento de importar el helper. Atar sólo el nombre deja
# vaciar el `codigo`: medido, poniendo `'$x = 1'` en el caso del `foreach` el assert seguía verde
# (un archivo sin dot-source también se rechaza), y con eso `LoopStatementAst` quedaba sin cobertura
# — es el único de los seis tipos que un solo fixture cubre, así que nada más lo tapaba.
# La única excepción es el caso cuyo contenido ES la ausencia del dot-source: exigirle que nombre
# el helper lo convertiría en otro caso.
$ramasVacias = @($ramasExigidas | Where-Object { $_ -ne 'un archivo sin ningún dot-source' } | ForEach-Object {
  $n = $_
  $caso = @($casosDeImport | Where-Object { $_.n -eq $n })[0]
  if ($null -eq $caso -or $caso.codigo -notlike "*temp-workspace.ps1*") { $n }
})
Assert ($ramasVacias.Count -eq 0) `
  "y cada fixture de rama sigue nombrando el helper (vaciados: $($ramasVacias -join ' | '))"
foreach ($ci in $casosDeImport) {
  # Un archivo por caso: juntos, un solo rechazo taparía a los demás.
  $fx = New-TestTempPath $script:runRoot "import" ".ps1"
  $ci.codigo | Set-Content -LiteralPath $fx -Encoding UTF8
  $r = Test-ImportaElHelper $fx 'lib\temp-workspace.ps1'
  $verbo = if ($ci.ok) { 'acepta' } else { 'RECHAZA' }
  Assert ($r -eq $ci.ok) "el conjunto cerrado $verbo : $($ci.n)"
}

# El detector de redefiniciones, con su control negativo: sin el negativo, uno que devuelva siempre
# vacío pasa el lint de abajo en verde sobre un repo lleno de stubs.
#
# UN FIXTURE POR NOMBRE, no uno solo. Con un único fixture sobre `New-TestRunRoot`, recortar la
# lista a ese nombre pasaba en verde (medido: fue un mutante que sobrevivió), y el nombre que más
# importa es otro: redefinir `Remove-TestRunRoot` deja filtrar TODO sin tocar ninguna de las APIs
# de %TEMP% que el otro lint vigila.
foreach ($fn in $script:FuncionesDelHelper) {
  $fxRedef = New-TestTempPath $script:runRoot "redef" ".ps1"
  ". (Join-Path `$PSScriptRoot `"lib\temp-workspace.ps1`")`nfunction $fn { }" |
    Set-Content -LiteralPath $fxRedef -Encoding UTF8
  $enc = @(Get-RedefinicionesDelHelper $fxRedef)
  Assert ($enc.Count -eq 1) "se ve una suite que redefine $fn después de importarlo (vistas: $($enc.Count))"
  # Membresía, no sólo cantidad: un detector que devolviera cualquier función daría 1 igual.
  Assert ($enc.Count -eq 1 -and $enc[0].Name -eq $fn) "y la que ve es $fn, no otra"
}
# Piso de la lista: si alguien la vacía o la recorta, el foreach de arriba mide menos y todo pasa.
Assert ($script:FuncionesDelHelper.Count -eq 4) `
  "la lista de funciones del helper tiene las cuatro (tiene: $($script:FuncionesDelHelper.Count))"
# Y que la lista siga siendo LA del helper: si el helper gana una quinta función, queda sin
# protección contra redefinición y en silencio. La lista se compara contra el archivo, no se cree.
$delHelper = @((Get-AstDe $lib).FindAll({
  param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst]
}, $true) | ForEach-Object { $_.Name })
$faltan = @($delHelper | Where-Object { $_ -notin $script:FuncionesDelHelper })
Assert ($faltan.Count -eq 0) `
  "la lista cubre todas las funciones del helper (sin cubrir: $($faltan -join ', '))"

$fxSinRedef = New-TestTempPath $script:runRoot "sinredef" ".ps1"
@'
. (Join-Path $PSScriptRoot "lib\temp-workspace.ps1")
function Assert-Algo { param($x) return $x }
'@ | Set-Content -LiteralPath $fxSinRedef -Encoding UTF8
Assert ((Get-RedefinicionesDelHelper $fxSinRedef).Count -eq 0) `
  "no confunde una función cualquiera con una redefinición del helper"

# A0c. `Test-TrapDeScript` y `Test-LimpiezaAlTerminar` contra fixtures sintéticos.
#
# Hasta acá estos dos predicados sólo se invocaban contra las nueve suites reales, que son
# correctas, así que **sólo podían dar verde**: medido, nueve mutaciones distintas sobre ellos
# sobrevivían la suite entera. Un chequeo cuya única forma de fallar es que alguien escriba una
# suite mala no es una red, es una nota.
#
# El caso del `break` es el que más importa y el que más tiempo estuvo sin test: con `continue` el
# trap se traga el aborto y la suite sigue, así que termina con exit 0 y "TODOS LOS TESTS PASARON"
# después de haber abortado. Es la única condición de este bloque que no es sobre la limpieza sino
# sobre no mentir el resultado.
$casosDeTrap = @(
  @{ ok = $true;  n = 'el trap canónico';                    codigo = "trap { Remove-TestRunRoot `$script:runRoot; break }`n`$x = 1" }
  @{ ok = $false; n = 'el trap termina en continue';         codigo = "trap { Remove-TestRunRoot `$script:runRoot; continue }`n`$x = 1" }
  @{ ok = $false; n = 'el trap sin la limpieza';             codigo = "trap { break }`n`$x = 1" }
  @{ ok = $false; n = 'el trap borra OTRA raíz';             codigo = "trap { Remove-TestRunRoot `$otra; break }`n`$x = 1" }
  @{ ok = $false; n = 'el trap metido en una función';       codigo = "function f { trap { Remove-TestRunRoot `$script:runRoot; break } }`n`$x = 1" }
  @{ ok = $false; n = 'un trap vacío ANTES del bueno';       codigo = "trap { break }`ntrap { Remove-TestRunRoot `$script:runRoot; break }`n`$x = 1" }
  @{ ok = $false; n = 'la limpieza escondida en un if del trap'; codigo = "trap { if (`$true) { Remove-TestRunRoot `$script:runRoot }; break }`n`$x = 1" }
  # Un elemento de pipeline que NO es un comando, dentro del trap. Sin este caso, borrar la guarda
  # `$e -isnot [CommandAst]` no es equivalente: revienta con "does not contain a method named
  # 'GetCommandName'" sobre un `CommandExpressionAst`. El caso sigue siendo de RECHAZO (no hay
  # limpieza de la raíz), pero ahora el predicado tiene que llegar a decirlo sin explotar.
  @{ ok = $false; n = 'un elemento no-comando dentro del trap'; codigo = "trap { `$x; break }`n`$y = 1" }
  # Y el mismo, pero CON la limpieza al lado: acá el veredicto correcto es aceptar, así que si el
  # predicado explota antes de llegar al comando, el caso se pone rojo.
  @{ ok = $true;  n = 'un no-comando y la limpieza en el mismo trap'; codigo = "trap { `$x; Remove-TestRunRoot `$script:runRoot; break }`n`$y = 1" }
  # El filtro posicional del trap exige ser hijo DIRECTO del cuerpo del archivo, y su comentario
  # dice que existe porque un trap metido en un `if`/`try`/loop de nivel de script no se dispara.
  # Ese caso no tenía fixture: sólo estaba el de la función, que `Test-Anidado` también rechaza, así
  # que aflojar el filtro a `-not (Test-Anidado $_)` pasaba en verde y reintroducía la regresión.
  @{ ok = $false; n = 'el trap dentro de un if de nivel de script'; codigo = "if (`$true) { trap { Remove-TestRunRoot `$script:runRoot; break } }`n`$x = 1" }
  @{ ok = $false; n = 'el trap dentro de un try de nivel de script'; codigo = "try { trap { Remove-TestRunRoot `$script:runRoot; break } } catch { }`n`$x = 1" }
  @{ ok = $false; n = 'el trap dentro de un foreach de nivel de script'; codigo = "foreach (`$i in 1..1) { trap { Remove-TestRunRoot `$script:runRoot; break } }`n`$x = 1" }
)
# Piso y membresía, igual que las otras cinco listas del archivo. Sin esto, vaciar `$casosDeTrap`
# deja el `foreach` sin iteraciones, cero asserts y la suite verde — con lo cual un
# `Test-TrapDeScript` que devuelva siempre `$true` pasaría A0c Y las nueve suites reales. Sería la
# misma propiedad que este bloque existe para eliminar, reintroducida en el bloque mismo.
Assert ($casosDeTrap.Count -ge 7) "A0c: están los casos de trap (hay: $($casosDeTrap.Count))"
Assert (@($casosDeTrap | Where-Object { -not $_.ok }).Count -ge 6) "A0c: y la mayoría son de RECHAZO"
# El del `continue` va pinneado por nombre: es la única condición del bloque que no es sobre la
# limpieza sino sobre no mentir el resultado, y es la que más tiempo estuvo sin test.
Assert ('el trap termina en continue' -in @($casosDeTrap | ForEach-Object { $_.n })) `
  "A0c: está el caso del trap que termina en continue (el que deja reportar verde tras abortar)"
foreach ($ct in $casosDeTrap) {
  $fx = New-TestTempPath $script:runRoot "trapfx" ".ps1"
  $ct.codigo | Set-Content -LiteralPath $fx -Encoding UTF8
  $r = Test-TrapDeScript $fx 'Remove-TestRunRoot' '$script:runRoot'
  Assert ($r -eq $ct.ok) "el chequeo del trap $(if ($ct.ok) { 'acepta' } else { 'RECHAZA' }) : $($ct.n)"
}

$casosDeLimpieza = @(
  @{ ok = $true;  n = 'la limpieza suelta al final';         codigo = "`$x = 1`nRemove-TestRunRoot `$script:runRoot" }
  @{ ok = $true;  n = 'la limpieza con -Root nombrado';      codigo = "`$x = 1`nRemove-TestRunRoot -Root `$script:runRoot" }
  @{ ok = $false; n = 'sin ninguna limpieza';                codigo = '$x = 1' }
  @{ ok = $false; n = 'la limpieza sólo dentro de un if';    codigo = "if (`$true) { Remove-TestRunRoot `$script:runRoot }" }
  @{ ok = $false; n = 'la limpieza sólo dentro de un switch'; codigo = "switch (1) { 1 { Remove-TestRunRoot `$script:runRoot } }" }
  @{ ok = $false; n = 'la limpieza sólo dentro de un try';   codigo = "try { Remove-TestRunRoot `$script:runRoot } catch { }" }
  @{ ok = $false; n = 'la limpieza sólo dentro del trap';    codigo = "trap { Remove-TestRunRoot `$script:runRoot; break }`n`$x = 1" }
  @{ ok = $false; n = 'la limpieza sólo dentro de una función'; codigo = "function f { Remove-TestRunRoot `$script:runRoot }" }
  # El lado de la limpieza del agujero de `&&`: sin `PipelineChainAst` en `Test-BajoCondicion`,
  # esto contaba como limpieza final garantizada y no lo es.
  @{ ok = $false; n = 'la limpieza a la derecha de un &&';   codigo = "`$true && Remove-TestRunRoot `$script:runRoot" }
  @{ ok = $false; n = 'la limpieza de OTRA raíz';            codigo = "Remove-TestRunRoot `$otraCosa" }
  # `Remove-TestRunRoot $otra $script:runRoot` borra `$otra` y manda la raíz a `$args` sin decir
  # nada: la función no tiene CmdletBinding, así que el extra no da error.
  @{ ok = $false; n = 'la raíz en segunda posición';         codigo = "Remove-TestRunRoot `$otra `$script:runRoot" }
  # `Test-ArgumentoEs` tiene dos ramas que ningún caso de arriba distingue: la que saltea los
  # parámetros nombrados que NO son `-Root`, y la forma con dos puntos (`-Param:$valor`), donde el
  # valor viaja en `.Argument` en vez de en el elemento siguiente. Sin estos dos casos, borrar
  # cualquiera de las dos ramas pasaba en verde.
  @{ ok = $true;  n = 'otro parámetro nombrado antes de la raíz'; codigo = "Remove-TestRunRoot -Verbose `$script:runRoot" }
  @{ ok = $true;  n = 'un parámetro con dos puntos antes de la raíz'; codigo = "Remove-TestRunRoot -Verbose:`$true `$script:runRoot" }
  @{ ok = $true;  n = '-Root con dos puntos';                codigo = "Remove-TestRunRoot -Root:`$script:runRoot" }
  # El gemelo nombrado de 'la limpieza de OTRA raíz'. Sin él, hacer que la rama de `-Root` devuelva
  # `$true` sin comparar nada pasaba en verde, y `Remove-TestRunRoot -Root $otraCosa` contaba como
  # limpieza válida — borrando otra cosa y dejando la raíz en disco.
  @{ ok = $false; n = 'la limpieza con -Root de OTRA raíz';  codigo = "Remove-TestRunRoot -Root `$otraCosa" }
  # La mitad "scriptblock" de `Test-Anidado`, del lado de la limpieza. Un pipeline vacío no ejecuta
  # su bloque NUNCA, así que esto no limpia nada; sin este caso, cambiar `Test-Anidado` por
  # `Test-DentroDeUnaFuncion` acá pasaba en verde y lo aceptaba como limpieza garantizada.
  @{ ok = $false; n = 'la limpieza dentro de un ForEach-Object'; codigo = "@() | ForEach-Object { Remove-TestRunRoot `$script:runRoot }" }
  @{ ok = $false; n = 'la limpieza dentro de un & { }';      codigo = "& { Remove-TestRunRoot `$script:runRoot }" }
)
Assert ($casosDeLimpieza.Count -ge 11) "A0c: están los casos de limpieza final (hay: $($casosDeLimpieza.Count))"
Assert (@($casosDeLimpieza | Where-Object { -not $_.ok }).Count -ge 9) "A0c: y la mayoría son de RECHAZO"
# El del `&&` va pinneado: es el lado de la limpieza del agujero que este slice abrió y cerró.
Assert ('la limpieza a la derecha de un &&' -in @($casosDeLimpieza | ForEach-Object { $_.n })) `
  "A0c: está el caso de la limpieza a la derecha de un && (el lado de la limpieza del agujero de PipelineChainAst)"
foreach ($cl in $casosDeLimpieza) {
  $fx = New-TestTempPath $script:runRoot "limpfx" ".ps1"
  $cl.codigo | Set-Content -LiteralPath $fx -Encoding UTF8
  $r = Test-LimpiezaAlTerminar $fx 'Remove-TestRunRoot' '$script:runRoot'
  Assert ($r -eq $cl.ok) "el chequeo de la limpieza final $(if ($cl.ok) { 'acepta' } else { 'RECHAZA' }) : $($cl.n)"
}

$suites = @(Get-ChildItem -LiteralPath $PSScriptRoot -Filter "*.tests.ps1" -File)
# Contra el piso conocido: sin esto, un glob que no matchea nada deja el foreach vacío y las
# aserciones de abajo "pasan" sin haber leído un solo archivo.
Assert ($suites.Count -ge 15) "el lint ve las suites del repo (encontradas: $($suites.Count))"

# TODOS los .ps1 bajo tests/, recursivo — no sólo `tests/*.tests.ps1` más `tests/lib/**`. El recorte
# anterior dejaba afuera cualquier directorio que no fuera `lib/`, y ya existe uno: `tests/fixtures/`.
# Un .ps1 ahí adentro podía crear temporales en la raíz de %TEMP%, con el glob incondicional y todo,
# sin que ninguno de los dos lints lo mirara. La exclusión del helper es por PATH y no por nombre:
# con un `-ne "temp-workspace.ps1"` a secas, un `lib/helpers/temp-workspace.ps1` con una fuga adentro
# quedaba sin mirar (medido).
#
# La enumeración va en su propia función para poder probarla contra un árbol SINTÉTICO, y no es
# ceremonia: hoy el único .ps1 en un subdirectorio de tests/ es el helper, y el helper se excluye,
# así que sobre el árbol real el conjunto recursivo y el no recursivo son IDÉNTICOS (15 y 15,
# medido). Ningún piso por cantidad puede distinguirlos — borrarle el `-Recurse` pasaría en verde y
# el agujero de `tests/fixtures/` volvería sin que nada se ponga rojo. El árbol sintético sí lo ve.
function Get-Ps1DeArbol([string]$raiz, [string]$excluido) {
  # `-Include` y no `-Filter`: hay que mirar los TRES tipos de archivo de PowerShell, no sólo
  # `.ps1`. Un `.psm1` bajo `tests/` era invisible para los dos lints (medido), y una suite puede
  # traérselo con `Import-Module`, que no es un dot-source y por lo tanto tampoco lo ve el conjunto
  # cerrado — la evasión quedaba completa.
  #
  # `-Force` porque `-Recurse` sin él NO baja a directorios ocultos ni lista archivos ocultos
  # (medido): un `tests\.oculto\fuga.ps1` no se miraba. Es el mismo recorte silencioso que este
  # trabajo vino a eliminar.
  return @(Get-ChildItem -LiteralPath $raiz -Include "*.ps1", "*.psm1", "*.psd1" -File -Recurse -Force |
    Where-Object { $_.FullName -ne $excluido })
}

$arbol = New-TestWorkspace $script:runRoot "arbol"
$subFixtures = Join-Path $arbol "fixtures"
$subFake = Join-Path (Join-Path $arbol "fake") "lib"
$subOculto = Join-Path $arbol ".oculto"
[IO.Directory]::CreateDirectory($subFixtures) | Out-Null
[IO.Directory]::CreateDirectory($subFake) | Out-Null
[IO.Directory]::CreateDirectory($subOculto) | Out-Null
(Get-Item -LiteralPath $subOculto -Force).Attributes = 'Directory,Hidden'
$exclSintetico = Join-Path $arbol "raiz.tests.ps1"
'$x = 1' | Set-Content -LiteralPath $exclSintetico -Encoding UTF8
'$x = 1' | Set-Content -LiteralPath (Join-Path $subFixtures "en-fixtures.ps1") -Encoding UTF8
'$x = 1' | Set-Content -LiteralPath (Join-Path $subFake "temp-workspace.ps1") -Encoding UTF8
'$x = 1' | Set-Content -LiteralPath (Join-Path $subFixtures "modulo.psm1") -Encoding UTF8
'$x = 1' | Set-Content -LiteralPath (Join-Path $subOculto "escondido.ps1") -Encoding UTF8
$vistos = Get-Ps1DeArbol $arbol $exclSintetico
# Cantidad Y membresía. Contar solo la cantidad deja pasar una lista que ve cuatro archivos
# equivocados; es la misma trampa que este repo ya documenta como "contar hallazgos en vez de
# atribuirlos". Cada uno de los cuatro cubre un recorte distinto del enumerador, y por eso van
# nombrados de a uno: un assert que sólo contara cuatro no diría CUÁL falta.
$nombresVistos = @($vistos | ForEach-Object { $_.Name })
Assert ($vistos.Count -eq 4) "la enumeración baja a los subdirectorios (vio: $($vistos.Count) de 4)"
Assert ('en-fixtures.ps1' -in $nombresVistos) "la enumeración ve un .ps1 en un subdirectorio nuevo (fixtures/)"
Assert ('temp-workspace.ps1' -in $nombresVistos) "la enumeración ve un stub anidado (fake/lib/)"
Assert ('modulo.psm1' -in $nombresVistos) "la enumeración ve un .psm1 (se puede traer con Import-Module)"
Assert ('escondido.ps1' -in $nombresVistos) "la enumeración baja a un directorio OCULTO"
Assert ($exclSintetico -notin @($vistos | ForEach-Object { $_.FullName })) `
  "la enumeración excluye el archivo excluido"

$todosLosPs1 = Get-Ps1DeArbol $PSScriptRoot $lib
# Membresía, no cantidad. Un `-ge $suites.Count` es tautológico acá: `$todosLosPs1` es por
# construcción un superconjunto de `$suites` (misma raíz, recursivo, y lo único excluido es el
# helper, que no es `*.tests.ps1`), así que no puede fallar nunca. Esto sí puede: si el enumerador
# deja de ver la raíz, o el filtro de extensiones se rompe, alguna suite falta y se dice cuál.
$rutasVistas = @($todosLosPs1 | ForEach-Object { $_.FullName })
$suitesSinMirar = @($suites | Where-Object { $_.FullName -notin $rutasVistas } | ForEach-Object { $_.Name })
Assert ($suitesSinMirar.Count -eq 0) `
  "el lint recursivo mira todas las suites (sin mirar: $($suitesSinMirar -join ', '))"
Assert ($lib -notin @($todosLosPs1 | ForEach-Object { $_.FullName })) `
  "el helper queda excluido del conjunto (es el único que puede tocar la raíz de %TEMP%)"
foreach ($f in $todosLosPs1) {
  $rel = $f.FullName.Substring($PSScriptRoot.Length + 1)
  $u = Get-UsosDeTempDirecto $f.FullName
  Assert ($u.Count -eq 0) "$rel : no construye temporales en la raíz de %TEMP% (usos directos: $($u.Count))"
  # Ningún archivo fuera del helper puede definir sus funciones. El helper está excluido del
  # conjunto, así que sus cuatro definiciones legítimas no se cuentan acá.
  $rd = Get-RedefinicionesDelHelper $f.FullName
  Assert ($rd.Count -eq 0) "$rel : no redefine ninguna función del helper (redefiniciones: $($rd.Count))"
}

$conHelper = 0
foreach ($s in $suites) {
  $usa = @((Get-AstDe $s.FullName).FindAll({
    param($n)
    $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'New-TestRunRoot'
  }, $true))
  if ($usa.Count -gt 0) {
    $conHelper++
    Assert (Test-ImportaElHelper $s.FullName 'lib\temp-workspace.ps1') `
      "$($s.Name): importa el helper con una de las dos formas admitidas"
    Assert (Test-TrapDeScript $s.FullName 'Remove-TestRunRoot' '$script:runRoot') `
      "$($s.Name): el trap borra la raíz desde el cuerpo del script y termina en break"
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
# ésta llegue a su propio New-TestRunRoot. La dirección del error es benigna y está verificada en
# un log instrumentado del colector: sería un verde de más, nunca un rojo de más, porque el
# `$fresco` y la `$larga` no caen por edad. Se acepta a cambio de que los fixtures sean
# reclamables. (Corridas concurrentes de esta suite se probaron varias veces sin fallos, pero no
# con un método anotado acá: tomalo como "no se observaron problemas", no como una medición.)
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

# ---------------------------------------------------------------------------
# E. Ejecutar y mirar: ¿una suite deja rastros?
# ---------------------------------------------------------------------------
# Los chequeos de la parte A miran la FORMA del código, y tres turnos seguidos de review les
# encontraron otra grafía que los evade — la última, una limpieza puesta debajo del `exit` final:
# está en el cuerpo del script, sin anidar y sin condición, así que la parte A la acepta, y no se
# ejecuta nunca. Ninguna lectura del árbol distingue "está escrito" de "se ejecuta".
# Esto lo mide directo: corre una suite de verdad como subproceso y cuenta lo que quedó en la raíz
# de %TEMP% bajo su prefijo. Es la propiedad que interesa, sin intermediarios.
# El prefijo, por AST. Leerlo con [regex]::Match sobre el archivo crudo tomaba el PRIMER match,
# comentarios incluidos: medido, una sola línea comentada que mencionara `New-TestRunRoot "zz"`
# hacía que se midiera un prefijo inexistente y una fuga REAL pasara en verde. Es la misma trampa
# que este archivo documenta treinta líneas más arriba —un grep cuenta las menciones en prosa— y
# la forma de comentario que la dispara ya existe en el helper.
function Get-PrefijoDe([string]$path) {
  $ast = Get-AstDe $path
  $cmds = @($ast.FindAll({
    param($n)
    $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'New-TestRunRoot'
  }, $true))
  if ($cmds.Count -eq 0) { return '' }
  $arg = $cmds[0].CommandElements[1]
  if ($arg -is [System.Management.Automation.Language.StringConstantExpressionAst]) { return $arg.Value }
  return ''
}

# UNA sola función de medición, usada por el assert que importa Y por su control positivo. El turno
# anterior la había partido en dos casi idénticas, así que el control validaba una copia: cegar la
# medición de verdad (filtrar por un PID que no existe) pasaba en verde. Un control positivo que no
# ejercita el mismo código que el assert no controla nada.
function Measure-RastrosDe([string]$suitePath, [string]$prefijo, [string[]]$Extra = @()) {
  $raiz = Split-Path $script:runRoot -Parent
  $log  = New-TestTempPath $script:runRoot "salida" ".txt"
  # Foto previa además del filtro por PID: Windows recicla PIDs, así que una raíz vieja abandonada
  # por una fuga anterior podría llevar el mismo número y contarse como nueva.
  $antes = @(Get-ChildItem -LiteralPath $raiz -Force -ErrorAction SilentlyContinue |
    Where-Object { $_.Name.StartsWith("$prefijo-run-") } | ForEach-Object { $_.Name })
  # Start-Process para saber el PID del hijo. El run root lleva el PID adentro, así que filtrar por
  # `<prefijo>-run-<pid-del-hijo>-` mide EXACTAMENTE lo que dejó esta corrida y nada más.
  # Comparar antes/después por prefijo no alcanza: la ventana es toda la corrida de la suite (~7 s
  # medidos) y otro proceso corriendo la MISMA suite en esa ventana aparecía como rastro nuevo —
  # medido, un rojo espurio a la primera. En este repo las corridas concurrentes son la norma, que
  # es la misma razón por la que el colector filtra por edad en vez de barrer por glob.
  # Los paths van entrecomillados a mano: Start-Process une la lista con espacios y no quotea, así
  # que con un repo bajo "Bootstrap Skills" pwsh recibía dos argumentos partidos y salía 64.
  # stderr también se redirige: los tres casos de "E (no feliz)" abortan a propósito, y sin esto
  # sus bloques de error rojo salen por la consola del padre y hacen que una corrida verde se lea
  # como rota. No cambia ningún assert; cambia si el resultado es legible.
  $logErr = New-TestTempPath $script:runRoot "salida-err" ".txt"
  $p = Start-Process -FilePath "pwsh" -ArgumentList (@("-NoProfile", "-File", "`"$suitePath`"") + $Extra) `
    -NoNewWindow -PassThru -Wait -RedirectStandardOutput $log -RedirectStandardError $logErr
  # Devuelve PATHS completos, no nombres ni objetos: el que consume esto los borra, y una mezcla de
  # tipos hace que el borrado apunte a cualquier lado sin fallar. Costó un rastro filtrado.
  $mios = @(Get-ChildItem -LiteralPath $raiz -Force -ErrorAction SilentlyContinue |
    Where-Object { $_.Name.StartsWith("$prefijo-run-$($p.Id)-") -and $_.Name -notin $antes } |
    ForEach-Object { $_.FullName })
  # La salida del hijo se conserva: sin ella, una falla ajena en la suite de referencia pone en rojo
  # esta suite sin decir por qué.
  $salida = if (Test-Path -LiteralPath $log) { Get-Content -LiteralPath $log } else { @() }
  # stderr se DEVUELVE, no sólo se redirige. Redirigirlo y no devolverlo mejoraba el verde a costa
  # del rojo: antes, una suite que reventaba con un error terminante lo mostraba en consola; con la
  # redirección sola, el operador veía `exit 1` y nada más.
  $salidaErr = if (Test-Path -LiteralPath $logErr) { Get-Content -LiteralPath $logErr } else { @() }
  return @{ nuevos = $mios; exit = $p.ExitCode; salida = $salida; salidaErr = $salidaErr }
}

# CINCO de las OCHO suites ejecutables, no una.
#
# El denominador es ocho, no nueve. Nueve suites usan el helper, pero la novena es ESTA, y la parte
# E no puede ejecutarla a ningún precio: se llamaría a sí misma en recursión. Su exclusión es
# estructural, no económica — la primera versión de este comentario decía "las nueve" y atribuía su
# exclusión al costo, que es falso.
#
# De las ocho ejecutables, la lista es la mitad barata de una medición de duración hecha el
# 2026-09-02, UNA corrida por suite:
#
#   apply-env 4,5 s | export-shareable 9,3 | gen-mcp-json 9,5 | copy-scaffold 19,9 | alignment-gate 21,1
#   review-loop-docs-gate 142,9 | review-loop-trigger 258,2 | review-marker 258,8
#
# Son n=1 y dependen de la carga de la máquina: remedidas bajo carga (con otra sesión corriendo las
# mismas suites) dieron hasta 1,5× y `copy-scaffold`/`alignment-gate` intercambian el orden. Los
# números absolutos no se pueden tomar al pie de la letra; lo que sí es robusto bajo las dos
# mediciones es la DECISIÓN, porque la diferencia entre los dos grupos es de un orden de magnitud.
#
# Las ocho suman 724 s y TRES son el 91 % del costo. Correr las ocho llevaría esta suite por encima
# de los 10 minutos — que es el techo de la tool con la que se la corre, no un timeout configurado
# en el repo: acá no hay CI ni runner con timeout — y dejaría de poder correrse de una. Una suite
# que no se corre no es una red. Las cinco baratas suman ~64 s y llevan la cobertura de 1/8 a 5/8.
# Entra `export-shareable`, que es justamente la que tenía el glob incondicional.
#
# Las tres caras quedan afuera a sabiendas: su higiene la cubren los chequeos estáticos de la parte
# A, que es estrictamente menos que ejecutarlas.
#
# ⚠️ `export-shareable` MUTA EL ÁRBOL DEL REPO mientras corre: escribe un
# `skills/bootstrap-ai-project/LEAK-TEST.md` de fixture y lo borra en un `finally`. Correr esta
# suite ahora arrastra esa escritura, y si el hijo muere entre el `Set-Content` y el `finally` el
# archivo queda. Se declara acá porque contradice de frente el argumento que este mismo archivo usa
# en la parte "E (no feliz)" para justificar las suites de juguete ("mutar el árbol contamina a los
# reviewers en paralelo, ya pasó"), y porque el residuo se verifica explícitamente después del
# foreach en vez de confiar en el `finally`.
$suitesBaratas = @('apply-env', 'export-shareable', 'gen-mcp-json', 'copy-scaffold', 'alignment-gate')
# Cantidad Y unicidad: con sólo la cantidad, duplicar un nombre mantiene el 5 y baja la cobertura
# real a cuatro suites en silencio. Contar no atribuye.
Assert ($suitesBaratas.Count -eq 5) "E: la lista de suites a ejecutar tiene las cinco (tiene: $($suitesBaratas.Count))"
Assert (@($suitesBaratas | Sort-Object -Unique).Count -eq 5) "E: y las cinco son distintas entre sí"
# Unicidad cierra el duplicado, no la SUSTITUCIÓN: cambiar 'export-shareable' por otra suite real
# mantiene el 5 y la unicidad, y pierde justamente la que motiva la lista (es la que tenía el glob
# incondicional, y la única de las cinco que toca el árbol). Membresía por nombre.
$baratasFaltantes = @(@('export-shareable', 'apply-env') | Where-Object { $_ -notin $suitesBaratas })
Assert ($baratasFaltantes.Count -eq 0) `
  "E: están las dos que motivan la lista — export-shareable (tenía el glob) y apply-env (fugaba archivos sueltos). Faltan: $($baratasFaltantes -join ', ')"
foreach ($nombreSuite in $suitesBaratas) {
  $suiteReal = Join-Path $PSScriptRoot "$nombreSuite.tests.ps1"
  Assert (Test-Path -LiteralPath $suiteReal) "E: existe la suite $nombreSuite"
  if (-not (Test-Path -LiteralPath $suiteReal)) { continue }
  # El prefijo no se escribe a mano: un literal que no coincida con el que la suite usa haría pasar
  # el assert de abajo sin haber mirado nada.
  $prefijoReal = Get-PrefijoDe $suiteReal
  Assert ($prefijoReal -ne '') "E: se pudo leer el prefijo de $nombreSuite ('$prefijoReal')"
  if ($prefijoReal -eq '') { continue }
  $r = Measure-RastrosDe $suiteReal $prefijoReal
  Assert ($r.exit -eq 0) "E: $nombreSuite corre en verde (exit $($r.exit))"
  if ($r.exit -ne 0) {
    $r.salida | Select-String -Pattern '^FAIL:' | ForEach-Object { Write-Host "      | $_" }
    # stderr también, y acotado: una suite que revienta antes del primer Assert no imprime ningún
    # `FAIL:`, así que sin esto el rojo no dice nada.
    $r.salidaErr | Select-Object -First 5 | ForEach-Object { Write-Host "      ! $_" }
  }
  # "su raíz de corrida", no "rastros" a secas: `Measure-RastrosDe` sólo ve entradas que empiezan
  # con `<prefijo>-run-<pid>-`. Un archivo suelto con otro nombre es invisible para este filtro —y
  # esa es justamente la forma de la fuga histórica de `apply-env` (34 `wscfg-*.json` sueltos, la
  # mitad del problema que este trabajo arregló). El filtro por PID es correcto y deliberado
  # (evita falsos rojos por concurrencia); lo que no se puede es afirmar más de lo que mide.
  Assert ($r.nuevos.Count -eq 0) "E: $nombreSuite no deja su raíz de corrida en %TEMP% (nuevas: $($r.nuevos.Count))"
}
# El residuo del fixture de fuga de `export-shareable`, verificado y no asumido: su `finally` no
# corre si el proceso muere antes.
#
# Dos límites de este assert, declarados porque no se pueden cerrar desde acá:
# 1. DETECTA, no remedia. Borrarlo sería peor: el path del fixture es FIJO (sin PID ni GUID), así
#    que una corrida concurrente podría estar usándolo en ese momento.
# 2. Por lo mismo, puede dar un rojo espurio: dos corridas simultáneas de esta suite —o una de
#    `export-shareable` sola— comparten ese path, y el muestreo puede caer en la ventana entre el
#    `Set-Content` de una y el `finally` de la otra. Es la única medición de este archivo que NO
#    puede filtrarse por PID, justamente porque el path es compartido. La solución de fondo es que
#    `export-shareable` arme su fixture de fuga en un clon temporal; queda fuera de este slice.
# El path va en el mensaje: si aparece, hay que borrarlo a mano, y además pone en rojo a
# `shareable-leaks` porque el contenido del fixture es un marcador de fuga dentro del payload
# exportable.
# El mensaje NO atribuye el residuo a esta corrida: sin una foto previa no se puede distinguir el
# que dejó una corrida anterior abortada —que es justamente el escenario que este assert dice
# vigilar— del que dejó ésta. `Measure-RastrosDe` resuelve eso con `$antes`; acá no se puede,
# porque el path es fijo y compartido. Así que se reporta el hecho, no la causa.
$residuoFuga = Join-Path $PSScriptRoot "..\skills\bootstrap-ai-project\LEAK-TEST.md"
Assert (-not (Test-Path -LiteralPath $residuoFuga)) `
  "E: no hay residuo del fixture de fuga de export-shareable en el árbol ($residuoFuga)"

# Control positivo: una suite de juguete con la limpieza puesta DESPUÉS del `exit` final — el
# defecto exacto que la parte A acepta y no puede ver. Sin este control, el assert de arriba pasaría
# igual con una medición que no mide nada. Es sintética y no una copia de la real porque una copia
# fuera de `tests/` resuelve mal su `$PSScriptRoot` y aborta antes de crear nada: mediría cero por
# el motivo equivocado, que es justo la clase de falso verde que este archivo persigue.
$fugada = New-TestTempPath $script:runRoot "suite-fugada" ".ps1"
# El path del helper va como ARGUMENTO, no interpolado en un literal: un usuario con apóstrofe en
# el nombre rompía el probe con un error de sintaxis, que se lee como "la medición está rota". Es
# el mismo arreglo que ya está noventa líneas más arriba, en Invoke-Probe.
@'
param([string]$Lib)
$ErrorActionPreference = "Stop"
. $Lib
$script:runRoot = New-TestRunRoot 'ctrlfuga'
trap { Remove-TestRunRoot $script:runRoot; break }
New-TestWorkspace $script:runRoot "caso" | Out-Null
exit 0
Remove-TestRunRoot $script:runRoot
'@ | Set-Content -LiteralPath $fugada -Encoding UTF8

$rc = Measure-RastrosDe $fugada "ctrlfuga" @("-Lib", "`"$lib`"")
Assert ($rc.exit -eq 0) "E (control): la suite de juguete sale en verde, como saldría la de verdad"
# Este control espera verde, así que si se pone rojo hay que poder ver por qué. Los tres casos de
# "E (no feliz)" abortan a propósito y ahí el stderr sería ruido; acá no.
if ($rc.exit -ne 0) { $rc.salidaErr | Select-Object -First 5 | ForEach-Object { Write-Host "      ! $_" } }
Assert ($rc.nuevos.Count -ge 1) "E (control positivo): con la limpieza DESPUÉS del exit, la medición sí ve el rastro (nuevos: $($rc.nuevos.Count))"
# El rastro del control hay que barrerlo, y SÓLO el propio: filtrado por el PID del hijo. La versión
# anterior borraba todo `ctrlfuga-*` que encontrara, así que dos corridas concurrentes de esta suite
# se robaban la evidencia entre sí — el mismo glob incondicional que este trabajo salió a eliminar,
# reintroducido en la suite que lo vigila.
foreach ($n in $rc.nuevos) { Remove-TestRunRoot $n }
# Y se verifica que se hayan ido: el control fabrica una fuga a propósito, así que si el barrido no
# la levanta esta suite se convierte en la que más rastros deja de todas.
$quedan = @($rc.nuevos | Where-Object { Test-Path -LiteralPath $_ })
Assert ($quedan.Count -eq 0) "E (control): el rastro que fabricó el control quedó barrido (quedan: $($quedan.Count))"

# ---------------------------------------------------------------------------
# E (no feliz). Las suites que NO terminan bien
# ---------------------------------------------------------------------------
# Todo lo de arriba mide suites que terminan en verde, y el camino que de verdad filtraba workspaces
# en este repo era el otro: la limpieza del final es una sentencia suelta y, con
# $ErrorActionPreference=Stop, cualquier error terminante fuera de un Assert la saltea. Para eso
# existe el `trap`. La parte C ya lo prueba con un probe EN PROCESO — pero un probe no puede medir
# qué queda en la raíz de %TEMP% después de que el proceso se muere, que es la propiedad que importa.
#
# Van sobre suites de juguete y no sobre las reales por costo y por seguridad: forzar a
# `copy-scaffold` a abortar pide mutarla, y mutar el árbol contamina a los reviewers en paralelo (ya
# pasó en este repo). En sintéticas cuesta milisegundos y el camino ejercitado es el mismo: mismo
# helper, mismo patrón de tres líneas, mismo trap.
# La suite de juguete escribe una MARCA en cuanto creó su workspace. Sin esa marca, este bloque
# tenía un agujero grande: el control positivo difiere del caso sólo en la línea del trap, y un
# control que difiere del caso sólo en X no puede detectar un defecto en X. Medido: con una llave
# sin cerrar en `$lineaTrap`, los dos casos con trap mueren en el PARSE —salen con 1, que es el
# exit esperado, y dejan cero rastros, que es el conteo esperado— así que los dos asserts pasaban
# en verde sin que el trap se hubiera ejecutado una sola vez. El `ParserError` va a stderr, que
# nadie lee. La parte C ya tenía este guard ("el probe con trap llegó a crear su raíz"); acá
# faltaba.
function New-SuiteDeJuguete([string]$prefijo, [bool]$conTrap, [string]$cuerpo, [string]$marca) {
  $p = New-TestTempPath $script:runRoot $prefijo ".ps1"
  # Salvo la marca, el trap es lo único que varía entre el caso y su control positivo (el prefijo
  # también cambia, pero sólo nombra el run root). Si variara algo más, el control estaría
  # validando otro programa.
  $lineaTrap = if ($conTrap) { 'trap { Remove-TestRunRoot $script:runRoot; break }' } else { '' }
  # Los dos paths entran por parámetro, no interpolados en el texto: un usuario con apóstrofe en el
  # nombre rompía el probe con un error de sintaxis, que se lee como "la medición está rota".
  @"
param([string]`$Lib, [string]`$Marca)
`$ErrorActionPreference = "Stop"
. `$Lib
`$script:runRoot = New-TestRunRoot '$prefijo'
$lineaTrap
New-TestWorkspace `$script:runRoot "caso" | Out-Null
Set-Content -LiteralPath `$Marca -Value "vivo" -Encoding UTF8
$cuerpo
"@ | Set-Content -LiteralPath $p -Encoding UTF8
  return $p
}

$casosNoFelices = @(
  # Así terminan las suites de verdad cuando hay fallas: limpian y recién después salen con 1.
  @{ n = 'una suite que FALLA limpia igual';        prefijo = 'ctrlfalla';   conTrap = $true;  deja = $false
     cuerpo = "Remove-TestRunRoot `$script:runRoot`nexit 1" }
  # El `throw` saltea la limpieza del final; si el trap no la levanta, el workspace queda.
  @{ n = 'una suite que ABORTA limpia por el trap'; prefijo = 'ctrlabort';   conTrap = $true;  deja = $false
     cuerpo = "throw 'aborto simulado'`nRemove-TestRunRoot `$script:runRoot" }
  # Control positivo, y no es opcional: es lo único que distingue "el trap limpió" de "la suite de
  # juguete nunca llegó a crear nada". Un error de sintaxis en el here-string de arriba daría cero
  # rastros en los dos casos anteriores y los dos pasarían en verde por el motivo equivocado. Sin el
  # trap, la MISMA suite tiene que filtrar.
  @{ n = 'control positivo: la misma, SIN el trap'; prefijo = 'ctrlsintrap'; conTrap = $false; deja = $true
     cuerpo = "throw 'aborto simulado'`nRemove-TestRunRoot `$script:runRoot" }
)
# Atribución, no cantidad: lo que importa no es "hay tres casos", es que EXISTA el control positivo.
# Reemplazar el tercero por otro `deja = $false` deja el count en 3, todo verde, y desaparece el
# único control del bloque. Es la trampa que este repo documenta como contar en vez de atribuir.
Assert (@($casosNoFelices | Where-Object { $_.deja }).Count -eq 1) `
  "E (no feliz): hay exactamente un control positivo"
Assert (@($casosNoFelices | Where-Object { -not $_.deja }).Count -eq 2) `
  "E (no feliz): y dos casos que NO deben dejar rastros"
# Atribuir sobre `deja` no alcanza: lo que hace control al control es `conTrap`. Medido, con sólo
# los dos asserts de arriba se podía poner `conTrap = $true` en el tercero y los cinco asserts del
# bloque seguían verdes — con las tres suites de juguete llevando trap, o sea sin demostrar nada
# sobre el trap. Estas dos condiciones son las que atan el par:
$elControl = @($casosNoFelices | Where-Object { $_.deja -and -not $_.conTrap })
Assert ($elControl.Count -eq 1) `
  "E (no feliz): el control positivo es el que NO lleva trap (con trap y sin trap no son intercambiables)"
# Y el control tiene que correr el MISMO cuerpo que el caso que controla; si no, compara dos
# programas distintos y su rastro no dice nada sobre el trap.
$elAbortado = @($casosNoFelices | Where-Object { -not $_.deja -and $_.conTrap -and $_.cuerpo -like "throw*" })
Assert ($elAbortado.Count -eq 1 -and $elControl.Count -eq 1 -and $elControl[0].cuerpo -eq $elAbortado[0].cuerpo) `
  "E (no feliz): el control corre el mismo cuerpo que el caso que aborta (sólo cambia el trap)"
foreach ($cnf in $casosNoFelices) {
  $marca = New-TestTempPath $script:runRoot "marca" ".txt"
  $tp = New-SuiteDeJuguete $cnf.prefijo $cnf.conTrap $cnf.cuerpo $marca
  $rnf = Measure-RastrosDe $tp $cnf.prefijo @("-Lib", "`"$lib`"", "-Marca", "`"$marca`"")
  # Prueba de vida ANTES que nada: si la suite de juguete no llegó a crear su workspace, los dos
  # asserts de abajo se satisfacen por el motivo equivocado.
  Assert (Test-Path -LiteralPath $marca) `
    "E (no feliz): $($cnf.n) — la suite de juguete llegó a crear su workspace (el escenario es real)"
  Assert ($rnf.exit -ne 0) "E (no feliz): $($cnf.n) — no sale con 0 (exit $($rnf.exit))"
  if ($cnf.deja) {
    Assert ($rnf.nuevos.Count -ge 1) "E (no feliz, control positivo): $($cnf.n) — SÍ deja rastro (nuevos: $($rnf.nuevos.Count))"
  } else {
    Assert ($rnf.nuevos.Count -eq 0) "E (no feliz): $($cnf.n) — no deja rastros (nuevos: $($rnf.nuevos.Count))"
  }
  # Barrido filtrado por el PID del hijo, igual que arriba: un glob por prefijo les robaría la
  # evidencia a las corridas concurrentes de esta misma suite.
  foreach ($nx in $rnf.nuevos) { Remove-TestRunRoot $nx }
  $quedanNf = @($rnf.nuevos | Where-Object { Test-Path -LiteralPath $_ })
  Assert ($quedanNf.Count -eq 0) "E (no feliz): $($cnf.n) — lo que haya dejado quedó barrido (quedan: $($quedanNf.Count))"
}

# ---------------------------------------------------------------------------
# F. Identidad en runtime: las funciones que quedan en scope, ¿SON el helper?
# ---------------------------------------------------------------------------
# Todo lo de la parte A mira la FORMA del código y aproxima estáticamente una pregunta de IDENTIDAD:
# "lo que quedó en scope, ¿es el helper de verdad?". El conjunto cerrado achica la evasión pero no la
# elimina — el borde declarado de la parte A (tabla en el comentario de $script:FuncionesDelHelper)
# lista grafías que lo pasan: la familia de redefinición (function global:/script:/local:,
# Set-Item function:, New-Item -Path function: -Force, Import-Module de un .psm1 de afuera) y la de
# redirección del import (foreach/Set-Variable/$script:lib). ($PSScriptRoot= no redirige a otro
# archivo: hace FALLAR el import, así que cae con el "import fallido" de F2, no acá.) Perseguirlas una
# por una es el juego que este archivo ya perdió cinco veces.
#
# Esto no aproxima: corre la suite en un runspace anidado y compara, por cada función del helper,
# `(Get-Command X).ScriptBlock.File` contra el archivo canónico del helper. El mecanismo es inmune a
# la FORMA de la evasión porque mide la identidad real: cualquier redefinición deja `.File` en otro
# archivo (o en null), y cualquier redirección del import carga las funciones desde otro archivo.
# Verificado empíricamente el 2026-09-03 (spikes): el probe distingue el helper real de una
# redefinición (por función global:/script:/local:, Set-Item, New-Item -Force, .psm1 y scriptblock
# fileless) y de un import fallido o redirigido (las funciones vienen de otro archivo, o quedan sin
# definir → null). Lo que F2 EJECUTA como control y lo que queda cubierto por el argumento de
# identidad se detalla abajo, caso por caso: no se afirma "las seis por ejecución", se afirma lo que
# cada assert corre.

# Corre una suite en un runspace anidado y devuelve las funciones del helper cuya identidad NO es el
# helper canónico. El runspace anidado es lo que hace esto posible: el `exit 0/1` con el que terminan
# las suites se contiene ahí adentro y no mata a este proceso (verificado). La suite se dot-sourcea
# POR PATH para preservar su $PSScriptRoot —sin él una suite real no resuelve su propio import—, y la
# tabla de funciones se lee del MISMO runspace después del Invoke.
#
# La comparación es igualdad exacta contra el path canónico, con `-ne` (case-insensitive, como los
# paths de Windows) y `GetFullPath` para normalizar separadores. Un `.File` vacío o null —el caso de
# una función redefinida sin archivo de respaldo— cuenta como identidad rota: no es el helper.
function Test-IdentidadEnRuntime([string]$suitePath, [string]$helperCanonico) {
  $esperado = [System.IO.Path]::GetFullPath($helperCanonico)
  $lector = @'
param($fns)
$o = @{}
foreach ($f in $fns) {
  $c = Get-Command $f -ErrorAction SilentlyContinue
  $o[$f] = if ($c -and $c.ScriptBlock) { $c.ScriptBlock.File } else { $null }
}
$o
'@
  $ps = [powershell]::Create()
  try {
    # El path de la suite va como literal single-quoted, NO interpolado con comillas dobles: un
    # %TEMP% con un `$` o un backtick (ambos legales en Windows) rompería `. "$suitePath"` — el
    # dot-source apuntaría a otro lado y las cuatro darían falso-marcadas. Es el mismo escape que
    # Get-LiteralDePath aplica a los paths embebidos en las suites sintéticas; acá aplica al de la
    # suite bajo prueba.
    [void]$ps.AddScript(". " + (Get-LiteralDePath $suitePath))
    # NO se atrapa la excepción de Invoke, a propósito. Casi todo lo que puede salir mal al cargar una
    # suite es NO terminante desde Invoke (medido 2026-09-03, bajo el ErrorActionPreference=Continue
    # por defecto del runspace hijo): un path errado, `$PSScriptRoot='C:\fake'`, un dot-source a un
    # inexistente, y —contra la intuición— un PARSE ERROR en la suite. Todos ésos dejan las funciones
    # sin definir y la rama null de abajo las marca. Lo ÚNICO que propaga terminante es un `throw`
    # explícito o un error bajo `$ErrorActionPreference='Stop'`; ahí, como no hay catch, la excepción
    # aborta temp-hygiene con su diagnóstico real en vez de relabelarse como "identidad rota". Un catch
    # acá convertía ese crash terminante en un falso "reemplaza el helper" (y encima no se disparaba
    # para los casos no terminantes, que son los más comunes).
    $ps.Invoke() | Out-Null
    $q = [powershell]::Create()
    try {
      $q.Runspace = $ps.Runspace
      [void]$q.AddScript($lector).AddArgument($script:FuncionesDelHelper)
      $tabla = $q.Invoke()[0]
    } finally { $q.Dispose() }
  } finally { $ps.Dispose() }
  $malas = @()
  foreach ($f in $script:FuncionesDelHelper) {
    $file = $tabla[$f]
    if ([string]::IsNullOrEmpty($file) -or ([System.IO.Path]::GetFullPath($file) -ne $esperado)) {
      $malas += $f
    }
  }
  return ,$malas
}

# Un path como literal PowerShell single-quoted, con los apóstrofes escapados (se doblan). Cuando hay
# que EMBEBER un path en el código de una suite (las sintéticas, y el dot-source de la suite bajo
# prueba en Test-IdentidadEnRuntime), el literal single-quoted es lo más robusto: a diferencia de
# `. "$p"` no interpola `$` ni backtick, y a diferencia de un literal crudo no lo rompe un apóstrofe
# (un %TEMP% bajo un usuario `O'Brien`). No es la única forma de esquivar el problema —la parte E lo
# resuelve pasando el path como ARGUMENTO en vez de embeberlo—, pero acá el path se embebe, así que
# se escapa. En un solo lugar porque varios sitios lo usan y una divergencia en el escape sería un
# bug latente.
function Get-LiteralDePath([string]$path) {
  return "'" + ($path -replace "'", "''") + "'"
}

# Suite sintética para el probe: dot-sourcea el helper real por path ABSOLUTO (vive en %TEMP%, así que
# su $PSScriptRoot no encuentra tests/lib/), aplica un sabotaje opcional, y sale 0.
function New-SuiteDeIdentidad([string]$prefijo, [string]$sabotaje) {
  $p = New-TestTempPath $script:runRoot $prefijo ".ps1"
  $libLit = Get-LiteralDePath $lib
  @"
. $libLit
$sabotaje
exit 0
"@ | Set-Content -LiteralPath $p -Encoding UTF8
  return $p
}

# F2. Controles sintéticos: uno por grafía de redefinición, un proxy de la familia de redirección, la
# rama del `.File` null, un import fallido, un control positivo de no-evasión, y una suite LIMPIA como
# control positivo del bloque. Sin la limpia un predicado que devolviera siempre "todas malas" pasaría
# todos los casos de sabotaje sin medir nada. Cada caso de sabotaje AFIRMA por función (atribución, no
# conteo): un caso que dijera sólo "hay marcadas" pasaría aunque marcara la función equivocada.
#
# QUÉ SE EJECUTA vs. QUÉ SE DEDUCE, explícito para no sobreafirmar:
#   - EJECUTADAS con control propio: function global:, function script:, function local:,
#     Set-Item function:, New-Item -Path function: -Force, Import-Module de un .psm1, y un scriptblock
#     fileless (para la rama .File null). Son las grafías de REDEFINICIÓN de la tabla del borde.
#   - PROXY (un control, no una grafía por control): la familia de REDIRECCIÓN del import
#     (foreach/Set-Variable/$script:lib) se cubre por su resultado observable —una suite que
#     dot-sourcea un stub—, no ejecutando cada grafía. Se declara así, no se afirma "verificada por
#     grafía".
#   - $PSScriptRoot= NO redirige a otro archivo: apunta el import a un dir inexistente y lo hace
#     FALLAR de forma NO terminante, así que las funciones quedan sin definir y la rama null las marca.
#     Cae en el mismo camino que el control "import fallido" de abajo, no en el proxy de redirección.
$fLimpia = New-SuiteDeIdentidad "idlimpia" ''
$mLimpia = Test-IdentidadEnRuntime $fLimpia $lib
Assert ($mLimpia.Count -eq 0) `
  "F (control positivo): una suite que importa el helper y no lo toca no marca ninguna (marcadas: $($mLimpia -join ', '))"

$casosDeIdentidad = @(
  @{ n = "function global:";  fn = 'New-TestRunRoot'
     sabotaje = 'function global:New-TestRunRoot { param($p) "X" }' }
  @{ n = "function script:";  fn = 'New-TestRunRoot'
     sabotaje = 'function script:New-TestRunRoot { param($p) "X" }' }
  @{ n = "function local:";   fn = 'New-TestRunRoot'
     sabotaje = 'function local:New-TestRunRoot { param($p) "X" }' }
  @{ n = "Set-Item function:"; fn = 'Remove-TestRunRoot'
     sabotaje = 'Set-Item -Path function:\Remove-TestRunRoot -Value { param($p) "X" }' }
  # New-Item necesita -Force: SIN él falla en un item existente (no terminante) y el helper queda
  # intacto — o sea sin -Force ni siquiera es una evasión. Con -Force sí redefine.
  @{ n = "New-Item -Path function: -Force"; fn = 'Remove-TestRunRoot'
     sabotaje = 'New-Item -Path function:\Remove-TestRunRoot -Value { param($p) "X" } -Force | Out-Null' }
  # Scriptblock fileless: su `.File` es null, así que ejercita específicamente la rama
  # `IsNullOrEmpty($file)` del predicado. Un mutante que borraba esa rama sobrevivía sin este caso —
  # ninguna otra suite produce un `.File` null.
  @{ n = "scriptblock fileless (.File null)"; fn = 'New-TestWorkspace'
     sabotaje = 'Set-Item -Path function:\New-TestWorkspace -Value ([scriptblock]::Create(''param($r,$n) "X"''))' }
)
foreach ($ci in $casosDeIdentidad) {
  $sp = New-SuiteDeIdentidad "ident" $ci.sabotaje
  $m = Test-IdentidadEnRuntime $sp $lib
  Assert ($m -contains $ci.fn) "F: $($ci.n) — el probe marca $($ci.fn) (marcadas: $($m -join ', '))"
}

# Import-Module de un .psm1 stub que redefine una función. El .psm1 va bajo la raíz de la corrida, no
# en tests/, porque la grafía que la parte A no ve es justamente la del módulo importado desde afuera.
$stubMod = New-TestTempPath $script:runRoot "stubmod" ".psm1"
'function New-TestWorkspace { param($r,$n) "X" }' | Set-Content -LiteralPath $stubMod -Encoding UTF8
$modLit = Get-LiteralDePath $stubMod
$fImport = New-SuiteDeIdentidad "idimport" "Import-Module $modLit -Force"
$mImport = Test-IdentidadEnRuntime $fImport $lib
Assert ($mImport -contains 'New-TestWorkspace') `
  "F: Import-Module de un .psm1 de afuera — el probe marca New-TestWorkspace (marcadas: $($mImport -join ', '))"

# Import FALLIDO (no terminante): una suite que dot-sourcea un archivo inexistente — el mismo error no
# terminante que produce `$PSScriptRoot = 'C:\fake'`. El helper nunca se define, así que las cuatro
# funciones quedan ausentes y la rama null las marca. NO ejercita ningún catch (Test-IdentidadEnRuntime
# no atrapa a propósito): un import fallido no terminante ni siquiera tira desde Invoke. Medido
# 2026-09-03 (turno 2 del review-loop): dot-sourcear un inexistente y `$PSScriptRoot='C:\fake'` son los
# dos no terminantes, y el probe los caza por AUSENCIA de las funciones, no por excepción.
$fFallo = New-TestTempPath $script:runRoot "idfallo" ".ps1"
$noExiste = Get-LiteralDePath (Join-Path $script:runRoot "no-existe-jamas.ps1")
@"
. $noExiste
exit 0
"@ | Set-Content -LiteralPath $fFallo -Encoding UTF8
$mFallo = Test-IdentidadEnRuntime $fFallo $lib
Assert ($mFallo.Count -eq 4) `
  "F: un import fallido deja las cuatro sin definir → las CUATRO marcadas por la rama null (marcadas: $($mFallo.Count))"

# El único error de carga TERMINANTE es un `throw` explícito (o uno bajo `-ErrorAction Stop`); ése SÍ
# propaga desde Invoke, y como Test-IdentidadEnRuntime no lo atrapa, aborta la corrida con la excepción
# real. Este control lo verifica: envuelve la llamada en su propio try/catch y exige que HAYA tirado.
# Es lo que ancla la decisión de NO poner un catch en el predicado — un parse error, en cambio, es no
# terminante y cae en el control de import fallido de arriba (medido; no confundir los dos).
$fThrow = New-SuiteDeIdentidad "idthrow" 'throw "identidad rota al cargar"'
$propago = $false
try { Test-IdentidadEnRuntime $fThrow $lib | Out-Null } catch { $propago = $true }
Assert $propago `
  "F: un error terminante al cargar (throw) propaga desde Test-IdentidadEnRuntime, no se traga (propagó: $propago)"

# Control positivo de NO-evasión: New-Item SIN -Force no pisa un item existente (el helper ya está
# importado) — falla no-terminante y el helper queda intacto, así que el probe NO debe marcar nada.
# Ancla con un test la afirmación de arriba ("sin -Force ni siquiera es evasión") en vez de sólo
# afirmarla, y prueba que el probe no da falso-positivo sobre una suite que intentó y no logró
# redefinir. Sin `-ErrorAction SilentlyContinue`: el error va al stream del runspace hijo (no a la
# consola) y es no terminante, así que no hace falta suprimirlo — y así el fixture es el natural.
$fNoForce = New-SuiteDeIdentidad "idnoforce" 'New-Item -Path function:\Remove-TestRunRoot -Value { param($p) "X" } | Out-Null'
$mNoForce = Test-IdentidadEnRuntime $fNoForce $lib
Assert ($mNoForce.Count -eq 0) `
  "F (control positivo): New-Item sin -Force no pisa el helper, el probe no marca nada (marcadas: $($mNoForce -join ', '))"

# Familia de REDIRECCIÓN del import, por PROXY: una suite que dot-sourcea un STUB en vez del helper.
# Las cuatro funciones vienen del stub, así que las cuatro salen marcadas. Ejercita el RESULTADO
# observable de las grafías foreach/Set-Variable/$script:lib (cargar desde otro archivo), no cada
# grafía literal — un control por deducción, declarado como tal.
$stubHelper = New-TestTempPath $script:runRoot "stubhelper" ".ps1"
@'
function New-TestRunRoot { param($p) "X" }
function Remove-TestRunRoot { param($p) }
function New-TestWorkspace { param($r,$n) "X" }
function New-TestTempPath { param($r,$n,$e) "X" }
'@ | Set-Content -LiteralPath $stubHelper -Encoding UTF8
$stubLit = Get-LiteralDePath $stubHelper
$fRedir = New-TestTempPath $script:runRoot "idredir" ".ps1"
@"
. $stubLit
exit 0
"@ | Set-Content -LiteralPath $fRedir -Encoding UTF8
$mRedir = Test-IdentidadEnRuntime $fRedir $lib
Assert ($mRedir.Count -eq 4) `
  "F: un import redirigido a un stub marca las CUATRO funciones (marcadas: $($mRedir.Count) — $($mRedir -join ', '))"

# El escape de Get-LiteralDePath, directo: ninguna suite de fixture tiene un apóstrofe en su path, así
# que este assert es lo ÚNICO que ejercita el `-replace "'","''"`. Un mutante que lo borraba sobrevivía
# sin él (la función quedaba sin test que la anclara).
Assert ((Get-LiteralDePath "C:\O'Brien\lib.ps1") -eq "'C:\O''Brien\lib.ps1'") `
  "F: Get-LiteralDePath escapa los apóstrofes (literal seguro para un path con comilla)"

# F3. Cobertura sobre las CINCO suites reales baratas (la misma lista que la parte E): ninguna
# reemplaza el helper. Es la red contra un agente futuro que edite una de estas cinco con una grafía
# invisible al estático. Corre en runspace anidado, no como subproceso.
# ⚠️ COSTO DECLARADO: esto vuelve a ejecutar las cinco (la parte E ya las corrió como subprocesos),
# ~64 s extra por corrida de temp-hygiene, y export-shareable muta el árbol del repo una SEGUNDA vez
# (su residuo se re-verifica más abajo, no se asume). Sigue holgadamente bajo el techo de 10 min. Los
# modelos de ejecución difieren (E: subproceso + medición de %TEMP% por PID; F: in-process +
# Get-Command), así que no se fusionan trivialmente en una sola corrida.
$cubiertas = 0
foreach ($nombreSuite in $suitesBaratas) {
  $suiteReal = Join-Path $PSScriptRoot "$nombreSuite.tests.ps1"
  $existe = Test-Path -LiteralPath $suiteReal
  Assert $existe "F: existe la suite real $nombreSuite"
  if (-not $existe) { continue }
  $mReal = Test-IdentidadEnRuntime $suiteReal $lib
  Assert ($mReal.Count -eq 0) `
    "F: la suite real '$nombreSuite' no reemplaza ninguna función del helper (marcadas: $($mReal -join ', '))"
  $cubiertas++
}
# Piso de cobertura PROPIO de F, no prestado de E: sin esto un `continue` silencioso (una suite
# renombrada) bajaría la cobertura de 5 a 4 sin ponerse en rojo. El assert de existencia de arriba ya
# lo caza, pero el piso lo ancla en F y no depende de que la parte E siga corriendo antes.
Assert ($cubiertas -eq $suitesBaratas.Count) `
  "F: el probe de identidad corrió sobre las $($suitesBaratas.Count) suites baratas (corrió: $cubiertas)"

# export-shareable corrió de nuevo acá dentro; su residuo se re-verifica, no se asume (su finally no
# corre si el proceso muere).
Assert (-not (Test-Path -LiteralPath $residuoFuga)) `
  "F: no quedó residuo del fixture de fuga de export-shareable tras la pasada de identidad ($residuoFuga)"

Remove-TestRunRoot $script:runRoot

Write-Host ""
if ($script:failures -gt 0) { Write-Host "$($script:failures) test(s) FALLARON"; exit 1 } else { Write-Host "TODOS LOS TESTS PASARON"; exit 0 }
