# Spec — Mejoras al bootstrap (Ras Mic + greploop + video MYTHOS/Fable 5)

- **Fecha:** 2026-06-09
- **Estado:** aprobado para planificar
- **Fuentes:** reporte del flujo de Ras Mic, skill `greploop` de greptileai, skill `grep-loop-review-workflow` de micky-podcast, reporte del video "MYTHOS 5 / Claude Fable 5".

## Objetivo

Incorporar al scaffold de bootstrap las metodologías de esas fuentes que **suman** al flujo de trabajo, descartando lo que es stack/entorno ajeno o no scaffoldeable. Son **6 cambios**, aplicados **espejados** en `bootstrap-personal-project` y `bootstrap-southpoint-project`.

## Principios y restricciones

- Las dos skills se mantienen espejadas en estructura; solo difieren en contenido DOMO e identidad git. Todo cambio se aplica a ambas.
- Respetar las hard rules del repo: copia por enumeración top-level (sin wildcard `scaffold\*`), no dejar directorios vacíos en `assets/scaffold/`, `gitignore.txt` no se renombra en el repo.
- Naturaleza de los cambios: **reglas duras universales** (decisión del usuario), salvo las dos notas de estilo (secciones 5 y 6).
- Si un cambio al `CLAUDE.md` template aplica también al `CLAUDE.md` real de Forecasting App, evaluarlo (hard rule del repo) — fuera del alcance de implementación de este spec, pero a registrar.

## Cambios

### 1. Seguridad: anti supply-chain `[alto valor]`

Regla dura nueva en `CLAUDE.md` → "Hard rules":

> No instalar dependencias publicadas hace menos de 14 días sin aprobación humana explícita (mitiga ataques de cadena de suministro recientes). Ante una dependencia nueva, verificar su fecha de publicación antes de agregarla.

Check adicional en `QA_CHECKLIST.md` → "During Implementation":

> `[ ] Dependencias nuevas tienen ≥14 días de publicadas (o aprobación explícita)`

### 2. PRs mínimos + stacked (regla dura) `[alto valor]`

Dos reglas duras, redactadas al estilo cualitativo de micky/greptileai con un número operativo:

> - Cada slice es una unidad pequeña y revisable. Objetivo: ≤ ~400 líneas de cambio por PR. Un diff cercano a los miles de líneas rompe el loop de review (reviewer y agente pierden precisión); si un slice supera ~400 líneas, dividirlo antes de implementar.
> - Cuando los slices dependen entre sí, encadenarlos con stacked PRs en vez de un PR grande.

Aterrizaje:
- `CLAUDE.md` → "Hard rules" (las dos reglas).
- `AI_DEVELOPMENT_WORKFLOW.md` → paso 3 "Vertical Slice Planning": cada slice debe caber en un PR ≤ ~400 líneas y, si encadenan, stackearse.
- `DEPLOYMENT_RULES.md` → "General": no abrir PRs gigantes; preferir cadena stackeada.

### 3. Skill #10 `review-loop` (GP Loop adaptado) `[alto valor]`

Nueva skill custom que replica la mecánica de `greploop`/GP-Loop usando `/code-review` nativo de Claude Code como motor (sin Greptile, Qodo ni servicios de pago; sin requerir PR ni remoto). Archivos nuevos:

- `.agents/skills/review-loop/SKILL.md`
- `.claude/commands/review-loop.md` (comando `/review-loop`)

**Mecánica de la skill:**

1. Pre-flight: ¿el diff es muy grande para revisar confiable? Si sí → sugerir dividir antes de loopear (conecta con el cambio 2).
2. Review: correr `/code-review` sobre el diff.
3. Procesar: leer hallazgos; arreglar solo los reales y relevantes (guardrail anti sobre-corrección; no reescribir código no relacionado).
4. Tests: agregar/actualizar tests por cada fix; correr tests/typechecks.
5. Re-review: volver a correr `/code-review`.
6. Repetir hasta: cero hallazgos de severidad media/alta, o máx 5 turnos, o bloqueo por una decisión humana → frenar y reportar.
7. Reporte final: lista de hallazgos resueltos + estado de tests.

**Condición de salida:** `/code-review` no da puntaje numérico (a diferencia del 5/5 de Greptile); da hallazgos clasificados por severidad. La salida se define como **cero hallazgos de severidad media/alta** (o máx 5 turnos), conservando la mecánica de iteración autónoma.

**Integración con el flujo:**
- `AI_DEVELOPMENT_WORKFLOW.md` paso 7 "Clean-Context Review" invoca `/review-loop`.
- `CLAUDE.md` → "Workflow State Machine": recomendar `/review-loop` en la transición post-implementación, antes de QA final/deploy.

**Costo de mantenimiento (subir 9→10 skills):** actualizar en ambas skills bootstrap todos los lugares que hoy dicen "9":
- `SKILL.md` de bootstrap, Step 2: verificación "9 skill directories" y "9 commands" → 10.
- `SKILL.md` de bootstrap, Step 2: línea de entrega ("9 skills / 9 commands") → 10.
- `SKILL.md` de bootstrap, descripción YAML que enumera las skills custom: agregar `review-loop`.
- `docs/TESTING.md` (raíz del repo): assertion "9 skills `.agents`, 9 comandos `.claude`" → 10.

**Decisión sobre `skills-lock.json`:** NO se modifica. El lockfile trackea solo las 9 skills sincronizadas desde `mattpocock/skills` (con hash upstream); lo consume `setup-matt-pocock-skills`. `review-loop` es una skill **propia** del scaffold, sin upstream, así que vive como archivo estático del template y queda fuera del lockfile. En el `SKILL.md` de bootstrap se aclara que de las 10 skills, 9 son sincronizadas (lockfile) y `review-loop` es propia.

### 4. Código como documentación `[alto valor]`

Regla dura en `CLAUDE.md`:

> Para librerías críticas o de las que el agente tiende a alucinar API, traer el código fuente real al repo (p. ej. `docs/vendor/<lib>/`) y apuntar al agente a ese código, en vez de confiar en su memoria o en documentación potencialmente desactualizada.

**Decisión de diseño:** NO se scaffoldea un `docs/vendor/` vacío (violaría la hard rule de no dejar dirs vacíos; git no lo trackearía). Es solo la regla declarativa; el directorio nace cuando el primer proyecto lo necesita.

### 5. Service Layer Abstraction `[medio valor]`

Regla de estilo en `CLAUDE.md` → "Preferred project style":

> Estructurar la lógica en capas de servicio reutilizables, para que el agente llame a funciones existentes en lugar de duplicarlas. Antes de escribir lógica nueva, buscar si ya existe un servicio que la cubra.

Refuerza el existente "Favor deep modules with simple interfaces".

### 6. Nota de selección de modelo `[medio valor — único aporte del video]`

Nota (no regla rígida) en `CLAUDE.md`:

> Usar el modelo más capaz para lógica de negocio, arquitectura y refactors de riesgo; reservar modelos más livianos/rápidos para tareas mecánicas o de bajo riesgo.

Sin precios, sin benchmarks, sin nombres de modelo concretos (envejecen; además varios datos del video no son verificables).

## Fuera de alcance (YAGNI)

Greptile/Qodo/PR-Agent como dependencia, Cursor, stack SvelteKit/Convex, Whisper Flow, vision-to-code, migraciones masivas, specs/precios/benchmarks de Fable/Mythos, 2FA/password managers. No es scaffoldeable o no aplica al flujo.

## Archivos afectados (×2, espejado salvo variantes DOMO)

Por cada skill (`bootstrap-personal-project`, `bootstrap-southpoint-project`):

- `assets/scaffold/CLAUDE.md` — cambios 1, 2, 4, 5, 6.
- `assets/scaffold/docs/ai-workflow/AI_DEVELOPMENT_WORKFLOW.md` — cambios 2, 3.
- `assets/scaffold/docs/ai-workflow/DEPLOYMENT_RULES.md` — cambio 2.
- `assets/scaffold/docs/ai-workflow/QA_CHECKLIST.md` — cambio 1.
- `assets/scaffold/.agents/skills/review-loop/SKILL.md` — nuevo (cambio 3).
- `assets/scaffold/.claude/commands/review-loop.md` — nuevo (cambio 3).
- `SKILL.md` (de la skill bootstrap) — conteos 9→10 y enumeración (cambio 3).
- `assets/scaffold/skills-lock.json` — **no se modifica** (ver decisión arriba).

Y una vez (raíz del repo, no por skill):

- `docs/TESTING.md` — assertion de conteos 9→10 (cambio 3).

## Validación posterior (no parte de este spec, pero requerida antes de cerrar)

1. Testear con skill-creator: eval de directorio vacío + eval de archivos preexistentes (mínimo de `docs/TESTING.md`).
2. Verificar conteos: `.agents/skills` con 10 directorios, `.claude/commands` con 10 archivos, sin `.agents/.agents` ni `.claude/.claude`.
3. Deployar con `tools/sync-skills.ps1`.
4. Commitear con identidad local `MartinDele703 <martin.deleon703@gmail.com>`.
5. Borrar cualquier rastro de testeo.
