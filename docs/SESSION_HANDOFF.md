# Session Handoff — 2026-07-06 (bootstrap compartible: spec + plan listos, ejecutar con subagentes)

## ▶ AL RETOMAR — estado y qué hacer

Rama actual: **`main`**, working tree limpio. Commits locales `6367e9e` (spec) y `45f7389` (plan) **sin pushear** a `origin/main` (pushear con la cuenta `southpointtech` cuando se quiera).

**PRÓXIMA ACCIÓN ÚNICA:** ejecutar el plan `docs/superpowers/plans/2026-07-06-bootstrap-compartible.md` con **`superpowers:subagent-driven-development`** (elección explícita del usuario). El brainstorming y el spec ya están aprobados — NO re-abrir diseño ni volver a preguntar lo decidido.

Reglas para la ejecución con subagentes:

- **Prohibir explícitamente `git checkout` / `git branch` a los subagentes implementadores** (memoria persistente: se van de rama solos). El orquestador maneja las ramas.
- 3 slices, cada uno en su feature branch: `feat/scaffold-english` → `feat/bootstrap-ai-project` → `feat/export-shareable` (en orden; cada uno mergea a main antes del siguiente).
- El hook `review-loop-trigger` dispara `/review-loop` en cada commit de feature branch: obedecerlo hasta que cierre.
- El hook `alignment-gate` va a frenar el primer edit de código de la sesión: el trabajo YA está alineado (spec aprobado) — reintentar y seguir.

## Qué se hizo en esta sesión (2026-07-06)

1. **Brainstorming completo del "bootstrap compartible"** (frente #1 del roadmap) con decisiones aprobadas por el usuario.
2. **Spec escrito y commiteado:** `docs/superpowers/specs/2026-07-06-bootstrap-compartible-design.md` (commit `6367e9e`).
3. **Plan de implementación escrito y commiteado:** `docs/superpowers/plans/2026-07-06-bootstrap-compartible.md` (commit `45f7389`) — 12 tasks en 3 slices + post-merge, con todo el contenido exacto (traducciones, scripts, tests) inline. Self-review pasado.

## Decisiones de diseño aprobadas (NO re-litigar)

- **Audiencia:** terceros corren el bootstrap en su propia máquina → skill 100% autocontenida.
- **Distribución:** repo público GitHub `MartinDele703/ai-project-bootstrap` (bootstrap + upgrade-bootstrap + README + install.ps1); actualizaciones vía git pull + re-install.
- **Enfoque A:** tercera skill espejada `skills/bootstrap-ai-project` en este repo; el repo público es espejo de publicación vía `tools/export-shareable.ps1`. Se descartó parametrizar con flavors y el fork one-time.
- **Zoho → genericizado** a "your issue tracker (GitHub Issues, Jira, Linear, …)"; tracker local `.scratch/` se preserva.
- **Identidad git:** la skill nueva NO la toca (usa la global del tercero; si falta, pide configurarla y espera).
- **Catálogo MCP compartible:** `firebase` + `github` (sin zoho-personal).
- **Idioma:** inglés puro en prosa/cuerpo/mensajes, PERO **las frases-trigger en español de los frontmatter `description:` se conservan en las 3 variantes** (bilingües; decisión posterior al spec, refinada en el planning — prevalece sobre el "inglés puro" del spec para los triggers).
- **Anglicización del canónico:** la prosa en español de los archivos compartidos del scaffold se traduce TAMBIÉN en personal y southpoint, para byte-identidad triple.
- **Gate anti-fuga:** marcadores case-insensitive `zoho, domo, MartinDele703, martin.deleon, southpoint` en `tools/leak-markers.txt` (fuente única para test + export). El README público NO lleva URL absoluta del repo (dispararía el marcador MartinDele703).
- **Plataforma v1:** pwsh 7+ requerido (cross-platform), sin port a bash.

## Datos técnicos descubiertos (importan al implementar)

- Las 2 skills existentes comparten 43/52 archivos byte-idénticos; divergen en 9 (SKILL.md, CLAUDE.md, 5 docs ai-workflow, gen-mcp-json.ps1, manifest).
- `.claude/commands/review-loop.md` NO es byte-idéntico a `.agents/skills/review-loop/SKILL.md` → traducir por bloque en los 4 archivos (2 por skill), no copiar uno sobre otro.
- `tests/review-loop-trigger.tests.ps1:35` asserta `"review-loop AHORA"` → la traducción del hook exige actualizar ese assert a `"review-loop NOW"` (el plan lo hace test-first).
- `tests/alignment-gate.tests.ps1` asserta `deny` + `grill` → sobrevive a la traducción sin cambios.
- El typo `proceds` está en el mensaje de `alignment-gate.ps1` (ambos scaffolds) — el plan lo corrige gratis en la traducción (follow-up Minor #4 del handoff anterior, queda cerrado).
- `upgrade-bootstrap` lee `generatedFrom` del manifest → integra la tercera skill sin cambios estructurales; solo se genericiza su redacción (menciones a las 2 skills, heurística legacy línea 22, guardrail línea 75, 8 strings de scripts — tabla exacta en el plan).
- El manifest del scaffold tiene campos `variant`, `generatedFrom`, `version`, `files` — el test del export asserta `generatedFrom -eq "bootstrap-ai-project"`.
- `tools/sync-skills.ps1` y `tools/gen-manifest.ps1` operan sobre el glob `bootstrap-*-project` → la skill nueva obtiene manifest + deploy gratis.
- Español en el scaffold: 31 ocurrencias acentuadas en 14 archivos + español sin acentos en hooks/copy-scaffold — el plan lista los reemplazos exactos; los `description:` con triggers en español NO se tocan.

## Tests

- Suite actual (6 archivos en `tests/`, runner sin Pester): todos pasaban al inicio de la sesión; no se tocó código en esta sesión (solo docs).
- Tests nuevos que el plan crea: `mirror.tests.ps1` (Slice 1, guard — pasa de entrada), `shareable-leaks.tests.ps1` (Slice 2, RED→GREEN), `export-shareable.tests.ps1` (Slice 3, RED→GREEN). Se extiende `gen-mcp-json.tests.ps1`.

## Pendientes / TODOs

1. Ejecutar el plan (3 slices + Task 12 post-merge: sync-skills + eval descartable + limpieza).
2. Pushear `main` a origin (cuenta southpointtech) cuando el usuario quiera.
3. **Export real al repo público = paso MANUAL del usuario** (crear `MartinDele703/ai-project-bootstrap` en GitHub, clonar, correr export, revisar diff, push con MartinDele703). NO hacerlo sin que lo pida.
4. Follow-ups Minor previos (handoff 2026-07-05): quedan 1, 2, 3 y 5 (el 4, typo proceds, lo cierra el Slice 1).
5. Roadmap tras esta feature: descubrir skills/loops nuevos auditando ambos árboles de repos → mejoras generales del scaffold.
6. Externo: Forecasting App y KBS siguen pendientes de upgrade/bootstrap. Tras mergear esta feature, este repo y los demás verán los archivos traducidos como `outdated-safe` en su próximo `/upgrade-bootstrap` (esperado).

## Reglas del repo (no olvidar)

- Editar skills acá NO tiene efecto hasta `tools\sync-skills.ps1`.
- Manifest generado, nunca a mano (`tools/gen-manifest.ps1`). Rastros de testeo se borran.
- Identidad git local de ESTE repo: MartinDele703; push a origin: solo cuenta `southpointtech` (MartinDele703 da 403).
- Espejado: tras el Slice 2 son TRES skills espejadas; `tests/mirror.tests.ps1` lo verifica determinísticamente.
- La copia del Step 2 vive en `skills/*/scripts/copy-scaffold.ps1` — NO volver a `Copy-Item <dir> -Recurse` ni wildcard.
- Commits en español estilo conventional (`feat(...)`, `docs(...)`, `test(...)`).

## Próximos 3 pasos recomendados

1. Invocar `superpowers:subagent-driven-development` con el plan `docs/superpowers/plans/2026-07-06-bootstrap-compartible.md`, empezando por Slice 1 (`feat/scaffold-english`, Tasks 1–4).
2. Al cerrar cada slice: review-loop limpio → merge a main → borrar branch → siguiente slice.
3. Post-merge del Slice 3: Task 12 (deploy + eval descartable + reporte al usuario para el export manual).
