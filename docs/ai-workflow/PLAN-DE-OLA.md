# Plan de la ola {{N}} — plantilla

> **Mecánica: este archivo no se edita en el proyecto.** Las `{{…}}` se rellenan **en el chat**,
> cada vez que se planea una ola, no acá. El plan completado se le muestra al humano, se escribe
> en la sección «La ola vigente» de [`PARALELISMO-DEL-PROYECTO.md`](PARALELISMO-DEL-PROYECTO.md)
> y **no se despacha nada hasta que lo apruebe**.

**Candidatos**: {{slices desbloqueados, con su dependencia ya integrada}}.
**Elegidos**: {{NN + NN + NN}} · **Aprobado por**: {{persona}}, {{fecha}}.

## Reparto

| Carril | Slice | Archivos de los que es dueño | Archivo caliente |
|---|---|---|---|
| **A** (camino crítico) | {{NN título}} | {{…}} | **dueño** / no |
| **B** | {{…}} | {{…}} | no: diff en su reporte |
| **C** | {{…}} | {{…}} | no |

**Recursos de dev por carril**: A → {{…}} · B → {{…}} · C → {{…}}.

## Por qué quedaron afuera los demás

- {{slice}}: {{comparte archivo X con el carril A → va en la ola siguiente}}.

## Medido antes de repartir

- {{slice}}: {{la función tiene K llamadores, J tests la tocan → entra/no entra en ~400}}.
- {{Chequeo de solapamiento: ningún archivo aparece en dos filas del reparto.}}

## Contratos y nombres compartidos de esta ola

- {{El carril B declara `NOMBRE_EXACTO`; el carril C lo consume con ese nombre.}}

## Lo que cada carril resuelve antes del primer test

- {{slice}}: {{pregunta}} → {{decidido por quién, o «técnica: la decide el carril»}}.

## Checklist del orquestador

**Antes de despachar**
- [ ] El humano aprobó este plan.
- [ ] El árbol principal está en `{{main}}` y limpio (`git status`); worktrees viejos listados (`git worktree list`).
- [ ] Ningún archivo tiene dos dueños.
- [ ] Dependencias que la ola necesita: ya agregadas por el orquestador, con fecha verificada (≥ 14 días).
- [ ] Worktrees abiertos con `abrir-carril.ps1`, con `.env` y las issues copiadas (verificá que la issue existe **dentro** de cada worktree).
- [ ] Recursos de dev aislados por carril.
- [ ] Cada brief lleva la lista de guardas transversales.

**Al integrar (por carril, en serie, sin subagentes vivos)**
- [ ] Memoria libre suficiente.
- [ ] `/review-loop` corrido con la cwd en el worktree, hasta cerrar; marcador avanzado.
- [ ] Rebase sobre `{{main}}` (salvo el primero) y suite del carril verde.
- [ ] Merge; diffs del archivo caliente aplicados si corresponde.
- [ ] Búsqueda de `skip`s que debieron despertar y de nombres de contrato que no coinciden.

**Al cerrar la ola**
- [ ] Suite completa + E2E verde sobre `{{main}}`, con el SHA anotado.
- [ ] Lecciones de la ola {{N}} escritas en sus dos destinos: «Lo que dejó la ola N» en `PARALELISMO-DEL-PROYECTO.md`, y las que valen para cualquier proyecto, subidas a la mecánica en Bootstrap Skills.
- [ ] Worktrees removidos; ramas conservadas.
- [ ] Handoff actualizado.
