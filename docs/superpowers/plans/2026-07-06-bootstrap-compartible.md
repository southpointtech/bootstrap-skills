# Bootstrap Compartible — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Crear la skill `bootstrap-ai-project` (variante compartible sin Zoho/DOMO/identidad de Martín), anglicizar la prosa del scaffold canónico, y montar el pipeline de publicación al repo público con gate anti-fuga.

**Architecture:** Tercera skill espejada junto a `bootstrap-personal-project` / `bootstrap-southpoint-project` (enfoque A del spec `docs/superpowers/specs/2026-07-06-bootstrap-compartible-design.md`). Tres slices en feature branches: (1) anglicización del canónico + test de espejado; (2) skill nueva + test de leaks + retoques a upgrade-bootstrap; (3) export al repo público + README/install.

**Tech Stack:** PowerShell 7+ (pwsh), tests estilo "runner sin Pester" (patrón `tests/copy-scaffold.tests.ps1`), tooling existente `tools/gen-manifest.ps1` / `tools/sync-skills.ps1`.

## Global Constraints

- Cada slice va en su **feature branch** (`feat/<slice>`); el hook `review-loop-trigger` dispara `/review-loop` en cada commit — obedecerlo sin preguntar hasta que cierre (cero findings medium/high o tope de 5 turnos).
- Slice ≤ ~400 líneas de diff de *lógica* (archivos copiados byte-idénticos del scaffold no cuentan como lógica).
- `.bootstrap-manifest.json` es **generado**: siempre `tools/gen-manifest.ps1 -SkillDir <skill>` tras tocar un scaffold, nunca a mano.
- Espejado: los archivos no-variante deben quedar **byte-idénticos entre las 3 skills** `bootstrap-*-project`. Lista de archivos que SÍ pueden divergir (allowlist, rutas relativas a la skill): `SKILL.md`, `assets/scaffold/CLAUDE.md`, `assets/scaffold/.bootstrap-manifest.json`, `assets/scaffold/docs/ai-workflow/AI_DEVELOPMENT_WORKFLOW.md`, `assets/scaffold/docs/ai-workflow/DEPLOYMENT_RULES.md`, `assets/scaffold/docs/ai-workflow/PRD_TEMPLATE.md`, `assets/scaffold/docs/ai-workflow/QA_CHECKLIST.md`, `assets/scaffold/docs/ai-workflow/TASK_TEMPLATE.md`, `assets/scaffold/docs/agents/issue-tracker.md`, `scripts/gen-mcp-json.ps1`.
- **NO tocar las frases-trigger en español de los frontmatter `description:`** de las skills del scaffold (decisión aprobada: triggers bilingües en las 3 variantes). Solo se traduce prosa de cuerpo, comentarios de scripts y mensajes.
- Marcadores de fuga (case-insensitive, substring): `zoho`, `domo`, `MartinDele703`, `martin.deleon`, `southpoint`. Fuente única: `tools/leak-markers.txt` (se crea en Slice 2).
- Rastros de testeo (dirs temporales) se borran al terminar cada test/eval.
- Mensajes de commit en español, estilo conventional-commits del repo (`feat(...)`, `docs(...)`, `test(...)`).

## File Structure

| Archivo | Slice | Acción |
|---|---|---|
| `tests/mirror.tests.ps1` | 1 | Crear — byte-identidad entre skills `bootstrap-*-project` |
| `skills/{bootstrap-personal-project,bootstrap-southpoint-project}/assets/scaffold/.agents/skills/review-loop/SKILL.md` | 1 | Traducir secciones "Modo PR" / "Modo commit" |
| `.../assets/scaffold/.claude/commands/review-loop.md` (ambas skills) | 1 | Traducir (mismo bloque) |
| `.../assets/scaffold/.claude/hooks/review-loop-trigger.ps1` (ambas) | 1 | Traducir comentarios + mensaje |
| `.../assets/scaffold/.claude/hooks/alignment-gate.ps1` (ambas) | 1 | Traducir + fix typo `proceds` |
| `.../assets/scaffold/CLAUDE.md` (ambas) | 1 | Traducir 3 bullets de "Agent skills" |
| `.../assets/scaffold/docs/agents/issue-tracker.md` (ambas) | 1 | Traducir línea 5 |
| `skills/{ambas}/scripts/copy-scaffold.ps1` | 1 | Traducir comentarios + throws |
| `tests/review-loop-trigger.tests.ps1` | 1 | Actualizar assert `review-loop AHORA` → `review-loop NOW` |
| `tools/leak-markers.txt` | 2 | Crear |
| `tests/shareable-leaks.tests.ps1` | 2 | Crear |
| `skills/bootstrap-ai-project/**` | 2 | Crear (copia de personal + 6 archivos divergentes) |
| `tests/gen-mcp-json.tests.ps1` | 2 | Extender con casos de la variante shareable |
| `skills/upgrade-bootstrap/SKILL.md` + `scripts/*.ps1` | 2 | Genericizar/anglicizar |
| `CLAUDE.md` (raíz del repo) | 2 | Regla de espejado 2→3 skills |
| `tests/export-shareable.tests.ps1` | 3 | Crear |
| `public/README.md`, `public/install.ps1` | 3 | Crear |
| `tools/export-shareable.ps1` | 3 | Crear |

---

## SLICE 1 — `feat/scaffold-english`: anglicización del canónico + test de espejado

Preparación: `git checkout -b feat/scaffold-english` desde `main`.

### Task 1: Test de espejado triple (`tests/mirror.tests.ps1`)

**Files:**
- Create: `tests/mirror.tests.ps1`

**Interfaces:**
- Produces: test glob-based sobre `skills/bootstrap-*-project` — cubre automáticamente la tercera skill cuando exista (Slice 2). Exit 0/1 + líneas `ok:`/`FAIL:` (patrón del repo).

- [ ] **Step 1: Escribir el test**

```powershell
# tests/mirror.tests.ps1 — runner sin Pester. Correr: pwsh -NoProfile -File tests/mirror.tests.ps1
# Espejado entre las skills bootstrap-*-project: mismo SET de archivos y byte-identidad
# en todo lo que no está en la allowlist de divergencia (archivos de variante).
$ErrorActionPreference = "Stop"
$repo = Split-Path $PSScriptRoot -Parent
$skills = @(Get-ChildItem (Join-Path $repo "skills") -Directory | Where-Object Name -like "bootstrap-*-project")
$script:failures = 0
function Assert($cond, $msg) {
  if ($cond) { Write-Host "ok:   $msg" } else { Write-Host "FAIL: $msg"; $script:failures++ }
}

Assert ($skills.Count -ge 2) "hay al menos 2 skills bootstrap-*-project ($($skills.Count))"

# Archivos de variante: PUEDEN divergir entre skills. Todo lo demás debe ser byte-idéntico.
$allow = @(
  "SKILL.md",
  "assets/scaffold/CLAUDE.md",
  "assets/scaffold/.bootstrap-manifest.json",
  "assets/scaffold/docs/ai-workflow/AI_DEVELOPMENT_WORKFLOW.md",
  "assets/scaffold/docs/ai-workflow/DEPLOYMENT_RULES.md",
  "assets/scaffold/docs/ai-workflow/PRD_TEMPLATE.md",
  "assets/scaffold/docs/ai-workflow/QA_CHECKLIST.md",
  "assets/scaffold/docs/ai-workflow/TASK_TEMPLATE.md",
  "assets/scaffold/docs/agents/issue-tracker.md",
  "scripts/gen-mcp-json.ps1"
)

function RelFiles($skillDir) {
  Get-ChildItem $skillDir -Recurse -File -Force | ForEach-Object {
    [IO.Path]::GetRelativePath($skillDir, $_.FullName) -replace '\\', '/'
  } | Sort-Object
}

$ref = $skills[0]
$refFiles = @(RelFiles $ref.FullName)
foreach ($other in ($skills | Select-Object -Skip 1)) {
  $otherFiles = @(RelFiles $other.FullName)
  $diffSet = @(Compare-Object $refFiles $otherFiles | ForEach-Object { $_.InputObject })
  Assert ($diffSet.Count -eq 0) "$($other.Name): mismo set de archivos que $($ref.Name) (diff: $($diffSet -join ', '))"
  foreach ($rel in $refFiles) {
    if ($allow -contains $rel) { continue }
    $a = Join-Path $ref.FullName   $rel
    $b = Join-Path $other.FullName $rel
    if (-not (Test-Path -LiteralPath $b)) { continue }  # ya reportado por el diff de set
    $same = (Get-FileHash -LiteralPath $a).Hash -eq (Get-FileHash -LiteralPath $b).Hash
    Assert $same "$($other.Name): $rel byte-idéntico a $($ref.Name)"
  }
}

if ($script:failures -eq 0) { Write-Host "TODOS LOS TESTS PASARON"; exit 0 }
else { Write-Host "$($script:failures) test(s) FALLARON"; exit 1 }
```

- [ ] **Step 2: Correrlo — debe pasar YA (las 2 skills existentes ya están espejadas)**

Run: `pwsh -NoProfile -File tests/mirror.tests.ps1`
Expected: `TODOS LOS TESTS PASARON`, exit 0. (No es un test RED de TDD: es un guard que congela el invariante antes de tocar el scaffold.)

- [ ] **Step 3: Commit**

```powershell
git add tests/mirror.tests.ps1
git commit -m "test(mirror): byte-identidad entre skills bootstrap-*-project con allowlist de variante"
```

### Task 2: Traducir el bloque español de review-loop (SKILL.md + comando, ambas skills)

**Files:**
- Modify: `skills/bootstrap-personal-project/assets/scaffold/.agents/skills/review-loop/SKILL.md:28-47`
- Modify: `skills/bootstrap-personal-project/assets/scaffold/.claude/commands/review-loop.md` (mismo bloque, líneas ~28-47)
- Modify: los 2 archivos homólogos en `skills/bootstrap-southpoint-project/`

**Interfaces:**
- Consumes: nada. NO tocar el frontmatter `description:` (trigger bilingüe).
- Produces: los 4 archivos quedan byte-idénticos entre skills (verificado por mirror.tests).

- [ ] **Step 1: En los 4 archivos, reemplazar el bloque en español por su traducción**

Bloque viejo (idéntico en los 4 archivos):

```markdown
## Modo PR (cuando lo dispara el hook)

Si llegaste acá porque el hook `review-loop-trigger` te lo pidió tras un `gh pr create` / `git push`, revisá el **diff del branch** (lo que el PR introduce sobre su base), no el working-tree:

```powershell
git diff <base>...HEAD --stat   # <base> es la rama base del PR (main/develop/etc., la que indicó el hook)
```

Usá ese mismo rango (`git diff <base>...HEAD`) como entrada de cada `/code-review` del loop. El modo working-tree (`git diff` sin rango) sigue siendo el default para invocación manual sobre cambios sin commitear.

## Modo commit / local (cuando lo dispara un `git commit`)

Si llegaste acá tras un `git commit` (típico en repos locales sin remote), revisá el diff del slice recién cerrado. Si el branch tiene una base resoluble, usá el rango del branch; si no, revisá el último commit:

```powershell
git --no-pager diff <base>...HEAD --stat   # si hay base (sirve también con base local, sin remote)
git --no-pager show --stat HEAD            # fallback: solo el último commit
```

Si el commit es solo un test que falla a propósito (RED de TDD) y todavía no hay código de implementación que revisar, cerrá el loop sin acción: no hay nada que arreglar aún.
```

Bloque nuevo (exacto, en los 4):

```markdown
## PR mode (when triggered by the hook)

If you got here because the `review-loop-trigger` hook asked for it after a `gh pr create` / `git push`, review the **branch diff** (what the PR introduces over its base), not the working tree:

```powershell
git diff <base>...HEAD --stat   # <base> is the PR's base branch (main/develop/etc., the one the hook reported)
```

Use that same range (`git diff <base>...HEAD`) as the input of every `/code-review` in the loop. Working-tree mode (`git diff` with no range) remains the default for manual invocation over uncommitted changes.

## Commit / local mode (when triggered by a `git commit`)

If you got here after a `git commit` (typical in local repos with no remote), review the diff of the slice just closed. If the branch has a resolvable base, use the branch range; otherwise review the last commit:

```powershell
git --no-pager diff <base>...HEAD --stat   # if there is a base (also works with a local base, no remote)
git --no-pager show --stat HEAD            # fallback: last commit only
```

If the commit is only a deliberately failing test (TDD RED) and there is no implementation code to review yet, close the loop with no action: there is nothing to fix yet.
```

Nota: `.claude/commands/review-loop.md` NO es byte-idéntico al SKILL.md (difieren fuera de este bloque) — aplicar el reemplazo de bloque, no copiar un archivo sobre el otro.

- [ ] **Step 2: Verificar espejado y que no quede español de cuerpo**

Run: `pwsh -NoProfile -File tests/mirror.tests.ps1`
Expected: PASA.
Run (verificación de residuos): `Get-ChildItem skills\bootstrap-*-project\assets\scaffold -Recurse -File -Force | Select-String -Pattern 'llegaste|revisá|usá el|cerrá' | Where-Object { $_.Line -notmatch '^description:' }`
Expected: sin resultados.

- [ ] **Step 3: Commit**

```powershell
git add skills/bootstrap-personal-project skills/bootstrap-southpoint-project
git commit -m "docs(scaffold): review-loop en inglés (cuerpo; triggers bilingües intactos)"
```

### Task 3: Traducir los hooks + fix `proceds` + actualizar test del trigger

**Files:**
- Modify: `skills/{ambas}/assets/scaffold/.claude/hooks/review-loop-trigger.ps1`
- Modify: `skills/{ambas}/assets/scaffold/.claude/hooks/alignment-gate.ps1`
- Modify: `tests/review-loop-trigger.tests.ps1:35`

**Interfaces:**
- Consumes: `tests/review-loop-trigger.tests.ps1` asserta hoy `$o -match "review-loop AHORA"`; `tests/alignment-gate.tests.ps1` asserta `deny` + `grill` (sobrevive a la traducción sin cambios).
- Produces: mensajes de hook en inglés; el trigger emite `Run /review-loop NOW`.

- [ ] **Step 1: Actualizar PRIMERO el assert del test (RED)**

En `tests/review-loop-trigger.tests.ps1` línea 35, reemplazar:

```powershell
Assert (($o -match "additionalContext") -and ($o -match "review-loop AHORA")) "git commit en feature branch dispara con mensaje imperativo"; Remove-Item -Recurse -Force $t
```

por:

```powershell
Assert (($o -match "additionalContext") -and ($o -match "review-loop NOW")) "git commit en feature branch dispara con mensaje imperativo"; Remove-Item -Recurse -Force $t
```

Run: `pwsh -NoProfile -File tests/review-loop-trigger.tests.ps1`
Expected: FAIL en ese assert (el hook todavía dice AHORA).

- [ ] **Step 2: Traducir `review-loop-trigger.ps1` en AMBAS skills**

Reemplazos exactos (comentarios y mensaje; el código no cambia):

| Viejo | Nuevo |
|---|---|
| Header líneas 1-4 completas | `# PostToolUse hook (Bash matcher). If the executed command was gh pr create, git push or`<br>`# git commit on a branch that is NOT the base, injects into Claude the order to run /review-loop`<br>`# over the slice diff. Dedupes by SHA in .git/review-loop-state.json so the same commit never`<br>`# fires twice. Any non-applicable path ends in a silent exit 0.` |
| `# 1. Leer el evento del hook por stdin` | `# 1. Read the hook event from stdin` |
| `# 2. Filtrar: gh pr create / git push / git commit` | `# 2. Filter: gh pr create / git push / git commit` |
| `# excluye git commit-graph y similares` | `# excludes git commit-graph and the like` |
| `# 3. Ubicarse en el repo (cwd del evento)` | `# 3. Locate the repo (event cwd)` |
| `# no es repo git` | `# not a git repo` |
| `# 4. Resolver la base branch (NO hardcodear main)` | `# 4. Resolve the base branch (do NOT hardcode main)` |
| `# 5. No revisar la base contra sí misma` | `# 5. Never review the base against itself` |
| `# 6. Dedupe por SHA del HEAD del branch` | `# 6. Dedupe by the branch HEAD SHA` |
| `# ya disparado para este commit` | `# already fired for this commit` |
| `# 7. Inyectar la instrucción a Claude` | `# 7. Inject the instruction to Claude` |

Mensaje (líneas 67-70), versión nueva exacta:

```powershell
$msg = "You just closed a commit/slice on branch '$branch' (base '$base'). " +
       "Run /review-loop NOW over the slice diff. Do not ask whether to run it: run it. " +
       "Use 'git diff $base...HEAD' if the branch has a resolvable base, or the last commit's diff in local repos. " +
       "Do not mark the work complete until the loop closes (zero medium/high-severity findings, or the 5-turn cap)."
```

- [ ] **Step 3: Traducir `alignment-gate.ps1` en AMBAS skills (incluye fix del typo)**

Reemplazos exactos:

| Viejo | Nuevo |
|---|---|
| Header líneas 1-5 completas | `# PreToolUse hook (Edit\|Write\|MultiEdit matcher). Stops the FIRST code Edit/Write of the session`<br>`# and offers the user to align (grill) before coding. Speed bump: once per session`<br>`# (dedup by session_id in .git/alignment-gate-state.json). NON-code files (docs, *.md,`<br>`# .scratch, .agents, .claude, configs, CONTEXT.md, CLAUDE.md, .gitignore) ALWAYS pass through,`<br>`# so aligning/documenting never gets blocked. Any non-applicable path ends in a silent exit 0.` |
| `# 1. Leer el evento del hook por stdin` | `# 1. Read the hook event from stdin` |
| `# 2. Juntar el/los file_path segun la tool (Edit/Write: tool_input.file_path; MultiEdit: edits[].file_path)` | `# 2. Collect the file_path(s) per tool (Edit/Write: tool_input.file_path; MultiEdit: edits[].file_path)` |
| `# 3. Clasificar cada path: no-codigo (allowlist) vs codigo. Solo se frena si hay AL MENOS un path de codigo.` | `# 3. Classify each path: non-code (allowlist) vs code. Only stop if there is AT LEAST one code path.` |
| `# todo no-codigo: pasa libre, sin marcar la sesion` | `# all non-code: passes through without marking the session` |
| `# 4. Dedup por session_id (una sola vez por sesion). Estado junto a review-loop-state.json.` | `# 4. Dedup by session_id (once per session). State lives next to review-loop-state.json.` |
| `# ya avisado en esta sesion` | `# already warned this session` |
| `# 5. Frenar este Edit y OFRECER alinear (el hook NO ejecuta el grill; lo decide el usuario)` | `# 5. Stop this Edit and OFFER to align (the hook does NOT run the grill; the user decides)` |

Mensaje (líneas 60-64), versión nueva exacta — nótese `proceed` corrigiendo el typo `proceds` (follow-up Minor #4 del handoff):

```powershell
$msg = "Before writing code in this task: no alignment/grill has happened yet in this session " +
       "(step 1 of the workflow: Alignment/Grill -> PRD -> task planning; see CLAUDE.md). Do not keep coding on " +
       "autopilot. Offer the user: do we run /grill-me or /grill-with-docs first, or do we proceed " +
       "because this is trivial / already aligned? Wait for their decision: do NOT run the grill on your own. " +
       "If the user says continue, retry the Edit and proceed (this warning will not repeat this session)."
```

- [ ] **Step 4: Correr los tests de hooks + mirror**

Run: `pwsh -NoProfile -File tests/review-loop-trigger.tests.ps1` → Expected: PASA (GREEN).
Run: `pwsh -NoProfile -File tests/alignment-gate.tests.ps1` → Expected: PASA (asserta `deny`+`grill`, ambos sobreviven).
Run: `pwsh -NoProfile -File tests/mirror.tests.ps1` → Expected: PASA.

- [ ] **Step 5: Commit**

```powershell
git add skills/ tests/review-loop-trigger.tests.ps1
git commit -m "feat(hooks): mensajes y comentarios en inglés + fix typo proceds->proceed"
```

### Task 4: Traducir CLAUDE.md (bullets), issue-tracker.md y copy-scaffold.ps1 (ambas skills)

**Files:**
- Modify: `skills/{ambas}/assets/scaffold/CLAUDE.md` (sección `## Agent skills`)
- Modify: `skills/{ambas}/assets/scaffold/docs/agents/issue-tracker.md:5`
- Modify: `skills/{ambas}/scripts/copy-scaffold.ps1` (comentarios + throws)

**Interfaces:**
- Consumes: `tests/copy-scaffold.tests.ps1` test #6 asserta hash-igualdad personal==southpoint de `copy-scaffold.ps1` — se mantiene traduciendo AMBAS copias idénticamente.
- Produces: texto inglés que la Slice 2 hereda al copiar la skill personal.

- [ ] **Step 1: En `CLAUDE.md` de ambas skills, sección `## Agent skills`, reemplazar los 3 bullets**

| Viejo | Nuevo |
|---|---|
| `Issues técnicos viven como markdown local en ``.scratch/``. Tareas de alto nivel se registran en Zoho Projects. Ver ``docs/agents/issue-tracker.md``.` | `Technical issues live as local markdown in ``.scratch/``. High-level tasks are registered in Zoho Projects. See ``docs/agents/issue-tracker.md``.` |
| `Vocabulario por defecto (needs-triage, needs-info, ready-for-agent, ready-for-human, wontfix). Ver ``docs/agents/triage-labels.md``.` | `Default vocabulary (needs-triage, needs-info, ready-for-agent, ready-for-human, wontfix). See ``docs/agents/triage-labels.md``.` |
| `Single-context: un ``CONTEXT.md`` + ``docs/adr/`` en la raíz. Ver ``docs/agents/domain.md``.` | `Single-context: one ``CONTEXT.md`` + ``docs/adr/`` at the root. See ``docs/agents/domain.md``.` |

(Zoho queda: estas son las variantes personal/southpoint. La genericización es solo de la shareable, Slice 2.)

- [ ] **Step 2: En `docs/agents/issue-tracker.md` de ambas, línea 5**

Viejo: `Issues y PRDs técnicos para este repo viven como archivos markdown en `.scratch/`.`
Nuevo: `Technical issues and PRDs for this repo live as markdown files in `.scratch/`.`

- [ ] **Step 3: En `scripts/copy-scaffold.ps1` de ambas, traducir header, throws y comentario inline**

Header nuevo (líneas 1-9) exacto:

```powershell
# copy-scaffold.ps1 — copies assets\scaffold\ into the project file by file, merging into
# pre-existing directories. Never copies a directory as a unit: Copy-Item -Recurse onto an
# existing destination nests (docs -> docs\docs, .agents -> .agents\.agents) instead of merging.
# Paths are always literal (-LiteralPath / .NET APIs): a project with brackets in its name
# (app[v2]) breaks cmdlets that interpret wildcards.
# gitignore.txt lands as .gitignore (named that way in assets so the skill repo does not
# treat it as its own ignore file). This mapping must match tools/gen-manifest.ps1:
# the paths landing here are the keys of the .bootstrap-manifest.json consumed by upgrade-bootstrap.
# Usage: pwsh -NoProfile -File copy-scaffold.ps1 -SkillDir <this skill's dir> -ProjectDir <project root>
```

Throws: `"No existe el scaffold: $scaffold"` → `"Scaffold not found: $scaffold"`; `"No existe el proyecto: $ProjectDir"` → `"Project dir not found: $ProjectDir"`.
Comentario inline: `# File.Copy con overwrite no pisa destinos read-only/ocultos (Copy-Item -Force sí lo hacía)` → `# File.Copy with overwrite cannot clobber read-only/hidden destinations (Copy-Item -Force could)`.

- [ ] **Step 4: Correr copy-scaffold tests + mirror**

Run: `pwsh -NoProfile -File tests/copy-scaffold.tests.ps1` → Expected: PASA (incl. test #6 hash-igualdad).
Run: `pwsh -NoProfile -File tests/mirror.tests.ps1` → Expected: PASA.

- [ ] **Step 5: Regenerar manifests (el scaffold cambió) y correr la suite completa**

```powershell
pwsh -NoProfile -File tools/gen-manifest.ps1 -SkillDir skills/bootstrap-personal-project
pwsh -NoProfile -File tools/gen-manifest.ps1 -SkillDir skills/bootstrap-southpoint-project
Get-ChildItem tests/*.tests.ps1 | ForEach-Object { pwsh -NoProfile -File $_.FullName; if ($LASTEXITCODE -ne 0) { throw "FALLÓ: $($_.Name)" } }
```

Expected: todos los tests pasan.

- [ ] **Step 6: Commit y cierre del slice**

```powershell
git add skills/ 
git commit -m "docs(scaffold): prosa de CLAUDE.md/issue-tracker/copy-scaffold en inglés + manifests regenerados"
```

Cerrar el `/review-loop` que dispare el hook. Con el loop limpio, mergear a `main` (fast-forward o merge según prefiera el usuario) y borrar el branch.

---

## SLICE 2 — `feat/bootstrap-ai-project`: la skill nueva + leaks + upgrade-bootstrap genérico

Preparación: desde `main` actualizado con Slice 1, `git checkout -b feat/bootstrap-ai-project`.

### Task 5: Marcadores de fuga + test de leaks (RED)

**Files:**
- Create: `tools/leak-markers.txt`
- Create: `tests/shareable-leaks.tests.ps1`

**Interfaces:**
- Produces: `tools/leak-markers.txt` (un marcador por línea, matching case-insensitive por substring) — consumido por este test y por `tools/export-shareable.ps1` (Slice 3).

- [ ] **Step 1: Crear `tools/leak-markers.txt`** (contenido exacto, 5 líneas):

```text
zoho
domo
MartinDele703
martin.deleon
southpoint
```

- [ ] **Step 2: Escribir `tests/shareable-leaks.tests.ps1`**

```powershell
# tests/shareable-leaks.tests.ps1 — runner sin Pester. Correr: pwsh -NoProfile -File tests/shareable-leaks.tests.ps1
# Lo que se publica al repo público (bootstrap-ai-project, upgrade-bootstrap, public/) no puede
# contener marcadores de fuga (datos de Martín / Southpoint). Fuente única: tools/leak-markers.txt.
$ErrorActionPreference = "Stop"
$repo = Split-Path $PSScriptRoot -Parent
$script:failures = 0
function Assert($cond, $msg) {
  if ($cond) { Write-Host "ok:   $msg" } else { Write-Host "FAIL: $msg"; $script:failures++ }
}

$markers = @(Get-Content (Join-Path $repo "tools/leak-markers.txt") | Where-Object { $_.Trim() })
Assert ($markers.Count -eq 5) "leak-markers.txt tiene 5 marcadores"

$targets = @("skills/bootstrap-ai-project", "skills/upgrade-bootstrap", "public") |
  ForEach-Object { Join-Path $repo $_ }

Assert (Test-Path (Join-Path $repo "skills/bootstrap-ai-project")) "skills/bootstrap-ai-project existe"

foreach ($t in ($targets | Where-Object { Test-Path $_ })) {
  $hits = @()
  foreach ($f in (Get-ChildItem $t -Recurse -File -Force)) {
    $text = Get-Content -LiteralPath $f.FullName -Raw
    foreach ($m in $markers) {
      if ($text -match [regex]::Escape($m)) {
        $hits += "$([IO.Path]::GetRelativePath($repo, $f.FullName)): '$m'"
      }
    }
  }
  $hits | ForEach-Object { Write-Host "  LEAK: $_" }
  Assert ($hits.Count -eq 0) "$([IO.Path]::GetRelativePath($repo, $t)) sin marcadores de fuga"
}

if ($script:failures -eq 0) { Write-Host "TODOS LOS TESTS PASARON"; exit 0 }
else { Write-Host "$($script:failures) test(s) FALLARON"; exit 1 }
```

- [ ] **Step 3: Correr — debe FALLAR (RED)**

Run: `pwsh -NoProfile -File tests/shareable-leaks.tests.ps1`
Expected: FAIL — `skills/bootstrap-ai-project` no existe todavía, y `skills/upgrade-bootstrap` tiene hits (`bootstrap-southpoint-project` en su SKILL.md, etc.).

- [ ] **Step 4: Commit (RED de TDD)**

```powershell
git add tools/leak-markers.txt tests/shareable-leaks.tests.ps1
git commit -m "test(leaks): marcadores de fuga + test RED para lo publicable"
```

### Task 6: Crear `skills/bootstrap-ai-project`

**Files:**
- Create: `skills/bootstrap-ai-project/**` (copia de `bootstrap-personal-project` + 6 archivos divergentes)

**Interfaces:**
- Consumes: la copia hereda las traducciones de la Slice 1.
- Produces: skill completa; su manifest declara `generatedFrom: bootstrap-ai-project` (lo genera `gen-manifest.ps1`).

- [ ] **Step 1: Copiar la skill personal como base**

```powershell
Copy-Item skills/bootstrap-personal-project skills/bootstrap-ai-project -Recurse
```

- [ ] **Step 2: Reescribir `skills/bootstrap-ai-project/SKILL.md`**

Sobre la copia, aplicar estos reemplazos exactos (el resto del archivo ya está en inglés y es compartido):

**(a) Frontmatter completo (líneas 1-4) →**

```markdown
---
name: bootstrap-ai-project
description: Bootstrap a new project directory with an AI-assisted workflow scaffolding (CLAUDE.md 8-step workflow, docs/ai-workflow, docs/agents, custom skills like grill-me/tdd/to-prd, review hooks, git init). Use whenever the user says they are starting a new project and wants it set up for AI-assisted development, asks to "bootstrap this project", "set up the AI workflow", "prepare this repo", "scaffold the project structure", or wants the disciplined AI development workflow installed in a directory — even if they don't name this skill. This is per-PROJECT (run inside the project folder). To update an already-bootstrapped project use upgrade-bootstrap.
---
```

**(b) Título e intro (líneas 6-10) →**

```markdown
# Bootstrap AI Project

Installs a proven AI-assisted modus operandi in a project: the 8-step AI workflow (alignment → PRD → vertical slices → task formatting → TDD → QA → clean-context review → human approval), the workflow docs it references, the agent conventions (local issue tracker, triage labels, domain docs), and the custom skills (grill-me, grill-with-docs, tdd, to-prd, to-issues, triage, handoff, zoom-out, review-loop).

The point is that the scaffolding lands **before** requirements or code, so every later session starts governed by the workflow instead of improvising.
```

**(c) Step 4, línea del catálogo →**

Viejo: `Present the personal catalog with `AskUserQuestion` (multiSelect): **firebase**, **zoho-personal**, **github**. Let the user pick zero or more. ...`
Nuevo (solo cambia el arranque; conservar el resto de la oración desde "Let the user pick zero or more"):

```markdown
Present the catalog with `AskUserQuestion` (multiSelect): **firebase**, **github**. Let the user pick zero or more. If `AskUserQuestion` is unavailable (non-interactive or agent context), don't block: infer the servers from the project's `CLAUDE.md`/context, or pick none if it's unclear, and note the inferred choice in the Step 6 report.
```

**(d) Step 5, bloque de identidad completo (desde "Set the **local** identity" hasta el fence de cierre del bloque `git config`) →**

```markdown
This skill does not set any git identity: commits use the user's own git config. Before committing, verify one exists — `git config user.name` and `git config user.email` must both return a value. If either is missing, ask the user to configure their identity first and wait; do not invent one.
```

Además, la última línea del Step 5:

Viejo: `If it is already its own repo root, still set the local identity and commit the scaffolding files on the current branch.`
Nuevo: `If it is already its own repo root, still verify the identity and commit the scaffolding files on the current branch.`

**(e) Step 6, ejemplos de env vars →**

Viejo: `— e.g. `ZOHO_PERSONAL_MCP_URL`, `GITHUB_PERSONAL_TOKEN` (+ Docker running), or `firebase login` once.`
Nuevo: `— e.g. `GITHUB_PERSONAL_TOKEN` (+ Docker running), or `firebase login` once.`
Y en la misma oración: `(as persistent Windows user variables)` → `(as persistent environment variables)`.

- [ ] **Step 3: Genericizar `assets/scaffold/CLAUDE.md` de la skill nueva**

Reemplazos exactos sobre la copia (que ya viene traducida de Slice 1):

| Viejo | Nuevo |
|---|---|
| `4. Zoho-ready task formatting` | `4. Tracker-ready task formatting` |
| `7. Zoho Task Formatting` | `7. Task Formatting` |
| `High-level tasks are registered in Zoho Projects.` (bullet Agent skills) | `High-level tasks are registered in your issue tracker (GitHub Issues, Jira, Linear, …).` |

- [ ] **Step 4: Genericizar los docs de ai-workflow de la skill nueva**

`docs/ai-workflow/AI_DEVELOPMENT_WORKFLOW.md`:

Viejo:
```markdown
## 4. Zoho Task Formatting

Each task must be ready to copy into Zoho Projects.
```
Nuevo:
```markdown
## 4. Task Formatting

Each task must be ready to copy into your issue tracker (GitHub Issues, Jira, Linear, …).
```

`docs/ai-workflow/TASK_TEMPLATE.md`: `## Notes for Zoho` → `## Notes for Your Tracker`.

- [ ] **Step 5: Genericizar `docs/agents/issue-tracker.md` de la skill nueva**

Título: `# Issue tracker: Local Markdown + Zoho Projects` → `# Issue tracker: Local Markdown + your project tracker`.

Sección secundaria completa, vieja (desde `## Secondary: Zoho Projects` hasta el final) →

```markdown
## Secondary: Your project tracker

High-level, non-technical tasks are tracked in your team's project tracker (GitHub Issues, Jira, Linear, …). Use it for:

- Registering milestones and high-level deliverables
- Tracking progress visible to stakeholders
- Task summaries that don't need implementation detail

When creating a tracker task, keep the description at a business/product level. The detailed technical breakdown lives in `.scratch/`.
```

- [ ] **Step 6: Reescribir `scripts/gen-mcp-json.ps1` de la skill nueva** (archivo completo):

```powershell
# gen-mcp-json.ps1 — generates the project's .mcp.json from this skill's MCP catalog.
# Usage: pwsh -NoProfile -File gen-mcp-json.ps1 -ProjectDir <path> -Servers firebase,github [-Force]
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$ProjectDir,
  [string[]]$Servers = @(),
  [switch]$Force
)
$ErrorActionPreference = "Stop"

$Catalog = [ordered]@{
  "firebase" = [ordered]@{
    config          = [ordered]@{ type = "stdio"; command = "npx"; args = @("-y","firebase-tools@latest","experimental:mcp") }
    requiredEnvVars = @()
    prereqs         = @("firebase login (once)")
  }
  "github" = [ordered]@{
    config          = [ordered]@{ type = "stdio"; command = "docker"; args = @("run","-i","--rm","-e","GITHUB_PERSONAL_ACCESS_TOKEN","ghcr.io/github/github-mcp-server"); env = [ordered]@{ GITHUB_PERSONAL_ACCESS_TOKEN = '${GITHUB_PERSONAL_TOKEN}' } }
    requiredEnvVars = @("GITHUB_PERSONAL_TOKEN")
    prereqs         = @("Docker Desktop running")
  }
}

if (-not (Test-Path $ProjectDir)) { throw "ProjectDir not found: $ProjectDir" }

# -File may deliver "-Servers a,b" as a single "a,b" string: split on commas ourselves.
$selected = @($Servers | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" })

foreach ($s in $selected) {
  if (-not $Catalog.Contains($s)) {
    throw "Unknown server: '$s'. Valid: $(($Catalog.Keys) -join ', ')"
  }
}

if ($selected.Count -eq 0) {
  [pscustomobject]@{ written = $false; reason = "no servers selected" } | ConvertTo-Json -Compress
  return
}

$target = Join-Path $ProjectDir ".mcp.json"

if ((Test-Path $target) -and -not $Force) {
  throw ".mcp.json already exists in $ProjectDir (use -Force to overwrite)"
}

$serverMap = [ordered]@{}
$envVars = New-Object System.Collections.Generic.List[string]
$prereqs = New-Object System.Collections.Generic.List[string]
foreach ($key in $Catalog.Keys) {
  if ($selected -contains $key) {
    $serverMap[$key] = $Catalog[$key].config
    foreach ($e in $Catalog[$key].requiredEnvVars) { if (-not $envVars.Contains($e)) { $envVars.Add($e) } }
    foreach ($p in $Catalog[$key].prereqs)         { if (-not $prereqs.Contains($p)) { $prereqs.Add($p) } }
  }
}

$doc = [ordered]@{ mcpServers = $serverMap }
$doc | ConvertTo-Json -Depth 10 | Set-Content -Path $target -Encoding UTF8

[pscustomobject]@{
  written         = $true
  path            = $target
  servers         = @($serverMap.Keys)
  requiredEnvVars = @($envVars)
  prereqs         = @($prereqs)
} | ConvertTo-Json -Depth 5
```

- [ ] **Step 7: Regenerar el manifest de la skill nueva y correr leaks + mirror**

```powershell
pwsh -NoProfile -File tools/gen-manifest.ps1 -SkillDir skills/bootstrap-ai-project
pwsh -NoProfile -File tests/shareable-leaks.tests.ps1
pwsh -NoProfile -File tests/mirror.tests.ps1
```

Expected: mirror PASA (los divergentes están en la allowlist). Leaks: `skills/bootstrap-ai-project` puede arrojar hits residuales no previstos (p. ej. en `.claude/commands/*.md` o `skills-lock.json`) — el test lista archivo y marcador exactos. Tratar cada hit con la misma regla: prosa → genericizar en inglés como en los Steps 3-5; si un hit es ambiguo (no es prosa genericizable), PARAR y reportar al usuario en vez de inventar. `skills/upgrade-bootstrap` seguirá en FAIL hasta la Task 8 — eso es esperado acá.

- [ ] **Step 8: Commit**

```powershell
git add skills/bootstrap-ai-project
git commit -m "feat(skill): bootstrap-ai-project — variante compartible (tracker genérico, sin identidad, catálogo firebase+github)"
```

### Task 7: Extender `tests/gen-mcp-json.tests.ps1` con la variante shareable

**Files:**
- Modify: `tests/gen-mcp-json.tests.ps1`

**Interfaces:**
- Consumes: helpers existentes del archivo (`RunScript`, `Assert`, `NewTmp`).

- [ ] **Step 1: Agregar la ruta del script nuevo junto a las existentes (tras la línea de `$southpoint`)**

```powershell
$shareable  = Join-Path $repo "skills/bootstrap-ai-project/scripts/gen-mcp-json.ps1"
```

- [ ] **Step 2: Agregar al final (antes del bloque de resultado `if ($script:failures ...)`) los casos shareable**

```powershell
# --- SHAREABLE: happy path firebase+github ---
$tsh = NewTmp
$rsh = RunScript $shareable @("firebase","github") $tsh
Assert ($rsh.exit -eq 0) "shareable happy: exit 0"
$shd = Get-Content (Join-Path $tsh ".mcp.json") -Raw | ConvertFrom-Json
Assert ($null -ne $shd.mcpServers.firebase -and $null -ne $shd.mcpServers.github) "shareable happy: firebase y github presentes"
Remove-Item -Recurse -Force $tsh

# --- SHAREABLE: zoho-personal NO existe en este catalogo ---
$tsh2 = NewTmp
$rsh2 = RunScript $shareable @("zoho-personal") $tsh2
Assert ($rsh2.exit -ne 0) "shareable: zoho-personal invalido en el catalogo compartible"
Remove-Item -Recurse -Force $tsh2
```

- [ ] **Step 3: Correr**

Run: `pwsh -NoProfile -File tests/gen-mcp-json.tests.ps1`
Expected: PASA (todos los casos, viejos y nuevos).

- [ ] **Step 4: Commit**

```powershell
git add tests/gen-mcp-json.tests.ps1
git commit -m "test(gen-mcp-json): casos de la variante shareable (catalogo firebase+github)"
```

### Task 8: Genericizar `upgrade-bootstrap` (SKILL.md + strings de scripts)

**Files:**
- Modify: `skills/upgrade-bootstrap/SKILL.md`
- Modify: `skills/upgrade-bootstrap/scripts/compare-scaffold.ps1:13`
- Modify: `skills/upgrade-bootstrap/scripts/merge-settings.ps1` (5 strings)
- Modify: `skills/upgrade-bootstrap/scripts/reseal-manifest.ps1:39`

**Interfaces:**
- Consumes: `tests/shareable-leaks.tests.ps1` (hoy FAIL sobre esta skill) — GREEN al cierre de esta task.
- Produces: skill publicable; los proyectos de Martín la siguen usando igual (mecánica intacta, solo redacción).

- [ ] **Step 1: SKILL.md — description (línea 3): reemplazar las menciones concretas**

En la description, reemplazar `bootstrap-personal-project or bootstrap-southpoint-project` por `a bootstrap-*-project skill`, y `(use bootstrap-personal-project / bootstrap-southpoint-project)` por `(use your bootstrap-*-project skill)`. Conservar las frases-trigger bilingües tal cual.

- [ ] **Step 2: SKILL.md — heurística legacy (línea 22), reemplazo completo de la línea**

Viejo: `- If there is no manifest (legacy project), determine the variant: if `CLAUDE.md` mentions DOMO it's `bootstrap-southpoint-project`, otherwise `bootstrap-personal-project`. If genuinely ambiguous, ask the user.`
Nuevo: `- If there is no manifest (legacy project), ask the user which bootstrap-*-project skill this project was originally bootstrapped with, and use that skill's scaffold as canonical.`

- [ ] **Step 3: SKILL.md — guardrail en español (línea 75), reemplazo completo**

Nuevo: `- `.mcp.json` is not part of the scaffold nor the manifest, so `compare-scaffold.ps1` does not see it and this upgrade never touches it. If the project was bootstrapped before the per-project MCP feature and you want to add a `.mcp.json`, run the menu manually with `~/.claude/skills/<generatedFrom>/scripts/gen-mcp-json.ps1` (not part of the upgrade flow).`

- [ ] **Step 4: Strings de scripts, reemplazos exactos**

| Archivo | Viejo | Nuevo |
|---|---|---|
| compare-scaffold.ps1 | `"Scaffold canónico sin manifest: $canonManifestPath"` | `"Canonical scaffold has no manifest: $canonManifestPath"` |
| merge-settings.ps1 | `"settings.json no existia: copiado el canonico."` | `"settings.json did not exist: canonical copied."` |
| merge-settings.ps1 | `"settings.json canonico no es JSON valido: $CanonicalSettings"` | `"canonical settings.json is not valid JSON: $CanonicalSettings"` |
| merge-settings.ps1 | `"settings.json del proyecto no es JSON valido: $ProjectSettings"` | `"project settings.json is not valid JSON: $ProjectSettings"` |
| merge-settings.ps1 | `"El settings.json canonico no tiene hooks: nada que hacer."` | `"Canonical settings.json has no hooks: nothing to do."` |
| merge-settings.ps1 | `"Hooks integrados al settings.json del proyecto: $added entrada/s nueva/s."` | `"Hooks merged into the project settings.json: $added new entry/ies."` |
| merge-settings.ps1 | `"Todos los hooks canonicos ya presentes: nada que hacer (idempotente)."` | `"All canonical hooks already present: nothing to do (idempotent)."` |
| reseal-manifest.ps1 | `"Manifest del proyecto re-sellado: version $($canon.version), $($files.Count) archivos"` | `"Project manifest re-sealed: version $($canon.version), $($files.Count) files"` |

Si el test de leaks encuentra más hits en esta skill (p. ej. comentarios en español con "zoho"/"southpoint" que este listado no cubre), traducirlos con el mismo criterio.

- [ ] **Step 5: Correr leaks (GREEN) + suite completa**

```powershell
pwsh -NoProfile -File tests/shareable-leaks.tests.ps1
Get-ChildItem tests/*.tests.ps1 | ForEach-Object { pwsh -NoProfile -File $_.FullName; if ($LASTEXITCODE -ne 0) { throw "FALLÓ: $($_.Name)" } }
```

Expected: TODO PASA (leaks incluido — cierre del RED de la Task 5).

- [ ] **Step 6: Actualizar la regla de espejado del `CLAUDE.md` raíz del repo**

Reemplazar el bullet:

Viejo: `- Las dos skills deben mantenerse **espejadas en estructura**: si cambiás la mecánica (Step 0–5 del SKILL.md), aplicá el mismo cambio en ambas. Solo difieren en: contenido DOMO (Southpoint sí, personal no) e identidad git.`
Nuevo: `- Las tres skills bootstrap (`southpoint`, `personal`, `ai-project`) se mantienen **espejadas en estructura**: si cambiás la mecánica (Step 0–5 del SKILL.md), aplicá el mismo cambio en las tres. Solo difieren en: contenido DOMO (solo Southpoint), issue tracker (Zoho en las tuyas, genérico en ai-project), catálogo MCP, identidad git (ai-project no la toca) y SKILL.md. `tests/mirror.tests.ps1` verifica la byte-identidad de todo lo demás; `tests/shareable-leaks.tests.ps1` garantiza que lo publicable no filtre datos personales.`

- [ ] **Step 7: Commit y cierre del slice**

```powershell
git add skills/upgrade-bootstrap CLAUDE.md
git commit -m "feat(upgrade-bootstrap): redaccion generica en ingles, publicable junto a bootstrap-ai-project"
```

Cerrar el `/review-loop` del hook; con el loop limpio, mergear a `main` y borrar el branch.

---

## SLICE 3 — `feat/export-shareable`: publicación al repo público

Preparación: desde `main` actualizado, `git checkout -b feat/export-shareable`.

### Task 9: Test del export (RED)

**Files:**
- Create: `tests/export-shareable.tests.ps1`

**Interfaces:**
- Consumes: `tools/leak-markers.txt` (Slice 2).
- Produces: contrato del export: estructura del clon + gate que aborta ante marcadores.

- [ ] **Step 1: Escribir el test**

```powershell
# tests/export-shareable.tests.ps1 — runner sin Pester. Correr: pwsh -NoProfile -File tests/export-shareable.tests.ps1
# El export al repo público debe: copiar limpio las 2 skills + README + install.ps1,
# y abortar (exit != 0) si el árbol exportado contiene un marcador de fuga.
$ErrorActionPreference = "Stop"
$repo   = Split-Path $PSScriptRoot -Parent
$script = Join-Path $repo "tools/export-shareable.ps1"
$script:failures = 0
function Assert($cond, $msg) {
  if ($cond) { Write-Host "ok:   $msg" } else { Write-Host "FAIL: $msg"; $script:failures++ }
}
function NewClone {
  $d = Join-Path ([IO.Path]::GetTempPath()) ("export-test-" + [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $d | Out-Null
  git -C $d init -b main --quiet
  $d
}

# Workspaces huérfanos de corridas anteriores abortadas
Get-ChildItem ([IO.Path]::GetTempPath()) -Directory -Filter "export-test-*" | Remove-Item -Recurse -Force

# 1. Happy path: estructura completa en el clon
$t = NewClone
& pwsh -NoProfile -File $script -PublicRepoDir $t | Out-Null
Assert ($LASTEXITCODE -eq 0) "export happy: exit 0"
Assert (Test-Path "$t\README.md") "export: README.md presente"
Assert (Test-Path "$t\install.ps1") "export: install.ps1 presente"
Assert (Test-Path "$t\skills\bootstrap-ai-project\SKILL.md") "export: bootstrap-ai-project presente"
Assert (Test-Path "$t\skills\upgrade-bootstrap\SKILL.md") "export: upgrade-bootstrap presente"
$manifest = Get-Content "$t\skills\bootstrap-ai-project\assets\scaffold\.bootstrap-manifest.json" -Raw | ConvertFrom-Json
Assert ($manifest.generatedFrom -eq "bootstrap-ai-project") "export: manifest generatedFrom correcto"

# 2. Re-export sobre clon sucio: borra huérfanos dentro de skills/
"orphan" | Set-Content "$t\skills\bootstrap-ai-project\HUERFANO.txt"
& pwsh -NoProfile -File $script -PublicRepoDir $t | Out-Null
Assert ($LASTEXITCODE -eq 0) "re-export: exit 0"
Assert (-not (Test-Path "$t\skills\bootstrap-ai-project\HUERFANO.txt")) "re-export: huérfano eliminado (copia limpia)"
Remove-Item -Recurse -Force $t

# 3. Gate anti-fuga: marcador inyectado en el payload -> aborta
$t2 = NewClone
$leakSrc = Join-Path $repo "skills\bootstrap-ai-project\LEAK-TEST.md"
"contact MartinDele703 for details" | Set-Content $leakSrc
try {
  & pwsh -NoProfile -File $script -PublicRepoDir $t2 2>&1 | Out-Null
  Assert ($LASTEXITCODE -ne 0) "gate: export con marcador inyectado aborta (exit != 0)"
} finally {
  Remove-Item $leakSrc -Force
}
Remove-Item -Recurse -Force $t2

# 4. No es un clon git -> aborta
$t3 = Join-Path ([IO.Path]::GetTempPath()) ("export-test-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $t3 | Out-Null
& pwsh -NoProfile -File $script -PublicRepoDir $t3 2>&1 | Out-Null
Assert ($LASTEXITCODE -ne 0) "PublicRepoDir sin .git: aborta"
Remove-Item -Recurse -Force $t3

if ($script:failures -eq 0) { Write-Host "TODOS LOS TESTS PASARON"; exit 0 }
else { Write-Host "$($script:failures) test(s) FALLARON"; exit 1 }
```

- [ ] **Step 2: Correr — RED**

Run: `pwsh -NoProfile -File tests/export-shareable.tests.ps1`
Expected: FAIL (`tools/export-shareable.ps1` no existe).

- [ ] **Step 3: Commit**

```powershell
git add tests/export-shareable.tests.ps1
git commit -m "test(export): contrato del export al repo publico (estructura + gate anti-fuga) — RED"
```

### Task 10: `public/README.md` + `public/install.ps1`

**Files:**
- Create: `public/README.md`
- Create: `public/install.ps1`

**Interfaces:**
- Produces: contenidos que `export-shareable.ps1` copia a la raíz del clon. El README NO incluye la URL del repo (evita el marcador `MartinDele703`).

- [ ] **Step 1: Crear `public/README.md`** (contenido completo):

```markdown
# AI Project Bootstrap

Skills for [Claude Code](https://claude.com/claude-code) that install a disciplined, AI-assisted development workflow into any project — before requirements or code, so every session starts governed by the workflow instead of improvising.

## What you get

Running `bootstrap-ai-project` inside a project directory installs:

- **`CLAUDE.md`** — an 8-step operating workflow: alignment → PRD → vertical slices → task formatting → TDD → QA → clean-context review → human approval.
- **`docs/ai-workflow/`** — the workflow docs: PRD and task templates, QA checklist, deployment rules.
- **`docs/agents/`** — agent conventions: local issue tracker, triage labels, domain docs.
- **10 custom skills** (`.agents/skills/`) — grill-me, grill-with-docs, tdd, to-prd, to-issues, triage, handoff, zoom-out, review-loop, and a skills setup helper.
- **2 hooks** (`.claude/hooks/`) — `review-loop-trigger` (auto-runs an iterative code-review loop every time you commit a slice on a feature branch) and `alignment-gate` (stops the first code edit of a session and offers to align on requirements first).
- **`.bootstrap-manifest.json`** — a version manifest so `upgrade-bootstrap` can bring future scaffold improvements without clobbering your customizations.

## Requirements

- [Claude Code](https://claude.com/claude-code)
- [PowerShell 7+](https://learn.microsoft.com/powershell/scripting/install/installing-powershell) (`pwsh`) — Windows, macOS or Linux
- git

## Install

Clone this repository, then run from its root:

```powershell
pwsh -NoProfile -File install.ps1
```

This copies the skills into `~/.claude/skills/`. They become active in your next Claude Code session.

## Use

In a new or existing project directory, start Claude Code and say:

> bootstrap this project

Claude picks up the `bootstrap-ai-project` skill and walks you through the setup (project info, optional MCP servers, git). Existing projects with their own `CLAUDE.md` are **adopted**, never overwritten — the original is preserved verbatim and merged with your approval.

## Update

```powershell
git pull
pwsh -NoProfile -File install.ps1
```

Then, inside each bootstrapped project, ask Claude to run `upgrade-bootstrap` — it applies only the delta since your install and never overwrites your customizations.
```

- [ ] **Step 2: Crear `public/install.ps1`** (contenido completo):

```powershell
# install.ps1 — installs the skills into ~/.claude/skills (removing previous versions first,
# so no orphan files survive from older versions).
$ErrorActionPreference = "Stop"
$src  = Join-Path $PSScriptRoot "skills"
$dest = Join-Path $HOME ".claude" "skills"
if (-not (Test-Path $src)) { throw "skills/ directory not found next to install.ps1" }
[IO.Directory]::CreateDirectory($dest) | Out-Null
foreach ($skill in (Get-ChildItem $src -Directory)) {
    $target = Join-Path $dest $skill.Name
    if (Test-Path $target) { Remove-Item $target -Recurse -Force }
    Copy-Item $skill.FullName $target -Recurse
    $n = @(Get-ChildItem $target -Recurse -File -Force).Count
    Write-Host "Installed: $($skill.Name) ($n files)"
}
Write-Host "Done. The skills become active in your next Claude Code session."
```

- [ ] **Step 3: Verificar que `public/` no dispara leaks**

Run: `pwsh -NoProfile -File tests/shareable-leaks.tests.ps1`
Expected: PASA (el test ya escanea `public/` cuando existe).

- [ ] **Step 4: Commit**

```powershell
git add public/
git commit -m "feat(public): README e install.ps1 del repo publico"
```

### Task 11: `tools/export-shareable.ps1` (GREEN)

**Files:**
- Create: `tools/export-shareable.ps1`

**Interfaces:**
- Consumes: `tools/gen-manifest.ps1` (existente), `tools/leak-markers.txt`, `public/*`, las 2 skills.
- Produces: clon del repo público listo para revisar/commitear a mano.

- [ ] **Step 1: Escribir el script** (contenido completo):

```powershell
# export-shareable.ps1 — publica las skills compartibles a un clon local del repo público.
# Copia limpia (borra el destino de cada skill primero) + gate anti-fuga: si el árbol exportado
# contiene un marcador de tools/leak-markers.txt, aborta con exit != 0 y lista los hits.
# El commit/push en el clon es SIEMPRE manual (revisar el diff antes).
# Uso: pwsh -NoProfile -File tools/export-shareable.ps1 -PublicRepoDir <clon local del repo publico>
param([Parameter(Mandatory)][string]$PublicRepoDir)
$ErrorActionPreference = "Stop"
$repo = Split-Path $PSScriptRoot -Parent

if (-not (Test-Path (Join-Path $PublicRepoDir ".git"))) {
    throw "PublicRepoDir is not a git clone: $PublicRepoDir"
}

# 1. Manifest fresco para que el scaffold exportado lleve hashes actuales
& (Join-Path $PSScriptRoot "gen-manifest.ps1") -SkillDir (Join-Path $repo "skills/bootstrap-ai-project")

# 2. Copia limpia del payload
$skillsDest = Join-Path $PublicRepoDir "skills"
[IO.Directory]::CreateDirectory($skillsDest) | Out-Null
foreach ($name in @("bootstrap-ai-project", "upgrade-bootstrap")) {
    $dest = Join-Path $skillsDest $name
    if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
    Copy-Item (Join-Path $repo "skills/$name") $dest -Recurse
}
Copy-Item (Join-Path $repo "public/README.md")   (Join-Path $PublicRepoDir "README.md")   -Force
Copy-Item (Join-Path $repo "public/install.ps1") (Join-Path $PublicRepoDir "install.ps1") -Force

# 3. Gate anti-fuga sobre TODO el árbol exportado (menos .git)
$markers = @(Get-Content (Join-Path $PSScriptRoot "leak-markers.txt") | Where-Object { $_.Trim() })
$hits = @()
foreach ($f in (Get-ChildItem $PublicRepoDir -Recurse -File -Force | Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' })) {
    $text = Get-Content -LiteralPath $f.FullName -Raw
    foreach ($m in $markers) {
        if ($text -match [regex]::Escape($m)) { $hits += "$($f.FullName): '$m'" }
    }
}
if ($hits.Count) {
    $hits | ForEach-Object { Write-Host "LEAK: $_" }
    throw "Export aborted: $($hits.Count) leak marker hit(s). Fix the source in this repo and re-export."
}

Write-Host "Export complete. Review the diff in $PublicRepoDir, then commit and push manually."
```

- [ ] **Step 2: Correr el test del export — GREEN**

Run: `pwsh -NoProfile -File tests/export-shareable.tests.ps1`
Expected: `TODOS LOS TESTS PASARON`.

- [ ] **Step 3: Suite completa**

```powershell
Get-ChildItem tests/*.tests.ps1 | ForEach-Object { pwsh -NoProfile -File $_.FullName; if ($LASTEXITCODE -ne 0) { throw "FALLÓ: $($_.Name)" } }
```

Expected: todo PASA.

- [ ] **Step 4: Commit y cierre del slice**

```powershell
git add tools/export-shareable.ps1
git commit -m "feat(export): publicacion al repo publico con gate anti-fuga"
```

Cerrar el `/review-loop` del hook; con el loop limpio, mergear a `main` y borrar el branch.

---

## POST-MERGE (en `main`) — deploy + eval de cierre

### Task 12: Deploy local y eval manual

- [ ] **Step 1: Deployar las skills** — `pwsh -NoProfile -File tools/sync-skills.ps1`. Expected: lista las skills deployadas incluyendo `bootstrap-ai-project` con su conteo de archivos.
- [ ] **Step 2: Eval de bootstrap descartable** — en un dir temporal del scratchpad, correr el flujo de la skill nueva tal como lo haría un tercero (Step 2 copy-scaffold + Step 5 git). Verificar: 10 dirs en `.agents/skills`, `.claude/hooks/alignment-gate.ps1` y `review-loop-trigger.ps1` presentes y en inglés, `.gitignore` presente, `git config user.name --local` NO seteado por la skill, cero hits del grep de marcadores sobre el proyecto generado.
- [ ] **Step 3: Borrar el proyecto descartable** (regla del repo: sin rastros de testeo).
- [ ] **Step 4: Export real (cuando el usuario cree el repo público)** — crear `MartinDele703/ai-project-bootstrap` en GitHub es un paso MANUAL del usuario; después: clonar, `tools/export-shareable.ps1 -PublicRepoDir <clon>`, revisar diff, commit y push con la cuenta MartinDele703. NO hacerlo sin que el usuario lo pida.
- [ ] **Step 5: Nota para los proyectos existentes** — reportar al usuario que Forecasting App / este repo verán los archivos traducidos como `outdated-safe` en su próximo `/upgrade-bootstrap` (esperado, sin acción inmediata).
