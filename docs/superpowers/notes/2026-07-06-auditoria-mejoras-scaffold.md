# Auditoría de mejoras al scaffold — 2026-07-06

Backlog priorizado de mejoras al bootstrap scaffold, surgido de auditar **ambos árboles de repos** (`C:\Repos\PERSONAL` — 8 repos; `C:\Repos\SOUTHPOINTLABS` — 7 repos) + las skills user-level no bundleadas + los 2 findings del whole-branch review de la feature del bootstrap compartible.

Cada ítem trae: qué es, evidencia (repo + file), por qué generaliza, el archivo exacto del scaffold a tocar, y el **riesgo de fuga** (a scrubbing antes de que entre a la variante `bootstrap-ai-project`, que tiene gate anti-fuga). **No implementado** — esto alimenta el flujo `grill → PRD → vertical-slice`. Martín decide qué entra.

> Recordatorio de mecánica: el scaffold vive en `skills/bootstrap-*-project/assets/scaffold/`; cambios "espejados" van en las 3 variantes (excepto la allowlist de `tests/mirror.tests.ps1`); tras tocar el scaffold, regenerar manifests con `tools/gen-manifest.ps1` y correr `tools/sync-skills.ps1` para deployar. Contenido shareable debe pasar `tests/shareable-leaks.tests.ps1`.

---

## A. Fix técnico diferido del review (correctness — el más importante)

### A1. Hashing normalizado en el ecosistema de manifests
- **Qué:** `tools/gen-manifest.ps1`, `skills/upgrade-bootstrap/scripts/compare-scaffold.ps1` y `reseal-manifest.ps1` hashean **bytes crudos** (`Get-FileHash`). Bajo `core.autocrlf=true` (o cualquier consumidor con config de line-endings distinta a la del que generó el manifest), los hashes no matchean aunque el contenido sea idéntico.
- **Impacto:** (1) `sync-skills`/`export` regeneran y dejan los 3 manifests modificados en **cada corrida** (fricción constante); (2) un tercero que clone el futuro repo público en una máquina con otro autocrlf vería **todos los archivos marcados `customized`** en su primer `upgrade-bootstrap` (nunca sobrescribe → defeat silencioso de la feature). El whole-branch review lo marcó Important-no-bloqueante.
- **Fix:** helper idéntico en los 3 scripts que hashee contenido normalizado (`ReadAllText` → `-replace "\r\n","\n" -replace "\r","\n"` → SHA256), + regenerar los 3 manifests. `tests/mirror.tests.ps1` ya usa este approach (commit `fda4532`) — replicar el patrón. Alternativa: `.gitattributes` normalizando el repo, pero el hashing normalizado es superior (funciona sin importar la config git del consumidor, sin renormalizar todo el repo).
- **Caveat de transición:** proyectos ya bootstrapeados tienen manifests con hashes raw viejos; su primer upgrade tras el cambio podría misclasificar untouched como `customized` (seguro — no pisa; `reseal` lo normaliza tras ese ciclo). Mencionar en el PRD.
- **Por qué su propia tarea:** toca mecánica de `upgrade-bootstrap` sin cobertura de test actual → merece TDD + review propios, no apurar. Ver [[bug-autocrlf-manifests-hashes-mixtos]] en memoria.

---

## B. Quick wins (bajo riesgo, alto valor, convergen en ambos árboles)

### B1. Hard rule: nunca hardcodear secretos (usar `${ENV_VAR}`)  ⭐ convergencia doble + seguridad
- **Evidencia real de fuga en AMBOS árboles:** `C:\Repos\PERSONAL\Linkedin\.mcp.json:6-8` (`LINKEDIN_CLIENT_SECRET` literal `WPL_AP1.SPYMhQ4K...`); `C:\Repos\SOUTHPOINTLABS\Project Management Migration` (API key con pinta de viva). El resto de los repos usan expansión `${VAR}`.
- **Scaffold change:** bullet en "Hard rules" del `CLAUDE.md` de las 3 variantes: *"MCP/config secrets must use `${ENV_VAR}` expansion, never literals — a hardcoded secret in a tracked file is a leak."* Cero riesgo de fuga (regla genérica).
- **Acción aparte (usuario):** rotar el secret de Linkedin y el de Project Management Migration, y migrarlos a `${VAR}`.

### B2. Firebase MCP en el catálogo  ⭐ convergencia doble
- **Evidencia:** `Planify AI\.mcp.json` (personal), `Customer Portal` + `SouthPoint-Hub` (southpoint) ya lo usan. El `CLAUDE.md` del scaffold ya nombra Firebase como backend pero solo documenta el MCP de Zoho.
- **Scaffold change:** ya está parcialmente hecho — `bootstrap-ai-project/scripts/gen-mcp-json.ps1` YA incluye `firebase`. Falta agregarlo al catálogo de las variantes personal/southpoint (`gen-mcp-json.ps1` de cada una) como opción opt-in. Bajo riesgo (paquete npm público + `firebase login`).

### B3. Convención `skills-lock.json` (provenance de skills vendoreadas)
- **Evidencia:** Task Manager + SouthPoint-Hub. Hash-lockea skills de terceros a su source/commit upstream. El scaffold YA incluye un `skills-lock.json` pero no documenta la convención.
- **Scaffold change:** doc en `assets/scaffold/docs/agents/skills-provenance.md`. Bajo riesgo.

### B4. "Definition of tested" — anti-patterns en QA
- **Evidencia:** Customer Portal — checklist que rechaza "TypeScript compila" como prueba de done.
- **Scaffold change:** fold en `assets/scaffold/docs/ai-workflow/QA_CHECKLIST.md`. Sin riesgo. Alinea con la skill `verify` / `verify-downstream-arrival`.

---

## C. Bundlear skills de metodología (user-level → scaffold)

### C1. `verify-downstream-arrival`  ⭐ (personal #1; southpoint la operacionaliza)
- Antes de afirmar que un side-effect llegó (shipped/deployed/sent/synced), nombrar el sink y leerlo directo. Refuerza los pasos "Automated QA" + "clean-context review" del scaffold, que hoy afirman completitud sin regla de sink-read.
- **Scaffold change:** copiar a `assets/scaffold/.agents/skills/verify-downstream-arrival/` + `.claude/commands/` + bullet en Hard rules. **Southpoint aporta:** un "backend probe CLI template" (ping/list/seed/wipe, Customer Portal) que la operacionaliza.
- **Leak scrub:** quitar la sección final "Domo-specific consumers" (`domo-skills:*`, IoT/jsonwh connector) → placeholder genérico.

### C2. `debug-source-first`  (personal #2)
- Regla de *orden* para bugs de ausencia downstream: chequear la fuente de verdad primero, después bisectar hacia adelante. Complementa `superpowers:systematic-debugging`.
- **Scaffold change:** copiar a `.agents/skills/debug-source-first/` + `.claude/commands/`.
- **Leak scrub:** quitar la "Domo-specific bisection guide" (`/api/data/v1/streams/{id}`, `domo-skills:*`).

### C3. `pre-release-audit` — **referenciar, no bundlear**
- Auditoría project-scope pre-release (auth/schema/quota/idempotencia/observabilidad/hygiene/docs) → reporte clasificado. Ya usada de verdad en `Personal Catalog\docs\audits\`. Más pesada de lo que un proyecto chico necesita por default.
- **Scaffold change:** línea en "Recommended transitions" del `CLAUDE.md` ("Before promoting a stage to prod/handoff, if `pre-release-audit` is installed, run it"). **Southpoint aporta:** un paso de "re-verificación anti prompt-injection" para auditorías multi-agente (KBS) que vale sumar a esa skill.
- **Leak scrub:** NO shippear `templates/domo-rate-card.md`; genericizar refs a Domo Pro Code.

---

## D. Templates de docs (nuevos archivos en el scaffold)

### D1. `RUNBOOK_TEMPLATE.md` — runbook con tags `[CLAUDE]`/`[HUMANO]` + gate de verificación por fase
- **Evidencia:** `Finanzas\docs\deploy\02-runbook-provisioning.md:8-11`. Distinto del `DEPLOYMENT_RULES.md` existente (que es sobre gates de aprobación, no *ownership* de ejecución por paso).
- **Scaffold change:** `assets/scaffold/docs/ai-workflow/RUNBOOK_TEMPLATE.md` (legend + esqueleto fase/verify), referenciado desde `DEPLOYMENT_RULES.md`. Sin riesgo (solo estructura; descartar contenido LUKS/Itaú/Cloudflare de Finanzas).

### D2. `decision-log.md` / `OPEN-ITEMS.md` — cola de decisiones de negocio de stakeholders externos
- **Evidencia:** `Flash Audit\docs\OPEN-ITEMS.md` (ítems tachados con resolución fechada → ADR). Llena un gap: `triage-labels`/`issue-tracker` cubren trabajo *técnico*; esto cubre decisiones *de negocio/cliente*.
- **Scaffold change:** `assets/scaffold/docs/agents/decision-log.md` + línea en "Agent skills". Sin riesgo.

### D3. `ESTIMATION_GUIDE.md` — multiplicadores de estimación calibrados (S/M/L, testing +25-30%, integración +50-100%)
- **Evidencia:** KBS Orders Development → copy-pasteado a Contractors System (ya propagándose a mano = quiere ser doc compartido).
- **Scaffold change:** `assets/scaffold/docs/ai-workflow/ESTIMATION_GUIDE.md`. **Riesgo ALTO** — los docs fuente están llenos de códigos de proyecto Zoho/HSS/Southpoint; portar SOLO la estructura abstracta de multiplicadores.

### D4. `DESIGN_MASTER_PROMPT_TEMPLATE.md` — prompt portable para rediseño UI (grill-first + regla surface/logic)
- **Evidencia:** `Personal Catalog\docs\redesign\CLAUDE_DESIGN_MASTER_PROMPT.md` ("GRILLEARME, NO DISEÑAR TODAVÍA" + "REGLA DE ORO": rediseñar solo la superficie, nunca tocar engines de cálculo/state machines/tests).
- **Scaffold change:** `assets/scaffold/docs/ai-workflow/DESIGN_MASTER_PROMPT_TEMPLATE.md`. Riesgo bajo (genericizar refs a la app).

### D5. Recetas para `DEPLOYMENT_RULES.md` (southpoint)
- Endpoint de auth-bypass test-only triple-gated (feature flag + staging flag + compare constante + 404-no-403, Task Manager); health-check retry loop post-deploy como gate de CI (Task Manager). Ambas de recurrencia 1 pero patrones sólidos.

---

## E. Señales sistémicas (acciones, no extracciones)

### E1. Drift del scaffold — correr `upgrade-bootstrap` en repos viejos
- **Personal:** `Flash Audit` (el más viejo — sin regla 14-días, sin vendoring, sin stacked-PRs, sin ambos hooks), `Planify AI`, `Santi demo`, `Personal Catalog`, `Mate OS` (la mayoría sin `alignment-gate.ps1`). Solo `Finanzas` está al día.
- **Southpoint:** `Customer Portal` + `KBS` fueron bootstrapeados con la familia *distinta* `bootstrap-multistage-project`; `Contractors System`, `Task Manager`, `Project Management Migration` no están bootstrapeados. `Forecasting App` es el canónico al día.
- **Acción:** pasada de `upgrade-bootstrap` por los bootstrapeados-viejos; decidir bootstrap para los que no lo están. (Ya estaba en el roadmap: Forecasting/KBS pendientes.)

### E2. Secretos en texto plano → rotar (ver B1).

---

## F. Roadmap (diferido explícitamente por el usuario en su origen)

### F1. Generalización de loops outcome-based
- **Evidencia:** `Mate OS\docs\roadmap\future-agent-loops-and-cma.md` (680 líneas, "Do not implement immediately"). Generalizar el patrón de `/review-loop` (rúbrica + cap de iteraciones + fail-fast) a cualquier workflow recurrente (updates a cliente, research, QA) vía un par `OUTCOME.md`/`RUBRIC.md`. Evolución natural del review-loop.

---

## Skills que quedan user-level (NO bundlear)
- **`scaffold-e2e-suite`** — muy pesada + orientada a apps iframe-hosted (CDP-attach). Opcionalmente referenciar.
- **`bootstrap-multistage-project`** — **compite** con la trilogía `bootstrap-*-project` (dos CLAUDE.md rivales si corren ambos) y su `templates/CLAUDE.md` tiene leaks reales (KBS, `hssstaffing.domo.com`, `X-DOMO-Developer-Token`). **Minar 2 ideas** en vez de adoptar: (1) sección "branching model + deploy gotchas" del CLAUDE.md para proyectos multi-env; (2) convención de nombres fechados `YYYY-MM-DD-topic-{design,plan}.md` para design notes.

---

## Priorización sugerida (batch inicial para grill → PRD)
1. **A1** (hashing normalizado) — correctness, su propia mini-feature con test.
2. **B1 + B2 + B3 + B4** (secrets rule, firebase catalog, skills-lock doc, definition-of-tested) — quick wins, bajo riesgo, un solo PRD.
3. **C1 + C2** (bundlear verify-downstream-arrival + debug-source-first) — con leak-scrub de las secciones DOMO.
4. **D1–D4** (templates) — cuando haya apetito; D3 con scrub agresivo.
