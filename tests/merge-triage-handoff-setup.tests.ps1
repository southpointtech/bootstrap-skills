# tests/merge-triage-handoff-setup.tests.ps1 — runner sin Pester.
# Correr: pwsh -NoProfile -File tests/merge-triage-handoff-setup.tests.ps1
#
# POR QUÉ EXISTE (issue v2 08): `triage`, `handoff` y `setup-matt-pocock-skills` tenían el cuerpo
# intacto respecto de su base de upstream y todo el drift propio en la `description`. El merge de tres
# vías se reduce a: adoptar el cuerpo del HEAD de upstream (`mattpocock/skills` @ 959a8e9) y re-aplicar
# lo nuestro. Lo nuestro son tres cosas, y esta suite ancla las tres:
#
#   1. La `description` propia, EXACTA (la política de invocación y su largo son el issue 13, no éste).
#   2. El vocabulario del flujo: upstream renombró `to-prd` -> `to-spec` y `to-issues` -> `to-tickets`
#      y lo llevó al texto distribuido (upstream 386d4ff, 44eed54 y a2f9333). ADR-0006 conserva
#      NUESTROS nombres y "PRD" como término del flujo, así que en esos renglones se revierte el rename.
#   3. La forma de los comandos: `.claude/commands/<n>.md` es el mismo cuerpo con los links a los
#      auxiliares reescritos a `.agents/skills/<n>/<archivo>`, porque el comando no vive en la carpeta
#      de la skill y un link relativo desde ahí no resuelve.
#
# QUÉ NO CUBRE: las anclas son diagnósticas. La red contra un mutante por AÑADIDO en los archivos de
# `.agents/skills/` es el golden por hash de `skills-lock.json` (`tools/skills-lock.ps1 -Action Verify`,
# dentro de `tests/skills-lock.tests.ps1`). Los comandos no los sella nadie: los sostiene la identidad
# entre copias y el assert de cuerpo transformado de acá.
$ErrorActionPreference = "Stop"
$repo = Split-Path $PSScriptRoot -Parent
$script:failures = 0
$script:checks   = 0

function Assert($cond, $msg) {
  $script:checks++
  if ($cond) { Write-Host "ok:   $msg" } else { Write-Host "FAIL: $msg"; $script:failures++ }
}

# Cantidad EXACTA de aserciones: sin esto, un mutante que borra asserts sale en verde.
$ExpectedChecks = 177

$scaffoldsEsperados = @("bootstrap-ai-project", "bootstrap-personal-project", "bootstrap-southpoint-project")
$scaffolds = @($scaffoldsEsperados | ForEach-Object { Join-Path $repo "skills/$_/assets/scaffold" })
$faltan = @($scaffolds | Where-Object { -not (Test-Path -LiteralPath $_) })
Assert ($faltan.Count -eq 0) "existen los tres scaffolds (faltan: $($faltan -join ', '))"
$raices = @($repo) + $scaffolds
function Etiqueta($raiz) { if ($raiz -eq $repo) { "repo" } else { Split-Path (Split-Path (Split-Path $raiz -Parent) -Parent) -Leaf } }

# Fines de línea normalizados: con core.autocrlf=true el mismo blob se materializa con bytes distintos.
function Texto($path) {
  $t = [IO.File]::ReadAllText($path)
  return ($t -replace "`r`n", "`n" -replace "`r", "`n")
}
# El frontmatter: las líneas entre el primer `---` y el que lo cierra. @() AFUERA del if: asignar un
# `if` desenrolla un array de un elemento a string.
function Frontmatter($texto) {
  $todas = @($texto -split "`n")
  $cierre = -1
  if ($todas.Count -gt 0 -and $todas[0] -ceq '---') {
    for ($k = 1; $k -lt $todas.Count; $k++) { if ($todas[$k] -ceq '---') { $cierre = $k; break } }
  }
  return @(if ($cierre -gt 1) { $todas[1..($cierre - 1)] })
}
function Cuerpo($texto) {
  return (($texto -split "`n" | Where-Object { -not $_.StartsWith("description:") }) -join "`n")
}
# El comando = el SKILL.md con los links a los auxiliares apuntando a la carpeta de la skill.
function ComoComando($texto, $nombre, $aux) {
  foreach ($a in $aux) {
    $texto = $texto.Replace("](./$a)", "](.agents/skills/$nombre/$a)").Replace("]($a)", "](.agents/skills/$nombre/$a)")
  }
  return $texto.Replace("seed templates in this skill folder", "seed templates in the skill folder")
}

$skills = @(
  @{ nombre = "triage"
     aux = @("AGENT-BRIEF.md", "OUT-OF-SCOPE.md")
     description = 'Triage issues through a state machine driven by triage roles. Use when the user wants to create an issue, triage/clasificar issues, review incoming bugs or feature requests, label and prioritize the backlog, prepare issues for an AFK/autonomous agent, manage the issue workflow, or says "triageá los issues", "revisá los bugs entrantes", "prepará los tickets para que los agarre un agente", or "ordená/priorizá el backlog".'
     presentes = @{
       "SKILL.md" = @(
         "**a PR is an issue with attached code**",
         "Run two checks against the codebase: (a) **redundancy**",
         # Upstream 221ffca reemplazó `/grill-with-docs` por `grilling` + `domain-modeling` (las trae el
         # issue 09), y fcf0071 fijó esta redacción de llamada por Skill tool.
         'call the Skill tool twice, for "grilling" and "domain-modeling"',
         "**Already implemented**: the change already exists in the codebase.",
         # Upstream 1dab982: una skill no invoca por Skill tool a otra user-invoked; le pide al humano.
         'If not, tell the user to run `/setup-matt-pocock-skills`.'
       )
       "AGENT-BRIEF.md"  = @("### Good agent brief (PR)")
       "OUT-OF-SCOPE.md" = @("Do **not** write here when something is closed as ``wontfix`` because it's **already implemented**.")
     }
     ausentes = @{
       "SKILL.md" = @("run a ``/grill-with-docs`` session", "**Reproduce (bugs only).**")
     } }
  @{ nombre = "handoff"
     aux = @()
     description = 'Compact the current conversation into a handoff document for another agent or session to pick up. Use when the user wants to wrap up and hand off the current work, preserve context before switching agents/terminals, or says "armá un handoff", "documentá el estado para otro agente", "compactá esto en un handoff", or "pasá el contexto a una sesión nueva".'
     presentes = @{
       "SKILL.md" = @(
         "naming which skills the next agent should call the Skill tool for.",
         # Re-aplicado: upstream dice "specs"; el vocabulario del flujo es PRD (ADR-0006).
         "(PRDs, plans, ADRs, issues, commits, diffs)"
       )
     }
     ausentes = @{
       "SKILL.md" = @("which suggests skills that the agent should invoke", "(specs, plans")
     } }
  @{ nombre = "setup-matt-pocock-skills"
     aux = @("domain.md", "issue-tracker-github.md", "issue-tracker-gitlab.md", "issue-tracker-local.md", "triage-labels.md")
     description = 'Sets up an `## Agent skills` block in AGENTS.md/CLAUDE.md and `docs/agents/` so the engineering skills know this repo''s issue tracker (GitHub or local markdown), triage label vocabulary, and domain doc layout. Run before first use of `to-issues`, `to-prd`, `triage`, `diagnose`, `tdd`, `improve-codebase-architecture`, or `zoom-out` — or if those skills appear to be missing context about the issue tracker, triage labels, or domain docs. Trigger when the user says "configurá/prepará las engineering skills", "armá el bloque de agent skills", "las skills no conocen mi issue tracker o mis labels de triage", or is wiring up the Matt Pocock skill set in a new repo for the first time.'
     presentes = @{
       "SKILL.md" = @(
         'Is the `triage` skill installed?',
         "Monorepo signals:",
         "> Do you want to keep the default triage labels? (recommended: **yes**)",
         # Re-aplicado: upstream dice `to-tickets` y `to-spec` (ADR-0006).
         'Skills like `to-issues`, `triage`, and `to-prd` read from and write to it.'
       )
       "domain.md" = @('The `/domain-modeling` skill')
       "issue-tracker-github.md" = @("Issues and PRDs for this repo live as GitHub issues.", "## Pull requests as a triage surface")
       "issue-tracker-gitlab.md" = @("Issues and PRDs for this repo live as GitLab issues.", "## Merge requests as a triage surface", '`glab issue list -F json`')
       "issue-tracker-local.md"  = @(
         "Issues and PRDs for this repo live as markdown files in ``.scratch/``.",
         # Re-aplicado: es el path que usan to-prd y docs/agents/issue-tracker.md del scaffold.
         '- The PRD is `.scratch/<feature-slug>/PRD.md`',
         "never a single combined tickets file"
       )
     }
     ausentes = @{
       "SKILL.md" = @("Don't dump all three at once.")
       "issue-tracker-local.md" = @("spec.md")
     } }
)

foreach ($sk in $skills) {
  $n = $sk.nombre
  $esperados = @(@("SKILL.md") + $sk.aux | Sort-Object)
  $copias = @{}   # archivo -> lista de textos por raíz
  $cmds = @()
  foreach ($raiz in $raices) {
    $etq = Etiqueta $raiz
    $dir = Join-Path $raiz ".agents/skills/$n"
    # El set de archivos EXACTO: ni un auxiliar de menos ni el `agents/openai.yaml` de upstream de más.
    $hay = @(if (Test-Path -LiteralPath $dir) {
      Get-ChildItem -LiteralPath $dir -Recurse -File -Force | ForEach-Object { $_.FullName.Substring($dir.Length + 1).Replace('\', '/') }
    })
    $hay = @($hay | Sort-Object)
    Assert (($hay -join '|') -ceq ($esperados -join '|')) "$etq : .agents/skills/$n tiene exactamente $($esperados -join ', ') (tiene: $($hay -join ', '))"
    foreach ($f in $esperados) {
      $p = Join-Path $dir $f
      if (-not $copias.ContainsKey($f)) { $copias[$f] = @() }
      $copias[$f] += , $(if (Test-Path -LiteralPath $p) { Texto $p } else { $null })
    }
    $pc = Join-Path $raiz ".claude/commands/$n.md"
    $cmds += , $(if (Test-Path -LiteralPath $pc) { Texto $pc } else { $null })
    Assert ($null -ne $cmds[-1]) "$etq : existe .claude/commands/$n.md"

    # name y description, dentro del frontmatter, una sola línea cada una.
    foreach ($par in @(@{ t = $copias["SKILL.md"][-1]; que = "SKILL.md" }, @{ t = $cmds[-1]; que = "comando" })) {
      $fm = Frontmatter $(if ($null -ne $par.t) { $par.t } else { "" })
      Assert (@($fm) -ccontains "name: $n") "$etq : el $($par.que) de $n declara ``name: $n`` en el frontmatter"
      $desc = @($fm | Where-Object { $_ -cmatch '^description:' })
      Assert ($desc.Count -eq 1 -and ($desc[0] -creplace '^description:\s*', '').Trim().Length -gt 0) `
        "$etq : el $($par.que) de $n tiene UNA línea ``description:`` con valor dentro del frontmatter"
    }
    # La description propia del SKILL.md se conserva tal cual.
    $fmS = Frontmatter $(if ($null -ne $copias["SKILL.md"][-1]) { $copias["SKILL.md"][-1] } else { "" })
    Assert (@($fmS) -ccontains "description: $($sk.description)") "$etq : el SKILL.md de $n conserva la description propia"
  }

  # Las cuatro copias de cada archivo y del comando son idénticas.
  foreach ($f in $esperados) {
    for ($i = 1; $i -lt $raices.Count; $i++) {
      Assert ($null -ne $copias[$f][0] -and $copias[$f][$i] -ceq $copias[$f][0]) "$n/$f : la copia de $(Etiqueta $raices[$i]) es idéntica a la del repo"
    }
  }
  for ($i = 1; $i -lt $raices.Count; $i++) {
    Assert ($null -ne $cmds[0] -and $cmds[$i] -ceq $cmds[0]) "$n : el comando de $(Etiqueta $raices[$i]) es idéntico al del repo"
  }

  # El comando ejecuta el mismo cuerpo que la skill, con los links reescritos.
  $skillTxt = if ($null -ne $copias["SKILL.md"][0]) { $copias["SKILL.md"][0] } else { "" }
  $cmdTxt   = if ($null -ne $cmds[0]) { $cmds[0] } else { "" }
  Assert ($skillTxt.Length -gt 0 -and (Cuerpo $cmdTxt) -ceq (Cuerpo (ComoComando $skillTxt $n $sk.aux))) `
    "$n : el comando tiene el cuerpo del SKILL.md con los links a los auxiliares apuntando a .agents/skills/$n/"
  foreach ($a in $sk.aux) {
    Assert ($cmdTxt.Contains("(.agents/skills/$n/$a)")) "$n : el comando linkea .agents/skills/$n/$a"
  }

  # Anclas del cuerpo adoptado.
  foreach ($f in $sk.presentes.Keys) {
    $t = if ($null -ne $copias[$f][0]) { $copias[$f][0] } else { "" }
    foreach ($frase in $sk.presentes[$f]) { Assert ($t.Contains($frase)) "$n/$f dice ``$frase``" }
  }
  foreach ($f in $sk.ausentes.Keys) {
    $t = if ($null -ne $copias[$f][0]) { $copias[$f][0] } else { "" }
    foreach ($frase in $sk.ausentes[$f]) { Assert ($t.Length -gt 0 -and -not $t.Contains($frase)) "$n/$f ya NO dice ``$frase``" }
  }

  # Ningún archivo de la skill ni su comando nombra las skills renombradas de upstream.
  $culpables = @()
  foreach ($f in $esperados) { foreach ($t in @($copias[$f][0])) {
    foreach ($p in @("to-spec", "to-tickets")) { if ($null -ne $t -and $t.IndexOf($p, [StringComparison]::OrdinalIgnoreCase) -ge 0) { $culpables += "${f}:$p" } }
  } }
  Assert ($culpables.Count -eq 0) "$n : ningún archivo nombra to-spec ni to-tickets ($($culpables -join ', '))"
}

# El lockfile sella como base la versión de upstream cuyo CUERPO es el del HEAD (959a8e9), no la base
# vieja: es lo que le dice al próximo merge de tres vías desde dónde comparar. Son los blobs que
# `tools/recover-skill-bases.py` recuperó el 2026-09-18 contra ese clon. Para triage y handoff es el
# blob del HEAD. Para setup NO: el blob del HEAD (7f6f576, upstream 5c89081) y el de 3216582 tienen el
# cuerpo idéntico y difieren sólo en el frontmatter (5c89081 entrecomilló la description), así que
# empatan y la herramienta elige la aparición más vieja (`tieOnIdenticalBodies`).
$bases = @{
  "triage"                   = "37ddea1e3dcf8fb5be5b92e4e45f2c34b8e61d3e"
  "handoff"                  = "2eb98a51b97bb5bac461a26ad14828eeac827909"
  "setup-matt-pocock-skills" = "7ddcbf41d8acbb047078716ed7119357a154590b"
}
foreach ($raiz in $raices) {
  $etq = Etiqueta $raiz
  $lock = Join-Path $raiz "skills-lock.json"
  $doc = if (Test-Path -LiteralPath $lock) { [IO.File]::ReadAllText($lock) | ConvertFrom-Json -AsHashtable } else { $null }
  foreach ($n in $bases.Keys) {
    $e = if ($null -ne $doc -and $doc.skills.Contains($n)) { $doc.skills[$n] } else { $null }
    $blob = if ($null -ne $e -and $null -ne $e.base) { $e.base.blob } else { "<sin base>" }
    Assert ($blob -ceq $bases[$n]) "$etq : el lockfile sella la base de $n en la versión de upstream con el cuerpo de @959a8e9 (dice: $blob)"
  }
}

Write-Host ""
if ($script:checks -ne $ExpectedChecks) {
  Write-Host "FAIL: corrieron $($script:checks) aserciones y se esperaban $ExpectedChecks"
  $script:failures++
}
Write-Host "$($script:checks) aserciones, $($script:failures) fallidas"
exit ([int]($script:failures -gt 0))
