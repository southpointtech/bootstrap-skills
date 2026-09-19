# tests/chicas-y-forks-propios.tests.ps1 — runner sin Pester.
# Correr: pwsh -NoProfile -File tests/chicas-y-forks-propios.tests.ps1
#
# POR QUÉ EXISTE (issue v2 12): entran al scaffold tres skills chicas de upstream (`mattpocock/skills`
# @ 959a8e9) con el cuerpo de upstream y la description propia, con triggers en español:
# `research`, `resolving-merge-conflicts` y `git-guardrails-claude-code`. `writing-for-agents` NO va
# al scaffold. Y `zoom-out`, que upstream borró, queda en el lockfile como `upstream-huerfano` con su
# base: un merge futuro no la reporta como faltante ni la borra.
#
# QUÉ NO CUBRE: la red contra una edición cualquiera de `.agents/skills/` es el golden por hash de
# `skills-lock.json` (`tests/skills-lock.tests.ps1`). Esta suite aporta lo que el golden no ve: que el
# comando sea la misma skill, QUÉ regla se perdió cuando algo cambia, y el contrato de `zoom-out`.
$ErrorActionPreference = "Stop"
$repo = Split-Path $PSScriptRoot -Parent
$tool = Join-Path $repo "tools/skills-lock.ps1"
$script:failures = 0
$script:checks   = 0

function Assert($cond, $msg) {
  $script:checks++
  if ($cond) { Write-Host "ok:   $msg" } else { Write-Host "FAIL: $msg"; $script:failures++ }
}

# Cantidad EXACTA de aserciones: sin ella, un mutante que borra asserts sale en verde (0 de 0).
$ExpectedChecks = 155

. (Join-Path $PSScriptRoot "lib\temp-workspace.ps1")
$script:runRoot = New-TestRunRoot "chfp"
trap { Remove-TestRunRoot $script:runRoot; break }

$scaffoldsEsperados = @("bootstrap-ai-project", "bootstrap-personal-project", "bootstrap-southpoint-project")
$scaffolds = @($scaffoldsEsperados | ForEach-Object { Join-Path $repo "skills/$_/assets/scaffold" })
$faltan = @($scaffolds | Where-Object { -not (Test-Path -LiteralPath $_) })
Assert ($faltan.Count -eq 0) "existen los tres scaffolds (faltan: $($faltan -join ', '))"
$raices = @($repo) + $scaffolds
function Etiqueta($raiz) { if ($raiz -eq $repo) { "repo" } else { Split-Path (Split-Path (Split-Path $raiz -Parent) -Parent) -Leaf } }

function Texto($path) {
  if (-not (Test-Path -LiteralPath $path)) { return $null }
  return ([IO.File]::ReadAllText($path) -replace "`r`n", "`n" -replace "`r", "`n")
}
# Las líneas entre el primer `---` y el que lo cierra. @() AFUERA del if: asignar un `if` desenrolla
# un array de un elemento a string.
function Frontmatter($texto) {
  if ($null -eq $texto) { return @() }
  $todas = @($texto -split "`n")
  $cierre = -1
  if ($todas[0] -ceq '---') {
    for ($k = 1; $k -lt $todas.Count; $k++) { if ($todas[$k] -ceq '---') { $cierre = $k; break } }
  }
  return @(if ($cierre -gt 1) { $todas[1..($cierre - 1)] })
}
# El comando = el SKILL.md con los links a los auxiliares apuntando a la carpeta de la skill: el
# comando no vive en esa carpeta y un link relativo desde `.claude/commands/` no resuelve.
function ComoComando($texto, $nombre, $aux) {
  foreach ($a in $aux) { $texto = $texto.Replace("]($a)", "](.agents/skills/$nombre/$a)") }
  return $texto
}

# --- A. Las tres chicas, en la raíz y en los tres scaffolds -------------------------------------
$skills = @(
  @{ nombre = "research"
     aux = @()
     description = 'Investigate a question against high-trust primary sources and capture the findings as a Markdown file in the repo. Use when the user wants a topic researched, docs or API facts gathered, or reading legwork delegated to a background agent, or says "investigá esto", "averiguá cómo funciona", "buscá en la documentación oficial", "juntá la info antes de implementar", or "dejá lo que encuentres en un markdown".'
     presentes = @(
       "Spin up a **background agent** to do the research, so you keep working while it reads.",
       "Investigate the question against **primary sources**",
       "Write the findings to a single Markdown file, citing each claim's source.") }
  @{ nombre = "resolving-merge-conflicts"
     aux = @()
     description = 'Use when you need to resolve an in-progress git merge/rebase conflict. Trigger when a merge or rebase stopped on conflicts, or the user says "resolvé los conflictos", "arreglá el merge", "se trabó el rebase", "hay conflictos", or "terminá el merge".'
     presentes = @(
       "1. **See the current state** of the merge/rebase.",
       "Do **not** invent new behaviour. Always resolve; never ``--abort``.",
       "5. **Finish the merge/rebase.**") }
  @{ nombre = "git-guardrails-claude-code"
     aux = @("scripts/block-dangerous-git.sh")
     description = 'Set up Claude Code hooks to block dangerous git commands (push, reset --hard, clean, branch -D, etc.) before they execute. Use when user wants to prevent destructive git operations, add git safety hooks, or block git push/reset in Claude Code, or says "bloqueá los comandos peligrosos de git", "que el agente no pueda pushear", "poné un guardrail de git", or "protegé el repo de un reset --hard".'
     presentes = @(
       "### 1. Ask scope",
       "### 5. Verify",
       '"matcher": "Bash",',
       "Should exit with code 2 and print a BLOCKED message to stderr.",
       # Lo nuestro: el hook no cubre la herramienta PowerShell (misma clase que el issue 21).
       "## What it does not cover",
       'a matcher of `Bash` does not match it: a `git push` sent through PowerShell never reaches this hook.') }
)

foreach ($sk in $skills) {
  $n = $sk.nombre
  $esperados = @(@("SKILL.md") + $sk.aux | Sort-Object)
  $copias = @{}
  $cmds = @()
  foreach ($raiz in $raices) {
    $etq = Etiqueta $raiz
    $dir = Join-Path $raiz ".agents/skills/$n"
    # El set EXACTO: ni un auxiliar de menos ni el `agents/openai.yaml` de upstream de más.
    $hay = @(if (Test-Path -LiteralPath $dir) {
      Get-ChildItem -LiteralPath $dir -Recurse -File -Force | ForEach-Object { $_.FullName.Substring($dir.Length + 1).Replace('\', '/') }
    })
    $hay = @($hay | Sort-Object)
    Assert (($hay -join '|') -ceq ($esperados -join '|')) "$etq : .agents/skills/$n tiene exactamente $($esperados -join ', ') (tiene: $($hay -join ', '))"
    foreach ($f in $esperados) {
      if (-not $copias.ContainsKey($f)) { $copias[$f] = @() }
      $copias[$f] += , (Texto (Join-Path $dir $f))
    }
    $cmds += , (Texto (Join-Path $raiz ".claude/commands/$n.md"))
    Assert ($null -ne $cmds[-1]) "$etq : existe .claude/commands/$n.md"

    $fm = Frontmatter $copias["SKILL.md"][-1]
    Assert (@($fm) -ccontains "name: $n") "$etq : el SKILL.md de $n declara name: $n en el frontmatter"
    Assert (@($fm) -ccontains "description: $($sk.description)") "$etq : el SKILL.md de $n tiene la description propia, con sus triggers en español"
    # Alcanzable por el agente: sin `disable-model-invocation`.
    Assert (-not (@($fm) -match '^disable-model-invocation:')) "$etq : $n es model-invoked"
  }

  # La description es un escalar YAML plano válido: un ': ' o un ' #' adentro rompe el frontmatter
  # entero y Claude Code se queda sin ningún trigger (lo que le pasó a review-loop).
  Assert (-not $sk.description.Contains(': ') -and -not $sk.description.Contains(' #') -and $sk.description[0] -notin @('"', "'", '`', '@')) `
    "$n : la description es un escalar YAML plano (sin ': ' ni ' #' adentro)"

  foreach ($f in $esperados) {
    for ($i = 1; $i -lt $raices.Count; $i++) {
      Assert ($null -ne $copias[$f][0] -and $copias[$f][$i] -ceq $copias[$f][0]) "$n/$f : la copia de $(Etiqueta $raices[$i]) es idéntica a la del repo"
    }
  }
  for ($i = 1; $i -lt $raices.Count; $i++) {
    Assert ($null -ne $cmds[0] -and $cmds[$i] -ceq $cmds[0]) "$n : el comando de $(Etiqueta $raices[$i]) es idéntico al del repo"
  }
  $skillTxt = if ($null -ne $copias["SKILL.md"][0]) { $copias["SKILL.md"][0] } else { "" }
  Assert ($skillTxt.Length -gt 0 -and $cmds[0] -ceq (ComoComando $skillTxt $n $sk.aux)) `
    "$n : el comando es el SKILL.md, con los links a los auxiliares apuntando a .agents/skills/$n/"
  foreach ($a in $sk.aux) {
    Assert ($null -ne $cmds[0] -and $cmds[0].Contains("](.agents/skills/$n/$a)")) "$n : el comando linkea .agents/skills/$n/$a"
  }
  foreach ($frase in $sk.presentes) { Assert ($skillTxt.Contains($frase)) "$n/SKILL.md dice ``$frase``" }
}
# El script del hook: el de upstream @ 959a8e9, con sus patrones. Si alguien lo edita, el lockfile
# lo delata; esta ancla dice qué patrón se perdió.
$sh = Texto (Join-Path $repo ".agents/skills/git-guardrails-claude-code/scripts/block-dangerous-git.sh")
foreach ($frase in @('#!/bin/bash', "COMMAND=`$(echo `"`$INPUT`" | jq -r '.tool_input.command')", '"git push"', '"git reset --hard"', '"git branch -D"', 'exit 2')) {
  Assert ($null -ne $sh -and $sh.Contains($frase)) "block-dangerous-git.sh dice ``$frase``"
}

# El lockfile sella como base el blob del HEAD de upstream (959a8e9) de cada una: es desde donde
# compara el próximo merge de tres vías. Son los que `tools/recover-skill-bases.py` recuperó el
# 2026-09-19 contra ese clon, y coinciden con `git rev-parse 959a8e9:<path>`.
$bases = @{
  "research"                   = "fecee97e9457ba039678d2fcf1b1bc9fca78307d"
  "resolving-merge-conflicts"  = "bfb7e5606e231e6808979f623fce76a9aad4b71c"
  "git-guardrails-claude-code" = "58bcdd875b164093b95f436fa32a65c6cb5eb572"
}
foreach ($raiz in $raices) {
  $etq = Etiqueta $raiz
  $lockTxt = Texto (Join-Path $raiz "skills-lock.json")
  $doc = if ($null -ne $lockTxt) { $lockTxt | ConvertFrom-Json -AsHashtable } else { $null }
  foreach ($n in @($bases.Keys | Sort-Object)) {
    $e = if ($null -ne $doc -and $doc.skills.Contains($n)) { $doc.skills[$n] } else { $null }
    $blob = if ($null -ne $e -and $null -ne $e.base) { $e.base.blob } else { "<sin base>" }
    Assert ($null -ne $e -and $e.upstreamState -ceq "upstream-vivo" -and $blob -ceq $bases[$n]) "$etq : el lockfile sella $n como upstream-vivo con la base del HEAD de upstream (dice: $blob)"
  }
}

# --- B. writing-for-agents no viaja al scaffold ------------------------------------------------
# Es una skill meta, para quien mantiene el scaffold: instalada en cada proyecto bootstrapeado se
# pagaría en el listado de skills sin que nadie la invoque.
foreach ($s in $scaffolds) {
  $etq = Etiqueta $s
  Assert (-not (Test-Path -LiteralPath (Join-Path $s ".agents/skills/writing-for-agents"))) "$etq : writing-for-agents NO está en .agents/skills del scaffold"
  Assert (-not (Test-Path -LiteralPath (Join-Path $s ".claude/commands/writing-for-agents.md"))) "$etq : writing-for-agents NO tiene comando en el scaffold"
}

# --- C. zoom-out: upstream-huerfano, ni faltante ni borrada --------------------------------------
# Upstream la borró. La recuperación por similitud SÍ le encontró base (7afa86d), y ADR-0005 no deja
# colapsar ese estado en fork-propio: tiraría la base.
$zoomBase = "7afa86d3"
foreach ($raiz in $raices) {
  $etq = Etiqueta $raiz
  Assert (Test-Path -LiteralPath (Join-Path $raiz ".agents/skills/zoom-out/SKILL.md")) "$etq : zoom-out sigue en .agents/skills"
  Assert (Test-Path -LiteralPath (Join-Path $raiz ".claude/commands/zoom-out.md")) "$etq : zoom-out sigue con su comando"
  $lock = Texto (Join-Path $raiz "skills-lock.json")
  $e = if ($null -ne $lock) { ($lock | ConvertFrom-Json -AsHashtable).skills["zoom-out"] } else { $null }
  Assert ($null -ne $e -and $e.upstreamState -ceq "upstream-huerfano") "$etq : el lockfile tiene zoom-out como upstream-huerfano ($(if ($e) { $e.upstreamState }))"
  Assert ($null -ne $e -and $null -ne $e.base -and "$($e.base.commit)".StartsWith($zoomBase) -and $e.base.upstreamPath -ceq "skills/engineering/zoom-out/SKILL.md") `
    "$etq : y conserva su base ($zoomBase, skills/engineering/zoom-out/SKILL.md)"
  Assert ($null -ne $e -and $null -eq $e.upstreamHeadPath -and $null -ne $e.source) "$etq : sin path en el HEAD de upstream (ahí ya no está) pero con su origen"
}

# El lockfile real verifica, y zoom-out no aparece en ningún reporte.
$v = & pwsh -NoProfile -File $tool -Action Verify 2>&1 | Out-String
Assert ($LASTEXITCODE -eq 0) "skills-lock.ps1 -Action Verify da verde sobre el árbol real (salida: $v)"
Assert (-not $v.Contains("zoom-out")) "y no nombra a zoom-out"

# El merge futuro, sobre una copia del árbol real: un re-sellado con -Bases, que es lo que corre al
# cerrar un merge de tres vías (docs/agents/recuperar-base-de-skills.md). Las bases se arman como las
# emite tools/recover-skill-bases.py para lo que el lockfile ya dice: zoom-out sale `recovered` con
# `gone-from-upstream-head`, que es lo que la herramienta reportó contra 959a8e9.
$sim = New-TestWorkspace -Root $script:runRoot -Name "merge"
$simSkills = Join-Path $sim ".agents/skills"
[IO.Directory]::CreateDirectory($simSkills) | Out-Null
Copy-Item -Path (Join-Path $repo ".agents/skills/*") -Destination $simSkills -Recurse -Force
Copy-Item -LiteralPath (Join-Path $repo "skills-lock.json") -Destination (Join-Path $sim "skills-lock.json")
$real = [IO.File]::ReadAllText((Join-Path $repo "skills-lock.json")) | ConvertFrom-Json -AsHashtable
$basesSim = @{
  upstream = @{ url = $real.upstream.url; head = $real.upstream.head }
  skills   = @(foreach ($k in $real.skills.Keys) {
    $e = $real.skills[$k]
    if ($null -eq $e.base) {
      @{ name = $k; status = "unmatched"; upstreamRelation = "no-match-above-threshold"; base = $null }
    } else {
      $gone = $e.upstreamState -eq "upstream-huerfano"
      @{ name = $k; status = "recovered"
         upstreamRelation = if ($gone) { "gone-from-upstream-head" } else { "in-upstream-head" }
         upstreamHead = @{ status = if ($gone) { "gone" } else { "present" }; path = $e.upstreamHeadPath }
         base = @{ blob = $e.base.blob; upstreamPath = $e.base.upstreamPath; commit = $e.base.commit; commitDate = $e.base.commitDate } }
    }
  })
}
$basesPath = New-TestTempPath -Root $script:runRoot -Name "bases" -Extension ".json"
[IO.File]::WriteAllText($basesPath, ($basesSim | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
$s = & pwsh -NoProfile -File $tool -Action Seal -Repo $sim -Bases $basesPath 2>&1 | Out-String
Assert ($LASTEXITCODE -eq 0) "el re-sellado del merge futuro da verde (salida: $s)"
Assert (-not $s.Contains("zoom-out")) "y no reporta a zoom-out (ni faltante ni sobrante)"
Assert (Test-Path -LiteralPath (Join-Path $simSkills "zoom-out/SKILL.md")) "y no borra la skill del árbol"
$despues = [IO.File]::ReadAllText((Join-Path $sim "skills-lock.json")) | ConvertFrom-Json -AsHashtable
$ez = $despues.skills["zoom-out"]
Assert ($null -ne $ez -and $ez.upstreamState -ceq "upstream-huerfano" -and "$($ez.base.commit)".StartsWith($zoomBase)) `
  "y zoom-out sigue sellada como upstream-huerfano con su base"
Assert ((Texto (Join-Path $sim "skills-lock.json")) -ceq (Texto (Join-Path $repo "skills-lock.json"))) `
  "el lockfile re-sellado es el mismo documento que el real: el merge no movió nada"

# --- D. This delivers: cuántas vienen por el lockfile -------------------------------------------
# mirror.tests.ps1 ata el total de skills y comandos; el desglose "N synced via skills-lock.json" no
# lo ataba nadie. Son las entradas del lockfile que vienen de upstream (todo menos fork-propio).
$sincronizadas = @($real.skills.Keys | Where-Object { $real.skills[$_].upstreamState -ne "fork-propio" }).Count
foreach ($b in $scaffoldsEsperados) {
  $t = Texto (Join-Path $repo "skills/$b/SKILL.md")
  $m = [regex]::Match($t, '\((\d+) skills — (\d+) synced via `skills-lock\.json`')
  Assert ($m.Success -and [int]$m.Groups[2].Value -eq $sincronizadas) "${b}: 'This delivers' dice $($m.Groups[2].Value) sincronizadas por el lockfile y son $sincronizadas"
}

Remove-TestRunRoot $script:runRoot
Write-Host ""
if ($script:checks -ne $ExpectedChecks) {
  Write-Host "FAIL: corrieron $($script:checks) aserciones y se esperaban $ExpectedChecks"
  $script:failures++
}
Write-Host "$($script:checks) aserciones, $($script:failures) fallidas"
exit ([int]($script:failures -gt 0))
