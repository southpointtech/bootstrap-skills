# Session Handoff — 2026-06-11

## 1. Objetivo del proyecto

Repo `Bootstrap Skills`: fuente de verdad de las skills personales de bootstrap de proyectos (`bootstrap-southpoint-project`, `bootstrap-personal-project`, `upgrade-bootstrap`). Las copias instaladas viven en `C:\Users\marti\.claude\skills\` y se deployan con `tools\sync-skills.ps1`. Reglas operativas en `CLAUDE.md` (raíz).

## 2. Tarea actual

Implementar una **feature nueva**: que `/bootstrap-...` adopte un proyecto que tiene `CLAUDE.md` propio pero **sin** `.bootstrap-manifest.json` — instalando la metodología de 8 steps **sin perder** el contexto/identidad del proyecto (merge del CLAUDE.md).

## 3. Estado de implementación

**Diseño y plan COMPLETOS y commiteados. La implementación NO empezó.** La próxima sesión arranca ejecutando el plan desde Task 1.

- Spec aprobado: `docs/superpowers/specs/2026-06-11-bootstrap-adopcion-merge-claudemd-design.md` (commit `ef11081`).
- Plan de implementación: `docs/superpowers/plans/2026-06-11-bootstrap-adopcion-merge-claudemd.md` (commit `7dec7b4`). **Este es el documento a ejecutar.**

### Decisiones de diseño (cerradas con el usuario)

- **Modelo conceptual:** la señal divisoria es `.bootstrap-manifest.json`. `/bootstrap-...` maneja TODO proyecto sin manifest (vacío, empezado sin CLAUDE.md, o empezado **con** CLAUDE.md propio → modo adopción). `/upgrade-bootstrap` SOLO si ya hay manifest.
- **Estrategia de merge = opción C (separar metodología de contexto):** el `CLAUDE.md` final queda canónico (8 steps); el contenido propio se reparte: reglas operativas → sección `## Hard rules` del CLAUDE.md; conocimiento de dominio (branching, gotchas, integraciones) → `docs/agents/domain.md`; descripción → `CONTEXT.md`.
- **4 salvaguardas:** (1) backup verbatim permanente del CLAUDE.md original en `docs/agents/legacy-claude.md`; (2) merge textual, prohibido parafrasear/resumir; (3) mapa de cobertura (bloque → destino) mostrado al usuario; (4) una aprobación global antes de aplicar (con override puntual).
- **Sellado del manifest = EMERGENTE (clave):** NO se tocan los scripts de `upgrade-bootstrap`. El modo adopción copia el scaffold completo (incluido `.bootstrap-manifest.json` que registra `CLAUDE.md = hash canónico` como base). Tras el merge, el CLAUDE.md en disco difiere del canónico → `compare-scaffold.ps1` lo clasifica como `customized` → un upgrade futuro nunca lo pisa. Verificado leyendo `compare-scaffold.ps1:29-34`.

## 4. Archivos cambiados en esta sesión

- `skills/bootstrap-southpoint-project/SKILL.md` — Step 0 reescrito (commit `8572d09`, ver nota abajo).
- `skills/bootstrap-personal-project/SKILL.md` — Step 0 reescrito espejado (commit `8572d09`).
- `skills/*/assets/scaffold/.bootstrap-manifest.json` — regenerados por sync (commit `8572d09`); corrigieron hashes stale de `settings.json` y `review-loop-trigger.ps1`.
- `docs/superpowers/specs/2026-06-11-bootstrap-adopcion-merge-claudemd-design.md` — nuevo (commit `ef11081`).
- `docs/superpowers/plans/2026-06-11-bootstrap-adopcion-merge-claudemd.md` — nuevo (commit `7dec7b4`).

**IMPORTANTE sobre el commit `8572d09`:** ese commit hizo que Step 0, ante "CLAUDE.md sin manifest", **derive a upgrade-bootstrap**. El plan nuevo (Task 2) **revierte ese comportamiento**: ese caso ahora entra en modo adopción (Step 0b), no deriva. No es un retroceso — es la evolución acordada.

## 5. Commands corridos (relevantes)

- `tools\sync-skills.ps1` — deploya y regenera manifests. Correr tras editar skills.
- `pwsh -File skills/upgrade-bootstrap/scripts/compare-scaffold.ps1 -ProjectDir <p> -CanonicalScaffold <c>` — clasifica archivos (verificación del sellado emergente).

## 6–11. Bugs / tests

- **Bug encontrado y corregido** esta sesión: el manifest commiteado tenía hashes stale de `.claude/settings.json` y `.claude/hooks/review-loop-trigger.ps1` (desde commits `105398b`/`2270412`). El sync los regeneró (commit `8572d09`).
- **Validación previa hecha:** se corrió un A/B con skill-creator del fix de Step 0; seguridad idéntica (5/5 runs no pisaron nada). No hay tests fallando. Workspace de evals borrado (hard rule del repo).
- **Tests pendientes (los define el plan):** caso de adopción en `docs/TESTING.md` (Task 1) + validación con subagente (Task 4).

## 12. TODOs pendientes (= ejecutar el plan)

Ejecutar `docs/superpowers/plans/2026-06-11-bootstrap-adopcion-merge-claudemd.md`, Task 1 → Task 5:
1. **Task 1:** agregar caso de adopción + assertions a `docs/TESTING.md`.
2. **Task 2:** reescribir bullet de Step 0 + agregar sección "Step 0b — Adoption mode" en `skills/bootstrap-southpoint-project/SKILL.md`.
3. **Task 3:** espejar verbatim en `skills/bootstrap-personal-project/SKILL.md` (verificar antes que el scaffold personal tenga `## Hard rules` y `docs/agents/domain.md`).
4. **Task 4:** `sync-skills.ps1`, sembrar proyecto KBS-like, correr la skill vía subagente, verificar 5 assertions + `compare-scaffold` clasifica `CLAUDE.md` como `customized`. Borrar workspace al final.
5. **Task 5:** commit de manifests regenerados si los hay.

## 13. Próximos pasos recomendados

Modo de ejecución elegido por el usuario: **continuar en terminal nueva**. La opción de ejecución del plan quedó abierta entre subagent-driven (recomendada) e inline — preguntar al usuario al retomar, o ir directo task-by-task. Empezar por Task 1 (es el más chico y de bajo riesgo).

## 14. Supuestos

- El bloque de prosa "Step 0b" es idéntico entre ambas variantes (no menciona DOMO ni identidad git), por eso el espejado es copia literal. **Verificar** en Task 3 Step 1 que el scaffold personal tiene `## Hard rules` antes de asumirlo.

## 15. Preferencias/constraints del usuario descubiertas

- El usuario considera que **el flujo de los 8 steps es lo de más valor** del bootstrap; todo lo demás son herramientas que cuelgan de esos steps. El merge debe priorizar adoptar la metodología.
- Miedo explícito a **perder contexto/valor** del CLAUDE.md → por eso las 4 salvaguardas son parte central, no opcionales.
- Modelo mental del usuario: "bootstrap para lo que no tiene bootstrap; upgrade solo si ya lo tiene".
- El usuario **no usa `/compact`**; prefiere handoff + terminal nueva.

## 16. Lo que la próxima sesión debe saber antes de editar

- **Hard rule del repo:** las dos skills de bootstrap se mantienen **espejadas en estructura** (Step 0–5). Todo cambio de mecánica va en ambas. Solo difieren en contenido DOMO e identidad git.
- **NO usar wildcard `scaffold\*`** en los copy de PowerShell (produce `.agents\.agents` anidados). Copia por enumeración top-level.
- Editar las skills acá NO tiene efecto hasta correr `tools\sync-skills.ps1`.
- `gitignore.txt` en assets se llama así a propósito (aterriza como `.gitignore`).
- Cualquier rastro de testeo (workspaces de evals, proyectos de prueba) se borra al terminar.
- Identidad de commit en este repo: `MartinDele703 <martin.deleon703@gmail.com>` (local).
- Git limpio al cierre de esta sesión salvo este handoff (que se commitea aparte).
