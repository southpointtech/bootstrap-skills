# Bootstrap Skills — Context

Este repo es la **fuente de verdad** de las skills personales de bootstrap de proyectos.

Ver `docs/agents/domain.md` para la estructura de skills y el flujo editar → testear → deployar → commitear.

## Language

### El ciclo de revisión

**Slice**:
La unidad de cambio que se implementa y se revisa como un todo, acotada para que el reviewer no pierda precisión.
_Avoid_: feature, tarea, ticket

**Cierre de slice**:
El momento en que un slice queda listo para revisión. Es un acto declarado, no una consecuencia de haber commiteado o pusheado.
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

## Flagged ambiguities

**"review" a secas está sobrecargado** y esa ambigüedad ya causó un bug real: el loop apuntaba al reviewer equivocado y se cerraba sin revisar nada. Los tres son cosas distintas:

- **`/code-review`** — el reviewer built-in de Claude Code. Solo lo puede invocar un humano; el agente no puede lanzarlo.
- **`/slice-review`** — el reviewer del scaffold, invocable por el agente. Es el que hace una **corrida de review**.
- **`/review-loop`** — el loop que encadena **turnos** de `/slice-review` + fixes hasta que cierra.

Cuando se dice "corré el review", se habla de `/review-loop`. Cuando se dice "el reviewer", se habla de un subagente con un **foco**.

**"turno" no es "corrida de review"**: un turno incluye los fixes y su verificación; la corrida es solo la parte que revisa.

## Estado de implementación de los términos

El glosario define el vocabulario **decidido**, que no es lo mismo que shippeado. Hoy están
implementados el **marcador de revisión**, el **delta sin revisar**, el **turno** incremental, el
**pase de confianza** y el **trailer de cierre** — la línea `Slice-Close:` en el mensaje del commit
con la que el **cierre de slice** se declara a mano, en lugar de que el hook dispare en cada commit.
Siguen decididos pero **sin implementar**: el **pase de coherencia** y la **mutación acotada**. El
diálogo de abajo habla del diseño completo, no del comportamiento de hoy.

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
