# ADR-0003 — `/code-review` como foco acotado del turno-1 (ensemble con `/slice-review`)

- **Estado**: aceptada
- **Fecha**: 2026-08-26
- **Contexto de la decisión**: grill del issue 08
  (`.scratch/review-cost-redesign/issues/08-framing-premisa-code-review-caducada.md`, fuera de git —
  `.scratch/` está gitignoreado, así que lo que hay que saber está acá) + verificación empírica de
  feasibility (2026-08-26).
- **Extiende**: ADR-0001 (`0001-review-incremental-con-marcador.md`), que construyó el motor del
  review-loop sobre `/slice-review`. Una de las premisas de ADR-0001 **caducó** (ver Contexto); su
  decisión sigue válida, solo esa premisa era falsa.

## Contexto

ADR-0001 y todo el andamiaje de `/slice-review` se justificaban, en parte, sobre esta premisa: *"el
built-in `/code-review` está marcado `disable-model-invocation`, el agente no puede lanzarlo
(`Skill code-review cannot be used with Skill tool`), así que un loop que dependa de él nunca cierra
solo"*. Por eso el scaffold trae `/slice-review`, un reviewer que el agente **sí** puede invocar.

**Esa premisa caducó.** Verificado empíricamente el 2026-08-26 (regla de afirmaciones — no razonado):
se despachó un subagente `general-purpose` que invocó la herramienta Skill con `skill=code-review`.
El tool respondió `Skill "code-review" launched (forked execution, running in the background)` — **sin**
error de rechazo — y el fork **corrió hasta completarse**, auditando el delta real. O sea:
`/code-review` **es invocable por el agente**, incluso desde un subagente del fan-out. La memoria
`slice-review-motor-del-loop.md` (2026-08-13) ya pedía verificarlo antes de cerrar Track A.

Que la premisa caduque **no** invalida `/slice-review`: su valor no dependía de ella. Sigue dando lo
que el built-in no da y lo que las Hard rules del `CLAUDE.md` exigen: reparto en focos independientes
en paralelo, pase de confianza 0-100, diff local sin PR ni remoto, foco de mutación acotada, pase de
coherencia, y el cumplimiento de las reglas del proyecto (espejo, afirmaciones, techo ~400, ruteo de
modelos). Lo que quedó abierto fue una oportunidad: si `/code-review` es invocable, **sumarlo** como
reviewer independiente mejora la calidad sin sacar nada.

El criterio del usuario para decidir (grill 2026-08-25): **calidad de la skill a largo plazo,
ignorando el costo de desarrollo, con un gate duro — la corrida del review-loop NO debe tardar más.**

## Decisión

El motor del `review-loop` queda como **ensemble**: `/slice-review` de **columna vertebral** + el
built-in `/code-review` **sumado como un reviewer independiente más**, acotado.

1. **`/code-review` corre SOLO en el turno 1**, como foco par en la MISMA ola paralela del fan-out de
   Step 4 de `/slice-review`, activado por el flag `--code-review`. `/review-loop` lo pasa junto a
   `--mutation` en el turno 1 y **nunca** después. Prohibido en los turnos 2+, simétrico con el foco
   de mutación.
2. **Esfuerzo medium** (no high/max), para que no se vuelva la lane más lenta ni siquiera dentro del
   slack del turno 1 (detrás del foco de mutación, que ya es la lane más lenta: worktree + suite ×≤8).
3. **Gate de latencia satisfecho por construcción**, sin necesidad de medir: al correr solo en el
   turno 1, en paralelo, en el slack detrás de la mutación, el wall-clock del turno no se mueve. (A
   confirmar igual en la primera corrida real contra la línea base congelada — memoria
   `sesion-2026-08-11-costo-review-loop`, vence 2026-09-10.)
4. **Sus hallazgos pasan por el pase de confianza (Step 5) existente**, con el mismo corte en 60 y las
   mismas severidades. Reusa maquinaria, ~3% del costo, paralelizable.
5. **Paso de dedup nuevo** (no existía) — una colación que corre **antes del fan-out de scoring** del
   pase de confianza (Step 5), en el mismo turno, sin round-trip extra: `/code-review` solapa
   el foco de bugs, así que sin dedup entrarían hallazgos duplicados al reporte y el loop arreglaría lo
   mismo dos veces. El dedup contrasta contra el foco de bugs y colapsa por **defecto subyacente**, no
   solo por `file:line` exacto (los dos reviewers lo redactan distinto y pueden apuntar a líneas
   cercanas). Es la única parte "no-cero-mecánica" del ensemble.

## Alternativas descartadas

**(a) Quedarse solo con `/slice-review`** y corregir la framing para justificarlo por su valor, sin
sumar `/code-review`. Descartada por el criterio de calidad a largo plazo: la tesis del loop es que
reviewers independientes se componen; `/code-review` es una lente fuerte, con tuning distinto,
**mantenida por Anthropic (mejora gratis en cada release)**. Excluirla por gusto deja calidad sobre la
mesa cuando sumarla es latency-neutral.

**Reemplazar `/slice-review` por `/code-review`.** Descartada: el built-in no hace cumplir las Hard
rules del `CLAUDE.md`, no da el reparto multi-foco + confianza + coherencia, y asume un PR de GitHub.
`/slice-review` sigue siendo la columna; `/code-review` se suma, no reemplaza.

**Esfuerzo high/max para `/code-review`.** Descartada: violaría el gate de latencia — se volvería la
lane más lenta y movería el wall-clock del turno. Medium es suficiente para una segunda lente.

**Correrlo en todos los turnos.** Descartada: en los turnos 2+ (que revisan un delta chico) sería el
cuello de botella y crecería el costo con la profundidad del loop. El grueso de los hallazgos sale en
el turno 1; acotarlo ahí es lo que mantiene el gate.

**Orquestarlo desde `/review-loop` en paralelo a `/slice-review`** (en vez de como foco del fan-out de
Step 4). Era el fallback si `/code-review` no fuera invocable desde el contexto del fan-out. La
feasibility verificada (invocable incluso desde un subagente) hizo innecesario el fallback: se despacha
como foco par en la ola de Step 4, que es lo más simple y lo que ya hace el foco de mutación.

## Consecuencias

**A favor:**

- Diversidad de reviewers: una segunda lente independiente, con tuning distinto, mantenida por Anthropic
  y mejorada gratis en cada release.
- Latency-neutral por construcción: acotado a turno-1, en paralelo, en el slack detrás de la mutación,
  a esfuerzo medium.
- Reusa el pase de confianza y las severidades existentes; el único mecanismo nuevo es el dedup.

**En contra / riesgos asumidos:**

- **Solape con el foco de bugs.** Mitigado por el paso de dedup por defecto subyacente; sin él el
  reporte double-contaría.
- **Dependencia de un built-in ajeno.** El comportamiento y el contrato de invocación de `/code-review`
  los controla Anthropic; un cambio futuro (p. ej. que vuelva a ser human-only) rompería el foco. Se
  acepta: si eso pasa, el foco se saca y `/slice-review` sigue siendo la columna intacta. La premisa
  vieja ya demostró que estos contratos cambian, así que la invocabilidad se re-verifica ante cualquier
  síntoma, no se asume perpetua.
- **La medición del gate se difiere a la primera corrida real** contra la línea base de agosto (vence
  2026-09-10). Riesgo de secuencia declarado; el diseño es latency-neutral por construcción, así que la
  medición confirma, no habilita.

## Vocabulario

Usa los términos del glosario de `CONTEXT.md`: **slice**, **corrida de review**, **turno**, **reviewer**,
**foco**, **pase de confianza**, **pase de coherencia**, **mutación acotada**, **delta sin revisar**,
**afirmación**. Suma un término: **ensemble** — el motor del review-loop corre más de un reviewer
independiente (columna `/slice-review` + `/code-review` acotado al turno 1) y compone sus hallazgos por
un pase de confianza y un dedup.
