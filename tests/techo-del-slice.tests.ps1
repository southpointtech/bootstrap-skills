# tests/techo-del-slice.tests.ps1 — runner sin Pester.
# Correr: pwsh -NoProfile -File tests/techo-del-slice.tests.ps1
#
# ADR-0008 — el techo de ~400 lineas se mide cuando el slice ABRE, no al cerrarlo. La regla vive en
# los 4 CLAUDE.md (repo + 3 scaffolds) y la EJECUTAN otros cuatro lugares: el pre-flight de
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
    # `\s+` y no un espacio: el texto envuelve, y "The\nceiling" no matchea "the ceiling".
    @{ patron = '(?i)the\s+ceiling is measured at slice open'
       msg    = 'el reviewer sabe que el techo se mide al abrir' }
    @{ patron = '(?i)says nothing about what the slice projected'
       msg    = 'el reviewer no convierte el tamano de la delta en un veredicto de planificacion' }
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
# POR QUE ESTO EXISTE. Ese parrafo del ADR tuvo CUATRO versiones y CUATRO afirmaciones falsas
# distintas sobre los mismos ocho commits, cada una encontrada por un turno del review-loop leyendo
# el arreglo del turno anterior. Agregar clausulas no cerro el ciclo. Lo que lo cierra es sacar el
# numero de la prosa: aca la tabla se compara contra `git`, asi que una quinta version equivocada se
# pone ROJA en vez de publicarse.
#
# La tabla es `<sha>` | <total> (<altas> + <bajas>) y cada fila es UN commit, medido igual que el
# resto del ADR: `git diff --numstat <sha>^ <sha> -- . ':(exclude)*.md'`. Si alguien vuelve a meter
# un rango acumulado como fila, `<sha>^` no es su base y el numero no va a dar.
$adr = Join-Path $repo "docs\adr\0008-el-techo-del-slice-se-mide-al-abrir.md"
if (-not (Test-Path -LiteralPath $adr)) {
  Assert $false "existe docs/adr/0008-el-techo-del-slice-se-mide-al-abrir.md"
} else {
  $filas = [regex]::Matches(
    [IO.File]::ReadAllText($adr),
    '(?m)^\|\s*`([0-9a-f]{7,40})`\s*\|\s*(\d+)\s*\((\d+)\s*\+\s*(\d+)\)\s*\|')
  # Sin este piso, borrar la tabla dejaria el bloque entero en verde sin verificar nada: cero filas,
  # cero asserts, "TODOS LOS TESTS PASARON".
  Assert ($filas.Count -eq 8) "la tabla del ADR-0008 tiene sus 8 filas de commit ($($filas.Count))"

  $scope = 0; $loop = 0
  foreach ($f in $filas) {
    $sha  = $f.Groups[1].Value
    $tot  = [int]$f.Groups[2].Value
    $alt  = [int]$f.Groups[3].Value
    $baj  = [int]$f.Groups[4].Value
    # La linea entera, para clasificar por lo que la propia fila dice de si misma.
    $linea = $f.Value + ([regex]::Match([IO.File]::ReadAllText($adr),
             [regex]::Escape($f.Value) + '([^\r\n]*)').Groups[1].Value)

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

    if ($linea -match 'scope') { $scope += $tot } else { $loop += $tot }
  }

  # Los dos totales que el texto publica, recomputados desde las filas que acabamos de verificar.
  $txtAdr = [IO.File]::ReadAllText($adr)
  Assert ($txtAdr -match "\*\*$scope de scope\*\*") `
    "ADR-0008: el total de scope que publica el texto es el que suman sus filas ($scope)"
  Assert ($txtAdr -match "\*\*$loop de fixes del loop\*\*") `
    "ADR-0008: el total de fixes que publica el texto es el que suman sus filas ($loop)"
  Assert ($scope -lt 400) "ADR-0008: el scope solo ($scope) esta por debajo del techo, como afirma"
  Assert ($loop -gt $scope) "ADR-0008: el loop puso mas lineas que el scope ($loop > $scope)"
}

if ($script:failures -gt 0) { Write-Host "`n$($script:failures) FALLARON"; exit 1 }
Write-Host "`nTODOS LOS TESTS PASARON"; exit 0
