---
name: review-loop
description: Use when a small, finished vertical slice or PR is ready for review and you want to iterate review→fix→re-review until it is clean. Runs /slice-review on the diff, fixes only real findings, re-reviews, and repeats until no medium/high-severity findings remain or a 5-turn cap is hit. Trigger when the user says "pasá el review-loop", "revisá y arreglá este diff hasta que quede limpio", "loop de code-review sobre el PR", "dejá el PR sin findings", or wants an iterative review→fix cycle on a finished slice. Adapts the Greptile "greploop" / GP-loop to a local, agent-invocable reviewer (no external paid service, no PR/remote required).
---

# Review Loop

Iterate review → fix → re-review on a small change until it is clean: zero medium/high-severity findings, or a hard cap of 5 turns.

## When to use

- A vertical slice / PR is finished and ready for review.
- The diff is small enough to review reliably (see pre-flight).
- Findings are specific enough to act on, and tests/typechecks can confirm fixes.

Do not use on huge diffs (thousands of lines) or for unclear product decisions.

## The reviewer: `/slice-review`, not `/code-review`

Every turn of this loop runs **`/slice-review`** — a multi-agent reviewer over the local diff.

Do **not** substitute the built-in `/code-review`: it is marked `disable-model-invocation`, so the
agent cannot launch it (`Skill code-review cannot be used with Skill tool`). A loop built on it can
never close on its own, which is how a slice ends up reported as "reviewed" with no reviewer having
run. `/code-review` remains available for a human to type.

## Pre-flight: is the diff small enough?

Before looping, check the diff size:

```powershell
git --no-pager diff --stat
```

If the change approaches or exceeds ~400 lines of diff, stop and split it into smaller slices / stacked PRs first (matching the project's PR-size rule). The loop loses accuracy on large diffs — both the reviewer and the coding agent.

## PR mode (when triggered by the hook)

If you got here because the `review-loop-trigger` hook asked for it after a `gh pr create` / `git push`, review the **branch diff** (what the PR introduces over its base), not the working tree:

```powershell
git diff <base>...HEAD --stat   # <base> is the PR's base branch (main/develop/etc., the one the hook reported)
```

Use that same range (`git diff <base>...HEAD`) as the input of every `/slice-review` in the loop. Working-tree mode (`git diff` with no range) remains the default for manual invocation over uncommitted changes.

## Commit / local mode (when triggered by a `git commit`)

If you got here after a `git commit` (typical in local repos with no remote), review the diff of the slice just closed. If the branch has a resolvable base, use the branch range; otherwise review the last commit:

```powershell
git --no-pager diff <base>...HEAD --stat   # if there is a base (also works with a local base, no remote)
git --no-pager show --stat HEAD            # fallback: last commit only
```

Watch the base: on a long-lived branch, `main...HEAD` can drag in commits from earlier slices. Use the real base of the slice you just closed.

If the commit is only a deliberately failing test (TDD RED) and there is no implementation code to review yet, close the loop with no action: there is nothing to fix yet.

## The loop

One turn = one complete pass through these three steps:

1. Run `/slice-review` on the current diff (pass the range as its argument).
2. Read the findings. Fix ONLY findings that are real and relevant to this change. Do not rewrite unrelated code.
3. For each bug fix, add or update a test when practical. Run the relevant tests/typechecks.

After step 3, begin the next turn back at step 1 (which re-reviews the updated diff). Stop when ANY of:

- The latest `/slice-review` reported clean: no findings of medium or high severity.
- 5 turns have run.
- You are blocked by a decision that needs a human → stop and report.

Note: `/slice-review` reports findings by severity, not a numeric score — "clean" means the latest review surfaced no medium/high-severity findings (the Greptile 5/5 score does not exist here).

## Guardrails

- Reviewers produce false positives — don't blindly accept every finding.
- Agents over-fix — touch only what the finding is about.
- A clean review means this diff looks clean, not that the product is valuable.
- Tests are the objective signal; "looks fine" is not a pass.
- Never report the loop as closed if no reviewer actually ran. If `/slice-review` could not run, say so plainly instead of substituting your own read of the diff for it.

## Final report

- List the findings resolved this run.
- State the tests/typechecks run and their result.
- Note any finding deliberately not fixed (with reason) and any blocker that needs a human.
