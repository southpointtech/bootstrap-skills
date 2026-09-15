# ADR 0010 — El pase de confianza puntúa el arreglo, no sólo el hallazgo

Status: accepted
Fecha: 2026-09-15

## Contexto

El pase de confianza (Step 5 de `/slice-review`) puntuaba una sola cosa: si el hallazgo era cierto. El
arreglo que el reviewer proponía viajaba junto al hallazgo y entraba al reporte sin que nadie lo
puntuara, y el loop lo aplicaba.

Eso se midió dos veces:

- **2026-09-05**: tres hallazgos con puntaje alto (92, 92, 80) cuyo arreglo propuesto igual habría
  empeorado el código.
- **2026-09-10**: dos veces en que el arreglo que proponían los reviewers movía el problema de lugar en
  vez de resolverlo; uno invertía el caso emblemático del propio hallazgo. Las dos las atajó pedirle al
  scorer que puntuara el arreglo.

La convergencia de varios focos sobre un mismo hallazgo valida el **hallazgo**, no el **arreglo**: los
focos se solapan en lo que miran, no en lo que proponen.

La regla se escribió el 2026-09-06 como parche local (`PATCH:prose-churn`, `docs/agents/parche-review-loop-prosa.md`)
en los repos donde dolía. ADR-0009 subió al scaffold las reglas de prosa de ese parche, pero no ésta. Al
revertir el parche durante el rollout del 2026-09-15 —como el propio parche indica— la regla se perdió en
los repos que la tenían, y el canónico nunca la tuvo.

## Decisión

El scorer del pase de confianza responde **tres preguntas** y las declara en su veredicto:

1. **¿El hecho afirmado es cierto?** Se verifica **corriendo un comando** contra el código real, no
   leyendo.
2. **¿El arreglo propuesto se sostiene?** El *reemplazo* se chequea igual que el hecho: quien corrige una
   frase falsa propone rutinariamente otra frase falsa.
3. **¿Arreglar este caso aislado es consistente con el resto del archivo?** Tocar 1 de N ocurrencias
   idénticas implica que las otras N-1 fueron auditadas; si no lo fueron, el arreglo engaña.

Un hallazgo que falla (2) o (3) se puntúa **bajo 60 y se descarta**, por certero que sea (1). El corte de
60 no cambia: cambia qué se puntúa.

Además, el scorer recibe por escrito el contra-argumento de alcance: *"¿esto es un defecto DEL delta, o
una condición preexistente que el delta simplemente iluminó?"* — lo segundo queda fuera de alcance.

La regla entra al canónico **sin los marcadores del parche**: no es un override temporal.

## Consecuencias

- Se descartan hallazgos ciertos cuyo arreglo no se sostiene. El reporte los cuenta entre los descartados
  por confianza, así que el silencio sigue siendo legible, pero el defecto que señalaban queda sin
  reportar hasta que alguien proponga un arreglo que pase (2) y (3).
- El pase de confianza hace más trabajo por hallazgo: la pregunta (1) exige correr un comando, no leer.
  Corre en el modelo más capaz, que es donde ya estaba el costo.
- El parche local queda cubierto por el canónico en este punto; los repos que lo revirtieron recuperan la
  regla vía `upgrade-bootstrap`.
- Falta medirlo: la señal a mirar es cuántos hallazgos se descartan por (2) o (3) en los próximos slices,
  y si alguno de esos defectos vuelve a aparecer después.
