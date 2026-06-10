---
name: bootstrap-southpoint-project
description: Bootstrap a new SOUTHPOINTLABS client project directory with the full AI-assisted workflow scaffolding (CLAUDE.md 8-step workflow, docs/ai-workflow, docs/agents, custom skills like grill-me/tdd/to-prd, git init as southpointtech). Use whenever the user says they are starting a new Southpoint/SOUTHPOINTLABS/work/client project, asks for "archivos base", "setup inicial", "scaffolding", "preparar el repo/ambiente", or wants to replicate the Forecasting App modus operandi in a new directory — even if they don't name this skill. For personal (non-work) projects use bootstrap-personal-project instead.
---

# Bootstrap SOUTHPOINTLABS Project

Recreates the proven setup of the Forecasting App in a new project directory: the 8-step AI workflow (alignment → PRD → vertical slices → Zoho tasks → TDD → QA → clean-context review → human approval), the workflow docs it references, the agent conventions (local issue tracker, triage labels, domain docs), and the custom skills (grill-me, grill-with-docs, tdd, to-prd, to-issues, triage, handoff, zoom-out, review-loop).

The point of this skill is that the scaffolding lands **before** requirements or code, so every later session starts governed by the workflow instead of improvising.

All template files live in `assets/scaffold/` next to this SKILL.md — copy them, don't regenerate them, so the wording of the workflow stays identical across projects.

## Step 0 — Safety check

Run this in the directory the user designates as the new project root (usually the current working directory).

- If `CLAUDE.md` or `docs/ai-workflow/` already exist there, **stop and ask** — the project may already be bootstrapped, and overwriting its operating rules silently would be destructive.
- If the directory contains other files (code, docs), list them and confirm with the user before proceeding. Never overwrite an existing file; scaffold around it.

## Step 1 — Project info

Infer the project name from the directory name or the user's message. Only ask if it's genuinely unclear. Ask for a one-line description if the user hasn't given one — it seeds README and CONTEXT.md.

## Step 2 — Copy the scaffold

Copy the entire `assets/scaffold/` tree into the project root. On Windows (adjust `$skill` to this skill's directory and `$proj` to the project root):

```powershell
$skill = "<base directory of this skill>"
$proj  = "<project root>"
Get-ChildItem "$skill\assets\scaffold" -Force |
  Where-Object Name -ne "gitignore.txt" |
  ForEach-Object { Copy-Item $_.FullName (Join-Path $proj $_.Name) -Recurse -Force }
Copy-Item "$skill\assets\scaffold\gitignore.txt" (Join-Path $proj ".gitignore")
```

Why enumerate instead of `scaffold\*`: wildcard expansion of dot-directories varies between PowerShell versions — combining a wildcard copy with explicit `.agents`/`.claude` copies has produced nested duplicates (`.agents\.agents`) when both ran. Enumerating top-level entries once is deterministic. (`gitignore.txt` is stored under that name so the skill repo doesn't treat it as its own ignore file — it must land as `.gitignore`.)

Before committing, verify the copy landed cleanly: `.agents\skills` has 10 skill directories, `.claude\commands` has 10 files, and neither `.agents\.agents` nor `.claude\.claude` exists.

This delivers: `CLAUDE.md`, `.gitignore`, `skills-lock.json`, `.agents/skills/` (10 skills — 9 synced via `skills-lock.json` + `review-loop`, own), `.claude/commands/` (10 commands), `docs/ai-workflow/` (5 docs), `docs/agents/` (3 docs).

## Step 3 — Project-specific files

Create these (they are per-project, so they are not in the scaffold):

- `README.md` — `# <Project Name>` plus the one-line description.
- `CONTEXT.md` — stub with the project name and a note that the canonical glossary/domain model will be produced by `grill-with-docs` during requirements closing. Don't invent domain content.
- `docs/adr/.gitkeep` — ADRs accumulate here as decisions crystallise.
- `.scratch/` directory — local issue tracker home (gitignored by design).

## Step 4 — Git

If the directory is not a git repository: `git init -b main`.

Set the **local** identity (local, so the user's global git config is untouched):

```powershell
git config user.name "southpointtech"
git config user.email "mdeleon@agtium.com"
```

Then commit everything as `chore: project scaffolding (AI workflow + skills)`.

If it's already a repo, still set the local identity and commit the scaffolding files on the current branch.

## Step 5 — Report and hand off

Report: files created (counts per area), git status, and the immediate next step of the workflow — closing requirements with `/grill-me` or `/grill-with-docs`, which produces CONTEXT.md content and the first ADRs, followed by `/to-prd` and `/to-issues`.

Do not start requirements, PRDs, or code as part of this skill — bootstrap ends here by design (step 1 of the workflow needs the human present).
