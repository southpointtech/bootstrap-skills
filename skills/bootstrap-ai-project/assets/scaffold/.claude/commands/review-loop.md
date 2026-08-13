---
name: review-loop
description: Use when a small, finished vertical slice or PR is ready for review and you want to iterate review→fix→re-review until it is clean. Runs /slice-review on the diff, fixes only real findings, re-reviews, and repeats until no medium/high-severity findings remain or a 5-turn cap is hit. Adapts the Greptile "greploop" / GP-loop to a local, agent-invocable reviewer (no external paid service, no PR/remote required).
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

## The range: review the unreviewed delta, not the whole branch

Every turn reviews the **unreviewed delta** — what changed since the last review run — never the
branch's full range again. Re-reviewing already-reviewed code is the single largest waste this loop
had: the same range was once re-reviewed across 5 separate runs, 27 reviewers, 540 minutes.

The review marker is what makes the delta knowable. It is a script, not a convention:

```powershell
pwsh -NoProfile -File .claude/scripts/review-marker.ps1 -Action range     # what to hand `git diff`
pwsh -NoProfile -File .claude/scripts/review-marker.ps1 -Action advance   # cut a new marker here
pwsh -NoProfile -File .claude/scripts/review-marker.ps1 -Action get       # the stored marker, if any
```

`range` prints a **bare** ref, so the input of every review run is:

```powershell
git --no-pager diff <range>       # <range> is exactly what -Action range printed
```

Do **not** rewrite it as `<range>..HEAD`. The two-dot form only covers commits, and would drop
uncommitted work — which is precisely what the marker exists to capture.

**Empty output from `range` means there is nothing new to review.** Close the loop with no action
instead of inventing a range; do not fall back to `main...HEAD`.

Failure modes are already decided, and both err toward reviewing too much:

- With no previous marker, `range` starts at the slice base, so the first turn covers the whole slice.
- If the marker's object was pruned by `git gc`, `range` falls back to the slice base as well.
- Outside a git repo, or on a detached HEAD, the script prints nothing and you decide.

If the marker script is missing (an older scaffold), fall back to the slice's branch range
(`git diff <base>...HEAD`) and say so in the final report — do not report the loop as incremental.

## When the hook triggered this loop

The `review-loop-trigger` hook fires on `gh pr create` / `git push` / `git commit` in a feature
branch and reports the branch and its base. That tells you *which slice* closed; it does not change
where the range comes from — still `-Action range`. The reported base only matters as the fallback
above, and watch it on long-lived branches: `main...HEAD` can drag in commits from earlier slices.

If the commit is only a deliberately failing test (TDD RED) with no implementation code to review
yet, close the loop with no action: there is nothing to fix yet.

## The loop

One turn = one complete pass through these steps:

1. Ask the marker for the range (`-Action range`). **Empty → the loop is done; close it.**
2. Run `/slice-review` on `git diff <range>` (pass the range as its argument).
3. Advance the marker (`-Action advance`). Do this **after the review run and BEFORE applying
   fixes**: the reviewer has now seen everything up to this point, and the fixes you are about to
   write become the next turn's unreviewed delta. Advancing after fixing would hand the next turn an
   empty range and the fixes would never be reviewed by anyone — which is the exact failure this
   loop exists to prevent.
4. Read the findings. Fix ONLY findings that are real and relevant to this change. Do not rewrite unrelated code.
5. For each bug fix, first write a test that **fails without the fix** — run it and watch it fail (RED)
   before writing the fix. A test that never failed is not a net. Then apply the fix, re-run the test,
   and run the relevant tests/typechecks.

After step 5, begin the next turn back at step 1 — which now reviews only the fixes you just made. Stop when ANY of:

- The latest `/slice-review` reported clean: no findings of medium or high severity.
- `range` came back empty.
- 5 turns have run.
- You are blocked by a decision that needs a human → stop and report.

Note: `/slice-review` reports findings by severity, not a numeric score — "clean" means the latest review surfaced no medium/high-severity findings (the Greptile 5/5 score does not exist here).

## Guardrails

- Reviewers produce false positives — don't blindly accept every finding.
- Agents over-fix — touch only what the finding is about.
- A clean review means this diff looks clean, not that the product is valuable.
- Tests are the objective signal; "looks fine" is not a pass.
- A fix whose test never went RED is unverified — the loop's own fixes are where regressions come from.
- Never report the loop as closed if no reviewer actually ran. If `/slice-review` could not run, say so plainly instead of substituting your own read of the diff for it.

## Final report

- List the findings resolved this run.
- State the tests/typechecks run and their result, including which fixes went RED before green.
- Note any finding deliberately not fixed (with reason) and any blocker that needs a human.
