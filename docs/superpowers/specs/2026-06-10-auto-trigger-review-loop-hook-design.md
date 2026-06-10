# Spec — Auto-trigger de review-loop vía hook PostToolUse (estilo greploop)

- **Fecha:** 2026-06-10
- **Estado:** aprobado para planificar
- **Fuente / referencia:** mecánica de disparo de `greploop` / GP-Loop (Greptile): el loop de review arranca cuando se abre/actualiza el PR. Acá se replica ese gatillo de forma determinística usando un hook nativo de Claude Code, sin servicio externo.

## Problema

`review-loop` hoy es **opt-in manual** (`/review-loop` o que el modelo lo sugiera). El scaffold no instala ningún hook ni `settings.json`, y el `CLAUDE.md` template solo dice "suggest ... via `/review-loop`". Resultado observado: un proyecto bootstrapeado y actualizado llevaba rato editando código y **nunca había corrido el loop**, porque dependía de que el modelo se acordara. Se comporta según diseño, pero el diseño no garantiza ejecución.

## Objetivo

Que en cada proyecto bootstrapeado, al **abrir o actualizar un PR**, se inyecte **determinísticamente** la orden de ejecutar `/review-loop` sobre el diff del branch. El hook garantiza la inyección de la instrucción (nunca se olvida); el modelo ejecuta el loop.

## Límite técnico asumido (confirmado)

- Un hook `PostToolUse` con matcher `Bash` puede leer el comando ejecutado (`tool_input.command` del JSON de stdin) e inyectar texto a Claude vía `hookSpecificOutput.additionalContext` (exit 0). Ese texto entra al contexto del modelo en ese turno.
- El hook **NO ejecuta** la skill ni mete a Claude en un loop multi-turno. Solo inyecta la instrucción de forma determinística; el modelo la sigue. Esto es suficiente para el objetivo (el fallo era el olvido, no la incapacidad).
- No se usan mecanismos `agent`/`mcp_tool`/`asyncRewake`: no se dan por estables en la versión actual y no son necesarios.
- El matcher de settings filtra solo por nombre de tool (`Bash`). El filtrado por contenido del comando lo hace el script.

## Principios y restricciones (hard rules del repo)

- **Espejado ×2:** se aplica idéntico en `bootstrap-personal-project` y `bootstrap-southpoint-project`. Como es infraestructura (no contenido DOMO ni identidad git), los archivos quedan **idénticos** entre ambas.
- Copia por enumeración top-level (sin wildcard `scaffold\*`). No dejar directorios vacíos en `assets/scaffold/`.
- El `.bootstrap-manifest.json` es generado: se regenera con `tools/gen-manifest.ps1` / `tools/sync-skills.ps1`, no se edita a mano.
- Testear con evals antes de deployar; deploy con `tools/sync-skills.ps1`; commit con identidad local `MartinDele703`.

## Diseño

### Gatillo: Enfoque 3 (híbrido `gh pr create` + `git push`, con dedupe por SHA)

Replica el ciclo completo de greploop: review en apertura del PR y re-review en cada push de actualización, sin disparar dos veces sobre el mismo commit.

### Componentes nuevos en el scaffold (×2)

1. **`.claude/settings.json`** — nuevo. Bloque `hooks.PostToolUse` con matcher `Bash` que invoca el script. (El scaffold no tenía settings.json; es archivo nuevo.)
2. **`.claude/hooks/review-loop-trigger.ps1`** — el script PowerShell del hook.

Estructura del `settings.json` (forma a validar en implementación):

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "pwsh -NoProfile -File \"${CLAUDE_PROJECT_DIR}/.claude/hooks/review-loop-trigger.ps1\"",
            "timeout": 30
          }
        ]
      }
    ]
  }
}
```

### Lógica del script `review-loop-trigger.ps1`

1. Lee el JSON de stdin; extrae `tool_input.command`.
2. Si el comando **no** matchea `gh pr create` ni `git push` → exit 0 silencioso (no-op). Camino caliente: cada Bash pasa por acá, así que el no-git debe ser instantáneo.
3. Resuelve el branch actual (`git rev-parse --abbrev-ref HEAD`) y la **base branch** (ver "Resolución de la base" abajo). Si el branch actual **es** la base → no-op (no se revisa la base contra sí misma).
4. **Dedupe:** lee `.git/review-loop-state.json` (dentro de `.git/`, nunca se commitea). Mapea `branch → último SHA disparado`. Si el SHA de `HEAD` para este branch ya fue disparado → no-op.
5. Si pasa el filtro: actualiza el marcador con el SHA actual del branch, y emite por stdout el JSON con `hookSpecificOutput.additionalContext` con una instrucción **imperativa**, p. ej.:
   > "Acabás de abrir/actualizar un PR (branch `<branch>`). Antes de dar el trabajo por terminado, ejecutá `/review-loop` revisando el diff del branch: `git diff <base>...HEAD`. No marques el trabajo como completo hasta que el loop cierre (cero hallazgos medium/high o tope de 5 turnos)."

Como cada fix del loop genera un commit nuevo (SHA distinto), el siguiente `git push` vuelve a disparar (re-review estilo greploop). Cuando el loop cierra sin commits nuevos, no re-dispara.

**Resolución de la base branch** (no se hardcodea `main` — proyectos como KBS usan `develop`, y otros podrían usar otras bases):

1. Si el comando es `gh pr create` y trae `--base <branch>` explícito → usar ese.
2. Si no, detectar el default branch del repo: `git symbolic-ref --short refs/remotes/origin/HEAD` (devuelve `origin/<base>` → extraer `<base>`). Fallback: `gh repo view --json defaultBranchRef -q .defaultBranchRef.name`.
3. Fallback final: el primer ref que exista entre `main`, `master`, `develop`.

La base resuelta se usa tanto para el filtro del paso 3 (no disparar si el branch actual es la base) como para el rango del diff (`git diff <base>...HEAD`) en el `additionalContext`.

### Ajuste a la skill `review-loop` (×2)

Hoy el pre-flight usa `git diff --stat` (working-tree). Agregar soporte de **modo PR**: cuando el disparo viene del hook, revisar el **rango del branch** (`git diff <base>...HEAD`) en vez del working-tree, para ser fiel a greploop (que revisa el diff del PR). El working-tree sigue siendo el modo por defecto para invocación manual sobre cambios sin commitear.

### Integración en docs del scaffold

- Nota en el `CLAUDE.md` template: el hook auto-dispara `review-loop` al abrir/actualizar un PR; el `/review-loop` manual sigue disponible para diffs locales.
- `.claude/settings.json` y `.claude/hooks/` se commitean en el proyecto destino (son parte del repo). El marcador de dedupe vive en `.git/` y no se commitea.

### Integración con `upgrade-bootstrap` (incluido en este spec)

- Los 2 archivos nuevos entran al `.bootstrap-manifest.json`, así `upgrade-bootstrap` los detecta como **missing** en proyectos viejos y los ofrece.
- **Caso especial — `settings.json` preexistente:** si el proyecto destino ya tiene `.claude/settings.json` propio, `upgrade-bootstrap` debe **mergear** el bloque `hooks.PostToolUse` (agregar la entrada del matcher `Bash` → review-loop-trigger si no está), **no sobreescribir** el archivo. Si no existe settings.json, copiarlo entero. El `review-loop-trigger.ps1`, al ser archivo propio bajo `.claude/hooks/`, se trata como un archivo missing normal.
- El merge debe ser idempotente: correr `upgrade-bootstrap` dos veces no duplica la entrada del hook.

## Casos de regresión a cubrir (TESTING.md)

- Bootstrap en directorio vacío: aparecen `.claude/settings.json` y `.claude/hooks/review-loop-trigger.ps1`; el manifest los incluye.
- Hook no-op: un comando Bash no-git (p. ej. `ls`) no inyecta nada y no rompe el flujo.
- Hook dispara: `gh pr create` en un branch de feature inyecta el `additionalContext` con la instrucción de `/review-loop`.
- Dedupe: `git push` seguido de `gh pr create` sobre el mismo commit dispara **una sola vez**.
- Branch base: estar en la base detectada no dispara — verificado con base `main` y con base `develop` (resolución dinámica, no hardcodeada).
- Base explícita: `gh pr create --base develop` usa `develop` como base del rango aunque el default del repo sea otro.
- `upgrade-bootstrap` con settings.json preexistente: mergea el hook sin pisar la config previa; correrlo dos veces no duplica.

## Fuera de alcance (YAGNI)

- Mecanismos de hook `agent`/`mcp_tool`/`asyncRewake` (no se asumen estables; no necesarios).
- Garantizar la **ejecución** del loop sin intervención del modelo (el hook solo inyecta la instrucción).
- Matcher por contenido de comando a nivel settings (lo hace el script).
- Backport del hook al `CLAUDE.md` / config real de Forecasting App (a evaluar aparte, hard rule del repo).

## Archivos afectados (×2, espejado idéntico salvo donde se indique)

**Nuevos:**
- `assets/scaffold/.claude/settings.json`
- `assets/scaffold/.claude/hooks/review-loop-trigger.ps1`

**Editados:**
- `assets/scaffold/.agents/skills/review-loop/SKILL.md` (modo PR)
- `assets/scaffold/.claude/commands/review-loop.md` (modo PR)
- `assets/scaffold/CLAUDE.md` (nota del auto-trigger)
- `assets/scaffold/.bootstrap-manifest.json` (regenerado)

**Skill `upgrade-bootstrap`:**
- `skills/upgrade-bootstrap/SKILL.md` (+ assets si aplica) — lógica de merge idempotente de `settings.json`.

**Docs del repo:**
- `docs/TESTING.md` (casos de regresión nuevos)
