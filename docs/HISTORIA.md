# Historia y decisiones de diseño

## Origen (2026-06-03)

Las skills nacen de la preparación del proyecto **Forecasting App** (SOUTHPOINTLABS): antes de tocar requerimientos o código se montó un modus operandi completo — CLAUDE.md con workflow de 8 pasos, `docs/ai-workflow/` (5 docs), `docs/agents/` (3 docs, patrón Matt Pocock), 9 skills custom (`grill-me`, `grill-with-docs`, `handoff`, `setup-matt-pocock-skills`, `tdd`, `to-issues`, `to-prd`, `triage`, `zoom-out`) con sus 9 comandos, `skills-lock.json` y estructura `CONTEXT.md` + `docs/adr/`. Ese setup probó funcionar (closing de requirements → SRS → tasks Zoho → implementación TDD) y se decidió empaquetarlo como skills reutilizables, creadas con `skill-creator`.

El snapshot de referencia es el commit inicial de Forecasting App (`c8da469`, "chore: initial commit — closing-requirements grill artifacts").

## Decisiones de diseño

1. **Dos skills, no una con modos**: decisión explícita de Martín. Southpoint = réplica verbatim (con DOMO/Zoho); personal = sin DOMO, persisten Playwright/Firebase/Azure/Zoho.
2. **Assets copiados, no regenerados**: el texto del workflow se mantiene idéntico entre proyectos; la skill copia `assets/scaffold/`, no improvisa contenido.
3. **Identidad git local por skill** (no toca config global): `southpointtech <mdeleon@agtium.com>` / `MartinDele703 <martin.deleon703@gmail.com>`. Branch `main`, commit `chore: project scaffolding (AI workflow + skills)`.
4. **El bootstrap termina en el bootstrap**: la skill cierra con handoff a `/grill-me` o `/grill-with-docs`; NO arranca requirements, PRD ni código (el paso 1 del workflow necesita al humano).
5. **Safety primero**: si `CLAUDE.md` o `docs/ai-workflow/` ya existen → stop and ask; archivos preexistentes nunca se sobrescriben (se scaffoldea alrededor).
6. **`gitignore.txt`** en assets para que el repo de la skill no lo trate como su propio ignore; aterriza como `.gitignore`.
7. **Workflow State Machine** (11 fases con transiciones recomendadas `/grill-with-docs` → `/to-prd` → `/to-issues` → `/tdd`, reporte de fin de fase, no avanzar sin aprobación): sección agregada por pedido de Martín a los templates de ambas skills y al CLAUDE.md real de Forecasting App — Claude como guía del proceso, no herramienta suelta.

## Evals (skill-creator, 2026-06-03)

3 test cases × (con skill / baseline sin skill), agentes en background sobre directorios temporales:
- eval-0: Southpoint, dir vacío ("KBS Inventory") — 8 assertions
- eval-1: personal, dir vacío (expense tracker) — 7 assertions
- eval-2: Southpoint con archivos preexistentes (src/index.js + README propio) — 4 assertions

| Métrica | Con skill (iter 2, final) | Con skill (iter 1) | Baseline |
|---|---|---|---|
| Pass rate | **100% ± 0** | 100% (con autocorrecciones) | 33% ± 29 |
| Tiempo | **73,0s ± 1,2** | 98,8s ± 26,6 | 211s ± 110 |
| Tokens | **33,6k ± 1,1k** | 38,6k ± 3,2k | 51,9k ± 28,9k |

**Bug encontrado y corregido en iter 2 (el hallazgo importante):** el Step 2 original combinaba `Copy-Item scaffold\* -Recurse` con copias explícitas de `.agents`/`.claude`. En PowerShell 7 el wildcard SÍ incluye dot-directories, y la copia explícita posterior anidaba duplicados (`.agents\.agents`, `.claude\.claude`) porque Copy-Item sobre un dir existente copia adentro en vez de mergear. Los 3 runs de iter 1 se autocorrigieron (commits fixup/amend); en iter 2 se reemplazó por **enumeración top-level** + verificación explícita (9 skills / 9 comandos / sin anidados) y los 3 runs salieron limpios con varianza ±1,2s. También se eliminaron 6 subdirs vacíos `.claude/skills/*` que se habían colado del working tree de Forecasting App.

**Fallos típicos del baseline (por qué existen las skills):** identidad git equivocada (3/3 runs), elegir stack e instalar dependencias antes del alignment (2/3 — uno hasta fijó React/Vite por ADR), omitir `.agents/skills` y `skills-lock.json` (3/3), branch `master`, contenido regenerado ≈ parecido pero no idéntico.

Los rastros de testeo (workspace, proyectos de prueba, gradings, benchmarks) se eliminaron al cierre por pedido de Martín. Este doc es el registro que sobrevive.

## Pendientes / ideas futuras

- (vacío — anotar acá lo que surja)
