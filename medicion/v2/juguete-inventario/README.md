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

**Las expectations son la intención, no el calificador.** Escritas en prosa, no alcanzan para
calificar sin interpretar: dos turnos de review sobre su texto encontraron 11 y ~9 agujeros, y cada
arreglo en prosa abrió uno nuevo. Por eso se congelaron así y la calificación se escribe como código
(`calificar.py`, issue `04b`), testeado contra repos de fixture, uno correcto y uno equivocado por
expectation. Si el código y la prosa discrepan, manda el código, y la prosa se corrige después. Los
agujeros que quedaron abiertos y que `calificar.py` tiene que cerrar con un test:

1. E09 rechaza la lectura coherente con valor absoluto, y dos lectores separados que descartan la
   fila `-15` también pasan: no mide el modelo compartido.
2. `ruteo.A` dispara con "alertas" (el nombre del comando) y con "baja" ("dar de baja"); `ruteo.C`
   entrega la regla de la fila ante "¿el stock puede quedar negativo?".
3. E12 pasa con un stub que devuelve 0: tiene que exigir que la falla sea por 135 o 105.
4. E10 falla una corrida correcta si el mismo commit hace andar `stock` y `rotacion`.
5. Una corrida que arregla el dato (borra la fila en su copia) en vez del código se califica
   contra `datos/` originales.
6. E04 exige `exportar` (acopla `alta` a otro slice de la misma ola) y compara JSON como texto exacto.
7. "El transcript" es uno solo, pero en `v2-olas` y con subagentes los pytest corren en otros JSONL.
8. E13 no se puede calificar desde la salida de `pytest -q`, y la regex de "test que invoca X"
   matchea `productos.csv`.
9. E16: el scaffold (`PARALELISMO.md`) borra los worktrees de carril antes de que el harness los mire.

Estado de cada agujero en `calificar.py` (la prosa de `evals.json` sigue igual, a propósito):

| # | Estado | Cómo |
|---|---|---|
| 1 | cerrado (04b slice 2) | decidido 2026-09-24: E09 mide coherencia, no modelo compartido. Pasa con cualquiera de los tres pares de `esperado` (descartar la fila, tal cual, valor absoluto) y falla si `stock` y `rotacion` la leen distinto. No distingue dos lectores separados con la misma regla de un modelo compartido |
| 2 | abierto, del harness | el `ruteo` lo aplica el aparato (`04a`), no `calificar.py` |
| 3 | abierto (04b slice 3) | E12 lee transcripts: queda `passed: null` en `no_calificadas` |
| 4 | cerrado (04b slice 2) | decidido 2026-09-24: E10 no puntúa. Queda `passed: null` en `summary.no_puntuadas`, y el orden en que empezaron a andar `stock` y `rotacion` (commits y relación: `mismo_commit`, `stock_antes`, `rotacion_antes`, `sin_relacion` o `falta_alguno`) va en `metricas_no_puntuadas.orden_stock_rotacion` |
| 5 | cerrado (04b slice 1) | E01-E07, E09 e "implementa X" corren sobre una copia fresca de `datos/` del juguete |
| 6 | cerrado (04b slice 1) | E04 mira el efecto de `alta` en `productos.csv`; E05 compara el JSON como objeto |
| 7 | abierto (04b slice 3) | E12 y E13 leen transcripts |
| 8 | abierto (04b slice 3) | E13 queda `passed: null` en `no_calificadas` |
| 9 | cerrado del lado del calificador (04b slice 2) | E16 lee `proyecto/.scratch/*/issues/*.md` y `copias-de-carriles/*/.scratch/*/issues/*.md` (`medicion/v2/CORRIDA.md`); que esas copias existan depende de que el aparato las guarde |

Lo que `calificar.py` decide y la prosa no dice:

- E11 corre `python -m pytest -q` sobre una copia del árbol final **tal como quedó**, con los datos
  del agente, no con datos frescos: E11 mide que su suite esté verde, y el agujero 5 ya lo cubren E02,
  E03 y E06.
- E14 y E15 leen la historia de `HEAD` del `proyecto/`; un repo sin `.git` o sin commits falla las
  dos. Un commit es un cierre si una línea de su mensaje empieza con `Slice-Close:`, sin sangría.
- E16: un issue es su ruta relativa a `.scratch/`, y cierra si alguna copia tiene una línea que, sin
  los espacios del final, es exactamente `Status: done`.
- E08 compara el `ts` de la ronda como fecha con huso, no como texto, y la ronda tiene que ser
  estrictamente anterior a la fecha de committer del commit que implementa `alertas`.
- Un error del propio calificador (por ejemplo, una línea de `bitacora.jsonl` que no es JSON) deja
  la expectation en `passed: null`, con el id en `summary.errores_del_calificador`, y `main` sale 3.
  El visor de skill-creator muestra `null` como fallada: el `summary` es el que separa los casos.

**E15 casi no discrimina:** `oraculo.py` calcula la salida de cinco de los seis comandos (todos menos
`alta`) en 135 líneas, con las interpretaciones equivocadas incluidas. Es una estimación, no una
medición sobre un proyecto hecho por un agente, pero sugiere que uno hecho en un solo slice también
queda bajo el techo. Queda porque el PRD lo
pide; el tamaño real de los slices se reporta en `metricas_no_puntuadas`.

**Asimetría conocida en E16:** la v2 trae `marcar-done.ps1`, que pone `Status: done` al cerrar el
slice; `f7ae28f` no lo trae, y en `v1-serie` el agente lo tiene que hacer a mano. E16 mide también
esa automatización, no solo la disciplina.

## Lo que le toca al harness (issue `04a`; la calificación es el `04b`)

- Materializar el scaffold de cada brazo y copiarle `enunciado.md` y `datos/`.
- La ronda de preguntas: cuando un turno termina con `PREGUNTAS.md`, rutear la respuesta según
  `cliente/respuestas.md` y `ruteo`, registrar la ronda en la bitácora (hora, copia, secciones
  entregadas), borrar el archivo y relanzar.
- Conservar el transcript de cada sesión.
- En `v2-olas`, guardar la copia de `.scratch/` de cada worktree de carril en
  `copias-de-carriles/<nombre>/.scratch/` antes de que el scaffold borre el worktree (agujero 9): `.scratch/`
  está gitignored, así que el `Status: done` que se escribe en un carril no llega al checkout
  principal con el merge, y E16 lee esas copias.

Lo que antes figuraba acá y ya hace `calificar.py`: correr la expectation funcional de cada comando
en cada commit para "implementa X", leer la salida en modo texto y escribir `grading.json` con el
formato de skill-creator.
