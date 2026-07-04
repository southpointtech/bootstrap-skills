# Session Handoff — 2026-06-23 (self-bootstrap del repo en modo adopción)

## ▶ AL RETOMAR — qué quedó y qué falta

Esta sesión **auto-bootstrapeó el propio repo Bootstrap Skills** con `bootstrap-personal-project`
(modo adopción), para que la fuente de verdad de las skills opere bajo su propio workflow de 8 pasos.

- **Rama:** `chore/bootstrap-self` (creada desde `main`, NO desde `feat/alignment-gate-hook`, para no mezclar con el WIP del hook).
- **Commit:** `f67331f` — `chore: project scaffolding (AI workflow + skills)`. Working tree limpio salvo este handoff.
- **PENDIENTE PRINCIPAL:** la rama **NO está mergeada a `main`**. El usuario reservó el merge para después de revisar el diff él mismo. **No mergear sin que lo pida.** Para revisar: `git diff main..chore/bootstrap-self`.

## Qué es el proyecto

`C:\Repos\PERSONAL\Bootstrap Skills` es la **fuente de verdad** de las skills de Claude Code que bootstrapean proyectos:
- `bootstrap-southpoint-project` — proyectos cliente SOUTHPOINTLABS (DOMO/Zoho).
- `bootstrap-personal-project` — proyectos personales.
- `upgrade-bootstrap` — actualiza proyectos ya bootstrapeados al scaffold actual.
- `setup-mcp-workstation` — prepara una PC Windows 1× por máquina.

Editar las skills acá NO tiene efecto hasta deployar con `pwsh -NoProfile -File tools/sync-skills.ps1`.
Commits con identidad local `MartinDele703 <martin.deleon703@gmail.com>`.
El repo está en GitHub: `southpointtech/bootstrap-skills` (privado). `origin/main` puede estar algunos commits atrás del `main` local.

## Objetivo de ESTA sesión — bootstrapear el propio repo

El usuario invocó `/upgrade-bootstrap` dentro de este repo. Como el repo NO es un proyecto bootstrapeado
(no tenía `.bootstrap-manifest.json`), upgrade no aplicaba. El usuario decidió **correr el bootstrap acá**.
Al tener `CLAUDE.md` propio sin manifest, entró por **modo adopción (Step 0b)**: el contenido original se preservó y mergeó.

### Lo que se hizo (commit `f67331f`)
- **Backup verbatim** del `CLAUDE.md` original → `docs/agents/legacy-claude.md` (red de recuperación permanente, no se borra).
- **Scaffold copiado**: `.agents/skills/` (10 skills), `.claude/` (10 commands + `settings.json` + hook `review-loop-trigger.ps1`), `docs/ai-workflow/` (5 docs), `docs/agents/` (issue-tracker, triage-labels, domain), `.bootstrap-manifest.json`, `skills-lock.json`, `CONTEXT.md`, `docs/adr/.gitkeep`, `.scratch/`.
- **Merge del CLAUDE.md original (coverage map aprobado por el usuario):**
  - Sus **7 hard rules** → `## Hard rules` del CLAUDE.md canónico (verbatim).
  - Flujo editar→testear→deployar→commitear + lista de skills + puntero a HISTORIA → `docs/agents/domain.md` (`## Project-specific domain`).
  - Descripción one-line → `CONTEXT.md`.
- **`.gitignore` MERGEADO** (no pisado): scaffold + reglas de evals propias (`*-workspace/`, `eval-workspace/`).
- **`.mcp.json`: NO generado** (el usuario eligió "ninguno"; el repo no usa Firebase/Zoho/GitHub MCP).
- **`README.md` preservado** intacto (no se tocó).

## Decisiones de esta sesión
- Variante usada: **`bootstrap-personal-project`** (no Southpoint — el repo es personal).
- Rama dedicada `chore/bootstrap-self` desde `main`, para aislar del WIP de `feat/alignment-gate-hook`.
- Merge a `main` **deliberadamente NO hecho** — lo reservó el usuario para tras su revisión del diff.

## Gotcha encontrado y corregido
- Como `docs/` ya existía en el proyecto, `Copy-Item -Recurse -Force` de la carpeta `docs` del scaffold
  **anidó el contenido en `docs/docs/`** en vez de mergear. Hubo que desanidar a mano
  (`docs/docs/agents` → `docs/agents`, `docs/docs/ai-workflow` → `docs/ai-workflow`, borrar `docs/docs`).
  Es el mismo patrón que el bug `.agents/.agents`, pero disparado por **carpetas preexistentes del proyecto**.
- **TODO sugerido:** evaluar reflejar esto en el Step 2 de ambas skills bootstrap (la copia de directorios
  que ya existen en destino debería ser por contenido/merge, no `Copy-Item -Recurse` del directorio entero).
  Aplica también a `upgrade-bootstrap` si copia directorios.

## Estado de verificación
- ✅ Copia del scaffold verificada: `.agents/skills` = 10, `.claude/commands` = 10, `settings.json` + hook presentes, sin `.agents/.agents` ni `.claude/.claude`.
- ✅ `docs/` preservado (HISTORIA.md, TESTING.md, assets, superpowers) + subdirs nuevos correctos.
- ✅ Commit `f67331f` hecho con identidad local correcta. Working tree limpio (salvo este handoff).
- ⏳ Merge `chore/bootstrap-self` → `main`: PENDIENTE de revisión del usuario.
- ℹ️ No se corrieron los Pester tests (`tests/*.tests.ps1`): el scaffolding no tocó código de skills, solo agregó archivos al root.

## Pendientes / próximos pasos
1. ~~**Usuario:** revisar `git diff main..chore/bootstrap-self` y mergear a `main` cuando esté conforme.~~ **HECHO 2026-07-04** (fast-forward, rama borrada).
2. ~~(Opcional) Reflejar el gotcha `docs/docs` en el Step 2 de las skills bootstrap + `upgrade-bootstrap`.~~ **HECHO 2026-07-04**: la copia del Step 2 ahora vive en `skills/*/scripts/copy-scaffold.ps1` (archivo por archivo, mergea en dirs preexistentes; test en `tests/copy-scaffold.tests.ps1`). `upgrade-bootstrap` no necesitaba cambio: aplica el delta por ruta relativa del manifest, nunca copia directorios.
3. **Aparte (otra rama):** `feat/alignment-gate-hook` sigue con el alignment-gate hook en estado spec+plan, IMPLEMENTACIÓN PENDIENTE (plan de 7 tasks). Ver `docs/superpowers/`.

## Reglas del repo (no olvidar)
- Las dos skills bootstrap se mantienen **espejadas en estructura**; todo cambio de mecánica va en ambas. Solo difieren en DOMO e identidad git.
- Editar skills acá NO tiene efecto hasta `tools\sync-skills.ps1` (regenera los `.bootstrap-manifest.json`).
- La copia del Step 2 vive en `skills/*/scripts/copy-scaffold.ps1` — NO volver a inline-ar `Copy-Item <dir> -Recurse` (anida `docs\docs` si el destino existe) ni wildcard `scaffold\*` (anida `.agents\.agents`).
- `gitignore.txt` en assets aterriza como `.gitignore` (no renombrar en el repo).
- El `.bootstrap-manifest.json` es generado; lo regenera `sync-skills.ps1`.
- Rastros de testeo (workspaces de evals/sandboxes temp) se borran al terminar.

## Gotchas técnicos (vigentes)
- `run_loop.py` del skill-creator (optimizador de descripción) está **roto en Windows**.
- El warning git "LF will be replaced by CRLF" en los `.md` es pre-existente (archivos en LF) e inofensivo.
- `gh` tiene dos cuentas logueadas (`southpointtech` activa, `MartinDele703`); verificá la activa antes de operar sobre el repo en GitHub.
