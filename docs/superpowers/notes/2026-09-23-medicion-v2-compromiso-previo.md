# Medición de la v2 — compromiso previo (2026-09-23)

Congelado antes de la primera corrida del A/B y del piloto. Este commit tiene que ser anterior a
cualquier artefacto de corrida; si hay que cambiar este párrafo después de ver datos, el cambio va
en un commit propio que lo diga, no editando este.

## Sujeto medido

El tag **`v2.1.0`** contra el scaffold **`2026-09-11`**, que es lo que tienen hoy los repos
bootstrapeados. El scaffold `2026-09-11` quedó sellado en el commit **`f7ae28f`**, en las tres
variantes. Los sufijos de sus manifests (`2026-09-11+567c77a` personal, `+441e753` southpoint,
`+1f9f297` ai) no son commits de este repo. La variante medida es **personal**.

## El compromiso

**Si el resultado de tarea empeora, el rollout se frena hasta entender por qué. Si queda igual y el
contexto sube, se revisa qué entró que no se pagó solo.**

**Qué es "empeora"**: el `pass_rate` medio de un brazo v2 (`v2-serie` o `v2-olas`) queda por
debajo del de `v1-serie` por más de un desvío estándar de `v1-serie`, con la media y el desvío que
reporta el harness. Si el desvío de `v1-serie` es cero, cualquier caída cuenta. Cada brazo v2 se
juzga por separado: basta con uno para frenar.

**Qué es "queda igual"**: la media del brazo v2 cae dentro de un desvío de `v1-serie`, para
arriba o para abajo. Si mejora por más de un desvío, la segunda rama no se dispara para ese brazo.

## Lo que ya se sabe antes de correr

El contexto sube. Medido con `tools/context-metric.ps1 -Ref <ref>` (variante personal, en code
points):

| Ref | CLAUDE.md | Comandos | Agents | Total |
|---|---|---|---|---|
| `f7ae28f` (scaffold `2026-09-11`) | 7.724 | 2.121 | 0 | **9.845** |
| `v2.1.0` | 7.556 | 9.217 | 599 | **17.372** |

Así que la segunda rama del compromiso ya está armada: si el resultado de tarea queda igual, la
revisión de qué no se pagó solo no es opcional.
