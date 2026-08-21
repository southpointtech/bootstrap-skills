---
description: Run a multi-agent code review over a local diff (no PR or remote required) and report findings by severity with a confidence pass that filters false positives. Use as step 1 of the review-loop, or standalone to review a finished slice.
argument-hint: [diff range — a bare ref from the review marker, or e.g. main...HEAD; or --coherence for the whole-slice coherence pass; defaults to the unreviewed delta from the marker]
---

# Slice Review

An agent-invocable code reviewer for **local** diffs. Unlike the built-in `/code-review` (which is
restricted to human invocation and assumes a GitHub PR), this command can be launched by the agent
itself, so `/review-loop` can actually close its loop.

Reviewers run as parallel subagents with distinct focus areas, then every finding goes through a
confidence pass before it reaches the report. That second pass is what keeps the loop from
"fixing" false positives.

## Step 1 — Resolve what to review

If `$ARGUMENTS` is `--coherence`, do not resolve a delta range here: jump straight to the
**Coherence pass** section at the end. That section reviews the whole slice at once rather than the
unreviewed delta, and it states which steps it replaces (this delta resolution and Step 4's
five-way fan-out) and which it reuses (Step 1's `ls-files`, Step 3's shared context, Step 5's
confidence pass, Step 6's report).

If `$ARGUMENTS` contains `--mutation`, strip that token and treat the rest as the range — it
combines with a range (`abc123 --mutation`) or stands alone and defaults to the marker delta
(standalone, opt in with `/slice-review --mutation`). It additionally turns on the **Mutation
focus** in Step 4's fan-out. `--mutation` and `--coherence` are **mutually exclusive**; if both
appear, `--coherence` wins and `--mutation` is ignored — they never co-occur in the normal flow
(mutation is a turn-1 focus, coherence a close-time pass).

Use `$ARGUMENTS` as the diff range when provided (e.g. `main...HEAD`, `abc123..HEAD`, or a **bare**
ref such as `abc123`). Use it **exactly as given** — never append `..HEAD` to a bare ref. When it
came from `/review-loop`'s marker it is a `git stash create` object whose first parent is HEAD, so
`git diff <ref>..HEAD` prints the working-tree changes **inverted**: you would review a reversed
diff and report it clean. `git diff <bare ref>` is the whole contract.

**New files are not in the diff.** `git diff` never shows untracked files, so a range alone can
hide the whole point of the change — the loop's fix step writes a brand-new test file, which is
untracked until someone commits it. List them and review their contents too:

```powershell
git -c core.quotepath=false ls-files --others --exclude-standard    # from the repo root
```

Without arguments, the default target is the **unreviewed delta** — what changed since the last
review run — resolved from the review marker, exactly the way `/review-loop` gets it. The whole
branch range is **not** the default: re-reviewing already-reviewed code is the waste the marker
exists to remove, and reviewing the full slice range is reserved for the coherence pass.

Check the marker script exists **before** invoking it — `pwsh -File` on a missing script does not
fail cleanly, it prints its usage block to **stdout**, which looks exactly like a range if you only
read stdout:

```powershell
Test-Path .claude/scripts/review-marker.ps1
```

If it is **missing** (an older scaffold, so there is no marker), fall back to the slice's branch
range (`git diff <base>...HEAD`) and say in the report that this run is **not incremental** — do
not mistake the usage dump for a range. Otherwise ask the marker (from the repo root):

```powershell
pwsh -NoProfile -File .claude/scripts/review-marker.ps1 -Action range
```

Read the **exit code**, not just the output — empty output means different things at exit 0 and at
exit 2:

- **exit 0 + a bare ref** → that ref is the range; review `git diff <ref>` (plus untracked files).
- **exit 0 + empty** → everything up to the marker was already reviewed. Report "nothing to
  review" and stop. Do **not** fall back to `main...HEAD` or invent a range — that re-review is
  exactly what the marker exists to remove.
- **exit 2 + empty** → undeterminable; do not treat it as "nothing to review". Which recovery to
  pick depends on why the base could not be resolved:
  - **detached HEAD, the repo's only ref, or an orphan branch** (no base could be resolved) →
    review the working tree (`git diff HEAD`) if it is dirty, else the last commit (`git show
    HEAD`), and say in the report that the run is not incremental.
    Do not reach for `git diff <base>...HEAD` here — the base is exactly what could not
    be resolved (unlike the missing-script case above, where the base *can* be resolved).
  - **not a git repo, or a repo with no commits** → there is nothing a `git diff` can review.
    Report that plainly and stop; do **not** reach for `git show HEAD` (it fails with no commits)
    and do not claim the slice was reviewed.

State the resolved target out loud before reviewing. Getting the base wrong is the most common
failure of this command: on long-lived branches `main...HEAD` can drag in commits from earlier
slices. If the range looks bigger than the slice you just closed, use the real base of the slice.

An empty diff with untracked files present is not nothing: it is the normal shape of a change made
entirely of new files — review their contents.

## Step 2 — Pre-flight

```powershell
git --no-pager diff <range> --stat
```

If the change approaches or exceeds ~400 lines of logic diff, say so: reviewer accuracy drops
sharply on large diffs. Review it anyway, but flag in the final report that the slice should have
been split.

If the diff is only a deliberately failing test (TDD RED) with no implementation yet, close with no
findings — there is nothing to review.

## Step 3 — Gather shared context (once)

Collect this and hand it to every reviewer, so none of them re-derives it:

- The diff itself (`git diff <range>`), **plus the contents of the untracked files** — they are
  part of the change and appear in no diff.
- The list of changed files.
- Paths of the relevant `CLAUDE.md` files: the root one, plus any in the directories touched.
- The slice's intent: the task/PRD/commit message it implements.

Put this instruction verbatim at the top of that shared context, so every focus receives it **once**
instead of it being re-pasted into each prompt by hand:

> **You are a reviewer, not an editor. Do NOT use Write, Edit, or any file-mutating tool — not even
> to fix what you find. Return findings only; fixing is the caller's job.** A reviewer that changes
> the tree corrupts the diff every other parallel reviewer is reading, and the confidence pass then
> scores those mutations as findings.

In a measured run, 84 of 345 reviewers used Write/Edit despite the prose telling them not to;
declaring the prohibition once, in the context all focuses share, is what stops it.

## Step 4 — Fan out parallel reviewers

Dispatch these as **parallel subagents** (`general-purpose`), all in a single message so they run
concurrently. Give each one the shared context from Step 3 and its own focus. Each returns a list
of findings; every finding must carry `file:line`, what is wrong, and why it matters.

**Models by focus** — mechanical audits run on a lighter model, judgment calls on the strongest:
project rules and historical context on **Sonnet 5**; bugs, contracts and tests on **Opus 5**. Pass
the model explicitly when you dispatch each subagent, so the run does not silently default all five
focuses to one model. The split is why this step got cheaper without losing precision: the two
audits that are pattern-matching against a file (`CLAUDE.md` rules, `git log`) do not need the
strongest model; the three that require reading logic and predicting failure do.

1. **Bugs** *(Opus 5)* — read the changed lines and hunt for real defects: wrong logic, unhandled
   errors, null/undefined paths, off-by-one, race conditions, resource leaks, broken async. Focus
   on the change itself, not the whole codebase. Skip nitpicks.
2. **Project rules** *(Sonnet 5)* — audit the change against the `CLAUDE.md` files. Flag only rules
   the file actually states, quoting the rule. `CLAUDE.md` is guidance for writing code, so not
   every line is a review criterion.
3. **Historical context** *(Sonnet 5)* — read `git log`/`git blame` for the modified regions. Flag
   anything that reintroduces a previously fixed bug, contradicts a deliberate past decision, or
   repeats a pattern that was already corrected here.
4. **Contracts and callers** *(Opus 5)* — check the change against the code around it: callers of
   every modified signature, comments and docstrings that state invariants, and existing types.
   Flag silent breaks in behavior a caller depends on.
5. **Tests** *(Opus 5)* — is the changed logic actually covered? Flag risky logic shipped with no
   test, tests asserting on mocks instead of behavior, and tests that would pass even if the feature
   broke.

**If `--mutation` was passed** — only `/review-loop`'s first turn does, or a standalone opt-in —
dispatch a **sixth focus** in the same parallel message: the **Mutation focus** (see its section
after Step 6). It verifies the slice's tests have teeth; unlike these five, it executes.

## Step 5 — Confidence pass (filter false positives)

Reviewers over-report. For each finding returned by the reviewers — Step 4's focuses, or the
coherence focus — dispatch a **parallel** subagent that
receives the finding plus the diff and scores it 0-100 — **the confidence pass runs on Opus 5**, the
same as the judgment reviewers: it is the only filter for false positives, costs ~3% of the run, and
is not where to save tokens. Give it this rubric verbatim:

- **90-100** — Certain. Verified in the code; the described failure clearly happens.
- **70-89** — Likely. Strong evidence, small chance context elsewhere makes it moot.
- **40-69** — Speculative. Plausible reading, but the reviewer did not prove it.
- **0-39** — False positive: already handled elsewhere, misread code, out of scope for this diff,
  or a rule the `CLAUDE.md` never actually states.

The scorer must check the claim against the real code, not just judge whether it sounds plausible.
For rule violations, it must confirm the rule literally exists in a `CLAUDE.md`.

**Drop everything below 60.** Findings that survive get classified:

- **High** — data loss/corruption, security holes, credential exposure, or a broken golden path.
- **Medium** — real bug in an edge case, violated project rule, risky logic shipped untested,
  contract break for an existing caller.
- **Low** — style, naming, nitpicks, speculative improvements.

## Step 6 — Report

Report findings grouped by severity, each as: `file:line` — the problem — why it matters — the
suggested fix. Then state explicitly:

- How many findings were dropped by the confidence pass (so the review's silence is legible).
- The diff range that was actually reviewed.
- **Clean** or **not clean**: clean means zero High and zero Medium findings.

Do not fix anything in this command — reporting is its whole job. Fixing belongs to the caller
(`/review-loop`) or to the human.

## Mutation focus

The five focuses in Step 4 only **read**. This one **executes**: it checks that the slice's tests
have teeth by breaking the changed code on purpose and seeing whether a test notices. A test that
stays green while its code is broken protects nothing — this focus finds those. It is dispatched
**only when `--mutation` was passed**, as a sixth focus alongside the five, in the same parallel
message.

The budget is the feature, not a detail, because it is what keeps the one executing focus from
making the loop expensive:

- **Only on the loop's first turn.** `/review-loop` passes `--mutation` on turn 1 and never after,
  so the per-turn cost does not grow with the depth of the loop.
  This focus is **prohibited on turns 2 onward** — turns 2+ never carry the flag.
- **At most 8 mutants**, one per changed line.
- **Only the logic lines the slice changed** — not the whole module, not the whole file.
- **Only the relevant test file**, never the whole suite.

Dispatch it on **the most capable model available** — do not pin a version (the strongest model you
are running). Give it the shared context from Step 3, the write prohibition included.

**It runs in an isolated git worktree, never in the user's tree.** Mutating code must not touch the
tree the user works in, and must not corrupt the diff the other five parallel reviewers are reading.
Build the worktree from the **live slice state**, not from the marker SHA — the marker is a `git
stash create` object that cannot hold untracked files, and on turn 1 it points at the slice's
*start*, not its new code, so a checkout of it would contain neither the slice's changes nor its
brand-new (untracked) test files:

```powershell
$snap = (git stash create); if (-not $snap) { $snap = "HEAD" }   # captures tracked, uncommitted work
git worktree add --detach $tmp $snap                             # $tmp is a temp dir OUTSIDE the repo
git -c core.quotepath=false ls-files --others --exclude-standard # copy each of these into $tmp, same paths
```

Now `$tmp` holds the slice as it actually stands (tracked + untracked), and the user's tree is
untouched. Use the **marker only to identify which lines changed** (`git diff <range>` from Step 1),
never to build the worktree.

**Apply the mutants one at a time** — one mutation, run the relevant test file, revert, then the
next; never all eight at once (accumulated, you cannot tell which one survived). Mutate only the
**logic lines the slice changed** (conditionals, comparisons, arithmetic, boolean operators, return
values, loop bounds — skip pure data, strings, comments, formatting), with the standard operators:
negate a conditional, move a comparison boundary (`<`↔`<=`, `==`↔`!=`), swap a boolean (`&&`↔`||`),
replace a return or constant (`return $true`→`$false`, `0`→`1`), delete a statement with an effect.
When the slice changed more than eight mutable lines, **prioritise by risk** (guards, branch
conditions, the core computation) with diversity — one mutant per line.

Find the **relevant test file from the slice's own diff** first: test-first means the test ships with
the code, so the test file the slice added or modified is the one meant to cover it. Fall back to
naming convention or grepping the changed symbol. Determine how the project runs a **single** test
file (its framework, `package.json`, or how tests are invoked in the repo) and run only that file —
never the whole suite. If **no test covers the changed logic**, that is itself a finding; do not run
the whole suite to compensate.

A **surviving mutant** — the test stayed green though the code was broken — is the finding: this
changed line can be broken with no test failing. Report survivors at **Medium** (risky logic shipped
untested); do not report mutants that died (those tests have teeth). Guard against the
**equivalent mutant**, a mutation that does not actually change behaviour, so its survival is not a
real gap: drop
the ones you can identify before reporting, and the **confidence pass (Step 5)** scores an equivalent
mutant — or one whose line falls outside the slice's changed lines — **below 60**, so it is dropped.
Everything that survives lands in the same report (Step 6) as any other finding.

**Clean up when done**: `git worktree remove --force $tmp` (and `git worktree prune` if the remove
fails), so no temporary worktree is left behind.

## Coherence pass

Steps 1–6 review the **unreviewed delta**, turn by turn. This pass is the counterpart: once, at the
close of `/review-loop` (whether it closed clean or hit the 5-turn cap), the slice is read **as a
whole** against its declared intent. Reviewing by parts lets through the defect that only shows in
the whole — a slice whose pieces are each fine but that does not cohere as a unit against what it
set out to do. Invoke it as `/slice-review --coherence`.

It differs from the per-turn review in four ways:

- **Target: the full slice range**, not the delta — the whole change from the **start of the closing
  slice**, plus its untracked files. Anchor it with the marker's `slice-base`, so on a stacked branch
  (several slices on one feature branch) this pass reads only the slice being closed, not the whole
  branch — the difference between the closing slice's ~250 lines and the branch's several thousand:

  ```powershell
  pwsh -NoProfile -File .claude/scripts/review-marker.ps1 -Action slice-base   # bare ref: start of the closing slice
  ```

  `slice-base` returns the point the loop's first turn recorded as this slice's start, and falls back
  to the branch base when there is none (the branch's first slice, or a standalone run with nothing
  recorded), so it is always at least as tight as the branch base. Review `git diff <base>` (plus the
  untracked files from Step 1's `ls-files`). This is the one run that re-reads already-reviewed code
  on purpose, because a whole-slice defect is invisible in any single delta. If the base is
  undeterminable (exit 2), the base is exactly what could not be resolved, so **do not reach for**
  `git diff <base>...HEAD` (the same rule as Step 1's exit-2 case): say the coherence pass could not
  be anchored and skip it for this close, or fall back to `git diff HEAD` / `git show HEAD` as a
  partial sanity read, stating it is not a whole-slice coherence read. If instead the marker
  **script is missing**, the base *can* still be resolved by name, so use the slice's branch range
  (`git diff <base>...HEAD`). If the resolved base equals HEAD (a base-branch slice with only
  uncommitted work), `git diff <base>` shows just the working tree — note the pass saw only that.
  If the anchor resolves but `git diff <base>` shows **changes you did not make** — a stale snapshot
  that `commit --amend`/`rebase`/`reset` left no longer an ancestor of HEAD — ignore it and review
  the slice's branch range. Do **not** re-run `slice-base` for that base: it hands back the same
  stale snapshot (it resolved — that is this case's premise). Get the branch base from **`-Action
  base`** instead (`git diff <base>...HEAD`, where `<base>` is what `base` prints — an ancestor of
  HEAD here, so it does resolve, unlike the exit-2 case).
- **A single read-only focus**, not the five-way fan-out. Dispatch **one** subagent on **Sonnet 5**,
  with the shared context from Step 3 (including the same write prohibition it carries), and this
  focus: read the slice as a unit against **its declared intent** — the task, the PRD, or the
  commit message it implements — and flag where the pieces do not add up to that intent: an
  acceptance criterion left unmet, two parts that contradict each other, a capability half-wired,
  dead scaffolding for a feature that never landed. It is a judgment read against intent, so it runs
  on Sonnet 5 rather than the lighter audits' model.
- **It executes nothing.** The executable behaviour was already verified by delta, turn by turn. The
  coherence pass is a read, not a second full run — that is the whole reason looking at the entire
  slice stays cheap.
- Everything else is unchanged: its findings go through the **same confidence pass (Step 5)** and
  land in the **same report (Step 6)** as any other finding, with the same 60 cutoff and severities.
