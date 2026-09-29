# Retrospectivo de la v2 en este repo — 2026-09-29

**Los dos brazos están contaminados y este reporte vale como contraste, no como veredicto.** El
"después" es la v2 usada por la misma persona que la escribió, sobre un trabajo distinto (el aparato
de medición, en vez del release). El "antes" tampoco está limpio: en esos días la v2 se construía en
el worktree `Bootstrap-Skills-bootstrap-v2` con su propio `CLAUDE.md` a medio cambiar, y el conjunto
`bs-todos` incluye esas sesiones. Y la métrica titular del beneficio, los hallazgos por reporte, está
confundida con un cambio en el formato de los reportes entre un brazo y otro (sección 3). Y el
"después" cierra muchos más slices `light` que el "antes" (sección 4), así que el costo por slice
tampoco compara lo mismo.

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
  review (los que en los primeros 160 caracteres se presentan como carril o implementador, o
  arrancan pidiendo una búsqueda con "Buscá" o "Necesito": la regex `NO_REVIEW` de
  `clasificar.mts`) son 12 de 516 y 12 de 381 en `bs-todos`.
- **Costo por slice**: `contar_slices.py`. De git (`--all`, deduplicado por subject porque los
  carriles se integran por cherry-pick) toma los commits con una línea `Slice-Close:` en cualquier
  parte del mensaje (como el hook: el parser de trailers de git solo lee el último párrafo), su
  `Review-Rigor` y los commits cuyo subject nombra un "turno". Del snapshot toma los subagentes y el
  `outTok`. Los commits van por fecha de autor, que un rebase no cambia, y los subagentes por `t0`,
  con los mismos bordes.
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
| slices cerrados (standard / light) | 09-21 | 36 (30 / 6) | 23 (12 / 11) |
| | 09-23 | 42 (35 / 7) | 17 (7 / 10) |
| commits cuyo subject nombra un turno, por slice cerrado | 09-21 | 43/36 = 1,2 | 22/23 = 1,0 |
| | 09-23 | 53/42 = 1,3 | 12/17 = 0,7 |
| subagentes por slice cerrado | 09-21 | 516/36 = 14,3 | 381/23 = 16,6 |
| | 09-23 | 647/42 = 15,4 | 250/17 = 14,7 |
| `outTok` de subagentes por slice cerrado | 09-21 | 7.364.008/36 = 204.556 | 3.614.946/23 = 157.172 |
| | 09-23 | 8.982.005/42 = 213.857 | 1.996.949/17 = 117.468 |

- **Subagentes por slice**: +16 % con un borde y −4,5 % con el otro. No dice nada.
- **`outTok` por slice** baja con los dos bordes (−23 % y −45 %), y los commits de turno por slice
  también (la fila cuenta además 11 commits `docs(handoff)` que nombran un turno sin serlo). Pero la
  mezcla de rigor cambió: los slices `light` pasan de 6 de 36 (17 %) a 11 de 23 (48 %) con el primer
  borde, y de 7 de 42 a 10 de 17 con el segundo, y un slice `light` corre un solo turno con dos
  focos. La baja puede venir entera de esa mezcla, que no es de la v2: `Review-Rigor` entró con
  ADR-0009, antes del inicio.
- El costo del loop principal (`tokenShare` de `report review-cost --split`) no se corrió: necesita
  cargar el snapshot a la DB, que está bloqueada por la sincronización cada 10 minutos, y ese
  reporte tardó más de 40 minutos sin terminar con 1.893 agentes (`.scratch/issue-review-cost-lento.md`
  de claude-analytics).

## 5. Qué dice, contra el A/B

Nada que contradiga ni confirme el A/B. Lo único que no depende del corte es que en el "después"
cada slice cerrado costó menos `outTok` de subagentes, y eso está confundido con la mezcla de
rigor. La caída de hallazgos queda sin atribuir hasta que el
parser de `finding-rules` lea el formato de reporte de la v2, y ese arreglo es de claude-analytics,
no de este PRD.
