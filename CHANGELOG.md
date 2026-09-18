# Changelog

## v1.0.0 — 2026-09-18

First tagged release. If your copy of these skills is from June, this is everything you are missing.
The v2 work in progress is **not** part of this release.

### How to update

1. In your clone of this repository: `git pull`
2. Deploy the skills: `pwsh -NoProfile -File tools\sync-skills.ps1`
3. Start a new Claude Code session (the skills load at session start).
4. In **each** bootstrapped project, open Claude Code and say *"update the bootstrap"*. That runs
   `upgrade-bootstrap`, which shows the delta and applies it with your approval. Files you customized
   are put to you as a decision, never overwritten silently.

If `upgrade-bootstrap` reports a file you never touched as customized, look at the diff before
deciding: line-ending hashing under `core.autocrlf` is a known open issue.

### Review loop — it now converges

The loop used to end at its 5-turn cap, fixing its own comments turn after turn. That is fixed:

- **Turn cap is 2.** A slice can declare `Review-Rigor: light` next to its `Slice-Close:` trailer
  (local tools, tests only, behavior-preserving refactors): it then runs **one** turn with the Bugs
  and Tests focuses only, and only a High blocks the close.
- **Comments no longer block the close.** A finding whose fix is only prose (comment, docstring,
  commit message, internal doc) is **Low**, unless end users read the text or it contradicts the code.
  Instructions in the files that govern the agent (`CLAUDE.md`, `.claude/`, `.agents/`,
  `docs/ai-workflow/`, `docs/agents/`) still count as behavior.
- **Prose from an earlier turn is not re-edited**, and a turn whose unreviewed delta is only prose
  closes the loop.
- **The confidence pass scores the suggested fix too.** A true finding with a bad suggestion keeps its
  severity, and its suggestion is marked REJECTED instead of being applied.
- **Writing rules for fixes** (step 5): a scripted replace that matches nothing must abort, and the
  prose that justifies a fix says only what was checked.
- **Incremental review:** each turn reviews only what changed since the last review (the review
  marker, `.claude/scripts/review-marker.ps1`), not the whole branch again.
- **Declared trigger:** the hook fires on a commit with a `Slice-Close:` trailer, on `git push` and on
  `gh pr create` in a feature branch, plus a safety net past ~400 unreviewed lines. A slice made only
  of `.md` documentation does not trigger it.
- **Reviewer:** `/slice-review` is a local multi-agent reviewer the agent can launch itself (the
  built-in `/code-review` joins it on turn 1). It adds a mutation check on turn 1 and a whole-slice
  coherence pass at close.

### Bootstrap and scaffold

- **`alignment-gate` hook:** the first code edit of a session is stopped once, so the agent offers
  `/grill-me` or `/grill-with-docs` before coding.
- **The copy backs up what it overwrites** into `.bootstrap-backup/` and reports every replaced file.
- **Adoption mode** for projects that already have a `CLAUDE.md`: the original is preserved at
  `docs/agents/legacy-claude.md` and merged only with your approval.
- **`bootstrap-ai-project`:** a shareable variant with no DOMO, a generic issue tracker, and no change
  to your git identity.
