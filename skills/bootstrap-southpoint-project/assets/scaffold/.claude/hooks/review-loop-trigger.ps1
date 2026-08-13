# PostToolUse hook (Bash matcher). If the executed command was gh pr create, git push or
# git commit on a branch that is NOT the base, injects into Claude the order to run /review-loop
# over the slice diff. Dedupes by SHA in .git/review-loop-state.json so the same commit never
# fires twice. Any non-applicable path ends in a silent exit 0.
$ErrorActionPreference = "SilentlyContinue"

# 1. Read the hook event from stdin
$raw = [Console]::In.ReadToEnd()
if (-not $raw) { exit 0 }
try { $evt = $raw | ConvertFrom-Json } catch { exit 0 }
$cmd = $evt.tool_input.command
if (-not $cmd) { exit 0 }

# 2. Filter: gh pr create / git push / git commit
$isPr     = $cmd -match '\bgh\s+pr\s+create\b'
$isPush   = $cmd -match '\bgit\s+push\b'
$isCommit = $cmd -match '\bgit\s+commit(?![\w-])'   # excludes git commit-graph and the like
if (-not ($isPr -or $isPush -or $isCommit)) { exit 0 }

# 3. Locate the repo (event cwd)
$cwd = if ($evt.cwd) { $evt.cwd } else { (Get-Location).Path }
Set-Location -LiteralPath $cwd
$gitDir = (git rev-parse --git-dir 2>$null)
if (-not $gitDir) { exit 0 }                 # not a git repo
if (-not [System.IO.Path]::IsPathRooted($gitDir)) { $gitDir = Join-Path $cwd $gitDir }
$branch = (git rev-parse --abbrev-ref HEAD 2>$null)
if (-not $branch -or $branch -eq "HEAD") { exit 0 }

# 4. Resolve the base branch (do NOT hardcode main)
$base = $null
if ($isPr -and $cmd -match '--base[ =]+([^\s''"]+)') { $base = $matches[1] }
if (-not $base) {
    $head = (git symbolic-ref --short refs/remotes/origin/HEAD 2>$null)
    if ($head) {
        # Strip `origin/` only if the local branch actually exists. A single-branch clone has
        # `origin/main` and no local `main`, and the stripped name would make the fallback range
        # this hook suggests (`git diff <base>...HEAD`) fail.
        $short = ($head -replace '^origin/', '')
        git rev-parse --verify --quiet "$short^{commit}" 2>$null | Out-Null
        $base = if ($LASTEXITCODE -eq 0) { $short } else { ([string]$head).Trim() }
    }
}
if (-not $base) {
    $def = (gh repo view --json defaultBranchRef -q .defaultBranchRef.name 2>$null)
    if ($def) { $base = $def.Trim() }
}
if (-not $base) {
    foreach ($cand in @("main", "master", "develop")) {
        git rev-parse --verify --quiet "$cand" 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) { $base = $cand; break }
    }
}
if (-not $base) { exit 0 }

# 5. Never review the base against itself (the base may be a remote-tracking ref)
if (($branch -eq $base) -or ($base -eq "origin/$branch")) { exit 0 }

# 6. Dedupe by the branch HEAD SHA
$sha = (git rev-parse HEAD 2>$null)
if (-not $sha) { exit 0 }
$statePath = Join-Path $gitDir "review-loop-state.json"
$state = @{}
if (Test-Path $statePath) {
    try {
        (Get-Content $statePath -Raw | ConvertFrom-Json).PSObject.Properties |
            ForEach-Object { $state[$_.Name] = $_.Value }
    } catch { $state = @{} }
}
if ($state[$branch] -eq $sha) { exit 0 }     # already fired for this commit
$state[$branch] = $sha
([pscustomobject]$state) | ConvertTo-Json | Set-Content -LiteralPath $statePath -Encoding UTF8

# 7. Inject the instruction to Claude
$msg = "You just closed a commit/slice on branch '$branch' (base '$base'). " +
       "Run /review-loop NOW over the slice diff. Do not ask whether to run it: run it. " +
       "The range comes from the marker ('.claude/scripts/review-marker.ps1 -Action range'), not from the whole branch: " +
       "only if that script is missing, use 'git diff $base...HEAD'. " +
       "Do not mark the work complete until the loop closes (zero medium/high-severity findings, or the 5-turn cap)."
@{ hookSpecificOutput = @{ hookEventName = "PostToolUse"; additionalContext = $msg } } |
    ConvertTo-Json -Depth 4 -Compress
exit 0
