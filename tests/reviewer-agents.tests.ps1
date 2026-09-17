# tests/reviewer-agents.tests.ps1 — runner sin Pester. Correr: pwsh -NoProfile -File tests/reviewer-agents.tests.ps1
#
# Cada foco de solo lectura del fan-out de /slice-review es un AGENT DECLARADO en .claude/agents/, con
# las herramientas que mutan archivos prohibidas por declaracion de la plataforma en vez de por prosa.
# La prosa sola no alcanzo: medido en este repo, 84 de 345 reviewers usaron Write/Edit igual.
#
# Por que la tabla es de IGUALDAD EXACTA y no de anclas: en este repo esta medido que un `Contains`
# sobre prosa no expresa semantica (la negacion satisface el ancla), que los anclajes semanticos son
# ciegos a los mutantes por AÑADIDO, y que prohibir una palabra que ninguna rama escribe no prueba
# nada. Un frontmatter es datos, no prosa: comparar el valor entero contra el esperado mata las tres
# familias de una, y editar una description a proposito exige tocar esta tabla en el mismo commit.
#
# Lo que se verifica es el HECHO, no la etiqueta: que herramientas declara cada agent, a que NOMBRE
# rutea cada foco de la skill, y que las 4 copias del arbol de agents son el mismo documento.
$ErrorActionPreference = "Stop"
$repo = Split-Path $PSScriptRoot -Parent
$script:failures = 0
function Assert($cond, $msg) {
  if ($cond) { Write-Host "ok:   $msg" } else { Write-Host "FAIL: $msg"; $script:failures++ }
}

# Las herramientas que mutan archivos. `Bash` NO esta en esta lista a proposito: un shell puede
# escribir igual (`echo x > f`), asi que la declaracion no lo cubre y la prohibicion en prosa del
# Step 3 sigue siendo la red para lo que un comando puede hacer. Por eso solo los tres focos que
# necesitan una lectura de git lo llevan.
$mutantes = @('Write', 'Edit', 'MultiEdit', 'NotebookEdit')

# name -> lo que su frontmatter DEBE declarar, palabra por palabra.
$esperados = [ordered]@{
  'slice-review-bugs'      = @{
    model = 'opus'
    tools = 'Read, Grep, Glob'
    desc  = "Bugs focus of /slice-review's fan-out. Dispatched by name; not invoked by hand."
  }
  'slice-review-rules'     = @{
    model = 'sonnet'
    tools = 'Read, Grep, Glob'
    desc  = "Project-rules focus of /slice-review's fan-out. Dispatched by name; not invoked by hand."
  }
  'slice-review-history'   = @{
    model = 'sonnet'
    tools = 'Read, Grep, Glob, Bash'
    desc  = "Historical-context focus of /slice-review's fan-out. Dispatched by name; not invoked by hand."
  }
  'slice-review-contracts' = @{
    model = 'opus'
    tools = 'Read, Grep, Glob'
    desc  = "Contracts-and-callers focus of /slice-review's fan-out. Dispatched by name; not invoked by hand."
  }
  'slice-review-tests'     = @{
    model = 'opus'
    tools = 'Read, Grep, Glob'
    desc  = "Tests focus of /slice-review's fan-out. Dispatched by name; not invoked by hand."
  }
  'slice-review-coherence' = @{
    model = 'sonnet'
    tools = 'Read, Grep, Glob, Bash'
    desc  = "Coherence focus of /slice-review's close. Dispatched by name; not invoked by hand."
  }
  'slice-review-scorer'    = @{
    model = 'opus'
    tools = 'Read, Grep, Glob, Bash'
    desc  = "Confidence-pass scorer of /slice-review. Dispatched by name; not invoked by hand."
  }
}
$nombres = @($esperados.Keys)
# En que seccion de /slice-review tiene que aparecer el nombre de cada agent. El ruteo es el hecho:
# que el nombre este en el archivo no dice nada si esta en la seccion equivocada.
$seccionDeFoco = @{
  'slice-review-bugs'      = 'Step 4 — Fan out parallel reviewers'
  'slice-review-rules'     = 'Step 4 — Fan out parallel reviewers'
  'slice-review-history'   = 'Step 4 — Fan out parallel reviewers'
  'slice-review-contracts' = 'Step 4 — Fan out parallel reviewers'
  'slice-review-tests'     = 'Step 4 — Fan out parallel reviewers'
  'slice-review-scorer'    = 'Step 5 — Confidence pass (filter false positives)'
  'slice-review-coherence' = 'Coherence pass'
}

$roots = @(@{ label = 'repo'; dir = $repo })
foreach ($s in @('bootstrap-ai-project', 'bootstrap-personal-project', 'bootstrap-southpoint-project')) {
  $roots += @{ label = $s; dir = (Join-Path $repo "skills\$s\assets\scaffold") }
}

# --- Frontmatter: se lee el bloque entre los dos `---` y se parte por la PRIMERA `: ` de cada linea.
# Devuelve $null si no hay bloque (y todos los asserts de abajo muerden en vez de comparar $null con
# $null, que es como este repo ya se autoaprobo una vez).
function Get-Frontmatter([string]$path) {
  $t = [IO.File]::ReadAllText($path) -replace "`r`n", "`n" -replace "`r", "`n"
  $lineas = @($t -split "`n")
  if ($lineas.Count -lt 2 -or $lineas[0] -ne '---') { return $null }
  $fin = -1
  for ($i = 1; $i -lt $lineas.Count; $i++) { if ($lineas[$i] -eq '---') { $fin = $i; break } }
  if ($fin -lt 1) { return $null }
  $fm = @{}
  for ($i = 1; $i -lt $fin; $i++) {
    $m = [regex]::Match($lineas[$i], '^([A-Za-z][A-Za-z0-9_]*):\s*(.*)$')
    if ($m.Success) { $fm[$m.Groups[1].Value] = $m.Groups[2].Value }
  }
  # El cuerpo entra para poder exigir que el agent NO quede vacio: un frontmatter correcto sobre un
  # archivo sin instrucciones declara un reviewer que no sabe que revisar.
  $fm['__body'] = if ($fin + 1 -lt $lineas.Count) { (@($lineas[($fin + 1)..($lineas.Count - 1)]) -join "`n") } else { "" }
  $fm['__fm']   = (@($lineas[1..($fin - 1)]) -join "`n")
  return $fm
}
function Split-Lista([string]$v) {
  if ($null -eq $v) { return @() }
  return @($v -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

# Hash del contenido con fines de linea normalizados: con core.autocrlf=true el mismo contenido git
# se materializa con bytes distintos segun como llego cada archivo (misma razon que mirror.tests.ps1).
function NormHash($path) {
  $text = [IO.File]::ReadAllText($path)
  $norm = $text -replace "`r`n", "`n" -replace "`r", "`n"
  $sha  = [Security.Cryptography.SHA256]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes($norm))
  [BitConverter]::ToString($sha).Replace("-", "")
}

# --- 1. Los agents declarados, en las 4 raices ---------------------------------------------------
$hashesPorAgent = @{}
foreach ($r in $roots) {
  $dir = Join-Path $r.dir ".claude\agents"
  if (-not (Test-Path -LiteralPath $dir -PathType Container)) {
    Assert $false "$($r.label): existe .claude/agents/"
    continue
  }
  Assert $true "$($r.label): existe .claude/agents/"

  # El SET exacto: ni falta uno ni sobra un agent que nadie rutea (foco huerfano por el otro lado).
  $hay = @(Get-ChildItem -LiteralPath $dir -File -Force | ForEach-Object { $_.Name } | Sort-Object)
  $esp = @($nombres | ForEach-Object { "$_.md" } | Sort-Object)
  $dif = @(Compare-Object $esp $hay | ForEach-Object { "$($_.SideIndicator) $($_.InputObject)" })
  Assert ($dif.Count -eq 0) "$($r.label): .claude/agents/ tiene exactamente los $($nombres.Count) agents declarados (diff: $($dif -join ', '))"

  foreach ($n in $nombres) {
    $f = Join-Path $dir "$n.md"
    if (-not (Test-Path -LiteralPath $f)) { Assert $false "$($r.label): existe .claude/agents/$n.md"; continue }
    $fm = Get-Frontmatter $f
    if ($null -eq $fm) { Assert $false "$($r.label)/${n}: el archivo abre y cierra un frontmatter YAML"; continue }
    $e = $esperados[$n]

    # El ruteo por nombre usa el campo `name`, no el nombre de archivo: si divergen, el dispatch falla.
    Assert ($fm['name'] -ceq $n) "$($r.label)/${n}: el campo name es '$n' (dice '$($fm['name'])')"

    # La description es UNA linea y la que la tabla declara. El anclado a principio de linea sobre el
    # frontmatter crudo es lo que prueba lo de "una linea": un bloque `description: |` de tres lineas
    # no matchea, y la igualdad exacta mata al mutante que le agrega una clausula al final.
    Assert ($fm['__fm'] -cmatch "(?m)^description: $([regex]::Escape($e.desc))$") `
      "$($r.label)/${n}: la description es una sola linea y dice exactamente lo declarado (dice: '$($fm['description'])')"

    # La PROHIBICION, por declaracion. Se asertan las dos direcciones sobre las listas parseadas —no
    # sobre el string— para que el hecho quede expresado aunque la tabla cambie: ninguna herramienta
    # que muta archivos en el allowlist, y las cuatro en el denylist.
    $tools = Split-Lista $fm['tools']
    $deny  = Split-Lista $fm['disallowedTools']
    $colados = @($mutantes | Where-Object { $tools -contains $_ })
    $faltan  = @($mutantes | Where-Object { -not ($deny -contains $_) })
    Assert ($tools.Count -gt 0) "$($r.label)/${n}: declara un allowlist de herramientas (sin tools hereda todas)"
    Assert ($colados.Count -eq 0) "$($r.label)/${n}: ninguna herramienta que muta archivos en el allowlist (coladas: $($colados -join ', '))"
    Assert ($faltan.Count -eq 0) "$($r.label)/${n}: el denylist nombra las $($mutantes.Count) herramientas que mutan archivos (faltan: $($faltan -join ', '))"
    # Y la tabla, palabra por palabra: el allowlist tambien acota que NO puede hacer (sin `Agent` no
    # puede delegar en un subagente sin la prohibicion, sin `Skill` no puede invocar una skill que escriba).
    Assert ($fm['tools'] -ceq $e.tools) "$($r.label)/${n}: tools == '$($e.tools)' (dice '$($fm['tools'])')"

    # El modelo, FIJADO por declaracion. Es lo unico del release donde el modelo se fija.
    Assert ($fm['model'] -ceq $e.model) "$($r.label)/${n}: model == '$($e.model)' (dice '$($fm['model'])')"

    # Un agent sin cuerpo es un reviewer sin foco: el frontmatter pasaria igual.
    Assert ($fm['__body'].Trim().Length -gt 200) "$($r.label)/${n}: el cuerpo lleva las instrucciones del foco ($($fm['__body'].Trim().Length) chars)"
    # La prohibicion tambien se escribe en el cuerpo, que es lo unico que el agent lee cuando corre.
    Assert ($fm['__body'] -match '(?i)reviewer, not an editor') "$($r.label)/${n}: el cuerpo repite la prohibicion de escritura"

    if (-not $hashesPorAgent.ContainsKey($n)) { $hashesPorAgent[$n] = @{} }
    $hashesPorAgent[$n][$r.label] = NormHash $f
  }
}

# Las 4 copias son el MISMO documento (mirror.tests.ps1 solo compara los 3 scaffolds entre si; la
# copia del repo, que es la que corre el loop de este repo, no figura ahi).
foreach ($n in $nombres) {
  $h = $hashesPorAgent[$n]
  if ($null -eq $h -or $h.Count -ne $roots.Count) {
    Assert $false "$($n): esta en las $($roots.Count) raices (esta en $(if ($null -eq $h) { 0 } else { $h.Count }))"
    continue
  }
  $distintos = @($h.Values | Sort-Object -Unique)
  Assert ($distintos.Count -eq 1) "$($n): las $($roots.Count) copias son identicas en contenido"
}

# --- 2. El ruteo: /slice-review invoca a cada agent por nombre -----------------------------------
# Las 8 copias del documento (command para el humano + SKILL.md para autodescubrimiento, en las 4
# raices) comparten el cuerpo, asi que las mismas aserciones corren sobre las 8.
function Section([string]$txt, [string]$header) {
  $m = [regex]::Match($txt, "(?im)^##\s+$([regex]::Escape($header)).*?(?=^##\s|\z)", 'Singleline')
  if ($m.Success) { return $m.Value } else { return "" }
}
$docs = @()
foreach ($r in $roots) {
  $docs += @{ label = $r.label; file = (Join-Path $r.dir ".claude\commands\slice-review.md") }
  $docs += @{ label = $r.label; file = (Join-Path $r.dir ".agents\skills\slice-review\SKILL.md") }
}
Assert ($docs.Count -eq 8) "se arman las 8 copias de /slice-review (4 raices x command+SKILL) ($($docs.Count))"

foreach ($d in $docs) {
  $rel = $d.file.Substring($repo.Length).TrimStart('\')
  if (-not (Test-Path -LiteralPath $d.file)) { Assert $false "existe $rel"; continue }
  $txt = [IO.File]::ReadAllText($d.file) -replace "`r`n", "`n" -replace "`r", "`n"

  foreach ($n in $nombres) {
    # Exactamente UNA linea lo nombra: dos focos ruteados al mismo agent, o un foco ruteado dos veces,
    # son los dos duplicados que el AC prohibe, y contar presencia no los ve.
    $lineas = @($txt -split "`n" | Where-Object { $_.Contains($n) })
    Assert ($lineas.Count -eq 1) "${rel}: ${n} se invoca en exactamente una linea ($($lineas.Count))"
    # Y en la seccion que le toca: nombrarlo en cualquier lado no es ruteo.
    $sec = Section $txt $seccionDeFoco[$n]
    Assert ($sec.Contains($n)) "${rel}: ${n} se invoca dentro de '$($seccionDeFoco[$n])'"
  }
  # Sin huerfanos por el otro lado: cada `slice-review-<algo>` que el documento nombra es un agent
  # declarado. Un rename a medias deja al fan-out despachando un subagent_type que no existe.
  $citados = @([regex]::Matches($txt, 'slice-review-[a-z-]+') | ForEach-Object { $_.Value } | Sort-Object -Unique)
  $fantasmas = @($citados | Where-Object { $_ -notin $nombres })
  Assert ($fantasmas.Count -eq 0) "${rel}: no nombra agents que no existen (fantasmas: $($fantasmas -join ', '))"

  # El foco de mutacion NO es uno de estos agents: es el unico que DEBE escribir (aplica mutantes en
  # su worktree aislado), asi que sigue siendo un subagente general-purpose.
  $mut = Section $txt 'Mutation focus'
  Assert ($mut -match '(?i)general-purpose') "${rel}: el foco de mutacion sigue despachandose como general-purpose"
  $enMut = @($nombres | Where-Object { $mut.Contains($_) })
  Assert ($enMut.Count -eq 0) "${rel}: el foco de mutacion no rutea a ningun agent de solo lectura ($($enMut -join ', '))"

  # El modelo lo fija la DECLARACION: un model pasado en el dispatch la pisa (tiene precedencia sobre
  # el frontmatter), asi que la orden vieja de pasarlo explicitamente desarmaria justo lo que este
  # slice fija. Es el unico ancla de prosa de este archivo — el hecho que expresa no tiene forma
  # estructural — y por eso va en las dos direcciones: la orden nueva presente y la vieja ausente.
  $s4 = Section $txt 'Step 4 — Fan out parallel reviewers'
  Assert ($s4 -match '(?is)do not pass a model\s+when you dispatch') `
    "${rel}: Step 4 ordena no pasar el modelo en el dispatch de un foco que es agent"
  # El `\s+` no es cosmetico: la oracion vieja esta CORTADA por el wrap del markdown ("Pass the
  # model\nexplicitly when you dispatch"), asi que la version sin `\s+` pasaba en verde hoy, contra el
  # texto que todavia esta. Prohibir algo que ninguna rama escribe no prueba nada.
  Assert ($s4 -notmatch '(?i)Pass the model\s+explicitly when you dispatch each subagent') `
    "${rel}: no queda la orden vieja de pasar el modelo en cada dispatch"
}

if ($script:failures -eq 0) { Write-Host "TODOS LOS TESTS PASARON"; exit 0 }
else { Write-Host "$($script:failures) test(s) FALLARON"; exit 1 }
