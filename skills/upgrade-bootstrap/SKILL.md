---
name: upgrade-bootstrap
description: Use to update a project that was already bootstrapped with a bootstrap-*-project skill when the scaffold has since changed (new files, edited rules, new skills like review-loop). Detects what is missing, outdated, or customized using the project's .bootstrap-manifest.json (with a fallback for legacy projects without one), and applies the delta with your approval — never overwriting your customizations. Trigger whenever the user wants to "actualizar/sincronizar el bootstrap", "traer los cambios nuevos del scaffold", "traé las skills nuevas (review-loop, etc.)", "poné al día el scaffolding de este proyecto", "mergeá los cambios del bootstrap acá", "sync the workflow scaffolding", or mentions a bootstrapped project being on an older/outdated scaffold version. Run this inside the already-bootstrapped project, not in the bootstrap-skills repo. Do NOT use to bootstrap a brand-new project (use your bootstrap-*-project skill), to run the review loop on a PR (use review-loop), or to update npm/package dependencies.
---

# Upgrade Bootstrap

Update an already-bootstrapped project to the current scaffold, without clobbering what the project customized.

Re-running `bootstrap-*-project` does NOT work for this — its safety check stops when `CLAUDE.md`/`docs/ai-workflow/` already exist. This skill applies the *delta* instead.

## How it decides (merge-base of 3 hashes)

For each scaffold file it compares three hashes — **base** (what the manifest recorded at install), **actual** (what's in the project now), **canonical** (the current scaffold). That yields: missing, up-to-date, outdated-safe (`actual==base`, safe to update), customized (`actual!=base`, never overwrite), or orphan (in project, not in canonical). Without a project manifest (legacy), it can only tell up-to-date from different — different files are shown as diffs for you to decide.

## Steps

### 1. Locate the project and the canonical scaffold

- The project is the current working directory unless the user points elsewhere.
- If `<project>/.bootstrap-manifest.json` exists, read `generatedFrom`; the canonical scaffold is `~/.claude/skills/<generatedFrom>/assets/scaffold`.
- If there is no manifest (legacy project), ask the user which bootstrap-*-project skill this project was originally bootstrapped with, and use that skill's scaffold as canonical.

### 2. Run the comparison

```powershell
pwsh -File <this-skill>/scripts/compare-scaffold.ps1 -ProjectDir "<project>" -CanonicalScaffold "<canonical scaffold>"
```

This prints JSON with `missing`, `outdated`, `customized`, `orphan`, `uptodate`, `hasProjectManifest`, `canonicalVersion`, `variant`.

### 3. Report

Summarize the JSON grouped by category, with counts. Be explicit about what each action will do. If `hasProjectManifest` is false, tell the user this is a legacy adoption run: customizations and old-but-untouched files can't be distinguished, so they appear under "different — your call".

Also check for an inherited `SESSION_HANDOFF.md` at the project root and in `docs/`. The comparison does not see them (they are not part of the scaffold), so list each one that exists in the plan too, as "retired: latest block migrated to the handoff in temp, then removed" (step 4b).

### 4. Apply, with the user's approval

Get explicit approval before writing anything. Then:

- **missing** → copy from the canonical scaffold into the project (same relative path), creating the parent directory first if it does not exist — the scaffold does add new directories (`.claude/scripts/`), and a plain copy into a missing parent fails. Special case: the canonical key `.gitignore` is sourced from `gitignore.txt` in the scaffold. Special case `.claude/settings.json`: copy it only if absent; if the project already has its own, treat it as the `settings.json` merge below instead of a plain copy.
  Do not fill in the placeholders of `docs/ai-workflow/PARALELISMO-DEL-PROYECTO.md` (its `{{…}}` marks): they are the project's lane data, filled in when the project opens its first wave of parallel lanes, and until then `.claude/scripts/abrir-carril.ps1` refuses to open a lane. Leave them as they come.
- **outdated** → overwrite the project file with the canonical version.
- **customized / different** → show the diff (canonical vs project). Offer, per file: skip (keep yours), or an assisted merge where you help integrate the new bits into the user's version. Never overwrite without per-file consent. **Special case `.claude/settings.json`:** do NOT diff-merge by hand — run `merge-settings.ps1` (below), which adds every missing canonical hook (`review-loop-trigger`, `alignment-gate`, and any future ones) idempotently without touching the rest of the user's config.
- **orphan** → list only; do not delete. Mention the user can remove them by hand.

When copying `.gitignore`, read from `<canonical scaffold>/gitignore.txt`.

**Merge of `.claude/settings.json`** (whenever it appears in `missing` with a pre-existing file, or in `customized`):

```powershell
pwsh -File <this-skill>/scripts/merge-settings.ps1 -ProjectSettings "<project>/.claude/settings.json" -CanonicalSettings "<canonical scaffold>/.claude/settings.json"
```

It is idempotent — running it twice never duplicates any hook. If the project had no `settings.json`, it copies the canonical one verbatim.

### 4b. Retire the inherited session handoff

Only if step 3 listed a `SESSION_HANDOFF.md`. The approval for the plan covers it: there is no separate question.

First, you migrate one block. Each file keeps its newest block at the top; when both files exist, take the more recent of the two tops (by the date in its heading, or the file's last commit when it has none). Write it to the handoff path in a single write, in that rule's format: the current state plus references to commits, issues and files, not a transcript. Move whatever already sits at that path to its `.prev` first, once: the rule keeps a single previous generation, so a second write would push the developer's live handoff out. If the block describes closed work, or is old enough that the code has moved past it, say so in one line and create nothing.

The path comes from the `### Handoff` section of the project's `CLAUDE.md`. If the project has none (step 4 left its `CLAUDE.md` customized), compute the path with the rule in `<canonical scaffold>/CLAUDE.md`, which depends only on the OS temp dir and the git toplevel, and carry the gap to the step 6 report.

Then invoke the script from the project's bootstrap skill (the one step 1 resolved, `generatedFrom` or the user's answer). It lives there and nowhere else:

```powershell
pwsh -File ~/.claude/skills/<generatedFrom>/scripts/retire-session-handoff.ps1 -ProjectDir "<project>"
```

It takes tracked files out with `git rm`, which stages the removal and does not commit it. Untracked and ignored ones go to `.bootstrap-backup/`, numbered `.2` when a backup is already there. It prints `{ removed[], backedUp[{file, backup}] }`. A tracked file with uncommitted edits appears in both lists: its edits are backed up before the `git rm`. Use the `backup` field as reported; do not derive it from `file`. If a file has staged changes that differ from both HEAD and the disk, the script exits non-zero having retired nothing: relay its message, leave both files in place, and say so in the step 6 report.

### 5. Re-seal the manifest

After applying, record the new baseline so the next run is precise:

```powershell
pwsh -File <this-skill>/scripts/reseal-manifest.ps1 -ProjectDir "<project>" -CanonicalScaffold "<canonical scaffold>"
```

For a legacy project this seeds `.bootstrap-manifest.json` for the first time — the project is now "adopted" into the versioning system.

### 5b. Variant extras

The bootstrap skill the canonical scaffold belongs to (the folder holding its `assets/scaffold`) may ship an `upgrade-extras.md` at its root: steps only that variant needs after an upgrade. If the file exists, read it and follow it now; its own completion criterion says what the step 6 report must carry. If it does not exist, there are no extras.

### 6. Report what changed

List files copied, updated, left customized (skipped), orphans flagged, the handoff files removed and backed up by step 4b (with each `backup` path) and, when the project's `CLAUDE.md` has no `### Handoff` section, that it should merge it: a next session only finds the migrated handoff through that rule, and whatever step 5b's extras asked the report to carry. Remind the user to review the diff and commit when satisfied. Do not commit on their behalf unless they ask.

## Guardrails

- Never overwrite a `customized` file without explicit per-file consent — that's the whole point.
- Don't delete orphans automatically.
- The scaffold's `.gitignore` lives as `gitignore.txt` in the source; map it when copying.
- If `compare-scaffold.ps1` errors (e.g. canonical scaffold has no manifest), stop and report — don't guess.
- `.mcp.json` is not part of the scaffold nor the manifest, so `compare-scaffold.ps1` does not see it and this upgrade never touches it. If the project was bootstrapped before the per-project MCP feature and you want to add a `.mcp.json`, run the menu manually with `~/.claude/skills/<generatedFrom>/scripts/gen-mcp-json.ps1` (not part of the upgrade flow).
