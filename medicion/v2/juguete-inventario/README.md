# Juguete de inventario — el sujeto del A/B de la v2

Issue `03` de la medición de la v2 (`.scratch/medicion-v2/`, gitignored). Es el proyecto que los tres
brazos del A/B (`v1-serie`, `v2-serie`, `v2-olas`) desarrollan entero. Vive fuera de la suite y fuera
del scaffold: nada de acá corre en `tests/run-all.ps1` ni se copia a un proyecto bootstrapeado.

**Este README es para el que mide, no para el agente.** Nombra las fricciones sembradas; el agente
recibe solo lo que lista `files` en `evals/evals.json`.

## Qué hay

| Archivo | Para quién | Qué es |
|---|---|---|
| `enunciado.md` | el agente | el pedido del cliente: seis comandos de un CLI `inv` en Python |
| `datos/*.csv` | el agente | el catálogo y los movimientos, con un error sembrado |
| `cliente/respuestas.md` | el harness | lo que contesta el cliente simulado y cuándo |
| `evals/evals.json` | el harness | definiciones, ruteo del cliente, prompt, 16 expectations y la salida `esperado` |
| `oraculo.py` | el que mide | calcula `esperado`; `--verificar` y `--discriminar` custodian los datos |

`esperado` sale del oráculo, no se escribe a mano. Si se tocan los datos o el pedido, se regenera y
tienen que dar `ok` los dos chequeos: `--verificar` (el `esperado` congelado es el del oráculo) y
`--discriminar` (cada interpretación equivocada de abajo sigue dando otra salida que la correcta).

## Los seis slices

`productos`, `stock`, `alta`, `exportar`, `rotacion`, `alertas`. Los cuatro primeros no dependen
funcionalmente entre sí y forman la primera ola; `rotacion` y `alertas` necesitan el stock, así que
van en la segunda. Los cuatro de la primera ola sí **comparten código**: el lector de
`productos.csv` (`stock` lo usa para rechazar un SKU desconocido y `alta` para rechazar uno repetido)
y el esqueleto del CLI (`python -m inv`, `--datos`). En `v2-olas` eso choca al integrar, y ese choque
es parte de la cola de integración que se mide; ninguna expectation puntúa si el lector del catálogo
quedó duplicado.

## Las tres fricciones

1. **Requerimiento ambiguo.** El pedido dice "avisar cuando el stock esté bajo" y no define "bajo".
   El cliente simulado lo define (sección A) solo si la pregunta coincide con `ruteo.A`: estrictamente
   menor que el punto de reorden, y sin punto de reorden no alerta. Con los datos, `<` da `CLA-004` y
   `TAR-005`; `<=` suma `TUE-002` (stock 40, punto 40); un umbral fijo de 10 da `ARA-003` y
   `BRO-006`. → **E07** (el resultado) y **E08** (preguntó antes de implementar). E07 no separa
   preguntar de adivinar: la columna `punto_reorden` sugiere `<`, y quien adivine `<` pasa E07. Lo
   que atribuye la fricción es E08.
2. **Dependencia real.** `rotacion` necesita el modelo de movimientos de `stock`. → **E10** (`stock`
   ya funcionaba en un ancestro estricto del commit que hace andar `rotacion`) y **E09** (con una
   salida negativa más de `CLA-004`, `stock` y `rotacion` la tratan igual, que es lo que pasa si
   comparten el modelo).
3. **Bug en los datos que destapa un test.** La línea 12 de `movimientos.csv` es una salida de
   `TOR-001` con cantidad `-15`. El pedido no dice qué hacer con una fila así: solo da el ejemplo
   `stock TOR-001` → `120`. Un test escrito desde ese ejemplo falla contra la implementación natural
   (restar la cantidad tal cual da 135; tomar el valor absoluto, 105) y obliga a investigar; si el
   agente pregunta, el cliente (sección C) dice que la fila está mal cargada y no se cuenta. →
   **E02** (el resultado) y **E12** (un test falló por el valor, no por un import).

**E03** y **E06** también dependen de la fricción 3: sin descartar la fila, `stock TOR-001` y la
rotación de `TOR-001` (65 tal cual, 95 con valor absoluto, contra 80) salen mal. E06 además mide el
rango de fechas: con el inicio exclusivo `CLA-004` da 70 y con el fin exclusivo 50, contra 80; y el
empate `CLA-004`/`TOR-001` en 80 mide el desempate por SKU.

Estas interpretaciones equivocadas están implementadas en `oraculo.py`
(`interpretaciones_equivocadas`) y `--discriminar` falla si alguna da lo mismo que la correcta. Se
probó rompiendo los datos en una copia: con el punto de reorden de `TUE-002` en 41, sin la fila
`-15`, o sin la salida de `CLA-004` del 2026-08-01, sale 1 y nombra la interpretación que dejó de
discriminar.

## Las expectations

Las 16 miran el artefacto (el árbol, la historia de git, el transcript, la bitácora del harness),
nunca que un hook haya corrido. Los términos que usan (archivo de test, "implementa X", rango de un
`Slice-Close:`, cómo se compara la salida) están en `definiciones` de `evals.json`. E01-E07 son el
resultado funcional; E08-E10 y E12, las fricciones; E11 y E13-E16, el proceso: suite verde, RED por
comando, al menos 4 cierres de slice, techo de ~400 líneas de lógica por slice, e issues cerrados.

**E15 casi no discrimina:** `oraculo.py` calcula la salida de cinco de los seis comandos (todos menos
`alta`) en 135 líneas, con las interpretaciones equivocadas incluidas. Es una estimación, no una
medición sobre un proyecto hecho por un agente, pero sugiere que uno hecho en un solo slice también
queda bajo el techo. Queda porque el PRD lo
pide; el tamaño real de los slices se reporta en `metricas_no_puntuadas`.

**Asimetría conocida en E16:** la v2 trae `marcar-done.ps1`, que pone `Status: done` al cerrar el
slice; `f7ae28f` no lo trae, y en `v1-serie` el agente lo tiene que hacer a mano. E16 mide también
esa automatización, no solo la disciplina.

## Lo que le toca al harness (issue `04`)

- Materializar el scaffold de cada brazo y copiarle `enunciado.md` y `datos/`.
- La ronda de preguntas: cuando un turno termina con `PREGUNTAS.md`, rutear la respuesta según
  `cliente/respuestas.md` y `ruteo`, registrar la ronda en la bitácora (hora, copia, secciones
  entregadas), borrar el archivo y relanzar.
- Conservar el transcript de cada sesión.
- Para "implementa X", correr la expectation funcional de cada comando en cada commit de la historia.
- En `v2-olas`, E16 lee también la copia de `.scratch/` de cada worktree de carril: `.scratch/` está
  gitignored, así que el `Status: done` que se escribe en un carril no llega al checkout principal
  con el merge.
- Leer la salida en modo texto (`\r\n` → `\n`): en Windows, `print` escribe `\r\n` a un pipe.
- Escribir `grading.json` con el formato de skill-creator.
