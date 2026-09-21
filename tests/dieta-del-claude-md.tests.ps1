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
# QUE ANCLA ESTA SUITE, Y QUE NO (leer antes de confiar en su verde).
#
# Ancla el PAYLOAD, no la redaccion: las rutas que gobiernan al agente salen de `$govern` del
# review-loop-trigger, los prefijos libres salen del array de `Is-NonCode` del alignment-gate, y los
# focos del rigor salen de la tabla de Rigor de la skill del loop. Un tripwire literal sobre una
# frase lo esquiva cualquier re-redaccion, y este archivo se comio esa leccion dos veces: primero
# con la lista entre parentesis (turno 1), despues con los backticks (turno 2). Por eso las rutas se
# buscan DESNUDAS, sin backticks, y al recorte se le saca antes el puntero literal al doc, que es el
# unico falso positivo que los backticks evitaban.
#
# LIMITE CONOCIDO, declarado porque el verde afirma menos de lo que parece: el anclaje es la ruta.
# Re-cachear el mecanismo en el CLAUDE.md SIN nombrar ninguna ruta —contar las condiciones de
# disparo, la red de ~400 lineas, el dedupe y el delta sin revisar en prosa— no lo caza nada de
# aca, y es contenido que el criterio de arriba manda mudar. Medido en el turno 2.
#
# QUE ESTA PROBADO NO-VACUO Y QUE NO. Esta suite se corrio entera contra 8d857a3 (el arbol de antes
# del cambio) en un worktree aparte. El metodo es ese y no otro: copiar este archivo a un checkout
# de 8d857a3 y contar las lineas FAIL/ok de su salida. Los verdes de esa corrida NO estan probados
# por ella, y son estos, enumerados por bloque para que el conteo se pueda rehacer:
#
#   - Todos los guards, que son pisos y no verificaciones: las 4 raices, los 16 consumidores, el
#     bullet unico de review-loop y el del gate, las rutas de govern, los prefijos libres del gate y
#     la fila `light` de la tabla de Rigor.
#   - Del bloque de coherencia, las cuatro mitades que ya eran ciertas en 8d857a3: que el hook
#     declare que no corre el grill solo, y que el CLAUDE.md lo diga (la frase ya estaba en el
#     bullet viejo) — con su negativa, que pasa por la misma razon.
#   - Del mismo bloque, las dos mitades del doc: en 8d857a3 la seccion no existia, asi que la
#     positiva daba rojo y la negativa pasaba por vacuidad.
#   - `OFFER alignment` en el bullet del gate: la frase ya estaba en el bullet viejo.
#
# Lo que ese RED no ejercita se probo por MUTACION, que es lo unico que mide un pin contra revert.
# Medido: invertir la direccion del gate en el CLAUDE.md de una raiz da rojo; inyectar la inversion
# en gerundio con doble negacion ("does not refrain from running the grill on its own") tambien;
# dar vuelta la semantica del rigor en el doc de una raiz da rojo; re-cachear la lista de gobierno
# en el CLAUDE.md con backticks, sin backticks, con dos puntos o con guiones da rojo nombrando las
# rutas; y meterle un `####` propio al checklist del reviewer para colgarlo de la seccion de
# disparo da rojo por el nivel del encabezado que lo domina.
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
$SEC_NUM = 7      # la seccion del doc donde vive el mecanismo del loop
$SEC_GATE_NUM = 1 # y la del gate

# Una sola forma de armar la ruta del doc. Habia cinco copias de esta expresion y cuatro usaban
# `-replace '/', '\\'`, que en el string de reemplazo de .NET mete DOS separadores (funciona solo
# porque Win32 los colapsa).
function Ruta-Doc($pre) { Join-Path $pre ($DOC -replace '/', '\') }

# Un solo recorte por bullet, con `^#` en el lookahead. Sin el, el bullet del gate —que es el
# ULTIMO de su seccion— seguia 17 caracteres adentro de `## Hard rules` (el encabezado y sus saltos)
# porque el corte solo miraba el proximo `- `. Los dos bullets comparten la forma para que no
# puedan divergir: antes habia dos regex distintos para el MISMO bullet del loop.
$BULLET_LOOP = '(?ms)^- After implementation, run .*?(?=^-\s|^#|\z)'
$BULLET_GATE = '(?ms)^- Before the first code edit of a session.*?(?=^-\s|^#|\z)'
$SEC_LOOP_RE = '(?ms)^### What fires the loop, and over what\r?$.*?(?=^#{2,4}\s|\z)'
$SEC_GATE_RE = '(?ms)^### The `alignment-gate` hook\r?$.*?(?=^#{2,4}\s|\z)'

# Las rutas se buscan DESNUDAS. El unico falso positivo es el puntero al doc, que contiene
# `docs/ai-workflow/`: se lo saca del texto antes de buscar, en vez de exigir backticks alrededor
# de la ruta (que es lo que el turno 2 midio como esquivable escribiendola sin ellos).
function Sin-Puntero([string]$txt) { $txt.Replace($DOC, '') }

# Para los chequeos de direccion: colapsa espacios y saltos y saca el enfasis de markdown, para que
# un reflow a dos lineas o un `**never**` no den un rojo con diagnostico invertido.
function Plano([string]$txt) { ($txt -replace '[*_]', '' -replace '\s+', ' ') }

# `$govern` del hook del trigger, deshaciendo ancla y escapes. Es la fuente de la lista de rutas.
function Get-RutasDeGobierno([string]$hookTxt) {
  $m = [regex]::Match($hookTxt, "(?m)^\s*\`$govern\s*=\s*'([^']+)'")
  if (-not $m.Success) { return @() }
  @($m.Groups[1].Value -split '\|(?![^(]*\))' | ForEach-Object {
    ($_ -replace '^\(\^\|/\)', '' -replace '\$$', '').Replace('\.', '.')
  })
}
# El gate no tiene una lista sola: `Is-NonCode` son tres reglas (extension, leafs, prefijos). Se lee
# SOLO el array de prefijos, que es el unico tramo que mapea 1:1 contra lo que la prosa enumera.
function Get-PrefijosLibres([string]$gateTxt) {
  $m = [regex]::Match($gateTxt, 'foreach \(\$d in @\(([^)]+)\)\)')
  if (-not $m.Success) { return @() }
  @([regex]::Matches($m.Groups[1].Value, "'([^']+)'") | ForEach-Object { $_.Groups[1].Value })
}

Write-Host ""
Write-Host "=== el mecanismo del review-loop vive en el doc del flujo, no en el CLAUDE.md ==="
foreach ($r in $raices) {
  $cF = Join-Path $r.pre "CLAUDE.md"
  $dF = Ruta-Doc $r.pre
  $hF = Join-Path $r.pre ".claude\hooks\review-loop-trigger.ps1"
  if (-not (Test-Path -LiteralPath $cF) -or -not (Test-Path -LiteralPath $dF) -or -not (Test-Path -LiteralPath $hF)) {
    Assert $false "$($r.label): existen CLAUDE.md, $DOC y el hook del trigger"; continue
  }
  $c = [IO.File]::ReadAllText($cF)
  $d = [IO.File]::ReadAllText($dF)

  $rutas = Get-RutasDeGobierno ([IO.File]::ReadAllText($hF))
  # Contar 5 no alcanza. Con el escape sin deshacer (`\.claude/`) la ruta nunca matchea la prosa y
  # el assert de abajo pasa en verde sobre un CLAUDE.md que SI la enumera (me paso). Y con un
  # metacaracter remanente —reemplazar una alternativa por `(CLAUDE|AGENTS)\.md$` deja el conteo en
  # 5 y sin backslash— pasa igual: se rechaza cualquier metacaracter de regex, no solo el backslash.
  $sucias = @($rutas | Where-Object { $_ -match '[\\()|*?+\[\]^$]' })
  Assert ($rutas.Count -eq 5 -and $sucias.Count -eq 0) `
    "$($r.label): guard: 5 rutas de govern, sin metacaracteres ($($rutas -join ', '))"

  $sec = [regex]::Matches($d, $SEC_LOOP_RE)
  Assert ($sec.Count -eq 1) "$($r.label): $DOC tiene exactamente una seccion de disparo del loop (encontradas: $($sec.Count))"
  if ($sec.Count -eq 1 -and $rutas.Count -eq 5 -and $sucias.Count -eq 0) {
    # POSITIVA: la seccion del doc enumera las rutas que el hook clasifica, todas.
    $faltan = @($rutas | Where-Object { $sec[0].Value -notmatch [regex]::Escape($_) })
    Assert ($faltan.Count -eq 0) "$($r.label): la seccion del doc enumera las rutas de govern [faltan: $($faltan -join ', ')]"
  }

  $bl = [regex]::Matches($c, $BULLET_LOOP)
  Assert ($bl.Count -eq 1) "$($r.label): guard: el CLAUDE.md tiene exactamente un bullet de review-loop (encontrados: $($bl.Count))"
  if ($bl.Count -eq 1 -and $rutas.Count -eq 5 -and $sucias.Count -eq 0) {
    # NEGATIVA: el bullet no cachea NINGUNA ruta, escrita como se escriba.
    $dentro = @($rutas | Where-Object { (Sin-Puntero $bl[0].Value) -match [regex]::Escape($_) })
    Assert ($dentro.Count -eq 0) "$($r.label): el bullet del loop ya no enumera rutas de gobierno [enumera: $($dentro -join ', ')]"
    # El puntero, dentro del bullet: el CLAUDE.md nombra el doc tambien en la lista de lectura
    # obligatoria, asi que un match sobre el archivo entero sobrevive a borrar el puntero. Y se
    # ancla el NUMERO de seccion: sin eso, mover una seccion del doc deja el puntero mintiendo.
    Assert ($bl[0].Value -match [regex]::Escape($DOC)) "$($r.label): el bullet del loop remite a $DOC"
    Assert ($bl[0].Value -match ([regex]::Escape($DOC) + '`?\s*§\s*' + $SEC_NUM + '\b')) `
      "$($r.label): el bullet del loop remite a la seccion $SEC_NUM"
  }

  # Y la dieta no se revierte en OTRO lugar del archivo: `.claude/` y `.agents/` no aparecen en
  # ninguna otra parte del CLAUDE.md (medido en las 4 raices), asi que para esas dos el chequeo
  # puede ser sobre el archivo entero. Las otras tres tienen usos legitimos afuera y no.
  $fuera = @(@('.claude/', '.agents/') | Where-Object { (Sin-Puntero $c) -match [regex]::Escape($_) })
  Assert ($fuera.Count -eq 0) "$($r.label): el CLAUDE.md no cachea esas rutas en ningun otro lado [aparece: $($fuera -join ', ')]"

  # El numero de seccion tiene que existir en el doc, o el puntero apunta al vacio.
  Assert ($d -match ('(?m)^## ' + $SEC_NUM + '\. ')) "$($r.label): el doc tiene la seccion $SEC_NUM"
}

Write-Host ""
Write-Host "=== el mecanismo del alignment-gate vive en el doc del flujo, no en el CLAUDE.md ==="
foreach ($r in $raices) {
  $cF = Join-Path $r.pre "CLAUDE.md"
  $dF = Ruta-Doc $r.pre
  $gF = Join-Path $r.pre ".claude\hooks\alignment-gate.ps1"
  if (-not (Test-Path -LiteralPath $cF) -or -not (Test-Path -LiteralPath $dF) -or -not (Test-Path -LiteralPath $gF)) {
    Assert $false "$($r.label): existen CLAUDE.md, $DOC y el hook del gate"; continue
  }
  $c = [IO.File]::ReadAllText($cF)
  $d = [IO.File]::ReadAllText($dF)
  $pref = Get-PrefijosLibres ([IO.File]::ReadAllText($gF))
  Assert ($pref.Count -eq 4) "$($r.label): guard: se leyeron los 4 prefijos libres del gate ($($pref -join ', '))"

  # --- lado CLAUDE.md: la regla se queda, el mecanismo no -----------------------------------
  $bg = [regex]::Matches($c, $BULLET_GATE)
  Assert ($bg.Count -eq 1) "$($r.label): guard: el CLAUDE.md tiene exactamente un bullet del gate (encontrados: $($bg.Count))"
  if ($bg.Count -eq 1) {
    if ($pref.Count -eq 4) {
      $cache = @($pref | Where-Object { (Sin-Puntero $bg[0].Value) -match [regex]::Escape($_) })
      Assert ($cache.Count -eq 0) "$($r.label): el bullet del gate ya no enumera los archivos que pasan libres [enumera: $($cache -join ', ')]"
    }
    Assert ($bg[0].Value -match [regex]::Escape($DOC)) "$($r.label): el bullet del gate remite a $DOC"
    Assert ($bg[0].Value -match ([regex]::Escape($DOC) + '`?\s*§\s*' + $SEC_GATE_NUM + '\b')) `
      "$($r.label): el bullet del gate remite a la seccion $SEC_GATE_NUM"
    # Y no cachea el MECANISMO, que es lo que la dieta vino a sacar. Sin esto, el bullet del gate
    # bajaba 7% contra el 61% del bullet del loop repitiendo el mecanismo palabra por palabra en
    # los dos lados, y ningun assert lo veia: el pase de coherencia lo encontro leyendo el slice
    # entero. Se anclan los hechos que el hook computa, no el largo del bullet.
    $mec = @('once per session', 'the grill on its own', 'PreToolUse', 'MultiEdit')
    $repetido = @($mec | Where-Object { $bg[0].Value -match [regex]::Escape($_) })
    Assert ($repetido.Count -eq 0) "$($r.label): el bullet del gate no repite el mecanismo del hook [repite: $($repetido -join ', ')]"
    # La REGLA se queda: ningun hook puede obligar a ofrecer la alineacion, solo frena el primer Edit.
    Assert ($bg[0].Value -match '(?i)OFFER alignment') "$($r.label): el bullet del gate conserva la regla (ofrecer alineacion antes de codear)"
  }

  # --- lado doc: el mecanismo esta entero ----------------------------------------------------
  $sec = [regex]::Matches($d, $SEC_GATE_RE)
  Assert ($sec.Count -eq 1) "$($r.label): $DOC tiene exactamente una seccion del alignment-gate (encontradas: $($sec.Count))"
  if ($sec.Count -eq 1 -and $pref.Count -eq 4) {
    # La lista del doc se COMPARA con la del hook, no se copia: comparar solo la aridad dejaba
    # pasar un swap (`.scratch/` -> `.tmp/` en las 4 raices deja todas las suites en verde, medido).
    # `*.md` va aparte: sale de la regla de extension, no del array, y la prosa resume el resto
    # (`.json`, `.ya?ml`, `.toml`, `.gitignore`, `.gitattributes`) como "config" a proposito.
    $faltan = @($pref | Where-Object { $sec[0].Value -notmatch [regex]::Escape('`' + $_ + '`') })
    Assert ($faltan.Count -eq 0) "$($r.label): la seccion del gate nombra los prefijos del hook [faltan: $($faltan -join ', ')]"
    $sobran = @([regex]::Matches($sec[0].Value, '`(\.[a-z]+/|docs/)`') | ForEach-Object { $_.Groups[1].Value } |
                Where-Object { $pref -notcontains $_ } | Select-Object -Unique)
    Assert ($sobran.Count -eq 0) "$($r.label): la seccion del gate no promete prefijos que el hook no tiene [sobran: $($sobran -join ', ')]"
    Assert ($sec[0].Value -match [regex]::Escape('`*.md`')) "$($r.label): la seccion del gate nombra *.md (regla de extension)"
    Assert ($sec[0].Value -match 'PreToolUse') "$($r.label): la seccion del gate dice en que evento engancha"
  }
}

Write-Host ""
Write-Host "=== nadie sigue atribuyendole la lista de gobierno al CLAUDE.md ==="
# El review-loop y el slice-review le dicen al agente donde vive la lista de rutas que gobiernan.
# Mientras la lista vivia en el CLAUDE.md esa atribucion era cierta; desde la dieta es falsa, y
# manda al agente a grepear un archivo que ya no la tiene. Peor: el Step 5 de /slice-review le
# ordena "confirm the rule literally exists in a CLAUDE.md", asi que la atribucion equivocada no
# es prosa floja, es una instruccion que hace descartar un hallazgo real por "regla inexistente".
#
# Se ancla en el TEXTO QUE PRECEDE a la lista, no en las dos frases que habia que corregir: el
# atribuidor vive ahi pegado, asi que cualquier re-redaccion que vuelva a nombrar al CLAUDE.md
# aparece en esa ventana. Anclar las frases viejas dejaba verde la re-atribucion escrita con la
# redaccion NUEVA, que es la regresion mas probable (medido en el turno 2).
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
    $i = $txt.IndexOf('`CLAUDE.md` anywhere')
    Assert ($i -ge 0) "$($r.label)/${rel}: guard: trae la lista de rutas que gobiernan"
    if ($i -lt 0) { continue }
    # La ventana previa: 200 caracteres alcanzan para cubrir la oracion atribuidora entera, que en
    # las dos redacciones vivas mide menos de 120.
    $antes = $txt.Substring([Math]::Max(0, $i - 200), [Math]::Min(200, $i))
    Assert ($antes -match 'AI_DEVELOPMENT_WORKFLOW\.md') `
      "$($r.label)/${rel}: atribuye la lista al doc del flujo, no al CLAUDE.md"
    Assert ($antes -match ('§\s*' + $SEC_NUM + '\b')) `
      "$($r.label)/${rel}: la atribucion nombra la seccion $SEC_NUM"
  }
}
# guard: una lista de consumidores vacia dejaria pasar el foreach entero sin mirar nada.
Assert ($vistos -eq 16) "guard: se miraron los 16 consumidores (4 raices x 4 archivos): $vistos"

Write-Host ""
Write-Host "=== la seccion mudada no se come el checklist del reviewer ==="
# El `###` nuevo se habia insertado DENTRO de la seccion 7, antes de "The reviewer must check:". En
# markdown eso deja ese checklist colgando de una subseccion que habla de OTRA cosa (que dispara el
# loop). En un archivo que gobierna al agente el alcance de un encabezado es comportamiento.
#
# Se mide por el NIVEL del encabezado que domina la linea, no por si cae dentro de un recorte:
# ponerle un `####` propio al checklist y meterlo adentro de la seccion de disparo lo sacaba del
# recorte y dejaba el assert en verde con el checklist igual de anidado (medido en el turno 2).
foreach ($r in $raices) {
  $dF = Ruta-Doc $r.pre
  if (-not (Test-Path -LiteralPath $dF)) { Assert $false "$($r.label): existe $DOC"; continue }
  $lineas = [IO.File]::ReadAllLines($dF)
  $iChk = [Array]::FindIndex($lineas, [Predicate[string]] { param($l) $l -match '^The reviewer must check' })
  Assert ($iChk -ge 0) "$($r.label): guard: el doc trae el checklist del reviewer"
  if ($iChk -lt 0) { continue }
  $dom = ($lineas[0..$iChk] | Where-Object { $_ -match '^#{1,6}\s' } | Select-Object -Last 1)
  Assert ($dom -match ('^## ' + $SEC_NUM + '\. ')) `
    "$($r.label): el checklist cuelga de la seccion $SEC_NUM, no de una subseccion (lo domina: $dom)"
}

Write-Host ""
Write-Host "=== el CLAUDE.md, el doc y el hook no se contradicen ==="
# El slice partio en dos una afirmacion que antes vivia en un solo lugar, y creo una duplicacion de
# tres puntas (hook, CLAUDE.md x4, doc x4) sin un solo test que las compare. Un mutante MEDIDO la
# invirtio en el CLAUDE.md y las tres suites quedaron verdes: un agente que obedezca eso deja de
# ofrecer alineacion y espera que el hook grille solo, o sea el paso 1 del flujo apagado en
# silencio. En un archivo que gobierna al agente eso es comportamiento, no prosa.
#
# Se ancla la DIRECCION sobre el texto aplanado (espacios colapsados, enfasis quitado), asi un
# reflow o un `**never**` no dan un rojo con diagnostico invertido. Y se cubre la conjugacion:
# anclar solo `runs` dejaba pasar "does not refrain from RUNNING the grill on its own", que es la
# misma inversion en gerundio con doble negacion (medido en el turno 2).
foreach ($r in $raices) {
  $cF = Join-Path $r.pre "CLAUDE.md"
  $dF = Ruta-Doc $r.pre
  $hF = Join-Path $r.pre ".claude\hooks\alignment-gate.ps1"
  if (-not (Test-Path -LiteralPath $cF) -or -not (Test-Path -LiteralPath $dF) -or -not (Test-Path -LiteralPath $hF)) {
    Assert $false "$($r.label): existen CLAUDE.md, $DOC y el hook del gate"; continue
  }
  $h = Plano ([IO.File]::ReadAllText($hF))
  # El hook es la fuente: su propio mensaje le dice al agente que no lo ejecute por su cuenta. El de
  # la raiz esta en castellano y los de los tres scaffolds en ingles: se aceptan los dos, porque lo
  # que se ancla es la direccion de la regla, no el idioma en que esta escrita.
  Assert ($h -match '(NO ejecutes el grill por tu cuenta|do NOT run the grill on your own)') `
    "$($r.label): el hook del gate declara que no corre el grill solo"
  # La POSITIVA vive solo en el doc: que el gate no corre el grill solo es un hecho del hook, y
  # exigirla tambien en el CLAUDE.md era consagrar la duplicacion que la dieta vino a matar (lo
  # encontro el pase de coherencia: el bullet del gate habia bajado 7% contra el 61% del loop,
  # justamente porque repetia el mecanismo palabra por palabra en los dos lados).
  Assert ((Plano ([IO.File]::ReadAllText($dF))) -match 'never runs the grill on its own') `
    "$($r.label)/${DOC}: dice que el gate nunca corre el grill solo"
  # La NEGATIVA sigue valiendo para los dos: la inversion es igual de grave escrita donde sea.
  foreach ($par in @(@{ n = "CLAUDE.md"; x = (Plano ([IO.File]::ReadAllText($cF))) },
                     @{ n = $DOC;        x = (Plano ([IO.File]::ReadAllText($dF))) })) {
    Assert ($par.x -notmatch '(?<!never )(runs?|running) the grill on its own') `
      "$($r.label)/$($par.n): no afirma lo contrario en ningun lado, en ninguna conjugacion"
  }
}

Write-Host ""
Write-Host "=== la semantica del rigor sale de la tabla de Rigor, no de una frase copiada ==="
# Otro mutante MEDIDO invirtio la oracion del rigor en el doc (light pasaba a correr el fan-out
# completo sobre dos turnos) y nada la cazaba: el capDocs de slice-review.tests.ps1 ancla la linea
# del techo, que la inversion deja intacta. Se deriva de la tabla de Rigor del review-loop, que es
# la fuente, en vez de fijar la frase literal.
foreach ($r in $raices) {
  $sF = Join-Path $r.pre ".agents\skills\review-loop\SKILL.md"
  $dF = Ruta-Doc $r.pre
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
