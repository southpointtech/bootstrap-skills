# Research — Dieta de contexto para el scaffold (2026-08-28)

**Pregunta**: qué se envía al modelo en cada request de un proyecto bootstrapeado, cuánto pesa, y qué
dice la fuente primaria (Matt Pocock, aihero.dev) más la documentación oficial de Claude Code sobre
cómo reducirlo sin perder comportamiento. Objetivo: que la próxima versión del bootstrap (que suma 9
skills + 2 disciplinas + reviewers como agents + una regla) no engorde el arranque "de manera
disparatada".

Todo número marcado **(medido)** se calculó sobre este repo el 2026-08-28. Todo lo marcado
**(fuente)** es cita o paráfrasis de la fuente enlazada. Lo que no pude verificar está marcado como tal.

---

## 1. Qué se carga en cada request — verificado contra la doc oficial

| Pieza | ¿Se carga siempre? | Fuente |
|---|---|---|
| `CLAUDE.md` (global, proyecto, `.claude/CLAUDE.md`, `CLAUDE.local.md`) | **Sí, entero**, hasta 4 MiB. Los `@imports` **también** cargan al inicio ("imported files still load and enter the context window at launch") | [memory](https://code.claude.com/docs/en/memory) |
| `.claude/rules/*.md` sin `paths:` | Sí, misma prioridad que `.claude/CLAUDE.md` | idem |
| `.claude/rules/*.md` **con** `paths:` | **No** — solo cuando Claude lee un archivo que matchea el glob | idem |
| `CLAUDE.md` en subdirectorios | No — bajo demanda al leer archivos de ese subdirectorio | idem |
| `MEMORY.md` (auto-memory) | Sí: primeras 200 líneas o 25 KB | idem |
| Skills / comandos: **name + description** | **Sí**, en un listado con **presupuesto = 1 % de la ventana** (200k → 2.000 tk; 1M → 10.000 tk). Si desborda, recorta descriptions empezando por las menos usadas. Cada description se trunca a 1.536 ch | [skills](https://code.claude.com/docs/en/skills) |
| Skills / comandos: **cuerpo** | **No** — solo al invocarse | idem |
| Skill con `disable-model-invocation: true` | **Description NO va al contexto**; solo la puede invocar el humano, y **ningún otro skill puede llamarla** | idem |
| Skill con `user-invocable: false` | Description siempre en contexto; oculta del menú `/` | idem |
| Subagents (`.claude/agents/`): **description** | **Sí** — warning a partir de 15.000 tk combinados. El system prompt del agent no, hasta que corre | [sub-agents](https://code.claude.com/docs/en/sub-agents) |
| Comentarios HTML de bloque en `CLAUDE.md` | **No** — se strippean antes de inyectar (notas para mantenedores gratis) | [memory](https://code.claude.com/docs/en/memory) |
| `.agents/skills/` | **No es un directorio que Claude Code lea** (la doc solo nombra `.claude/skills/`, `.claude/commands/`, `~/.claude/skills/`). Lo que hay ahí en el scaffold es portabilidad a otros harnesses, no contexto | [skills](https://code.claude.com/docs/en/skills) |

Dos detalles operativos de la doc oficial que importan para la decisión:

- **`.claude/commands/` y `.claude/skills/` son lo mismo**: "Custom commands have been merged into
  skills. A file at `.claude/commands/deploy.md` and a skill at `.claude/skills/deploy/SKILL.md` both
  create `/deploy` and work the same way." Los comandos aceptan el mismo frontmatter.
- **`/doctor`** (v2.1.206+; instalado: **2.1.250**) estima el costo del listado de skills con sus
  mayores contribuyentes, y **propone recortes** para un `CLAUDE.md` checkeado: corta lo derivable del
  código y conserva "pitfalls, rationale, and conventions that differ from tool defaults".
- `skillOverrides` en `settings.json`: `"off"` (fuera del payload), `"user-invocable-only"` (typeable,
  Claude no la ve), `"name-only"` (lista sin description).

## 2. Lo que dice Pocock — y qué está respaldado

### Tesis central (fuente)

> "only include what is both **undiscoverable** and **globally relevant**." —
> [Never Run Claude /init](https://www.aihero.dev/never-run-claude-init)

Su `CLAUDE.md` propio: *"you are on WSL on Windows"* (seis palabras). Todo lo demás lo delega a skills.
El mínimo que propone para un `AGENTS.md` de proyecto: descripción de una frase + gestor de paquetes si
no es npm + comandos de build no estándar. *"That's honestly it. Everything else should go elsewhere."*
— [A Complete Guide To AGENTS.md](https://www.aihero.dev/a-complete-guide-to-agents-md)

Las cuatro categorías que `/init` genera y que él considera veneno: listado de comandos (ya está en
`package.json`), descripción de arquitectura (derivable de configs/imports), referencias a archivos
(se pudren al primer rename y **desorientan activamente**), patrones de implementación (relevantes a
una fracción de las sesiones).

### El presupuesto de instrucciones — inconsistente entre sus propios artículos

- *Never Run /init*: "LLMs can realistically handle around **300 to 400 instructions** at a time.
  Bigger models push this to maybe 500."
- *Complete Guide*: "Frontier thinking LLMs can follow ~ **150-200 instructions** with reasonable
  consistency."

Ninguna de las dos cifras cita fuente. El paper que enlaza como "research confirms this" es
[Gloaguen et al., *Evaluating AGENTS.md*, arXiv:2602.11988](https://arxiv.org/abs/2602.11988) y **no
mide presupuesto de instrucciones**. Lo que sí mide es más útil para nosotros:

> "providing context files does not generally improve task success rates, while increasing
> inference cost by more than 20% on average" — consistente entre LLMs, agentes, y archivos generados
> por LLM **y** commiteados por desarrolladores.
>
> "while **instructions in context files are well followed** by coding agents, **general
> repository descriptions**, although popular and recommended by model providers, **are not useful**."

Es decir: el paper no dice "achicá el `CLAUDE.md`"; dice **"las instrucciones se cumplen, las
descripciones del repo no sirven"**. Eso cambia el diagnóstico (ver §4).

### "Lost in the middle" — afirmación sin evidencia en la fuente

[What Is The Context Window?](https://www.aihero.dev/what-is-the-context-window): "even if that
model supports a big context window, you'll definitely still get better results from using fewer
tokens in the context". **No cita estudio ni da cifra.** Es una recomendación práctica, no un dato.
La doc oficial dice algo más acotado y verificable: "Files over 200 lines consume more context and may
reduce adherence" y "Shorter files produce better adherence".

### El 63 % — reportado, no reproducible desde acá

La página del changelog v1 devuelve 404. El resumen del buscador dice: al poner
`disable-model-invocation: true`, "its description no longer gets included in the context window...
a 63% reduction in token cost for skill descriptions". Base = costo en tokens de las descriptions del
set de Matt. **No lo reproduje**, pero el mecanismo es el documentado oficialmente (§1) y **el mismo
cálculo sobre nuestro set da 65 %** (§4.2).

### Su modelo de invocación — la regla que más nos sirve (fuente)

De `.agents/invocation.md` y `writing-for-agents/SKILL-MECHANICS.md` (clon local del upstream):

> "Pick model-invocation only when the agent must reach the skill on its own, or another skill
> must. If it only ever fires by hand, make it user-invoked and pay no context load."
>
> "A **user-invoked** skill strips the description from the agent's reach [...] the `description`
> becomes human-facing: a one-line summary, trigger lists stripped."
>
> "The description is the skill's top-level context pointer, forced to stay loaded at all times:
> permanent context load in exchange for discoverability."

Y la idea de **cache** (changelog v1.2, `writing-for-agents`): un doc que restata lo que
`package.json`, un config o un `--help` ya dicen es "a cache of a lookup, earning its load only when
the lookup is expensive". Lo que sí vale cachear: "unwritten conventions, the reason behind a choice,
gotchas no config confesses".

### `How To Kill The Bloat` — aplica a la máquina, no al scaffold

[El artículo](https://www.aihero.dev/how-to-kill-the-bloat-in-claude-codes-system-prompt) ataca el
**system prompt de Claude Code** (schemas de tools, skills bundled, Workflow), no los archivos del
proyecto. Sus palancas son de `settings.json` de usuario: `disableBundledSkills`, `disableWorkflows`,
`permissions.deny` con nombres pelados (`"NotebookEdit"` saca la definición; `"Bash(rm *)"` bloquea
la llamada pero deja la definición), `skillOverrides`. Su caso: 69 tools · 154.946 bytes · 65.538 tk
de entrada reales; Workflow solo ~5.307 tk. Es una optimización **por máquina**, útil para vos, pero
**no viaja en el scaffold** (y meter `permissions.deny` en el `settings.json` del scaffold le sacaría
herramientas a 20 repos de golpe).

## 3. Lo que pesa hoy un proyecto bootstrapeado (medido)

| Pieza | chars | ~tokens |
|---|---|---|
| `CLAUDE.md` del scaffold | 7.250 | ~2.010 |
| descriptions de los 11 comandos | 2.996 | ~830 |
| **arranque del proyecto** | **~10.250** | **~2.850** |
| + tus 13 skills globales (`~/.claude/skills`) | 8.341 | ~2.320 |
| + 19 skills de plugins | 3.477 | ~970 |
| **listado de skills total que ve un proyecto tuyo** | **14.814** | **~4.100** |

**El listado ya desborda el presupuesto oficial en una ventana de 200k** (7.200 ch de presupuesto vs
14.814 cargados: **206 %**). En 1M entra (41 %). Consecuencia concreta: en cualquier sesión de 200k,
Claude Code **ya está recortando descriptions** empezando por las skills que menos usás — y las del
scaffold, siendo 11 entre 43, están entre las candidatas a perder sus triggers en español. En 1M no
pasa, pero cada skill nueva acerca el límite.

Anatomía del `CLAUDE.md` del scaffold: 103 líneas (dentro del "<200" oficial), **62 ítems / ~102
oraciones-instrucción**. Con el presupuesto más pesimista de Pocock (150-200) está adentro pero cerca;
con el oficial (líneas) está cómodo. `Workflow State Machine` + `Hard rules` = **79 %** del archivo.
**Un solo bullet pesa 2.000 ch (11 oraciones): el del `/review-loop`.** Ese bullet describe en detalle
la mecánica del hook (`Slice-Close:`, gate solo-docs, qué cuenta como gobierno, red de ~400 líneas,
`review-marker.ps1 -Action range`) — y él mismo dice que el hook "reinforces this deterministically
[...] so it does not depend on the agent remembering". **Es documentación del hook, cargada en cada
request.**

Frontmatter de los 11 comandos: solo `setup-matt-pocock-skills` y `zoom-out` tienen
`disable-model-invocation: true`. Los otros 9 pagan description siempre.

## 4. Aplicación al scaffold — tres hallazgos y sus números

### 4.1 El diagnóstico del paper nos favorece: el `CLAUDE.md` es del tipo "bueno"

El `CLAUDE.md` del scaffold es casi todo **instrucciones** (workflow + hard rules) y casi nada
**descripción del repo** — justo la mitad que el paper dice que sí se cumple. No hay listados de
comandos ni mapas de archivos que se pudran. Recortarlo a lo Pocock ("seis palabras") **destruiría el
producto**: el scaffold *es* un conjunto de reglas de proceso; su valor no está en el código del
proyecto, que Claude puede explorar, sino en un flujo que Claude no descubriría solo. La tesis
"undiscoverable and globally relevant" se cumple para casi todo el archivo.

Lo que sí sobra, por la regla de **cache**: lo que restata un mecanismo que ya está enforzado. El
bullet de 2.000 ch documenta el hook; el hook es la fuente de verdad y corre igual aunque el bullet no
exista. Candidato claro a: **3 oraciones en el `CLAUDE.md`** (corré el loop al cierre de cada slice;
declaralo con el trailer `Slice-Close:`; trabajá en feature branches) **+ un pointer** a
`docs/ai-workflow/REVIEW_LOOP.md` con la mecánica completa. Ahorro: ~1.700 ch (~470 tk, 23 % del
archivo) por request, en 20+ repos. Riesgo: ese bullet creció incidente por incidente cuando **no
había hook**; ahora lo hay, y es determinista — el argumento para mantenerlo largo caducó. Igual, la
única forma de confirmar que no vuelve el olvido es correrlo. Lo mismo, a menor escala, para el bullet
del `alignment-gate` (611 ch): describe el hook.

`/doctor` propone estos recortes automáticamente; conviene correrlo sobre el scaffold como segunda
opinión antes de editar a mano.

### 4.2 El listado de skills: la palanca grande es la invocación, no el largo

Aplicando la regla de Pocock ("model-invoked solo si el agente u otra skill debe alcanzarla") a
nuestras 11 — con una restricción propia: `/review-loop` y `/slice-review` los invoca el **agente**
(orden del hook + `review-loop` llama a `slice-review` por Skill tool), así que **deben** seguir
model-invoked, igual que documentó ADR-0003 para `/code-review` (`Skill ... cannot be used with Skill
tool` es exactamente el error de invocar una user-invoked):

| comando | hoy (ch) | quién lo alcanza | invocación | ch en contexto |
|---|---|---|---|---|
| review-loop | 412 | el agente (hook) | model | 412 |
| slice-review | 421 | review-loop | model | 421 |
| tdd | 206 | el agente tras aprobar issues | model | 206 |
| grill-me | 231 | el humano (el gate solo OFRECE) | **user** | 0 |
| grill-with-docs | 278 | el humano | **user** | 0 |
| to-prd | 155 | el humano | **user** | 0 |
| to-issues | 242 | el humano | **user** | 0 |
| triage | 217 | el humano | **user** | 0 |
| handoff | 143 | el humano | **user** | 0 |
| setup-matt-pocock-skills | 469 | ya user | user | 0 |
| zoom-out | 222 | ya user | user | 0 |
| **total** | **2.996** | | | **1.039 (−65 %)** |

Coincide con la clasificación que hizo upstream en v1 para las mismas skills (`grill-me`,
`grill-with-docs`, `to-spec`, `to-tickets`, `triage`, `handoff`: todas `disable-model-invocation:
true`). Y con el 63 % que reporta Matt.

Proyección con lo decidido en el grill del 2026-08-28 (descriptions upstream, en inglés; en español
serán más largas):

| | ch en contexto |
|---|---|
| 3 model-invoked actuales | 1.039 |
| + `grilling` 152, `domain-modeling` 150, `git-guardrails` 243, `diagnosing-bugs` 156, `wizard` 313, `resolving-merge-conflicts` 72, `research` 238 (model) | +1.324 |
| + `to-questionnaire` (user) | 0 |
| + `verify-downstream-arrival` 497 + `debug-source-first` 507 (model por naturaleza: "use when about to claim…") | +1.004 |
| **19 comandos, con disciplina de invocación** | **3.367 (+12 % sobre los 2.996 de hoy)** |
| 19 comandos, sin disciplina (todo model-invoked) | ~6.000 (+100 %) |

**Con la regla de invocación, el release casi duplica las skills y suma 12 % al listado.** Sin ella,
lo duplica.

Sobre las descriptions en sí: las nuestras son 3-5× las de upstream (`grill-me` 546 ch en
`.agents/`, 231 en el comando; `grilling` 152). Pero **el largo importa poco en una user-invoked**
(no se carga) y **en una model-invoked los triggers en español son la razón de ser** — recortarlos es
perder auto-invocación, que es lo que se quería. El tope oficial es 1.536 ch; ninguna se acerca. La
disciplina útil no es "≤ N caracteres" sino la de Pocock: description **model-facing con triggers**
para las model-invoked, **una línea human-facing** para las user-invoked.

### 4.3 Los reviewers como agents: barato, con una condición

Las 5-6 descriptions de `.claude/agents/` **sí** cargan siempre (§1), pero el umbral de warning es
15.000 tk y una description de reviewer bien escrita son ~100-150 ch → **~600-900 ch en total**. El
system prompt de cada uno (el foco entero) no carga hasta que corre. Condición: escribir la description
de un reviewer como *"foco X del fan-out de slice-review; no invocar a mano"*, no como la explicación
del foco.

## 5. Herramientas para no volver a preguntarlo a ojo

- **`/context`** en una sesión de un proyecto bootstrapeado: la fila *Skills* muestra el listado **ya
  recortado** por presupuesto (v2.1.196+), y *Memory files* confirma qué `CLAUDE.md` cargaron.
- **`/doctor`**: costo estimado del listado + mayores contribuyentes + propuesta de trim del `CLAUDE.md`.
- **`InstructionsLoaded` hook**: loguea qué archivos de instrucciones se cargaron, cuándo y por qué —
  sirve para verificar reglas con `paths:`.
- **`skillListingBudgetFraction`** (p. ej. `0.02`) o `SLASH_COMMAND_TOOL_CHAR_BUDGET`: subir el
  presupuesto del listado por máquina si se quiere que en 200k no se recorten descriptions.
- **`.claude/rules/` con `paths:`**: para reglas que solo importan al tocar ciertos archivos. En el
  scaffold hay pocas candidatas (la de Firebase/Azure, quizá); en **este repo** sí: la regla del
  espejo de las tres skills solo importa al editar `skills/**`.
- **Comentarios HTML de bloque** en `CLAUDE.md`: notas para el mantenedor a costo cero.

## 6. Resumen para decidir

1. **El `CLAUDE.md` del scaffold no está inflado por el tipo de contenido** — es instrucciones, que el
   paper dice que se cumplen. Está inflado por **cachear mecanismos ya enforzados por hooks**: un bullet
   de 2.000 ch y otro de 611 documentan los dos hooks. Mudarlos a `docs/` con pointer ahorra ~2.300 ch
   (~30 %) por request y **no cambia ninguna regla**, porque los hooks siguen corriendo.
2. **La palanca de las skills es `disable-model-invocation`, no el largo de la description.** 6 de las
   11 actuales las invoca solo el humano → **−65 % del listado** hoy, y las 8 nuevas entran por **+12 %**
   en vez de +100 %. Es lo que hizo upstream en v1 con las mismas skills.
3. **El listado ya desborda el presupuesto oficial en 200k** por tus 13 skills globales + 19 de
   plugins, no por el scaffold. Eso es dieta **de tu máquina** (`skillOverrides`, `/doctor`), y es la
   única parte donde aplica *How To Kill The Bloat*.
4. Los reviewers como agents cuestan ~600-900 ch si la description es una línea. Trivial.
5. Ningún número de Pocock sobre "presupuesto de instrucciones" tiene fuente y sus dos artículos se
   contradicen (150-200 vs 300-400). El único umbral con respaldo oficial es **<200 líneas por
   `CLAUDE.md`**, y el scaffold está en 103.

## Fuentes

- Matt Pocock — [Never Run Claude /init](https://www.aihero.dev/never-run-claude-init)
- Matt Pocock — [A Complete Guide To AGENTS.md](https://www.aihero.dev/a-complete-guide-to-agents-md)
- Matt Pocock — [My AGENTS.md file for building plans you actually read](https://www.aihero.dev/my-agents-md-file-for-building-plans-you-actually-read)
- Matt Pocock — [How To Kill The Bloat In Claude Code's System Prompt](https://www.aihero.dev/how-to-kill-the-bloat-in-claude-codes-system-prompt)
- Matt Pocock — [v1: 63% Token Reduction](https://www.aihero.dev/skills/skills-changelog-v1-announcement) (404 al fetch; contenido vía resumen del buscador + `CHANGELOG.md` y `.agents/invocation.md` del clon de `mattpocock/skills`)
- Matt Pocock — [What Is The Context Window?](https://www.aihero.dev/what-is-the-context-window)
- Matt Pocock — [Context pointer | AI Coding Dictionary](https://www.aihero.dev/ai-coding-dictionary/context-pointer) (404 al fetch; definición vía resumen del buscador + `writing-for-agents/SKILL.md` upstream)
- `mattpocock/skills` — `skills/productivity/writing-for-agents/SKILL-MECHANICS.md`, `.agents/invocation.md`, `CHANGELOG.md` (clon local, HEAD `6654f6b`)
- Gloaguen, Mündler, Müller, Raychev, Vechev — [Evaluating AGENTS.md: Are Repository-Level Context Files Helpful for Coding Agents?](https://arxiv.org/abs/2602.11988) (arXiv:2602.11988, v2 2026-06-23)
- Claude Code docs — [How Claude remembers your project](https://code.claude.com/docs/en/memory)
- Claude Code docs — [Extend Claude with skills](https://code.claude.com/docs/en/skills)
- Claude Code docs — [Subagents](https://code.claude.com/docs/en/sub-agents)
