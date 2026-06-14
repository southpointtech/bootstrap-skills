# Bootstrap Skills

Fuente de verdad de las skills de Claude Code que scaffoldean proyectos nuevos con el modus operandi de desarrollo asistido por AI (workflow de 8 pasos + Workflow State Machine, docs de ai-workflow, skills de agente, git init con identidad correcta).

| Skill | Para | Git identity |
|---|---|---|
| `bootstrap-southpoint-project` | Proyectos de cliente SOUTHPOINTLABS (incluye DOMO/Zoho) | `southpointtech <mdeleon@agtium.com>` |
| `bootstrap-personal-project` | Proyectos personales (sin DOMO; persisten Playwright/Firebase/Azure/Zoho) | `MartinDele703 <martin.deleon703@gmail.com>` |
| `setup-mcp-workstation` | Preparar una PC Windows 1× (credenciales git/DOMO/Zoho + clientes DOMO/Playwright) antes de usar las bootstrap | — (setea las env vars de identidad, no commitea) |

## Estructura

```
skills/          ← las dos skills (SKILL.md + assets/scaffold con ~43 archivos c/u)
tools/           ← sync-skills.ps1: deploya repo → ~/.claude/skills/
docs/            ← HISTORIA.md (contexto y decisiones) + TESTING.md (cómo correr evals)
```

## Uso de las skills (ya deployadas)

Abrir Claude Code en la carpeta del proyecto nuevo y decir, por ejemplo:
- *"proyecto nuevo de Southpoint, armame los archivos base"*
- *"arranco un proyecto personal, prepará el ambiente y el repo"*

## Onboarding de una PC nueva (compañero nuevo)

La primera vez que alguien va a usar estas skills en su máquina, corre `setup-mcp-workstation` una sola vez:

1. Clonar/recibir este repo.
2. Correr `.\tools\sync-skills.ps1` (deploya las skills a `~/.claude/skills/`).
3. Abrir Claude Code y decir *"configurá mi máquina para Southpoint"* → corre `setup-mcp-workstation`, que pide git/DOMO/Zoho **una sola vez**, persiste las env vars de usuario (sin imprimir secretos) e instala DOMO (`pip`) + Playwright (browsers).
4. Reiniciar Claude Code (para que tome las env vars nuevas).
5. Ya puede usar `bootstrap-southpoint-project` en cualquier proyecto: la identidad git sale de las env vars y el catálogo DOMO ya no necesita `DOMO_MCP_HOME`.

Python (para DOMO) y Node (para Playwright) son prerequisitos: la skill los verifica y, si faltan, guía cómo instalarlos (no aborta).

## Editar y deployar

```powershell
# después de editar skills/ en este repo:
.\tools\sync-skills.ps1
```
