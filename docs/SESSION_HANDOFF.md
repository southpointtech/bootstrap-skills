# Session Handoff — 2026-06-14

## ▶ AL RETOMAR — `setup-mcp-workstation` IMPLEMENTADA; solo falta deployar

La feature está **implementada, corregida y con todos los tests en verde**. Tasks 1-7 del plan + 3 revisiones (corrección DOMO). **Lo único pendiente es deployar** con `pwsh -NoProfile -File tools/sync-skills.ps1` (y, opcional, un eval con skill-creator). NO hay bloqueante externo.

**Corrección importante hecha en la sesión 2026-06-14:** al pedir "el paquete pip de `domo_mcp`" se descubrió que el cliente DOMO oficial (`github.com/DomoApps/domo-mcp-server`) **NO es un paquete pip** — es clonar-y-ejecutar (no tiene setup.py/pyproject.toml; no hay paquete en PyPI). Martín eligió que la skill **clone el repo automáticamente**. Resultado: `install-clients.ps1` clona `DomoApps/domo-mcp-server` a `~/.claude/domo-mcp-server`, instala deps con `pip install -r requirements.txt` y **setea `DOMO_MCP_HOME` solo**; el catálogo southpoint **mantiene** `PYTHONPATH=${DOMO_MCP_HOME}` (se revirtió la eliminación que había hecho la Task 4 original). El usuario sigue dando solo su token de DOMO.

**Si retomás:** correr `tools/sync-skills.ps1` para deployar (decisión del usuario, es acción hacia afuera). Verificar luego que `~/.claude/skills/setup-mcp-workstation/SKILL.md` exista y commitear los manifests regenerados de las bootstrap.

---

## Qué es el proyecto

`C:\Repos\PERSONAL\Bootstrap Skills` es la **fuente de verdad** de las skills personales de bootstrap de Claude Code (`bootstrap-southpoint-project`, `bootstrap-personal-project`, `upgrade-bootstrap`). Las copias instaladas viven en `C:\Users\marti\.claude\skills\`; editar acá NO tiene efecto hasta deployar con `tools\sync-skills.ps1`.

## Feature en curso: `setup-mcp-workstation`

**Motivación:** Martín comparte las Bootstrap Skills con un compañero nuevo de trabajo (entra el 2026-06-15). Hoy el setup de credenciales/MCPs es manual y atado al entorno de Martín. Esta feature crea una skill que prepara una PC Windows **una vez por máquina**: el usuario ingresa sus credenciales una sola vez (responde preguntas o llena un archivo) y la skill persiste las env vars e instala los clientes. Después solo usa `bootstrap-southpoint-project` normal.

**Decisiones de diseño (todas ya tomadas y aprobadas por el usuario):**
- **Skill aparte** (no embebida en bootstrap): responsabilidad única, frecuencia 1×/PC, testeable sola, no se duplica.
- **Fuente de verdad = un archivo** `~/.claude/mcp-workstation.local.json` (fuera de todo repo). La skill lo lee y **aplica env vars persistentes de usuario** vía `[Environment]::SetEnvironmentVariable(...,'User')`. El usuario NUNCA corre comandos en la terminal. (Se descartó `settings.json`→`env` porque NO está documentado que expanda `${VAR}` en `.mcp.json`; el `${VAR}` lee del entorno del proceso — confirmado por claude-code-guide.)
- **Instalación híbrida:** auto-hace lo no-admin/no-interactivo (env vars, **clone de DOMO + `pip install -r requirements.txt`**, `npx playwright install chromium`); **verifica y guía** lo que necesita admin/interacción (Git, Python, Node).
- **Alcance de credenciales:** git (name+email) + DOMO (token) + Zoho (mcpUrl). github y firebase quedan fuera (siguen con env vars manuales). Host DOMO = constante (`hssstaffing.domo.com`), no se pregunta.
- **`domo_mcp` se obtiene CLONANDO el repo oficial** `DomoApps/domo-mcp-server` a `~/.claude/domo-mcp-server` (NO es paquete pip; solo se instalan sus dependencias con `pip install -r requirements.txt`). La skill **setea `DOMO_MCP_HOME` sola** → el catálogo southpoint **mantiene** `PYTHONPATH=${DOMO_MCP_HOME}`. (Esto corrige la suposición original de "pip install + eliminar DOMO_MCP_HOME".)
- **Identidad git parametrizada en AMBAS bootstrap** (regla de espejado): leen env var por área con fallback a la identidad actual. southpoint → `SOUTHPOINT_GIT_NAME`/`EMAIL` (fallback `southpointtech`/`mdeleon@agtium.com`); personal → `PERSONAL_GIT_NAME`/`EMAIL` (fallback `MartinDele703`/`martin.deleon703@gmail.com`).
- **Playwright** = tooling de QA, no MCP, no credencial: solo se instalan los browsers (chromium) a nivel máquina.

## Estado de implementación

- **Diseño:** ✅ spec (`f269d31`) + plan (`dcae61c`).
- **Código:** ✅ Tasks 1-7 implementadas con subagent-driven (impl + spec-review + code-review por task) + 3 revisiones por la corrección DOMO (clone, no pip). Últimos commits: `3eb6a64`, `fcc203b`, `0c3da2f`, `fc3d306`.
- **Tests:** ✅ las 3 suites pasan — `apply-env` (12), `install-clients` (17), `gen-mcp-json` (26).
- **Deploy:** ❌ pendiente (`tools/sync-skills.ps1` NO corrido; las copias en `~/.claude/skills/` siguen con lo viejo).
- **Prereqs de la skill:** Git + Python (DOMO) + Node (Playwright); la skill los verifica y guía si faltan.

## Archivos que el plan crea / modifica (ninguno tocado aún salvo los docs de spec/plan)

**Crear:** `skills/setup-mcp-workstation/SKILL.md`, `skills/setup-mcp-workstation/scripts/apply-env.ps1`, `skills/setup-mcp-workstation/scripts/install-clients.ps1`, `tests/apply-env.tests.ps1`, `tests/install-clients.tests.ps1`.
**Modificar:** `skills/bootstrap-southpoint-project/scripts/gen-mcp-json.ps1` (server domo: **mantiene** `PYTHONPATH=${DOMO_MCP_HOME}` con prereq "clonado por setup-mcp-workstation"), `tests/gen-mcp-json.tests.ps1` (aserciones domo), `skills/bootstrap-southpoint-project/SKILL.md` (Step 5 identidad git + Step 0 chequeo de máquina), `skills/bootstrap-personal-project/SKILL.md` (Step 5 identidad git), `README.md`, `docs/HISTORIA.md`, `docs/TESTING.md`.

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
- **`DOMO_MCP_HOME` sigue vivo** pero ahora lo **setea la skill automáticamente** al clonar DOMO (apunta a `~/.claude/domo-mcp-server`), en vez de que el usuario lo configure a mano (antes apuntaba a `C:\Repos\SOUTHPOINTLABS\domo-mcp-server`). El catálogo lo usa vía `PYTHONPATH=${DOMO_MCP_HOME}`.

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
2. ✅ Tasks 1-7 ejecutadas + 3 revisiones (corrección DOMO clone); tests verdes.
3. Pendiente: (opcional) eval con skill-creator, y deployar con `tools\sync-skills.ps1` (luego commitear los manifests regenerados).
