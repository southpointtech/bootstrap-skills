# Paralelismo por carriles — datos del proyecto

> **Datos de este repo para [`PARALELISMO.md`](PARALELISMO.md)**, que es mecánica y no se edita.
> Este archivo sí se edita, y la norma nombra sus secciones por su título: no las renombres.
>
> - **Cuándo se rellena**: cuando el proyecto ya tiene issues y va a abrir su primera ola. **No
>   se rellena al bootstrapear ni al correr `upgrade-bootstrap`**: el proyecto todavía no tiene
>   camino crítico ni ola, y un dato inventado pasa por medido.
> - **Las marcas**: cada dato sin rellenar va entre dobles llaves. Mientras quede una en este
>   archivo, `.claude/scripts/abrir-carril.ps1` se niega a abrir un carril y lista las líneas
>   (con `-DryRun` las muestra como aviso).
> - **«no aplica» es un valor válido**: un dato que no corresponde a este repo se escribe así,
>   nunca se deja la marca. En el bloque `carriles`, «no aplica» equivale a no declarar la clave
>   y rige el valor por defecto del script.
> - **«Lo que dejó la ola N» arranca vacía** y crece al cerrar cada ola.

## Encabezado

**Fecha**: 2026-09-17 · **Decidido con**: el dueño del repo, en el grill del 2026-09-17 ·
**Alcance**: los issues pendientes del release `bootstrap-v2` (`.scratch/bootstrap-v2/issues/`:
07 a 16, 18 y 19). Decisiones en ADR-0011 y en la sección «Los carriles» de `CONTEXT.md`.

## El camino crítico

Medido el 2026-09-17 sobre el grafo de `.scratch/bootstrap-v2/issues/`, con 01 a 06 y 17 cerrados
y el 20 como slice fundacional de los carriles:

```
07–12 → 13 → 18
```

El 13 está bloqueado por los seis pendientes (07 a 12), así que 09 a 12 son tan del camino crítico como 07 y
08. Aparte: 10 → 16. El 18 (deploy, rollout y resellado) espera a los issues 01 a 17 y al 20; el 19
no lo bloquea y puede ir en cualquier ola. Desbloqueados: 07, 08, 09, 10, 11, 12, 14, 15 y 19.

3 eslabones: se pasa de 12 slices en fila a ~3 niveles, pero con el techo de 3 carriles los 11
anteriores al 18 necesitan al menos 4 olas. Además, 07 a 12 comparten archivos calientes (abajo),
que es lo que decide cuántos de ellos entran en una misma ola.

## Contratos fijados

| Módulo | Firma fijada |
|---|---|
| no aplica | Los issues de v2 no se llaman entre sí por código. Lo que comparten son archivos generados y `CLAUDE.md` (ver «Archivos calientes»). |

## Archivos calientes

Dos listas, no una. **Dueño único** rige sólo para lo **escrito a mano**: un conflicto ahí se
mergea leyendo, y dos carriles editándolo a la vez es una ola perdida. Lo **generado** no lleva
dueño: se regenera. Medido el 2026-09-17 al planear la ola 1: con los generados dentro de la regla
de dueño único, los tres `.bootstrap-manifest.json` —que toca cualquier slice que edite un
scaffold— dejaban la ola en **un solo carril**. Los dos candidatos de la ola 1 que tocan scaffold
(07 y 15) piden espejado en sus criterios de aceptación, así que los dos regeneran manifest.

### Dueño único: uno solo por ola, nombrado en el plan

Quien no es dueño **no lo edita**: escribe en su reporte el diff que necesita y lo aplica el
orquestador al integrar.

- La línea `This delivers:` de los tres `skills/bootstrap-*/SKILL.md`: **escrita a mano**, y
  `tests/mirror.tests.ps1` ata sus conteos a lo que el scaffold tiene de verdad. La tocan todos los
  que suman una skill o un doc de flujo (09, 10, 11, 12, 14 y 16), así que un conflicto acá se
  mergea a mano contando contra el scaffold.
- La allowlist `$allow` de `tests/mirror.tests.ps1`.
- `CLAUDE.md` de la raíz y de los tres scaffolds: los tocan 14 y 20. La norma ya lo reserva al
  orquestador, así que un carril que necesita tocarlo salió de su alcance.

### Generados: sin dueño, pero el carril sella lo que su suite mira

**Nunca a mano**, en ningún caso: un generado se toca corriendo su herramienta. Eso no se negocia.

Lo que sí depende del archivo es **cuándo**:

- **Si su desfasaje pone una suite en rojo, lo sella el carril, en su rama, antes de entregar.**
  Una rama no se entrega roja, y el carril siguiente que corra la suite no tiene por qué ver un
  rojo ajeno.
- **Si no lo pone en rojo, se difiere** al cierre de la ola y el carril lo **declara** en su
  reporte. No hace falta que cada carril regenere lo que el orquestador va a regenerar igual.

En las dos ramas, el orquestador **re-corre la herramienta una vez sobre el árbol ya integrado**:
el sellado de un carril queda invalidado por el merge del siguiente, así que el sellado final es
suyo. Un conflicto al rebasar se resuelve tomando cualquiera de los dos lados y volviendo a correr
la herramienta.

Medido el 2026-09-17, en el review del carril A de la ola 1: la versión anterior de esta regla
decía «una vez, al final de la ola» sin distinguir, el carril no selló `skills-lock.json` —cuya
suite compara el lockfile real contra el árbol real— y entregó la rama con `run-all.ps1` en rojo.
Peor: para meter igual el dato que necesitaba, **editó el archivo generado a mano**, que es lo que
esta regla prohíbe. Las dos mitades de la regla vieja no se sostenían juntas.

- `skills-lock.json` (raíz y los tres scaffolds): `pwsh -NoProfile -File tools/skills-lock.ps1
  -Action Seal`, verificado por `tests/skills-lock.tests.ps1`. Su campo `files` hashea el
  `SKILL.md` de cada skill, así que lo toca **cualquier carril que edite el cuerpo de una skill**:
  07 a 12, 15 y 16. El 19 lo toca sólo si su métrica nueva cambia algún `base`.
- `.bootstrap-manifest.json` de los tres scaffolds: `pwsh -NoProfile -File tools/gen-manifest.ps1
  -SkillDir skills/<bootstrap-x>`. Lo toca cualquier slice que edite un scaffold.
- Los goldens de `tests/fixtures/`: `tools/reseal-step0b.ps1` (Step 0b), `tools/reseal-step5.ps1
  -Block <nombre>` (`step5`, `tdd-loop`, `fan-out`, `agents`) y `tools/reseal-goldens.ps1` (Step 2
  y techos). `fan-out` congela el Step 3 y el Step 4 de `slice-review`, y `agents` los siete
  `.claude/agents/slice-review-*.md`, los dos verificados por `tests/reviewer-agents.tests.ps1`:
  **un carril que toque el Step 3 o el 4 de `slice-review`, o cualquier agent, mueve esos goldens**
  y los resella con la herramienta, mirando el diff.
- `.scratch/bootstrap-v2/skill-bases.json`: gitignoreado, así que cada carril recibe su copia y
  lo que cambie ahí **no viaja por git**. El orquestador lo re-aplica en el worktree de v2 al
  integrar.

## Config compartida

- `tools/leak-markers.txt` (append-only; `tests/shareable-leaks.tests.ps1` asserta su conteo).
- `.claude/settings.json` de la raíz y de los tres scaffolds.

## Recursos compartidos

| Recurso | Aislamiento por carril |
|---|---|
| Temporales de las suites en `%TEMP%` | Ya aislados: cada corrida cuelga de su propia raíz (`tests/lib/temp-workspace.ps1`, PID + GUID) y la recolección de huérfanos es por edad (> 1 día), así que dos suites concurrentes no se pisan. |
| Base de datos / emulador | no aplica |
| Puertos | no aplica: no hay servidores ni E2E de navegador. |
| Deploy a `~/.claude/skills` (`tools/sync-skills.ps1`) | Lo corre sólo el orquestador, en el issue 18. Ningún carril deploya. |

## Lo que un worktree no hereda

| Qué | Cómo se resuelve |
|---|---|
| `.scratch/` (issues, PRD y `skill-bases.json` de v2) | Lo copia `abrir-carril.ps1` (clave `copiar`). |
| `node_modules/`, venv | no aplica: los tests son PowerShell y `tools/recover-skill-bases.py` usa el Python de la máquina, sin dependencias instaladas. |

## Guardas transversales

- `tests/mirror.tests.ps1`: espejado de los tres scaffolds y golden del Step 0b.
- `tests/shareable-leaks.tests.ps1`: nada publicable filtra datos personales.
- `tests/temp-hygiene.tests.ps1`: toda suite usa el helper de temporales con su `trap`.

Comando: `pwsh -NoProfile -File tests/<suite>.tests.ps1`. La suite completa
(`pwsh -NoProfile -File tests/run-all.ps1`) la corre sólo el orquestador.

## El bloque que lee el script

`abrir-carril.ps1` lee sólo este bloque. Claves: `copiar` (rutas gitignoreadas, separadas por
coma), `worktrees` (carpeta de los worktrees, fuera del repo) y `base` (rama de la que salen los
carriles y donde se integran). Una clave distinta es un error. Un parámetro del script gana sobre
el bloque.

```carriles
copiar: .scratch
worktrees: C:\Repos\PERSONAL\carriles\Bootstrap Skills
base: feat/bootstrap-v2
```

La sesión del orquestador vive en `main`, en `C:\Repos\PERSONAL\Bootstrap Skills`, y
`feat/bootstrap-v2` está checkouteada en su propio worktree
(`C:\Repos\PERSONAL\Bootstrap-Skills-bootstrap-v2`). Por eso el script se corre desde ese
worktree, e integra el orquestador con `git -C` sobre él. El hook no dispara desde `main`: el
`/review-loop` de cada carril lo corre el orquestador, a mano y en serie.

## La ola vigente

**Ola 4** · Aprobada por el dueño del repo el 2026-09-19 · Base `feat/bootstrap-v2` @ `25f4bac`
(slice light de Lows, `run-all.ps1` verde, 33 suites).

**Cerrada el 2026-09-19**: integrada en `feat/bootstrap-v2` @ `5151ce4`, `run-all.ps1` verde (34
suites) sobre el árbol integrado. Dejó dos issues nuevos, los dos fuera del alcance de sus slices y
verificados por el confidence pass: **23** (`merge-settings.ps1` reconcilia comandos, nunca el
`matcher` de una entrada que ya existe) y **24** (`Hide-Literals` parsea comillas de bash y pierde
un cierre declarado desde PowerShell con rutas de Windows).

Las olas 1 (07, 15, 19), 2 (09, 10, 08) y 3 (12, 11, 16) cerraron el 2026-09-18 y el 2026-09-19 en
`628c84b`, `6e1a0e9` y `c7faaa5`; sus planes quedaron en el historial de este archivo
(`git log -p`) y sus lecciones, abajo.

| Carril | Slice | Dueño de | Caliente escrito a mano |
|---|---|---|---|
| **A** (camino crítico) | 13 — política de invocación con test declarativo | `.claude/commands/{grill-me,grill-with-docs,to-prd,to-issues,triage,handoff}.md` y `.agents/skills/<esas 6>/SKILL.md` (raíz + 3 scaffolds), y `tests/invocation-policy.tests.ps1` (nuevo) | no |
| **B** | 21 — el matcher del `review-loop-trigger` no cubre la herramienta PowerShell | `.claude/settings.json` (raíz + 3 scaffolds) y los casos nuevos de `tests/review-loop-trigger.tests.ps1` | **dueño** de `settings.json`, que es config compartida |

Integración: **A → B**. A es el más grande y el único que mueve `skills-lock.json`; B rebasa contra
cuatro líneas de JSON y un test.

Afuera: 14 es `CLAUDE.md` y la norma lo reserva al orquestador, así que va en serie entre olas; 18
es HITL y va último. Los Lows del slice `25f4bac` van en un slice light después de esta ola.

Medido al repartir (2026-09-19, sobre `25f4bac`):

- Ningún archivo escrito a mano aparece en dos filas: A toca comandos y skills, B toca
  `settings.json` y el test del hook.
- Los tres `.bootstrap-manifest.json` los tocan los dos: son generados y el orquestador los
  re-sella sobre el árbol integrado. `skills-lock.json` lo mueve **solo A** (hashea el `SKILL.md`
  de cada skill) y su suite se pone roja si no sella: **A sella en su rama antes de entregar**.
- Tamaño de A: 6 comandos × 2 archivos × 4 raíces = 48 ediciones de frontmatter de una línea, más
  el test. Tamaño de B: cuatro líneas de `matcher` más los casos del test. Los dos bajo ~400.
- Listado de skills (descriptions de `.claude/commands/`, que es lo que carga en cada request):
  hoy **6.667 ch en 18 comandos**; con la regla, **5.709 en 12** (−14 %). Entra en el presupuesto
  del 1 % de la ventana (~8.000 ch en 200k). El **"+12 %" del issue 13 no se sostiene**: es de
  antes de las skills de las olas 2 y 3. **Corregido al integrar el carril A (2026-09-19)**: la
  línea base del 2026-08-28 no es 2.996 ch / 11 comandos sino **2.062 / 9** —`setup-matt-pocock-
  skills` y `zoom-out` ya llevaban el flag, así que no cargaban—, y el release queda en **+176,9 %**,
  no en el +91 % que decía este plan. El 2.996 sale de otro método, que la nota de research no
  declara: el frontmatter entero menos la línea `name:`, o sea sumándole el `argument-hint` y la
  propia línea del flag. Está anotado en el encabezado de `tests/invocation-policy.tests.ps1`.
  Las seis descriptions model-invoked más largas suman
  3.780 ch, el 66 % del listado (`verify-downstream-arrival` 746, `debug-source-first` 666,
  `domain-modeling` 631, `wizard` 612, `diagnosing-bugs` 583, `grilling` 542). **Decisión del
  dueño del repo (2026-09-19): la disciplina es de clasificación, no de caracteres — no se
  recortan; el carril corrige el número en el issue y lo deja anotado.**
- Restricción del issue 13 verificada antes de repartir: ninguna de las 6 user-invoked es invocada
  por otra skill ni por un hook. El `alignment-gate` **ofrece** `/grill-me` al usuario (no lo
  invoca) y las menciones en `setup-matt-pocock-skills` son referencias en prosa.

Lo que cada carril resuelve antes del primer test:

- 13: el flag va en el comando, en el `SKILL.md`, o en los dos. `.agents/skills/` no lo lee Claude
  Code, pero las tres skills ya clasificadas (`zoom-out`, `to-questionnaire`,
  `setup-matt-pocock-skills`) lo llevan en ambos → técnica: el carril sigue ese precedente y el
  test lee el frontmatter real de los comandos, como pide el issue.
- 13: las descriptions user-invoked pasan a una línea human-facing, lo que edita el frontmatter de
  skills sincronizadas de mattpocock y las desvía del upstream → técnica: el carril lo hace, lo
  declara en su reporte y sella el lockfile en su rama.
- 21: cómo se llama la herramienta en el campo `tool_name` del evento, y si el matcher acepta la
  misma alternancia que el `alignment-gate` → técnica: lo mide el carril con un hook de
  diagnóstico en un directorio temporal, lo pega en el issue y borra el hook y el log.
- 21: el hook no mira `tool_name` (solo `tool_input.command`), así que el sujeto del test nuevo es
  el `matcher` de `settings.json` evaluado como regex → técnica: la decide el carril.
- 21: el hook de `git-guardrails-claude-code` tiene el mismo defecto de clase (anotado por la ola
  3) → queda **afuera**: el issue prohíbe ensanchar guards de paso.


## Lo que dejó la ola N

### Ola 4 (13, 21), cerrada el 2026-09-19

- **El número que el orquestador le pasa a un carril entra al repo con su firma.** El brief del
  carril A llevaba una línea base sacada de la memoria del proyecto (2.996 ch / 11 comandos); el
  carril la escribió en un comentario, en el issue y en el mensaje del commit, y el review demostró
  que sale de un método que ninguna nota declara —el frontmatter entero menos la línea `name:`, que
  suma el `argument-hint` y hasta la propia línea `disable-model-invocation: true`—. Bajo el método
  que el slice declara son 2.062 / 9. Un dato heredado no está verificado por haber sido heredado;
  si el brief lo trae, el brief tiene que decir de dónde sale. Vale para cualquier proyecto.
- **Corregir un número en un solo lugar deja el repo contradiciéndose.** El turno 1 lo arregló en el
  test; el turno 2 encontró el viejo todavía en `PARALELISMO-DEL-PROYECTO.md` (este archivo) y en el
  issue. Al retractar un dato, la lista de lugares se arma ANTES de editar: `grep` del número, no
  memoria.
- **Un fix de prosa puede matar una guarda.** Sacar el `"` pelado de la lista de marcas de agente
  —para evitar un falso positivo que no existía en el árbol— se llevó puesta la única marca que
  atrapaba a `zoom-out`. Antes de relajar una heurística: qué positivo verdadero estaba sosteniendo.
  La reemplazó una marca estructural (dos pares de comillas o más = lista de triggers).
- **`.scratch/` es por worktree y no viaja en el merge.** El carril B midió el `tool_name` y lo pegó
  en el issue de SU worktree; el criterio de aceptación pedía el issue del repo. El coherence pass
  lo encontró. Lo que un carril escribe en `.scratch/` lo copia el orquestador al integrar, o se
  pierde.
- **Medir antes de creerle a un hallazgo repetido.** Cuatro reviewers reportaron como mutante vivo
  una skill sin clasificar; el confidence pass mostró que muere en la suite del lockfile. Y dos
  reviewers del turno 2 propusieron "corregir" 12 sondas a 11: el 12 era correcto y la enumeración
  estaba incompleta. Un hallazgo repetido no es un hallazgo verificado.
- **El reviewer mide lo que el carril no midió.** El carril B declaró abiertamente que no sabía si
  el matcher era anclado o case-sensitive; un scorer lo midió con 12 sondas y dos corridas de
  `claude -p`: es **case-sensitive y anclado**. Eso convirtió el oráculo del test (que usaba
  `-notmatch`, case-insensitive y sin anclar) en un fix necesario.
- Los dos carriles cerraron el review-loop en dos turnos: A por tope (el turno 2 encontró Medium en
  los fixes del turno 1), B limpio. Los dos con coherencia corrida; la de B encontró el criterio de
  aceptación sin cumplir.

### Ola 3 (12, 11, 16), cerrada el 2026-09-19

- **Un archivo que un carril escribe antes de que otro traiga un `.gitattributes` queda con el fin
  de línea viejo en disco.** Git no reescribe archivos existentes cuando cambian los atributos, y el
  cherry-pick solo toca los paths de cada commit: los `.sh` del carril A quedaron CRLF aunque el
  índice fuera LF y `git status` estuviera limpio. Se detecta con `git ls-files --eol` (`w/crlf`) y
  se arregla borrando el archivo y volviendo a sacarlo; `git add --renormalize` arregla el índice,
  no el disco. Vale para cualquier proyecto: candidata a subir a la mecánica.
- **El lockfile chocó al integrar el tercer carril y se resolvió con la herramienta, no leyendo.**
  Tomar un lado, `recover-skill-bases.py` sobre el árbol integrado y `Seal -Bases`: esta vez ningún
  veredicto se movió respecto de los carriles (a diferencia de la ola 1).
- **Dos loops cerraron por tope (A y B) y uno limpio (C).** En A y B los Medium del turno 2 fueron
  prosa que instruye al agente (qué bloquea el guardrail, cuándo parar) y un test que miraba el blob
  en vez del disco; sus arreglos no tienen review propio.
- **Los reviewers vuelven a proponer fijar en los tests lo que el lockfile ya sella** (campos de la
  base, cuerpos adoptados, anclas de reglas). En los cinco casos el scorer lo dejó en Low o lo
  descartó, por diseño: el lockfile es el golden y re-sellar es el acto revisado. La excepción fue
  `writing-for-agents`, que vive fuera del lockfile: ahí sí subió a Medium y se fijó por hash.
- **El foco `--code-review` no corrió en ningún carril**: el fork revisa la cwd de la sesión
  (`main`), no el worktree del carril. Y `review-marker -Action range`/`slice-base` siguen dando el
  merge-base con `main` en los worktrees de carril: se usaron rangos explícitos.


### Ola 2 (09, 10, 08), cerrada el 2026-09-18

- **Los tres review-loops cerraron limpios** (09 y 10 en el turno 2, 08 en el turno 1), a diferencia
  de la ola 1, donde los tres cerraron por tope. Cada uno tuvo un solo Medium real o ninguno; el
  resto de los hallazgos cayeron en el scorer como Low o como diseño preexistente.
- **Integrar en el orden de las dependencias de prosa.** El 08 adoptó el cuerpo de `triage`, que
  llama a `grilling` y `domain-modeling`, que trae el 09. Integrar A → B → C dejó cada nombre
  existiendo antes de que entrara quien lo nombra. Las referencias de prosa entre carriles de la
  misma ola no violan el reparto, pero fijan el orden de integración.
- **Lo que un carril difiere al orquestador va en el brief de la coherencia.** El 10 difirió los
  manifests, como manda la regla de generados, y el pase de coherencia lo reportó como Medium
  («half-wired»). No era un defecto: el brief no le decía que estaba declarado.
- **`gen-manifest` sobre el árbol integrado cambia hashes de archivos ajenos** (siete, por el fin de
  línea en disco: el bug conocido de hashes crudos con `autocrlf`). Que los carriles difieran los
  manifests evita ese ruido en cada rama y lo deja en un solo commit de integración, declarado.
- **Los mutantes por AÑADIDO sobreviven a los tests del carril y los mata el hash del lockfile.**
  Pasó en los tres. El scorer lo clasificó como diseño (el lockfile es el golden de las skills
  adoptadas), no como hueco del slice: agregar anclas no es el arreglo.
- **Un agente `Plan` tiene `Bash`, y el pase de coherencia del 09 corrió las suites** aunque el brief
  decía «no ejecutes nada». No ensució el árbol, pero la prohibición en prosa no alcanza: sin los
  agents declarados cargados (sesión abierta en `main`), el único freno es mirar el árbol después.

### Ola 1 (07, 15, 19), cerrada el 2026-09-18

- **Una predicción de un carril sobre otro se re-mide en el árbol integrado.** El carril C midió
  sobre `98a8f36` que su métrica nueva «no cambia ningún veredicto». Con el carril A adentro sí
  cambió uno: la base de `to-issues` pasó de `4a21285c` a `e868c831`. Y la equivocada era la
  vieja, que el carril A había sellado con la métrica por carácter. Ninguno de los dos carriles
  podía verlo desde su rama. El orquestador corre la herramienta sobre el árbol integrado **antes**
  de sellar, y explica por escrito cada veredicto que se mueva.
- **Integrar por cherry-pick en el worktree de la base, no rebasando las ramas de carril.** Las
  ramas conservan los SHAs que revisó el loop, y el orden A → B → C salió sin conflictos: el único
  archivo que tocaban dos carriles era `skills-lock.json`, un generado, que se auto-mergeó y
  después se re-selló igual.
- **Los números del reporte de un carril se re-miden antes de pasarlos a docs.** Los tiempos del
  carril C (6,2 s contra 109,1 s) salieron hoy en 5,6 s contra 94,5 s: la proporción se mantiene,
  los absolutos dependen de la carga. Un doc que los copia sin re-medir afirma un número que nadie
  verificó.
- **Los tres review-loops cerraron por tope**, ninguno limpio, y dos carriles pasaron el techo de
  ~400 líneas de lógica, declarado en vez de partido (B ~505; C ~455 contando el generador).
