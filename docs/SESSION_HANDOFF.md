# Session Handoff — 2026-08-26 parte 2 (08b CERRADO + COMMITEADO `2ca95f6` — framing de la premisa caduca + guard del workflow doc; review-loop dogfoodeado limpio + COHERE — TRACK A / issue 08 COMPLETO — próximo: DEPLOY, luego ROLLOUT de B)

## ▶▶▶▶▶▶▶▶▶▶▶▶ ESTADO AL RETOMAR — próximo: (1) DEPLOY (con humano), luego (2) ROLLOUT de B a los 4 repos

Rama **`feat/marcador-de-revision`**, HEAD **`2ca95f6`** (`feat(review-loop): 08b — framing de la
premisa /code-review caducada + guard del workflow doc`, **sin trailer**). **Árbol limpio.** `range`
post-close **vacío + exit 0** = nada sin revisar. **Sin pushear.** **08a Y 08b CERRADOS → el issue 08
está COMPLETO** (solo queda deploy + rollout, ambos operativos). No hay decisión pendiente del usuario
salvo arrancar el deploy.

### Qué hizo esta sesión (08b — framing, CERRADA)

08a ya estaba cerrado y commiteado (`f3ed1fe`). Esta sesión implementó **08b** (corrección de framing,
doc) y lo cerró con el review-loop dogfoodeando el ensemble:

1. **Framing corregida** (la premisa "/code-review es human-only / no invocable" caducó): `README.md`
   (justifica `/slice-review` por su valor real + ensemble del turno 1), `docs/ai-workflow/AI_DEVELOPMENT_WORKFLOW.md`
   (**raíz + 3 scaffolds**, en la allowlist de divergencia del mirror), `docs/TESTING.md` (premisa →
   valor real; caso "Regresión a /code-review" **invertido**; documentados los tests nuevos del foco),
   `docs/adr/0001` (nota fáctica corregida sin afirmar la causa caduca + nota de expiración → ADR-0003).
   **`public/README.md` NO se tocó**: no tenía la premisa (verificado por 3 focos; el conteo de "6
   archivos" del handoff viejo lo incluía por error). **`review-loop.md`/SKILL ya limpios por 08a.**
2. **Guard nuevo 08b** en `tests/slice-review.tests.ps1` (bloque al final, `$workflowDocs`): blinda las
   **4 copias** de `AI_DEVELOPMENT_WORKFLOW.md` (repo + 3 scaffolds) con `-notmatch 'restricted to human
   invocation'` + positivo `folds in the built-in /code-review` (borrar la frase sin poner la framing
   correcta también falla). **RED verificado** (inyecté la premisa → 2 asserts fallaron → revertí con
   Edit reversible → GREEN). Motivo: el guard de 08a solo cubría los pares slice/loop, y mirror solo
   exige byte-identidad ENTRE scaffolds — el workflow doc quedaba sin blindar.
3. **3 manifests regenerados** (`gen-manifest.ps1`; solo el hash del workflow doc + version stamp, sin
   ruido de autocrlf).
4. **Review-loop dogfoodeado (ensemble) CERRADO LIMPIO**: turno 1 (5 focos de lectura + fork de
   `/code-review` medium) → **3 hallazgos reales**: (A) `README.md` "almost no cost" sin hedge —regla de
   afirmaciones, 2 focos—; (B) `docs/adr/0001` "los primeros reviewers de la historia del repo"
   sobre-generalizaba —2 focos—; (C) faltaba guard de test del workflow doc —1 foco—. **Fixes**: A hedge
   de latencia (a confirmar, no medido), B acotado a lo medido, C el guard nuevo. → turno 2 (3 focos)
   **limpio** → coherencia **COHERE** (5 AC) → `close` limpio.
   - **Descartados**: (D) el diff de review excluyó scaffolds/manifests —deliberado, espejo idéntico al
     raíz ya revisado—; (#2) `slice-review.md:180` el texto de dedup motiva el solape solo contra "Bugs
     focus" pero `/code-review` también puede duplicar "Contracts and callers" —**fuera de scope** (es
     de 08a); anotado como **follow-up Low** en el issue 08—.
5. **Commit `2ca95f6`** (11 archivos, sin trailer — el loop ya corrió sobre el árbol). **Suites verdes**:
   `slice-review`, `mirror`, `review-loop-incremental`. Memorias `slice-review-motor-del-loop.md` +
   `MEMORY.md` actualizadas (08a+08b cerrados).

### 🔴 Gotcha reconfirmado esta sesión (marcador previo a ADR-0003)

El marcador de 08a quedó en `950cc8e2` (un punto **previo** a la creación de `docs/adr/0003` en 08a —
consistente con el gotcha del `index.lock` que documentó el handoff de 08a). Por eso el delta de 08b
**incluyó ADR-0003** (114 líneas, de 08a) además de los 5 archivos de 08b. No fue un problema (0003 ya
se revisó en 08a; re-revisarlo fue barato y COHERE lo confirmó), pero **si al retomar un range sale más
grande de lo esperado, sospechar del marcador** (ver el follow-up del `git stash create` vacío abajo).

### Roadmap restante (en orden) — issue 08 COMPLETO; queda solo el despliegue de Track A

- **(1) DEPLOY** (A7-like, **con humano presente**): resellar el `.bootstrap-manifest.json` de la **RAÍZ**
  (`tools/reseal-manifest.ps1`) + `tools/sync-skills.ps1` (regenera los 3 manifests de scaffold y deploya
  a `~/.claude/skills`). Requiere presencia humana.
- **(2) ROLLOUT de B** — `upgrade-bootstrap` a los 4 repos + revertir la mitigación interina. **🔴 lo
  frena el clasificador de auto-mode** (edita/gitea otros repos): permiso amplio o sesión dedicada por
  repo. Los 4 (memoria `forecasting-app-mitigacion-interina-review`): **Forecasting App**, **Outsourcing
  Development** (git en `hssapp/`, usar `-C hssapp`), **claude-analytics** (Claude Analytics), **Survey
  Clients**. Revertir en cada uno: borrar `.scratch/review-loop-interino.md` + quitar el bullet ⚠️
  INTERINO del `CLAUDE.md`, **solo** tras confirmar que el review-loop nuevo quedó instalado ahí.
- **Follow-ups anotados en el issue 08 (Notas)**: (a) el texto de dedup de `slice-review.md` motiva el
  solape solo contra "Bugs focus" (también puede duplicar "Contracts and callers") — refinamiento Low de
  redacción, toca los 4 espejos + manifests, slice propio; (b) `review-marker.ps1` debería tratar un
  `git stash create` vacío como **error duro**, no fallback silencioso a HEAD (toca ADR-0001 → slice de
  robustez); (c) Lows viejos: prosa Step 2 slice-review (`--stat` vs `git show HEAD`); `autocrlf`
  date-bump en manifests; `copy-scaffold.ps1` pisa `.gitignore`.

### Antes de tocar código (crítico)

- **Deploy y rollout son OPERATIVOS, no diseño.** El paso 1 (grill) del issue 08 está cerrado. Si el
  `alignment-gate` frena el primer edit de **código** (los `.md`/`docs/` pasan sin frenar), **decilo y
  reintentá, NO re-grilles** (frenó 1 vez esta sesión sobre el `.ps1` del guard; se reintentó).
- **Regla del espejo**: canónicos en raíz (`.claude/commands/*.md`, `.agents/skills/*/SKILL.md`), `cp` a
  los 3 scaffolds, regenerar los 3 manifests (`tools/gen-manifest.ps1 -SkillDir skills/<s>`). **`tests/`
  y `docs/` del REPO NO se espejan**, pero `assets/scaffold/docs/ai-workflow/AI_DEVELOPMENT_WORKFLOW.md`
  SÍ existe en los 3 scaffolds (en la **allowlist de divergencia** de `mirror.tests.ps1:23` — pueden
  divergir; NO exige byte-identidad). Manifests **generados**, identidad por hash normalizado.
- **⚠️ Line-wrap**: los asserts de los `.tests.ps1` son `-match` sin singleline; una frase asertada
  partida en 2 líneas por el reflow FALLA. Mantener contigua la frase asertada.
- **Bash tool = Git Bash**: commits `-m "..."` repetidos, **nunca** here-strings `@'...'@`. Tests Pester
  v3 con harness propio: FOREGROUND con redirect + grep `^FAIL:`/"TODOS LOS TESTS PASARON". `review-marker`
  tarda; las otras ~30-120s.
- **Review-loop con foco de code-review** (si se dogfoodea de nuevo): esperar el fork completo antes del
  `advance`; chequear `.git/index.lock` stale antes de las ops del marcador; reviewers en SOLO LECTURA;
  `/code-review` read-only nunca `--fix`.

### Preferencias del usuario (vigentes)

- **No commitear sin que lo pida** (esta sesión pidió: commit de 08b). **Nada a Zoho.** **Impacto medido
  antes de cambiar el proceso.** **Decidir lo técnico, preguntar lo de diseño.** **Prefiere Opus 4.8
  sobre Opus 5.** **Paraleliza todo lo posible.** Prefiere **cortar y seguir en terminal nueva** — por
  eso este handoff.

---

# Session Handoff — 2026-08-26 (08a CERRADO + COMMITEADO `f3ed1fe` — review-loop dogfoodeado limpio + coherencia COHERE — próximo: 08b, luego deploy/rollout)

## ▶▶▶▶▶▶▶▶▶▶▶▶ ESTADO AL RETOMAR — próximo: (1) 08b (framing en 6 archivos, apilado sobre 08a), luego deploy + ROLLOUT de B

Rama **`feat/marcador-de-revision`**, HEAD **`f3ed1fe`** (`feat(review-loop): 08a — /code-review como
foco par acotado del turno-1 (ensemble)`, **sin trailer**). **Árbol limpio.** `range` post-close
**vacío + exit 0** = nada sin revisar. **Sin pushear.** No hay decisión pendiente salvo arrancar 08b.

### Qué hizo esta sesión (08a — mecánica del ensemble, CERRADA)

El grill del issue 08 ya estaba cerrado (parte 3). Esta sesión implementó **08a** test-first y lo
cerró con el review-loop dogfoodeando el foco nuevo:

1. **Feasibility VERIFICADA** (regla de afirmaciones): `/code-review` es invocable **desde un
   subagente** — se despachó uno que lo lanzó como fork y corrió hasta completarse. La premisa
   "human-only" caducó. ⇒ wiring: foco par en la ola del fan-out de Step 4 (contexto principal), sin
   fallback.
2. **Mecánica (test-first, 3 cycles RED→GREEN)**: flag `--code-review` en `/slice-review` (Step 1
   parse + Step 4 dispatch + sección `## Code-review focus`), simétrico con `--mutation`, turno-1-only,
   esfuerzo **medium**. **Paso de dedup** nuevo en Step 5 (colación antes del scoring, vs foco de bugs,
   por defecto subyacente). `/review-loop` pasa `--code-review` en el turno 1. **Guard invertido**
   (de "prohibido ordenar /code-review" → positivo turno-1/medium). **Framing local** corregida SOLO
   en `slice-review.md`/`review-loop.md` (los otros 6 archivos → 08b, para no dejar 08a incoherente).
   **ADR-0003** nuevo. Espejo ×4 + 3 manifests.
3. **Review-loop dogfoodeado y CERRADO LIMPIO**: turno 1 (5 focos de lectura + el **fork de
   `/code-review` medium** como 6º foco) → turno 2 (1 **Medium**: concurrencia) → turno 3 (limpio) →
   coherencia **COHERE** → cierre limpio. El dogfood valió: `/code-review` aportó **2 hallazgos únicos**
   (scope del rango + duplicación de flags) que ningún otro foco vio.
4. **Contratos robustos del dogfood** (todos en la mecánica): `/code-review` read-only/**sin `--fix`**;
   revisa el **working-tree diff** (no toma el stash ref del marcador); **join del fork async** (juntar
   sus hallazgos antes de Step 5); y **concurrencia del `index.lock`** — ver abajo.
5. **13 suites verdes**. Commit **`f3ed1fe`** (21 archivos, sin trailer — el loop ya corrió sobre el
   árbol; con trailer re-dispararía con range vacío).

### 🔴 Gotcha nuevo descubierto (crítico para futuros review-loops con el foco de code-review)

**El fork de `/code-review` corre `git` en el repo real en paralelo.** Esta sesión dejó un
`.git/index.lock` stale que hizo **fallar en silencio el `git stash create`** del `-Action advance`
del marcador → cayó a **HEAD** (over-scope). Se detectó (el rango del turno 2 dio el slice entero),
se removió el lock stale (0 bytes, 16 min → seguro) y se siguió. **Mitigado en la mecánica**: el foco
y el paso 3 del loop ahora ordenan **dejar terminar el fork y limpiar el lock stale antes de las ops
del marcador**. Si al retomar un review-loop el `advance` devuelve HEAD y el rango sale enorme,
sospechar del `index.lock`.

### Roadmap restante (en orden)

- **(1) 08b** — corrección de framing (doc), **apilado sobre 08a**. Los 6 archivos con la premisa
  caduca: `review-loop.md`/SKILL ×4 (nota: 08a ya corrigió el CUERPO de review-loop; 08b revisa que no
  quede resto), `README.md`, `public/README.md`, `docs/TESTING.md` (+ documentar los tests nuevos del
  foco de code-review), `AI_DEVELOPMENT_WORKFLOW.md`, `docs/adr/0001` (corregir la nota fáctica falsa
  en `0001:15-17` "un reviewer que el agente no podía invocar"). Ningún archivo debe afirmar que
  `/code-review` es human-only. Actualizar la memoria `slice-review-motor-del-loop.md` al cerrar 08b.
- **(2) Deploy** (A7-like, con humano): resellar el `.bootstrap-manifest.json` de la RAÍZ +
  `sync-skills.ps1` a `~/.claude/skills`. Requiere presencia humana.
- **(3) ROLLOUT de B** — `upgrade-bootstrap` a los 4 repos + revertir la mitigación interina.
  **🔴 lo frena el clasificador de auto-mode** (edita/gitea otros repos): permiso amplio o sesión
  dedicada por repo. Los 4 repos (memoria `forecasting-app-mitigacion-interina-review`): **Forecasting
  App**, **Outsourcing Development** (git en `hssapp/`, usar `-C hssapp`), **claude-analytics** (Claude
  Analytics — **discrepancia RESUELTA**: `docs/adr/0001:8` lo nombra textual; la parte-2 decía "Call
  Center" por error), **Survey Clients**.
- **Follow-up anotado (issue 08 Notas)**: `review-marker.ps1` debería tratar un `git stash create`
  vacío como **error duro**, no fallback silencioso a HEAD (toca la lógica de ADR-0001 → slice propio
  de robustez del marcador). Lows viejos: prosa Step 2 slice-review; `autocrlf` date-bump en manifests;
  `copy-scaffold.ps1` pisa `.gitignore`.

### Antes de tocar código (crítico)

- **08b es doc/framing.** El paso 1 (grill) del issue 08 YA está cerrado. Si el `alignment-gate` frena
  el primer edit de código, **decilo y reintentá, NO re-grilles**.
- **Regla del espejo**: canónicos en raíz (`.claude/commands/*.md`, `.agents/skills/*/SKILL.md`), `cp`
  a los 3 scaffolds, regenerar los 3 manifests (`tools/gen-manifest.ps1 -SkillDir skills/<s>`). **`tests/`
  y `docs/` NO se espejan.** Manifests **generados**. Identidad por hash normalizado, no `diff` crudo.
  **⚠️ Line-wrap**: los asserts son `-match` sin singleline; una frase asertada partida en 2 líneas por
  el reflow FALLA (mordió 1 vez esta sesión: "prohibited on turns 2 onward").
- **Bash tool = Git Bash**: commits `-m "..."` repetidos, **nunca** here-strings `@'...'@`. Tests Pester
  v3 con harness propio: FOREGROUND con redirect + grep `^FAIL:`/"TODOS LOS TESTS PASARON". `review-marker`
  tarda >2min (no la tocó 08a).
- **Review-loop con el foco de code-review**: al dogfoodearlo, el agente principal (corriendo
  `/slice-review`) despacha los focos de lectura como subagentes Y invoca `/code-review` (Skill tool,
  args de esfuerzo `medium`) en el mismo mensaje. **Esperar el fork completo antes del `advance`** (ver
  el gotcha del index.lock). Reviewers en SOLO LECTURA; `git status` antes de creerle a un hallazgo.

### Preferencias del usuario (vigentes)

- **No commitear sin que lo pida** (esta sesión pidió: commit de 08a). **Nada a Zoho.** **Impacto
  medido antes de cambiar el proceso.** **Decidir lo técnico, preguntar lo de diseño.** **Prefiere Opus
  4.8 sobre Opus 5.** **Paraleliza todo lo posible.** Prefiere **cortar y seguir en terminal nueva** —
  por eso este handoff.

---

# Session Handoff — 2026-08-25 parte 3 (TRACK A MERGEADO+PUSHEADO a origin/main + grill del issue 08 CERRADO (08a→08b apilados) + review-loop del push CERRADO LIMPIO — próximo: ROLLOUT de B, luego 08a)

## ▶▶▶▶▶▶▶▶▶▶▶▶ ESTADO AL RETOMAR — próximo: (1) ROLLOUT de B a los 4 repos (bloqueado por el clasificador esta sesión), (2) implementar 08a

Rama **`feat/marcador-de-revision`**. **Track A COMPLETO, MERGEADO a `main` (fast-forward) y PUSHEADO
a `origin/main`** (`7993f68..2f94108`, remoto `origin` = southpointtech, único remoto). El review-loop
que disparó el push **cerró LIMPIO** (1 turno). **Lo único que queda del pedido B es el ROLLOUT**, que
el clasificador de auto-mode frenó esta sesión.

### 🔴 Bloqueo de entorno descubierto esta sesión (crítico para el próximo)

El **clasificador de auto-mode denegó**: (a) lanzar un **fork/Agent autónomo** que hiciera
merge/push/rollout ("Blocked by classifier"), y (b) **`git push`** hasta que el usuario dio permiso
explícito por chat (ahí sí pasó). **Los subagentes de SOLO LECTURA (reviewers del slice-review) SÍ se
lanzaron** sin problema. Consecuencia: **el rollout (que edita/gitea otros repos) va a chocar el mismo
muro** — hacerlo con permiso Bash amplio para `git`/edición, o en sesión dedicada por repo.

### Qué hizo esta sesión

1. **B — merge + push HECHOS.** `main` se avanzó a `2f94108` con `git branch -f main
   feat/marcador-de-revision` (**fast-forward, SIN checkout** — para no tocar el working tree mientras
   corría el grill; era ff porque `HEAD..main` estaba vacío). `git push origin main` → `7993f68..2f94108`.
   Tests previos: **13/13 suites verdes**. **`origin` es el único remoto** (southpointtech); no existe
   remoto `MartinDele703` (la nota vieja del handoff sobre el 403 no aplica: push directo funcionó).
2. **B — ROLLOUT: PENDIENTE.** `upgrade-bootstrap` a los 4 repos bootstrapeados + revertir la
   mitigación interina. Fuente de verdad de los repos = memoria `forecasting-app-mitigacion-interina-review`
   (4 repos: **Forecasting App**, **Outsourcing Development** —git en `hssapp/`, Claude corre en la
   raíz, usar `-C hssapp`—, **claude-analytics** (Claude Analytics), **Survey Clients**). El handoff
   parte 2 decía "Call Center" en vez de Claude Analytics — **discrepancia a resolver, no adivinar**.
   Revertir en cada uno: borrar `.scratch/review-loop-interino.md` + quitar el bullet ⚠️ INTERINO del
   `CLAUDE.md` (sin commitear en los 4), **solo después** de confirmar que el review-loop nuevo quedó
   instalado ahí.
3. **Grill del issue 08 CERRADO** (skill `grill-with-docs`). Decisiones firmadas en
   `.scratch/review-cost-redesign/issues/08-framing-premisa-code-review-caducada.md` (secciones
   "Decisiones del grill" + "Slices" + AC + Notas). Criterio elegido por el usuario: **calidad a largo
   plazo, ignorando costo de desarrollo, con gate duro: el review-loop NO debe tardar más.** Decisiones:
   - **(c) ENSEMBLE, no (a)**: el motor del `review-loop` = `/slice-review` de columna vertebral **+
     `/code-review` como reviewer independiente sumado** (mejora gratis vía Anthropic; diversidad de
     reviewers = más calidad; slice-review sigue siendo columna porque es lo único que hace cumplir las
     Hard rules del `CLAUDE.md` + focos + confianza + coherencia). **La premisa "/code-review es
     human-only" CADUCÓ** (verificado: es invocable por el agente).
   - **code-review corre SOLO en el turno 1**, foco par en la ola paralela, **en el slack detrás del
     foco de mutación** (la lane más lenta) → **latency-neutral por construcción**. Esfuerzo **medium**.
     NO en turnos 2+.
   - Sus hallazgos pasan por el **pase de confianza (Step 5) existente**. **Hace falta un DEDUP nuevo**
     (hoy NO existe — verificado en slice-review.md Steps 5-6) contra el foco de bugs, dentro de la ola
     del pase de confianza.
   - **El guard anti-`/code-review` de `tests/slice-review.tests.ps1` se INVIERTE** (de "prohibido
     ordenar code-review" a "invocado a propósito, acotado turno-1/medium"), test-first.
   - **DOS slices apilados: 08a (mecánica, código+tests) primero, 08b (framing en 6 archivos) después**
     (08b redacta la realidad nueva; depende de 08a). **ADR-0003 nuevo** (`docs/adr/0003-code-review-como-foco-acotado.md`)
     dentro de 08a; 08b corrige además la nota fáctica falsa dentro de ADR-0001.
   - **Feasibility a verificar test-first antes de sellar 08a**: que `/code-review` sea invocable desde
     el contexto donde corre `/slice-review`; si no, fallback a que `/review-loop` lo orqueste en paralelo.
4. **Review-loop disparado por el push → CERRADO LIMPIO (1 turno).** Delta revisado = `0379d82..HEAD`
   (lógica real = 6 líneas del guard de AC8 en `tests/slice-review.tests.ps1`; el resto, 4 manifests
   generados + handoff, no cuenta). 6 focos + confianza + coherencia. **Cero Medium/High.** Confianza:
   A (sin fixture positivo, preexistente) **18→descartado**, C (verbos no exhaustivos, limitación
   inherente) **20→descartado**, B (imperativo negado `Do not run \`/code-review\`` matchea) **87→sobrevive
   pero Low**. Coherencia **COHERE** + un 2º gap latente (`\s+` cruza newlines). **Cero fixes**: los 2
   Low son latentes (suite verde, corpus no los dispara) sobre un guard que **08a reescribe** → **ambos
   deferidos a 08a**, registrados en el issue 08 (sección Notas). Marcador: `open`→`advance`→`close`
   limpio; `range` post-close **vacío + exit 0**.

### Roadmap restante (en orden)

- **(1) ROLLOUT de B** (arriba) — necesita permiso amplio o sesión dedicada por el bloqueo del clasificador.
- **(2) 08a** — mecánica del ensemble (feasibility test-first → foco code-review turno-1/medium +
  dedup + flip del guard + ADR-0003 + tests). `/to-issues` para formalizar 08a/08b, luego `/tdd` sobre 08a.
- **(3) 08b** — corrección de framing en los 6 archivos, apilado sobre 08a.
- Lows viejos de fondo: gap de prosa Step 2 de `slice-review.md`; `core.autocrlf` con date-bump en
  manifests (ensucia el tree en cada sync); `copy-scaffold.ps1` pisa el `.gitignore` del destino.

### Antes de tocar código (crítico)

- **El clasificador de auto-mode frena acciones hacia afuera** (Agent autónomo con git/push, `git push`
  sin permiso, y muy probablemente el rollout que edita otros repos). Los subagentes de SOLO LECTURA sí
  corren. Pedir permiso/hacerlo en sesión dedicada, no reintentar a ciegas.
- **08a necesita paso 1 (grill) YA HECHO** — las decisiones están firmadas en el issue 08. Si el
  `alignment-gate` frena el primer edit de código, decilo y reintentá, **no re-grilles**. La feasibility
  de invocabilidad de `/code-review` se verifica test-first DENTRO de 08a antes de sellar la mecánica.
- **Regla del espejo**: canónicos en raíz (`.claude/commands/*.md`, `.agents/skills/*/SKILL.md`), `cp`
  a los 3 scaffolds, regenerar los 3 manifests (`tools/gen-manifest.ps1 -SkillDir skills/<s>`). **`tests/`
  y `docs/` NO se espejan.** Manifests **generados**. Identidad por hash normalizado, no `diff` crudo.
- **Bash tool = Git Bash**: commits `-m "..."` repetidos, nunca here-strings `@'...'@`. Tests Pester v3
  con harness propio: FOREGROUND con redirect + grep `^FAIL:`/"TODOS LOS TESTS PASARON". Los background
  se matan (salvo el que corrí con run_in_background esta sesión, que sí completó).

### Preferencias del usuario (vigentes)

- **No commitear sin que lo pida** (esta sesión pidió: commit final de todo). **Nada a Zoho.** **Impacto
  medido antes de cambiar el proceso.** **Decidir lo técnico, preguntar lo de diseño.** **Prefiere Opus
  4.8 sobre Opus 5.** **Paraleliza todo lo posible.** Prefiere **cortar y seguir en terminal nueva**.

---

# Session Handoff — 2026-08-25 parte 2 (ITEM 2 + A7 DEPLOY + AC8 CERRADOS — hallazgo mayor: la premisa /code-review-human-only CADUCÓ → issue 08; próximo: merge/push/rollout o grill de A8)

## ▶▶▶▶▶▶▶▶▶▶▶▶ ESTADO AL RETOMAR — próximo: (B) merge→main + push + rollout, o (A) grill de diseño del issue 08

Rama **`feat/marcador-de-revision`**, HEAD **`2f94108`**. **Árbol limpio salvo este handoff.** Track A
**COMPLETO** (A1–A7). El deploy a `~/.claude/skills` **corrió y se verificó**. **Sin pushear.** **Sin
mergear a main.** No hay decisión pendiente salvo elegir el próximo frente.

```
2f94108  fix(review-loop): endurecer el guard anti-/code-review (hallazgo AC8)   <- sin trailer
16cc286  chore(review-loop): A7 — sellar y deployar Track A + doc de migración    <- sin trailer
5fe2df4  feat(review-loop): ruteo de modelos agnostico en slice-review/review-loop
```

### Qué hizo esta sesión

1. **Item 2 (TESTING.md stale) — CERRADO limpio.** Fixeó `docs/TESTING.md:71,72,85` (esquema viejo
   "Sonnet 5"/"Opus 5" → frases agnósticas) + agregó sección `## Testeo de la migración a ruteo de
   modelos agnóstico`. Review-loop: **turno 1 limpio** (6 focos, 0 hallazgos; contratos verificó las
   7 afirmaciones del doc contra los tests) + **coherencia COHERE** + `close`. `docs/` no se espeja.
2. **A7 (sellar y deployar) — HECHO + verificado** (con el usuario presente). Resello manifest raíz
   (`reseal-manifest.ps1`, 51 archivos, `2026-08-25+a5bde47`); `sync-skills.ps1` regeneró los 3
   manifests de scaffold (solo bump de fecha, hashes idénticos) y deployó las 5 skills que el repo
   posee a `~/.claude/skills`. **Verificado**: instalado con 0 pins viejos, frases agnósticas, verbo
   `close`, fecha de hoy. Suite **13/13 verde**. Commit `16cc286` (sin trailer). AC de A7 todos ✓.
3. **AC8 (el commit base `8cc6e9e`, 1/8, nunca revisado) — revisado retroactivamente** (5 focos,
   cada hallazgo marcado SURVIVES/SUPERSEDED en HEAD). Cero medium/high sobreviven. Un Low fixeado:
   la regex anti-`/code-review` de `tests/slice-review.tests.ps1:44` se endureció (caza run/invoke/
   execute/call/launch/use adyacente, RED-first, sin falso positivo) — commit `2f94108`.
4. **🔴 HALLAZGO MAYOR — la premisa CADUCÓ.** La justificación de todo `/slice-review` ("el built-in
   `/code-review` es human-only / `disable-model-invocation`, el agente no puede lanzarlo") es
   **FALSA hoy**: invocar `/code-review` con la Skill tool **lo lanzó y corrió una review completa**
   (2 evidencias: se lanzó + terminó con hallazgos). La memoria `slice-review-motor-del-loop.md` ya
   pedía verificarlo antes de cerrar Track A — ahora verificado, actualizada. La framing falsa vive
   en 6 archivos (`review-loop.md`/SKILL ×4, `README.md`, `public/README.md`, `docs/TESTING.md`,
   `AI_DEVELOPMENT_WORKFLOW.md`, `docs/adr/0001`). **Re-anotado como issue 08** (`needs-info`):
   corrección de framing, ENTRELAZADA con una decisión de diseño a grillar — ¿el review-loop debería
   usar `/code-review` ahora que es invocable, o quedarse con `/slice-review` (cuyo valor —focos
   paralelos + confianza + sin PR— no depende de la premisa)? El usuario eligió: **follow-up con
   grill primero**, no reescribir hoy.

### Roadmap restante

- **A (issue 08)** — corrección de framing de la premisa caduca. **Necesita grill de diseño** primero
   (`/code-review` vs `/slice-review` vs ambos). Doc que toca 4 espejos + manifests + su review-loop.
- **B — pasos manuales fuera de alcance de A7 (PRD)**: **merge** `feat/marcador-de-revision` → `main`;
   **push** (solo cuenta el remoto `southpointtech`; `MartinDele703` da 403); **rollout** con
   `upgrade-bootstrap` a los bootstrapeados (hssapp/Outsourcing, Forecasting App, Survey Clients,
   Call Center) + **revertir la mitigación interina** en Forecasting App y Outsourcing (memoria
   `forecasting-app-mitigacion-interina-review`).
- Low no accionado (AC8): gap de prosa Step 2 de `slice-review.md` (`--stat` no aplica al fallback
   `git show HEAD`); un agente lo adapta. Pendientes de fondo viejos: `core.autocrlf` con date-bump
   en manifests (cada sync ensucia el tree); `copy-scaffold.ps1` pisa `.gitignore` del destino.

### Antes de tocar código (crítico)

- **El deploy YA cambió tu tooling vivo**: proyectos bootstrapeados de ahora en más traen el
   review-loop incremental + ruteo agnóstico; los ya bootstrapeados NO cambian hasta el rollout (B).
- **Issue 08 necesita grill** (decisión de diseño abierta): si el `alignment-gate` frena el primer
   edit, **ofrecé/hacé el grill**, no reintentes a ciegas (a diferencia de los slices ya alineados).
- **Regla del espejo**: canónicos en raíz (`.claude/commands/*.md`, `.agents/skills/*/SKILL.md`),
   `cp` a los 3 scaffolds, regenerar los 3 manifests (`tools/gen-manifest.ps1 -SkillDir skills/<s>`).
   **`tests/` y `docs/` NO se espejan.** Manifests **generados**. Identidad de copias por hash
   normalizado (`mirror`/`review-loop-incremental`), no `diff` crudo (CRLF root vs LF).
- **Bash tool = Git Bash**: commits `-m "..."` repetidos, nunca here-strings `@'...'@`. Tests Pester
   v3 con harness propio: FOREGROUND con redirect + grep `^FAIL:`/"TODOS LOS TESTS PASARON". Los
   background se matan. `review-marker`/`review-loop-trigger` tardan >2 min.

### Preferencias del usuario (vigentes)

- **No commitear sin que lo pida** (esta sesión pidió A7 + el fix de regex). **Nada a Zoho.**
   **Impacto medido antes de cambiar el proceso.** **Decidir lo técnico, preguntar lo de diseño.**
   **Prefiere Opus 4.8 sobre Opus 5.** **Paraleliza todo lo posible.** Prefiere **cortar y seguir en
   terminal nueva**.

---

# Session Handoff — 2026-08-25 (MIGRACIÓN A AGNÓSTICO: review-loop CERRADO LIMPIO + coherencia COHERE + COMMITEADA — próximo: TESTING.md stale (Low) o A7 (deploy, con humano))

## ▶▶▶▶▶▶▶▶▶▶▶▶ ESTADO AL RETOMAR — próximo: item 2 (TESTING.md stale, Low) o item 3 (A7 deploy, con humano)

Rama **`feat/marcador-de-revision`**, HEAD **`5fe2df4`** (`feat(review-loop): ruteo de modelos
agnostico en slice-review/review-loop`, **sin trailer**). **Árbol limpio salvo este handoff.** El
review-loop de la migración **cerró LIMPIO** (2 turnos + coherencia COHERE) y **se commiteó**.
Marcador: **`-Action range` sale VACÍO + exit 0** = nada sin revisar. **Sin pushear.** **No hay
decisión pendiente del usuario** salvo arrancar el próximo item.

```
5fe2df4  feat(review-loop): ruteo de modelos agnostico en slice-review/review-loop   <- migracion (SIN trailer)
4045903  fix(review-loop): correcciones del review-loop sobre A4c
e38115f  feat(review-loop): A4c — limpiar el ancla slice-open al cierre limpio        <- Slice-Close: A4c
```

### Qué hizo esta sesión

1. **Continuó y cerró el review-loop de la migración a modelo-agnóstico** (venía a mitad del turno 1,
   con los 6 reviewers SIN despachar). Marcador: `open` (write-once, ya estaba) → 6 focos turno 1 →
   `advance` → fix → `advance` → turno 2 → coherencia → `close`.
   - **Turno 1** (6 focos, incl. mutación; opus para bugs/contratos/tests/mutación, sonnet para
     reglas/historia): **1 Medium** (foco tests). `review-loop.md`/SKILL solo tenían guard anti-pin
     acotado a la sección `## At close` (`review-loop-incremental.tests.ps1:165`, vía `$closeSec`); el
     cuerpo (líneas 1-181) quedaba sin cubrir → un pin reintroducido ahí, consistente en las 4 copias,
     pasaba mirror + todos los guards. **Fixeado**: guard file-wide nuevo en el loop `loopPairs` de
     `tests/slice-review.tests.ps1:409-415`, simétrico al de `slice-review.md`. **RED-verificado** (pin
     inyectado en "The reviewer", fuera de At close → falla el guard nuevo; el viejo `$closeSec` no lo
     cazaba). Bugs/contratos/reglas/historia/mutación: limpios (la mutación mutó prosa a pins en
     worktree aislado y confirmó dientes en ambos guards).
   - **⚠️ Incidente recuperado**: durante la verificación RED, un `git checkout -- .claude/commands/review-loop.md`
     revirtió por error el cambio de migración del **canónico** `review-loop.md` (la línea de coherencia
     volvió a "on Sonnet 5"). Se **detectó y restauró** (mirror byte-idéntico lo confirma). LECCIÓN:
     no usar `git checkout` para revertir mutaciones RED sobre archivos con cambios sin commitear; usar
     Edit reversible.
   - **Turno 2** (delta = las 7 líneas del guard nuevo): **limpio** (scope `$txt` file-wide correcto,
     regex con dientes, `.claude/scripts` bien rechazado por el `\d`, comentarios verificados).
   - **Coherencia** (sonnet, slice entero desde slice-base `083268e`): **COHERE** — migración completa
     en las 4 canónicas, dos tiers bien mapeados sin invertir, el párrafo reescrito de coherencia
     (`slice-review.md` ~L314-323) resuelve una inconsistencia latente previa ("Sonnet 5 rather than
     the lighter audits' model" era auto-contradictorio) en vez de introducir una.
   - **Cierre**: `-Action close` borró el ancla `slice-open` (cierre limpio, tras la coherencia).
     `slice-base` ahora cae al branch base `43166da`.
2. **Commiteó la migración** (`5fe2df4`, sin trailer — el loop ya corrió sobre el árbol; con trailer
   re-dispararía el hook y `range` saldría del delta post-close = vacío). 21 archivos = 4 canónicos
   .md + 6 scaffolds .md + 3 manifests + 2 tests.
3. **Suites finales verdes**: `slice-review`, `review-loop-incremental`, `mirror` (3/3).

### Roadmap restante — 2 items (el usuario los dejó para esta terminal nueva)

- **Item 2 — `docs/TESTING.md` stale (Low)**: `docs/TESTING.md:71-72,85` todavía documenta el esquema
  viejo ("Sonnet 5"/"Opus 5") por foco; tras la migración describe un ruteo que ya no coincide con
  `slice-review.md`/SKILL. Follow-up chico (fuera de los archivos del slice, por eso no se tocó).
  Además `TESTING.md` no tiene sección para esta migración (ni para A3–A6). Es su propio micro-slice.
- **Item 3 — A7** (`07-sellar-y-deployar.md`, `ready-for-human`): deploy a `~/.claude/skills` +
  resellar el `.bootstrap-manifest.json` de la **RAÍZ**. **Requiere presencia humana.** Va al final.

### Antes de tocar código (crítico)

- **Migración CERRADA y COMMITEADA.** El paso 1 (grill) NO aplica al item 2 (es doc trivial). Si el
  `alignment-gate` frena el primer edit de código: decilo y reintentá, **no grilles** (speed-bump de
  una vez; en esta sesión frenó el edit de tests y se reintentó).
- **Regla del espejo**: canónicos en raíz (`.claude/commands/*.md`, `.agents/skills/*/SKILL.md` —
  comparten CUERPO, difieren en frontmatter), `cp` a los 3 scaffolds, regenerar los 3 manifests
  (`pwsh -NoProfile -File tools/gen-manifest.ps1 -SkillDir skills/<skill>`). **`tests/` y `docs/` NO
  se espejan** (item 2 es solo `docs/TESTING.md`, sin manifests). Los manifests son **generados**.
- **`diff` crudo miente por line endings** (CRLF root vs LF): la identidad de las 4 copias la validan
  `mirror.tests.ps1` + `review-loop-incremental.tests.ps1` con hash **normalizado**, NO `diff`.
- **Bash tool = Git Bash**: commits con `-m "..."` repetidos, nunca here-strings `@'...'@`. Tests =
  Pester v3 con harness propio: FOREGROUND con redirect (`> out.txt 2>&1`, el background se mata acá)
  y grepear `^FAIL:` / "TODOS LOS TESTS PASARON". `review-marker` tarda >2 min.

### Preferencias del usuario (vigentes)

- **No commitear sin que lo pida** (esta sesión pidió commit explícito de la migración). **Nada a
  Zoho.** **Impacto medido antes de cambiar el proceso.** **Decidir lo técnico, preguntar lo de
  diseño.** **Prefiere Opus 4.8 sobre Opus 5.** **Paraleliza todo lo posible.** Prefiere **cortar y
  seguir en terminal nueva** — por eso este handoff.

---

# Session Handoff — 2026-08-24 parte 2 (MIGRACIÓN A AGNÓSTICO implementada test-first + VERDE — review-loop a MEDIO ARRANCAR: turno 1 con reviewers SIN despachar)

## ▶▶▶▶▶▶▶▶▶▶▶▶ ESTADO AL RETOMAR — próximo: DESPACHAR los 6 reviewers del turno 1 del review-loop

Rama **`feat/marcador-de-revision`**, HEAD sigue **`4045903`** (NADA commiteado esta sesión). **Árbol
sucio: 22 archivos** = 21 de la migración (16 docs + 3 manifests + 2 tests) + este handoff. **Suites
verdes**: `slice-review`, `mirror`, `review-loop-incremental` (3/3). **Sin decisión pendiente del
usuario** salvo continuar el loop.

**Marcador**: `-Action range` = **`083268e8db51e011ca4e076890965ad56dc745a7`** (exit 0). **`-Action
open` YA corrió** este turno (snapshoteó `083268e` como `slice-open`; es **write-once**, re-correrlo
al retomar es no-op seguro). El marcador **NO se avanzó todavía** (el `advance` va DESPUÉS del review).

### Lo PRIMERO que hay que hacer (continuar el turno 1 del review-loop)

El loop quedó **a mitad del turno 1**: rango tomado + `open` hecho + diff capturado, pero **los
reviewers NO se despacharon**. Continuar:

1. **Re-tomar el rango** (`-Action range`) por si `083268e` fue podado (caería a slice-base; usar lo
   que devuelva). Re-capturar el diff (el `$TEMP/slice.diff` de la sesión anterior NO sobrevive):
   `git --no-pager diff <range> -- ':!*/assets/scaffold/*' ':!docs/SESSION_HANDOFF.md'`. **Sin
   untracked.** Los scaffolds se excluyen del review a propósito: son **espejo byte-idéntico**
   (verificado por md5 + `mirror.tests.ps1`); los manifests son **generados**. El diff canónico+tests
   son ~239 líneas, muy por debajo de 400.
2. **Despachar 6 focos en paralelo** (turno 1 lleva `--mutation`), solo lectura, un mensaje:
   bugs/contratos/tests/confianza/**mutación** en **`opus`** (4.8), reglas/historia/**coherencia** en
   **`sonnet`** — dogfoodeando el ruteo agnóstico recién migrado (el prompt dice "most capable"/"lighter",
   el despacho real usa los modelos disponibles). **Mutación probablemente short-circuitea**: slice de
   prosa (.md) + asserts (.ps1), sin lógica ejecutable propia que mutar (no toca `review-marker.ps1`).
3. **`-Action advance`** SOLO si un reviewer corrió y devolvió reporte, **DESPUÉS del review y ANTES
   de los fixes**. Fixear solo hallazgos reales (RED-first). Loop hasta cerrar limpio o cap 5.
4. **Al cierre**: `/slice-review --coherence` (modelo liviano = `sonnet`, solo lectura) UNA vez;
   en cierre **limpio** `-Action close`.

### Qué hizo esta sesión (migración a modelo-agnóstico, test-first, SIN commit)

**Intención del slice**: migrar el ruteo de modelos por foco de nombres pinneados (Opus 5 / Sonnet 5)
a **tiers agnósticos sin versión**, preservando los DOS niveles. Frases elegidas: tier fuerte =
**"the most capable model available"** (idéntica a la del foco de mutación, L215, que ya era
agnóstica y fue el patrón); tier liviano = **"a lighter, faster model"**.

1. **`slice-review.md` + SKILL (canónicos)** — 9 de-pins: párrafo "Models by focus" (reglas/historia
   → liviano; bugs/contratos/tests → capaz + cláusula "do not pin a version"); los 5 tags inline de
   los focos (`*(most capable model)*` / `*(lighter model)*`); confianza ("runs on the most capable
   model available"); coherencia L311 ("on a lighter, faster model"). **L316-317 reword semántico**
   (no swap): un swap literal daba "lighter rather than lighter"; ahora contrasta el tier liviano de
   coherencia contra "the most capable one the logic reviewers use".
2. **`review-loop.md` + SKILL (canónicos)** — **scope extendido** (no estaba en el plan original): la
   descripción del pase de coherencia en la sección "At close" (L191) también pinneaba "on Sonnet 5"
   → de-pinneada a "on a lighter, faster model". Es la MISMA feature; dejarla rompía el agnóstico
   end-to-end (y la coherencia del propio slice). Un pin, cohesivo.
3. **Espejo**: `cp` a los 3 scaffolds (16 docs con 1 md5 por artefacto), 3 manifests regenerados.
4. **Tests (test-first, RED verificado antes)**:
   - `slice-review.tests.ps1`: migró los 4 asserts de nombres pinneados a las frases agnósticas +
     **guard anti-pin file-wide** nuevo (`-not ($txt -match '(?i)(opus|sonnet|haiku|claude|gpt)[- ]?\d')`)
     — un pin reintroducido en CUALQUIER sección lo caza ("CLAUDE.md" y "0-100" no matchean).
   - `review-loop-incremental.tests.ps1`: 2 asserts nuevos en el bloque `$closeSec` (no pinnea +
     usa "a lighter, faster model").
5. **Verificación**: barrido `grep` repo-wide confirmó **0 pins** en artefactos shippeados
   (`.claude`, `.agents`, scaffolds; excluyendo `CLAUDE.md`/`claude-code`/manifests). 3 suites verdes.

### Archivos modificados (22, sin commitear)

`slice-review.md`+SKILL ×4 · `review-loop.md`+SKILL ×4 (=16 docs) · 3 manifests ·
`tests/slice-review.tests.ps1` · `tests/review-loop-incremental.tests.ps1` · este handoff.

### Antes de tocar código (crítico)

- **Paso 1 (grill) NO aplica**: la decisión (agnóstico, dos tiers, sin pin) ya estaba tomada. El
  `alignment-gate` frenará el primer edit de código en la sesión nueva (es una sesión fresca): **decilo
  y reintentá, NO grilles** (pasó esta sesión, es speed-bump de una vez).
- **⚠️ Line-wrap** (costó 2 rondas esta sesión): los asserts son `-match` sin singleline. Cualquier
  frase asertada ("the most capable model available", "a lighter, faster model") **partida en 2 líneas**
  por el reflow a ~100 col FALLA. Al editar, mantener la frase asertada contigua en una sola línea.
- **Regla del espejo**: canónicos en raíz (`.claude/commands/*.md`, `.agents/skills/*/SKILL.md` —
  comparten CUERPO, difieren en frontmatter), `cp` a los 3 scaffolds, regenerar los 3 manifests
  (`pwsh -NoProfile -File tools/gen-manifest.ps1 -SkillDir skills/<skill>`). 1 md5 por artefacto entre
  las 4 copias. Los manifests son **generados**.
- **Bash tool = Git Bash**: commits con `-m "..."` repetidos, nunca here-strings `@'...'@`. Tests =
  **Pester v3** con harness propio: correr en FOREGROUND con redirect (`> out.txt 2>&1`, el background
  se mata acá) y grepear `^FAIL:` / "TODOS LOS TESTS PASARON". (`review-marker` tarda >2 min; las otras
  ~30-90s.)
- **Reviewers en SOLO LECTURA** en subagentes paralelos; `git status` antes de creerle a un hallazgo.
  Marcador: `open` (write-once) ya corrió; `advance` DESPUÉS del review y ANTES de los fixes; la
  coherencia NO avanza; `close` solo en cierre limpio tras la coherencia.
- **Commit (cuando el usuario lo pida)**: el loop corre sobre el árbol SIN commitear, así que un commit
  al final NO necesita el trailer para "disparar" el loop (ya corrió). Con trailer `Slice-Close:` el
  hook re-dispararía y `range` saldría del delta post-advance. Decidir con el usuario; sugerido
  `feat(review-loop): ruteo de modelos agnóstico en slice-review/review-loop` — **preguntar** si con o
  sin trailer.

### Preferencias del usuario (vigentes)

- **No commitear sin que lo pida.** **Nada a Zoho.** **Impacto medido antes de cambiar el proceso.**
  **Decidir lo técnico, preguntar lo de diseño.** **Prefiere Opus 4.8 sobre Opus 5.** **Paraleliza
  todo lo posible.** Prefiere **cortar y seguir en terminal nueva** — por eso este handoff.

### Roadmap restante (después de cerrar esta migración)

- **A1b** (elección de base / 15 hallazgos + nudo de diseño), cuando se quiera.
- **A7** (`07-sellar-y-deployar.md`, `ready-for-human`): deploy a `~/.claude/skills` + resellar el
  `.bootstrap-manifest.json` de la RAÍZ. **Requiere presencia humana.** Al final.
- Pendientes de fondo (Low): `docs/TESTING.md` sin sección para esta migración; PRDs/issues en
  `.scratch/` gitignoreado; `copy-scaffold.ps1` pisa el `.gitignore` del destino; `core.autocrlf` con
  hashes mixtos en manifests. **Forecasting App**: al upgradear, llevar la regla de afirmaciones (A6).

---

# Session Handoff — 2026-08-24 (A4c CERRADO: implementado + review-loop limpio 2 turnos + coherencia + close dogfoodeado + COMMITEADO — próximo: migración a agnóstico o A7)

## ▶▶▶▶▶▶▶▶▶▶▶▶ ESTADO AL RETOMAR — próximo: SLICE de migración a modelo-agnóstico (elegido), o A7 (deploy, con humano)

Rama **`feat/marcador-de-revision`**, HEAD **`4045903`** (`fix(review-loop): correcciones del
review-loop sobre A4c`, sin trailer). **Árbol limpio salvo este handoff.** El marcador se avanzó a
HEAD al cerrar: **`-Action range` sale VACÍO + exit 0** = nada sin revisar. **Sin pushear.** **No hay
decisión pendiente del usuario** salvo arrancar el próximo slice.

```
4045903  fix(review-loop): correcciones del review-loop sobre A4c        <- fixes del loop (sin trailer)
e38115f  feat(review-loop): A4c — limpiar el ancla slice-open al cierre limpio   <- Slice-Close: A4c
6cccea9  fix(review-loop): correcciones del review-loop sobre A6
```

### Qué hizo esta sesión

1. **Grill de A4c CERRADO** (paso 1): decisiones firmadas en
   `.scratch/review-cost-redesign/issues/04c-limpieza-del-slice-open-al-cierre.md` (sección
   "Decisiones del grill", status `ready-for-agent`). Se descartó el candidato 2 (guard por
   ancestría: no distingue re-corrida de slice-nuevo). Elegido candidato 1: verbo `close` + `open`
   write-once + borrar solo en cierre limpio. **ADR-0002 nuevo** (`docs/adr/0002-limpieza-del-ancla-de-coherencia.md`).
2. **Implementó A4c test-first** (`e38115f`, `Slice-Close: A4c`): **7º verbo `-Action close`** en
   `review-marker.ps1` (borra `slice-open:<branch>`, idempotente, exit 0, sin cuarentena `.bad`
   porque un estado corrupto lo devuelve `Read-State` como `@{}` y sale antes de escribir); **`open`
   write-once**; `/review-loop` llama `close` **solo en cierre limpio, tras la coherencia, nunca en
   cap** (sección "At close" de `review-loop.md`/SKILL). Espejo ×4 + 3 manifests. `docs/TESTING.md`
   sección A4c + fix del conteo de verbos (4→7).
3. **Dogfoodeó A4c con el `/review-loop` y cerró LIMPIO** (`4045903`, sin trailer):
   - **Turno 1** (6 focos, incl. mutación): 5 hallazgos reales fixeados. **(A)** el write-once original
     no-opeaba solo si el ancla *resolvía* → un ancla stale/irresoluble se sobreescribía con el
     marcador ya avanzado = **under-scope**; fix: no-op sobre la **PRESENCIA** de la clave (RED→GREEN).
     **(B)** ADR-2 afirmaba cuarentena `.bad` en `close` (falsa, A6, triple-converge) → corregido.
     **(C)** header de verbos sin `close`/write-once → agregado. **(E)** `CONTEXT.md` glosario "cierre
     de slice" (limpio/cap) + línea de estado stale → actualizado. **(F)** test de `close` sobre estado
     corrupto → **mata al mutante M8** (verificado: RED al quitar el guard `ContainsKey`). Mutantes M3/M4
     descartados por equivalentes (salida muerta de `open`, loop fire-and-forget).
   - **Turno 2** (3 focos: bugs+contratos, afirmaciones/A6 sobre los docs, tests): **cero medium/high**.
     2 Low: dejé el assert `.bad` (guarda direccional de la decisión del ADR), saqué un assert
     tautológico.
   - **Coherencia** (Sonnet, sobre el slice A4c real desde `6cccea9` — `slice-base` daba `b4223d0`, el
     ancla legacy over-scopeada de A5/A6 que cerraron con el loop viejo sin `close`): **EL SLICE COHERE**,
     5 AC trazados. Único gap: 2 casos de test sin listar en `TESTING.md` → corregido.
   - **Cierre = dogfood en vivo**: `-Action close` **borró el ancla legacy `b4223d0`** → el próximo
     slice ancla fresco. El mecanismo de A4c se validó sobre sí mismo.
4. **Suites finales verdes**: `review-marker`, `review-loop-incremental`, `mirror`, `slice-review`,
   `regla-de-afirmaciones` (5/5).

### Roadmap restante — 2 items

- **Migración a modelo-agnóstico** (SLICE elegido esta sesión, NO empezado): `slice-review.md` Step 4
  todavía hardcodea "Opus 5"/"Sonnet 5" por foco (líneas ~134-165 + 311/317 de coherencia; la 215 de
  mutación YA es agnóstica y es el patrón a copiar). **Decisión del usuario 2026-08-24: ruteo
  AGNÓSTICO** ("most capable model available" para bugs/contratos/tests/confianza/mutación; "a
  lighter, faster model" para reglas/historia/coherencia — preservar los DOS niveles, sin pin de
  versión). Self-contained, bajo riesgo, **no necesita grill** (es técnico). Toca `slice-review.md` +
  SKILL ×4 + 3 manifests + quizás `tests/slice-review.tests.ps1` si asERTa nombres de modelo (chequear
  primero). **NO toca los archivos de A4c → sin conflicto de espejo.** El paso 1 (grill) NO aplica;
  si el `alignment-gate` frena el primer edit, decilo y reintentá.
- **A7** (`07-sellar-y-deployar.md`, `ready-for-human`): deploy a `~/.claude/skills` + resellar el
  `.bootstrap-manifest.json` de la **RAÍZ**. **Requiere presencia humana.** Va al final.

Pendientes de fondo (Low): PRDs/issues en `.scratch/` gitignoreado; `copy-scaffold.ps1` pisa el
`.gitignore` del destino; `core.autocrlf` con hashes mixtos en manifests. **Forecasting App**: al
upgradear ese repo, llevar la regla de afirmaciones (A6) y evaluar el resto del scaffold nuevo.

### Antes de tocar código (crítico)

- **A4c CERRADO.** El próximo slice (migración) tiene el paso 1 (grill) **NO aplicable** (es técnico,
  decisión ya tomada): si el `alignment-gate` frena el primer edit, decilo y reintentá, **no grilles**.
- **Regla del espejo de slice-review**: canónico en **raíz** (`.claude/commands/slice-review.md`,
  `.agents/skills/slice-review/SKILL.md` — comparten CUERPO, difieren en frontmatter), `cp` a los 3
  scaffolds, regenerar los 3 manifests (`pwsh -NoProfile -File tools/gen-manifest.ps1 -SkillDir
  skills/<skill>`). 1 md5 por artefacto entre las 4 copias. Los manifests son **generados**.
- **Bash tool = Git Bash**, NO PowerShell: mensajes de commit con `-m "..."` repetidos, nunca
  here-strings `@'...'@`. Tests son **Pester v3** con harness propio `ok:`/`FAIL:`: correr
  `pwsh -NoProfile -File tests/<t>.tests.ps1` en FOREGROUND con redirect (`> out.txt 2>&1`, el
  background se mata acá) y grepear `^FAIL:` / "TODOS LOS TESTS PASARON". **La suite `review-marker`
  tarda >2 min** — usar timeout 420000.
- **Reviewers en SOLO LECTURA** en subagentes paralelos; `git status` antes de creerle a un hallazgo.
  El marcador **avanza DESPUÉS de cada review y ANTES de los fixes**; `-Action open` (turno 1) y la
  coherencia NO avanzan; `-Action close` corre solo en cierre limpio tras la coherencia.
- **Modelo por foco (para el review-loop de la migración)**: como la migración cambia justamente ese
  ruteo en el prompt, para *dogfoodear* usá los modelos disponibles vía Agent tool (`opus`=4.8 para
  bugs/contratos/tests/mutación/confianza, `sonnet` para reglas/historia/coherencia) — el prompt
  agnóstico y el despacho real conviven.

### Preferencias del usuario (vigentes)

- **No commitear sin que lo pida** (esta sesión pidió commit explícito de A4c y de los fixes del loop).
  **Nada a Zoho.** **Impacto medido antes de cambiar el proceso.** **Decidir lo técnico, preguntar lo
  de diseño** (modelo/costo/scope). **Prefiere Opus 4.8 sobre Opus 5.** **Paraleliza todo lo posible.**
  Prefiere **cortar y seguir en terminal nueva** — por eso este handoff.

---

# Session Handoff — 2026-08-23 (A5 fixes COMMITEADOS + A6 IMPLEMENTADO y review-loop CERRADO LIMPIO + COHERE — próximo: A4c o A7)

## ▶▶▶▶▶▶▶▶▶▶▶▶ ESTADO AL RETOMAR — próximo paso: elegir A4c (grill) o A7 (deploy, con humano)

Rama **`feat/marcador-de-revision`**, HEAD **`6cccea9`** (`fix(review-loop): correcciones del
review-loop sobre A6`, sin trailer). **Árbol limpio salvo este handoff.** Marcador: **`-Action range`
sale VACÍO + exit 0** = nada sin revisar (el loop de A6 cerró). slice-base = `b4223d0`. **Sin
pushear.** **No hay decisión pendiente del usuario** salvo elegir el próximo slice.

```
6cccea9  fix(review-loop): correcciones del review-loop sobre A6   <- fix del loop (sin trailer)
12242bc  feat(review-loop): A6 — regla de afirmaciones             <- Slice-Close: A6
dfb2dc6  fix(review-loop): correcciones del review-loop sobre A5   <- fixes de A5 (sin trailer)
89360a0  feat(review-loop): A5 — foco de mutacion acotada          <- Slice-Close: A5
```

### Qué hizo esta sesión

1. **Commiteó los 12 fixes del review-loop de A5** (`dfb2dc6`, sin trailer) tras verificar
   `slice-review`+`review-loop-incremental`+`mirror` en verde. (Ojo: el primer intento salió con `@`
   de subject por usar sintaxis PowerShell `@'...'@` en la **Bash tool** (Git Bash) — corregido con
   `--amend`. En la Bash tool usar `-m "..."` múltiples, no here-strings de PowerShell.)
2. **Implementó A6 test-first** (`12242bc`, `Slice-Close: A6`): la **regla de afirmaciones**. Dos
   puntos, cero agentes dedicados: (a) una regla dura en las Hard rules de las **4 CLAUDE.md** (repo
   + 3 scaffolds; edición separada, divergen por allowlist del mirror) — *"Write a verifiable claim
   only after verifying it. An assertion … is written only if it was verified; if you did not verify
   it, do not write it."*; (b) una línea en el **reviewer de contratos** (foco 4 de Step 4 de
   slice-review) — *"Also flag unverified assertions — a comment, docstring, or commit message that
   states as fact something the diff does not support"* — espejada byte-idéntica en las 4 copias.
   Test nuevo `tests/regla-de-afirmaciones.tests.ps1` (RED 16→GREEN). 3 manifests regenerados.
3. **Dogfoodeó A6 con el `/review-loop` y cerró LIMPIO**:
   - **Turno 1** (6 focos, incl. mutación): **1 Medium** (foco tests) — el comentario del test
     afirmaba que `mirror.tests.ps1` verifica la byte-identidad de las 4 copias de slice-review, pero
     mirror **solo compara los 3 scaffolds** (no la copia del repo). Afirmación no verificada en un
     comentario, justo lo que A6 ataca. **Fixeado** (`6cccea9`): la byte-identidad de las 4 copias la
     verifica **`review-loop-incremental.tests.ps1:211-226`** (verificado). El "gap de cobertura" que
     el reviewer infería se **descartó por confianza (<60)**: no existe, review-loop-incremental la
     cubre. Bugs/reglas/historia/contratos: sin hallazgos. **Mutación short-circuiteó** (slice de
     prosa + presence-test, sin lógica ejecutable que mutar; sin worktree).
   - **Turno 2** (delta = el fix del comentario): **limpio** (un reviewer verificó las 3 afirmaciones
     del comentario nuevo contra el código real, todas verdaderas).
   - **Pase de coherencia** (Sonnet, slice completo desde slice-base `b4223d0`): **EL SLICE COHERE**
     — los 7 AC trazados y cumplidos.
   - Suites finales verdes: `regla-de-afirmaciones`, `slice-review`, `mirror`, `review-loop-incremental`.
4. **Follow-up de Forecasting App anotado, no aplicado** (AC7): en el issue de A6 + ya lo cubre la
   regla existente del CLAUDE.md del repo ("Si cambiás el CLAUDE.md template, evaluá si aplica al
   CLAUDE.md real de Forecasting App"). Agregar la regla de afirmaciones allá al upgradear ese repo.

### Roadmap restante — elegir próximo slice

- **A4c** (`04c-limpieza-del-slice-open-al-cierre.md`, status `needs-info`): el verbo `close`/`clear`
  del marcador (follow-up del hallazgo B de A4b). **Necesita GRILL primero** (el mecanismo/semántica
  del verbo NO está decidido) → el `alignment-gate` acá SÍ debe correr el grill (a diferencia de
  A1–A6, cerrados). Es un caso off-workflow de segundo orden.
- **A7** (`07-sellar-y-deployar.md`): deploy a `~/.claude/skills` + resellar el `.bootstrap-manifest.json`
  de la **RAÍZ** del repo. **Requiere presencia humana.** Va al final del track.
- **A1b** cuando se quiera (15 hallazgos + nudo de diseño). **Track B** (B1/B2) lo lleva el usuario en
  otra terminal, vence **10/9**.
- Pendientes de fondo: `docs/TESTING.md` sin actualizar desde A2b (A3–A6 agregaron tests sin sección
  "Testeo de…"; Low, no urgente); la migración del esquema modelo-por-foco viejo ("Opus 5"/"Sonnet 5"
  en slice-review Step 4) a agnóstico es SU PROPIO slice; PRDs/issues en `.scratch/` gitignoreado;
  `copy-scaffold.ps1` pisa el `.gitignore` del destino; `core.autocrlf` con hashes mixtos en manifests.

### Antes de tocar código (crítico)

- **A6 CERRADO** (implementado + loop + coherencia). Para **A4c el grill NO está cerrado**: si el
  `alignment-gate` frena el primer edit, **ofrecé/hacé el grill** (no reintentes a ciegas). Para A7,
  el paso 1 es operativo (deploy), no diseño.
- **Regla del espejo de slice-review**: canónico en **raíz** (`.claude/commands/slice-review.md`,
  `.agents/skills/slice-review/SKILL.md` — comparten CUERPO, difieren en frontmatter), `cp` a los 3
  scaffolds, regenerar los 3 manifests (`pwsh -NoProfile -File tools/gen-manifest.ps1 -SkillDir
  skills/<skill>`). 1 md5 por artefacto entre las 4 copias (command y SKILL dan hashes DISTINTOS
  entre sí, iguales dentro de cada tipo). Las **CLAUDE.md divergen** (allowlist del mirror): editar
  las 4 por separado. Los manifests son **generados**, no a mano.
- **Bash tool = Git Bash**, NO PowerShell: para mensajes de commit usar `-m "..."` repetidos, nunca
  `@'...'@`. Pester acá es **v3**: los tests usan su propio harness `ok:`/`FAIL:`, correr con
  `pwsh -NoProfile -File tests/<t>.tests.ps1` y grepear `^FAIL:` / "TODOS LOS TESTS PASARON" (no
  `Invoke-Pester -Output`). Correr en FOREGROUND con redirect (el background se mata en este entorno).
- **Reviewers en SOLO LECTURA** en subagentes paralelos; `git status` antes de creerle a un hallazgo.
  Modelo por foco: bugs/contratos/tests Opus, reglas/historia/coherencia Sonnet; mutación "most
  capable available". El marcador **avanza DESPUÉS de cada review y ANTES de los fixes**; `-Action
  open` (turno 1) y la coherencia NO avanzan.

### Preferencias del usuario (vigentes)

- **No commitear sin que lo pida** (esta sesión pidió commit explícito de los fixes de A5, de A6 y
  del fix del loop de A6). **Nada a Zoho.** **Impacto medido antes de cambiar el proceso.** **Decidir
  lo técnico, preguntar lo de diseño** (modelo/costo/scope). **Prefiere Opus 4.8 sobre Opus 5.**
  Prefiere **cortar y seguir en terminal nueva** — por eso este handoff.

---

# Session Handoff — 2026-08-20 (A4b CERRADO + A5 IMPLEMENTADO y review-loop CERRADO LIMPIO — próximo: COMMIT de los fixes de A5 + A6/A4c)

## ▶▶▶▶▶▶▶▶▶▶▶▶ ESTADO AL RETOMAR — próximo paso: COMMITEAR los fixes del review-loop de A5 (sin trailer)

Rama **`feat/marcador-de-revision`**, HEAD **`89360a0`** (`feat(review-loop): A5 — foco de mutacion
acotada`, con trailer `Slice-Close: A5`). **Árbol sucio: 13 archivos** = 12 de los fixes del
review-loop de A5 (turnos 1-2) + este handoff. Marcador en **`b4223d0`**; **`-Action range` sale
VACÍO + exit 0** = nada sin revisar (el loop cerró). **slice-base = `b3e4eae`** = inicio de A5.

**El review-loop de A5 CERRÓ LIMPIO en el turno 3 + la coherencia COHERE.** No hay decisión pendiente
del usuario salvo pedir el commit. El usuario cortó acá para seguir en terminal nueva.

### Lo PRIMERO que hay que hacer

**Commitear los 12 fixes del loop de A5**, SIN trailer (para no re-disparar el hook). Sugerido:
`fix(review-loop): correcciones del review-loop sobre A5`. Los 12 archivos:
`.claude/commands/slice-review.md` + `.agents/skills/slice-review/SKILL.md` (canónicos) · 3 scaffolds
× (slice-review.md + SKILL.md + `.bootstrap-manifest.json`) = 9 · `tests/slice-review.tests.ps1`.
(`review-loop.md`/SKILL NO se tocaron en los fixes — ya fueron en `89360a0`.) El handoff va aparte.
**Verificá antes**: `slice-review` + `review-loop-incremental` + `mirror` en verde (lo estaban al
cerrar; corré en FOREGROUND con redirect, el background se mata en este entorno).

### Qué hizo esta sesión

1. **Cerró el review-loop de A4b** (venía a medio cerrar): turno 3 limpio + pase de coherencia
   COHERE. **Hallazgo B → slice propio A4c** (decisión del usuario): issue nuevo
   `.scratch/review-cost-redesign/issues/04c-limpieza-del-slice-open-al-cierre.md` (`needs-info`,
   necesita grill del verbo `close`/`clear`). Commiteó los fixes de A4b (`8a50124`, sin trailer).
2. **Grill de A5 CERRADO** (paso 1): 8 decisiones firmadas en
   `.scratch/review-cost-redesign/issues/05-mutacion-acotada.md` (sección "Decisiones del grill",
   status `ready-for-agent`). Reencuadres clave del grill (leer el issue): (a) el gate "solo turno 1"
   lo dueña `/review-loop` vía flag `--mutation`, no el foco; (b) el worktree se construye del
   **estado vivo** (`git stash create` + copiar untracked), NO del SHA del marcador (que no captura
   untracked y en turno 1 apunta al inicio del slice); (c) modelo **agnóstico** ("most capable model
   available"), no pin — Martín volvió a Opus 4.8; (d) mutación **on-by-default** en el turno 1 del
   loop (opción A), a MEDIR en la primera corrida real.
3. **Implementó A5 test-first** (`89360a0`, `Slice-Close: A5`): 6º foco `## Mutation focus` en
   `/slice-review` (worktree aislado, ≤8 mutantes uno-a-la-vez, test relevante del diff,
   sobreviviente=Medium, equivalentes descartados por confianza <60) + ruteo `--mutation` en Step 1 +
   despacho en Step 4; `/review-loop` pasa `--mutation` solo en turno 1. 269 líneas de lógica (bajo
   el techo). Espejo 4 copias + 3 manifests.
4. **Dogfoodeó A5 sobre sí mismo** con el `/review-loop` (la validación en vivo): **cerró LIMPIO en
   el turno 3**. Turno 1 (6 reviewers, incl. el foco de mutación nuevo): 7 hallazgos reales fixeados
   (ver abajo). Turno 2 (2 reviewers): 1 Medium fixeado (la excepción de escritura concedía ubicación
   pero no mecanismo → ahora dice "may use file-editing tools ... only inside `$tmp`"). Turno 3
   (contratos): LIMPIO. Pase de coherencia (Sonnet): **EL SLICE COHERE**.
   - **Medición del foco de mutación (dogfood)**: en un slice de PROSA (A5 es prompts) el foco
     short-circuitea correctamente ("sin lógica ejecutable que mutar", ~76s, no creó worktree). La
     medición real de tiempo del mutate-run-revert **sigue pendiente** de un slice con código real.

### Los 7 hallazgos del turno 1 (todos fixeados, RED-verificados)

Todos en la sección/ruteo de mutación de `slice-review.md`+SKILL y sus tests:
1. `--coherence` gana no estaba enforced (Step 1 chequeaba igualdad exacta) → el bloque `--mutation`
   ahora resuelve `--coherence` primero. 2. la prohibición de escritura contradecía al foco (no podía
   mutar) → excepción tallada. 3. `$tmp` sin asignar → `$tmp = Join-Path $env:TEMP "sr-mutation-$PID"`.
   4. worktree sin deps gitignoradas (JS/Python) → declara "could not execute" en vez de falso limpio.
   5. guard anti-pin solo cazaba "Opus 5" → `(opus|sonnet|haiku|claude|gpt)[- ]?\d`. 6. `8 mutants`
   no anclaba a "at most" → `at most\s+8 mutants`. 7. assert standalone usaba `$txt` → `$s1`.
   Descartado (<60): techo de 400 (755 crudas pero ~187 lógica única; espejos no cuentan, práctica
   del proyecto). Low no fijado: el regex anti-pin no cubre Gemini/Llama/o3/Grok (solo Anthropic+GPT).

### Antes de tocar código (crítico)

- **Paso 1 (grill) de A5 CERRADO.** Si el `alignment-gate` frena el primer edit: decilo y reintentá,
  **no re-grilles** (pasó esta sesión, speed-bump de una vez).
- **Regla del espejo de slice-review**: canónico en **raíz** (`.claude/commands/slice-review.md`,
  `.agents/skills/slice-review/SKILL.md` — comparten el CUERPO, difieren en frontmatter), `cp` a los
  3 scaffolds (`skills/bootstrap-*/assets/scaffold/...`), regenerar los 3 manifests
  (`pwsh -NoProfile -File tools/gen-manifest.ps1 -SkillDir skills/<skill>`). Verificar 1 solo md5 por
  archivo across las 4 copias. **Cuidado con line-wraps**: los asserts son `-match` sin singleline;
  una frase asertada partida en 2 líneas por el reflow a ~100 col falla (pasó ~6 veces esta sesión).
- **Reviewers en SOLO LECTURA** en subagentes paralelos, con la prohibición "reviewer, not an editor"
  en el contexto compartido. `git status` antes de creerle a un hallazgo. Modelo por foco:
  bugs/contratos/tests Opus, reglas/historia/coherencia Sonnet. El foco de mutación: "most capable
  available" (= Opus 4.8 hoy).
- **⚠️ Los tests en BACKGROUND se matan en este entorno.** Correr en FOREGROUND redirigiendo a
  archivo (`... > out.txt 2>&1`) y grepear. La suite `review-loop-trigger` sola tarda >2 min (correrla
  con timeout 400000); las otras van con 240000.
- **El marcador avanza DESPUÉS de cada review y ANTES de los fixes.** `-Action open` (turno 1) NO
  avanza. El pase de coherencia NO avanza.

### Preferencias del usuario (vigentes — 2 nuevas esta sesión, en memoria)

- **No commitear sin que lo pida.** **Nada a Zoho.** **Impacto medido antes de cambiar el proceso.**
  Prefiere **cortar y seguir en terminal nueva**.
- **NUEVO — Prefiere Opus 4.8 sobre Opus 5** (`memory/prefiere-opus-4-8-sobre-opus-5.md`): volvió a
  4.8, termina más rápido; Opus 5 le daba muchas vueltas. Al hardcodear "Opus 5" en skills, preguntar
  si cambiar a 4.8 o dejar agnóstico.
- **NUEVO — Decidir lo técnico, preguntar lo de diseño** (`memory/decidir-tecnico-preguntar-diseno.md`):
  en preguntas técnicas confía en mi recomendación (decidir yo); elevar a pregunta solo diseño/
  producto/preferencia (modelo, costo/tiempo, scope).

### Roadmap restante

**Commit de los fixes de A5** (arriba) → **A6** (`06-regla-de-afirmaciones.md`) o **A4c** (grill del
verbo `close`/`clear`, follow-up de A4b). **A7 al final** (`07-sellar-y-deployar.md`: deploy a
`~/.claude/skills` + resellar el `.bootstrap-manifest.json` de la RAÍZ; requiere presencia humana).
**A1b** cuando se quiera. **Track B** (B1/B2) lo lleva el usuario en otra terminal, vence **10/9**.
Pendientes de fondo: la migración del esquema modelo-por-foco viejo ("Opus 5"/"Sonnet 5" en
`slice-review.md` Step 4) a agnóstico es SU PROPIO slice (no se hizo en A5, a propósito); PRDs/issues
en `.scratch/` gitignoreado; `copy-scaffold.ps1` pisa el `.gitignore` del destino; `core.autocrlf`
con hashes mixtos en manifests.

---

# Session Handoff — 2026-08-19 parte 3 (A4b COMMITEADO + review-loop turnos 1-2 corridos — próximo: DECIDIR B + cerrar el loop)

## ▶▶▶▶▶▶▶▶▶▶▶▶ ESTADO AL RETOMAR — próximo paso: DECISIÓN sobre el hallazgo B, después cerrar el loop

Rama **`feat/marcador-de-revision`**, HEAD **`c80241e`** (A4b commiteado con trailer `Slice-Close: A4b`;
el hook disparó el `/review-loop`). **Árbol sucio**: 16 archivos modificados (los fixes de los turnos
1-2 del loop) + este handoff. Suite A4b **4/4 verde** (`mirror`, `review-marker`, `slice-review`,
`review-loop-incremental`). Marcador en **`35d625a`**; delta sin revisar (turno 3) = **solo
`tests/review-marker.tests.ps1`** (una línea de assert, trivial). **`-Action slice-base` = `f86d1eb`
= arranque de A4b** → el anclaje de la coherencia funciona EN VIVO (no toma la rama entera). **NO
commiteado** (loop a medio cerrar + B sin decidir; el usuario pidió seguir en terminal nueva).

### 🔴 Decisión pendiente del usuario: el hallazgo B (Medium, confianza 62)

**B: `open` sobreescribe `slice-open` sin guard → under-scope al re-correr `/review-loop` sobre un
slice SIN cerrar.** `review-marker.ps1:267` escribe `slice-open:$branch` incondicionalmente y ningún
verbo lo limpia al cierre. Si el loop agota el cap de 5 turnos SIN cerrar limpio y alguien re-corre
`/review-loop` sobre el MISMO slice, el turno-1 `open` re-snapshotea el marcador YA avanzado → la
coherencia ancla más tarde y lee MENOS que el slice (la dirección "under-scope" que el diseño llama
peligrosa). **Fuertemente acotado**: nunca dispara en el flujo normal un-loop-por-slice; la coherencia
a scope completo YA corre en el primer cap-close ANTES de cualquier re-corrida; re-correr un slice sin
cerrar es off-workflow. **El fix correcto es mecanismo NUEVO** (un verbo `close`/`clear` atado al
trailer `Slice-Close:` + `open` write-once-hasta-limpiar) — un write-once naive ROMPE el flujo
multi-slice (cada slice nuevo DEBE re-snapshotear). Fuera del scope de A4b (que es solo *anclaje*).
**Opciones**: (a) extender A4b ahora con el verbo `close`; (b) abrir slice propio **A4c**; (c)
aceptarlo como límite conocido documentado. **Mi recomendación: (b) o (c)** — es off-workflow y de
segundo orden, y "impacto medido antes de cambiar el proceso" desaconseja meter mecanismo nuevo a
mitad de slice. **Es tu llamada.**

### Después de decidir B: cerrar el loop

1. **Turno 3** (trivial): el delta sin revisar es solo el assert positivo que agregué en el turno 2
   (`open registra el marcador como slice-open`). Ya está RED/green-verificado por mutación (key-swap
   y early-exit). Un reviewer enfocado de tests lo cierra en un toque, o se pliega.
2. **Pase de coherencia** (`/slice-review --coherence`) UNA vez al cierre. Anclará en `slice-base` =
   `f86d1eb` = **solo A4b** (dogfoodea el propio fix de A4b). Sonnet 5, solo lectura.
3. **Commitear los fixes del loop** cuando el usuario lo pida. Sugerido: `fix(review-loop):
   correcciones del review-loop sobre A4b`, **SIN trailer** (para no re-disparar el hook). Si B se
   arregla acá, mencionarlo; si va a A4c, dejarlo fuera.

### Qué hizo esta sesión (commit A4b + review-loop turnos 1-2)

1. **Commiteó A4b** (`c80241e`, trailer `Slice-Close: A4b`) tras verificar la suite 4/4. El hook
   `review-loop-trigger` disparó la orden de correr `/review-loop`.
2. **Dogfoodeó A4b sobre sí mismo**: turno 1 corrió `-Action open` → snapshoteó `f86d1eb` como
   `slice-open` → `slice-base` pasó de `43166da` (base de rama) a `f86d1eb` (arranque de A4b). **El
   fix de A4b validado en vivo.**
3. **Turno 1** (5 reviewers, modelo por foco; pase de confianza en Opus, 0 descartados): 3 Medium
   (B, C, D) + 2 Low (A, F).
   - **A (Low, conf 92)** — bloque de cuarentena `.bad` en `open` era **código muerto inalcanzable**
     (`$sha` sale del estado ya leído; estado corrupto = vacío → sale en el guard antes) + comentario
     falso "same quarantine as advance". **FIXEADO**: borrado el bloque, comentario correcto.
   - **C (Medium, conf 85)** — ningún test que `open` preserve `untracked:`/dedupe del hook (mutación
     "escribir solo slice-open" quedaba verde). **FIXEADO**: bloque de test nuevo, RED-verificado.
   - **D (Medium, conf 85)** — ningún test que `open` NO avance el marcador (si avanzara, el próximo
     `range` cerraría sin revisar). **FIXEADO** en el mismo bloque, RED-verificado.
   - **F (Low, conf 68)** — el caveat amend/rebase nombraba `<branch-base>` sin decir cómo obtenerlo
     (y `slice-base` devuelve el snapshot stale ahí). **FIXEADO**: apunta a `-Action base`.
   - **B (Medium, conf 62)** — NO fixeado, ver arriba (decisión del usuario).
4. **Turno 2** (3 reviewers enfocados): bugs+contratos **limpio**, mirror+reglas **limpio**, tests
   marcó un Medium (mi bloque C/D no asertaba el positivo `open escribió slice-open`). **Verificado
   empíricamente** que las 2 mutaciones que nombraba (key-swap y early-exit) **ya las mata el tracer
   apilado adyacente** (`slice-base -eq $m1`, línea 607) → "already handled elsewhere". Aun así
   agregué el assert positivo (bloque auto-contenido), RED/green-verificado.
5. **Regla del espejo respetada**: 4 copias byte-idénticas del marcador y de slice-review .md/SKILL,
   3 manifests regenerados con `tools/gen-manifest.ps1`. `tests/` no se espeja.

### Archivos modificados (sin commitear, 16)

`review-marker.ps1` ×4 · `slice-review.md`+SKILL ×4 (=8) · 3 manifests · `tests/review-marker.tests.ps1`.
(review-loop.md/SKILL NO se tocaron este turno.) + este handoff.

### Antes de tocar código (crítico)

- **Paso 1 (grill) de A4b CERRADO.** Si el `alignment-gate` frena el primer edit: decilo y reintentá,
  **no re-grilles** (pasó esta sesión, es speed-bump de una vez).
- **Regla del espejo del marcador**: la copia que leen los tests es **`bootstrap-personal-project`**
  (`tests/review-marker.tests.ps1:5`); editar ahí, mutar/restaurar ahí, y espejar a raíz + otras 2
  (byte-idénticas, la raíz también) con `cp`, después `md5sum` para confirmar 1 solo hash. slice-review
  .md/SKILL: canónico en **raíz** (`.claude/commands/`, `.agents/skills/`), `cp` a 3 scaffolds.
  Regenerar los 3 manifests: `pwsh -NoProfile -File tools/gen-manifest.ps1 -SkillDir skills/<skill>`.
- **⚠️ Los tests en BACKGROUND se MATARON dos veces en este entorno** (status `killed`, sin output).
  Correr las suites en **FOREGROUND redirigiendo a un archivo** (`... > out.txt 2>&1`) y después
  `grep` el archivo. Timeout amplio (240000). Las 4 suites de A4b juntas tardan ~1-2 min.
- **Reviewers en SOLO LECTURA** en subagentes paralelos; `git status` antes de creerle a un hallazgo.
  Modelo por foco: bugs/contratos/tests Opus, reglas/historia/coherencia Sonnet.
- **Cada fix con RED verificado ANTES** (mutar la copia personal, ver `FAIL:`, restaurar). Verificado
  esta sesión: mutante-D (avanza marcador), mutante-C (borra claves), mutante key-swap (slice-open→marker).
- **El marcador avanza DESPUÉS de cada review y ANTES de los fixes.** `-Action open` NO avanza (snapshotea).
  Esta sesión: avanzó `f86d1eb`→`c80241e` (turno 1) y `c80241e`→`35d625a` (turno 2).

### Preferencias del usuario (vigentes)

- **No commitear sin que lo pida.** **Nada va a Zoho.** **Impacto medido antes de cambiar el proceso**
  (aplica a la decisión de B). Prefiere **cortar y seguir en terminal nueva** — por eso este handoff.

### Roadmap restante

**Cerrar el loop de A4b** (decidir B → turno 3 + coherencia → commit) → A5 (mutación acotada,
`05-mutacion-acotada.md`) → A6 (`06-regla-de-afirmaciones.md`) → **A7 al final**
(`07-sellar-y-deployar.md`: deploy a `~/.claude/skills` + resellar el `.bootstrap-manifest.json` de la
RAÍZ; requiere presencia humana). **A1b** cuando se quiera (15 hallazgos + nudo de diseño). **Track B**
(B1/B2) lo lleva el usuario en otra terminal, vence **10/9**. Pendientes de fondo: PRDs/issues en
`.scratch/` gitignoreado; `copy-scaffold.ps1` pisa el `.gitignore` del destino; `core.autocrlf` con
hashes mixtos en manifests.

---

# Session Handoff — 2026-08-19 parte 2 (A4b IMPLEMENTADO test-first, SIN COMMITEAR — próximo: commit + review-loop en terminal nueva)

## ▶▶▶▶▶▶▶▶▶▶▶▶ ESTADO AL RETOMAR — próximo paso: COMMIT de A4b + `/review-loop`

Rama **`feat/marcador-de-revision`**, HEAD sigue **`4713031`** (A4b **NO commiteado**). **Árbol sucio**:
25 archivos modificados (el trabajo de A4b) + este handoff. Suite de A4b **verde** (`mirror`,
`review-marker`, `slice-review`, `review-loop-incremental` → 4/4). Marcador de revisión en **`f86d1eb`**
(sin avanzar esta sesión: todavía no corrió ningún review sobre A4b). **Decisión del usuario 2026-08-19:
commitear A4b y correr el `/review-loop` EN LA PRÓXIMA TERMINAL**, no en esta sesión.

### Lo PRIMERO que hay que hacer (el usuario ya lo aprobó)

1. **Commitear A4b** con el trailer que dispara el hook:
   ```
   feat(review-loop): A4b — anclar el pase de coherencia al slice que cierra

   Slice-Close: A4b
   ```
2. **Correr `/review-loop`** sobre el delta sin revisar (`-Action range` → `f86d1eb`) hasta que cierre
   (cero medium/high, o techo de 5 turnos). NO preguntar si correrlo — correrlo.
3. **Esto dogfoodea A4b sobre sí mismo**: el `/review-loop` del repo ya trae el `-Action open` en el
   turno 1, así que la coherencia al cierre anclará en `slice-base` = `slice-open` snapshoteado =
   `f86d1eb` → `git diff f86d1eb` = solo A4b, no la rama entera. Es la validación viva del fix. (Si el
   snapshot no anduviera, caería a base de rama = sobre-scope, dirección segura.)

### Qué hizo esta sesión (grill + TDD de A4b, sin commit)

1. **Grill de A4b** (paso 1 del workflow, cerrado). Decisiones firmadas en el issue
   `.scratch/review-cost-redesign/issues/04b-anclaje-del-pase-de-coherencia.md` (status
   `needs-info` → `ready-for-agent`, sección "Decisiones del grill" + AC). Reencuadre clave: el hook
   dispara también por push y por la red de 400 líneas (no solo por trailer), así que **el enfoque 2
   (caminar `git log` a trailers) se descartó** — mis-ancla cuando el cierre no está declarado. Se
   eligió: el slice = donde quedó la última revisión (el marcador al inicio del loop), persistido con
   verbo (enfoque 1+3).
2. **TDD de A4b** test-first (RED verificado antes de cada impl). **180 add / 37 del de lógica**
   (marcador canónico + `.md` canónicos + tests; espejos y manifests no cuentan). Bajo el techo.
   - `review-marker.ps1`: **dos verbos nuevos**. `-Action open` (turno 1: guarda el marcador actual
     como `slice-open:<branch>`, **solo si `Resolve-Commit` pasa**; sin marcador/podado no escribe;
     misma cuarentena `.bad` que `advance`). `-Action slice-base` (devuelve `slice-open` si resuelve,
     si no cae a `Get-SliceBase` = idéntico a `base`; **superset estricto de `base`**; mismo contrato
     de exit `0+ref`/`2+nada`). Header del contrato actualizado a 6 verbos + clave `slice-open:`.
   - `slice-review.md` (command+SKILL): la coherencia ancla en **`-Action slice-base`** (no `base`) +
     caveat amend/rebase ("changes you did not make" → `git diff <branch-base>...HEAD`, acá la base SÍ
     resuelve, distinto del exit-2).
   - `review-loop.md` (command+SKILL): turno 1 llama **`-Action open`** después del `range` y antes
     del `advance` (snapshot = cierre del slice anterior; el `advance` lo mueve pero deja el snapshot).
   - Tests: `review-marker.tests.ps1` (+tracer de **rama apilada de 2 slices**: `slice-base` lee solo
     el slice-2 mientras `base` sigue trayendo la rama entera; + primer slice → base de rama;
     + slice-open irresoluble → fallback; + exit 2 sin base). `slice-review.tests.ps1` (`slice-base`
     + no `base` viejo + caveat). `review-loop-incremental.tests.ps1` (orden `open` entre range y
     advance, `Idx`, 4 copias).
3. **Regla del espejo respetada**: 4 copias byte-idénticas del marcador y de los 4 `.md` (un md5 por
   archivo), 3 manifests regenerados con `tools/gen-manifest.ps1`.

### Archivos modificados (sin commitear)

`review-marker.ps1` ×4 · `slice-review.md`+SKILL ×4 · `review-loop.md`+SKILL ×4 · 3 manifests ·
`tests/review-marker.tests.ps1` · `tests/slice-review.tests.ps1` ·
`tests/review-loop-incremental.tests.ps1` · este handoff.

### Antes de tocar código (crítico)

- **El paso 1 (grill) de A4b está CERRADO** esta sesión (decisiones en el issue). Si el
  `alignment-gate` frena el primer edit: decilo y reintentá, **no re-grilles**.
- **Regla del espejo**: editar canónicos root (`.claude/scripts/review-marker.ps1`,
  `.claude/commands/*.md`, `.agents/skills/*/SKILL.md`), `cp` a los 3 scaffolds
  (`skills/bootstrap-*-project/assets/scaffold/...`), regenerar manifests
  (`pwsh -NoProfile -File tools/gen-manifest.ps1 -SkillDir skills/<skill>`, una por vez).
  Para el **marcador**, la copia que leen los tests es la de `bootstrap-personal-project`; editar ahí
  y espejar a raíz + otras 2 (byte-idénticas, la raíz también).
- **Los reviewers del loop corren en SOLO LECTURA** en subagentes paralelos; chequear `git status`
  antes de creerle a un hallazgo. Modelo por foco: bugs/contratos/tests Opus, reglas/historia/
  coherencia Sonnet.
- **Las suites del review-loop tardan >2 min** — background, timeout amplio. Cada fix con RED
  verificado ANTES (mutante que **empieza** con `FAIL:`).
- **El marcador avanza DESPUÉS de cada review y ANTES de los fixes**. El `-Action open` NO avanza el
  marcador (snapshotea). El pase de coherencia NO avanza el marcador.

### Preferencias del usuario (vigentes)

- **No commitear sin que lo pida** (aprobó el commit de A4b, pero pidió hacerlo en terminal nueva).
  **Nada va a Zoho.** **Impacto medido antes de cambiar el proceso.** Prefiere **cortar y seguir en
  terminal nueva** antes que dejar crecer el contexto — por eso este handoff.

### Roadmap restante

**A4b** (commit + review-loop, arriba) → A5 (mutación acotada, `05-mutacion-acotada.md`) → A6
(`06-regla-de-afirmaciones.md`) → **A7 al final** (`07-sellar-y-deployar.md`: deploy a
`~/.claude/skills` + resellar el `.bootstrap-manifest.json` de la RAÍZ; requiere presencia humana).
**A1b** cuando se quiera (15 hallazgos + nudo de diseño). **Track B** (B1/B2) lo lleva el usuario en
otra terminal, vence **10/9**. Pendientes de fondo: PRDs/issues en `.scratch/` gitignoreado;
`copy-scaffold.ps1` pisa el `.gitignore` del destino; `core.autocrlf` con hashes mixtos en manifests.

---

# Session Handoff — 2026-08-19 (A4 CERRADO + review-loop limpio + coherencia cohere — próximo: A4b)

## ▶▶▶▶▶▶▶▶▶▶▶▶ ESTADO AL RETOMAR — próximo paso: GRILL de A4b (anclaje del pase)

Rama **`feat/marcador-de-revision`**, HEAD **`4713031`**. **Árbol limpio** salvo este handoff.
**Sin pushear.** Suite completa **12/12 verde**. Marcador de revisión en **`f86d1eb`** (`-Action
range` sale `f86d1eb` exit 0; el delta es SOLO la línea `argument-hint` de `slice-review.md` +
manifests = doc/frontmatter, **cero lógica**, fue la recomendación del propio pase de coherencia).
**No hay decisión pendiente del usuario** salvo arrancar el grill de A4b.

```
4713031  fix(review-loop): correcciones del review-loop sobre A4 (coherencia interna del pase)  <- fixes del loop (sin trailer)
c9843d5  feat(review-loop): A4 — pase de coherencia al cierre del slice                          <- Slice-Close A4
89917fe  fix(review-loop): correcciones del review-loop sobre A3 (resolucion del marcador + cobertura)
```

### Qué hizo esta sesión

1. **Implementó A4** test-first (`c9843d5`, trailer `Slice-Close: A4`): el **pase de coherencia**
   (issue `04-pase-de-coherencia.md`). Un reviewer único de solo lectura que mira el **slice entero**
   una vez al cierre, contra la intención declarada, en **Sonnet 5**, sin ejecutar nada, con sus
   hallazgos pasando por el pase de confianza. Vive en dos archivos canónicos:
   - `/slice-review` (`.claude/commands/slice-review.md` + `.agents/skills/slice-review/SKILL.md`):
     nueva sección `## Coherence pass` + ruteo de `--coherence` en Step 1; el rango completo se
     ancla con `review-marker.ps1 -Action base`.
   - `/review-loop` (`.claude/commands/review-loop.md` + `.agents/skills/review-loop/SKILL.md`):
     nueva sección `## At close: the coherence pass` que lo invoca en **ambos** cierres (limpio y
     techo de 5 turnos), con regla de skip si ningún reviewer corrió.
   - `tests/slice-review.tests.ps1`: +cobertura A4 (helper `Section` que aísla la sección; asserts
     de los 8 AC sobre las 4 copias), RED verificado antes de implementar.
2. **Corrió el `/review-loop` sobre A4 y lo cerró LIMPIO** (`4713031`, sin trailer para no
   re-disparar), **dogfoodeando la versión NUEVA** de `/review-loop` + `/slice-review` del repo
   (incluido el pase de coherencia recién agregado):
   - **Turno 1** (5 reviewers, modelo por foco): 2 Medium + 4 Low. **M1** (contratos+bugs convergen):
     el ruteo `--coherence` decía "skip Steps 1–5" pero el pase **reusa** Step 3/5/6 → un agente
     literal saltearía el pase de confianza (viola AC6); reescrito para nombrar qué reemplaza
     (delta+fan-out) vs qué reusa. **M2** (historia): el fallback exit-2 caía al branch range,
     contradiciendo la regla de A3 (`89917fe`: en exit-2 la base es lo irresoluble); reescrito
     (exit-2 → no `<base>...HEAD`; script ausente → base resoluble por nombre; guard base==HEAD).
     3 Low baratos fijados (ref "returned in Step 4", `[regex]::Escape` en el helper, argument-hint).
     1 Low **descartado por el pase de confianza** (falso positivo: "copia repo fuera de la red del
     mirror" — ya la cubre `review-loop-incremental.tests.ps1`, que compara las 4 copias).
   - **Turno 2** (2 reviewers enfocados, Opus): **limpio**, RED-before/green-after verificado.
   - **Pase de coherencia** (Sonnet 5, solo lectura, sobre el slice A4 real desde `a83125f`): **el
     slice COHERE** — trazó loop→`--coherence`→ruteo→sección→confianza→reporte end-to-end, los 8 AC,
     mirror y ADR. Único nit (argument-hint sin `--coherence`) ya corregido.
3. **Regla del espejo respetada**: 4 copias byte-idénticas de ambos pares (command+SKILL), 3
   manifests regenerados con `tools/gen-manifest.ps1`, `mirror.tests.ps1` + `review-loop-incremental`
   verdes.
4. **Destapó un hallazgo de diseño y lo capturó como A4b** (ver abajo).

### 🔴 A4b — anclaje del pase de coherencia (PRÓXIMO, necesita GRILL antes de TDD)

Issue nuevo: `.scratch/review-cost-redesign/issues/04b-anclaje-del-pase-de-coherencia.md` (leerlo
primero). **Problema medido** dogfoodeando el pase: A4 ancla en `-Action base` = base de la **rama**
contra main. En esta rama con slices **apilados** (A1..A4) eso da **9613 líneas / 56 archivos** en
vez de las **248** del slice A4. Bajo "feature branch per slice" (`CLAUDE.md`) sería correcto, pero
la práctica apila. **Decisión del usuario 2026-08-19**: tratarlo como slice propio (A4b), no asumir
el modelo un-slice-por-rama. **El *cómo* anclar es una bifurcación de diseño sin resolver** — 3
enfoques en el issue (marcador de apertura de slice / commit previo con `Slice-Close:` / verbo
`-Action slice-base`). El grill debe fijar: qué es "el slice" al apilar, el primer slice de la rama
(cae a base de rama), interacción con `--amend`/`rebase`.

### Antes de tocar código (crítico)

- **El `alignment-gate` frena el primer edit** de código por sesión. Para A4b el paso 1 **NO está
  cerrado** (es diseño nuevo): **ofrecé/ hacé el grill** (`/grill-me` sobre el anclaje) antes de
  codear. (Distinto de A1–A4, que sí estaban cerrados por el grill del 11/8.)
- **Regla del espejo**: editar los 2 canónicos root (`.claude/commands/`, `.agents/skills/`),
  propagar con `cp` a los 3 scaffolds (`skills/bootstrap-*-project/assets/scaffold/...`), regenerar
  manifests (`pwsh -NoProfile -File tools/gen-manifest.ps1 -SkillDir skills/<skill>`, una por vez).
  Si A4b toca `review-marker.ps1`, ese va a las **4 copias byte-idénticas** (la raíz también) y el
  hook raíz difiere solo en comentarios/`$msg`.
- **Editar skills acá NO tiene efecto** hasta `tools/sync-skills.ps1` (pendiente heredado del 1/8);
  no afecta a los tests, que leen del scaffold directo. Igual se puede **dogfoodear** el
  `/slice-review` y `/review-loop` del repo (los commands `.claude/` toman la versión del repo).
- **Los reviewers del loop corren en SOLO LECTURA** en subagentes paralelos; se les pasa la
  prohibición "reviewer, not an editor" en el contexto compartido (una sola vez — hay test que lo
  fija). Chequear `git status` antes de creerle a un hallazgo. Modelo por foco: bugs/contratos/tests
  en Opus, reglas/historia y **coherencia** en Sonnet (`Agent` tool: `model: opus`/`sonnet`).
- **Correr las suites del review-loop tarda >2 min** — la suite entera en background, timeout amplio.
- **Cada fix con test en RED verificado ANTES** (mutar en copia/inline, ver rojo, restaurar). El
  mutante se verifica con una línea que **empieza** con `FAIL:`.
- **El marcador avanza DESPUÉS de cada corrida de review y ANTES de aplicar los fixes** (invariante
  del ADR). El pase de coherencia NO avanza el marcador (es una relectura del slice entero).

### Preferencias del usuario (vigentes)

- **No commitear sin que lo pida** (esta sesión pidió commit explícito de A4 y de los fixes del
  loop). **Nada va a Zoho.** **Impacto medido antes de cambiar el proceso.** Prefiere **cortar y
  seguir en terminal nueva** antes que dejar crecer el contexto — por eso este handoff.

### Roadmap restante

**A4b** (próximo, necesita grill) → A5 (mutación acotada, `05-mutacion-acotada.md`) → A6
(`06-regla-de-afirmaciones.md`) → **A7 al final** (`07-sellar-y-deployar.md`: deploy a
`~/.claude/skills` + resellar el `.bootstrap-manifest.json` de la RAÍZ del repo, que sigue hasheando
el slice-review viejo; requiere presencia humana). **A1b** cuando se quiera (15 hallazgos + nudo de
diseño). **Track B** (B1/B2) lo lleva el usuario en otra terminal, vence **10/9**. Pendientes de
fondo: PRDs/issues viven en `.scratch/` gitignoreado; `copy-scaffold.ps1` pisa el `.gitignore` del
destino; `core.autocrlf` con hashes mixtos en manifests.

---

# Session Handoff — 2026-08-18 (A3 CERRADO + review-loop limpio turno 3 — próximo: A4)

## ▶▶▶▶▶▶▶▶▶▶▶▶ ESTADO AL RETOMAR — próximo paso: abrir A4

Rama **`feat/marcador-de-revision`**, HEAD **`89917fe`**. **Árbol limpio** salvo este handoff. **Sin
pushear.** Suite completa **12/12 verde**. Marcador de revisión avanzado a **`a83125f`** (`-Action
range` imprime ese SHA con exit 0, y **`git diff a83125f` sale vacío** = nada sin revisar). **No hay
decisión pendiente del usuario.**

```
89917fe  fix(review-loop): correcciones del review-loop sobre A3 (resolucion del marcador + cobertura)  <- fixes del loop (sin trailer)
4cc6227  feat(review-loop): A3 — corrida de review incremental                                          <- Slice-Close A3
67e45f1  fix(review-loop): correcciones del review-loop sobre A2b (encoding stdin + cobertura)
```

### Qué hizo esta sesión

1. **Implementó A3** test-first (`4cc6227`, trailer `Slice-Close: A3`): los 3 cambios a `/slice-review`
   del issue `03-corrida-de-review-incremental.md` —
   - **Cambio 1+2**: el objetivo por DEFECTO (sin args) pasa a ser el **delta sin revisar** resuelto
     del marcador (`review-marker.ps1 -Action range`); el rango completo del slice queda reservado al
     pase de coherencia (A4); delta vacío (exit 0) → "nothing to review" sin inventar rango; exit 2 →
     recuperación declarada no-incremental.
   - **Cambio 3**: la prohibición de escritura viaja en el **contexto compartido**, una sola vez
     ("You are a reviewer, not an editor…"), para todos los focos (84/345 reviewers editaban).
   - **Cambio 4+5**: **modelo por foco** — Sonnet 5 para reglas e historia (mecánicos), Opus 5 para
     bugs, contratos y tests; el pase de confianza sigue en Opus 5, misma rúbrica y corte en 60.
2. **Corrió el `/review-loop` sobre A3 y lo cerró LIMPIO en el turno 3** (`89917fe`, sin trailer para
   no re-disparar). Se dogfoodeó la versión NUEVA de `/slice-review` (la del repo, no la instalada):
   - **Turno 1** (5 reviewers): **Media** con convergencia de 3 (bugs/historia/contratos) — el Step 1
     metía "marker script missing" en el bucket **exit 2**, pero `pwsh -File <missing>` sale **64** e
     imprime usage a stdout (verificado empíricamente), contradiciendo el `Test-Path` de
     `review-loop.md`. Fix: **pre-flight `Test-Path`** del marcador (script ausente → branch range,
     no-incremental) + **exit-2 partido** en base-irresoluble (working-tree/último commit) vs
     no-repo/sin-commits (reportar y parar, sin `git show HEAD`). Más gaps de cobertura (exit-2 sin
     test) y el lead-in corregido. Reglas/mirror/tamaño: limpios.
   - **Turno 2** (3 reviewers): **Media** — las *acciones* de recuperación seguían sin pinnear (solo
     la detección). Fix: asserts de las 3 acciones + caveat de parity con `review-loop.md:86` (no
     arrastrar `git diff <base>...HEAD` en detached-HEAD).
   - **Turno 3** (2 reviewers, enfocado): **LIMPIO**, cero medium/high. Todos los fixes con RED/mutación
     verificada.
3. **Regla del espejo respetada**: 8 archivos de prompt byte-idénticos (root + 3 scaffolds × command/
   SKILL), 3 manifests regenerados con `tools/gen-manifest.ps1`, `mirror.tests.ps1` verde.

### Dos Lows PRE-EXISTENTES notados, NO fijados (fuera de scope de A3, ambos reviewers coincidieron)

- La ambigüedad **orphan-branch-sin-commits** entre los sub-casos exit-2 (a) y (b) de `slice-review.md`
  (un orphan sin commits matchea "orphan branch" de (a) y "no commits" de (b); un agente razonable
  rutea a (b)). Pre-existente, no introducido por A3.
- El **fallback de script-ausente** (`git diff <base>...HEAD`) no guarda el corner "script ausente +
  detached/orphan", donde la base tampoco resuelve. El caveat lo aclara como generalización, no
  absoluto.

### Archivos tocados (ya commiteados)

`.claude/commands/slice-review.md` + `.agents/skills/slice-review/SKILL.md` (canónicos) · 3 scaffolds
× ambos · `tests/slice-review.tests.ps1` (+11 asserts, `-ge 2`→`-ge 3`) · los 3
`.bootstrap-manifest.json`.

### Próximo paso: A4 — pase de coherencia

Issue: `.scratch/review-cost-redesign/issues/04-pase-de-coherencia.md`. **Leerlo primero** (los AC son
el contrato). Contexto de A3 que A4 asume: el rango completo del slice quedó **reservado al pase de
coherencia** (eso es A4); `/slice-review` por defecto revisa solo el delta incremental.

### Antes de tocar código (crítico)

- **El `alignment-gate` frena el primer edit** de código por sesión. El paso 1 está cerrado para este
  track (grill 11/8, PRD e issues aprobados 12/8): **decilo y reintentá, NO ofrezcas grill.**
- **Regla del espejo**: editar los 2 canónicos root (command en `.claude/commands/`, SKILL en
  `.agents/skills/`), propagar con `cp` a los 3 scaffolds (byte-idénticos), regenerar manifests
  (`pwsh -NoProfile -File tools/gen-manifest.ps1 -SkillDir skills/<skill>`, una por vez). El test
  itera sobre repo + 3 skills. `mirror.tests.ps1` verifica byte-identidad entre scaffolds.
- **Editar skills acá NO tiene efecto** hasta `tools/sync-skills.ps1` (pendiente heredado del 1/8); no
  afecta a los tests, que leen del scaffold directo. Igual se puede **dogfoodear** el `/slice-review`
  del repo (el command `.claude/commands/` sí toma la versión del repo en esta sesión).
- **Los reviewers del loop corren en SOLO LECTURA** en subagentes paralelos; chequear `git status`
  antes de creerle a un hallazgo (un reviewer que muta contamina a los paralelos). Modelo por foco:
  bugs/contratos/tests en Opus, reglas/historia en Sonnet (Agent tool: `model: opus`/`sonnet`).
- **Correr las suites del review-loop tarda >2 min** — mejor la suite entera en background, timeout
  amplio. El runner ad-hoc con `[ -n "$failed" ] && …` da falso exit 1 si no hubo fallas; terminar con
  `exit 0`.
- **Cada fix con test en RED verificado ANTES** (mutar en copia/inline, ver rojo, restaurar). El
  mutante se verifica con una línea que **empieza** con `FAIL:`. Para asserts de conteo (p.ej.
  `not incremental` ≥2), verificar que borrar UNA ocurrencia baja el conteo y el assert muerde.

### Preferencias del usuario (vigentes)

- **No commitear sin que lo pida** (esta sesión pidió commit explícito de A3 y de los fixes del loop).
  **Nada va a Zoho.** **Impacto medido antes de cambiar el proceso.** Prefiere **cortar y seguir en
  terminal nueva** antes que dejar crecer el contexto — por eso este handoff y A4 va en terminal nueva.

### Roadmap restante

A4 (próximo) → A5 → A6 → **A7 al final** (deploy a `~/.claude/skills` + resellar el
`.bootstrap-manifest.json` de la RAÍZ del repo, que sigue hasheando el slice-review viejo; requiere
presencia humana). **A1b** cuando se quiera (15 hallazgos + nudo de diseño). **Track B** (B1/B2) lo
lleva el usuario en otra terminal, vence **10/9**. Pendientes de fondo: PRDs/issues viven en
`.scratch/` gitignoreado; `copy-scaffold.ps1` pisa el `.gitignore` del destino; `core.autocrlf` con
hashes mixtos en manifests.

---

# Session Handoff — 2026-08-18 (A2b CERRADO + review-loop limpio — próximo: A3)

## ▶▶▶▶▶▶▶▶▶▶▶▶ ESTADO AL RETOMAR — próximo paso: abrir A3

Rama **`feat/marcador-de-revision`**, HEAD **`67e45f1`**. **Árbol limpio** salvo este handoff. **Sin
pushear.** Suite completa **12/12 verde**. Marcador de revisión en **HEAD** (`-Action range` sale
**vacío + exit 0** = nada sin revisar). **No hay decisión pendiente del usuario.**

```
67e45f1  fix(review-loop): correcciones del review-loop sobre A2b (encoding stdin + cobertura)
040e666  fix(review-loop): A2b — resolucion de base del hook y correcciones de logica   <- Slice-Close A2b
7de07a2  fix(review-loop): correcciones de los turnos 2-5 sobre el disparo por cierre de slice (grupo seguro)
```

### Qué hizo esta sesión

1. **Commiteó el grupo seguro** heredado (`7de07a2`): tests + prosa, cerró la Alta B de sesiones previas.
2. **Implementó A2b** test-first (`040e666`, con trailer `Slice-Close:`): los 4 fixes de lógica que
   quedaban del review-loop de A2 —
   - **Alta A** (la que dejaba el mecanismo muerto): el hook hacía `exit 0` antes del gate del trailer
     cuando la base no era `main`/`master`/`develop`, quedando **mudo** en repos base `trunk`/`dev`/
     `release`. Fix: **delega la base al marcador** con una acción nueva **`-Action base`** (mismo
     resolvedor que `range`: `Get-SliceBase` con `for-each-ref` + `merge-base --octopus`).
   - **`$(...)`/backtick**: cuando el comando los contiene, recalcula las banderas sobre el comando
     **crudo** y las combina con OR (no modela `$()`, la dirección segura ya declarada).
   - **Cuarentena `.bad` en `advance`**: si el estado es ilegible, lo aparta antes de pisarlo (gemelo
     de lo que el hook ya hacía).
   - **Eliminó `gh repo view`** (llamada de red por commit delante del fallback local).
3. **Corrió el `/review-loop` sobre A2b y lo cerró LIMPIO en el turno 2** (`67e45f1`, sin trailer para
   no re-disparar). Hallazgos:
   - **Turno 1** (5 reviewers): **F3 (Medium)** — el hook forzaba `OutputEncoding` pero **no
     `InputEncoding`**; el JSON del evento llega por **stdin**, y bajo consola OEM un `cwd` no-ASCII
     mojibakeaba, `Set-Location` fallaba en silencio y **el hook operaba sobre el repo AMBIENTE y
     disparaba mal**. (Es el "flake" que sesiones previas descartaron: era un bug real.) Fix: forzar
     `InputEncoding=UTF-8` + **hardening** (`exit 0` si el `cwd` del evento no resuelve). Más **F1**
     (comentario del OR sobreafirmaba → corregido + fixture del costo aceptado) y **F4** (rama
     `$writable` de la cuarentena sin test → agregado). Todos RED-verificados por mutante.
   - **Turno 2** (2 reviewers, enfocado): bugs+contratos **limpio**; el de tests **falló por límite de
     sesión** pero marcó que **Test B era frágil** (dependía de la frescura del HEAD de este repo) →
     rehecho **self-contained**, RED/GREEN por mutante.
4. **Documentó como límite conocido (Low, no fijados)** en `docs/TESTING.md`: **F9** (el guard del paso
   5 "no revisar la base contra sí misma" compara por NOMBRE, pero la base delegada es un SHA → un
   `Slice-Close` **directo sobre una base `trunk`** dispara; off-workflow, dirección segura) y **F2**
   (`.bad -Force` pisa una cuarentena previa).
5. **Actualizó la memoria** `forecasting-app-mitigacion-interina-review`: **Claude Analytics** es el
   tercer repo con la mitigación interina (bullet + `.scratch/review-loop-interino.md`, sin commitear
   allá), a revertir al upgradear.

### Archivos tocados (ya commiteados)

Hook `review-loop-trigger.ps1` (4 copias: raíz en español, 3 skills byte-idénticas) · marcador
`review-marker.ps1` (4 copias) · `tests/review-loop-trigger.tests.ps1` · `tests/review-marker.tests.ps1`
· `docs/TESTING.md` · los 3 `.bootstrap-manifest.json` (regenerados).

### Próximo paso: A3 — corrida de review incremental

Issue: `.scratch/review-cost-redesign/issues/03-corrida-de-review-incremental.md`. Modifica
**`/slice-review`** (la skill/command del reviewer), tests en **`tests/slice-review.tests.ps1`**. Tres
cambios: (1) objetivo por defecto = delta sin revisar desde el marcador (con delta vacío, reporta "nada
que revisar", no inventa rango); (2) **la prohibición de escribir viaja en el contexto compartido** una
sola vez (84/345 reviewers editaron pese a la orden); (3) **modelo por foco**: Sonnet 5 para reglas e
historia, Opus 5 para bugs/contratos/tests + pase de confianza. AC completos en el issue. **Regla del
espejo: 4 copias byte-idénticas + `mirror.tests.ps1` verde.**

### Antes de tocar código (crítico)

- **El `alignment-gate` frena el primer edit** de código por sesión. El paso 1 está cerrado para este
  track (grill 11/8, PRD e issues aprobados 12/8): **decilo y reintentá, NO ofrezcas grill.**
- **Regla del espejo**: editar el canónico en **`bootstrap-personal-project`** (es a donde apuntan los
  tests), espejar con `Copy-Item` a `ai-project` y `southpoint` (byte-idénticas) **al final**, y para
  la copia raíz replicar la **lógica** (el hook raíz va en español; `review-marker.ps1` y las skills
  `.md` raíz son byte-idénticas). Después regenerar manifests: `pwsh -NoProfile -File
  tools/gen-manifest.ps1 -SkillDir skills/<skill>`, una por vez. Para A3 el archivo es
  `slice-review.md` (¿en `.claude/commands/` y `.agents/skills/`? verificar dónde vive en el scaffold).
- **Editar skills acá NO tiene efecto** hasta `tools/sync-skills.ps1` (pendiente heredado del 1/8) —
  no afecta a los tests, que leen del scaffold directo.
- **Los reviewers del loop corren en SOLO LECTURA** y experimentan en copias del scratchpad; chequear
  `git status` antes de creerle a un hallazgo (un reviewer que muta contamina a los paralelos).
- **Correr las suites del review-loop tarda >2 min** — una por vez, en background, timeout amplio.
- **Cada fix con test en RED verificado ANTES** (mutar producción en copia scratch, ver rojo, restaurar).
  El mutante se verifica con una línea que **empieza** con `FAIL:`, no con `-split 'FAIL:'`.
- **El guard del harness bloquea `Remove-Item -Recurse` en PowerShell** en algunos contextos: correr
  las pruebas manuales sin cleanup inline y limpiar los temporales con `rm -rf` vía Bash después.
- **`$CLAUDE_JOB_DIR` no está seteada en la tool de PowerShell**; usar rutas temp concretas.

### Preferencias del usuario (vigentes)

- **No commitear sin que lo pida.** **Nada de esto va a Zoho.** **Impacto medido antes de cambiar el
  proceso.** Prefiere **cortar y seguir en terminal nueva** antes que dejar crecer el contexto.

### Roadmap restante

A3 (próximo) → A4/A5 → A6 → **A7 al final** (deploy a `~/.claude/skills`, requiere presencia humana).
**A1b** cuando se quiera (15 hallazgos + nudo de diseño). **Track B** (B1/B2) lo lleva el usuario en
otra terminal, vence **10/9**. Pendientes de fondo sin cerrar: PRDs/issues viven en `.scratch/`
gitignoreado (existen solo en el working tree, sin decidir desde 12/8); `copy-scaffold.ps1` pisa el
`.gitignore` del destino; `core.autocrlf` con hashes mixtos en manifests.

---

# Session Handoff — 2026-08-15 (GRUPO SEGURO APLICADO — la alta B está cerrada)

## ▶▶▶▶▶▶▶▶▶▶▶▶ ESTADO AL RETOMAR — próximo paso: abrir A2b

Rama **`feat/marcador-de-revision`**. Último commit sigue siendo **`e320510`** (A2). Encima están los
**26 archivos modificados sin commitear** (los mismos de antes: no se creó ni borró ningún archivo).
Suite completa **12/12 verde**, corrida entera al cierre de esta sesión.

```
e320510  feat(review-loop): disparo por cierre de slice declarado          <- A2
67ae410  fix(review-loop): correcciones del ciclo de revision sobre el marcador
326aee3  feat(review-loop): marcador de revision y turno incremental       <- A1
```

**No hay ninguna decisión pendiente del usuario.**

### Qué hizo esta sesión: el paso 1 del plan (los 7 hallazgos del "grupo seguro")

Sólo tests y prosa — **cero cambios de producción**, que es lo que hacía seguro aplicarlos con el cap
de 5 turnos agotado. Cada uno con su mutante verificado, no inferido.

| # | Hallazgo | Qué se hizo | Verificación |
|---|---|---|---|
| **Alta B** | el fixture del "costo aceptado" pinea sólo la mitad del bloque borrado | assert **gemelo** `git -C '<otro>' push` en `tests/review-loop-trigger.tests.ps1` | mutante = reintroducir SOLO la rama `git -C` del 3b: el gemelo se pone **rojo** y el fixture viejo del `cd` sigue **verde** — o sea, medido, el viejo no protegía esa forma |
| Media | la ventana de binarios de 8000 B no la fija ningún test | fixture con el primer NUL en el byte **5460** y 420 líneas | mutante 8000 → 4096: **rojo** |
| Media | el UTF-8 del hook no tiene fixture con ruta de repo no-ASCII | caso con repo bajo `…ñandu…` y code page **850 forzada dentro del hijo**, con control positivo | mutante = angostar el forzado al solo `ls-files`: **rojo** (dispara cuando no debe) |
| Media-baja | `tests/review-marker.tests.ps1` — el `$hu.Count` no muerde | `@($prop.Value \| Where-Object { $_ })`: un valor nulo cuenta 0 | mutante = el `advance` escribe la clave en `$null`: pre-fix imprime `ok: … fichó un untracked (1)` **mintiendo**, post-fix `FAIL: … (0)` |
| Baja | setup muerto en los fixtures de `--base` | se sacó el `git -C $t branch develop` de los **tres** (el hallazgo nombraba dos) | medido: las 3 formas × con/sin la rama → los 6 asserts pasan igual. El hook **no valida** que la base exista |
| Baja ×3 | `docs/TESTING.md` desfasada | ver abajo | — |

**Las correcciones de `docs/TESTING.md`**: el bullet del costo aceptado ahora declara los **dos**
fixtures y por qué hacen falta los dos; la lista de patrones sin fixture vive **en un solo lugar**
(las dos discrepaban sobre `*.lock`; el único lockfile con fixture es `package-lock.json`, por
`*lock.json`); el bullet de `$(...)` pasó de "límite sin repro" a **límite con repro ejecutable**, y
el bullet del comando normalizado dejó de leerse como "el bypass por texto entrecomillado está
cerrado", porque no lo está.

### El hallazgo 19 (`$(...)`) quedó reproducido sobre la función real

Corrido contra el `Hide-Literals` del hook, no sobre una reimplementación:

```
push=False commit=True   <- git commit -m "$(sed 's/"/x/' f)" && git push      # push REAL perdido
push=False commit=False  <- echo "$(sed 's/"/x/' f)" && git commit -m cierre   # cierre declarado perdido
push=True  commit=True   <- git commit -m "wrote $(echo "git push") today"     # dispara salteando gate/frescura/techo
push=True  commit=True   <- git commit -m "fecha $(date +"%F")" && git push    # uso NATURAL: correcto
```

La última fila es la que acota la severidad a media: con número **par** de comillas dobles el
recorrido se re-alinea solo. **Sigue sin arreglar** — es de lógica, va a A2b, y la opción elegida
está escrita en `docs/TESTING.md`: no modelar `$()`, sino calcular las banderas también sobre el
comando crudo cuando aparece `$(` o un backtick y quedarse con el **OR**.

### Tests

- **Suite completa 12/12 verde**, corrida entera esta sesión (las dos del review-loop por separado,
  las otras 10 en un loop). Runner por archivo: `pwsh -NoProfile -File tests/<archivo>.tests.ps1`.
- `tests/review-loop-trigger.tests.ps1`: **62 asserts** (eran 57; +4 nuevos, +1 guard).
  `tests/review-marker.tests.ps1`: **67 asserts**, todos verdes.
- **4 mutantes verificados, los 4 mueren** (uno por fix de fixture). Ninguno sobrevivió.
- Los mutantes se corrieron **siempre en copias del scratchpad**, nunca sobre el árbol: al cierre
  `git status` muestra los mismos 26 modificados, ningún archivo nuevo ni borrado.
- Repos temporales (`$TEMP/rlt-test-*`, `rm-test-*`): **0** al cerrar.

### ⚠️ El cap sigue agotado — lo que esta sesión escribió NO lo revisó ningún turno

Es la razón por la que sólo se tocaron tests y prosa. El delta desde el marcador (`78b8a9b`) son
**69 líneas de lógica de test** + prosa (`docs/TESTING.md` + este handoff). Bien bajo el techo.

### Bugs

- **Cerrados esta sesión**: la **alta B** y 6 hallazgos más del turno 5 (tabla de arriba).
- **Abiertos del turno 5, todos de lógica → van a A2b**: la **alta A** (resolución de base del
  hook), `$(...)` en `Hide-Literals`, la cuarentena del `advance`, el `gh repo view` delante del
  fallback local, y las bajas restantes (heredocs sin enmascarar, `$base` sin verificar, cuarentena
  que sólo atrapa el JSON que lanza, exit code de `ls-files` fuera de `$measurable`,
  `git -C my\ dir push`, hash vacío permanente en `review-marker.ps1:195-198`).
- **Sin resolver**: la contradicción de medición del comentario `review-marker.ps1:37-38` (si un
  `pwsh` hijo con stdout redirigido hereda o no el 65001). El fix es correcto en las dos lecturas;
  lo que puede estar mal es el comentario que lo justifica. Hace falta una medición limpia.
- **Sigue abierto**: los 15 hallazgos de A1b; `copy-scaffold.ps1` pisa el `.gitignore` del destino;
  `core.autocrlf` con hashes mixtos en los manifests; el `.bootstrap-manifest.json` de la **raíz**
  sin resellar (AC de A7); el diff de `fix/review-loop-motor-invocable` nunca pasó por reviewer.

### Antes de tocar código

- **El `alignment-gate` frena el primer edit.** El paso 1 está cerrado (grill 11/8, PRD e issues
  aprobados 12/8): decilo y reintentá, **no ofrezcas grill**.
- **Esta sesión NO necesitó espejar ni regenerar manifests**: sólo se tocaron `tests/` y
  `docs/TESTING.md`, que no están sujetos a la regla del espejo. En cuanto A2b toque el hook o
  `review-marker.ps1`, vuelve a aplicar: editar la copia de `bootstrap-personal-project` (es a donde
  apuntan los tests), espejar con `Copy-Item` a las otras dos del scaffold **al final**, y replicar
  la lógica —no copiar el archivo— en la copia raíz del hook, que va en español. Después,
  `pwsh -NoProfile -File tools/gen-manifest.ps1 -SkillDir skills/<skill>`, una skill por vez.
- Editar skills acá **no tiene efecto** hasta `tools/sync-skills.ps1` (pendiente heredado del 1/8).
- **Los reviewers corren en SOLO LECTURA y experimentan en copias del scratchpad.**
- Correr las dos suites del review-loop encadenadas **tarda más de 2 min**: una por vez, timeout amplio.

### Preferencias del usuario (vigentes)

- **No commitear sin que lo pida.**
- **Nada de esto va a Zoho.**
- Quiere **impacto medido antes de cambiar el proceso**.
- Criterio: "el menor tiempo posible pero que la revisión sea completa y acertada".
- Prefiere **cortar y seguir en terminal nueva** antes que dejar crecer el contexto.

### Próximos pasos — en orden

1. **Abrir A2b — "resolución de base del hook"** como slice propio con cap de 5 turnos propio.
   Arreglar ahí la **alta A**: `.claude/hooks/review-loop-trigger.ps1:166` hace `exit 0` **antes**
   del gate del trailer cuando la base no resuelve, así que en un repo cuya base no se llama
   `main`/`master`/`develop` el hook queda mudo — y el bug se esconde justo en GitHub, donde
   `gh repo view` lo rescata. Fix preferido: **delegar la base al marcador** (`-Action base`), que ya
   resuelve esos repos con `Get-OtherRefs` + `merge-base --octopus`; elimina la asimetría en vez de
   duplicarla. Entran también `$(...)`, la cuarentena del `advance` y sacar el `gh repo view` de
   delante del fallback local.
2. **Commitear** cuando el usuario lo pida. Sugerido: `fix(review-loop): correcciones de los turnos
   2-5 sobre el disparo por cierre de slice`, con trailer `Slice-Close:` sólo si se considera cierre.
3. Después **A3** (`.scratch/review-cost-redesign/issues/03-corrida-de-review-incremental.md`), luego
   A4/A5, luego A6, y **A7 al final** (requiere presencia humana: deploya a `~/.claude/skills`).
4. **A1b** cuando se quiera; sigue con 15 hallazgos y el nudo de diseño sin resolver.
5. Track B (B1/B2) lo lleva el usuario en otra terminal; **vence el 10/9**.

### Supuestos declarados

- El marcador sigue en **`78b8a9b`**. **No se avanzó** esta sesión: la corrida de review del turno 5
  ya lo había avanzado, y lo que se escribió después (los fixes de arriba) es delta sin revisar —
  correctamente, porque el cap está agotado y nadie lo revisó.
- El techo se mide a mano contra la copia canónica ×1. Los fixes de esta sesión no se espejan, así
  que canónico y bruto coinciden: **69 líneas de lógica**.
- Los PRDs e issues viven en `.scratch/`, **gitignoreado**: existen sólo en el working tree.
  Señalado desde el 12/8, **sigue sin decidirse**.
- Los 4 mutantes se verificaron con el criterio correcto (una línea que **empieza** con `FAIL:`), no
  con el `-split 'FAIL:'` que daba falsos "MUERE".

---

# Session Handoff — 2026-08-14 parte 3 (TURNO 5 CORRIDO — el cap se agotó SIN cerrar limpio)

## ▶▶▶▶▶▶▶▶▶▶▶ ESTADO AL RETOMAR — el review-loop terminó por CAP, no por limpio

Rama **`feat/marcador-de-revision`**. Último commit sigue siendo **`e320510`** (A2). Encima siguen los
**26 archivos modificados sin commitear** (fixes de los turnos 1-4). **Esta sesión NO tocó una sola
línea de código**: corrió el turno 5, encontró 19 hallazgos y no aplicó ninguno (razón abajo).

```
e320510  feat(review-loop): disparo por cierre de slice declarado          <- A2
67ae410  fix(review-loop): correcciones del ciclo de revision sobre el marcador
326aee3  feat(review-loop): marcador de revision y turno incremental       <- A1
```

### ⚠️ Lo primero que hay que saber: el rango contiene SÓLO este handoff, y eso NO es "limpio"

```powershell
pwsh -NoProfile -File .claude/scripts/review-marker.ps1 -Action range   # 78b8a9b…, exit 0
git --no-pager diff --stat 78b8a9b                                     # sólo docs/SESSION_HANDOFF.md
```

El marcador se avanzó `2585e54` → **`78b8a9b`** al terminar la corrida de review (paso 3 del loop:
tres reviewers corrieron y devolvieron informe, así que corresponde avanzarlo). Quedó vacío en ese
momento; **lo único que entró después son las 262 líneas de prosa de este handoff**, que el reviewer
puede saltear: **cero líneas de lógica sin revisar**.

Que el rango no traiga código **no significa que el slice esté limpio**: hay **19 hallazgos abiertos,
2 de ellos altas**, y el código que los contiene ya fue leído. No cerrar el loop por eso.

**El cap de 5 turnos está AGOTADO.** Cualquier fix que se escriba de acá en adelante **no lo revisa
ningún turno**. Eso es el límite conocido del mecanismo y hay que decirlo al reportar.

### Qué hizo esta sesión

Turno 5 con 4 focos declarados (hook post-borrado del 3b, marcador, tests/`TESTING.md`, espejado).
**Corrieron 3 reviewers de 4**; el foco de espejado lo cubrió el agente principal con comandos de
comparación, no un subagente. La corrida costó **7 caídas por `529 Overloaded`** antes de que la API
se estabilizara — falla del servidor, no de los prompts. Los tres informes que llegaron son de
corridas completas, cada una con el repo verificado intacto al inicio y al final.

### 🔴 Las 2 ALTAS

**A) El hook queda mudo en un repo cuya base no se llama `main`/`master`/`develop`** —
`.claude/hooks/review-loop-trigger.ps1:157-167` ×4. La resolución de base sólo conoce `origin/HEAD`,
`gh repo view` y esos tres literales; si ninguno responde, `exit 0` en la línea 163 **antes** del gate
del trailer y del techo. Reproducido dos veces, independientemente:

```
repo con base 'trunk', rama feat/y, commit con "Slice-Close: la feature y"
  marcador -Action range  ->  5effd494…  exit 0     <- resuelve perfecto
  hook     git commit     ->  SILENCIO              <- pierde el cierre DECLARADO
  control: git branch -m trunk main -> DISPARA
```

Es el falso negativo mudo que este slice existe para eliminar, en el caso que el `CLAUDE.md` promete
soportar ("funciona en repos locales sin remoto"). Hay **asimetría entre las dos mitades del motor**:
el marcador SÍ resuelve ese repo (`Get-OtherRefs` + `merge-base --octopus`; sus comentarios nombran
`trunk`, `dev`, `release`), el hook no. Y el bug **se esconde justo en GitHub**, donde `gh repo view`
lo rescata. Fixes posibles, de mejor a peor: delegar la base al marcador (agregarle `-Action base`);
extender el fallback con `for-each-ref` como `Get-OtherRefs`; o —el más barato— cuando el trailer
está declarado y no resuelve base, disparar igual.

**B) El fixture del "costo aceptado" pinea sólo la mitad del bloque borrado** —
`docs/TESTING.md:112` + `tests/review-loop-trigger.tests.ps1:121-124`. El doc afirma que existe
"para que reintroducir el bloque no pase inadvertido", y no lo logra: el bloque borrado probaba
**primero** `git -C <ruta>` y sólo caía al `cd`; el fixture usa nada más `cd '$otro' && git push`.
**Mutante vivo verificado**: reintroducir *sólo* la rama `git -C` deja la **suite completa en verde**.
El otro fixture que menciona `-C` usa `git -C '$t' push` con `$t` = *este* repo, que resuelve al mismo
toplevel y no discrimina. Es la única defensa contra reintroducir la clase de código que el usuario
decidió borrar. **Fix**: el assert gemelo, que es literalmente el borrado con la polaridad invertida —
`$otro = New-Repo; $t = New-Repo; Fire $t "git -C '$otro' push"` → `Assert ($o -match "additionalContext")`.

### 🟠 Las 5 MEDIAS

| Dónde | Qué | Evidencia |
|---|---|---|
| hook `:158` | `gh repo view` es una **llamada de red en cada commit** cuando `origin/HEAD` no está seteado (lo normal en `git init` + `remote add`; sólo `clone` lo setea), y corre **antes** del fallback local que lo resolvería gratis | medido: ~700-1000 ms extra por commit |
| hook `:282,286` | La ventana de binarios de **8000 B no la fija ningún test** ni figura en el bloque de no-cubiertos. El único fixture pone el NUL en el offset 3 | revertir 8000 → 4096 sobrevive la suite entera |
| hook `:23` | La mitad "toda llamada a git" del **UTF-8 del hook** no tiene fixture (el marcador sí lo recibió). Ningún fixture de trigger usa ruta de repo no-ASCII | angostar el alcance al `ls-files` sobrevive. Si regresa: bajo `C:\Users\Martín\…` la red mide la rama entera en silencio |
| hook, `Hide-Literals` | **El hallazgo 19 (`$(...)`) YA TIENE REPRO** — ver abajo | dos reviewers convergen |
| `review-marker.ps1:264-271` | `advance` **pisa un estado ilegible** y destruye `marker:*` / `untracked:*` de las otras ramas y el dedupe del hook, **sin cuarentena**. El hook implementa el `.bad` para este mismo archivo: el marcador es la mitad asimétrica | repro corrido; este repo tiene claves de 4 ramas |

### 🟡 El hallazgo 19 dejó de estar "sin repro" — y es peor de lo que se creía

El handoff anterior lo dejó declarado sin acción por falta de repro ejecutable. Se encontró, y no es
sólo el falso positivo que se sospechaba: **también pierde disparadores reales**.

```bash
git commit -m "$(sed 's/"/x/' f)" && git push      # $isPush=False   <- push REAL perdido
echo "$(sed 's/"/x/' f)" && git commit -m cierre   # $isCommit=False <- cierre declarado perdido
git commit -m "wrote $(echo "git push") today"     # dispara salteando gate, frescura y techo
```

Mecanismo: una comilla **doble** dentro de comillas **simples** dentro de una sustitución `$(...)`
deja el total de dobles en número **impar**; el walker se desalinea y se traga el resto de la línea.
**Medición que acota la severidad a media**: los usos naturales (`date +"%F"`, `basename "$PWD"`,
`cat msg.txt`) tienen número **par**, se re-alinean solos y **no** pierden disparadores.

Opciones, con la recomendación en la primera:
1. **No modelar `$()`**: si el comando contiene `$(` o backtick, calcular las banderas también sobre
   el comando crudo y quedarse con el **OR**. Convierte todo falso negativo en falso positivo (la
   dirección que el proyecto ya declaró segura), ~2 líneas, sin walker nuevo.
2. Modelar `$(...)` con paréntesis balanceados antes de caminar los literales. Correcto, pero es
   volver al pozo del parseo.
3. Dejarlo declarado en `docs/TESTING.md`, ahora **con** el repro, y arreglarlo en slice propio.

### ⚪ Media-bajas (2) y bajas (10)

- **Media-baja** — `$base` nunca se verifica que resuelva (`--base $(git config x)` inyecta `$(git`
  en el mensaje; `--base no-such-branch` pasa tal cual).
- **Media-baja** — **los heredocs no se enmascaran**, aunque el paso 6 los vende como forma soportada:
  `git commit -F- <<'EOF'` con "git push" en el cuerpo prende `$isPush` y saltea gate, frescura y
  techo. Reproducido. Dirección segura.
- Cuarentena que sólo atrapa el JSON que **lanza excepción**: un `[1,2,3]` válido no lanza y el paso 7
  escribe de vuelta propiedades de reflexión de .NET (`Length`, `IsReadOnly`, `SyncRoot`…).
- Exit code de `ls-files` fuera de `$measurable` (la mitad trackeada está protegida, la untracked no).
- `git -C my\ dir push` (espacio escapado sin comillas) pliega a `git dir push` y nunca dispara.
- `tests/review-marker.tests.ps1:491` — el `Assert ($hu.Count -eq 1)` **sigue sin morder** pese al
  arreglo del turno 4: quedó el `Count` encima de la misma variable, y `@($null).Count` vale 1.
  Imprime `ok: … fichó un untracked (1)` justo cuando no se fichó nada.
- Setup muerto en los dos fixtures nuevos de `--base` (`:447`, `:454`): crean `branch develop` pero
  el hook nunca valida que la base exista; corridos sin la rama, los asserts pasan igual.
- `docs/TESTING.md:131` desfasada de `:111` (dos listas del mismo hecho que discrepan sobre `*.lock`).
- `docs/TESTING.md:126` subdeclara `$(...)`: la línea 108 se lee como "el bypass del gate por texto
  entrecomillado está cerrado", y no lo está.
- `review-marker.ps1:195-198` — hash vacío permanente para archivos ilegibles (symlink roto, o pwsh
  en Linux): la entrada `path|` es estable y `Test-NewUntracked` nunca dispara para ediciones
  posteriores. No reproducible en Windows.
- `tests/review-marker.tests.ps1:496-527` — el caso de ruta no-ASCII invoca el marcador **en-proceso**
  (`& '$marker'`), pero producción lo invoca como `pwsh -NoProfile -File`. Y falta el caso
  5.1 + no-ASCII + code page OEM, que son las máquinas destino del scaffold. Las tres variantes se
  probaron a mano y **pasan**: es un hueco de cobertura, no un defecto.

### ⚠️ Contradicción de medición, SIN RESOLVER

`review-marker.ps1:37-38` afirma que "un `pwsh` hijo con stdout redirigido no hereda el 65001 del
padre y reporta OEM". El turno 4 lo midió así; el reviewer del turno 5 midió **lo contrario**
(`parent=65001 → child=65001`) y atribuye el bug a que la consola default de Windows ya es OEM.
**El fix es correcto en las dos lecturas**; lo que está mal es el comentario que lo justifica.
Consecuencia práctica: si el segundo tiene razón, `chcp 65001` en la terminal **sí** es una mitigación
válida, y el comentario induce a creer que no. No se resolvió: hace falta una medición limpia.

### Por qué NO se aplicó ningún fix (decisión declarada)

El paso 5 del loop exige un test en RED antes de cada fix, y el cap ya está agotado: **lo que se
escriba ahora no lo revisa nadie**. Dos hallazgos tocan la zona que produjo 8 altas en 3 turnos, sobre
la que el usuario ya tomó una decisión de política (borrar antes que parchar). Escribir esos fixes sin
revisor es el modo de falla que el mecanismo existe para prevenir, así que se elevó a decisión del
usuario. El usuario respondió: **actualizar el handoff y seguir en terminal nueva** con el criterio
del agente.

Los hallazgos se parten limpio en dos grupos por riesgo:

- **Seguros sin revisor** (tests y prosa: agregan red, no cambian producción): el fixture gemelo
  `git -C` (**cierra la alta B**), el fixture de la ventana de 8000 B, el fixture de UTF-8 del hook,
  el `$hu.Count`, el setup muerto de `--base`, y las tres correcciones de `docs/TESTING.md`.
- **Cambian lógica, piden turno propio**: la resolución de base (**alta A**), `$(...)` en
  `Hide-Literals`, la cuarentena del `advance`, y el `gh repo view`.

### Lo que se verificó LIMPIO

- **Espejado byte-idéntico** en las 3 copias del scaffold para hook, `review-marker.ps1`,
  `review-loop.md` y `SKILL.md`. La copia raíz del hook difiere sólo en 3 comentarios traducidos y el
  `$msg` — el drift deliberado.
- **Los 3 `.bootstrap-manifest.json` están al día** (hashes correctos para los 5 archivos tocados en
  las 3 skills). Ojo al verificarlo: `gen-manifest.ps1` usa `Get-FileHash` **crudo**, sin normalizar
  CRLF; normalizar da falsos "desalineado".
- **Ninguna prosa quedó mintiendo** sobre el paso 3b borrado, y no quedaron rastros de las variables
  eliminadas (`Read-Path`, `$trg`, `$here`/`$there`) en ninguna copia ni en los tests.
- El costo aceptado está declarado en el encabezado del hook ×4, en `docs/TESTING.md:112` y en el
  fixture.
- `$stateWritable` saltea **sólo** la escritura (verificado con el `.bad` bloqueado por
  `FileShare.None`). Bordes de la frescura medidos con `GIT_COMMITTER_DATE` (−1700 s dispara /
  −1801 s no / futuro rechazado por `Abs()`); `--amend` refresca `%ct`. La ventana de 8000 B
  **coincide con git** (un NUL en el byte 6000 es binario para `--numstat`). Las 16 llamadas a git del
  marcador están cubiertas por el forzado de encoding, y `[Console]::OutputEncoding` +
  `[Text.UTF8Encoding]::new($false)` son la propiedad y el constructor correctos.
- Sin backtracking catastrófico: el regex de plegado sobre 100 KB sin espacios tarda 12 ms;
  `Hide-Literals` es lineal (300 ms sobre 200 KB).
- El delta **NO removió** nada del marcador: al contrario, elimina un peligro latente — un nombre de
  rama no-ASCII decodificado como mojibake rompía las exclusiones `$_ -ne $branch` de
  `Get-NamedBases`/`Get-OtherRefs` y podía dejar que la propia rama ganara el octopus.

### Tests

- **`tests/review-loop-trigger.tests.ps1`: 57 asserts verdes.**
  **`tests/review-marker.tests.ps1`: 81 asserts verdes.** Corridos de verdad esta sesión, desde una
  copia del scratchpad, una suite por vez.
- **La suite completa (12 archivos) NO se corrió esta sesión**, pero **no se tocó código**, así que el
  12/12 verde del handoff anterior sigue valiendo.
- **13 mutaciones verificadas: 10 mueren, 3 sobreviven** (ventana de 8000, alcance del UTF-8 del hook,
  atribución por `git -C`) — son las tres medias/alta de arriba.
- **Límite declarado y verificado como honesto**: colapsar el `$end` de la comilla sin cerrar a
  `[Math]::Min($j, $s.Length - 1)` sobrevive la suite, exactamente como `docs/TESTING.md:125` declara.
- Correr las dos suites del review-loop encadenadas **tarda más de 2 min**: una por vez, timeout amplio.

### Antes de tocar código

- **El `alignment-gate` frena el primer edit.** El paso 1 está cerrado (grill 11/8, PRD e issues
  aprobados 12/8): decilo y reintentá, **no ofrezcas grill**.
- **Regla del espejo**: hook, `review-marker.ps1`, `review-loop.md` y `review-loop/SKILL.md` van a las
  **4 copias**. Editar la de `bootstrap-personal-project` (es a donde apuntan los tests) y espejar con
  `Copy-Item` a las otras dos del scaffold. El `review-marker.ps1` de la raíz es **byte-idéntico**, se
  copia igual. **El hook de la raíz va en español**: replicar la lógica, no copiar el archivo.
- **Espejar SIEMPRE al final**, después del último edit del canónico.
- **Manifests generados**: `pwsh -NoProfile -File tools/gen-manifest.ps1 -SkillDir skills/<skill>`, una
  skill por vez, antes de commitear. Están al día al estado actual.
- Editar skills acá **no tiene efecto** hasta `tools/sync-skills.ps1` (pendiente heredado del 1/8).
- **Los reviewers corren en SOLO LECTURA y experimentan en copias del scratchpad.** Los tres de esta
  sesión verificaron `git status` idéntico al inicio y al final. Mantener esa instrucción: la
  contaminación entre paralelos ya arruinó una corrida.
- Repos temporales de prueba (`$TEMP/rlt-*`, `rm-test-*`, `t5*`) borrados; quedaron 0.

### Bugs

- **Arreglados**: los 11 del turno 2, los 11 del turno 3 y los 18 del turno 4.
- **Abiertos, nuevos**: los **19 del turno 5** (arriba), 2 altas + 5 medias + 2 media-bajas + 10 bajas.
- **Sigue abierto**: los 15 hallazgos de A1b.
- **Sigue abierto**: `copy-scaffold.ps1` pisa el `.gitignore` del proyecto destino.
- **Sigue abierto**: `core.autocrlf` con hashes mixtos en los manifests.
- **Sigue abierto**: el `.bootstrap-manifest.json` de la **raíz** no se reselló (AC de A7).
- **Sigue abierto**: el diff de `fix/review-loop-motor-invocable` nunca pasó por reviewer.

### Preferencias del usuario (vigentes)

- **No commitear sin que lo pida.**
- **Nada de esto va a Zoho.**
- Quiere **impacto medido antes de cambiar el proceso**.
- Criterio: "el menor tiempo posible pero que la revisión sea completa y acertada".
- Prefiere **cortar y seguir en terminal nueva** antes que dejar crecer el contexto.

### Próximos pasos — el plan recomendado, en orden

1. **Aplicar el grupo seguro** (tests y prosa, 7 hallazgos). Cierra la **alta B** y no necesita
   revisor porque no cambia producción. Empezar por el **fixture gemelo `git -C`**, que hoy es la
   única defensa contra reintroducir el bloque borrado y no muerde. Cada fixture nuevo, verificado en
   RED antes (mutar producción en una copia del scratchpad, ver el assert rojo, restaurar).
2. **Abrir A2b — "resolución de base del hook"** como slice propio con su propio cap de 5 turnos, y
   arreglar ahí la **alta A**. Es la única que deja el mecanismo muerto en un repo real, y hoy ningún
   test la detecta. Fix preferido: delegar la base al marcador (`-Action base`), que ya tiene la
   lógica correcta — elimina la asimetría en vez de duplicarla.
3. En A2b entran también las otras tres de lógica: `$(...)` en `Hide-Literals` (opción 1 de arriba),
   la cuarentena del `advance`, y sacar el `gh repo view` de delante del fallback local.
4. **Commitear** cuando el usuario lo pida. Sugerido: `fix(review-loop): correcciones de los turnos
   2-5 sobre el disparo por cierre de slice`, con trailer `Slice-Close:` sólo si se considera cierre.
5. Después **A3** (`.scratch/review-cost-redesign/issues/03-corrida-de-review-incremental.md`), luego
   A4/A5, luego A6, y **A7 al final** (requiere presencia humana: deploya a `~/.claude/skills`).
6. **A1b** cuando se quiera; sigue con 15 hallazgos y el nudo de diseño sin resolver.
7. Track B (B1/B2) lo lleva el usuario en otra terminal; **vence el 10/9**.

### Supuestos declarados

- El marcador está en **`78b8a9b`** y el rango sale **vacío con exit 0**. **Eso NO es "el loop cerró
  limpio"**: el cap se agotó con 19 hallazgos abiertos.
- El techo de ~400 líneas se mide a mano contra la copia canónica ×1. Este rango midió **344**
  canónicas (bruto 824/398 con el espejado ×4 y los handoffs), bajo el techo. La regla del `CLAUDE.md`
  no exime explícitamente las copias espejadas, así que una lectura literal pondría el bruto encima.
- Los PRDs e issues viven en `.scratch/`, **gitignoreado**: existen sólo en el working tree.
  Señalado desde el 12/8, **sigue sin decidirse**.
- El foco de espejado del turno 5 lo cubrió el agente principal con comandos de comparación, no un
  subagente dedicado (el 4º reviewer murió por 529 y no se relanzó). Lo verificado está listado arriba.
- Los 19 hallazgos vienen con repro ejecutable o mutante verificado, **pero ninguno pasó por un pase
  de confianza formal con scorers**; la alta A se verificó dos veces de forma independiente.

---

# Session Handoff — 2026-08-14 parte 2 (los 19 hallazgos del turno 4, resueltos; falta el TURNO 5)

## ▶▶▶▶▶▶▶▶▶▶ ESTADO AL RETOMAR — la tarea es el turno 5 del `/review-loop`, y es el ÚLTIMO del cap

Rama **`feat/marcador-de-revision`**. Último commit sigue siendo **`e320510`** (A2). Encima hay
**26 archivos modificados sin commitear**: los fixes de los turnos 1, 2, 3 **y 4** del `/review-loop`.
Suite completa **12/12 verde**, corrida entera al cierre de esta sesión.

```
e320510  feat(review-loop): disparo por cierre de slice declarado          <- A2
67ae410  fix(review-loop): correcciones del ciclo de revision sobre el marcador
326aee3  feat(review-loop): marcador de revision y turno incremental       <- A1
```

**No hay ninguna decisión pendiente del usuario.** La que bloqueaba (paso 3b del hook) se tomó y se
ejecutó — ver abajo.

### Lo primero: el turno 5

```powershell
pwsh -NoProfile -File .claude/scripts/review-marker.ps1 -Action range   # da 2585e54..., exit 0
```

El marcador quedó en **`2585e54`** a propósito y **no hay que avanzarlo antes de revisar**: el rango
es exactamente lo que esta sesión escribió, que es lo que el turno 5 tiene que leer.

**Ojo con el ruido del rango**: adentro entran también ~380 líneas de `docs/SESSION_HANDOFF.md` (el
handoff anterior + éste), escritas después de que el marcador avanzara. Es prosa de handoff, no
lógica: el reviewer la puede saltear. La lógica real del rango son **341 líneas canónicas ×1**
(hook 136, tests 157, marcador 32, `docs/TESTING.md` 16), bajo el techo de ~400. El bruto con el
espejado ×4 da 1057.

**El turno 5 es el último del cap.** Al cerrarlo hay que reportar el estado del cap explícitamente:
sus propios fixes, si los hay, no los va a revisar nadie. Es el límite conocido del mecanismo.

### La decisión que se tomó y se ejecutó: se borró el paso 3b

El usuario eligió la **opción 1: borrar el bloque de atribución por parseo entero** (~45 líneas ×4).
Se ejecutó. Lo que queda protegiendo al hook son señales **observables**, no parseo:

- **frescura del HEAD** (`git log -1 --format=%ct`, ventana de 1800 s con `Abs()`) para los commits;
- **dedupe por SHA** en `review-loop-state.json` para todo lo demás.

**Costo aceptado y declarado**: un `git push` corrido en OTRO repo desde una sesión abierta acá
dispara un review-loop de más. Hay un **fixture que lo fija** (`review-loop-trigger.tests.ps1`), para
que reintroducir el bloque no pase inadvertido: si alguien lo vuelve a agregar, ese assert se pone
rojo y hay que discutirlo.

**Ojo — el borrado NO se llevó los 7 hallazgos del grupo B, se llevó 5.** Los otros dos vivían en
`Hide-Literals`, que el **paso 2** sigue necesitando para el gate del trailer. Uno se arregló
(`'\''`), el otro quedó declarado sin acción (ver abajo).

### Los 18 hallazgos cerrados, cada uno con RED verificado antes del fix

| Sev | Dónde | Qué era | Fix |
|---|---|---|---|
| **Alta** | `review-marker.ps1` ×4 | `rev-parse --show-toplevel` y `--git-dir` leídos fuera del ajuste de encoding: bajo ruta no-ASCII las **tres** acciones daban exit 2 en silencio, `advance` no avanzaba nunca y el loop revisaba la rama entera para siempre | UTF-8 forzado **una sola vez** al tope del script (siempre corre como proceso hijo efímero). El save/restore local de `Get-UntrackedList` quedó redundante y se borró |
| **Alta ×5** | hook ×4 | todo el parser del 3b: `$trg` tomaba el primer disparador, el salto de línea no separaba segmentos, `(?i)` leía `-c` como `-C`, el regex del `cd` no cubría subshell/`pushd`, `--git-dir=` no atribuía | **borrado** (decisión del usuario) |
| **Alta** | hook ×4 | `Hide-Literals` con `'\''` (el idioma de bash para un apóstrofe): la comilla suelta se tomaba por apertura, el resto del mensaje quedaba expuesto y `git push` en el texto prendía `$isPush`, salteando el gate del trailer, la frescura **y** el techo | la barra invertida **fuera** de literal escapa al carácter siguiente |
| Media-Alta | hook ×4 | el guard de cuarentena era **código muerto**: con `SilentlyContinue` el `Move-Item` no lanza y el `catch { exit 0 }` nunca corría. Y su diseño era incorrecto: suprimir el disparo por una falla de I/O es el lado peligroso | `-ErrorAction Stop` + flag `$stateWritable`, que saltea la **escritura** del paso 7 y sigue hasta el paso 8 |
| Media | hook ×4 | `--base` leído del `$cmd` crudo: `--base "develop"` entrecomillado se ignoraba, y un `--base` citado en `--title` ganaba por ser el primer match → rango contra una rama inexistente | la bandera se ubica sobre `$scan` y el valor se lee de `$cmd` **por índice** (por eso `Hide-Literals` sigue preservando la longitud) |
| Media | `review-marker.tests.ps1` | el guard del `advance` desde subdirectorio no guardaba: `@($null).Count` vale **1**. Y el `ReadAllText` iba sin `Test-Path` con `$ErrorActionPreference = "Stop"` | se mira la **propiedad** del JSON, no el Count; lectura afuera del Assert con `Test-Path` |
| Media | `review-loop-trigger.tests.ps1` | el fixture del untracked acentuado no verificaba que la code page se hubiera forzado (el `catch {}` se tragaba la falla) | `Assert` de que `[Console]::OutputEncoding.CodePage -eq 850` |
| Media | `review-loop-trigger.tests.ps1` | el fixture del `git -C` citado no distinguía nada | se fue junto con el 3b |
| Baja | hook ×4 | ventana de detección de binarios de 4096 B; git usa ~8000, así que un NUL más allá contaba como texto e inflaba el techo | 8000 B, y el comentario dejó de mentir |
| Baja | hook ×4 | off-by-one en la rama de comilla sin cerrar (`Min($j, len-1)` dejaba el último carácter sin enmascarar) | los dos finales (cerrado / sin cerrar) quedaron separados explícitamente |
| Baja | `review-loop-trigger.tests.ps1` | setup muerto en el fixture de la rama huérfana (la primera copia del marcador la borraba el `reset --hard`) | se copia **después** del `--orphan` |
| Baja | `docs/TESTING.md` | decía "los tres casos" y enumeraba dos; faltaba `*.lock`; describía mal el agujero de `--git-dir`/`--work-tree`; la rama de comilla sin cerrar no estaba declarada | corregidos, más los bullets nuevos |

### 🟡 El hallazgo 19, declarado SIN ACCIÓN

`Hide-Literals` y la sustitución de comandos **`$(...)`**: bash reinicia el contexto de comillas
adentro y la función no lo modela. El hallazgo del turno 4 lo agrupaba con `'\''`, pero **el repro
ejecutable era sólo del segundo**. No se encontró un comando que reproduzca el de `$(...)`, así que
**no se tocó el código**: está anotado como límite conocido en `docs/TESTING.md`, no como cubierto.
Si el turno 5 encuentra el repro, ahí sí vale arreglarlo.

### Decisiones tomadas esta sesión

| # | Decisión | Quién |
|---|---|---|
| 1 | Borrar el paso 3b entero en vez de seguir parchándolo (3 turnos seguidos con altas en la misma zona; sus fallas eran falsos negativos mudos) | **usuario** |
| 2 | El costo del borrado (un push ajeno dispara acá) se fija con un **fixture propio**, no sólo con un comentario | agente |
| 3 | El encoding se fuerza **una vez al tope** de cada script en vez de alrededor de cada llamada a git: son procesos hijos efímeros y el patrón duplicado ya había dejado dos llamadas afuera | agente |
| 4 | La cuarentena fallida saltea la **escritura**, no el disparo — perder un cierre declarado es peor que perder el dedupe | agente |
| 5 | `$(...)` no se toca sin repro: cambiar código sin evidencia contradice el criterio de impacto medido del usuario | agente, declarado |

### Bugs

- **Arreglados**: los 11 del turno 2, los 11 del turno 3 y los **18 del turno 4** (tabla de arriba).
- **Abierto, declarado**: el hallazgo 19 (`$(...)` en `Hide-Literals`), sin repro.
- **Sigue abierto**: los 15 hallazgos de A1b.
- **Sigue abierto**: la escritura del estado no es atómica (declarado en `docs/TESTING.md`).
- **Sigue abierto**: `copy-scaffold.ps1` pisa el `.gitignore` del proyecto destino.
- **Sigue abierto**: `core.autocrlf` con hashes mixtos en los manifests.
- **Sigue abierto**: el `.bootstrap-manifest.json` de la **raíz** no se reselló (AC de A7). Los 3
  manifests de las skills SÍ se regeneraron esta sesión (`tools/gen-manifest.ps1`).
- **Sigue abierto**: el diff de `fix/review-loop-motor-invocable` nunca pasó por reviewer.

### Tests

- **Suite completa 12/12 verde**. Runner por archivo: `pwsh -NoProfile -File tests/<archivo>.tests.ps1`.
  Correr las dos suites del review-loop encadenadas **tarda más de 2 min**: correrlas por separado o
  con timeout amplio.
- `tests/review-loop-trigger.tests.ps1`: se agregaron 5 asserts (apóstrofe a la bash, `--base` ×2,
  cuarentena bloqueada ×2), se borraron los 5 del 3b y se agregó el del costo aceptado.
- `tests/review-marker.tests.ps1`: caso nuevo de **ruta no-ASCII** con code page 850 forzada dentro
  del `pwsh` hijo, con **control positivo** de que la code page se forzó de verdad.
- **RED verificado antes de cada fix.** El del marcador reprodujo exactamente el bug: `exit 2`.
- **Trampa nueva**: `pwsh -Command "& script"` devuelve **su propio** código (1 ante cualquier error),
  no el del script. Sin `; exit $LASTEXITCODE` al final, un assert de exit code no distingue el
  `exit 2` del script de un fallo del host.

### Antes de tocar código

- **El `alignment-gate` frena el primer edit.** El paso 1 está cerrado (grill 11/8, PRD e issues
  aprobados 12/8): decilo y reintentá, **no ofrezcas grill**.
- **Regla del espejo**: el hook, `review-marker.ps1`, `review-loop.md`, `review-loop/SKILL.md` van a
  las **4 copias**. Editar la de `bootstrap-personal-project` (es a donde apuntan los tests) y espejar
  con `Copy-Item` a las otras dos del scaffold. **El `review-marker.ps1` de la raíz está en inglés y
  es byte-idéntico**: se copia igual que las otras. **El hook de la raíz va en español**: replicar la
  lógica, no copiar el archivo. `tests/review-loop-incremental.tests.ps1` compara la lógica de las 4 y
  `mirror.tests.ps1` la byte-identidad de las 3 del scaffold.
- **Espejar SIEMPRE al final**, después del último edit del canónico: esta sesión un edit de comentario
  posterior al `Copy-Item` puso `mirror.tests.ps1` en rojo.
- **Manifests generados**: `pwsh -NoProfile -File tools/gen-manifest.ps1 -SkillDir skills/<skill>`, una
  skill por vez, antes de commitear. Ya están regenerados al estado actual.
- Editar skills acá **no tiene efecto** hasta `tools/sync-skills.ps1` (pendiente heredado del 1/8).
- Los repos temporales de prueba (`$TEMP/rlt-*`, `rm-test-*`) se borran al terminar. Al cierre de esta
  sesión quedaron 0.

### Preferencias del usuario (vigentes)

- **No commitear sin que lo pida.**
- **Nada de esto va a Zoho.**
- Quiere **impacto medido antes de cambiar el proceso**.
- Criterio: "el menor tiempo posible pero que la revisión sea completa y acertada".
- Prefiere **cortar y seguir en terminal nueva** antes que dejar crecer el contexto. Fue el motivo de
  este handoff: pidió explícitamente correr el turno 5 del loop **en la terminal nueva**.

### Próximos pasos

1. **Turno 5 del `/review-loop`** sobre el rango del marcador (`2585e54...`). Es el **último del cap**;
   al cerrarlo, reportar el estado del cap y qué queda sin revisar.
2. **Commitear** cuando el usuario lo pida (sugerido: `fix(review-loop): correcciones de los turnos
   2-5 sobre el disparo por cierre de slice`, con trailer `Slice-Close:` sólo si se considera cierre
   de slice).
3. Después **A3** (`.scratch/review-cost-redesign/issues/03-corrida-de-review-incremental.md`), luego
   A4/A5, luego A6, y **A7 al final** (requiere presencia humana: deploya a `~/.claude/skills`).
4. **A1b** cuando se quiera; sigue con 15 hallazgos y el nudo de diseño sin resolver.
5. Track B (B1/B2) lo lleva el usuario en otra terminal; **vence el 10/9**.

### Supuestos declarados

- El marcador está en `2585e54` y **no se avanzó**: el rango del turno 5 es exactamente lo que esta
  sesión escribió, más la prosa de los dos handoffs.
- Los PRDs e issues viven en `.scratch/`, **gitignoreado**: existen sólo en el working tree.
  Señalado desde el 12/8, **sigue sin decidirse**.
- El techo de ~400 líneas se mide a mano contra la copia canónica ×1. Este rango mide **341**
  canónicas, bajo el techo. La regla del `CLAUDE.md` no exime explícitamente las copias espejadas,
  así que una lectura literal pondría el bruto (1057) por encima.
- Los 18 fixes tienen RED verificado, pero **ningún reviewer los leyó todavía**: eso es el turno 5.

---

# Session Handoff — 2026-08-14 (turnos 2 y 3 del review-loop aplicados; turno 4 REVISADO SIN FIXES)

## ▶▶▶▶▶▶▶▶▶ ESTADO AL RETOMAR — hay UNA decisión del usuario pendiente antes de codear

Rama **`feat/marcador-de-revision`**. Último commit sigue siendo **`e320510`** (A2). Encima hay
**26 archivos modificados sin commitear**: los fixes de los turnos 1, 2 y 3 del `/review-loop`.
Suite completa **12/12 verde** (corrida entera al cierre del turno 3; después no se tocó código).

```
e320510  feat(review-loop): disparo por cierre de slice declarado          <- A2
67ae410  fix(review-loop): correcciones del ciclo de revision sobre el marcador
326aee3  feat(review-loop): marcador de revision y turno incremental       <- A1
```

### ⚠️ Lo primero: el marcador está avanzado y el rango sale VACÍO — eso NO es "limpio"

```powershell
pwsh -NoProfile -File .claude/scripts/review-marker.ps1 -Action range   # da vacío, exit 0
```

El marcador quedó en **`2585e54`**, avanzado después de la corrida de review del turno 4 y **antes**
de aplicar sus fixes (es el paso 3 del loop). Como los fixes del turno 4 **todavía no se escribieron**,
el rango está vacío. **No cerrar el loop por eso.** En cuanto se escriban los fixes, el rango pasa a
ser exactamente esos fixes y el turno 5 los revisa.

### ⚠️ La decisión pendiente (bloquea los fixes del parser, no los demás)

Se le preguntó al usuario y **cortó la sesión antes de responder**. Hay que volver a preguntarle.

El **paso 3b del hook** (`.claude/hooks/review-loop-trigger.ps1`) averigua si el comando de git corrió
en **otro repo**, parseando la línea de comando de bash con regex. Medición de los tres turnos:

| Turno | Altas en ese parser |
|---|---|
| 2 | 1 — `$isPush` evaluado sobre el comando crudo (el texto del `-m` prendía la bandera) |
| 3 | 3 — comillas escapadas `\"`, apóstrofes, y el 3b que quedó sin migrar a `$scan` |
| 4 | 4 — `$trg` toma el primer disparador, el salto de línea no separa segmentos, `(?i)` lee `-c` como `-C`, y `Hide-Literals` se rompe con `'\''` y `$(...)` |

Dato que inclina la balanza: **ese bloque existe sólo para evitar disparar de más**, pero sus fallas
son **falsos negativos** (pierde cierres declarados en silencio), que es la dirección peligrosa.

Las tres opciones que se le plantearon, con la recomendación puesta en la primera:

1. **Borrar el bloque 3b entero** (~60 líneas ×4 copias). Los commits siguen protegidos por la
   frescura del HEAD (`git log -1 --format=%ct`) y el dedupe por SHA, que son señales **observables**
   y no parseo. Costo: un `git push` hecho en otro repo desde una sesión abierta acá dispararía un
   review-loop de más. Elimina 5 de las 8 altas y la clase de bug entera.
   **Ojo**: `Hide-Literals` **no** se puede borrar — el paso 2 lo necesita para que un mensaje de
   commit que diga "git push" no saltee la puerta del trailer. Pero se simplifica mucho: sin la
   atribución ya no hace falta preservar la longitud ni recuperar rutas por índice.
2. **Señal observable**: para push, verificar `git rev-parse @{u}` contra HEAD. No parsea nada, pero
   no funciona en repos locales sin remote, que el scaffold soporta hoy.
3. **Seguir parchando** el parser en el turno 5 (último del cap).

### Qué se hizo esta sesión

**Turno 2 del `/review-loop`** (5 focos: bugs, reglas, historia, contratos, tests) — 18 hallazgos,
11 arreglados. **Turno 3** (4 focos) — 15 hallazgos, 11 arreglados. **Turno 4** (3 focos: parser,
conteo/estado, tests/docs) — 19 hallazgos, **0 arreglados** (es lo que queda por hacer).

**Arreglado en el turno 2** (cada uno con RED verificado antes del fix):

| Sev | Qué era | Fix |
|---|---|---|
| Alta | `$isPush` se evaluaba sobre el comando crudo, que incluye el texto del `-m`: un commit cuyo mensaje mencionaba "git push" salteaba el gate del trailer, la frescura **y** el techo | matchear sobre el comando normalizado |
| Alta | `-- .` es pathspec relativo al cwd → desde un subdirectorio el techo medía sólo ese subárbol | `git -C $root` |
| Alta | `ls-files` relativo al cwd + `Join-Path $root` → desde un subdirectorio no contaba ningún untracked | `git -C $root` |
| Media | el conteo de untracked era absoluto e ignoraba la huella `untracked:<rama>` del marcador | descuenta los que el marcador ya cubrió |
| Media | las exclusiones se aplicaban sólo a la mitad trackeada | `$skipPat` compartido; se sumaron `pnpm-lock.yaml`, `bun.lockb`, `go.sum` |
| Media | `Get-Content` leía binarios enteros (4,9 s medidos con 12 MB) en cada commit | se saltean binarios |
| Media | la detección de `cd` era ciega al orden | el `cd` sólo cuenta si precede al git |
| Media | `git -C <repo> push` no matcheaba nada | se pliegan las opciones globales de git |
| Media | 5 piezas sin test (mutantes vivos): `Abs()`, borde inferior del techo, guard `$here/$there`, `.bad` sin control positivo | fixture para cada una |
| Media | `Code()` corta en `$msg =`: el bloque de emisión de la copia raíz no lo cubría nadie | asserts ×4 + chequeo de sintaxis con el parser de PowerShell |
| Baja | `README.md` describía el disparo viejo; `TESTING.md` documentaba 7 comportamientos sobre 25 asserts | corregidos |

**Arreglado en el turno 3** (las 4 primeras eran fixes rotos del turno 2):

| Sev | Qué era | Fix |
|---|---|---|
| Alta | el blanqueo de literales por regex fallaba con `\"` (volvía a saltear el gate) y con apóstrofes (`-m "don't" && git push` se tragaba un push real) | `Hide-Literals`, que recorre los literales respetando el escape y **preserva la longitud** |
| Alta | el paso 3b había quedado leyendo `$cmd` crudo y sin guard de posición para `-C` | lee `$scan`, acotado al **segmento** del disparador, con `Read-Path` recuperando por índice |
| Alta | `$seen` comparaba sólo el path: un untracked que **creció** desde el marcador era invisible | se compara la entrada entera `path\|sha256`, igual que `Test-NewUntracked` |
| Alta | untracked con nombre no-ASCII contaban **0**: faltaba forzar `[Console]::OutputEncoding` | se fuerza UTF-8 alrededor del `ls-files`, como ya hacía el marcador |
| Media | exit 2 del marcador: el fallback `<base>...HEAD` falla con `fatal: no merge base` y el conteo daba 0 | `$measurable`; si el conteo no es confiable, dispara |
| Media | el `$msg` de la copia raíz se podía reescribir para ordenar `main...HEAD` con las 3 suites verdes | assert anclado al bloque del mensaje en las 4 copias |
| Media | el marcador fichaba las huellas relativas al cwd; el hook las lee relativas a la raíz | `review-marker.ps1` normaliza `$dir` al toplevel |
| Media | huella usada aunque `git gc` hubiera podado el marcador | se valida con `cat-file -e` antes de confiar en ella |
| Baja | handle sin `finally`; `--git-dir=x` sin plegar; `-split '\|'` por el primer pipe | corregidos |

### 🔴 Los 19 hallazgos del turno 4 — SIN ARREGLAR, todos reproducidos en vivo

**Grupo A — independientes de la decisión, se pueden arreglar ya:**

| Sev | Dónde | Qué |
|---|---|---|
| **Alta** | `.claude/scripts/review-marker.ps1:45` ×4 | **Regresión del turno 3.** El `$top = git rev-parse --show-toplevel` quedó FUERA del ajuste de `[Console]::OutputEncoding` que el propio archivo aplica a su `ls-files`. En un repo con ruta no-ASCII (`C:\Users\Martín\…`) `$dir` queda mojibake y el marcador da **exit 2 en las tres acciones**: `advance` nunca avanza y el loop revisa la rama entera para siempre, en silencio. Medido: un `pwsh` hijo con stdout redirigido reporta cp=850 aunque el padre esté en 65001 — que es exactamente cómo el hook invoca al marcador. Adyacente: `review-marker.ps1:38` (`--git-dir`) tiene la misma exposición y alimenta `$statePath` |
| Media-Alta | `.claude/hooks/review-loop-trigger.ps1:94` ×4 | El guard de cuarentena escrito en el turno 3 es **código muerto**: con `$ErrorActionPreference = "SilentlyContinue"` el `Move-Item` no lanza excepción terminante y el `catch { exit 0 }` nunca corre. Fix: `-ErrorAction Stop`. **Y el fix del turno 3 estaba mal pensado**: suprimir el disparo por una falla de I/O contradice "disparar de más es seguro". Lo correcto es un flag `$stateWritable` que saltee la **escritura** del paso 7 y siga hasta el paso 8 |
| Media | hook `:145` | `--base` se lee del `$cmd` **crudo**: `--base "develop"` entrecomillado se ignora (cae al fallback), y un `--base` citado en `--title` gana por ser el primer match → el mensaje inyectado manda a un rango contra una rama inexistente. Es el único renglón que rompe la regla que el comentario del paso 2 declara |
| Baja | hook `:287-293` | La ventana de detección de binarios es de 4096 B y git usa ~8000: un NUL entre medio cuenta como texto. Cuenta de más (molesto). El comentario afirma consistencia con `--numstat` y no la hay |
| Media | `tests/review-marker.tests.ps1:481` | El guard positivo del `advance` desde subdirectorio **no guarda**: `@($st."untracked:feat/x").Count -eq 1` da 1 también cuando la clave no existe (`@($null).Count` = 1). Además el `ReadAllText` va sin `Test-Path` y con `$ErrorActionPreference = "Stop"` abortaría la corrida |
| Media | `tests/review-loop-trigger.tests.ps1:422` | El fixture del untracked acentuado no verifica que la code page se haya forzado: si el `[Console]::OutputEncoding = 850` falla, el `catch {}` se lo traga y el caso pasa sin ejercitar nada. Falta `Assert ([Console]::OutputEncoding.CodePage -eq 850)` |
| Media | `tests/review-loop-trigger.tests.ps1:332` | El fixture del `git -C` citado en el mensaje **no muerde**: el disparador matchea en índice 0 y la cita queda fuera del segmento, así que `$scan` y `$cmd` dan lo mismo. Mutación que sobrevive: que el 3b lea `$cmd` en las 4 ocurrencias. El caso que sí distingue necesita el literal ANTES del disparador, p. ej. `echo "x && cd '<otro>'" && git commit -m cierre` |
| Baja | `tests/review-loop-trigger.tests.ps1:232` | En el fixture de la rama huérfana, la primera copia del marcador es setup muerto (el `--orphan` + `reset --hard` la borra). El resto del caso sí llega adonde dice |
| Baja | `docs/TESTING.md` | Dice "los tres casos" y enumera dos; falta `*.lock` en la lista de patrones sin fixture; describe mal el agujero de `--git-dir`/`--work-tree` (no es falta de fixture: la atribución **no existe** para esa forma); y la rama de comilla sin cerrar de `Hide-Literals` no está declarada |

**Grupo B — dependen de la decisión sobre el paso 3b:**

| Sev | Qué | Comando que lo reproduce |
|---|---|---|
| Alta | `$trg` toma el **primer** disparador, no el operativo | `git -C '<otro>' commit -m x && git push` → silencio (debería disparar) |
| Alta | el salto de línea no está en los separadores de segmento, así que el `-C` de la línea anterior sangra | `git -C '<otro>' fetch` ⏎ `git commit -m cierre` (con trailer) → silencio. Inconsistente consigo mismo: el regex del `cd` sí usa `(?im)` y `^` |
| Alta | `(?i)` hace que `-c` (config override) se lea como `-C` (destino) **y tape el fallback del `cd`** | `cd '<otro>' && git -c user.email=x push` → dispara (debería callar). `git -c` es uso normal: el propio `New-Repo` de la suite lo usa |
| Alta | `Hide-Literals` expone el mensaje con `'\''` (el idioma de bash para un apóstrofe) y con `$(...)` | `git commit -m 'fix: it'\''s ready to git push now'` → dispara salteando el gate entero |
| Baja | el regex del `cd` no cubre subshell ni `pushd`, y cuenta un `cd` de pipeline (que corre en subshell y no cambia el cwd) | `(cd '<otro>' && git push)` y `pushd '<otro>' && git push` → disparan; `cd '<otro>' \| tee log && git push` → silencio |
| Baja | `--git-dir=`/`--work-tree=` se reconocen para plegar y para `$trg`, pero **no** para atribuir | `git --git-dir='<otro>/.git' --work-tree='<otro>' push` → dispara atribuyendo mal |
| Baja | off-by-one en la rama de comilla sin cerrar: `$end = Min($j, $s.Length - 1)` deja el último carácter sin enmascarar | el comentario dice "se come el resto" y no es lo que hace |

### Decisiones tomadas esta sesión

| # | Decisión | Quién |
|---|---|---|
| 1 | Los reviewers corren con instrucción explícita de **solo lectura** y experimentan en copias del scratchpad. Resolvió la contaminación entre paralelos de la sesión anterior: los 4 turnos verificaron `git status` limpio | agente |
| 2 | El turno 4 usó **3 focos** en vez de 5, apuntados donde el material se concentra (parser, conteo/estado, tests/docs). Declarado porque un cap silencioso se lee como "se cubrió todo" | agente |
| 3 | Se tocó `review-marker.ps1` (anclaje al toplevel) aunque no es parte de A2: es un bug que este slice destapó y el fix es de 2 líneas. **No** se tocó `Get-SliceBase`, que sigue reservada a A1b | agente, declarado |
| 4 | La lectura del estado JSON se movió del paso 7 al paso 3a (el techo necesita la huella). Efecto observable declarado: un estado ilegible ahora se aparta como `.bad` también en caminos que no disparan | agente |
| 5 | El parseo de la línea de comando se elevó a **decisión del usuario** en vez de seguir parchando: 3 turnos consecutivos con altas en la misma zona | agente |

### Bugs

- **Arreglados**: los 11 del turno 2 y los 11 del turno 3 (tablas de arriba), cada uno con RED verificado.
- **Abiertos**: los **19 del turno 4** (tablas de arriba).
- **Sigue abierto**: los 15 hallazgos de A1b.
- **Sigue abierto**: la escritura del estado no es atómica (declarado en `docs/TESTING.md`).
- **Sigue abierto**: `copy-scaffold.ps1` pisa el `.gitignore` del proyecto destino.
- **Sigue abierto**: `core.autocrlf` con hashes mixtos en los manifests.
- **Sigue abierto**: el `.bootstrap-manifest.json` de la **raíz** no se reselló (AC de A7). Hoy además no registra las versiones nuevas de los 3 archivos tocados, así que un `upgrade-bootstrap` sobre este repo los vería como `customized`.
- **Sigue abierto**: el diff de `fix/review-loop-motor-invocable` nunca pasó por reviewer.

### Tests

- **Suite completa 12/12 verde**. Runner por archivo: `pwsh -NoProfile -File tests/<archivo>.tests.ps1`.
  Hay un runner de todos en el scratchpad de la sesión (`suite.ps1`), no está en el repo.
- `tests/review-loop-trigger.tests.ps1` pasó de 25 a **~45 asserts**.
- **Mutación**: 13 mutantes verificados en el turno 2 (12 mueren, 1 sobrevive: el centinela `$LASTEXITCODE = 99`, declarado como redundancia en `docs/TESTING.md`), y 8 en el turno 3 (los 8 mueren).
- **⚠️ Trampa nueva, en el verificador de mutación, no en los tests**: partir la salida con `$out -split 'FAIL:'` da un falso "MUERE" cuando **no** hay ningún FAIL — el único segmento resultante contiene todos los `ok:` y matchea igual. El criterio correcto es una línea que **empieza** con `FAIL:`. Las primeras verificaciones de la sesión se rehicieron por esto.
- **⚠️ Dos fixtures propios que no distinguían nada**, encontrados y corregidos dentro de la sesión: uno usaba `commit --allow-empty` (el marcador daba rango vacío y el hook salía antes del bloque bajo prueba) y otro creaba un binario de 300 KB de ceros **sin saltos de línea** (leído como texto contaba 1 línea, así que pasaba con y sin la detección de binarios).

### Antes de tocar código

- **El `alignment-gate` puede frenar el primer edit.** El paso 1 está cerrado (grill 11/8, PRD e issues aprobados 12/8): decilo y reintentá, no ofrezcas grill.
- **Regla del espejo**: el hook, `review-marker.ps1`, `review-loop.md`, `review-loop/SKILL.md` van a las **4 copias**. Editar la de `bootstrap-personal-project` (es a donde apuntan los tests) y espejar con `Copy-Item` a las otras dos del scaffold; la copia de la **raíz** va en **español** — replicar la lógica, no copiar el archivo. `tests/review-loop-incremental.tests.ps1` compara la lógica de las 4.
- **Manifests generados**: `pwsh -NoProfile -File tools/gen-manifest.ps1 -SkillDir skills/<skill>`, una skill por vez, antes de commitear. Ya están regenerados al estado actual.
- Editar skills acá **no tiene efecto** hasta `tools/sync-skills.ps1` (pendiente heredado del 1/8).
- **Verificar mutantes sin dejar el árbol sucio**: los scripts de mutación con `try/finally` **no restauran si el proceso se mata** (pasó dos veces esta sesión: quedó la copia de `bootstrap-personal-project` mutada). Correr en foreground con timeout amplio, o restaurar desde una copia hermana intacta.
- Los repos temporales de prueba (`$TEMP/rlt-*`, `rm-test-*`, `dbg*`) se borran al terminar. Al cierre de esta sesión quedaron 0.

### Preferencias del usuario (vigentes)

- **No commitear sin que lo pida.**
- **Nada de esto va a Zoho.**
- Quiere **impacto medido antes de cambiar el proceso**.
- Criterio: "el menor tiempo posible pero que la revisión sea completa y acertada".
- Prefiere **cortar y seguir en terminal nueva** antes que dejar crecer el contexto. Fue el motivo de este handoff.

### Próximos pasos

1. **Preguntarle al usuario la decisión del paso 3b** (las 3 opciones de arriba). Bloquea el grupo B.
2. **Arreglar el grupo A**, que no depende de esa decisión. Empezar por la **alta del marcador**
   (`$top` mojibake), que hoy deja el slice entero muerto en cualquier repo con ruta no-ASCII.
3. Aplicar el grupo B según lo decidido, con RED verificado por fix.
4. **Turno 5 del `/review-loop`** — es el último del cap. Al cerrarlo, reportar el estado del cap.
5. **Commitear** cuando el usuario lo pida (sugerido: `fix(review-loop): correcciones de los turnos 2-4 sobre el disparo por cierre de slice`, con trailer `Slice-Close:` sólo si se considera cierre de slice).
6. Después **A3**, luego A4/A5, luego A6, y **A7 al final** (requiere presencia humana: deploya a `~/.claude/skills`).
7. **A1b** cuando se quiera; sigue con 15 hallazgos y el nudo de diseño sin resolver.
8. Track B (B1/B2) lo lleva el usuario en otra terminal; **vence el 10/9**.

### Supuestos declarados

- El marcador está avanzado a `2585e54` y el rango sale **vacío con exit 0** porque los fixes del
  turno 4 no se escribieron todavía. **Eso no es "el loop cerró limpio".**
- Los PRDs e issues viven en `.scratch/`, **gitignoreado**: existen sólo en el working tree.
  Señalado desde el 12/8, **sigue sin decidirse**.
- El techo de ~400 líneas se mide a mano contra la copia canónica ×1. El rango del turno 4 medía
  **325 líneas canónicas**, bajo el techo. La regla del `CLAUDE.md` no exime explícitamente las
  copias espejadas, así que una lectura literal pondría el rango bruto (742) por encima.
- Los 19 hallazgos del turno 4 salieron de 3 reviewers; **ninguno pasó por un pase de confianza
  formal**, pero todos vienen con reproducción ejecutable verificada por el reviewer que los reportó.

---

# Session Handoff — 2026-08-13 parte 3 (A2 commiteado + turno 1 del review-loop SIN COMMITEAR)

## ▶▶▶▶▶▶▶▶ ESTADO AL RETOMAR — seguir por el turno 2 del loop

Rama **`feat/marcador-de-revision`**. **A2 está commiteado** (`e320510`) y encima hay **los fixes del
turno 1 del `/review-loop`, SIN COMMITEAR**: 19 archivos, 588 inserciones. Suite **12/12 verde**.
El loop **no cerró**: el turno 1 corrió entero (5 focos + pase de confianza + fixes), y sus fixes
son delta que **no revisó nadie**.

```
e320510  feat(review-loop): disparo por cierre de slice declarado          <- A2
67ae410  fix(review-loop): correcciones del ciclo de revision sobre el marcador
326aee3  feat(review-loop): marcador de revision y turno incremental       <- A1
```

**El marcador quedó en `422f2ad`** (avanzado después de la corrida de review y antes de los fixes,
como manda el paso 3 del loop). O sea: `-Action range` ya devuelve exactamente los fixes del turno 1.
**El turno 2 es correr `/review-loop` y listo** — el rango sale solo.

### Lo primero: el turno 2

```powershell
pwsh -NoProfile -File .claude/scripts/review-marker.ps1 -Action range   # debe dar 422f2ad...
```

Foco sugerido para el turno 2, porque es lo que más cambió y nadie miró: el bloque de la red de
seguridad del hook (conteo con pathspec de exclusión + untracked), el manejo del estado ilegible
(`.bad`), y la detección del `cd` fuera del repo.

### Qué se hizo esta sesión

**A2 implementado con `/tdd`** (`.scratch/review-cost-redesign/issues/02-disparo-por-cierre-de-slice.md`),
5 ciclos RED→GREEN, y commiteado con el trailer — el hook **disparó en vivo**, que era la prueba
end-to-end del disparo nuevo. Los 12 acceptance criteria del issue están cubiertos.

Después corrió el **turno 1 del `/review-loop`** sobre `9053dc9` (que incluía además los ~55
renglones del turno 5 de A1 que habían quedado sin revisar — se decidió no avanzar el marcador antes
de empezar, para cubrirlos). **25 hallazgos únicos, 3 descartados** por el pase de confianza.

**Los 3 descartados, para no volver a perseguirlos:**

| Hallazgo | Puntaje | Por qué se cayó |
|---|---|---|
| El regex del trailer no ancla a inicio de línea | 25 | `(?m)^\s*` sí ancla; verificado con 5 variantes |
| `pwsh` ausente rompe el guard de `$LASTEXITCODE` | 35 | El mecanismo es real pero degrada al lado seguro |
| El camino `octopus` esconde commits con exit 0 vacío | 20 | No reproduce: el único caso vacío tiene `rev-list --count trunk..HEAD` = 0. Es estructural — que `merge-base --octopus <refs> HEAD == HEAD` exige que HEAD sea ancestro de todos los refs, así que no hay nada que esconder |

**Arreglados en el turno 1, cada uno con RED verificado antes del fix:**

| Sev | Qué era | Fix |
|---|---|---|
| Alta | el hook trataba `exit 0 + vacío` del marcador ("nada sin revisar") como "indeterminable" y caía al rango de la rama → disparaba justo después de que el loop cerraba limpio | `$rangeKnown`: exit 0 vacío sale sin disparar; sólo exit 2 / sin marcador caen al rango de la rama |
| Alta | `git commit && git push` es UN comando y prende las dos banderas: el gate del trailer salía con exit 0 y se llevaba puesto el disparo del push | `if ($isCommit -and -not ($isPush -or $isPr))` |
| Media | la ventana de frescura de 120 s se tragaba cierres declarados: PostToolUse corre cuando termina **toda** la llamada de Bash, así que `git commit && npm test` llega tarde | ventana de 1800 s + `[Math]::Abs()` (reloj adelantado) |
| Media | el techo contaba generados y vendored, que la regla del CLAUDE.md excluye textualmente | pathspec `:(exclude)` — **ojo: `*` pelado, no `**`**, que no matchea en la raíz |
| Media | el techo era ciego a los untracked, y el paso 5 del loop *ordena* escribir un test nuevo | suma las líneas de `ls-files --others --exclude-standard` |
| Media | un JSON ilegible hacía que el hook reescribiera el estado con sólo su clave de dedupe, borrando `marker:*` y `untracked:*` de todas las ramas | el corrupto se aparta como `.bad` y se arranca limpio |
| Media | `Test-Path` sin `-LiteralPath`: bajo una ruta con corchetes el estado se leía como inexistente y el dedupe no existía en cada corrida | `-LiteralPath` |
| Media | `push` / `gh pr create` corridos en otro repo se seguían atribuyendo acá (la frescura sólo protege commits: un push no mueve HEAD) | detecta `cd <path>` en el comando y compara el toplevel; un subdirectorio del mismo repo sigue disparando |
| Media | prosa que quedó falsa: `/review-loop` ×8 decía que dispara en cada commit, `CONTEXT.md` declaraba el trailer "sin implementar", `docs/TESTING.md` afirmaba lo contrario del test | corregidas las tres, con assert nuevo que blinda la de `/review-loop` |
| Media | **tests que no mordían** (ver abajo) | ver abajo |
| Baja | el encabezado del hook ×4 describía el disparo viejo | reescrito en las 4 |

### ⚠️ Tests que pasaban sin verificar nada (esta clase de bug ya salió 3 sesiones seguidas)

- El assert de la huella acentuada **pasaba aunque el hook no escribiera nada**: sólo comprobaba que
  el literal siguiera en el archivo. Ahora lleva un **control positivo** (que el estado tenga el SHA
  de HEAD) antes del assert.
- El assert de espejado matcheaba el **comentario** que dice `Slice-Close:`, no el gate: se podía
  borrar el gate dejando el comentario con las 3 suites en verde. Y `-le\s+400` matcheaba `-le 4000`.
- **La causa raíz**: el hook **no** está en `$mirrored` de `review-loop-incremental.tests.ps1` (la
  copia de este repo tiene los comentarios en español) y `mirror.tests.ps1` compara sólo las 3 skills
  entre sí. Ahora hay una comparación de **lógica** (líneas sin comentarios, cortando en `$msg =`
  porque el mensaje está traducido a propósito) entre las 4 copias.
- La ventana y el techo **no estaban fijados**: el fixture backdateaba a 2020, así que cualquier
  ventana < 6 años pasaba. Ahora hay dos bordes (600 s dispara / 5400 s no).
- **Faltaba la ruta de producción de la red de seguridad**: el único test del disparo era con repo
  **sin** marcador, que en producción no existe. Se agregó el caso con marcador + >400 sin revisar.
- `New-Repo` no aislaba el gitconfig global (`commit.gpgsign` y compañía). Ya lo hace.

**Mutantes verificados muertos**: `-le 4000`, `-gt 86400`, y forzar el rango del marcador a algo que
siempre mida 0.

### Lo que NO se arregló, declarado

- **Alta — la elección de base sobre-revisa**: una rama recién cortada de `develop`, sin un commit
  propio, ya reporta delta sin revisar, y ese delta es todo lo que `develop` lleve adelantado sobre
  `main`. Reproducido y puntuado 95. **Va a A1b** (`.scratch/review-cost-redesign/issues/01b-...`,
  hallazgo #15, escrito con el repro): es la función que el usuario decidió sacar a slice propio, y
  tocarla acá contradice esa decisión. Es el mismo guard del turno 5 visto del otro lado.
- **Baja** — la escritura del estado no es atómica (un solo `WriteAllText`, sin temp+move).
- **Proceso** — el `CLAUDE.md` pide evaluar si un cambio de template aplica al de Forecasting App.
  Evaluado: **no aplica hoy** — ese repo tiene el hook viejo instalado y un bloque interino que manda
  no correr `/review-loop`, así que su texto ("dispara en cada `git commit`") sigue siendo cierto
  **para él**. Al aplicarle `upgrade-bootstrap` (A7) hay que revertir el bloque interino y corregir
  ese paréntesis en `CLAUDE.md:82` de ese repo.

### Decisiones tomadas esta sesión

| # | Decisión | Quién |
|---|---|---|
| 1 | No avanzar el marcador antes de A2, para que el review de A2 cubriera también los ~55 renglones del turno 5 de A1 | agente, declarado |
| 2 | El trailer se lee del **commit ya creado** (`git log -1 --format=%B`), no se parsea del comando: sobrevive a `-m`, `-F`, heredoc y `--amend` | agente |
| 3 | El trailer gobierna **sólo** a `git commit`; push y pr create siguen disparando siempre | issue |
| 4 | La ventana de frescura pasó de 120 s a **1800 s**: el falso negativo (perder un cierre declarado) es mudo y peligroso; el falso positivo lo tapa el dedupe | agente |
| 5 | El espejado del hook se verifica por **lógica** y no byte a byte, porque el drift de idioma de la copia del repo es deliberado | agente |
| 6 | El pase de confianza se agrupó en **2 scorers temáticos**, y los hallazgos con repro ejecutable o mutación se dieron por confirmados sin scorer | agente, declarado |
| 7 | La alta de la elección de base no se arregla acá: va a A1b | agente, por la decisión previa del usuario |

### Bugs

- **Arreglados**: los 11 de la tabla de arriba, cada uno con test en RED verificado.
- **Sigue abierto**: los 15 hallazgos de A1b (14 + el #15 nuevo).
- **Sigue abierto**: escritura no atómica del estado del hook.
- **Sigue abierto**: `copy-scaffold.ps1` pisa el `.gitignore` del proyecto destino.
- **Sigue abierto**: `core.autocrlf` con hashes mixtos en los manifests.
- **Sigue abierto**: el `.bootstrap-manifest.json` de la **raíz** no se reselló (AC de A7).
- **Sigue abierto**: el diff de `fix/review-loop-motor-invocable` nunca pasó por reviewer.

### Tests

- **Suite completa 12/12 verde** al cierre. Runner por archivo:
  `pwsh -NoProfile -File tests/<archivo>.tests.ps1`.
- `tests/review-loop-trigger.tests.ps1` pasó de 12 a **25 asserts**.
- **Trampa nueva que apareció**: tres asserts del bloque de atribución compartían repo y SHA, así que
  el 2º y el 3º pasaban por el **dedupe**, no por la lógica. Se corrigió con un repo fresco por caso.
- **Trampa nueva 2**: un `Assert` que lee un archivo inexistente **aborta la corrida entera** y se
  lleva puestos los tests de abajo. La lectura va afuera del Assert, no adentro de un `if`.

### Antes de tocar código

- **El `alignment-gate` va a frenar el primer edit.** El paso 1 está cerrado (grill 11/8, PRD e
  issues aprobados 12/8): decilo y reintentá, no ofrezcas grill.
- **Regla del espejo**: el hook, `review-marker.ps1`, `review-loop.md`, `review-loop/SKILL.md`,
  `tdd.md` y `tdd/SKILL.md` van a las **4 copias**. Editar la de `bootstrap-personal-project` (es a
  donde apuntan los tests) y espejar. El hook de este repo va en **español**: replicar la lógica, no
  copiar el archivo.
- **Manifests generados**: `pwsh -NoProfile -File tools/gen-manifest.ps1 -SkillDir skills/<skill>`,
  una skill por vez, antes de commitear.
- Editar skills acá **no tiene efecto** hasta `tools/sync-skills.ps1` (pendiente heredado del 1/8).
- **Los reviewers que mutan archivos contaminan a los que corren en paralelo**: el foco de tests dejó
  el hook mutado mientras los otros cuatro leían, y tres reportaron como hallazgo un `86400` y un
  `-le 40` que eran mutantes. Verificar `git status` limpio antes de creerle a un hallazgo de valor.
- Los repos temporales de prueba se borran al terminar (`$TEMP/rlt-*`). Esta sesión quedaron 7
  huérfanos por una corrida abortada; ya se borraron.

### Preferencias del usuario (vigentes)

- **No commitear sin que lo pida.**
- **Nada de esto va a Zoho.**
- Quiere **impacto medido antes de cambiar el proceso**.
- Criterio: "el menor tiempo posible pero que la revisión sea completa y acertada".
- Prefiere **cortar y seguir en terminal nueva** antes que dejar crecer el contexto.

### Próximos pasos

1. **Turno 2 del `/review-loop`** — el marcador ya está en `422f2ad` y devuelve los fixes del turno 1.
2. **Commitear los fixes del turno 1** cuando el usuario lo pida (sugerido: `fix(review-loop):
   correcciones del turno 1 sobre el disparo por cierre de slice`, con trailer `Slice-Close:` sólo
   si se lo considera cierre de slice).
3. Después **A3** (depende sólo de A1), luego A4/A5, luego A6, y **A7 al final** (requiere presencia
   humana: deploya a `~/.claude/skills`).
4. **A1b** cuando se quiera; ahora tiene 15 hallazgos y el nudo de diseño sigue sin resolver.
5. Track B (B1/B2) lo lleva el usuario en otra terminal; **vence el 10/9**.

### Supuestos declarados

- Los PRDs e issues viven en `.scratch/`, **gitignoreado**: los 16 archivos existen sólo en el
  working tree. Señalado desde el 12/8, **sigue sin decidirse**.
- El techo de ~400 líneas se mide a mano contra la copia canónica ×1. A2 canónico ≈ 123 líneas; los
  fixes del turno 1 ≈ 200. **Medido esta sesión: el hook cuenta 2.78× lo canónico en este repo** por
  el espejado ×4, así que su techo efectivo son ~144 líneas canónicas.
- El turno 2 no corrió: los fixes del turno 1 no los revisó nadie.

---

# Session Handoff — 2026-08-13 parte 2 (A1 cerrado y commiteado; arrancar A2)

## ▶▶▶▶▶▶▶ ESTADO AL RETOMAR — la tarea es A2, empezar por acá

Rama **`feat/marcador-de-revision`**, **working tree limpio**, suite **12/12 verde**.
**A1 está terminado y commiteado.** La tarea de esta sesión nueva es **A2 — Disparo por cierre de
slice** (`.scratch/review-cost-redesign/issues/02-disparo-por-cierre-de-slice.md`).

```
67ae410  fix(review-loop): correcciones del ciclo de revision sobre el marcador   <- los 5 turnos
326aee3  feat(review-loop): marcador de revision y turno incremental              <- A1
b962d45  docs(review-cost): glosario del ciclo de revision, ADR-0001 y handoff
```

### Lo que hay que hacer: A2

El issue está completo y aprobado, con 12 acceptance criteria. Resumen de las tres piezas:

1. **El disparo deja de ocurrir en cada `git commit`** y pasa a ocurrir cuando se declara el cierre de
   slice con un trailer `Slice-Close:` en el mensaje del commit.
2. **Red de seguridad**: si el delta sin revisar supera ~400 líneas, dispara igual (olvidarse del
   trailer no puede dejar un slice gigante sin revisar).
3. **Bug a arreglar** (reproducido en vivo el 11/8): el hook **atribuye commits de otros repos**.
   Confía en `$evt.cwd` (cwd de la sesión) en vez de verificar dónde corrió el comando; un `git commit`
   en un repo de `mktemp -d` disparó la orden de revisar el rango de este repo. Fix acordado: comparar
   `git log -1 --format=%ct` contra el momento del evento; si el HEAD del repo no es reciente, el
   commit fue en otro lado y no dispara.

Archivos: `.claude/hooks/review-loop-trigger.ps1` (**81 líneas**, ×4 copias byte-idénticas) y
`tests/review-loop-trigger.tests.ps1` (**69 líneas**, runner sin Pester, repos git temporales).

**Ojo con una cosa**: el hook ya fue tocado por A1 (ahora pide el rango al marcador en vez de inyectar
`main...HEAD`). La copia de este repo está en **español** y las 3 del scaffold en **inglés** — es drift
previo y **esperado**; `mirror.tests.ps1` sólo compara las 3 skills entre sí, y ésas sí son idénticas.

### Qué se hizo en la sesión anterior (A1, cerrado)

Se corrió el **turno 5 del `/review-loop`** — el último, ya que 5 es el tope. Corrieron los **5 focos**
(bugs, reglas del CLAUDE.md, historia, contratos, tests), a diferencia del turno 4, donde el de tests
murió por límite de sesión. **24 hallazgos únicos, 3 descartados** por el pase de confianza → 1 alta +
10 medias + 10 bajas.

**La alta era una regresión que el propio loop se metió en los turnos 3/4.** Al elegir la base del
slice por "gana el merge-base más cercano", cualquier rama nombrada que ya contenga HEAD puntúa
distancia 0, gana siempre, y la base colapsa a HEAD: el rango deja de mostrar los commits del slice y
`range` sale con **exit 0**, que para el caller significa "rango confiable". O sea, el loop cerraba
reportando limpio un slice que nadie leyó. Reproducido corriendo las dos versiones del script sobre el
mismo fixture (rama mergeada a `develop` y trabajo que sigue encima):

| | rango emitido | qué ve el reviewer |
|---|---|---|
| versión `1d66cf3` | la base correcta | `s1.txt s2.txt` |
| versión de los turnos 3/4 | **HEAD** | nada (árbol limpio) |

**Se cerraron 4 hallazgos, cada uno con RED verificado antes del fix:**

| Sev | Qué era | Fix |
|---|---|---|
| Alta | el colapso de la base a HEAD | HEAD queda como **último recurso** en la elección de base, nunca por delante de un candidato con delta commiteado |
| Media | el paso 1 del loop ordenaba `fall back to the branch range` en exit 2 — justo lo que la sección reescrita en ese mismo delta prohíbe. En las **8 copias** | remite a la sección de exit codes en vez de nombrar el rango de la rama |
| Media | el JSON de estado se escribía sin BOM en `pwsh` y se leía con la code page ANSI en PowerShell 5.1: con un untracked acentuado, esa rama **no podía volver a cerrar nunca** | lectura y escritura con `[IO.File]::ReadAllText`/`WriteAllText` + UTF-8 explícito |
| Baja | `review-loop.md` y `TESTING.md` afirmaban cosas que dejaron de ser ciertas, y `TESTING.md` declaraba cubierto lo que ningún test toca | prosa corregida + sección nueva **"Lo que este archivo de tests NO cubre"**, con los mutantes que sobreviven |

### ⚠️ Decisión del usuario que se ejecutó, y el desvío que hubo que declararle

El usuario eligió **revertir la elección de base y sacarla a slice propio**. Al ejecutar la reversión
literal a `1d66cf3` apareció que **esa versión tiene su propio agujero** (en un repo de una sola rama
emite HEAD con exit 0, escondiendo los commits) y que revertir **ponía 8 asserts en RED** que habría
que borrar. Se le informó y se entró con un **guard de 6 líneas** en lugar de la reversión de 60.
Ningún test existente pasa por ese camino, así que no rompió nada.

**No repetir el intento de revertir a `1d66cf3`** — está documentado por qué no sirve.

### El slice nuevo que quedó escrito: A1b

`.scratch/review-cost-redesign/issues/01b-eleccion-de-base-del-slice.md` — **14 hallazgos**, con el
nudo de diseño arriba de todo, que hay que resolver **antes** de codear:

```
A) rama base `dev`, con `feature/a` creada en la punta        -> se quiere: rango = HEAD (exit 0)
B) rama `feat/x` con 1 commit, y un `git branch wip` en HEAD  -> se quiere: exit 2 (indeterminable)
```

Son **el mismo estado de git** y hoy nada los distingue. Cualquier regla que satisfaga A rompe B. Por
eso esa función se rompió dos veces en cinco turnos. B falla en la dirección peligrosa, así que si hay
que sacrificar uno, es A. **A1b no bloquea a A2 ni a A3.**

### ⚠️ Lo que quedó sin revisar (declarado, no es omisión)

El marcador está en **`9053dc9`** y el delta contra él son **los fixes del turno 5**: 216 líneas / 18
archivos, ~55 canónicas ×1. **Ese pedazo no lo revisó ningún reviewer.** Es el límite conocido del cap:
cada turno revisa los fixes del anterior, así que el último siempre queda descubierto. El hook va a
volver a pedir `/review-loop`; su propia condición de parada ("o el tope de 5 turnos") ya está cumplida
para A1. Dos formas de cerrarlo, ninguna urgente: un turno acotado sobre esos 55 renglones (el marcador
ya tiene el rango exacto), o dejarlo para el review de A1b, que va a tocar esa misma función.

**Al arrancar A2 conviene avanzar el marcador primero** (`-Action advance`), para que el rango de A2
sea el delta de A2 y no arrastre los fixes de A1.

### Decisiones tomadas esta sesión

| # | Decisión | Quién |
|---|---|---|
| 1 | Arreglar sólo la alta + los fixes chicos aislados; la elección de base sale a slice propio (A1b) | usuario |
| 2 | **El techo de A1 se acepta como está** (~900 líneas canónicas, el doble de las ~400). No se parte | usuario |
| 3 | Guard mínimo en lugar de la reversión literal a `1d66cf3`, porque la reversión reintroduce un agujero y rompe 8 asserts | agente, informado al usuario |
| 4 | No correr un turno 6: el cap de 5 se alcanzó y el cap existe por la medición de costo | agente, declarado |
| 5 | El pase de confianza se agrupó en 4 scorers por tema en vez de 24 (uno por hallazgo) | agente, declarado |

### Bugs

- **Arreglados esta sesión**: los 4 de la tabla de arriba, cada uno con test en RED verificado.
- **Sigue abierto**: los 14 hallazgos de A1b (ver el issue).
- **Sigue abierto**: `copy-scaffold.ps1` pisa el `.gitignore` del proyecto destino.
- **Sigue abierto**: `core.autocrlf` con hashes mixtos en los manifests (`gen-manifest.ps1` hashea
  bytes crudos).
- **Sigue abierto**: el `.bootstrap-manifest.json` de la **raíz** no se reselló (es AC de A7). Ojo: los
  4 archivos de la raíz que figuran en él ya **no** matchean sus hashes, así que hoy un
  `compare-scaffold` los vería como `customized`. Además `.claude/scripts/review-marker.ps1` **no
  figura** en ese manifest (archivo nuevo).
- **Sigue abierto**: el hook `review-loop-trigger.ps1` usa `Get-Content`/`Set-Content` sobre el mismo
  `review-loop-state.json` que el marcador. Si alguna vez corre bajo PowerShell 5.1 puede corromper la
  huella de untracked al reescribir el JSON. **Esto lo toca A2** — vale arreglarlo de paso.
- **Sigue abierto**: el diff de `fix/review-loop-motor-invocable` nunca pasó por reviewer.

### Tests

- **Suite completa 12/12 verde**, corrida entera al cierre. Cero tests fallando.
- Runner por archivo: `pwsh -NoProfile -File tests/<archivo>.tests.ps1` (imprimen `TODOS LOS TESTS
  PASARON` o `N test(s) FALLARON`). No hay runner único.
- Tests nuevos de esta sesión: candidato que contiene HEAD (`review-marker.tests.ps1`), cruce
  pwsh↔PowerShell 5.1, y el assert negativo del paso 1 en `review-loop-incremental.tests.ps1`.
- **Trampa que apareció otra vez**: el primer intento del test de la alta usaba `$r -ne HEAD`, que
  **también se cumple con el rango vacío** — pasaba sin verificar nada. Se corrigió comprobando primero
  que hay rango. Ver `docs/TESTING.md`, sección "Lo que este archivo de tests NO cubre".

### Antes de tocar código

- **El `alignment-gate` va a frenar el primer edit de código.** El paso 1 está cerrado (grill 11/8, PRD
  e issues aprobados 12/8) y A2 ya está diseñado en su issue: **decilo y reintentá, no ofrezcas grill**.
- **Regla del espejo**: `review-loop-trigger.ps1` (lo que toca A2), `review-marker.ps1`,
  `review-loop.md`, `review-loop/SKILL.md`, `slice-review.md` y `slice-review/SKILL.md` van a las
  **4 copias**. Editar la de `bootstrap-personal-project` (es a donde apuntan los tests) y espejar.
  El comando y el SKILL.md difieren **sólo** en la línea `description`.
- **Manifests generados**: `pwsh -NoProfile -File tools/gen-manifest.ps1 -SkillDir skills/<skill>`, una
  skill por vez, antes de commitear.
- Editar skills acá **no tiene efecto** hasta `tools/sync-skills.ps1` (pendiente heredado del 1/8).
- Los repos temporales de prueba se borran al terminar.

### Preferencias del usuario (vigentes)

- **No commitear sin que lo pida.**
- **Nada de esto va a Zoho.**
- Quiere **impacto medido antes de cambiar el proceso**.
- Criterio: "el menor tiempo posible pero que la revisión sea completa y acertada".
- Prefiere **cortar y seguir en terminal nueva** antes que dejar crecer el contexto. Fue el motivo de
  este handoff.

### Próximos pasos

1. **Implementar A2** con `/tdd` sobre `.scratch/review-cost-redesign/issues/02-disparo-por-cierre-de-slice.md`.
   Un test a la vez (RED → GREEN). Avanzar el marcador antes de empezar.
2. Al cerrar A2: `/review-loop` sobre el delta (el marcador ya funciona y está probado en vivo).
3. Después **A3** (depende sólo de A1), luego A4/A5, luego A6, y **A7 al final** (requiere presencia
   humana: deploya a `~/.claude/skills`).
4. **A1b** cuando se quiera; no bloquea nada. Empezar por resolver el nudo de diseño.
5. Track B (B1/B2) lo lleva el usuario en otra terminal; **vence el 10/9**.

### Supuestos declarados

- Los PRDs e issues viven en `.scratch/`, que está **gitignoreado** (`.gitignore:23`). Los 16 archivos
  (incluido el A1b nuevo) existen **sólo en el working tree**. Si se pierde el directorio, se pierde
  toda la planificación del track. Señalado desde el 12/8, **sigue sin decidirse**.
- El techo de ~400 líneas se mide a mano contra la copia canónica ×1; no hay tooling que lo verifique.
- Los fixes del turno 5 no los revisó nadie (ver arriba).

---

# Session Handoff — 2026-08-13 (A1 commiteado + 4 turnos de review-loop sobre él)

## ▶▶▶▶▶▶ ESTADO AL RETOMAR — decir "continuemos" y seguir desde acá

Rama **`feat/marcador-de-revision`**. **A1 está commiteado** (2 commits) y encima hay **4 turnos de
`/review-loop` aplicados y SIN COMMITEAR** en el working tree. Suite **12/12 verde**. El loop
**NO cerró**: falta el turno 5, que es también el tope.

```
b962d45  docs(review-cost): glosario del ciclo de revision, ADR-0001 y handoff
326aee3  feat(review-loop): marcador de revision y turno incremental      <- A1
         (+ 4 turnos de fixes del loop, sin commitear)
```

### Lo primero: el turno 5 (y por qué el marcador NO se avanzó)

El marcador quedó en **`1d66cf3`** a propósito. El turno 4 corrió con **un solo reviewer**: el de
tests murió por límite de sesión (`You've hit your session limit`), así que los tests del turno 3
**nunca los revisó nadie**. Avanzar el marcador los habría dejado del lado "revisado" sin serlo, así
que se dejó quieto: el turno 5 vuelve a cubrir todo desde `1d66cf3` (revisar de más, nunca de menos).

Para arrancar el turno 5:

```powershell
pwsh -NoProfile -File .claude/scripts/review-marker.ps1 -Action range   # debe dar 1d66cf3...
```

y correr `/slice-review` sobre ese rango, con foco en **tests** (es lo que quedó sin revisar) y en
la resolución de base del turno 4.

### Qué encontró cada turno (todo reproducido en vivo, no inferido)

| Turno | Medium/high | De dónde salieron |
|---|---|---|
| 1 | 11 de 22 únicos | el slice A1 original |
| 2 | 5 | los fixes del turno 1 — **2 regresiones propias** |
| 3 | 4 | los fixes del turno 2 — incluido un fix que no arreglaba nada |
| 4 | 1 alto + 6 | los fixes del turno 3 — **1 regresión propia** |

Los agujeros más graves que se cerraron, todos en la dirección peligrosa (**revisar de menos con
exit 0**, que es "rango confiable" para el caller):

1. **Untracked invisibles.** `git stash create` y `git diff` los ignoran → un fix hecho de archivos
   nuevos daba rango vacío y el loop cerraba sin revisarlo. Y el paso 5 del propio loop *ordena*
   crear un test nuevo. Ahora `advance` guarda una huella `path|sha256` de los untracked junto al
   marcador y `range` compara contra ella. **Ojo**: `/slice-review` también se cambió para recibir
   los untracked — antes había emisor sin receptor.
2. **Base mal resuelta.** Se pelaba `origin/` y se usaba el nombre local, que en un clon de una sola
   rama no existe → sin base → **slice entero sin revisar en el primer turno**.
3. **`advance` guardaba basura.** En un merge conflictivo `git stash create` falla escribiendo
   `<archivo>: needs merge` por **stdout**; eso quedaba persistido como marcador.
4. **"vacío" significaba dos cosas.** Ahora exit 0 = aplicable, **exit 2** = indeterminable. Cerrar
   el loop con exit 2 es reportar limpio un slice que nadie miró.
5. **Rama hermana como base.** Elegir el merge-base más cercano hacía que un `git branch wip` a
   mitad del slice se convirtiera en la base. Ahora: entre nombres conocidos el más cercano; entre
   refs cualesquiera el ancestro común **más lejano** (`merge-base --octopus`, un solo proceso git
   en vez de tres por ref — medido: 48 s en un repo con 300 refs).
6. **El hook contradecía al loop.** Seguía inyectando `git diff main...HEAD`. Se verificó en vivo:
   es el mensaje que llegó al commitear A1.

### Trampas de testing que aparecieron (valen para cualquier test del repo)

- **`[regex]::Match(...).Index` vale `0` cuando NO hay match**, no -1. Dos asserts de orden eran
  tautologías: se podía borrar el paso 1 del doc entero y la suite quedaba verde. Fix: helper `Idx`
  en `tests/review-loop-incremental.tests.ps1`.
- **`mirror.tests.ps1` compara las 3 skills ENTRE SÍ**: la copia del repo — la que efectivamente
  corre acá — no entra en ninguna comparación. Se agregó hash normalizado de 5 archivos × 4 copias
  en `review-loop-incremental.tests.ps1`.
- Un assert dentro de `if (Test-Path)` no verifica nada: borrar el archivo dejaba la suite verde.
- `git ls-files` C-quotea nombres no-ASCII (`"\303\261andu.txt"`) y PowerShell decodifica la salida
  del hijo con la code page de consola. Las dos cosas rompían la huella de `ñandú.txt`. Fix:
  `-c core.quotepath=false` + forzar UTF-8 en `Console::OutputEncoding` alrededor de la llamada.

### Archivos cambiados (39, todos sin commitear)

Lógica: `.claude/scripts/review-marker.ps1` (109 → **245** líneas), `.claude/hooks/review-loop-trigger.ps1`.
Instrucciones: `review-loop.md` + `review-loop/SKILL.md`, `slice-review.md` + `slice-review/SKILL.md`.
Tests: `tests/review-marker.tests.ps1` (139 → **425**), `tests/review-loop-incremental.tests.ps1` (47 → **135**).
Docs: `CLAUDE.md` (×4: repo + 3 plantillas), `CONTEXT.md`, `docs/TESTING.md`, `docs/adr/0001-...`,
`skills/upgrade-bootstrap/SKILL.md`. Más las 3 copias espejadas de cada archivo del scaffold y los
3 `.bootstrap-manifest.json` regenerados.

### ⚠️ El slice se pasó del techo

`git diff --stat 01fa552` da **3386 líneas** (39 archivos). Descontando las 3 copias espejadas, los
manifests generados y los docs, la lógica canónica ×1 ronda **900 líneas** — más del doble del techo
de ~400 de `CLAUDE.md`. **Es decisión del usuario** si se parte (marcador ↔ instrucciones del loop)
o se acepta como está; no se partió por cuenta propia.

### Decisiones tomadas esta sesión

| # | Decisión | Quién |
|---|---|---|
| 1 | El marcador avanza **después del review y antes de los fixes** (se apartó de la letra del issue 01) | usuario, confirmado |
| 2 | Exit 2 como señal de "no puedo determinar el rango", distinta de "no hay delta" | agente |
| 3 | Entre nombres conocidos, merge-base más cercano; entre refs cualesquiera, el más lejano | agente |
| 4 | El marcador NO se avanza si el reviewer no corrió (regla escrita en el loop) | agente |
| 5 | A1 se commiteó en 2 commits (docs aparte del slice) para no inflar el diff a revisar | agente |
| 6 | Un repo con una sola ref da exit 2 y no HEAD, aunque sea la forma en que nacen los proyectos bootstrapeados (se trabaja en feature branch por slice, así que no aparece en el flujo normal) | agente, declarado |

### Bugs

- **Arreglados**: los 6 de arriba, cada uno con un test que se verificó en RED antes del fix.
- **Sigue abierto**: `copy-scaffold.ps1` pisa el `.gitignore` del proyecto destino.
- **Sigue abierto**: `core.autocrlf` con hashes mixtos en los manifests — este slice suma 3 entradas
  más del lado equivocado (`tools/gen-manifest.ps1` hashea bytes crudos).
- **Sigue abierto**: el `.bootstrap-manifest.json` de la **raíz** no se reselló (es AC de A7).
  Verificado que hoy no misclasifica nada: los 3 archivos tocados en la raíz son byte-idénticos a
  los canónicos.
- **Sigue abierto**: el diff de `fix/review-loop-motor-invocable` nunca pasó por reviewer.

### Tests

- **Suite completa 12/12 verde**, corrida entera después de cada turno.
- `tests/review-marker.tests.ps1`: ~60 asserts sobre repos git temporales, runner sin Pester.
- Los fixtures ahora aíslan el gitconfig global (`commit.gpgsign`, `core.hooksPath`,
  `core.excludesFile`): sin eso, una máquina con gpgsign activo daba 23 fallos.
- **Mutación verificada a mano** en los asserts nuevos: mueren el de espejado de las 4 copias y el
  de orden del `advance`.

### Antes de tocar código

- **El `alignment-gate` va a frenar el primer edit de código.** El paso 1 está cerrado (grill 11/8,
  PRD e issues aprobados 12/8): decilo y reintentá.
- **Regla del espejo**: `review-marker.ps1`, `review-loop.md`, `review-loop/SKILL.md`,
  `slice-review.md`, `slice-review/SKILL.md` y el hook van a las **4 copias**. Editar la de
  `bootstrap-personal-project` y espejar; el comando y el SKILL.md difieren **solo** en la línea
  `description`. El hook de la copia del repo está en **español** (drift previo, esperado).
- **Manifests generados**: `pwsh -NoProfile -File tools/gen-manifest.ps1 -SkillDir skills/<skill>`,
  una skill por vez, antes de commitear.
- Editar skills acá **no tiene efecto** hasta `tools/sync-skills.ps1` (pendiente heredado del 1/8).

### Próximos pasos

1. **Turno 5 del `/review-loop`** sobre `1d66cf3` (rango que ya devuelve el marcador), con foco en
   tests. Es el último: al cerrarlo, el loop llegó al tope y se reporta como tal.
2. **Decidir si A1 se parte** (ver el aviso de techo) antes de commitear los fixes.
3. **Commitear los 4 turnos de fixes**, sugerido en un commit propio
   (`fix(review-loop): correcciones del ciclo de revisión sobre el marcador`).
4. Seguir con **A2 y A3** (dependen solo de A1), después A4/A5, después A6, y **A7 al final**
   (requiere presencia humana: deploya a `~/.claude/skills`).
5. Track B (B1/B2) lo lleva el usuario en otra terminal; **vence el 10/9**.

### Supuestos declarados

- El turno 4 corrió con **un solo foco** (bugs/contratos) por el límite de sesión; el de tests no
  llegó a correr. El turno 5 lo compensa.
- Los turnos 2, 3 y 4 usaron 2-3 focos en vez de los 5 de `/slice-review`: el delta de esos turnos
  era el mismo material (script + tests + prosa), no superficie nueva. Está declarado acá porque un
  cap silencioso se lee como "se cubrió todo".
- El techo de ~400 líneas se midió a mano; no hay tooling que lo verifique.

---

# Session Handoff — 2026-08-12 parte 2 (A1 implementado con TDD: marcador + loop incremental)

## ▶▶▶▶▶ ESTADO AL RETOMAR — decir "continuemos" y seguir desde acá

Rama **`feat/marcador-de-revision`**, commit base `01fa552`. **A1 está IMPLEMENTADO y la suite
completa (12/12) está verde. NADA commiteado.** El siguiente paso es commitear el slice y correr
`/review-loop` sobre él.

### Qué se hizo esta sesión

Se implementó **A1 — El turno incremental** (`.scratch/review-cost-redesign/issues/01-el-turno-incremental.md`)
con `/tdd`, un test a la vez (RED → GREEN), nunca todos los tests primero. Las 3 piezas del issue
shippean juntas y están las 3.

**Pieza 1 — el marcador, como script.** `.claude/scripts/review-marker.ps1` (98 líneas, directorio
nuevo), con la interfaz de 3 verbos aprobada en el grill:

| Verbo | Qué hace |
|---|---|
| `-Action get` | el marcador guardado para esta rama, o vacío |
| `-Action range` | qué pasarle a `git diff` (marcador si resuelve; si no, merge-base del slice); **vacío si no hay delta** |
| `-Action advance` | `git stash create` (fallback HEAD con árbol limpio), persiste e imprime |

Detalles de implementación que ya están resueltos y testeados:

- `range` emite el marcador **PELADO** (`git diff <marcador>`), no `<marcador>..HEAD` — la forma con
  `..HEAD` solo cubre commits y dejaría afuera lo no commiteado.
- Estado en `<git-dir>/review-loop-state.json` bajo claves **`marker:<rama>`**. Verificado por test
  que **no pisa** el dedupe por SHA del hook (que usa la clave `<rama>` pelada) en el mismo archivo.
- Parámetros `-Action` (obligatorio, `ValidateSet`) y `-RepoDir` (por testabilidad, estilo
  `copy-scaffold.ps1`). Todo con `git -C $dir`, sin depender del cwd.
- Base del slice resuelta sin hardcodear `main`: `origin/HEAD` → candidatos `main`/`master`/`develop`
  (excluyendo la rama actual) → `merge-base`.
- Guards: fuera de repo git, detached HEAD, repo sin commits, marcador podado por `git gc` →
  **salida vacía, exit 0**. El modo de falla por default es revisar de más, nunca de menos.

**Pieza 2 — el loop lo usa.** Reescritas 2 secciones de `review-loop` (comando + SKILL.md): la nueva
sección "The range: review the unreviewed delta, not the whole branch" reemplaza a "PR mode" /
"Commit / local mode", y "The loop" pasó de 3 a 5 pasos.

**Pieza 3 — RED obligatorio.** El paso 5 del loop exige un test que **falle sin el fix** (verificado
en vivo) antes de escribir el fix, en lugar del viejo "add or update a test when practical".

### ⚠️ Decisión de diseño que se APARTA de la letra del issue (declarada, no consultada)

El issue decía: *"aplica fixes y avanza el marcador al cerrar [el turno]"*. **Eso está implementado al
revés a propósito**: `advance` va **después de la corrida de review y ANTES de aplicar los fixes**.

Razón: si el marcador avanzara después de los fixes, el turno siguiente recibiría un rango vacío y
**los fixes del loop nunca los revisaría nadie** — exactamente el modo de falla que el ADR-0001 dice
evitar ("el turno 2 revisa los fixes del turno 1, no el slice entero"), y la causa de que 59 de 235
reportes de turno atribuyeran sus hallazgos a los fixes del turno anterior.

Riesgo asumido y sin mitigar: si el proceso muere entre `advance` y los fixes, esos fixes quedan del
lado revisado sin haberlo sido. **Vale confirmarlo con el usuario**, es lo único del slice que no
sigue el issue al pie de la letra.

### Archivos de esta sesión

Nuevos (sin trackear):

```
.claude/scripts/review-marker.ps1                                    98 líneas  (×4 copias)
skills/bootstrap-{personal,southpoint,ai}-project/assets/scaffold/.claude/scripts/review-marker.ps1
tests/review-marker.tests.ps1                                       139 líneas (24 asserts)
tests/review-loop-incremental.tests.ps1                              47 líneas (contrato ×4 copias)
```

Modificados:

```
.claude/commands/review-loop.md                    ×4 copias (repo + 3 skills)
.agents/skills/review-loop/SKILL.md                ×4 copias (repo + 3 skills)
tests/slice-review.tests.ps1                       1 assert relajado (ver abajo)
skills/*/assets/scaffold/.bootstrap-manifest.json  ×3 REGENERADOS (50 → 51 archivos)
```

**Tamaño del slice contra la copia canónica ×1** (decisión 5 del handoff previo): ≈358 líneas de
lógica. Bajo el techo de ~400.

### Regresión encontrada y arreglada dentro de la sesión

`tests/slice-review.tests.ps1` exigía `^1\. Run \`/slice-review\`` — el reviewer en el **paso 1**.
Con el loop incremental el paso 1 es pedirle el rango al marcador y la corrida de review es el paso 2,
así que los 6 asserts iban a RED. Se relajó a `^\d+\. Run \`/slice-review\``: lo que ese test blinda
es el **motor** (que no se vuelva a `/code-review`), no el número de paso. El assert que prohíbe
ordenar `/code-review` quedó intacto.

### Verificación hecha (no es "parece que anda")

- **Suite completa: 12/12 archivos verdes**, corrida entera al cierre. Cero tests fallando.
- `tests/review-marker.tests.ps1`: **24 asserts**, sobre repos git temporales, runner sin Pester
  (patrón de `review-loop-trigger.tests.ps1`). Cubre las 9 conductas del issue + detached HEAD +
  coexistencia con el dedupe del hook.
- **Mutación acotada (4 mutantes, hechos a mano sobre el script):**
  | Mutante | Resultado |
  |---|---|
  | `stash create` → `rev-parse HEAD` | **muere** (árbol sucio) |
  | guard de detached HEAD debilitado | **muere** |
  | validación `cat-file -e` del marcador borrada | **muere** (marcador podado) |
  | guard de "no es repo git" borrado | **SOBREVIVE** |
  El sobreviviente es **redundancia, no un agujero**: el guard de `branch` ya tapa el caso y la
  conducta observable (vacío, exit 0) sigue verificada. Se dejó el guard como defensa explícita.
- El fixture del test de `git gc` tiene su **propio guard** (`Assert` de que el objeto realmente se
  podó): sin eso el test pasaba en verde sin ejercitar nada.

### Bugs

- **Ninguno nuevo encontrado ni arreglado** en el código del repo.
- **Sigue abierto**: los 5 heredados (atribución cruzada del hook, RED faltante, reviewers que
  escriben en el árbol, desperdicio de `main...HEAD`, loop que se autoalimenta). A1 resuelve los
  puntos 2, 4 y parte del 5 **en el contenido del scaffold**, pero **no llegan a la máquina hasta
  A7** (`sync-skills`).
- **Sigue abierto**: `copy-scaffold.ps1` pisa el `.gitignore` del proyecto destino (encontrado en la
  sesión anterior, sin arreglar, candidato a issue propio).
- **Sigue abierto**: `core.autocrlf` con hashes mixtos en los manifests.

### Antes de tocar código (leer sí o sí)

- **El `alignment-gate` va a frenar el primer edit de código de la sesión nueva.** El paso 1 está
  cerrado (grill 11/8, PRD e issues aprobados 12/8) y A1 ya está implementado: **no ofrezcas grill,
  decilo y reintentá el edit**.
- **Regla del espejo**: `review-marker.ps1`, `review-loop.md` y `review-loop/SKILL.md` van
  **byte-idénticos a las 4 copias** (3 skills + la del repo). El espejado ya está hecho y
  `mirror.tests.ps1` está verde; si tocás uno, replicá en los 4 o va a RED.
- El comando y el SKILL.md del loop difieren **solo en la línea `description`** (el SKILL.md lleva
  los triggers en español). Para sincronizarlos: copiar el comando y restaurar esa línea 3.
- **`.bootstrap-manifest.json` es generado**: `pwsh -NoProfile -File tools/gen-manifest.ps1 -SkillDir <skill>`
  (toma `-SkillDir` obligatorio, una skill por vez). Ya está corrido para las 3.
- **PENDIENTE menor no resuelto**: el `.bootstrap-manifest.json` de la **raíz del repo** (del
  self-bootstrap) **no** se regeneró — `gen-manifest.ps1` solo apunta a skills. Decidir si se resella
  (hay scripts de reseal en `skills/upgrade-bootstrap/scripts/`) o si se deja.
- Editar skills acá **no tiene efecto** hasta `tools/sync-skills.ps1` (pendiente heredado del 1/8).

### Preferencias del usuario (vigentes)

- **No commitear sin que lo pida.** Por eso el slice está sin commitear.
- **Nada de esto va a Zoho.**
- Quiere **impacto medido antes de cambiar el proceso**.
- Criterio: "el menor tiempo posible pero que la revisión sea completa y acertada".
- Prefiere **cortar y seguir en terminal nueva** antes que dejar crecer el contexto.

### Próximos pasos

1. **Confirmar (o no) la decisión de `advance` antes de los fixes** — es lo único que se aparta del
   issue. Un minuto de conversación, cambia el orden de dos pasos si él prefiere la letra del issue.
2. **Commitear el slice de A1.** Sugerido: `feat(review-loop): marcador de revisión y turno incremental`.
   El hook `review-loop-trigger` va a disparar la orden de correr el loop.
3. **`/review-loop` sobre el diff del slice.** El `/review-loop` de ESTE repo sí puede cerrarse
   (`/slice-review` existe acá). **Ojo — el loop que acaba de cambiar es el del scaffold, no el que
   corre esta sesión**: la sesión usa `.claude/commands/review-loop.md` del repo, que también se
   espejó, así que el propio loop va a intentar usar el marcador nuevo. Es la primera prueba real.
4. **A2 y A3** (dependen solo de A1), después A4/A5, después A6, y **A7 al final (requiere presencia
   humana**: deploya a `~/.claude/skills`).
5. Sin bloquear: el Track B (B1/B2, vencen **10/9**) lo lleva el usuario en otra terminal en
   `claude-analytics`.
6. Pendientes heredados: el diff de `fix/review-loop-motor-invocable` nunca pasó por reviewer; no
   mergear a `main` hasta cerrar Track A; `sync-skills` pendiente.

### Supuestos declarados

- Que los PRDs e issues vivan en `.scratch/` (gitignoreado) sigue siendo una consecuencia, no una
  decisión. **Sigue sin preguntarse.** Si se pierde el directorio, se pierden los 15 archivos.
- El techo de ~400 líneas se midió a mano contando la copia canónica ×1; no hay tooling que lo
  verifique.
- No se verificó que el marcador funcione **end-to-end dentro de una corrida real del loop** — los
  tests cubren el script y el contenido de las instrucciones, no la ejecución del loop completo. El
  paso 3 de arriba es esa prueba.

---

# Session Handoff — 2026-08-12 (PRDs + issues de los dos tracks, bootstrap de claude-analytics)

## ▶▶▶▶ ESTADO AL RETOMAR (sesión 2026-08-12)

Rama **`feat/marcador-de-revision`**, creada esta sesión desde `fix/review-loop-motor-invocable`
(commit `01fa552`). **Nada commiteado en este repo esta sesión.** Working tree:

```
 M CONTEXT.md                                        (de la sesión anterior, sin commitear)
 M docs/SESSION_HANDOFF.md
?? docs/adr/0001-review-incremental-con-marcador.md  (nuevo, sin trackear)
```

**Fases del workflow completadas esta sesión: paso 4 (PRD) y paso 6 (issues).** El paso 5
(aprobación del PRD) y la aprobación de los issues los dio el usuario. **La implementación de A1
está aprobada y diseñada pero NO empezada** — el usuario pidió explícitamente hacerla en una
terminal nueva.

### ⚠️ Lo primero que tenés que saber: los PRDs y los issues NO están en git

`.scratch/` está en el `.gitignore` de los dos repos. Los 15 archivos de abajo existen **solo en el
working tree**. Si se pierde el directorio, se pierden. Evaluar con el usuario si conviene moverlos
a `docs/` o commitearlos; no se hizo porque él no lo pidió.

```
Bootstrap Skills/.scratch/review-cost-redesign/          (Track A — 1 PRD + 7 issues)
claude-analytics/.scratch/review-cost-measurement/       (Track B — 1 PRD + 6 issues)
```

El ADR sí está en git-land (`docs/adr/0001-...`), aunque todavía sin trackear.

### Qué se produjo esta sesión

**Dos PRDs** (paso 4), a partir del grill del 11/8, sin volver a entrevistar:

- **Track A** — `Bootstrap Skills/.scratch/review-cost-redesign/PRD.md`. Rediseño del ciclo de
  revisión. 36 user stories, las 8 decisiones del grill + 4 menores, 5 módulos.
- **Track B** — `claude-analytics/.scratch/review-cost-measurement/PRD.md`. La medición que juzga al
  Track A. 31 user stories, 3 slices.

**Un ADR** — `docs/adr/0001-review-incremental-con-marcador.md`. Primero del repo. Documenta la
decisión de alcance con sus 5 alternativas descartadas (incluidas "bajar el cap a 2" y "matar el
pase de confianza", las dos que se cayeron con números).

**13 issues** (paso 6), aprobados con granularidad, techo y orden confirmados por el usuario:

| Track A (`.scratch/review-cost-redesign/issues/`) | Tipo | Bloqueado por |
|---|---|---|
| `01-el-turno-incremental.md` | AFK | — |
| `02-disparo-por-cierre-de-slice.md` | AFK | 01 |
| `03-corrida-de-review-incremental.md` | AFK | 01 |
| `04-pase-de-coherencia.md` | AFK | 03 |
| `05-mutacion-acotada.md` | AFK | 03 |
| `06-regla-de-afirmaciones.md` | AFK | — (serializar tras 05: toca `slice-review` en 1 línea) |
| `07-sellar-y-deployar.md` | **HITL** | 01–06 |

| Track B (en `claude-analytics/.scratch/review-cost-measurement/issues/`) | Tipo | Bloqueado por |
|---|---|---|
| `01-congelar-prompts-de-reviewer.md` | AFK | — ⏳ **vence 10/9** |
| `02-completar-el-snapshot.md` | AFK | 01 ⏳ **vence 10/9** |
| `03-clasificar-foco-y-turno.md` | AFK | 01 |
| `04-atribuir-reviewer-a-turno.md` | AFK | 01 |
| `05-reporte-de-costo-de-revision.md` | AFK | 03, 04 |
| `06-comparacion-contra-la-linea-base.md` | AFK | 05 |

### Decisiones tomadas esta sesión

| # | Decisión | Quién |
|---|---|---|
| 1 | El **marcador es un script real** (`.claude/scripts/review-marker.ps1`), no prosa en el SKILL.md | usuario |
| 2 | Se testean los 4 targets: marcador, hook trigger, contenido de los SKILL.md, y baseline/sidechain del Track B | usuario |
| 3 | **El ADR se escribe** junto con el PRD | usuario |
| 4 | Granularidad: **13 slices**, como se propuso | usuario |
| 5 | El techo de ~400 líneas se mide contra la **copia canónica ×1**, no contra las 4 copias espejadas (si no, ningún slice del Track A es posible: el test de espejo exige las 4 juntas) | usuario |
| 6 | Orden: **B1+B2 → A1–A7 → B3–B6** (primero lo que vence) | usuario |
| 7 | **Nada de esto va a Zoho** | usuario |
| 8 | `claude-analytics` se bootstrapea **antes** de desarrollar | usuario |
| 9 | Se bootstrapea **tal cual** (con el scaffold viejo) + `upgrade-bootstrap` después de A7, en vez de deployar el fix ahora | usuario |
| 10 | **Los tracks avanzan en paralelo.** Sin dependencia técnica; lo único que conviene esperar es A7 (deploya a la máquina entera) | agente, no objetado |
| 11 | El PRD y los issues del Track B **viven en `claude-analytics`**, no acá: es su tracker | agente, no objetado |

### Diseño de A1 cerrado en la planificación de `/tdd` (implementar tal cual)

Interfaz de `.claude/scripts/review-marker.ps1`, **tres verbos que hacen cosas distintas**:

```
-Action get      -> el marcador guardado para esta rama, o vacío si no hay   (consulta pura)
-Action range    -> qué pasarle a `git diff`, o vacío si no hay nada nuevo
                    (el marcador si es válido; si no, el merge-base del slice)
-Action advance  -> git stash create (fallback HEAD si el árbol está limpio), persiste e imprime
```

- **`range` emite el marcador PELADO, no `<marcador>..HEAD`** (cambio de contrato aprobado por el
  usuario). Razón: la forma con `..HEAD` solo cubre commits y dejaría afuera lo no commiteado, que
  es justamente lo que `git stash create` existe para incluir. El contrato es `git diff <marcador>`.
  Con `merge-base` como fallback, `git diff <merge-base>` reproduce exacto `base...HEAD`.
- **Ubicación `.claude/scripts/`** (directorio nuevo, aprobado). No es un hook: no lo dispara Claude
  Code por evento, lo invocan el loop y —en A2— el disparo. `tools/gen-manifest.ps1` lo levanta solo
  (recorre recursivo), no hay que registrarlo en ningún lado.
- **Estado**: mismo `.git/review-loop-state.json`, bajo claves `marker:<rama>`. Git prohíbe `:` en
  nombres de rama, así que no puede colisionar con el dedupe por SHA que ya vive ahí, y los archivos
  de estado existentes siguen funcionando sin migración.
- **Marcador recolectado por `git gc`** → cae al merge-base. El modo de falla por default es revisar
  de más, nunca de menos.
- **Parámetro `-RepoDir`** (además de `-Action`), por testabilidad y siguiendo el estilo de
  `copy-scaffold.ps1` / `gen-mcp-json.ps1`, que ya toman `-ProjectDir`.
- **Detached HEAD** → salida vacía, igual que hace el hook hoy.

Las 9 conductas a testear salen de los criterios del issue 01: árbol sucio incluido en el corte,
`advance` no commitea, `advance` no toca el árbol, el rango no repite lo ya revisado, sin marcador
previo arranca en la base, idempotencia con árbol limpio, fuera de un repo git no rompe, el estado
no aparece en el diff del slice, y marcador recolectado cae a la base.

El **tracer bullet** ya estaba escrito cuando el usuario cortó: en `tests/review-marker.tests.ps1`,
`advance` devuelve un objeto resoluble y `get` lo devuelve de vuelta. **No llegó a disco** (lo frenó
el `alignment-gate`), así que hay que reescribirlo.

### Bootstrap de `claude-analytics` — HECHO

Commit **`6d136a0`** en `C:\Repos\PERSONAL\claude-analytics` (rama `master`, sin remote), 52
archivos: `CLAUDE.md`, `README.md`, `CONTEXT.md` (stub), `skills-lock.json`,
`.bootstrap-manifest.json`, `.agents/skills/` (10), `.claude/` (10 comandos + settings + 2 hooks),
`docs/ai-workflow/` (5), `docs/agents/` (3), `docs/adr/.gitkeep`, `.scratch/`.

**No fue modo adopción**: el repo no tenía `CLAUDE.md` ni `docs/ai-workflow/`, así que no hay
`docs/agents/legacy-claude.md` ni mapa de cobertura. Fue bootstrap normal sobre directorio con
contenido.

Dos cosas que la skill **no** maneja y hubo que hacer a mano:

1. **`.gitignore`**: `copy-scaffold.ps1` sobrescribe sin preguntar (`[IO.File]::Copy(..., $true)`),
   contradiciendo el "never overwrite" del Step 0. Se respaldó, se copió y se fusionaron las reglas
   propias bajo una sección marcada `# --- Project-specific (preserved from the pre-bootstrap
   .gitignore) ---`. **Crítico**: ahí vive `output/raw/`, donde están los 4 JSONL de la línea base de
   agosto. Verificado con `git check-ignore -v`: sigue ignorado, los datasets intactos.
   → **Esto es un bug del scaffold que vale anotar como backlog**: cualquier bootstrap sobre un repo
   con `.gitignore` propio lo pierde en silencio.
2. **`.mcp.json`**: no se corrió `gen-mcp-json.ps1`. El proyecto ya tenía uno curado (zoho-projects,
   fellow, m365-southpoint) y el generador lo habría reemplazado por el catálogo personal.

Sin tocar: los 3 archivos que ya estaban sin trackear (2 PDFs y `ZOHO-CARGA-2026-06-29_07-06.md`).
Identidad local seteada: `MartinDele703 <martin.deleon703@gmail.com>`.

**Caveat aceptado por el usuario**: la skill instalada en `~/.claude/skills` es del **6 de julio** y
**no tiene `slice-review`** (10 comandos, no 11). O sea, `claude-analytics` nació con el ciclo
inerte: su `/review-loop` apunta al built-in human-only y no puede cerrarse solo. Para B1/B2 el plan
es `/code-review` tipeado a mano; después de A7, `upgrade-bootstrap` ahí. Sigue pendiente
`tools/sync-skills.ps1` (pendiente heredado del 1/8).

### Bugs

- **Encontrado esta sesión**: `copy-scaffold.ps1` pisa el `.gitignore` del proyecto destino (ver
  arriba). **No arreglado** — no estaba en alcance. Candidato a issue propio.
- **Sigue abierto** (heredados, ninguno arreglado): los 5 del handoff del 11/8 — atribución cruzada
  del hook, RED faltante en el loop, reviewers que escriben en el árbol, desperdicio del rango
  `main...HEAD`, y el loop que se autoalimenta. Los cinco son exactamente lo que A1–A6 resuelven.

### Tests y comandos

- **No se corrió ninguna suite** en ninguno de los dos repos. `tests/*.ps1` sin ejecutar. No hay
  tests fallando conocidos ni verificados.
- Comandos con efecto: `git checkout -b feat/marcador-de-revision` (acá) y, en `claude-analytics`,
  `copy-scaffold.ps1` + `git config user.name/email` + `git add` selectivo + `git commit`.
- Verificaciones de solo lectura: `git check-ignore -v` sobre `output/raw/`, conteo de skills y
  comandos del scaffold copiado, chequeo de anidamientos (`.agents\.agents`, `.claude\.claude`,
  `docs\docs`: ninguno).

### Antes de editar código (leer sí o sí)

- **El `alignment-gate` va a frenar tu primer edit de código**, porque es una sesión nueva y el
  contador es por sesión. **El paso 1 ya está cerrado** (grill del 11/8, PRD y issues aprobados el
  12/8): no ofrezcas grill, decilo y reintentá el edit.
- **Regla del espejo**: `review-marker.ps1` (nuevo), `review-loop/SKILL.md`, `slice-review/SKILL.md`
  y `review-loop-trigger.ps1` **no** están en la allowlist de `tests/mirror.tests.ps1` → van
  byte-idénticos a las 3 skills bootstrap **y** a la copia de este repo. Cuatro copias o el test va a
  RED. Los `assets/scaffold/CLAUDE.md` **sí** están en la allowlist: se editan por separado.
- Implementá primero en `skills/bootstrap-personal-project/assets/scaffold/` (es a donde apuntan los
  tests existentes) y después espejá.
- El `.bootstrap-manifest.json` es **generado**: `tools/gen-manifest.ps1` antes de commitear.
- Editar skills acá **no tiene efecto** hasta `tools/sync-skills.ps1`.
- Los repos temporales de test se borran al terminar.

### Preferencias del usuario (vigentes)

- **No commitear sin que lo pida.** Sigue vigente: esta sesión no se commiteó nada acá.
- **Nada de esto va a Zoho.**
- Quiere **impacto medido antes de cambiar el proceso**; ya rechazó dos propuestas con datos.
- Criterio de optimización: "el menor tiempo posible pero que la revisión sea completa y acertada".
- Prefiere **cortar y seguir en terminal nueva** antes que dejar crecer el contexto. Fue el motivo de
  este handoff: la implementación de A1 se corta acá a propósito.

### Próximos pasos

1. **Implementar A1** con `/tdd` sobre `.scratch/review-cost-redesign/issues/01-el-turno-incremental.md`,
   en la rama `feat/marcador-de-revision` que ya existe. El diseño está cerrado arriba: empezá por el
   tracer bullet en `tests/review-marker.tests.ps1`, un test a la vez (RED → GREEN), nunca todos los
   tests primero.
2. Al cerrar A1: `/review-loop` sobre el diff del slice. **Ojo**: el `/review-loop` de ESTE repo ya
   tiene el fix (`/slice-review` existe acá), así que sí puede cerrarse.
3. Seguir con A2 y A3 (los dos dependen solo de A1), después A4/A5, después A6, y A7 al final.
4. **A7 requiere presencia humana**: deploya a `~/.claude/skills` y cambia el tooling de la máquina.
5. Sin bloquear lo de arriba: el Track B (B1/B2) lo está haciendo el usuario en otra terminal, en
   `claude-analytics`. No hay dependencia técnica entre los tracks.
6. Pendientes heredados que siguen vivos: el diff de `fix/review-loop-motor-invocable` nunca pasó por
   ningún reviewer; no mergear a `main` hasta que cierre el Track A; `sync-skills` pendiente; el bug
   de `core.autocrlf` con hashes mixtos en los manifests.

### Supuestos declarados

- Que `.scratch/` esté gitignoreado es intencional por convención del tracker, pero nadie decidió que
  los PRDs vivan fuera de git — es una consecuencia, no una decisión. Vale preguntarle.
- El paralelismo entre tracks asume que el usuario efectivamente está corriendo B1 en otra terminal
  (lo dijo, no se verificó desde acá).
- La medición que fundamenta todo el Track A es la del handoff del 11/8; no se re-verificó nada de
  esos números en esta sesión.

---

# Session Handoff — 2026-08-11 (rediseño del costo del review-loop: medición + grill cerrado)

## ▶▶▶ ESTADO AL RETOMAR (sesión 2026-08-11)

Rama **`fix/review-loop-motor-invocable`**, commit `01fa552`. Working tree: **solo `CONTEXT.md` modificado** (sin commitear). No se tocó código ni skills.

**Fase del workflow completada: paso 1 (alineación) vía `/grill-with-docs`. El siguiente paso es `/to-prd`.** No hay implementación empezada. Aprobación humana dada para el orden de cambios; falta aprobar el PRD.

### Qué pidió el usuario y qué se descubrió

Pregunta original: "Claude tarda mucho más desde Opus 5 — ¿es el modelo, es el Bootstrap, o son los proyectos más grandes?" Un compañero con el mismo scaffold reportó lo mismo.

**Respuesta medida: no es Opus 5.** Fuente: 703 transcripts JSONL (130.252 líneas, 28.502 llamadas al modelo, 1.393 turnos) + la DB de `claude-analytics` para el baseline abril–junio.

- **Latencia por llamada, p50, estable desde abril**: opus-4-7 4,7–6,2 s · opus-4-8 7,0–8,0 s · **opus-5 6,5–7,1 s**. La cola *mejoró*: p90 42,4 s (opus-4-8, junio) → 29,2 s (opus-5, agosto). Throughput 62–75 tok/s sin cambio.
- **Lo que se duplicó es el turno**: pasos/turno 4 → 9, tool calls 4 → 10, wall p50 92 s → 187 s. Turnos/día iguales (60–90), pero horas de máquina ocupada por día ~7 h → ~11 h.
- **Causa dominante: el review-loop empezó a funcionar de verdad el 1/8 a las 14:08** (commit `8cc6e9e`, el fix del reviewer invocable). Primer subagente `slice-review` de la historia: 1/8 14:29, 21 minutos después. Antes el loop apuntaba a `/code-review` (human-only) y se cerraba sin revisar nada.
- **Costo del review en agosto**: 357 subagentes · 8.930 pasos · 8,74M tokens · **67,2 h en serie / 36,3 h de reloj** (concurrencia 1,8×). **46% de todos los tokens de salida de agosto los generaron reviewers** (8% en julio).
- **El costo está en la profundidad, no en el ancho**: **73% de los pasos de reviewer son comandos de shell** (7.503 Bash + 220 PowerShell). Reviewer típico: 23 pasos / 8,2 min.
- **Aporte real de Opus 5** (mismo repo, mismo mes, para aislar): Forecasting App julio, opus-4-8 262 s de máquina por turno vs opus-5 345 s → **+32%**. Es amplificador, no causa.
- **Refutado: "los proyectos son más grandes".** Contexto por llamada *bajó*: 183k (abr) → 145k (jun) → 102k (ago).
- **El compañero**: la rama del fix **no está en `main`**, así que quien tenga el scaffold publicado tiene el loop inerte. Su lentitud no puede venir del fan-out. Sin datos de su máquina — es inferencia.

### Decisiones tomadas en el grill (las 8)

| # | Decisión |
|---|---|
| Alcance | Review **incremental** del delta sin revisar + **pase de coherencia** final (1 reviewer, read-only, sin ejecutar nada) sobre `base...HEAD` |
| Marcador | **`git stash create`** — verificado: no commitea, no toca el árbol, y el diff contra el marcador trae solo lo nuevo |
| Afirmaciones falsas | **Regla en `CLAUDE.md`** (no escribir afirmaciones no verificadas) + 1 línea en el reviewer de contratos. **Cero agentes dedicados** (hoy: 123 agentes, 34,3 h = 51% del review) |
| Mutación | **RED obligatorio** en los fixes del loop + **mutación acotada** una vez en el turno 1: ≤8 mutantes, solo líneas del slice, solo el test file. Prohibida en turnos 2+ |
| Modelos | **Sonnet 5**: reglas, historia, coherencia. **Opus 5**: bugs, contratos/callers, tests, mutación **y scorer** |
| Read-only | Mutación en **worktree creado desde el marcador** (verificado: incluye lo no commiteado, el árbol original queda intacto). Prohibición para el resto en el contexto compartido del Step 3, no pegada a mano por prompt |
| Disparo del hook | **Trailer `Slice-Close:` en el commit** + techo de ~400 líneas de delta sin revisar como red. **Deja de disparar en cada commit** |
| Scorer | **Se queda.** Cuesta 3% (2,0 h de 67,2) y es el único filtro de falsos positivos. Descartado matarlo |

Decisiones menores resueltas por el agente (el usuario no las objetó):

- **El techo de 5 turnos queda igual** — con re-reviews angostos cada turno cuesta ~6 min; el cap solo acota la cola.
- **Fix del bug del hook**: comparar `git log -1 --format=%ct` contra el momento del evento; si el HEAD del repo no es reciente, el commit fue en otro repo y no dispara.
- **La regla de afirmaciones** va en los 3 `assets/scaffold/CLAUDE.md` (están en la allowlist del espejo → 3 ediciones separadas) + el `CLAUDE.md` de este repo. El `CLAUDE.md` real de Forecasting App queda como **follow-up marcado**, no editado en silencio.
- **El RED va en el paso 3 de `review-loop`**, no en `tdd` (`tdd/SKILL.md:67` ya lo exige; el que no lo pedía era el loop).

### Bugs encontrados (ninguno arreglado — no se implementó nada)

1. **El hook `review-loop-trigger` atribuye commits de otros repos.** Reproducido en vivo: un `git commit` en un repo temporal de `mktemp -d` disparó la orden de correr `/review-loop` sobre `main...HEAD` de Bootstrap Skills. Confía en `$evt.cwd` (cwd de la sesión) en lugar de verificar dónde corrió el comando. El dedupe por SHA no lo tapa en el primer disparo de la sesión.
2. **`review-loop/SKILL.md:66` no exige RED** al agregar tests para un fix ("add or update a test when practical"), mientras `tdd/SKILL.md:67` sí. Los tests que el loop escribe para sus propios fixes nacen sin dientes — es literalmente lo que los reviewers de mutación venían encontrando ("5 mutantes vivos en el trigger", "mi fix del turno 4 volvió inmatables 3 términos del guard").
3. **Los reviewers escriben en el árbol**: 84 de 345 subagentes usaron Write/Edit (217 Write + 202 Edit) cuando `slice-review` dice "Do not fix anything in this command". De ahí venían los "🚫 PROHIBIDO editar" pegados a mano en los prompts.
4. **Desperdicio del rango `main...HEAD`**: en Forecasting App el mismo rango se revisó en **5 disparos a lo largo de 3 días, 27 agentes, 540 minutos**; cada disparo re-revisa todo lo ya revisado. En Survey Clients: 2 disparos, 15 agentes, 186 min. En hssapp los repetidos son turnos del mismo loop (legítimos).
5. **El loop se autoalimenta**: 59 de 235 reportes de turno atribuyen los hallazgos a sus propios fixes anteriores. Los turnos 2–5 encuentran regresiones reales, pero introducidas por el turno previo. Por eso **no** se bajó el cap: cortar en 2 entrega los fixes del turno 2 sin revisar (el propio agente lo marcó en rojo el 9/8).

### Archivos tocados en esta sesión

- **`CONTEXT.md`** (modificado, sin commitear) — glosario llenado por primera vez: 12 términos (slice, cierre de slice, corrida de review, turno, marcador de revisión, delta sin revisar, reviewer, foco, pase de confianza, pase de coherencia, mutación acotada, afirmación), la ambigüedad de "review" que causó el bug original (`/code-review` vs `/slice-review` vs `/review-loop`), y un diálogo de ejemplo.
- **Fuera del repo**: los datasets de la medición se copiaron a `C:\Repos\PERSONAL\claude-analytics\output\raw\review-cost-baseline-2026-08\` (gitignored, repo sin remote): `steps.jsonl` (28.502 pasos), `turns.jsonl` (1.393 turnos), `agents.jsonl` (441 subagentes con prompt y reporte), `parent-texts.jsonl` (4.439 textos del agente padre), y los 5 scripts `.mjs` que los generan y analizan.

### ⏳ Lo urgente con fecha de vencimiento

`cleanupPeriodDays` no está configurado → **retención default de 30 días**. El transcript más viejo que sobrevive hoy es del **2026-07-12**. La DB de `claude-analytics` **sí** ingiere subagentes (1.363 de 2.066 archivos ingeridos) y conserva tokens/tiempos/modelos, pero **no guarda el texto de los prompts**, que es lo único que permite clasificar foco y turno. **La parte semántica de la línea base de agosto se borra alrededor del 10/9/2026.** Los `.jsonl` copiados arriba son la copia de seguridad; si se pierden, la comparación "antes vs después" ya no se puede hacer.

### Próximos pasos

1. **`/to-prd`**, en dos tracks:
   - **Track A — Bootstrap Skills**: `slice-review/SKILL.md` ×4 copias, `review-loop/SKILL.md` ×4, `.claude/hooks/review-loop-trigger.ps1` ×4, 3 `assets/scaffold/CLAUDE.md` + el `CLAUDE.md` del repo, tests (`review-loop-trigger.tests.ps1`, `slice-review.tests.ps1`, `mirror.tests.ps1` debe seguir verde) y manifests regenerados.
   - **Track B — claude-analytics** (el usuario eligió verificar desde ahí, no con scripts sueltos): primera slice = **congelar la línea base de agosto** (antes del 10/9), después modelar sidechain/turnos, después el reporte.
2. **ADR ofrecido y sin responder**: la decisión de alcance (review incremental + marcador) cumple los tres criterios — difícil de revertir, sorprendente sin contexto, producto de un trade-off real con alternativas descartadas por números. Preguntarle si lo escribe.
3. **El diff de esta rama sigue sin pasar por ningún reviewer** (pendiente heredado del 1/8, sigue vigente).
4. **No mergear a `main` todavía** — decisión de esta sesión: mergear tal cual le entrega a los demás proyectos el multiplicador de agosto. Merge después de Track A.
5. Después del merge: `upgrade-bootstrap` en hssapp/Outsourcing, Forecasting App, Survey Clients, Call Center.

### Riesgo de secuencia (declarado al usuario, aceptado)

El rediseño se aplica **antes** de que exista la medición que lo juzga (Track B es un proyecto aparte). Mitigación: los datasets congelados de arriba.

### Tests y comandos

- **No se corrió ninguna suite del repo** en esta sesión (no hubo cambios de código). `tests/*.ps1` sin ejecutar; no hay tests fallando conocidos ni verificados.
- Comandos ejecutados: los 5 scripts `.mjs` de medición (ahora en `claude-analytics/output/raw/review-cost-baseline-2026-08/`), consultas de solo lectura a `claude-analytics.db`, y dos experimentos en repos temporales que **verificaron** `git stash create` como marcador y `git worktree add --detach <marcador>` como aislamiento con los cambios no commiteados incluidos.

### Supuestos del análisis (para que el próximo no los tome como certezas)

- La clasificación de focos y turnos de los subagentes es **por regex sobre el prompt inicial**. 83 de 142 corridas no declaran número de turno, así que los cortes por turno son piso, no techo.
- Métricas de tiempo en **medianas**; los huecos > 30 min se descartan (humano ausente). `<task-notification>` cuenta como prompt humano, lo que infla el conteo de turnos.
- Agosto está concentrado en hssapp y Forecasting App: es el patrón de trabajo actual, no una ley general.
- Los JSONL crudos solo cubren 12/7 → 11/8; abril–junio viene de la DB y solo da latencia por llamada.

### Preferencias del usuario detectadas en esta sesión

- Criterio de optimización explícito: **"el menor tiempo posible pero que la revisión sea completa y acertada"** — se usó para decidir cada rama del árbol.
- **Los slices ya están definidos para tener un largo coherente** que le dé precisión al reviewer: por eso eligió disparar por slice y no por commit.
- No quiere abaratar el filtro de falsos positivos.
- Quiere evaluar impacto **con números antes de aplicar cambios**; rechazó dos propuestas ("matar el scorer", "bajar el cap") cuando la medición mostró que el ahorro no justificaba el riesgo.
- Sigue vigente: no commitear sin que lo pida (de ahí el marcador con `git stash create` en vez de un commit por turno).

### Antes de editar código

- **Regla del espejo**: `slice-review/SKILL.md`, `review-loop/SKILL.md` y `review-loop-trigger.ps1` **no** están en la allowlist de `tests/mirror.tests.ps1` → cada cambio va idéntico a las 3 skills bootstrap **y** a la copia del propio repo (4 copias). `assets/scaffold/CLAUDE.md` **sí** está en la allowlist → los 3 divergen y se editan por separado.
- El `.bootstrap-manifest.json` es generado: regenerarlo con `tools/gen-manifest.ps1` (o `tools/sync-skills.ps1`) antes de commitear.
- El hook `alignment-gate` bloquea la primera edición de código de cada sesión: es un speed-bump, ya se cumplió el paso 1 en esta sesión pero la nueva no lo sabe.

---

# Session Handoff — 2026-08-01 (fix: el review-loop no podía cerrarse solo)

## ▶▶ ESTADO AL RETOMAR (sesión 2026-08-01)

Rama **`fix/review-loop-motor-invocable`**, commit **`8cc6e9e`**, working tree limpio. **Sin mergear a `main` y sin pushear.**

**El bug:** el built-in `/code-review` está marcado `disable-model-invocation` — solo lo puede tipear un humano (`Skill code-review cannot be used with Skill tool`). Era el paso 1 del `review-loop`, así que **el loop nunca podía cerrarse solo**: el hook `review-loop-trigger` ordenaba en cada commit algo imposible de cumplir, y un slice podía terminar reportado como "revisado" sin reviewer. Lo detectó Martín en `C:\Repos\Outsourcing Development`, pero la causa estaba en el scaffold: lo heredaban todos los proyectos bootstrapeados.

**El fix:** nuevo comando **`/slice-review`** (command + SKILL.md, espejado en las 3 skills bootstrap y en el propio repo) — reviewer multi-agente sobre el diff **local**: reviewers en paralelo (bugs, reglas del CLAUDE.md, historia del código, contratos/callers, tests) + pase de confianza 0-100 que descarta findings < 60. Los comandos custom **sí** son invocables por el modelo; ese es todo el truco. `tests/slice-review.tests.ps1` blinda la regresión (verificado que falla al revertir el paso 1). Suite: **10/10 verde**. Manifests regenerados + manifest del repo resellado.

**Pendientes de esta sesión, en orden:**

1. **`/review-loop` sobre `main...HEAD`** — este diff **todavía no pasó por ningún reviewer**. No darlo por revisado.
2. **Merge a `main`** una vez limpio (y push con cuenta `southpointtech`; MartinDele703 da 403 acá).
3. **`tools/sync-skills.ps1`** — hasta que no corra, un bootstrap nuevo sigue instalando la versión rota.
4. **Outsourcing Development**: ya tiene el fix aplicado a mano y funcionando. Después del deploy conviene correr `upgrade-bootstrap` ahí para que el manifest selle esos archivos como canónicos en vez de marcarlos "customized".
5. **Resto de proyectos bootstrapeados** (Forecasting App, etc.): necesitan `upgrade-bootstrap`.

Reapareció el bug conocido de `core.autocrlf` (los archivos nuevos quedaron LF en el working tree, CRLF en el próximo checkout) — los hashes de los manifests siguen sin normalizar. No se tocó en esta sesión.

## ▶▶ PRIORIDAD ANTERIOR — SIGUE PENDIENTE (2026-07-06, nueva terminal)

El usuario quiere que le **expliques la auditoría del scaffold en lenguaje llano, conversando**, no que sigas con implementación. El documento técnico le resultó demasiado técnico. Arrancá así:

1. Leé `docs/superpowers/notes/2026-07-06-auditoria-EN-CRIOLLO.md` (versión sin jerga) — es tu guion.
2. Explicale de forma charlada, empezando por lo urgente (las **2 claves/secretos expuestos** en `Linkedin` y `Project Management Migration` → rotar) y siguiendo por las mejoras que más rinden. NO uses jerga técnica (hashes, autocrlf, manifests, rutas de archivo) salvo que él lo pida.
3. Dejá que él pregunte y priorice. Recién cuando elija qué mejora quiere, ahí sí entrás al flujo `grill-me → PRD → slices`.
4. El backlog técnico completo (evidencia file:line, leak-scrub, archivo exacto) está en `docs/superpowers/notes/2026-07-06-auditoria-mejoras-scaffold.md` — usalo solo como respaldo si él quiere el detalle.

La feature del bootstrap compartible YA está terminada y mergeada (ver abajo). Salvo que él lo pida, no hay que tocar código todavía.

## ▶ AL RETOMAR — estado y qué hacer

Rama: **`main`**, working tree limpio. El plan del bootstrap compartible está **ejecutado completo** (3 slices + eval). Commits locales **sin pushear** a `origin/main` (pushear con cuenta `southpointtech` cuando se quiera).

**Lo único que NO puedo hacer yo (requiere al usuario):**
1. **Push de `main`** a origin (cuenta `southpointtech`; MartinDele703 da 403 en este repo).
2. **Export real al repo público**: crear `MartinDele703/ai-project-bootstrap` en GitHub → clonar → `pwsh -NoProfile -File tools/export-shareable.ps1 -PublicRepoDir <clon>` → revisar diff → commit/push con cuenta **MartinDele703**.

## Qué se hizo esta sesión (2026-07-06)

Ejecuté `docs/superpowers/plans/2026-07-06-bootstrap-compartible.md` con `superpowers:subagent-driven-development` (implementer + task-review por task, review-loop por slice, whole-branch review final). Todo mergeado a `main` por fast-forward:

- **Slice 1 — `feat/scaffold-english`** (`dd27ab9..77b01ae`): anglicización de la prosa del scaffold canónico en las 2 skills (review-loop docs/comando, hooks, bullets de CLAUDE.md, issue-tracker, copy-scaffold). Nuevo `tests/mirror.tests.ps1` (guard de espejado). Fix typo `proceds→proceed`. Triggers `description:` español intactos (bilingües).
- **Slice 2 — `feat/bootstrap-ai-project`** (`8df1b98..35b194e`): tercera skill `skills/bootstrap-ai-project` (copia de personal + 6 divergentes genericizados). `tools/leak-markers.txt` + `tests/shareable-leaks.tests.ps1`. `upgrade-bootstrap` genericizado (publicable). CLAUDE.md raíz: regla de espejado 2→3 skills.
- **Slice 3 — `feat/export-shareable`** (`4d30449..a2313ee`): `tools/export-shareable.ps1` (copia limpia + gate anti-fuga) + `public/README.md` + `public/install.ps1` + `tests/export-shareable.tests.ps1`.

**Fixes surgidos en los review-loops (más allá del plan):**
- `tools/gen-manifest.ps1`: `variant` derivado del nombre (`bootstrap-ai-project`→`ai`; antes la heurística binaria lo dejaba `personal`).
- `tests/mirror.tests.ps1`: hashea contenido **normalizado** (CRLF/CR→LF), robusto ante `core.autocrlf` (antes daba RED espurio).
- `tools/export-shareable.ps1`: regenera el manifest **en el clon**, no en el repo fuente (ya no ensucia el working tree al correr el test).

**Eval descartable (Task 12): PASÓ.** Deploy con `sync-skills` OK. Bootstrap de un proyecto temporal como tercero: 10 skills, hooks en inglés (`NOW`/`proceed`), `.gitignore` mapeado, `gitignore.txt` ausente, identidad git NO seteada por la skill, `CLAUDE.md` genericizado ("your issue tracker"), **0 marcadores de fuga**. Proyecto borrado.

Suite completa (9 archivos en `tests/`): toda verde.

## Follow-up técnico DESCUBIERTO (pendiente, su propia tarea)

`core.autocrlf=true` + archivos que llegan por vías distintas (checkout=CRLF, Write de agente=LF) → los `.bootstrap-manifest.json` **commiteados tienen hashes mixtos LF/CRLF**. Consecuencia: `sync-skills.ps1` y `export-shareable.ps1` regeneran y dejan los 3 manifests modificados en **cada corrida** (fricción del flujo normal). NO es un leak; el export se auto-sana (regenera en el clon). **Fix sugerido:** `.gitattributes` normalizando el repo (`* text=auto eol=lf` o marcar el scaffold) + `git add --renormalize` + regenerar los 3 manifests + commitear. Blast radius alto → merece brainstorm + review propio, no apurarlo. (mirror ya quedó inmune vía hash normalizado.)

## Auditoría de mejoras al scaffold (frente de mayor valor — COMPLETA)

Auditoría de ambos árboles (`C:\Repos\PERSONAL` — 8 repos; `C:\Repos\SOUTHPOINTLABS` — 7 repos) + skills user-level + los 2 findings del whole-branch review. **Backlog priorizado y de-riesgado en `docs/superpowers/notes/2026-07-06-auditoria-mejoras-scaffold.md`** — NO implementado (alimenta grill → PRD → slices; Martín decide). Highlights:

- **A1 (correctness, el más importante):** hashing normalizado en `gen-manifest`/`compare-scaffold`/`reseal-manifest` — hoy hashean bytes crudos → bajo autocrlf rompen la comparación de `upgrade-bootstrap` para consumidores del repo público + ensucian los manifests en cada `sync`/`export`. Su propia mini-feature con test (patrón ya usado en `mirror.tests.ps1`). Ver [[bug-autocrlf-manifests-hashes-mixtos]].
- **Quick wins (convergen en ambos árboles):** hard rule "secretos con `${ENV_VAR}`, nunca literales" (se encontraron 2 secretos reales hardcodeados: `Linkedin/.mcp.json`, `Project Management Migration` — **rotar aparte**); Firebase MCP en el catálogo de personal/southpoint; doc de convención `skills-lock.json`; "definition of tested" en QA_CHECKLIST.
- **Bundlear:** `verify-downstream-arrival` + `debug-source-first` (con scrub de secciones DOMO).
- **Templates:** runbook `[CLAUDE]`/`[HUMANO]`, decision-log de stakeholders, estimation-guide (scrub alto), design-master-prompt.
- **Sistémico:** drift del scaffold — pasada de `upgrade-bootstrap` por repos viejos (la mayoría sin `alignment-gate`).
- **NO bundlear:** `scaffold-e2e-suite` (pesada), `bootstrap-multistage-project` (compite + leaks) — minar 2 ideas: sección branching-model + convención de nombres fechados.

**Además, cierre de calidad post-review (commiteado en `main`):** traducción de prosa/comentarios español residuales en las skills publicadas (`bootstrap-ai-project/SKILL.md:87` + comentarios de los 3 scripts de `upgrade-bootstrap`) que se colaban por los gates automáticos.

## Reglas del repo (no olvidar)

- Editar skills acá NO tiene efecto hasta `tools\sync-skills.ps1`.
- Manifest generado, nunca a mano (`tools/gen-manifest.ps1`). Rastros de testeo se borran.
- Identidad git local de ESTE repo: MartinDele703; push a origin: solo `southpointtech`.
- Ahora son **TRES** skills espejadas; `tests/mirror.tests.ps1` (contenido normalizado) + `tests/shareable-leaks.tests.ps1` lo verifican.
- Commits español conventional (`feat/docs/test/fix(...)`).
