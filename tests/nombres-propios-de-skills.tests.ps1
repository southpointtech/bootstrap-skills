# tests/nombres-propios-de-skills.tests.ps1 — runner sin Pester.
# Correr: pwsh -NoProfile -File tests/nombres-propios-de-skills.tests.ps1
#
# POR QUÉ EXISTE: upstream renombró dos de nuestras skills — `to-prd` pasó a `to-spec` y `to-issues`
# se fusionó con `to-plan` en `to-tickets`— y ADR-0006 decidió adoptar los CUERPOS conservando
# NUESTROS nombres, porque `/to-prd` y `/to-issues` están escritos como pasos del flujo en el
# `CLAUDE.md` del scaffold y por lo tanto en el de cada proyecto ya bootstrapeado. Sin un test, la
# próxima sesión que compare el set contra upstream lee `to-prd` como atrasado y lo "corrige",
# rompiendo ese `CLAUDE.md`; y el mapeo nombre-nuestro -> path-upstream, que vive en el lockfile y es
# lo único que le dice al próximo merge de tres vías contra qué archivo comparar, se pierde sin que
# nada lo note (ADR-0005, ADR-0006).
#
# Las anclas negativas no son decoración: un anclaje por presencia es ciego a un mutante por AÑADIDO
# (dejar el cuerpo VIEJO y pegarle el nuevo al lado pasa todas las positivas). Por eso cada frase que
# el cuerpo nuevo REEMPLAZA se asierta ausente.
$ErrorActionPreference = "Stop"
$repo = Split-Path $PSScriptRoot -Parent
$script:failures = 0
$script:checks   = 0

function Assert($cond, $msg) {
  $script:checks++
  if ($cond) { Write-Host "ok:   $msg" } else { Write-Host "FAIL: $msg"; $script:failures++ }
}

# Cantidad EXACTA de aserciones. Se actualiza a mano al agregar o quitar checks. Sin este número un
# mutante que BORRA asserts sale en verde: 0 fails de 0 checks también es "0 fail".
$ExpectedChecks = 88

# Las cuatro raíces que llevan una copia de las skills: el repo y los tres scaffolds. Los nombres de
# los scaffolds se asertan, no se cuentan: con un `-ge` una skill bootstrap podía desaparecer y el
# barrido seguía verde sobre las que quedaran.
$scaffoldsEsperados = @("bootstrap-ai-project", "bootstrap-personal-project", "bootstrap-southpoint-project")
$scaffolds = @($scaffoldsEsperados | ForEach-Object { Join-Path $repo "skills/$_/assets/scaffold" })
$ausentes = @($scaffolds | Where-Object { -not (Test-Path -LiteralPath $_) })
Assert ($ausentes.Count -eq 0) "existen los tres scaffolds que nombra el CLAUDE.md (faltan: $($ausentes -join ', '))"
$raices = @($repo) + $scaffolds

# Texto con fines de línea normalizados: con core.autocrlf=true el MISMO contenido git se materializa
# con bytes distintos según cómo llegó cada archivo (checkout=CRLF, escritura de agente=LF).
function Texto($path) {
  $t = [IO.File]::ReadAllText($path)
  return ($t -replace "`r`n", "`n" -replace "`r", "`n")
}

# El cuerpo: todo salvo la línea `description:` del frontmatter. El SKILL.md y el comando comparten
# cuerpo pero hoy NO comparten description (la del comando todavía es la de la base de upstream), así
# que compararlos enteros mediría otra cosa. La política de descriptions es el issue 13, no éste.
function Cuerpo($texto) {
  return (($texto -split "`n" | Where-Object { -not $_.StartsWith("description:") }) -join "`n")
}

$skills = @(
  @{ nombre = "to-prd"
     # El cuerpo nuevo viene de `skills/engineering/to-spec/SKILL.md` en upstream.
     presentes = @(
       # Paso 2 nuevo: seams en lugar de módulos profundos. Es la contraparte de la skill `tdd`, que
       # desde el issue 06 exige seams PRE-ACORDADOS; to-prd es donde se acuerdan.
       "The fewer seams across the codebase, the better",
       "Check with the user that these seams match their expectations.",
       # El vocabulario del flujo de 8 pasos se conserva: PRD, no spec (ADR-0006).
       "<prd-template>",
       "A description of the things that are out of scope for this PRD.",
       "produces a PRD"
     )
     ausentes = @(
       # Lo que el cuerpo nuevo REEMPLAZA.
       "A deep module (as opposed to a shallow module)",
       "Check with the user which modules they want tests written for.",
       "<spec-template>",
       # El rename de upstream no entra a nuestro árbol.
       "to-spec"
     ) }
  @{ nombre = "to-issues"
     # El cuerpo nuevo viene de `skills/engineering/to-tickets/SKILL.md` en upstream.
     presentes = @(
       "Wide refactors are the exception to vertical slicing.",
       "expand–contract",
       "Make the change easy, then make the easy change.",
       "Work the **frontier**",
       "blocking edges",
       # Drift propio que se re-aplica: la regla del techo del slice, en la lista y en el quiz.
       "Keep each slice ≤ ~400 lines of *logic* diff.",
       "Does any slice project over ~400 lines of logic diff? If so, split it now.",
       # Drift propio que se conserva: HITL/AFK sigue clasificando los slices, porque
       # docs/ai-workflow/PARALELISMO.md del scaffold y los issues del proyecto lo usan.
       "Slices may be 'HITL' or 'AFK'.",
       "- **Type**: HITL / AFK"
     )
     ausentes = @(
       # Lo que el cuerpo nuevo REEMPLAZA (viñeta de la base que upstream sacó).
       "Prefer many thin slices over few thick ones",
       # Un segundo template para el mismo tracker contradiría docs/agents/issue-tracker.md.
       "<local-ticket-template>",
       # El rename de upstream no entra a nuestro árbol.
       "to-tickets"
     ) }
)

foreach ($sk in $skills) {
  $n = $sk.nombre
  $textosSkill = @()
  $textosCmd   = @()
  foreach ($raiz in $raices) {
    $etq = if ($raiz -eq $repo) { "repo" } else { Split-Path (Split-Path (Split-Path $raiz -Parent) -Parent) -Leaf }
    $pSkill = Join-Path $raiz ".agents/skills/$n/SKILL.md"
    $pCmd   = Join-Path $raiz ".claude/commands/$n.md"

    $haySkill = Test-Path -LiteralPath $pSkill
    Assert $haySkill "$etq : existe .agents/skills/$n/SKILL.md"
    $hayCmd = Test-Path -LiteralPath $pCmd
    Assert $hayCmd "$etq : existe .claude/commands/$n.md"

    # El nombre declarado en el frontmatter es el NUESTRO. Se ancla la línea entera: un `Contains`
    # de "$n" matchearía también `name: to-issues-v2` o una mención en la prosa.
    if ($haySkill) {
      $t = Texto $pSkill
      $textosSkill += $t
      Assert (@($t -split "`n") -contains "name: $n") "$etq : el SKILL.md de $n declara ``name: $n``"
    } else { Assert $false "$etq : el SKILL.md de $n declara ``name: $n`` (no se pudo leer)" }
    if ($hayCmd) {
      $t = Texto $pCmd
      $textosCmd += $t
      Assert (@($t -split "`n") -contains "name: $n") "$etq : el comando $n.md declara ``name: $n``"
    } else { Assert $false "$etq : el comando $n.md declara ``name: $n`` (no se pudo leer)" }
  }

  # Las cuatro copias son el mismo archivo. Sin esto, las anclas de contenido de más abajo (que
  # miran una sola copia) dejarían pasar tres copias atrasadas.
  for ($i = 1; $i -lt $raices.Count; $i++) {
    $ok = ($textosSkill.Count -eq $raices.Count) -and ($textosSkill[$i] -ceq $textosSkill[0])
    Assert $ok "$n : la copia $i del SKILL.md es idéntica a la del repo"
    $okc = ($textosCmd.Count -eq $raices.Count) -and ($textosCmd[$i] -ceq $textosCmd[0])
    Assert $okc "$n : la copia $i del comando es idéntica a la del repo"
  }
  # El comando y la skill comparten cuerpo: si uno se actualiza y el otro no, `/to-prd` ejecuta el
  # cuerpo viejo aunque la skill esté al día.
  $mismoCuerpo = ($textosSkill.Count -gt 0 -and $textosCmd.Count -gt 0) -and
                 ((Cuerpo $textosCmd[0]) -ceq (Cuerpo $textosSkill[0]))
  Assert $mismoCuerpo "$n : el comando tiene el mismo cuerpo que el SKILL.md (todo salvo la description)"

  $ref = if ($textosSkill.Count -gt 0) { $textosSkill[0] } else { "" }
  foreach ($frase in $sk.presentes) {
    Assert ($ref.Contains($frase)) "$n : el cuerpo adoptado dice ``$frase``"
  }
  foreach ($frase in $sk.ausentes) {
    Assert (-not $ref.Contains($frase)) "$n : el cuerpo adoptado ya NO dice ``$frase``"
  }
}

# Ninguna referencia del scaffold apunta a los nombres de upstream. El lockfile es la EXCEPCIÓN
# —es justamente donde vive el mapeo— y por eso se excluye acá y se asierta aparte más abajo.
# El manifest es generado y solo lleva paths y hashes.
$excluidos = @("skills-lock.json", ".bootstrap-manifest.json")
$prohibidos = @("to-spec", "to-tickets")
foreach ($raiz in $raices) {
  $etq = if ($raiz -eq $repo) { "repo" } else { Split-Path (Split-Path (Split-Path $raiz -Parent) -Parent) -Leaf }
  # En el repo se barren las dos carpetas donde viven las skills; en un scaffold, todo el árbol.
  $zonas = if ($raiz -eq $repo) { @((Join-Path $raiz ".agents"), (Join-Path $raiz ".claude")) } else { @($raiz) }
  $culpables = @()
  foreach ($zona in $zonas) {
    if (-not (Test-Path -LiteralPath $zona)) { continue }
    foreach ($f in @(Get-ChildItem -LiteralPath $zona -Recurse -File -Force)) {
      if ($excluidos -contains $f.Name) { continue }
      $t = [IO.File]::ReadAllText($f.FullName)
      foreach ($p in $prohibidos) {
        if ($t.Contains($p)) { $culpables += "$($f.Name):$p" }
      }
    }
  }
  Assert ($culpables.Count -eq 0) "$etq : nada del scaffold apunta a to-spec ni a to-tickets ($($culpables -join ', '))"
}

# El lockfile registra el path que cada skill tiene HOY en el HEAD de upstream, bajo su nombre
# renombrado. Sin esto el próximo merge de tres vías compara contra ninguno: busca `to-issues` en un
# upstream donde ese path ya no existe (ADR-0006).
$esperado = @{
  "to-prd"    = "skills/engineering/to-spec/SKILL.md"
  "to-issues" = "skills/engineering/to-tickets/SKILL.md"
}
foreach ($raiz in $raices) {
  $etq = if ($raiz -eq $repo) { "repo" } else { Split-Path (Split-Path (Split-Path $raiz -Parent) -Parent) -Leaf }
  $lock = Join-Path $raiz "skills-lock.json"
  $doc = if (Test-Path -LiteralPath $lock) { [IO.File]::ReadAllText($lock) | ConvertFrom-Json -AsHashtable } else { $null }
  foreach ($n in @("to-prd", "to-issues")) {
    $e = if ($null -ne $doc -and $doc.skills.Contains($n)) { $doc.skills[$n] } else { $null }
    Assert ($null -ne $e -and $e.upstreamHeadPath -eq $esperado[$n]) `
      "$etq : el lockfile mapea $n -> $($esperado[$n]) (dice: $(if ($e) { $e.upstreamHeadPath } else { '<sin entrada>' }))"
    # Sin `upstream-vivo` la herramienta de sellado pone `upstreamHeadPath` en null: el estado y el
    # mapeo son un solo hecho, y asertar solo el path dejaría pasar una entrada que el próximo
    # re-sellado vacía.
    Assert ($null -ne $e -and $e.upstreamState -eq "upstream-vivo") `
      "$etq : el lockfile marca $n como upstream-vivo (dice: $(if ($e) { $e.upstreamState } else { '<sin entrada>' }))"
  }
}

Write-Host ""
if ($script:checks -ne $ExpectedChecks) {
  Write-Host "FAIL: corrieron $($script:checks) aserciones y se esperaban $ExpectedChecks"
  $script:failures++
}
Write-Host "$($script:checks) aserciones, $($script:failures) fallidas"
exit ([int]($script:failures -gt 0))
