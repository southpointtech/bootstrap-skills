# ADR-0008 — El techo de tamaño del slice se mide al abrirlo, no al cerrarlo

- **Estado**: aceptada
- **Fecha**: 2026-09-01
- **Contexto de la decisión**: release `bootstrap-v2`, después de que dos slices seguidos cerraran por
  encima del techo, con una parte del exceso puesta por el propio `/review-loop`.

## Contexto

El `CLAUDE.md` pide que cada slice vertical sea *"a small, reviewable unit of ≤ ~400 lines of logic
diff"*, y aclara que un slice **proyectado** muy por encima hay que partirlo antes de implementar. Lo
que no decía es **contra qué diff se mide el techo**, y en la práctica se leía como el diff final.

Medido sobre el slice 04c, **un commit por fila** — sin acumulados, que es de donde salieron todas
las atribuciones falsas de este documento. Cada fila es `git diff --numstat <sha>^ <sha> -- .
':(exclude)*.md'`, altas más bajas. La clasificación sale del cuerpo de cada commit y del handoff.

**`tests/techo-del-slice.tests.ps1` verifica esta tabla contra `git` en cada corrida.** Si un número
de acá abajo deja de ser cierto, la suite se pone roja. No es prosa: es un aserto.

| commit | líneas | qué es |
|---|---|---|
| `cf925c0` | 117 (111 + 6) | scope (F3, F15) |
| `64b5587` | 166 (139 + 27) | fixes del loop |
| `c8ec7ee` | 103 (63 + 40) | fixes del loop |
| `900ba7f` | 232 (207 + 25) | scope (F2, F4, F5, F6, F21) — lleva el trailer `Slice-Close:` |
| `0eb467f` | 248 (180 + 68) | fixes del loop |
| `693d0e2` | 111 (75 + 36) | fixes del loop |
| `efbe76e` | 37 (20 + 17) | fixes del loop |
| `2edb0a1` | 18 (8 + 10) | fixes del loop |

Sumados por tipo: **349 de scope** (dos commits) y **683 de fixes del loop** (seis commits). El
acumulado del slice entero (`3e175b0..2edb0a1`) es **660**, y no coincide con 349 + 683 = 1.032
porque hay churn: una línea que dos commits tocan cuenta dos veces en la suma por commit y una sola
en el acumulado. Por eso la suma por commit **sobrecuenta**, y por eso sirve para lo único que se le
pide acá.

La única conclusión que estos números sostienen: **el loop puso más líneas que el scope**, y el scope
solo —349, y realmente menos, porque sobrecuenta— está **por debajo** del techo. No hay evidencia de
que 04c estuviera mal dimensionado al planificarse.

> **Cuatro versiones de este párrafo, cuatro afirmaciones falsas mías, todas sobre los mismos ocho
> commits.** (1) *"el primer commit son 117 líneas y el resto lo agregó el review"* — había un commit
> de scope más, `900ba7f`. (2) *"cuando 04c declaró su cierre ya estaba en 494 líneas, antes de que el
> review tocara nada"* — el loop ya había corrido dos turnos antes de `900ba7f`
> (`docs/SESSION_HANDOFF.md:190`) y 269 de esas 494 eran suyas. (3) *"había tres commits de scope
> más"* — había uno. (4) La tabla que se anunciaba "commit por commit" tenía una fila
> (`900ba7f..2edb0a1`, 296) que era **un acumulado de cuatro commits**; por commit son 414.
>
> Las cuatro tienen la misma causa y las cuatro las encontró un turno del review-loop leyendo el
> arreglo del turno anterior. Agregar cláusulas no las cerró. Lo que las cierra es **sacar el número
> de la prosa**: la tabla de arriba hoy la verifica un test contra `git`, y una quinta versión
> equivocada se pone roja en vez de publicarse.

### Tres formas de contar, y ninguna es "la" forma

Un aviso para el próximo que compare números del techo, porque hay **tres bases distintas dando
vueltas** sobre el mismo rango `3e175b0..2edb0a1`:

| base | líneas | quién la usa |
|---|---|---|
| altas solas, excluyendo `.md` | **617** | el handoff del 2026-09-01 |
| altas + bajas, excluyendo `.md` | **660** | este ADR |
| altas + bajas, con el `$skipPat` real del hook (que **no** excluye `.md`) | **874** | `.claude/hooks/review-loop-trigger.ps1` |

Un cuarto número, el **716** que el handoff publica para 04b (`docs/SESSION_HANDOFF.md:398`), **no reproduce con ninguna de las tres** sobre el rango que el propio handoff declara (`:351`): esa base da 735, y 607 con la otra frontera. Queda anotado como no reproducido en vez de asignado a una base que no lo produce.

Ninguna de las tres está mal; no son comparables entre sí. Y la exclusión de `.md` que aplicaron el handoff y
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
- La regla se propaga a cuatro lugares más que la **ejecutan**, y cambiarla en el `CLAUDE.md` sin
  tocarlos deja instrucciones contradictorias vivas: el pre-flight de `/review-loop`, el paso "Close
  the slice" de `tdd`, el pre-flight de `/slice-review` y los dos docs de `docs/ai-workflow/` que el
  `CLAUDE.md` declara lectura obligatoria. `tests/techo-del-slice.tests.ps1` verifica las dos mitades
  —cláusula nueva presente, instrucción vieja ausente— en las 4 copias de cada sitio, porque
  `mirror.tests.ps1` tiene `assets/scaffold/CLAUDE.md` en su allowlist, así que ninguna suite miraba
  **el bullet** (sí hay otras que leen esos archivos por otras reglas).

### Evaluación de Forecasting App (regla del `CLAUDE.md`)

El `CLAUDE.md` pide evaluar si un cambio al template aplica también al `CLAUDE.md` real de
Forecasting App. **Evaluado el 2026-09-01: aplica.** `C:\Repos\SOUTHPOINTLABS\Forecasting App\CLAUDE.md:98`
tiene el bullet viejo —el que no dice contra qué diff se mide, que es justamente lo que esta
decisión cierra—. **No se aplicó desde acá**, a propósito: ese repo se
actualiza por el rollout del issue 18, que además necesita aprobación humana. Dato para ese rollout:
el bullet del `/review-loop` de Forecasting (`:82`) está **más adelantado** que el de esta rama —ya
trae el gate de docs de `main`—, así que el merge no es en una sola dirección.

## Alternativas descartadas

- **Medir al cerrar** (statu quo): consistente con la letra vieja, pero exige partir a mitad del loop,
  que rompe el propio loop. Los dos últimos slices lo habrían gatillado, con cualquiera de las dos
  formas de contar.
- **Dos números** (techo de planificación al abrir, techo de alarma más alto al cerrar): cubre el caso
  del slice que crece de más, pero agrega una regla y un número sin medición que lo justifique. Si
  aparece el caso de un slice que crece sin que el loop lo explique, se revisa.
