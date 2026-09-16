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

La regla se escribió el 2026-09-06 como parche local (bloque `PATCH:prose-churn`) en los repos donde dolía;
su doc de respaldo vive fuera de este repo (`~/.claude/PARCHE-review-loop-prosa.md`, y una copia marcada
REVERTIDO en `docs/agents/parche-review-loop-prosa.md` de Administracion May). ADR-0009 subió al scaffold las reglas de prosa de ese parche, pero no ésta. Al
revertir el parche durante el rollout del 2026-09-15 —como el propio parche indica— la regla se perdió en
los repos que la tenían, y el canónico nunca la tuvo.

## Decisión

El scorer del pase de confianza responde **tres preguntas** y las declara en su veredicto:

1. **¿El hecho afirmado es cierto?** Se verifica **corriendo un comando read-only** contra el código
   real, no leyendo.
2. **¿El arreglo propuesto se sostiene?** El *reemplazo* se chequea igual que el hecho: quien corrige una
   frase falsa propone rutinariamente otra frase falsa.
3. **¿Arreglar este caso aislado es consistente con el resto del archivo?** Tocar 1 de N ocurrencias
   idénticas implica que las otras N-1 fueron auditadas; si no lo fueron, el arreglo engaña.

Una pregunta que **no aplica** no es un fallo: sólo cuenta un fallo afirmativo. Y lo que (2) y (3) deciden
es la suerte de la **sugerencia**, no la del hallazgo, así que se aplican **después** de clasificar:

- un hallazgo **Low** que falla (2) o (3) se **descarta**, por certero que sea (1): toda su sustancia es
  la sugerencia, y rechazada la sugerencia no queda nada que reportar;
- un hallazgo **Medium o High** queda en el reporte con su arreglo marcado **REJECTED** y el motivo del
  scorer. Conserva su severidad, bloquea el cierre igual que con un arreglo sano, y el Step 6 lo declara
  uno por uno. El `/review-loop` lo sabe: un hallazgo con la sugerencia rechazada es real, y un rango
  vacío por no haberlo arreglado es cierre por techo o bloqueado, nunca limpio.

El **número 0-100 contesta (1) sola**: (2) y (3) vuelven como veredictos aparte y no se le restan. Si se
le restaran, el hallazgo moriría en el corte de 60 antes de clasificarse — que es justo el agujero que
esta decisión cierra.

El corte de 60 no cambia: cambia qué se puntúa. Esta separación es lo que el turno 1 del review-loop de
este mismo slice corrigió: la versión que se commiteó primero descartaba el hallazgo entero, y tres
reviewers independientes mostraron que un High certero con una sugerencia floja desaparecía del reporte y
el loop cerraba **limpio** sobre él.

Además, el scorer recibe por escrito el contra-argumento de alcance: *"¿esto es un defecto DEL delta, o
una condición preexistente que el delta simplemente iluminó?"* — lo segundo queda fuera de alcance.

La pregunta (1) exige un comando **read-only** (un grep, una lectura de archivo, una lectura de `git`);
read-only es literal: una suite que escribe archivos no es read-only. La regla viaja verbatim a cada
proyecto que el scaffold bootstrapea, así que no afirma nada sobre la suite de ninguno en particular. Y el dispatch del scorer lleva la
prohibición de escritura del Step 3, como ya hacía el foco de coherencia: la pregunta (1) convierte a los
scorers paralelos en agentes que ejecutan, y sin esa guarda mutarían el árbol que los demás leen.

La regla entra al canónico **sin los marcadores del parche**: no es un override temporal.

## Consecuencias

- Se descartan hallazgos **Low** ciertos cuyo arreglo no se sostiene. Un Medium o High no se descarta: se
  reporta con la sugerencia marcada REJECTED, y el Step 6 declara cuáles lo llevan, así que un defecto real
  nunca sale del reporte por culpa de una sugerencia mala.
- Un Medium o High con la sugerencia rechazada sigue bloqueando el cierre, así que un slice puede cerrar
  por techo en vez de limpio. Un cierre por techo es cierto; un cierre limpio sobre un High vivo, no.
- El pase de confianza hace más trabajo por hallazgo: la pregunta (1) exige correr un comando, no leer.
  Corre en el modelo más capaz, que es donde ya estaba el costo.
- El parche local queda cubierto por el canónico en este punto; los repos que lo revirtieron recuperan la
  regla vía `upgrade-bootstrap`.
- Falta medirlo: la señal a mirar es cuántos hallazgos se descartan por (2) o (3) en los próximos slices,
  y si alguno de esos defectos vuelve a aparecer después.
- La mecánica del bloque queda congelada por un **golden por hash** (`tests/fixtures/step5-score-the-fix.golden.sha256`,
  resellable con `tools/reseal-step5.ps1`). En el turno 2 se midió que los asserts semánticos muerden lo que
  edita o borra una oración y son ciegos a lo que **agrega**: una cláusula de excepción al final desarma la
  regla con la suite en verde. El golden no impide reescribir el bloque; lo hace visible.
