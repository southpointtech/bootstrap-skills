# ADR-0008 — El techo de tamaño del slice se mide al abrirlo, no al cerrarlo

- **Estado**: aceptada
- **Fecha**: 2026-09-01
- **Contexto de la decisión**: release `bootstrap-v2`, después de que dos slices seguidos cerraran por
  encima del techo sin que ninguno estuviera mal planificado.

## Contexto

El `CLAUDE.md` pide que cada slice vertical sea *"a small, reviewable unit of ≤ ~400 lines of logic
diff"*, y aclara que un slice **proyectado** muy por encima hay que partirlo antes de implementar. Lo
que no decía es **contra qué diff se mide el techo**, y en la práctica se leía como el diff final.

Medido hoy sobre el slice 04c (`3e175b0..2edb0a1`, excluyendo `.md` y la lista de generados del
`CLAUDE.md`), contando altas **y** bajas, que es como cuenta el hook `review-loop-trigger`:

| | líneas |
|---|---|
| **04c al cerrar** | **660** (604+39 en `tools/recover-skill-bases.py`, 13+4 en su test) |
| su primer commit (`cf925c0`) | 117 |

Un aviso para el próximo que compare números: el handoff del 2026-09-01 reporta **617** para el mismo
rango, y para 04b reporta 716. Los 617 son las **altas solas** (604 + 13); el hook cuenta altas más
bajas. Los dos números miden cosas distintas y ninguno está mal — pero no son comparables entre sí.

Lo que importa no es el valor exacto sino de dónde salió: **de los fixes del propio `/review-loop`**,
que en cuatro turnos cerró nueve hallazgos Medium sobre el mismo archivo. El primer commit del slice
son 117 líneas; el resto lo agregó el review. El loop le agrega líneas al slice que revisa.

Con el techo medido al cerrar, la regla se incumple sola: cuanto mejor funciona el review, más se
viola el techo. Y la única forma de cumplirla sería partir el slice **a mitad del loop**, que es
justamente lo que el loop no tolera, porque cada turno revisa un **rango** anclado al marcador; mover
la base a mitad de camino deja turnos revisando rangos que ya no corresponden a nada.

## Decisión

**El techo se mide cuando el slice ABRE**, sobre lo que uno se propone implementar.

- Un slice **proyectado** muy por encima de ~400 líneas de lógica se parte **antes** de implementar.
- Las líneas que `/review-loop` agrega arreglando sus propios hallazgos **no cuentan** contra el slice
  que está arreglando.
- Si el diff de cierre termina muy por encima igual, se **declara** al cerrar. No se parte a mitad del
  loop.
- Lo que nunca cuenta sigue igual: generados, vendored (`docs/vendor/`), lockfiles y snapshots.

## Consecuencias

- La regla vuelve a ser accionable en el único momento en que se puede actuar sobre ella: al
  planificar. Antes obligaba a una acción imposible en el único momento en que se evaluaba.
- Se pierde la señal automática de "este slice terminó grande". Se compensa declarándolo al cerrar,
  que es información para el handoff, no un bloqueo.
- La red de seguridad del hook `review-loop-trigger` **no cambia**: sigue midiendo el delta sin
  revisar contra la misma guía de ~400 líneas para disparar un review en un commit sin trailer. Esa
  guía responde otra pregunta —"¿esto quedó sin revisar?"— y no es el techo de planificación.

## Alternativas descartadas

- **Medir al cerrar** (statu quo): consistente con la letra vieja, pero exige partir a mitad del loop,
  que rompe el propio loop. Los dos últimos slices lo habrían gatillado, con cualquiera de las dos
  formas de contar.
- **Dos números** (techo de planificación al abrir, techo de alarma más alto al cerrar): cubre el caso
  del slice que crece de más, pero agrega una regla y un número sin medición que lo justifique. Si
  aparece el caso de un slice que crece sin que el loop lo explique, se revisa.
