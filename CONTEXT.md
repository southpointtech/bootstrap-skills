# Bootstrap Skills — Context

Este repo es la **fuente de verdad** de las skills personales de bootstrap de proyectos.

Ver `docs/agents/domain.md` para la estructura de skills y el flujo editar → testear → deployar → commitear.

## Language

### El ciclo de revisión

**Slice**:
La unidad de cambio que se implementa y se revisa como un todo, acotada para que el reviewer no pierda precisión.
_Avoid_: feature, tarea, ticket

**Cierre de slice**:
El momento en que un slice queda listo para revisión. Es un acto declarado, no una consecuencia de haber commiteado o pusheado. El loop distingue tres formas de cierre: **cierre limpio** (la última revisión no dejó hallazgos medium/high; en `light`, ningún High), **cierre por prosa** (el delta sin revisar es sólo prosa fuera de los archivos que gobiernan al agente) y **cierre por cap** (se agotó el techo de turnos con hallazgos abiertos). Todo cierre que no sea por cap limpia el ancla `slice-open` del pase de coherencia (ADR-0002, ampliado por ADR-0009).
_Avoid_: terminar, cerrar el commit

**Corrida de review**:
Una invocación completa del reviewer sobre un diff, con todos sus focos en paralelo.
_Avoid_: oleada, batch, pasada

**Turno**:
Una vuelta completa del loop: corrida de review → fixes → verificación. El loop tiene un techo de turnos.
_Avoid_: iteración, ciclo, ronda

**Rigor de review**:
Cuánta revisión lleva un slice, declarada por el agente en el commit de cierre con el trailer `Review-Rigor:`. `light` es un turno con dos focos y sin pase de coherencia; `standard`, el default, son hasta dos turnos. Un High en un slice `light` lo promueve a `standard`.
_Avoid_: nivel, modo, profundidad

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
Una skill que solo puede invocar el humano tipeando su nombre. Su description no entra al contexto y ninguna otra skill puede llamarla. Hoy el scaffold no tiene ninguna: desde ADR-0013 las 21 son model-invoked, y pasar una a user-invoked es decisión del dueño del repo.
_Avoid_: comando manual, skill oculta

**Cache de mecanismo**:
Texto del `CLAUDE.md` que restata lo que un hook, un config o un script ya hacen cumplir por sí mismos. Se carga en cada request sin agregar comportamiento; la fuente de verdad es el mecanismo. Se reduce a lo que el agente debe hacer más un pointer a la documentación.
_Avoid_: explicación del hook, contexto de fondo

### El bootstrap

**Scaffold**:
El árbol de archivos canónico que la skill instala en un proyecto. Es la fuente de verdad: se copia, no se regenera, para que la redacción del workflow sea idéntica en todos los proyectos.
_Avoid_: template, boilerplate, plantilla

**Modo adopción**:
La instalación del scaffold sobre un proyecto que ya trae su propia versión del workflow —un `CLAUDE.md` o un `docs/ai-workflow/` sin manifest—, y por eso exige un mapa de cobertura aprobado antes de mergear. Que el destino tenga otros archivos no alcanza: un directorio con código pero sin esos dos es un bootstrap normal, que informa lo que pisó y sigue.
_Avoid_: bootstrap sobre existente, re-bootstrap, migración

**Archivo propio**:
El que ya existía en el destino y no vino del scaffold. No es una personalización de nada: nunca fue canónico.
_Avoid_: archivo del usuario, custom, local

**Pisado**:
El archivo propio sobre el que la copia escribió. Toda copia que pisa deja primero un respaldo, así que pisar no es perder.
_Avoid_: sobrescrito, conflicto, clobber

### Los carriles

**Orquestador**:
La única terminal que habla con el humano cuando se trabaja en paralelo. Planea la ola, abre los worktrees, despacha los carriles, revisa e integra en serie.
_Avoid_: agente principal, coordinador

**Carril**:
Un subagente que implementa un solo slice en su propio worktree, durante una sola ola. No habla con el humano ni con otros carriles.
_Avoid_: agente paralelo, worker, lane

**Ola**:
Hasta tres carriles que corren a la vez. Termina cuando todas sus ramas están integradas y la suite completa pasó sobre la base.
_Avoid_: tanda, batch, sprint

**Mecánica de carriles**:
Las reglas de trabajo en paralelo que valen para cualquier proyecto. Llegan igual a todos por el scaffold y ningún proyecto las edita. Una lección de una ola que vale para cualquier proyecto se sube a la mecánica, no se queda en el proyecto donde apareció.
_Avoid_: norma del proyecto, plantilla de paralelismo

**Datos del proyecto** (de carriles):
Lo que la mecánica necesita saber de un proyecto concreto: camino crítico, archivos calientes, recursos por carril, carpeta de worktrees, guardas transversales, la ola vigente y lo que dejó cada ola. Llega con marcas sin rellenar y se completa recién cuando el proyecto tiene issues y va a abrir su primera ola.
_Avoid_: configuración, plantilla rellenada

**Marca sin rellenar**:
Un `{{…}}` que sigue en los datos del proyecto. Mientras quede una, no se despacha ninguna ola: una marca vacía no puede pasar por un dato.
_Avoid_: placeholder, TODO

**Archivo caliente**:
El archivo que casi todos los slices de una ola necesitan tocar (entrypoint, router, registro). Tiene un solo dueño por ola; los demás carriles le pasan su diff al orquestador.
_Avoid_: archivo compartido, hotspot

### La sincronización con el Hub

**Hub**:
El SouthPoint-Hub: donde el cliente ve el estado de su proyecto, su trazabilidad y el soporte posterior al deploy. Todo lo que se escribe ahí puede llegarle al cliente.
_Avoid_: portal, dashboard, Command Center

**Proyecto del Hub**:
Uno solo por repo, y acumula todos sus stages: un stage nuevo se escribe a continuación de lo anterior, no en un proyecto aparte, para que quede el registro completo.
_Avoid_: proyecto por stage, delivery (es el tipo, no el término)

**Stage**:
Un tramo planificado del proyecto que se desarrolla y se libera. Los stages son sucesivos, nunca paralelos, y viven todos en el mismo proyecto del Hub.
_Avoid_: fase (la fase es una entidad del Hub), etapa, versión

**Ongoing Support**:
El soporte posterior a la liberación, uno por proyecto y del proyecto en general, sin importar qué stage originó el pedido. Puede correr en paralelo con el desarrollo de un stage nuevo.
_Avoid_: onboarding support, maintenance (es el tipo en el Hub), mantenimiento

**Propuesta**:
Un cambio al Hub que todavía nadie aprobó. La genera la máquina; solo el PM la convierte en escritura.
_Avoid_: borrador, draft, update (Update es una entidad del Hub, no esto)

**Recolección**:
La corrida diaria en la máquina de cada dev que lee lo que pasó en el proyecto y deja propuestas. No lee ni escribe el Hub.
_Avoid_: sync, sincronización, job

**Bandeja de propuestas**:
El lugar compartido donde las recolecciones de todos los devs dejan sus propuestas y donde el PM las revisa.
_Avoid_: cola, inbox, artifact

**Aprobación**:
El acto del PM de revisar las propuestas contra el estado actual del Hub, editarlas, juntarlas o descartarlas, y recién entonces escribirlas. Es el único camino por el que algo llega al Hub.
_Avoid_: review, revisión (ver la ambigüedad de "review" abajo), publicación

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
