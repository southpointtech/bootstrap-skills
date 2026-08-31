---
name: bootstrap-ai-project
description: Bootstrap a new project directory with an AI-assisted workflow scaffolding (CLAUDE.md 8-step workflow, docs/ai-workflow, docs/agents, custom skills like grill-me/tdd/to-prd, review hooks, git init). Use whenever the user says they are starting a new project and wants it set up for AI-assisted development, asks to "bootstrap this project", "set up the AI workflow", "prepare this repo", "scaffold the project structure", or wants the disciplined AI development workflow installed in a directory — even if they don't name this skill. This is per-PROJECT (run inside the project folder). To update an already-bootstrapped project use upgrade-bootstrap.
---

# Bootstrap AI Project

Installs a proven AI-assisted modus operandi in a project: the 8-step AI workflow (alignment → PRD → vertical slices → task formatting → TDD → QA → clean-context review → human approval), the workflow docs it references, the agent conventions (local issue tracker, triage labels, domain docs), and the custom skills (grill-me, grill-with-docs, tdd, to-prd, to-issues, triage, handoff, zoom-out, review-loop).

The point is that the scaffolding lands **before** requirements or code, so every later session starts governed by the workflow instead of improvising.

All template files live in `assets/scaffold/` next to this SKILL.md — copy them, don't regenerate them, so the wording of the workflow stays identical across projects.

## Step 0 — Safety check

Run this in the directory the user designates as the new project root (usually the current working directory).

- If `.bootstrap-manifest.json` already exists, the project **was bootstrapped with this scaffold** — do not re-run bootstrap. Tell the user to use `upgrade-bootstrap` to pull scaffold changes, and stop.
- If `CLAUDE.md` or `docs/ai-workflow/` exist but there is **no** `.bootstrap-manifest.json`, the project is **not** bootstrapped — it just has its own files. Do **not** say "already bootstrapped", and do **not** derive to `upgrade-bootstrap` (that skill is only for projects that already have a manifest). Instead, enter **Step 0b — Adoption mode** below: install the methodology while preserving the project's own content.
- If the directory contains other files (code, docs), list them and confirm with the user before proceeding. Where the project has its own version of a file the scaffold also ships, the copy **does** overwrite it — backing the original up to `.bootstrap-backup/` and declaring it under `overwritten` first (Step 2, ADR-0007). Report that list; never assume nothing of the project's was touched.

## Step 0b — Adoption mode

Reached from Step 0 when the project has its own `CLAUDE.md` (or `docs/ai-workflow/`) but no `.bootstrap-manifest.json`. Goal: install the 8-step methodology without losing the project's context or identity. Two invariants govern this mode: **the original is never lost** (a verbatim, permanent backup), and **the merge is never applied before the user approves a coverage map** of where each block of their content goes.

Define `$skill` and `$proj` as in Step 2.

### A. Copy the scaffold

Run **Step 2** exactly as written (the `copy-scaffold.ps1` script, which merges into pre-existing directories like `docs/` instead of nesting). This installs the canonical `CLAUDE.md`, all 52 files, and `.bootstrap-manifest.json`, overwriting the project's `CLAUDE.md` with the canonical 8-step template — fine: the script copies every file it is about to overwrite into `.bootstrap-backup/` first, and lists them under `overwritten` in its JSON report. **Keep that report — steps B and D both need it.**

### B. Park the original CLAUDE.md

**First look at `docs/agents/legacy-claude.md`.** If it already exists, an earlier run parked the original there and *that file* is it — leave it exactly as it is and go straight to step C. Never move anything on top of it: it is the permanent recovery net, and by the time a re-run makes a fresh backup the project's own text is no longer what gets copied.

Otherwise park it, **only if `.bootstrap-backup/CLAUDE.md` exists after the copy**. For this one file take the **un-numbered** path — the opposite of the rule for every other entry. The numbered copies (`.2`, `.3`) hold what a later run overwrote, which by then is the canonical template; the un-numbered one is the project's own original, and that is what step C has to classify. Everywhere else you want the newest, here you want the oldest.

```powershell
Move-Item "$proj\.bootstrap-backup\CLAUDE.md" "$proj\docs\agents\legacy-claude.md" -Force
```

`docs/agents/legacy-claude.md` stays in the repo forever as the recovery net.

If **neither** `docs/agents/legacy-claude.md` nor `.bootstrap-backup/CLAUDE.md` exists, there is no original to park and steps C and E have nothing to classify — skip them, and say exactly that in the Step 6 report instead of the sentence step F would otherwise have you write. That happens when the project had no `CLAUDE.md` at all (Step 0 also routes into adoption on a bare `docs/ai-workflow/`), or when its `CLAUDE.md` was already content-identical to the canonical one, in which case there is nothing of the project's to recover. Check both before concluding it: a run that died at the approval point leaves the original parked and the `CLAUDE.md` already canonical, so looking only at the backup would report "no original" over a project whose rules were never merged. Never run the `Move-Item` blind: `-Force` does not conjure a missing source, it throws, and it would abort the adoption with the scaffold already landed on the project's files.

### C. Classify the original's content

Read `docs/agents/legacy-claude.md`. Split it into blocks — **treat each top-level heading and its body as one block, and any leading title or description before the first heading as its own block**. Classify each block into exactly one destination, **moving text verbatim — never paraphrase or summarize**:

- **Operational rule** (governs behavior, e.g. "never deploy without approval", "don't trust the 2xx as proof of arrival") → the `## Hard rules` section of the canonical `CLAUDE.md`.
- **Domain knowledge** (what the project does, integrations, technical gotchas, branching model) → `docs/agents/domain.md`, appended under a new `## Project-specific domain` section.
- **Project description** (the one-line of what this is) → `CONTEXT.md` (created in Step 3).
- **Doesn't fit / unsure** → leave it only in `legacy-claude.md` and mark it on the map for the user to decide.

### D. Present the coverage map and get approval

Show the user a table: every block of the original → its destination, quoting the block verbatim. Make any unassigned ("doesn't fit") blocks visible.

**The map must also cover every other entry in the copy's `overwritten` list.** Those are the project's own files the scaffold just replaced, and each one is a decision, not a default: keep the scaffold's version (often right — it is the update you came to deliver), restore the project's from `.bootstrap-backup/`, or merge the two. A `.gitignore` almost always needs merging, because the scaffold's rules are additions and the project's own entries are still needed. Nothing is lost either way — each original sits at the `backup` path its own `overwritten` entry names (the one exception is `CLAUDE.md`, which step B moved to `docs/agents/legacy-claude.md`) — but say out loud what each file got.

Get a **single explicit approval** (the user may correct individual rows before approving). Do **not** write the merge until approved.

### E. Apply the merge

After approval: insert operational-rule blocks into `## Hard rules` as new bullets (verbatim); append domain blocks under `## Project-specific domain` in `docs/agents/domain.md` (verbatim); seed `CONTEXT.md` with the description. Leave `legacy-claude.md` untouched as the permanent backup.

The `.bootstrap-manifest.json` copied in step A records the canonical `CLAUDE.md` hash as its base. Because the project's `CLAUDE.md` now differs (project Hard rules merged in), a future `upgrade-bootstrap` automatically classifies it as **customized** and never overwrites it — no extra sealing needed.

### F. Continue with Steps 3–6

Proceed to Step 3 (project-specific files — but if step E already seeded `CONTEXT.md`, do **not** overwrite it with a stub), Step 4 (MCP servers — the `.mcp.json` menu applies to adopted projects too), Step 5 (git), and Step 6 (report). In the Step 6 report, state where the original ended up — preserved at `docs/agents/legacy-claude.md` with the list of which blocks went to `## Hard rules` vs `docs/agents/domain.md`, or, on the skip path of step B, that there was no original distinct from the canonical template and nothing was classified. Never claim the file exists without having parked it.

## Step 1 — Project info

Infer the project name from the directory name or the user's message. Only ask if it's genuinely unclear. Ask for a one-line description if the user hasn't given one — it seeds README and CONTEXT.md.

## Step 2 — Copy the scaffold

Copy the entire `assets/scaffold/` tree into the project root by running the bundled script. On Windows (adjust `$skill` to this skill's directory and `$proj` to the project root):

```powershell
$skill = "<base directory of this skill>"
$proj  = "<project root>"
pwsh -NoProfile -File "$skill\scripts\copy-scaffold.ps1" -SkillDir $skill -ProjectDir $proj
```

The script copies file-by-file, merging into directories the project already has. Do NOT replace it with `Copy-Item <dir> -Recurse` (nests into `docs\docs` / `.agents\.agents` when the destination directory exists) or a `scaffold\*` wildcard (dot-directory expansion varies between PowerShell versions). It also lands `gitignore.txt` as `.gitignore` (stored under that name so the skill repo doesn't treat it as its own ignore file).

Before committing, verify the copy landed cleanly: `.agents\skills` and `.claude\commands` have as many entries as the scaffold itself does (count them there — a number written here goes stale the next time a skill is added), `.claude\settings.json` and `.claude\hooks\review-loop-trigger.ps1` and `.claude\hooks\alignment-gate.ps1` exist, and neither `.agents\.agents` nor `.claude\.claude` exists.

The script prints a JSON report on stdout: `created` lists the files it added, `overwritten` lists the project's own files it replaced, each with the path where it backed the original up — normally `.bootstrap-backup/<same relative path>`, but numbered `.2`, `.3` where a backup was already there, so read the `backup` field instead of deriving it from `file`. A file that differs only in CRLF vs LF is not reported — that is `core.autocrlf` noise, not a change. **Report the `overwritten` list to the user.** On an empty project directory it comes back empty and there is nothing to say. On a project that already had files it is the list of what the copy replaced: in adoption mode (Step 0b/D) every entry needs a decision before the merge; otherwise report it and continue.

This delivers: `CLAUDE.md`, `.gitignore`, `skills-lock.json`, `.bootstrap-manifest.json` (scaffold version manifest, used by `upgrade-bootstrap`), `.agents/skills/` (11 skills — 9 synced via `skills-lock.json` + `review-loop` and `slice-review`, bundled here), `.claude/commands/` (11 commands), `.claude/settings.json` + `.claude/hooks/review-loop-trigger.ps1` (auto-runs `review-loop` on each slice commit/push or PR) + `.claude/hooks/alignment-gate.ps1` (stops the first code edit of the session and offers to align before coding), `docs/ai-workflow/` (5 docs), `docs/agents/` (3 docs).

## Step 3 — Project-specific files

Create these (they are per-project, so they are not in the scaffold):

- `README.md` — `# <Project Name>` plus the one-line description.
- `CONTEXT.md` — stub with the project name and a note that the canonical glossary/domain model will be produced by `grill-with-docs` during requirements closing. Don't invent domain content.
- `docs/adr/.gitkeep` — ADRs accumulate here as decisions crystallise.
- `.scratch/` directory — local issue tracker home (gitignored by design).

## Step 4 — MCP servers (.mcp.json)

Ask which MCP tools this project will use, then generate a committed `.mcp.json` (project scope). Tokens are referenced via `${VAR}` — never written into the file.

Present the catalog with `AskUserQuestion` (multiSelect): **firebase**, **github**. Let the user pick zero or more. If `AskUserQuestion` is unavailable (non-interactive or agent context), don't block: infer the servers from the project's `CLAUDE.md`/context, or pick none if it's unclear, and note the inferred choice in the Step 6 report.

Then run the generator (adjust `$skill` to this skill's directory and `$proj` to the project root):

```powershell
$skill   = "<base directory of this skill>"
$proj    = "<project root>"
# $picks = the servers the user selected, e.g. @("firebase","github")
$servers = ($picks -join ',')   # -> "firebase,github" (no spaces)
pwsh -NoProfile -File "$skill\scripts\gen-mcp-json.ps1" -ProjectDir $proj -Servers $servers
```

The script ships with this skill at `$skill\scripts\gen-mcp-json.ps1`. If that path doesn't exist or the script exits non-zero, stop and report it — don't proceed to the Git step with a half-written `.mcp.json`.

The script writes `<proj>/.mcp.json` with only the chosen servers and prints a JSON summary with `requiredEnvVars` and `prereqs`. If the user picks nothing, it writes no file — that's fine, skip it.

`.mcp.json` is a per-project generated file (like README/CONTEXT): it is NOT part of the scaffold, NOT tracked by `.bootstrap-manifest.json`, and `upgrade-bootstrap` never touches it. It is committed with the rest of the scaffolding in the Git step.

Keep the script's `requiredEnvVars` / `prereqs` output for the final report (Step 6).

## Step 5 — Git

If the project directory is not **its own** git repository root — check with `git -C $proj rev-parse --show-toplevel` and confirm it equals `$proj`, not a parent repo the project happens to sit inside — run `git init -b main` so it gets its own repository. Never commit the scaffolding into an enclosing parent repo.

This skill does not set any git identity: commits use the user's own git config. Before committing, verify one exists — `git config user.name` and `git config user.email` must both return a value. If either is missing, ask the user to configure their identity first and wait; do not invent one.

Then commit everything as `chore: project scaffolding (AI workflow + skills)` — **except `.bootstrap-backup/`**. That directory holds copies of the project's own files and is deliberately not gitignored so the user sees it; whether it belongs in history is their call, not the skill's. Stage with an exclusion rather than a bare `git add -A` — `git add -A -- . ':!.bootstrap-backup'` — and point the directory out in the Step 6 report.

If it is already its own repo root, still verify the identity and commit the scaffolding files on the current branch.

## Step 6 — Report and hand off

Report: files created (counts per area), git status, and the immediate next step of the workflow — closing requirements with `/grill-me` or `/grill-with-docs`, which produces CONTEXT.md content and the first ADRs, followed by `/to-prd` and `/to-issues`. If a `.mcp.json` was generated, also report the **environment variables to set** (as persistent environment variables) and prerequisites from the script's summary — e.g. `GITHUB_PERSONAL_TOKEN` (+ Docker running), or `firebase login` once. The MCP servers won't connect until those env vars exist; this is expected, not an error.

Do not start requirements, PRDs, or code as part of this skill — bootstrap ends here by design (step 1 of the workflow needs the human present).
