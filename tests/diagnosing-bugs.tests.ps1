# tests/diagnosing-bugs.tests.ps1 — runner sin Pester.
# Correr: pwsh -NoProfile -File tests/diagnosing-bugs.tests.ps1
#
# POR QUÉ EXISTE (issue v2 10): `diagnosing-bugs` entra al scaffold como MOTOR de diagnóstico, con el
# cuerpo de upstream (`mattpocock/skills`, `skills/engineering/diagnosing-bugs`) y tres cosas nuestras
# encima: la description en español con sus triggers, la sección que dice dónde encaja frente a
# `debug-source-first` (regla de primer paso para ausencias downstream, issue 16) y frente a
# `superpowers:systematic-debugging`, y la plantilla bash de loop con humano en el ciclo RETIRADA.
#
# La red contra una edición cualquiera del SKILL.md es el golden por hash del lockfile
# (`tools/skills-lock.ps1 -Action Verify`, dentro de `tests/skills-lock.tests.ps1`), que sella
# `.agents/skills/` y nada más. Este archivo aporta lo que el golden no ve: que el comando
# `.claude/commands/diagnosing-bugs.md` sea la misma skill, y QUÉ regla se perdió cuando algo cambia.
$ErrorActionPreference = "Stop"
$repo = Split-Path $PSScriptRoot -Parent
$script:failures = 0
$script:checks   = 0

function Assert($cond, $msg) {
  $script:checks++
  if ($cond) { Write-Host "ok:   $msg" } else { Write-Host "FAIL: $msg"; $script:failures++ }
}

# Cantidad EXACTA de aserciones: sin ella, un mutante que borra asserts sale en verde (0 de 0).
$ExpectedChecks = 74

$scaffoldsEsperados = @("bootstrap-ai-project", "bootstrap-personal-project", "bootstrap-southpoint-project")
$scaffolds = @($scaffoldsEsperados | ForEach-Object { Join-Path $repo "skills/$_/assets/scaffold" })
$ausentes = @($scaffolds | Where-Object { -not (Test-Path -LiteralPath $_) })
Assert ($ausentes.Count -eq 0) "existen los tres scaffolds (faltan: $($ausentes -join ', '))"
$raices = @($repo) + $scaffolds

function Texto($path) {
  if (-not (Test-Path -LiteralPath $path)) { return $null }
  return ([IO.File]::ReadAllText($path) -replace "`r`n", "`n" -replace "`r", "`n")
}

# El frontmatter es el bloque entre la PRIMERA línea `---` y la siguiente. Una description debajo del
# cierre no es una description: el comando no se invoca nunca.
function Frontmatter($t) {
  if ($null -eq $t) { return $null }
  $l = $t -split "`n"
  if ($l[0] -ne '---') { return $null }
  for ($i = 1; $i -lt $l.Count; $i++) { if ($l[$i] -eq '---') { return ($l[1..($i - 1)] -join "`n") } }
  return $null
}

# Posición de una línea EXACTA (anclada a principio y fin): una cita en prosa no la satisface.
function PosLinea($t, $linea) {
  if ($null -eq $t) { return -1 }
  $m = [regex]::Matches($t, '(?m)^' + [regex]::Escape($linea) + '$')
  if ($m.Count -ne 1) { return -1 }
  return $m[0].Index
}

# El orden del cuerpo de upstream: se verifica por POSICIÓN, no por presencia.
$secciones = @(
  '## Where this fits',
  '## Redact',
  '## Phase 1: Build a feedback loop',
  '## Phase 2: Reproduce + minimise',
  '## Phase 3: Hypothesise',
  '## Phase 4: Instrument',
  '## Phase 5: Fix + regression test',
  '## Phase 6: Cleanup')

$triggers = @('"diagnose"', '"debug this"', '"diagnosticá"', '"debuggeá esto"', '"se rompió"', '"tira una excepción"', '"anda lento"', 'debug-source-first')

$copias = @{}
foreach ($r in $raices) {
  $nombre = if ($r -eq $repo) { "raiz" } else { Split-Path (Split-Path $r -Parent) -Parent | Split-Path -Leaf }
  $skillDir = Join-Path $r ".agents/skills/diagnosing-bugs"
  $skill = Texto (Join-Path $skillDir "SKILL.md")
  $cmd   = Texto (Join-Path $r ".claude/commands/diagnosing-bugs.md")
  Assert ($null -ne $skill) "${nombre}: existe .agents/skills/diagnosing-bugs/SKILL.md"
  Assert ($null -ne $cmd) "${nombre}: existe .claude/commands/diagnosing-bugs.md"

  # El comando ES la skill: sin links relativos que reescribir, no hay motivo para que difieran.
  Assert ($null -ne $cmd -and $cmd -ceq $skill) "${nombre}: el comando es idéntico a la skill (fin de línea aparte)"

  $fm = Frontmatter $skill
  $desc = @(if ($null -ne $fm) { $fm -split "`n" | Where-Object { $_ -match '^description: \S' } })
  Assert (($null -ne $fm) -and ($fm -split "`n" -contains 'name: diagnosing-bugs')) "${nombre}: el frontmatter declara name: diagnosing-bugs"
  Assert ($desc.Count -eq 1) "${nombre}: hay UNA description con valor, dentro del frontmatter ($($desc.Count))"
  $faltan = @($triggers | Where-Object { -not ($desc.Count -eq 1 -and $desc[0].Contains($_)) })
  Assert ($faltan.Count -eq 0) "${nombre}: la description conserva sus triggers (faltan: $($faltan -join ' '))"
  # Un `: ` dentro de un escalar YAML sin comillas rompe el parseo del frontmatter entero.
  Assert ($desc.Count -eq 1 -and -not $desc[0].Substring('description: '.Length).Contains(': ')) "${nombre}: la description no tiene ': ' adentro (YAML plano)"
  Assert (-not (($fm -split "`n") -match '^disable-model-invocation:')) "${nombre}: es model-invoked (el agente la tiene que alcanzar solo)"

  $pos = @($secciones | ForEach-Object { PosLinea $skill $_ })
  $noEstan = @(for ($k = 0; $k -lt $secciones.Count; $k++) { if ($pos[$k] -lt 0) { $secciones[$k] } })
  Assert ($noEstan.Count -eq 0) "${nombre}: cada sección aparece exactamente una vez en su propia línea (mal: $($noEstan -join ' | '))"
  $enOrden = $noEstan.Count -eq 0
  for ($k = 1; $k -lt $pos.Count; $k++) { if ($pos[$k] -le $pos[$k - 1]) { $enOrden = $false } }
  Assert $enOrden "${nombre}: las secciones están en el orden de upstream, con 'Where this fits' antes de todo (posiciones: $($pos -join ', '))"

  # Dónde encaja: las dos relaciones, dentro de SU sección y no en cualquier parte del archivo.
  $ini = PosLinea $skill '## Where this fits'
  $fin = PosLinea $skill '## Redact'
  $encaja = if ($ini -ge 0 -and $fin -gt $ini) { $skill.Substring($ini, $fin - $ini) } else { "" }
  Assert ($encaja.Contains('`debug-source-first`') -and $encaja.Contains('failing hop')) "${nombre}: 'Where this fits' cede el primer paso de una ausencia downstream a debug-source-first y retoma en el salto que falla"
  Assert ($encaja.Contains('`superpowers:systematic-debugging`')) "${nombre}: 'Where this fits' nombra su relación con superpowers:systematic-debugging"
  Assert ($encaja.Contains('not merged')) "${nombre}: 'Where this fits' dice que las skills no se fusionan"

  # La plantilla HITL: retirada, y dicho en la skill. Ni el directorio ni una orden de usarla.
  Assert (-not (Test-Path -LiteralPath (Join-Path $skillDir "scripts"))) "${nombre}: no viaja scripts/ (la plantilla HITL se retiró)"
  Assert (-not (Test-Path -LiteralPath (Join-Path $skillDir "agents"))) "${nombre}: no viaja agents/openai.yaml (ninguna skill del scaffold lo lleva)"
  $menciones = @(if ($null -ne $skill) { $skill -split "`n" | Where-Object { $_.Contains('hitl-loop.template.sh') } })
  Assert ($menciones.Count -eq 1 -and $menciones[0].Contains('is not shipped')) "${nombre}: la plantilla HITL se nombra UNA vez, y es para decir que no viaja ($($menciones.Count))"

  $copias[$nombre] = $skill
}

# Las cuatro copias son el mismo documento. `mirror` compara sólo los scaffolds entre sí.
$ref = $copias["raiz"]
foreach ($k in @($copias.Keys | Where-Object { $_ -ne "raiz" } | Sort-Object)) {
  Assert ($null -ne $ref -and $copias[$k] -ceq $ref) "${k}: la skill es idéntica a la de la raíz"
}

# El lockfile la registra con su base y su path upstream. El commit base NO se fija acá: avanza con
# cada merge de tres vías, y eso lo sella la herramienta, no este test.
$lock = Texto (Join-Path $repo "skills-lock.json")
$e = if ($null -ne $lock) { ($lock | ConvertFrom-Json -AsHashtable).skills["diagnosing-bugs"] } else { $null }
Assert ($null -ne $e) "skills-lock.json tiene la entrada diagnosing-bugs"
Assert ($null -ne $e -and $e.upstreamState -eq "upstream-vivo") "diagnosing-bugs está sellada como upstream-vivo ($($e.upstreamState))"
Assert ($null -ne $e -and $e.upstreamHeadPath -eq "skills/engineering/diagnosing-bugs/SKILL.md") "diagnosing-bugs registra su path en el HEAD de upstream ($($e.upstreamHeadPath))"
Assert ($null -ne $e -and $null -ne $e.base -and $e.base.upstreamPath -eq "skills/engineering/diagnosing-bugs/SKILL.md" -and $e.base.commit -match '^[0-9a-f]{40}$') "diagnosing-bugs registra una base con commit y path upstream"
Assert ($null -ne $e -and @($e.files.Keys).Count -eq 1 -and $e.files.Contains("SKILL.md")) "diagnosing-bugs sella un solo archivo, el SKILL.md ($(if ($e) { @($e.files.Keys) -join ', ' }))"

Assert ($script:checks + 1 -eq $ExpectedChecks) "se corrieron exactamente $ExpectedChecks aserciones ($($script:checks + 1))"
if ($script:failures -eq 0) { Write-Host "TODOS LOS TESTS PASARON ($($script:checks))"; exit 0 }
else { Write-Host "$($script:failures) de $($script:checks) test(s) FALLARON"; exit 1 }
