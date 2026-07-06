# AI Project Bootstrap

Skills for [Claude Code](https://claude.com/claude-code) that install a disciplined, AI-assisted development workflow into any project — before requirements or code, so every session starts governed by the workflow instead of improvising.

## What you get

Running `bootstrap-ai-project` inside a project directory installs:

- **`CLAUDE.md`** — an 8-step operating workflow: alignment → PRD → vertical slices → task formatting → TDD → QA → clean-context review → human approval.
- **`docs/ai-workflow/`** — the workflow docs: PRD and task templates, QA checklist, deployment rules.
- **`docs/agents/`** — agent conventions: local issue tracker, triage labels, domain docs.
- **10 custom skills** (`.agents/skills/`) — grill-me, grill-with-docs, tdd, to-prd, to-issues, triage, handoff, zoom-out, review-loop, and a skills setup helper.
- **2 hooks** (`.claude/hooks/`) — `review-loop-trigger` (auto-runs an iterative code-review loop every time you commit a slice on a feature branch) and `alignment-gate` (stops the first code edit of a session and offers to align on requirements first).
- **`.bootstrap-manifest.json`** — a version manifest so `upgrade-bootstrap` can bring future scaffold improvements without clobbering your customizations.

## Requirements

- [Claude Code](https://claude.com/claude-code)
- [PowerShell 7+](https://learn.microsoft.com/powershell/scripting/install/installing-powershell) (`pwsh`) — Windows, macOS or Linux
- git

## Install

Clone this repository, then run from its root:

```powershell
pwsh -NoProfile -File install.ps1
```

This copies the skills into `~/.claude/skills/`. They become active in your next Claude Code session.

## Use

In a new or existing project directory, start Claude Code and say:

> bootstrap this project

Claude picks up the `bootstrap-ai-project` skill and walks you through the setup (project info, optional MCP servers, git). Existing projects with their own `CLAUDE.md` are **adopted**, never overwritten — the original is preserved verbatim and merged with your approval.

## Update

```powershell
git pull
pwsh -NoProfile -File install.ps1
```

Then, inside each bootstrapped project, ask Claude to run `upgrade-bootstrap` — it applies only the delta since your install and never overwrites your customizations.
