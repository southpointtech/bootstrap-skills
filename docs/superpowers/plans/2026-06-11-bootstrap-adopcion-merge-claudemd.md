# Adopción con merge de CLAUDE.md en bootstrap — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Que `/bootstrap-...` adopte un proyecto con `CLAUDE.md` propio (sin manifest), instalando la metodología de 8 steps sin perder el contexto/identidad del proyecto.

**Architecture:** Cambio de prosa en el `SKILL.md` de ambas skills de bootstrap (espejado): reescribir el bullet de Step 0 y agregar una sección "Step 0b — Adoption mode" con backup verbatim, copia del scaffold, clasificación de bloques, mapa de cobertura + aprobación, y aplicación del merge. El sellado del `CLAUDE.md` como `customized` es **emergente** (el manifest copiado registra el hash canónico como base; el merge lo hace diferir), así que no se tocan los scripts de `upgrade-bootstrap`.

**Tech Stack:** Markdown (SKILL.md), PowerShell (pasos determinísticos del scaffold ya existentes), skill-creator (evals), `compare-scaffold.ps1` (verificación de clasificación).

---

## File Structure

- **Modify:** `skills/bootstrap-southpoint-project/SKILL.md` — Step 0 + nueva sección Step 0b.
- **Modify:** `skills/bootstrap-personal-project/SKILL.md` — espejo verbatim del cambio.
- **Modify:** `docs/TESTING.md` — nuevo caso canónico de adopción + assertions.
- **No tocar:** `skills/upgrade-bootstrap/scripts/*.ps1` (el sellado customized es emergente).
- **Deploy:** `tools/sync-skills.ps1` (copia repo → `~/.claude/skills/`, regenera manifests).

El bloque de prosa "Step 0b" es **idéntico** en ambas variantes (no menciona DOMO ni identidad git), de modo que el espejado es una copia literal.

---

## Task 1: Definir el caso de eval y sus assertions (test-first)

**Files:**
- Modify: `docs/TESTING.md`

- [ ] **Step 1: Agregar el 4º caso canónico bajo "Test cases canónicos"**

En `docs/TESTING.md`, después del caso 3 ("Southpoint, archivos preexistentes"), agregar:

```markdown
4. **Southpoint, adopción (CLAUDE.md propio sin manifest)** — sembrar un `CLAUDE.md` hecho a mano (branching model main/develop + un gotcha técnico + una mención a DOMO) y un `worker.js`, sin `.bootstrap-manifest.json`, y pedir: "agregale el bootstrap a este proyecto". Debe entrar en **modo adopción** (Step 0b), no frenar ni derivar a upgrade-bootstrap.
```

- [ ] **Step 2: Agregar las assertions del modo adopción bajo "Assertions clave"**

En la sección "Assertions clave", agregar estas líneas:

```markdown
- Modo adopción: `docs/agents/legacy-claude.md` existe y es **byte-idéntico** al `CLAUDE.md` original sembrado.
- Modo adopción: el `CLAUDE.md` final es el canónico (contiene "Workflow State Machine"); las reglas operativas del original aparecen en su sección `## Hard rules`; el conocimiento de dominio del original aparece en `docs/agents/domain.md`.
- Modo adopción: cada bloque del original quedó representado (en `legacy-claude.md` + su destino); ningún bloque se perdió en silencio.
- Modo adopción: tras adoptar, `compare-scaffold.ps1` clasifica `CLAUDE.md` como **customized** (ni `outdated` ni `uptodate`), confirmando que un upgrade futuro no lo pisa.
```

- [ ] **Step 3: Commit**

```bash
git add docs/TESTING.md
git commit -m "test(adoption): caso canonico de adopcion con merge de CLAUDE.md"
```

---

## Task 2: Reescribir Step 0 y agregar Step 0b en bootstrap-southpoint-project

**Files:**
- Modify: `skills/bootstrap-southpoint-project/SKILL.md`

- [ ] **Step 1: Reemplazar el segundo bullet de Step 0**

Buscar el bullet actual (línea ~19):

```markdown
- If `CLAUDE.md` or `docs/ai-workflow/` exist but there is **no** `.bootstrap-manifest.json`, do **not** say "already bootstrapped" — it isn't. It just has its own files (e.g. a hand-written `CLAUDE.md`). **Stop and ask**: overwriting would be destructive, and the right path is `upgrade-bootstrap` (legacy adoption — seeds the scaffold + manifest without clobbering the existing `CLAUDE.md`). Point the user there instead of bootstrapping.
```

Reemplazarlo por:

```markdown
- If `CLAUDE.md` or `docs/ai-workflow/` exist but there is **no** `.bootstrap-manifest.json`, the project is **not** bootstrapped — it just has its own files. Do **not** say "already bootstrapped", and do **not** derive to `upgrade-bootstrap` (that skill is only for projects that already have a manifest). Instead, enter **Step 0b — Adoption mode** below: install the methodology while preserving the project's own content.
```

- [ ] **Step 2: Insertar la sección "Step 0b — Adoption mode" entre Step 0 y Step 1**

Insertar este bloque completo justo después del último bullet de "## Step 0 — Safety check" y antes de "## Step 1 — Project info":

````markdown
## Step 0b — Adoption mode

Reached from Step 0 when the project has its own `CLAUDE.md` (or `docs/ai-workflow/`) but no `.bootstrap-manifest.json`. Goal: install the 8-step methodology without losing the project's context or identity. Two invariants govern this mode: **the original is never lost** (a verbatim, permanent backup), and **the merge is never applied before the user approves a coverage map** of where each block of their content goes.

Define `$skill` and `$proj` as in Step 2.

### A. Back up the original verbatim

Before copying anything, stash the project's `CLAUDE.md` so the scaffold copy can't clobber it:

```powershell
Copy-Item "$proj\CLAUDE.md" "$proj\CLAUDE.legacy.md" -Force
```

### B. Copy the scaffold, then park the backup

Run **Step 2** exactly as written (the enumerated copy + `.gitignore`). This installs the canonical `CLAUDE.md`, all 44 files, and `.bootstrap-manifest.json`, overwriting the project's `CLAUDE.md` with the canonical 8-step template — fine, the original is stashed. Then move the stash to its permanent home (now that `docs/agents/` exists from the scaffold copy):

```powershell
Move-Item "$proj\CLAUDE.legacy.md" "$proj\docs\agents\legacy-claude.md" -Force
```

`docs/agents/legacy-claude.md` stays in the repo forever as the recovery net.

### C. Classify the original's content

Read `docs/agents/legacy-claude.md`. Split it into blocks (by heading or logical unit). Classify each block into exactly one destination, **moving text verbatim — never paraphrase or summarize**:

- **Operational rule** (governs behavior, e.g. "never deploy without approval", "don't trust the 2xx as proof of arrival") → the `## Hard rules` section of the canonical `CLAUDE.md`.
- **Domain knowledge** (what the project does, integrations, technical gotchas, branching model) → `docs/agents/domain.md`, appended under a new `## Project-specific domain` section.
- **Project description** (the one-line of what this is) → `CONTEXT.md` (created in Step 3).
- **Doesn't fit / unsure** → leave it only in `legacy-claude.md` and mark it on the map for the user to decide.

### D. Present the coverage map and get approval

Show the user a table: every block of the original → its destination, quoting the block verbatim. Make any unassigned ("doesn't fit") blocks visible. Get a **single explicit approval** (the user may correct individual rows before approving). Do **not** write the merge until approved.

### E. Apply the merge

After approval: insert operational-rule blocks into `## Hard rules` as new bullets (verbatim); append domain blocks under `## Project-specific domain` in `docs/agents/domain.md` (verbatim); seed `CONTEXT.md` with the description. Leave `legacy-claude.md` untouched as the permanent backup.

The `.bootstrap-manifest.json` copied in step B records the canonical `CLAUDE.md` hash as its base. Because the project's `CLAUDE.md` now differs (project Hard rules merged in), a future `upgrade-bootstrap` automatically classifies it as **customized** and never overwrites it — no extra sealing needed.

### F. Continue with Steps 3–6

Proceed to Step 3 (project-specific files — but if step E already seeded `CONTEXT.md`, do **not** overwrite it with a stub), Step 4 (MCP servers — the `.mcp.json` menu applies to adopted projects too), Step 5 (git), and Step 6 (report). In the Step 6 report, explicitly state that the original is preserved at `docs/agents/legacy-claude.md`, and list which blocks went to `## Hard rules` vs `docs/agents/domain.md`.
````

- [ ] **Step 3: Verificar que el cambio es coherente**

Run: `Select-String -Path skills/bootstrap-southpoint-project/SKILL.md -Pattern "Step 0b — Adoption mode"`
Expected: una coincidencia (la sección existe).

Run: `Select-String -Path skills/bootstrap-southpoint-project/SKILL.md -Pattern "derive to .upgrade-bootstrap."`
Expected: una coincidencia en el bullet de Step 0 (el caso ya no deriva, lo dice explícitamente).

- [ ] **Step 4: Commit**

```bash
git add skills/bootstrap-southpoint-project/SKILL.md
git commit -m "feat(bootstrap-southpoint): Step 0b modo adopcion con merge de CLAUDE.md"
```

---

## Task 3: Espejar el cambio en bootstrap-personal-project

**Files:**
- Modify: `skills/bootstrap-personal-project/SKILL.md`

- [ ] **Step 1: Confirmar que el scaffold personal tiene las secciones destino**

Run: `Select-String -Path skills/bootstrap-personal-project/assets/scaffold/CLAUDE.md -Pattern "^## Hard rules"`
Expected: una coincidencia. (Si no existe, detener y reportar: el merge necesita esa sección. No inventar.)

Run: `Test-Path skills/bootstrap-personal-project/assets/scaffold/docs/agents/domain.md`
Expected: `True`.

- [ ] **Step 2: Aplicar el MISMO reemplazo del bullet de Step 0**

Reemplazar el segundo bullet de Step 0 en `skills/bootstrap-personal-project/SKILL.md` por el texto **idéntico** del Task 2 Step 1 (el bloque que empieza con "If `CLAUDE.md` or `docs/ai-workflow/` exist but there is **no** `.bootstrap-manifest.json`, the project is **not** bootstrapped...").

- [ ] **Step 3: Insertar la MISMA sección "Step 0b — Adoption mode"**

Insertar el bloque **idéntico** del Task 2 Step 2, entre "## Step 0 — Safety check" y "## Step 1 — Project info".

- [ ] **Step 4: Verificar que ambos SKILL.md tienen el Step 0b idéntico**

Run:
```powershell
$a = Select-String -Path skills/bootstrap-southpoint-project/SKILL.md -Pattern "Step 0b — Adoption mode" -Context 0,40 | Out-String
$b = Select-String -Path skills/bootstrap-personal-project/SKILL.md   -Pattern "Step 0b — Adoption mode" -Context 0,40 | Out-String
if ($a -eq $b) { "IDENTICOS" } else { "DIFIEREN — revisar" }
```
Expected: `IDENTICOS`.

- [ ] **Step 5: Commit**

```bash
git add skills/bootstrap-personal-project/SKILL.md
git commit -m "feat(bootstrap-personal): Step 0b modo adopcion (espejo de southpoint)"
```

---

## Task 4: Deployar y validar con un eval real de adopción

**Files:**
- Run: `tools/sync-skills.ps1`
- Create (temporal): `bootstrap-southpoint-project-workspace/` (se borra al final)

- [ ] **Step 1: Deployar las skills al directorio instalado**

Run: `& "tools\sync-skills.ps1"`
Expected: "Deployada: bootstrap-southpoint-project" y "...personal" sin errores; manifests regenerados.

- [ ] **Step 2: Sembrar el proyecto de prueba (escenario adopción)**

```powershell
$P = "bootstrap-southpoint-project-workspace\eval-adopt\project"
New-Item -ItemType Directory -Force $P | Out-Null
@'
# KBS Orders — Branching model (notas propias)

Proyecto de Southpoint. Sincroniza ordenes con el dataset DOMO de KBS.

## Branching
- main = produccion (deploy automatico al Worker)
- develop = staging

## Reglas
- Nunca deployar al Worker sin aprobacion humana.

## Gotchas
- El Worker cachea el webhook 60s; no confiar en el 2xx como prueba de arribo.
'@ | Set-Content "$P\CLAUDE.md" -Encoding UTF8
"console.log('kbs worker');" | Set-Content "$P\worker.js" -Encoding UTF8
```

- [ ] **Step 3: Correr la skill (modo adopción) vía subagente**

Dispatch a subagent (Agent tool) que:
- Lee `~/.claude/skills/bootstrap-southpoint-project/SKILL.md` y la sigue.
- cwd del "proyecto" = el dir `...\eval-adopt\project`.
- Prompt del usuario: "agregale el bootstrap a este proyecto".
- Para el mapa de cobertura (Step 0b.D), el subagente aprueba el mapa propuesto (simula al usuario diciendo "ok").
- No tocar `worker.js`.

- [ ] **Step 4: Verificar las assertions (determinísticas)**

```powershell
$P = "bootstrap-southpoint-project-workspace\eval-adopt\project"
# 1) backup byte-identico
$origHash = (Get-FileHash "$P\docs\agents\legacy-claude.md" -Algorithm SHA256).Hash
"backup existe: $(Test-Path "$P\docs\agents\legacy-claude.md")"
# 2) CLAUDE.md final es canonico (tiene Workflow State Machine)
Select-String -Path "$P\CLAUDE.md" -Pattern "Workflow State Machine" -Quiet
# 3) regla operativa migrada a Hard rules
Select-String -Path "$P\CLAUDE.md" -Pattern "sin aprobacion humana|prueba de arribo" -Quiet
# 4) dominio migrado a domain.md
Select-String -Path "$P\docs\agents\domain.md" -Pattern "DOMO|develop = staging" -Quiet
# 5) worker.js intacto
Select-String -Path "$P\worker.js" -Pattern "kbs worker" -Quiet
```
Expected: backup existe `True`; assertions 2-5 `True`.

- [ ] **Step 5: Verificar la clasificación del manifest (el sellado emergente)**

```powershell
$P = "bootstrap-southpoint-project-workspace\eval-adopt\project"
$canon = "$env:USERPROFILE\.claude\skills\bootstrap-southpoint-project\assets\scaffold"
pwsh -File skills/upgrade-bootstrap/scripts/compare-scaffold.ps1 -ProjectDir $P -CanonicalScaffold $canon |
  ConvertFrom-Json | ForEach-Object { $_.customized.file }
```
Expected: la lista de `customized` **incluye** `CLAUDE.md` (confirma que un upgrade futuro no lo pisaría). `CLAUDE.md` NO debe aparecer en `uptodate` ni `outdated`.

- [ ] **Step 6: Limpiar el workspace de evals (hard rule del repo)**

```powershell
Remove-Item -Recurse -Force "bootstrap-southpoint-project-workspace" -ErrorAction SilentlyContinue
if (Test-Path "bootstrap-southpoint-project-workspace") { Start-Sleep -Milliseconds 500; Remove-Item -Recurse -Force "bootstrap-southpoint-project-workspace" }
Test-Path "bootstrap-southpoint-project-workspace"
```
Expected: `False`.

---

## Task 5: Commit final de manifests regenerados (si los hay)

**Files:**
- Modify (posible): `skills/*/assets/scaffold/.bootstrap-manifest.json` (regenerados por sync)

- [ ] **Step 1: Revisar qué dejó el sync**

Run: `git status --short`
Expected: solo cambios de manifests (ruido de version/fecha) si los hay; ningún archivo de testeo.

- [ ] **Step 2: Commit (solo si hay cambios de manifest)**

```bash
git add skills/*/assets/scaffold/.bootstrap-manifest.json
git commit -m "chore(scaffold): regenerar manifests tras deploy del modo adopcion"
```

Si `git status` está limpio, saltar este paso.

---

## Notas de verificación (self-review del plan)

- **Cobertura del spec:** modelo conceptual (Task 2 Step 1, bullet de Step 0) ✓; estrategia C (Task 2 Step 2, sección C) ✓; 4 salvaguardas (backup A/B, verbatim C, mapa D, aprobación D) ✓; sellado customized emergente (Task 2 Step 2 nota en E + Task 4 Step 5) ✓; espejado (Task 3) ✓; testing (Task 1 + Task 4) ✓.
- **Sin placeholders:** todo el texto de prosa y los comandos están completos y literales.
- **Consistencia:** el bloque "Step 0b" es idéntico en ambas tareas (Task 3 referencia el de Task 2); los nombres de archivo (`docs/agents/legacy-claude.md`, `CLAUDE.legacy.md`, `## Project-specific domain`) son consistentes entre tareas.
```
