---
name: git-guardrails-claude-code
description: Set up Claude Code hooks to block dangerous git commands (push, reset --hard, clean, branch -D, etc.) before they execute. Use when user wants to prevent destructive git operations, add git safety hooks, or block git push/reset in Claude Code, or says "bloqueá los comandos peligrosos de git", "que el agente no pueda pushear", "poné un guardrail de git", or "protegé el repo de un reset --hard".
---

# Setup Git Guardrails

Sets up a PreToolUse hook that intercepts and blocks dangerous git commands before Claude executes them.

## What Gets Blocked

- `git push` (all variants including `--force`)
- `git reset --hard`
- `git clean -f` / `git clean -fd`
- `git branch -D`
- `git checkout .` / `git restore .`

When blocked, Claude sees a message telling it that it does not have authority to access these commands.

## What it does not cover

The hook is registered with `"matcher": "Bash"`, so it only sees commands sent through Claude Code's Bash tool. On Windows, Claude Code also has a PowerShell tool, and a matcher of `Bash` does not match it: a `git push` sent through PowerShell never reaches this hook. This skill ships no PowerShell version of the hook. When you install it where the agent has the PowerShell tool, tell the user the guardrail does not cover that tool.

The hook needs `jq` on the PATH of the shell that runs Claude Code's hooks, and Git for Windows does not ship it. Without it the script prints `jq: command not found` and exits 0: it lets every command through. Before installing, run `command -v jq`; if it finds nothing, tell the user the hook will not block anything until `jq` is installed. If the check in step 5 does not exit with code 2, stop and tell the user the guardrail is not working.

The patterns are matched as substrings of the whole command line, so:

- A global option between `git` and the subcommand slips past most of them: with `-C <path>` or `-c <key>=<value>` in between, `push`, `branch -D`, `clean -f`, `checkout .` and `restore .` get through. Only `push --force` and `reset --hard` are still blocked, because those patterns also match without the `git ` prefix.
- It blocks harmless commands that merely contain a pattern, such as a commit message that mentions `git push`, or `git checkout .gitignore`.

## Steps

### 1. Ask scope

Ask the user: install for **this project only** (`.claude/settings.json`) or **all projects** (`~/.claude/settings.json`)?

### 2. Copy the hook script

The bundled script is at: [scripts/block-dangerous-git.sh](scripts/block-dangerous-git.sh)

Copy it to the target location based on scope:

- **Project**: `.claude/hooks/block-dangerous-git.sh`
- **Global**: `~/.claude/hooks/block-dangerous-git.sh`

Make it executable with `chmod +x`.

### 3. Add hook to settings

Add to the appropriate settings file:

**Project** (`.claude/settings.json`):

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/block-dangerous-git.sh"
          }
        ]
      }
    ]
  }
}
```

**Global** (`~/.claude/settings.json`):

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/hooks/block-dangerous-git.sh"
          }
        ]
      }
    ]
  }
}
```

If the settings file already exists, merge the hook into the existing `hooks.PreToolUse` array. Don't overwrite other settings.

### 4. Ask about customization

Ask if user wants to add or remove any patterns from the blocked list. Edit the copied script accordingly.

### 5. Verify

Run a quick test:

```bash
echo '{"tool_input":{"command":"git push origin main"}}' | <path-to-script>
```

Should exit with code 2 and print a BLOCKED message to stderr.
