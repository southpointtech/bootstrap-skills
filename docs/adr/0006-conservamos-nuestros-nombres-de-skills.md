# ADR-0006 — Conservamos nuestros nombres de skills frente a los renames de upstream

- **Estado**: aceptada
- **Fecha**: 2026-08-28
- **Contexto de la decisión**: grill de la próxima versión del bootstrap (2026-08-28).

## Contexto

Upstream renombró dos de las skills que usamos: `to-prd` pasó a `to-spec`, y `to-issues` se fusionó con
`to-plan` en `to-tickets`. Adoptar los cuerpos nuevos obliga a decidir qué pasa con los nombres.

Los nombres viejos no son solo nombres de archivo: `/to-prd` y `/to-issues` están escritos como pasos
del flujo en el `CLAUDE.md` del scaffold, y por lo tanto en el `CLAUDE.md` de cada proyecto ya
bootstrapeado. "PRD" además es vocabulario del flujo de 8 pasos, no una etiqueta interna.

## Decisión

Las skills conservan **nuestros** nombres — `to-prd` y `to-issues` — con el contenido nuevo de
`to-spec` y `to-tickets` adentro. El lockfile registra el mapeo al path de upstream, para que el
próximo merge sepa contra qué comparar.

## Alternativas descartadas

**Adoptar `to-spec` y `to-tickets`.** Alineación total y diffs futuros triviales. Descartada porque
obliga a editar el `CLAUDE.md` de cada proyecto bootstrapeado en el mismo movimiento, y porque borra
"PRD" del vocabulario del flujo, que es un término con el que ya se habla.

**Mantener las dos: skills con nombre nuevo y punteros con el viejo.** Nadie pierde el comando y el
repo queda alineado con upstream. Descartada por inflar el listado de skills con cuatro entradas para
dos capacidades, en un set que ya crece de 11 a 20.

## Consecuencias

- **Un lector futuro va a ver atraso donde hay decisión.** Sin este registro, la próxima sesión que
  compare el set contra upstream va a leer `to-prd` como desactualizado y "corregirlo", rompiendo el
  `CLAUDE.md` de todos los proyectos. Ese es el motivo principal de este ADR.
- **El mapeo nombre-nuestro → path-upstream tiene que vivir en el lockfile** (ver ADR-0005) o el merge
  de tres vías compara contra el archivo equivocado — o contra ninguno, si busca por el nombre viejo en
  un upstream donde ya no existe.
- La misma regla aplica a `zoom-out`, que upstream eliminó: se conserva marcada como **fork propio**.
