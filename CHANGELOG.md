# Changelog

## Unreleased

### Fixed — the review-loop hook lost slice closes declared from PowerShell

v2.0.0 widened the `review-loop-trigger` matcher to `Bash|PowerShell`, so the hook started receiving
commands from the PowerShell tool — but it still parsed them with **bash** quoting, where `\`
escapes. In PowerShell `\` is an ordinary character and a quoted Windows path *ends* in one, so the
literal walker ran past the closing quote, masked to the end of the line, and the trigger vanished:
`git -C "C:\repo\" commit` with a declared `Slice-Close:` trailer fired **nothing, silently**. Same
for `Set-Location "C:\tmp\"; git commit` and `git -C "$env:REPO\" push`.

The hook now picks the quoting grammar from the event's `tool_name`: backtick and doubled quotes for
PowerShell, `\` for bash, and bash for an event without the field. Nothing changes for the Bash tool.

No action needed beyond taking the new hook (`upgrade-bootstrap`). If you closed slices from the
PowerShell tool with a quoted path ending in `\`, those closes never got a review turn — the marker
still holds the range, so the next close reviews them together.

## v2.0.0 — 2026-09-21

Skills refreshed from upstream by three-way merge, a thinner `CLAUDE.md`, lanes for parallel work,
and manifests re-sealed with line-ending-independent hashing. **Two doctrine changes** (below) mean
your project's `CLAUDE.md` may now contradict the skills it receives: check it after upgrading.

### How to update

1. In your clone of this repository: `git pull`
2. Deploy the skills: `pwsh -NoProfile -File tools\sync-skills.ps1`
3. If you have user-level copies of `research`, `debug-source-first` or `verify-downstream-arrival`
   in `~/.claude/skills/`, delete them: the scaffold now ships its own, and a user-level skill with
   the same name can hide the project's (seen with `research`).
4. Start a new Claude Code session.
5. In **each** bootstrapped project, say *"update the bootstrap"* (`upgrade-bootstrap`), then do the
   `CLAUDE.md` check below.

Manifests are now hashed with normalized line endings (CRLF and LF hash the same), and the upgrade
re-seals your project's manifest that way. Your project's manifest still holds the old raw hashes
until this upgrade re-seals it; they are still recognized, including for a file that was sealed as
CRLF and is LF now (or the reverse). One case is not: a file sealed with **mixed** line endings
(some lines CRLF, some LF) whose line endings changed since can show up as customized, and keeps
doing so on later upgrades until you take the canonical version.

### Doctrine change 1 — TDD is `red → green`

The refactor step left the TDD cycle (ADR-0004): it happens in the review stage, where the review
loop already runs after every slice close. If your `CLAUDE.md` says `red → green → refactor`, or
otherwise promises three TDD stages, rewrite it to `red → green`.

### Doctrine change 2 — the review-loop and alignment-gate mechanics moved out of `CLAUDE.md`

The template `CLAUDE.md` now keeps three sentences and a pointer for each; the detail lives in
`docs/ai-workflow/AI_DEVELOPMENT_WORKFLOW.md` (§7 for the review loop, §1 for the alignment gate).
The hooks enforce both, so no rule changed. `upgrade-bootstrap` decides file by file: the workflow
doc usually lands on its own, while a customized `CLAUDE.md` is kept unless you pick the assisted
merge. **Keep the mechanics in one place only**: either in your `CLAUDE.md` or in the workflow doc,
never both, and make sure your `CLAUDE.md` does not point to a section that did not land.

### Lanes for parallel work

New files: `docs/ai-workflow/PARALELISMO.md` (the norm), `PLAN-DE-OLA.md` (wave plan),
`BRIEF-DE-CARRIL.md` (lane brief), `.claude/scripts/abrir-carril.ps1` (opens a lane), and
`docs/ai-workflow/PARALELISMO-DEL-PROYECTO.md`, your project's data. That last one arrives with
**unfilled placeholders on purpose**: neither the bootstrap nor the upgrade fills them, and
`abrir-carril.ps1` refuses to open a lane while any remain (`-DryRun` only warns).

### Skills

- **New:** `grilling` and `domain-modeling` (`grill-me` and `grill-with-docs` are now short pointers
  to them), `diagnosing-bugs`, `wizard`, `to-questionnaire`, `research`, `resolving-merge-conflicts`,
  `git-guardrails-claude-code`, `verify-downstream-arrival`, `debug-source-first`.
- **Updated from upstream, names kept:** `to-prd`, `to-issues`, `triage`, `handoff`,
  `setup-matt-pocock-skills`, `tdd`.
- **Invocation policy:** skills only a human types (`grill-me`, `grill-with-docs`, `to-prd`,
  `to-issues`, `triage`, `handoff`, `to-questionnaire`, `setup-matt-pocock-skills`, `zoom-out`) are
  user-invoked and no longer load their description into every request.
- **Reviewers are declared agents** (`.claude/agents/slice-review-*.md`): write tools are denied by
  declaration, not by a prose request.

### Scaffold

- A secrets rule in `CLAUDE.md`: never hardcode a secret; a leaked one is rotated, not just deleted.
- Document templates in `docs/ai-workflow/` (`PRD_TEMPLATE.md`, `TASK_TEMPLATE.md`,
  `RUNBOOK_TEMPLATE.md`).
- Firebase in the MCP catalog.
- `.gitattributes` with `*.sh text eol=lf`.
- The `review-loop-trigger` hook also fires on commits made with the PowerShell tool.

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
