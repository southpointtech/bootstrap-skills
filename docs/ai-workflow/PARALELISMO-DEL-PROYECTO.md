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

**Ola 2** · Aprobada por el dueño del repo el 2026-09-18 · Base `feat/bootstrap-v2` @ `b8c246c`.

La ola 1 (07, 15, 19) cerró el 2026-09-18 en `628c84b`; su plan quedó en el historial de este
archivo (`git log -p`) y sus lecciones, abajo.

| Carril | Slice | Dueño de | Caliente escrito a mano |
|---|---|---|---|
| **A** (camino crítico) | 09 — `grilling` + `domain-modeling`, y `grill-me` / `grill-with-docs` como punteros | `.agents/skills/{grilling,domain-modeling,grill-me,grill-with-docs}/` y sus `.claude/commands/` (raíz + 3 scaffolds) | **dueño** de `This delivers:` y de la allowlist `$allow` |
| **B** | 10 — `diagnosing-bugs` | `.agents/skills/diagnosing-bugs/` y su `.claude/commands/` (raíz + 3 scaffolds) | no: el diff que necesita en `This delivers:` va en su reporte |
| **C** | 08 — merge de `triage`, `handoff` y `setup-matt-pocock-skills` | `.agents/skills/{triage,handoff,setup-matt-pocock-skills}/` y sus `.claude/commands/` (raíz + 3 scaffolds) | no: no suma skills, no toca `This delivers:` |

Afuera: 11 y 12 por el techo de 3 (y los dos sumarían otra edición de `This delivers:`); 21 no
es del camino crítico y entra en una ola posterior; 13 espera a 08–12; 14 es `CLAUDE.md` y va en
serie entre olas; 16 espera al 10; 18 es HITL y va último. Con este reparto, la ola 3 es 11 + 12
+ 16 y la 4 es 13 + 21.

Medido al repartir (2026-09-18, contra el clon de upstream en `959a8e9`, cuerpo + auxiliares):

- `grilling` 31 líneas (2 archivos), `domain-modeling` 184 (4), `grill-me` y `grill-with-docs` 12
  cada una (2).
- `diagnosing-bugs` 185 (3).
- `triage` 429 (4), `setup-matt-pocock-skills` 308 (7), `handoff` 21 (2).
- Son cuerpos que se adoptan de upstream, copiados ×4; la lógica propia de cada carril
  (`description`, punteros, lock, tests) es lo que se mide contra las ~400 líneas, y cada carril
  la proyecta antes de su primer test.
- Ningún archivo escrito a mano aparece en dos filas. `skills-lock.json` y los tres
  `.bootstrap-manifest.json` los tocan los tres carriles: son generados, cada carril los sella en
  su rama y el orquestador los re-sella sobre el árbol integrado.

Lo que cada carril resuelve antes del primer test:

- 09: dónde quedan alcanzables el formato de `CONTEXT.md` y el de ADR que hoy cuelgan de
  `grill-with-docs` → técnica: la decide el carril.
- 10: si la plantilla de loop con humano en el ciclo viaja al scaffold o se retira → la decide el
  carril, por delegación del dueño del repo, y la deja dicha en la skill y en su reporte.
- 08: nada abierto.

## Lo que dejó la ola N

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
