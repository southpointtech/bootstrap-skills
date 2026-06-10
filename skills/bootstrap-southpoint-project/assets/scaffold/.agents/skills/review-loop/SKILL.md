---
name: review-loop
description: Use when a small, finished vertical slice or PR is ready for review and you want to iterate review→fix→re-review until it is clean. Runs /code-review on the diff, fixes only real findings, re-reviews, and repeats until no medium/high-severity findings remain or a 5-turn cap is hit. Adapts the Greptile "greploop" / GP-loop to Claude Code's native reviewer (no external paid service, no PR/remote required).
---

# Review Loop

Iterate review → fix → re-review on a small change until it is clean: zero medium/high-severity findings, or a hard cap of 5 turns.

## When to use

- A vertical slice / PR is finished and ready for review.
- The diff is small enough to review reliably (see pre-flight).
- Findings are specific enough to act on, and tests/typechecks can confirm fixes.

Do not use on huge diffs (thousands of lines) or for unclear product decisions.

## Pre-flight: is the diff small enough?

Before looping, check the diff size:

```powershell
git --no-pager diff --stat
```

If the change is large (approaching thousands of lines, or well over ~400 lines), stop and split it into smaller slices / stacked PRs first. The loop loses accuracy on large diffs — both the reviewer and the coding agent.

## The loop (max 5 turns)

1. Run `/code-review` on the current diff.
2. Read the findings. Fix ONLY findings that are real and relevant to this change. Do not rewrite unrelated code.
3. For each bug fix, add or update a test when practical. Run the relevant tests/typechecks.
4. Re-run `/code-review`.
5. Repeat from step 1.

Stop when ANY of:

- No findings of medium or high severity remain.
- 5 turns reached.
- Blocked by a decision that needs a human → stop and report.

Note: `/code-review` reports findings by severity, not a numeric score — "clean" means no medium/high-severity findings remain, which is this loop's exit condition (the Greptile 5/5 score does not exist here).

## Guardrails

- Reviewers produce false positives — don't blindly accept every finding.
- Agents over-fix — touch only what the finding is about.
- A clean review means this diff looks clean, not that the product is valuable.
- Tests are the objective signal; "looks fine" is not a pass.

## Final report

- List the findings resolved this run.
- State the tests/typechecks run and their result.
- Note any finding deliberately not fixed (with reason) and any blocker that needs a human.
