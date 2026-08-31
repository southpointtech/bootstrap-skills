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
pierde.

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
| `--upstream-url URL` | Qué clonar cuando no le pasás `--upstream-clone`. |
| `--self-test` | Verificación offline contra un repo de fixture sintético. No toca la red. |

`--upstream-clone` acepta un clon normal, uno `--bare` y un worktree: lo resuelve preguntándole a
git (`git -C <clon> rev-parse --git-dir`), no mirando si hay un `.git` que sea directorio.

## Qué requiere

- **Red**, salvo que le pases `--upstream-clone`. El clon tiene que traer **toda la historia**: la
  base vive en blobs viejos, no en el HEAD. Nada de `--depth`.
- **git** y **Python 3** (solo librería estándar: `difflib`, `json`, `subprocess`).
- **Tiempo.** Medido el 2026-08-28 en la máquina de Martín, contra `mattpocock/skills` en
  `6654f6b` (413 blobs `*/SKILL.md` en toda la historia):
  - 11 skills con el clon ya hecho: **~1 m 22 s** (dos corridas: 81,1 s y 83,9 s).
  - 2 skills (`grill-me` y `tdd`) incluyendo clonar desde GitHub: **8,2 s**.

  Cada skill local se compara contra los 413 blobs, así que el grueso del tiempo es la comparación,
  no el clon.

## Qué emite

JSON. Por skill:

- `status`:
  - `recovered`: hay base y hay commit fechado que la introdujo.
  - `unresolved-commit`: hay blob base, pero ningún commit del log lo introduce (caso típico: el
    blob solo existe como resolución de un merge). El criterio de aceptación pide commit fechado,
    así que **no cuenta como recuperada** y el resumen la lista aparte.
  - `unmatched`: nada supera el umbral.
- `upstreamRelation`: la relación con upstream, que **no** es lo mismo que el status.
  - `never-upstream`: esta skill nunca salió de upstream (`review-loop`, `slice-review`).
  - `in-upstream-head`: vino de upstream y hoy sigue viva ahí, en el mismo path o renombrada.
  - `orphaned`: vino de upstream y upstream la borró (`to-issues`, `zoom-out`).
  El campo existe porque "fork propio" nombraba las dos primeras a la vez: `review-loop` nunca fue
  de upstream, mientras que ADR-0006 llama fork propio a `zoom-out`, que **sí** vino de upstream.
  Son conjuntos disjuntos, y el lockfile (issue 05) necesita distinguirlos.
- `similarity`: el ratio de `difflib.SequenceMatcher` sobre el cuerpo, redondeado a 4 decimales;
  `1.0` = cuerpo idéntico salvo redondeo (el resumen sí usa el ratio crudo, ver abajo).
- `base.blob`: el identificador del blob de git de la versión base. Es el objeto exacto contra el que
  se hace el merge de tres vías.
- `base.upstreamPath`: el path **histórico** en el que apareció por primera vez ese contenido, que
  puede no ser el de hoy ni el más obvio (upstream renombró y reorganizó carpetas: el cuerpo base de
  `grill-me` aparece por primera vez en `grill-me/SKILL.md`, en la raíz del repo).
- `base.commit` / `base.commitDate` / `base.commitSubject`: la **aparición más vieja de ese
  contenido en toda la historia publicada, en cualquier path**. Vale la invariante
  `git rev-parse <commit>:<upstreamPath>` == `base.blob`; verificada para las nueve el 2026-08-28.
- `base.alsoSeenAtPaths`: otros paths donde el mismo blob apareció. Solo informativo.
- `base.tiedCandidates` / `base.tieNote`: aparecen cuando **más de un blob empata en el mejor
  ratio**, que es lo que pasa cuando upstream retocó solo el frontmatter y dejó el cuerpo igual.
  La herramienta elige la aparición más vieja, y deja los empatados a la vista para que quien decide
  el lockfile lo vea en vez de confiar en el desempate. No es raro: medido el 2026-08-28, **34 de
  los 373 cuerpos distintos de upstream existen en más de un blob** (74 de 413 blobs), y tres de
  nuestras nueve skills caen en ese caso.
- `upstreamHead`: dónde vive hoy ese archivo en upstream — `present` (mismo path), `renamed` (git
  detectó el renombre; incluye `renameChain`) o `gone` (**sin correspondencia**: upstream lo borró).

A nivel reporte:

- `upstream.url` es el `remote.origin.url` **real del clon que se usó**, no una constante: si
  apuntás la herramienta a otro clon o a otra URL, la salida dice a cuál. Un artefacto generado no
  puede afirmar contra qué corrió sin haberlo mirado (ADR-0005).
- `summary.exactBodyMatches` cuenta cuerpos **idénticos**, sobre el ratio sin redondear:
  `round(0.99996, 4)` da `1.0` y no es un cuerpo idéntico.
- `summary.tiedBestSimilarity` cuenta las skills cuyo mejor ratio quedó empatado entre varios blobs.

La búsqueda es **por contenido, no por nombre**. Por eso `to-prd` encuentra su base en
`skills/engineering/to-prd/SKILL.md` sin saber que hoy upstream la llama `to-spec`, y recién después
resuelve el renombre con los registros de git.

### Cómo se elige entre varias apariciones del mismo contenido

Dos reglas, las dos con guard en el self-test:

1. **La base es la aparición más vieja del contenido**, considerando todos los blobs empatados en el
   mejor ratio y todas sus apariciones, en cualquier path. Elegir el par `(blob, path)` antes de
   mirar la historia reporta el commit del renombre en vez del que introdujo el contenido.
2. **El orden es por instante, no por reloj de pared.** Se compara `%ct` (epoch entero). El ISO
   `%cI` lleva el offset local, así que comparado como string ordena mal un repo con commits de
   husos distintos — y los commits hechos desde la web de GitHub son siempre `+00:00`. A igual
   segundo desempata el commit más viejo del log.

### Lo que la herramienta NO decide

Cuando `upstreamHead.status` es `gone`, la herramienta lista `unconfirmedSuccessorCandidates` con su
similitud. **No son bases y no son sucesores**: son pistas para que un humano decida.

El caso concreto es `to-issues`. Upstream la reemplazó por `to-tickets` en `386d4ff`
("refactor: unify planning skills into /to-spec + /to-tickets", 2026-07-08). Medido el 2026-08-28
sobre ese commit: `skills/engineering/to-issues/SKILL.md` sale `D` y `skills/engineering/to-tickets/SKILL.md`
sale `A` con la sensibilidad por defecto. Bajándola, `to-tickets` aparece como `R026` desde
`skills/engineering/to-plan/SKILL.md` —una skill que nunca fue nuestra— y `to-issues` sigue saliendo
`D` en todo el rango de 5 % a 50 %: con `to-plan` en el mismo commit, git le adjudica `to-tickets` a
`to-plan` y `to-issues` se queda sin par.

En el diff de punta a punta (`git diff --find-renames=N% 221ffca9 HEAD -- '*SKILL.md'`), donde
`to-plan` no existe ni en la base ni en el HEAD y por eso el par queda libre, sí se emparejan, y **la
sensibilidad los separa**: `to-issues` → `to-tickets` sale `R015` y aguanta hasta un umbral de 15 %;
`zoom-out` → `wait-what` sale `R010` y solo aparece con umbral ≤ 10 %. Entre 11 % y 15 % git empareja
el par bueno y descarta el falso.

Que exista esa ventana no la vuelve una regla. Es un umbral elegido **después** de saber la
respuesta, calibrado sobre este par de commits y sostenido por una circunstancia del diff (que
`to-plan` no esté en ninguna de las dos puntas); y 15 % de similitud es demasiado poco para
defenderlo como default. Por eso la herramienta usa la detección de renombres **por defecto** y,
cuando no alcanza, dice `gone` en vez de adivinar. El mapeo `to-issues` → `to-tickets` es una
**decisión humana**: vive en ADR-0006 y en el lockfile, no acá.

La similitud de cuerpo que mide la herramienta, para los mismos pares (2026-08-28):
`to-issues` ↔ `to-tickets` **0,2449**; `zoom-out` ↔ `wait-what` **0,0591** — y el candidato más
parecido a `zoom-out` en el HEAD de upstream no es `wait-what` sino `grill-with-docs`, con 0,2060,
que es tan falso como el otro. De ahí que la lista se llame *unconfirmed*.

## La salida es la entrada del lockfile

`.scratch/bootstrap-v2/skill-bases.json` es un **artefacto generado**. Alimenta el lockfile de skills
externas (`skills-lock.json`), que es lo que sí queda versionado —`.scratch/` está en el `.gitignore`,
así que esta salida es local y se regenera cuando haga falta. **No se edita a mano**: si algo está
mal, se corrige la herramienta y se vuelve a correr. Editarlo a mano reintroduce exactamente el problema que ADR-0005 documenta —una
afirmación verificable escrita sin verificar.

## Resultado conocido

Medido el 2026-08-28 contra `mattpocock/skills` en `6654f6b`. Sirve de regresión: si volvés a correr
la herramienta contra ese mismo HEAD y no da esto, algo cambió en la herramienta.

| skill | similitud | base (blob) | path histórico | commit base | HEAD de upstream | empate |
| --- | --- | --- | --- | --- | --- | --- |
| grill-me | 1.0000 | `bd04394c` | `grill-me/SKILL.md` | `a6bdfd9f` 2026-03-26 | renamed → `skills/productivity/grill-me` | no |
| grill-with-docs | 1.0000 | `5ea0aa91` | `skills/engineering/grill-with-docs/SKILL.md` | `e74f0061` 2026-05-13 | present | no |
| handoff | 1.0000 | `0aa5b993` | `skills/productivity/handoff/SKILL.md` | `d54c497a` 2026-05-19 | present | sí: `ec762d97` 2026-06-12 |
| setup-matt-pocock-skills | 1.0000 | `1ebc6e14` | `skills/engineering/setup-matt-pocock-skills/SKILL.md` | `43692562` 2026-04-29 | present | no |
| tdd | 0.8625 | `7a989411` | `skills/engineering/tdd/SKILL.md` | `7afa86d3` 2026-04-28 | present | no |
| to-issues | 0.9466 | `9f6efbfe` | `skills/engineering/to-issues/SKILL.md` | `ff3ee1dd` 2026-05-06 | **gone** | sí: `9b7dec9e` 2026-06-12 |
| to-prd | 1.0000 | `47a01d4e` | `skills/engineering/to-prd/SKILL.md` | `70141119` 2026-05-06 | renamed → `to-spec` | no |
| triage | 1.0000 | `3dee68f9` | `skills/engineering/triage/SKILL.md` | `179a14e7` 2026-04-28 | present | no |
| zoom-out | 1.0000 | `1e7a5dc7` | `skills/engineering/zoom-out/SKILL.md` | `7afa86d3` 2026-04-28 | **gone** | sí: `8cc007c4` 2026-06-12 |

Siete cuerpos intactos, y las dos con drift real (`tdd` y `to-issues`) son exactamente las dos
modificaciones que ya estaban documentadas.

Tres de las nueve —`handoff`, `to-issues`, `zoom-out`— tienen el mismo cuerpo repartido en dos blobs,
y las tres reportaban `221ffca9` (2026-06-12), que es el **más nuevo** de los dos. Ese commit toca
solo el frontmatter: la `description` en `to-issues` y `zoom-out`, `disable-model-invocation` en
`handoff`. El cuerpo no cambia, así que la base correcta es la aparición vieja, y es la que sale hoy.

`grill-me` no empata en blob, pero su único blob vive en tres paths: la aparición que corresponde es
`a6bdfd9f` (2026-03-26) en `grill-me/SKILL.md`, no `62f43a18` (2026-04-28), que es el commit que la
movió de carpeta (`R100 skills/grill-me/SKILL.md → skills/productivity/grill-me/SKILL.md`, un
renombre puro).

Las skills propias del scaffold que están en el mismo directorio salen `unmatched` con
`upstreamRelation: never-upstream`, como corresponde: `review-loop` con 0,0308 de mejor similitud y
`slice-review` con 0,0202.

## Verificación

La **recuperación real** no va a la suite: necesita red y ~90 s, que no es algo que pueda correr en
cada corrida de tests. Por eso la herramienta trae su propia verificación **offline**, adentro:

```
py tools/recover-skill-bases.py --self-test
```

Y ese self-test **sí** está en la suite, envuelto en `tests/recover-skill-bases.tests.ps1` como los
demás runners del repo (que no son Pester: son runners propios con una función `Assert`, igual que
los otros doce). El envoltorio no re-verifica lo que el self-test ya verifica; asserta las dos puntas
que un exit code solo no cubre: que la línea de resumen **exista** —un self-test que sale 0 sin
correr nada daría verde vacío— y que el total de aserciones no baje de un piso declarado, que es lo
único que muerde a un mutante que borra checks. Verificado con tres mutantes: desempate invertido
(3 fallas), assert borrado (1 falla, la del piso) y resumen suprimido (4 fallas).

Arma un repo de git sintético en un temporal, con **fechas fijas** —sin eso, el guard del desempate
solo se ejercitaba cuando dos commits caían por casualidad en el mismo segundo— y verifica **44
afirmaciones** sobre nueve skills de fixture. Tarda ~30 s (medido: tres corridas de 31 s, 26 s y
31,6 s, las tres 44/44) y no toca la red. Los ~25 s de diferencia contra las 39 afirmaciones
anteriores son las tres recuperaciones completas que ejercitan el CLI de punta a punta; se pagan
porque los tres agujeros que tapan eran silenciosos. Cubre:

- que el frontmatter y los fines de línea no cuenten para la similitud;
- que la base sea la primera aparición del contenido y no una reaparición posterior, incluso cuando
  los dos commits caen en el mismo segundo;
- que ante **dos blobs distintos con el mismo cuerpo** gane el viejo, y que el empate quede expuesto
  en la salida;
- que el orden entre apariciones sea por instante y no por el ISO con offset, con dos commits en
  husos distintos donde las dos reglas dan resultados opuestos;
- que la similitud parcial conserve sus 4 decimales (un cuerpo con drift real, no todo en 1.0);
- que un blob que solo sale de un merge no se reporte como recuperado ni se cuente como tal;
- que el renombre se siga hasta el HEAD y que una skill borrada se reporte como `gone`, con sus
  candidatos a sucesor ordenados;
- que una skill sin correspondencia **no** reciba una base de similitud baja inventada, y que su
  mejor similitud quede acotada por las dos puntas;
- que la URL reportada sea la del clon y no una constante;
- que un `SKILL.md` que no es utf-8 no voltee la corrida entera;
- que se acepte un clon bare y se siga rechazando un directorio que no es repo.

Devuelve código de salida distinto de cero si alguna falla, e imprime todas: una regresión temprana
no esconde las que vienen después.
