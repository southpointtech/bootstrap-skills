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
# Ancla el PAYLOAD cuando el payload es un TOKEN, derivado de su fuente: las rutas que gobiernan al
# agente salen de `$govern` del review-loop-trigger; los disparadores (`gh pr create`, `git push`,
# `Slice-Close:`, el techo `400`), de las lineas del mismo hook que los deciden; los prefijos libres,
# del array de `Is-NonCode` del alignment-gate; los focos de `light` y el nombre del rigor por
# defecto, de la tabla de Rigor de la skill del loop. Las rutas se buscan DESNUDAS (sin backticks y,
# en las negativas, con la barra final opcional, via `Patron-Ruta`), y al recorte se le saca antes el
# puntero literal al doc, que es el unico falso positivo que los backticks evitaban.
#
# LIMITES CONOCIDOS. Cuando el payload es una FRASE, derivar no compra nada: protege contra que el
# payload cambie, no contra que se parafrasee. Lo que queda afuera por eso:
#   - Re-cachear el mecanismo en el CLAUDE.md con otras palabras y sin nombrar ningun token de arriba.
#     `$mec` (el bullet del gate no repite el mecanismo) es un tripwire literal sobre cuatro frases:
#     el turno 1 del loop midio dos parafrasis que lo dejan verde, y el bloque entero con el.
#   - "Work in feature branches per slice" en la seccion 7: es semantica, no token, y no lo ancla nada.
#   - La negativa de direccion del gate exige la negacion pegada al verbo ("will not ever run" da un
#     rojo espurio) y la frase "on its own" ("runs the grill by itself" no la ve nada).
#   - En el pipeline de /slice-review se anclan seis ventanas de decision por raiz; re-atar al
#     CLAUDE.md solo una oracion que no este en ellas no da rojo.
#
# QUE ESTA PROBADO NO-VACUO Y QUE NO. Esta suite se corrio entera contra 8d857a3 (el arbol de antes
# del issue 14) copiando este archivo a un checkout aparte: 95 ok, 128 FAIL. Fuera de los guards, que
# son pisos y no verificaciones, los verdes de esa corrida son 20, cinco asserts por raiz, y esa
# corrida NO los prueba:
#   - el hook del gate declara que no corre el grill solo (hecho de la fuente, previo a la dieta);
#   - `OFFER alignment` en el bullet del gate (la frase ya estaba en el bullet viejo);
#   - el checklist del reviewer cuelga de la seccion 7 (ya colgaba);
#   - las dos negativas de direccion, en el CLAUDE.md y en el doc (nadie afirmaba lo contrario).
#
# Lo que ese RED no ejercita se probo por MUTACION, que es lo unico que mide un pin contra revert.
# Medido sobre 919f5ce, un mutante por vez en un worktree descartable: invertir la direccion del gate
# en el CLAUDE.md de la raiz o de un scaffold da rojo, y tambien en el doc; la inversion en gerundio
# con doble negacion ("does not refrain from running the grill on its own") da rojo; y meterle un
# `####` propio al checklist da rojo por el nivel del encabezado que lo domina. Los mutantes de los
# asserts agregados por el turno 1 del loop (atribucion hibrida, subseccion movida de seccion, ruta
# sin barra, parrafo de disparo borrado, rigor por defecto invertido, piso roto) estan en el mensaje
# de e07c98d, con el conteo de rojos de la suite vieja y de la nueva.
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
# Las aridades de los pisos, escritas una sola vez. Estaban repetidas en el guard y en cada if que
# dependia de el: bumpear una copia y olvidar la otra apagaba 8 asserts sin un solo rojo.
$N_RUTAS = 5 # rutas de `$govern` del trigger
$N_PREF = 4  # prefijos libres de `Is-NonCode` del gate
$N_DISP = 4  # disparadores del trigger que la seccion 7 tiene que contar

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

# El patron con que las NEGATIVAS buscan una ruta cacheada. La barra final es opcional: escribir
# `.agents` en vez de `.agents/` re-cacheaba el mecanismo en verde (turno 1 del loop). Pero relajarla
# sin bordes rompe: `CLAUDE.md` del repo nombra `.agents\.agents` (el bug de Copy-Item) y el bullet
# del gate nombra `/grill-with-docs`. Un nombre con punto no es una palabra comun y lleva bordes; uno
# sin punto (`docs`) si lo es, asi que sin la barra se exige el backtick. Las POSITIVAS no lo usan:
# ahi exigir la ruta exacta es lo estricto.
function Patron-Ruta([string]$ruta) {
  if (-not $ruta.EndsWith('/')) { return [regex]::Escape($ruta) }
  $base = [regex]::Escape($ruta.TrimEnd('/'))
  if ($ruta.StartsWith('.')) { return '(?<![\\\w.-])' + $base + '(?:/|(?![\\\w]|\.\w))' }
  '(?<![\\\w.-])(?:' + $base + '/|`' + $base + '`)'
}

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
# Los disparadores del trigger, leidos de las lineas que los deciden: los dos comandos (`$isPr` y
# `$isPush` sobre el comando plegado), el trailer que declara el cierre y el techo de la red. Son
# tokens, asi que derivarlos si protege contra que el hook cambie. Una frase como "work in feature
# branches per slice" no es derivable y no esta aca (ver el LIMITE CONOCIDO de la cabecera).
function Get-Disparadores([string]$hookTxt) {
  $out = @()
  foreach ($v in @('isPr', 'isPush')) {
    $m = [regex]::Match($hookTxt, "(?m)^\`$$v\s*=\s*\`$folded -match '\\b(.+?)\\b'")
    if ($m.Success) { $out += ($m.Groups[1].Value -replace '\\s\+', ' ') }
  }
  $m = [regex]::Match($hookTxt, "\`$body -notmatch '\(\?m\)\^\\s\*([\w-]+:)'")
  if ($m.Success) { $out += $m.Groups[1].Value }
  $m = [regex]::Match($hookTxt, '\$lines -le (\d+)\)')
  if ($m.Success) { $out += $m.Groups[1].Value }
  @($out)
}

# Contencion: el `##` que domina una linea. Los punteros `§ 7` y `§ 1` solo son ciertos si la
# subseccion vive adentro de esa seccion; que exista no alcanza (moverla dejaba 21 punteros § 7 y 4
# § 1 mintiendo con las suites verdes). Se mira el `##` y no cualquier encabezado porque la linea
# ancla ES un `###`: el patron de nivel dominante del bloque del checklist daria rojo tautologico.
function Seccion-Que-Domina([string[]]$lineas, [string]$ancla) {
  $i = [Array]::FindIndex($lineas, [Predicate[string]] { param($l) $l -eq $ancla })
  if ($i -le 0) { return $null }
  $lineas[0..($i - 1)] | Where-Object { $_ -match '^## ' } | Select-Object -Last 1
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
  $rutasOk = ($rutas.Count -eq $N_RUTAS -and $sucias.Count -eq 0)
  Assert $rutasOk "$($r.label): guard: $N_RUTAS rutas de govern, sin metacaracteres ($($rutas -join ', '))"
  $disp = Get-Disparadores ([IO.File]::ReadAllText($hF))
  Assert ($disp.Count -eq $N_DISP) "$($r.label): guard: se leyeron los $N_DISP disparadores del trigger ($($disp -join ', '))"

  $sec = [regex]::Matches($d, $SEC_LOOP_RE)
  Assert ($sec.Count -eq 1) "$($r.label): $DOC tiene exactamente una seccion de disparo del loop (encontradas: $($sec.Count))"
  if ($sec.Count -eq 1) {
    if ($rutasOk) {
      # POSITIVA: la seccion del doc enumera las rutas que el hook clasifica, todas.
      $faltan = @($rutas | Where-Object { $sec[0].Value -notmatch [regex]::Escape($_) })
      Assert ($faltan.Count -eq 0) "$($r.label): la seccion del doc enumera las rutas de govern [faltan: $($faltan -join ', ')]"
    }
    if ($disp.Count -eq $N_DISP) {
      # Y cuenta QUE dispara el loop. Las rutas viven todas en el segundo parrafo, asi que borrar el
      # primero (trailer, push, PR, red de ~400) dejaba las suites verdes. El `400` se busca en el
      # recorte y no en el doc: el doc lo nombra tambien en la seccion 3, que no es el mecanismo.
      $sinDisp = @($disp | Where-Object { $sec[0].Value -notmatch ('(?<![\w-])' + [regex]::Escape($_) + '(?![\w])') })
      Assert ($sinDisp.Count -eq 0) "$($r.label): la seccion del doc nombra los disparadores del trigger [faltan: $($sinDisp -join ', ')]"
    }
  }
  $dom = Seccion-Que-Domina ([IO.File]::ReadAllLines($dF)) '### What fires the loop, and over what'
  Assert ($dom -match ('^## ' + $SEC_NUM + '\. ')) "$($r.label): la seccion de disparo vive adentro de la seccion $SEC_NUM (la domina: $dom)"

  $bl = [regex]::Matches($c, $BULLET_LOOP)
  Assert ($bl.Count -eq 1) "$($r.label): guard: el CLAUDE.md tiene exactamente un bullet de review-loop (encontrados: $($bl.Count))"
  if ($bl.Count -eq 1) {
    if ($rutasOk) {
      # NEGATIVA: el bullet no cachea NINGUNA ruta, escrita como se escriba.
      $dentro = @($rutas | Where-Object { (Sin-Puntero $bl[0].Value) -match (Patron-Ruta $_) })
      Assert ($dentro.Count -eq 0) "$($r.label): el bullet del loop ya no enumera rutas de gobierno [enumera: $($dentro -join ', ')]"
    }
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
  $fuera = @(@('.claude/', '.agents/') | Where-Object { (Sin-Puntero $c) -match (Patron-Ruta $_) })
  Assert ($fuera.Count -eq 0) "$($r.label): el CLAUDE.md no cachea esas rutas en ningun otro lado [aparece: $($fuera -join ', ')]"
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
  Assert ($pref.Count -eq $N_PREF) "$($r.label): guard: se leyeron los $N_PREF prefijos libres del gate ($($pref -join ', '))"

  # --- lado CLAUDE.md: la regla se queda, el mecanismo no -----------------------------------
  $bg = [regex]::Matches($c, $BULLET_GATE)
  Assert ($bg.Count -eq 1) "$($r.label): guard: el CLAUDE.md tiene exactamente un bullet del gate (encontrados: $($bg.Count))"
  if ($bg.Count -eq 1) {
    if ($pref.Count -eq $N_PREF) {
      $cache = @($pref | Where-Object { (Sin-Puntero $bg[0].Value) -match (Patron-Ruta $_) })
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
  if ($sec.Count -eq 1) {
    if ($pref.Count -eq $N_PREF) {
      # La lista del doc se COMPARA con la del hook, no se copia: comparar solo la aridad dejaba
      # pasar un swap (`.scratch/` -> `.tmp/` en las 4 raices deja todas las suites en verde, medido).
      # `*.md` va aparte: sale de la regla de extension, no del array, y la prosa resume el resto
      # (`.json`, `.ya?ml`, `.toml`, `.gitignore`, `.gitattributes`) como "config" a proposito.
      $faltan = @($pref | Where-Object { $sec[0].Value -notmatch [regex]::Escape('`' + $_ + '`') })
      Assert ($faltan.Count -eq 0) "$($r.label): la seccion del gate nombra los prefijos del hook [faltan: $($faltan -join ', ')]"
      $sobran = @([regex]::Matches($sec[0].Value, '`(\.[a-z]+/|docs/)`') | ForEach-Object { $_.Groups[1].Value } |
                  Where-Object { $pref -notcontains $_ } | Select-Object -Unique)
      Assert ($sobran.Count -eq 0) "$($r.label): la seccion del gate no promete prefijos que el hook no tiene [sobran: $($sobran -join ', ')]"
    }
    Assert ($sec[0].Value -match [regex]::Escape('`*.md`')) "$($r.label): la seccion del gate nombra *.md (regla de extension)"
    Assert ($sec[0].Value -match 'PreToolUse') "$($r.label): la seccion del gate dice en que evento engancha"
  }
  $dom = Seccion-Que-Domina ([IO.File]::ReadAllLines($dF)) '### The `alignment-gate` hook'
  Assert ($dom -match ('^## ' + $SEC_GATE_NUM + '\. ')) "$($r.label): la seccion del gate vive adentro de la seccion $SEC_GATE_NUM (la domina: $dom)"
}

Write-Host ""
Write-Host "=== nadie sigue atribuyendole la lista de gobierno al CLAUDE.md ==="
# El review-loop y el slice-review le dicen al agente donde vive la lista de rutas que gobiernan.
# Mientras la lista vivia en el CLAUDE.md esa atribucion era cierta; desde la dieta es falsa, y
# manda al agente a grepear un archivo que ya no la tiene. Peor: el Step 5 de /slice-review le
# ordenaba "confirm the rule literally exists in a CLAUDE.md", asi que la atribucion equivocada no
# era prosa floja, era una instruccion que hacia descartar un hallazgo real por "regla
# inexistente". Esa orden la cubre el bloque siguiente.
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
    # Y la NEGATIVA: con solo las dos positivas, la forma hibrida ("the paths `CLAUDE.md` lists ...,
    # mirrored in ... § 7") pasaba en verde. `$antes` termina justo antes del `CLAUDE.md` que abre la
    # lista, asi que ese no cae adentro (medido: 16 ventanas, ninguna con CLAUDE.md).
    Assert ($antes -notmatch 'CLAUDE\.md') "$($r.label)/${rel}: la atribucion no vuelve a nombrar al CLAUDE.md"
  }
}
# guard: una lista de consumidores vacia dejaria pasar el foreach entero sin mirar nada.
Assert ($vistos -eq 16) "guard: se miraron los 16 consumidores (4 raices x 4 archivos): $vistos"

Write-Host ""
Write-Host "=== el pipeline de reglas de /slice-review lee tambien el doc del flujo ==="
# El bloque de arriba mira a los que ENUMERAN la lista; estos son los que DECIDEN si una regla
# cuenta: el Step 3 le pasa las fuentes de reglas al foco, el foco solo reporta lo que puede citar,
# y el scorer baja lo que no existe "literalmente en un CLAUDE.md". Desde la dieta, la regla de que
# `.md` es lo unico que cuenta como documentacion vive solo en el doc: atado al CLAUDE.md, el
# pipeline descartaba un hallazgo real por regla inexistente. Se ancla el payload (la ruta del doc)
# en la ventana de cada punto de decision, no en el archivo entero: SKILL.md ya nombra el doc en
# otro lado. Limite: re-atar una OTRA oracion del pipeline al CLAUDE.md solo no lo ve.
$DECISIONES = @(
  @{ rel = ".agents\skills\slice-review\SKILL.md"; rx = '(?m)^- Paths of the .*$' },
  @{ rel = ".agents\skills\slice-review\SKILL.md"; rx = '(?m)^For rule violations, .*$' },
  @{ rel = ".claude\commands\slice-review.md";     rx = '(?m)^- Paths of the .*$' },
  @{ rel = ".claude\commands\slice-review.md";     rx = '(?m)^For rule violations, .*$' },
  @{ rel = ".claude\agents\slice-review-rules.md"; rx = '(?ms)^## Your focus\r?$.*?(?=^## |\z)' },
  @{ rel = ".claude\agents\slice-review-scorer.md"; rx = '(?ms)^## Your focus\r?$.*?(?=^## |\z)' }
)
$vistas = 0
foreach ($r in $raices) {
  foreach ($p in $DECISIONES) {
    $f = Join-Path $r.pre $p.rel
    if (-not (Test-Path -LiteralPath $f)) { Assert $false "$($r.label): existe $($p.rel)"; continue }
    $v = [regex]::Matches([IO.File]::ReadAllText($f), $p.rx)
    Assert ($v.Count -eq 1) "$($r.label)/$($p.rel): guard: una sola ventana de decision (encontradas: $($v.Count))"
    if ($v.Count -ne 1) { continue }
    $vistas++
    Assert ($v[0].Value -match [regex]::Escape($DOC)) "$($r.label)/$($p.rel): la decision sobre reglas incluye $DOC"
  }
}
Assert ($vistas -eq 24) "guard: se miraron las 24 ventanas de decision (4 raices x 6): $vistas"

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
  # La NEGATIVA sigue valiendo para los dos: la inversion es igual de grave escrita donde sea. El
  # lookbehind acepta cualquier negacion adyacente, no solo `never`: con `never` solo, "does not run
  # the grill on its own" (que dice lo correcto) daba un rojo espurio. Limite medido: la negacion
  # tiene que estar pegada ("will not ever run" sigue dando rojo), y una inversion que no diga "on
  # its own" ("runs the grill by itself") no la ve nada de aca.
  foreach ($par in @(@{ n = "CLAUDE.md"; x = (Plano ([IO.File]::ReadAllText($cF))) },
                     @{ n = $DOC;        x = (Plano ([IO.File]::ReadAllText($dF))) })) {
    Assert ($par.x -notmatch "(?<!(\bnever|\bnot|n't|\bno)\s+)(runs?|running) the grill on its own") `
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
  $tabla = [IO.File]::ReadAllText($sF)
  $fila = [regex]::Match($tabla, '(?m)^\| `light` \|.*?the (.+?) focuses only')
  Assert ($fila.Success) "$($r.label): guard: se leyo la fila light de la tabla de Rigor"
  # El nombre del rigor por defecto sale de la fila marcada `(default)`: asi un mutante que mueva la
  # marca a `light` tambien da rojo, cosa que un `standard` escrito aca no ve.
  $filaDef = [regex]::Match($tabla, '(?m)^\| `([a-z]+)` \(default\) \|')
  Assert ($filaDef.Success) "$($r.label): guard: se leyo la fila (default) de la tabla de Rigor"
  $orac = [regex]::Match([IO.File]::ReadAllText($dF), '(?m)A slice that declares `Review-Rigor: light`[^.]+\.')
  Assert ($orac.Success) "$($r.label): guard: el doc trae la oracion del rigor"
  if (-not $orac.Success) { continue }
  $partes = $orac.Value -split ';', 2
  Assert ($partes.Count -eq 2) "$($r.label): guard: la oracion del rigor separa light de standard con punto y coma"
  if ($partes.Count -ne 2) { continue }
  # light: un turno y los focos que dice la tabla. standard: el fan-out completo. Invertirlo da rojo.
  # Solo los dos asserts de focos dependen de la fila light; los demas no se apagan si falta.
  Assert ($partes[0] -match 'one turn') "$($r.label): la clausula de light dice un solo turno"
  Assert ($partes[1] -match 'full fan-out') "$($r.label): la clausula de standard dice fan-out completo"
  if ($fila.Success) {
    $focos = $fila.Groups[1].Value    # "Bugs and Tests"
    Assert ($partes[0] -match [regex]::Escape($focos)) "$($r.label): la clausula de light nombra los focos de la tabla ($focos)"
    Assert ($partes[1] -notmatch [regex]::Escape($focos)) "$($r.label): standard no se queda con los focos de light"
  }
  if ($filaDef.Success) {
    # Anclado a la frase verbal: un `standard` pelado lo esquiva "runs `light`, not `standard`".
    # No hay mitad de `light`: `$partes[0]` lo contiene siempre por el ancla de `$orac`.
    $def = $filaDef.Groups[1].Value
    Assert ($partes[1] -match ('it runs `' + [regex]::Escape($def) + '`')) `
      "$($r.label): la clausula sin trailer corre el rigor por defecto de la tabla ($def)"
  }
}

Write-Host ""
if ($script:failures -eq 0) { Write-Host "TODOS LOS TESTS PASARON"; exit 0 }
Write-Host "$($script:failures) test(s) FALLARON"
exit 1
