# Bootstrap Skills — Reglas operativas

Este repo es la **fuente de verdad** de las skills personales de bootstrap de proyectos:

- `skills/bootstrap-southpoint-project/` — proyectos de cliente SOUTHPOINTLABS
- `skills/bootstrap-personal-project/` — proyectos personales de Martín

Las copias **instaladas** (las que Claude Code realmente usa) viven en `C:\Users\marti\.claude\skills\`. Editar acá NO tiene efecto hasta deployar.

## Flujo de trabajo

1. **Editar** la skill acá (SKILL.md y/o `assets/scaffold/`).
2. **Testear** con el skill-creator antes de deployar (ver `docs/TESTING.md`). Mínimo: el eval de directorio vacío + el de archivos preexistentes.
3. **Deployar** con `tools\sync-skills.ps1` (copia repo → `~/.claude/skills/`, borrando la versión instalada primero para no dejar archivos huérfanos).
4. **Commitear** acá con identidad local `MartinDele703 <martin.deleon703@gmail.com>`.

## Hard rules

- Las dos skills deben mantenerse **espejadas en estructura**: si cambiás la mecánica (Step 0–5 del SKILL.md), aplicá el mismo cambio en ambas. Solo difieren en: contenido DOMO (Southpoint sí, personal no) e identidad git.
- NO usar wildcard `scaffold\*` en los comandos de copia del Step 2 — en PowerShell 7 produce duplicados anidados `.agents\.agents` (bug encontrado y corregido en evals 2026-06-03). La copia es por enumeración top-level.
- `gitignore.txt` en assets se llama así a propósito (debe aterrizar como `.gitignore` en el proyecto destino). No renombrarlo en el repo.
- No dejar directorios vacíos en `assets/scaffold/` (git no los trackea y generan ruido en la copia).
- Si cambiás el `CLAUDE.md` template, evaluá si el cambio también aplica al `CLAUDE.md` real de Forecasting App (`C:\Repos\SOUTHPOINTLABS\Forecasting App`).
- Cualquier rastro de testeo (workspaces de evals, proyectos de prueba) se borra al terminar.

## Contexto histórico

Ver `docs/HISTORIA.md` para el origen, las decisiones de diseño y los resultados de los evals (iteraciones 1 y 2).
