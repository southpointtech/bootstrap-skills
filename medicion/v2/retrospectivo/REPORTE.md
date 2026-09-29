# Retrospectivo de la v2 en este repo — 2026-09-29

**Los dos brazos están contaminados y este reporte vale como contraste, no como veredicto.** El
"después" es la v2 usada por la misma persona que la escribió, sobre un trabajo distinto (el aparato
de medición, en vez del release). El "antes" tampoco está limpio: en esos días la v2 se construía en
el worktree `Bootstrap-Skills-bootstrap-v2` con su propio `CLAUDE.md` a medio cambiar, y el conjunto
`bs-todos` incluye esas sesiones. Y la métrica titular del beneficio, los hallazgos por reporte, está
confundida con un cambio en el formato de los reportes entre un brazo y otro (sección 3). Con 14 y 7 slices
cerrados por brazo, ningún cociente por slice sostiene una conclusión.

Issue: `.scratch/medicion-v2/issues/08-retrospectivo-este-repo.md`. PRD: `.scratch/medicion-v2/PRD.md`.

## 1. El corte

El partidor divide un solo snapshot por fecha, así que los dos brazos comparten la ventana y el
ruleset (ADR-0006 de claude-analytics). El borde es la fecha en que la doctrina de la v2 entró a
este repo, leída de git (`git log --first-parent main -- CLAUDE.md docs/ai-workflow .claude`):

| Fecha (UTC) | Commit | Qué entró | Papel |
|---|---|---|---|
| 2026-09-11 22:52 | `f7ae28f` | scaffold `2026-09-11`, con el review-loop de ADR-0009 (`cb5b6cd`, `451eb32`) | **inicio** del "antes": es la doctrina v1 que se compara |
| 2026-09-21 18:47 | `816f4f3` | merge de la v2 (release v2.0.0): cambian a la vez `CLAUDE.md`, `docs/ai-workflow/` y `.claude/` | **borde principal** |
| 2026-09-23 15:52 | `7131d3d` | ADR-0013 (las 9 skills vuelven a ser model-invoked), base del tag `v2.1.0` | **borde de control**, para ver si el signo depende del corte |

El "después" termina donde termina el snapshot: 2026-09-27 17:52 UTC.

## 2. Método

- **Snapshot**: `claude-analytics/output/raw/review-cost-snapshot-2026-09-27` (congelado por la
  tarea semanal; 3.865 subagentes, `t0` del 2026-08-27 al 2026-09-27).
- **Filtro por repo**: el partidor no filtra por repo, así que `filtrar.py` escribe una copia con
  los subagentes cuyo `cwd` está en el repo y cuyo `t0` es posterior al inicio. Dos conjuntos:
  `bs-main` (solo el árbol principal: 697 subagentes) y `bs-todos` (más los carriles y el worktree
  de la v2: 897). Ninguno sin fecha.
- **Beneficio**: `tools/finding-measure.ts --split <borde>` de claude-analytics (`master`), ruleset
  `v2-2026-09-09`. Su denominador, `report.present`, es **todo subagente con reporte**, no solo los
  reviewers.
- **Por qué todos los subagentes y no solo los reviewers**: `clasificar.mts` le pasa el clasificador
  de reviewers de claude-analytics (`focus-rules`, v3 del 2026-09-04) a los dos conjuntos. En
  `bs-todos` reconoce 293 de 516 en el "antes" y 188 de 381 en el "después". Entre los prompts
  que deja afuera hay focos y scorers de `/slice-review` ("Sos el foco **Bugs** de
  un /slice-review", "Brief and rubric: …"), con formatos que el clasificador no conoce. Filtrar
  con él quitaría reviewers de verdad, y más de un brazo que del otro. Los subagentes que no son
  review (prompts con `implementador`, `carril`, `investig`…) son 17 de 516 y 10 de 381 en
  `bs-todos`.
- **Costo por slice**: `contar_slices.py`. De git (`--all`, deduplicado por subject porque los
  carriles se integran por cherry-pick) toma los commits con trailer `Slice-Close`, su
  `Review-Rigor` y los commits cuyo subject nombra un "turno". Del snapshot toma los subagentes y el
  `outTok`. Todo es por fecha de committer o por `t0`, con los mismos bordes.
- **Cómo re-correrlo**, desde un checkout de claude-analytics en `master`:
  ```
  python <aca>/filtrar.py <snapshot> <salida>
  node --import tsx <aca>/clasificar.mts <salida> <borde>
  node --import tsx <aca>/auditar.mts <salida> <borde>
  node --import tsx tools/finding-measure.ts --split <borde> <salida>/bs-main <salida>/bs-todos
  python <aca>/contar_slices.py <este repo> <salida>/bs-todos/agents.jsonl <borde> 2026-09-27T17:53:00Z
  ```

## 3. Beneficio: hallazgos por reporte (`finding-measure`)

| Métrica (denominador) | Borde | bs-main antes | bs-main después | bs-todos antes | bs-todos después |
|---|---|---|---|---|---|
| hallazgos cada 100 reportes (`report.present`) | 09-21 | 402/435 (92,4) | 158/262 (60,3) | 448/516 (86,8) | 262/381 (68,8) |
| | 09-23 | 466/507 (91,9) | 94/190 (49,5) | 593/647 (91,7) | 117/250 (46,8) |
| reportes con hallazgos (`report.present`) | 09-21 | 114/435 (26,2 %) | 43/262 (16,4 %) | 124/516 (24,0 %) | 67/381 (17,6 %) |
| High (`findings.total`) | 09-21 | 22/402 (5,5 %) | 1/158 (0,6 %) | 23/448 (5,1 %) | 5/262 (1,9 %) |
| reportes con tabla (`report.present`) | 09-21 | 22/435 (5,1 %) | 0/262 (0,0 %) | 30/516 (5,8 %) | 0/381 (0,0 %) |

Con los dos bordes y en los dos conjuntos baja, **pero ese número no se puede leer**. El parser
cuenta hallazgos que están rotulados (tabla, encabezado, negrita), y el formato de los reportes cambió
entre los brazos: las tablas pasan de 30/516 a 0/381. No medí qué parte de la v2 lo causa. `auditar.mts` cuenta, en `bs-todos`, los
reportes que nombran una severidad (High, Medium…) y de los que el parser no sacó ningún hallazgo:
230/516 (44,6 %) en el "antes" y 195/381 (51,2 %) en el "después". Es una cota gruesa, porque "no
High findings" también nombra una severidad. Aun así alcanza para ver que el parser se pierde una
parte grande en los dos brazos, y una parte mayor en el "después". Con eso, la caída puede venir
entera del formato y no de la doctrina.

## 4. Costo por slice cerrado (`bs-todos`, no depende del formato)

| Métrica (denominador) | Borde | antes | después |
|---|---|---|---|
| slices cerrados (standard / light) | 09-21 | 14 (11 / 3) | 7 (4 / 3) |
| | 09-23 | 16 (12 / 4) | 5 (3 / 2) |
| commits de turno por slice cerrado | 09-21 | 35/14 = 2,5 | 30/7 = 4,3 |
| | 09-23 | 53/16 = 3,3 | 12/5 = 2,4 |
| subagentes por slice cerrado | 09-21 | 516/14 = 36,9 | 381/7 = 54,4 |
| | 09-23 | 647/16 = 40,4 | 250/5 = 50,0 |
| `outTok` de subagentes por slice cerrado | 09-21 | 7.364.008/14 = 526.001 | 3.614.946/7 = 516.421 |
| | 09-23 | 8.982.005/16 = 561.375 | 1.996.949/5 = 399.390 |

- **Commits de turno por slice**: el signo se invierte según el borde. No dice nada.
- **Subagentes por slice**: sube con los dos bordes (+47 % y +24 %). Es la única dirección que no
  depende del corte, y con 7 y 5 slices en el "después" sigue siendo ruido posible. No resta el
  trabajo que no cierra slice (la corrida en seco, los carriles del aparato), que en el "después" es
  proporcionalmente mayor.
- **`outTok` por slice**: plano con el primer borde, baja con el segundo. No dice nada.
- El costo del loop principal (`tokenShare` de `report review-cost --split`) no se corrió: necesita
  cargar el snapshot a la DB, que está bloqueada por la sincronización cada 10 minutos, y ese
  reporte tardó más de 40 minutos sin terminar con 1.893 agentes (`.scratch/issue-review-cost-lento.md`
  de claude-analytics).

## 5. Qué dice, contra el A/B

Nada que contradiga ni confirme el A/B. Lo único estable ante el corte es que en el "después" se
lanzan más subagentes por slice cerrado. La caída de hallazgos queda sin atribuir hasta que el
parser de `finding-rules` lea el formato de reporte de la v2, y ese arreglo es de claude-analytics,
no de este PRD.
