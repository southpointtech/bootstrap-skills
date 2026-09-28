# Aparato — el harness del A/B de la v2

Issue `04a`. Corre el juguete (`../juguete-inventario/`) en los tres brazos del A/B. Vive fuera de
la suite y fuera del scaffold: nada de acá corre en `tests/run-all.ps1`.

**Materializa un brazo y abre su corrida** (slices 1 y 2) y **lanza al agente sobre ella**
(slice 3): rondas de `PREGUNTAS.md`, transcripts, `.scratch/` de los carriles y credencial. Lo que
escribe una corrida y lee el calificador (`04b`) está fijado en `../CORRIDA.md`.

## Uso

Desde esta carpeta (`medicion/v2/aparato/`), con Python 3.12, git y `pwsh` en el PATH (y `claude`
para `correr`):

```
python -m aparato materializar --brazo v1-serie --raiz <dir fuera del repo>
python -m aparato correr --brazo v2-olas --raiz <dir fuera del repo>
python -m pytest -q
```

`--raiz` es obligatorio, no tiene default y no puede caer dentro del repo (se rechaza antes de
crear nada). Los dos imprimen la carpeta de la corrida (`correr`, apenas la materializa). Salen con
1 y una línea `error: <Tipo>: ...` en stderr, sin traceback, si el `version` materializado no es el
del brazo (el mensaje nombra el esperado y el obtenido), si el `ref` no existe, si falla git o el
`copy-scaffold.ps1`, si falta un ejecutable, si el tar del ref está roto, si el manifest
materializado falta, no es JSON o no es un objeto, o (en `correr`) si una sesión de claude sale
distinto de 0. `correr` sale con 0 si la corrida cierra `completa` y con 3 si cierra por
`tope_rondas`.

Flags técnicos de `correr`:

| Flag | Default | Qué es |
|---|---|---|
| `--claude` | `claude` del PATH | el ejecutable; un `.py` corre con el mismo Python (el `claude` falso de los tests) |
| `--tope-rondas` | 5 | rondas de preguntas respondidas; si la sesión siguiente deja otra `PREGUNTAS.md`, cierra con `tope_rondas` |
| `--sondeo` | 2.0 | segundos entre dos miradas a los worktrees de carril |
| `--credencial` | `~/.claude/.credentials.json` | lo que se copia a `config/.credentials.json` |

## Los brazos

Están en `aparato/brazos.py`, una línea por brazo: nombre, `ref` de git, `version` esperada del
`.bootstrap-manifest.json` materializado y modo (`serie` u `olas`). Re-apuntar un brazo a otra
versión es cambiar su `ref` y su `version` ahí. El sufijo de `version` (`+567c77a`) no es un commit:
no sirve como `ref`.

## Qué hace `materializar`

1. Rechaza una `--raiz` dentro del repo y resuelve el `ref` a un sha
   (`git rev-parse <ref>^{commit}`). Si algo de esto falla, no se crea la corrida.
2. Crea `<raiz>/<brazo>-<AAAAMMDDTHHMMSSZ>/` (UTC); si ya existe, falla sin tocarla.
3. `git_archive`: extrae `skills/bootstrap-personal-project` de ese sha (nunca checkout).
4. `copy_scaffold`: corre **su** `copy-scaffold.ps1` hacia `proyecto/`.
5. `copiar_juguete`: copia a `proyecto/` solo `enunciado.md` y `datos/`, y calcula su huella.
6. `leer_manifest`: lee `version` del `.bootstrap-manifest.json` de `proyecto/` y la compara con la
   del brazo.
7. `git_init`: `proyecto/` pasa a ser un repo (rama `main`) con un único commit con todo lo
   anterior. La identidad de ese commit (`aparato <aparato@invalid>`) va por `-c` y no queda en la
   config del repo: los commits del agente salen con la identidad de la máquina.

Si un paso del 3 al 7 falla, la bitácora se cierra con `materializacion_fallida` y el error se
propaga (si además falla escribir ese evento, el error original sigue siendo el que sale, con una
nota). Los `git` corren sin los `GIT_DIR`/`GIT_WORK_TREE`/`GIT_INDEX_FILE` heredados, que los
mandarían a otro repo. La corrida fallida queda como está; relanzar abre otra carpeta (otro segundo).

## Qué hace `correr`

`materializar` y después `lanzar` (`aparato/correr.py`), según `../CORRIDA.md`:

1. Crea `config/` y copia la credencial a `config/.credentials.json`, su único archivo. Se borra
   siempre al terminar, también si la corrida falla. Su contenido no se imprime ni se registra.
2. Lanza `claude -p --output-format json --model claude-opus-5-5 --dangerously-skip-permissions`
   con cwd en `proyecto/` y `CLAUDE_CONFIG_DIR=<corrida>/config`. El prompt va por stdin: el de
   `evals[0].prompt`, una línea en blanco y la frase del modo (`FRASE_MODO` en
   `aparato/brazos.py`). El entorno del agente no lleva ninguna variable `CLAUDE*` de quien lanza
   (esfuerzo, id de sesión) ni los `GIT_*` heredados: los tres brazos arrancan igual.
3. Si la sesión sale con 0 y dejó `PREGUNTAS.md`: la copia a `preguntas/ronda-NN.md`, arma la
   respuesta con `ruteo` (A y C por `re.search` con `re.IGNORECASE`, B siempre, en orden A, C, B;
   el cuerpo de cada sección de `cliente/respuestas.md`, separados por una línea en blanco),
   registra `ronda_preguntas`, borra `PREGUNTAS.md` y relanza con la respuesta como prompt,
   **continuando la sesión**: `--resume <session_id>` con el `session_id` que devolvió el JSON de
   la sesión anterior, o `--continue` si no vino ninguno, para que el agente siga con el contexto de
   lo que preguntó (que `--resume` conserve el `session_id` con el `claude` real lo mide la corrida
   en seco; la bitácora registra el que devuelve cada sesión). Pasado el tope, la última `PREGUNTAS.md` queda en `proyecto/` sin responder.
4. Mientras corre, un hilo mira cada `--sondeo` segundos `git -C proyecto worktree list
   --porcelain` y, por cada worktree que no es el principal y tiene `.scratch/`, guarda su copia
   en `copias-de-carriles/<nombre de la carpeta>/.scratch/` (copia nueva completa y después reemplaza: si el
   agente la borra a mitad, queda la anterior). Mira una vez más al terminar. El agente borra los
   worktrees al cerrar cada ola, así que lo que queda es la última copia vista.
5. Al final (también si falla) copia crudos a `transcripts/` todos los `*.jsonl` de
   `config/projects/`, recursivo y con las mismas subcarpetas, y cierra con `corrida_cerrada`.

Eventos nuevos en la bitácora: `sesion_lanzada`, `sesion_terminada`, `ronda_preguntas` y
`corrida_cerrada`, con los campos de `../CORRIDA.md`. Una sesión que sale distinto de 0 cierra con
`motivo: error` y `error: "SesionFallida: ..."`.

## Una corrida

| Ruta | Qué es |
|---|---|
| `proyecto/` | donde trabaja el agente: repo git con el scaffold, `enunciado.md` y `datos/` |
| `skill-en-ref/` | la skill tal como salió del `git archive` |
| `copy-scaffold.json` | el reporte (`created` / `overwritten`) del `copy-scaffold.ps1` del ref |
| `bitacora.jsonl` | append-only, un evento JSON por línea con `ts` UTC ISO |
| `config/` | el `CLAUDE_CONFIG_DIR` de la corrida (`correr`); la credencial ya no está al terminar |
| `preguntas/ronda-NN.md` | copia byte a byte de cada `PREGUNTAS.md` respondida (`correr`) |
| `transcripts/` | los JSONL de `config/projects/`, crudos (`correr`) |
| `copias-de-carriles/<nombre>/.scratch/` | la última copia vista del `.scratch/` de cada carril (`correr`, solo si hubo) |

Eventos, en orden: `corrida_abierta` (brazo, ref, sha, modo) y después uno terminal (falta solo si
el proceso muere sin llegar a escribirlo, por ejemplo matado desde afuera):

- `materializado` (brazo, ref, sha, version, `juguete_sha256`, `commit_inicial`)
- `version_incorrecta` (brazo, ref, sha, esperada, obtenida)
- `materializacion_fallida` (brazo, ref, sha, `paso`, `error` = `"<Tipo>: <mensaje>"`), con `paso`
  uno de `git_archive`, `copy_scaffold`, `copiar_juguete`, `leer_manifest`, `git_init`

`modo` (`serie` u `olas`) es lo único que separa `v2-serie` de `v2-olas`. Nada se borra al cerrar.

Con `juguete_sha256` se prueba que los tres brazos vieron el mismo juguete: si coincide, vieron los
mismos bytes. Es el sha256 de las líneas `<ruta POSIX>\0<sha256 del contenido>\n` de cada archivo
de `enunciado.md` y `datos/`, en orden de ruta (`huella_juguete` en `aparato/materializar.py`). Se
calcula sobre `proyecto/` recién copiado, así que se recalcula desde la corrida o desde el juguete.
