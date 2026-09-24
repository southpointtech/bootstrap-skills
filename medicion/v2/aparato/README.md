# Aparato — el harness del A/B de la v2

Issue `04a`. Corre el juguete (`../juguete-inventario/`) en los tres brazos del A/B. Vive fuera de
la suite y fuera del scaffold: nada de acá corre en `tests/run-all.ps1`.

Por ahora **materializa un brazo y abre su corrida** (slices 1 y 2). Lanzar al agente, las rondas
de `PREGUNTAS.md`, los transcripts y las olas son el slice 3; la calificación es el `04b`.

## Uso

Desde esta carpeta (`medicion/v2/aparato/`), con Python 3.12, git y `pwsh` en el PATH:

```
python -m aparato materializar --brazo v1-serie --raiz <dir fuera del repo>
python -m pytest -q
```

`--raiz` es obligatorio, no tiene default y no puede caer dentro del repo (se rechaza antes de
crear nada). Imprime la carpeta de la corrida. Sale con 1 y una línea `error: <Tipo>: ...` en
stderr, sin traceback, si el `version` materializado no es el del brazo (el mensaje nombra el
esperado y el obtenido), si el `ref` no existe, si falla git o el `copy-scaffold.ps1`, si falta un
ejecutable o si el manifest materializado falta o no es JSON.

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
propaga. La corrida fallida queda como está; relanzar abre otra carpeta (otro segundo).

## Una corrida

| Ruta | Qué es |
|---|---|
| `proyecto/` | donde trabaja el agente: repo git con el scaffold, `enunciado.md` y `datos/` |
| `skill-en-ref/` | la skill tal como salió del `git archive` |
| `copy-scaffold.json` | el reporte (`created` / `overwritten`) del `copy-scaffold.ps1` del ref |
| `bitacora.jsonl` | append-only, un evento JSON por línea con `ts` UTC ISO |

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
