# ADR-0001 — Review incremental sobre el delta sin revisar, anclado a un marcador

- **Estado**: aceptada
- **Fecha**: 2026-08-11
- **Contexto de la decisión**: sesión de `/grill-with-docs` sobre el costo del ciclo de revisión
- **Implementa**: Track A, `.scratch/review-cost-redesign/PRD.md` — **fuera de git** (`.scratch/`
  está gitignoreado), así que este ADR no depende de él: lo que hay que saber está acá.
- **Se juzga con**: Track B, la medición que vive en el repo `claude-analytics`
  (`.scratch/review-cost-measurement/`), también fuera de git. La línea base de agosto que sostiene
  esta decisión se pierde alrededor del **2026-09-10** por la retención de 30 días de los
  transcripts; la copia congelada está en `claude-analytics/output/raw/review-cost-baseline-2026-08/`.

## Contexto

El 1 de agosto de 2026 el ciclo de revisión empezó a funcionar de verdad: hasta ese día el loop
apuntaba al built-in `/code-review` y no producía reviews que lo cerraran, así que cerraba sin
revisar nada. Con el fix (apuntarlo a `/slice-review`), apareció el costo completo.

> Nota (2026-08-26): la justificación original de este cambio incluía la premisa de que `/code-review`
> "no era invocable por el agente". Esa premisa **caducó** — se verificó que es invocable, incluso
> desde un subagente (ver `docs/adr/0003-code-review-como-foco-acotado.md`). La decisión de este ADR
> sigue válida; solo esa premisa era falsa, y el motor del loop ahora suma `/code-review` como
> reviewer independiente del turno 1.

Medido sobre 703 transcripts (28.502 llamadas al modelo, 1.393 turnos), en agosto: 357 reviewers,
8.930 pasos, 8,74M tokens, **67,2 h en serie / 36,3 h de reloj**, y el **46% de todos los tokens de
salida del mes** generados por reviewers (era 8% en julio). El turno pasó de 4 a 9 pasos y de 92 s a
187 s de reloj; las horas de máquina ocupada por día pasaron de ~7 a ~11.

Se descartaron dos explicaciones alternativas con datos:

- **No es el modelo.** Latencia por llamada estable desde abril (opus-4-7 4,7–6,2 s, opus-4-8
  7,0–8,0 s, opus-5 6,5–7,1 s) y cola en mejora (p90 42,4 s → 29,2 s). Aislando repo y mes, Opus 5
  aporta +32% de tiempo de máquina por turno: amplificador, no causa.
- **No son proyectos más grandes.** El contexto por llamada bajó: 183k (abril) → 145k (junio) → 102k
  (agosto).

El desperdicio dominante es **revisar dos veces lo mismo**. El disparo ocurría en cada `git commit` y
la corrida de review tomaba el rango completo de la rama. En un repo, el mismo rango se revisó en 5
disparos a lo largo de 3 días: 27 reviewers, 540 minutos. En otro: 2 disparos, 15 reviewers, 186
minutos.

El criterio de optimización del usuario, textual: **"el menor tiempo posible pero que la revisión sea
completa y acertada"**.

## Decisión

El ciclo de revisión deja de razonar sobre el rango completo de la rama y pasa a razonar sobre el
**delta sin revisar**, anclado a un **marcador de revisión** que avanza **después de cada corrida de
review y antes de aplicar los fixes de ese turno** — no al cerrar el turno. Avanzarlo al cierre le
entregaría al turno siguiente un rango vacío y los fixes del loop no los revisaría nadie, que es
justo el modo de falla que esta decisión evita (59 de 235 reportes de turno atribuían sus hallazgos
a los fixes del turno anterior). El
**slice** completo se mira **una sola vez**, al cierre, en un **pase de coherencia** de solo lectura
que no ejecuta nada.

Dos elecciones concretas dentro de esa decisión:

1. **El marcador se fija con `git stash create`.** Verificado en repos temporales: no crea un commit,
   no cambia de rama, no toca el árbol de trabajo, e incluye los cambios sin commitear en el punto de
   corte. El diff contra el marcador trae exactamente lo nuevo.
2. **El pase de coherencia no ejecuta nada.** Lo ejecutable ya se verificó por delta, turno a turno.
   Mirar el slice como unidad es una lectura contra la intención declarada, no una segunda corrida
   completa.

## Alternativas descartadas

**Revisar el slice entero en cada turno (el statu quo).** Es lo más simple de explicar y lo que hacía
el ciclo hasta ahora. Descartada por los números: es literalmente el desperdicio medido (540 minutos
sobre un mismo rango). Cada turno vuelve a pagar los cinco focos y, con el rediseño, también pagaría
la mutación acotada, sobre código que ya pasó la revisión.

**Marcar el avance con un commit por turno.** Habría dado un marcador trivial (`HEAD`) y sin
mecánica nueva. Descartada porque el usuario tiene una preferencia explícita y sostenida de no
commitear sin pedirlo: un ciclo que commitea por su cuenta le ensucia la historia y le quita el
control del cierre de slice. `git stash create` da el mismo punto de corte sin ninguno de esos
efectos.

**Revisar solo por delta, sin pase de coherencia.** Es la variante más barata. Descartada porque
revisar por partes deja pasar el defecto que solo se ve en el conjunto: un slice cuyas piezas están
todas bien pero que no cierra como unidad contra su intención. El costo de una lectura de solo
lectura al final es chico comparado con lo que evita.

**Bajar el techo de turnos de 5 a 2.** Propuesta y rechazada con los datos: 59 de 235 reportes de
turno encuentran regresiones introducidas por el turno anterior. Cortar en 2 entrega los fixes del
turno 2 sin revisar. Con re-reviews angostos un turno cuesta ~6 minutos, así que el techo solo acota
la cola: el ahorro no justifica el riesgo.

**Eliminar el pase de confianza.** Propuesta y rechazada con los datos: cuesta el 3% del total (2,0 h
de 67,2) y es el único filtro de falsos positivos del sistema. El usuario fue explícito en no
abaratarlo.

## Consecuencias

**A favor:**

- Ningún cambio se revisa dos veces ni queda sin revisar — es el invariante que el marcador existe
  para sostener.
- El costo de un turno deja de crecer con la profundidad del loop: el turno 2 revisa los fixes del
  turno 1, no el slice entero.
- El slice sigue mirándose como unidad, con un costo acotado y explícito.
- El ciclo funciona sin commitear, que es como el usuario trabaja.

**En contra / riesgos asumidos:**

- **Estado nuevo que puede desincronizarse.** Si el marcador se pierde o queda viejo, el ciclo revisa
  de más (tolerable) o de menos (no tolerable). Mitigación: el marcador arranca en la base del slice
  cuando no existe, así que el modo de falla por default es revisar de más.
- **El objeto de `git stash create` es podable.** Un `git gc` agresivo puede recoger el objeto del
  marcador. Mitigación: el modo de falla vuelve a ser revisar desde la base del slice.
- **Más mecánica que explicar.** El ciclo pasa de "revisá el diff" a un procedimiento con estado. Por
  eso el marcador se implementa como un script con tres verbos y tests propios, en vez de como prosa
  en las instrucciones: el comportamiento queda fijado por tests y no depende de que el agente lo
  reconstruya bien en cada corrida.
- **La decisión se aplica antes de la medición que la juzga.** Riesgo de secuencia declarado y
  aceptado; el Track B congela la línea base de agosto (vence el 10/9/2026) para que la comparación
  siga siendo posible.

## Vocabulario

Esta ADR usa los términos del glosario de `CONTEXT.md`: **slice**, **cierre de slice**, **corrida de
review**, **turno**, **marcador de revisión**, **delta sin revisar**, **reviewer**, **foco**, **pase
de confianza**, **pase de coherencia**, **mutación acotada**, **afirmación**.
