# tests/invocation-policy.tests.ps1 — runner sin Pester.
# Correr: pwsh -NoProfile -File tests/invocation-policy.tests.ps1
#
# POR QUÉ EXISTE (issue v2 13): el listado de comandos se carga en CADA request de CADA proyecto
# bootstrapeado. La regla es de clasificación, no de caracteres: es **model-invoked** lo que el
# agente, un hook u otra skill tienen que alcanzar solos, y **user-invoked** (`disable-model-
# invocation: true`) lo que sólo escribe un humano. Una user-invoked no carga su description en el
# listado; una model-invoked la carga entera, triggers en español incluidos, porque esos triggers
# son la razón por la que el agente la alcanza.
#
# MEDIDO el 2026-09-19 sobre `skills/bootstrap-personal-project/assets/scaffold` (sumando el valor de
# la línea `description:` de cada comando que NO lleva el flag, sin el prefijo `description: `):
#   antes de este slice  : 18 comandos model-invoked, 6.667 caracteres
#   después de este slice: 12 comandos model-invoked, 5.709 caracteres  (−14,4 %)
# La MISMA cuenta sobre el árbol del 2026-08-28 (`00c2160`) da 9 comandos y 2.062 caracteres — no 11
# y 2.996: `setup-matt-pocock-skills` y `zoom-out` ya llevaban el flag, así que no cargaban. Medido
# así, el release queda en +176,9 %. (El +12 % que estimaba el issue es de otro método y de antes
# de tener las nueve skills nuevas: no se compara con éste.) El 2.996 de `docs/superpowers/notes/2026-08-28-research-dieta-de-
# contexto.md` sale de otro método, que esa nota no declara: el frontmatter entero menos la línea
# `name:`, o sea sumándole el `argument-hint` y hasta la propia línea `disable-model-invocation:
# true` — la línea que impide que esa description cargue. No lo compares contra los números de acá.
#
# LAS DOS ROTURAS QUE ATAJA:
#   1. Clasificar mal una que el agente necesita alcanzar: `review-loop` la ordena el hook
#      `review-loop-trigger` y ella invoca a `slice-review` por Skill tool. Con el flag puesto, la
#      Skill tool no las puede invocar y el loop no corre — el error que documentó ADR-0003. Las dos
#      tienen su assert propio, por nombre.
#   2. Un comando que entra al árbol sin decidir su invocación. Por eso la lista es DECLARADA y se
#      compara en las dos direcciones: un comando presente y no listado falla, y uno listado y
#      ausente también.
#
# QUÉ NO CUBRE: el cuerpo de cada skill y la identidad entre las cuatro copias los sostienen las
# suites de cada slice (`grilling-y-punteros`, `merge-triage-handoff-setup`, `nombres-propios-de-
# skills`, `wizard-y-to-questionnaire`) y el golden por hash del lockfile. Acá va SÓLO la política de
# invocación y la forma de la description que se sigue de ella.
#
# LA FORMA DE LA DESCRIPTION SE VERIFICA SÓLO EN `.claude/commands/`, a propósito: es la copia que
# Claude Code carga en cada request, o sea la que se paga. A `.agents/skills/` Claude Code no la
# DESCUBRE como skills —su `description:` nunca entra a ese listado, aunque sí lea esos archivos
# cuando un comando linkea a ellos— y esa copia viaja a otros agentes que no necesariamente honran
# el flag: si se le sacaran los triggers, ahí quedaría inalcanzable. Decidido por el dueño del repo
# el 2026-09-19. El FLAG sí se compara en las dos copias (más abajo): lo que no puede divergir es la
# CLASIFICACIÓN.
# Medido el 2026-09-19 sobre las 9 user-invoked: de las nueve copias de `.agents/skills/`, cinco
# conservan la forma de agente (`handoff`, `setup-matt-pocock-skills`, `to-issues`, `to-prd`,
# `triage`), `zoom-out` conserva su disparo sin marcas, y `grill-me`, `grill-with-docs` y
# `to-questionnaire` no la tienen: las dos primeras son punteros de dos líneas y la tercera
# simplemente nunca la tuvo. O sea que la exención cubre un surtido, no nueve copias de lo mismo.
# Si algún día se recortan esas descriptions: `merge-triage-handoff-setup` pinea EXACTAS las de
# `triage`, `handoff` y `setup-matt-pocock-skills`; las de `to-prd`, `to-issues` y `zoom-out` no las
# pinea nadie palabra por palabra, pero el hash de `skills-lock.json` las sella, así que recortarlas
# obliga a re-sellar el lockfile.
$ErrorActionPreference = "Stop"
$repo = Split-Path $PSScriptRoot -Parent
$script:failures = 0
$script:checks   = 0

function Assert($cond, $msg) {
  $script:checks++
  if ($cond) { Write-Host "ok:   $msg" } else { Write-Host "FAIL: $msg"; $script:failures++ }
}

# Cantidad EXACTA de aserciones: sin ella, un mutante que borra asserts sale en verde (0 de 0).
$ExpectedChecks = 324   # 20 fijas + 4 raíces x (2 direcciones + 21 comandos x 3 + 9 user-invoked + 2 del ADR-0003)

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
# Las líneas entre el PRIMER `---` y el que lo cierra. Un flag debajo del cierre no lo lee nadie.
function Frontmatter($t) {
  if ($null -eq $t) { return @() }
  $l = @($t -split "`n")
  if ($l.Count -eq 0 -or $l[0] -cne '---') { return @() }
  for ($i = 1; $i -lt $l.Count; $i++) { if ($l[$i] -ceq '---') { return @(if ($i -gt 1) { $l[1..($i - 1)] }) } }
  return @()
}
# El valor de la description, o "" si no hay exactamente una dentro del frontmatter.
function Description($fm) {
  $d = @($fm | Where-Object { $_ -cmatch '^description:' })
  if ($d.Count -ne 1) { return "" }
  return ($d[0] -creplace '^description:\s*', '').Trim()
}
# La línea entera y exacta: `disable-model-invocation: false` o comentada NO desactiva nada.
function EsUserInvoked($fm) {
  return (@($fm | Where-Object { $_ -cmatch '^disable-model-invocation:\s*true\s*$' }).Count -gt 0)
}

# La fórmula de disparo: lo que le dice al agente CUÁNDO alcanzar la skill solo. Sin ella, una
# model-invoked paga su description en cada request y no se dispara nunca.
$disparadores = @('Use when', 'Use as', 'Usala cuando', 'Usala antes')
function Disparadores($d) { return @($disparadores | Where-Object { $d.Contains($_) }) }

# La marca de que una description le habla al AGENTE sobre el usuario en tercera persona, o le lista
# los triggers entre comillas. Una user-invoked la escribe el humano en su terminal: su description
# la lee él, así que se le habla a él (`Use when you're unfamiliar...`), no a un agente sobre él
# (`Use when the user wants...`). No es una regla de largo: `setup-matt-pocock-skills` es
# user-invoked y su description tiene 438 caracteres, y está bien.
# `Usala cuando` y `Usala antes` están acá porque son dos de los `$disparadores` de arriba: una
# user-invoked no necesita decirle al agente cuándo alcanzarla. El `"` PELADO no está, porque
# marcaría también una description que entrecomilla un término; ninguna lo hacía en el árbol, así
# que sacarlo no arregló nada que estuviera fallando — y se llevó puesta la única marca que
# atrapaba a `zoom-out`, cuya forma de agente no dice `the user` ni `user wants` sino que LISTA sus
# triggers entrecomillados. Eso último se marca por estructura, abajo: dos pares de comillas o más
# son una lista, uno solo es un término.
$marcasDeAgente = @('the user', 'user wants', 'el usuario', 'Usala cuando', 'Usala antes', 'Trigger when')
function MarcasDeAgente($d) {
  $m = @($marcasDeAgente | Where-Object { $d.Contains($_) })
  if (@($d.ToCharArray() | Where-Object { $_ -ceq '"' }).Count -ge 4) { $m += 'lista de triggers entre comillas' }
  return @($m)
}

# Una description plegada (`description: >` y el texto indentado abajo) deja a `Description` con el
# `>` pelado: sin esto, una user-invoked pasaba las marcas sin que nadie leyera su texto.
function EsEscalarPlano($d) { return ($d.Length -gt 0 -and $d[0] -notin @('>', '|', '"', "'")) }

# --- Anclas de los chequeadores ---
# Sin esto, un `EsUserInvoked` que devuelve siempre $false (o un `Disparadores` que devuelve siempre
# algo) deja la suite entera en verde sin mirar nada.
Assert (EsUserInvoked @('name: x', 'disable-model-invocation: true')) "EsUserInvoked ve el flag puesto"
Assert (-not (EsUserInvoked @('name: x'))) "EsUserInvoked no inventa el flag donde no está"
Assert (-not (EsUserInvoked @('disable-model-invocation: false'))) "EsUserInvoked no toma ``false`` por user-invoked"
Assert (-not (EsUserInvoked @('# disable-model-invocation: true'))) "EsUserInvoked no toma una línea comentada por el flag"
Assert ((Disparadores 'Use when the user wants X.').Count -gt 0) "Disparadores ve ``Use when``"
Assert ((Disparadores 'Compact the current conversation into a handoff document.').Count -eq 0) "Disparadores no inventa un disparo donde no hay"
Assert ((MarcasDeAgente 'Use when user wants to create an issue.').Count -gt 0) "MarcasDeAgente ve ``user wants``"
Assert ((MarcasDeAgente 'Tell the agent to zoom out. Use when you are unfamiliar with a section of code.').Count -eq 0) "MarcasDeAgente no marca una description que le habla al humano"
# Los dos parsers también van anclados: sin esto, un `Frontmatter` que devuelve el archivo entero
# deja la suite en verde, y es EXACTAMENTE el bug que ya se coló una vez acá (una description
# debajo del cierre dada por buena, `nombres-propios-de-skills.tests.ps1`).
Assert (-not (EsUserInvoked (Frontmatter "---`nname: x`n---`ndisable-model-invocation: true"))) "Frontmatter no ve un flag que cae DEBAJO del cierre"
Assert ((Frontmatter "prosa`nname: x`n---`nname: y`n---").Count -eq 0) "Frontmatter no toma por frontmatter un archivo que no abre con ``---``"
Assert ((Description @('description: una', 'description: otra')) -eq "") "Description no elige entre dos ``description:``"
Assert ((MarcasDeAgente 'Zoom out. Usala o deci cosas como "zoom out", "aleja la camara".').Count -gt 0) "MarcasDeAgente ve una lista de triggers entre comillas"
Assert ((MarcasDeAgente 'Mide el ancho del "slice" antes de cerrarlo.').Count -eq 0) "MarcasDeAgente no marca un solo término entrecomillado"
Assert (-not (EsEscalarPlano '>')) "EsEscalarPlano rechaza una description plegada"
Assert (EsEscalarPlano 'Una linea sola.') "EsEscalarPlano acepta una description de una línea"

# --- La lista DECLARADA ---
# $true = user-invoked (sólo la escribe un humano: lleva `disable-model-invocation: true`).
# $false = model-invoked (el agente, un hook u otra skill la tienen que alcanzar solos).
$politica = [ordered]@{
  'debug-source-first'         = $false   # la alcanza el agente ante una ausencia downstream
  'diagnosing-bugs'            = $false   # la alcanza el agente ante un bug
  'domain-modeling'            = $false   # la invoca el puntero /grill-with-docs por Skill tool
  'git-guardrails-claude-code' = $false
  'grill-me'                   = $true    # paso 1 del flujo: lo escribe el humano
  'grill-with-docs'            = $true    # paso 1 del flujo: lo escribe el humano
  'grilling'                   = $false   # la invocan los dos punteros por Skill tool
  'handoff'                    = $true    # lo pide el humano al cerrar la sesión
  'research'                   = $false
  'resolving-merge-conflicts'  = $false
  'review-loop'                = $false   # LA ORDENA EL HOOK review-loop-trigger (ADR-0003)
  'setup-matt-pocock-skills'   = $true
  'slice-review'               = $false   # LA INVOCA review-loop por Skill tool (ADR-0003)
  'tdd'                        = $false
  'to-issues'                  = $true    # paso 6 del flujo: lo escribe el humano
  'to-prd'                     = $true    # paso 4 del flujo: lo escribe el humano
  'to-questionnaire'           = $true
  'triage'                     = $true
  'verify-downstream-arrival'  = $false   # la alcanza el agente antes de afirmar que algo llegó
  'wizard'                     = $false
  'zoom-out'                   = $true
}
$declarados = @($politica.Keys)
$userInvoked  = @($declarados | Where-Object { $politica[$_] })
$modelInvoked = @($declarados | Where-Object { -not $politica[$_] })

# Los conteos, fijos: un mutante que da vuelta la clasificación en masa cambia estos dos números.
Assert ($userInvoked.Count -eq 9)   "la lista declara 9 comandos user-invoked (declara: $($userInvoked.Count))"
Assert ($modelInvoked.Count -eq 12) "la lista declara 12 comandos model-invoked (declara: $($modelInvoked.Count))"

# Los dos que NO se pueden clasificar mal, por nombre y contra la lista misma.
Assert ($politica.Contains('review-loop')  -and -not $politica['review-loop'])  "la lista declara review-loop model-invoked (el hook review-loop-trigger ordena correrla)"
Assert ($politica.Contains('slice-review') -and -not $politica['slice-review']) "la lista declara slice-review model-invoked (review-loop la invoca por Skill tool)"

# --- El frontmatter REAL de los comandos, en las cuatro raíces ---
foreach ($raiz in $raices) {
  $etq = Etiqueta $raiz
  $dirCmd = Join-Path $raiz ".claude/commands"
  $hay = @(if (Test-Path -LiteralPath $dirCmd) { Get-ChildItem -LiteralPath $dirCmd -File -Filter *.md | ForEach-Object { $_.BaseName } })
  $hay = @($hay | Sort-Object)

  # Las dos direcciones, por separado, para que el mensaje diga cuál de las dos se rompió.
  $sobran = @($hay | Where-Object { -not $politica.Contains($_) })
  Assert ($sobran.Count -eq 0) "$etq : todo comando instalado está en la lista de invocación (sin clasificar: $($sobran -join ', '))"
  $faltan = @($declarados | Where-Object { $hay -notcontains $_ })
  Assert ($faltan.Count -eq 0) "$etq : todo comando de la lista está instalado (falta: $($faltan -join ', '))"

  foreach ($n in $declarados) {
    $esperadoUser = $politica[$n]
    $que = if ($esperadoUser) { "user-invoked (disable-model-invocation: true)" } else { "model-invoked (sin el flag: el agente la tiene que alcanzar solo)" }

    $fmCmd = @(Frontmatter (Texto (Join-Path $dirCmd "$n.md")))
    Assert ($fmCmd.Count -gt 0 -and (EsUserInvoked $fmCmd) -eq $esperadoUser) "$etq : el comando $n es $que"

    # El flag va en los dos lados. `.claude/commands/` es lo que lee Claude Code; `.agents/skills/`
    # es la copia que sella el lockfile y la que viaja a otros agentes: si divergen, el lockfile
    # sella una clasificación que no es la que corre.
    $fmSkill = @(Frontmatter (Texto (Join-Path $raiz ".agents/skills/$n/SKILL.md")))
    Assert ($fmSkill.Count -gt 0 -and (EsUserInvoked $fmSkill) -eq (EsUserInvoked $fmCmd)) "$etq : el SKILL.md de $n declara la misma invocación que el comando"

    # La forma de la description se sigue de la clasificación, no del largo.
    $d = Description $fmCmd
    if ($esperadoUser) {
      $marcas = @(MarcasDeAgente $d)
      Assert ($d.Length -gt 0 -and $marcas.Count -eq 0) "$etq : la description de $n le habla al humano que la escribe (marcas de agente: $($marcas -join ' | '))"
      Assert (EsEscalarPlano $d) "$etq : la description de $n es una línea plana — plegada (``>``/``|``) no la lee ni este test ni el humano en el selector"
    } else {
      $disp = @(Disparadores $d)
      Assert ($disp.Count -gt 0) "$etq : la description de $n conserva su fórmula de disparo ($($disparadores -join ' / ')) — sin ella el agente no la alcanza y la paga igual"
    }
  }

  # Los dos del ADR-0003, otra vez contra el archivo: acá se lee el frontmatter, no la lista.
  foreach ($n in @('review-loop', 'slice-review')) {
    $fm = @(Frontmatter (Texto (Join-Path $dirCmd "$n.md")))
    Assert ($fm.Count -gt 0 -and -not (EsUserInvoked $fm)) "$etq : el comando $n NO lleva disable-model-invocation (una user-invoked no se invoca por Skill tool)"
  }
}

Write-Host ""
if ($script:checks -ne $ExpectedChecks) {
  Write-Host "FAIL: corrieron $($script:checks) aserciones y se esperaban $ExpectedChecks"
  $script:failures++
}
Write-Host "$($script:checks) aserciones, $($script:failures) fallidas"
exit ([int]($script:failures -gt 0))
