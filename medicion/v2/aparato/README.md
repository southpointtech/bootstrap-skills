# Aparato — el harness del A/B de la v2

Issue `04a`. Corre el juguete (`../juguete-inventario/`) en los tres brazos del A/B. Vive fuera de
la suite y fuera del scaffold: nada de acá corre en `tests/run-all.ps1`.

Este primer slice solo **materializa un brazo y abre su corrida**. Lanzar al agente, las rondas de
`PREGUNTAS.md`, los transcripts y las olas son el slice siguiente; la calificación es el `04b`.

## Uso

Desde esta carpeta (`medicion/v2/aparato/`), con Python 3.12, git y `pwsh` en el PATH:

```
python -m aparato materializar --brazo v1-serie --raiz <dir fuera del repo>
python -m pytest -q
```

`--raiz` es obligatorio y no tiene default. Imprime la carpeta de la corrida; sale con 1 si el
`version` materializado no es el del brazo (el mensaje nombra el esperado y el obtenido).

## Los brazos

Están en `aparato/brazos.py`, una línea por brazo: nombre, `ref` de git, `version` esperada del
`.bootstrap-manifest.json` materializado y modo (`serie` u `olas`). Re-apuntar un brazo a otra
versión es cambiar su `ref` y su `version` ahí. El sufijo de `version` (`+567c77a`) no es un commit:
no sirve como `ref`.

## Qué hace `materializar`

1. Resuelve el `ref` a un sha (`git rev-parse <ref>^{commit}`).
2. Crea `<raiz>/<brazo>-<AAAAMMDDTHHMMSSZ>/` (UTC); si ya existe, falla sin tocarla.
3. Extrae `skills/bootstrap-personal-project` de ese sha con `git archive` (nunca checkout) y corre
   **su** `copy-scaffold.ps1` hacia `proyecto/`.
4. Copia a `proyecto/` solo `enunciado.md` y `datos/` del juguete.
5. Lee `version` del `.bootstrap-manifest.json` de `proyecto/` y la compara con la del brazo.

## Una corrida

| Ruta | Qué es |
|---|---|
| `proyecto/` | donde trabaja el agente: el scaffold más `enunciado.md` y `datos/` |
| `skill-en-ref/` | la skill tal como salió del `git archive` |
| `copy-scaffold.json` | el reporte (`created` / `overwritten`) del `copy-scaffold.ps1` del ref |
| `bitacora.jsonl` | append-only, un evento JSON por línea con `ts` UTC ISO |

Eventos de este slice: `corrida_abierta` (brazo, ref, sha, modo), `materializado` (brazo, ref, sha,
version) o `version_incorrecta` (ref, sha, esperada, obtenida). Nada se borra al cerrar.
