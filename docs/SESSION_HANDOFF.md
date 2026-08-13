# Session Handoff — 2026-08-12 parte 2 (A1 implementado con TDD: marcador + loop incremental)

## ▶▶▶▶▶ ESTADO AL RETOMAR — decir "continuemos" y seguir desde acá

Rama **`feat/marcador-de-revision`**, commit base `01fa552`. **A1 está IMPLEMENTADO y la suite
completa (12/12) está verde. NADA commiteado.** El siguiente paso es commitear el slice y correr
`/review-loop` sobre él.

### Qué se hizo esta sesión

Se implementó **A1 — El turno incremental** (`.scratch/review-cost-redesign/issues/01-el-turno-incremental.md`)
con `/tdd`, un test a la vez (RED → GREEN), nunca todos los tests primero. Las 3 piezas del issue
shippean juntas y están las 3.

**Pieza 1 — el marcador, como script.** `.claude/scripts/review-marker.ps1` (98 líneas, directorio
nuevo), con la interfaz de 3 verbos aprobada en el grill:

| Verbo | Qué hace |
|---|---|
| `-Action get` | el marcador guardado para esta rama, o vacío |
| `-Action range` | qué pasarle a `git diff` (marcador si resuelve; si no, merge-base del slice); **vacío si no hay delta** |
| `-Action advance` | `git stash create` (fallback HEAD con árbol limpio), persiste e imprime |

Detalles de implementación que ya están resueltos y testeados:

- `range` emite el marcador **PELADO** (`git diff <marcador>`), no `<marcador>..HEAD` — la forma con
  `..HEAD` solo cubre commits y dejaría afuera lo no commiteado.
- Estado en `<git-dir>/review-loop-state.json` bajo claves **`marker:<rama>`**. Verificado por test
  que **no pisa** el dedupe por SHA del hook (que usa la clave `<rama>` pelada) en el mismo archivo.
- Parámetros `-Action` (obligatorio, `ValidateSet`) y `-RepoDir` (por testabilidad, estilo
  `copy-scaffold.ps1`). Todo con `git -C $dir`, sin depender del cwd.
- Base del slice resuelta sin hardcodear `main`: `origin/HEAD` → candidatos `main`/`master`/`develop`
  (excluyendo la rama actual) → `merge-base`.
- Guards: fuera de repo git, detached HEAD, repo sin commits, marcador podado por `git gc` →
  **salida vacía, exit 0**. El modo de falla por default es revisar de más, nunca de menos.

**Pieza 2 — el loop lo usa.** Reescritas 2 secciones de `review-loop` (comando + SKILL.md): la nueva
sección "The range: review the unreviewed delta, not the whole branch" reemplaza a "PR mode" /
"Commit / local mode", y "The loop" pasó de 3 a 5 pasos.

**Pieza 3 — RED obligatorio.** El paso 5 del loop exige un test que **falle sin el fix** (verificado
en vivo) antes de escribir el fix, en lugar del viejo "add or update a test when practical".

### ⚠️ Decisión de diseño que se APARTA de la letra del issue (declarada, no consultada)

El issue decía: *"aplica fixes y avanza el marcador al cerrar [el turno]"*. **Eso está implementado al
revés a propósito**: `advance` va **después de la corrida de review y ANTES de aplicar los fixes**.

Razón: si el marcador avanzara después de los fixes, el turno siguiente recibiría un rango vacío y
**los fixes del loop nunca los revisaría nadie** — exactamente el modo de falla que el ADR-0001 dice
evitar ("el turno 2 revisa los fixes del turno 1, no el slice entero"), y la causa de que 59 de 235
reportes de turno atribuyeran sus hallazgos a los fixes del turno anterior.

Riesgo asumido y sin mitigar: si el proceso muere entre `advance` y los fixes, esos fixes quedan del
lado revisado sin haberlo sido. **Vale confirmarlo con el usuario**, es lo único del slice que no
sigue el issue al pie de la letra.

### Archivos de esta sesión

Nuevos (sin trackear):

```
.claude/scripts/review-marker.ps1                                    98 líneas  (×4 copias)
skills/bootstrap-{personal,southpoint,ai}-project/assets/scaffold/.claude/scripts/review-marker.ps1
tests/review-marker.tests.ps1                                       139 líneas (24 asserts)
tests/review-loop-incremental.tests.ps1                              47 líneas (contrato ×4 copias)
```

Modificados:

```
.claude/commands/review-loop.md                    ×4 copias (repo + 3 skills)
.agents/skills/review-loop/SKILL.md                ×4 copias (repo + 3 skills)
tests/slice-review.tests.ps1                       1 assert relajado (ver abajo)
skills/*/assets/scaffold/.bootstrap-manifest.json  ×3 REGENERADOS (50 → 51 archivos)
```

**Tamaño del slice contra la copia canónica ×1** (decisión 5 del handoff previo): ≈358 líneas de
lógica. Bajo el techo de ~400.

### Regresión encontrada y arreglada dentro de la sesión

`tests/slice-review.tests.ps1` exigía `^1\. Run \`/slice-review\`` — el reviewer en el **paso 1**.
Con el loop incremental el paso 1 es pedirle el rango al marcador y la corrida de review es el paso 2,
así que los 6 asserts iban a RED. Se relajó a `^\d+\. Run \`/slice-review\``: lo que ese test blinda
es el **motor** (que no se vuelva a `/code-review`), no el número de paso. El assert que prohíbe
ordenar `/code-review` quedó intacto.

### Verificación hecha (no es "parece que anda")

- **Suite completa: 12/12 archivos verdes**, corrida entera al cierre. Cero tests fallando.
- `tests/review-marker.tests.ps1`: **24 asserts**, sobre repos git temporales, runner sin Pester
  (patrón de `review-loop-trigger.tests.ps1`). Cubre las 9 conductas del issue + detached HEAD +
  coexistencia con el dedupe del hook.
- **Mutación acotada (4 mutantes, hechos a mano sobre el script):**
  | Mutante | Resultado |
  |---|---|
  | `stash create` → `rev-parse HEAD` | **muere** (árbol sucio) |
  | guard de detached HEAD debilitado | **muere** |
  | validación `cat-file -e` del marcador borrada | **muere** (marcador podado) |
  | guard de "no es repo git" borrado | **SOBREVIVE** |
  El sobreviviente es **redundancia, no un agujero**: el guard de `branch` ya tapa el caso y la
  conducta observable (vacío, exit 0) sigue verificada. Se dejó el guard como defensa explícita.
- El fixture del test de `git gc` tiene su **propio guard** (`Assert` de que el objeto realmente se
  podó): sin eso el test pasaba en verde sin ejercitar nada.

### Bugs

- **Ninguno nuevo encontrado ni arreglado** en el código del repo.
- **Sigue abierto**: los 5 heredados (atribución cruzada del hook, RED faltante, reviewers que
  escriben en el árbol, desperdicio de `main...HEAD`, loop que se autoalimenta). A1 resuelve los
  puntos 2, 4 y parte del 5 **en el contenido del scaffold**, pero **no llegan a la máquina hasta
  A7** (`sync-skills`).
- **Sigue abierto**: `copy-scaffold.ps1` pisa el `.gitignore` del proyecto destino (encontrado en la
  sesión anterior, sin arreglar, candidato a issue propio).
- **Sigue abierto**: `core.autocrlf` con hashes mixtos en los manifests.

### Antes de tocar código (leer sí o sí)

- **El `alignment-gate` va a frenar el primer edit de código de la sesión nueva.** El paso 1 está
  cerrado (grill 11/8, PRD e issues aprobados 12/8) y A1 ya está implementado: **no ofrezcas grill,
  decilo y reintentá el edit**.
- **Regla del espejo**: `review-marker.ps1`, `review-loop.md` y `review-loop/SKILL.md` van
  **byte-idénticos a las 4 copias** (3 skills + la del repo). El espejado ya está hecho y
  `mirror.tests.ps1` está verde; si tocás uno, replicá en los 4 o va a RED.
- El comando y el SKILL.md del loop difieren **solo en la línea `description`** (el SKILL.md lleva
  los triggers en español). Para sincronizarlos: copiar el comando y restaurar esa línea 3.
- **`.bootstrap-manifest.json` es generado**: `pwsh -NoProfile -File tools/gen-manifest.ps1 -SkillDir <skill>`
  (toma `-SkillDir` obligatorio, una skill por vez). Ya está corrido para las 3.
- **PENDIENTE menor no resuelto**: el `.bootstrap-manifest.json` de la **raíz del repo** (del
  self-bootstrap) **no** se regeneró — `gen-manifest.ps1` solo apunta a skills. Decidir si se resella
  (hay scripts de reseal en `skills/upgrade-bootstrap/scripts/`) o si se deja.
- Editar skills acá **no tiene efecto** hasta `tools/sync-skills.ps1` (pendiente heredado del 1/8).

### Preferencias del usuario (vigentes)

- **No commitear sin que lo pida.** Por eso el slice está sin commitear.
- **Nada de esto va a Zoho.**
- Quiere **impacto medido antes de cambiar el proceso**.
- Criterio: "el menor tiempo posible pero que la revisión sea completa y acertada".
- Prefiere **cortar y seguir en terminal nueva** antes que dejar crecer el contexto.

### Próximos pasos

1. **Confirmar (o no) la decisión de `advance` antes de los fixes** — es lo único que se aparta del
   issue. Un minuto de conversación, cambia el orden de dos pasos si él prefiere la letra del issue.
2. **Commitear el slice de A1.** Sugerido: `feat(review-loop): marcador de revisión y turno incremental`.
   El hook `review-loop-trigger` va a disparar la orden de correr el loop.
3. **`/review-loop` sobre el diff del slice.** El `/review-loop` de ESTE repo sí puede cerrarse
   (`/slice-review` existe acá). **Ojo — el loop que acaba de cambiar es el del scaffold, no el que
   corre esta sesión**: la sesión usa `.claude/commands/review-loop.md` del repo, que también se
   espejó, así que el propio loop va a intentar usar el marcador nuevo. Es la primera prueba real.
4. **A2 y A3** (dependen solo de A1), después A4/A5, después A6, y **A7 al final (requiere presencia
   humana**: deploya a `~/.claude/skills`).
5. Sin bloquear: el Track B (B1/B2, vencen **10/9**) lo lleva el usuario en otra terminal en
   `claude-analytics`.
6. Pendientes heredados: el diff de `fix/review-loop-motor-invocable` nunca pasó por reviewer; no
   mergear a `main` hasta cerrar Track A; `sync-skills` pendiente.

### Supuestos declarados

- Que los PRDs e issues vivan en `.scratch/` (gitignoreado) sigue siendo una consecuencia, no una
  decisión. **Sigue sin preguntarse.** Si se pierde el directorio, se pierden los 15 archivos.
- El techo de ~400 líneas se midió a mano contando la copia canónica ×1; no hay tooling que lo
  verifique.
- No se verificó que el marcador funcione **end-to-end dentro de una corrida real del loop** — los
  tests cubren el script y el contenido de las instrucciones, no la ejecución del loop completo. El
  paso 3 de arriba es esa prueba.

---

# Session Handoff — 2026-08-12 (PRDs + issues de los dos tracks, bootstrap de claude-analytics)

## ▶▶▶▶ ESTADO AL RETOMAR (sesión 2026-08-12)

Rama **`feat/marcador-de-revision`**, creada esta sesión desde `fix/review-loop-motor-invocable`
(commit `01fa552`). **Nada commiteado en este repo esta sesión.** Working tree:

```
 M CONTEXT.md                                        (de la sesión anterior, sin commitear)
 M docs/SESSION_HANDOFF.md
?? docs/adr/0001-review-incremental-con-marcador.md  (nuevo, sin trackear)
```

**Fases del workflow completadas esta sesión: paso 4 (PRD) y paso 6 (issues).** El paso 5
(aprobación del PRD) y la aprobación de los issues los dio el usuario. **La implementación de A1
está aprobada y diseñada pero NO empezada** — el usuario pidió explícitamente hacerla en una
terminal nueva.

### ⚠️ Lo primero que tenés que saber: los PRDs y los issues NO están en git

`.scratch/` está en el `.gitignore` de los dos repos. Los 15 archivos de abajo existen **solo en el
working tree**. Si se pierde el directorio, se pierden. Evaluar con el usuario si conviene moverlos
a `docs/` o commitearlos; no se hizo porque él no lo pidió.

```
Bootstrap Skills/.scratch/review-cost-redesign/          (Track A — 1 PRD + 7 issues)
claude-analytics/.scratch/review-cost-measurement/       (Track B — 1 PRD + 6 issues)
```

El ADR sí está en git-land (`docs/adr/0001-...`), aunque todavía sin trackear.

### Qué se produjo esta sesión

**Dos PRDs** (paso 4), a partir del grill del 11/8, sin volver a entrevistar:

- **Track A** — `Bootstrap Skills/.scratch/review-cost-redesign/PRD.md`. Rediseño del ciclo de
  revisión. 36 user stories, las 8 decisiones del grill + 4 menores, 5 módulos.
- **Track B** — `claude-analytics/.scratch/review-cost-measurement/PRD.md`. La medición que juzga al
  Track A. 31 user stories, 3 slices.

**Un ADR** — `docs/adr/0001-review-incremental-con-marcador.md`. Primero del repo. Documenta la
decisión de alcance con sus 5 alternativas descartadas (incluidas "bajar el cap a 2" y "matar el
pase de confianza", las dos que se cayeron con números).

**13 issues** (paso 6), aprobados con granularidad, techo y orden confirmados por el usuario:

| Track A (`.scratch/review-cost-redesign/issues/`) | Tipo | Bloqueado por |
|---|---|---|
| `01-el-turno-incremental.md` | AFK | — |
| `02-disparo-por-cierre-de-slice.md` | AFK | 01 |
| `03-corrida-de-review-incremental.md` | AFK | 01 |
| `04-pase-de-coherencia.md` | AFK | 03 |
| `05-mutacion-acotada.md` | AFK | 03 |
| `06-regla-de-afirmaciones.md` | AFK | — (serializar tras 05: toca `slice-review` en 1 línea) |
| `07-sellar-y-deployar.md` | **HITL** | 01–06 |

| Track B (en `claude-analytics/.scratch/review-cost-measurement/issues/`) | Tipo | Bloqueado por |
|---|---|---|
| `01-congelar-prompts-de-reviewer.md` | AFK | — ⏳ **vence 10/9** |
| `02-completar-el-snapshot.md` | AFK | 01 ⏳ **vence 10/9** |
| `03-clasificar-foco-y-turno.md` | AFK | 01 |
| `04-atribuir-reviewer-a-turno.md` | AFK | 01 |
| `05-reporte-de-costo-de-revision.md` | AFK | 03, 04 |
| `06-comparacion-contra-la-linea-base.md` | AFK | 05 |

### Decisiones tomadas esta sesión

| # | Decisión | Quién |
|---|---|---|
| 1 | El **marcador es un script real** (`.claude/scripts/review-marker.ps1`), no prosa en el SKILL.md | usuario |
| 2 | Se testean los 4 targets: marcador, hook trigger, contenido de los SKILL.md, y baseline/sidechain del Track B | usuario |
| 3 | **El ADR se escribe** junto con el PRD | usuario |
| 4 | Granularidad: **13 slices**, como se propuso | usuario |
| 5 | El techo de ~400 líneas se mide contra la **copia canónica ×1**, no contra las 4 copias espejadas (si no, ningún slice del Track A es posible: el test de espejo exige las 4 juntas) | usuario |
| 6 | Orden: **B1+B2 → A1–A7 → B3–B6** (primero lo que vence) | usuario |
| 7 | **Nada de esto va a Zoho** | usuario |
| 8 | `claude-analytics` se bootstrapea **antes** de desarrollar | usuario |
| 9 | Se bootstrapea **tal cual** (con el scaffold viejo) + `upgrade-bootstrap` después de A7, en vez de deployar el fix ahora | usuario |
| 10 | **Los tracks avanzan en paralelo.** Sin dependencia técnica; lo único que conviene esperar es A7 (deploya a la máquina entera) | agente, no objetado |
| 11 | El PRD y los issues del Track B **viven en `claude-analytics`**, no acá: es su tracker | agente, no objetado |

### Diseño de A1 cerrado en la planificación de `/tdd` (implementar tal cual)

Interfaz de `.claude/scripts/review-marker.ps1`, **tres verbos que hacen cosas distintas**:

```
-Action get      -> el marcador guardado para esta rama, o vacío si no hay   (consulta pura)
-Action range    -> qué pasarle a `git diff`, o vacío si no hay nada nuevo
                    (el marcador si es válido; si no, el merge-base del slice)
-Action advance  -> git stash create (fallback HEAD si el árbol está limpio), persiste e imprime
```

- **`range` emite el marcador PELADO, no `<marcador>..HEAD`** (cambio de contrato aprobado por el
  usuario). Razón: la forma con `..HEAD` solo cubre commits y dejaría afuera lo no commiteado, que
  es justamente lo que `git stash create` existe para incluir. El contrato es `git diff <marcador>`.
  Con `merge-base` como fallback, `git diff <merge-base>` reproduce exacto `base...HEAD`.
- **Ubicación `.claude/scripts/`** (directorio nuevo, aprobado). No es un hook: no lo dispara Claude
  Code por evento, lo invocan el loop y —en A2— el disparo. `tools/gen-manifest.ps1` lo levanta solo
  (recorre recursivo), no hay que registrarlo en ningún lado.
- **Estado**: mismo `.git/review-loop-state.json`, bajo claves `marker:<rama>`. Git prohíbe `:` en
  nombres de rama, así que no puede colisionar con el dedupe por SHA que ya vive ahí, y los archivos
  de estado existentes siguen funcionando sin migración.
- **Marcador recolectado por `git gc`** → cae al merge-base. El modo de falla por default es revisar
  de más, nunca de menos.
- **Parámetro `-RepoDir`** (además de `-Action`), por testabilidad y siguiendo el estilo de
  `copy-scaffold.ps1` / `gen-mcp-json.ps1`, que ya toman `-ProjectDir`.
- **Detached HEAD** → salida vacía, igual que hace el hook hoy.

Las 9 conductas a testear salen de los criterios del issue 01: árbol sucio incluido en el corte,
`advance` no commitea, `advance` no toca el árbol, el rango no repite lo ya revisado, sin marcador
previo arranca en la base, idempotencia con árbol limpio, fuera de un repo git no rompe, el estado
no aparece en el diff del slice, y marcador recolectado cae a la base.

El **tracer bullet** ya estaba escrito cuando el usuario cortó: en `tests/review-marker.tests.ps1`,
`advance` devuelve un objeto resoluble y `get` lo devuelve de vuelta. **No llegó a disco** (lo frenó
el `alignment-gate`), así que hay que reescribirlo.

### Bootstrap de `claude-analytics` — HECHO

Commit **`6d136a0`** en `C:\Repos\PERSONAL\claude-analytics` (rama `master`, sin remote), 52
archivos: `CLAUDE.md`, `README.md`, `CONTEXT.md` (stub), `skills-lock.json`,
`.bootstrap-manifest.json`, `.agents/skills/` (10), `.claude/` (10 comandos + settings + 2 hooks),
`docs/ai-workflow/` (5), `docs/agents/` (3), `docs/adr/.gitkeep`, `.scratch/`.

**No fue modo adopción**: el repo no tenía `CLAUDE.md` ni `docs/ai-workflow/`, así que no hay
`docs/agents/legacy-claude.md` ni mapa de cobertura. Fue bootstrap normal sobre directorio con
contenido.

Dos cosas que la skill **no** maneja y hubo que hacer a mano:

1. **`.gitignore`**: `copy-scaffold.ps1` sobrescribe sin preguntar (`[IO.File]::Copy(..., $true)`),
   contradiciendo el "never overwrite" del Step 0. Se respaldó, se copió y se fusionaron las reglas
   propias bajo una sección marcada `# --- Project-specific (preserved from the pre-bootstrap
   .gitignore) ---`. **Crítico**: ahí vive `output/raw/`, donde están los 4 JSONL de la línea base de
   agosto. Verificado con `git check-ignore -v`: sigue ignorado, los datasets intactos.
   → **Esto es un bug del scaffold que vale anotar como backlog**: cualquier bootstrap sobre un repo
   con `.gitignore` propio lo pierde en silencio.
2. **`.mcp.json`**: no se corrió `gen-mcp-json.ps1`. El proyecto ya tenía uno curado (zoho-projects,
   fellow, m365-southpoint) y el generador lo habría reemplazado por el catálogo personal.

Sin tocar: los 3 archivos que ya estaban sin trackear (2 PDFs y `ZOHO-CARGA-2026-06-29_07-06.md`).
Identidad local seteada: `MartinDele703 <martin.deleon703@gmail.com>`.

**Caveat aceptado por el usuario**: la skill instalada en `~/.claude/skills` es del **6 de julio** y
**no tiene `slice-review`** (10 comandos, no 11). O sea, `claude-analytics` nació con el ciclo
inerte: su `/review-loop` apunta al built-in human-only y no puede cerrarse solo. Para B1/B2 el plan
es `/code-review` tipeado a mano; después de A7, `upgrade-bootstrap` ahí. Sigue pendiente
`tools/sync-skills.ps1` (pendiente heredado del 1/8).

### Bugs

- **Encontrado esta sesión**: `copy-scaffold.ps1` pisa el `.gitignore` del proyecto destino (ver
  arriba). **No arreglado** — no estaba en alcance. Candidato a issue propio.
- **Sigue abierto** (heredados, ninguno arreglado): los 5 del handoff del 11/8 — atribución cruzada
  del hook, RED faltante en el loop, reviewers que escriben en el árbol, desperdicio del rango
  `main...HEAD`, y el loop que se autoalimenta. Los cinco son exactamente lo que A1–A6 resuelven.

### Tests y comandos

- **No se corrió ninguna suite** en ninguno de los dos repos. `tests/*.ps1` sin ejecutar. No hay
  tests fallando conocidos ni verificados.
- Comandos con efecto: `git checkout -b feat/marcador-de-revision` (acá) y, en `claude-analytics`,
  `copy-scaffold.ps1` + `git config user.name/email` + `git add` selectivo + `git commit`.
- Verificaciones de solo lectura: `git check-ignore -v` sobre `output/raw/`, conteo de skills y
  comandos del scaffold copiado, chequeo de anidamientos (`.agents\.agents`, `.claude\.claude`,
  `docs\docs`: ninguno).

### Antes de editar código (leer sí o sí)

- **El `alignment-gate` va a frenar tu primer edit de código**, porque es una sesión nueva y el
  contador es por sesión. **El paso 1 ya está cerrado** (grill del 11/8, PRD y issues aprobados el
  12/8): no ofrezcas grill, decilo y reintentá el edit.
- **Regla del espejo**: `review-marker.ps1` (nuevo), `review-loop/SKILL.md`, `slice-review/SKILL.md`
  y `review-loop-trigger.ps1` **no** están en la allowlist de `tests/mirror.tests.ps1` → van
  byte-idénticos a las 3 skills bootstrap **y** a la copia de este repo. Cuatro copias o el test va a
  RED. Los `assets/scaffold/CLAUDE.md` **sí** están en la allowlist: se editan por separado.
- Implementá primero en `skills/bootstrap-personal-project/assets/scaffold/` (es a donde apuntan los
  tests existentes) y después espejá.
- El `.bootstrap-manifest.json` es **generado**: `tools/gen-manifest.ps1` antes de commitear.
- Editar skills acá **no tiene efecto** hasta `tools/sync-skills.ps1`.
- Los repos temporales de test se borran al terminar.

### Preferencias del usuario (vigentes)

- **No commitear sin que lo pida.** Sigue vigente: esta sesión no se commiteó nada acá.
- **Nada de esto va a Zoho.**
- Quiere **impacto medido antes de cambiar el proceso**; ya rechazó dos propuestas con datos.
- Criterio de optimización: "el menor tiempo posible pero que la revisión sea completa y acertada".
- Prefiere **cortar y seguir en terminal nueva** antes que dejar crecer el contexto. Fue el motivo de
  este handoff: la implementación de A1 se corta acá a propósito.

### Próximos pasos

1. **Implementar A1** con `/tdd` sobre `.scratch/review-cost-redesign/issues/01-el-turno-incremental.md`,
   en la rama `feat/marcador-de-revision` que ya existe. El diseño está cerrado arriba: empezá por el
   tracer bullet en `tests/review-marker.tests.ps1`, un test a la vez (RED → GREEN), nunca todos los
   tests primero.
2. Al cerrar A1: `/review-loop` sobre el diff del slice. **Ojo**: el `/review-loop` de ESTE repo ya
   tiene el fix (`/slice-review` existe acá), así que sí puede cerrarse.
3. Seguir con A2 y A3 (los dos dependen solo de A1), después A4/A5, después A6, y A7 al final.
4. **A7 requiere presencia humana**: deploya a `~/.claude/skills` y cambia el tooling de la máquina.
5. Sin bloquear lo de arriba: el Track B (B1/B2) lo está haciendo el usuario en otra terminal, en
   `claude-analytics`. No hay dependencia técnica entre los tracks.
6. Pendientes heredados que siguen vivos: el diff de `fix/review-loop-motor-invocable` nunca pasó por
   ningún reviewer; no mergear a `main` hasta que cierre el Track A; `sync-skills` pendiente; el bug
   de `core.autocrlf` con hashes mixtos en los manifests.

### Supuestos declarados

- Que `.scratch/` esté gitignoreado es intencional por convención del tracker, pero nadie decidió que
  los PRDs vivan fuera de git — es una consecuencia, no una decisión. Vale preguntarle.
- El paralelismo entre tracks asume que el usuario efectivamente está corriendo B1 en otra terminal
  (lo dijo, no se verificó desde acá).
- La medición que fundamenta todo el Track A es la del handoff del 11/8; no se re-verificó nada de
  esos números en esta sesión.

---

# Session Handoff — 2026-08-11 (rediseño del costo del review-loop: medición + grill cerrado)

## ▶▶▶ ESTADO AL RETOMAR (sesión 2026-08-11)

Rama **`fix/review-loop-motor-invocable`**, commit `01fa552`. Working tree: **solo `CONTEXT.md` modificado** (sin commitear). No se tocó código ni skills.

**Fase del workflow completada: paso 1 (alineación) vía `/grill-with-docs`. El siguiente paso es `/to-prd`.** No hay implementación empezada. Aprobación humana dada para el orden de cambios; falta aprobar el PRD.

### Qué pidió el usuario y qué se descubrió

Pregunta original: "Claude tarda mucho más desde Opus 5 — ¿es el modelo, es el Bootstrap, o son los proyectos más grandes?" Un compañero con el mismo scaffold reportó lo mismo.

**Respuesta medida: no es Opus 5.** Fuente: 703 transcripts JSONL (130.252 líneas, 28.502 llamadas al modelo, 1.393 turnos) + la DB de `claude-analytics` para el baseline abril–junio.

- **Latencia por llamada, p50, estable desde abril**: opus-4-7 4,7–6,2 s · opus-4-8 7,0–8,0 s · **opus-5 6,5–7,1 s**. La cola *mejoró*: p90 42,4 s (opus-4-8, junio) → 29,2 s (opus-5, agosto). Throughput 62–75 tok/s sin cambio.
- **Lo que se duplicó es el turno**: pasos/turno 4 → 9, tool calls 4 → 10, wall p50 92 s → 187 s. Turnos/día iguales (60–90), pero horas de máquina ocupada por día ~7 h → ~11 h.
- **Causa dominante: el review-loop empezó a funcionar de verdad el 1/8 a las 14:08** (commit `8cc6e9e`, el fix del reviewer invocable). Primer subagente `slice-review` de la historia: 1/8 14:29, 21 minutos después. Antes el loop apuntaba a `/code-review` (human-only) y se cerraba sin revisar nada.
- **Costo del review en agosto**: 357 subagentes · 8.930 pasos · 8,74M tokens · **67,2 h en serie / 36,3 h de reloj** (concurrencia 1,8×). **46% de todos los tokens de salida de agosto los generaron reviewers** (8% en julio).
- **El costo está en la profundidad, no en el ancho**: **73% de los pasos de reviewer son comandos de shell** (7.503 Bash + 220 PowerShell). Reviewer típico: 23 pasos / 8,2 min.
- **Aporte real de Opus 5** (mismo repo, mismo mes, para aislar): Forecasting App julio, opus-4-8 262 s de máquina por turno vs opus-5 345 s → **+32%**. Es amplificador, no causa.
- **Refutado: "los proyectos son más grandes".** Contexto por llamada *bajó*: 183k (abr) → 145k (jun) → 102k (ago).
- **El compañero**: la rama del fix **no está en `main`**, así que quien tenga el scaffold publicado tiene el loop inerte. Su lentitud no puede venir del fan-out. Sin datos de su máquina — es inferencia.

### Decisiones tomadas en el grill (las 8)

| # | Decisión |
|---|---|
| Alcance | Review **incremental** del delta sin revisar + **pase de coherencia** final (1 reviewer, read-only, sin ejecutar nada) sobre `base...HEAD` |
| Marcador | **`git stash create`** — verificado: no commitea, no toca el árbol, y el diff contra el marcador trae solo lo nuevo |
| Afirmaciones falsas | **Regla en `CLAUDE.md`** (no escribir afirmaciones no verificadas) + 1 línea en el reviewer de contratos. **Cero agentes dedicados** (hoy: 123 agentes, 34,3 h = 51% del review) |
| Mutación | **RED obligatorio** en los fixes del loop + **mutación acotada** una vez en el turno 1: ≤8 mutantes, solo líneas del slice, solo el test file. Prohibida en turnos 2+ |
| Modelos | **Sonnet 5**: reglas, historia, coherencia. **Opus 5**: bugs, contratos/callers, tests, mutación **y scorer** |
| Read-only | Mutación en **worktree creado desde el marcador** (verificado: incluye lo no commiteado, el árbol original queda intacto). Prohibición para el resto en el contexto compartido del Step 3, no pegada a mano por prompt |
| Disparo del hook | **Trailer `Slice-Close:` en el commit** + techo de ~400 líneas de delta sin revisar como red. **Deja de disparar en cada commit** |
| Scorer | **Se queda.** Cuesta 3% (2,0 h de 67,2) y es el único filtro de falsos positivos. Descartado matarlo |

Decisiones menores resueltas por el agente (el usuario no las objetó):

- **El techo de 5 turnos queda igual** — con re-reviews angostos cada turno cuesta ~6 min; el cap solo acota la cola.
- **Fix del bug del hook**: comparar `git log -1 --format=%ct` contra el momento del evento; si el HEAD del repo no es reciente, el commit fue en otro repo y no dispara.
- **La regla de afirmaciones** va en los 3 `assets/scaffold/CLAUDE.md` (están en la allowlist del espejo → 3 ediciones separadas) + el `CLAUDE.md` de este repo. El `CLAUDE.md` real de Forecasting App queda como **follow-up marcado**, no editado en silencio.
- **El RED va en el paso 3 de `review-loop`**, no en `tdd` (`tdd/SKILL.md:67` ya lo exige; el que no lo pedía era el loop).

### Bugs encontrados (ninguno arreglado — no se implementó nada)

1. **El hook `review-loop-trigger` atribuye commits de otros repos.** Reproducido en vivo: un `git commit` en un repo temporal de `mktemp -d` disparó la orden de correr `/review-loop` sobre `main...HEAD` de Bootstrap Skills. Confía en `$evt.cwd` (cwd de la sesión) en lugar de verificar dónde corrió el comando. El dedupe por SHA no lo tapa en el primer disparo de la sesión.
2. **`review-loop/SKILL.md:66` no exige RED** al agregar tests para un fix ("add or update a test when practical"), mientras `tdd/SKILL.md:67` sí. Los tests que el loop escribe para sus propios fixes nacen sin dientes — es literalmente lo que los reviewers de mutación venían encontrando ("5 mutantes vivos en el trigger", "mi fix del turno 4 volvió inmatables 3 términos del guard").
3. **Los reviewers escriben en el árbol**: 84 de 345 subagentes usaron Write/Edit (217 Write + 202 Edit) cuando `slice-review` dice "Do not fix anything in this command". De ahí venían los "🚫 PROHIBIDO editar" pegados a mano en los prompts.
4. **Desperdicio del rango `main...HEAD`**: en Forecasting App el mismo rango se revisó en **5 disparos a lo largo de 3 días, 27 agentes, 540 minutos**; cada disparo re-revisa todo lo ya revisado. En Survey Clients: 2 disparos, 15 agentes, 186 min. En hssapp los repetidos son turnos del mismo loop (legítimos).
5. **El loop se autoalimenta**: 59 de 235 reportes de turno atribuyen los hallazgos a sus propios fixes anteriores. Los turnos 2–5 encuentran regresiones reales, pero introducidas por el turno previo. Por eso **no** se bajó el cap: cortar en 2 entrega los fixes del turno 2 sin revisar (el propio agente lo marcó en rojo el 9/8).

### Archivos tocados en esta sesión

- **`CONTEXT.md`** (modificado, sin commitear) — glosario llenado por primera vez: 12 términos (slice, cierre de slice, corrida de review, turno, marcador de revisión, delta sin revisar, reviewer, foco, pase de confianza, pase de coherencia, mutación acotada, afirmación), la ambigüedad de "review" que causó el bug original (`/code-review` vs `/slice-review` vs `/review-loop`), y un diálogo de ejemplo.
- **Fuera del repo**: los datasets de la medición se copiaron a `C:\Repos\PERSONAL\claude-analytics\output\raw\review-cost-baseline-2026-08\` (gitignored, repo sin remote): `steps.jsonl` (28.502 pasos), `turns.jsonl` (1.393 turnos), `agents.jsonl` (441 subagentes con prompt y reporte), `parent-texts.jsonl` (4.439 textos del agente padre), y los 5 scripts `.mjs` que los generan y analizan.

### ⏳ Lo urgente con fecha de vencimiento

`cleanupPeriodDays` no está configurado → **retención default de 30 días**. El transcript más viejo que sobrevive hoy es del **2026-07-12**. La DB de `claude-analytics` **sí** ingiere subagentes (1.363 de 2.066 archivos ingeridos) y conserva tokens/tiempos/modelos, pero **no guarda el texto de los prompts**, que es lo único que permite clasificar foco y turno. **La parte semántica de la línea base de agosto se borra alrededor del 10/9/2026.** Los `.jsonl` copiados arriba son la copia de seguridad; si se pierden, la comparación "antes vs después" ya no se puede hacer.

### Próximos pasos

1. **`/to-prd`**, en dos tracks:
   - **Track A — Bootstrap Skills**: `slice-review/SKILL.md` ×4 copias, `review-loop/SKILL.md` ×4, `.claude/hooks/review-loop-trigger.ps1` ×4, 3 `assets/scaffold/CLAUDE.md` + el `CLAUDE.md` del repo, tests (`review-loop-trigger.tests.ps1`, `slice-review.tests.ps1`, `mirror.tests.ps1` debe seguir verde) y manifests regenerados.
   - **Track B — claude-analytics** (el usuario eligió verificar desde ahí, no con scripts sueltos): primera slice = **congelar la línea base de agosto** (antes del 10/9), después modelar sidechain/turnos, después el reporte.
2. **ADR ofrecido y sin responder**: la decisión de alcance (review incremental + marcador) cumple los tres criterios — difícil de revertir, sorprendente sin contexto, producto de un trade-off real con alternativas descartadas por números. Preguntarle si lo escribe.
3. **El diff de esta rama sigue sin pasar por ningún reviewer** (pendiente heredado del 1/8, sigue vigente).
4. **No mergear a `main` todavía** — decisión de esta sesión: mergear tal cual le entrega a los demás proyectos el multiplicador de agosto. Merge después de Track A.
5. Después del merge: `upgrade-bootstrap` en hssapp/Outsourcing, Forecasting App, Survey Clients, Call Center.

### Riesgo de secuencia (declarado al usuario, aceptado)

El rediseño se aplica **antes** de que exista la medición que lo juzga (Track B es un proyecto aparte). Mitigación: los datasets congelados de arriba.

### Tests y comandos

- **No se corrió ninguna suite del repo** en esta sesión (no hubo cambios de código). `tests/*.ps1` sin ejecutar; no hay tests fallando conocidos ni verificados.
- Comandos ejecutados: los 5 scripts `.mjs` de medición (ahora en `claude-analytics/output/raw/review-cost-baseline-2026-08/`), consultas de solo lectura a `claude-analytics.db`, y dos experimentos en repos temporales que **verificaron** `git stash create` como marcador y `git worktree add --detach <marcador>` como aislamiento con los cambios no commiteados incluidos.

### Supuestos del análisis (para que el próximo no los tome como certezas)

- La clasificación de focos y turnos de los subagentes es **por regex sobre el prompt inicial**. 83 de 142 corridas no declaran número de turno, así que los cortes por turno son piso, no techo.
- Métricas de tiempo en **medianas**; los huecos > 30 min se descartan (humano ausente). `<task-notification>` cuenta como prompt humano, lo que infla el conteo de turnos.
- Agosto está concentrado en hssapp y Forecasting App: es el patrón de trabajo actual, no una ley general.
- Los JSONL crudos solo cubren 12/7 → 11/8; abril–junio viene de la DB y solo da latencia por llamada.

### Preferencias del usuario detectadas en esta sesión

- Criterio de optimización explícito: **"el menor tiempo posible pero que la revisión sea completa y acertada"** — se usó para decidir cada rama del árbol.
- **Los slices ya están definidos para tener un largo coherente** que le dé precisión al reviewer: por eso eligió disparar por slice y no por commit.
- No quiere abaratar el filtro de falsos positivos.
- Quiere evaluar impacto **con números antes de aplicar cambios**; rechazó dos propuestas ("matar el scorer", "bajar el cap") cuando la medición mostró que el ahorro no justificaba el riesgo.
- Sigue vigente: no commitear sin que lo pida (de ahí el marcador con `git stash create` en vez de un commit por turno).

### Antes de editar código

- **Regla del espejo**: `slice-review/SKILL.md`, `review-loop/SKILL.md` y `review-loop-trigger.ps1` **no** están en la allowlist de `tests/mirror.tests.ps1` → cada cambio va idéntico a las 3 skills bootstrap **y** a la copia del propio repo (4 copias). `assets/scaffold/CLAUDE.md` **sí** está en la allowlist → los 3 divergen y se editan por separado.
- El `.bootstrap-manifest.json` es generado: regenerarlo con `tools/gen-manifest.ps1` (o `tools/sync-skills.ps1`) antes de commitear.
- El hook `alignment-gate` bloquea la primera edición de código de cada sesión: es un speed-bump, ya se cumplió el paso 1 en esta sesión pero la nueva no lo sabe.

---

# Session Handoff — 2026-08-01 (fix: el review-loop no podía cerrarse solo)

## ▶▶ ESTADO AL RETOMAR (sesión 2026-08-01)

Rama **`fix/review-loop-motor-invocable`**, commit **`8cc6e9e`**, working tree limpio. **Sin mergear a `main` y sin pushear.**

**El bug:** el built-in `/code-review` está marcado `disable-model-invocation` — solo lo puede tipear un humano (`Skill code-review cannot be used with Skill tool`). Era el paso 1 del `review-loop`, así que **el loop nunca podía cerrarse solo**: el hook `review-loop-trigger` ordenaba en cada commit algo imposible de cumplir, y un slice podía terminar reportado como "revisado" sin reviewer. Lo detectó Martín en `C:\Repos\Outsourcing Development`, pero la causa estaba en el scaffold: lo heredaban todos los proyectos bootstrapeados.

**El fix:** nuevo comando **`/slice-review`** (command + SKILL.md, espejado en las 3 skills bootstrap y en el propio repo) — reviewer multi-agente sobre el diff **local**: reviewers en paralelo (bugs, reglas del CLAUDE.md, historia del código, contratos/callers, tests) + pase de confianza 0-100 que descarta findings < 60. Los comandos custom **sí** son invocables por el modelo; ese es todo el truco. `tests/slice-review.tests.ps1` blinda la regresión (verificado que falla al revertir el paso 1). Suite: **10/10 verde**. Manifests regenerados + manifest del repo resellado.

**Pendientes de esta sesión, en orden:**

1. **`/review-loop` sobre `main...HEAD`** — este diff **todavía no pasó por ningún reviewer**. No darlo por revisado.
2. **Merge a `main`** una vez limpio (y push con cuenta `southpointtech`; MartinDele703 da 403 acá).
3. **`tools/sync-skills.ps1`** — hasta que no corra, un bootstrap nuevo sigue instalando la versión rota.
4. **Outsourcing Development**: ya tiene el fix aplicado a mano y funcionando. Después del deploy conviene correr `upgrade-bootstrap` ahí para que el manifest selle esos archivos como canónicos en vez de marcarlos "customized".
5. **Resto de proyectos bootstrapeados** (Forecasting App, etc.): necesitan `upgrade-bootstrap`.

Reapareció el bug conocido de `core.autocrlf` (los archivos nuevos quedaron LF en el working tree, CRLF en el próximo checkout) — los hashes de los manifests siguen sin normalizar. No se tocó en esta sesión.

## ▶▶ PRIORIDAD ANTERIOR — SIGUE PENDIENTE (2026-07-06, nueva terminal)

El usuario quiere que le **expliques la auditoría del scaffold en lenguaje llano, conversando**, no que sigas con implementación. El documento técnico le resultó demasiado técnico. Arrancá así:

1. Leé `docs/superpowers/notes/2026-07-06-auditoria-EN-CRIOLLO.md` (versión sin jerga) — es tu guion.
2. Explicale de forma charlada, empezando por lo urgente (las **2 claves/secretos expuestos** en `Linkedin` y `Project Management Migration` → rotar) y siguiendo por las mejoras que más rinden. NO uses jerga técnica (hashes, autocrlf, manifests, rutas de archivo) salvo que él lo pida.
3. Dejá que él pregunte y priorice. Recién cuando elija qué mejora quiere, ahí sí entrás al flujo `grill-me → PRD → slices`.
4. El backlog técnico completo (evidencia file:line, leak-scrub, archivo exacto) está en `docs/superpowers/notes/2026-07-06-auditoria-mejoras-scaffold.md` — usalo solo como respaldo si él quiere el detalle.

La feature del bootstrap compartible YA está terminada y mergeada (ver abajo). Salvo que él lo pida, no hay que tocar código todavía.

## ▶ AL RETOMAR — estado y qué hacer

Rama: **`main`**, working tree limpio. El plan del bootstrap compartible está **ejecutado completo** (3 slices + eval). Commits locales **sin pushear** a `origin/main` (pushear con cuenta `southpointtech` cuando se quiera).

**Lo único que NO puedo hacer yo (requiere al usuario):**
1. **Push de `main`** a origin (cuenta `southpointtech`; MartinDele703 da 403 en este repo).
2. **Export real al repo público**: crear `MartinDele703/ai-project-bootstrap` en GitHub → clonar → `pwsh -NoProfile -File tools/export-shareable.ps1 -PublicRepoDir <clon>` → revisar diff → commit/push con cuenta **MartinDele703**.

## Qué se hizo esta sesión (2026-07-06)

Ejecuté `docs/superpowers/plans/2026-07-06-bootstrap-compartible.md` con `superpowers:subagent-driven-development` (implementer + task-review por task, review-loop por slice, whole-branch review final). Todo mergeado a `main` por fast-forward:

- **Slice 1 — `feat/scaffold-english`** (`dd27ab9..77b01ae`): anglicización de la prosa del scaffold canónico en las 2 skills (review-loop docs/comando, hooks, bullets de CLAUDE.md, issue-tracker, copy-scaffold). Nuevo `tests/mirror.tests.ps1` (guard de espejado). Fix typo `proceds→proceed`. Triggers `description:` español intactos (bilingües).
- **Slice 2 — `feat/bootstrap-ai-project`** (`8df1b98..35b194e`): tercera skill `skills/bootstrap-ai-project` (copia de personal + 6 divergentes genericizados). `tools/leak-markers.txt` + `tests/shareable-leaks.tests.ps1`. `upgrade-bootstrap` genericizado (publicable). CLAUDE.md raíz: regla de espejado 2→3 skills.
- **Slice 3 — `feat/export-shareable`** (`4d30449..a2313ee`): `tools/export-shareable.ps1` (copia limpia + gate anti-fuga) + `public/README.md` + `public/install.ps1` + `tests/export-shareable.tests.ps1`.

**Fixes surgidos en los review-loops (más allá del plan):**
- `tools/gen-manifest.ps1`: `variant` derivado del nombre (`bootstrap-ai-project`→`ai`; antes la heurística binaria lo dejaba `personal`).
- `tests/mirror.tests.ps1`: hashea contenido **normalizado** (CRLF/CR→LF), robusto ante `core.autocrlf` (antes daba RED espurio).
- `tools/export-shareable.ps1`: regenera el manifest **en el clon**, no en el repo fuente (ya no ensucia el working tree al correr el test).

**Eval descartable (Task 12): PASÓ.** Deploy con `sync-skills` OK. Bootstrap de un proyecto temporal como tercero: 10 skills, hooks en inglés (`NOW`/`proceed`), `.gitignore` mapeado, `gitignore.txt` ausente, identidad git NO seteada por la skill, `CLAUDE.md` genericizado ("your issue tracker"), **0 marcadores de fuga**. Proyecto borrado.

Suite completa (9 archivos en `tests/`): toda verde.

## Follow-up técnico DESCUBIERTO (pendiente, su propia tarea)

`core.autocrlf=true` + archivos que llegan por vías distintas (checkout=CRLF, Write de agente=LF) → los `.bootstrap-manifest.json` **commiteados tienen hashes mixtos LF/CRLF**. Consecuencia: `sync-skills.ps1` y `export-shareable.ps1` regeneran y dejan los 3 manifests modificados en **cada corrida** (fricción del flujo normal). NO es un leak; el export se auto-sana (regenera en el clon). **Fix sugerido:** `.gitattributes` normalizando el repo (`* text=auto eol=lf` o marcar el scaffold) + `git add --renormalize` + regenerar los 3 manifests + commitear. Blast radius alto → merece brainstorm + review propio, no apurarlo. (mirror ya quedó inmune vía hash normalizado.)

## Auditoría de mejoras al scaffold (frente de mayor valor — COMPLETA)

Auditoría de ambos árboles (`C:\Repos\PERSONAL` — 8 repos; `C:\Repos\SOUTHPOINTLABS` — 7 repos) + skills user-level + los 2 findings del whole-branch review. **Backlog priorizado y de-riesgado en `docs/superpowers/notes/2026-07-06-auditoria-mejoras-scaffold.md`** — NO implementado (alimenta grill → PRD → slices; Martín decide). Highlights:

- **A1 (correctness, el más importante):** hashing normalizado en `gen-manifest`/`compare-scaffold`/`reseal-manifest` — hoy hashean bytes crudos → bajo autocrlf rompen la comparación de `upgrade-bootstrap` para consumidores del repo público + ensucian los manifests en cada `sync`/`export`. Su propia mini-feature con test (patrón ya usado en `mirror.tests.ps1`). Ver [[bug-autocrlf-manifests-hashes-mixtos]].
- **Quick wins (convergen en ambos árboles):** hard rule "secretos con `${ENV_VAR}`, nunca literales" (se encontraron 2 secretos reales hardcodeados: `Linkedin/.mcp.json`, `Project Management Migration` — **rotar aparte**); Firebase MCP en el catálogo de personal/southpoint; doc de convención `skills-lock.json`; "definition of tested" en QA_CHECKLIST.
- **Bundlear:** `verify-downstream-arrival` + `debug-source-first` (con scrub de secciones DOMO).
- **Templates:** runbook `[CLAUDE]`/`[HUMANO]`, decision-log de stakeholders, estimation-guide (scrub alto), design-master-prompt.
- **Sistémico:** drift del scaffold — pasada de `upgrade-bootstrap` por repos viejos (la mayoría sin `alignment-gate`).
- **NO bundlear:** `scaffold-e2e-suite` (pesada), `bootstrap-multistage-project` (compite + leaks) — minar 2 ideas: sección branching-model + convención de nombres fechados.

**Además, cierre de calidad post-review (commiteado en `main`):** traducción de prosa/comentarios español residuales en las skills publicadas (`bootstrap-ai-project/SKILL.md:87` + comentarios de los 3 scripts de `upgrade-bootstrap`) que se colaban por los gates automáticos.

## Reglas del repo (no olvidar)

- Editar skills acá NO tiene efecto hasta `tools\sync-skills.ps1`.
- Manifest generado, nunca a mano (`tools/gen-manifest.ps1`). Rastros de testeo se borran.
- Identidad git local de ESTE repo: MartinDele703; push a origin: solo `southpointtech`.
- Ahora son **TRES** skills espejadas; `tests/mirror.tests.ps1` (contenido normalizado) + `tests/shareable-leaks.tests.ps1` lo verifican.
- Commits español conventional (`feat/docs/test/fix(...)`).
