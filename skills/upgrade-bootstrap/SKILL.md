---
name: upgrade-bootstrap
description: Use to update a project that was already bootstrapped with bootstrap-personal-project or bootstrap-southpoint-project when the scaffold has since changed (new files, edited rules, new skills like review-loop). Detects what is missing, outdated, or customized using the project's .bootstrap-manifest.json (with a fallback for legacy projects without one), and applies the delta with your approval — never overwriting your customizations. Trigger whenever the user wants to "actualizar el bootstrap", "traer los cambios nuevos del scaffold", "sync the workflow scaffolding", or mentions a bootstrapped project being on an older version. Run this inside the already-bootstrapped project, not in the bootstrap-skills repo. Do NOT use to bootstrap a brand-new project (use bootstrap-personal-project / bootstrap-southpoint-project), to run the review loop on a PR (use review-loop), or to update npm/package dependencies.
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
- If there is no manifest (legacy project), determine the variant: if `CLAUDE.md` mentions DOMO it's `bootstrap-southpoint-project`, otherwise `bootstrap-personal-project`. If genuinely ambiguous, ask the user.

### 2. Run the comparison

```powershell
pwsh -File <this-skill>/scripts/compare-scaffold.ps1 -ProjectDir "<project>" -CanonicalScaffold "<canonical scaffold>"
```

This prints JSON with `missing`, `outdated`, `customized`, `orphan`, `uptodate`, `hasProjectManifest`, `canonicalVersion`, `variant`.

### 3. Report

Summarize the JSON grouped by category, with counts. Be explicit about what each action will do. If `hasProjectManifest` is false, tell the user this is a legacy adoption run: customizations and old-but-untouched files can't be distinguished, so they appear under "different — your call".

### 4. Apply, with the user's approval

Get explicit approval before writing anything. Then:

- **missing** → copy from the canonical scaffold into the project (same relative path). Special case: the canonical key `.gitignore` is sourced from `gitignore.txt` in the scaffold. Special case `.claude/settings.json`: copy it only if absent; if the project already has its own, treat it as the `settings.json` merge below instead of a plain copy.
- **outdated** → overwrite the project file with the canonical version.
- **customized / different** → show the diff (canonical vs project). Offer, per file: skip (keep yours), or an assisted merge where you help integrate the new bits into the user's version. Never overwrite without per-file consent. **Special case `.claude/settings.json`:** do NOT diff-merge by hand — run `merge-settings.ps1` (below), which adds the `review-loop-trigger` hook idempotently without touching the rest of the user's config.
- **orphan** → list only; do not delete. Mention the user can remove them by hand.

When copying `.gitignore`, read from `<canonical scaffold>/gitignore.txt`.

**Merge of `.claude/settings.json`** (whenever it appears in `missing` with a pre-existing file, or in `customized`):

```powershell
pwsh -File <this-skill>/scripts/merge-settings.ps1 -ProjectSettings "<project>/.claude/settings.json" -CanonicalSettings "<canonical scaffold>/.claude/settings.json"
```

It is idempotent — running it twice never duplicates the hook. If the project had no `settings.json`, it copies the canonical one verbatim.

### 5. Re-seal the manifest

After applying, record the new baseline so the next run is precise:

```powershell
pwsh -File <this-skill>/scripts/reseal-manifest.ps1 -ProjectDir "<project>" -CanonicalScaffold "<canonical scaffold>"
```

For a legacy project this seeds `.bootstrap-manifest.json` for the first time — the project is now "adopted" into the versioning system.

### 6. Report what changed

List files copied, updated, left customized (skipped), and orphans flagged. Remind the user to review the diff and commit when satisfied. Do not commit on their behalf unless they ask.

## Guardrails

- Never overwrite a `customized` file without explicit per-file consent — that's the whole point.
- Don't delete orphans automatically.
- The scaffold's `.gitignore` lives as `gitignore.txt` in the source; map it when copying.
- If `compare-scaffold.ps1` errors (e.g. canonical scaffold has no manifest), stop and report — don't guess.
- `.mcp.json` no es parte del scaffold ni del manifest, así que `compare-scaffold.ps1` no lo ve y este upgrade nunca lo toca. Si el proyecto fue bootstrapeado antes de la feature de MCP-por-área y querés agregarle un `.mcp.json`, corré el menú a mano con `~/.claude/skills/<generatedFrom>/scripts/gen-mcp-json.ps1` (no es parte del flujo de upgrade).
