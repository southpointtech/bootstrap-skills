---
name: bootstrap-personal-project
description: Bootstrap a new personal (non-work) project directory with the AI-assisted workflow scaffolding (CLAUDE.md 8-step workflow, docs/ai-workflow without DOMO, docs/agents, custom skills like grill-me/tdd/to-prd, git init as MartinDele703). Use whenever the user says they are starting a new personal/side/hobby project, asks for "archivos base", "setup inicial", "scaffolding", "preparar el repo/ambiente" for something that is NOT a SOUTHPOINTLABS/client project — even if they don't name this skill. For Southpoint/work projects use bootstrap-southpoint-project instead.
---

# Bootstrap Personal Project

Recreates the proven SOUTHPOINTLABS modus operandi for a personal project: the 8-step AI workflow (alignment → PRD → vertical slices → Zoho tasks → TDD → QA → clean-context review → human approval), the workflow docs it references, the agent conventions (local issue tracker, triage labels, domain docs), and the custom skills (grill-me, grill-with-docs, tdd, to-prd, to-issues, triage, handoff, zoom-out, review-loop).

This variant drops everything DOMO-specific; Playwright, Firebase, Azure and Zoho conventions persist. The point is that the scaffolding lands **before** requirements or code, so every later session starts governed by the workflow instead of improvising.

All template files live in `assets/scaffold/` next to this SKILL.md — copy them, don't regenerate them, so the wording of the workflow stays identical across projects.

## Step 0 — Safety check

Run this in the directory the user designates as the new project root (usually the current working directory).

- If `.bootstrap-manifest.json` already exists, the project **was bootstrapped with this scaffold** — do not re-run bootstrap. Tell the user to use `upgrade-bootstrap` to pull scaffold changes, and stop.
- If `CLAUDE.md` or `docs/ai-workflow/` exist but there is **no** `.bootstrap-manifest.json`, do **not** say "already bootstrapped" — it isn't. It just has its own files (e.g. a hand-written `CLAUDE.md`). **Stop and ask**: overwriting would be destructive, and the right path is `upgrade-bootstrap` (legacy adoption — seeds the scaffold + manifest without clobbering the existing `CLAUDE.md`). Point the user there instead of bootstrapping.
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

Before committing, verify the copy landed cleanly: `.agents\skills` has 10 skill directories, `.claude\commands` has 10 files, `.claude\settings.json` and `.claude\hooks\review-loop-trigger.ps1` exist, and neither `.agents\.agents` nor `.claude\.claude` exists.

This delivers: `CLAUDE.md`, `.gitignore`, `skills-lock.json`, `.bootstrap-manifest.json` (scaffold version manifest, used by `upgrade-bootstrap`), `.agents/skills/` (10 skills — 9 synced via `skills-lock.json` + `review-loop`, bundled here), `.claude/commands/` (10 commands), `.claude/settings.json` + `.claude/hooks/review-loop-trigger.ps1` (auto-dispara `review-loop` al abrir/actualizar un PR), `docs/ai-workflow/` (5 docs), `docs/agents/` (3 docs).

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
git config user.name "MartinDele703"
git config user.email "martin.deleon703@gmail.com"
```

Then commit everything as `chore: project scaffolding (AI workflow + skills)`.

If it's already a repo, still set the local identity and commit the scaffolding files on the current branch.

## Step 5 — Report and hand off

Report: files created (counts per area), git status, and the immediate next step of the workflow — closing requirements with `/grill-me` or `/grill-with-docs`, which produces CONTEXT.md content and the first ADRs, followed by `/to-prd` and `/to-issues`.

Do not start requirements, PRDs, or code as part of this skill — bootstrap ends here by design (step 1 of the workflow needs the human present).
