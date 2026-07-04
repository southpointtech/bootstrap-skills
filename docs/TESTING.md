# Cómo testear las skills

Las skills se testean con el **skill-creator** (`/skill-creator:skill-creator` en Claude Code), que orquesta: runs con skill + baseline en directorios temporales → grading con assertions → benchmark → viewer HTML para revisión humana.

## Test cases canónicos (re-usar estos)

1. **Southpoint, directorio vacío** — "Acabo de crear esta carpeta para un proyecto nuevo de Southpoint: un tablero de inventario para KBS (se llama 'KBS Inventory'). Dejame el directorio listo con todos los archivos base para arrancar, como hicimos en Forecasting App."
2. **Personal, directorio vacío** — "ok arranco un proyecto personal aca, una app para trackear mis gastos del mes. preparame el ambiente y el repo con el setup base antes de escribir nada de codigo"
3. **Southpoint, archivos preexistentes** — sembrar `src/index.js` y un `README.md` propio ("WIP - notas propias del proyecto") y pedir: "Este repo ya tiene un par de archivos del proyecto nuevo de Southpoint (KBS Inventory). Armame el scaffolding del workflow de AI sin romper lo que ya hay."
4. **Southpoint, adopción (CLAUDE.md propio sin manifest)** — sembrar un `CLAUDE.md` hecho a mano (branching model main/develop + un gotcha técnico + una mención a DOMO) y un `worker.js`, sin `.bootstrap-manifest.json`, y pedir: "agregale el bootstrap a este proyecto". Debe entrar en **modo adopción** (Step 0b), no frenar ni derivar a upgrade-bootstrap.

## Assertions clave (lo que define "pasa")

- Scaffold completo: CLAUDE.md (8 pasos + Workflow State Machine), 5 docs ai-workflow, 10 skills `.agents` (9 de mattpocock vía `skills-lock.json` + `review-loop` propia), 10 comandos `.claude`, 3 docs agents, `.gitignore` (con `.scratch/`), `skills-lock.json`, `.bootstrap-manifest.json`, `.claude/settings.json`, `.claude/hooks/review-loop-trigger.ps1`, `.claude/hooks/alignment-gate.ps1`, README, CONTEXT.md stub, `docs/adr/`.
- Variante correcta: Southpoint menciona DOMO; personal CERO menciones a DOMO pero conserva Playwright/Firebase/Azure/Zoho.
- Git: branch `main`, **un solo commit**, autor exacto según variante, config local (global intacta).
- Sin duplicados anidados (`.agents\.agents`, `.claude\.claude`) — regresión del bug de iter 1.
- No se adelanta: sin package.json, sin src/ (en dirs vacíos), sin ADRs inventados, sin PRD.
- Preexistentes intactos byte a byte y commiteados.
- Modo adopción: `docs/agents/legacy-claude.md` existe y es **byte-idéntico** al `CLAUDE.md` original sembrado.
- Modo adopción: el `CLAUDE.md` final es el canónico (contiene "Workflow State Machine"); las reglas operativas del original aparecen en su sección `## Hard rules`; el conocimiento de dominio del original aparece en `docs/agents/domain.md`.
- Modo adopción: cada bloque del original quedó representado (en `legacy-claude.md` + su destino); ningún bloque se perdió en silencio.
- Modo adopción: tras adoptar, `compare-scaffold.ps1` clasifica `CLAUDE.md` como **customized** (ni `outdated` ni `uptodate`), confirmando que un upgrade futuro no lo pisa.

## Gotchas operativos del entorno de testing

- Los agentes baseline en el entorno de Forecasting App pueden copiar del repo real → baseline inflado; correr los tests desde un cwd neutro si se quiere baseline puro.
- El viewer (`generate_review.py`) en Windows necesita `$env:PYTHONUTF8 = "1"` (crash cp1252 si no).
- El agregador (`scripts.aggregate_benchmark`) espera `eval-N/<config>/run-1/grading.json` y un bloque `summary` `{pass_rate, passed, failed, total}` en cada grading.
- Si un run baseline corre `npm install`, borrar su `node_modules` antes de levantar el viewer (el escaneo recursivo se cuelga).
- Borrar el workspace de evals al terminar (regla del repo).

## Testeo de `upgrade-bootstrap`

La skill que actualiza proyectos ya bootstrapeados se testea con fixtures (no con skill-creator), porque su lógica vive en los scripts `compare-scaffold.ps1` y `reseal-manifest.ps1`. Casos de regresión:

1. **Manifest + desactualizado-no-tocado** — proyecto con `.bootstrap-manifest.json` y un archivo cuyo hash actual == base pero != canónico → debe clasificar `outdated` (seguro de actualizar).
2. **Manifest + personalizado** — archivo cuyo hash actual != base → debe clasificar `customized` (no pisar).
3. **Legacy sin manifest** — proyecto bootstrapeado con la versión vieja (sin manifest): `hasProjectManifest=False`, detecta `missing` (los 2 de `review-loop`, y ahora también `.claude/hooks/alignment-gate.ps1`) y `customized` los que difieren; tras aplicar, siembra el manifest.
4. **Al día** — proyecto recién bootstrapeado: `missing/outdated/customized` vacíos, `uptodate` == 48.

Los fixtures determinísticos para los casos 1-2 y el re-sellado están en el plan `docs/superpowers/plans/2026-06-10-upgrade-bootstrap-skill.md` (Tasks 4-5); los casos 3-4 corren contra el scaffold instalado (Task 8).

## Testeo de la copia del scaffold (`copy-scaffold.ps1`)

La copia del Step 2 (`skills/*/scripts/copy-scaffold.ps1`, espejada en ambas skills bootstrap) se testea con un runner sin Pester: `pwsh -NoProfile -File tests/copy-scaffold.tests.ps1` (fixtures en directorios temporales, imprime `TODOS LOS TESTS PASARON` o `N test(s) FALLARON`). Casos cubiertos:

- **Destino vacío** — aterrizan los 48 archivos, sin `.agents/.agents` ni `.claude/.claude`, `gitignore.txt` → `.gitignore` con contenido idéntico.
- **Regresión `docs/docs`** — `docs/` y `docs/agents/` preexistentes en el proyecto → el contenido se mergea (sin anidar) y los archivos propios quedan intactos (gotcha del self-bootstrap 2026-06-23).
- **Dot-dirs preexistentes** — `.claude/` con archivos propios → merge sin anidar ni pisar lo ajeno.
- **Conflicto de archivo** — un `CLAUDE.md` preexistente es reemplazado por el canónico (semántica del Step 2; en adopción el original ya está stasheado).
- **Paths con corchetes** — un proyecto `...[v2]` copia igual (paths literales, sin interpretación de wildcards).
- **Espejado** — los dos `copy-scaffold.ps1` son byte-idénticos (hash SHA256).

## Testeo del hook `review-loop-trigger` y del merge de settings

El script del hook y `merge-settings.ps1` se testean con fixtures determinísticos (repos git temporales), no con skill-creator. Runner: `pwsh -NoProfile -File tests/review-loop-trigger.tests.ps1` (imprime `TODOS LOS TESTS PASARON` o `N test(s) FALLARON`). **Importante:** el hook resuelve el repo desde `cwd`; en los tests, `cwd` debe ser un path Windows real (como el que pasa Claude Code), no un path MSYS `/tmp/...`, o `Set-Location` falla y el hook corre contra el repo equivocado. Casos cubiertos:

- **No-op no-git** — un comando que no es `gh pr create`/`git push`/`git commit` no emite nada.
- **Dispara post-PR/push** — `git push` en un branch de feature emite `additionalContext`.
- **Dispara post-commit** — `git commit` en un branch de feature emite la orden imperativa de correr `/review-loop` (cubre repos locales sin remote).
- **Dedupe por SHA** — segundo disparo sobre el mismo commit no emite; tras un commit nuevo vuelve a disparar.
- **Base dinámica** — estar en la base no dispara; `gh pr create --base develop` usa `develop` (no hardcodea `main`).
- **Merge de settings** — `settings.json` ausente → copia el canónico; preexistente propio (p. ej. con `enabledPlugins`) → agrega el hook sin pisar lo demás; correrlo dos veces no duplica la entrada.

El hook `alignment-gate` (PreToolUse) se testea aparte, con su propio runner: `pwsh -NoProfile -File tests/alignment-gate.tests.ps1` (mismos fixtures determinísticos, mismo formato de salida). Casos cubiertos:

- **Deny en código, sesión nueva** — `Write`/`Edit` sobre un archivo de código (`src/app.py`) en una sesión sin actividad previa → `deny` + ofrece `grill`.
- **Allowlist no-código pasa libre** — `.md`, `CLAUDE.md`, `.scratch/**` (clave: no romper la escritura del PRD) y `.json` de config no disparan nada.
- **Dedup por sesión** — un segundo `Edit`/`Write` de código dentro de la misma `session_id` no vuelve a disparar; una `session_id` distinta sí.
- **MultiEdit** — detecta código dentro de `edits[].file_path` (no solo `tool_input.file_path`).
- **Espejado** — `alignment-gate.ps1` es byte-idéntico entre `bootstrap-personal-project` y `bootstrap-southpoint-project` (hash SHA256).
- **`settings.json` válidos con ambos hooks** — en ambos scaffolds, `settings.json` parsea como JSON y declara `alignment-gate` en `PreToolUse` a la vez que conserva `review-loop-trigger` en `PostToolUse`.

## Testeo de `gen-mcp-json` (MCP por área)

El generador del `.mcp.json` por proyecto (`scripts/gen-mcp-json.ps1`, uno por skill) se testea con un runner sin Pester: `pwsh -NoProfile -File tests/gen-mcp-json.tests.ps1` (corre ambos scripts como subproceso y verifica `.mcp.json` + el resumen JSON de stdout). Cubre: happy path personal y southpoint, ninguna selección (no escribe archivo), clave inválida por área (`no-existe`, y `zoho-personal` rechazada en southpoint), no pisar sin `-Force`, y `-Force` sobrescribe. Los secretos quedan como literales `${VAR}`.

Evals manuales del flujo del bootstrap (corridos 2026-06-11, ambos OK):

1. **Directorio vacío** — `gen-mcp-json.ps1` personal con `-Servers firebase,zoho-personal` → escribe `.mcp.json` con esos dos servers, el JSON parsea, resumen con `requiredEnvVars=[ZOHO_PERSONAL_MCP_URL]`.
2. **`.mcp.json` preexistente** — sembrar `{"mcpServers":{"MIO":{}}}` y correr `gen-mcp-json.ps1` southpoint con `-Servers domo` sin `-Force` → exit ≠ 0 y `MIO` intacto (no se pisa).

Los workspaces temporales se borran al terminar cada eval.

## Testeo de setup-mcp-workstation

Los dos scripts de la skill se testean con runners sin Pester, cada uno imprime `TODOS LOS TESTS PASARON` o `N test(s) FALLARON` y devuelve el exit code acorde:

- `pwsh -NoProfile -File tests/apply-env.tests.ps1`
- `pwsh -NoProfile -File tests/install-clients.tests.ps1`

**`apply-env.tests.ps1`** cubre: validación de la config (campo faltante → error que **nombra** el campo; config inexistente → error), que la salida **no filtra valores de secretos** (solo nombres de vars + estado), y todo corre con `-DryRun` para no ensuciar el entorno real.

**`install-clients.tests.ps1`** cubre: todos los prereqs presentes (usa `pwsh` como stand-in vía `-GitCmd`/`-PythonCmd`/`-NpxCmd`), y que el comando referencie el repo oficial de DOMO + `requirements.txt`; Git ausente (reporta el prereq, **NO clona**, igual sigue con Playwright), Python ausente (no intenta pip), npx ausente (reporta Node), todo en `-DryRun` (no clona ni instala nada de verdad).

El flujo end-to-end de la skill se evalúa con skill-creator usando el caso *"configurá mi máquina para Southpoint"* (verifica que pida git/DOMO/Zoho, escriba el archivo de config y llame a los dos scripts), con `-DryRun` o un `$env:USERPROFILE` temporal para no tocar el entorno real. El workspace de evals se borra al terminar.
