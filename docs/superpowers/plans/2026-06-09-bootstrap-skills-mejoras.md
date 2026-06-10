# Bootstrap Skills — Mejoras (review-loop, PRs, anti supply-chain) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Incorporar 6 mejoras de metodología (anti supply-chain, PRs mínimos + stacked, skill `review-loop`, código-como-documentación, service layer, nota de modelo) al scaffold de ambas skills de bootstrap, espejadas.

**Architecture:** Edición de archivos de template Markdown/JSON en `skills/bootstrap-personal-project/assets/scaffold/` y `skills/bootstrap-southpoint-project/assets/scaffold/`, más una skill nueva `review-loop` autocontenida. Las dos skills se mantienen espejadas; las líneas-ancla usadas para insertar son idénticas en ambas variantes, así que cada edición se aplica con el mismo texto en personal y southpoint. No hay código ejecutable ni tests unitarios: la verificación es por `grep`/diff de contenido, conteo de archivos tras copia, y los evals del skill-creator.

**Tech Stack:** Markdown, JSON, PowerShell, git. Skills de Claude Code (`/code-review`, skill-creator).

**Spec:** `docs/superpowers/specs/2026-06-09-bootstrap-skills-mejoras-design.md`

---

## File Structure

Rutas relativas a la raíz del repo `C:\Repos\PERSONAL\Bootstrap Skills`. `P` = `skills/bootstrap-personal-project`, `S` = `skills/bootstrap-southpoint-project`.

**Archivos nuevos (idénticos en ambas skills):**
- `{P,S}/assets/scaffold/.agents/skills/review-loop/SKILL.md` — la skill review-loop.
- `{P,S}/assets/scaffold/.claude/commands/review-loop.md` — el comando `/review-loop` (idéntico al SKILL.md; no tiene sub-referencias que reajustar).

**Archivos modificados (mismas ediciones en ambas skills salvo donde se indique):**
- `{P,S}/assets/scaffold/CLAUDE.md` — Hard rules (anti supply-chain, PRs×2, código-como-doc) + Preferred project style (service layer, nota de modelo).
- `{P,S}/assets/scaffold/docs/ai-workflow/AI_DEVELOPMENT_WORKFLOW.md` — paso 3 (PRs) y paso 7 (review-loop).
- `{P,S}/assets/scaffold/docs/ai-workflow/DEPLOYMENT_RULES.md` — sección General (PRs).
- `{P,S}/assets/scaffold/docs/ai-workflow/QA_CHECKLIST.md` — During Implementation (anti supply-chain).
- `{P,S}/SKILL.md` — conteos 9→10 y enumeración de skills.

**Modificado una vez (raíz del repo):**
- `docs/TESTING.md` — assertion de conteos 9→10.

**NO se toca:** `{P,S}/assets/scaffold/skills-lock.json` (trackea solo las 9 skills upstream de `mattpocock/skills`; `review-loop` es propia y queda fuera del lockfile).

---

## Task 0: Asegurar identidad git local

**Files:** ninguno (config de repo).

- [ ] **Step 1: Setear identidad local del repo**

Run:
```powershell
git config user.name "MartinDele703"
git config user.email "martin.deleon703@gmail.com"
```

- [ ] **Step 2: Verificar**

Run: `git config user.name; git config user.email`
Expected:
```
MartinDele703
martin.deleon703@gmail.com
```

---

## Task 1: Crear la skill `review-loop` (personal + southpoint)

**Files:**
- Create: `skills/bootstrap-personal-project/assets/scaffold/.agents/skills/review-loop/SKILL.md`
- Create: `skills/bootstrap-personal-project/assets/scaffold/.claude/commands/review-loop.md`
- Create: `skills/bootstrap-southpoint-project/assets/scaffold/.agents/skills/review-loop/SKILL.md`
- Create: `skills/bootstrap-southpoint-project/assets/scaffold/.claude/commands/review-loop.md`

- [ ] **Step 1: Crear el SKILL.md en personal**

Escribir en `skills/bootstrap-personal-project/assets/scaffold/.agents/skills/review-loop/SKILL.md` exactamente:

```markdown
---
name: review-loop
description: Use when a small, finished vertical slice or PR is ready for review and you want to iterate review→fix→re-review until it is clean. Runs /code-review on the diff, fixes only real findings, re-reviews, and repeats until no medium/high-severity findings remain or a 5-turn cap is hit. Adapts the Greptile "greploop" / GP-loop to Claude Code's native reviewer (no external paid service, no PR/remote required).
---

# Review Loop

Iterate review → fix → re-review on a small change until it is clean: zero medium/high-severity findings, or a hard cap of 5 turns.

## When to use

- A vertical slice / PR is finished and ready for review.
- The diff is small enough to review reliably (see pre-flight).
- Findings are specific enough to act on, and tests/typechecks can confirm fixes.

Do not use on huge diffs (thousands of lines) or for unclear product decisions.

## Pre-flight: is the diff small enough?

Before looping, check the diff size:

```powershell
git --no-pager diff --stat
```

If the change is large (approaching thousands of lines, or well over ~400 lines), stop and split it into smaller slices / stacked PRs first. The loop loses accuracy on large diffs — both the reviewer and the coding agent.

## The loop (max 5 turns)

1. Run `/code-review` on the current diff.
2. Read the findings. Fix ONLY findings that are real and relevant to this change. Do not rewrite unrelated code.
3. For each bug fix, add or update a test when practical. Run the relevant tests/typechecks.
4. Re-run `/code-review`.
5. Repeat from step 1.

Stop when ANY of:

- No findings of medium or high severity remain.
- 5 turns reached.
- Blocked by a decision that needs a human → stop and report.

Note: `/code-review` reports findings by severity, not a numeric score — "clean" means no medium/high-severity findings remain, which is this loop's exit condition (the Greptile 5/5 score does not exist here).

## Guardrails

- Reviewers produce false positives — don't blindly accept every finding.
- Agents over-fix — touch only what the finding is about.
- A clean review means this diff looks clean, not that the product is valuable.
- Tests are the objective signal; "looks fine" is not a pass.

## Final report

- List the findings resolved this run.
- State the tests/typechecks run and their result.
- Note any finding deliberately not fixed (with reason) and any blocker that needs a human.
```

- [ ] **Step 2: Crear el command en personal (idéntico al SKILL.md)**

Copiar el mismo contenido del Step 1 a `skills/bootstrap-personal-project/assets/scaffold/.claude/commands/review-loop.md`.

Run:
```powershell
$src = "skills/bootstrap-personal-project/assets/scaffold/.agents/skills/review-loop/SKILL.md"
$dst = "skills/bootstrap-personal-project/assets/scaffold/.claude/commands/review-loop.md"
Copy-Item $src $dst
```

- [ ] **Step 3: Espejar ambos archivos a southpoint**

Run:
```powershell
$ps = "skills/bootstrap-personal-project/assets/scaffold"
$ss = "skills/bootstrap-southpoint-project/assets/scaffold"
New-Item -ItemType Directory -Force "$ss/.agents/skills/review-loop" | Out-Null
Copy-Item "$ps/.agents/skills/review-loop/SKILL.md" "$ss/.agents/skills/review-loop/SKILL.md"
Copy-Item "$ps/.claude/commands/review-loop.md" "$ss/.claude/commands/review-loop.md"
```

- [ ] **Step 4: Verificar que los 4 archivos existen y los pares son idénticos**

Run:
```powershell
$ps = "skills/bootstrap-personal-project/assets/scaffold"
$ss = "skills/bootstrap-southpoint-project/assets/scaffold"
Test-Path "$ps/.agents/skills/review-loop/SKILL.md","$ps/.claude/commands/review-loop.md","$ss/.agents/skills/review-loop/SKILL.md","$ss/.claude/commands/review-loop.md"
"--- diff SKILL vs command (personal) ---"; (Compare-Object (Get-Content "$ps/.agents/skills/review-loop/SKILL.md") (Get-Content "$ps/.claude/commands/review-loop.md")).Count
"--- diff personal vs southpoint (SKILL) ---"; (Compare-Object (Get-Content "$ps/.agents/skills/review-loop/SKILL.md") (Get-Content "$ss/.agents/skills/review-loop/SKILL.md")).Count
```
Expected: cuatro `True`, y ambos `Count` = `0` (archivos idénticos).

- [ ] **Step 5: Commit**

```powershell
git add skills/bootstrap-personal-project/assets/scaffold/.agents/skills/review-loop skills/bootstrap-personal-project/assets/scaffold/.claude/commands/review-loop.md skills/bootstrap-southpoint-project/assets/scaffold/.agents/skills/review-loop skills/bootstrap-southpoint-project/assets/scaffold/.claude/commands/review-loop.md
git commit -m "feat(scaffold): add review-loop skill (greploop adaptado a /code-review)"
```

---

## Task 2: CLAUDE.md — Hard rules + Preferred project style (ambas skills)

**Files:**
- Modify: `skills/bootstrap-personal-project/assets/scaffold/CLAUDE.md`
- Modify: `skills/bootstrap-southpoint-project/assets/scaffold/CLAUDE.md`

Las cuatro ediciones de esta tarea usan líneas-ancla idénticas en ambas variantes; aplicar el MISMO cambio en los dos archivos.

- [ ] **Step 1: Agregar reglas duras (anti supply-chain, PRs×2, código-como-doc) tras la última línea de "Hard rules"**

En AMBOS `CLAUDE.md`, reemplazar la línea:

```
- After implementation, report changed files, tests run, risks, and manual QA steps.
```

por:

```
- After implementation, report changed files, tests run, risks, and manual QA steps.
- Do not install dependencies published less than 14 days ago without explicit human approval (recent supply-chain attack mitigation). Check a new dependency's publish date before adding it.
- Keep each vertical slice a small, reviewable unit. Target ≤ ~400 lines of change per PR; a diff approaching thousands of lines breaks the review loop. If a slice exceeds ~400 lines, split it before implementing.
- When slices depend on each other, chain them as stacked PRs instead of one large PR.
- For critical libraries (or ones the agent tends to hallucinate APIs for), vendor the library's real source into the repo (e.g. `docs/vendor/<lib>/`) and point the agent at that code instead of relying on memory or possibly-stale docs.
```

- [ ] **Step 2: Agregar service layer + nota de modelo en "Preferred project style"**

En AMBOS `CLAUDE.md`, reemplazar la línea:

```
- Avoid unnecessary abstraction.
```

por:

```
- Avoid unnecessary abstraction.
- Structure logic in reusable service layers so the agent calls existing functions instead of duplicating them. Before writing new logic, check whether a service already covers it.
- Model selection: use the most capable model for business logic, architecture, and risky refactors; reserve lighter/faster models for mechanical or low-risk tasks.
```

- [ ] **Step 3: Recomendar `/review-loop` en el Workflow State Machine**

En AMBOS `CLAUDE.md`, dentro de "Recommended transitions", reemplazar:

```
- After implementation, suggest QA and clean-context review.
```

por:

```
- After implementation, suggest QA and the clean-context review via `/review-loop`.
```

- [ ] **Step 4: Verificar que las reglas nuevas + la transición están en ambos archivos**

Run:
```powershell
$f = "skills/bootstrap-personal-project/assets/scaffold/CLAUDE.md","skills/bootstrap-southpoint-project/assets/scaffold/CLAUDE.md"
foreach ($x in $f) { "=== $x ==="; Select-String -Path $x -Pattern "less than 14 days","reviewable unit","stacked PRs","vendor the library","reusable service layers","Model selection","clean-context review via" | ForEach-Object { $_.Line.Trim() } }
```
Expected: las 7 frases aparecen una vez en CADA archivo (14 líneas en total).

- [ ] **Step 5: Commit**

```powershell
git add skills/bootstrap-personal-project/assets/scaffold/CLAUDE.md skills/bootstrap-southpoint-project/assets/scaffold/CLAUDE.md
git commit -m "feat(scaffold): hard rules de seguridad/PRs/vendor + estilo service-layer y modelo"
```

---

## Task 3: AI_DEVELOPMENT_WORKFLOW.md — paso 3 (PRs) + paso 7 (review-loop)

**Files:**
- Modify: `skills/bootstrap-personal-project/assets/scaffold/docs/ai-workflow/AI_DEVELOPMENT_WORKFLOW.md`
- Modify: `skills/bootstrap-southpoint-project/assets/scaffold/docs/ai-workflow/AI_DEVELOPMENT_WORKFLOW.md`

Ambas ediciones usan anclas idénticas en las dos variantes.

- [ ] **Step 1: Paso 3 — regla de tamaño de slice/PR**

En AMBOS archivos, reemplazar:

```
unless there is a strong reason.
```

por:

```
unless there is a strong reason.

Each slice must fit in a small, reviewable PR (target ≤ ~400 lines of change). If a slice is larger, split it; when slices depend on each other, chain them as stacked PRs.
```

- [ ] **Step 2: Paso 7 — invocar el review-loop**

En AMBOS archivos, reemplazar:

```
For important changes, a second review must be performed from a clean context.
```

por:

```
For important changes, a second review must be performed from a clean context.

Run this as a loop with the `/review-loop` skill: `/code-review` → fix real findings → re-review, repeating until no medium/high-severity findings remain (or a 5-turn cap).
```

- [ ] **Step 3: Verificar**

Run:
```powershell
$f = "skills/bootstrap-personal-project/assets/scaffold/docs/ai-workflow/AI_DEVELOPMENT_WORKFLOW.md","skills/bootstrap-southpoint-project/assets/scaffold/docs/ai-workflow/AI_DEVELOPMENT_WORKFLOW.md"
foreach ($x in $f) { "=== $x ==="; Select-String -Path $x -Pattern "small, reviewable PR","/review-loop" | ForEach-Object { $_.Line.Trim() } }
```
Expected: ambas frases en cada archivo (4 líneas).

- [ ] **Step 4: Commit**

```powershell
git add skills/bootstrap-personal-project/assets/scaffold/docs/ai-workflow/AI_DEVELOPMENT_WORKFLOW.md skills/bootstrap-southpoint-project/assets/scaffold/docs/ai-workflow/AI_DEVELOPMENT_WORKFLOW.md
git commit -m "feat(scaffold): paso 3 con limite de PR y paso 7 con review-loop"
```

---

## Task 4: DEPLOYMENT_RULES.md (PRs) + QA_CHECKLIST.md (anti supply-chain)

**Files:**
- Modify: `skills/bootstrap-personal-project/assets/scaffold/docs/ai-workflow/DEPLOYMENT_RULES.md`
- Modify: `skills/bootstrap-southpoint-project/assets/scaffold/docs/ai-workflow/DEPLOYMENT_RULES.md`
- Modify: `skills/bootstrap-personal-project/assets/scaffold/docs/ai-workflow/QA_CHECKLIST.md`
- Modify: `skills/bootstrap-southpoint-project/assets/scaffold/docs/ai-workflow/QA_CHECKLIST.md`

- [ ] **Step 1: DEPLOYMENT_RULES.md — regla de PRs en "General"**

En AMBOS `DEPLOYMENT_RULES.md`, reemplazar:

```
Claude must never deploy without explicit human approval.
```

por:

```
Claude must never deploy without explicit human approval.

Never open giant PRs. Keep each PR a small, reviewable unit (target ≤ ~400 lines); when changes depend on each other, prefer a chain of stacked PRs.
```

- [ ] **Step 2: QA_CHECKLIST.md — check de dependencias**

En AMBOS `QA_CHECKLIST.md`, reemplazar:

```
- [ ] Tests added or updated
```

por:

```
- [ ] Tests added or updated
- [ ] New dependencies are ≥14 days old (or explicitly approved)
```

- [ ] **Step 3: Verificar**

Run:
```powershell
$dep = "skills/bootstrap-personal-project/assets/scaffold/docs/ai-workflow/DEPLOYMENT_RULES.md","skills/bootstrap-southpoint-project/assets/scaffold/docs/ai-workflow/DEPLOYMENT_RULES.md"
$qa  = "skills/bootstrap-personal-project/assets/scaffold/docs/ai-workflow/QA_CHECKLIST.md","skills/bootstrap-southpoint-project/assets/scaffold/docs/ai-workflow/QA_CHECKLIST.md"
foreach ($x in $dep) { Select-String -Path $x -Pattern "Never open giant PRs" | ForEach-Object { $_.Line.Trim() } }
foreach ($x in $qa)  { Select-String -Path $x -Pattern "14 days old" | ForEach-Object { $_.Line.Trim() } }
```
Expected: la frase de PRs en los 2 DEPLOYMENT_RULES y la de dependencias en los 2 QA_CHECKLIST (4 líneas).

- [ ] **Step 4: Commit**

```powershell
git add skills/bootstrap-personal-project/assets/scaffold/docs/ai-workflow/DEPLOYMENT_RULES.md skills/bootstrap-southpoint-project/assets/scaffold/docs/ai-workflow/DEPLOYMENT_RULES.md skills/bootstrap-personal-project/assets/scaffold/docs/ai-workflow/QA_CHECKLIST.md skills/bootstrap-southpoint-project/assets/scaffold/docs/ai-workflow/QA_CHECKLIST.md
git commit -m "feat(scaffold): regla de PRs en deployment + check anti supply-chain en QA"
```

---

## Task 5: Conteos 9→10 en SKILL.md (ambas) + docs/TESTING.md

**Files:**
- Modify: `skills/bootstrap-personal-project/SKILL.md`
- Modify: `skills/bootstrap-southpoint-project/SKILL.md`
- Modify: `docs/TESTING.md`

Las tres líneas a tocar en los `SKILL.md` son idénticas entre personal y southpoint.

- [ ] **Step 1: Enumeración de skills en el cuerpo (línea ~8)**

En AMBOS `SKILL.md`, reemplazar:

```
the custom skills (grill-me, grill-with-docs, tdd, to-prd, to-issues, triage, handoff, zoom-out).
```

por:

```
the custom skills (grill-me, grill-with-docs, tdd, to-prd, to-issues, triage, handoff, zoom-out, review-loop).
```

- [ ] **Step 2: Línea de verificación del Step 2 (conteos)**

En AMBOS `SKILL.md`, reemplazar:

```
Before committing, verify the copy landed cleanly: `.agents\skills` has 9 skill directories, `.claude\commands` has 9 files, and neither `.agents\.agents` nor `.claude\.claude` exists.
```

por:

```
Before committing, verify the copy landed cleanly: `.agents\skills` has 10 skill directories, `.claude\commands` has 10 files, and neither `.agents\.agents` nor `.claude\.claude` exists.
```

- [ ] **Step 3: Línea de entrega del Step 2**

En AMBOS `SKILL.md`, reemplazar:

```
This delivers: `CLAUDE.md`, `.gitignore`, `skills-lock.json`, `.agents/skills/` (9 skills), `.claude/commands/` (9 commands), `docs/ai-workflow/` (5 docs), `docs/agents/` (3 docs).
```

por:

```
This delivers: `CLAUDE.md`, `.gitignore`, `skills-lock.json`, `.agents/skills/` (10 skills — 9 synced via `skills-lock.json` + `review-loop`, own), `.claude/commands/` (10 commands), `docs/ai-workflow/` (5 docs), `docs/agents/` (3 docs).
```

- [ ] **Step 4: Assertion de conteos en docs/TESTING.md**

En `docs/TESTING.md`, reemplazar:

```
- Scaffold completo: CLAUDE.md (8 pasos + Workflow State Machine), 5 docs ai-workflow, 9 skills `.agents`, 9 comandos `.claude`, 3 docs agents, `.gitignore` (con `.scratch/`), `skills-lock.json`, README, CONTEXT.md stub, `docs/adr/`.
```

por:

```
- Scaffold completo: CLAUDE.md (8 pasos + Workflow State Machine), 5 docs ai-workflow, 10 skills `.agents` (9 de mattpocock vía `skills-lock.json` + `review-loop` propia), 10 comandos `.claude`, 3 docs agents, `.gitignore` (con `.scratch/`), `skills-lock.json`, README, CONTEXT.md stub, `docs/adr/`.
```

- [ ] **Step 5: Verificar que no quedan "9 skills"/"9 commands"/"9 skill directories" obsoletos**

Run:
```powershell
Select-String -Path "skills/bootstrap-personal-project/SKILL.md","skills/bootstrap-southpoint-project/SKILL.md","docs/TESTING.md" -Pattern "9 skill","9 commands","9 comandos","9 files"
```
Expected: **sin resultados** (todos migrados a 10).

- [ ] **Step 6: Commit**

```powershell
git add skills/bootstrap-personal-project/SKILL.md skills/bootstrap-southpoint-project/SKILL.md docs/TESTING.md
git commit -m "chore: actualizar conteos 9->10 por la skill review-loop"
```

---

## Task 6: Verificación mecánica de espejo y copia

**Files:** ninguno (solo checks).

- [ ] **Step 1: Confirmar que las dos skills siguen espejadas salvo DOMO/identidad**

Run:
```powershell
$ps = "skills/bootstrap-personal-project/assets/scaffold"
$ss = "skills/bootstrap-southpoint-project/assets/scaffold"
"=== review-loop debe ser IDENTICO ==="
(Compare-Object (Get-Content "$ps/.agents/skills/review-loop/SKILL.md") (Get-Content "$ss/.agents/skills/review-loop/SKILL.md")).Count
"=== CLAUDE.md: las diferencias deben ser SOLO lineas DOMO/Firebase/Azure ==="
Compare-Object (Get-Content "$ps/CLAUDE.md") (Get-Content "$ss/CLAUDE.md") | Format-Table -AutoSize
```
Expected: `review-loop` Count = `0`; el `Compare-Object` de CLAUDE.md muestra únicamente las líneas DOMO ya preexistentes (las reglas nuevas NO deben aparecer como diferencia — prueba de que se aplicaron igual en ambas).

- [ ] **Step 2: Simular la copia del scaffold y verificar conteos + ausencia de duplicados anidados**

Run:
```powershell
$tmp = Join-Path $env:TEMP ("scaffold-check-" + (Get-Random))
New-Item -ItemType Directory -Force $tmp | Out-Null
$skill = "skills/bootstrap-personal-project"
Get-ChildItem "$skill\assets\scaffold" -Force |
  Where-Object Name -ne "gitignore.txt" |
  ForEach-Object { Copy-Item $_.FullName (Join-Path $tmp $_.Name) -Recurse -Force }
"skills dirs: " + @(Get-ChildItem "$tmp/.agents/skills" -Directory).Count
"commands:    " + @(Get-ChildItem "$tmp/.claude/commands" -File).Count
"nested .agents: " + (Test-Path "$tmp/.agents/.agents")
"nested .claude: " + (Test-Path "$tmp/.claude/.claude")
Remove-Item $tmp -Recurse -Force
```
Expected:
```
skills dirs: 10
commands:    10
nested .agents: False
nested .claude: False
```

---

## Task 7: Testear con skill-creator

**Files:** ninguno (evals; ver `docs/TESTING.md`).

- [ ] **Step 1: Correr los evals canónicos**

Invocar la skill `skill-creator:skill-creator` y correr, como mínimo, los test cases de `docs/TESTING.md`:
1. Personal, directorio vacío.
2. Southpoint, directorio vacío.
3. Southpoint (o personal), archivos preexistentes.

- [ ] **Step 2: Confirmar assertions clave (de `docs/TESTING.md`)**

Verificar en los runs:
- Scaffold completo con **10 skills `.agents` y 10 comandos `.claude`** (la nueva assertion), 5 docs ai-workflow, 3 docs agents, `skills-lock.json` con las 9 entradas upstream intactas.
- `review-loop/SKILL.md` presente en `.agents/skills/` y `review-loop.md` en `.claude/commands/`.
- Variante correcta: southpoint menciona DOMO; personal CERO DOMO.
- Sin duplicados anidados `.agents\.agents` / `.claude\.claude`.
- Git: branch `main`, un solo commit, autor correcto por variante.
- Preexistentes intactos byte a byte (caso 3).

- [ ] **Step 3: Borrar el workspace de evals**

Regla del repo: borrar cualquier rastro de testeo al terminar.

---

## Task 8: Deploy a ~/.claude/skills + commit final

**Files:** ninguno (deploy + git).

- [ ] **Step 1: Deployar las skills actualizadas**

Run: `pwsh -File tools/sync-skills.ps1`
Expected: dos líneas `Deployada: bootstrap-personal-project (...)` y `Deployada: bootstrap-southpoint-project (...)`, sin error.

- [ ] **Step 2: Verificar la copia instalada tiene review-loop**

Run:
```powershell
Test-Path "$env:USERPROFILE/.claude/skills/bootstrap-personal-project/assets/scaffold/.agents/skills/review-loop/SKILL.md","$env:USERPROFILE/.claude/skills/bootstrap-southpoint-project/assets/scaffold/.claude/commands/review-loop.md"
```
Expected: dos `True`.

- [ ] **Step 3: Estado git limpio**

Run: `git status --short`
Expected: sin cambios pendientes (todo commiteado en las tareas previas). Si quedó algo suelto, commitearlo con un mensaje descriptivo.

---

## Notas de seguimiento (fuera de alcance de este plan)

- Hard rule del repo: evaluar si el cambio del `CLAUDE.md` template (reglas nuevas) aplica también al `CLAUDE.md` real de Forecasting App (`C:\Repos\SOUTHPOINTLABS\Forecasting App`). Registrarlo; no implementarlo aquí.
