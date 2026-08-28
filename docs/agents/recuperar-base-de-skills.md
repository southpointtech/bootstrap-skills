# Recuperar la base de merge de las skills externas

Herramienta: `tools/recover-skill-bases.py`.

Nueve de las skills del scaffold salieron de `mattpocock/skills`. La **base de merge** de cada una
—la versión de upstream de la que salió nuestra copia— no está declarada en ningún lado y **no se
recupera por hash**: los `computedHash` del lockfile viejo son fabricados (ADR-0005, medido: 24.738
hashes probados contra toda la historia publicada de upstream, cero coincidencias).

Sí se recupera **por similitud**: la base es la versión histórica de upstream que maximiza la
similitud contra nuestra copia, medida sobre el **cuerpo sin frontmatter**, porque el drift propio
vive casi todo en la `description`.

Esta herramienta hace esa recuperación. Es de **mantenimiento, invocada a mano** cuando una base se
pierde. No corre en la suite y no está en ningún runner: necesita red y más de un minuto.

## Cómo se corre

Con un clon de upstream ya hecho (lo normal si venís de otra corrida):

```
py tools/recover-skill-bases.py --upstream-clone <ruta al clon>
```

Sin clon: lo clona solo en un directorio temporal e imprime la ruta para reusarla.

```
py tools/recover-skill-bases.py
```

Otras opciones:

| Opción | Para qué |
| --- | --- |
| `--skills-dir PATH` | Otro árbol de skills. Por defecto, el de `bootstrap-ai-project`. |
| `--skill NOMBRE` | Repetible. Por defecto recorre todas las skills del directorio. |
| `--out PATH` | Por defecto `.scratch/bootstrap-v2/skill-bases.json`. |
| `--stdout` | Imprime el JSON en vez de escribirlo. |
| `--threshold FLOAT` | Umbral de similitud mínima para aceptar una base (default `0.60`). |
| `--self-test` | Verificación offline contra un repo de fixture sintético. No toca la red. |

## Qué requiere

- **Red**, salvo que le pases `--upstream-clone`. El clon tiene que traer **toda la historia**: la
  base vive en blobs viejos, no en el HEAD. Nada de `--depth`.
- **git** y **Python 3** (solo librería estándar: `difflib`, `json`, `subprocess`).
- **Tiempo.** Medido el 2026-08-28 en la máquina de Martín, contra `mattpocock/skills` en
  `6654f6b` (413 blobs `*/SKILL.md` en toda la historia):
  - 11 skills con el clon ya hecho: **~1 m 20 s** (dos corridas: 1:18 y 1:25).
  - 2 skills incluyendo clonar desde GitHub: **13,6 s**.

## Qué emite

JSON. Por skill:

- `status`: `recovered` (hay base) o `unmatched` (nada supera el umbral: es un fork propio).
- `similarity`: el ratio de `difflib.SequenceMatcher` sobre el cuerpo, `1.0` = cuerpo idéntico.
- `base.blob`: el identificador del blob de git de la versión base. Es el objeto exacto contra el que
  se hace el merge de tres vías.
- `base.upstreamPath`: el path **histórico**, que puede no ser el de hoy (upstream renombró y
  reorganizó carpetas).
- `base.commit` / `base.commitDate` / `base.commitSubject`: la **primera aparición de ese contenido en
  ese path**. Vale la invariante `git rev-parse <commit>:<upstreamPath>` == `base.blob`; verificada
  para las nueve el 2026-08-28.
- `base.alsoSeenAtPaths`: otros paths donde el mismo contenido apareció (aparece cuando upstream movió
  carpetas). Solo informativo: el path que importa es el que llega al HEAD.
- `upstreamHead`: dónde vive hoy ese archivo en upstream — `present` (mismo path), `renamed` (git
  detectó el renombre; incluye `renameChain`) o `gone` (**sin correspondencia**: upstream lo borró).

La búsqueda es **por contenido, no por nombre**. Por eso `to-prd` encuentra su base en
`skills/engineering/to-prd/SKILL.md` sin saber que hoy upstream la llama `to-spec`, y recién después
resuelve el renombre con los registros de git.

### Lo que la herramienta NO decide

Cuando `upstreamHead.status` es `gone`, la herramienta lista
`unconfirmedSuccessorCandidates` con su similitud. **No son bases y no son sucesores**: son pistas
para que un humano decida.

El caso concreto es `to-issues`. Upstream la reemplazó por `to-tickets` en un commit que hizo como
**borrado + alta**, no como renombre (`386d4ff`, "unify planning skills into /to-spec + /to-tickets"),
y a la sensibilidad por defecto de git el par no se detecta. Bajarle la sensibilidad no es la salida:
medido el 2026-08-28, con `--find-renames=10%` git sí empareja `to-issues` → `to-tickets`, pero al
mismo precio empareja `zoom-out` → `wait-what`, que es falso. Los dos pares están en el mismo rango de
ruido —0,2449 y 0,2060 de similitud de cuerpo—, así que ninguna sensibilidad los separa. Por eso la
herramienta usa la detección de renombres **por defecto** y, cuando no alcanza, dice `gone` en vez de
adivinar. El mapeo `to-issues` → `to-tickets` es una **decisión humana**: vive en ADR-0006 y en el
lockfile, no acá.

## La salida es la entrada del lockfile

`.scratch/bootstrap-v2/skill-bases.json` es un **artefacto generado**. Alimenta el lockfile de skills
externas (`skills-lock.json`), que es lo que sí queda versionado —`.scratch/` está en el `.gitignore`,
así que esta salida es local y se regenera cuando haga falta. **No se edita a mano**: si algo está
mal, se corrige la herramienta y se vuelve a correr. Editarlo a mano reintroduce exactamente el problema que ADR-0005 documenta —una
afirmación verificable escrita sin verificar.

## Resultado conocido

Medido el 2026-08-28 contra `mattpocock/skills` en `6654f6b`. Sirve de regresión: si volvés a correr
la herramienta contra ese mismo HEAD y no da esto, algo cambió en la herramienta.

| skill | similitud | base (blob) | path histórico | commit base | HEAD de upstream |
| --- | --- | --- | --- | --- | --- |
| grill-me | 1.0000 | `bd04394c` | `skills/productivity/grill-me/SKILL.md` | `62f43a18` 2026-04-28 | present |
| grill-with-docs | 1.0000 | `5ea0aa91` | `skills/engineering/grill-with-docs/SKILL.md` | `e74f0061` 2026-05-13 | present |
| handoff | 1.0000 | `ec762d97` | `skills/productivity/handoff/SKILL.md` | `221ffca9` 2026-06-12 | present |
| setup-matt-pocock-skills | 1.0000 | `1ebc6e14` | `skills/engineering/setup-matt-pocock-skills/SKILL.md` | `43692562` 2026-04-29 | present |
| tdd | 0.8625 | `7a989411` | `skills/engineering/tdd/SKILL.md` | `7afa86d3` 2026-04-28 | present |
| to-issues | 0.9466 | `9b7dec9e` | `skills/engineering/to-issues/SKILL.md` | `221ffca9` 2026-06-12 | **gone** |
| to-prd | 1.0000 | `47a01d4e` | `skills/engineering/to-prd/SKILL.md` | `70141119` 2026-05-06 | renamed → `to-spec` |
| triage | 1.0000 | `3dee68f9` | `skills/engineering/triage/SKILL.md` | `179a14e7` 2026-04-28 | present |
| zoom-out | 1.0000 | `8cc007c4` | `skills/engineering/zoom-out/SKILL.md` | `221ffca9` 2026-06-12 | **gone** |

Siete cuerpos intactos, y las dos con drift real (`tdd` y `to-issues`) son exactamente las dos
modificaciones que ya estaban documentadas.

Las skills propias del scaffold que están en el mismo directorio salen `unmatched`, como corresponde:
`review-loop` con 0,0308 de mejor similitud y `slice-review` con 0,0202.

## Verificación

La herramienta no va a la suite, pero trae su propia verificación **offline**:

```
py tools/recover-skill-bases.py --self-test
```

Arma un repo de git sintético en un temporal (una skill que sobrevive y se renombra, una que upstream
borra, una que nunca existió upstream) y verifica 14 afirmaciones: que el frontmatter y los fines de
línea no cuenten para la similitud, que el path histórico y el commit base sean los que introdujeron
el contenido —y no una reaparición posterior—, que el renombre se siga hasta el HEAD, que una skill
borrada se reporte como `gone`, y que una skill sin correspondencia **no** reciba una base de
similitud baja inventada. Devuelve código de salida distinto de cero si alguna falla.
