# Bootstrap Skills

Fuente de verdad de las skills de Claude Code que scaffoldean proyectos nuevos con el modus operandi de desarrollo asistido por AI (workflow de 8 pasos + Workflow State Machine, docs de ai-workflow, skills de agente, git init con identidad correcta).

| Skill | Para | Git identity |
|---|---|---|
| `bootstrap-southpoint-project` | Proyectos de cliente SOUTHPOINTLABS (incluye DOMO/Zoho) | `southpointtech <mdeleon@agtium.com>` |
| `bootstrap-personal-project` | Proyectos personales (sin DOMO; persisten Playwright/Firebase/Azure/Zoho) | `MartinDele703 <martin.deleon703@gmail.com>` |

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

## Editar y deployar

```powershell
# después de editar skills/ en este repo:
.\tools\sync-skills.ps1
```
