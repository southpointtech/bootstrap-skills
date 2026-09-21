# Runbook: [what this runbook leaves working]

> **Scope.** What this runbook provisions or deploys, and what it explicitly does not cover.
>
> **Starting state.** The runbook, environment, or step this one assumes is already done.
>
> **How to run it.** Phases go in order. Every step carries its owner:
>
> - **[CLAUDE]** — the agent runs or proposes it; the human approves anything privileged.
> - **[HUMAN]** — a console flow, a login, an MFA prompt, or a secret the agent must not handle.
>
> Tick each box as the step closes. **Do not start a phase before the previous one verified.**
> A runbook is the execution plan for a deployment; the approval gates that authorize it live in
> `DEPLOYMENT_RULES.md`, and this file does not override them.

---

## Phase 0 — [name]

- [ ] **[CLAUDE]** Step, with the exact command:

  ```bash
  <command>
  ```

- [ ] **[CLAUDE]** Step.

**Verification:** the observable fact that proves the phase is done — a command's output, a row in
a table, a URL that answers, a log line. Not "it ran without errors".

---

## Phase 1 — [name]

- [ ] **[HUMAN]** Step that needs a person: credential, console, approval, payment.
- [ ] **[CLAUDE]** Step the agent runs once the human step landed.

  > Warning about any step whose order is irreversible — write it before the step, not after.

**Verification:**

---

## Phase N — [name]

- [ ] ...

**Verification:**

---

## Rollback

For each phase that changes state someone can observe: how to get back to the previous state, who
can do it, and how long the window lasts before rollback stops being possible.

## Open items

What this runbook deliberately leaves undone, and who is blocked on each item.
