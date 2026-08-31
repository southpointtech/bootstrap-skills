# Bootstrap Skills — Context

Este repo es la **fuente de verdad** de las skills personales de bootstrap de proyectos.

Ver `docs/agents/domain.md` para la estructura de skills y el flujo editar → testear → deployar → commitear.

## Language

### El ciclo de revisión

**Slice**:
La unidad de cambio que se implementa y se revisa como un todo, acotada para que el reviewer no pierda precisión.
_Avoid_: feature, tarea, ticket

**Cierre de slice**:
El momento en que un slice queda listo para revisión. Es un acto declarado, no una consecuencia de haber commiteado o pusheado. El loop distingue dos formas de cierre: **cierre limpio** (la última revisión no dejó hallazgos medium/high) y **cierre por cap** (se agotaron los 5 turnos con hallazgos abiertos); solo el limpio limpia el ancla `slice-open` del pase de coherencia (ADR-0002).
_Avoid_: terminar, cerrar el commit

**Corrida de review**:
Una invocación completa del reviewer sobre un diff, con todos sus focos en paralelo.
_Avoid_: oleada, batch, pasada

**Turno**:
Una vuelta completa del loop: corrida de review → fixes → verificación. El loop tiene un techo de turnos.
_Avoid_: iteración, ciclo, ronda

**Marcador de revisión**:
La referencia que fija hasta dónde llegó la última revisión. Existe para que ningún cambio se revise dos veces ni quede sin revisar.
_Avoid_: checkpoint, snapshot, último SHA

**Delta sin revisar**:
El cambio entre el marcador de revisión y el estado actual del trabajo. Es el insumo de toda corrida de review salvo el pase de coherencia.
_Avoid_: diff pendiente, cambios nuevos

### Los revisores

**Reviewer**:
Un subagente con un único foco, sin permiso para modificar el trabajo que revisa. Reporta hallazgos; no arregla.
_Avoid_: revisor, agente de review, crítico

**Foco**:
El único ángulo que se le asigna a un reviewer, para que no se solape con los demás ni re-derive lo que ya derivó otro.
_Avoid_: área, especialidad, rol

**Pase de confianza**:
El filtro que puntúa cada hallazgo contra el código antes de que llegue al reporte, para que el loop no arregle falsos positivos.
_Avoid_: scorer, confidence pass, validación

**Pase de coherencia**:
La lectura final del slice como unidad, contra la intención declarada. No ejecuta nada: lo ejecutable ya se verificó por delta.
_Avoid_: review final, pase global

**Mutación acotada**:
La verificación de que los tests tienen dientes, con presupuesto: solo la lógica que el slice cambió, un techo de mutantes y el archivo de test relevante en lugar de la suite entera.
_Avoid_: mutation testing, mutation run

**Afirmación**:
Un enunciado verificable escrito en un comentario, docstring o mensaje de commit. Se escribe solo si se verificó; si no se verificó, no se escribe.
_Avoid_: claim, aserción, nota

### Las skills externas

**Base de merge**:
La versión de una skill externa de la que salió nuestra copia. El lockfile no la declara: se recupera identificando la versión histórica de upstream que minimiza el diff contra la nuestra. Sin base no hay merge de tres vías, solo adopción a ciegas.
_Avoid_: versión original, upstream viejo, el commit del que salió

**Drift**:
La distancia entre nuestra copia de una skill externa y su base de merge. Es exactamente lo que hay que volver a aplicar después de adoptar una versión nueva de upstream.
_Avoid_: customización, cambios locales, parche

**Fork propio**:
El veredicto —humano, firmado en el lockfile— de que una skill ya no se merge contra upstream: se marca así para que ningún merge futuro la busque, la reporte como faltante ni la borre en silencio. Es una conclusión, no una medición: la herramienta que recupera bases **no lo emite**, porque las dos situaciones que lo justifican son distintas y ninguna lo prueba sola.
_Avoid_: skill vieja, skill customizada, huérfana, orphaned

**Sin base sobre el umbral** (`no-match-above-threshold`):
Ninguna versión histórica de upstream supera el umbral de similitud contra nuestra copia. Es todo lo que se midió: un cuerpo con suficiente drift cae por debajo igual, así que no prueba que la skill nunca haya salido de upstream.
_Avoid_: never-upstream, nunca salió de upstream, skill nuestra

**Ausente del HEAD de upstream** (`gone-from-upstream-head`):
La skill tiene base de merge recuperada, pero su path ya no está en el HEAD de upstream y git no detecta renombre. No dice que upstream la haya borrado y listo: puede haber sucesor con otro nombre, y confirmarlo es decisión humana.
_Avoid_: orphaned, huérfana, skill borrada

**Skill puntero**:
Una skill cuyo cuerpo es una invocación a otra y cuyo único aporte propio es su description. Deja que el contenido evolucione en un solo lugar mientras el nombre y los triggers en español siguen siendo los que usan los proyectos.
_Avoid_: alias, wrapper, redirect

**Skill model-invoked**:
Una skill cuya description queda cargada en el contexto de cada request para que el agente —u otra skill— pueda alcanzarla solo. Se paga contexto permanente a cambio de auto-invocación; se justifica únicamente cuando el agente debe llegar a ella sin que un humano la tipee.
_Avoid_: skill automática, skill con triggers

**Skill user-invoked**:
Una skill que solo puede invocar el humano tipeando su nombre. Su description no entra al contexto y ninguna otra skill puede llamarla. Es el default para todo lo que en el flujo se *sugiere* al usuario en vez de ejecutarse solo.
_Avoid_: comando manual, skill oculta

**Cache de mecanismo**:
Texto del `CLAUDE.md` que restata lo que un hook, un config o un script ya hacen cumplir por sí mismos. Se carga en cada request sin agregar comportamiento; la fuente de verdad es el mecanismo. Se reduce a lo que el agente debe hacer más un pointer a la documentación.
_Avoid_: explicación del hook, contexto de fondo

## Flagged ambiguities

**"review" a secas está sobrecargado** y esa ambigüedad ya causó un bug real: el loop apuntaba al reviewer equivocado y se cerraba sin revisar nada. Los tres son cosas distintas:

- **`/code-review`** — el reviewer built-in de Claude Code. Solo lo puede invocar un humano; el agente no puede lanzarlo.
- **`/slice-review`** — el reviewer del scaffold, invocable por el agente. Es el que hace una **corrida de review**.
- **`/review-loop`** — el loop que encadena **turnos** de `/slice-review` + fixes hasta que cierra.

Cuando se dice "corré el review", se habla de `/review-loop`. Cuando se dice "el reviewer", se habla de un subagente con un **foco**.

**"turno" no es "corrida de review"**: un turno incluye los fixes y su verificación; la corrida es solo la parte que revisa.

## Estado de implementación de los términos

El glosario define el vocabulario **decidido**, que no es lo mismo que shippeado. Hoy están
implementados el **marcador de revisión** (con sus verbos de anclaje `open`/`slice-base` y de
limpieza `close`), el **delta sin revisar**, el **turno** incremental, el **pase de confianza**, el
**trailer de cierre** — la línea `Slice-Close:` en el mensaje del commit con la que el **cierre de
slice** se declara a mano, en lugar de que el hook dispare en cada commit —, el **pase de coherencia**
y la **mutación acotada**. Lo único que queda del track es el deploy a `~/.claude/skills` (A7). El
diálogo de abajo habla del diseño completo.

## Example dialogue

> **Dev**: Cerré el slice del formulario. ¿Corro el review?
>
> **Domain expert**: Si lo cerraste, el disparo ya pidió el loop. El primer turno revisa el delta sin revisar, no el slice entero.
>
> **Dev**: ¿Y por qué no el slice entero, si el slice es la unidad?
>
> **Domain expert**: Porque el slice entero lo va a mirar el pase de coherencia, una vez y sin ejecutar nada. Si cada turno revisara todo, pagarías la mutación acotada y los cinco focos de nuevo sobre código que ya pasó.
>
> **Dev**: El reviewer de tests me marcó que un assert no tiene dientes. ¿Lo arreglo?
>
> **Domain expert**: Primero mirá si sobrevivió al pase de confianza. Si el hallazgo entró al reporte, arreglalo y el turno siguiente revisa ese fix como delta sin revisar — no vuelve a mirar el resto.
>
> **Dev**: Le agrego un test al fix, entonces.
>
> **Domain expert**: Y verificás que falle sin el fix, antes de darlo por bueno. Un test que nunca falló no es una red, y si escribís en el comentario que lo mediste sin haberlo medido, eso es una afirmación sin verificar.
