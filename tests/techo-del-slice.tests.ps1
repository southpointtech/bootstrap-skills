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
# sin tocar sus ejecutores): 88 fallos, 17 ok. O sea que la mayoria de las aserciones muerden, pero
# NO todas, y conviene saber cuales:
#   - Rojas contra 919e567, o sea probadas: las 5 mitades negativas de los ejecutores, y las
#     clausulas nuevas del bullet (artefacto nombrado, distincion con la red del hook, disparo no
#     espurio).
#   - Verdes contra 919e567, o sea NO probadas por ese RED: "el techo se mide al ABRIR" y "las lineas
#     del loop no cuentan" (ya estaban en 919e567: son pins contra un revert, no contra este cambio),
#     "el umbral del hook sigue siendo 400" (verde a proposito: el hook no cambia), y la mitad
#     negativa del bullet en la linea marcada mas abajo, cuya redaccion vieja ya no estaba en
#     919e567 — tambien es un pin contra un revert al texto original, no una verificacion de este
#     cambio. Si agregas aserciones, decidi a proposito en cual de los dos grupos caen.
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
    @{ patron = '(?i)it says nothing about what the slice projected when it opened'
       msg    = 'el pre-flight no concluye un veredicto de planificacion desde la delta' }
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

if ($script:failures -gt 0) { Write-Host "`n$($script:failures) FALLARON"; exit 1 }
Write-Host "`nTODOS LOS TESTS PASARON"; exit 0
