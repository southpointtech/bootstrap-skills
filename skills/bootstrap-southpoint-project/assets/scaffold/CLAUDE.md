# Project AI Operating Rules

This project uses an AI-assisted development workflow.

Claude must not jump directly from requirements to code for non-trivial work.

Before implementing features, bug fixes, refactors, backend changes, deployment changes, or DOMO frontend changes, Claude must follow this workflow:

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
- docs/ai-workflow/PARALELISMO.md — only when more than one lane (carril) runs at the same time: before dispatching a wave, read it together with docs/ai-workflow/PARALELISMO-DEL-PROYECTO.md, the project's lane data.

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
- After implementation, run `/review-loop` at the close of every slice — do NOT ask whether to run it, just run it until it closes (zero medium/high findings, or its turn cap: 2 turns, 1 under `Review-Rigor: light`). The close of a slice is DECLARED, not inferred from having committed: put a `Slice-Close: <what closed>` trailer in that commit's message, and next to it `Review-Rigor: light` when the slice has a low blast radius (a local tool or script, tests only, a behavior-preserving refactor) — without it the slice runs `standard`. Prose-only findings are scored per `/slice-review` Step 5: Low unless the text reaches an end user or would mislead the next modifier, and instructions in the files that govern the agent count as behavior. What fires the loop, what each turn reviews and which files count as documentation are mechanism the `review-loop-trigger` hook enforces on its own: the detail lives in `docs/ai-workflow/AI_DEVELOPMENT_WORKFLOW.md` § 7, not here.
- Before the first code edit of a session, OFFER alignment (`/grill-me` or `/grill-with-docs`) instead of coding straight from the request. The `alignment-gate` hook reinforces that deterministically — it blocks that first edit once per session and never runs the grill on its own — so if the work is trivial or already aligned, just retry the edit and proceed. This breaks the "fix→implement" autopilot that text rules alone do not stop. Which files the gate watches and which it lets through is in `docs/ai-workflow/AI_DEVELOPMENT_WORKFLOW.md` § 1.

## Hard rules

- Do not assume missing requirements. Ask questions first.
- Write a verifiable claim only after verifying it. An **assertion** — a checkable statement in a comment, docstring, or commit message — is written only if it was verified; if you did not verify it, do not write it.
- Prefer vertical slices over horizontal implementation.
- Keep tasks small enough to avoid long-context degradation.
- Use Playwright for frontend validation when UI behavior changes.
- For DOMO frontends, respect iframe constraints and dataset alias mappings.
- For Firebase or Azure backends, identify the target backend before editing.
- Never deploy to DOMO, Firebase, or Azure without explicit human approval.
- Never modify secrets, production config, Firestore rules, Azure resources, or DOMO-deployed assets without approval.
- Never hardcode a secret. Tokens, keys and connection strings live in environment variables or a secret store; tracked files (`.mcp.json`, config, CI) reference them as `${ENV_VAR}`. A secret that reached a commit is a leak: rotate it, do not just delete the line.
- After implementation, report changed files, tests run, risks, and manual QA steps.
- Do not install dependencies published less than 14 days ago without explicit human approval (recent supply-chain attack mitigation). Check a new dependency's publish date before adding it (e.g. `npm view <pkg> time.modified` or `pip index versions <pkg>`).
- Keep each vertical slice a small, reviewable unit of ≤ ~400 lines of *logic* diff. **The ceiling is measured when the slice OPENS**, over what you plan to implement — not over the diff at close: a slice projected well over ~400 lines of logic must be split before implementing, not after, because a diff approaching thousands of lines breaks the review loop. Lines that `/review-loop` adds while fixing its own findings do NOT count against the slice they are fixing — splitting mid-loop breaks the loop, which reviews a range anchored to the review marker. Generated files, vendored code (`docs/vendor/`), lockfiles and snapshots never count. Cohesion comes first. If the closing diff lands far above the ceiling anyway, **declare it in the `Slice-Close:` trailer and in the session handoff** instead of splitting. This planning ceiling is NOT the hook's ~400-line safety net described above: that one asks a different question — "did this go unreviewed?" — counts additions plus deletions over its own exclusion list, and a review it triggers is never spurious, so run the loop. Neither list exempts `.md`: if you exclude prose when you project a slice, that is your judgement, not a rule either of these grants (ADR-0008).
- When slices depend on each other, chain them as stacked PRs instead of one large PR.
- For critical libraries (or ones the agent tends to hallucinate APIs for), vendor the library's real source into the repo (e.g. `docs/vendor/<lib>/`) and point the agent at that code instead of relying on memory or possibly-stale docs.

## Preferred project style

- Favor deep modules with simple interfaces.
- Avoid unnecessary abstraction.
- Structure logic in reusable service layers so the agent calls existing functions instead of duplicating them. Before writing new logic, check whether a service already covers it.
- Model selection: use the most capable model for business logic, architecture, and risky refactors; reserve lighter/faster models for mechanical or low-risk tasks.
- Avoid large context sessions. Use clean-context review before marking important work complete.
- For DOMO Pro Code apps, prefer full copy-paste-ready files when the changed logic spans multiple sections.

## Agent skills

### Issue tracker

Technical issues live as local markdown in `.scratch/`. High-level tasks are registered in Zoho Projects. See `docs/agents/issue-tracker.md`.

### Triage labels

Default vocabulary (needs-triage, needs-info, ready-for-agent, ready-for-human, wontfix). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one `CONTEXT.md` + `docs/adr/` at the root. See `docs/agents/domain.md`.