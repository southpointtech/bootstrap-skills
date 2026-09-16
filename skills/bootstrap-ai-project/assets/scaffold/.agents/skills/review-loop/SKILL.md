---
name: review-loop
description: Use when a small, finished vertical slice or PR is ready for review and you want to iterate review→fix→re-review until it is clean. Runs /slice-review on the diff, fixes only real findings, re-reviews, and repeats until no medium/high-severity findings remain or the turn cap is hit (2 turns; 1 when the slice declares `Review-Rigor: light`). Trigger when the user says "pasá el review-loop", "revisá y arreglá este diff hasta que quede limpio", "loop de code-review sobre el PR", "dejá el PR sin findings", or wants an iterative review→fix cycle on a finished slice. Adapts the Greptile "greploop" / GP-loop to a local, agent-invocable reviewer (no external paid service, no PR/remote required).
---

# Review Loop

Iterate review → fix → re-review on a small change until it is clean: zero medium/high-severity findings, or the turn cap — **2 turns**, or **1** for a slice that declares `Review-Rigor: light` (see **Rigor** below).

## When to use

- A vertical slice / PR is finished and ready for review.
- The diff is small enough to review reliably (see pre-flight).
- Findings are specific enough to act on, and tests/typechecks can confirm fixes.

Do not use on huge diffs (thousands of lines) or for unclear product decisions.

## Rigor: light or standard

How much review a slice gets is declared by the agent, per slice, next to the close trailer:

```
Slice-Close: <what closed>
Review-Rigor: light
```

| Rigor | Turn cap | Turn 1 runs | Coherence pass | What blocks the close |
|---|---|---|---|---|
| `light` | 1 | `/slice-review --light`: the Bugs and Tests focuses only | skipped | a High finding |
| `standard` (default) | 2 | the five focuses, plus `--mutation` and `--code-review` | runs at close | a High or Medium finding |

Decide the rigor **once, on turn 1**, and keep it for the whole loop: only a promotion changes it,
and only upward. It is `light` only if the newest commit in the unreviewed range (HEAD) carries a
`Slice-Close:` line, **every** commit in the range that carries one also carries
`Review-Rigor: light`, and no tracked file has uncommitted changes (the marker's range carries
them, and they belong to no declared close). Anything else is `standard`: no trailer, a mix,
commits after the last close, a dirty tree, or a loop fired by `git push` or by the ~400-line net
with no `Slice-Close:` in the range. If `range` exited 2, the rigor is `standard`. Match the lines
anywhere in the message, as the hook does: git's own trailer parser reads only the last paragraph,
so it misses a trailer written above the attribution block.

```powershell
$msgs   = @(git rev-list "<range>..HEAD" | ForEach-Object { (git log -1 --format=%B $_) -join "`n" })
$closes = @($msgs | Where-Object { $_ -match '(?m)^\s*Slice-Close:' })
$head   = (git log -1 --format=%B HEAD) -join "`n"
$dirty  = @(git status --porcelain --untracked-files=no).Count -gt 0
$light  = -not $dirty -and $msgs.Count -gt 0 -and
          $head -match '(?m)^\s*Slice-Close:' -and
          @($closes | Where-Object { $_ -notmatch '(?m)^\s*Review-Rigor:\s*light\s*$' }).Count -eq 0
```

`<range>..HEAD` lists commits here, not a diff, so the two-dot warning in the next section does not
apply to it.

Declare `light` for a slice with a low blast radius: a local tool or script, a tests-only change, or
a refactor that preserves behavior. Keep `standard` for anything a client or production depends on,
data writes or migrations, security, auth, money, or deploy config. When in doubt, `standard`.

A High in a `light` slice promotes it to `standard` on that same turn: fix the High and that turn's
real Medium findings, and run turn 2 on those fixes, so no fix ships unreviewed.

## The reviewer: `/slice-review` as backbone, `/code-review` as a turn-1 extra

Every turn of this loop runs **`/slice-review`** — a multi-agent reviewer over the local diff. It is
the backbone: it enforces this project's `CLAUDE.md` hard rules, splits the review across parallel
focuses, filters findings through a confidence pass, and runs a whole-slice coherence pass at close —
none of which the built-in `/code-review` does.

On the **first turn only**, the loop **also** runs the built-in **`/code-review`** as one more
independent reviewer, folded into `/slice-review`'s fan-out via `--code-review` (see its Code-review
focus). The built-in turned out to be agent-invocable after all, so adding it costs almost nothing
but buys reviewer diversity — a second, differently-tuned reviewer maintained by Anthropic. It is
bounded to turn 1 at medium effort with the intent of staying latency-neutral — to be confirmed on
the first real run against the frozen baseline (see `docs/adr/0003-code-review-como-foco-acotado.md`).

## Pre-flight: is the diff small enough?

Before looping, check the size of what you are about to review — the range from the next section,
not the working tree. On the dominant path (the hook fires right after a commit) the tree is clean,
so a bare `git diff --stat` prints nothing and the size rule silently never applies:

```powershell
git --no-pager diff --stat <range>
```

If the change approaches or exceeds ~400 lines of diff, say so in the final report — do NOT split the slice here. The project's PR-size ceiling is measured when the slice OPENS, and by this point the slice is already closed; splitting mid-loop breaks the loop, whose every turn reviews a range anchored to the review marker. Lines this loop adds while fixing its own findings are exempt from that ceiling. The loop still loses accuracy on large diffs — both the reviewer and the coding agent — so report how big this range is. Stop at the size: never turn it into a verdict about how the slice was planned. No range measured here can establish that — not on turn 2 onward, where the range IS the loop's own fixes, and not on turn 1 either, where it is the closing diff and the ceiling was spent at open. It says nothing about what the slice projected when it opened.

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
   it as the stop conditions and the At close section say. Empty with exit 2 → undeterminable; recover as the exit-code section above says, and do
   not close.** On the **first turn only**, once there is something to review, record where this
   slice starts so the coherence pass at close reads only this slice and not the whole stacked
   branch: `-Action open`. It snapshots the marker as it stands right now — the previous slice's
   close — and the `advance` in step 3 then moves the marker forward but leaves that snapshot put.
   `open` is **write-once**: if this slice already recorded an anchor — a re-run of a slice that hit
   the cap without closing — it keeps the original start instead of re-snapshotting the by-now
   advanced marker, so a re-run never under-scopes the coherence pass. A missing or pruned marker
   records nothing, and the coherence pass falls back to the branch base. A `light` loop runs
   `open` too: it costs nothing, and if a High promotes the slice, its coherence pass reads the
   anchor turn 1 recorded (`-Action slice-base`).
2. Run `/slice-review` on `git diff <range>` (pass the range as its argument), plus the untracked
   files the range does not carry. In a `light` loop pass **`--light`** and no other flag. In
   `standard`, on the **first turn only**, add **`--mutation` and
   `--code-review`** so `/slice-review` also runs the **Mutation focus** — which checks the slice's
   tests have teeth by breaking changed lines and seeing whether a test notices — and adds the
   built-in **`/code-review`** as an extra independent reviewer. Later turns must not carry either
   flag: both focuses are **prohibited on turns 2 onward**, keeping the per-turn cost flat.
3. Advance the marker (`-Action advance`) — but **only if a reviewer actually ran and returned a
   report**. If the review run failed or was interrupted, leave the marker where it is: advancing
   past code nobody read hides it from every future turn, and there is no verb to walk it back.
   On turn 1, first make sure the `/code-review` fork has **fully finished** and no stale
   `.git/index.lock` remains — it runs `git` concurrently, so a lock left behind makes `git stash
   create` fail silently and `advance` fall back to HEAD, over-scoping the next turn.
   Do this **after the review run and BEFORE applying fixes**: the reviewer has now seen everything
   up to this point, and the fixes you are about to write become the next turn's unreviewed delta.
   Advancing after fixing would hand the next turn an empty range and the fixes would never be
   reviewed by anyone — which is the exact failure this loop exists to prevent.
4. Read the findings. A finding whose suggested fix comes marked **REJECTED** by the confidence pass
   is a **real finding with a bad suggestion** — the defect stands at its own severity; only the
   suggestion was thrown out, and writing a better one is your job.
   Fix ONLY findings that are real, relevant to this change, and **Medium or High**
   — in `light`, **High only**: a `light` slice reports its Medium findings as deliberately not
   fixed, because no turn would review their fix. When a High promotes the slice, fix that turn's
   real Medium findings too: turn 2 reviews them. Low findings are reported, not fixed. Do not
   rewrite unrelated code. Do not re-edit a comment, docstring or message that an earlier turn of
   this same loop wrote, unless the new finding about it scored Medium or High.
5. For each bug fix, first write a test that **fails without the fix** — run it and watch it fail (RED)
   before writing the fix. A test that never failed is not a net. Then apply the fix, re-run the test,
   and run the relevant tests/typechecks.

After step 5, begin the next turn back at step 1 — which now reviews only the fixes you just made. Stop when ANY of:

- The latest `/slice-review` reported clean: no findings of medium or high severity (in `light`,
  no High).
- `range` came back empty **with exit 0** (exit 2 is not a stop condition). After a turn whose
  reviewer ran, this means you fixed nothing because you judged every Medium/High not real: that
  is a **clean close** — unless the last review reported a Medium/High you judged **real** and left
  unfixed (a rejected suggestion you could not replace, or a call that needs a human). Then it is a
  cap or blocked close, never a clean one. On the first turn no reviewer ran this loop: stop, with
  no coherence pass and no `-Action close`.
- The unreviewed delta is only prose with no behavior change: comments, docstrings, or `.md` files
  **outside** the paths `CLAUDE.md` says govern the agent (`CLAUDE.md` anywhere, `.claude/`,
  `.agents/`, `docs/ai-workflow/`, `docs/agents/`). An edit to a governing file is behavior, so it
  keeps the next turn.
- The turn cap in the **Rigor** table has run (a promoted slice has the `standard` cap).
- You are blocked by a decision that needs a human → stop and report.

Note: `/slice-review` reports findings by severity, not a numeric score — "clean" means the latest review surfaced no medium/high-severity findings (the Greptile 5/5 score does not exist here).

## At close: the coherence pass

However a `standard` loop ended — clean, prose-only delta, or at the turn cap — run the coherence pass **once** before the
final report:

```
/slice-review --coherence
```

It reads the **whole slice** as a unit against its declared intent (on a lighter, faster model,
read-only,
executing nothing), catching the defect that survives every per-turn delta review because it only
shows in the whole — a slice whose pieces each passed but that does not cohere against what it set
out to do. Its findings go through the same confidence pass as any other; fix the real ones as in
step 5 (a test that fails without the fix first), then report.

Run it on **every** exit that closes the loop — clean, prose-only and cap — because a slice can pass every delta review and still
fail to cohere as a unit; the cap exit needs it most, since it closes with findings still open.
Skip it only when no reviewer ever ran this loop: an empty range with nothing to review from the
first turn (a RED-only commit, or a slice already fully reviewed before the loop began). With
nothing read, there is no slice to check for coherence.

A `light` loop skips it: its point is one cheap turn, and its slices are the ones where a
whole-slice re-read buys the least.

Name the close before acting on it; the final report states it:

- **clean close** — the last review left no Medium/High you judged real (in `light`: no High). This
  holds even when that review was the cap turn, and covers an empty range after a reviewed turn. A
  Medium/High carrying a **REJECTED** suggestion is real unless you can say why the defect itself is
  not, so a close over one is not clean.
- **prose-only close** — the prose-only stop condition fired **before** the cap ran.
- **cap close** — the cap ran and its last review reported a Medium/High (a High in `light`
  promotes, so in practice `standard`). Its fixes were never reviewed, so a prose-only fix delta
  left by that last turn is still a cap close.

A stop because you are blocked on a human decision, and an empty range on the first turn, are
**not** closes.

Run `-Action close` on a **clean** or **prose-only** close only, strictly after the coherence pass
when one runs (a `light` loop has none to wait for). It deletes `slice-open:<branch>` so the next
slice's first-turn `open` records its own start instead of inheriting this one's. Do **not** run it
on a cap close, a blocked stop, or a first-turn empty range: each may be followed by a re-run of the
same slice, and keeping the anchor (`open` is write-once) keeps that re-run scoped to the slice's
real start instead of under-scoping to the advanced marker. Order matters — the coherence pass reads
the anchor via `-Action slice-base`, so `close` runs strictly after it. See `docs/adr/0002-limpieza-del-ancla-de-coherencia.md`.

## Guardrails

- Reviewers produce false positives — don't blindly accept every finding.
- Agents over-fix — touch only what the finding is about.
- A clean review means this diff looks clean, not that the product is valuable.
- Tests are the objective signal; "looks fine" is not a pass.
- A fix whose test never went RED is unverified — the loop's own fixes are where regressions come from.
- Never report the loop as closed if no reviewer actually ran. If `/slice-review` could not run, say so plainly instead of substituting your own read of the diff for it.

## Final report

- State the rigor (`light` or `standard`) and how the loop closed: clean, prose-only delta, or cap.
- List the findings resolved this run.
- State the tests/typechecks run and their result, including which fixes went RED before green.
- Note any finding deliberately not fixed (with reason) and any blocker that needs a human.
