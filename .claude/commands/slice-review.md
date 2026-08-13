---
description: Run a multi-agent code review over a local diff (no PR or remote required) and report findings by severity with a confidence pass that filters false positives. Use as step 1 of the review-loop, or standalone to review a finished slice.
argument-hint: [diff range — a bare ref from the review marker, or e.g. main...HEAD; defaults to the working tree]
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

Without arguments, pick the first that applies:

1. Uncommitted work exists (`git status --porcelain` is non-empty) → review the working tree:
   `git diff HEAD`
2. On a feature branch with a resolvable base → review the branch:
   `git diff <base>...HEAD` (base = `origin/HEAD`, else `main`/`master`/`develop` if it exists locally)
3. Otherwise → review the last commit: `git show HEAD`

State the resolved target out loud before reviewing. Getting the base wrong is the most common
failure of this command: on long-lived branches `main...HEAD` can drag in commits from earlier
slices. If the range looks bigger than the slice you just closed, use the real base of the slice.

If the resolved diff is empty **and there are no untracked files**, stop and report "nothing to
review" — do not invent a target. An empty diff with untracked files present is not nothing: it is
the normal shape of a change made entirely of new files.

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

## Step 4 — Fan out parallel reviewers

Dispatch these as **parallel subagents** (`general-purpose`), all in a single message so they run
concurrently. Give each one the shared context from Step 3 and its own focus. Each returns a list
of findings; every finding must carry `file:line`, what is wrong, and why it matters.

1. **Bugs** — read the changed lines and hunt for real defects: wrong logic, unhandled errors,
   null/undefined paths, off-by-one, race conditions, resource leaks, broken async. Focus on the
   change itself, not the whole codebase. Skip nitpicks.
2. **Project rules** — audit the change against the `CLAUDE.md` files. Flag only rules the file
   actually states, quoting the rule. `CLAUDE.md` is guidance for writing code, so not every line
   is a review criterion.
3. **Historical context** — read `git log`/`git blame` for the modified regions. Flag anything that
   reintroduces a previously fixed bug, contradicts a deliberate past decision, or repeats a
   pattern that was already corrected here.
4. **Contracts and callers** — check the change against the code around it: callers of every
   modified signature, comments and docstrings that state invariants, and existing types. Flag
   silent breaks in behavior a caller depends on.
5. **Tests** — is the changed logic actually covered? Flag risky logic shipped with no test, tests
   asserting on mocks instead of behavior, and tests that would pass even if the feature broke.

## Step 5 — Confidence pass (filter false positives)

Reviewers over-report. For each finding returned in Step 4, dispatch a **parallel** subagent that
receives the finding plus the diff and scores it 0-100. Give it this rubric verbatim:

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
