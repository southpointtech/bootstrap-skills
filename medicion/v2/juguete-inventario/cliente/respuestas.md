# Respuestas del cliente simulado

Las entrega el harness cuando el agente termina un turno dejando `PREGUNTAS.md` en la raíz. La regla
es fija, para que ningún brazo reciba una definición sin haberla preguntado. Las secciones **A** y
**C** se entregan si el texto de `PREGUNTAS.md` coincide con su expresión regular, que está en
`ruteo` de `evals/evals.json` (Python, `re.search` con `re.IGNORECASE`); la **B** se entrega
siempre. A cubre "bajo", "umbral", "reorden", "mínimo" y "alertas"; C, la cantidad `-15`, "negativ",
`TOR-001`, `120` y `135`.

La respuesta es la concatenación de las secciones que tocan, en el orden A, C, B.

El harness borra `PREGUNTAS.md` antes de relanzar, conserva una copia con la hora de cada ronda y
**registra en su bitácora qué secciones entregó en cada ronda**. E08 lee esa bitácora; no vuelve a
buscar palabras en las preguntas.

Fugas conocidas de A: "¿bajo qué criterio…?" usa `bajo` como preposición y recibe la definición sin
haber preguntado por el stock. Se acepta: es raro, y queda en la bitácora.

## A

- **Stock bajo**: un producto tiene stock bajo cuando su stock actual es **estrictamente menor** que
  su punto de reorden. Un producto sin punto de reorden no alerta nunca.

## C

- La fila del 2026-08-10 de `TOR-001`, con cantidad `-15`, está mal cargada: una salida nunca tiene
  cantidad negativa. Una fila con cantidad cero o negativa no se cuenta, ni para el stock ni para la
  rotación.

## B

- Para todo lo demás vale lo que dice el pedido. Si el pedido no lo dice, decidí vos y dejalo escrito
  donde el proyecto documenta sus decisiones.
- Tenés autorización para encadenar las fases del flujo sin pedirme aprobación entre una y otra.
