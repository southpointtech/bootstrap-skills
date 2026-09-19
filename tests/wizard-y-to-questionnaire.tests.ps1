# tests/wizard-y-to-questionnaire.tests.ps1 — runner sin Pester.
# Correr: pwsh -NoProfile -File tests/wizard-y-to-questionnaire.tests.ps1
#
# POR QUÉ EXISTE (issue v2 11): entran dos skills de upstream (`mattpocock/skills` @ 959a8e9) que
# trabajan sobre la interacción con el humano, con el cuerpo literal y dos cosas nuestras encima:
#
#   1. La invocación. `wizard` la alcanza el agente: description en español con triggers y sin
#      `disable-model-invocation`. `to-questionnaire` la escribe solo el humano: description de una
#      línea, human-facing, y `disable-model-invocation: true` (clasificación firmada en el issue 13).
#   2. `wizard/template.sh` VIAJA, y la skill dice por qué, frente a la plantilla HITL que el 10 retiró
#      de `diagnosing-bugs`: esa la corría el agente; un wizard lo corre el humano en su terminal.
#
# QUÉ NO CUBRE: la red contra una edición cualquiera de `.agents/skills/` es el golden por hash del
# lockfile (`tests/skills-lock.tests.ps1`). Acá va lo que el golden no ve: que los comandos sean la
# misma skill, que las cuatro copias coincidan, y QUÉ regla se perdió cuando algo cambia.
$ErrorActionPreference = "Stop"
$repo = Split-Path $PSScriptRoot -Parent
$script:failures = 0
$script:checks   = 0

function Assert($cond, $msg) {
  $script:checks++
  if ($cond) { Write-Host "ok:   $msg" } else { Write-Host "FAIL: $msg"; $script:failures++ }
}

# Cantidad EXACTA de aserciones: sin ella, un mutante que borra asserts sale en verde (0 de 0).
$ExpectedChecks = 127

$scaffoldsEsperados = @("bootstrap-ai-project", "bootstrap-personal-project", "bootstrap-southpoint-project")
$scaffolds = @($scaffoldsEsperados | ForEach-Object { Join-Path $repo "skills/$_/assets/scaffold" })
$ausentes = @($scaffolds | Where-Object { -not (Test-Path -LiteralPath $_) })
Assert ($ausentes.Count -eq 0) "existen los tres scaffolds (faltan: $($ausentes -join ', '))"
$raices = @($repo) + $scaffolds
function Etiqueta($raiz) { if ($raiz -eq $repo) { "repo" } else { Split-Path (Split-Path (Split-Path $raiz -Parent) -Parent) -Leaf } }

# Fines de línea normalizados: con core.autocrlf=true el mismo blob se materializa con bytes distintos.
function Texto($path) {
  if (-not (Test-Path -LiteralPath $path)) { return $null }
  return ([IO.File]::ReadAllText($path) -replace "`r`n", "`n" -replace "`r", "`n")
}
# Las líneas entre el PRIMER `---` y el que lo cierra. Una description debajo del cierre no cuenta.
function Frontmatter($t) {
  if ($null -eq $t) { return @() }
  $l = @($t -split "`n")
  if ($l[0] -cne '---') { return @() }
  for ($i = 1; $i -lt $l.Count; $i++) { if ($l[$i] -ceq '---') { return @(if ($i -gt 1) { $l[1..($i - 1)] }) } }
  return @()
}
# Posición de una línea EXACTA (anclada a principio y fin), que aparece UNA sola vez.
function PosLinea($t, $linea) {
  if ($null -eq $t) { return -1 }
  $m = [regex]::Matches($t, '(?m)^' + [regex]::Escape($linea) + '$')
  if ($m.Count -ne 1) { return -1 }
  return $m[0].Index
}

$descWizard = 'description: Genera un wizard interactivo en bash que guía a un humano, paso a paso, por lo que solo él puede hacer (abrir el dashboard de un tercero, copiar credenciales, cargar secrets de CI, correr una migración o un cutover de una sola vez), y guarda cada valor donde va (.env, GitHub secrets). Usala cuando el usuario diga "wizard", "armá un wizard", "guiame paso a paso", "tengo que configurar las credenciales", "cargá los secrets de CI", "provisioning de infraestructura" o "migración manual", o cuando un procedimiento tenga pasos que solo puede hacer el humano. No la uses para pasos que el agente puede hacer solo.'
$descQuest  = 'description: Turn a decision you can''t fully answer into a questionnaire for someone else to fill in.'

$skills = @(
  @{ nombre = "wizard"
     archivos = @("SKILL.md", "template.sh")
     description = $descWizard
     userInvoked = $false
     # El orden del cuerpo de upstream, por POSICIÓN.
     secciones = @('# Wizard', '## Process', '### 1. Scope the procedure', '### 2. Map each stage''s journey', '### 3. Author the wizard', '### 4. Verify and hand off')
     # El comando no vive en la carpeta de la skill: lo que apunta a template.sh se reescribe.
     comoComando = { param($t) $t.Replace('[template.sh](template.sh)', '[template.sh](.agents/skills/wizard/template.sh)').Replace('Copy `template.sh` to the target path', 'Copy `.agents/skills/wizard/template.sh` to the target path') } }
  @{ nombre = "to-questionnaire"
     archivos = @("SKILL.md")
     description = $descQuest
     userInvoked = $true
     secciones = @('1. **Who is it going to?** Ask, in one exchange, the recipient''s role, expertise, and relationship to the user. This fixes the questionnaire''s tone and how much context it must carry. Done when you know who the recipient is and what they know that the user doesn''t.',
                   '2. **What do you need back?** Ask, in one exchange, the specific decisions or facts the user can''t resolve alone and needs from this person. Done when you have a concrete list of what the user must walk away able to do or decide.',
                   '## Document structure', '<questionnaire-template>', '## Anything else?', '</questionnaire-template>')
     comoComando = { param($t) $t } }
)

foreach ($sk in $skills) {
  $n = $sk.nombre
  $esperados = @($sk.archivos | Sort-Object)
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
    $skill = $copias["SKILL.md"][-1]
    $cmd = Texto (Join-Path $raiz ".claude/commands/$n.md")
    $cmds += , $cmd
    Assert ($null -ne $cmd) "$etq : existe .claude/commands/$n.md"

    # Skill y comando comparten el frontmatter entero: name, description e invocación.
    $fm  = @(Frontmatter $skill)
    $fmC = @(Frontmatter $cmd)
    Assert ($fm.Count -gt 0 -and (($fm -join "`n") -ceq ($fmC -join "`n"))) "$etq : el comando de $n tiene el mismo frontmatter que la skill"
    Assert ($fm -ccontains "name: $n") "$etq : el frontmatter de $n declara ``name: $n``"
    $desc = @($fm | Where-Object { $_ -cmatch '^description:' })
    Assert ($desc.Count -eq 1 -and $desc[0] -ceq $sk.description) "$etq : $n tiene UNA description, la nuestra (tiene: $($desc -join ' | '))"
    # Escalar YAML plano: un `: ` o un ` #` adentro rompe el parseo del frontmatter entero.
    $valor = if ($desc.Count -eq 1) { $desc[0].Substring('description: '.Length) } else { ": " }
    Assert (-not $valor.Contains(': ') -and -not $valor.Contains(' #')) "$etq : la description de $n es un escalar YAML plano (sin ': ' ni ' #')"
    $dmi = @($fm | Where-Object { $_ -cmatch '^disable-model-invocation:' })
    if ($sk.userInvoked) {
      Assert ($dmi.Count -eq 1 -and $dmi[0] -ceq 'disable-model-invocation: true') "$etq : $n es user-invoked (disable-model-invocation: true)"
    } else {
      Assert ($dmi.Count -eq 0) "$etq : $n es model-invoked (el agente la tiene que alcanzar solo)"
    }

    # El cuerpo de upstream, en su orden.
    $pos = @($sk.secciones | ForEach-Object { PosLinea $skill $_ })
    $enOrden = -not ($pos -contains -1)
    for ($k = 1; $k -lt $pos.Count; $k++) { if ($pos[$k] -le $pos[$k - 1]) { $enOrden = $false } }
    Assert $enOrden "$etq : el cuerpo de $n tiene las anclas de upstream, una vez cada una y en orden (posiciones: $($pos -join ', '))"
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
  # El comando ejecuta el mismo cuerpo que la skill, con lo que apunta al auxiliar reescrito.
  $s0 = $copias["SKILL.md"][0]
  Assert ($null -ne $s0 -and $null -ne $cmds[0] -and $cmds[0] -ceq (& $sk.comoComando $s0)) "$n : el comando es la skill, con lo que apunta a sus auxiliares reescrito a .agents/skills/$n/"
}

# wizard: template.sh VIAJA, y la skill dice por qué.
$wz  = Texto (Join-Path $repo ".agents/skills/wizard/SKILL.md")
$tpl = Texto (Join-Path $repo ".agents/skills/wizard/template.sh")
$nota = '`template.sh` ships with this skill, unlike the human-in-the-loop template that `diagnosing-bugs` retires. That one needs the agent''s shell to hand its prompts to a human, which it cannot do. A wizard never asks that of the agent: the human runs it in their own terminal (on Windows, from Git Bash), and step 4 tells you not to run it yourself.'
$posNota = PosLinea $wz $nota
Assert ($posNota -gt (PosLinea $wz '# Wizard') -and $posNota -lt (PosLinea $wz '## Process')) "wizard dice, antes de ## Process, que template.sh viaja y por qué (frente a la plantilla HITL del 10)"
Assert ($null -ne $wz -and $wz.Contains("- Don't run it end-to-end yourself: it opens browsers and blocks on human input.")) "wizard conserva la orden de upstream de no correr el wizard de punta a punta"
Assert ($null -ne $tpl -and ($tpl -split "`n")[0] -ceq '#!/usr/bin/env bash') "template.sh arranca con el shebang de bash"
Assert ($null -ne $tpl -and $tpl.Contains("`n# STAGES: author this section. One stage() per step the human takes.`n")) "template.sh conserva el marcador STAGES que separa la librería de las etapas"
# Una lista FIJA de helpers: los que nombra el paso 3 de la skill, más `finish` y `banner`, que usa la
# sección de etapas de ejemplo de la plantilla. Cada uno tiene que estar definido como función.
$helpers = @('stage', 'say', 'step', 'open_url', 'ask', 'ask_secret', 'write_env', 'set_secret', 'set_var', 'pause', 'confirm', 'finish', 'banner')
$sinDefinir = @($helpers | Where-Object { $null -eq $tpl -or -not ([regex]::IsMatch($tpl, '(?m)^' + [regex]::Escape($_) + '\(\)\s*\{')) })
Assert ($sinDefinir.Count -eq 0) "template.sh define como función los $($helpers.Count) helpers de la lista fija (faltan: $($sinDefinir -join ', '))"

# El comando de wizard no vive en la carpeta de la skill: lo que apunta a template.sh tiene que resolver
# desde la raíz del proyecto. La igualdad comando == comoComando(skill) no alcanza sola: si la skill
# deja de contener la cadena fuente, los .Replace() no hacen nada y comando == skill pasa igual.
$fuentes = @('[template.sh](template.sh)', 'Copy `template.sh` to the target path')
foreach ($raiz in $raices) {
  $etq = Etiqueta $raiz
  $s = Texto (Join-Path $raiz ".agents/skills/wizard/SKILL.md")
  $c = Texto (Join-Path $raiz ".claude/commands/wizard.md")
  foreach ($f in $fuentes) {
    $veces = if ($null -ne $s) { [regex]::Matches($s, [regex]::Escape($f)).Count } else { 0 }
    Assert ($veces -eq 1) "$etq : la skill wizard contiene ``$f`` exactamente una vez ($veces)"
  }
  $apunta = if ($null -ne $c) { [regex]::Matches($c, [regex]::Escape('.agents/skills/wizard/template.sh')).Count } else { 0 }
  Assert ($apunta -eq 2) "$etq : el comando wizard nombra .agents/skills/wizard/template.sh exactamente dos veces ($apunta)"
  $links = @(if ($null -ne $c) { [regex]::Matches($c, '\]\(([^)\s]+)\)') | ForEach-Object { $_.Groups[1].Value } })
  $rotos = @($links | Where-Object { -not (Test-Path -LiteralPath (Join-Path $raiz $_) -PathType Leaf) })
  Assert ($links.Count -gt 0 -and $rotos.Count -eq 0) "$etq : todo link del comando wizard resuelve desde la raíz del proyecto (links: $($links.Count), rotos: $($rotos -join ', '))"
}

# El lockfile registra las dos con su base y su path upstream, en las cuatro copias. El commit base NO
# se fija acá: avanza con cada merge de tres vías, y eso lo sella la herramienta, no este test.
$headPaths = @{ "wizard" = "skills/engineering/wizard/SKILL.md"; "to-questionnaire" = "skills/productivity/to-questionnaire/SKILL.md" }
$selladas  = @{ "wizard" = "SKILL.md|template.sh"; "to-questionnaire" = "SKILL.md" }
foreach ($raiz in $raices) {
  $etq = Etiqueta $raiz
  $lock = Texto (Join-Path $raiz "skills-lock.json")
  $doc = if ($null -ne $lock) { $lock | ConvertFrom-Json -AsHashtable } else { $null }
  foreach ($n in @("wizard", "to-questionnaire")) {
    $e = if ($null -ne $doc -and $doc.skills.Contains($n)) { $doc.skills[$n] } else { $null }
    Assert ($null -ne $e -and $e.upstreamState -eq "upstream-vivo" -and $e.upstreamHeadPath -eq $headPaths[$n]) "$etq : el lockfile sella $n como upstream-vivo en $($headPaths[$n]) ($(if ($e) { "$($e.upstreamState) $($e.upstreamHeadPath)" }))"
    Assert ($null -ne $e -and $null -ne $e.base -and $e.base.upstreamPath -eq $headPaths[$n] -and $e.base.commit -match '^[0-9a-f]{40}$') "$etq : $n registra una base con commit y path upstream"
    $keys = if ($null -ne $e) { (@($e.files.Keys) | Sort-Object) -join '|' } else { "" }
    Assert ($keys -ceq $selladas[$n]) "$etq : el lockfile sella de $n exactamente $($selladas[$n]) (sella: $keys)"
  }
}

Write-Host ""
if ($script:checks -ne $ExpectedChecks) {
  Write-Host "FAIL: corrieron $($script:checks) aserciones y se esperaban $ExpectedChecks"
  $script:failures++
}
Write-Host "$($script:checks) aserciones, $($script:failures) fallidas"
exit ([int]($script:failures -gt 0))
