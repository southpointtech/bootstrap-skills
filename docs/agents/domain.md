# Domain Docs

How the engineering skills should consume this repo's domain documentation when exploring the codebase.

## Before exploring, read these

- **`CONTEXT.md`** at the repo root, or
- **`CONTEXT-MAP.md`** at the repo root if it exists — it points at one `CONTEXT.md` per context. Read each one relevant to the topic.
- **`docs/adr/`** — read ADRs that touch the area you're about to work in.

If any of these files don't exist, **proceed silently**. Don't flag their absence; don't suggest creating them upfront. The producer skill (`/grill-with-docs`) creates them lazily when terms or decisions actually get resolved.

## File structure

Single-context repo:

```
/
├── CONTEXT.md
├── docs/adr/
│   ├── 0001-event-sourced-orders.md
│   └── 0002-postgres-for-write-model.md
└── src/
```

## Use the glossary's vocabulary

When your output names a domain concept (in an issue title, a refactor proposal, a hypothesis, a test name), use the term as defined in `CONTEXT.md`. Don't drift to synonyms the glossary explicitly avoids.

If the concept you need isn't in the glossary yet, that's a signal — either you're inventing language the project doesn't use (reconsider) or there's a real gap (note it for `/grill-with-docs`).

## Flag ADR conflicts

If your output contradicts an existing ADR, surface it explicitly rather than silently overriding:

> _Contradicts ADR-0007 (event-sourced orders) — but worth reopening because…_

## Project-specific domain

Este repo es la **fuente de verdad** de las skills personales de bootstrap de proyectos:

- `skills/bootstrap-southpoint-project/` — proyectos de cliente SOUTHPOINTLABS
- `skills/bootstrap-personal-project/` — proyectos personales de Martín
- `skills/upgrade-bootstrap/` — actualiza proyectos ya bootstrapeados al scaffold actual (merge-base por `.bootstrap-manifest.json`)

Las copias **instaladas** (las que Claude Code realmente usa) viven en `C:\Users\marti\.claude\skills\`. Editar acá NO tiene efecto hasta deployar.

### Flujo de trabajo

1. **Editar** la skill acá (SKILL.md y/o `assets/scaffold/`).
2. **Testear** con el skill-creator antes de deployar (ver `docs/TESTING.md`). Mínimo: el eval de directorio vacío + el de archivos preexistentes.
3. **Deployar** con `tools\sync-skills.ps1` (copia repo → `~/.claude/skills/`, borrando la versión instalada primero para no dejar archivos huérfanos).
4. **Commitear** acá con identidad local `MartinDele703 <martin.deleon703@gmail.com>`.

### Contexto histórico

Ver `docs/HISTORIA.md` para el origen, las decisiones de diseño y los resultados de los evals (iteraciones 1 y 2).
