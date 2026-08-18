# Cómo testear las skills

Las skills se testean con el **skill-creator** (`/skill-creator:skill-creator` en Claude Code), que orquesta: runs con skill + baseline en directorios temporales → grading con assertions → benchmark → viewer HTML para revisión humana.

## Test cases canónicos (re-usar estos)

1. **Southpoint, directorio vacío** — "Acabo de crear esta carpeta para un proyecto nuevo de Southpoint: un tablero de inventario para KBS (se llama 'KBS Inventory'). Dejame el directorio listo con todos los archivos base para arrancar, como hicimos en Forecasting App."
2. **Personal, directorio vacío** — "ok arranco un proyecto personal aca, una app para trackear mis gastos del mes. preparame el ambiente y el repo con el setup base antes de escribir nada de codigo"
3. **Southpoint, archivos preexistentes** — sembrar `src/index.js` y un `README.md` propio ("WIP - notas propias del proyecto") y pedir: "Este repo ya tiene un par de archivos del proyecto nuevo de Southpoint (KBS Inventory). Armame el scaffolding del workflow de AI sin romper lo que ya hay."
4. **Southpoint, adopción (CLAUDE.md propio sin manifest)** — sembrar un `CLAUDE.md` hecho a mano (branching model main/develop + un gotcha técnico + una mención a DOMO) y un `worker.js`, sin `.bootstrap-manifest.json`, y pedir: "agregale el bootstrap a este proyecto". Debe entrar en **modo adopción** (Step 0b), no frenar ni derivar a upgrade-bootstrap.

## Assertions clave (lo que define "pasa")

- Scaffold completo: CLAUDE.md (8 pasos + Workflow State Machine), 5 docs ai-workflow, 10 skills `.agents` (9 de mattpocock vía `skills-lock.json` + `review-loop` propia), 10 comandos `.claude`, 3 docs agents, `.gitignore` (con `.scratch/`), `skills-lock.json`, `.bootstrap-manifest.json`, `.claude/settings.json`, `.claude/hooks/review-loop-trigger.ps1`, `.claude/hooks/alignment-gate.ps1`, README, CONTEXT.md stub, `docs/adr/`.
- Variante correcta: Southpoint menciona DOMO; personal CERO menciones a DOMO pero conserva Playwright/Firebase/Azure/Zoho.
- Git: branch `main`, **un solo commit**, autor exacto según variante, config local (global intacta).
- Sin duplicados anidados (`.agents\.agents`, `.claude\.claude`) — regresión del bug de iter 1.
- No se adelanta: sin package.json, sin src/ (en dirs vacíos), sin ADRs inventados, sin PRD.
- Preexistentes intactos byte a byte y commiteados.
- Modo adopción: `docs/agents/legacy-claude.md` existe y es **byte-idéntico** al `CLAUDE.md` original sembrado.
- Modo adopción: el `CLAUDE.md` final es el canónico (contiene "Workflow State Machine"); las reglas operativas del original aparecen en su sección `## Hard rules`; el conocimiento de dominio del original aparece en `docs/agents/domain.md`.
- Modo adopción: cada bloque del original quedó representado (en `legacy-claude.md` + su destino); ningún bloque se perdió en silencio.
- Modo adopción: tras adoptar, `compare-scaffold.ps1` clasifica `CLAUDE.md` como **customized** (ni `outdated` ni `uptodate`), confirmando que un upgrade futuro no lo pisa.

## Gotchas operativos del entorno de testing

- Los agentes baseline en el entorno de Forecasting App pueden copiar del repo real → baseline inflado; correr los tests desde un cwd neutro si se quiere baseline puro.
- El viewer (`generate_review.py`) en Windows necesita `$env:PYTHONUTF8 = "1"` (crash cp1252 si no).
- El agregador (`scripts.aggregate_benchmark`) espera `eval-N/<config>/run-1/grading.json` y un bloque `summary` `{pass_rate, passed, failed, total}` en cada grading.
- Si un run baseline corre `npm install`, borrar su `node_modules` antes de levantar el viewer (el escaneo recursivo se cuelga).
- Borrar el workspace de evals al terminar (regla del repo).

## Testeo de `upgrade-bootstrap`

La skill que actualiza proyectos ya bootstrapeados se testea con fixtures (no con skill-creator), porque su lógica vive en los scripts `compare-scaffold.ps1` y `reseal-manifest.ps1`. Casos de regresión:

1. **Manifest + desactualizado-no-tocado** — proyecto con `.bootstrap-manifest.json` y un archivo cuyo hash actual == base pero != canónico → debe clasificar `outdated` (seguro de actualizar).
2. **Manifest + personalizado** — archivo cuyo hash actual != base → debe clasificar `customized` (no pisar).
3. **Legacy sin manifest** — proyecto bootstrapeado con la versión vieja (sin manifest): `hasProjectManifest=False`, detecta `missing` (los 2 de `review-loop`, y ahora también `.claude/hooks/alignment-gate.ps1`) y `customized` los que difieren; tras aplicar, siembra el manifest.
4. **Al día** — proyecto recién bootstrapeado: `missing/outdated/customized` vacíos, `uptodate` == 48.

Los fixtures determinísticos para los casos 1-2 y el re-sellado están en el plan `docs/superpowers/plans/2026-06-10-upgrade-bootstrap-skill.md` (Tasks 4-5); los casos 3-4 corren contra el scaffold instalado (Task 8).

## Testeo de la copia del scaffold (`copy-scaffold.ps1`)

La copia del Step 2 (`skills/*/scripts/copy-scaffold.ps1`, espejada en ambas skills bootstrap) se testea con un runner sin Pester: `pwsh -NoProfile -File tests/copy-scaffold.tests.ps1` (fixtures en directorios temporales, imprime `TODOS LOS TESTS PASARON` o `N test(s) FALLARON`). Casos cubiertos:

- **Destino vacío** — aterrizan los 50 archivos (11 skills en `.agents/skills`), sin `.agents/.agents` ni `.claude/.claude`, `gitignore.txt` → `.gitignore` con contenido idéntico.
- **Regresión `docs/docs`** — `docs/` y `docs/agents/` preexistentes en el proyecto → el contenido se mergea (sin anidar) y los archivos propios quedan intactos (gotcha del self-bootstrap 2026-06-23).
- **Dot-dirs preexistentes** — `.claude/` con archivos propios → merge sin anidar ni pisar lo ajeno.
- **Conflicto de archivo** — un `CLAUDE.md` preexistente es reemplazado por el canónico (semántica del Step 2; en adopción el original ya está stasheado).
- **Paths con corchetes** — un proyecto `...[v2]` copia igual (paths literales, sin interpretación de wildcards).
- **Espejado** — los dos `copy-scaffold.ps1` son byte-idénticos (hash SHA256).

## Testeo del motor del review-loop (`/slice-review`)

El paso 1 del loop tiene que ser **invocable por el agente**. El built-in `/code-review` está marcado `disable-model-invocation` (falla con `Skill code-review cannot be used with Skill tool`), así que un loop apoyado en él nunca cierra solo: el hook `review-loop-trigger` ordena algo imposible de cumplir y el slice termina reportado como "revisado" sin que haya corrido ningún reviewer. Por eso el scaffold trae `/slice-review` (reviewer multi-agente sobre el diff local). Runner: `pwsh -NoProfile -File tests/slice-review.tests.ps1`. Casos cubiertos, en las tres skills bootstrap:

- **Existencia del par** — `.claude/commands/slice-review.md` y `.agents/skills/slice-review/SKILL.md` presentes.
- **Invocabilidad** — ambos declaran `description` en el frontmatter y **ninguno** setea `disable-model-invocation: true`.
- **Regresión a `/code-review`** — ningún archivo del par (ni el de `review-loop`) *ordena* correr `/code-review`; mencionarlo para explicar por qué no se usa sí está permitido.
- **El motor del loop** — `review-loop` (command y SKILL.md) corre `/slice-review` como paso numerado. El assert no fija el número: desde el turno incremental el paso 1 es pedirle el rango al marcador y la corrida de review es el paso 2. Lo que se blinda es el motor, no su posición.

## Testeo del marcador de revisión y del turno incremental

El loop revisa el **delta sin revisar**, no el rango completo de la rama en cada turno. Dos runners lo cubren.

`pwsh -NoProfile -File tests/review-marker.tests.ps1` — el script `.claude/scripts/review-marker.ps1` sobre repos git temporales (runner sin Pester). Casos cubiertos:

- **Los cuatro verbos** — `advance` fija un punto de corte resoluble, `get` lo devuelve, `range` dice qué pasarle a `git diff`, y `base` devuelve la base del slice (un merge-base) para que el hook **delegue** la resolución de base cuando sus propias ramas nombradas fallan. `base` comparte el resolvedor de `range` (`Get-SliceBase`) y su contrato de exit codes: 0 + ref resoluble, o **exit 2 + vacío** cuando no hay base determinable — nunca 0 + vacío, que el hook leería como "no hay nada que revisar". Fixture: base `trunk` devuelve el merge-base; repo de una sola rama da exit 2.
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
- **El disparador se lee del comando normalizado, no del crudo** — el comando incluye el texto del `-m`, así que un commit cuyo mensaje menciona `git push` prendía la bandera del push y salteaba la puerta del trailer entera; y `git -C <repo> push` no matcheaba ningún patrón, así que un push legítimo nunca disparaba. Hay fixture para los dos, y para las dos formas en que un blanqueo por regex falla: comillas **escapadas** (`\"git push\"`, que dispara cuando no debe), un **apóstrofe** en el mensaje (`-m "don't" && git push`, que se traga el push real) y el apóstrofe **escrito a la bash** (`'\''`, que cierra y reabre el literal: leído sin mirar el escape de afuera dejaba el resto del mensaje expuesto). Por eso los literales se recorren en vez de reemplazarse por regex. La sustitución de comandos `$(...)` y los backticks reinician el contexto de comillas de bash adentro y desalineaban el recorrido en las dos direcciones (perdían un `git push` real y también un cierre declarado). **A2b lo cierra sin modelar `$()`**: cuando el comando contiene `$(` o un backtick, las banderas se recalculan sobre el comando **crudo** y se combinan con OR, así que todo falso negativo se vuelve falso positivo (un review-loop de más, la dirección segura). Fixture: `git commit -m "$(sed 's/"/x/' f)" && git push` dispara (mutante = sacar el OR → rojo), y `echo "$(...)" && git commit -m cierre` con trailer no queda mudo. Los usos naturales (`date +"%F"`) mantienen número par de comillas y no llegan a esa rama.
- **Red de seguridad por techo** — un commit sin trailer cuyo delta sin revisar pasa las ~400 líneas dispara igual, y el techo se mide sobre el rango del **marcador**, no sobre el rango completo de la rama (mutado a mano: ignorar el marcador pone el caso en rojo). El **borde de abajo** también está fijado (200 líneas no disparan): sin ese caso, mutar `-le 400` a `-le 100` sobrevivía la suite entera.
- **El techo se mide sobre el repo entero** — los pathspec y `ls-files` se resuelven contra el cwd del proceso git, y el evento trae el cwd de la **sesión**, que en un monorepo es un subdirectorio: sin anclar a la raíz, la red de seguridad medía sólo ese subárbol y desaparecía en silencio. Hay fixture para la mitad trackeada y para la untracked. Y para la **ruta del repo** no-ASCII, que es la otra mitad del problema de encoding: sin forzar UTF-8 una sola vez arriba de todo (y no sólo alrededor del `ls-files`), `rev-parse --show-toplevel` bajo `C:\Users\Martín\...` vuelve mojibake, el `git -C $root diff` del techo falla, `$measurable` queda en falso y la red **dispara siempre**, en silencio. Ese fixture fuerza la code page a 850 **dentro del hijo** para ser determinístico en cualquier máquina, lo que obliga a invocar el hook en-proceso en vez de con `pwsh -File` como lo invoca Claude Code — la misma concesión que el caso no-ASCII del marcador.
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

- La **resolución de la base** por `gh repo view` y por `origin/HEAD` con rama local ausente: ningún fixture tiene remote, así que esos dos caminos nunca corren.
- Que el fold de opciones globales cubra algo más que `-C`: `--git-dir`, `--work-tree`, `-c`, `--no-pager` y `--paginate` están en el patrón pero no tienen fixture. Sólo afecta al reconocimiento del disparador (que un `git --git-dir=x push` se lea como push); ya no hay atribución que pueda equivocarse con ellos.
- La rama de **comilla sin cerrar** de `Hide-Literals`: se come el resto de la línea, y eso no es observable por conducta — todo lo que queda después ya está enmascarado, así que ningún comando distingue la versión correcta de la que dejaba el último carácter afuera. Se arregló porque el comentario afirmaba lo que el código no hacía, no porque haya un caso que lo pruebe.
- La **sustitución de comandos** `$(...)`: bash reinicia el contexto de comillas adentro, y `Hide-Literals` no lo modela. Ya **no** es un límite sin repro — el 2026-08-14 se reprodujo sobre la función real, y falla en las dos direcciones, no sólo en la del falso positivo que se sospechaba:

  ```bash
  git commit -m "$(sed 's/"/x/' f)" && git push      # isPush=False   <- push REAL perdido
  echo "$(sed 's/"/x/' f)" && git commit -m cierre   # isCommit=False <- cierre declarado perdido
  git commit -m "wrote $(echo "git push") today"     # isPush=True    <- dispara salteando gate, frescura y techo
  ```

  Mecanismo: una comilla **doble** dentro de comillas **simples** dentro de la sustitución deja el total de dobles en número **impar**, el recorrido de literales se desalinea y se traga el resto de la línea. Lo que acota la severidad a media es que los usos naturales tienen número **par** y se re-alinean solos: `git commit -m "fecha $(date +"%F")" && git push` mide `isPush=True`, o sea correcto (medido). Sigue **sin arreglar** y sin fixture: el fix va en A2b, y la opción elegida es no modelar `$()` sino calcular las banderas también sobre el comando crudo cuando aparece `$(` o un backtick, quedándose con el OR — convierte todo falso negativo en falso positivo, que es la dirección que este hook ya declaró segura.
- Los **heredocs**: el blanqueo de literales entrecomillados no los toca, así que un mensaje de commit pasado por heredoc que mencione `git push` sigue prendiendo la bandera. Degrada al comportamiento anterior al fix, no a algo peor.
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
