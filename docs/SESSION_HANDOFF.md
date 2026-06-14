# Session Handoff — 2026-06-14

## ▶ AL RETOMAR — `setup-mcp-workstation` TERMINADA y deployada; no hay tarea activa

La feature `setup-mcp-workstation` está **completa, evaluada y deployada**. No queda trabajo pendiente de esta feature. El working tree está **limpio** (todo commiteado). Si arrancás una sesión nueva sin una tarea concreta, no hay nada que continuar acá; este handoff es el registro de cierre + contexto del repo.

**Único paso del lado del usuario (Martín):** reiniciar Claude Code para que tome del todo la skill nueva (ya aparece como disponible). En su PC el entorno ya está armado, así que correrla ofrecería "re-aplicar" en vez de setup limpio.

---

## Qué es el proyecto

`C:\Repos\PERSONAL\Bootstrap Skills` es la **fuente de verdad** de las skills de Claude Code que bootstrapean proyectos:
- `bootstrap-southpoint-project` — proyectos de cliente SOUTHPOINTLABS (DOMO/Zoho).
- `bootstrap-personal-project` — proyectos personales de Martín.
- `upgrade-bootstrap` — actualiza proyectos ya bootstrapeados al scaffold actual.
- `setup-mcp-workstation` — **NUEVA** (esta sesión): prepara una PC Windows 1× por máquina.

Las copias **instaladas** (las que Claude Code usa) viven en `C:\Users\marti\.claude\skills\`. **Editar acá NO tiene efecto hasta deployar** con `pwsh -NoProfile -File tools/sync-skills.ps1`. Identidad de commit del repo: `MartinDele703 <martin.deleon703@gmail.com>` (ya configurada local). Se trabaja directo en `main`.

## Feature cerrada esta sesión: `setup-mcp-workstation`

**Motivación:** compartir las Bootstrap Skills con un compañero nuevo (entró 2026-06-15). El setup de credenciales/MCP era manual y atado al entorno de Martín; esta skill lo hace reproducible en cualquier PC.

**Qué hace la skill (1× por máquina):** pide identidad git + token DOMO + URL MCP Zoho una sola vez → los escribe en `~/.claude/mcp-workstation.local.json` (fuera de repos, nunca commiteado) → persiste env vars de usuario (`apply-env.ps1`, sin imprimir secretos) → instala clientes (`install-clients.ps1`): **clona** el cliente DOMO + deps, instala Playwright chromium. Después el usuario solo usa `bootstrap-southpoint-project`.

### Decisión técnica clave (el giro de la sesión)
El plan original asumía que `domo_mcp` se instalaba por **pip**. **Es falso:** el cliente oficial `github.com/DomoApps/domo-mcp-server` **NO es un paquete pip** (no tiene setup.py/pyproject.toml; no hay paquete en PyPI). Es **clonar-y-ejecutar**: `python -m domo_mcp` con `PYTHONPATH` apuntando al clone. Martín eligió "clonar el repo automático", así que:
- `install-clients.ps1` clona `DomoApps/domo-mcp-server` → `~/.claude/domo-mcp-server`, hace `pip install -r requirements.txt`, y **setea `DOMO_MCP_HOME` solo**.
- El catálogo southpoint **mantiene** `PYTHONPATH=${DOMO_MCP_HOME}` (se **revirtió** la eliminación que había hecho la Task 4 original del plan).
- Prereqs de la skill: **Git + Python** (DOMO) + **Node** (Playwright); los verifica y guía si faltan, sin abortar.

### Env vars y nombres (consistentes punta a punta)
- `apply-env.ps1` setea: `SOUTHPOINT_GIT_NAME`, `SOUTHPOINT_GIT_EMAIL`, `DOMO_SOUTHPOINT_TOKEN`, `ZOHO_SOUTHPOINT_MCP_URL`.
- `install-clients.ps1` setea: `DOMO_MCP_HOME` (= dir del clone).
- Identidad git parametrizada por env var con fallback en AMBAS bootstrap (espejado): southpoint `SOUTHPOINT_GIT_NAME`/`EMAIL` (fallback `southpointtech`/`mdeleon@agtium.com`); personal `PERSONAL_GIT_NAME`/`EMAIL` (fallback `MartinDele703`/`martin.deleon703@gmail.com`). `PERSONAL_*` NO las setea esta skill (sería manual).

## Estado / verificación

- **Código:** ✅ completo. Implementado con `subagent-driven-development` (impl + spec-review + code-review por task), Tasks 1-7 del plan + 3 revisiones por la corrección DOMO + 1 mejora del eval.
- **Tests (runners sin Pester):** ✅ las 3 suites pasan.
  - `pwsh -NoProfile -File tests/apply-env.tests.ps1` → 12 ok.
  - `pwsh -NoProfile -File tests/install-clients.tests.ps1` → 17 ok.
  - `pwsh -NoProfile -File tests/gen-mcp-json.tests.ps1` → 26 ok.
- **Eval (skill-creator, aislado):** ✅ con-skill 100% (8/8) vs baseline 75%. Corrido en sandbox (`-DryRun` + config en temp) para no pisar los tokens reales de Martín. Workspace de eval borrado (regla del repo).
- **Deploy:** ✅ `tools/sync-skills.ps1` corrido. Skill instalada en `~/.claude/skills/setup-mcp-workstation`. Manifests de las bootstrap regenerados y commiteados.
- **Working tree:** ✅ limpio.

## Commits de esta sesión (sobre `6066ffe`, todos en `main`, HEAD `af96d2e`)

`a5c8708` apply-env + tests · `d51fca7` install-clients (pip, luego corregido) · `e85e059` pin PSNative · `ea2a23f` SKILL.md · `7a459be` fix $skill · `857e4ef` (Task 4 quitar DOMO_MCP_HOME, **luego revertido**) · `8244b69` identidad git por env var · `8752b2d` Step 0 machine-check · `8cecbc5` Step 6 cleanup · `e32af18` docs · `3eb6a64` **install-clients modelo clone** · `fcc203b` aviso pull falla · `0c3da2f` **revertir Task 4 (restaurar PYTHONPATH/DOMO_MCP_HOME)** · `fc3d306` docs a modelo clone · `136040e` handoff · `f9a9bfe` Step 0 señal canónica (eval) · `af96d2e` deploy + manifests.

## Archivos de la feature

**Skill nueva:** `skills/setup-mcp-workstation/{SKILL.md, scripts/apply-env.ps1, scripts/install-clients.ps1}`.
**Tests nuevos:** `tests/apply-env.tests.ps1`, `tests/install-clients.tests.ps1`.
**Modificados:** `skills/bootstrap-southpoint-project/scripts/gen-mcp-json.ps1` (catálogo domo), `tests/gen-mcp-json.tests.ps1`, ambos bootstrap `SKILL.md` (identidad git; southpoint además Step 0 + Step 6), `README.md`, `docs/HISTORIA.md`, `docs/TESTING.md`.

## Reglas del repo (no olvidar)

- Las dos skills bootstrap se mantienen **espejadas en estructura**; todo cambio de mecánica va en ambas. Solo difieren en DOMO e identidad git.
- Editar skills acá NO tiene efecto hasta `tools\sync-skills.ps1` (regenera los manifests de las bootstrap).
- NO usar wildcard `scaffold\*` en los copy de PowerShell (anida `.agents\.agents`).
- `gitignore.txt` en assets se llama así a propósito (aterriza como `.gitignore`).
- El `.bootstrap-manifest.json` es generado; lo regenera `sync-skills.ps1` antes de deployar.
- Rastros de testeo (workspaces de evals) se borran al terminar.

## Gotchas técnicos descubiertos esta sesión (para no repetirlos)

- **pwsh 7.6.x:** `@($lista)` de un `List[object]` de `[ordered]` hashtables rompe `ConvertTo-Json` ("Argument types do not match") → usar `.ToArray()`. (Los `List[string]` serializan bien con `@(...)`.)
- **pwsh 7.4+:** `$PSNativeCommandUseErrorActionPreference` default `$true` + `$ErrorActionPreference="Stop"` hace que un exit no-cero de un comando nativo (pip/npx/git) **lance excepción y aborte**. `install-clients.ps1` lo pinea en `$false` para que los prereqs faltantes no aborten.
- **Eval de una skill que muta la máquina:** SIEMPRE aislar (config en `[IO.Path]::GetTempPath()`, scripts con `-DryRun`, `-DomoHome` temp). Las env vars de usuario van al registro de Windows → un eval sin `-DryRun` pisaría los tokens reales. Documentado en `docs/TESTING.md`.
- **Baseline inflado:** un agente baseline (sin skill) que corre dentro de este repo puede leer los archivos de la skill y "hacer trampa" → el delta del benchmark subestima el valor real.

## Follow-ups históricos (opcionales, NO de esta feature)

Del lado de Martín, pendientes viejos que no bloquean nada: rotar token DOMO, agregar github MCP cuando Docker corra, adopción de proyectos legacy sin el hook. Detalle en `docs/HISTORIA.md` y memoria del proyecto.

## Próximos pasos recomendados

1. (Usuario) Reiniciar Claude Code para cargar la skill nueva limpia.
2. No hay tarea de código pendiente. Si surge una nueva, arrancar con `superpowers:brainstorming` antes de tocar código (flujo del repo).
3. Si se evoluciona el scaffold de las bootstrap, recordar deployar con `sync-skills.ps1` y commitear los manifests regenerados.
