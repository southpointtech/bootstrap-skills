# AI Development Workflow

## 1. Alignment / Grill Me

Before implementation, Claude must interview the developer about the requested change.

The goal is to eliminate ambiguity before writing code.

Claude must clarify:

- Product goal
- Users affected
- Current behavior
- Desired behavior
- Data dependencies
- Firebase or Azure backend target
- Edge cases
- Testing strategy
- Deployment risks
- Acceptance criteria

Claude must not write code during this phase.

### The `alignment-gate` hook

`PreToolUse` on `Edit`/`Write`/`MultiEdit`. It blocks the first edit of a *code* file once per session and tells the agent to OFFER alignment (`/grill-me` or `/grill-with-docs`) before coding — it never runs the grill on its own, and non-code files (`*.md`, `docs/`, `.scratch/`, `.agents/`, `.claude/`, config) pass through untouched. If the work is trivial or already aligned, just retry the edit and proceed. This breaks the "fix→implement" autopilot that text rules alone do not stop.


## 2. PRD

After alignment, Claude creates or updates a PRD.

The PRD must include:

- Problem statement
- Goals
- Non-goals
- User stories
- Functional requirements
- Technical requirements
- Data requirements
- Testing requirements
- Acceptance criteria
- Risks
- Open questions

## 3. Vertical Slice Planning

Claude must break the PRD into independently testable vertical slices.

Prefer slices that cross UI, backend, data, and tests when relevant.

Avoid splitting work only into horizontal layers like:

- Database only
- API only
- UI only

unless there is a strong reason.

Each slice must be PLANNED to fit in a small, reviewable PR (target ≤ ~400 lines of change) — the ceiling is measured when the slice opens, over what you set out to implement. A slice projected larger is split before implementing; when slices depend on each other, chain them as stacked PRs. A slice that ends up larger than planned is declared at close, not split retroactively.

## 4. Task Formatting

Each task must be ready to copy into your issue tracker (GitHub Issues, Jira, Linear, …).

Each task must include:

- Title
- Description
- Acceptance criteria
- Dependencies
- Test plan
- Deployment target
- Estimated complexity
- Affected area: frontend, Firebase, Azure, Playwright, docs, config

Calibrate `Estimated complexity` against `ESTIMATION_GUIDE.md`. It ships empty: fill it from this project's own logged actuals, and until then say the estimate is uncalibrated.

## 5. Implementation

Claude must implement one selected vertical slice at a time.

Rules:

- Read the PRD first.
- Read the selected task first.
- Use TDD when practical.
- Add or update Playwright tests for UI behavior changes.
- Keep changes focused.
- Do not touch unrelated files.
- Do not deploy.

## 6. QA

Before marking work complete, Claude must run or propose:

- Unit tests
- Type checks
- Lint checks
- Playwright tests
- Manual QA checklist

If tests cannot be run, Claude must explain why.

## 7. Clean-Context Review

For important changes, a second review must be performed from a clean context.

Run this as a loop via `/review-loop`: `/slice-review` → fix real findings → re-review, repeating until no medium/high-severity findings remain (or its turn cap: 2 turns, or 1 when the slice declares `Review-Rigor: light`). The backbone reviewer is `/slice-review` (a local multi-agent reviewer the agent can launch); on the first turn the loop also folds in the built-in `/code-review` as one more independent reviewer.

The reviewer must check:

- Requirements coverage
- Bugs
- Security risks
- Deployment risks
- Test gaps
- Overengineering
- Firebase/Azure constraints

### What fires the loop, and over what

The `review-loop-trigger` hook enforces this deterministically, so it does not depend on the agent remembering: on a commit carrying the `Slice-Close:` trailer, on `git push` or on `gh pr create` in a feature branch, it injects the order to run `/review-loop`. As a safety net it fires on a trailer-less commit too, once the unreviewed delta passes the ~400-line guide, so forgetting the trailer cannot leave a big slice unreviewed. Work in feature branches per slice — commits directly on the base branch do not trigger the loop.

A slice that is ENTIRELY documentation does not trigger the loop at all: prose is not worth a review turn. `.md` is the only thing that counts as documentation — anything else under `docs/` is code — and the files that govern the agent are never documentation no matter their extension (`CLAUDE.md` anywhere, `.claude/`, `.agents/`, `docs/ai-workflow/`, `docs/agents/`), so editing a rule still fires the loop. One non-doc file is enough to leave that gate open, and uncommitted work counts — tracked edits and brand-new files alike. Generated artifacts are the exception on both sides: a re-sealed manifest or a re-recorded snapshot is nobody's writing, so it neither counts as documentation nor keeps the gate open. An open gate is not the same as firing — the trailer and the ~400-line net still get their say on a commit, and the per-commit dedupe silences a second push of the same SHA on every trigger.

Each turn reviews the **unreviewed delta** — what changed since the last review run, per the review marker (`.claude/scripts/review-marker.ps1 -Action range`) — not the branch's full range again. This works in local repos (no remote) and on GitHub alike. A slice that declares `Review-Rigor: light` runs one turn with two focuses, Bugs and Tests; without that trailer it runs `standard`, with the full fan-out.

## 8. Human Approval

Human approval is required before:

- Deploying Firebase Functions or Hosting
- Deploying Azure backend changes
- Changing production config
- Changing secrets
- Changing Firestore rules or indexes
- Changing auth, permissions, or external integrations
