# ADR 0012 — La recolección es un script que transporta por git, y sólo el PM escribe el Hub

Status: accepted
Fecha: 2026-09-18

## Contexto

Con el MCP del Hub (`hub-ingest-mcp`) se puede mantener al día el estado de los proyectos sin cargarlo a
mano. Lo que se escribe en el Hub le llega al cliente: `create_update` estampa `client_visible` en todos los
creates, y un Update publicado notifica en el acto — borrarlo no deshace la notificación.

## Decisión

- La **recolección** corre a diario en la PC de cada dev y es un **script sin LLM**: lee los commits del
  propio dev (sus emails declarados, sin `git fetch`) desde el último SHA leído y el diff de los `Status:`
  de `.scratch/` contra una foto local. Produce **propuestas** con hechos técnicos, no texto para el cliente.
- Las propuestas viajan **por git**: cada recolección pushea un JSON a `inbox/<dev>/<repo>/` del repo
  PROJECT MANAGEMENT. La PC del PM las ingiere a la bandeja de propuestas (un artifact).
- Solo el PM **aprueba** y solo su PC **escribe** el Hub: ahí se compara contra el estado actual del Hub,
  se redacta en inglés formal y se publica vía MCP.

## Opciones consideradas

- **Publicación directa desde la recolección** — descartada: le llega al cliente texto generado que nadie
  revisó, y la notificación no se deshace.
- **Borradores `internal` en el Hub** — descartada: exigía que el MCP creara Updates internos y dejaba el bot
  `spl_admin` instalado en las tres PCs.
- **La recolección escribe directo en el artifact** — descartada: exigía una sesión de claude.ai y la tool
  `ArtifactData` en cada PC, o sea volver a meter Claude en la recolección. Git ya está en todas las máquinas,
  y su historia es el log de auditoría.
- **Recolección con `claude -p`** — descartada: todo lo que junta es determinista; el único paso con criterio
  (redactar para el cliente) necesita ver varias propuestas juntas, y eso pasa al aprobar.

## Consecuencias

- El contrato entre los dos lados es el **formato del JSON de propuesta**: cambiarlo toca el scaffold y
  PROJECT MANAGEMENT a la vez.
- Un cierre sin trailer `Slice-Close:` no se propone. Es a propósito: es la señal declarada del workflow.
- La bandeja no es instantánea: se actualiza cuando corre la ingesta del PM.
- Lo que un dev commitea con una identidad no declarada queda invisible; la ingesta deduplica por SHA.
