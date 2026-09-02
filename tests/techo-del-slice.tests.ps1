# tests/techo-del-slice.tests.ps1 — runner sin Pester.
# Correr: pwsh -NoProfile -File tests/techo-del-slice.tests.ps1
#
# ADR-0008 — el techo de ~400 lineas se mide cuando el slice ABRE, no al cerrarlo. La regla vive en
# los 4 CLAUDE.md (repo + 3 scaffolds) y la EJECUTAN otros cinco lugares: el pre-flight de
# /review-loop, el paso "Close the slice" de tdd, el pre-flight de /slice-review y los dos docs de
# ai-workflow que el CLAUDE.md declara lectura obligatoria.
#
# Por que existe este test: mirror.tests.ps1 tiene "assets/scaffold/CLAUDE.md" en su allowlist
# (los 4 divergen legitimamente entre variantes), asi que NINGUNA suite miraba el bullet. Los 4
# podian separarse entre si, y la regla podia cambiar en el CLAUDE.md sin que sus ejecutores la
# siguieran — que es exactamente lo que paso y lo que este test impide que vuelva a pasar.
#
# TRAMPA a evitar al editarlo: la primera oracion del bullet
#   "Keep each vertical slice a small, reviewable unit of <= ~400 lines of *logic* diff."
# es IDENTICA en la version vieja y la nueva. Tambien lo son "400" y "split it before implementing".
# Anclar ahi da un test que pasa verde contra el texto que la regla vino a reemplazar.
#
# QUE ESTA PROBADO NO-VACUO Y QUE NO. El RED se corrio contra 919e567 (el commit que cambio el bullet
# sin tocar sus ejecutores). La mayoria de las aserciones se ponen rojas ahi; unas pocas NO, y son
# estas cinco — el resto queda probado por ese RED:
#   - "el techo se mide al ABRIR" y "las lineas del loop no cuentan": ya estaban en 919e567, asi que
#     son pins contra un revert, no verificaciones de este cambio.
#   - "el umbral del hook sigue siendo 400": verde a proposito, el hook no cambia. Su no-vacuidad se
#     probo aparte, con el `\b` (ver el comentario de esa linea).
#   - la mitad negativa del bullet marcada mas abajo: su redaccion vieja ya no estaba en 919e567,
#     asi que tambien es un pin contra revert.
#   - "hay al menos 3 skills bootstrap-*-project": es un piso, no una verificacion del cambio.
# No se anotan totales de fallos aca: cambian cada vez que se agrega una asercion, y quedaron
# desactualizados dos veces. Si necesitas el numero, corre el test contra 919e567 en un worktree.
$ErrorActionPreference = "Stop"
$repo = Split-Path $PSScriptRoot -Parent
$skills = @(Get-ChildItem (Join-Path $repo "skills") -Directory | Where-Object Name -like "bootstrap-*-project")
$script:failures = 0
function Assert($cond, $msg) {
  if ($cond) { Write-Host "ok:   $msg" } else { Write-Host "FAIL: $msg"; $script:failures++ }
}

Assert ($skills.Count -ge 3) "hay al menos 3 skills bootstrap-*-project ($($skills.Count))"

# Un "sitio" = una ruta relativa que existe en el repo y en cada scaffold. Devuelve las 4 copias.
function Copias([string]$rel) {
  $out = @(@{ label = "repo"; path = (Join-Path $repo $rel) })
  foreach ($s in $skills) {
    $out += @{ label = $s.Name; path = (Join-Path $s.FullName (Join-Path "assets\scaffold" $rel)) }
  }
  return $out
}

# Cada copia se verifica con las DOS mitades: la clausula nueva tiene que estar, y la instruccion
# vieja que la contradice NO tiene que estar. Solo la mitad positiva dejaria pasar un archivo que
# dice las dos cosas a la vez — que es el estado exacto en el que quedo el repo tras cambiar el
# bullet sin tocar sus ejecutores.
# LO QUE ESTO NO CUBRE, medido: la mitad negativa esta anclada a la REDACCION vieja, no a la
# semantica, asi que reescribir la misma orden con otras palabras la esquiva — y esquivarla en las
# 4 copias a la vez tampoco lo ve el espejado. Para los dos sitios de ai-workflow eso lo cierra el
# golden del paso 5b; para los otros tres el hueco sigue abierto y queda declarado aca.
function VerificarSitio([string]$rel, [hashtable[]]$debeDecir, [hashtable[]]$noDebeDecir) {
  foreach ($c in Copias $rel) {
    $nombre = "$($c.label)/$rel"
    if (-not (Test-Path -LiteralPath $c.path)) { Assert $false "${nombre}: existe"; continue }
    $txt = [IO.File]::ReadAllText($c.path)
    foreach ($d in $debeDecir) {
      Assert ($txt -match $d.patron) "${nombre}: $($d.msg)"
    }
    foreach ($d in $noDebeDecir) {
      Assert (-not ($txt -match $d.patron)) "${nombre}: $($d.msg)"
    }
  }
}

# --- 1. La regla, en los 4 CLAUDE.md ---
VerificarSitio "CLAUDE.md" @(
  @{ patron = '(?i)ceiling is measured when the slice OPENS'
     msg    = 'el techo se mide al ABRIR el slice' }
  @{ patron = '(?i)do NOT count against the slice they are fixing'
     msg    = 'las lineas que agrega el loop no cuentan contra el slice que arregla' }
  @{ patron = '(?i)declare it in the .Slice-Close:. trailer and in the session handoff'
     msg    = 'el exceso al cerrar se declara en un artefacto nombrado, no al aire' }
  @{ patron = '(?i)is NOT the hook.s ~400-line safety net'
     msg    = 'distingue el techo de planificacion de la red del hook' }
  @{ patron = '(?i)a review it triggers is never spurious'
     msg    = 'cierra la lectura peligrosa: un disparo del hook no se saltea' }
) @(
  # PIN CONTRA REVERT, no verificacion de este cambio: esta redaccion ya no existia en 919e567, asi
  # que esta asercion salio VERDE en el RED. Guarda contra volver al bullet original, no contra el
  # estado intermedio que el turno 1 encontro (bullet nuevo + ejecutores viejos).
  @{ patron = '(?i)Cohesion comes first, but a slice projected'
     msg    = 'ya no queda la redaccion original del bullet (pin contra revert)' }
)

# --- 2. El pre-flight de /review-loop: corre DESPUES del cierre, no puede ordenar partir ---
foreach ($rel in @(".claude\commands\review-loop.md", ".agents\skills\review-loop\SKILL.md")) {
  VerificarSitio $rel @(
    @{ patron = '(?i)do NOT split the slice here'
       msg    = 'el pre-flight no ordena partir' }
    @{ patron = '(?i)exempt from that ceiling'
       msg    = 'declara exentas las lineas del propio loop' }
    @{ patron = '(?i)never turn it into a verdict about how the slice was planned'
       msg    = 'el pre-flight prohibe el veredicto de planificacion SIN condicionarlo al turno' }
  ) @(
    @{ patron = '(?i)stop and split it into smaller slices'
       msg    = 'ya no ordena partir a mitad del loop' }
  )
}

# --- 3. tdd, paso "Close the slice": mide al cerrar, asi que solo puede DECLARAR ---
foreach ($rel in @(".claude\commands\tdd.md", ".agents\skills\tdd\SKILL.md")) {
  VerificarSitio $rel @(
    @{ patron = '(?i)declared in the .Slice-Close:. trailer'
       msg    = 'el exceso al cerrar se declara en el trailer' }
  ) @(
    @{ patron = '(?i)close the cohesive part as its own slice first'
       msg    = 'ya no ordena partir en el cierre' }
  )
}

# --- 4. El pre-flight de /slice-review: no puede fabricar el hallazgo que la regla exime ---
foreach ($rel in @(".claude\commands\slice-review.md", ".agents\skills\slice-review\SKILL.md")) {
  VerificarSitio $rel @(
    # `\s+` donde el texto envuelve: "the\nceiling" no matchea "the ceiling".
    @{ patron = '(?i)the\s+ceiling was spent at open'
       msg    = 'el reviewer sabe que el techo pertenece a la apertura del slice' }
    # Ancla en la forma INCONDICIONAL. La version condicionada ("on turn 2 onward ... says nothing
    # about what the slice projected") satisfacia un ancla mas corta y dejaba el turno 1 sin cubrir.
    @{ patron = '(?i)never turn it into a verdict about how the slice was planned'
       msg    = 'el reviewer prohibe el veredicto de planificacion SIN condicionarlo al turno' }
    @{ patron = '(?i)not on turn 1 either'
       msg    = 'la razon cubre tambien el turno 1' }
  ) @(
    @{ patron = '(?i)flag in the final report that the slice should have\s+been split'
       msg    = 'ya no reporta "should have been split" sobre la delta del loop' }
  )
}

# --- 5. Los dos docs de ai-workflow, que el CLAUDE.md declara lectura obligatoria ---
VerificarSitio "docs\ai-workflow\AI_DEVELOPMENT_WORKFLOW.md" @(
  @{ patron = '(?i)the ceiling is measured when the slice opens'
     msg    = 'el doc de workflow mide al abrir' }
) @(
  @{ patron = '(?i)If a slice is larger, split it'
     msg    = 'ya no ordena partir sobre el PR terminado' }
)

VerificarSitio "docs\ai-workflow\DEPLOYMENT_RULES.md" @(
  @{ patron = '(?i)measured when the slice opens'
     msg    = 'las reglas de deploy miden al abrir' }
) @(
  @{ patron = '(?i)Keep each PR a small, reviewable unit \(target'
     msg    = 'ya no queda la redaccion vieja medida sobre el PR' }
)

# --- 5b. El GOLDEN de los dos parrafos de ai-workflow ---
# Las mitades negativas de arriba estan ancladas a la REDACCION vieja, no a la semantica. Medido:
# reescribir la ultima frase del parrafo a "A slice that ends up larger than planned must be broken
# into smaller slices before the PR is opened" —la orden retroactiva que el ADR-0008 deroga, con
# otras palabras— dejaba las dos mitades VERDES en las 4 copias a la vez, con la contradiccion
# publicada. El golden congela ese parrafo y lo compara byte a byte en las 4 copias, asi que esa
# reescritura ahora se pone roja.
#
# QUE HACE Y QUE NO, medido — no lo escribas mas fuerte de lo que es:
#  - NO impide la reescritura: la vuelve VISIBLE. Re-grabar el golden con
#    `tools/reseal-goldens.ps1` en el mismo commit deja la suite verde, y es a proposito: el
#    reseal es el paso donde un humano mira el diff del fixture y decide. Editarlo a mano, en
#    cambio, sella el bug sin que nadie lo mire (misma regla que el golden del Step 0b).
#  - NO congela el documento, solo esa linea: AGREGAR una frase nueva en otra parte del archivo
#    —"If the final diff ends up above the target, break it into smaller slices before opening
#    the PR"— deja la suite verde con el doc diciendo las dos cosas a la vez. Medido. Congelar el
#    documento entero haria que toda edicion de prosa exigiera un reseal, y no se eligio eso.
#  - Cubre los dos sitios de ai-workflow, de una sola linea e identicos en las 4 copias. Los otros
#    tres sitios siguen con anclas de redaccion, con el hueco declarado arriba.
foreach ($g in @(
  @{ rel = "docs\ai-workflow\AI_DEVELOPMENT_WORKFLOW.md"; ancla = 'ceiling is measured when the slice opens'; fixture = "tests/fixtures/techo-ai-development-workflow.golden.md" }
  @{ rel = "docs\ai-workflow\DEPLOYMENT_RULES.md";        ancla = 'measured when the slice opens';          fixture = "tests/fixtures/techo-deployment-rules.golden.md" })) {
  $gp = Join-Path $repo $g.fixture
  # Se normaliza tambien el CR suelto, igual que `tools/reseal-goldens.ps1`: si un lado lo hace y
  # el otro no, un fixture con un CR suelto deja la suite roja y el reseal diciendo "sin cambios".
  $golden = if (Test-Path -LiteralPath $gp) { ([IO.File]::ReadAllText($gp) -replace "`r`n", "`n" -replace "`r", "`n").Trim("`n") } else { $null }
  Assert (-not [string]::IsNullOrWhiteSpace($golden)) "existe el golden de $($g.rel) y no esta vacio ($($g.fixture))"
  foreach ($c in Copias $g.rel) {
    $nombre = "$($c.label)/$($g.rel)"
    if (-not (Test-Path -LiteralPath $c.path)) { continue }   # el sitio 5 ya puso rojo su existencia
    $lineas = @(([IO.File]::ReadAllText($c.path) -replace "`r`n", "`n" -replace "`r", "`n") -split "`n" | Where-Object { $_.Contains($g.ancla) })
    Assert ($lineas.Count -eq 1) "${nombre}: el parrafo del techo aparece exactamente una vez ($($lineas.Count))"
    if ($lineas.Count -eq 1) {
      Assert ($null -ne $golden -and $lineas[0] -ceq $golden) "${nombre}: el parrafo del techo es identico al golden - si el cambio es deliberado, re-grabalo en $($g.fixture) en este mismo commit"
    }
  }
}

# --- 5c. Las citas del ADR al handoff tienen que resolver a UN solo lugar ---
# El ADR citaba el handoff por numero de linea y las cinco citas quedaron obsoletas: `ed07ceb`
# prepende 210 lineas y todo se corrio. Se cambiaron por anclas de texto, pero eso mueve el riesgo
# en vez de sacarlo: la skill `session-handoff` PREPENDE un bloque por sesion, y estos titulos son
# genericos y repetibles ("El techo de tamano, otra vez"). La cita se rompe en silencio el dia que
# alguien repita uno. Se chequea de los dos lados —que el ADR siga citando el ancla y que el
# handoff la resuelva una sola vez— para que ninguno de los dos se mueva sin el otro.
# Son las cinco citas: cuatro son titulos o filas, y la quinta —la que reemplazo a `:22-23`— se
# ancla por el texto de la fila F14, porque la prosa que la nombra ("tabla de cierre de 04c") no
# es texto del handoff y no resolvia a nada.
$adrPath = Join-Path $repo "docs\adr\0008-el-techo-del-slice-se-mide-al-abrir.md"
$txtAdrCitas = if (Test-Path -LiteralPath $adrPath) { [IO.File]::ReadAllText($adrPath) } else { "" }
$handoffPath = Join-Path $repo "docs\SESSION_HANDOFF.md"
$txtHandoff = if (Test-Path -LiteralPath $handoffPath) { [IO.File]::ReadAllText($handoffPath) } else { $null }
Assert ($null -ne $txtHandoff) "existe docs/SESSION_HANDOFF.md, que es lo que el ADR-0008 cita"
foreach ($a in @('El techo de tamaño, otra vez', 'Dos cosas ABIERTAS que el próximo debe saber',
                 'turno 2 de 5, NO cerrado', '`1c52fe0`…`3e175b0`',
                 '| F14 | la invariante')) {
  Assert ($txtAdrCitas.Contains($a)) "ADR-0008 sigue citando el ancla '$a' del handoff"
  if ($null -ne $txtHandoff) {
    # `Split` con un separador de string cuenta apariciones sin depender de regex: los titulos
    # llevan acentos y comillas que habria que escapar.
    $veces = $txtHandoff.Split(@($a), [StringSplitOptions]::None).Length - 1
    Assert ($veces -eq 1) "el ancla '$a' resuelve a un solo lugar del handoff ($veces) — si una sesión nueva repitió el título, cambiá la cita del ADR-0008 por una que siga siendo única, no el handoff"
  }
}

# --- 6. El hook: su codigo NO cambia, pero su comentario no puede seguir llamandose "el techo del
#     CLAUDE.md", porque el CLAUDE.md ahora dice otra cosa. El umbral literal sigue siendo 400. ---
foreach ($c in Copias ".claude\hooks\review-loop-trigger.ps1") {
  $nombre = "$($c.label)/review-loop-trigger.ps1"
  if (-not (Test-Path -LiteralPath $c.path)) { Assert $false "${nombre}: existe"; continue }
  $txt = [IO.File]::ReadAllText($c.path)
  Assert ($txt -match '(?i)ADR-0008') "${nombre}: el comentario remite al ADR que separa los dos ~400"
  # `\b` obligatorio: sin la frontera, `-le 400` matchea `-le 4000` y la asercion deja de morder.
  # Es una trampa ya documentada en este repo (ver el comentario de review-loop-incremental.tests.ps1
  # y el handoff del 2026-08-13), y se colo igual en la primera version de este archivo.
  Assert ($txt -match '\$lines\s+-le\s+400\b') "${nombre}: el umbral del hook sigue siendo 400"
}

# --- 7. La tabla de medicion del ADR-0008, verificada contra git ---
#
# POR QUE ESTO EXISTE. Ese parrafo del ADR acumulo CINCO afirmaciones falsas sobre los mismos ocho
# commits, cada una encontrada por el turno siguiente del review-loop leyendo el arreglo del turno
# anterior. Agregar clausulas no cerro el ciclo. Lo cierran dos cosas distintas:
#   - la mitad MEDIBLE (los numeros) se saca de la prosa y se compara contra `git`, aca abajo;
#   - la mitad NO medible (a quien atribuirle cada linea) se cierra NO AFIRMANDOLA. `0eb467f` es un
#     commit mixto: cierra F14 y F18, que eran scope, junto con fixes del loop. Cualquier reparto
#     scope/loop de sus 248 lineas seria una estimacion presentada como medicion. El ultimo assert
#     de este bloque impide que ese reparto vuelva al documento.
#
# La tabla es `<sha>` | <total> (<altas> + <bajas>) y cada fila es UN commit, medido igual que el
# resto del ADR: `git diff --numstat <sha>^ <sha> -- . ':(exclude)*.md'`.
$adr = Join-Path $repo "docs\adr\0008-el-techo-del-slice-se-mide-al-abrir.md"
if (-not (Test-Path -LiteralPath $adr)) {
  Assert $false "existe docs/adr/0008-el-techo-del-slice-se-mide-al-abrir.md"
} else {
  $txtAdr = [IO.File]::ReadAllText($adr)
  $filas = [regex]::Matches($txtAdr,
    '(?m)^\|\s*`([0-9a-f]{7,40})`\s*\|\s*(\d+)\s*\((\d+)\s*\+\s*(\d+)\)\s*\|')
  # Sin este piso, borrar la tabla dejaria el bloque entero en verde sin verificar nada: cero filas,
  # cero asserts, "TODOS LOS TESTS PASARON".
  Assert ($filas.Count -eq 8) "la tabla del ADR-0008 tiene sus 8 filas de commit ($($filas.Count))"

  foreach ($f in $filas) {
    $sha = $f.Groups[1].Value
    $tot = [int]$f.Groups[2].Value
    $alt = [int]$f.Groups[3].Value
    $baj = [int]$f.Groups[4].Value

    $a = 0; $d = 0
    $rows = @(git -C $repo diff --numstat "$sha^" $sha -- . ':(exclude)*.md' 2>$null)
    $medible = ($LASTEXITCODE -eq 0)
    foreach ($r in $rows) {
      $c = $r -split "`t"
      if ($c.Count -ge 2 -and $c[0] -match '^\d+$' -and $c[1] -match '^\d+$') {
        $a += [int]$c[0]; $d += [int]$c[1]
      }
    }
    # Si git no pudo medir, esto NO puede pasar en silencio: seria el test verde sobre nada.
    Assert $medible "ADR-0008/${sha}: git pudo medir el commit"
    if (-not $medible) { continue }
    Assert (($a -eq $alt) -and ($d -eq $baj) -and ($tot -eq ($alt + $baj))) `
      "ADR-0008/${sha}: la tabla dice $tot ($alt + $baj) y git mide $($a+$d) ($a + $d)"
  }

  # MEMBRESIA, no solo medicion. El turno 4 del loop probo que verificar solo los numeros deja pasar
  # las dos formas en que este parrafo fallo de verdad: cambiar una fila por un commit repetido queda
  # verde, y AGREGAR una novena fila con un rango acumulado tambien (no parsea como sha, asi que el
  # piso de 8 lo satisfacen las buenas y la mentirosa se publica sin ningun assert encima).
  $delSlice = @(git -C $repo rev-list --reverse "3e175b0..2edb0a1" 2>$null)
  Assert (($LASTEXITCODE -eq 0) -and ($delSlice.Count -eq 8)) `
    "git enumera los 8 commits del slice 04c ($($delSlice.Count))"
  $enTabla = @($filas | ForEach-Object { $_.Groups[1].Value })
  for ($i = 0; $i -lt [Math]::Min($enTabla.Count, $delSlice.Count); $i++) {
    Assert ($delSlice[$i].StartsWith($enTabla[$i])) `
      "ADR-0008 fila $($i+1): $($enTabla[$i]) es el commit $($i+1) del slice"
  }

  # Ninguna fila de NINGUNA tabla puede ser un rango. Se mira el documento entero, no la region de
  # la tabla principal: el turno 5 probo que acotarlo a esa region dejaba pasar una SEGUNDA tabla,
  # 15 lineas mas abajo, titulada "Reparto, commit por commit" y hecha de rangos acumulados. Una
  # fila `a..b` no parsea como sha, asi que el bucle de medicion tampoco la ve: si no se la caza
  # aca, no la caza nadie.
  # Se ancla en la PRIMERA celda, que es donde va el commit. Un rango nombrado en otra columna es
  # legitimo (la tabla de bases dice sobre que rango mide cada una); lo que no puede pasar es que un
  # rango ocupe el lugar de un commit.
  #
  # ESTO ES UN ALAMBRE DE TROPIEZO, NO UNA PRUEBA. Declararlo es parte del guard, no una excusa:
  # se lo ensancho cuatro veces y cada ronda de mutacion encontro formas nuevas de esquivarlo
  # —sin backticks, negrita, indentacion, blockquote, sin pipes externos, una palabra antes del
  # sha, link markdown, tabla HTML, elipsis unicode, <td> multilinea, <th>, entidades numericas,
  # sha de 6 caracteres—. Es la cuarta vez que este repo mide lo mismo: parchar un guard de
  # superficie no converge (ver ADR-0008 y la nota de `VerificarSitio`). Asi que se dejo de
  # ensanchar a proposito. Caza la forma en que un autor escribiria la fila sin querer; a quien
  # busque el hueco se lo dejamos declarado.
  #
  # QUE CAZA, medido: la fila con o sin backticks, en negrita, indentada, con el sha en
  # mayusculas, con `...` en vez de `..`, con la celda envuelta en un link markdown, con etiquetas
  # HTML inline en el medio, con elipsis unicode, y la fila HTML de una linea (primer `<td>`).
  # QUE NO CAZA, declarado: una palabra antes del sha (`commit 900ba7f..2edb0a1`), la fila dentro
  # de un blockquote —que en este archivo es CITA, y los otros guards tambien la excluyen—, un
  # rango en la SEGUNDA celda con una columna indice adelante, un `<td>` partido en varias lineas,
  # un `<th>`, las entidades numericas (`&#46;`) y un sha abreviado a menos de 7.
  # El rango exige los DOS lados: `<sha>..<sha|HEAD>`. Sin el lado derecho, una elipsis de prosa
  # detras de un sha (`| \`cf925c0\` ... |`) normalizaba a `cf925c0...` y ponia roja una fila
  # legitima. `-match` es case-insensitive, asi que el sha en mayusculas entra igual.
  $reRango = '^[0-9a-f]{7,40}\.\.\.?(?:[0-9a-f]|HEAD)'
  function CeldaNormalizada([string]$linea) {
    # El blockquote NO se pela: en este archivo `>` es cita, y confundir la cita con la afirmacion
    # es el error que los otros guards de aca evitan. Pelarlo hacia roja la retractacion, que cita
    # la fila retractada a proposito.
    if ($linea -match '^\s*>') { return $null }
    $l = $linea -replace '^\s+', ''
    $l = $l -replace '^\|', ''
    if (-not $l.Contains('|')) { return $null }
    $celda = $l.Substring(0, $l.IndexOf('|'))
    # `[label](url)` se queda con el label, y las etiquetas HTML inline se van: las dos escondian
    # el rango dentro de la celda.
    $celda = [regex]::Replace($celda, '\[([^\]]*)\]\([^)]*\)', '$1')
    $celda = [regex]::Replace($celda, '<[^>]*>', '')
    # La elipsis unicode se normaliza a `..` porque es como el propio ADR escribe rangos.
    return (($celda -replace '\u2026', '..') -replace '[`*\s]', '')
  }
  $filasRango = @()
  foreach ($linea in [regex]::Split($txtAdr, '\r?\n')) {
    # La fila HTML de una linea: solo el PRIMER `<td>`, que es el que ocupa el lugar del commit.
    # Mirar todos hacia roja una tabla con columna indice, que en GFM si es legitima.
    $td = [regex]::Match($linea, '(?i)<td[^>]*>([^<]*)<')
    if ($td.Success -and ((($td.Groups[1].Value -replace '\u2026', '..') -replace '[`*\s]', '') -match $reRango)) {
      $filasRango += $linea
      continue
    }
    $celda = CeldaNormalizada $linea
    if ($null -eq $celda) { continue }
    # El rango tiene que ARRANCAR la celda. Buscarlo en cualquier parte cazaba una palabra antes
    # del sha, pero ponia roja la fila legitima que DESCRIBE una base nombrando su rango
    # (`| altas + bajas sobre \`3e175b0..2edb0a1\` | 660 | ... |`) y cualquier prosa con un pipe
    # adentro. Se eligio el falso negativo declarado por sobre el falso positivo que rompe el doc.
    if ($celda -match $reRango) { $filasRango += $linea }
  }
  Assert ($filasRango.Count -eq 0) `
    "ninguna fila de tabla del ADR-0008 tiene un rango acumulado donde va el commit ($($filasRango.Count))"

  # El unico numero derivado que el texto publica: las lineas de los commits POSTERIORES al cierre
  # declarado (`900ba7f`). Es derivable porque son commits enteros; el reparto scope/loop NO lo es.
  $iCierre = -1
  for ($i = 0; $i -lt $enTabla.Count; $i++) {
    if ("900ba7fc72555a659162d81c4975c6d5ce0b57aa".StartsWith($enTabla[$i])) { $iCierre = $i }
  }
  Assert ($iCierre -ge 0) "la fila del cierre declarado (900ba7f) esta en la tabla"
  if ($iCierre -ge 0) {
    $post = 0
    for ($i = $iCierre + 1; $i -lt $filas.Count; $i++) { $post += [int]$filas[$i].Groups[2].Value }
    Assert ($post -gt 0) "hay commits posteriores al cierre declarado ($post lineas)"
    Assert ($txtAdr -match "\*\*$post[\s\r\n]+lineas\*\*|\*\*$post[\s\r\n]+l\u00edneas\*\*") `
      "ADR-0008: las lineas posteriores al cierre que publica el texto son las que suman sus filas ($post)"
    Assert ($post -gt 400) "ADR-0008: esas lineas superan el techo, como afirma el texto ($post)"
  }

  # La afirmacion que el turno 4 tiro abajo no puede volver por la ventana. DOS MITADES, porque una
  # sola no alcanza:
  #
  # La NEGATIVA es un ALAMBRE DE TROPIEZO, no una prueba. Vigila las formas conocidas de escribir el
  # reparto; una redaccion nueva lo esquiva, y el turno 5 lo demostro: con el ancla vieja
  # (`\d+ de scope`), la frase "El scope aporta 349 lineas y el loop las 683 restantes" pasaba en
  # verde. Es la trampa ya fichada en este repo: un match sobre prosa no expresa semantica. Por eso
  # va acompanada de la mitad POSITIVA, que ancla en la seccion donde el documento explica POR QUE no
  # hay reparto: mientras esa seccion siga ahi, republicar el reparto se contradice con ella a la
  # vista, que es lo mas que un test de prosa puede dar.
  # El bloque de retractacion CITA las falsedades a proposito, asi que los guards no pueden mirarlo:
  # un guard que confunde la cita con la afirmacion es inservible. La retractacion es una blockquote,
  # y solo ella lo es en este documento — se descartan las lineas que empiezan con `>`.
  $sinCitas = ($txtAdr -split "`r?`n" | Where-Object { $_ -notmatch '^\s*>' }) -join "`n"
  Assert ($sinCitas -match '(?m)^### Por qué acá no hay un reparto') `
    "el filtro de citas no se comio el cuerpo del documento"
  foreach ($mala in @(
      '(?i)\d[\d.,]*\s+de scope',
      '(?i)(scope|loop)\s+(aporta|aportó|aporto|puso|sum[oa]|agreg[oa])\s+(las\s+)?\*{0,2}\d',
      '(?i)el scope solo está por debajo del techo',
      '(?i)\*{0,2}\d[\d.,]*\*{0,2}\s+líneas?\s+de\s+(scope|fixes del loop)')) {
    Assert (-not ($sinCitas -match $mala)) `
      "ADR-0008 no republica el reparto scope/loop en la forma /$mala/"
  }
  Assert ($txtAdr -match '(?m)^###\s+Por qué acá no hay un reparto') `
    "ADR-0008 conserva la seccion que explica por que el reparto no es medible"
  Assert ($txtAdr -match '(?i)sería una estimación presentada como medición') `
    "ADR-0008 dice explicitamente que repartir esas lineas seria estimar, no medir"
}

if ($script:failures -gt 0) { Write-Host "`n$($script:failures) FALLARON"; exit 1 }
Write-Host "`nTODOS LOS TESTS PASARON"; exit 0
