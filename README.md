<p align="center">
  <img src="docs/assets/southpoint-icon.png" alt="SOUTHPOINTLABS" width="110" />
</p>

<h1 align="center">Bootstrap Skills</h1>

<p align="center">
  <strong>SOUTHPOINT LABS · AI-assisted development, standardized.</strong>
</p>

<p align="center">
  A set of Claude Code skills that scaffold every new project with the same proven,
  AI-first way of working — <em>before</em> a single requirement or line of code is written.
</p>

---

## What this is

**Bootstrap Skills** is the source of truth for how we start projects at SOUTHPOINT LABS.

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

## The 8-step workflow (the heart of it)

The single most important rule the scaffold installs is this:

> **Claude must not jump straight from a request to code.** For any non-trivial work, it walks the
> developer through eight steps first, producing a clear artifact at each one.

Why that matters: an AI agent left to improvise will happily pick a stack before anyone agreed on the
problem, write a 2,000-line change nobody can review, degrade as the context fills up, and deploy
without a human looking. The workflow exists to prevent exactly those failure modes — it turns "build
me X" into a reviewable, testable, approvable sequence. Each phase ends with Claude reporting what was
produced and **waiting for your approval** before moving on (the *Workflow State Machine*); it never
assumes you remember the next step.

| # | Phase | What happens — and the artifact it produces | Skill / command |
|---|---|---|---|
| **1** | **Alignment / Grill Me** | Claude *interviews you* to kill ambiguity **before writing any code**: product goal, affected users, current vs. desired behavior, data dependencies, platform constraints, edge cases, testing strategy, deployment risks, acceptance criteria. It pressure-tests your plan and finds the holes. | `/grill-me`, `/grill-with-docs` |
| **2** | **PRD** | The shared understanding is written up as a **PRD** (Product Requirements Document — the project's requirements spec, the SRS): problem statement, goals, non-goals, user stories, functional / technical / data / testing requirements, acceptance criteria, risks, open questions. | `/to-prd` |
| **3** | **Vertical-slice planning** | The PRD is broken into **independently testable vertical slices** — each one cutting through UI + backend + data + tests — instead of horizontal "DB-only / API-only / UI-only" layers. Each slice is kept small (target ≤ ~400 lines) so it stays reviewable; dependent slices become stacked PRs. | `/to-issues` |
| **4** | **Task formatting** | Each slice becomes a task ready to paste into **Zoho Projects**: title, description, acceptance criteria, dependencies, test plan, deployment target, estimated complexity, affected area (DOMO / Firebase / Azure / Playwright / docs / config). | `/to-issues`, `/triage` |
| **5** | **Test-first implementation** | **One slice at a time.** TDD when practical (red → green → refactor), Playwright tests for UI changes. Focused changes only — no touching unrelated files, no deploying. | `/tdd` |
| **6** | **Automated QA** | Before anything is called "done": unit tests, type checks, lint, Playwright, and the manual QA checklist. If a check can't run, Claude has to say why. | QA checklist |
| **7** | **Clean-context review** | A second review from a **fresh context** (so the author's blind spots don't carry over): `/code-review` → fix only real findings → re-review, looping until no medium/high-severity findings remain. | `/review-loop` |
| **8** | **Human approval** | **Nothing ships without a person.** No deploy to DOMO / Firebase / Azure, and no change to secrets, production config, or Firestore rules, happens without explicit human sign-off. | (human) |

**Why vertical slices?** A slice that delivers one thin end-to-end behavior can be tested, reviewed,
and shipped on its own — so feedback comes early and PRs stay small. Splitting by horizontal layer
(all the DB, then all the API, then all the UI) means nothing works until the very end and every review
is huge.

### The review loop — the automated quality gate

Step 7 deserves its own spotlight, because it's what takes a change from "it works" to **clean,
review-passing code**. The **`review-loop`** skill runs a tight cycle:

```
/code-review on the diff  →  fix ONLY the real findings  →  re-review  →  repeat
                          until no medium/high-severity findings remain (hard cap: 5 turns)
```

What makes it more than "just run a review":

- **It loops until clean, not just once.** It keeps reviewing and fixing until the reviewer stops
  finding medium/high-severity issues — that's the bar for "clean" here. (It adapts Greptile's
  *greploop* to Claude Code's **native** reviewer, so there's no paid external service and no PR or
  remote required — it works on local uncommitted changes too.)
- **It fires automatically.** A bundled hook, `review-loop-trigger`, watches for `gh pr create` /
  `git push` and **injects the order to run the loop on the branch diff** — so the quality gate doesn't
  depend on the agent (or the human) remembering to run it. The manual `/review-loop` is still there
  for reviewing local changes before you commit.
- **It has guardrails.** Reviewers produce false positives, so it doesn't accept findings blindly;
  agents over-fix, so it touches only what each finding is about; and **tests are the objective
  signal** — "looks fine" is not a pass. It refuses to run on huge diffs (≥ ~400 lines), pushing you
  back to smaller slices where the loop is actually accurate.

> A note on "5/5": that score comes from Greptile's tool. Claude Code's reviewer reports findings by
> **severity**, not a number — so here "5/5" means *the latest review surfaced no medium/high-severity
> findings*. Same goal (ship clean code), expressed in the reviewer we actually use.

Two helper skills support the loop without being steps of it: **`/zoom-out`** gives a higher-level map
of how a piece fits the architecture before you dive in, and **`/handoff`** compacts the current
session into a clean handoff so another agent or a fresh terminal can pick up without losing context.

## MCP servers & clients

A big part of working "like Forecasting App" is that Claude can reach the **real systems** the project
runs on — its database, its BI platform, its task tracker, its repo — through
[MCP](https://modelcontextprotocol.io) (Model Context Protocol) servers. These skills wire that up in
**two layers** so it's reproducible and safe:

**1. Machine-level clients** — installed once by `setup-mcp-workstation`, shared by every project:

| Client | What it is | Why |
|---|---|---|
| **DOMO MCP client** | The official `DomoApps/domo-mcp-server`, cloned to `~/.claude/domo-mcp-server` (it's clone-and-run, not a pip package). | Lets any project talk to DOMO without re-installing it each time. |
| **Playwright browsers** | Chromium, installed via `npx playwright install`. | Powers end-to-end UI tests against a real browser. |

**2. Per-project MCP servers** — `bootstrap-southpoint-project` asks which ones a project needs (Step 4)
and writes a committed `.mcp.json` listing only those. From the Southpoint catalog:

| Server | Connects to | What Claude can do with it |
|---|---|---|
| **`domo`** | The **DOMO** BI platform (`python -m domo_mcp`). | Query datasets and cards — pull the data forecasts and reports run on. |
| **`zoho-projects`** | **Zoho Projects** (remote HTTP MCP). | Read and create tasks — the workflow turns the SRS into Zoho tasks. |
| **`firebase`** | A **Firebase** project (`npx firebase-tools`). | Inspect/operate Auth, Firestore and Hosting — the app's backend. Needs `firebase login` once. |
| **`github`** | **GitHub** (runs the GitHub MCP server in Docker). | Pull requests, issues and repo operations. Needs Docker Desktop. |

**How the two layers stay secure.** Secrets (DOMO token, Zoho MCP URL, GitHub token) are stored **once**
as user environment variables by `setup-mcp-workstation` — they never live in a repo. The generated
`.mcp.json` only references them as `${DOMO_SOUTHPOINT_TOKEN}`, `${ZOHO_SOUTHPOINT_MCP_URL}`, etc., so it
is safe to commit. A new machine just re-runs `setup-mcp-workstation` and every project's `.mcp.json`
resolves automatically.

> Personal projects skip DOMO; the Firebase / Zoho / Playwright conventions still apply.

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

