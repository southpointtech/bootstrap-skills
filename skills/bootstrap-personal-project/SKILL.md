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
- If `CLAUDE.md` or `docs/ai-workflow/` exist but there is **no** `.bootstrap-manifest.json`, the project is **not** bootstrapped — it just has its own files. Do **not** say "already bootstrapped", and do **not** derive to `upgrade-bootstrap` (that skill is only for projects that already have a manifest). Instead, enter **Step 0b — Adoption mode** below: install the methodology while preserving the project's own content.
- If the directory contains other files (code, docs), list them and confirm with the user before proceeding. Never overwrite an existing file; scaffold around it.

## Step 0b — Adoption mode

Reached from Step 0 when the project has its own `CLAUDE.md` (or `docs/ai-workflow/`) but no `.bootstrap-manifest.json`. Goal: install the 8-step methodology without losing the project's context or identity. Two invariants govern this mode: **the original is never lost** (a verbatim, permanent backup), and **the merge is never applied before the user approves a coverage map** of where each block of their content goes.

Define `$skill` and `$proj` as in Step 2.

### A. Back up the original verbatim

Before copying anything, stash the project's `CLAUDE.md` so the scaffold copy can't clobber it:

```powershell
Copy-Item "$proj\CLAUDE.md" "$proj\CLAUDE.legacy.md" -Force
```

### B. Copy the scaffold, then park the backup

Run **Step 2** exactly as written (the enumerated copy + `.gitignore`). This installs the canonical `CLAUDE.md`, all 44 files, and `.bootstrap-manifest.json`, overwriting the project's `CLAUDE.md` with the canonical 8-step template — fine, the original is stashed. Then move the stash to its permanent home (now that `docs/agents/` exists from the scaffold copy):

```powershell
Move-Item "$proj\CLAUDE.legacy.md" "$proj\docs\agents\legacy-claude.md" -Force
```

`docs/agents/legacy-claude.md` stays in the repo forever as the recovery net.

### C. Classify the original's content

Read `docs/agents/legacy-claude.md`. Split it into blocks (by heading or logical unit). Classify each block into exactly one destination, **moving text verbatim — never paraphrase or summarize**:

- **Operational rule** (governs behavior, e.g. "never deploy without approval", "don't trust the 2xx as proof of arrival") → the `## Hard rules` section of the canonical `CLAUDE.md`.
- **Domain knowledge** (what the project does, integrations, technical gotchas, branching model) → `docs/agents/domain.md`, appended under a new `## Project-specific domain` section.
- **Project description** (the one-line of what this is) → `CONTEXT.md` (created in Step 3).
- **Doesn't fit / unsure** → leave it only in `legacy-claude.md` and mark it on the map for the user to decide.

### D. Present the coverage map and get approval

Show the user a table: every block of the original → its destination, quoting the block verbatim. Make any unassigned ("doesn't fit") blocks visible. Get a **single explicit approval** (the user may correct individual rows before approving). Do **not** write the merge until approved.

### E. Apply the merge

After approval: insert operational-rule blocks into `## Hard rules` as new bullets (verbatim); append domain blocks under `## Project-specific domain` in `docs/agents/domain.md` (verbatim); seed `CONTEXT.md` with the description. Leave `legacy-claude.md` untouched as the permanent backup.

The `.bootstrap-manifest.json` copied in step B records the canonical `CLAUDE.md` hash as its base. Because the project's `CLAUDE.md` now differs (project Hard rules merged in), a future `upgrade-bootstrap` automatically classifies it as **customized** and never overwrites it — no extra sealing needed.

### F. Continue with Steps 3–6

Proceed to Step 3 (project-specific files — but if step E already seeded `CONTEXT.md`, do **not** overwrite it with a stub), Step 4 (MCP servers — the `.mcp.json` menu applies to adopted projects too), Step 5 (git), and Step 6 (report). In the Step 6 report, explicitly state that the original is preserved at `docs/agents/legacy-claude.md`, and list which blocks went to `## Hard rules` vs `docs/agents/domain.md`.

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

## Step 4 — MCP servers (.mcp.json)

Ask which MCP tools this project will use, then generate a committed `.mcp.json` (project scope). Tokens are referenced via `${VAR}` — never written into the file.

Present the personal catalog with `AskUserQuestion` (multiSelect): **firebase**, **zoho-personal**, **github**. Let the user pick zero or more.

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

If the directory is not a git repository: `git init -b main`.

Set the **local** identity (local, so the user's global git config is untouched):

```powershell
git config user.name "MartinDele703"
git config user.email "martin.deleon703@gmail.com"
```

Then commit everything as `chore: project scaffolding (AI workflow + skills)`.

If it's already a repo, still set the local identity and commit the scaffolding files on the current branch.

## Step 6 — Report and hand off

Report: files created (counts per area), git status, and the immediate next step of the workflow — closing requirements with `/grill-me` or `/grill-with-docs`, which produces CONTEXT.md content and the first ADRs, followed by `/to-prd` and `/to-issues`. If a `.mcp.json` was generated, also report the **environment variables to set** (as persistent Windows user variables) and prerequisites from the script's summary — e.g. `ZOHO_PERSONAL_MCP_URL`, `GITHUB_PERSONAL_ACCESS_TOKEN` (+ Docker running), or `firebase login` once. The MCP servers won't connect until those env vars exist; this is expected, not an error.

Do not start requirements, PRDs, or code as part of this skill — bootstrap ends here by design (step 1 of the workflow needs the human present).
