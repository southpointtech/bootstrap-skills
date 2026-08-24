# ADR-0002 — Limpieza del ancla del pase de coherencia (`slice-open`) solo en el cierre limpio

- **Estado**: aceptada
- **Fecha**: 2026-08-23
- **Contexto de la decisión**: grill de A4c (`.scratch/review-cost-redesign/issues/04c-limpieza-del-slice-open-al-cierre.md`, fuera de git — `.scratch/` está gitignoreado, así que lo que hay que saber está acá)
- **Extiende**: ADR-0001 (`0001-review-incremental-con-marcador.md`), que introdujo el marcador y el ancla `slice-open` del pase de coherencia.

## Contexto

ADR-0001 fijó que el slice completo se mira una vez, al cierre, en un pase de coherencia anclado en
el arranque del slice. En una rama con slices apilados ese arranque no es la base de la rama, así que
A4b lo persiste en la clave `slice-open:<branch>`: el verbo `-Action open` la escribe en el primer
turno del loop (el marcador tal como quedó al cerrar el slice anterior), y `-Action slice-base` la lee.

El review-loop de A4b destapó un hueco (hallazgo B, Medium, confianza 62): `open` escribía
`slice-open` **incondicionalmente** y **ningún verbo la borraba**. Si el loop agota el cap de 5 turnos
**sin cerrar limpio** y alguien **re-corre `/review-loop` sobre el mismo slice sin cerrar**, el `open`
de la re-corrida re-snapshotea el marcador **ya avanzado** por la corrida anterior → `slice-open`
apunta más adelante que el arranque real del slice → la coherencia ancla más tarde y lee **menos** que
el slice. Es la dirección **under-scope**, la que ADR-0001 declara peligrosa (a diferencia del
over-scope, que es la segura).

El caso está fuertemente acotado (nunca dispara en el flujo normal un-loop-por-slice; la coherencia a
scope completo ya corre en el primer cap-close antes de cualquier re-corrida; re-correr un slice sin
cerrar es off-workflow), pero el fix correcto es mecanismo nuevo, no parche de anclaje, así que se
trató como slice propio (A4c) en vez de meterlo a mitad de A4b.

## Decisión

Se limpia el ancla con un verbo nuevo, y se hace `open` idempotente dentro de un mismo slice:

1. **`-Action close`** (nuevo, hace par con `open`): borra `slice-open:<branch>` del estado.
   Idempotente (no-op si no está). **No necesita la cuarentena `.bad` de `advance`**: un estado
   ilegible lo devuelve `Read-State` como `@{}`, así que `close` no encuentra la clave y sale sin
   escribir, dejando el archivo intacto y recuperable (`advance` sí la necesita porque escribe el
   marcador incondicionalmente). En el camino normal sale **0**; no poder borrar deja el ancla vieja,
   que a lo sumo over-scopea — la dirección segura.
2. **`open` pasa a write-once, sobre la PRESENCIA de la clave, no sobre si resuelve**: escribe
   `slice-open` **solo si está sin fijar**. Si ya está fijado — resuelva o no — **no-op**. Dejar
   intacta incluso un ancla stale (que un rebase o `gc` dejó sin resolver) es deliberado: reemplazarla
   con el marcador actual, que en una re-corrida ya avanzó más allá del arranque del slice,
   **under-scopearía**; dejarla hace que `slice-base` caiga a la base de rama (over-scope, seguro).
   Así el ancla nunca se mueve hacia adelante dentro del mismo slice, que es la causa raíz del
   under-scope.
3. **`/review-loop` llama `-Action close` únicamente en el cierre LIMPIO** (cero hallazgos
   medium/high), **después** del pase de coherencia — que lee `slice-open` vía `slice-base` —, y
   **nunca en el cierre por cap**.

El punto no obvio es el 3: **borrar solo en limpio, no en cap.** Un cierre por cap significa "el slice
no terminó, quizá se re-corra"; conservar `slice-open` ahí hace que la re-corrida (con `open`
write-once) siga anclando en el arranque real. Un cierre limpio significa "el slice terminó de verdad";
recién ahí se borra el ancla para que el `open` del slice siguiente escriba fresco.

### Mapeo a los criterios de aceptación de A4c

- *Re-correr `/review-loop` sobre un slice sin cerrar no mueve `slice-open` hacia adelante*: el cap no
  borra + `open` write-once ⇒ la re-corrida es no-op sobre el ancla. ✓
- *Un slice nuevo tras cierre real sí re-snapshotea*: el cierre limpio borra ⇒ el `open` siguiente ve
  el ancla vacía y escribe. ✓
- *El primer slice de una rama cae a la base de rama*: `slice-open` vacío ⇒ `slice-base` cae a
  `Get-SliceBase`. ✓
- *`-Action base` sin cambios; `slice-base` sigue siendo superset estricto de `base`*: A4c no toca
  esos caminos. ✓

## Alternativas descartadas

**Guard por ancestría en `open` (sin verbo nuevo).** Re-snapshotear solo si el marcador actual es
ancestro-o-igual al `slice-open` guardado. Descartada: en la re-corrida de un slice sin cerrar y en un
slice nuevo el marcador es, en **ambos** casos, descendiente estricto del `slice-open` guardado (avanzó
turno a turno en un caso, cruzó el cierre en el otro). La ancestría no distingue los dos casos, así que
el guard o bien bloquea el movimiento legítimo del slice nuevo (rompe el flujo apilado) o bien permite
el movimiento ilegítimo de la re-corrida (no arregla nada). Hace falta el evento de cierre, que es
justo lo que aporta el verbo `close`.

**Borrar `slice-open` en ambos cierres (limpio y cap).** Más simple de explicar. Descartada porque
reabre el under-scope: tras un cap-close el ancla quedaría borrada y la re-corrida manual del mismo
slice re-snapshotearía el marcador ya avanzado — exactamente el bug que A4c existe para tapar.

**Aceptarlo como límite documentado (no arreglarlo).** Es lo que A4b hizo interinamente. Descartada
por decisión del usuario (2026-08-20): se arregla en su propio slice, no se documenta como límite
aceptado, porque el modo de falla es under-scope (revisar de menos), el único intolerable.

## Consecuencias

**A favor:**

- Se elimina el único camino conocido a under-scope del pase de coherencia.
- El flujo normal un-loop-por-slice queda sin over-scope: cada cierre limpio borra el ancla antes del
  slice siguiente.
- El mecanismo es trigger-independiente: `close` lo llama el loop (que sabe si cerró limpio), no el
  hook (que dispara también por push y por la red de 400 líneas).

**En contra / riesgos asumidos:**

- **Over-scope residual en slices abandonados al cap.** Si un slice se abandona en el cap (nunca llega
  a limpio) y se arranca el siguiente sin cerrarlo, `slice-open` queda viejo y el slice siguiente
  over-scopea (revisa el abandonado + el nuevo). Es raro, off-normal y **siempre en la dirección
  segura** (nunca under-scopea). Se acepta a cambio de matar el under-scope.
- **Un verbo más que explicar.** El marcador pasa de seis a siete verbos (`advance`, `range`, `base`,
  `open`, `slice-base`, `get`, `close`). El comportamiento queda fijado por tests, como el resto.

## Vocabulario

Usa los términos del glosario de `CONTEXT.md`: **slice**, **cierre de slice**, **corrida de review**,
**turno**, **marcador de revisión**, **pase de coherencia**, **delta sin revisar**. Suma un matiz al
**cierre de slice**: el loop distingue **cierre limpio** (cero hallazgos medium/high) de **cierre por
cap** (5 turnos), y solo el primero limpia el ancla `slice-open`.
