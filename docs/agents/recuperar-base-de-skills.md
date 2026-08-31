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
git (`--is-bare-repository`, y después `--absolute-git-dir` o `--show-toplevel`), no mirando si hay
un `.git` que sea directorio. Tiene que ser la **raíz**: `git rev-parse` sube por el árbol, así que
sin comparar contra la raíz cualquier carpeta de adentro de un repo pasaba por clon — un
`--upstream-clone` mal tipeado que cayera adentro de este repo lo analizaba a él —que tiene más de
cien blobs `*/SKILL.md` propios— y emitía bases con similitud 1.0 citando commits nuestros. Un
subdirectorio, y también `<clon>/.git`, se rechazan con `No es un clon de git`. (La cifra exacta no
se fija acá a propósito: se midió 109, 116 y 118 en tres momentos distintos de la misma semana, y
además depende de qué refs tengas localmente — 118 con `--all`, 100 alcanzables solo desde un commit.
Si la necesitás al día: `git rev-list --objects --all` filtrando por `SKILL.md`.)

### Exit codes

| código | qué pasó |
|---|---|
| 0 | terminó bien: escribió el reporte, o lo imprimió con `--stdout`, o el `--self-test` pasó |
| 1 | solo con `--self-test`: alguna aserción falló |
| 2 | error de invocación, **detectado antes de trabajar**: `--upstream-clone` que no es la raíz de un clon, `--skills-dir` inexistente, un `--skill` sin `SKILL.md`, o un `--out` que no se va a poder escribir. También es el que usa argparse para una opción inválida |
| 3 | la recuperación salió bien pero la escritura de `--out` falló igual (permisos, disco lleno, ruta de red). El reporte sale por **stdout** para no perderlo, y el destino que ya estaba queda intacto |
| 4 | no se pudo clonar upstream (sin red, URL mala, git que falla). Va aparte del 2 a propósito: "lo tipeaste mal" no se reintenta, "no hay red" sí |

Todo lo que se puede detectar se detecta antes de clonar y de recuperar, porque la recuperación
cuesta entre 81 s y 98 s con el clon ya hecho (medido) y un error de invocación no debe costar eso —
y sobre todo no debe terminar escribiendo un reporte todo-ceros encima de uno bueno.

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
  - `missing-locally`: el nombre pedido con `--skill` no tiene `SKILL.md` en el directorio de
    skills. Por el CLI no se llega: el pre-flight lo rechaza antes de trabajar (ver abajo), así que
    en todo reporte producido por la herramienta este contador vale 0. Queda para quien llame a
    `recover()` como librería, que es lo que hace el self-test.
- `upstreamRelation`: la relación con upstream, que **no** es lo mismo que el status. Los tres
  valores nombran **lo medido**, no el veredicto:
  - `no-match-above-threshold`: ninguna versión histórica de upstream supera el umbral de similitud
    de cuerpo contra nuestra copia (`review-loop`, `slice-review`). Eso es todo lo que afirma: **no**
    prueba que la skill nunca haya salido de upstream. Un cuerpo con suficiente drift cae por debajo
    igual, y el mecanismo está medido (issue 19): con drift prependido, un par real pasa de 0,7800 a
    0,0842 sin que cambie una línea del original.
  - `in-upstream-head`: tiene base recuperada y su path sigue vivo en el HEAD de upstream, en el
    mismo lugar o renombrado.
  - `gone-from-upstream-head`: tiene base recuperada, pero su path ya no está en el HEAD de upstream
    y git no detecta renombre (`to-issues`, `zoom-out`). Tampoco es un veredicto: puede haber sucesor
    con otro nombre, y para eso salen los `unconfirmedSuccessorCandidates`.
  El campo existe porque "fork propio" nombraba los dos extremos a la vez: `review-loop` no tiene
  ninguna base sobre el umbral, mientras que ADR-0006 llama fork propio a `zoom-out`, que **sí** vino
  de upstream y tiene base recuperada. Son conjuntos disjuntos y el lockfile (issue 05) necesita
  distinguirlos. **"Fork propio" no lo emite la herramienta**: lo firma un humano mirando esto.
- `similarity`: el ratio de `difflib.SequenceMatcher` sobre el cuerpo, redondeado a 4 decimales;
  `1.0` = cuerpo idéntico salvo redondeo (el resumen sí usa el ratio crudo, ver abajo). **Solo en las
  entradas que tienen base**; una `unmatched` trae `bestSimilarity` en su lugar.
- `bestSimilarity`: la mejor similitud **vista**, en las entradas `unmatched`. No es una base: es el
  techo que no llegó al umbral. Va aparte de `similarity` justamente para que no se lo lea como una
  base floja.
- `base.blob`: el identificador del blob de git de la versión base. Es el objeto exacto contra el que
  se hace el merge de tres vías.
- `base.upstreamPath`: el path **histórico** en el que apareció por primera vez ese contenido, que
  puede no ser el de hoy ni el más obvio (upstream renombró y reorganizó carpetas: el cuerpo base de
  `grill-me` aparece por primera vez en `grill-me/SKILL.md`, en la raíz del repo).
- `base.commit` / `base.commitDate` / `base.commitSubject`: la **aparición más vieja de ese
  contenido en toda la historia publicada, en cualquier path**. Vale la invariante
  `git rev-parse <commit>:<upstreamPath>` == `base.blob` (verificada para las nueve el
  2026-08-28), pero **no corrobora que la base sea la correcta**: `commit` y `upstreamPath`
  salen del mismo registro, así que se cumple igual con una base equivocada — de hecho se
  cumplía con las cuatro que `00c2160` reemplazó. Lo que sí verifica es que el par
  `(commit, path)` publicado exista tal cual en upstream, y ahí sí muerde —verificado con su
  mutante— cuando el path reportado deja de ser el de **esa aparición** y pasa a ser otro del
  mismo blob, o cuando viaja C-quoteado. Con la detección de renombres apagada **no** se cae:
  medido sobre el fixture, `diff.renames=false` parte el renombre en `D`+`A`, el `A` queda en el
  path nuevo del mismo commit y los 22 registros siguen cerrando. Por eso está asertada en el
  self-test, y con un conteo al lado: sin él, cero bases verificadas también daría verde.
- `base.alsoSeenAtPaths`: otros paths donde el mismo blob apareció. Solo informativo.
- `base.tiedCandidates` / `base.tieNote` / `base.tieOnIdenticalBodies`: aparecen cuando **más de un
  blob empata en el mejor ratio**. La herramienta elige la aparición más vieja y deja los empatados a
  la vista, para que quien decide el lockfile lo vea en vez de confiar en el desempate. No es raro:
  medido el 2026-08-28, **34 de los 373 cuerpos distintos de upstream existen en más de un blob**
  (74 de 413 blobs), y tres de nuestras nueve skills caen en ese caso.
  El empate se calcula sobre el **ratio**, no sobre el contenido, así que de qué es el empate hay que
  mirarlo: `tieOnIdenticalBodies` compara los cuerpos —ya normalizados: sin frontmatter, con CRLF a
  LF y extremos recortados— y lo dice. En `true` los cuerpos son idénticos y lo que difiere entre los
  blobs está **fuera** del cuerpo normalizado: en la práctica el frontmatter (es el caso de las tres
  de hoy), aunque un BOM, los fines de línea o un espacio en los extremos producirían lo mismo, y la
  herramienta no distingue cuál de esos fue.
  En `false` **al menos dos** de los cuerpos empatados difieren —`same_body` es un `all()`, y con
  tres o más blobs empatados el resto puede coincidir—: son versiones distintas con el mismo ratio,
  elegir mal cambia el merge de tres vías, y ahí el desempate por fecha es una convención, no una
  respuesta. `summary.tiedOnDifferentBodies` los cuenta.
- `upstreamHead`: dónde vive hoy ese archivo en upstream — `present` (mismo path), `renamed` (git
  detectó el renombre; incluye `renameChain`) o `gone` (**sin correspondencia**: upstream lo borró).

A nivel reporte:

- `upstream.url` es el `remote.origin.url` **real del clon que se usó**, no una constante: si
  apuntás la herramienta a otro clon o a otra URL, la salida dice a cuál. Un artefacto generado no
  puede afirmar contra qué corrió sin haberlo mirado (ADR-0005).
- `summary.exactBodyMatches` cuenta cuerpos **idénticos**, sobre el ratio sin redondear:
  `round(0.99996, 4)` da `1.0` y no es un cuerpo idéntico.
- `summary.tiedBestSimilarity` cuenta las skills cuyo mejor ratio quedó empatado entre varios blobs.
- `summary.tiedOnDifferentBodies` cuenta cuántos de esos empates **no** son de cuerpo idéntico. Es el
  subconjunto que pide decisión humana. El campo es posterior a la corrida del 2026-08-28, así que no
  tiene valor publicado; lo que sí está verificado (2026-08-31, contra un clon real) es que los
  tres empates de esa corrida son de cuerpo byte-idéntico, y con esos datos el contador daría 0.
- `method.fieldsByStatus` publica el contrato condicional: qué campos trae cada `status`. Está en la
  salida y no solo acá porque el consumidor del JSON (el lockfile) no tiene por qué descubrirlo a los
  golpes, y el self-test lo compara contra las claves que cada entrada emite de verdad.

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

### La métrica y su límite: `autojunk`

La similitud es `difflib.SequenceMatcher(None, mine, other).ratio()` **con el `autojunk` de la
librería activo**, que es su default. Cuando la **segunda** secuencia tiene 200 elementos o más,
`SequenceMatcher` marca como "populares" los que aparecen en más de `len(b)//100 + 1` posiciones de
`b` y los saca del índice: dejan de poder **sembrar** un match (uno ya sembrado sí se extiende sobre
ellos — un cuerpo contra sí mismo sigue dando 1.0, así que "los excluye del matching" sería
sobreafirmar). Sobre markdown comparado carácter a carácter, "popular" son las letras comunes.

Lo que importa acá: **`b` es el blob de upstream**, así que el heurístico se dispara en casi
**toda** comparación del corpus, no solo en los cuerpos largos. Medido el 2026-08-31 sobre las
skills locales: `zoom-out` —169 B de cuerpo— contra `slice-review` da 0,0020 con `autojunk` y 0,0086
sin él (4,2×); al revés, `slice-review` contra `zoom-out`, donde `b` tiene 169 elementos y no llega
a 200, da 0,0083 con y sin el heurístico. Esa asimetría es la firma de que el efecto depende de `b`
y no del largo de nuestro cuerpo.

Los números con `autojunk` son de la corrida del 2026-08-28; los de `autojunk=False` se midieron
aparte el 2026-08-31, sobre las mismas once skills locales:

| skill | cuerpo | mejor similitud con `autojunk` (lo que se publica) | con `autojunk=False` |
| --- | --- | --- | --- |
| `review-loop` | > 7 KB | 0,0308 | **0,1305**, y elige **otro archivo** (`wayfinder/SKILL.md` → `improve-codebase-architecture/SKILL.md`) |
| `slice-review` | > 7 KB | 0,0202 | **0,1101**, otro blob |

Son las **dos únicas** que pasan los 7 KB —la tercera más larga tiene 6.335 B—, pero eso **no** es
la razón por la que son las únicas que se mueven: el heurístico distorsiona casi todos los pares (ver
arriba). Se mueven porque son las dos que **no tienen match verdadero**: de las otras nueve, siete
tienen cuerpo idéntico (1,0, insensible al heurístico) y las dos con drift dan el mismo ratio contra
su base con y sin él (`tdd` 0,8625 y `to-issues` 0,9466, medido el 2026-08-31). Con la salvedad de
que eso vale para el ratio **contra su base**: que ningún otro de los 413 blobs las supere con el
heurístico apagado no se verificó. Dos consecuencias, distintas entre sí:

- **El veredicto no cambia.** 0,1305 y 0,1101 siguen muy por debajo del umbral de 0,60: las dos
  salen `unmatched` / `no-match-above-threshold` con `autojunk` prendido o apagado.
- **El número publicado y el blob citado sí son artefactos del heurístico.** No leerlos como "el
  parecido real con lo más parecido de upstream": son el parecido que quedó después de tirar los
  caracteres frecuentes, y el blob que ganó esa comparación degradada.

**No se apaga**, y es una decisión de costo medida el 2026-08-31, no un olvido: `autojunk=False`
lleva la corrida de ~98 s a **~2.500-3.500 s** (40-60 minutos) en la misma máquina. Cambiar la métrica —tokenizar por
línea en vez de por carácter, que ataca la misma causa sin el costo cuadrático— es el **issue 19**,
no esta herramienta.

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
`upstreamRelation: no-match-above-threshold`, como corresponde: `review-loop` con 0,0308 de mejor
similitud y `slice-review` con 0,0202. **Esos dos números están deprimidos por `autojunk`** (son las
dos únicas con cuerpo > 7 KB): sin el heurístico dan 0,1305 y 0,1101, contra otros blobs. El
veredicto es el mismo con los cuatro números —todos quedan lejos del umbral de 0,60—, pero la cifra
publicada no es "el parecido real". Ver *La métrica y su límite*.

## Verificación

La **recuperación real** no va a la suite: necesita red y ~90 s, que no es algo que pueda correr en
cada corrida de tests. Por eso la herramienta trae su propia verificación **offline**, adentro:

```
py tools/recover-skill-bases.py --self-test
```

Y ese self-test **sí** está en la suite, envuelto en `tests/recover-skill-bases.tests.ps1` como los
demás runners del repo (que no son Pester: son runners propios con una función `Assert`, igual que
los otros trece). El envoltorio no re-verifica lo que el self-test ya verifica; asserta las dos puntas
que un exit code solo no cubre: que la línea de resumen **exista** —un self-test que sale 0 sin
correr nada daría verde vacío— y que el total de aserciones sea **exactamente** el declarado
(`$ExpectedChecks`), que es lo único que muerde a un mutante que borra checks. No es un piso: con
`-ge` la holgura se acumula en silencio. Verificado con tres mutantes: desempate invertido
(3 fallas), assert borrado (1 falla, la del total exacto) y resumen suprimido (2 fallas).

Arma un repo de git sintético en un temporal, con **fechas fijas** —sin eso, el guard del desempate
solo se ejercitaba cuando dos commits caían por casualidad en el mismo segundo— y verifica **84
afirmaciones** sobre doce skills de fixture, y no toca la red.

El tiempo **depende mucho más de la carga de la máquina que de la cantidad de aserciones**. Esta
versión, en máquina ociosa: del orden de **10 s** (medidas sueltas entre 7,8 s y 12,2 s en la misma
máquina y la misma versión, según qué más estuviera corriendo).
La prueba de que la carga manda: una versión anterior con **menos** aserciones (44) se midió en
31 / 26 / 31,6 s por estar tomada con siete procesos en paralelo. El grueso no son las aserciones
sino armar el fixture, que hace una docena de commits de git. Cubre:

- que el frontmatter y los fines de línea no cuenten para la similitud;
- que la base sea la primera aparición del contenido y no una reaparición posterior, incluso cuando
  los dos commits caen en el mismo segundo;
- que ante **dos blobs distintos con el mismo cuerpo** gane el viejo, y que el empate quede expuesto
  en la salida;
- que la nota del empate **diga que los cuerpos difieren** cuando difieren, en vez de atribuir la
  diferencia al frontmatter sin haberla comparado: el fixture trae dos versiones **distintas** que
  empatan en el mismo ratio (0,9914, medido) contra nuestra copia, y ese caso tiene que salir marcado
  como empate de ratio y no de contenido;
- que el orden entre apariciones sea por instante y no por el ISO con offset, con dos commits en
  husos distintos donde las dos reglas dan resultados opuestos;
- que la similitud parcial conserve sus 4 decimales (un cuerpo con drift real, no todo en 1.0);
- que un blob que solo sale de un merge no se reporte como recuperado ni se cuente como tal;
- que el renombre se siga hasta el HEAD y que una skill borrada se reporte como `gone`, con sus
  candidatos a sucesor ordenados;
- que una skill sin correspondencia **no** reciba una base de similitud baja inventada, que su mejor
  similitud quede acotada por las dos puntas, y que su nota **no afirme** que la skill nunca salió de
  upstream —que es lo que no se midió—;
- que el umbral que ejercita el self-test sea **el default del CLI** y no un literal paralelo, que
  ese default **valga 0,60** —el cableado solo no alcanzaba: los tres términos de la igualdad leen la
  misma constante, así que moverla dejaba todo en verde— y que la frontera esté donde dice: un ratio
  **igual** al umbral se acepta, y un `1e-9` por encima ya no. La constante contra la que se compara
  la frontera se asserta a su vez contra el ratio que el fixture produce, porque si deriva la
  frontera deja de ser frontera sin que nada se ponga rojo;
- que `similarity()` devuelva el `ratio()` y no una de las **cotas baratas**: sobre este fixture el
  mutante `quick_ratio()` no solo infla el número (0,2607 → 0,8304) sino que cambia **cuál** es el
  mejor candidato a sucesor;
- que el par `(commit, upstreamPath)` de cada base publicada exista tal cual en upstream;
- que cada entrada emita **exactamente** los campos que `method.fieldsByStatus` declara para su
  status, incluida `missing-locally`, que por el CLI no se alcanza;
- que la URL reportada sea la del clon y no una constante;
- que un `SKILL.md` que no es utf-8 no voltee la corrida entera;
- que se acepte un clon bare y se siga rechazando un directorio que no es repo, **y también un
  subdirectorio** de un repo o de un bare, que es lo que hacía pasar a este repo por upstream;
- que un `--out` sin directorio se escriba en el cwd, y que las otras formas que fallaban recién en
  el `open()` —ruta vacía, un directorio ya existente, un componente intermedio que es archivo, una
  ruta terminada en separador, una raíz que no existe— se rechacen **antes** de trabajar, cada una
  diciendo cuál es. El caso de la raíz se asserta contra la función y no contra el CLI, y simula la
  raíz ausente **parcheando `os.path.exists`**: hardcodear `Z:` hacía que en una máquina con `Z:`
  mapeada la herramienta **escribiera el reporte en ese share**, y buscar una letra libre en runtime
  —el arreglo intermedio— ataba el caso a cómo esté montada la máquina y se auto-excluía cuando
  todas estaban ocupadas, dejando pasar en verde al mutante que borra la rama. Con el parche el caso
  vale igual en Windows y en POSIX, sin tocar el disco. (Un UNC inalcanzable cae por la misma rama,
  pero eso no lo ejercita ningún caso.) El
  motivo se ancla en un token con guiones (`destino-ocupado:`), no en una palabra suelta: el mensaje
  imprime la ruta, así que assertar `"directorio"` lo satisfacía el nombre del fixture y no el
  motivo, y los motivos se podían intercambiar entre sí sin que nada fallara;
- que si la escritura falla igual (exit 3), el reporte salga **entero por stdout**, el destino que
  ya estaba quede **intacto** y no sobre ningún temporal. La escritura es a un temporal de nombre
  único al lado (`mkstemp`, no un `.tmp` fijo que dos corridas se pisarían) y un `os.replace`
  encima, porque `open(dest, "w")` trunca antes de escribir y una falla a mitad destruía el reporte
  bueno. El caso se ejercita haciendo fallar el `os.replace`, que es el único punto donde el
  temporal ya se escribió: forzarlo con un nombre inválido reventaba en el `open()` y dejaba la
  atomicidad, la limpieza y el `replace` sin ejecutar nunca;
- que un `--skill` inexistente, o una **carpeta sin `SKILL.md`**, salgan con 2, digan por stderr qué
  nombre faltó y dónde se buscó, y **no pisen** el reporte que ya estaba;
- que un `--skill` válido siga corriendo y produzca sólo esa skill (sin esto, un guard que rechaza
  todo pasaba en verde y el modo `--skill` quedaba roto sin que nada lo notara);
- que un `--skills-dir` inexistente se rechace antes de recuperar, **y también antes de clonar** —
  esa segunda mitad va en un caso propio, sin `--upstream-clone` y con una URL inalcanzable, porque
  con el clon ya dado la propiedad es inobservable: mover el guard después del bloque de clonado
  dejaba el caso anterior en verde;
- que `missingLocally` cuente **los que faltan** y no cualquier estado (el fixture tiene dos
  faltantes y una presente a propósito: con un solo faltante el contador daba 1 con cualquier
  predicado).

Devuelve código de salida distinto de cero si alguna falla, e imprime todas: una regresión temprana
no esconde las que vienen después.
