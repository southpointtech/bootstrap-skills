# Respuestas del cliente simulado

Las entrega el harness cuando el agente termina un turno dejando `PREGUNTAS.md` en la raíz. La regla
es fija, para que ningún brazo reciba la definición de "stock bajo" sin haberla preguntado:

- si `PREGUNTAS.md` contiene la palabra `bajo` (sin distinguir mayúsculas), la respuesta es la
  sección **A** seguida de la **B**;
- si no, es solo la sección **B**.

El harness borra `PREGUNTAS.md` antes de relanzar y conserva una copia con la hora de cada ronda.

## A

- **Stock bajo**: un producto tiene stock bajo cuando su stock actual es **estrictamente menor** que
  su punto de reorden. Un producto sin punto de reorden no alerta nunca.

## B

- Para todo lo demás vale lo que dice el pedido. Si el pedido no lo dice, decidí vos y dejalo escrito
  donde el proyecto documenta sus decisiones.
- Tenés autorización para encadenar las fases del flujo sin pedirme aprobación entre una y otra.
