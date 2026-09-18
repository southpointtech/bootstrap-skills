# tests/grilling-y-punteros.tests.ps1 — runner sin Pester.
# Correr: pwsh -NoProfile -File tests/grilling-y-punteros.tests.ps1
#
# POR QUÉ EXISTE (issue v2 09): upstream mudó la mecánica del grilling a dos skills reales
# —`grilling` y `domain-modeling`— y dejó `grill-me` y `grill-with-docs` como PUNTEROS de una línea
# que las invocan por Skill tool. Adoptamos esa forma conservando nuestros nombres (ADR-0006): son los
# que el humano escribe y los que el `CLAUDE.md` del scaffold nombra como pasos del flujo.
#
# Las tres roturas que este archivo ataja:
#  1. Un puntero que apunta a una skill que el scaffold NO instala, o que la instala como
#     user-invoked (`disable-model-invocation: true`): la Skill tool no la puede invocar y el
#     `/grill-me` del proyecto no hace nada (el error que documentó ADR-0003).
#  2. Un puntero que vuelve a duplicar la mecánica: dos copias de la misma entrevista que divergen.
#  3. `/grill-with-docs` que deja de ACTUALIZAR la documentación del proyecto: los formatos de
#     `CONTEXT.md` y de ADR colgaban de `grill-with-docs/`; ahora cuelgan de `domain-modeling/`, y un
#     link roto a cualquiera de los dos deja la entrevista sin la mitad que escribe los docs.
#
# La red contra un mutante por AÑADIDO en los `.agents/skills/` es el golden por hash del lockfile
# (`tools/skills-lock.ps1 -Action Verify`, en tests/skills-lock.tests.ps1). Las `.claude/commands/`
# no las sella nadie: las sostiene ESTA suite, por la identidad entre copias y la igualdad
# comando == skill con los links reescritos.
$ErrorActionPreference = "Stop"
$repo = Split-Path $PSScriptRoot -Parent
$script:failures = 0
$script:checks   = 0

function Assert($cond, $msg) {
  $script:checks++
  if ($cond) { Write-Host "ok:   $msg" } else { Write-Host "FAIL: $msg"; $script:failures++ }
}

# Cantidad EXACTA de aserciones. Todas las ramas asertan aunque falte el archivo, así que el número no
# depende de que el árbol esté sano. Sin él, un mutante que BORRA asserts sale en verde.
$ExpectedChecks = 245

$scaffoldsEsperados = @("bootstrap-ai-project", "bootstrap-personal-project", "bootstrap-southpoint-project")
$scaffolds = @($scaffoldsEsperados | ForEach-Object { Join-Path $repo "skills/$_/assets/scaffold" })
$ausentes = @($scaffolds | Where-Object { -not (Test-Path -LiteralPath $_) })
Assert ($ausentes.Count -eq 0) "existen los tres scaffolds que nombra el CLAUDE.md (faltan: $($ausentes -join ', '))"
$raices = @($repo) + $scaffolds
function Etiqueta($raiz) {
  if ($raiz -eq $repo) { return "repo" }
  return (Split-Path (Split-Path (Split-Path $raiz -Parent) -Parent) -Leaf)
}

function Texto($path) {
  if (-not (Test-Path -LiteralPath $path)) { return $null }
  return ([IO.File]::ReadAllText($path) -replace "`r`n", "`n" -replace "`r", "`n")
}

# Parte un archivo en frontmatter (líneas entre el primer `---` y el que lo cierra) y cuerpo (lo de
# después, recortado). Sin cierre, `Fm` sale vacío y el cuerpo es $null: un archivo sin frontmatter
# no es una skill que se pueda invocar.
function Partir($texto) {
  $r = @{ Fm = @(); Cuerpo = $null }
  if ($null -eq $texto) { return $r }
  $l = @($texto -split "`n")
  if ($l.Count -eq 0 -or $l[0] -cne '---') { return $r }
  for ($k = 1; $k -lt $l.Count; $k++) {
    if ($l[$k] -ceq '---') {
      $r.Fm = @(if ($k -gt 1) { $l[1..($k - 1)] })
      $r.Cuerpo = (@(if ($k + 1 -lt $l.Count) { $l[($k + 1)..($l.Count - 1)] }) -join "`n").Trim()
      return $r
    }
  }
  return $r
}
function Description($partes) {
  $d = @($partes.Fm | Where-Object { $_ -cmatch '^description:' })
  if ($d.Count -ne 1) { return "" }
  return ($d[0] -creplace '^description:\s*', '').Trim()
}
function EsUserInvoked($partes) {
  return (@($partes.Fm | Where-Object { $_ -cmatch '^disable-model-invocation:\s*true\s*$' }).Count -gt 0)
}
function Archivos($dir) {
  if (-not (Test-Path -LiteralPath $dir)) { return @() }
  $a = [string[]]@(Get-ChildItem -LiteralPath $dir -Recurse -File -Force | ForEach-Object {
    [IO.Path]::GetRelativePath($dir, $_.FullName) -replace '\\', '/' })
  [Array]::Sort($a, [StringComparer]::Ordinal)
  return $a
}

# Qué archivos tiene cada skill. `agents/openai.yaml` de upstream NO entra: es metadata de la interfaz
# de otro agente y el scaffold apunta a Claude Code (el mismo criterio con que `tdd` y `to-prd` se
# adoptaron sin él).
$esperadoArchivos = @{
  "grilling"        = @("SKILL.md")
  "domain-modeling" = @("ADR-FORMAT.md", "CONTEXT-FORMAT.md", "SKILL.md")
  "grill-me"        = @("SKILL.md")
  "grill-with-docs" = @("SKILL.md")
}
$nombres = @("grilling", "domain-modeling", "grill-me", "grill-with-docs")

# Los punteros: el cuerpo ENTERO es la llamada, igual que upstream. Igualdad exacta y no `Contains`:
# un `Contains` deja pasar el puntero con la entrevista vieja pegada abajo, que es la duplicación que
# el slice vino a sacar.
$punteros = @{
  "grill-me"        = @{ cuerpo = 'Call the Skill tool with "grilling".'; destinos = @("grilling") }
  "grill-with-docs" = @{ cuerpo = 'Call the Skill tool twice, for "grilling" and "domain-modeling".'; destinos = @("grilling", "domain-modeling") }
}

$textos = @{}   # "$n|skill|$i" y "$n|cmd|$i" -> texto normalizado
for ($i = 0; $i -lt $raices.Count; $i++) {
  $raiz = $raices[$i]; $etq = Etiqueta $raiz
  foreach ($n in $nombres) {
    $dir = Join-Path $raiz ".agents/skills/$n"
    $hay = @(Archivos $dir)
    Assert (($hay -join ',') -ceq ($esperadoArchivos[$n] -join ',')) `
      "$etq : .agents/skills/$n tiene exactamente $($esperadoArchivos[$n] -join ', ') (tiene: $($hay -join ', '))"
    $ts = Texto (Join-Path $dir "SKILL.md")
    $tc = Texto (Join-Path $raiz ".claude/commands/$n.md")
    $textos["$n|skill|$i"] = $ts
    $textos["$n|cmd|$i"]   = $tc
    foreach ($par in @(@{ t = $ts; que = "el SKILL.md de $n" }, @{ t = $tc; que = "el comando $n.md" })) {
      $p = Partir $par.t
      Assert (@($p.Fm) -ccontains "name: $n") "$etq : $($par.que) declara ``name: $n`` en el frontmatter"
      $d = Description $p
      Assert ($d.Length -gt 0) "$etq : $($par.que) tiene ``description:`` con valor dentro del frontmatter"
    }
  }
}

# Las cuatro copias de cada archivo son el mismo archivo.
foreach ($n in $nombres) {
  foreach ($f in $esperadoArchivos[$n]) {
    $ref = Texto (Join-Path $repo ".agents/skills/$n/$f")
    for ($i = 1; $i -lt $raices.Count; $i++) {
      $otro = Texto (Join-Path $raices[$i] ".agents/skills/$n/$f")
      Assert ($null -ne $ref -and $ref -ceq $otro) "$n/$f : la copia de $(Etiqueta $raices[$i]) es idéntica a la del repo"
    }
  }
  for ($i = 1; $i -lt $raices.Count; $i++) {
    $a = $textos["$n|cmd|0"]; $b = $textos["$n|cmd|$i"]
    Assert ($null -ne $a -and $a -ceq $b) "$n.md : el comando de $(Etiqueta $raices[$i]) es idéntico al del repo"
  }
}

# El comando es la skill con los links reescritos a la raíz del proyecto: `./X` en la skill es
# `.agents/skills/<n>/X` en el comando, porque el comando no vive al lado de sus auxiliares. Todo lo
# demás —description incluida— es el mismo texto: si uno se actualiza y el otro no, `/grill-me`
# ejecuta la versión vieja aunque la skill esté al día.
foreach ($n in $nombres) {
  $s = $textos["$n|skill|0"]; $c = $textos["$n|cmd|0"]
  $cNorm = if ($null -ne $c) { $c.Replace("](.agents/skills/$n/", "](./") } else { $null }
  Assert ($null -ne $s -and $s -ceq $cNorm) "$n : el comando es el SKILL.md con los links reescritos a la raíz"
}

# Los punteros: cuerpo exacto, y cada destino instalado como skill Y como comando en la MISMA raíz,
# y model-invoked. La Skill tool de Claude Code resuelve por `.claude/commands/`; `.agents/skills/` es
# la copia que sella el lockfile.
for ($i = 0; $i -lt $raices.Count; $i++) {
  $raiz = $raices[$i]; $etq = Etiqueta $raiz
  foreach ($n in @("grill-me", "grill-with-docs")) {
    $p = Partir $textos["$n|skill|$i"]
    Assert ($p.Cuerpo -ceq $punteros[$n].cuerpo) "$etq : el cuerpo de $n es sólo el puntero ``$($punteros[$n].cuerpo)`` (es: ``$($p.Cuerpo)``)"
    $citados = @([regex]::Matches([string]$p.Cuerpo, '"([a-z][a-z0-9-]*)"') | ForEach-Object { $_.Groups[1].Value })
    Assert (($citados -join ',') -ceq ($punteros[$n].destinos -join ',')) "$etq : $n invoca, en orden, $($punteros[$n].destinos -join ' y ') (invoca: $($citados -join ', '))"
    foreach ($dst in $punteros[$n].destinos) {
      $pd = Partir (Texto (Join-Path $raiz ".claude/commands/$dst.md"))
      $ps = Partir (Texto (Join-Path $raiz ".agents/skills/$dst/SKILL.md"))
      Assert ($null -ne $pd.Cuerpo -and $null -ne $ps.Cuerpo) "$etq : el destino $dst de $n está instalado como comando y como skill"
      Assert ($null -ne $pd.Cuerpo -and -not (EsUserInvoked $pd)) "$etq : el destino $dst de $n es model-invoked (una user-invoked no se invoca por Skill tool)"
    }
    # Los triggers viven en la skill real, no en el puntero: dos descriptions compitiendo por la
    # misma frase reparten el disparo al azar.
    Assert (-not (Description $p).Contains("grilleame")) "$etq : la description de $n no repite los triggers de grilling"
  }
}

# La mecánica que se mudó, anclada donde vive ahora. Diagnóstico: el golden del lockfile dice
# «cambió»; esto dice QUÉ regla se perdió.
$anclas = @{
  "grilling" = @(
    "Map this as a **design tree**",
    "Work the tree in **rounds**. The **frontier** is every decision whose prerequisites are already settled",
    "Finding _facts_ is your job, never the user's.",
    "Do not act on it until the user confirms you have reached a shared understanding.")
  "domain-modeling" = @(
    "When a term is resolved, update ``CONTEXT.md`` right there.",
    "### Offer ADRs sparingly",
    "Create files lazily: only when you have something to write.")
}
foreach ($n in $anclas.Keys) {
  $t = [string]$textos["$n|skill|0"]
  foreach ($a in $anclas[$n]) { Assert ($t.Contains($a)) "$n : conserva ``$a``" }
}

# Los formatos de CONTEXT.md y de ADR son alcanzables desde donde vive la mecánica: los links del
# SKILL.md de domain-modeling son exactamente esos dos y resuelven a un archivo, desde la skill
# (relativos a su carpeta) y desde el comando (relativos a la raíz del proyecto).
$formatos = @("CONTEXT-FORMAT.md", "ADR-FORMAT.md")
for ($i = 0; $i -lt $raices.Count; $i++) {
  $raiz = $raices[$i]; $etq = Etiqueta $raiz
  foreach ($modo in @("skill", "cmd")) {
    $t = [string]$textos["domain-modeling|$modo|$i"]
    $links = @([regex]::Matches($t, '\]\(([^)\s]+)\)') | ForEach-Object { $_.Groups[1].Value })
    $base  = if ($modo -eq "skill") { Join-Path $raiz ".agents/skills/domain-modeling" } else { $raiz }
    $pref  = if ($modo -eq "skill") { "./" } else { ".agents/skills/domain-modeling/" }
    $esper = @($formatos | ForEach-Object { "$pref$_" })
    Assert (($links -join ',') -ceq ($esper -join ',')) "$etq : el $modo de domain-modeling linkea $($esper -join ' y ') (linkea: $($links -join ', '))"
    $rotos = @($links | Where-Object { -not (Test-Path -LiteralPath (Join-Path $base $_) -PathType Leaf) })
    Assert ($links.Count -gt 0 -and $rotos.Count -eq 0) "$etq : los links del $modo de domain-modeling resuelven (rotos: $($rotos -join ', '))"
  }
}

# Triggers en español donde el agente alcanza la skill sola.
$triggers = @{ "grilling" = "grilleame"; "domain-modeling" = "registrá esta decisión como ADR" }
foreach ($n in $triggers.Keys) {
  $d = Description (Partir $textos["$n|skill|0"])
  Assert ($d.Contains($triggers[$n])) "$n : la description conserva el trigger en español ``$($triggers[$n])``"
}
# "grilleame con la documentación" pedía entrevista Y documentación: era el trigger del grill-with-docs
# viejo. El puntero no lleva triggers, y "grilleame" solo lleva a grilling, que no escribe docs. Tiene
# que llevarlo la skill que trae la mitad de la documentación.
$dm = Description (Partir $textos["domain-modeling|skill|0"])
Assert ($dm.Contains('"grilleame con la documentación"')) "domain-modeling : la description lleva el trigger ``grilleame con la documentación`` que tenía el grill-with-docs viejo"

# El lockfile: las dos nuevas con su path upstream, y la base de los punteros AVANZADA — el cuerpo
# adoptado es el de upstream de hoy, así que una base vieja le atribuiría al drift propio todo lo que
# upstream cambió (docs/agents/recuperar-base-de-skills.md, "la base avanza").
$headPath = @{
  "grilling"        = "skills/productivity/grilling/SKILL.md"
  "domain-modeling" = "skills/engineering/domain-modeling/SKILL.md"
  "grill-me"        = "skills/productivity/grill-me/SKILL.md"
  "grill-with-docs" = "skills/engineering/grill-with-docs/SKILL.md"
}
$baseVieja = @{
  "grill-me"        = "bd04394c675ee54173a093c50eb74da01a2940fa"
  "grill-with-docs" = "5ea0aa913629bec683690f371839bd10e588413d"
}
foreach ($raiz in $raices) {
  $etq = Etiqueta $raiz
  $lock = Join-Path $raiz "skills-lock.json"
  $doc = if (Test-Path -LiteralPath $lock) { [IO.File]::ReadAllText($lock) | ConvertFrom-Json -AsHashtable } else { $null }
  foreach ($n in $nombres) {
    $e = if ($null -ne $doc -and $doc.skills.Contains($n)) { $doc.skills[$n] } else { $null }
    Assert ($null -ne $e -and $e.upstreamState -ceq "upstream-vivo" -and $e.upstreamHeadPath -ceq $headPath[$n]) `
      "$etq : el lockfile registra $n como upstream-vivo en $($headPath[$n]) (dice: $(if ($e) { "$($e.upstreamState) $($e.upstreamHeadPath)" } else { '<sin entrada>' }))"
    $blob = if ($null -ne $e -and $null -ne $e.base) { [string]$e.base.blob } else { "" }
    Assert ($blob -cmatch '^[0-9a-f]{40}$') "$etq : el lockfile registra la base de $n (blob: $blob)"
    $claves = [string[]]@(if ($null -ne $e -and $null -ne $e.files) { $e.files.Keys })
    [Array]::Sort($claves, [StringComparer]::Ordinal)
    Assert (($claves -join ',') -ceq ($esperadoArchivos[$n] -join ',')) "$etq : el lockfile sella $($esperadoArchivos[$n] -join ', ') de $n (sella: $($claves -join ', '))"
  }
  foreach ($n in $baseVieja.Keys) {
    $e = if ($null -ne $doc -and $doc.skills.Contains($n)) { $doc.skills[$n] } else { $null }
    $blob = if ($null -ne $e -and $null -ne $e.base) { [string]$e.base.blob } else { "" }
    Assert ($blob.Length -gt 0 -and $blob -cne $baseVieja[$n]) "$etq : la base de $n avanzó desde la del cuerpo viejo ($blob)"
  }
}

Write-Host ""
if ($script:checks -ne $ExpectedChecks) {
  Write-Host "FAIL: corrieron $($script:checks) aserciones y se esperaban $ExpectedChecks"
  $script:failures++
}
Write-Host "$($script:checks) aserciones, $($script:failures) fallidas"
exit ([int]($script:failures -gt 0))
