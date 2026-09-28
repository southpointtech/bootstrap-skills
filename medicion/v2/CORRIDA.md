# Contrato de una corrida — lo que escribe el aparato (04a) y lee el calificador (04b)

Fijado por el orquestador el 2026-09-24, antes de la ola 2 de la medición. Ningún carril lo edita:
un cambio acá vuelve al orquestador. El aparato (`aparato/`) es el único que escribe una corrida;
`juguete-inventario/calificar.py` la lee y solo escribe `grading.json`.

## La carpeta

`<raiz>/<brazo>-<AAAAMMDDTHHMMSSZ>/`, fuera del repo:

| Ruta | Escribe | Qué es |
|---|---|---|
| `proyecto/` | aparato, después el agente | el repo git donde trabaja el agente (ya existe desde el slice 1) |
| `skill-en-ref/`, `copy-scaffold.json` | aparato | ya existen desde el slice 1 |
| `bitacora.jsonl` | aparato | append-only, un evento JSON por línea con `ts` (ISO 8601 UTC con offset, `datetime.isoformat()`) y `evento` |
| `preguntas/ronda-NN.md` | aparato | copia byte a byte del `PREGUNTAS.md` de la ronda `NN` (dos dígitos, desde `01`) |
| `transcripts/**/*.jsonl` | aparato | **todos** los JSONL de sesión de Claude Code de la corrida (sesión principal, subagentes, carriles), copiados crudos, sin reescribir. El nombre y las subcarpetas son del aparato: el calificador los lee con un glob recursivo y los ordena por el `timestamp` de su primera línea que lo tenga |
| `copias-de-carriles/<nombre>/.scratch/` | aparato | la última copia vista del `.scratch/` de cada worktree de carril que abrió el agente (`<nombre>` = nombre de la carpeta del worktree). Existe solo si hubo carriles. No se llama `carriles/` porque ahí abre sus worktrees el scaffold (`abrir-carril.ps1`: `<padre del repo>/carriles/<repo>/<slug>`, y el padre de `proyecto/` es la corrida) |
| `config/` | aparato | el `CLAUDE_CONFIG_DIR` de la corrida. `config/.credentials.json` se borra siempre al terminar, también si la corrida falla |
| `grading.json` | calificador | formato skill-creator |

## Eventos de la bitácora

Los del slice 1 y 2 siguen iguales (`corrida_abierta`, `materializado`, `version_incorrecta`,
`materializacion_fallida`). Los nuevos:

| `evento` | Campos | Cuándo |
|---|---|---|
| `sesion_lanzada` | `sesion` (int, desde 1), `session_id` (str o `null` si no se conoce todavía) | antes de cada `claude -p` |
| `sesion_terminada` | `sesion`, `session_id`, `exit_code` | al volver cada `claude -p` |
| `ronda_preguntas` | `ronda` (int, desde 1), `copia` (ruta relativa a la carpeta de la corrida, `preguntas/ronda-NN.md`), `secciones` (lista en el orden entregado, subconjunto de `["A", "C", "B"]`; `B` siempre) | cuando una sesión terminó dejando `PREGUNTAS.md`, antes de relanzar |
| `carril_sin_copia` | `carril` (nombre de la carpeta del worktree), `error` (`"<Tipo>: <mensaje>"` del último intento de copia), `copia_anterior` (bool: si `copias-de-carriles/<carril>/.scratch/` tiene una copia buena de un intento anterior) | uno por carril cuyo último intento de copia falló, en el hilo principal después del `join` del sondeo, antes de `corrida_cerrada` (camino exitoso o de error) |
| `corrida_cerrada` | `motivo`: `completa` (terminó sin `PREGUNTAS.md`), `tope_rondas`, `error`; y `error` (`"<Tipo>: <mensaje>"`) si el motivo es `error` | una sola vez, al final |

E08 lee `ronda_preguntas`: una ronda con `"A"` en `secciones` y `ts` anterior a la fecha de
committer del commit que implementa `alertas`.

## Cómo se lanza el agente

- `claude -p` con cwd en `proyecto/`, `CLAUDE_CONFIG_DIR=<corrida>/config` (vacío salvo una copia
  de `~/.claude/.credentials.json`), `--dangerously-skip-permissions`, `--model claude-opus-5-5`.
  Decisiones del dueño del repo (2026-09-24): config limpia para que ningún brazo vea las skills ni
  el `CLAUDE.md` de usuario de la máquina; Opus 5.5; permisos salteados porque la corrida es
  desatendida y siempre cae fuera del repo.
- El prompt es el de `evals.json` más **una** frase según el `modo` del brazo, que vive en
  `aparato/brazos.py` (decisión del dueño del repo, 2026-09-24):
  - `serie`: `Trabajá un slice por vez, sin carriles ni worktrees paralelos.`
  - `olas`: `Trabajá por olas de carriles en paralelo, como indica \`docs/ai-workflow/PARALELISMO.md\`.`
- La respuesta del cliente sale de `juguete-inventario/cliente/respuestas.md` y de `ruteo` de
  `evals.json` (secciones A y C por `re.search` con `re.IGNORECASE` sobre el texto de
  `PREGUNTAS.md`; B siempre; concatenadas en el orden A, C, B). El aparato borra `PREGUNTAS.md`
  antes de relanzar.

Medido el 2026-09-24 con `claude` 2.1.281: con `CLAUDE_CONFIG_DIR` limpio y la credencial copiada,
`claude -p` autentica, y el JSONL de la sesión queda en `config/projects/<slug del cwd>/<session_id>.jsonl` (en el slug, `:`, los separadores y los
espacios pasan a `-`). Dónde quedan los de subagentes no está medido: lo mide el 04a.
Las skills sincronizadas de la cuenta de claude.ai (`config/skills/synced/`) bajan igual en los
tres brazos: no favorecen a ninguno y no se sacan.
