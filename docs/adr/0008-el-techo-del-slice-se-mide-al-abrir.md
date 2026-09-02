# ADR-0008 — El techo de tamaño del slice se mide al abrirlo, no al cerrarlo

- **Estado**: aceptada
- **Fecha**: 2026-09-01
- **Contexto de la decisión**: release `bootstrap-v2`, después de que dos slices seguidos cerraran por
  encima del techo, con una parte del exceso puesta por el propio `/review-loop`.

## Contexto

El `CLAUDE.md` pide que cada slice vertical sea *"a small, reviewable unit of ≤ ~400 lines of logic
diff"*, y aclara que un slice **proyectado** muy por encima hay que partirlo antes de implementar. Lo
que no decía es **contra qué diff se mide el techo**, y en la práctica se leía como el diff final.

Medido sobre el slice 04c, **un commit por fila** — sin acumulados, que es de donde salieron las
primeras atribuciones falsas de este documento. Cada fila es `git diff --numstat <sha>^ <sha> -- .
':(exclude)*.md'`, altas más bajas.

**`tests/techo-del-slice.tests.ps1` verifica esta tabla contra `git`**: los ocho números, que las
filas sean exactamente los ocho commits del slice y en orden, y que ninguna fila sea un rango. Lo
que el test **no** puede verificar es a quién atribuirle cada línea; de eso habla la sección
*«Por qué acá no hay un reparto»*, más abajo.

| commit | líneas | |
|---|---|---|
| `cf925c0` | 117 (111 + 6) | |
| `64b5587` | 166 (139 + 27) | |
| `c8ec7ee` | 103 (63 + 40) | |
| `900ba7f` | 232 (207 + 25) | ← lleva el trailer `Slice-Close:`, o sea **declara el cierre del slice** |
| `0eb467f` | 248 (180 + 68) | |
| `693d0e2` | 111 (75 + 36) | |
| `efbe76e` | 37 (20 + 17) | |
| `2edb0a1` | 18 (8 + 10) | |

El acumulado del slice entero (`3e175b0..2edb0a1`) es **660**. No es la suma de las filas (1.032)
porque hay churn: una línea que dos commits tocan cuenta dos veces por commit y una sola en el
acumulado. La suma por commit **sobrecuenta**, siempre.

### Por qué acá no hay un reparto entre "scope" y "fixes del loop"

Porque **no se puede hacer con estos commits**. `0eb467f` es mixto: su cuerpo dice *"F18 y F14, que el
trailer del commit anterior daba por cerrados sin que el delta los tocara"*, y el handoff (la fila `| F14 | la invariante` de la tabla de cierre de 04c, y la de F18)
los registra cerrados ahí. F14 y F18 son **scope** —dos de los nueve Medium que el slice vino a
cerrar— y viajan en el mismo commit que arreglos de hallazgos del loop. Cualquier número que reparta
esas 248 líneas entre las dos categorías sería una estimación presentada como medición, que es
exactamente el error que este documento acumuló cinco veces.

Lo que la tabla **sí** sostiene, y alcanza para la decisión:

- Cuatro de los ocho commits son **posteriores al cierre declarado** (`900ba7f`), y suman **414
  líneas**. Existen porque el `/review-loop` corrió después de que el slice se dio por cerrado: no
  hay otra cosa que los explique, y son más que el techo entero.
- El loop también había corrido **antes** de ese cierre —dos turnos, `docs/SESSION_HANDOFF.md`, encabezado
  (*"turno 2 de 5, NO cerrado"*)—, así que su contribución no está acotada a esos cuatro commits.

Con eso basta: **el loop le agrega líneas al slice que revisa, después de que el slice cerró.** Si el
techo se mide sobre el diff final, esas líneas cuentan contra un slice que ya no se puede replanificar.

> **Cinco afirmaciones falsas mías en este párrafo, sobre los mismos ocho commits.** (1) *"El primer
> commit del slice son 117 líneas; el resto lo agregó el review."* — había más commits que cierran
> scope. (2) *"Cuando 04c declaró su cierre ya estaba en 494 líneas, 1,2× el techo, antes de que el
> review tocara nada"* — el loop ya había corrido dos turnos antes de `900ba7f`. (3) *"había tres
> commits de scope más"* — la corrección que se publicó en su lugar (*"había uno"*) también era
> falsa, y por la misma causa: se calculó con la clasificación que la falsedad (5) derogó cuatro
> líneas más abajo. Lo verificable es la **membresía**, no el reparto de líneas: **tres** commits
> cierran alguno de los nueve Medium — `cf925c0` (F3, F15), `900ba7f` (F2, F5, F21) y
> `0eb467f` (F14, F18), con F4 y F6 cerrados entre los dos —, y el último es mixto. (4) Una tabla anunciada "commit por commit" con una
> fila (`900ba7f..2edb0a1`, 296) que era un acumulado de cuatro commits; por commit son 414.
> (5) Clasificar las 248 líneas de `0eb467f` como "fixes del loop" cuando el commit también cierra
> F14 y F18, que eran scope — y de esa
> clasificación dependía la conclusión *"el scope solo está por debajo del techo"*, que por eso ya no
> se afirma.
>
> Fueron **cuatro** las versiones que publicaron alguna de estas cinco —`919e567` la (1), `87f11fe`
> la (2), `ebfc19b` las (3) y (4), `5ba9aff` la (5)—, así que la correspondencia no es una por
> versión. A cada una la corrigió el turno siguiente del
> review-loop leyendo el arreglo del turno anterior. **Todas eran de atribución, no de medición**: los
> números siempre estuvieron bien; lo que estaba mal era de quién se decía que eran. Poner la
> medición bajo un test cierra la mitad medible. La otra mitad se cierra **no afirmándola**.

### Tres formas de contar, y ninguna es "la" forma

Un aviso para el próximo que compare números del techo, porque hay **tres bases distintas dando
vueltas** sobre el mismo rango `3e175b0..2edb0a1`:

| base | líneas | quién la usa |
|---|---|---|
| altas solas, excluyendo `.md` | **617** | el handoff (que lo declara sobre otro rango; ver abajo) |
| altas + bajas, excluyendo `.md` | **660** | este ADR |
| altas + bajas, con el `$skipPat` real del hook (que **no** excluye `.md`) | **874** | `.claude/hooks/review-loop-trigger.ps1` |

El **617** viene del handoff (`docs/SESSION_HANDOFF.md`, encabezado "El techo de tamaño, otra vez"), pero **no sobre el rango que el handoff declara**: ahí dice `3e175b0..HEAD`, y ese rango daba 919 altas medido en `4227fde` — al terminar en `HEAD` el número cambia con cada commit, que es exactamente el problema. Reproduce sobre `3e175b0..2edb0a1`, que es el que usa este ADR — o sea que el número es correcto y la referencia del handoff quedó vieja al seguir avanzando `HEAD`.

Un cuarto número, el **716** que el handoff publica para 04b (`docs/SESSION_HANDOFF.md`, encabezado "Dos cosas ABIERTAS que el próximo debe saber", punto 1), **no reproduce con ninguna de las tres** sobre el rango que el propio handoff declara (su tabla de slices, fila 04b: `1c52fe0`…`3e175b0`): esa base da 735, y 607 con la otra frontera. Queda anotado como no reproducido en vez de asignado a una base que no lo produce.

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
- La regla se propaga a **cinco** sitios más que la **ejecutan**, y cambiarla en el `CLAUDE.md` sin
  tocarlos deja instrucciones contradictorias vivas: el pre-flight de `/review-loop`, el paso "Close
  the slice" de `tdd`, el pre-flight de `/slice-review`, y los dos docs de `docs/ai-workflow/`
  (`AI_DEVELOPMENT_WORKFLOW.md` y `DEPLOYMENT_RULES.md`) que el `CLAUDE.md` declara lectura
  obligatoria. Un sexto portador, `to-issues`, **no** hizo falta tocarlo: ya medía al proyectar
  (*"a slice projected well over ~400 lines ... MUST be split before it is published"*). `tests/techo-del-slice.tests.ps1` verifica las dos mitades
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
