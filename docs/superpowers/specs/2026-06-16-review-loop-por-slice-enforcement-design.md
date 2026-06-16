# Diseño: enforcement de slices chiquitos + review-loop por slice

**Fecha:** 2026-06-16
**Repo:** `C:\Repos\PERSONAL\Bootstrap Skills` (fuente de verdad de las skills bootstrap)
**Estado:** propuesto (pendiente de revisión del usuario)

## Problema

El review-loop no se está ejecutando con cada unidad de trabajo, como se había
diseñado. Observado en dos proyectos reales:

- **Forecasting App** (repo git **local sin remote**, branch `master`): el hook
  `review-loop-trigger` está instalado pero **nunca disparó** (no existe
  `.git/review-loop-state.json`). Causa: el hook cuelga de `git push` /
  `gh pr create`, y en un repo local sin remote ninguno de los dos ocurre.
- **KBS Orders Development** (en GitHub): no tiene el scaffold instalado (se
  intentó `upgrade-bootstrap` sobre un proyecto que nunca fue bootstrapeado;
  `upgrade-bootstrap` no bootstrapea proyectos vírgenes). Caso aparte: corregir
  con `bootstrap-southpoint-project`. **Fuera de alcance de este spec.**

Síntoma de fondo (independiente de GitHub): el agente escribe todo el código de
todas las tareas en una sola tanda y recién al final ofrece —preguntando— el
review-loop. Las dos causas raíz:

1. **Los slices no nacen chiquitos.** `to-issues` parte el trabajo en vertical
   slices pero **no pone techo de tamaño**; la regla `≤ ~400 líneas` del
   `CLAUDE.md` es pasiva y el agente la ignora.
2. **El loop no se dispara por unidad de trabajo.** El trigger depende de
   `git push`/`gh pr create` (no ocurren en local) y `tdd` no tiene un paso de
   cierre de slice que fuerce el review. El lenguaje es sugerente ("sugerí
   review-loop"), no imperativo, así que el agente pregunta en vez de ejecutar.

## Objetivos

- El review-loop corre con **cada commit de implementación** y un pase final al
  cerrar cada slice, **sin preguntar**.
- Los slices nacen chiquitos (≤ ~400 líneas de **lógica**) y se parten en
  planificación, no al final.
- Un solo mecanismo que funcione igual en **repos locales sin remote** y en
  **repos con GitHub** (no fragmentar en dos sistemas).
- Cambios **espejados** en `bootstrap-personal-project` y
  `bootstrap-southpoint-project` (hard rule del repo).

## No-objetivos (explícitamente descartado)

- **Sacar el review-loop a una GitHub Action / servicio externo estilo Greptile.**
  Evaluado y descartado: el usuario también trabaja en repos locales sin remote
  (Forecasting App), donde una Action no puede correr; tendría que mantener dos
  mecanismos distintos; agrega fricción de CI (runner, `ANTHROPIC_API_KEY` como
  secret, billing aparte); y no resuelve el problema de los PRs grandes (un
  review server-side sobre 1000 líneas sigue siendo malo). Greptile gana con ese
  modelo porque el review-server *es su producto*; replicarlo es complejidad sin
  retorno para este flujo.
- Arreglar el estado de KBS (es un bootstrap faltante, no un problema de diseño).
- Un gate mecánico **duro** que bloquee commits por conteo crudo de líneas
  (contraproducente: falsos positivos en generado/vendor/lockfiles/snapshots →
  evasión con `--no-verify`). El conteo es un **aviso**, no un bloqueo.

## Decisión de ritmo: multi-commit por slice

Elegido **multi-commit** (cada paso green/refactor su propio commit) por sobre
"un commit de cierre por slice". Razón del usuario: revisar en cada commit
asegura la calidad incremental; para cuando se cierra el slice, el review del
diff acumulado encuentra poco (solo problemas de interacción entre commits). Se
prioriza calidad de código por sobre economía de tokens.

Implicancia: el hook dispara una vez por commit (dedupe por SHA del HEAD ⇒ no
re-dispara sobre el mismo commit). Es más caro en tokens, aceptado a conciencia.

### Manejo del commit RED

Un commit que es solo un test que falla a propósito (RED en TDD) no tiene código
de implementación que revisar. Reglas:

- El flujo `tdd` corre el loop **tras green/refactor**, no tras red.
- Si el hook igual dispara sobre un commit RED, el **pre-flight del loop** lo
  detecta (no hay código nuevo significativo / los tests fallan por diseño) y
  cierra sin ruido. El loop ya es idempotente: re-revisar algo limpio cierra en
  un turno.

## Diseño — 5 cambios espejados

El enforcement primario vive en el **flujo (las skills)**, no en el hook. Un hook
de Claude Code no ejecuta una skill: solo inyecta `additionalContext` que el
modelo puede seguir o ignorar. El hook es el **refuerzo determinístico** en los
puntos git; las skills son el mecanismo principal.

### ① `to-issues` — techo de tamaño en planificación

En `<vertical-slice-rules>`, agregar: cada slice se estima y se mantiene en
**≤ ~400 líneas de diff de lógica**. No cuentan archivos generados, vendor,
lockfiles ni snapshots. Si un slice se proyecta más grande, **partirlo antes de
publicarlo**. En el quiz al usuario, agregar la pregunta de tamaño
("¿algún slice se proyecta > ~400 líneas? partámoslo").

### ② `tdd` — nuevo Step 5 "Cerrar el slice" (corazón del fix)

Después del refactor, antes de pasar al próximo slice:

1. Chequear tamaño del diff (`git --no-pager diff --stat`), con exclusiones. Si
   excede ~400 líneas de lógica, partir/cerrar lo cohesivo primero.
2. Correr `/review-loop` sobre el diff del slice **sin preguntar**, hasta cerrar
   (cero hallazgos medium/high o tope de 5 turnos).
3. Recién entonces, el próximo slice.

Además, en el Incremental Loop (Step 3), tras cada green/refactor el agente
commitea y deja que el ritmo de review corra (loop por commit). Redacción
imperativa: "no marques el slice como terminado hasta que el loop cierre".

### ③ `CLAUDE.md` — endurecer el lenguaje

- La regla de tamaño pasa de "Target ≤ ~400 lines" a regla de proceso con
  exclusiones explícitas (generado/vendor/lockfiles/snapshots no cuentan).
- La transición de review pasa de "sugerir `/review-loop`" a "correr
  `/review-loop` al cerrar cada slice y tras cada commit de implementación,
  **sin preguntar**".

### ④ Hook `review-loop-trigger.ps1` — ampliar matcher a `git commit`

- Agregar `git commit` a los comandos que disparan (además de `git push` /
  `gh pr create`), para cubrir repos locales sin remote.
- Mantener el resto de la lógica: resolución dinámica de base, dedupe por SHA en
  `.git/review-loop-state.json`, salida silenciosa (`exit 0`) en cualquier
  camino que no aplique.
- Reescribir el mensaje inyectado a **orden imperativa, no oferta**: "Ejecutá
  `/review-loop` ahora sobre el diff del slice. No preguntes. No marques el
  trabajo como completo hasta cerrar el loop."
- El diff a revisar: en repo con remote/PR, `git diff <base>...HEAD` (como hoy);
  en commit local, el diff del slice (último commit / acumulado contra base
  local) — coordinado con el ⑤.

### ⑤ `review-loop` SKILL.md — "Modo commit/local"

Agregar una sección análoga al "Modo PR" existente: cuando lo dispara un `git
commit` (típicamente repo local sin remote), revisar el diff del slice. Aclarar
el pre-flight para el caso RED (si no hay código de implementación que revisar,
cerrar sin ruido).

## Espejado, deploy y manifest

- Aplicar los 5 cambios **idénticos** en ambas skills bootstrap (solo difieren en
  contenido DOMO e identidad git, que acá no aplican).
- `upgrade-bootstrap`: verificar que los cambios de `settings.json`/hook se
  propaguen vía `merge-settings.ps1` (el matcher sigue siendo `Bash`; cambia el
  script, no la estructura del `settings.json`, así que el merge no debería
  romperse — confirmar en eval).
- Regenerar `.bootstrap-manifest.json` con `tools/sync-skills.ps1` al deployar.
- Deploy con `tools/sync-skills.ps1`; commit con identidad local
  `MartinDele703 <martin.deleon703@gmail.com>`.

## Testing (evals con skill-creator)

- Eval directorio vacío: bootstrap genera el scaffold con los 5 cambios.
- Eval archivos preexistentes (modo adopción/merge): no rompe `settings.json`
  propios.
- Eval del hook: `git commit` en branch de feature inyecta la orden imperativa;
  dedupe por SHA no re-dispara; commit RED no genera ruido.
- Eval `upgrade-bootstrap`: un proyecto ya bootstrapeado adopta el nuevo hook +
  ritmo sin pisar personalizaciones.

## Riesgos / trade-offs

- **Costo de tokens** por review en cada commit. Aceptado a conciencia
  (prioridad: calidad).
- **Falsos disparos** del hook (p. ej. commit RED, commits de docs). Mitigado por
  el pre-flight del loop que cierra rápido si no hay nada que revisar.
- **Estimar líneas en planificación es impreciso.** Por eso es guía + aviso, no
  ley dura; el criterio primario sigue siendo la cohesión del slice.
