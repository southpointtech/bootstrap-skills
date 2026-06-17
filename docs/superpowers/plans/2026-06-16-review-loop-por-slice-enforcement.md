# Review-loop por slice + enforcement de slices chiquitos — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Hacer que el review-loop corra con cada commit de implementación y al cerrar cada slice (sin preguntar), y que los slices nazcan ≤ ~400 líneas de lógica, en repos locales sin remote y en GitHub por igual.

**Architecture:** El enforcement primario vive en las skills del scaffold (`to-issues`, `tdd`, `review-loop`) y en `CLAUDE.md`; el hook `review-loop-trigger.ps1` es el refuerzo determinístico, ampliado para disparar también en `git commit`. Todos los cambios se espejan en `bootstrap-personal-project` y `bootstrap-southpoint-project`. Tras editar se deploya con `tools/sync-skills.ps1` (regenera `.bootstrap-manifest.json`) y se commitea con identidad local.

**Tech Stack:** Markdown (skills/commands/CLAUDE.md), PowerShell 7 (hook + tooling de deploy), skill-creator para evals.

---

## Contexto crítico para el implementador

- **Duplicación de contenido:** cada skill existe en DOS archivos con el mismo cuerpo:
  `.agents/skills/<name>/SKILL.md` (canónico) y `.claude/commands/<name>.md` (copia; difiere solo en el `description` del frontmatter y en los paths de los links). **Todo cambio de cuerpo va en ambos.**
- **Espejado:** `to-issues`, `tdd`, `review-loop` y el hook son **idénticos** entre personal y southpoint (verificado por `diff`). El mismo `old_string`/`new_string` aplica a las rutas de ambas skills. `CLAUDE.md` difiere en contenido DOMO, pero las secciones que tocamos son textualmente idénticas.
- **Rutas base:**
  - `PER = skills/bootstrap-personal-project/assets/scaffold`
  - `SOU = skills/bootstrap-southpoint-project/assets/scaffold`
- **Flujo en feature branches:** el hook NO dispara cuando `branch == base` (no se revisa la base contra sí misma). El ritmo asume trabajar en **feature branches por slice**, incluso en repos locales (en local la base se resuelve por fallback a `main`/`master`/`develop`). Commits directos sobre la base no disparan — es deseado.
- **NO** correr `git checkout`/`git branch` durante la implementación (regla conocida de subagent-driven). Trabajar sobre el árbol actual.
- **NO** editar `.bootstrap-manifest.json` a mano: lo regenera `sync-skills.ps1`.

---

## Task 1: `to-issues` — techo de tamaño en planificación

**Files (mismo edit en los 4):**
- Modify: `PER/.agents/skills/to-issues/SKILL.md`
- Modify: `PER/.claude/commands/to-issues.md`
- Modify: `SOU/.agents/skills/to-issues/SKILL.md`
- Modify: `SOU/.claude/commands/to-issues.md`

- [ ] **Step 1: Agregar la regla de tamaño en `<vertical-slice-rules>`**

En cada uno de los 4 archivos, reemplazar:

```
<vertical-slice-rules>
- Each slice delivers a narrow but COMPLETE path through every layer (schema, API, UI, tests)
- A completed slice is demoable or verifiable on its own
- Prefer many thin slices over few thick ones
</vertical-slice-rules>
```

por:

```
<vertical-slice-rules>
- Each slice delivers a narrow but COMPLETE path through every layer (schema, API, UI, tests)
- A completed slice is demoable or verifiable on its own
- Prefer many thin slices over few thick ones
- Keep each slice ≤ ~400 lines of *logic* diff. Generated files, vendored code (`docs/vendor/`), lockfiles and snapshots do NOT count. Cohesion comes first — this is a guide, not a hard gate — but a slice projected well over ~400 lines of logic MUST be split before it is published, not after.
</vertical-slice-rules>
```

- [ ] **Step 2: Agregar la pregunta de tamaño en el quiz (Step 4)**

En cada uno de los 4 archivos, reemplazar:

```
Ask the user:

- Does the granularity feel right? (too coarse / too fine)
- Are the dependency relationships correct?
- Should any slices be merged or split further?
- Are the correct slices marked as HITL and AFK?
```

por:

```
Ask the user:

- Does the granularity feel right? (too coarse / too fine)
- Does any slice project over ~400 lines of logic diff? If so, split it now.
- Are the dependency relationships correct?
- Should any slices be merged or split further?
- Are the correct slices marked as HITL and AFK?
```

- [ ] **Step 3: Verificar**

Run:
```bash
grep -rl "≤ ~400 lines of \*logic\* diff" skills/*/assets/scaffold/.agents/skills/to-issues/ skills/*/assets/scaffold/.claude/commands/to-issues.md
```
Expected: 4 rutas listadas (2 SKILL.md + 2 command.md).

---

## Task 2: `tdd` — Step 5 "Close the slice" + ritmo multi-commit

**Files (mismo edit en los 4):**
- Modify: `PER/.agents/skills/tdd/SKILL.md`
- Modify: `PER/.claude/commands/tdd.md`
- Modify: `SOU/.agents/skills/tdd/SKILL.md`
- Modify: `SOU/.claude/commands/tdd.md`

- [ ] **Step 1: Insertar la sección "5. Close the slice" antes de "## Checklist Per Cycle"**

En cada uno de los 4 archivos, reemplazar:

```
**Never refactor while RED.** Get to GREEN first.

## Checklist Per Cycle
```

por:

```
**Never refactor while RED.** Get to GREEN first.

### 5. Close the slice

After green/refactor, before starting the next slice. This is NOT optional and you do NOT ask permission — you run it:

1. Check the diff size: `git --no-pager diff --stat` (or `git --no-pager diff <base>...HEAD --stat` on a feature branch). Generated files, vendored code, lockfiles and snapshots don't count toward the ~400-line guide. If the logic diff is well over ~400 lines, close the cohesive part as its own slice first.
2. Commit. Multi-commit per slice is expected — one commit per green/refactor step — and `/review-loop` runs per commit.
3. Run `/review-loop` on the slice diff and iterate until it closes (zero medium/high findings, or the 5-turn cap). Do NOT mark the slice done until the loop closes.
4. Only then start the next slice.

A RED-only commit (a failing test, no implementation) has nothing to review — run the loop after green/refactor, not after red. If the hook triggers the loop on a RED commit anyway, its pre-flight closes it without noise.

## Checklist Per Cycle
```

- [ ] **Step 2: Verificar**

Run:
```bash
grep -rl "### 5. Close the slice" skills/*/assets/scaffold/.agents/skills/tdd/ skills/*/assets/scaffold/.claude/commands/tdd.md
```
Expected: 4 rutas listadas.

---

## Task 3: `review-loop` — "Modo commit / local"

**Files (mismo edit en los 4):**
- Modify: `PER/.agents/skills/review-loop/SKILL.md`
- Modify: `PER/.claude/commands/review-loop.md`
- Modify: `SOU/.agents/skills/review-loop/SKILL.md`
- Modify: `SOU/.claude/commands/review-loop.md`

- [ ] **Step 1: Insertar la sección "Modo commit / local" después del bloque "Modo PR"**

El bloque "Modo PR" termina así (idéntico en los 4 archivos):

```
Usá ese mismo rango (`git diff <base>...HEAD`) como entrada de cada `/code-review` del loop. El modo working-tree (`git diff` sin rango) sigue siendo el default para invocación manual sobre cambios sin commitear.
```

En cada uno de los 4 archivos, reemplazar ese párrafo por:

````
Usá ese mismo rango (`git diff <base>...HEAD`) como entrada de cada `/code-review` del loop. El modo working-tree (`git diff` sin rango) sigue siendo el default para invocación manual sobre cambios sin commitear.

## Modo commit / local (cuando lo dispara un `git commit`)

Si llegaste acá tras un `git commit` (típico en repos locales sin remote), revisá el diff del slice recién cerrado. Si el branch tiene una base resoluble, usá el rango del branch; si no, revisá el último commit:

```powershell
git --no-pager diff <base>...HEAD --stat   # si hay base (sirve también con base local, sin remote)
git --no-pager show --stat HEAD            # fallback: solo el último commit
```

Si el commit es solo un test que falla a propósito (RED de TDD) y todavía no hay código de implementación que revisar, cerrá el loop sin acción: no hay nada que arreglar aún.
````

- [ ] **Step 2: Verificar**

Run:
```bash
grep -rl "Modo commit / local" skills/*/assets/scaffold/.agents/skills/review-loop/ skills/*/assets/scaffold/.claude/commands/review-loop.md
```
Expected: 4 rutas listadas.

---

## Task 4: `CLAUDE.md` — lenguaje imperativo + regla de tamaño

**Files (mismo edit en ambos):**
- Modify: `PER/CLAUDE.md`
- Modify: `SOU/CLAUDE.md`

- [ ] **Step 1: Reescribir la transición de review a orden imperativa**

En ambos archivos, reemplazar la línea:

```
- After implementation, suggest QA and the clean-context review via `/review-loop`. Además, al abrir o actualizar un PR (`gh pr create` / `git push`), el hook `review-loop-trigger` inyecta automáticamente la orden de correr `/review-loop` sobre el diff del branch; no depende de que el agente lo recuerde. El `/review-loop` manual sigue disponible para revisar cambios locales sin commitear.
```

por:

```
- After implementation, run `/review-loop` at the close of every slice and after each implementation commit — do NOT ask whether to run it, just run it until it closes (zero medium/high findings, or the 5-turn cap). The `review-loop-trigger` hook reinforces this deterministically: on `git commit`, `git push` or `gh pr create` in a feature branch it injects the order to run `/review-loop` over the slice diff, so it does not depend on the agent remembering. This works in local repos (no remote) and on GitHub alike. Work in feature branches per slice — commits directly on the base branch do not trigger the loop.
```

- [ ] **Step 2: Reescribir la regla de tamaño de slice con exclusiones**

En ambos archivos, reemplazar la línea:

```
- Keep each vertical slice a small, reviewable unit. Target ≤ ~400 lines of change per PR; a diff approaching thousands of lines breaks the review loop. If a slice exceeds ~400 lines, split it before implementing.
```

por:

```
- Keep each vertical slice a small, reviewable unit of ≤ ~400 lines of *logic* diff. Generated files, vendored code (`docs/vendor/`), lockfiles and snapshots do not count. Cohesion comes first, but a slice projected well over ~400 lines of logic must be split before implementing, not after — a diff approaching thousands of lines breaks the review loop.
```

- [ ] **Step 3: Verificar**

Run:
```bash
grep -c "run \`/review-loop\` at the close of every slice" skills/bootstrap-personal-project/assets/scaffold/CLAUDE.md skills/bootstrap-southpoint-project/assets/scaffold/CLAUDE.md
```
Expected: cada archivo devuelve `1`.

---

## Task 5: Hook `review-loop-trigger.ps1` — disparar en `git commit` + mensaje imperativo

**Files (mismo edit en ambos — son idénticos):**
- Modify: `PER/.claude/hooks/review-loop-trigger.ps1`
- Modify: `SOU/.claude/hooks/review-loop-trigger.ps1`

- [ ] **Step 1: Ampliar el filtro de comandos a `git commit`**

En ambos archivos, reemplazar:

```powershell
# 2. Filtrar: solo gh pr create / git push
$isPr   = $cmd -match '\bgh\s+pr\s+create\b'
$isPush = $cmd -match '\bgit\s+push\b'
if (-not ($isPr -or $isPush)) { exit 0 }
```

por:

```powershell
# 2. Filtrar: gh pr create / git push / git commit
$isPr     = $cmd -match '\bgh\s+pr\s+create\b'
$isPush   = $cmd -match '\bgit\s+push\b'
$isCommit = $cmd -match '\bgit\s+commit\b'
if (-not ($isPr -or $isPush -or $isCommit)) { exit 0 }
```

- [ ] **Step 2: Reescribir el mensaje inyectado a orden imperativa que cubre el caso local**

En ambos archivos, reemplazar:

```powershell
# 7. Inyectar la instrucción a Claude
$msg = "Acabas de abrir o actualizar un PR (branch '$branch' sobre base '$base'). " +
       "Antes de dar el trabajo por terminado, ejecuta /review-loop revisando el diff del " +
       "branch con: git diff $base...HEAD. No marques el trabajo como completo hasta que el " +
       "loop cierre (cero hallazgos de severidad media/alta, o el tope de 5 turnos)."
```

por:

```powershell
# 7. Inyectar la instrucción a Claude
$msg = "Cerraste un commit/slice en el branch '$branch' (base '$base'). " +
       "Ejecuta /review-loop AHORA sobre el diff del slice. No preguntes si querés correrlo: corrélo. " +
       "Usá 'git diff $base...HEAD' si el branch tiene base resoluble, o el diff del ultimo commit en repos locales. " +
       "No marques el trabajo como completo hasta que el loop cierre (cero hallazgos de severidad media/alta, o el tope de 5 turnos)."
```

- [ ] **Step 3: Test del hook — dispara en `git commit` en feature branch**

Run (desde la raíz del repo Bootstrap Skills, que está en un feature branch o main; usa un repo temporal para aislar):
```bash
tmp=$(mktemp -d) && git -C "$tmp" init -q && git -C "$tmp" commit --allow-empty -q -m base && git -C "$tmp" checkout -q -b feat/x && git -C "$tmp" commit --allow-empty -q -m slice1
echo "{\"tool_input\":{\"command\":\"git commit -m slice1\"},\"cwd\":\"$tmp\"}" | pwsh -NoProfile -File "skills/bootstrap-personal-project/assets/scaffold/.claude/hooks/review-loop-trigger.ps1"
```
Expected: un JSON con `additionalContext` que contiene "Ejecuta /review-loop AHORA". (La base resuelve a `master`/`main`; el branch `feat/x` != base → dispara.)

- [ ] **Step 4: Test del hook — NO dispara dos veces sobre el mismo commit (dedupe)**

Run (reusando `$tmp`, segundo disparo sobre el mismo HEAD):
```bash
echo "{\"tool_input\":{\"command\":\"git commit -m slice1\"},\"cwd\":\"$tmp\"}" | pwsh -NoProfile -File "skills/bootstrap-personal-project/assets/scaffold/.claude/hooks/review-loop-trigger.ps1"
```
Expected: salida vacía (exit 0, sin JSON) — ya disparó para ese SHA.

- [ ] **Step 5: Test del hook — NO dispara en commit sobre la base**

Run:
```bash
git -C "$tmp" checkout -q master 2>/dev/null || git -C "$tmp" checkout -q main; git -C "$tmp" commit --allow-empty -q -m onbase
echo "{\"tool_input\":{\"command\":\"git commit -m onbase\"},\"cwd\":\"$tmp\"}" | pwsh -NoProfile -File "skills/bootstrap-personal-project/assets/scaffold/.claude/hooks/review-loop-trigger.ps1"; rm -rf "$tmp"
```
Expected: salida vacía (branch == base → exit 0).

- [ ] **Step 6: Confirmar que personal y southpoint siguen idénticos**

Run:
```bash
diff -q skills/bootstrap-personal-project/assets/scaffold/.claude/hooks/review-loop-trigger.ps1 skills/bootstrap-southpoint-project/assets/scaffold/.claude/hooks/review-loop-trigger.ps1
```
Expected: sin salida (idénticos).

---

## Task 6: Deploy + manifest

- [ ] **Step 1: Regenerar manifest y deployar a `~/.claude/skills/`**

Run:
```bash
pwsh -NoProfile -File tools/sync-skills.ps1
```
Expected: copia las skills al destino y regenera `.bootstrap-manifest.json` en ambos scaffolds sin errores.

- [ ] **Step 2: Verificar que el manifest cambió (contempla los archivos editados)**

Run:
```bash
git status --short skills/*/assets/scaffold/.bootstrap-manifest.json
```
Expected: ambos manifests aparecen modificados.

---

## Task 7: Evals con skill-creator

Seguir `docs/TESTING.md`. Mínimo requerido por las reglas del repo: eval de directorio vacío + eval de archivos preexistentes.

- [ ] **Step 1: Eval directorio vacío (bootstrap-personal y bootstrap-southpoint)**

Bootstrapear en un workspace temporal y verificar que aterrizan: `to-issues`/`tdd`/`review-loop` con los cambios, `CLAUDE.md` con el lenguaje imperativo, y el hook con `git commit`.

Expected: scaffold completo, `grep "### 5. Close the slice"` y `grep "git commit"` en el hook destino → presentes.

- [ ] **Step 2: Eval archivos preexistentes / modo adopción**

Verificar que `merge-settings.ps1` (de `upgrade-bootstrap`) sigue mergeando el hook sin pisar un `settings.json` propio (p. ej. uno con `enabledPlugins`, como KBS). El matcher sigue siendo `Bash`; solo cambió el script.

Expected: el bloque `PostToolUse`/`Bash` se agrega/preserva junto al `enabledPlugins` existente; sin duplicados.

- [ ] **Step 3: Limpiar workspaces de eval**

Run: borrar todo workspace temporal de testeo (hard rule del repo).

---

## Task 8: Commit

- [ ] **Step 1: Commitear con identidad local**

Run:
```bash
git add -A
git -c user.name="MartinDele703" -c user.email="martin.deleon703@gmail.com" commit -m "feat(scaffold): review-loop por commit/slice + techo de tamano en planificacion

to-issues: techo ~400 lineas de logica con exclusiones. tdd: Step 5
'Close the slice' (commit + review-loop sin preguntar, multi-commit).
review-loop: modo commit/local. CLAUDE.md: lenguaje imperativo. Hook:
dispara tambien en git commit + mensaje imperativo. Espejado en ambas
skills; manifest regenerado.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

- [ ] **Step 2: Verificar el commit**

Run: `git log --oneline -1 && git status`
Expected: commit creado, working tree limpio.

---

## Self-review del plan (cobertura del spec)

- ① to-issues techo de tamaño → Task 1 ✓
- ② tdd Step 5 cerrar slice + multi-commit → Task 2 ✓
- ③ CLAUDE.md lenguaje imperativo + regla tamaño → Task 4 ✓
- ④ hook ampliado a git commit + mensaje imperativo → Task 5 ✓
- ⑤ review-loop modo commit/local + manejo RED → Task 3 ✓
- Espejado personal/southpoint → cada task lista las 2-4 rutas ✓
- Deploy + manifest → Task 6 ✓
- Evals (vacío + preexistente + hook + upgrade-merge) → Task 7 ✓
- Commit identidad local → Task 8 ✓
