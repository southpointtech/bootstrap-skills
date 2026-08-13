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

# 6. A commit fires only when the slice close is DECLARED with a `Slice-Close:` trailer.
# The trailer is read from the commit that was just created, not parsed out of the command line,
# so it works the same for `-m`, `-F file`, a heredoc or `--amend`.
if ($isCommit) {
    # The event carries the SESSION cwd, not the directory the command ran in: a `git commit`
    # inside another repo would otherwise be attributed to this one. If this repo's HEAD is not
    # fresh, the commit happened somewhere else.
    $ct = (git log -1 --format=%ct 2>$null)
    if (-not $ct) { exit 0 }
    if (([DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - [int64]$ct) -gt 120) { exit 0 }

    $body = ((git log -1 --format=%B 2>$null) -join "`n")
    if ($body -notmatch '(?m)^\s*Slice-Close:') {
        # Safety net: forgetting the trailer must not leave a huge slice unreviewed. If the
        # UNREVIEWED delta is already over the ~400-line guide of CLAUDE.md, fire anyway.
        $range = $null
        $root = (git rev-parse --show-toplevel 2>$null)
        if ($root) {
            $marker = Join-Path $root ".claude/scripts/review-marker.ps1"
            if (Test-Path -LiteralPath $marker) {
                $r = (& pwsh -NoProfile -File $marker -Action range -RepoDir $root 2>$null)
                if ($LASTEXITCODE -eq 0 -and $r) { $range = ([string]$r).Trim() }
            }
        }
        # No marker (older scaffold) or no marker range yet: fall back to the branch range.
        if (-not $range) { $range = "$base...HEAD" }
        $lines = 0
        foreach ($row in (git diff --numstat $range 2>$null)) {
            $cols = ($row -split "`t")
            if ($cols.Count -ge 2) {
                foreach ($n in $cols[0..1]) { if ($n -match '^\d+$') { $lines += [int]$n } }
            }
        }
        if ($lines -le 400) { exit 0 }
    }
}

# 7. Dedupe by the branch HEAD SHA
$sha = (git rev-parse HEAD 2>$null)
if (-not $sha) { exit 0 }
$statePath = Join-Path $gitDir "review-loop-state.json"
$state = @{}
# Same file the review marker writes. Read and write it as UTF-8 explicitly: Get-Content /
# Set-Content use the ANSI code page under Windows PowerShell 5.1, which turns the marker's
# accented untracked fingerprint into mojibake and leaves that branch unable to ever close.
if (Test-Path $statePath) {
    try {
        ([IO.File]::ReadAllText($statePath) | ConvertFrom-Json).PSObject.Properties |
            ForEach-Object { $state[$_.Name] = $_.Value }
    } catch { $state = @{} }
}
if ($state[$branch] -eq $sha) { exit 0 }     # already fired for this commit
$state[$branch] = $sha
$json = ([pscustomobject]$state) | ConvertTo-Json -Depth 6
[IO.File]::WriteAllText($statePath, $json, (New-Object Text.UTF8Encoding($false)))

# 8. Inject the instruction to Claude
$msg = "You just closed a commit/slice on branch '$branch' (base '$base'). " +
       "Run /review-loop NOW over the slice diff. Do not ask whether to run it: run it. " +
       "The range comes from the marker ('.claude/scripts/review-marker.ps1 -Action range'), not from the whole branch: " +
       "only if that script is missing, use 'git diff $base...HEAD'. " +
       "Do not mark the work complete until the loop closes (zero medium/high-severity findings, or the 5-turn cap)."
@{ hookSpecificOutput = @{ hookEventName = "PostToolUse"; additionalContext = $msg } } |
    ConvertTo-Json -Depth 4 -Compress
exit 0
