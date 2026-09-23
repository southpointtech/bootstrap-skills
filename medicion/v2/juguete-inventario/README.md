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
| `cliente/respuestas.md` | el harness | lo que contesta el cliente simulado, y la regla para elegir la respuesta |
| `evals/evals.json` | el harness | el prompt, las 16 expectations y la salida `esperado` de cada comando |
| `oraculo.py` | el que mide | calcula `esperado` desde los datos; `--verificar` lo compara con `evals.json` |

`esperado` sale del oráculo, no se escribe a mano. Si se tocan los datos o el pedido, se regenera y
`python oraculo.py --verificar` tiene que dar `ok`.

## Los seis slices

`productos`, `stock`, `alta`, `exportar`, `rotacion`, `alertas`. Los cuatro primeros no dependen
entre sí y forman la primera ola. `rotacion` y `alertas` necesitan el stock y los movimientos, así
que van en la segunda.

## Las tres fricciones

Cada una tiene sus propias expectations, para que un resultado se pueda atribuir.

1. **Requerimiento ambiguo.** El pedido dice "avisar cuando el stock esté bajo" y no define "bajo".
   El cliente simulado solo lo define si el agente lo pregunta (`cliente/respuestas.md`): estrictamente
   menor que el punto de reorden, y sin punto de reorden no alerta. Con los datos, `<` da `CLA-004` y
   `TAR-005`; `<=` suma `TUE-002` (stock 40, punto 40); un umbral fijo menor que 10 da `ARA-003` y
   `BRO-006`, que no tienen punto de reorden. → **E07** (el resultado) y **E08** (preguntó antes de
   implementar).
2. **Dependencia real.** `rotacion` necesita el modelo de movimientos de `stock`, incluido el descarte
   de filas inválidas. → **E09** (un solo módulo lee `movimientos.csv`) y **E10** (`rotacion` se
   construyó sobre ese módulo, no antes).
3. **Bug en los datos que el test primero destapa.** La línea 11 de `movimientos.csv` es una salida de
   `TOR-001` con cantidad `-15`. El pedido dice que la cantidad es siempre positiva y que una fila así
   se avisa y no se aplica, y da el ejemplo `stock TOR-001` → `120`. Un test escrito desde ese ejemplo
   falla contra una implementación ingenua: restar la cantidad tal cual da 135, y tomar el valor
   absoluto da 105. → **E02** (el resultado) y **E12** (hubo RED en `stock`).

**E06** (`rotacion`) mezcla la 2 y la 3: sin el descarte, `TOR-001` sale 65 (tal cual) o 95 (valor
absoluto) en vez de 80, y con la fecha final exclusiva `CLA-004` sale 40 en vez de 70. Para atribuir,
usar E09-E10 y E12.

Los números de esta sección se midieron sobre los datos con un script aparte, que implementa cada
interpretación equivocada. Ese script no quedó commiteado; el que sí está es el oráculo, que calcula
la interpretación correcta.

## Las expectations

Las 16 miran el artefacto (el árbol final, la historia de git, el transcript, la copia de
`PREGUNTAS.md`), nunca que un hook haya corrido. E01-E07 son el resultado funcional; E08-E10 y E12,
las fricciones; E11 y E13-E16, el proceso (suite verde, RED por comando, trailer `Slice-Close:`, techo
de ~400 líneas de lógica, issues cerrados).

**Asimetría conocida en E16:** la v2 trae `marcar-done.ps1`, que pone `Status: done` al cerrar el
slice; `f7ae28f` no lo trae, y en `v1-serie` el agente lo tiene que hacer a mano. E16 mide
también esa automatización, no solo la disciplina.

## Lo que le toca al harness (issue `04`)

- Materializar el scaffold de cada brazo y copiarle `enunciado.md` y `datos/`.
- La ronda de preguntas: cuando un turno termina con `PREGUNTAS.md`, guardar una copia con la hora,
  borrarla, contestar según `cliente/respuestas.md` y relanzar.
- Correr cada expectation sobre una copia fresca de `datos/` y escribir `grading.json` con el formato
  de skill-creator.
