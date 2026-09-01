# ADR-0008 — El techo de tamaño del slice se mide al abrirlo, no al cerrarlo

- **Estado**: aceptada
- **Fecha**: 2026-09-01
- **Contexto de la decisión**: release `bootstrap-v2`, después de que dos slices seguidos cerraran por
  encima del techo, con una parte del exceso puesta por el propio `/review-loop`.

## Contexto

El `CLAUDE.md` pide que cada slice vertical sea *"a small, reviewable unit of ≤ ~400 lines of logic
diff"*, y aclara que un slice **proyectado** muy por encima hay que partirlo antes de implementar. Lo
que no decía es **contra qué diff se mide el techo**, y en la práctica se leía como el diff final.

Medido sobre el slice 04c, commit por commit, contando altas **y** bajas y excluyendo `.md`:

| tramo | líneas |
|---|---|
| `3e175b0..cf925c0` — primer commit | **117** (111 + 6) |
| `3e175b0..900ba7f` — hasta el commit que **declara** el cierre (trailer `Slice-Close`) | **494** (458 + 36) |
| `900ba7f..2edb0a1` — los cuatro turnos del `/review-loop` | **296** (224 + 72) |
| `3e175b0..2edb0a1` — al cerrar | **660** (604 + 39 en `tools/recover-skill-bases.py`, 13 + 4 en su test) |

**El loop aportó 296 de 660 — el 45 %, no el grueso.** Cuando 04c declaró su cierre ya estaba en 494
líneas, 1,2× el techo, antes de que el review tocara nada. O sea que 04c **también** estaba mal
dimensionado al planificarse: su scope declarado eran los nueve Medium que había dejado abiertos el
review del issue 04, y esos nueve solos ya rompían el techo.

Eso importa para no sobrevender el motivo: el loop **no** es la única causa del exceso, es una causa
que se suma a un slice que ya estaba grande. Pero es la causa que **no se puede evitar planificando**,
y es la que hace que la regla se incumpla sola. Las otras dos formulaciones —"el primer commit son 117
líneas y el resto lo agregó el review", y "ninguno de los dos slices estaba mal planificado"—
estuvieron escritas en la primera versión de este ADR y son **falsas**; el review-loop de este mismo
slice las midió y las tiró abajo.

### Tres formas de contar, y ninguna es "la" forma

Un aviso para el próximo que compare números del techo, porque hay **tres bases distintas dando
vueltas** sobre el mismo rango `3e175b0..2edb0a1`:

| base | líneas | quién la usa |
|---|---|---|
| altas solas, excluyendo `.md` | **617** | el handoff del 2026-09-01 (y el 716 de 04b) |
| altas + bajas, excluyendo `.md` | **660** | este ADR |
| altas + bajas, con el `$skipPat` real del hook (que **no** excluye `.md`) | **874** | `.claude/hooks/review-loop-trigger.ps1` |

Ninguna está mal; no son comparables entre sí. Y la exclusión de `.md` que aplicaron el handoff y
este ADR **no la concede ninguna regla escrita**: ni el bullet del `CLAUDE.md` ni el `$skipPat` del
hook la mencionan. Se aplicó por criterio, no por contrato. Cerrar esa ambigüedad —qué cuenta como
"línea de lógica", y si se cuentan altas o altas+bajas— queda fuera del alcance de esta decisión y es
trabajo propio.

Con el techo medido al cerrar, la parte que pone el loop se vuelve inevitable: cuanto mejor funciona
el review, más se viola el techo. Y la única forma de cumplirlo sería partir el slice **a mitad del
loop**, que es justamente lo que el loop no tolera, porque cada turno revisa un **rango** anclado al
marcador; mover la base a mitad de camino deja turnos revisando rangos que ya no corresponden a nada.

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
