# tests/dieta-del-claude-md.tests.ps1 — runner sin Pester.
# Correr: pwsh -NoProfile -File tests/dieta-del-claude-md.tests.ps1
#
# Issue 14 — dieta del CLAUDE.md. El CLAUDE.md se carga ENTERO en cada request de cada proyecto
# bootstrapeado; dos de sus bullets contaban en prosa el mecanismo que un hook ya enforza solo
# (cache de mecanismo). Ese mecanismo se muda a docs/ai-workflow/AI_DEVELOPMENT_WORKFLOW.md, que el
# CLAUDE.md ya declara lectura obligatoria, y en el CLAUDE.md queda la REGLA mas un puntero.
#
# El criterio del corte, que es lo que esta suite fija: se muda lo que un hook enforza (que dispara
# el loop, que cuenta como documentacion, cual es el delta sin revisar, que archivo frena el primer
# Edit). NO se muda lo que ningun hook puede enforzar y el agente igual tiene que obedecer: declarar
# el cierre con el trailer, elegir el rigor, y puntuar la prosa segun el Step 5 de /slice-review.
#
# Por que existe: sin la mitad NEGATIVA (el CLAUDE.md ya no trae el mecanismo) la dieta se revierte
# sola en el primer turno que "aclare" algo, y nada se pone rojo. Y sin la mitad POSITIVA el
# mecanismo se puede borrar del doc destino y el CLAUDE.md queda apuntando a nada.
#
# QUE ESTA PROBADO NO-VACUO Y QUE NO. La suite se corrio entera contra 8d857a3 (el arbol de antes
# del cambio) en un worktree aparte: 68 FAIL y 42 ok. El metodo es ese y no otro: copiar este
# archivo a un checkout de 8d857a3 y contar las lineas FAIL/ok de su salida. Los 42 verdes NO
# estan probados por ese RED y se enumeran aca, uno por uno, en vez de taparlos con una
# justificacion global (la primera version de esta cabecera decia 'cubiertas por construccion' y
# eso no le aplicaba ni a la mitad del bloque que decia cubrir):
#
#   - Los guards, que son pisos y no verificaciones: las 4 raices, los 16 consumidores, el bullet
#     unico de review-loop y el del gate, las 5 rutas de govern, los 4 prefijos libres del gate y
#     la fila `light` de la tabla de Rigor.
#   - Los pins contra revert del bloque de coherencia: que el hook declare que no corre el grill
#     solo, y que el CLAUDE.md diga lo mismo. Ya lo decian en 8d857a3, asi que este RED no los
#     ejercita. Lo que SI los ejercita es una mutacion: invertir esa frase en el CLAUDE.md de la
#     raiz da 2 FAIL (medido), y era el mutante que sobrevivia antes de que existiera este bloque.
#   - `OFFER alignment` en el bullet del gate: la frase ya estaba en el bullet viejo.
#   - La mitad `no afirma lo contrario` del doc: en 8d857a3 la seccion no existia, asi que pasa
#     por vacuidad.
#
# Los otros dos anclajes tambien se probaron por mutacion, no por este RED: invertir la semantica
# del rigor en el doc de una sola raiz da 4 FAIL, y re-cachear la lista de gobierno en el
# CLAUDE.md redactada con dos puntos en vez de parentesis —la forma que el tripwire literal
# anterior dejaba pasar en verde— da 1 FAIL nombrando las 5 rutas.
$ErrorActionPreference = "Stop"
$repo = Split-Path $PSScriptRoot -Parent
$skills = @(Get-ChildItem (Join-Path $repo "skills") -Directory | Where-Object Name -like "bootstrap-*-project")
$script:failures = 0
function Assert($cond, $msg) {
  if ($cond) { Write-Host "ok:   $msg" } else { Write-Host "FAIL: $msg"; $script:failures++ }
}

# Las 4 raices: el repo (que se auto-bootstrapeo) y los 3 scaffolds. Se arma igual que en
# slice-review.tests.ps1 para que agregar una variante no deje una raiz sin mirar.
$raices = @(@{ label = "repo"; pre = $repo }) + @($skills | ForEach-Object {
  @{ label = $_.Name; pre = (Join-Path $_.FullName "assets\scaffold") }
})
Assert ($raices.Count -eq 4) "guard: se arman las 4 raices (armadas: $($raices.Count))"

$DOC = "docs/ai-workflow/AI_DEVELOPMENT_WORKFLOW.md"

# Las dos mitades NEGATIVAS derivan del clasificador que corresponde, no de una frase literal. Un
# tripwire literal ("no matter their extension (...)", ".scratch/") lo esquiva cualquier
# re-redaccion: se MIDIO que re-agregar el mecanismo entero al CLAUDE.md con la lista escrita con
# dos puntos en vez de parentesis deja la suite en verde. Lo que hay que prohibir es el PAYLOAD
# (las rutas), no la puntuacion. Mismo patron que review-loop-docs-gate.tests.ps1, que ya lee
# $govern del hook en vez de hardcodearlo.
function Get-RutasDeGobierno([string]$hookTxt) {
  $m = [regex]::Match($hookTxt, "(?m)^\s*\`$govern\s*=\s*'([^']+)'")
  if (-not $m.Success) { return @() }
  @($m.Groups[1].Value -split '\|(?![^(]*\))' | ForEach-Object {
    ($_ -replace '^\(\^\|/\)', '' -replace '\$$', '').Replace('\.', '.')
  })
}
# El gate no tiene una lista sola: Is-NonCode son tres reglas (extension, leafs, prefijos). Se lee
# SOLO el array de prefijos, que es el unico tramo que mapea 1:1 contra lo que la prosa enumera.
function Get-PrefijosLibres([string]$gateTxt) {
  $m = [regex]::Match($gateTxt, 'foreach \(\$d in @\(([^)]+)\)\)')
  if (-not $m.Success) { return @() }
  @([regex]::Matches($m.Groups[1].Value, "'([^']+)'") | ForEach-Object { $_.Groups[1].Value })
}

# La lista de rutas que gobiernan al agente, tal como la recorta review-loop-docs-gate.tests.ps1:
# entre parentesis, detras de "no matter their extension". Es el corazon del mecanismo mudado.
function Get-ListaDeGobierno([string]$txt) {
  ([regex]::Match($txt, 'no matter their extension \(([^)]+)\)')).Groups[1].Value
}

Write-Host ""
Write-Host "=== el mecanismo del review-loop vive en el doc del flujo, no en el CLAUDE.md ==="
foreach ($r in $raices) {
  $cF = Join-Path $r.pre "CLAUDE.md"
  $dF = Join-Path $r.pre ($DOC -replace '/', '\')
  if (-not (Test-Path -LiteralPath $cF)) { Assert $false "$($r.label): existe CLAUDE.md"; continue }
  if (-not (Test-Path -LiteralPath $dF)) { Assert $false "$($r.label): existe $DOC"; continue }
  $c = [IO.File]::ReadAllText($cF)
  $d = [IO.File]::ReadAllText($dF)

  # POSITIVA: el mecanismo esta COMPLETO en el doc destino. Se mide por la lista de gobierno, que es
  # lo unico del bullet que otra suite ya sabe comparar contra el clasificador del hook.
  Assert ((Get-ListaDeGobierno $d) -ne '') "$($r.label): $DOC trae la lista de rutas que gobiernan al agente"

  # NEGATIVA: el CLAUDE.md ya no cachea NINGUNA de las rutas, escrita como se escriba. Se anclan
  # con backticks: el puntero del bullet contiene `docs/ai-workflow/AI_DEVELOPMENT_WORKFLOW.md`,
  # y sin el backtick de cierre la ruta `docs/ai-workflow/` matchearia adentro del propio puntero.
  $hookF = Join-Path $r.pre ".claude\hooks\review-loop-trigger.ps1"
  if (-not (Test-Path -LiteralPath $hookF)) { Assert $false "$($r.label): existe el hook del trigger" }
  else {
    $rutas = Get-RutasDeGobierno ([IO.File]::ReadAllText($hookF))
    # Contar 5 no alcanza: con el escape sin deshacer (`\\.claude/`) la ruta nunca matchea la prosa
    # y el assert de abajo pasa en verde sobre un CLAUDE.md que SI la enumera. Medido, me paso.
    $rotas = @($rutas | Where-Object { $_ -match '[\\\\]' })
    Assert ($rutas.Count -eq 5 -and $rotas.Count -eq 0) "$($r.label): guard: 5 rutas de govern, sin escapes sin deshacer ($($rutas -join ', '))"
    if ($rutas.Count -eq 5) {
      $bl = [regex]::Matches($c, '(?ms)^- After implementation, run .*?(?=^-\s|^#|\z)')
      if ($bl.Count -eq 1) {
        $dentro = @($rutas | Where-Object { $bl[0].Value -match [regex]::Escape('`' + $_ + '`') })
        Assert ($dentro.Count -eq 0) "$($r.label): el bullet del loop ya no enumera rutas de gobierno [enumera: $($dentro -join ', ')]"
      }
    }
  }

  # El puntero: sin el, la regla que queda en el CLAUDE.md manda a ningun lado. Se ancla DENTRO del
  # bullet del loop, no en el archivo entero: el CLAUDE.md nombra el doc tambien en «Required
  # workflow docs», asi que un match suelto sobrevive a borrar el puntero.
  $m = [regex]::Matches($c, '(?ms)^- After implementation, run .*?(?=^-\s|\z)')
  Assert ($m.Count -eq 1) "$($r.label): guard: el CLAUDE.md tiene exactamente un bullet de review-loop (encontrados: $($m.Count))"
  if ($m.Count -ne 1) { continue }
  Assert ($m[0].Value -match [regex]::Escape($DOC)) "$($r.label): el bullet del loop remite a $DOC"
}

Write-Host ""
Write-Host "=== el mecanismo del alignment-gate vive en el doc del flujo, no en el CLAUDE.md ==="
# La lista de archivos que el gate deja pasar es el mecanismo: la computa el hook, no el agente.
# El `\r?` va porque estos archivos van en CRLF y el `$` de .NET ancla solo ante `\n`.
#
# ESTRUCTURA: primero el lado del CLAUDE.md y despues el del doc, cada uno con SU propia guarda y
# sin `continue`. Al reves —que es como nacio— el guard de la seccion del doc se llevaba puesto
# tambien todo el bloque del CLAUDE.md, que no depende de el: en el RED contra 8d857a3 quedaban
# 10 asserts por raiz sin ejecutar y la cabecera los declaraba "cubiertos por construccion" sin
# que eso les aplicara. Dos guardas independientes, ninguna suprime a la otra.
$SEC_GATE = '(?ms)^### The `alignment-gate` hook\r?$.*?(?=^#{2,4}\s|\z)'
# El corte del bullet admite `^#` ademas de `^- `: el del gate es el ULTIMO bullet de su seccion,
# asi que sin eso el match se desbordaba 571 caracteres adentro de `## Hard rules` y los asserts
# "sobre el bullet" miraban texto de la seccion siguiente.
$BULLET_GATE = '(?ms)^- Before the first code edit of a session.*?(?=^-\s|^#|\z)'
foreach ($r in $raices) {
  $cF = Join-Path $r.pre "CLAUDE.md"
  $dF = Join-Path $r.pre ($DOC -replace '/', '\\')
  if (-not (Test-Path -LiteralPath $cF) -or -not (Test-Path -LiteralPath $dF)) { Assert $false "$($r.label): existen CLAUDE.md y $DOC"; continue }
  $c = [IO.File]::ReadAllText($cF)
  $d = [IO.File]::ReadAllText($dF)

  # --- lado CLAUDE.md: la regla se queda, el mecanismo no -----------------------------------
  $bg = [regex]::Matches($c, $BULLET_GATE)
  Assert ($bg.Count -eq 1) "$($r.label): guard: el CLAUDE.md tiene exactamente un bullet del gate (encontrados: $($bg.Count))"
  if ($bg.Count -eq 1) {
    $gateF = Join-Path $r.pre ".claude\hooks\alignment-gate.ps1"
    if (-not (Test-Path -LiteralPath $gateF)) { Assert $false "$($r.label): existe el hook del gate" }
    else {
      $pref = Get-PrefijosLibres ([IO.File]::ReadAllText($gateF))
      Assert ($pref.Count -eq 4) "$($r.label): guard: se leyeron los 4 prefijos libres del gate ($($pref -join ', '))"
      if ($pref.Count -eq 4) {
        $cache = @($pref | Where-Object { $bg[0].Value -match [regex]::Escape('`' + $_ + '`') })
        Assert ($cache.Count -eq 0) "$($r.label): el bullet del gate ya no enumera los archivos que pasan libres [enumera: $($cache -join ', ')]"
      }
    }
    # El puntero, dentro del bullet: el CLAUDE.md nombra el doc tambien en la lista de lectura obligatoria.
    Assert ($bg[0].Value -match [regex]::Escape($DOC)) "$($r.label): el bullet del gate remite a $DOC"
    # La REGLA se queda: ningun hook puede obligar a ofrecer la alineacion, solo frena el primer Edit.
    Assert ($bg[0].Value -match '(?i)OFFER alignment') "$($r.label): el bullet del gate conserva la regla (ofrecer alineacion antes de codear)"
  }

  # --- lado doc: el mecanismo esta entero ----------------------------------------------------
  $sec = [regex]::Matches($d, $SEC_GATE)
  Assert ($sec.Count -eq 1) "$($r.label): $DOC tiene exactamente una seccion del alignment-gate (encontradas: $($sec.Count))"
  if ($sec.Count -eq 1) {
    foreach ($ruta in @('*.md', 'docs/', '.scratch/', '.agents/', '.claude/')) {
      Assert ($sec[0].Value -match [regex]::Escape('`' + $ruta + '`')) "$($r.label): la seccion del gate nombra $ruta entre lo que pasa libre"
    }
    Assert ($sec[0].Value -match 'PreToolUse') "$($r.label): la seccion del gate dice en que evento engancha"
  }
}

Write-Host "=== nadie sigue atribuyendole la lista de gobierno al CLAUDE.md ==="
# El review-loop y el slice-review le dicen al agente donde vive la lista de rutas que gobiernan.
# Mientras la lista vivia en el CLAUDE.md esa atribucion era cierta; desde la dieta es falsa, y
# manda al agente a grepear un archivo que ya no la tiene. Peor: el Step 5 de /slice-review le
# ordena "confirm the rule literally exists in a CLAUDE.md", asi que la atribucion equivocada no
# es prosa floja, es una instruccion que hace descartar un hallazgo real por "regla inexistente".
# Ninguna otra suite lo ve: Get-GovList ancla en la lista y no en la frase que la atribuye.
$CONSUMIDORES = @(
  ".claude\commands\review-loop.md",
  ".claude\commands\slice-review.md",
  ".agents\skills\review-loop\SKILL.md",
  ".agents\skills\slice-review\SKILL.md"
)
$vistos = 0
foreach ($r in $raices) {
  foreach ($rel in $CONSUMIDORES) {
    $f = Join-Path $r.pre $rel
    if (-not (Test-Path -LiteralPath $f)) { Assert $false "$($r.label): existe $rel"; continue }
    $vistos++
    $txt = [IO.File]::ReadAllText($f)
    Assert ($txt -notmatch '`CLAUDE\.md` (says govern the agent|lists as never documentation)') `
      "$($r.label)/${rel}: ya no le atribuye al CLAUDE.md la lista de rutas que gobiernan"
    # Y la nombra donde SI vive, o el agente se queda sin saber donde buscarla.
    Assert ($txt -match 'AI_DEVELOPMENT_WORKFLOW\.md') `
      "$($r.label)/${rel}: nombra el doc del flujo como hogar de esa lista"
  }
}
# guard: una lista de consumidores vacia dejaria pasar el foreach entero sin mirar nada.
Assert ($vistos -eq 16) "guard: se miraron los 16 consumidores (4 raices x 4 archivos): $vistos"

Write-Host ""
Write-Host "=== la seccion mudada no se come el checklist del reviewer ==="
# El `###` nuevo se inserto DENTRO de la seccion 7, antes de "The reviewer must check:". En
# markdown eso deja ese checklist colgando de una subseccion que habla de OTRA cosa (que dispara
# el loop), y el recorte de review-loop-docs-gate.tests.ps1 se lo traga como si fuera parte del
# disparo. En un archivo que gobierna al agente el alcance de un encabezado es comportamiento.
foreach ($r in $raices) {
  $dF = Join-Path $r.pre ($DOC -replace '/', '\\')
  if (-not (Test-Path -LiteralPath $dF)) { Assert $false "$($r.label): existe $DOC"; continue }
  $d = [IO.File]::ReadAllText($dF)
  $sc = [regex]::Matches($d, '(?ms)^### What fires the loop, and over what\r?$.*?(?=^#{2,4}\s|\z)')
  Assert ($sc.Count -eq 1) "$($r.label): guard: una sola seccion de disparo (encontradas: $($sc.Count))"
  if ($sc.Count -ne 1) { continue }
  Assert ($sc[0].Value -notmatch 'The reviewer must check') `
    "$($r.label): el checklist del reviewer quedo fuera de la seccion de disparo"
}

Write-Host ""
Write-Host "=== el CLAUDE.md, el doc y el hook no se contradicen ==="
# El slice partio en dos una afirmacion que antes vivia en un solo lugar, y creo una duplicacion de
# tres puntas (hook, CLAUDE.md x4, doc x4) sin un solo test que las compare. Un mutante MEDIDO la
# invirtio en el CLAUDE.md ("...and runs the grill on its own") y las tres suites quedaron verdes:
# un agente que obedezca eso deja de ofrecer alineacion y espera que el hook grille solo, o sea el
# paso 1 del flujo apagado en silencio. En un archivo que gobierna al agente eso es comportamiento,
# no prosa. Se ancla la DIRECCION con un lookbehind, no la frase entera: asi un reflow no la rompe
# pero la inversion si.
foreach ($r in $raices) {
  $cF = Join-Path $r.pre "CLAUDE.md"
  $dF = Join-Path $r.pre ($DOC -replace '/', '\\')
  $hF = Join-Path $r.pre ".claude\hooks\alignment-gate.ps1"
  if (-not (Test-Path -LiteralPath $cF) -or -not (Test-Path -LiteralPath $dF) -or -not (Test-Path -LiteralPath $hF)) {
    Assert $false "$($r.label): existen CLAUDE.md, $DOC y el hook del gate"; continue
  }
  $c = [IO.File]::ReadAllText($cF); $d = [IO.File]::ReadAllText($dF); $h = [IO.File]::ReadAllText($hF)
  # El hook es la fuente: su propio mensaje le dice al agente que no lo ejecute por su cuenta.
  # El de la raiz esta en castellano y los de los tres scaffolds en ingles: se aceptan los dos,
  # porque lo que se ancla es la direccion de la regla, no el idioma en que esta escrita.
  Assert ($h -match '(NO ejecutes el grill por tu cuenta|do NOT run the grill on your own)') "$($r.label): el hook del gate declara que no corre el grill solo"
  foreach ($par in @(@{ n = "CLAUDE.md"; x = $c }, @{ n = $DOC; x = $d })) {
    Assert ($par.x -match 'never runs the grill on its own') "$($r.label)/$($par.n): dice que el gate nunca corre el grill solo"
    Assert ($par.x -notmatch '(?<!never )runs the grill on its own') "$($r.label)/$($par.n): no afirma lo contrario en ningun lado"
  }
}

Write-Host ""
Write-Host "=== la semantica del rigor sale de la tabla de Rigor, no de una frase copiada ==="
# Otro mutante MEDIDO invirtio la oracion del rigor en el doc (light pasaba a correr el fan-out
# completo sobre dos turnos) y nada la caza: el capDocs de slice-review.tests.ps1 ancla la linea
# del techo, que la inversion deja intacta. Se deriva de la tabla de Rigor del review-loop, que es
# la fuente, en vez de fijar la frase literal.
foreach ($r in $raices) {
  $sF = Join-Path $r.pre ".agents\skills\review-loop\SKILL.md"
  $dF = Join-Path $r.pre ($DOC -replace '/', '\\')
  if (-not (Test-Path -LiteralPath $sF) -or -not (Test-Path -LiteralPath $dF)) { Assert $false "$($r.label): existen la skill del loop y $DOC"; continue }
  $fila = [regex]::Match([IO.File]::ReadAllText($sF), '(?m)^\| `light` \|.*?the (.+?) focuses only')
  Assert ($fila.Success) "$($r.label): guard: se leyo la fila light de la tabla de Rigor"
  if (-not $fila.Success) { continue }
  $focos = $fila.Groups[1].Value    # "Bugs and Tests"
  $orac = [regex]::Match([IO.File]::ReadAllText($dF), '(?m)A slice that declares `Review-Rigor: light`[^.]+\.')
  Assert ($orac.Success) "$($r.label): guard: el doc trae la oracion del rigor"
  if (-not $orac.Success) { continue }
  $partes = $orac.Value -split ';', 2
  Assert ($partes.Count -eq 2) "$($r.label): guard: la oracion del rigor separa light de standard con punto y coma"
  if ($partes.Count -ne 2) { continue }
  # light: un turno y los focos que dice la tabla. standard: el fan-out completo. Invertirlo da rojo.
  Assert ($partes[0] -match [regex]::Escape($focos)) "$($r.label): la clausula de light nombra los focos de la tabla ($focos)"
  Assert ($partes[0] -match 'one turn') "$($r.label): la clausula de light dice un solo turno"
  Assert ($partes[1] -match 'full fan-out') "$($r.label): la clausula de standard dice fan-out completo"
  Assert ($partes[1] -notmatch [regex]::Escape($focos)) "$($r.label): standard no se queda con los focos de light"
}

Write-Host ""
if ($script:failures -eq 0) { Write-Host "TODOS LOS TESTS PASARON"; exit 0 }
Write-Host "$($script:failures) test(s) FALLARON"
exit 1
