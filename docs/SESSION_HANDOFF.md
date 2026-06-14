# Session Handoff — 2026-06-14

## ▶ AL RETOMAR — ejecutar el plan de `setup-mcp-workstation` con subagent-driven

La fase de diseño y planificación de una feature nueva está **terminada y commiteada**. Lo que sigue es **implementar**, task por task, con `superpowers:subagent-driven-development` (el usuario ya eligió ese modo).

**Arrancar así:**
1. Leer el plan: `docs/superpowers/plans/2026-06-14-setup-mcp-workstation.md` (8 tasks, TDD, con código completo).
2. Leer el spec para contexto: `docs/superpowers/specs/2026-06-14-setup-mcp-workstation-design.md`.
3. Invocar `superpowers:subagent-driven-development` y ejecutar Task 1 → 8 en orden, con review entre tasks.

**Bloqueante externo (solo Martín lo sabe):** el **nombre/fuente real del paquete pip de `domo_mcp`** (PyPI público / índice privado / `git+https`). El plan usa el marcador `"domo-mcp"` y lo reemplaza en **Task 8, Step 1**. Tasks 1-7 NO dependen de ese dato — se pueden hacer enteras antes de pedirlo. Pedirlo recién al llegar a Task 8.

---

## Qué es el proyecto

`C:\Repos\PERSONAL\Bootstrap Skills` es la **fuente de verdad** de las skills personales de bootstrap de Claude Code (`bootstrap-southpoint-project`, `bootstrap-personal-project`, `upgrade-bootstrap`). Las copias instaladas viven en `C:\Users\marti\.claude\skills\`; editar acá NO tiene efecto hasta deployar con `tools\sync-skills.ps1`.

## Feature en curso: `setup-mcp-workstation`

**Motivación:** Martín comparte las Bootstrap Skills con un compañero nuevo de trabajo (entra el 2026-06-15). Hoy el setup de credenciales/MCPs es manual y atado al entorno de Martín. Esta feature crea una skill que prepara una PC Windows **una vez por máquina**: el usuario ingresa sus credenciales una sola vez (responde preguntas o llena un archivo) y la skill persiste las env vars e instala los clientes. Después solo usa `bootstrap-southpoint-project` normal.

**Decisiones de diseño (todas ya tomadas y aprobadas por el usuario):**
- **Skill aparte** (no embebida en bootstrap): responsabilidad única, frecuencia 1×/PC, testeable sola, no se duplica.
- **Fuente de verdad = un archivo** `~/.claude/mcp-workstation.local.json` (fuera de todo repo). La skill lo lee y **aplica env vars persistentes de usuario** vía `[Environment]::SetEnvironmentVariable(...,'User')`. El usuario NUNCA corre comandos en la terminal. (Se descartó `settings.json`→`env` porque NO está documentado que expanda `${VAR}` en `.mcp.json`; el `${VAR}` lee del entorno del proceso — confirmado por claude-code-guide.)
- **Instalación híbrida:** auto-hace lo no-admin/no-interactivo (env vars, `pip install` de DOMO, `npx playwright install chromium`); **verifica y guía** lo que necesita admin/interacción (Python, Node).
- **Alcance de credenciales:** git (name+email) + DOMO (token) + Zoho (mcpUrl). github y firebase quedan fuera (siguen con env vars manuales). Host DOMO = constante (`hssstaffing.domo.com`), no se pregunta.
- **`domo_mcp` se instala por `pip install`** (no checkout, no git clone). Esto elimina `DOMO_MCP_HOME` del catálogo MCP de southpoint.
- **Identidad git parametrizada en AMBAS bootstrap** (regla de espejado): leen env var por área con fallback a la identidad actual. southpoint → `SOUTHPOINT_GIT_NAME`/`EMAIL` (fallback `southpointtech`/`mdeleon@agtium.com`); personal → `PERSONAL_GIT_NAME`/`EMAIL` (fallback `MartinDele703`/`martin.deleon703@gmail.com`).
- **Playwright** = tooling de QA, no MCP, no credencial: solo se instalan los browsers (chromium) a nivel máquina.

## Estado de implementación

- **Diseño:** ✅ spec escrito y commiteado (`f269d31`).
- **Plan:** ✅ plan escrito y commiteado (`dcae61c`), con un fix de sintaxis aplicado después (`-match`).
- **Código:** ❌ NADA implementado todavía. Las 8 tasks están sin tocar.

## Archivos que el plan crea / modifica (ninguno tocado aún salvo los docs de spec/plan)

**Crear:** `skills/setup-mcp-workstation/SKILL.md`, `skills/setup-mcp-workstation/scripts/apply-env.ps1`, `skills/setup-mcp-workstation/scripts/install-clients.ps1`, `tests/apply-env.tests.ps1`, `tests/install-clients.tests.ps1`.
**Modificar:** `skills/bootstrap-southpoint-project/scripts/gen-mcp-json.ps1` (quitar `DOMO_MCP_HOME`/`PYTHONPATH` del server domo), `tests/gen-mcp-json.tests.ps1` (aserciones domo), `skills/bootstrap-southpoint-project/SKILL.md` (Step 5 identidad git + Step 0 chequeo de máquina), `skills/bootstrap-personal-project/SKILL.md` (Step 5 identidad git), `README.md`, `docs/HISTORIA.md`, `docs/TESTING.md`.

## Comandos de test (runners sin Pester, estilo del repo)

```powershell
pwsh -NoProfile -File tests/apply-env.tests.ps1        # nuevo (Task 1)
pwsh -NoProfile -File tests/install-clients.tests.ps1  # nuevo (Task 2)
pwsh -NoProfile -File tests/gen-mcp-json.tests.ps1     # existente, se actualiza en Task 4
```
Cada uno imprime "TODOS LOS TESTS PASARON" o "N test(s) FALLARON" + exit code. Aún no corridos (código no escrito).

## Decisiones técnicas clave para no romper nada

- `apply-env.ps1` **nunca imprime valores de tokens** (solo nombres de vars + estado `set`/`unchanged`). El `-DryRun` calcula sin escribir → los tests usan dry-run para no ensuciar el entorno real.
- `install-clients.ps1` acepta `-PythonCmd`/`-NpxCmd` para que los tests simulen ausencia pasando un comando inexistente. Prereqs faltantes **no abortan**.
- La skill personal **no tiene server domo** (catálogo = firebase/zoho-personal), así que Task 4 toca **solo** southpoint.
- **`DOMO_MCP_HOME` queda deprecado** por esta feature (antes apuntaba a `C:\Repos\SOUTHPOINTLABS\domo-mcp-server`). Es un cambio intencional: con pip ya no hace falta `PYTHONPATH`.

## Reglas del repo (no olvidar)

- Las dos skills bootstrap se mantienen **espejadas en estructura**; todo cambio de mecánica va en ambas. Solo difieren en DOMO e identidad git.
- Editar skills acá NO tiene efecto hasta `tools\sync-skills.ps1` (regenera manifests de las bootstrap). `sync-skills.ps1` enumera todo `skills/`, así que `setup-mcp-workstation` entra sola al deployar (Task 8).
- NO wildcard `scaffold\*` en los copy de PowerShell (anida `.agents\.agents`).
- Identidad de commit en ESTE repo: `MartinDele703 <martin.deleon703@gmail.com>` (ya configurada local).
- Rastros de testeo (workspaces de evals) se borran al terminar.
- Los evals de skill se corren con skill-creator (ver `docs/TESTING.md`).

## Contexto previo (cerrado, no es trabajo pendiente)

Features anteriores YA mergeadas y deployadas: "adopción con merge de CLAUDE.md" (Step 0b) y "MCP por área" (`gen-mcp-json.ps1` + Step 4). La migración MCP por área del entorno de Martín quedó hecha (8 `.mcp.json` generados, global vaciado, env vars seteadas). Pendientes históricos del lado de Martín (opcionales, no bloquean esta feature): rotar token DOMO, agregar github MCP cuando Docker corra, adopción de proyectos legacy. Detalle en el historial de git si se necesita.

## Próximos 3 pasos recomendados

1. Invocar `superpowers:subagent-driven-development` apuntando al plan `docs/superpowers/plans/2026-06-14-setup-mcp-workstation.md`.
2. Ejecutar Tasks 1-7 (no requieren el paquete pip real); correr los tests de cada task antes de commitear.
3. Al llegar a Task 8, pedir a Martín el paquete pip real de `domo_mcp`, reemplazarlo, correr toda la batería + eval con skill-creator, y deployar con `tools\sync-skills.ps1`.
