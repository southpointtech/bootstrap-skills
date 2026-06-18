# Alignment Gate Hook — Design

**Fecha:** 2026-06-18
**Estado:** Aprobado (brainstorming), pendiente de plan de implementación
**Repo:** Bootstrap Skills (fuente de verdad de las skills de bootstrap)

## Problema

El workflow de 8 pasos del scaffold tiene una asimetría de enforcement:

| Paso del workflow | Enforcement hoy |
|---|---|
| **Paso 1 — Alignment / Grill Me** | ❌ Solo texto blando en `CLAUDE.md` ("Claude must not jump directly from requirements to code", "must not move from one phase to the next without approval"). Nada lo fuerza. |
| **Paso 7 — Review loop** | ✅ Hook duro `review-loop-trigger.ps1` (`PostToolUse` en `git commit/push/pr create`) que inyecta la orden de correr `/review-loop`. |

El **final** del workflow está blindado con un hook determinístico; el **inicio** (el grill/alignment) depende 100% de que el agente se autodiscipline leyendo `CLAUDE.md`.

**Caso real (2026-06):** una usuaria arrancó una sesión en modo "fix this → implement that" sobre un proyecto ya existente (migración App Studio → Pro Code, trabajo no-trivial). El agente saltó directo de requisitos a código sin pasar por el alignment. Su explicación lo confirma: *"El hook de workflow no frenó la ejecución"* — racionalizando un hook que **no existe**. No fue mala suerte: es el agujero estructural descrito arriba.

## Objetivo

Hacer el **inicio** del workflow tan determinístico como el final, sin trabar trabajo trivial legítimo ni auto-ejecutar nada. El hook debe **detectar** que aún no hubo alignment para el trabajo actual y hacer que el agente **se lo ofrezca al usuario**, frenando el piloto automático "fix→implement" una sola vez al arrancar.

## Decisiones de diseño (brainstorming)

1. **Mecanismo:** hook `PreToolUse` (duro, frena la herramienta). Simétrico al `review-loop-trigger` que es `PostToolUse`.
2. **Señal de estado:** gate **por sesión** + override implícito. No intenta adivinar leyendo artefactos del proyecto (`CONTEXT.md`, `docs/adr/` persisten entre features y darían falsos negativos). Pone el check en el momento clave —el primer `Edit`/`Write` de código— igual que el review-loop pone el check en el commit.
3. **Scope (qué dispara):** allowlist de no-código pasa siempre libre; el resto cuenta como código y dispara el gate. Evita el deadlock de no poder alinear/documentar porque el gate frena el `Edit`.
4. **Dureza:** **speed bump** — frena una vez, el agente reconsidera, y puede proceder. No es un bloqueo permanente ni exige que exista un PRD.
5. **Acción al frenar:** el agente **ofrece** al usuario alinear (`/grill-me` o `/grill-with-docs`, o seguir si es trivial) y **espera la decisión**. NUNCA auto-ejecuta el grill ni sigue codeando solo.
6. **Re-armado:** una sola vez por sesión. Tras el primer aviso, el `CLAUDE.md` (enforcement blando que ya existe) gobierna el resto. Persistencia más fina queda **fuera de alcance** (ver abajo).

## Componente: `alignment-gate.ps1`

Hook `PreToolUse`, matcher `Edit|Write|MultiEdit`, registrado en `.claude/settings.json` junto al `PostToolUse` existente.

### Lógica (primer match gana; todo camino que no aplica termina en `exit 0` silencioso)

1. **Leer stdin** → JSON del evento. Extraer `session_id`, `cwd`, `tool_input.file_path`. Sin `file_path` → `exit 0`.
2. **Allowlist no-código** → si el `file_path` cae en la allowlist, `exit 0` (pasa libre):
   - Cualquier `*.md`
   - `docs/**`, `.scratch/**`, `.agents/**`, `.claude/**`
   - `CONTEXT.md`, `CLAUDE.md`
   - Configs: `*.json`, `*.yaml`, `*.yml`, `*.toml`, `.gitignore`
   - (El `file_path` se normaliza relativo a `cwd` antes de evaluar los patrones de path.)
3. **Sesión ya avisada** → si `session_id` ya está en el estado, `exit 0`.
4. **Frenar + marcar** → escribir `session_id` en el estado e inyectar `permissionDecision: "deny"` con el mensaje de oferta. Como el estado quedó marcado, cualquier reintento del `Edit` (paso 3) pasa libre.

### Mensaje inyectado (`permissionDecisionReason`)

> ⛔ Antes de escribir código en este trabajo: detecto que en esta sesión todavía no nos alineamos con el grill (paso 1 del workflow: Alignment/Grill → PRD → task planning, ver CLAUDE.md). **No sigas codeando en piloto automático.** Ofrecele al usuario: ¿querés que hagamos `/grill-me` o `/grill-with-docs` primero, o seguimos porque es trivial / ya se alinearon para esto? Esperá su decisión — no ejecutes el grill por tu cuenta. Si el usuario dice que sigamos, reintentá el Edit y proceds; este aviso no se repite en esta sesión.

### Estado

- Archivo: `.git/alignment-gate-state.json`. Forma: `{ "<session_id>": true }`.
- Mismo patrón y ubicación que `review-loop-state.json` (dentro de `--git-dir`).
- Dedup por `session_id` → **una vez por sesión**.
- Sin `.git` (caso raro: el scaffold corre `git init`, así que normalmente existe): fallback a `$env:TEMP` o `exit 0` no-op. Detalle de implementación, no de diseño.

### Mecánica del bloqueo

`PreToolUse` con salida JSON:

```powershell
@{ hookSpecificOutput = @{
    hookEventName = "PreToolUse"
    permissionDecision = "deny"
    permissionDecisionReason = $msg
} } | ConvertTo-Json -Depth 4 -Compress
```

`deny` impide ese `Edit` puntual y devuelve la razón al agente. No ejecuta nada. El reintento pasa porque la sesión ya quedó marcada.

## Cambios en el scaffold (espejados en ambas skills)

Por la hard rule de espejado (`CLAUDE.md` del repo), todo cambio va en `bootstrap-personal-project` **y** `bootstrap-southpoint-project`, idéntico salvo lo específico de cada uno.

1. **`.claude/hooks/alignment-gate.ps1`** (nuevo) — en ambos scaffolds.
2. **`.claude/settings.json`** — agregar bloque `PreToolUse` (matcher `Edit|Write|MultiEdit`) junto al `PostToolUse` existente:
   ```json
   "PreToolUse": [
     {
       "matcher": "Edit|Write|MultiEdit",
       "hooks": [
         { "type": "command",
           "command": "pwsh -NoProfile -File \"${CLAUDE_PROJECT_DIR}/.claude/hooks/alignment-gate.ps1\"" }
       ]
     }
   ]
   ```
3. **`CLAUDE.md` template** — una línea que mencione el `alignment-gate` hook como refuerzo determinístico del paso 1, simétrico a cómo la línea ~63 ya menciona el `review-loop-trigger` para el paso 7. Aclarar que **ofrece, no ejecuta**, y que frena una vez por sesión.
4. **`.bootstrap-manifest.json`** — regenerar con `tools/gen-manifest.ps1` (es generado, no se edita a mano).
5. **Deploy** con `tools/sync-skills.ps1`.

## Testing

Mínimos exigidos por el `CLAUDE.md` del repo más un test específico del hook:

1. **Eval directorio vacío** — el bootstrap aterriza el hook y el `settings.json` con ambos bloques.
2. **Eval archivos preexistentes** — sin romper la copia top-level (no wildcard `scaffold\*`).
3. **Test unitario del hook** (análogo al test del falso positivo del commit-graph): simular stdin con
   - `file_path` de código (`src/foo.py`) y sesión nueva → debe **deny** + escribir el `session_id` en el estado.
   - `file_path` `.md` o bajo `docs/` → debe `exit 0` (pasa libre, sin marcar).
   - `file_path` de código con la sesión **ya marcada** → debe `exit 0` (pasa libre).

## Fuera de alcance (anotado para futuro)

- **Persistencia más fina del re-armado:** re-armar por feature/branch o tras cada commit (para cubrir sesiones largas que cambian de tarea a mitad de camino). Decisión actual: una vez por sesión + `CLAUDE.md` gobierna el resto; "más persistente" se evalúa después si hace falta.
- **Detección semántica de trivial vs no-trivial:** el gate no juzga el contenido del cambio; delega ese juicio al usuario vía la oferta.
