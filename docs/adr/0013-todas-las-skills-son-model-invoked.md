# ADR 0013 — Todas las skills del scaffold son model-invoked

Status: accepted
Fecha: 2026-09-23
Revierte: la clasificación del issue v2 13 (`0ae9cce`, 2026-09-19)

## Contexto

El issue v2 13 marcó con `disable-model-invocation: true` a seis skills (`grill-me`,
`grill-with-docs`, `to-prd`, `to-issues`, `triage`, `handoff`), que se sumaron a las tres que ya lo
traían de upstream (`to-questionnaire`, `setup-matt-pocock-skills`, `zoom-out`). La razón fue la
dieta de contexto: una user-invoked no carga su description en cada request.

El costo apareció en el uso: cuando el flujo llegaba a una de esas nueve, el agente no podía
invocarla (`Skill to-issues cannot be used with Skill tool due to disable-model-invocation`) y el
humano tenía que tipearla. El dueño del repo, el 2026-09-23: "Quiero que todas esas skills vuelvan a
ser invocables por vos. No estoy de acuerdo con ese cambio."

## Decisión

- Las 21 skills del scaffold son **model-invoked**. Ninguna lleva `disable-model-invocation`, ni en
  `.claude/commands/` ni en `.agents/skills/`, en las cuatro raíces.
- La description de cada comando lleva su fórmula de disparo. Donde el `SKILL.md` ya la tenía, el
  comando recupera esa misma description. `grill-me`, `grill-with-docs` y `to-questionnaire` no
  tenían ninguna y ganaron una; los dos punteros de grill no repiten los triggers de `grilling`.
- `tests/invocation-policy.tests.ps1` sigue siendo una lista **declarada**: un comando nuevo se
  clasifica al entrar, y hoy las 21 entradas dicen model-invoked.

## Consecuencias

- **Costo medido** (mismo método que el issue 13: suma del valor de la línea `description:` de cada
  comando sin el flag, sobre `skills/bootstrap-personal-project/assets/scaffold/.claude/commands`):
  12 comandos / 5.709 caracteres antes, 21 comandos / 9.217 caracteres después (+3.508, +61,4 %).
  Se acepta a cambio de que el agente encadene el flujo sin frenar al humano.
- No se vuelve a pasar una skill a user-invoked para ahorrar contexto sin que lo decida el dueño del
  repo. Las notas viejas (`docs/superpowers/notes/2026-08-28-research-dieta-de-contexto.md`, el issue
  13) describen la decisión anterior, no la vigente.
- Queda en el cuerpo de `to-issues`, `to-prd` y `triage` la frase de upstream "tell the user to run
  `/setup-matt-pocock-skills`" (en `triage` la pinea `merge-triage-handoff-setup.tests.ps1`). Ya no es
  obligatoria, porque el agente puede invocarla, pero no es falsa: el humano todavía puede correrla.
