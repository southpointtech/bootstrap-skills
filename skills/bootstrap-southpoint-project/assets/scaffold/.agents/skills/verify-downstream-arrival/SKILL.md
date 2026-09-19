---
name: verify-downstream-arrival
description: Usala antes de afirmar que un efecto llegó a su destino después de una escritura de varios saltos ("ya llegó", "ya está deployado", "se mandó el mail", "quedó sincronizado", "ya está en producción", "shipped", "deployed", "sent") — deploys, POSTs a webhooks, disparos de jobs o workflows, ingesta asíncrona por cron, cola o ETL, cambios de UI publicados, emails o notificaciones, config propagada. Exige leer el destino directamente (la fila en la base, la celda del dashboard, la URL del bundle que pide el consumidor, el log de entrega, el estado del run, el timestamp del snapshot) y no tomar un 2xx del primer salto ni un build, test o CI en verde como prueba de llegada. Si el efecto no llegó, el salto que falla lo busca debug-source-first.
---

# Verify Downstream Arrival

## Overview

A 2xx from the first writer is honest about *receipt*, not about *arrival*. The user observes the sink, not your POST response.

**Core principle:** Evidence lives at the sink, not in the response of the writer.

**Violating the letter of this rule is violating the spirit of this rule.**

**RELATED:** `superpowers:verification-before-completion` (when installed) covers the local dev loop (tests, build, lint, regression). This skill covers integration boundaries: anywhere your write crosses into a system you don't directly own the read path for. When the sink shows the effect did NOT arrive, this skill stops and `debug-source-first` takes over.

## The Iron Law

```
NO ARRIVAL CLAIMS WITHOUT READING THE SINK
```

If you haven't read the destination in this message, you cannot claim the effect arrived.

## The Gate Function

Before claiming any side effect produced its expected state:

1. **NAME the sink.** Which artifact would a user observe to verify this? Not the first 2xx — the final user-visible thing. Examples: row in DB, file at URL, email in inbox, workflow run with `final_state=success`, dashboard cell showing the new value.
2. **FETCH the sink.** Read it directly: SQL by primary key, fetch the asset URL the consumer actually requests, screenshot the UI in the environment the user uses, read the delivery log, get the run state by ID.
3. **WAIT + TIMESTAMP-VERIFY.** If the pipeline is async (cron, queue, ETL, eventual consistency), wait the known lag window — *and* confirm `sink.updated_at >= write.timestamp`. A read that returns the old value is not "didn't arrive"; it's "snapshot was taken before your write." Distinguish.
4. **COMPARE.** Does the sink confirm the effect?
   - Yes → claim WITH the evidence (cite the query result, URL fetched, screenshot, run ID).
   - No → state the gap honestly, then find the failing hop with `debug-source-first`.
   - Sink unreachable from your environment → name the gap and ask the user to confirm. Don't claim.
5. **Never infer arrival from upstream 2xx alone.**

## Mechanisms for Evidence

Technology-agnostic catalog. Pick the one matching your sink:

| Sink type | How to read | Common trap |
|-----------|-------------|-------------|
| DB / table row | `SELECT … WHERE id = X` by primary key | Listing with a filter may hit a hardcoded `LIMIT` in the caller or a default ordering window; the row exists but is past the cutoff. Read by ID. If the API only exposes a list endpoint, also check pagination metadata (`total`, `hasMore`, `limit`, `nextCursor`) before concluding absence — a 5000-row page is not the dataset. |
| Connector / ingestion dataset | Rowcount delta around your write + row read by ID | "Ingestion returned 200" can be an empty run. Check the run's inserted-row count or its last-success timestamp. |
| Snapshot / materialized view / ETL output | Read row + check `updated_at >= write.timestamp` | Value-check alone is ambiguous; the snapshot may predate your write. Old value at the sink ≠ write didn't apply. |
| Workflow / job run | Trigger returns a run ID → poll the run by ID for `final_state` | Trigger 200 = accepted, not finished. The job may still error mid-run. |
| Deployed asset / bundle | Fetch the URL the consumer (host iframe, CDN edge, browser) actually requests | Manifest endpoint 200 doesn't guarantee the asset row exists at that version. Some platforms 404 on the next request. |
| Email / notification | Delivery log or recipient confirmation | SMTP 250 / API 200 ≠ delivered. HTML may render blank in some clients even with a successful send. |
| UI feature | Screenshot or E2E run against the environment the user uses (the production host, not localhost) | "Build green + dev-server boots" proves code, not output. |
| Config / secret rotation | Read it back from the consumer that uses it | Write-side 200 doesn't propagate; cached references and warm processes may still hold the old value. |

If the project has platform-specific skills or docs for its deploy target, workflow engine or ingestion connector, they name the sink for that platform: read it there, with the same gate.

## Rationalization Prevention

| Excuse | Reality |
|--------|---------|
| "Webhook returned 200" | URL-orphan endpoints also return 200. Receipt ≠ persistence. |
| "Backend wrapper says `ok=true`" | The wrapper can lie — orphan URL, swallowed exception, no-op mock. Trust the sink. |
| "Build + tests + dev-server boot" | Proves code correctness, not observable user state. |
| "CI green" | CI covers code, not integration boundaries. |
| "Manifest endpoint 200" | The bundle row may not exist. Fetch the URL the consumer requests. |
| "Cron is running" | Firing ≠ landing. The ingestion can be in an error state while cron keeps firing. |
| "Ingestion returned 200" | Empty runs return 200. Check how many rows the run inserted. |
| "I listed and the row wasn't there" | Your list may be truncated by a hardcoded `LIMIT` or filtered by a default. Check pagination metadata; then read by ID. |
| "I read the sink and it still shows the old value" | Likely a stale snapshot. Check `updated_at` vs your write timestamp before concluding the write failed. |
| "E2E suite passed" | Tests have flakes, weak assertions, stale mocks. Distinguish "first-run green" from "green after retries." |
| "Status was 200, partial check is enough" | Partial proves nothing for the sink. |
| "Same words rephrased so the rule doesn't apply" | Spirit over letter. |

## Red Flags — STOP

- About to say "live", "shipped", "done", "deployed", "delivered" without a one-line evidence reference below it.
- "200 OK" appears in your reasoning but no sink read does.
- You read the sink but didn't check `updated_at` against your write timestamp.
- You listed or filtered the sink but didn't verify the list wasn't truncated.
- "Cron ran" or "trigger fired" used as proof, not as a precondition for verification.
- Confidence rising as time pressure rises ("the client is waiting, just send it").
- Any sentence implying success without a fresh fetch of the sink in the same turn.

## When To Apply

ALWAYS before:
- ANY claim that a side effect on an external system completed
- ANY "shipped / deployed / live / delivered / propagated / submitted / synced"
- Closing a task whose value crosses into a system you don't own the read path for
- Reporting status to a client or stakeholder

## When NOT To Apply

- Pure local code change with no external side effect → use `superpowers:verification-before-completion` (when installed)
- Investigating a reported absence or wrong value → use `debug-source-first`, which hands the failing hop to `diagnosing-bugs`
- One-off scripts whose effect is the local terminal output you just observed

## The Bottom Line

Name the sink. Fetch it. Compare timestamps. THEN claim.

If you can't read the sink from your environment, name the gap and ask. An honest "you'll need to verify X at the destination" beats a confident "it's live."
