# Cómo testear las skills

Las skills se testean con el **skill-creator** (`/skill-creator:skill-creator` en Claude Code), que orquesta: runs con skill + baseline en directorios temporales → grading con assertions → benchmark → viewer HTML para revisión humana.

## Test cases canónicos (re-usar estos)

1. **Southpoint, directorio vacío** — "Acabo de crear esta carpeta para un proyecto nuevo de Southpoint: un tablero de inventario para KBS (se llama 'KBS Inventory'). Dejame el directorio listo con todos los archivos base para arrancar, como hicimos en Forecasting App."
2. **Personal, directorio vacío** — "ok arranco un proyecto personal aca, una app para trackear mis gastos del mes. preparame el ambiente y el repo con el setup base antes de escribir nada de codigo"
3. **Southpoint, archivos preexistentes** — sembrar `src/index.js` y un `README.md` propio ("WIP - notas propias del proyecto") y pedir: "Este repo ya tiene un par de archivos del proyecto nuevo de Southpoint (KBS Inventory). Armame el scaffolding del workflow de AI sin romper lo que ya hay."

## Assertions clave (lo que define "pasa")

- Scaffold completo: CLAUDE.md (8 pasos + Workflow State Machine), 5 docs ai-workflow, 10 skills `.agents` (9 de mattpocock vía `skills-lock.json` + `review-loop` propia), 10 comandos `.claude`, 3 docs agents, `.gitignore` (con `.scratch/`), `skills-lock.json`, `.bootstrap-manifest.json`, README, CONTEXT.md stub, `docs/adr/`.
- Variante correcta: Southpoint menciona DOMO; personal CERO menciones a DOMO pero conserva Playwright/Firebase/Azure/Zoho.
- Git: branch `main`, **un solo commit**, autor exacto según variante, config local (global intacta).
- Sin duplicados anidados (`.agents\.agents`, `.claude\.claude`) — regresión del bug de iter 1.
- No se adelanta: sin package.json, sin src/ (en dirs vacíos), sin ADRs inventados, sin PRD.
- Preexistentes intactos byte a byte y commiteados.

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
3. **Legacy sin manifest** — proyecto bootstrapeado con la versión vieja (sin manifest): `hasProjectManifest=False`, detecta `missing` (los 2 de `review-loop`) y `customized` los que difieren; tras aplicar, siembra el manifest.
4. **Al día** — proyecto recién bootstrapeado: `missing/outdated/customized` vacíos, `uptodate` == 45.

Los fixtures determinísticos para los casos 1-2 y el re-sellado están en el plan `docs/superpowers/plans/2026-06-10-upgrade-bootstrap-skill.md` (Tasks 4-5); los casos 3-4 corren contra el scaffold instalado (Task 8).
