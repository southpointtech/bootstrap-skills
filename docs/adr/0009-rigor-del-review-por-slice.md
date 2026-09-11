# ADR 0009 — El rigor del review se declara por slice, con techo de 2 turnos

Status: accepted
Fecha: 2026-09-11

## Contexto

Los tres slices de `review-cost --split` en `claude-analytics` (01a, 01b, 01c) cerraron su review-loop
por el techo de 5 turnos, ninguno limpio. Medido el 2026-09-11 sobre `8a39ab9..0ca4551`: 14 de los 19
commits eran fixes de review, y de las 1.666 líneas agregadas en `src/`, 900 eran comentarios.

El mecanismo estaba documentado desde el 2026-09-04 en un parche operativo fuera del repo: el pase de
confianza clasificaba Medium todo lo que "viola una regla del proyecto", la regla de afirmaciones del
`CLAUDE.md` es una regla del proyecto, y entonces una frase floja en un comentario nacía Medium. Su fix
era prosa nueva, el marcador se la entregaba al turno siguiente, y el cierre limpio (cero Medium/High)
quedaba fuera de alcance. Además, el mismo rigor se aplicaba a una herramienta local de un solo usuario
que al código de un cliente en producción.

El techo de 5 turnos venía de la skill original, y ADR-0001 lo reafirmó: rechazó bajarlo a 2 porque "59
de 235 reportes de turno encuentran regresiones introducidas por el turno anterior", y cortar en 2
"entrega los fixes del turno 2 sin revisar". Esa evidencia sigue en pie. Esta decisión la acepta a
sabiendas: el usuario eligió el techo de 2 el 2026-09-11, con el rechazo de ADR-0001 a la vista.

## Decisión

1. **Techo de 2 turnos** para el rigor `standard`: el turno 1 con todos los focos, y el turno 2 revisa
   sólo los fixes.
2. **Rigor por slice**, declarado por el agente con el trailer `Review-Rigor: light` junto al
   `Slice-Close:`. `light` es un turno con los focos de Bugs y Tests, sin mutación, sin `/code-review` y
   sin pase de coherencia. Sólo un High bloquea y sólo un High se arregla: los Medium de un slice
   `light` se reportan sin arreglar, porque ningún turno revisaría su fix. Un High promueve el slice a
   `standard`. El rigor se decide una vez, en el turno 1: es `light` sólo si al menos un commit del rango
   lleva `Slice-Close:` y todos los que lo llevan declaran `Review-Rigor: light`; si no, `standard`.
3. **La prosa es Low** en el pase de confianza, cualquiera sea la regla que viola, salvo que el texto lo
   lea un usuario final o contradiga el código de un modo que engañe a quien lo modifique después. Las
   instrucciones de los archivos que gobiernan al agente (`CLAUDE.md`, `.claude/`, `.agents/`,
   `docs/ai-workflow/`, `docs/agents/`) no son prosa: una frase que le dice al agente qué hacer se
   clasifica como código.
4. **El loop arregla sólo Medium y High.** No re-edita prosa escrita por un turno anterior del mismo loop
   salvo por un hallazgo Medium o High, y cierra sin otro turno si el delta sin revisar es sólo prosa
   fuera de los archivos que gobiernan al agente.
5. **Todo cierre que no sea por cap limpia el ancla `slice-open`**: el limpio y el cierre por prosa.
   Amplía la decisión 3 de ADR-0002, que sólo la limpiaba en el limpio.

Esto incorpora al bootstrap las reglas 1 a 3 del parche `PARCHE-review-loop-prosa.md`. La regla 4 (cómo
escribir prosa para no generar hallazgos) queda afuera, y el parche sigue haciendo falta en cada repo
hasta que corra `upgrade-bootstrap`.

## Consecuencias

- Los fixes del turno 2 de un slice `standard` no los revisa ningún turno: sólo los relee el pase de
  coherencia, que es de solo lectura, corre en el modelo más liviano y no ejecuta nada. Es el riesgo que
  ADR-0001 había rechazado, aceptado ahora.
- Un slice puede cerrar con hallazgos Low abiertos, y un slice `light` con Medium abiertos; el reporte
  final los lista.
- Un slice `light` recibe menos cobertura. El criterio para declararlo está en el `CLAUDE.md`, y ante la
  duda se usa `standard`.
- Reemplaza el techo de 5 turnos que ADR-0001 reafirmó y amplía la decisión 3 de ADR-0002; el resto de
  ADR-0002 sigue vigente.
- Falta medirlo: la señal a mirar son los próximos slices, cuántos cierran limpios y no por techo.
