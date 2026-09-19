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

**Ola 3** · Aprobada por el dueño del repo el 2026-09-19 · Base `feat/bootstrap-v2` en el commit de
este plan, sobre `b9a9139` (el arreglo previo del frontmatter de `review-loop`, que Claude Code
descartaba entero por un `: ` sin comillas).

Las olas 1 (07, 15, 19) y 2 (09, 10, 08) cerraron el 2026-09-18 en `628c84b` y `6e1a0e9`; sus
planes quedaron en el historial de este archivo (`git log -p`) y sus lecciones, abajo.

| Carril | Slice | Dueño de | Caliente escrito a mano |
|---|---|---|---|
| **A** (camino crítico) | 12 — `research`, `resolving-merge-conflicts` y `git-guardrails-claude-code` al scaffold; `writing-for-agents` solo en este repo; `zoom-out` | `.agents/skills/{research,resolving-merge-conflicts,git-guardrails-claude-code,zoom-out}/` y sus `.claude/commands/` (raíz + 3 scaffolds), y `.claude/skills/writing-for-agents/` (solo raíz; ver «Correcciones al integrar») | **dueño** de `This delivers:` y de la allowlist `$allow` |
| **B** (camino crítico) | 11 — `wizard` + `to-questionnaire` | `.agents/skills/{wizard,to-questionnaire}/` y sus `.claude/commands/` (raíz + 3 scaffolds) | no: el diff que necesita en `This delivers:` va en su reporte |
| **C** | 16 — `verify-downstream-arrival` + `debug-source-first` al scaffold | `.agents/skills/{verify-downstream-arrival,debug-source-first}/` y sus `.claude/commands/`, y la sección `## Where this fits` de `.agents/skills/diagnosing-bugs/` (raíz + 3 scaffolds) | no: diff en su reporte; si necesita marcas nuevas, las agrega al final de `tools/leak-markers.txt` |

Integración: **A → B → C**. C va último porque es el único que edita una skill ya integrada
(`diagnosing-bugs`), y A primero porque es el dueño de `This delivers:` y `$allow`.

Afuera: 13 espera a 11 y 12; 21 no es del camino crítico y va a la ola 4 junto al 13; 14 es
`CLAUDE.md` y va en serie entre olas; 18 es HITL y va último. Los Lows sueltos de la ola 2 van en
un slice light después de esta ola.

Medido al repartir (2026-09-19, contra el clon de upstream en `959a8e9`, cuerpo + auxiliares, y
contra las copias de usuario en `~/.claude/skills/`):

- `research` 15 líneas (2 archivos), `resolving-merge-conflicts` 17 (2),
  `git-guardrails-claude-code` 123 (3, con `scripts/block-dangerous-git.sh`), `writing-for-agents`
  106 (3). `zoom-out` no está en el HEAD de upstream.
- `wizard` 251 (3, con `template.sh`), `to-questionnaire` 59 (2).
- `debug-source-first` 167 y `verify-downstream-arrival` 107 (1 archivo cada una), con 11 líneas
  que nombran herramientas o clientes puntuales. Es el único carril con prosa propia que escribir.
- Ningún archivo escrito a mano aparece en dos filas. `skills-lock.json` y los tres
  `.bootstrap-manifest.json` los tocan los tres carriles: son generados, y el orquestador los
  re-sella sobre el árbol integrado.

Corrección al issue 12, decidida por el orquestador: el issue pide marcar `zoom-out` como fork
propio sin base, pero el lockfile ya la selló como `upstream-huerfano` con la base que recuperó la
similitud (`7afa86d`), y `tests/skills-lock.tests.ps1` exige exactamente eso para una skill que
upstream borró (ADR-0005: colapsarla en `fork-propio` tira su base). El criterio pasa a ser:
**`zoom-out` sigue como `upstream-huerfano`, y un test verifica que ese estado no se reporta como
faltante ni se borra.**

Correcciones al integrar (2026-09-19):

- `writing-for-agents` no entró en `.agents/skills/` de la raíz: `tools/skills-lock.ps1 -Action Seal`
  exige el mismo árbol de skills en las cuatro raíces y se negó a sellar. El dueño del repo eligió
  instalarla como skill nativa de proyecto en `.claude/skills/writing-for-agents/`, fuera del
  lockfile y de los scaffolds; el test la fija por hash normalizado contra el blob de upstream.
- `research`: el carril A midió con `claude -p` que, con una skill de usuario del mismo nombre en
  `~/.claude/skills/research`, gana la de usuario y la del proyecto no se lista. Lo mismo se espera,
  sin medir, para `debug-source-first` y `verify-downstream-arrival`. Decisión del dueño: retirar las
  tres copias de usuario al deployar (nota en el issue 18).
- `to-questionnaire` entra ya con `disable-model-invocation: true` (decisión delegada al carril B):
  es una skill nueva, upstream la trae así y el issue 13 la clasifica user-invoked. A diferencia de
  07 y 08, no cambia la invocación de una skill ya instalada. Nota en el issue 13.
- `.gitattributes` en la raíz con `*.sh text eol=lf` (carril B, por el review): con
  `core.autocrlf=true` un checkout escribía los `.sh` con CRLF y bash de WSL no los corre.
  `tests/sh-eol.tests.ps1` lo verifica en el blob, el atributo y el disco. Al integrar, los `.sh`
  del carril A quedaron CRLF en disco (git no reescribe archivos existentes al cambiar atributos):
  se borraron y se volvieron a sacar con `git checkout -- <f>`.

Lo que cada carril resuelve antes del primer test:

- 12: `research` ya existe como skill de usuario (`~/.claude/skills/research`, 10 líneas). Cuál
  gana cuando están las dos → técnica: la mide el carril y la deja escrita.
- 12: el hook de `git-guardrails-claude-code` se engancha solo a la herramienta Bash y no cubre la
  de PowerShell (la misma clase que el issue 21) → técnica: el carril lo deja dicho; no toca
  `.claude/settings.json`.
- 11: `wizard/template.sh` viaja al scaffold o se retira, con el precedente de la plantilla HITL
  del 10 → técnica: la decide el carril y la deja dicha en la skill y en su reporte.
- 16: la extensión de `debug-source-first` para valores equivocados sobrevive, y su paso 5 devuelve
  a `diagnosing-bugs` en vez de a `superpowers:systematic-debugging` (nota de la ola 2 en el issue)
  → decidido en el issue.

## Lo que dejó la ola N

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
