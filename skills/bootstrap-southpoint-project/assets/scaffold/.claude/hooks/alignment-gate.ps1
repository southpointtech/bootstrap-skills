# PreToolUse hook (Edit|Write|MultiEdit matcher). Stops the FIRST code Edit/Write of the session
# and offers the user to align (grill) before coding. Speed bump: once per session
# (dedup by session_id in .git/alignment-gate-state.json). NON-code files (docs, *.md,
# .scratch, .agents, .claude, configs, CONTEXT.md, CLAUDE.md, .gitignore) ALWAYS pass through,
# so aligning/documenting never gets blocked. Any non-applicable path ends in a silent exit 0.
$ErrorActionPreference = "SilentlyContinue"

# 1. Read the hook event from stdin
$raw = [Console]::In.ReadToEnd()
if (-not $raw) { exit 0 }
try { $evt = $raw | ConvertFrom-Json } catch { exit 0 }

# 2. Collect the file_path(s) per tool (Edit/Write: tool_input.file_path; MultiEdit: edits[].file_path)
$paths = @()
if ($evt.tool_input.file_path) { $paths += [string]$evt.tool_input.file_path }
foreach ($e in @($evt.tool_input.edits)) { if ($e.file_path) { $paths += [string]$e.file_path } }
if ($paths.Count -eq 0) { exit 0 }

$cwd = if ($evt.cwd) { $evt.cwd } else { (Get-Location).Path }

# 3. Classify each path: non-code (allowlist) vs code. Only stop if there is AT LEAST one code path.
function Is-NonCode($p, $cwd) {
    $rel = ($p -replace '\\', '/')
    if ($cwd) {
        $c = (($cwd -replace '\\', '/').TrimEnd('/'))
        if ($rel.ToLower().StartsWith(($c.ToLower() + '/'))) { $rel = $rel.Substring($c.Length + 1) }
    }
    if ($rel.StartsWith('./')) { $rel = $rel.Substring(2) }
    $leaf = Split-Path $rel -Leaf
    if ($leaf -match '\.(md|json|ya?ml|toml)$') { return $true }
    if (@('CONTEXT.md','CLAUDE.md','.gitignore') -contains $leaf) { return $true }
    foreach ($d in @('docs/', '.scratch/', '.agents/', '.claude/')) {
        if ($rel.ToLower().StartsWith($d)) { return $true }
    }
    return $false
}
$hasCode = $false
foreach ($p in $paths) { if (-not (Is-NonCode $p $cwd)) { $hasCode = $true; break } }
if (-not $hasCode) { exit 0 }   # all non-code: passes through without marking the session

# 4. Dedup by session_id (once per session). State lives next to review-loop-state.json.
$sid = if ($evt.session_id) { [string]$evt.session_id } else { "unknown" }
Set-Location -LiteralPath $cwd
$gitDir = (git rev-parse --git-dir 2>$null)
if ($gitDir -and -not [System.IO.Path]::IsPathRooted($gitDir)) { $gitDir = Join-Path $cwd $gitDir }
$stateDir = if ($gitDir) { $gitDir } else { $env:TEMP }
$statePath = Join-Path $stateDir "alignment-gate-state.json"
$state = @{}
if (Test-Path $statePath) {
    try {
        (Get-Content $statePath -Raw | ConvertFrom-Json).PSObject.Properties |
            ForEach-Object { $state[$_.Name] = $_.Value }
    } catch { $state = @{} }
}
if ($state[$sid]) { exit 0 }     # already warned this session
$state[$sid] = $true
([pscustomobject]$state) | ConvertTo-Json | Set-Content -LiteralPath $statePath -Encoding UTF8

# 5. Stop this Edit and OFFER to align (the hook does NOT run the grill; the user decides)
$msg = "Before writing code in this task: no alignment/grill has happened yet in this session " +
       "(step 1 of the workflow: Alignment/Grill -> PRD -> task planning; see CLAUDE.md). Do not keep coding on " +
       "autopilot. Offer the user: do we run /grill-me or /grill-with-docs first, or do we proceed " +
       "because this is trivial / already aligned? Wait for their decision: do NOT run the grill on your own. " +
       "If the user says continue, retry the Edit and proceed (this warning will not repeat this session)."
@{ hookSpecificOutput = @{ hookEventName = "PreToolUse"; permissionDecision = "deny"; permissionDecisionReason = $msg } } |
    ConvertTo-Json -Depth 4 -Compress
exit 0
