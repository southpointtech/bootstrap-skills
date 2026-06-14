<p align="center">
  <img src="docs/assets/southpoint-icon.png" alt="SOUTHPOINTLABS" width="110" />
</p>

<h1 align="center">Bootstrap Skills</h1>

<p align="center">
  <strong>SOUTHPOINTLABS · AI-assisted development, standardized.</strong>
</p>

<p align="center">
  A set of Claude Code skills that scaffold every new project with the same proven,
  AI-first way of working — <em>before</em> a single requirement or line of code is written.
</p>

---

## What this is

**Bootstrap Skills** is the source of truth for how we start projects at SOUTHPOINTLABS.

Instead of every repo improvising its own structure, conventions, and AI workflow, these skills
drop a complete, battle-tested operating model into a fresh directory in seconds: the 8-step
AI-assisted workflow, the supporting documentation, the agent conventions, the custom Claude Code
skills, and a correctly-configured git repository.

The skills run **inside [Claude Code](https://claude.com/claude-code)**. You open Claude in a folder,
say what you're starting, and the right skill takes over.

## Why it matters

The methodology was extracted from a real, working project (the Forecasting App) where it proved itself
end to end: closing requirements → SRS → tasks → TDD implementation. Packaging it as skills gives the
whole company three things:

- **Consistency** — every project starts from the *same* CLAUDE.md, the same workflow, the same
  conventions. Onboarding a teammate onto any repo feels familiar.
- **Quality from line zero** — the scaffolding lands *before* the code, so every later Claude Code
  session is governed by the workflow instead of improvising. No more "we'll add structure later".
- **Speed** — what used to be a manual, error-prone setup is now a single request. In our evals, the
  skill-driven setup was **~3× faster, used ~35% fewer tokens, and passed 100% of checks** versus an
  unguided baseline that got the git identity wrong, picked a stack before alignment, and skipped half
  the conventions.

> Why "before the code"? The first step of the workflow needs a human (requirements alignment).
> The bootstrap deliberately stops there and hands off — it sets the stage, it doesn't start writing
> the play.

## How it works

Each skill is a self-contained package: a `SKILL.md` describing *when* and *how* Claude should act,
plus an `assets/scaffold/` folder holding the exact template files to copy. Claude **copies** these
files verbatim (it doesn't regenerate them), so the wording of the workflow stays identical across
every project in the company.

A typical lifecycle:

```
  New machine ──▶ setup-mcp-workstation   (run once per PC: credentials, MCP clients)
                          │
  New project ──▶ bootstrap-*-project     (scaffold CLAUDE.md + workflow + skills + git)
                          │
  Scaffold drifts ──▶ upgrade-bootstrap   (pull only the new/changed scaffold, keep your edits)
```

When the scaffold itself evolves, projects don't fall behind: each scaffolded project records a
`.bootstrap-manifest.json`, and `upgrade-bootstrap` uses it to apply *only* the delta — never
overwriting a file you've customized.

## The skills (components)

| Skill | What it does | When to use |
|---|---|---|
| **`setup-mcp-workstation`** | Prepares a Windows PC **once**: stores git identity, DOMO token and Zoho MCP URL as user env vars, clones the DOMO MCP client + installs its deps, installs Playwright browsers. | First time someone uses these skills on a new machine (onboarding). |
| **`bootstrap-southpoint-project`** | Scaffolds a **client / SOUTHPOINTLABS** project: full AI workflow + DOMO & Zoho conventions, git initialized with the company identity. | Starting any client/work project. |
| **`bootstrap-personal-project`** | Scaffolds a **personal** project: same workflow, without DOMO; Playwright / Firebase / Azure / Zoho conventions persist, git initialized with a personal identity. | Starting a personal / side project. |
| **`upgrade-bootstrap`** | Brings an already-bootstrapped project up to the current scaffold, applying only what's missing or changed and never clobbering your customizations. | An existing project is on an older version of the scaffold. |

## What gets scaffolded into a project

Both bootstrap skills land the same operating model:

- **`CLAUDE.md`** — the 8-step AI-assisted workflow (alignment → PRD → vertical slices → tasks →
  TDD → QA → clean-context review → human approval) plus a **Workflow State Machine** that keeps
  Claude acting as a guide through the process, not a loose tool.
- **`docs/ai-workflow/`** — the workflow documentation the CLAUDE.md references.
- **`docs/agents/`** — agent conventions (local issue tracker, triage labels, domain docs).
- **Custom Claude Code skills** — `grill-me`, `grill-with-docs`, `tdd`, `to-prd`, `to-issues`,
  `triage`, `handoff`, `zoom-out`, `review-loop` and their commands.
- **A configured git repository** — `main` branch, correct identity, an initial scaffolding commit,
  and a `.bootstrap-manifest.json` so the project can later be upgraded safely.

## Getting started

### 1. Prepare your machine (once per PC)

The first time you use these skills on a computer:

1. Clone this repository.
2. Deploy the skills into Claude Code:
   ```powershell
   .\tools\sync-skills.ps1
   ```
3. Open Claude Code and say, e.g., *"set up my machine for Southpoint"* — this runs
   **`setup-mcp-workstation`**, which asks for your git identity, DOMO token and Zoho MCP URL
   **once**, persists them as user env vars (never printing the secrets), clones the official DOMO
   MCP client and installs its dependencies, and installs the Playwright browsers.
4. Restart Claude Code so it picks up the new environment variables.

> Git, Python (for DOMO) and Node (for Playwright) are prerequisites. The skill checks for them and,
> if any are missing, tells you how to install them — it won't silently fail.

### 2. Start a new project

Open Claude Code **in the new project's folder** and say what you're starting:

- *"new Southpoint project, set up the base files"* → runs `bootstrap-southpoint-project`
- *"I'm starting a personal project, prepare the repo and environment"* → runs `bootstrap-personal-project`

You don't need to name the skill — the request is enough for Claude to pick the right one.

### 3. Keep an existing project up to date

Open Claude Code **inside the already-bootstrapped project** and ask to *"update the bootstrap"* or
*"pull the new scaffold changes"* → runs `upgrade-bootstrap`, which shows you the delta and applies
it with your approval.

## Repository structure

```
skills/          The four skills (each: SKILL.md + assets/scaffold with ~43 template files)
tools/           sync-skills.ps1  → deploys repo → ~/.claude/skills/
                 gen-manifest.ps1 → regenerates the scaffold's .bootstrap-manifest.json
docs/            HISTORIA.md  → origin, design decisions, eval results
                 TESTING.md   → how to run the skill evals
                 assets/      → branding
CLAUDE.md        Operating rules for maintaining this repo
```

## Maintaining the skills

The **installed** copies (the ones Claude Code actually runs) live in `C:\Users\<you>\.claude\skills\`.
Editing the skills here has **no effect** until you deploy. The workflow is:

1. **Edit** the skill in this repo (`SKILL.md` and/or `assets/scaffold/`).
2. **Test** with the skill-creator evals before deploying — see [`docs/TESTING.md`](docs/TESTING.md).
   At minimum: the empty-directory eval and the pre-existing-files eval.
3. **Deploy** with `tools\sync-skills.ps1` (copies repo → `~/.claude/skills/`, removing the installed
   version first so no orphan files are left behind).
4. **Commit** here.

A few hard rules worth knowing (the full list is in [`CLAUDE.md`](CLAUDE.md)):

- The two bootstrap skills must stay **mirrored in structure** — a change to the mechanics of one
  applies to the other. They only differ in DOMO content and git identity.
- The scaffold's `.bootstrap-manifest.json` is **generated, not hand-edited**. `sync-skills.ps1`
  regenerates it before deploying; if you commit a scaffold change without syncing, regenerate it with
  `tools/gen-manifest.ps1` so `upgrade-bootstrap` compares against correct hashes.
- Don't leave empty directories in `assets/scaffold/` (git won't track them and they add noise).
- Any testing artifacts (eval workspaces, test projects) are deleted when you're done.

For the full history, design rationale, and eval results, see [`docs/HISTORIA.md`](docs/HISTORIA.md).

---

<p align="center">
  <sub>SOUTHPOINTLABS · Built on <a href="https://claude.com/claude-code">Claude Code</a></sub>
</p>
