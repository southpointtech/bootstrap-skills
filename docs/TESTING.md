# Cómo testear las skills

Las skills se testean con el **skill-creator** (`/skill-creator:skill-creator` en Claude Code), que orquesta: runs con skill + baseline en directorios temporales → grading con assertions → benchmark → viewer HTML para revisión humana.

## Test cases canónicos (re-usar estos)

1. **Southpoint, directorio vacío** — "Acabo de crear esta carpeta para un proyecto nuevo de Southpoint: un tablero de inventario para KBS (se llama 'KBS Inventory'). Dejame el directorio listo con todos los archivos base para arrancar, como hicimos en Forecasting App."
2. **Personal, directorio vacío** — "ok arranco un proyecto personal aca, una app para trackear mis gastos del mes. preparame el ambiente y el repo con el setup base antes de escribir nada de codigo"
3. **Southpoint, archivos preexistentes** — sembrar `src/index.js` y un `README.md` propio ("WIP - notas propias del proyecto") y pedir: "Este repo ya tiene un par de archivos del proyecto nuevo de Southpoint (KBS Inventory). Armame el scaffolding del workflow de AI sin romper lo que ya hay."
4. **Southpoint, adopción (CLAUDE.md propio sin manifest)** — sembrar un `CLAUDE.md` hecho a mano (branching model main/develop + un gotcha técnico + una mención a DOMO) y un `worker.js`, sin `.bootstrap-manifest.json`, y pedir: "agregale el bootstrap a este proyecto". Debe entrar en **modo adopción** (Step 0b), no frenar ni derivar a upgrade-bootstrap.
5. **Adopción, re-corrida sobre un proyecto ya adoptado** — partir del árbol que dejó el caso 4, borrar el `.bootstrap-manifest.json`, editar una línea del `CLAUDE.md` vivo y volver a pedir: "agregale el bootstrap a este proyecto". Ejercita la rama que protege el original de un `Move-Item -Force`; sin este caso el eval nunca la toca.
6. **Adopción, colisión de nombre** — sembrar un `CLAUDE.md` propio Y un `docs/agents/legacy-claude.md` que NO sea el original del proyecto (dos líneas de cualquier otra cosa), sin manifest, y pedir el bootstrap. Es la rama donde el agente no puede decidir solo, y la única que ni el runner ni los otros casos tocan. **Cuando la corrida pregunte, responder que el original es el respaldo** (`.bootstrap-backup/CLAUDE.md`): la respuesta va fijada acá a propósito, porque el step B ofrece dos candidatos y el observable de abajo cambia según cuál se elija.
7. **Adopción, el usuario no sabe cuál es el original** — igual que el caso 6, pero sembrando además un `.gitignore` propio con dos entradas que el scaffold no trae, y respondiendo **"ninguno de los dos es mi original"**. Es la otra respuesta que el step B admite, y la única que ejercita el camino donde se saltea la clasificación **pero igual hay que aplicar el mapa**: cuando la corrida presente la fila del `.gitignore`, aprobarla como **merge**.

## Assertions clave (lo que define "pasa")

- Scaffold completo: CLAUDE.md (8 pasos + Workflow State Machine), 5 docs ai-workflow, 11 skills `.agents` (9 de mattpocock vía `skills-lock.json` + `review-loop` y `slice-review` propias), 11 comandos `.claude`, 3 docs agents, `.gitignore` (con `.scratch/`), `skills-lock.json`, `.bootstrap-manifest.json`, `.claude/settings.json`, `.claude/hooks/review-loop-trigger.ps1`, `.claude/hooks/alignment-gate.ps1`, README, CONTEXT.md stub, `docs/adr/`. Los conteos se verifican contra el scaffold, no contra estos números.
- Variante correcta: Southpoint menciona DOMO; personal CERO menciones a DOMO pero conserva Playwright/Firebase/Azure/Zoho.
- Git: branch `main`, **un solo commit**, autor exacto según variante, config local (global intacta).
- Sin duplicados anidados (`.agents\.agents`, `.claude\.claude`) — regresión del bug de iter 1.
- No se adelanta: sin package.json, sin src/ (en dirs vacíos), sin ADRs inventados, sin PRD.
- Preexistentes intactos byte a byte y commiteados — **salvo** los que el scaffold también trae: esos se pisan, con el original respaldado en `.bootstrap-backup/` y declarado en `overwritten` (ADR-0007).
- Modo adopción: `docs/agents/legacy-claude.md` existe y es **byte-idéntico** al `CLAUDE.md` original sembrado.
- Modo adopción: el `CLAUDE.md` final es el canónico (contiene "Workflow State Machine"); las reglas operativas del original aparecen en su sección `## Hard rules`; el conocimiento de dominio del original aparece en `docs/agents/domain.md`.
- Modo adopción: cada bloque del original quedó representado (en `legacy-claude.md` + su destino); ningún bloque se perdió en silencio.
- Modo adopción: tras adoptar, `compare-scaffold.ps1` clasifica `CLAUDE.md` como **customized** (ni `outdated` ni `uptodate`), confirmando que un upgrade futuro no lo pisa.
- Modo adopción, **re-corrida** (caso 5): el `docs/agents/legacy-claude.md` de la primera corrida queda **byte-idéntico** (el Step B no lo pisa) y el respaldo del `CLAUDE.md` vivo que la copia acaba de pisar existe en `.bootstrap-backup/`. Va al path **sin numerar**, no a `.2`: el `Move-Item` de la primera corrida vació ese slot. Las dos cosas se observan sobre el árbol; que ese respaldo haya recibido fila en el mapa de cobertura se verifica en la transcripción.
- Modo adopción, **colisión de nombre** (caso 6): la corrida **frena y pregunta** cuál es el original, en vez de clasificar el archivo ajeno. Ese comportamiento se verifica **en la transcripción**, y no de cualquier forma: la pregunta tiene que nombrar los dos candidatos (`docs/agents/legacy-claude.md` y `.bootstrap-backup/CLAUDE.md`) diciendo cuál existe, y el mapa de cobertura no puede aparecer antes de la respuesta. Sobre el árbol, **con la respuesta que el caso 6 fija** (el original es el respaldo): `docs/agents/legacy-claude.original.md` existe, es byte-idéntico al `CLAUDE.md` sembrado (el respaldo no se siembra: lo produce la corrida bajo prueba, así que compararlo contra él sería comparar una salida contra otra) y **aparece en `git ls-files`** — el Step 5 stagea con `':!.bootstrap-backup'`, así que un archivo que solo viva ahí no está preservado y el commit es el observable correcto —, y el `legacy-claude.md` ajeno sigue byte-idéntico.
- Modo adopción, **el usuario no sabe** (caso 7): el observable es el `.gitignore`, no el `CLAUDE.md`. Sobre el árbol, las dos entradas propias que se sembraron **siguen en el `.gitignore` final** junto a las del scaffold — o sea que el "merge" aprobado se aplicó de verdad. Es el único caso que distingue "se salteó la clasificación" de "se salteó también el mapa": si el step E se saltea entero, el `.gitignore` queda con las reglas del scaffold solas y las del proyecto solo en `.bootstrap-backup/`, que el Step 5 no commitea. En la transcripción, además: nada quedó clasificado y el reporte lo dice sin afirmar que no existía un original.
- Dos criterios que NO sirven para el caso 6: que el archivo sembrado siga intacto (el scaffold no trae ese path, así que la copia no lo toca por ninguna rama) y la ausencia de líneas del archivo ajeno en `## Hard rules` (la satisface también el agente que crashea o que nunca entra en adopción; y con la otra respuesta posible esas líneas aterrizan ahí por el camino **correcto**).

## Gotchas operativos del entorno de testing

- Los agentes baseline en el entorno de Forecasting App pueden copiar del repo real → baseline inflado; correr los tests desde un cwd neutro si se quiere baseline puro.
- El viewer (`generate_review.py`) en Windows necesita `$env:PYTHONUTF8 = "1"` (crash cp1252 si no).
- El agregador (`scripts.aggregate_benchmark`) espera `eval-N/<config>/run-1/grading.json` y un bloque `summary` `{pass_rate, passed, failed, total}` en cada grading.
- Si un run baseline corre `npm install`, borrar su `node_modules` antes de levantar el viewer (el escaneo recursivo se cuelga).
- Borrar el workspace de evals al terminar (regla del repo).

## Workspaces temporales de las suites (`tests/lib/temp-workspace.ps1`)

Ninguna suite crea temporales por su cuenta: todas cuelgan de una raíz única por corrida que
entrega el helper. `tests/temp-hygiene.tests.ps1` lo verifica y se pone rojo si alguna lo esquiva.

Para una suite nueva, son tres líneas y una al final:

```powershell
. (Join-Path $PSScriptRoot "lib\temp-workspace.ps1")
$script:runRoot = New-TestRunRoot "<prefijo>"
trap { Remove-TestRunRoot $script:runRoot; break }
# ... $t = New-TestWorkspace $script:runRoot "caso"   /   $p = New-TestTempPath $script:runRoot "cfg" ".json"
Remove-TestRunRoot $script:runRoot
```

El trap se escribe **en una línea y siempre igual**: el lint lo verifica exacto, porque un regex
laxo sobre un bloque multilínea acepta un trap que atrapa y no borra. Y no puede vivir dentro del
helper: un `trap` queda atado al frame que lo ejecuta, y el del helper termina cuando el
dot-source vuelve.

Por qué las tres partes hacen falta, y qué pasa si falta cada una:

| parte | qué cubre | qué se filtra sin ella |
|---|---|---|
| raíz única por corrida | la salida normal | lo que un camino intermedio no alcanzó a borrar |
| `trap` | el aborto por error terminante | **todo** el árbol, cada vez que un error saltea la limpieza final |
| recolección **por edad** | lo que el trap no alcanza | lo que dejan un `exit` temprano, un Ctrl+C, un proceso matado y un borrado que falló |

La tercera **no es opcional**: el `trap` sólo corre en errores terminantes, así que un `exit`
temprano (`review-marker.tests.ps1` tiene uno si falta el script del marcador), un Ctrl+C o un
`pwsh` matado dejan la raíz en disco, y la recolección por edad es lo único que la junta después.
Y su filtro de fecha es igual de obligatorio: sin él es un glob incondicional que borra los
fixtures **en uso** de las corridas concurrentes, que en este repo son la norma porque el
review-loop lanza reviewers en paralelo. `export-shareable.tests.ps1` lo hacía.

Usa `LastWriteTime`, no `CreationTime`: crear un hijo actualiza el `LastWriteTime` del padre
(medido), así que una corrida viva y larga se rejuvenece sola, mientras que un huérfano de verdad
no se toca más y envejece igual. Con `CreationTime` una corrida de más de un día se borraba a sí
misma los fixtures en pleno uso.

**Verificación de aceptación** (2026-09-01, tras migrar las 8 suites): correr las 15 suites y contar
**archivos y directorios** en la raíz de `%TEMP%` antes y después. Delta de rastros de suite = **0**.
Contar solo directorios no sirve: `apply-env` deja archivos (`wscfg-*.json`, 34 medidos), y ese fue
justamente el error que hizo fallar el primero de los tres intentos manuales de arreglar esto.

Dos precisiones sobre esa medición, para quien la repita y crea que la rompió:

- **Hay una ventana de borrado pendiente.** En Windows un `Remove-Item` sobre un árbol cuyo handle
  todavía sostiene otro proceso queda pendiente: medido, `review-loop-docs-gate.tests.ps1` dejaba su
  raíz en disco en 3 de 3 corridas verdes porque el proceso de fondo de git seguía con el `.git` del
  fixture abierto, y el árbol desaparecía segundos después. `Remove-TestRunRoot` reintenta una vez y
  avisa con un `Write-Warning` si aun así queda; contado inmediatamente después de esa suite, el
  delta puede dar +1 sin que nada esté roto.
- **Los rastros LEGACY no se recolectan solos.** El colector busca `<prefijo>-run-*` y sólo
  directorios, así que los nombres viejos (`mcp-test-*`, `export-test-<guid>`, `cs-test-*`, y los
  **archivos** `wscfg-*.json`) quedan fuera de su alcance para siempre. Se barrieron a mano una vez
  en esta máquina (112 el 2026-09-01); en otro clon siguen ahí. **No agregar un glob incondicional
  para "arreglarlo"** — es el bug que este trabajo sacó. Barrelos a mano si molestan.

## El golden del Step 0b

La mecánica del modo adopción está congelada en `tests/fixtures/step0b.golden.md`, y `mirror.tests.ps1`
compara contra él el tramo `## Step 0b` → `## Step 1` de las tres skills. **Cualquier** edición de ese
tramo pone la suite en rojo: es a propósito, porque esa prosa es un procedimiento que un agente ejecuta
sobre el `CLAUDE.md` de un proyecto ajeno, y un chequeo de presencia sobre texto no distingue una orden
de su negación (medido: `apply the map first` lo satisfacía igual el texto que decía `do NOT apply the
map first`). El ciclo es:

1. Editar el Step 0b en `skills/bootstrap-ai-project/SKILL.md`.
2. Propagar el bloque entero a las otras dos (no editar tres veces a mano).
3. `tools/reseal-step0b.ps1` — frena si las tres no coinciden, así que sellar es también el chequeo
   de espejado. `-Check` no escribe nada y sale 1 si el golden quedó desactualizado.
4. Commitear el golden **junto con** las skills. Un golden regrabado y no commiteado pasa verde local
   y rojo en el próximo clone.

El paso 3 es donde un humano mira `git diff tests/fixtures/step0b.golden.md` y decide. Regrabar sin
mirar el diff es la única forma de sellar un bug, y por eso el golden no se edita a mano nunca.

## Testeo de `upgrade-bootstrap`

La skill que actualiza proyectos ya bootstrapeados se testea con fixtures (no con skill-creator), porque su lógica vive en los scripts `compare-scaffold.ps1` y `reseal-manifest.ps1`. Casos de regresión:

1. **Manifest + desactualizado-no-tocado** — proyecto con `.bootstrap-manifest.json` y un archivo cuyo hash actual == base pero != canónico → debe clasificar `outdated` (seguro de actualizar).
2. **Manifest + personalizado** — archivo cuyo hash actual != base → debe clasificar `customized` (no pisar).
3. **Legacy sin manifest** — proyecto bootstrapeado con la versión vieja (sin manifest): `hasProjectManifest=False`, detecta `missing` (los 2 de `review-loop`, y ahora también `.claude/hooks/alignment-gate.ps1`) y `customized` los que difieren; tras aplicar, siembra el manifest.
4. **Al día** — proyecto recién bootstrapeado: `missing/outdated/customized` vacíos, `uptodate` == 48.

Los fixtures determinísticos para los casos 1-2 y el re-sellado están en el plan `docs/superpowers/plans/2026-06-10-upgrade-bootstrap-skill.md` (Tasks 4-5); los casos 3-4 corren contra el scaffold instalado (Task 8).

## Testeo de la copia del scaffold (`copy-scaffold.ps1`)

La copia del Step 2 (`skills/*/scripts/copy-scaffold.ps1`, espejada en las **tres** skills bootstrap) se testea con un runner sin Pester: `pwsh -NoProfile -File tests/copy-scaffold.tests.ps1` (fixtures en directorios temporales, imprime `TODOS LOS TESTS PASARON` o `N test(s) FALLARON`). Los conteos se afirman **contra el scaffold**, nunca contra un literal: un número escrito acá envejece la próxima vez que entra una skill. Casos cubiertos:

- **Destino vacío** — aterriza el scaffold completo, sin `.agents/.agents` ni `.claude/.claude`, `gitignore.txt` → `.gitignore` con contenido idéntico, y `.agents/skills` / `.claude/commands` con tantas entradas como el scaffold.
- **Regresión `docs/docs`** — `docs/` y `docs/agents/` preexistentes en el proyecto → el contenido se mergea (sin anidar) y los archivos propios quedan intactos (gotcha del self-bootstrap 2026-06-23).
- **Dot-dirs preexistentes** — `.claude/` con archivos propios → merge sin anidar ni pisar lo ajeno.
- **Conflicto de archivo** — un `CLAUDE.md` preexistente es reemplazado por el canónico (semántica deliberada del Step 2; el original queda en `.bootstrap-backup/`, que es de donde el Step 0b lo toma **mientras no exista ya un `docs/agents/legacy-claude.md`** — si existe, el Step 0b parte de ése, y solo frena a preguntar cuando está vacío o es ajeno).
- **Paths con corchetes** — un proyecto `...[v2]` copia igual (paths literales, sin interpretación de wildcards) y respalda igual.
- **Respaldo y reporte** (ADR-0007) — un archivo propio que difiere se respalda en `.bootstrap-backup/<mismo path>` y se declara en `overwritten`, con el `backup` apuntando al subpath completo; el respaldo más viejo no se pisa y la versión posterior se guarda al lado (`.2`); un archivo ajeno al scaffold no se toca, no se respalda ni se declara; con destino vacío no se crea el directorio.
- **Ruido de EOL** — una diferencia de solo CRLF vs LF no cuenta como pisada, en las dos direcciones, con el fixture escrito explícitamente (no derivado del checkout, que depende de `core.autocrlf`).
- **Comparación por bytes** — un archivo del mismo largo con distinto contenido, y uno que difiere solo por el BOM, sí se declaran pisados: la comparación normaliza EOL sobre los bytes y no decodifica a texto.
- **Espejado** — los **tres** `copy-scaffold.ps1` son byte-idénticos (hash SHA256).

Cada workspace temporal cuelga de un directorio único por corrida (`cs-run-<pid>-<guid>`) y solo se borra ése: la limpieza vieja barría todo `cs-test-*` del TEMP compartido y mataba los fixtures de cualquier corrida concurrente — pasa de verdad con los reviewers en paralelo del review-loop.

## Testeo del motor del review-loop (`/slice-review`)

El paso 1 del loop tiene que ser **invocable por el agente**. `/slice-review` es la columna del motor porque hace cumplir las Hard rules del `CLAUDE.md`, reparte la revisión en focos paralelos, filtra con un pase de confianza y corre un pase de coherencia al cierre — nada de lo cual da el built-in `/code-review`, y todo sobre el diff local sin PR ni remoto. (La vieja premisa de que `/code-review` "no era invocable por el agente" **caducó**: verificado el 2026-08-26, es invocable incluso desde un subagente — ver `docs/adr/0003-code-review-como-foco-acotado.md`. Por eso el turno 1 del loop ahora lo **suma** como reviewer independiente, ver el foco de code-review abajo.) Runner: `pwsh -NoProfile -File tests/slice-review.tests.ps1`. Casos cubiertos, en las tres skills bootstrap:

- **Existencia del par** — `.claude/commands/slice-review.md` y `.agents/skills/slice-review/SKILL.md` presentes.
- **Invocabilidad** — ambos declaran `description` en el frontmatter y **ninguno** setea `disable-model-invocation: true`.
- **El motor del loop** — `review-loop` (command y SKILL.md) corre `/slice-review` como paso numerado. El assert no fija el número: desde el turno incremental el paso 1 es pedirle el rango al marcador y la corrida de review es el paso 2. Lo que se blinda es el motor, no su posición.

### Foco de code-review — ensemble (08a)

El guard viejo ("ningún archivo *ordena* correr `/code-review`") **se invirtió**: la premisa de no-invocabilidad caducó y el motor ahora suma `/code-review` como un reviewer independiente más, acotado. Los asserts (en `tests/slice-review.tests.ps1`, sobre las cuatro copias del par `slice-review`) blindan esa mecánica:

- **Sección propia** — existe `## Code-review focus` en el prompt de `/slice-review`.
- **Acotado al turno 1** — el foco declara que corre **solo en el turno 1** (`only on the loop's first turn`) y está **prohibido en los turnos 2+** (`prohibited on turns 2`), simétrico con el foco de mutación.
- **Esfuerzo medium** — el foco corre a `medium effort` (acotado, no high/max), para no volverse la lane más lenta ni dentro del slack del turno 1.
- **Invocación y flag** — el foco invoca el built-in `/code-review`; Step 1 parsea `--code-review` y Step 4 lo despacha condicional a ese flag (`/review-loop` lo pasa junto a `--mutation` en el turno 1).
- **Framing coherente** — el doc del par **ya no** afirma que `/code-review` es human-only (`-notmatch 'restricted to human invocation'`); dejar la vieja frase dejaría el slice internamente incoherente con la mecánica que lo invoca.
- **Dedup** — Step 5 dedupea los hallazgos de `/code-review` contra el foco de bugs (`de-duplicate`/`dedup`), por **defecto subyacente** (`underlying defect`), no solo `file:line` exacto.
- **Fork join** — el foco espera y junta los hallazgos del fork async **antes** de Step 5 (`collect its findings before`), o el reporte se emitiría con el fork todavía corriendo.
- **Read-only** — se invoca `/code-review` en solo lectura, **nunca** con `--fix` (`never with --fix`): corre en el árbol real compartido y `--fix` lo mutaría.
- **Scope aceptado** — `/code-review` revisa el `working-tree diff` (no toma el stash ref del marcador), que puede ser más amplio que el delta; el dedup + la confianza lo absorben.

## Testeo de la corrida de review incremental (A3)

A3 hizo que el objetivo por defecto de `/slice-review` (sin args) sea el **delta sin revisar** resuelto del marcador, no la vieja cascada working-tree/branch. El contenido del prompt se verifica en `tests/slice-review.tests.ps1` sobre las **cuatro copias** (repo + 3 skills bootstrap), en los dos artefactos de cada ubicación (command para el humano + SKILL.md para autodescubrimiento), que comparten el cuerpo. Casos cubiertos:

- **Objetivo por defecto** — sin args, el default es el delta sin revisar (`review-marker.ps1 -Action range`); el rango completo del slice queda **reservado al pase de coherencia**, no es el default.
- **Delta vacío** — con delta vacío (exit 0) reporta "nada que revisar" (`everything up to the marker was already reviewed`) en vez de inventar un rango.
- **Prohibición de escritura** — la prohibición (`reviewer, not an editor`) viaja en el contexto compartido y aparece **exactamente una vez**.
- **Modelo por foco** — reglas e historia declaran **el modelo más liviano y rápido** (`a lighter, faster model`); bugs, contratos y tests declaran **el modelo más capaz disponible** (`the most capable model available`), sin pin de versión (ver la sección de la migración a ruteo agnóstico).
- **Pase de confianza** — corre en **el modelo más capaz disponible**, con la misma rúbrica y el corte en **60** (`Drop everything below 60`).
- **Reporte** — sigue diciendo cuántos hallazgos descartó la confianza y qué rango se revisó (regresión de AC6).
- **Script del marcador ausente** — se maneja pre-flight con `Test-Path`, no se mete en el bucket de exit 2 (`pwsh -File <missing>` sale 64 con usage a stdout, no exit 2 + vacío); su recuperación cae al branch range del slice.
- **Contrato de exit 2** — separa "no es repo git / sin commits" (reportar y parar, sin llamar `git show HEAD` que falla sin commits) del caso base-indeterminable; la rama de recuperación queda pinneada (`exit 2 + empty`).
- **Recuperaciones no incrementales** — tanto el script ausente como el exit-2 base-irresoluble declaran que la corrida **no es incremental** (conteo ≥ 2); en base irresoluble no se arrastra `git diff <base>...HEAD` (la base es justo lo irresoluble): working tree, si no el último commit.

## Testeo del pase de coherencia (A4)

A4 agregó un pase de coherencia: un foco **único de solo lectura** que mira el **slice entero** una sola vez, al cierre, contra la intención declarada. La mecánica vive en `/slice-review` y la invoca `/review-loop` al cerrar. Se verifica en `tests/slice-review.tests.ps1`, anclado a la **sección** del pase (`## Coherence pass`), no al archivo entero (la cadena "coherence pass" ya aparece en A3, así que un match suelto pasaría sin la sección nueva), sobre las 4 copias. Casos cubiertos:

- **Sección propia** — foco único de solo lectura (`single read-only focus`) sobre el rango completo del slice (`full slice range`).
- **No ejecuta nada** — lo declara explícitamente (`executes nothing`).
- **Intención declarada** — lee el slice contra su intención declarada: la tarea, el PRD o el mensaje de commit que implementa.
- **Modelo** — corre en **el modelo más liviano y rápido** (`a lighter, faster model`), anclado a la sección del pase (ver la sección de la migración a ruteo agnóstico).
- **Pase de confianza** — sus hallazgos pasan por el mismo pase de confianza que cualquier otro (`same confidence pass`).
- **Invocación** — se dispara con `/slice-review --coherence`; Step 1 rutea `--coherence` a la sección del pase, no como un rango de diff.
- **No saltea steps reusados** — el ruteo de `--coherence` no manda a saltear los steps que el pase reusa (Step 3 contexto compartido, Step 5 confianza, Step 6 reporte): un `skip Steps 1-5` haría que un agente literal saltee la confianza (AC6).
- **Base irresoluble** — en exit 2 la base es justo lo irresoluble: la frase `do not reach for` vive DENTRO de la sección del pase, no solo en el Step 1.
- **El loop lo invoca al cierre** — verificado en `/review-loop` (command + SKILL, 4 copias), sección `## At close: the coherence pass`: invoca `/slice-review --coherence` en **ambos** cierres (limpio o por el techo de 5 turnos) y lo saltea solo cuando ningún reviewer corrió (rango vacío desde el primer turno).

## Testeo del anclaje del pase de coherencia (A4b)

En una rama con slices **apilados**, la base de rama sobre-scopea la coherencia a toda la rama; A4b la ancla en el **inicio del slice que cierra**. Suma dos verbos al marcador — `open` (captura el punto de arranque del slice en el turno 1) y `slice-base` (resuelve ese punto) — verificados en `tests/review-marker.tests.ps1`, y fija el orden del turno en `tests/review-loop-incremental.tests.ps1`. Casos cubiertos.

En el marcador (`review-marker.tests.ps1`):

- **`slice-base` ancla en el inicio del slice** — devuelve el marcador capturado por `open` (el cierre del slice anterior), no la base de rama. En una rama apilada, `slice-base` lee solo el slice que cierra (`s2.txt`, no `s1.txt`), mientras `base` sigue devolviendo la base de rama (la rama entera). El tracer prueba las dos mitades a la vez: slice-base ajustado, base intacto (medido en el fixture del diseño: 9613/56 con base de rama vs 248/5 con slice-base).
- **`open` sólo escribe `slice-open`** — no avanza el marcador (`marker:<rama>` intacto: si lo avanzara, el próximo `range` no vería delta y cerraría el slice sin revisar) y no pierde las otras claves del estado (preserva el dedupe del hook de nombre pelado y las `untracked:` de otras ramas). Registra el marcador como `slice-open:<rama>`.
- **Primer slice de la rama** — sin marcador previo, `open` no deja un `slice-open` espurio y `slice-base` cae a la base de rama.
- **`slice-open` irresoluble** — si un rebase o `git gc` dejó el snapshot sin resolver, `slice-base` lo ignora y cae a la base de rama (la dirección segura: revisar de más, nunca un diff con hunks fantasma contra un ref muerto).
- **Sin base determinable** — `slice-base` sale con **exit 2**, no 0 (exit 0 vacío cerraría la coherencia sobre un slice que nadie ancló).

En el orden del turno (`review-loop-incremental.tests.ps1`):

- **`-Action open` en el turno 1** — el turno 1 captura el inicio del slice con `open`, y el orden verificado por posición en las 4 copias es range → open → advance (open snapshotea el marcador tal como está, el advance recién lo mueve).

## Testeo de la limpieza del ancla de coherencia (A4c)

Cuando un slice cierra **limpio**, el ancla `slice-open` se borra para que el slice siguiente arranque fresco; un cierre por **cap** la conserva, para que una re-corrida del mismo slice sin cerrar siga anclando en su arranque real en vez de under-scopear (hallazgo B de A4b, `docs/adr/0002-limpieza-del-ancla-de-coherencia.md`). Suma un **séptimo verbo** al marcador, `close`, verificado en `tests/review-marker.tests.ps1`, más la prosa del cierre en `tests/review-loop-incremental.tests.ps1`. Casos cubiertos.

En el marcador (`review-marker.tests.ps1`):

- **`close` borra `slice-open`** — elimina `slice-open:<rama>`, sale con **exit 0** y no avanza ni toca `marker:<rama>`.
- **`open` es write-once** — con un `slice-open` ya fijado y resoluble, un `open` posterior (una re-corrida de un slice que capeó sin cerrar, con el marcador ya avanzado) **no** re-snapshotea: el ancla queda en el arranque real del slice, matando el under-scope (la dirección peligrosa).
- **`open` write-once sobre un ancla IRRESOLUBLE** — con un `slice-open` presente pero que ya no resuelve (podado por `gc` / reescrito por rebase), `open` tampoco lo pisa con el marcador avanzado (write-once sobre la **presencia**, no sobre si resuelve); dejarlo hace que `slice-base` caiga a la base de rama (over-scope, seguro) en vez de under-scopear.
- **`close` + slice nuevo re-snapshotea** — tras un `close` (cierre limpio), el `open` del slice siguiente SÍ escribe el arranque nuevo: write-once no rompe el flujo multi-slice apilado.
- **`close` preserva las demás claves y es idempotente** — borra solo `slice-open:<rama>` (conserva el dedupe del hook, los marcadores de otras ramas y el propio `marker:<rama>`); una segunda llamada sin `slice-open` es no-op y sale 0.
- **`close` sobre estado corrupto** — un `review-loop-state.json` ilegible lo deja **byte-idéntico** (no lo reescribe a `{}` ni crea `.bad`): `Read-State` devuelve `@{}`, `close` no encuentra la clave y sale antes de escribir. No necesita la cuarentena de `advance`.

En la prosa del cierre (`review-loop-incremental.tests.ps1`):

- **`-Action close` solo en cierre limpio** — la sección "At close" de `review-loop.md`/SKILL llama `close` únicamente en el cierre limpio (no en el cap) y **después** del pase de coherencia (que lee el ancla vía `slice-base`), verificado por posición sobre las 4 copias.

## Testeo del foco de mutación acotada (A5)

A5 agregó un **sexto foco** condicional a `/slice-review` que verifica que los tests del slice tienen dientes: rompe líneas de lógica cambiadas y mira si algún test se da cuenta. A diferencia de los 5 focos de lectura pura, este **ejecuta**, de ahí el worktree aislado. Se verifica en `tests/slice-review.tests.ps1`, anclado a la sección `## Mutation focus` sobre las 4 copias, más el ruteo del flag y el paso del turno 1 en `tests/review-loop-incremental.tests.ps1`. Casos cubiertos:

- **Presupuesto** — a lo sumo **8 mutantes** (`at most`, no "at least"), solo en el turno 1 del loop, prohibido en los turnos 2+ (para que el costo por turno no crezca con la profundidad).
- **Worktree aislado** — se construye con `git worktree add --detach` desde un snapshot vivo (`git stash create`, no el SHA del marcador), copiando los untracked (`ls-files --others`, porque los tests nuevos no están en el snapshot), FUERA del repo; el marcador solo identifica qué líneas cambiaron.
- **Aislamiento** — muta solo dentro del worktree, nunca en el árbol del usuario.
- **Selección de mutantes** — uno a la vez, solo líneas de lógica que el slice cambió, priorizadas por riesgo cuando hay más de 8.
- **Test relevante** — sale del diff del slice, nunca la suite entera; "ningún test cubre la lógica cambiada" es un hallazgo.
- **Hallazgo** — un mutante **sobreviviente** se reporta como **Medium**; los que mueren no se reportan. El mutante equivalente se contempla y lo descarta el pase de confianza (<60).
- **Modelo agnóstico** — corre en el modelo más capaz disponible, sin pin de versión (el assert caza cualquier `opus`/`sonnet`/`haiku`/`claude`/`gpt` seguido de dígito).
- **Excepción de escritura** — como el foco DEBE mutar, se talla una excepción explícita a la prohibición de escritura del contexto compartido: puede editar SOLO dentro de su worktree aislado, y la excepción concede el **mecanismo** (usar herramientas de edición), no solo la ubicación.
- **Robustez de la receta** — asigna `$tmp` (no lo usa sin definir); si el test no arranca por deps gitignoradas (node_modules/.venv) reporta "could not execute", no un falso limpio ni un falso hallazgo.
- **Cleanup** — limpia el worktree con `git worktree remove` al terminar.
- **Ruteo** — Step 1 parsea `--mutation` (standalone: `/slice-review --mutation`); es **excluyente** con `--coherence` y, si llegan ambos, gana coherence (resuelto ANTES de tratar el resto como rango); Step 4 lo despacha como sexto foco condicional.
- **En el loop** — el turno 1 pasa `--mutation` a `/slice-review` (`first turn only`); los turnos 2+ no lo llevan (`prohibited on turns 2`), verificado en `review-loop-incremental.tests.ps1`.

## Testeo de la regla de afirmaciones (A6)

A6 fijó la regla de afirmaciones: una afirmación (enunciado verificable en un comentario, docstring o mensaje de commit) se escribe SOLO si se verificó; si no se verificó, no se escribe. Se ataca en dos puntos, con cero agentes dedicados, y `tests/regla-de-afirmaciones.tests.ps1` (runner sin Pester) blinda ambos. Casos cubiertos:

- **Regla dura en las 4 CLAUDE.md** — la regla vive en las reglas del proyecto de los 3 scaffolds + el propio repo (4 archivos **no espejados**: las CLAUDE.md divergen legítimamente y están en la allowlist del mirror, así que son 4 ediciones separadas). Se verifican la mitad positiva (`written only if it was verified`) y la negativa, que es el punto (`do not write it`).
- **Una línea en el reviewer de contratos** — la detección barata es una línea en el foco 4 de Step 4 de `/slice-review` (que YA corre), sin foco nuevo: el reviewer de contratos marca `unverified assertion`. Se verifica la presencia de la línea en las 4 copias de slice-review (repo + 3 scaffolds); la byte-identidad la cubre `review-loop-incremental.tests.ps1`.
- **Sin foco de lectura extra** — siguen los 5 focos de lectura numerados (`^5.`) y no se agregó un 6to foco de lectura numerado (`^6.` ausente): el único 6to condicional es el de mutación (A5), que ejecuta y vive en su propia sección, no como item 6 de Step 4.

## Testeo de la migración a ruteo de modelos agnóstico

El ruteo de modelos por foco pasó de nombres pinneados (`Opus 5` / `Sonnet 5`) a **tiers agnósticos sin versión**, preservando los dos niveles: tier fuerte = **the most capable model available** (bugs, contratos, tests, confianza, mutación), tier liviano = **a lighter, faster model** (reglas, historia, coherencia). La frase del tier fuerte es idéntica a la que ya usaba el foco de mutación (A5), que fue el patrón. Se verifica en `tests/slice-review.tests.ps1` y `tests/review-loop-incremental.tests.ps1` sobre las 4 copias. Casos cubiertos:

- **Frases agnósticas por tier** — en `slice-review.tests.ps1`, el párrafo "Models by focus" rutea reglas e historia a `a lighter, faster model` y bugs/contratos/tests a `the most capable model available`; la confianza declara `the confidence pass runs on the most capable model available` y el pase de coherencia `a lighter, faster model`.
- **Guard anti-pin file-wide** — más allá de las frases positivas, cada par se chequea entero contra `(?i)(opus|sonnet|haiku|claude|gpt)[- ]?\d`: un pin reintroducido en CUALQUIER sección lo caza, no solo en la sección migrada. En `slice-review.tests.ps1` el guard cubre el par slice-review y el par review-loop; `CLAUDE.md` y rangos como `0-100` no matchean (no hay dígito pegado a un nombre de modelo).
- **Coherencia del loop anclada a la sección** — en `review-loop-incremental.tests.ps1`, la sección `## At close` del par review-loop no pinnea el modelo y describe el pase de coherencia en `a lighter, faster model`.

## Testeo del marcador de revisión y del turno incremental

El loop revisa el **delta sin revisar**, no el rango completo de la rama en cada turno. Dos runners lo cubren.

`pwsh -NoProfile -File tests/review-marker.tests.ps1` — el script `.claude/scripts/review-marker.ps1` sobre repos git temporales (runner sin Pester). Casos cubiertos:

- **Los verbos de rango** (`advance`, `get`, `range`, `base`) — `advance` fija un punto de corte resoluble, `get` lo devuelve, `range` dice qué pasarle a `git diff`, y `base` devuelve la base del slice (un merge-base) para que el hook **delegue** la resolución de base cuando sus propias ramas nombradas fallan. (Los verbos de anclaje `open`/`slice-base` y de limpieza `close` — siete verbos en total — se cubren en las secciones A4b y A4c de arriba.) `base` comparte el resolvedor de `range` (`Get-SliceBase`) y su contrato de exit codes: 0 + ref resoluble, o **exit 2 + vacío** cuando no hay base determinable — nunca 0 + vacío, que el hook leería como "no hay nada que revisar". Fixture: base `trunk` devuelve el merge-base; repo de una sola rama da exit 2.
- **`advance` es no-invasivo** — no commitea, no mueve HEAD, no toca el árbol de trabajo, y el árbol sucio entra en el punto de corte (`git stash create`, no `rev-parse HEAD`).
- **`advance` pone en cuarentena un estado ilegible antes de pisarlo** — el archivo compartido guarda las claves `marker:*` / `untracked:*` de todas las ramas y el dedupe del hook. Si queda ilegible (una escritura no atómica pisada a mitad, otra herramienta), `advance` lo movía a `@{}` y reescribía sólo su clave, borrando las demás sin rastro. Ahora lo mueve a `.bad` (recuperable) antes de escribir — la misma cuarentena que el hook ya hacía de su lado; si el `Move-Item` falla (archivo tomado a mitad de escritura), salta la escritura en vez de pisar lo que no pudo respaldar. Fixture: JSON inválido con una clave de otra rama → el `.bad` la conserva y el estado nuevo trae el marcador de la rama actual.
- **El rango no repite lo ya revisado** y sí trae el delta nuevo, incluidos los fixes **sin commitear** y los **archivos nuevos sin trackear** (que `git diff` nunca muestra).
- **Base del slice** — sale de la rama remota cuando no hay rama local con ese nombre (un clon de una sola rama tiene `origin/main` y ningún `main`); sobre la propia rama base cae a HEAD para cubrir lo no commiteado.
- **Exit codes** — vacío + 0 es "no hay delta"; vacío + **2** es "no puedo determinar el rango". Con fixture: fuera de repo, detached HEAD y repo cuya única ref es la rama actual. Sin fixture (verificado a mano, no cubierto): repo sin commits. Confundir los dos códigos es lo que hace que un slice se reporte revisado sin reviewer.
- **La base no se llama siempre `main`** — si no resuelve ninguno de los nombres usuales (base `trunk`, `dev`, `release`), entran las demás refs y la base es el ancestro común **más lejano** de todas: una rama hermana nacida a mitad del slice está más cerca que la base real, y elegirla haría perder los commits anteriores. Con una sola ref en el repo (o una rama huérfana) el rango da exit 2 en vez de emitir HEAD.
- **Un candidato que ya contiene HEAD no gana la elección de base** — con la rama mergeada a `develop` y trabajo que sigue encima, `merge-base develop HEAD` es HEAD y su distancia es 0, así que en una comparación "gana el más cercano" gana siempre y la base colapsa a HEAD: `git diff HEAD` deja de mostrar los commits del slice, con exit 0. HEAD queda como último recurso, nunca por delante de un candidato con delta commiteado.
- **El estado cruza shells** — lo escribe `pwsh` 7 y lo lee Windows PowerShell 5.1 sin corromperse. Sus defaults de encoding discrepan (BOM sí/no, y `Get-Content -Raw` cae en la code page ANSI), y con eso la huella de un untracked acentuado no vuelve a matchear nunca: esa rama ya no puede cerrar el loop por "no hay delta".

- **Untracked desde el marcador** — un archivo sin trackear que el marcador ya cubrió no vuelve a contar como delta (`advance` guarda su huella junto al marcador); uno nuevo sí. Sin eso el rango nunca vuelve a quedar vacío y el loop no puede cerrar por "no hay delta".
- **El marcador trabaja desde la raíz del repo** — `advance` corrido desde un subdirectorio ficha los untracked con la ruta relativa a la **raíz**. `ls-files` lista sólo el subárbol del cwd y con rutas relativas a él, así que en un monorepo la huella quedaba con otra base que la que lee el hook (que sí ancla a la raíz) y ninguna de las dos volvía a matchear: un untracked ya revisado seguía contando como delta para siempre.
- **`advance` nunca persiste basura** — durante un merge conflictivo `git stash create` falla escribiendo `<archivo>: needs merge` en STDOUT; se validan el exit code y la forma del sha.
- **Marcador podado por `git gc`** → cae a la base del slice (el fixture verifica que la poda ocurrió de verdad).
- **Coexistencia con el hook** — el estado vive en `<git-dir>/review-loop-state.json` bajo `marker:<rama>`, no ensucia el árbol ni el diff del slice, y no pisa el dedupe por SHA del disparo.
- **Repo bajo una ruta no-ASCII** — el marcador se invoca en un `pwsh` hijo con la code page forzada a **850**, que es como lo llama el hook (proceso hijo con stdout redirigido, sin heredar el 65001 de la consola). Sin forzar el encoding dentro del script, `rev-parse --show-toplevel` volvía mojibake y las **tres** acciones salían con exit 2 en silencio: `advance` no avanzaba nunca y el ciclo revisaba la rama entera para siempre. El caso lleva **control positivo** de que la code page se forzó de verdad, porque el `catch` del `GetEncoding` se traga la falla.

**Lo que este archivo de tests NO cubre** (verificado por mutación, no inferido — los mutantes sobreviven con la suite en verde). Este bloque va al final de la lista a propósito: cuando se insertó en el medio, los cuatro bullets de arriba quedaron leyéndose como descubiertos teniendo fixture propio.

- Entre **dos** nombres conocidos con merge-base distinto, que gane el **más cercano**: invertir la comparación a "más lejano" no pone nada en rojo. Ningún fixture tiene dos candidatos nombrados que difieran.
- El **fallback pairwise** para historias no relacionadas (cuando `merge-base --octopus` falla): reemplazarlo por `return $null` no pone nada en rojo.
- Que **HEAD entre en el `--octopus`**: sacarlo no pone nada en rojo, aunque sin él el rango puede arrancar en un commit que no es ancestro de HEAD y mostrarle al reviewer cambios ajenos con exit 0.
- **El guard del candidato que contiene HEAD sólo existe en el camino de nombres conocidos.** Por el camino de `Get-OtherRefs` + `merge-base --octopus` (base llamada `trunk`, `dev`, `release`) un candidato que contiene HEAD sigue ganando, y el rango sale vacío con exit 0 escondiendo los commits del slice. Ningún fixture pasa por ahí. Pertenece al slice A1b.
- `if ($headResolved) { return $head }` (HEAD como último recurso): borrar esa línea sobrevive la suite entera; en los fixtures actuales el otro camino devuelve HEAD igual.
- El fixture del **upstream pusheado con otro nombre** pasa por el camino de nombres conocidos (`git clone` deja `origin/HEAD → origin/trunk`), así que `Get-OtherRefs` nunca corre: el resultado es correcto, pero por el camino equivocado.
- Que la clave de la huella de untracked sea **por rama** (`untracked:<rama>`): con una clave global, la huella de una rama tapa el archivo nuevo de otra y el rango queda vacío.
- El **exit code de `get`** cuando todavía no hay marcador (el header del script lo declara como contrato).
- Los dos guards de `advance` (forma del sha y exit code de `git stash create`) **se tapan mutuamente**: cada uno sobrevive solo; sólo mueren juntos.
- La **mitad de escritura** del fix de encoding: volver `[IO.File]::WriteAllText` a `Set-Content -Encoding UTF8` sobrevive. Es esperable — bajo 5.1 eso escribe UTF-8 **con** BOM y no corrompe; la corrupción real está sólo del lado de la lectura, que sí está cubierta.

`pwsh -NoProfile -File tests/review-loop-incremental.tests.ps1` — el contrato en las **cuatro** copias (3 skills + este repo): que las instrucciones usen el marcador, distingan el exit 2, exijan RED en los fixes, y que el **orden** sea range → corrida de review → `advance` → fixes (verificado por posición, no por presencia: un doc que avanzara al final pasaba todos los asserts de presencia). Incluye el hash normalizado de las 4 copias del script, porque `mirror.tests.ps1` compara solo las 3 skills entre sí y la copia de este repo — la que corre acá — no entra en ninguna comparación. El **hook** no puede compararse byte a byte (la copia de este repo tiene los comentarios en español, drift deliberado), así que se compara su **lógica**, cortando en `$msg =` porque el mensaje está traducido a propósito. Ese corte deja afuera todo el bloque de emisión, así que ese bloque lleva asserts propios en las 4 copias (`hookEventName`, `additionalContext`, la serialización) más un chequeo de sintaxis del archivo entero: sin eso, romper el emisor de una sola copia dejaba las tres suites en verde y esa copia dejaba de inyectar la orden en silencio.

## Testeo del hook `review-loop-trigger` y del merge de settings

El script del hook y `merge-settings.ps1` se testean con fixtures determinísticos (repos git temporales), no con skill-creator. Runner: `pwsh -NoProfile -File tests/review-loop-trigger.tests.ps1` (imprime `TODOS LOS TESTS PASARON` o `N test(s) FALLARON`). **Importante:** el hook resuelve el repo desde `cwd`; en los tests, `cwd` debe ser un path Windows real (como el que pasa Claude Code), no un path MSYS `/tmp/...`, o `Set-Location` falla y el hook corre contra el repo equivocado. Casos cubiertos:

- **No-op no-git** — un comando que no es `gh pr create`/`git push`/`git commit` no emite nada.
- **Dispara post-PR/push** — `git push` en un branch de feature emite `additionalContext`.
- **El cierre de slice se declara** — un `git commit` **con** trailer `Slice-Close:` emite la orden imperativa de correr `/review-loop` (cubre repos locales sin remote); **sin** el trailer no emite nada.
- **El disparador se lee del comando normalizado, no del crudo** — el comando incluye el texto del `-m`, así que un commit cuyo mensaje menciona `git push` prendía la bandera del push y salteaba la puerta del trailer entera; y `git -C <repo> push` no matcheaba ningún patrón, así que un push legítimo nunca disparaba. Hay fixture para los dos, y para las dos formas en que un blanqueo por regex falla: comillas **escapadas** (`\"git push\"`, que dispara cuando no debe), un **apóstrofe** en el mensaje (`-m "don't" && git push`, que se traga el push real) y el apóstrofe **escrito a la bash** (`'\''`, que cierra y reabre el literal: leído sin mirar el escape de afuera dejaba el resto del mensaje expuesto). Por eso los literales se recorren en vez de reemplazarse por regex. La sustitución de comandos `$(...)` y los backticks reinician el contexto de comillas de bash adentro y desalineaban el recorrido en las dos direcciones (perdían un `git push` real y también un cierre declarado). **A2b lo cierra sin modelar `$()`**: cuando el comando contiene `$(` o un backtick, las banderas se recalculan sobre el comando **crudo** y se combinan con OR, así que todo falso negativo se vuelve falso positivo (un review-loop de más, la dirección segura). Fixture: `git commit -m "$(sed 's/"/x/' f)" && git push` dispara (mutante = sacar el OR → rojo), y `echo "$(...)" && git commit -m cierre` con trailer no queda mudo. Los usos naturales (`date +"%F"`) mantienen número par de comillas y no llegan a esa rama. **Costo aceptado (F3/confianza)**: como `$isPush`/`$isPr` en `true` ruteán alrededor del paso 6, un commit cuyo **mensaje** menciona "git push" dentro de un `$(...)` ahora dispara salteando la puerta del trailer y la frescura — un falso positivo, la dirección segura (un review-loop de más que pide el rango del marcador y cierra en vacío), no un cierre perdido. Se **fija con un fixture** (`git commit -m "recorda: $(echo git push) al terminar"` dispara) para que ese ensanchamiento no cambie en silencio; contrasta con el fixture sin `$(` de arriba, donde la misma frase entrecomillada **no** dispara.
- **Red de seguridad por techo** — un commit sin trailer cuyo delta sin revisar pasa las ~400 líneas dispara igual, y el techo se mide sobre el rango del **marcador**, no sobre el rango completo de la rama (mutado a mano: ignorar el marcador pone el caso en rojo). El **borde de abajo** también está fijado (200 líneas no disparan): sin ese caso, mutar `-le 400` a `-le 100` sobrevivía la suite entera.
- **El techo se mide sobre el repo entero** — los pathspec y `ls-files` se resuelven contra el cwd del proceso git, y el evento trae el cwd de la **sesión**, que en un monorepo es un subdirectorio: sin anclar a la raíz, la red de seguridad medía sólo ese subárbol y desaparecía en silencio. Hay fixture para la mitad trackeada y para la untracked.
- **El cwd del evento no-ASCII llega por STDIN (A2b, F3)** — el JSON del evento se decodifica con `[Console]::InputEncoding`, y un hook lanzado con la consola en OEM (el default de Windows) no hereda UTF-8 en la **entrada**, no sólo en la salida. Sin forzar `InputEncoding` (además de `OutputEncoding`), un `cwd` con `ñ` volvía mojibake, `Set-Location` fallaba en silencio y el hook corría sobre el repo **AMBIENTE** y disparaba — desubicando todo. El fix fuerza `InputEncoding = UTF-8` antes de la primera lectura de `[Console]::In`, más una **red de hardening**: si el `cwd` del evento no resuelve (`Test-Path` falso), `exit 0` en vez de seguir sobre el ambiente. Dos fixtures deterministas, ambos con el hook invocado como `pwsh -File` (igual que Claude Code) y la consola de entrada forzada a 850: un **control positivo** —repo bajo ruta `ñ` con cierre declarado fresco, que dispara nombrando **su** rama (`feat/x`), imposible si el cwd mojibakea— y el de **hardening** —un cwd inexistente no dispara sobre el repo ambiente—. El control positivo reemplaza al fixture viejo que sólo aseraba "no dispara" (ambiguo: lo satisfacía tanto resolver bien como el hardening) y era no-determinístico según la code page de la máquina.
- **La red de seguridad sí ancla a la raíz bajo ruta no-ASCII** — con el cwd ya resuelto (fix de arriba), `rev-parse --show-toplevel` y el `git -C $root diff` del techo miden bien; sin el forzado de encoding, `$root` dejaba de ser un repo, `$measurable` quedaba en falso y la red **disparaba siempre**.
- **Qué cuenta para el techo** — hay fixture para: generados y vendored del lado **trackeado**, un lockfile del lado **sin trackear**, un binario sin trackear, un untracked que el marcador ya cubrió (no cuenta) y **otro que creció desde el marcador** (sí cuenta: la huella se compara por `path|sha256` entero, igual que el marcador), y un untracked con nombre **acentuado** (que sin forzar el encoding sumaba cero). El **tamaño** de la ventana de detección de binarios también está fijado desde el 2026-08-14: un untracked cuyo primer NUL cae en el byte 5460 se descarta igual, así que revertir los 8000 B a 4096 pone el caso en rojo (antes sólo había un fixture con el NUL en el offset 3, que cualquier ventana encuentra). Los patrones sin fixture están listados abajo, en lo que este archivo **no** cubre.
- **Atribución cruzada** — un commit ejecutado en otro repo no dispara acá: si el HEAD de este repo no es reciente, el commit ocurrió en otro lado. Los **dos bordes** de la ventana están fijados (10 min dispara / 90 min no) y también el reloj adelantado (`Abs()`: un HEAD fechado 2 h en el futuro tampoco cuenta). Para **push y PR**, que no mueven HEAD, ya no hay atribución: el bloque que la deducía parseando la línea de comando se **borró** el 2026-08-14, después de que tres turnos de revisión seguidos encontraran altas en él (1 → 3 → 4), todas falsos negativos que descartaban cierres declarados en silencio. El costo aceptado — un push corrido en otro repo dispara acá — tiene **dos** fixtures, uno por forma: `cd '<otro>' && git push` y `git -C '<otro>' push`. Hacen falta los dos y no es simetría decorativa: el bloque borrado probaba **primero** la forma `git -C` y sólo caía al `cd`, así que con el fixture del `cd` solo, reintroducir únicamente la rama `git -C` dejaba la suite entera en verde — medido el 2026-08-14 — y el único assert que declara "este bloque se borró" no protegía la forma que el bloque probaba primero.
- **`--base` se lee del comando normalizado** — la bandera se ubica sobre `$scan` y su valor se recupera de `$cmd` por índice. Hay fixture para las dos formas en que fallaba leyendo el crudo: `--base "develop"` **entrecomillado** (no matcheaba y caía al fallback) y un `--base` citado dentro de `--title` (ganaba por ser el primer match, mandando a un rango contra una rama inexistente). Lo que **no** se verifica es que la base exista: el hook toma el valor tal cual y lo pone en el mensaje inyectado. Los tres fixtures de `--base` creaban la rama `develop` como setup y se midió (las tres formas, con y sin la rama) que los seis asserts pasan igual: el setup era muerto y se sacó, porque hacía leer el caso como si la existencia estuviera cubierta.
- **La resolución de base delega en el marcador (A2b, cierra la Alta A)** — cuando ni `origin/HEAD` ni las ramas nombradas (`main`/`master`/`develop`) resuelven, el hook llamaba `exit 0` **antes** del gate del trailer, quedando **mudo** en un repo cuya base es `trunk`/`dev`/`release` y perdiendo un cierre DECLARADO en silencio — el falso negativo que el hook existe para eliminar, escondido justo en GitHub donde `gh repo view` lo rescataba. Ahora, agotadas las nombradas, delega en el marcador co-ubicado (`-Action base`), que resuelve esos repos con `for-each-ref` + `merge-base --octopus`. Fixture: cierre declarado en repo base `trunk` con el marcador presente **dispara** (mutante = revertir la delegación al `exit 0` → rojo). De paso se **borró el `gh repo view`**: era una llamada de red en cada commit cuando `origin/HEAD` no está seteado (el caso `git init` + `remote add`) y corría antes del fallback local que resuelve gratis.
- **Contrato del marcador** — exit 0 con ref dispara, exit 0 vacío ("nada sin revisar") no dispara, y **exit 2** (rama huérfana, sin base común) dispara igual: ahí el rango de fallback `<base>...HEAD` ni siquiera se puede medir (`fatal: no merge base`), y con el error tragado eso se leía como 0 líneas. El marcador ausente y `pwsh` fuera del PATH también caen del lado que dispara, en vez de quedarse mudos.
- **El mensaje inyectado** manda el ciclo al delta sin revisar (`review-marker.ps1 -Action range`), no al rango completo de la rama. El assert va anclado al bloque del mensaje en las **4 copias**: sobre el archivo entero lo satisfacía el nombre del script dentro de la red de seguridad, así que se podía reescribir el mensaje para ordenar el rango de la rama con las tres suites en verde.
- **El hook no corrompe el estado del marcador** — invocado bajo Windows PowerShell 5.1 sobre un estado con huella acentuada, la huella sobrevive (lectura y escritura con `[IO.File]` + UTF-8), con control positivo de que el hook realmente reescribió el estado. Un estado ilegible se aparta como `.bad` en vez de pisarse, queda recuperable, y el hook **dispara igual** (sin ese último assert, un `exit 0` colado en el `catch` sobrevivía). Y si la **cuarentena misma falla** — fixture que bloquea el destino `.bad` con `FileShare.None` —, el hook saltea la escritura del estado pero dispara igual: el original queda intacto.
- **Dedupe por SHA** — segundo disparo sobre el mismo commit no emite; tras un commit nuevo vuelve a disparar. Sigue funcionando bajo una ruta con corchetes (`-LiteralPath`).
- **Base dinámica** — estar en la base no dispara; `gh pr create --base develop` usa `develop` (no hardcodea `main`).
- **Merge de settings** — `settings.json` ausente → copia el canónico; preexistente propio (p. ej. con `enabledPlugins`) → agrega el hook sin pisar lo demás; correrlo dos veces no duplica la entrada.

**Lo que este archivo de tests NO cubre** (verificado por mutación, no inferido):

- La **resolución de la base** por `origin/HEAD` con rama local ausente: ningún fixture tiene remote, así que ese camino nunca corre. (El camino por `gh repo view` se **eliminó** en A2b — era una llamada de red por commit delante del fallback local.)
- Que el fold de opciones globales cubra algo más que `-C`: `--git-dir`, `--work-tree`, `-c`, `--no-pager` y `--paginate` están en el patrón pero no tienen fixture. Sólo afecta al reconocimiento del disparador (que un `git --git-dir=x push` se lea como push); ya no hay atribución que pueda equivocarse con ellos.
- La rama de **comilla sin cerrar** de `Hide-Literals`: se come el resto de la línea, y eso no es observable por conducta — todo lo que queda después ya está enmascarado, así que ningún comando distingue la versión correcta de la que dejaba el último carácter afuera. Se arregló porque el comentario afirmaba lo que el código no hacía, no porque haya un caso que lo pruebe.
- La **sustitución de comandos** `$(...)`: bash reinicia el contexto de comillas adentro, y `Hide-Literals` no lo modela. Ya **no** es un límite sin repro — el 2026-08-14 se reprodujo sobre la función real, y falla en las dos direcciones, no sólo en la del falso positivo que se sospechaba:

  ```bash
  git commit -m "$(sed 's/"/x/' f)" && git push      # isPush=False   <- push REAL perdido
  echo "$(sed 's/"/x/' f)" && git commit -m cierre   # isCommit=False <- cierre declarado perdido
  git commit -m "wrote $(echo "git push") today"     # isPush=True    <- dispara salteando gate, frescura y techo
  ```

  Mecanismo: una comilla **doble** dentro de comillas **simples** dentro de la sustitución deja el total de dobles en número **impar**, el recorrido de literales se desalinea y se traga el resto de la línea. **A2b lo cerró** calculando las banderas también sobre el comando crudo cuando aparece `$(` o un backtick y quedándose con el OR (ver la entrada "El disparador se lee del comando normalizado" arriba); ahora sí tiene fixtures, incluido el del costo aceptado. Ya no es un ítem sin cubrir.
- Los **heredocs**: el blanqueo de literales entrecomillados no los toca, así que un mensaje de commit pasado por heredoc que mencione `git push` sigue prendiendo la bandera. Degrada al comportamiento anterior al fix, no a algo peor.
- El **guard "no revisar la base contra sí misma" (paso 5) con base delegada** (A2b): compara por NOMBRE (`$branch -eq $base`), pero cuando la base se delega al marcador (`-Action base`) éste devuelve un **commit SHA**, que nunca iguala el nombre de la rama. En un repo con base de nombre no estándar (`trunk`/`dev`/`release`) y ramas hermanas presentes, un commit hecho **directamente sobre la base** ya no queda suprimido por el paso 5 — contradice la garantía del `CLAUDE.md` "commits directos a la base no disparan". Acotado y off-workflow (el flujo es una feature branch por slice; declarar un `Slice-Close:` sobre la base ya está fuera del flujo) y en la dirección segura (un review-loop de más, nunca un cierre perdido). Sin fixture; documentado como límite conocido.
- La **cuarentena `.bad` con `-Force` pisa una cuarentena previa**: un segundo evento de corrupción sobrescribe el primer `.bad`, perdiendo la copia recuperable anterior. Aplica al marcador (`advance`) y a la copia gemela del hook. Baja: un `.bad` que se pisa sigue siendo mejor que no respaldar, pero la palabra "recuperable" es algo optimista si hay dos corrupciones seguidas.
- El **centinela `$global:LASTEXITCODE = 99`**: borrarlo sobrevive la suite. Cuando `pwsh` no está en el PATH, PowerShell ya deja `$LASTEXITCODE` en un valor distinto de 0 por su cuenta, así que en ese escenario el centinela es **redundancia, no un agujero** — la conducta observable (la red dispara igual) sí está verificada. Protegería contra otra falla de la llamada que no toque `$LASTEXITCODE`, y no hay fixture para eso.
- La escritura del estado **no es atómica** (un solo `WriteAllText`, sin temp+move): no hay test y no está arreglado. Lo que sí se hizo es cortar su peor consecuencia — si la cuarentena del estado ilegible falla, el hook no escribe encima —, y **eso sí tiene fixture** desde el 2026-08-14. Antes ese camino era además **código muerto**: con `$ErrorActionPreference = "SilentlyContinue"` el `Move-Item` no lanzaba excepción terminante y el `catch` nunca corría.
- Que la huella de untracked se **ignore cuando su marcador fue podado** por `git gc`: la lógica está, el fixture no.
- El lado untracked de **generados y vendored** (del lado trackeado sí hay fixture), y los patrones `*.snap`, `go.sum`, `*.lock`, `*lock.yaml` y `*.lockb` de los **dos** lados — el único lockfile con fixture es `package-lock.json`, por el patrón `*lock.json`. Se apoyan en que comparten el mismo `$skipPat` con los que sí lo tienen. (Esta lista y la de arriba decían cosas distintas sobre `*.lock`; ahora la lista vive sólo acá.)

El hook `alignment-gate` (PreToolUse) se testea aparte, con su propio runner: `pwsh -NoProfile -File tests/alignment-gate.tests.ps1` (mismos fixtures determinísticos, mismo formato de salida). Casos cubiertos:

- **Deny en código, sesión nueva** — `Write`/`Edit` sobre un archivo de código (`src/app.py`) en una sesión sin actividad previa → `deny` + ofrece `grill`.
- **Allowlist no-código pasa libre** — `.md`, `CLAUDE.md`, `.scratch/**` (clave: no romper la escritura del PRD) y `.json` de config no disparan nada.
- **Dedup por sesión** — un segundo `Edit`/`Write` de código dentro de la misma `session_id` no vuelve a disparar; una `session_id` distinta sí.
- **MultiEdit** — detecta código dentro de `edits[].file_path` (no solo `tool_input.file_path`).
- **Espejado** — `alignment-gate.ps1` es byte-idéntico entre `bootstrap-personal-project` y `bootstrap-southpoint-project` (hash SHA256).
- **`settings.json` válidos con ambos hooks** — en ambos scaffolds, `settings.json` parsea como JSON y declara `alignment-gate` en `PreToolUse` a la vez que conserva `review-loop-trigger` en `PostToolUse`.

## Testeo del gate de slices sólo-docs (paso 5c del hook)

Runner: `pwsh -NoProfile -File tests/review-loop-docs-gate.tests.ps1` (imprime `TODOS LOS TESTS PASARON` o `N test(s) FALLARON`). El gate decide **cuándo se revisa el código**, así que un bug acá no se ve: apaga revisiones en silencio. Por eso la suite corre el **hook real end-to-end** sobre repos git temporales en vez de copiar el clasificador — la probe original de la que salió esta feature se probaba a sí misma, y sacarle una rama al `$govern` la dejaba entera en verde.

Casos cubiertos:

- **Prosa** — un slice de sólo `.md` no dispara; varios `.md` sueltos tampoco; un `.md` **con acento** sigue clasificando como doc (el fixture fuerza `core.quotePath true` para que sacar el `-c core.quotepath=false` del hook caiga en rojo).
- **Lo que gobierna al agente sí dispara aunque sea `.md`** — `CLAUDE.md` (también uno **anidado**), `.claude/**`, `.agents/**`, `docs/ai-workflow/**`, `docs/agents/**`.
- **Código** — normal, **bajo `docs/`** (el falso negativo de la v1), y un slice mixto (basta un archivo no-doc).
- **El camino del marcador**, que es el único que existe en un repo bootstrapeado: con el marcador instalado y avanzado, un delta sólo-docs no dispara aunque la rama ya traiga código revisado, y sí dispara cuando el delta trae código aunque el último commit sea prosa. Sin estos dos fixtures, mutar `$docRange` a `"$base...HEAD"` o a `"HEAD~1...HEAD"` sobrevivía la suite entera y el ajuste que motivó todo el port quedaba sin verificar.
- **Descuento de untracked contra la huella del marcador** — un untracked ya fichado no mantiene el gate apagado para siempre.
- **Modificación sin commitear de un archivo trackeado** (camino sin marcador, donde el rango es de commits y el árbol queda afuera). Lleva **dos controles positivos**: que el rango de commits sea sólo prosa y que la modificación haya quedado sin commitear.
- **Lo generado no cuenta, lo demás sí** — el gate filtra por `$genPat` (`*.bootstrap-manifest.json`, `*.snap`: lo que no escribió nadie), **no** por el `$skipPat` del techo. Siete casos, dos de ellos por la mitad **sin trackear**, y fijan mutaciones **disjuntas** (medido, una corrida por mutante): sacar el filtro `$genPat` de esa mitad lo caza sólo el del **manifest**; poner `$skipPat` ahí en su lugar lo caza sólo el del **lockfile**. Ninguno subsume al otro, así que ninguno de los dos es podable por redundante. Manifest + prosa → silencio; snapshot + prosa → silencio; manifest sin trackear + prosa → silencio; **lockfile** + prosa → dispara; **`docs/vendor/**`** + prosa → dispara; lockfile sin trackear + prosa → dispara; y **`.md` vendorado solo** → silencio (un `.md` bajo `docs/vendor/` es prosa para el gate: es el único camino de silencio que la separación de listas introdujo, fijado a propósito para que cambiarlo haya que declararlo). Un assert aparte fija que **`$genPat` sea subconjunto estricto de `$skipPat`**, leyendo las dos listas del hook: sin él, agregar un patrón a una y no a la otra no lo detecta nadie.
- **La monotonicidad se exige sobre lo AUTORADO, no sobre todo**: darle al gate el `$skipPat` entero volvía la decisión no monotónica donde importa (el lockfile solo disparaba, el mismo lockfile con un README al lado se callaba, y ahí se silenciaba justo donde se verifica la regla de supply-chain). Sobre un generado la inversión sigue existiendo — manifest solo dispara, manifest + README se calla — y es benigna a propósito: no hay nada escrito por una persona ahí adentro para leer.
- **Delta neto vacío dispara** — vacío no es sólo-docs.
- **Fail-open** con rango irresoluble, y **con un untracked `.md` presente**: sin ese segundo caso, sacar el guard del exit code del `git diff` quedaba tapado por el guard de colección vacía.
- **Renames** — mover código a un nombre `.md` sigue disparando. Lleva control positivo de que git está **detectando** el rename (si no lo detectara, el caso no distinguiría un hook con `--no-renames` de uno sin él).
- **La prosa de los 4 `CLAUDE.md` coincide con el clasificador** — `$govern` se **lee del hook** y las rutas esperadas se **derivan** de él, en vez de hardcodearlas: hardcodeadas, **reemplazar** una alternativa del clasificador sin tocar la prosa no lo detecta nadie (medido: cambiar `(^|/)docs/agents/` por `(^|/)docs/` cae en rojo con la derivación y queda **verde** sin ella). *Agregar* una alternativa, en cambio, no distingue las dos variantes: cae en rojo con y sin derivación, porque ahí ya muerde el assert de las 5 alternativas. Se fija que tenga 5 alternativas, que **todas** estén ancladas `(^|/)`, que se encuentren los **4** archivos, que cada uno tenga **exactamente un** bullet de review-loop (recortado del texto crudo por su encabezado, y cortando sólo en un bullet de primer nivel: juntando las líneas que mencionen el hook, una mención de otra sección satisfacía el assert desde afuera, y cualquier reflow o sub-lista daba rojo diciendo que faltaban rutas que sí estaban), que las rutas aparezcan **dentro de la lista entre paréntesis** (sobre el bullet entero, `docs/` está nombrado en la frase que dice lo contrario, así que una alternativa `docs/` habría quedado anclada por la frase que la niega), y que la **dirección** de la regla esté escrita — sin ese último assert la prosa podía invertirse y volver a declarar el bug de la v1 quedando en verde.
  Límite conocido de la derivación: sólo deshace el ancla `(^|/)`, el `$` final y el escape `\.`. Una alternativa que no sea una ruta literal deja este assert en **rojo permanente** — hay que tocar la derivación, no la prosa.
- **Controles positivos** en `Commit-Files`, `Add-Marker` (que el commit se creó) y `Advance-Marker` (que cortó marcador de verdad): sin ellos, un `commit.gpgsign` global no neutralizado o un `advance` que no avanza dejan los casos midiendo otra cosa, en verde.

**Costo aceptado, medido**: el paso 5b resuelve el rango del marcador en **todos** los disparadores (antes sólo en un commit sin trailer), lo que agrega un `pwsh` hijo por evento — medido ~1,3 s, el hook pasó de ~1,3 s a ~2,6 s por disparo. Esa mitad cara está adentro del **marcador** (`Get-UntrackedList` hashea todo untracked sin saltear binarios). El gate **también** hashea, en `Get-UntrackedNew`, pero sólo cuando hay una huella contra la cual comparar y sólo si la mitad trackeada volvió toda prosa; medido acá, SHA-256 de un archivo de 12 MB son **~35 ms**, así que esa mitad no es la que pesa. El `4,9 s` que cita el comentario del paso 6 **no se remidió acá** y no se reprodujo en los intentos hechos (`Get-Content -TotalCount 401` sobre 12 MB dio entre 16 y 172 ms según la forma del binario): la cifra viene heredada de `7de07a2` y queda sin atribuir a una causa concreta hasta que alguien la remida. **No hay fixture que fije este costo**; bajarlo es trabajo del marcador, no de este bloque.

**Lo que este archivo de tests NO cubre** (verificado por mutación, no inferido):

- **`.mdx`, `.markdown` y `README.MD`**: el gate sólo trata `.md` como doc, y `-notmatch` es case-insensitive, así que `README.MD` cuenta como prosa y un `.mdx` como código. Es la conducta real medida, pero ningún assert la fija.
- **Slices de sólo borrado** (de prosa o de código): conducta verificada a mano, sin fixture.
- **`gh pr create` como disparador**: todos los casos usan `git push` o `git commit`.
- **El colapso de las tres salidas del contrato del marcador**: el gate usa `if ($range)`, así que trata "exit 0 + vacío" (nada sin revisar) igual que "sin marcador / exit 2" y ensancha el alcance a la rama entera. Dirección fail-open, sin fixture.
- El **caso del acento** y el de **rename** dependen de cómo el git local resuelva paths y similitud; llevan control positivo, pero no se ejercitan bajo otras configuraciones de `core.quotePath`/`diff.renames` globales.
- **Un generado SOLO dispara** (medido: manifest solo → dispara; snapshot solo → dispara; manifest + README → silencio). Es la inversión benigna que documenta el bullet de arriba: sin nada más en el slice, el filtro lo saca, la colección queda vacía y gana la regla de "un slice vacío no es un slice sólo-docs". De las dos mitades de esa inversión, la de `manifest + README → silencio` **sí** está fijada (dos asserts trackeados, más la variante sin trackear); la que no tiene assert es la del generado **solo**.

## Testeo de `gen-mcp-json` (MCP por área)

El generador del `.mcp.json` por proyecto (`scripts/gen-mcp-json.ps1`, uno por skill) se testea con un runner sin Pester: `pwsh -NoProfile -File tests/gen-mcp-json.tests.ps1` (corre ambos scripts como subproceso y verifica `.mcp.json` + el resumen JSON de stdout). Cubre: happy path personal y southpoint, ninguna selección (no escribe archivo), clave inválida por área (`no-existe`, y `zoho-personal` rechazada en southpoint), no pisar sin `-Force`, y `-Force` sobrescribe. Los secretos quedan como literales `${VAR}`.

Evals manuales del flujo del bootstrap (corridos 2026-06-11, ambos OK):

1. **Directorio vacío** — `gen-mcp-json.ps1` personal con `-Servers firebase,zoho-personal` → escribe `.mcp.json` con esos dos servers, el JSON parsea, resumen con `requiredEnvVars=[ZOHO_PERSONAL_MCP_URL]`.
2. **`.mcp.json` preexistente** — sembrar `{"mcpServers":{"MIO":{}}}` y correr `gen-mcp-json.ps1` southpoint con `-Servers domo` sin `-Force` → exit ≠ 0 y `MIO` intacto (no se pisa).

Los workspaces temporales se borran al terminar cada eval.

## Testeo de setup-mcp-workstation

Los dos scripts de la skill se testean con runners sin Pester, cada uno imprime `TODOS LOS TESTS PASARON` o `N test(s) FALLARON` y devuelve el exit code acorde:

- `pwsh -NoProfile -File tests/apply-env.tests.ps1`
- `pwsh -NoProfile -File tests/install-clients.tests.ps1`

**`apply-env.tests.ps1`** cubre: validación de la config (campo faltante → error que **nombra** el campo; config inexistente → error), que la salida **no filtra valores de secretos** (solo nombres de vars + estado), y todo corre con `-DryRun` para no ensuciar el entorno real.

**`install-clients.tests.ps1`** cubre: todos los prereqs presentes (usa `pwsh` como stand-in vía `-GitCmd`/`-PythonCmd`/`-NpxCmd`), y que el comando referencie el repo oficial de DOMO + `requirements.txt`; Git ausente (reporta el prereq, **NO clona**, igual sigue con Playwright), Python ausente (no intenta pip), npx ausente (reporta Node), todo en `-DryRun` (no clona ni instala nada de verdad).

El flujo end-to-end de la skill se evalúa con skill-creator usando el caso *"configurá mi máquina para Southpoint"* (verifica que pida git/DOMO/Zoho, escriba el archivo de config y llame a los dos scripts), con `-DryRun` o un `$env:USERPROFILE` temporal para no tocar el entorno real. El workspace de evals se borra al terminar.
