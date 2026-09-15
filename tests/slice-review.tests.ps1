# tests/slice-review.tests.ps1 — runner sin Pester. Correr: pwsh -NoProfile -File tests/slice-review.tests.ps1
# El motor del review-loop tiene que ser invocable POR EL AGENTE. /slice-review es la columna
# vertebral: es lo unico que hace cumplir las Hard rules del CLAUDE.md (espejo, afirmaciones, techo
# ~400, ruteo) y aporta el reparto multi-foco + pase de confianza + coherencia. El built-in
# /code-review resulto SER invocable por el agente (verificado 2026-08-26: corrio como fork desde un
# subagente), asi que el loop lo SUMA como reviewer independiente acotado al turno 1 (foco par,
# esfuerzo medium) para diversidad de reviewers — no lo reemplaza. Ver ADR-0003.
$ErrorActionPreference = "Stop"
$repo = Split-Path $PSScriptRoot -Parent
$skills = @(Get-ChildItem (Join-Path $repo "skills") -Directory | Where-Object Name -like "bootstrap-*-project")
$script:failures = 0
function Assert($cond, $msg) {
  if ($cond) { Write-Host "ok:   $msg" } else { Write-Host "FAIL: $msg"; $script:failures++ }
}
. (Join-Path $PSScriptRoot "lib\temp-workspace.ps1")
$script:runRoot = New-TestRunRoot "srv"
trap { Remove-TestRunRoot $script:runRoot; break }

Assert ($skills.Count -ge 3) "hay al menos 3 skills bootstrap-*-project ($($skills.Count))"

# Pares (command para el humano, SKILL.md con triggers para autodescubrimiento) de cada scaffold.
foreach ($s in $skills) {
  $scaffold = Join-Path $s.FullName "assets\scaffold"
  $pairs = @{
    "slice-review" = @(
      (Join-Path $scaffold ".claude\commands\slice-review.md"),
      (Join-Path $scaffold ".agents\skills\slice-review\SKILL.md")
    )
    "review-loop"  = @(
      (Join-Path $scaffold ".claude\commands\review-loop.md"),
      (Join-Path $scaffold ".agents\skills\review-loop\SKILL.md")
    )
  }

  foreach ($name in $pairs.Keys) {
    foreach ($f in $pairs[$name]) {
      $rel = $f.Substring($s.FullName.Length).TrimStart('\')
      if (-not (Test-Path -LiteralPath $f)) { Assert $false "$($s.Name): existe $rel"; continue }
      Assert $true "$($s.Name): existe $rel"
      $txt = [IO.File]::ReadAllText($f)

      # Invocable por el agente: necesita description en el frontmatter y no puede estar bloqueado.
      Assert ($txt -match '(?m)^description:\s*\S') "$($s.Name): $rel declara description (invocable)"
      Assert ($txt -notmatch '(?m)^disable-model-invocation:\s*true') `
        "$($s.Name): $rel no se bloquea con disable-model-invocation"

      # 08a — el guard viejo se INVIRTIO. La premisa "/code-review es human-only / no invocable"
      # caduco (verificado 2026-08-26), asi que ya NO se prohibe ordenar /code-review: el loop lo
      # invoca a proposito como foco acotado a turno-1/medium. Que SE invoque a proposito lo aseveran
      # positivamente los asserts del bloque "08a: /code-review como foco par" (mas abajo, sobre
      # $slicePairs y $loopPairs). Aca solo queda que el doc no se auto-bloquee (disable-model-invocation).
    }
  }

  # La corrida de review del loop tiene que apuntar al reviewer invocable. El número de paso no
  # se fija acá: desde el review incremental, el paso 1 es pedirle el rango al marcador y la
  # corrida de review es el paso 2. Lo que este test blinda es el MOTOR, no el orden.
  foreach ($f in $pairs["review-loop"]) {
    $rel = $f.Substring($s.FullName.Length).TrimStart('\')
    if (-not (Test-Path -LiteralPath $f)) { continue }
    $txt = [IO.File]::ReadAllText($f)
    Assert ($txt -match '(?m)^\d+\. Run `/slice-review`') "$($s.Name): $rel corre /slice-review como paso numerado del loop"
  }
}

# --- A3: corrida de review incremental ---------------------------------------------------------
# El contenido del prompt de slice-review se verifica en las 3 skills bootstrap Y en la copia del
# repo (AC: "verificados en las 3 skills bootstrap y en la copia del repo"). Los dos artefactos de
# cada ubicacion (command para el humano + SKILL.md para autodescubrimiento) comparten el CUERPO,
# asi que las mismas aserciones corren sobre ambos.
$slicePairs = @(
  @{ label = "repo"; files = @(
      (Join-Path $repo ".claude\commands\slice-review.md"),
      (Join-Path $repo ".agents\skills\slice-review\SKILL.md")
  ) }
)
foreach ($s in $skills) {
  $scaffold = Join-Path $s.FullName "assets\scaffold"
  $slicePairs += @{ label = $s.Name; files = @(
      (Join-Path $scaffold ".claude\commands\slice-review.md"),
      (Join-Path $scaffold ".agents\skills\slice-review\SKILL.md")
  ) }
}

foreach ($p in $slicePairs) {
  foreach ($f in $p.files) {
    $rel = Split-Path $f -Leaf
    if (-not (Test-Path -LiteralPath $f)) { Assert $false "$($p.label): existe slice-review ($rel)"; continue }
    $txt = [IO.File]::ReadAllText($f)

    # Cambio 1 — el objetivo por DEFECTO (sin args) es el delta sin revisar, resuelto del marcador.
    Assert ($txt -match 'review-marker\.ps1 -Action range') `
      "$($p.label)/${rel}: el default resuelve el delta desde el marcador (-Action range)"
    # El rango completo del slice queda reservado al pase de coherencia (A4), no es el default.
    Assert ($txt -match '(?i)reserved for the coherence pass') `
      "$($p.label)/${rel}: el rango completo del slice queda reservado al pase de coherencia"

    # Cambio 2 — con delta vacio (exit 0) reporta 'nada que revisar' en vez de inventar un rango.
    Assert ($txt -match '(?i)everything up to the marker was already reviewed') `
      "$($p.label)/${rel}: delta vacio del marcador => nada que revisar, sin inventar rango"

    # Cambio 3 — la prohibicion de escritura viaja en el contexto compartido, una sola vez.
    Assert ($txt -match '(?i)reviewer, not an editor') `
      "$($p.label)/${rel}: declara la prohibicion de escritura en el contexto compartido"

    # Cambio 4 — cada foco declara su TIER de modelo (agnostico, sin pin de version):
    # reglas/historia en el modelo mas liviano, bugs/contratos/tests en el mas capaz.
    Assert ($txt -match '(?i)project rules and historical context on \*\*a lighter, faster model\*\*') `
      "$($p.label)/${rel}: reglas e historia declaran el modelo mas liviano (agnostico)"
    Assert ($txt -match '(?i)bugs, contracts and tests on \*\*the most capable model available\*\*') `
      "$($p.label)/${rel}: bugs, contratos y tests declaran el modelo mas capaz (agnostico)"

    # Cambio 5 — el pase de confianza corre en el modelo mas capaz, misma rubrica y corte en 60.
    Assert ($txt -match '(?i)the confidence pass runs on the most capable model available') `
      "$($p.label)/${rel}: el pase de confianza corre en el modelo mas capaz (agnostico)"
    Assert ($txt -match 'Drop everything below 60') `
      "$($p.label)/${rel}: el pase de confianza mantiene el corte en 60 (regresion)"

    # Migracion a agnostico — NINGUNA seccion del doc pinnea un modelo+version. Mismo guard que el
    # foco de mutacion (mas abajo) pero a TODO el archivo: un pin reintroducido en cualquier lado
    # (Opus 5, Sonnet 5, Opus 4.8, Haiku 4.5, GPT-4...) lo caza. "CLAUDE.md" no matchea (no hay
    # digito tras el separador opcional); "0-100" tampoco (no lo precede un nombre de modelo).
    Assert (-not ($txt -match '(?i)(opus|sonnet|haiku|claude|gpt)[- ]?\d')) `
      "$($p.label)/${rel}: el doc no pinnea ningun modelo+version (ruteo agnostico end-to-end)"

    # AC6 (regresion) — el reporte sigue diciendo cuantos descarto la confianza y que rango se reviso.
    Assert ($txt -match '(?i)dropped by the confidence pass') `
      "$($p.label)/${rel}: el reporte dice cuantos hallazgos descarto la confianza"
    Assert ($txt -match '(?i)diff range that was actually reviewed') `
      "$($p.label)/${rel}: el reporte dice que rango se reviso"

    # --- Turno 1 del review-loop sobre A3: correcciones del Step 1 (marcador) ---
    # A — el script AUSENTE se maneja pre-flight (Test-Path), no metido en el bucket exit 2
    #     (pwsh -File <missing> sale 64 e imprime usage a stdout, no exit 2 + empty).
    Assert ($txt -match '(?i)Test-Path[^\r\n]*review-marker\.ps1') `
      "$($p.label)/${rel}: chequea Test-Path del marcador antes de invocarlo (script ausente != exit 2)"
    # B — exit 2 separa el caso 'no es repo git / sin commits' (reportar y parar) del base-indeterminable.
    Assert ($txt -match '(?i)not a git repo, or a repo with no commits') `
      "$($p.label)/${rel}: exit 2 separa el caso no-repo/sin-commits (reportar y parar)"
    # C — la rama de recuperacion exit-2 queda pinneada (no borrable en silencio).
    Assert ($txt -match '(?i)exit 2 \+ empty') `
      "$($p.label)/${rel}: documenta la recuperacion de exit 2"
    # D — el marcador es el objetivo por DEFECTO sin args (no la vieja cascada working-tree/branch).
    Assert ($txt -match '(?i)without arguments, the default target is the \*\*unreviewed delta\*\*') `
      "$($p.label)/${rel}: sin args, el default es el delta del marcador"
    Assert ($txt -match '(?i)or invent a range') `
      "$($p.label)/${rel}: con delta vacio no inventa un rango (accion pinneada)"
    # F — la prohibicion de escritura aparece UNA sola vez (el punto del cambio 3).
    Assert (([regex]::Matches($txt, 'reviewer, not an editor')).Count -eq 1) `
      "$($p.label)/${rel}: la prohibicion de escritura aparece exactamente una vez"

    # --- Turno 2 del review-loop sobre A3: pinnear las ACCIONES de recuperacion (no solo la deteccion) ---
    # G (parity con review-loop.md:86) — en detached-HEAD no se usa <base>...HEAD (la base es lo irresoluble).
    Assert ($txt -match '(?i)do not reach for .git diff <base>\.\.\.HEAD. here') `
      "$($p.label)/${rel}: caveat: en exit-2 base-irresoluble no arrastrar git diff <base>...HEAD"
    # H1 — la accion del script ausente: caer al branch range del slice.
    Assert ($txt -match '(?i)fall back to the slice.s branch\s+range') `
      "$($p.label)/${rel}: script ausente => fallback al branch range del slice"
    # H2 — la recuperacion exit-2 base-irresoluble: working tree, si no el ultimo commit.
    Assert ($txt -match '(?i)else the last commit') `
      "$($p.label)/${rel}: exit-2 base-irresoluble => working tree, si no el ultimo commit"
    # H3 — AMBAS recuperaciones (script ausente y exit-2 base-irresoluble) declaran no-incremental.
    #      Conteo >= 2: borrar una sola de las dos declaraciones baja a 1 y el assert muerde.
    Assert (([regex]::Matches($txt, '(?i)not incremental')).Count -ge 2) `
      "$($p.label)/${rel}: ambas recuperaciones declaran que la corrida no es incremental"
    # H4 — el caso no-repo/sin-commits NO llama git show HEAD (falla sin commits): reportar y parar.
    Assert ($txt -match '(?i)it fails with no commits') `
      "$($p.label)/${rel}: no-repo/sin-commits => no llamar git show HEAD (reportar y parar)"
  }
}

# --- A4: pase de coherencia ------------------------------------------------------------------
# El pase de coherencia mira el SLICE ENTERO una sola vez, al cierre, contra la intencion
# declarada. Vive en /slice-review (la mecanica) y lo invoca /review-loop al cerrar. Se verifica
# sobre las 4 copias (repo + 3 skills). Los asserts de contenido se anclan a la SECCION del pase
# (no al archivo entero): la cadena "coherence pass" ya aparece en A3 ("reserved for the coherence
# pass"), asi que un match suelto pasaria sin la seccion nueva.

# Extrae el cuerpo de una seccion markdown: desde su header `## <titulo>` hasta el proximo `## ` o
# el fin del archivo. Cadena vacia si la seccion no existe (y todos los asserts anclados muerden).
function Section([string]$txt, [string]$header) {
  # $header es un titulo LITERAL: se escapa para que un ':' u otro metacaracter no rompa el regex.
  $m = [regex]::Match($txt, "(?im)^##\s+$([regex]::Escape($header)).*?(?=^##\s|\z)", 'Singleline')
  if ($m.Success) { return $m.Value } else { return "" }
}

foreach ($p in $slicePairs) {
  foreach ($f in $p.files) {
    $rel = Split-Path $f -Leaf
    if (-not (Test-Path -LiteralPath $f)) { continue }
    $txt = [IO.File]::ReadAllText($f)
    $coh = Section $txt 'Coherence pass'

    # AC1 — existe como seccion propia: foco unico, de solo lectura, sobre el rango completo.
    Assert ($coh -ne "") "$($p.label)/${rel}: existe la seccion del pase de coherencia (## Coherence pass)"
    Assert ($coh -match '(?i)single read-only focus') `
      "$($p.label)/${rel}: el pase de coherencia es un foco unico de solo lectura"
    Assert ($coh -match '(?i)full slice range') `
      "$($p.label)/${rel}: el pase de coherencia mira el rango completo del slice"
    # A4b — el rango completo se ancla en el INICIO DEL SLICE (-Action slice-base), no en la base de
    # rama (-Action base): en una rama apilada la base de rama sobre-scopea a toda la rama. slice-base
    # cae a la base de rama cuando no hay snapshot, así que sigue cubriendo el primer slice.
    Assert ($coh -match '-Action slice-base') `
      "$($p.label)/${rel}: el pase de coherencia ancla en el inicio del slice (-Action slice-base)"
    # No debe quedar el -Action base viejo dentro de la seccion (seria anclar en la rama entera).
    Assert (-not ($coh -match '-Action base\b')) `
      "$($p.label)/${rel}: el pase de coherencia ya no ancla en la base de rama (-Action base)"
    # A4b — caveat de amend/rebase: si el snapshot resuelve pero quedo no-ancestro, el diff trae hunks
    # que no hiciste; ahi SI se cae al branch range (la base de rama resuelve, distinto del exit 2).
    Assert ($coh -match '(?i)changes you did not make') `
      "$($p.label)/${rel}: el pase de coherencia tiene el caveat de amend/rebase (hunks que no hiciste)"

    # AC2 — declara explicitamente que no ejecuta nada.
    Assert ($coh -match '(?i)executes nothing') `
      "$($p.label)/${rel}: el pase de coherencia declara que no ejecuta nada"

    # AC3 — lee el slice contra su intencion declarada (tarea, PRD o mensaje de commit).
    Assert ($coh -match '(?i)declared intent') `
      "$($p.label)/${rel}: el pase de coherencia lee contra la intencion declarada"
    Assert ($coh -match '(?i)the\s+task,\s+the\s+PRD,\s+or\s+the\s+commit\s+message\s+it\s+implements') `
      "$($p.label)/${rel}: la intencion declarada es la tarea, el PRD o el mensaje de commit"

    # AC4 — corre en el modelo mas liviano (agnostico, sin pin; mismo tier que reglas/historia).
    Assert ($coh -match '(?i)a lighter, faster model') `
      "$($p.label)/${rel}: el pase de coherencia corre en el modelo mas liviano (agnostico)"

    # AC6 — sus hallazgos pasan por el mismo pase de confianza que cualquier otro.
    Assert ($coh -match '(?i)same confidence pass') `
      "$($p.label)/${rel}: los hallazgos del pase de coherencia pasan por el pase de confianza"

    # Contrato de invocacion: se dispara con --coherence.
    Assert ($coh -match '/slice-review --coherence') `
      "$($p.label)/${rel}: el pase de coherencia se invoca con /slice-review --coherence"
    # Step 1 rutea --coherence a la seccion en vez de tratarlo como un rango de diff.
    Assert ($txt -match '(?i)if .\$ARGUMENTS. is .--coherence') `
      "$($p.label)/${rel}: Step 1 rutea --coherence a la seccion del pase (no como rango de diff)"

    # --- Turno 1 del review-loop sobre A4: correcciones de coherencia interna ---
    # M1 (contratos+bugs convergen) — el ruteo de --coherence NO puede mandar a saltear los steps
    #   que el pase REUSA: Step 3 (contexto compartido), Step 5 (pase de confianza) y Step 6
    #   (reporte). "skip Steps 1-5" los tragaba y un agente literal saltearia la confianza (AC6).
    Assert ($txt -notmatch '(?i)skip Steps 1') `
      "$($p.label)/${rel}: el ruteo de --coherence no manda a saltear los steps que el pase reusa (Step 3/5/6)"
    # M2 (historia) — en exit 2 la base es JUSTO lo irresoluble: no arrastrar git diff <base>...HEAD
    #   (misma regla que el Step 1). La frase 'do not reach for' tiene que vivir DENTRO de la seccion
    #   del pase, no solo en el Step 1 (por eso se ancla en $coh, no en $txt).
    Assert ($coh -match '(?i)do not reach for') `
      "$($p.label)/${rel}: el pase de coherencia no cae al branch range cuando la base es irresoluble (exit 2)"
  }
}

# --- A5: foco de mutacion acotada ------------------------------------------------------------
# Un 6º foco que verifica que los tests del slice tienen DIENTES: rompe lineas de logica cambiadas
# a proposito y mira si algun test se da cuenta. A diferencia de los 5 focos de lectura pura, este
# EJECUTA, de ahi el worktree aislado. Presupuesto explicito (solo turno 1, <=8 mutantes) para que
# el costo no crezca con la profundidad del loop. Anclado a la SECCION del foco (## Mutation focus).
foreach ($p in $slicePairs) {
  foreach ($f in $p.files) {
    $rel = Split-Path $f -Leaf
    if (-not (Test-Path -LiteralPath $f)) { continue }
    $txt = [IO.File]::ReadAllText($f)
    $mut = Section $txt 'Mutation focus'

    # Existe como seccion propia.
    Assert ($mut -ne "") "$($p.label)/${rel}: existe la seccion del foco de mutacion (## Mutation focus)"
    # Presupuesto: <=8 mutantes, solo turno 1, prohibido turnos 2+.
    Assert ($mut -match '(?i)at most\s+8 mutants') `
      "$($p.label)/${rel}: declara el tope de <=8 mutantes (at most, no 'at least')"
    Assert ($mut -match "(?i)only on the loop.s first turn") `
      "$($p.label)/${rel}: declara que corre solo en el turno 1"
    Assert ($mut -match '(?i)prohibited on turns 2') `
      "$($p.label)/${rel}: declara que esta prohibido en los turnos 2+"
    # Worktree del estado VIVO del slice, no del SHA del marcador; fuera del repo; con untracked.
    Assert ($mut -match 'git worktree add --detach') `
      "$($p.label)/${rel}: construye un worktree aislado (git worktree add --detach)"
    Assert ($mut -match 'git stash create') `
      "$($p.label)/${rel}: el worktree parte de un snapshot vivo (git stash create), no del marcador"
    Assert ($mut -match '(?i)ls-files --others') `
      "$($p.label)/${rel}: copia los untracked al worktree (los tests nuevos no estan en el snapshot)"
    Assert ($mut -match '(?i)OUTSIDE the repo|outside the repo') `
      "$($p.label)/${rel}: el worktree vive fuera del repo"
    Assert ($mut -match "(?i)use the .*marker only to identify which lines changed") `
      "$($p.label)/${rel}: el marcador solo identifica las lineas cambiadas, no construye el worktree"
    # Aislamiento: muta solo en el worktree, el arbol del usuario queda intacto.
    Assert ($mut -match "(?i)never in the user.s tree") `
      "$($p.label)/${rel}: muta solo en el worktree, nunca en el arbol del usuario"
    # Mutantes uno a la vez, solo lineas de logica cambiadas, priorizados por riesgo.
    Assert ($mut -match '(?i)one at a time') `
      "$($p.label)/${rel}: aplica los mutantes uno a la vez (no acumulados)"
    Assert ($mut -match '(?i)logic lines the slice changed') `
      "$($p.label)/${rel}: muta solo lineas de logica que el slice cambio"
    Assert ($mut -match '(?i)prioritise by risk|prioritize by risk') `
      "$($p.label)/${rel}: prioriza por riesgo cuando hay mas de 8 lineas mutables"
    # Test relevante del diff, nunca la suite entera, 'sin test' es un hallazgo.
    Assert ($mut -match "(?i)relevant test file from the slice.s own diff") `
      "$($p.label)/${rel}: el test relevante sale del diff del slice"
    Assert ($mut -match '(?i)never the whole suite') `
      "$($p.label)/${rel}: nunca corre la suite entera"
    Assert ($mut -match '(?i)no test covers the changed logic') `
      "$($p.label)/${rel}: 'sin test que cubra la logica' es un hallazgo"
    # Hallazgo = sobreviviente = Medium; no se reportan los que mueren.
    Assert ($mut -match '(?i)surviving mutant') `
      "$($p.label)/${rel}: el hallazgo es un mutante sobreviviente"
    Assert ($mut -match '(?i)survivors at \*\*Medium\*\*') `
      "$($p.label)/${rel}: el sobreviviente se reporta como Medium"
    # Mutante equivalente: filtrado por el foco y por el pase de confianza (<60).
    Assert ($mut -match '(?i)equivalent mutant') `
      "$($p.label)/${rel}: contempla el mutante equivalente"
    Assert ($mut -match '(?i)below 60') `
      "$($p.label)/${rel}: el pase de confianza descarta el equivalente (<60)"
    # Modelo agnostico: el mas capaz disponible, sin pin de version.
    Assert ($mut -match '(?i)most capable model available') `
      "$($p.label)/${rel}: corre en el modelo mas capaz disponible (agnostico, sin pin)"
    # Agnostico de verdad: no puede pinnear NINGUN modelo+version (Opus 5, Opus 4.8, Sonnet 5,
    # Haiku 4.5, GPT-4...), no solo el string "Opus 5" que ya envejecio. Un pin agregado al lado de
    # "most capable model available" romperia el AC #9 (decision del grill) y este assert lo caza.
    Assert (-not ($mut -match '(?i)(opus|sonnet|haiku|claude|gpt)[- ]?\d')) `
      "$($p.label)/${rel}: el foco de mutacion no pinnea ningun modelo+version (es agnostico)"
    # Cleanup del worktree garantizado.
    Assert ($mut -match 'git worktree remove') `
      "$($p.label)/${rel}: limpia el worktree al terminar (git worktree remove)"
    # Fix turno 1 (contratos) — el foco DEBE mutar archivos, asi que la prohibicion de escritura del
    # contexto compartido necesita una excepcion explicita: puede mutar SOLO dentro de su worktree.
    # Sin esto, un subagente que obedece la prohibicion no aplica ningun mutante y el foco no produce nada.
    Assert ($mut -match '(?i)exception to the write prohibition') `
      "$($p.label)/${rel}: talla una excepcion a la prohibicion de escritura para el foco"
    Assert ($mut -match '(?i)only inside its isolated worktree') `
      "$($p.label)/${rel}: la excepcion de escritura es solo dentro del worktree aislado"
    # Fix turno 2 (contratos) — la excepcion tiene que conceder el MECANISMO, no solo la ubicacion:
    # el ban de Step 3 prohibe 'Write, Edit, or any file-mutating tool', asi que la excepcion debe
    # decir explicitamente que el foco PUEDE usar sus herramientas de edicion dentro del worktree,
    # o un foco obediente a la letra mas fuerte no aplica ningun mutante y produce cero.
    Assert ($mut -match '(?i)file-editing tools') `
      "$($p.label)/${rel}: la excepcion concede el mecanismo (usar herramientas de edicion en el worktree)"
    # Fix turno 1 (bugs) — la receta debe ASIGNAR $tmp; un snippet que usa $tmp sin asignarlo corre
    # 'git worktree add $tmp' vacio => error de git 'requires a path'.
    Assert ($mut -match '(?m)\$tmp\s*=') `
      "$($p.label)/${rel}: la receta asigna `$tmp (no lo usa sin definir)"
    # Fix turno 1 (bugs) — el worktree no trae deps gitignoradas (node_modules/.venv); si el test no
    # puede correr por eso, el foco reporta 'no pude ejecutar', no un falso limpio ni un falso hallazgo.
    Assert ($mut -match '(?i)could not execute') `
      "$($p.label)/${rel}: si el test no arranca (deps gitignoradas) reporta que no pudo ejecutar"
  }
}

# --- A5 ruteo: --mutation en Step 1, despacho condicional en Step 4, exclusivo con --coherence ----
foreach ($p in $slicePairs) {
  foreach ($f in $p.files) {
    $rel = Split-Path $f -Leaf
    if (-not (Test-Path -LiteralPath $f)) { continue }
    $txt = [IO.File]::ReadAllText($f)
    $s1 = Section $txt 'Step 1 — Resolve what to review'
    $s4 = Section $txt 'Step 4 — Fan out parallel reviewers'

    # Step 1 reconoce y saca el flag, tratando el resto como el rango.
    Assert ($s1 -match "(?i)contains .--mutation.") `
      "$($p.label)/${rel}: Step 1 parsea --mutation"
    # Standalone opt-in explicito (anclado a Step 1, no al archivo entero).
    Assert ($s1 -match '/slice-review --mutation') `
      "$($p.label)/${rel}: standalone se pide con /slice-review --mutation"
    # Excluyente con --coherence; si ambos, coherence gana.
    Assert ($s1 -match '(?i)mutually exclusive') `
      "$($p.label)/${rel}: --mutation y --coherence son excluyentes"
    Assert ($s1 -match "(?i)--coherence.? wins") `
      "$($p.label)/${rel}: si llegan ambos, --coherence gana"
    # Fix turno 1 (bugs+contratos) — 'coherence gana' tiene que estar ENFORCED por el ruteo, no solo
    # declarado: el chequeo pre-existente de coherencia es igualdad exacta ('is --coherence'), asi que
    # con ambos flags el bloque de --mutation lo trataria como rango basura. El ruteo debe resolver
    # --coherence ANTES de tratar el resto como rango.
    Assert ($s1 -match "(?i)ignore .--mutation. and jump to the Coherence pass") `
      "$($p.label)/${rel}: el ruteo resuelve --coherence antes que --mutation (coherence gana de verdad)"
    # Step 4 despacha el 6to foco condicional a --mutation.
    Assert ($s4 -match '(?i)--mutation') `
      "$($p.label)/${rel}: Step 4 despacha el foco de mutacion condicional a --mutation"
    Assert ($s4 -match '(?i)sixth focus') `
      "$($p.label)/${rel}: Step 4 lo despacha como sexto foco"
  }
}

# --- 08a: /code-review como foco par acotado a turno-1 (ensemble) --------------------------------
# La premisa "/code-review es human-only / no invocable" CADUCO (verificado 2026-08-26: invocable
# desde un subagente, corrio como fork hasta completarse). El review-loop lo suma como reviewer
# independiente en el turno 1 (foco par en la ola del fan-out), esfuerzo medium, latency-neutral en
# el slack detras del foco de mutacion. Anclado a la SECCION del foco (## Code-review focus) y a Step 1/4.
foreach ($p in $slicePairs) {
  foreach ($f in $p.files) {
    $rel = Split-Path $f -Leaf
    if (-not (Test-Path -LiteralPath $f)) { continue }
    $txt = [IO.File]::ReadAllText($f)
    $s1  = Section $txt 'Step 1 — Resolve what to review'
    $s4  = Section $txt 'Step 4 — Fan out parallel reviewers'
    $s5  = Section $txt 'Step 5 — Confidence pass (filter false positives)'
    $cr  = Section $txt 'Code-review focus'

    # Existe como seccion propia.
    Assert ($cr -ne "") "$($p.label)/${rel}: existe la seccion del foco de code-review (## Code-review focus)"
    # Gate: solo turno 1, prohibido turnos 2+ (simetrico con la mutacion).
    Assert ($cr -match "(?i)only on the loop.s first turn") `
      "$($p.label)/${rel}: el foco de code-review corre solo en el turno 1"
    Assert ($cr -match '(?i)prohibited on turns 2') `
      "$($p.label)/${rel}: el foco de code-review esta prohibido en los turnos 2+"
    # Esfuerzo acotado a medium. El assert se ancla a "medium effort", no al token suelto "medium"
    # (que pasaria con "not medium - use high"); dientes reales sobre el tier elegido (tests F3+).
    Assert ($cr -match '(?i)medium effort') `
      "$($p.label)/${rel}: el foco de code-review corre a esfuerzo medium (acotado)"
    # Invoca el built-in /code-review (invocable por el agente; la premisa de no-invocabilidad caduco).
    Assert ($cr -match '/code-review') `
      "$($p.label)/${rel}: el foco invoca el built-in /code-review"
    # Step 1 parsea --code-review.
    Assert ($s1 -match '(?i)--code-review') `
      "$($p.label)/${rel}: Step 1 parsea --code-review"
    # Step 4 despacha el foco de code-review condicional a --code-review.
    Assert ($s4 -match '(?i)--code-review') `
      "$($p.label)/${rel}: Step 4 despacha el foco de code-review condicional a --code-review"
    # Framing (coherencia de 08a): el doc ya no afirma que /code-review es human-only / no invocable.
    # La premisa caduco; dejar la vieja frase dejaria el slice internamente incoherente (la mecanica
    # lo invoca). El resto de la framing (README, TESTING, ADR-0001, etc.) es 08b.
    Assert ($txt -notmatch '(?i)restricted to human invocation') `
      "$($p.label)/${rel}: el doc ya no afirma que /code-review es human-only (framing coherente con la mecanica)"

    # 08a dedup — /code-review solapa el foco de bugs; sin dedup entran hallazgos duplicados al
    # reporte. El paso de dedup vive en el pase de confianza (Step 5, latency-neutral), contrasta
    # contra el foco de bugs y dedupea por DEFECTO SUBYACENTE (no solo file:line exacto).
    Assert ($s5 -match '(?i)de-duplicat|dedup') `
      "$($p.label)/${rel}: Step 5 tiene un paso de dedup de hallazgos"
    Assert ($s5 -match '(?i)underlying defect') `
      "$($p.label)/${rel}: el dedup es por defecto subyacente (no solo file:line exacto)"
    Assert ($s5 -match '(?i)Bugs focus') `
      "$($p.label)/${rel}: el dedup contrasta los hallazgos de code-review contra el foco de bugs"

    # 08a turno 1 (fork join; bugs+contratos+code-review, 4x) — /code-review corre como FORK async;
    # hay que esperar su reporte y juntar sus hallazgos ANTES de Step 5, o se emite el reporte con el
    # fork corriendo y sus hallazgos se pierden (el modo de falla que el loop existe para evitar).
    Assert ($cr -match '(?i)collect its findings before') `
      "$($p.label)/${rel}: el foco espera y junta los hallazgos del fork de code-review antes de Step 5"
    # 08a turno 1 (read-only; contratos) — /code-review no recibe la prohibicion de escritura de Step 3
    # y corre en el arbol real; hay que invocarlo read-only, NUNCA con --fix (mutaria el arbol compartido).
    Assert ($cr -match '(?i)never with .--fix') `
      "$($p.label)/${rel}: el foco invoca /code-review read-only, nunca con --fix"
    # 08a turno 1 (scope; code-review) — /code-review no toma el stash ref del marcador; revisa el
    # working-tree diff, que puede ser mas amplio que el delta. Aceptado (dedup + confianza lo absorben).
    Assert ($cr -match '(?i)working-tree diff') `
      "$($p.label)/${rel}: el foco documenta que /code-review revisa el working-tree diff (no el stash ref)"
    # 08a turno 1 (precedencia; tests+contratos) — simetrico con el guard de --mutation (mas arriba):
    # --coherence gana sobre --code-review y hay que pinnearlo, o una regresion que borre la clausula
    # de precedencia pasa verde. Misma clase de defecto que el fix M del turno 1 de A5.
    Assert ($s1 -match '(?i)ignore .--code-review. and jump to the Coherence pass') `
      "$($p.label)/${rel}: Step 1 pinnea que --coherence gana sobre --code-review"
    # 08a turno 1 (co-ocurrencia; tests+bugs) — el turno 1 pasa AMBOS flags juntos (--mutation y
    # --code-review); comportamiento load-bearing sin cobertura hasta ahora.
    Assert ($s1 -match '(?i)passes \*\*both\*\* together') `
      "$($p.label)/${rel}: Step 1 documenta que el turno 1 pasa ambos flags juntos"
    # 08a turno 2 (concurrencia; contratos) — /code-review corre git en el repo real en paralelo; su
    # index.lock stale hizo fallar en silencio el stash-create del marcador (advance -> HEAD, over-scope).
    # El foco debe advertir que hay que dejar terminar el fork y limpiar un lock stale antes de las ops
    # del marcador. Guard: la seccion menciona index.lock.
    Assert ($cr -match '(?i)index\.lock') `
      "$($p.label)/${rel}: el foco advierte de la contencion de index.lock del fork vs el marcador"
  }
}

# AC5 — el loop invoca el pase al cerrar, tanto por limpio como por techo de turnos. Vive en
# /review-loop (command + SKILL), sobre las 4 copias (repo + 3 skills).
$loopPairs = @(
  @{ label = "repo"; files = @(
      (Join-Path $repo ".claude\commands\review-loop.md"),
      (Join-Path $repo ".agents\skills\review-loop\SKILL.md")
  ) }
)
foreach ($s in $skills) {
  $scaffold = Join-Path $s.FullName "assets\scaffold"
  $loopPairs += @{ label = $s.Name; files = @(
      (Join-Path $scaffold ".claude\commands\review-loop.md"),
      (Join-Path $scaffold ".agents\skills\review-loop\SKILL.md")
  ) }
}

foreach ($p in $loopPairs) {
  foreach ($f in $p.files) {
    $rel = Split-Path $f -Leaf
    if (-not (Test-Path -LiteralPath $f)) { Assert $false "$($p.label): existe review-loop ($rel)"; continue }
    $txt = [IO.File]::ReadAllText($f)
    $coh = Section $txt 'At close: the coherence pass'

    Assert ($coh -ne "") "$($p.label)/${rel}: el loop tiene la seccion del pase de coherencia al cierre"
    Assert ($coh -match '/slice-review --coherence') `
      "$($p.label)/${rel}: el loop invoca el pase de coherencia (/slice-review --coherence)"
    # Corre en AMBOS cierres: limpio y por techo de turnos.
    Assert ($coh -match '(?i)clean, prose-only delta, or at the turn cap') `
      "$($p.label)/${rel}: el loop corre el pase tanto por limpio como por techo de turnos"
    Assert ($coh -match '(?i)run it on \*\*every\*\* exit that closes the loop') `
      "$($p.label)/${rel}: el loop corre el pase en ambos cierres explicitamente"
    # No hay slice que leer si ningun reviewer corrio (rango vacio desde el primer turno).
    Assert ($coh -match '(?i)skip it only when no reviewer ever ran') `
      "$($p.label)/${rel}: el loop saltea el pase si ningun reviewer corrio"

    # Migracion a agnostico — el guard file-wide tambien sobre review-loop.md/SKILL, no solo la
    # seccion At close (esa la cubre review-loop-incremental.tests.ps1 via $closeSec). Simetrico con
    # el guard de slice-review.md (mas arriba): un pin reintroducido en CUALQUIER seccion del doc
    # (Opus 5, Sonnet 5, Opus 4.8, Haiku 4.5, GPT-4...) lo caza. "CLAUDE.md"/"0-100" no matchean.
    Assert (-not ($txt -match '(?i)(opus|sonnet|haiku|claude|gpt)[- ]?\d')) `
      "$($p.label)/${rel}: review-loop no pinnea ningun modelo+version (agnostico end-to-end)"

    # 08a — el loop pasa --code-review en el PASO del loop (turno 1, junto a --mutation), no solo en la
    # narrativa del header. Anclado a la seccion "The loop" (tests F2): la mencion del header podria
    # quedar mientras el paso del loop se revierte, y el assert file-wide pasaria igual.
    $theLoop = Section $txt 'The loop'
    Assert ($theLoop -match '(?i)--code-review') `
      "$($p.label)/${rel}: el loop pasa --code-review en el paso del loop (turno 1)"
    # 08a turno 2 (concurrencia; contratos) — antes de avanzar el marcador (stash create), el paso del
    # loop debe asegurar que el fork de /code-review termino y no quedo un index.lock stale, o el advance
    # falla en silencio y cae a HEAD (over-scope del proximo turno). Guard: el paso menciona index.lock.
    Assert ($theLoop -match '(?i)index\.lock') `
      "$($p.label)/${rel}: el paso del loop advierte del index.lock del fork antes de avanzar el marcador"
    # Framing (coherencia de 08a): el loop ya no afirma que el built-in /code-review no se puede lanzar
    # (la premisa caduco 2026-08-26). El error fabricado "cannot be used with Skill tool" era falso.
    Assert ($txt -notmatch '(?i)cannot be used with Skill tool') `
      "$($p.label)/${rel}: el loop ya no afirma que /code-review no es invocable (premisa caduca)"
  }
}

# --- Rigor por slice (ADR-0009) ------------------------------------------------------------------
# La lista de rutas que gobiernan al agente vive en el CLAUDE.md, en el clasificador `$govern` del hook
# y en dos lugares de las skills. Se compara como CONJUNTO de tokens: chequear un solo token dejaba
# borrar cualquier otro en verde (turno 2 del loop).
function Get-GovList([string]$txt) {
  $m = [regex]::Match($txt, '`CLAUDE\.md` anywhere((?:,\s*`[^`]+`)+)')
  if (-not $m.Success) { return '' }
  $toks = @('CLAUDE.md') + @([regex]::Matches($m.Groups[1].Value, '`([^`]+)`') | ForEach-Object { $_.Groups[1].Value })
  (@($toks | Sort-Object) -join ',')
}
function Get-HookGov([string]$hookTxt) {
  $m = [regex]::Match($hookTxt, "(?m)^\s*\`$govern\s*=\s*'([^']+)'")
  if (-not $m.Success) { return '' }
  $toks = @([regex]::Matches($m.Groups[1].Value, '\(\^\|/\)([^|]+)') | ForEach-Object { [regex]::Unescape($_.Groups[1].Value).TrimEnd('$') })
  (@($toks | Sort-Object) -join ',')
}
# "X wins over A and B" -> aristas X>A, X>B. Una precedencia escrita de otra forma da aristas faltantes
# y el assert falla: erra hacia el rojo.
function Get-PrecEdges([string]$s1) {
  $e = foreach ($m in [regex]::Matches($s1, '`(--[\w-]+)` wins? over((?:\s*(?:,|and)?\s*`--[\w-]+`)+)')) {
    foreach ($l in [regex]::Matches($m.Groups[2].Value, '`(--[\w-]+)`')) { "$($m.Groups[1].Value)>$($l.Groups[1].Value)" } }
  (@($e | Sort-Object) -join ',')
}
$expPrec = (@('--light>--mutation', '--light>--code-review', '--coherence>--light') | Sort-Object) -join ','
$claudeGov = Get-GovList ([IO.File]::ReadAllText((Join-Path $repo "CLAUDE.md")))
Assert ($claudeGov -ne '') "el CLAUDE.md declara la lista de rutas que gobiernan al agente ($claudeGov)"

# Los tres slices de review-cost-split cerraron por el techo de 5 turnos: la prosa nacia Medium y cada
# fix de prosa era delta nuevo para el turno siguiente. El loop pasa a techo de 2 turnos (1 en `light`),
# la prosa es Low en el pase de confianza y el rigor se declara por slice con el trailer `Review-Rigor:`.
# Las anclas son flags, filas de tabla y el trailer; las dos reglas de prosa no tienen otro ancla.
foreach ($p in $slicePairs) {
  foreach ($f in $p.files) {
    $rel = Split-Path $f -Leaf
    if (-not (Test-Path -LiteralPath $f)) { continue }
    $txt = [IO.File]::ReadAllText($f)
    $s1 = Section $txt 'Step 1 — Resolve what to review'
    $s4 = Section $txt 'Step 4 — Fan out parallel reviewers'
    $s5 = Section $txt 'Step 5 — Confidence pass (filter false positives)'
    Assert ($s1 -match '--light') "$($p.label)/${rel}: Step 1 parsea --light"
    Assert ($s4 -match '(?is)if `--light` was passed.*only the \*\*Bugs\*\* and \*\*Tests\*\* focuses') `
      "$($p.label)/${rel}: Step 4 reduce --light a los focos de Bugs y Tests"
    Assert ($s5 -match '(?is)only prose.*is \*\*Low\*\*') `
      "$($p.label)/${rel}: Step 5 clasifica Low el hallazgo cuyo fix es solo prosa"
    Assert ($txt -notmatch '(?i)5-turn cap') "$($p.label)/${rel}: no quedan menciones al techo de 5 turnos"
    # Turno 1 del loop: la precedencia de --light y la excepcion de la regla de prosa no tenian ancla,
    # y los mutantes que las invertian sobrevivian.
    Assert ((Get-PrecEdges $s1) -eq $expPrec) `
      "$($p.label)/${rel}: precedencia --light>{--mutation,--code-review} y --coherence>--light ($(Get-PrecEdges $s1))"
    Assert ($s4 -match '(?is)if `--light` was passed.*no\s+Mutation or Code-review focus') `
      "$($p.label)/${rel}: Step 4 no despacha mutacion ni code-review con --light"
    Assert ($s5 -match '(?is)only prose.*is \*\*Low\*\*.*Medium only when.*end user') `
      "$($p.label)/${rel}: la regla de prosa conserva su excepcion (Medium si llega a un usuario final)"
    # Una instruccion en un archivo que gobierna al agente es comportamiento, no prosa.
    Assert ((Get-GovList $s5) -eq $claudeGov) "$($p.label)/${rel}: la lista de gobierno del Step 5 es la del CLAUDE.md"
    Assert ($s5 -match '(?is)\*\*Instructions are not prose\*\*.{0,500}?is behavior and is classified like code') `
      "$($p.label)/${rel}: Step 5 clasifica como codigo las instrucciones de los archivos que gobiernan al agente"
  }
}
# El snippet de PowerShell de la seccion Rigor es la definicion operativa de `light`: se EJECUTA contra
# repos temporales, en cada una de las 8 copias. Leer su texto no alcanzaba: borrarle una guarda
# (`$closes.Count -gt 0`) o volver a leer solo HEAD pasaba en verde (turno 2 del loop).
function Init-RigRepo([string]$t) {
  git -C $t init -q -b master
  git -C $t config user.email a@b.c; git -C $t config user.name a
  git -C $t config commit.gpgsign false; git -C $t config core.hooksPath ""; git -C $t config core.excludesFile ""
  [IO.File]::WriteAllText((Join-Path $t "f.txt"), "base`n")
  git -C $t add -A; git -C $t commit -q -m base
}
function Commit-Msg([string]$t, [string]$msg) {
  $mf = New-TestTempPath $script:runRoot "msg" ".txt"
  [IO.File]::WriteAllText($mf, $msg); git -C $t commit -q --allow-empty -F $mf
}
$LC = "feat: x`n`nSlice-Close: x`nReview-Rigor: light`n"
$SC = "feat: y`n`nSlice-Close: y`n"
$PL = "wip: z`n"
$LW = "feat: v`n`nSlice-Close: v`nReview-Rigor: lightweight`n"
$AT = "feat: w`n`nSlice-Close: w`nReview-Rigor: light`n`nCo-Authored-By: A <a@b.c>`nClaude-Session: https://x`n"
$rigCases = @(
  @{ n = 'cierre light';                                pre = @();    in = @($LC);      dirty = $false; exp = $true  },
  @{ n = 'sin Slice-Close en el rango';                 pre = @();    in = @($PL);      dirty = $false; exp = $false },
  @{ n = 'mixto: standard y luego light';               pre = @();    in = @($SC, $LC); dirty = $false; exp = $false },
  @{ n = 'trailer arriba del parrafo de atribucion';    pre = @();    in = @($AT);      dirty = $false; exp = $true  },
  @{ n = 'un standard ANTES del rango no cuenta';       pre = @($SC); in = @($LC);      dirty = $false; exp = $true  },
  @{ n = 'light y despues un commit sin trailer';       pre = @();    in = @($LC, $PL); dirty = $false; exp = $false },
  @{ n = 'light con cambios trackeados sin commitear';  pre = @();    in = @($LC);      dirty = $true;  exp = $false },
  @{ n = 'Review-Rigor: lightweight no es light';       pre = @();    in = @($LW);      dirty = $false; exp = $false },
  # Rango vacio con HEAD en un cierre light: sin la guarda de rango vacio el snippet decia light.
  @{ n = 'rango vacio aunque HEAD sea un cierre light'; pre = @($LC); in = @();       dirty = $false; exp = $false }
)
foreach ($c in $rigCases) {
  $t = New-TestWorkspace $script:runRoot "rig"; Init-RigRepo $t
  foreach ($m in $c.pre) { Commit-Msg $t $m }
  $c.base = (git -C $t rev-parse HEAD).Trim()
  foreach ($m in $c.in) { Commit-Msg $t $m }
  if ($c.dirty) { [IO.File]::WriteAllText((Join-Path $t "f.txt"), "cambio`n") }
  $c.dir = $t
}
function Invoke-RigorSnippet([string]$rig, [string]$dir, [string]$base) {
  $fences = [regex]::Matches($rig, '(?s)```powershell\r?\n(.*?)\r?\n```')
  if ($fences.Count -ne 1) { return "fences=$($fences.Count)" }
  if ($fences[0].Groups[1].Value -notmatch '<range>') { return 'sin <range>' }
  Push-Location -LiteralPath $dir
  # `&` y no dot-source: temp-hygiene exige que el unico dot-source del archivo sea el del helper.
  try { return & ([scriptblock]::Create($fences[0].Groups[1].Value.Replace('<range>', $base) + "`n`$light")) }
  finally { Pop-Location }
}
foreach ($p in $loopPairs) {
  foreach ($f in $p.files) {
    $rel = Split-Path $f -Leaf
    if (-not (Test-Path -LiteralPath $f)) { continue }
    $txt = [IO.File]::ReadAllText($f)
    $rig = Section $txt 'Rigor: light or standard'
    $theLoop = Section $txt 'The loop'
    $coh = Section $txt 'At close: the coherence pass'
    Assert ($rig -match 'Review-Rigor: light') "$($p.label)/${rel}: el loop declara el trailer Review-Rigor"
    Assert ($rig -match '\|\s*`light`\s*\|\s*1\s*\|') "$($p.label)/${rel}: light tiene techo de 1 turno"
    Assert ($rig -match '\|\s*`standard` \(default\)\s*\|\s*2\s*\|') `
      "$($p.label)/${rel}: standard es el default, con techo de 2 turnos"
    Assert ($rig -match '(?i)promotes it to `standard`') "$($p.label)/${rel}: un High en light promueve el slice a standard"
    Assert ($theLoop -match '--light') "$($p.label)/${rel}: el paso del loop pasa --light en un slice light"
    Assert ($theLoop -match '(?i)delta is only prose') "$($p.label)/${rel}: el loop cierra si el delta sin revisar es solo prosa"
    Assert ($theLoop -notmatch '(?i)5 turns have run') "$($p.label)/${rel}: el techo ya no es de 5 turnos"
    Assert ($coh -match '(?i)a `light` loop skips it') "$($p.label)/${rel}: un loop light saltea el pase de coherencia"
    Assert ($txt -notmatch '(?i)5-turn cap|cap of 5 turns') "$($p.label)/${rel}: no quedan menciones al techo de 5 turnos"
    # El rigor se decide una vez, en el turno 1, sobre TODOS los commits del rango, y un rango sin
    # Slice-Close: es standard (el push y la red de ~400 lineas no pueden caer en light).
    Assert ($rig -match '(?i)once, on turn 1') "$($p.label)/${rel}: el rigor se decide una vez, en el turno 1"
    Assert ($rig -match '(?is)newest commit in the unreviewed range \(HEAD\) carries a\s+`Slice-Close:` line, \*\*every\*\*') `
      "$($p.label)/${rel}: light exige que HEAD sea un Slice-Close y que todos los del rango declaren light"
    Assert ($rig -match '(?i)If `range` exited 2, the rigor is `standard`') "$($p.label)/${rel}: con el rango en exit 2 el rigor es standard"
    foreach ($c in $rigCases) {
      $got = Invoke-RigorSnippet $rig $c.dir $c.base
      Assert (($got -is [bool]) -and $got -eq $c.exp) "$($p.label)/${rel}: rigor '$($c.n)' -> $($c.exp) (dio $got)"
    }
    # Un High que promueve el slice hace arreglar tambien los Medium de ese turno: el turno 2 los revisa.
    Assert ($rig -match "(?is)fix the High and that turn's\s+real Medium findings") "$($p.label)/${rel}: la promocion arregla tambien los Medium del turno"
    Assert ($theLoop -match "(?is)When a High promotes the slice, fix that turn's\s+real Medium findings too") `
      "$($p.label)/${rel}: el paso 4 arregla los Medium de un slice promovido"
    Assert ($rig -notmatch 'trailers:key') "$($p.label)/${rel}: el rigor no se lee con el parser de trailers de git (solo lee el ultimo parrafo)"
    # El techo vive en un solo lugar, la tabla; la condicion de corte la cita en vez de repetir el numero.
    Assert ($theLoop -match '(?i)turn cap in the \*\*Rigor\*\* table') "$($p.label)/${rel}: la condicion de corte cita la tabla de rigor"
    Assert ($theLoop -notmatch '(?i)\b[2-9]\b\s+(turns?\s+)?in\s+`standard`') "$($p.label)/${rel}: la condicion de corte no repite un numero de turnos"
    # Que se arregla y que no.
    Assert ($theLoop -match '\*\*Medium or High\*\*') "$($p.label)/${rel}: standard arregla Medium y High"
    Assert ($theLoop -match '(?i)in `light`, \*\*High only\*\*') "$($p.label)/${rel}: light arregla solo High (sus Medium se reportan)"
    Assert ($theLoop -match '(?i)Low findings are reported, not fixed') "$($p.label)/${rel}: los Low se reportan y no se arreglan"
    Assert ($theLoop -match '(?is)do not re-edit.*unless the new finding about it scored Medium or High') `
      "$($p.label)/${rel}: la prohibicion de re-editar prosa de un turno previo cede ante un Medium"
    # El cierre por prosa excluye los archivos que gobiernan al agente.
    Assert ((Get-GovList $theLoop) -eq $claudeGov) "$($p.label)/${rel}: la condicion de corte por prosa excluye la lista del CLAUDE.md"
    Assert ($theLoop -match '(?is)governing file is behavior,?\s+so it\s+keeps the next turn') `
      "$($p.label)/${rel}: editar un archivo que gobierna al agente mantiene el turno siguiente"
    # light tambien ancla el slice, y todo cierre que no sea por cap limpia el ancla.
    Assert ($theLoop -match '(?i)A `light` loop runs\s+`open`') "$($p.label)/${rel}: un loop light tambien corre -Action open"
    Assert ($coh -match '(?i)prose-only delta, or at the turn cap') "$($p.label)/${rel}: la coherencia corre tambien en el cierre por prosa"
    # Cada cierre se nombra: limpio, por prosa o por cap. -Action close corre en los dos primeros; la
    # parada bloqueada y el rango vacio del turno 1 no son cierres.
    Assert ($coh -match '(?i)Name the close before acting on it') "$($p.label)/${rel}: el cierre se nombra antes de actuar"
    Assert ($coh -match 'Run `-Action close` on a \*\*clean\*\* or \*\*prose-only\*\* close only') `
      "$($p.label)/${rel}: -Action close corre en el cierre limpio o por prosa"
    Assert ($coh -match '(?is)Do \*\*not\*\* run it\s+on a cap close, a blocked stop, or a first-turn empty range') `
      "$($p.label)/${rel}: -Action close no corre en cap, parada bloqueada ni rango vacio del turno 1"
    Assert ($coh -match '(?is)\*\*clean close\*\*.{0,200}?even when that review was the cap turn') `
      "$($p.label)/${rel}: un turno limpio es cierre limpio aunque sea el del cap"
    Assert ($coh -match '(?is)\*\*cap close\*\*.{0,300}?prose-only fix delta\s+left by that last turn is still a cap close') `
      "$($p.label)/${rel}: un delta de prosa del ultimo turno sigue siendo cierre por cap"
    Assert ($theLoop -match '(?is)empty \*\*with exit 0\*\*.{0,200}?that\s+is a \*\*clean close\*\*') `
      "$($p.label)/${rel}: el rango vacio tras un turno revisado es cierre limpio"
    Assert ($theLoop -match '(?is)close\s+it as the stop conditions and the At close section say') `
      "$($p.label)/${rel}: el paso 1 remite el cierre a las condiciones de corte y a At close"
  }
}

# El techo tambien vive en el hook, el CLAUDE.md, el AI_DEVELOPMENT_WORKFLOW y tdd. Ninguna suite los
# leia: un revert simetrico a "5-turn cap" en las copias pasaba mirror en verde.
$capRoots = @($repo) + @($skills | ForEach-Object { Join-Path $_.FullName "assets\scaffold" })
$capDocs = @()
foreach ($pre in $capRoots) {
  $capDocs += @(
    (Join-Path $pre ".claude\hooks\review-loop-trigger.ps1"),
    (Join-Path $pre "CLAUDE.md"),
    (Join-Path $pre "docs\ai-workflow\AI_DEVELOPMENT_WORKFLOW.md"),
    (Join-Path $pre ".claude\commands\tdd.md"),
    (Join-Path $pre ".agents\skills\tdd\SKILL.md")
  )
}
Assert ($capDocs.Count -eq 20) "se arman 20 rutas (4 raices x 5 docs) ($($capDocs.Count))"
foreach ($f in $capDocs) {
  $rel = $f.Substring($repo.Length).TrimStart('\')
  if (-not (Test-Path -LiteralPath $f)) { Assert $false "existe $rel"; continue }
  $txt = [IO.File]::ReadAllText($f)
  Assert ($txt -match '(?i)(turn cap|tope de turnos):\s*2\b[^.]{0,60}?\b1\b[^.]{0,60}?Review-Rigor: light') `
    "${rel}: cita el techo nuevo (2, o 1 en light)"
  Assert ($txt -notmatch '(?i)5-turn cap|cap of 5 turns|tope de 5 turnos|hard cap of 5|5 turns have run') `
    "${rel}: no cita el techo de 5 turnos"
}
# El CLAUDE.md no reescribe la regla de prosa sin su excepcion: remite al Step 5.
foreach ($pre in $capRoots) {
  $f = Join-Path $pre "CLAUDE.md"
  $rel = $f.Substring($repo.Length).TrimStart('\')
  if (-not (Test-Path -LiteralPath $f)) { Assert $false "existe $rel"; continue }
  $txt = [IO.File]::ReadAllText($f)
  Assert ($txt -match 'scored per `/slice-review` Step 5') "${rel}: la regla de prosa remite al Step 5 de /slice-review"
  Assert ($txt -notmatch '(?i)only prose is Low and never blocks') "${rel}: no afirma que toda prosa es Low sin excepcion"
}
# La lista de gobierno del CLAUDE.md es la que clasifica el hook, en cada raiz; y el hook no le dice al
# agente que el rigor sale de "el commit": sale del slice, sobre todo el rango.
foreach ($pre in $capRoots) {
  $cF = Join-Path $pre "CLAUDE.md"; $hF = Join-Path $pre ".claude\hooks\review-loop-trigger.ps1"
  if (-not (Test-Path -LiteralPath $cF) -or -not (Test-Path -LiteralPath $hF)) { Assert $false "existe CLAUDE.md/hook en $pre"; continue }
  $hTxt = [IO.File]::ReadAllText($hF)
  $cg = Get-GovList ([IO.File]::ReadAllText($cF))
  Assert ($cg -ne '' -and $cg -eq (Get-HookGov $hTxt)) "${pre}: la lista de gobierno del CLAUDE.md coincide con `$govern del hook ($cg)"
  Assert ($hTxt -match "(?i)(si el slice declara|if the slice declares) 'Review-Rigor: light'") "${pre}: el hook atribuye el rigor al slice"
  Assert ($hTxt -notmatch "(?i)(si el commit declara|if the commit declares)") "${pre}: el hook no atribuye el rigor a un commit"
}

# --- 08b: framing en AI_DEVELOPMENT_WORKFLOW.md (el unico doc no-par que se copia al scaffold) ------
# El AC de 08b ("ningun archivo del scaffold afirma que /code-review es human-only") descansaba, para
# este archivo, en un chequeo a mano: el guard de framing de 08a solo cubre los pares slice/loop, y
# mirror.tests.ps1 solo exige byte-identidad ENTRE los 3 scaffolds (una reintroduccion simetrica de la
# premisa pasa mirror verde, y la copia repo-root ni figura ahi). AI_DEVELOPMENT_WORKFLOW.md es el unico
# doc que 08b corrigio a mano y que se copia a TODOS los proyectos bootstrapeados, asi que el invariante
# se blinda aca sobre las 4 copias (repo + 3 scaffolds), simetrico con el guard de $loopPairs.
# --- Score the FIX: el pase de confianza puntua el ARREGLO, no solo el hallazgo ---
# Medido dos veces (2026-09-05 y 2026-09-10): hallazgos certeros (92/92/80) cuyo arreglo igual
# habria empeorado el codigo, y dos veces en que el arreglo que proponian los REVIEWERS movia el
# problema de lugar (uno invertia el caso emblematico). La convergencia de focos valida el HALLAZGO,
# no el ARREGLO. Vivio como parche local (PATCH:prose-churn, 2026-09-06) y se perdio al revertirlo;
# esto lo sube al canonico sin los marcadores del parche. Ver ADR-0010.
foreach ($p in $slicePairs) {
  foreach ($f in $p.files) {
    $rel = Split-Path $f -Leaf
    if (-not (Test-Path -LiteralPath $f)) { continue }
    $txt = [IO.File]::ReadAllText($f)
    $s5  = Section $txt 'Step 5 — Confidence pass (filter false positives)'

    # Las tres preguntas viven en Step 5 (donde corre el scorer), no sueltas en el archivo.
    # 1 — el hecho se VERIFICA CORRIENDO algo, no leyendo (las afirmaciones sobre datos se miden).
    Assert ($s5 -match '(?i)running a command against the real code') `
      "$($p.label)/${rel}: Step 5 exige verificar el hecho corriendo un comando (no leyendo)"
    # 2 — el REEMPLAZO propuesto se chequea igual que el hecho. Es el corazon de la regla: sin esto,
    #     el scorer aprueba un arreglo falso adosado a un hallazgo verdadero.
    Assert ($s5 -match '(?i)check the \*replacement\* the same way') `
      "$($p.label)/${rel}: Step 5 chequea el reemplazo propuesto igual que el hecho"
    # 3 — arreglar 1 de N ocurrencias identicas implica haber auditado las otras N-1.
    Assert ($s5 -match '(?i)N-1') `
      "$($p.label)/${rel}: Step 5 exige consistencia con las demas ocurrencias identicas"

    # El corte tiene DIENTES: fallar (2) o (3) baja el puntaje bajo 60 aunque (1) sea certero.
    # Anclado al VINCULO entre el fallo y el corte: un texto que mencione ambos por separado no
    # expresa la regla.
    Assert ($s5 -match '(?is)fails \(2\) or \(3\).{0,160}below 60') `
      "$($p.label)/${rel}: fallar (2) o (3) se descarta bajo 60 aunque (1) sea certero"
    # ...y el descarte NO depende de la certeza del hecho.
    Assert ($s5 -match '(?is)however certain \(1\) is') `
      "$($p.label)/${rel}: el descarte por (2)/(3) es independiente de la certeza de (1)"

    # Contra-argumento de alcance: defecto DEL delta vs. condicion preexistente que el delta ilumina.
    # \s+ porque la frase esta envuelta a 100 columnas en el doc: el salto de linea cae justo ahi.
    Assert ($s5 -match '(?is)pre-existing\s+condition the delta merely illuminated') `
      "$($p.label)/${rel}: Step 5 le da al scorer el contra-argumento de alcance (delta vs. preexistente)"

    # Es canonico, no un parche temporal: los marcadores del override local no viajan al scaffold.
    Assert ($txt -notmatch 'PATCH:prose-churn') `
      "$($p.label)/${rel}: la regla entra como canonico, sin los marcadores del parche temporal"
  }
}

$workflowDocs = @(@{ label = "repo"; file = (Join-Path $repo "docs\ai-workflow\AI_DEVELOPMENT_WORKFLOW.md") })
foreach ($s in $skills) {
  $workflowDocs += @{ label = $s.Name; file = (Join-Path $s.FullName "assets\scaffold\docs\ai-workflow\AI_DEVELOPMENT_WORKFLOW.md") }
}
foreach ($p in $workflowDocs) {
  $rel = "docs/ai-workflow/AI_DEVELOPMENT_WORKFLOW.md"
  if (-not (Test-Path -LiteralPath $p.file)) { Assert $false "$($p.label): existe $rel"; continue }
  $txt = [IO.File]::ReadAllText($p.file)
  # Guard de framing: la premisa caduca ("restricted to human invocation") NO puede reaparecer.
  Assert ($txt -notmatch '(?i)restricted to human invocation') `
    "$($p.label)/${rel}: no afirma que /code-review es human-only (premisa caduca)"
  # Positivo: describe el ensemble real del turno 1 (que el built-in se suma como reviewer), o el guard
  # de arriba pasaria verde con la frase simplemente borrada, sin la framing correcta en su lugar.
  Assert ($txt -match '(?i)folds in the built-in `/code-review`') `
    "$($p.label)/${rel}: documenta que el turno 1 suma el built-in /code-review (ensemble)"
}

Remove-TestRunRoot $script:runRoot
if ($script:failures -eq 0) { Write-Host "TODOS LOS TESTS PASARON"; exit 0 }
else { Write-Host "$($script:failures) test(s) FALLARON"; exit 1 }
