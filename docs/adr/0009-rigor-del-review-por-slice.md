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

## Decisión

1. **Techo de 2 turnos** para el rigor `standard`: el turno 1 con todos los focos, y el turno 2 revisa
   sólo los fixes.
2. **Rigor por slice**, declarado por el agente con el trailer `Review-Rigor: light` junto al
   `Slice-Close:`. `light` es un turno con los focos de Bugs y Tests, sin mutación, sin `/code-review` y
   sin pase de coherencia; sólo un High bloquea. Sin trailer, el slice va `standard`. Un High en un
   slice `light` lo promueve a `standard`, para que ningún fix de un High salga sin revisar.
3. **La prosa es Low** en el pase de confianza, cualquiera sea la regla que viola, salvo que el texto lo
   lea un usuario final o contradiga el código de un modo que engañe a quien lo modifique después.
4. **El loop arregla sólo Medium y High**, no re-edita prosa escrita por un turno anterior del mismo
   loop, y cierra sin otro turno si el delta sin revisar es sólo prosa.

Esto incorpora al bootstrap las reglas 1 a 3 del parche `PARCHE-review-loop-prosa.md`, que deja de
hacer falta.

## Consecuencias

- Un slice puede cerrar con hallazgos Low abiertos; el reporte final los lista.
- Un slice `light` recibe menos cobertura. El criterio para declararlo está en el `CLAUDE.md`, y ante la
  duda se usa `standard`.
- El techo de 5 turnos de ADR-0002 queda reemplazado; el resto de ADR-0002 (sólo el cierre limpio limpia
  el ancla `slice-open`) sigue vigente.
- Falta medirlo: la señal a mirar son los próximos slices, cuántos cierran limpios y no por techo.
