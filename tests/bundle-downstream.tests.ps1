# tests/bundle-downstream.tests.ps1 — runner sin Pester.
# Correr: pwsh -NoProfile -File tests/bundle-downstream.tests.ps1
#
# POR QUÉ EXISTE (issue v2 16): `verify-downstream-arrival` y `debug-source-first` entran al scaffold
# desde las copias de usuario de quien mantiene el repo. No vienen de upstream, así que el lockfile
# las sella como `fork-propio`, igual que `review-loop` y `slice-review`. Al entrar se limpiaron los
# ejemplos que nombraban herramientas de un cliente puntual, y `debug-source-first` dejó de devolver
# a `superpowers:systematic-debugging` como su motor: el salto que falla lo diagnostica
# `diagnosing-bugs` (issue 10), cuya sección `## Where this fits` depende de que `debug-source-first`
# conserve su extensión para valores equivocados. Esa dependencia es lo que este archivo ancla.
#
# La red contra una edición cualquiera del SKILL.md es el golden por hash del lockfile
# (`tools/skills-lock.ps1 -Action Verify`, dentro de `tests/skills-lock.tests.ps1`), que sella
# `.agents/skills/` y nada más. Acá va lo que el golden no ve: que cada comando sea la misma skill, y
# QUÉ regla se perdió cuando algo cambia.
$ErrorActionPreference = "Stop"
$repo = Split-Path $PSScriptRoot -Parent
$script:failures = 0
$script:checks   = 0

function Assert($cond, $msg) {
  $script:checks++
  if ($cond) { Write-Host "ok:   $msg" } else { Write-Host "FAIL: $msg"; $script:failures++ }
}

# Cantidad EXACTA de aserciones: sin ella, un mutante que borra asserts sale en verde (0 de 0).
$ExpectedChecks = 132

$scaffoldsEsperados = @("bootstrap-ai-project", "bootstrap-personal-project", "bootstrap-southpoint-project")
$scaffolds = @($scaffoldsEsperados | ForEach-Object { Join-Path $repo "skills/$_/assets/scaffold" })
$ausentes = @($scaffolds | Where-Object { -not (Test-Path -LiteralPath $_) })
Assert ($ausentes.Count -eq 0) "existen los tres scaffolds (faltan: $($ausentes -join ', '))"
$raices = @($repo) + $scaffolds

function Texto($path) {
  if (-not (Test-Path -LiteralPath $path)) { return $null }
  return ([IO.File]::ReadAllText($path) -replace "`r`n", "`n" -replace "`r", "`n")
}

# El frontmatter es el bloque entre la PRIMERA línea `---` y la siguiente.
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

# Lo que ningún ejemplo puede nombrar: las herramientas y clientes que traían las copias de usuario, y
# los términos propios de la plataforma de ese cliente que se colaban en las tablas genéricas.
$prohibidos = '(?i)domo|zoho|southpoint|\bhss\b|forecasting|firebase|azure|outlook|jsonwh|rowsInserted|lastSuccess|DataFlow'

$skills = [ordered]@{
  'debug-source-first'        = @('"no llegó el mail"', '"no aparece en el dashboard"', '"el reporte salió vacío"', '"llegó mal"', 'diagnosing-bugs')
  'verify-downstream-arrival' = @('"ya llegó"', '"ya está deployado"', '"se mandó el mail"', '"quedó sincronizado"', 'debug-source-first')
}

# Las reglas que cada skill no puede perder, como líneas EXACTAS.
$extension = '**Extension — same algorithm for wrong values in a pipeline:** when the symptom is "the value at the sink is incorrect" (truncated, transformed wrong, partial) AND the data crosses multiple hops, the same bisect-forward applies — at each hop, check *"is the value correct here?"* instead of *"is it present here?"*. The first hop where the value diverges from the source is the failing transition.'
$paso5 = '**5. Root-cause THAT transition.** Now switch to `diagnosing-bugs` and run its Phase 1 against the failing transition alone. You''ve eliminated all the other hops.'
$roles = '**Two roles, not merged:** this skill is the **first-step rule** — it answers *where* the data is lost or goes wrong, by locating the failing transition. `diagnosing-bugs` is the **diagnosis engine** — it answers *why* that transition fails, with its six phases. Run this one first, then hand the transition over; don''t diagnose a hop you haven''t localized, and don''t bisect again once you have.'
$errorDirecto = '- Symptom is an **error message** with a stack trace → use `diagnosing-bugs` directly.'
$gateNo = '   - No → state the gap honestly, then find the failing hop with `debug-source-first`.'
$verifyRoles = '**RELATED:** `superpowers:verification-before-completion` (when installed) covers the local dev loop (tests, build, lint, regression). This skill covers integration boundaries: anywhere your write crosses into a system you don''t directly own the read path for. When the sink shows the effect did NOT arrive, this skill stops and `debug-source-first` takes over.'

$copias = @{}
foreach ($r in $raices) {
  $nombre = if ($r -eq $repo) { "raiz" } else { Split-Path (Split-Path $r -Parent) -Parent | Split-Path -Leaf }
  foreach ($s in $skills.Keys) {
    $skillDir = Join-Path $r ".agents/skills/$s"
    $skill = Texto (Join-Path $skillDir "SKILL.md")
    $cmd   = Texto (Join-Path $r ".claude/commands/$s.md")
    Assert ($null -ne $skill) "${nombre}: existe .agents/skills/$s/SKILL.md"
    Assert ($null -ne $cmd) "${nombre}: existe .claude/commands/$s.md"
    # El comando ES la skill: sin links relativos que reescribir, no hay motivo para que difieran.
    Assert ($null -ne $cmd -and $cmd -ceq $skill) "${nombre}/${s}: el comando es idéntico a la skill (fin de línea aparte)"
    $extra = @(if (Test-Path -LiteralPath $skillDir) { Get-ChildItem -LiteralPath $skillDir -Recurse -File -Force | Where-Object Name -ne 'SKILL.md' })
    Assert ($extra.Count -eq 0) "${nombre}/${s}: la skill es un solo archivo, el SKILL.md (sobran: $($extra.Name -join ', '))"

    $fm = Frontmatter $skill
    $desc = @(if ($null -ne $fm) { $fm -split "`n" | Where-Object { $_ -match '^description: \S' } })
    Assert (($null -ne $fm) -and ($fm -split "`n" -contains "name: $s")) "${nombre}/${s}: el frontmatter declara name: $s"
    Assert ($desc.Count -eq 1) "${nombre}/${s}: hay UNA description con valor, dentro del frontmatter ($($desc.Count))"
    $faltan = @($skills[$s] | Where-Object { -not ($desc.Count -eq 1 -and $desc[0].Contains($_)) })
    Assert ($faltan.Count -eq 0) "${nombre}/${s}: la description trae sus triggers en español (faltan: $($faltan -join ' '))"
    # Un `: ` o un ` #` dentro de un escalar YAML sin comillas rompe el parseo del frontmatter entero.
    $valor = if ($desc.Count -eq 1) { $desc[0].Substring('description: '.Length) } else { '' }
    Assert ($desc.Count -eq 1 -and -not $valor.Contains(': ') -and -not $valor.Contains(' #') -and $valor[0] -notin @('"', "'", '|', '>', '@', '`')) "${nombre}/${s}: la description es un escalar YAML plano válido"
    Assert (-not (($fm -split "`n") -match '^disable-model-invocation:')) "${nombre}/${s}: es model-invoked (el agente la tiene que alcanzar solo)"

    $hits = @(if ($null -ne $skill) { [regex]::Matches($skill, $prohibidos) | ForEach-Object Value })
    Assert ($hits.Count -eq 0) "${nombre}/${s}: ningún ejemplo nombra herramientas o clientes puntuales (encontrados: $($hits -join ', '))"

    $copias["$nombre/$s"] = $skill
  }

  $dsf = $copias["$nombre/debug-source-first"]
  Assert ((PosLinea $dsf $extension) -ge 0) "${nombre}: debug-source-first conserva su extensión para valores equivocados (diagnosing-bugs depende de ella)"
  Assert ((PosLinea $dsf $paso5) -ge 0) "${nombre}: el paso 5 de debug-source-first devuelve a diagnosing-bugs"
  Assert ((PosLinea $dsf $roles) -ge 0) "${nombre}: debug-source-first escribe los dos roles (primer paso y motor) sin fusionarlos"
  Assert ((PosLinea $dsf $errorDirecto) -ge 0) "${nombre}: un error con stack trace va directo a diagnosing-bugs"
  Assert ($null -ne $dsf -and -not $dsf.Contains('systematic-debugging')) "${nombre}: debug-source-first ya no nombra a systematic-debugging como motor"
  $posRoles = PosLinea $dsf $roles
  $posLey = PosLinea $dsf '## The Iron Law'
  Assert ($posRoles -ge 0 -and $posLey -gt $posRoles) "${nombre}: los roles se leen antes de la Iron Law"

  $vda = $copias["$nombre/verify-downstream-arrival"]
  Assert ((PosLinea $vda $verifyRoles) -ge 0) "${nombre}: verify-downstream-arrival le cede a debug-source-first cuando el efecto no llegó"
  Assert ((PosLinea $vda $gateNo) -ge 0) "${nombre}: el paso COMPARE de verify-downstream-arrival bisecta con debug-source-first"
  Assert ($null -ne $vda -and -not $vda.Contains('systematic-debugging')) "${nombre}: verify-downstream-arrival no manda a systematic-debugging"
  Assert ($null -ne $vda -and -not $vda.Contains('scaffold-e2e-suite')) "${nombre}: verify-downstream-arrival no nombra skills que el scaffold no instala"
}

# Las cuatro copias de cada skill son el mismo documento.
foreach ($s in $skills.Keys) {
  $ref = $copias["raiz/$s"]
  foreach ($n in $scaffoldsEsperados) {
    Assert ($null -ne $ref -and $copias["$n/$s"] -ceq $ref) "${n}/${s}: la skill es idéntica a la de la raíz"
  }
}

# El lockfile las sella como fork propio: no vienen de upstream, así que no tienen base ni fuente.
$lock = Texto (Join-Path $repo "skills-lock.json")
$entradas = if ($null -ne $lock) { ($lock | ConvertFrom-Json -AsHashtable).skills } else { @{} }
foreach ($s in $skills.Keys) {
  $e = $entradas[$s]
  Assert ($null -ne $e) "skills-lock.json tiene la entrada $s"
  Assert ($null -ne $e -and $e.upstreamState -eq "fork-propio" -and $null -eq $e.source -and $null -eq $e.base) "$s está sellada como fork-propio, sin fuente ni base ($(if ($e) { $e.upstreamState }))"
}

Assert ($script:checks + 1 -eq $ExpectedChecks) "se corrieron exactamente $ExpectedChecks aserciones ($($script:checks + 1))"
if ($script:failures -eq 0) { Write-Host "TODOS LOS TESTS PASARON ($($script:checks))"; exit 0 }
else { Write-Host "$($script:failures) de $($script:checks) test(s) FALLARON"; exit 1 }
