# Project AI Operating Rules

This project uses an AI-assisted development workflow.

Claude must not jump directly from requirements to code for non-trivial work.

Before implementing features, bug fixes, refactors, backend changes, deployment changes, or frontend changes, Claude must follow this workflow:

1. Alignment / Grill Me
2. PRD creation or PRD update
3. Vertical-slice task planning
4. Zoho-ready task formatting
5. Test-first implementation when practical
6. Automated QA
7. Clean-context review
8. Human approval before deployment

## Required workflow docs

Claude must read and follow:

- docs/ai-workflow/AI_DEVELOPMENT_WORKFLOW.md
- docs/ai-workflow/PRD_TEMPLATE.md
- docs/ai-workflow/TASK_TEMPLATE.md
- docs/ai-workflow/QA_CHECKLIST.md
- docs/ai-workflow/DEPLOYMENT_RULES.md

## Workflow State Machine

For any new project or non-trivial feature, Claude must guide the user through this workflow:

1. Source Material Analysis
2. Project Context Creation
3. Grill With Docs
4. PRD Creation
5. PRD Approval
6. Issue / Task Breakdown
7. Zoho Task Formatting
8. TDD Implementation
9. QA / Playwright Validation
10. Clean Context Review
11. Human-approved Deployment

Claude must not assume the user remembers the workflow.

At the end of every phase, Claude must explicitly say:

- Current phase completed
- Files created or updated
- Remaining open questions
- Recommended next command or skill
- Whether human approval is required before continuing

Claude must not move from one phase to the next without explicit user approval.

Recommended transitions:

- After source material analysis, suggest `/grill-with-docs`
- After `/grill-with-docs`, suggest `/to-prd`
- After `/to-prd`, ask for PRD review and approval
- After PRD approval, suggest `/to-issues`
- After issues are approved, suggest `/tdd` for the selected task
- After implementation, suggest QA and the clean-context review via `/review-loop`

## Hard rules

- Do not assume missing requirements. Ask questions first.
- Prefer vertical slices over horizontal implementation.
- Keep tasks small enough to avoid long-context degradation.
- Use Playwright for frontend validation when UI behavior changes.
- For Firebase or Azure backends, identify the target backend before editing.
- Never deploy to Firebase or Azure without explicit human approval.
- Never modify secrets, production config, Firestore rules, or Azure resources without approval.
- After implementation, report changed files, tests run, risks, and manual QA steps.
- Do not install dependencies published less than 14 days ago without explicit human approval (recent supply-chain attack mitigation). Check a new dependency's publish date before adding it (e.g. `npm view <pkg> time.modified` or `pip index versions <pkg>`).
- Keep each vertical slice a small, reviewable unit. Target ≤ ~400 lines of change per PR; a diff approaching thousands of lines breaks the review loop. If a slice exceeds ~400 lines, split it before implementing.
- When slices depend on each other, chain them as stacked PRs instead of one large PR.
- For critical libraries (or ones the agent tends to hallucinate APIs for), vendor the library's real source into the repo (e.g. `docs/vendor/<lib>/`) and point the agent at that code instead of relying on memory or possibly-stale docs.

## Preferred project style

- Favor deep modules with simple interfaces.
- Avoid unnecessary abstraction.
- Structure logic in reusable service layers so the agent calls existing functions instead of duplicating them. Before writing new logic, check whether a service already covers it.
- Model selection: use the most capable model for business logic, architecture, and risky refactors; reserve lighter/faster models for mechanical or low-risk tasks.
- Avoid large context sessions. Use clean-context review before marking important work complete.
- Prefer full copy-paste-ready files when the changed logic spans multiple sections.

## Agent skills

### Issue tracker

Issues técnicos viven como markdown local en `.scratch/`. Tareas de alto nivel se registran en Zoho Projects. Ver `docs/agents/issue-tracker.md`.

### Triage labels

Vocabulario por defecto (needs-triage, needs-info, ready-for-agent, ready-for-human, wontfix). Ver `docs/agents/triage-labels.md`.

### Domain docs

Single-context: un `CONTEXT.md` + `docs/adr/` en la raíz. Ver `docs/agents/domain.md`.
