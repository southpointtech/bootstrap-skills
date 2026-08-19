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

Before looping, check the size of what you are about to review — the range from the next section,
not the working tree. On the dominant path (the hook fires right after a commit) the tree is clean,
so a bare `git diff --stat` prints nothing and the size rule silently never applies:

```powershell
git --no-pager diff --stat <range>
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
uncommitted work — which is precisely what the marker exists to capture. Worse than narrower: when
the marker came from `git stash create`, its first parent *is* HEAD, so `git diff <range>..HEAD`
prints the working-tree changes **inverted** — the reviewer reads a reversed diff and reports clean.

`git diff` never shows untracked files. Pass them to the reviewer alongside the range (both this and
the marker commands are run from the **repo root**; from a subdirectory `ls-files` only lists that
subtree while the diff covers everything). `core.quotepath=false` keeps accented filenames readable
instead of escaped to octal:

```powershell
git -c core.quotepath=false ls-files --others --exclude-standard
```

**Read the exit code — empty output means two different things:**

| Exit | Output | Meaning | What you do |
|---|---|---|---|
| 0 | a ref | there is unreviewed delta | review `git diff <ref>` |
| 0 | empty | genuinely nothing new since the last review run | close the loop |
| 2 | empty | undeterminable — see below | **do not close the loop**; pick the recovery that applies and say so in the report |

Exit 2 is one signal for several situations, so check which one you are in before recovering:

- **Detached HEAD, or no base could be resolved** (the current branch is the repo's only ref, or an
  orphan branch with no common ancestor) → review the working tree (`git diff HEAD`) if it is
  dirty; if it is clean, review the last commit (`git show HEAD`). Do not reach for
  `git diff <base>...HEAD` here — the base is exactly what could not be resolved.
- **Not a git repo, or a repo with no commits** (`git rev-parse --git-dir` or `git rev-parse HEAD`
  fails) → there is nothing a `git diff` can review. Report that plainly and stop; do not claim
  the slice was reviewed.

On empty **with exit 0**, close: everything up to the marker was already reviewed, so do not fall
back to `main...HEAD` and do not invent a range — that re-review is the waste the marker removes.

Never treat exit 2 as "clean". Closing on it is how a slice gets reported reviewed with no reviewer
having run, which this loop exists to prevent.

Failure modes err toward reviewing too much:

- With no previous marker, `range` starts at the slice base, so the first turn covers the whole slice.
- If the marker's object was pruned by `git gc`, `range` falls back to the slice base as well.
- The base is not assumed to be called `main`. When one of the usual names resolves
  (`origin/HEAD`, `main`, `master`, `develop`, or their `origin/` forms) the base is the merge-base
  **nearest** HEAD among them — they are all plausible bases, and that keeps unpushed commits on
  `develop` inside the range. Only when none of them resolves — a repo based on `trunk`, `dev`,
  `release` — do other refs come into play, and there the base is the **farthest** common ancestor
  of all of them: a branch cut from the middle of this slice (a `wip` backup, a worktree, an
  upstream pushed under another name) is always nearer than the real base, so picking the nearest
  would drop the slice's own earlier commits.
- On the base branch itself HEAD is a legitimate base: nothing branched off, so the range covers the
  uncommitted work. That holds only while every candidate ref points at HEAD — a sibling branch left
  behind HEAD makes the range start at its fork point instead, which reviews more than the slice
  rather than less. When the current branch is the repo's only ref — or an orphan branch
  with no common ancestor — nothing can tell a base from a slice, so `range` reports exit 2 rather
  than emitting HEAD and hiding the branch's own commits behind a confident-looking exit 0. A repo
  freshly created by the bootstrap skills is in that shape until its first feature branch exists;
  work in a feature branch per slice and the case does not arise.

One case does **not** err that way: after `commit --amend`, `rebase` or `reset --hard`, a marker
that still resolves but is no longer an ancestor of HEAD yields a diff containing reverted hunks.
If the diff shows changes you did not make, ignore the marker and review the slice's branch range.

If the marker script is missing (an older scaffold), fall back to the slice's branch range
(`git diff <base>...HEAD`) and say so in the final report — do not report the loop as incremental.
Check with `Test-Path` before invoking it: `pwsh -File` on a missing script prints its usage block
to **stdout**, which looks exactly like a range if you only read stdout.

## When the hook triggered this loop

The `review-loop-trigger` hook fires on `gh pr create` / `git push` in a feature branch, and on a
commit that DECLARES the close of a slice with a `Slice-Close:` trailer in its message. A commit
without that trailer does not fire it — unless the unreviewed delta has already passed the
~400-line safety net, which fires anyway so that forgetting the trailer cannot leave a big slice
unreviewed. The hook reports the branch and its base. That tells you *which slice* closed; it does
not change where the range comes from — still `-Action range`. The reported base only matters as
the fallback above, and watch it on long-lived branches: `main...HEAD` can drag in commits from
earlier slices.

If the commit is only a deliberately failing test (TDD RED) with no implementation code to review
yet, close the loop with no action: there is nothing to fix yet. The trailer belongs on the commit
that finishes the slice, so a RED commit normally does not declare a close at all.

## The loop

One turn = one complete pass through these steps:

1. Ask the marker for the range (`-Action range`). **Empty with exit 0 → the loop is done; close
   it. Empty with exit 2 → undeterminable; recover as the exit-code section above says, and do
   not close.**
2. Run `/slice-review` on `git diff <range>` (pass the range as its argument), plus the untracked
   files the range does not carry.
3. Advance the marker (`-Action advance`) — but **only if a reviewer actually ran and returned a
   report**. If the review run failed or was interrupted, leave the marker where it is: advancing
   past code nobody read hides it from every future turn, and there is no verb to walk it back.
   Do this **after the review run and BEFORE applying fixes**: the reviewer has now seen everything
   up to this point, and the fixes you are about to write become the next turn's unreviewed delta.
   Advancing after fixing would hand the next turn an empty range and the fixes would never be
   reviewed by anyone — which is the exact failure this loop exists to prevent.
4. Read the findings. Fix ONLY findings that are real and relevant to this change. Do not rewrite unrelated code.
5. For each bug fix, first write a test that **fails without the fix** — run it and watch it fail (RED)
   before writing the fix. A test that never failed is not a net. Then apply the fix, re-run the test,
   and run the relevant tests/typechecks.

After step 5, begin the next turn back at step 1 — which now reviews only the fixes you just made. Stop when ANY of:

- The latest `/slice-review` reported clean: no findings of medium or high severity.
- `range` came back empty **with exit 0** (exit 2 is not a stop condition).
- 5 turns have run.
- You are blocked by a decision that needs a human → stop and report.

Note: `/slice-review` reports findings by severity, not a numeric score — "clean" means the latest review surfaced no medium/high-severity findings (the Greptile 5/5 score does not exist here).

## At close: the coherence pass

However the loop ended — clean, or at the 5-turn cap — run the coherence pass **once** before the
final report:

```
/slice-review --coherence
```

It reads the **whole slice** as a unit against its declared intent (on Sonnet 5, read-only,
executing nothing), catching the defect that survives every per-turn delta review because it only
shows in the whole — a slice whose pieces each passed but that does not cohere against what it set
out to do. Its findings go through the same confidence pass as any other; fix the real ones as in
step 5 (a test that fails without the fix first), then report.

Run it on **both** exits — clean and cap — because a slice can pass every delta review and still
fail to cohere as a unit; the cap exit needs it most, since it closes with findings still open.
Skip it only when no reviewer ever ran this loop: an empty range with nothing to review from the
first turn (a RED-only commit, or a slice already fully reviewed before the loop began). With
nothing read, there is no slice to check for coherence.

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
