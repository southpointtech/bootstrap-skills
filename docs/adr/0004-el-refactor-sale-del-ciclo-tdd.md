# ADR-0004 — El refactor sale del ciclo de TDD y vive en la etapa de review

- **Estado**: aceptada
- **Fecha**: 2026-08-28
- **Contexto de la decisión**: grill de la próxima versión del bootstrap (2026-08-28), al adoptar la
  versión actual de la skill `tdd` de upstream.

## Contexto

La skill `tdd` del scaffold enseña `red → green → refactor` y su `description` usa esa frase como
trigger. Upstream (`mattpocock/skills`) eliminó la tercera etapa el 2026-06-30, en el commit `80e9dcc`
(*"tdd: drop the refactor stage — red → green, not red → green → refactor"*), con este motivo textual:

> Refactoring belongs to the review stage, not the implementation loop.

Ese commit borró además `refactoring.md`, hoy presente en nuestra copia (10 líneas).

El argumento de upstream aplica con más fuerza acá que allá: este scaffold ya tiene un `review-loop`
que corre después de cada cierre de slice, detecta y arregla, con un foco dedicado a simplificación.
Con el refactor también dentro del loop de implementación, la misma mejora se busca dos veces —
primero sin la evidencia que da la corrida de review, después con ella.

## Decisión

Adoptamos `red → green`. El refactor deja de ser una etapa del ciclo de TDD y pasa a ser
responsabilidad de la etapa de review. `refactoring.md` se retira junto con la regla.

## Alternativas descartadas

**Conservar `red → green → refactor` como fork propio.** Era lo barato: no toca el vocabulario ya
instalado en los proyectos bootstrapeados ni la `description` de la skill. Descartada porque convierte
cada merge futuro de `tdd` contra upstream en un conflicto recurrente, y porque deja el refactor
viviendo en dos lugares del flujo sin decir cuál manda.

**Diferirlo hasta medir cuántos refactors del loop de TDD encuentran algo que el review no habría
encontrado igual.** Descartada por costo de medición desproporcionado frente al tamaño del cambio: la
señal requeriría clasificar transcripts a mano, y la decisión es reversible con una línea si se
demuestra lo contrario.

## Consecuencias

- **Cambia doctrina escrita fuera de este repo.** La frase `red-green-refactor` aparece en el
  `CLAUDE.md` del scaffold y por lo tanto en los proyectos ya bootstrapeados. El cambio viaja con el
  rollout de esta versión y hay que anunciarlo explícitamente: un proyecto que reciba la skill nueva y
  conserve el texto viejo queda contradiciéndose a sí mismo.
- **La `description` de `tdd` pierde un trigger.** Quien diga "red-green-refactor" tiene que seguir
  cayendo en la skill, así que el trigger se conserva aunque la etapa no exista, apuntando a que el
  refactor se hace en el review.
- **Sube la carga del `review-loop`**: lo que antes se limpiaba durante la implementación ahora llega
  al review. Es el efecto buscado, no un daño colateral, pero conviene mirarlo cuando se comparen los
  turnos por slice antes y después.
