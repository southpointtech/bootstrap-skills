---
name: bootstrap-southpoint-project
description: Bootstrap a new SOUTHPOINTLABS client project directory with the full AI-assisted workflow scaffolding (CLAUDE.md 8-step workflow, docs/ai-workflow, docs/agents, custom skills like grill-me/tdd/to-prd, the project's .mcp.json for DOMO/Zoho, git init as southpointtech). Use whenever the user says they are starting/arrancando a new Southpoint/SOUTHPOINTLABS/HSS/work/client project, asks for "archivos base", "setup inicial del proyecto", "scaffolding", "preparar el repo/ambiente", "armá la estructura del proyecto", "generá el CLAUDE.md y el .mcp.json de este proyecto", "dejá listo este repo para laburar como en Forecasting", or wants to replicate the Forecasting App modus operandi in a new directory — even if they don't name this skill. This is per-PROJECT (run inside the project folder). For personal (non-work) projects use bootstrap-personal-project; to prepare the MACHINE itself (DOMO token, env vars, clients) use setup-mcp-workstation; to update an already-bootstrapped project use upgrade-bootstrap.
---

# Bootstrap SOUTHPOINTLABS Project

Recreates the proven setup of the Forecasting App in a new project directory: the 8-step AI workflow (alignment → PRD → vertical slices → Zoho tasks → TDD → QA → clean-context review → human approval), the workflow docs it references, the agent conventions (local issue tracker, triage labels, domain docs), and the custom skills (grill-me, grill-with-docs, tdd, to-prd, to-issues, triage, handoff, zoom-out, review-loop).

The point of this skill is that the scaffolding lands **before** requirements or code, so every later session starts governed by the workflow instead of improvising.

All template files live in `assets/scaffold/` next to this SKILL.md — copy them, don't regenerate them, so the wording of the workflow stays identical across projects.

## Step 0 — Safety check

Run this in the directory the user designates as the new project root (usually the current working directory).

- If `.bootstrap-manifest.json` already exists, the project **was bootstrapped with this scaffold** — do not re-run bootstrap. Tell the user to use `upgrade-bootstrap` to pull scaffold changes, and stop.
- If `CLAUDE.md` or `docs/ai-workflow/` exist but there is **no** `.bootstrap-manifest.json`, the project is **not** bootstrapped — it just has its own files. Do **not** say "already bootstrapped", and do **not** derive to `upgrade-bootstrap` (that skill is only for projects that already have a manifest). Instead, enter **Step 0b — Adoption mode** below: install the methodology while preserving the project's own content.
- If the directory contains other files (code, docs), list them and confirm with the user before proceeding. Where the project has its own version of a file the scaffold also ships, the copy **does** overwrite it — backing the original up to `.bootstrap-backup/` and declaring it under `overwritten` first (Step 2, ADR-0007). Report that list; never assume nothing of the project's was touched.

**Chequeo de máquina (no bloqueante):** si no existe la env var `SOUTHPOINT_GIT_NAME` ni el archivo `"$env:USERPROFILE\.claude\mcp-workstation.local.json"`, esta PC probablemente no fue preparada para Southpoint. No frenes el bootstrap, pero avisá al usuario que conviene correr la skill `setup-mcp-workstation` una vez (deja la identidad git, los tokens de DOMO/Zoho y Playwright listos), y anotalo en el reporte del Step 6. Si la env var o el archivo existen, no digas nada.

## Step 0b — Adoption mode

Reached from Step 0 when the project has its own `CLAUDE.md` (or `docs/ai-workflow/`) but no `.bootstrap-manifest.json`. Goal: install the 8-step methodology without losing the project's context or identity. Two invariants govern this mode: **the original is never lost** (a verbatim, permanent backup), and **the merge is never applied before the user approves a coverage map** of where each block of their content goes.

Define `$skill` and `$proj` as in Step 2.

### A. Copy the scaffold

Run **Step 2** exactly as written (the `copy-scaffold.ps1` script, which merges into pre-existing directories like `docs/` instead of nesting). This installs the canonical `CLAUDE.md`, all 52 files, and `.bootstrap-manifest.json`, overwriting the project's `CLAUDE.md` with the canonical 8-step template — fine: the script copies every file it is about to overwrite into `.bootstrap-backup/` first, and lists them under `overwritten` in its JSON report. **Keep that report — steps B and D both need it.**

### B. Park the original CLAUDE.md

**First look at `docs/agents/legacy-claude.md`.** If it already exists it is normally the original, parked by an earlier run — leave it exactly as it is and go straight to step C. Read it before trusting it, though: if it is empty, or is plainly not this project's `CLAUDE.md`, then the real original is the backup below and the name collided; say so rather than classifying an empty or foreign file. Never move anything on top of it: it is the permanent recovery net, and by the time a re-run makes a fresh backup the project's own text is no longer what gets copied.

Otherwise park it, **only if `.bootstrap-backup/CLAUDE.md` exists after the copy**. For this one file take the **un-numbered** path — the opposite of the rule for every other entry. The numbered copies (`.2`, `.3`) hold what a later run overwrote, which by then is the canonical template plus whatever was merged or edited into it; the un-numbered one is the project's own original, and that is what step C has to classify. Everywhere else you want the newest, here you want the oldest.

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

**The map must also cover every other entry in the copy's `overwritten` list.** Those are the project's own files the scaffold just replaced, and each one is a decision, not a default: keep the scaffold's version (often right — it is the update you came to deliver), restore the project's from `.bootstrap-backup/`, or merge the two. A `.gitignore` almost always needs merging, because the scaffold's rules are additions and the project's own entries are still needed. Nothing is lost either way — each original sits at the `backup` path its own `overwritten` entry names — but say out loud what each file got. `CLAUDE.md` is off this map **only when step B actually parked it**; if step B took the branch that left `legacy-claude.md` alone, its backup holds the project's live `CLAUDE.md` (canonical plus everything merged into it since) and it needs a row like any other file, or that work is reverted with nobody asked.

Get a **single explicit approval** (the user may correct individual rows before approving). Do **not** write the merge until approved.

### E. Apply the merge

After approval: insert operational-rule blocks into `## Hard rules` as new bullets (verbatim); append domain blocks under `## Project-specific domain` in `docs/agents/domain.md` (verbatim); seed `CONTEXT.md` with the description. Leave `legacy-claude.md` untouched as the permanent backup.

The `.bootstrap-manifest.json` copied in step A records the canonical `CLAUDE.md` hash as its base. Because the project's `CLAUDE.md` now differs (project Hard rules merged in), a future `upgrade-bootstrap` automatically classifies it as **customized** and never overwrites it — no extra sealing needed.

### F. Continue with Steps 3–6

Proceed to Step 3 (project-specific files — but if step E already seeded `CONTEXT.md`, do **not** overwrite it with a stub), Step 4 (MCP servers — the `.mcp.json` menu applies to adopted projects too), Step 5 (git), and Step 6 (report). In the Step 6 report, state where the original ended up — preserved at `docs/agents/legacy-claude.md` with the list of which blocks went to `## Hard rules` vs `docs/agents/domain.md`, or, on the skip path of step B, that there was no original distinct from the canonical template and nothing was classified. Never claim the file exists without having checked that it does — parked by this run or by an earlier one.

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

This delivers: `CLAUDE.md`, `.gitignore`, `skills-lock.json`, `.bootstrap-manifest.json` (scaffold version manifest, used by `upgrade-bootstrap`), `.agents/skills/` (11 skills — 9 synced via `skills-lock.json` + `review-loop` and `slice-review`, bundled here), `.claude/commands/` (11 commands), `.claude/settings.json` + `.claude/hooks/review-loop-trigger.ps1` (auto-dispara `review-loop` al abrir/actualizar un PR) + `.claude/hooks/alignment-gate.ps1` (frena el primer edit de código por sesión y ofrece alinear antes de codear), `docs/ai-workflow/` (5 docs), `docs/agents/` (3 docs).

## Step 3 — Project-specific files

Create these (they are per-project, so they are not in the scaffold):

- `README.md` — `# <Project Name>` plus the one-line description.
- `CONTEXT.md` — stub with the project name and a note that the canonical glossary/domain model will be produced by `grill-with-docs` during requirements closing. Don't invent domain content.
- `docs/adr/.gitkeep` — ADRs accumulate here as decisions crystallise.
- `.scratch/` directory — local issue tracker home (gitignored by design).

## Step 4 — MCP servers (.mcp.json)

Ask which MCP tools this project will use, then generate a committed `.mcp.json` (project scope). Tokens are referenced via `${VAR}` — never written into the file.

Present the southpoint catalog with `AskUserQuestion` (multiSelect): **firebase**, **domo**, **zoho-projects**, **github**. Let the user pick zero or more. If `AskUserQuestion` is unavailable (non-interactive or agent context), don't block: infer the servers from the project's `CLAUDE.md`/context, or pick none if it's unclear, and note the inferred choice in the Step 6 report.

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

Set the **local** identity (local, so the user's global git config is untouched):
La identidad se toma de las env vars que deja `setup-mcp-workstation` (`SOUTHPOINT_GIT_NAME` / `SOUTHPOINT_GIT_EMAIL`), con fallback a la identidad de servicio si no están seteadas:

```powershell
git config user.name  "$($env:SOUTHPOINT_GIT_NAME  ?? 'southpointtech')"
git config user.email "$($env:SOUTHPOINT_GIT_EMAIL ?? 'mdeleon@agtium.com')"
```

Then commit everything as `chore: project scaffolding (AI workflow + skills)` — **except `.bootstrap-backup/`**. That directory holds copies of the project's own files and is deliberately not gitignored so the user sees it; whether it belongs in history is their call, not the skill's. Stage with an exclusion rather than a bare `git add -A` — `git add -A -- . ':!.bootstrap-backup'` — and point the directory out in the Step 6 report.

If it is already its own repo root, still set the local identity and commit the scaffolding files on the current branch.

## Step 6 — Report and hand off

Report: files created (counts per area), git status, and the immediate next step of the workflow — closing requirements with `/grill-me` or `/grill-with-docs`, which produces CONTEXT.md content and the first ADRs, followed by `/to-prd` and `/to-issues`. If a `.mcp.json` was generated, also report the **environment variables to set** (as persistent Windows user variables) and prerequisites from the script's summary — e.g. `ZOHO_SOUTHPOINT_MCP_URL`, `DOMO_SOUTHPOINT_TOKEN`, `DOMO_MCP_HOME` (esta última la deja `setup-mcp-workstation` al clonar DOMO), `GITHUB_SOUTHPOINT_TOKEN` (+ Docker running), or `firebase login` once. The MCP servers won't connect until those env vars exist; this is expected, not an error.

Do not start requirements, PRDs, or code as part of this skill — bootstrap ends here by design (step 1 of the workflow needs the human present).
