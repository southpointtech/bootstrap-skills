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

Rige la regla de dueño único de la norma: **uno solo de estos carriles por ola toca cada archivo de
esta lista**, y el plan de la ola lo nombra. Regenerar es cómo se resuelve un conflicto, no un
permiso para que dos carriles lo editen a la vez.

- `skills-lock.json` (raíz y los tres scaffolds): se regenera con
  `pwsh -NoProfile -File tools/skills-lock.ps1 -Action Seal`. Lo tocan 07 a 12 y 16.
- `.scratch/bootstrap-v2/skill-bases.json`: gitignoreado, así que cada carril recibe su copia y
  lo que cambie ahí **no viaja por git**. El orquestador lo re-aplica en el worktree de v2 al
  integrar.
- `.bootstrap-manifest.json` de los tres scaffolds: `pwsh -NoProfile -File tools/gen-manifest.ps1
  -SkillDir skills/<bootstrap-x>`. Lo toca cualquier slice que edite un scaffold.
- La línea `This delivers:` de los tres `skills/bootstrap-*/SKILL.md`: **escrita a mano**, y
  `tests/mirror.tests.ps1` ata sus conteos a lo que el scaffold tiene de verdad. La tocan todos los
  que suman una skill o un doc de flujo (09, 10, 11, 12, 14 y 16), así que un conflicto acá se
  mergea a mano contando contra el scaffold.
- Los goldens de `tests/fixtures/`: `tools/reseal-step0b.ps1` (Step 0b), `tools/reseal-step5.ps1
  -Block <nombre>` (`step5`, `tdd-loop`) y `tools/reseal-goldens.ps1` (Step 2 y techos).
- La allowlist `$allow` de `tests/mirror.tests.ps1`.
- `CLAUDE.md` de la raíz y de los tres scaffolds: los tocan 14 y 20.

**Un conflicto en un archivo generado se resuelve regenerándolo con su herramienta, nunca a
mano.** El carril dueño lo re-sella en su rama; si al rebasar hay conflicto, el orquestador toma
cualquiera de los dos lados y vuelve a correr la herramienta sobre el árbol integrado.

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

Ninguna todavía. La ola 1 se planea con `PLAN-DE-OLA` al cerrar el issue 20 y se muestra antes de
despachar.

## Lo que dejó la ola N
