---
name: slice-review
description: Run a multi-agent code review over a local diff (no PR or remote required) and report findings by severity with a confidence pass that filters false positives. Use as step 1 of the review-loop, or standalone to review a finished slice. Trigger when the user says "revisá este diff", "pasale el reviewer a este slice", "code review de lo que acabo de commitear", "revisá el commit antes de mergear", "corré el reviewer sobre la rama", or wants a review of a local change without opening a PR. Use this instead of the built-in /code-review, which is restricted to human invocation.
---

# Slice Review

An agent-invocable code reviewer for **local** diffs. Unlike the built-in `/code-review` (which is
restricted to human invocation and assumes a GitHub PR), this command can be launched by the agent
itself, so `/review-loop` can actually close its loop.

Reviewers run as parallel subagents with distinct focus areas, then every finding goes through a
confidence pass before it reaches the report. That second pass is what keeps the loop from
"fixing" false positives.

## Step 1 — Resolve what to review

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
exists to remove, and reviewing the full slice range is reserved for the coherence pass. Ask the
marker (from the repo root):

```powershell
pwsh -NoProfile -File .claude/scripts/review-marker.ps1 -Action range
```

Read the exit code — empty output means two different things:

- **exit 0 + a bare ref** → that ref is the range; review `git diff <ref>` (plus untracked files).
- **exit 0 + empty** → everything up to the marker was already reviewed. Report "nothing to
  review" and stop. Do **not** fall back to `main...HEAD` or invent a range — that re-review is
  exactly what the marker exists to remove.
- **exit 2 + empty** → the marker could not resolve a base (detached HEAD, the repo's only ref, an
  orphan branch, or the marker script is missing on an older scaffold). Do not treat this as
  "nothing to review": recover by reviewing the working tree (`git diff HEAD`) if it is dirty, else
  the last commit (`git show HEAD`), and say in the report that the marker was unavailable so this
  run is not incremental.

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

## Step 5 — Confidence pass (filter false positives)

Reviewers over-report. For each finding returned in Step 4, dispatch a **parallel** subagent that
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
