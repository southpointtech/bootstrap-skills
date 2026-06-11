# Adopción con merge de CLAUDE.md en `/bootstrap-...`

**Fecha:** 2026-06-11
**Estado:** Diseño aprobado (brainstorming) — pendiente plan de implementación
**Skills afectadas:** `bootstrap-southpoint-project`, `bootstrap-personal-project` (espejadas), `upgrade-bootstrap` (reuso de maquinaria)

## Problema

Hoy, al correr `/bootstrap-...` en un proyecto que no tiene el scaffold pero **sí tiene un `CLAUDE.md` propio** (hecho a mano), el Step 0 frena y deriva a `upgrade-bootstrap` (cambio del commit `8572d09`). Eso resuelve la confusión del mensaje, pero no le da al usuario lo que más valor tiene del bootstrap: **el flujo de trabajo de los 8 steps (la metodología)**. El proyecto se queda sin la metodología, o el usuario tiene que hacer un merge manual.

Lo que el usuario quiere: que `/bootstrap-...` sea el punto de entrada para **todo** proyecto sin bootstrap —vacío o ya empezado— y que, si hay un `CLAUDE.md` propio, **adopte la metodología sin perder el contexto ni la identidad del proyecto**.

## Modelo conceptual

La señal divisoria entre las dos skills es `.bootstrap-manifest.json`:

| Estado del proyecto | Skill | Acción |
|---|---|---|
| Sin manifest, vacío | `/bootstrap-...` | scaffold normal (sin cambios) |
| Sin manifest, empezado sin `CLAUDE.md` propio | `/bootstrap-...` | scaffold-around (sin cambios) |
| Sin manifest, empezado **con** `CLAUDE.md` propio | `/bootstrap-...` | **adopción + merge** (nuevo) |
| Con manifest | `/upgrade-bootstrap` | delta (sin cambios) |

Regla mental del usuario: *"bootstrap para lo que no tiene bootstrap (sea virgen o empezado); upgrade solo si ya lo tiene."*

Esto **reescribe** el Step 0 del commit `8572d09`: el caso "CLAUDE.md sin manifest" deja de derivar a upgrade y pasa a ser manejado por bootstrap en modo adopción. El caso "manifest presente → derivar a upgrade" se mantiene.

## Estrategia de merge (opción C: separar metodología de contexto)

El `CLAUDE.md` resultante es **canónico** (el template de 8 steps, idéntico entre proyectos). El contenido propio del proyecto se reubica según su naturaleza, usando los casilleros que el scaffold **ya define**:

- **Regla operativa genuina** (manda comportamiento, ej. "no confiar en el 2xx como prueba de arribo") → sección `Hard rules` del `CLAUDE.md` canónico.
- **Conocimiento de dominio** (qué hace el proyecto, integraciones, gotchas técnicos, branching model) → `docs/agents/domain.md`.
- **Descripción del proyecto** (one-liner) → `CONTEXT.md`.
- **Dudoso / no encaja** → se queda solo en el backup y se marca en el mapa para decisión del usuario.

Principio: separar el **cómo trabajamos** (metodología, uniforme en todos los proyectos) del **qué hacemos** (contexto, propio de cada uno). El `CLAUDE.md` ya referencia `docs/agents/domain.md` en su sección `Domain docs`, así que esto usa la arquitectura existente, no inventa estructura nueva.

## Salvaguardas (parte central del diseño, no opcionales)

El merge es **interpretativo** (Claude clasifica y reubica), no una copia determinística, así que hay riesgo de omisión, mala clasificación o parafraseo. Se neutraliza a **cero pérdida irrecuperable** con cuatro redes:

1. **Backup verbatim permanente.** Antes de tocar nada, el `CLAUDE.md` original se copia byte a byte a `docs/agents/legacy-claude.md`. Queda versionado en git, para siempre, nunca se borra. Aunque el merge se equivoque en todo, el original entero está recuperable.
2. **Merge por preservación, nunca por resumen.** Los bloques se mueven **textuales**; prohibido parafrasear o condensar. Un número, un nombre de webhook o un gotcha entran y salen idénticos.
3. **Mapa de cobertura verificable.** Tras clasificar, se muestra al usuario "cada bloque/heading del original → su destino" (Hard rules / domain.md / CONTEXT.md / solo-backup). Si un bloque no tiene destino, salta a la vista.
4. **Una aprobación global antes de aplicar.** El usuario ve el mapa completo con la clasificación propuesta y aprueba de una; puede corregir bloques puntuales antes de aplicar. Nada se mueve en silencio.

Honestidad del contrato: el riesgo de **equivocación** del merge existe, pero es **visible y corregible** (mapa + aprobación); el riesgo de **pérdida** se elimina (backup verbatim permanente).

## Flujo del modo adopción

Cuando el Step 0 detecta "sin manifest + `CLAUDE.md`/`docs/ai-workflow/` propio":

1. **Backup**: copiar `CLAUDE.md` → `docs/agents/legacy-claude.md` (determinístico, script).
2. **Scaffold-around**: traer los 44 archivos del scaffold **sin** pisar el `CLAUDE.md` del proyecto (el canónico todavía no se aplica).
3. **Clasificar** cada bloque del original en los cuatro destinos.
4. **Mapa**: presentar al usuario el mapeo bloque → destino, textual.
5. **Aprobación global** (con override puntual posible).
6. **Aplicar**: instalar el `CLAUDE.md` canónico con los bloques de regla operativa injertados en `Hard rules`; escribir el contexto en `domain.md` y `CONTEXT.md`; bloques verbatim.
7. **Sellar el manifest** marcando `CLAUDE.md` como **customized permanente**, para que un `upgrade-bootstrap` futuro nunca lo pise.

## Detalle técnico: sellado del manifest

El merge-base de 3 hashes de `upgrade-bootstrap` compara base (manifest) / actual (disco) / canónico (scaffold). Si se sellara `base = hash del CLAUDE.md mergeado`, un futuro cambio del template canónico daría `actual == base != canónico` → clasificado `outdated-safe` → **pisaría el merge**. No deseado.

Solución: para el `CLAUDE.md` adoptado, sellar `base = hash del CLAUDE.md canónico` (no el del archivo en disco). Así, futuro: `actual (mergeado) != base (canónico)` → `customized` → nunca se pisa. El `reseal-manifest.ps1` debe aceptar una excepción por archivo, o el flujo de adopción debe sellar `CLAUDE.md` aparte con el hash canónico. Decisión de implementación a resolver en el plan.

## Alcance

- Cambio **espejado** en ambas skills de bootstrap (hard rule del repo). Solo difieren en contenido DOMO e identidad git.
- Backup y sellado del manifest: **determinísticos** (PowerShell / reuso de `reseal-manifest.ps1`).
- Clasificación, mapa y aplicación del merge: **interpretativos** (prosa que Claude sigue), consistente con cómo están escritas las skills.
- Reuso de la maquinaria de `upgrade-bootstrap` para el sembrado del manifest, sin que el usuario invoque esa skill.

### Fuera de alcance (YAGNI)

- No se toca el flujo de proyecto vacío ni el de scaffold-around sin `CLAUDE.md`.
- No se cambia `upgrade-bootstrap` salvo lo necesario para el sellado del `CLAUDE.md` customized.
- No se automatiza la clasificación con heurísticas rígidas: Claude clasifica con criterio y el usuario valida.

## Testing (per `docs/TESTING.md`)

- **Nuevo caso canónico**: proyecto con `CLAUDE.md` propio (branching + gotchas + DOMO) sin manifest → adopta, mergea, preserva todo. Assertions:
  - `docs/agents/legacy-claude.md` es **byte-idéntico** al `CLAUDE.md` original.
  - Cada bloque del original aparece en el backup **y** en su destino (cobertura completa).
  - El `CLAUDE.md` final es el canónico de 8 steps + las reglas operativas injertadas.
  - El manifest sella `CLAUDE.md` como customized (futuro upgrade no lo pisa).
  - Variante correcta (southpoint menciona DOMO; personal no).
- **Validación con skill-creator**: A/B contra la versión actual, escenario CLAUDE.md-con-contenido.
- **Fixtures** para el sellado del manifest (caso "adoptado" no debe clasificarse `outdated`).

## Decisiones tomadas en el brainstorming

- Estrategia de merge: **opción C** (separar metodología vs contexto).
- Backup en: **`docs/agents/legacy-claude.md`** (versionado, permanente).
- Automatismo: **mapa global + 1 aprobación** (con override puntual).
- Trigger: **`/bootstrap-...` maneja todo proyecto sin manifest**; `/upgrade-bootstrap` solo con manifest.
