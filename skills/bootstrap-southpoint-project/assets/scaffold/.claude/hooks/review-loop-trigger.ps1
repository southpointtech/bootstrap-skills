# PostToolUse hook (Bash matcher). Injects into Claude the order to run /review-loop over the
# unreviewed delta when a slice closes on a branch that is NOT the base. It fires on `gh pr create`,
# on `git push`, and on a `git commit` that DECLARES the close with a `Slice-Close:` trailer — a
# commit without the trailer fires only as a safety net, once the unreviewed delta passes the
# ~400-line guide. Ahead of all of that, step 5c drops any slice that is entirely documentation, on
# every trigger including `git push`. Commits are also checked for freshness, because the event
# carries the session's cwd and a commit made in another repo would otherwise be attributed to it.
# Shares .git/review-loop-state.json with the review marker: dedupes by SHA there and never
# destroys the marker's own keys. Any non-applicable path ends in a silent exit 0.
#
# What this hook deliberately does NOT do: work out which repo the command ran in by parsing the
# bash command line. That block existed to avoid firing when a `git push` was run elsewhere from a
# session opened here, and over three review turns it produced eight high-severity bugs of its own —
# every one of them a FALSE NEGATIVE that dropped a declared slice close in silence. The signals
# kept are observable rather than parsed: HEAD freshness (`git log -1 --format=%ct`) for commits and
# the SHA dedupe for everything. The accepted cost is one extra review-loop when a push really was
# run in another repo, which is the safe direction.
$ErrorActionPreference = "SilentlyContinue"

# git writes UTF-8 and PowerShell decodes child output with Console::OutputEncoding. A hook runs as
# a child process with stdout redirected, so it does not inherit a UTF-8 console: every git call
# whose output can carry a path needs this, not just the `ls-files` of the guide. `rev-parse
# --show-toplevel` under a non-ASCII path came back mangled and the marker could no longer be found.
try { [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false) } catch { }
# The event JSON arrives on STDIN, decoded with Console::InputEncoding — and a hook spawned with an
# OEM console (the Windows default) does NOT inherit UTF-8 on input either. Without this, an event
# whose `cwd` holds a non-ASCII path (`C:\Users\Martín\…`) came back mojibake, `Set-Location` below
# failed silently, and the hook ran against the AMBIENT repo and fired — mislocating the whole thing.
# Set before the first read of [Console]::In so the reader is (re)built with UTF-8.
try { [Console]::InputEncoding = [Text.UTF8Encoding]::new($false) } catch { }

# 1. Read the hook event from stdin
$raw = [Console]::In.ReadToEnd()
if (-not $raw) { exit 0 }
try { $evt = $raw | ConvertFrom-Json } catch { exit 0 }
$cmd = $evt.tool_input.command
if (-not $cmd) { exit 0 }

# 2. Filter: gh pr create / git push / git commit
# Every decision below reads a NORMALISED command, never the raw one: the raw command contains the
# text of `-m`, so a commit whose message merely mentions `git push` used to light up $isPush and
# skip the entire trailer gate of step 6 — no gate, no freshness window, no guide.
#
# Neutralising quoted text with a plain `-replace "\"[^\"]*\""` is not enough, and both ways it
# fails were reproduced: `-m "... \"git push\" ..."` ends the match at the escaped quote and leaves
# the text exposed (fires when it must not), and an apostrophe inside double quotes
# (`-m "don't" && git push`) makes the single-quote pattern span from one apostrophe to the next
# and swallow the real push in between (does not fire when it must). So the literals are walked:
# bash escapes with `\` inside double quotes and not at all inside single quotes.
#
# The result keeps the ORIGINAL LENGTH — the body is replaced char-for-char with U+0001 — so an
# index into $scan is also an index into $cmd, which is how step 4 reads the real value of `--base`
# back out of a literal this function deliberately cannot see through.
function Hide-Literals([string]$s) {
    $out = [char[]]$s
    $i = 0
    while ($i -lt $s.Length) {
        $q = $s[$i]
        # OUTSIDE a literal a backslash escapes the next character, and skipping that rule is not
        # cosmetic: `'\''` is how bash writes an apostrophe (close, escaped quote, reopen). Read as
        # an opening quote, the loose quote pairs with the NEXT one, the remainder of the message is
        # left exposed, and a `-m "... git push ..."` lights up $isPush and skips the whole trailer
        # gate. Verified with `git commit -m 'fix: it'\''s ready to git push now'`.
        if ($q -eq '\') { $i += 2; continue }
        if ($q -ne "'" -and $q -ne '"') { $i++; continue }
        $j = $i + 1
        while ($j -lt $s.Length) {
            if ($q -eq '"' -and $s[$j] -eq '\' -and $j + 1 -lt $s.Length) { $j += 2; continue }
            if ($s[$j] -eq $q) { break }
            $j++
        }
        # Two different endings, kept apart on purpose: a closed literal ends AT the closing quote,
        # an unterminated one swallows the rest of the line — the safe reading of a broken command.
        # Collapsing them into one `Min($j, length - 1)` left the very last character unmasked,
        # which is not what the comment claimed.
        $end = if ($j -lt $s.Length) { $j } else { $s.Length }
        for ($k = $i + 1; $k -lt $end; $k++) { $out[$k] = [char]1 }
        $i = $end + 1
    }
    return (-join $out)
}
$scan = Hide-Literals $cmd
# `git -C <path> push` matched none of the patterns, so a legitimate push never closed the loop.
# Git's global options are folded away so the subcommand sits right after `git`. This copy of the
# command is only used for the flags: the fold changes offsets, so step 4 works off $scan.
$folded   = $scan -replace '(?i)\bgit\s+(?:(?:-C|-c|--git-dir|--work-tree)(?:\s+|=)\S+\s+|--no-pager\s+|--paginate\s+)+', 'git '
$isPr     = $folded -match '\bgh\s+pr\s+create\b'
$isPush   = $folded -match '\bgit\s+push\b'
$isCommit = $folded -match '\bgit\s+commit(?![\w-])'   # excludes git commit-graph and the like
# Command substitution `$(...)` and backticks restart bash's quoting context inside, which
# Hide-Literals does not model: a double quote inside single quotes inside `$(...)` leaves the total
# count of double quotes ODD, the literal walker desyncs and swallows the rest of the line, DROPPING
# real triggers — `git commit -m "$(sed 's/"/x/' f)" && git push` came out with $isPush FALSE, the
# push lost. Rather than model `$()` (the bash-parsing pit that produced eight highs), when the
# command contains `$(` or a backtick, compute the flags over the RAW command too and OR them in.
# The cost is a wider false-POSITIVE surface: a commit whose MESSAGE text mentions "git push" /
# "gh pr create" inside a `$(...)` now raises $isPush/$isPr from that text, and since step 6's gate is
# `-not ($isPush -or $isPr)`, such a commit skips the trailer gate, the freshness window AND the
# ceiling, firing with only step 5c's docs gate left in its way (and still SHA-deduped to one
# fire). That is not free — it defeats the
# freshness guard that stops another repo's stale commit from being attributed here — but the worst
# outcome is one spurious /review-loop, which asks the marker for THIS repo's range and closes on
# empty: the "review too much" direction the project already declared safe, never a dropped close.
# Natural uses (`date +"%F"`, `basename "$PWD"`) keep an even quote count, re-align on their own and
# do not reach this branch. The accepted false positive is pinned by a fixture so it cannot regress
# into a silent behavior change.
if ($cmd.Contains('$(') -or $cmd.Contains('`')) {
    $rawFolded = $cmd -replace '(?i)\bgit\s+(?:(?:-C|-c|--git-dir|--work-tree)(?:\s+|=)\S+\s+|--no-pager\s+|--paginate\s+)+', 'git '
    $isPr     = $isPr     -or ($rawFolded -match '\bgh\s+pr\s+create\b')
    $isPush   = $isPush   -or ($rawFolded -match '\bgit\s+push\b')
    $isCommit = $isCommit -or ($rawFolded -match '\bgit\s+commit(?![\w-])')
}
if (-not ($isPr -or $isPush -or $isCommit)) { exit 0 }

# 3. Locate the repo (event cwd)
# If the event carries a cwd that does not resolve on disk, exit rather than fall through: with
# $ErrorActionPreference = SilentlyContinue a failed Set-Location is silent, and the hook would keep
# running against whatever directory it was spawned in — the AMBIENT repo — and inject a false slice
# close there. The encoding force above is the primary fix for a non-ASCII cwd; this is the net that
# keeps ANY unresolvable cwd (mojibake, a stale path, a deleted dir) from firing on the wrong repo.
$cwd = if ($evt.cwd) { $evt.cwd } else { (Get-Location).Path }
if (-not (Test-Path -LiteralPath $cwd)) { exit 0 }
Set-Location -LiteralPath $cwd
$gitDir = (git rev-parse --git-dir 2>$null)
if (-not $gitDir) { exit 0 }                 # not a git repo
if (-not [System.IO.Path]::IsPathRooted($gitDir)) { $gitDir = Join-Path $cwd $gitDir }
$branch = (git rev-parse --abbrev-ref HEAD 2>$null)
if (-not $branch -or $branch -eq "HEAD") { exit 0 }

# 3a. Load the shared state. Read before step 6 because the guide needs the marker's untracked
# fingerprint, and again at step 7 for the SHA dedupe — reading it once keeps the two in sync.
# Same file the review marker writes. Read and write it as UTF-8 explicitly: Get-Content /
# Set-Content use the ANSI code page under Windows PowerShell 5.1, which turns the marker's
# accented untracked fingerprint into mojibake and leaves that branch unable to ever close.
# -LiteralPath: without it a repo under a path containing brackets reads as "no state file" on
# EVERY run, so the dedupe silently stops existing and the state gets overwritten each time.
$statePath = Join-Path $gitDir "review-loop-state.json"
$state = @{}
$stateWritable = $true
if (Test-Path -LiteralPath $statePath) {
    try {
        ([IO.File]::ReadAllText($statePath) | ConvertFrom-Json).PSObject.Properties |
            ForEach-Object { $state[$_.Name] = $_.Value }
    } catch {
        # Unparseable state: the marker's `marker:*` / `untracked:*` keys live in this same file,
        # and rewriting it with just the dedupe key would wipe them for every branch with no trace.
        # Move it aside so it stays recoverable, and start clean.
        $state = @{}
        # If the quarantine itself fails — the likeliest cause being the marker holding the file
        # mid-rewrite, since that write is not atomic — the file must be left ALONE: writing over it
        # at step 7 destroys exactly what the quarantine exists to preserve. Skipping the write is
        # the whole remedy; skipping the TRIGGER as an earlier version did (`catch { exit 0 }`)
        # traded a recoverable file for a silently dropped slice close, which is the dangerous
        # direction. Losing the dedupe only means the next commit may fire twice.
        # -ErrorAction Stop is what makes this reachable at all: with $ErrorActionPreference set to
        # SilentlyContinue, Move-Item's failure is non-terminating and the catch never ran.
        try { Move-Item -LiteralPath $statePath -Destination "$statePath.bad" -Force -ErrorAction Stop }
        catch { $stateWritable = $false }
    }
}

# 4. Resolve the base branch (do NOT hardcode main)
# The FLAG is located on $scan and its value read out of $cmd at the same index — the one place a
# real value has to be recovered from behind the mask. Matching the raw command instead broke both
# ways: a quoted `--base "develop"` did not match at all (the character class stops at the quote) and
# fell through to the fallback, and a `--base` merely mentioned inside `--title` won by being the
# first match, so the injected message pointed at a range against a branch that does not exist.
$base = $null
if ($isPr) {
    $bm = [regex]::Match($scan, '--base(?:\s+|=)')
    if ($bm.Success) {
        $tail = $cmd.Substring($bm.Index + $bm.Length)
        if ($tail -match '^(?:''([^'']*)''|"([^"]*)"|([^\s;&|]+))') {
            foreach ($g in 1, 2, 3) { if (-not $base -and $matches[$g]) { $base = $matches[$g] } }
        }
    }
}
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
    foreach ($cand in @("main", "master", "develop")) {
        git rev-parse --verify --quiet "$cand" 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) { $base = $cand; break }
    }
}
# Non-standard base names (`trunk`, `dev`, `release`): delegate to the marker, whose resolver
# already handles them (for-each-ref + merge-base --octopus). This closes the ASYMMETRY that made
# this the mute half of the engine — the old code `exit 0`ed here, BEFORE the trailer gate below, so
# a repo whose base is not main/master/develop silently dropped a DECLARED slice close, exactly the
# false negative this hook exists to eliminate, hidden on GitHub where `gh repo view` used to rescue
# it. That `gh repo view` is also gone: it was a network call on every commit when origin/HEAD is
# unset (the `git init` + `remote add` case), and it ran BEFORE the local fallback that resolves for
# free. A clone's default branch is already covered by origin/HEAD above; a non-clone falls to the
# named branches and then here. The marker emits a commit (the merge-base), used only as a diff
# endpoint and in the message, never as a branch-name guard. Absent marker (not a bootstrapped repo,
# so there is no /review-loop to run anyway) leaves $base null and the hook stays silent.
if (-not $base) {
    $root = (git rev-parse --show-toplevel 2>$null)
    if ($root) {
        $mk = Join-Path $root ".claude/scripts/review-marker.ps1"
        if (Test-Path -LiteralPath $mk) {
            # Sentinel: if `pwsh` is off the PATH the swallowed error would leave $LASTEXITCODE at
            # the 0 of the git call above, which would read as a successful exit 0 from the marker.
            $global:LASTEXITCODE = 99
            $rb = (& pwsh -NoProfile -File $mk -Action base -RepoDir $root 2>$null)
            if (($LASTEXITCODE -eq 0) -and $rb) { $base = ([string]$rb).Trim() }
        }
    }
}
if (-not $base) { exit 0 }

# 5. Never review the base against itself (the base may be a remote-tracking ref)
if (($branch -eq $base) -or ($base -eq "origin/$branch")) { exit 0 }

# 5b. Resolve the unreviewed range ONCE, for both the docs gate below and the safety net of step 6.
# It used to be resolved inside step 6, where only a trailer-less commit ever reached it. The docs
# gate needs the same range on EVERY trigger, and resolving it twice would let the two halves
# disagree about what the slice even is.
$range = $null
$rangeKnown = $false
$root = (git rev-parse --show-toplevel 2>$null)
if ($root) {
    $marker = Join-Path $root ".claude/scripts/review-marker.ps1"
    if (Test-Path -LiteralPath $marker) {
        # Sentinel: with `pwsh` missing from PATH the error is swallowed and $LASTEXITCODE
        # would still hold the 0 of the git call above, reading as a successful exit 0.
        $global:LASTEXITCODE = 99
        $r = (& pwsh -NoProfile -File $marker -Action range -RepoDir $root 2>$null)
        if ($LASTEXITCODE -eq 0) {
            $rangeKnown = $true
            if ($r) { $range = ([string]$r).Trim() }
        }
    }
}

# TWO lists, because the two callers below ask different questions of them, and answering both with
# one list is a bug: it silences review of a lockfile bump that happens to ship next to a README.
#
# `$skipPat` — what CLAUDE.md excludes from LINES OF LOGIC. The file still exists and still deserves
# review; it just contributes 0 to the ~400-line guide of step 6.
# Plain `*` and not `**`: pathspec wildcards already cross `/`, while `**/name` fails to match that
# name at the repo root — verified, the manifest kept being counted.
$skipPat = @('*.bootstrap-manifest.json', 'docs/vendor/*', '*.lock', '*lock.json',
             '*lock.yaml', '*.lockb', 'go.sum', '*.snap')
# `$genPat` — what nobody AUTHORED, so it cannot be what makes a slice worth reviewing. Only the
# gate uses it, and it is deliberately a strict subset: a generated manifest re-sealed alongside a
# docs edit should not keep firing the loop, but a lockfile is exactly where CLAUDE.md's
# supply-chain rule gets checked, and vendored source is what a critical library was pinned to.
# Feeding the gate the whole `$skipPat` made the decision non-monotonic — `package-lock.json` alone
# fired, the same lockfile plus a README went silent — so adding prose switched review off. What
# monotonicity is owed to is AUTHORED work: a re-sealed manifest alone still fires and goes quiet
# next to a README, and that is fine, because there is nothing authored in it to read.
# One consequence worth naming: a `.md` under `docs/vendor/` is prose to this gate, so a slice made
# only of vendored documentation is not reviewed.
$genPat = @('*.bootstrap-manifest.json', '*.snap')

# The untracked files that are NEW since the last review. Filtering is left to the callers, because
# they filter by DIFFERENT lists (`$genPat` vs `$skipPat`) — folding either one in here would answer
# both questions with one answer, which is the bug the two lists exist to avoid. `git diff` never
# shows untracked files, and step 5 of the loop ORDERS writing a new test, which stays untracked
# until someone commits it — so both callers below need them.
# What counts is untracked SINCE THE MARKER: the marker records its own `path|sha256` fingerprint in
# `untracked:<branch>` for exactly this reason. Counting them absolutely made one already-reviewed
# new file re-fire the net forever, and — until this discount was shared — a single stray untracked
# file left the docs gate permanently disabled in that repo.
# The fingerprint is keyed on the WHOLE `path|sha256` entry, exactly as the marker's own
# Test-NewUntracked compares it. Keying on the path alone meant a file fingerprinted at one line and
# since grown to 600 was skipped forever. And it only means anything while its marker lives: once
# `git gc` prunes the marker object the range widens back to the slice base, so discounting against
# a dead fingerprint would under-count exactly when the range just grew.
# Hashing is the expensive half, so it runs at most ONCE per event: the successful result is cached.
# (A failure is not cached — it returns before any hashing, so re-running it costs another `git
# ls-files` and nothing more.)
# Returns $null when git could not be asked at all; both callers read that as "cannot tell" and fail
# open. `,$out` on the way out because PowerShell collapses a bare empty array to $null, which would
# make "nothing new" indistinguishable from that failure.
$script:untrackedNewCache = $null
function Get-UntrackedNew {
    if ($null -ne $script:untrackedNewCache) { return ,$script:untrackedNewCache }
    if (-not $root) { return $null }
    $seen = @{}
    $markerSha = [string]$state["marker:$branch"]
    if ($markerSha) {
        git -C $root cat-file -e "$markerSha^{commit}" 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) {
            foreach ($e in @($state["untracked:$branch"])) { if ($e) { $seen[[string]$e] = $true } }
        }
    }
    # core.quotepath off so git does not C-quote a non-ASCII name ("\303\261andu.txt"), which would
    # fail Test-Path and be dropped. The decoding half is handled once at the top of this file.
    $others = @(git -C $root -c core.quotepath=false ls-files --others --exclude-standard 2>$null)
    if ($LASTEXITCODE -ne 0) { return $null }
    $out = @()
    foreach ($f in @($others | Where-Object { $_ })) {
        $p = Join-Path $root $f
        if (-not (Test-Path -LiteralPath $p)) { continue }
        # With no fingerprint recorded there is nothing to compare against, so the hash would be
        # computed only to be thrown away. Skipping it keeps the common path — no marker yet, or a
        # marker cut with a clean tree — free of reading every untracked file end to end.
        if ($seen.Count -eq 0) { $out += $f; continue }
        # Hashed the same way the marker does, so the entries compare byte for byte.
        $h = ""
        try { $h = (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash } catch { }
        if ($seen[("{0}|{1}" -f $f, $h)]) { continue }
        $out += $f
    }
    $script:untrackedNewCache = $out
    return ,$out
}

# 5c. A slice that is ENTIRELY documentation does not earn a review turn. This block is shaped by
# two bugs found the hard way in a project that ran an earlier version of it, and BOTH were false
# NEGATIVES — the gate silently switching reviews off, which is the only way it can hurt.
#
# DOC = ends in `.md` AND NOTHING ELSE. The first version treated all of `docs/` as documentation.
# In a repo that keeps non-`.md` files under it — frozen design assets, portal sources, anything its
# CLAUDE.md declares the frontend's source of truth — a frontend-only slice then came out with no
# review at all and no symptom to notice it by.
#
# These do NOT count as docs even when they are `.md`, because they govern the agent: `.claude/**`
# and `.agents/**` (hooks, commands and the SKILL.md files — the tdd skill is where the
# `Slice-Close:` trailer this very hook reads is defined), any `CLAUDE.md` (the hard rules), and
# `docs/ai-workflow/**` + `docs/agents/**`, which CLAUDE.md declares required reading. Breaking a
# rule in there has the same effect as breaking code. The anchors are `(^|/)` and not `^`: Claude
# Code auto-loads the `CLAUDE.md` of the directory being worked in, so a bare `^` covered only the
# root one and let every nested one through.
#
# Decided over the same range the loop would review, never over the last commit alone: a slice that
# already carries code keeps firing even when the commit that just landed is docs-only. Untracked
# files are folded in for the same reason (see Get-UntrackedNew above), so a slice whose only code
# is a still-uncommitted new test is not mistaken for prose.
#
# Conservative on purpose: ONE non-doc file in the slice is enough to leave the gate open, and
# anything git cannot answer leaves it open too (fail-open). An open gate is not the same as firing:
# on a commit the trailer gate and the ~400-line net of step 6 still get their say, and on EVERY
# trigger the SHA dedupe of step 7 does — a second `git push` on the same commit stays silent with
# the gate wide open, which is the ordinary shape of pushing again after the loop closed.
# `core.quotepath=false` is required: git C-quotes non-ASCII paths and wraps them in literal quotes,
# and those quotes break the `$` anchor below, so a `.md` with an accent read as non-doc and every
# prose slice containing one fired anyway.
if ($root) {
    # Every alternative is anchored `(^|/)` and none of them `^`: a bootstrapped project can sit in
    # a subdirectory of a monorepo, or vendor a second scaffold under one, and a bare `^` covered
    # only the root copy while every nested one, governing the agent just as much, slipped through
    # as prose.
    $govern = '(^|/)\.claude/|(^|/)\.agents/|(^|/)CLAUDE\.md$|(^|/)docs/ai-workflow/|(^|/)docs/agents/'
    $docRange = if ($range) { $range } else { "$base...HEAD" }
    # `--no-renames` because with rename detection on, `--name-only` reports only the DESTINATION:
    # moving code to a `.md` name showed up as a single doc file and silenced the review of what was
    # removed. Off, the same move lists the old path too, and one non-doc entry is enough.
    $touched = @(git -C $root -c core.quotepath=false diff --name-only --no-renames $docRange -- . 2>$null)
    $touchedOk = ($LASTEXITCODE -eq 0)
    # Without a marker the range is `<base>...HEAD`, a range of COMMITS: the working tree is not in
    # it, so a TRACKED file modified and not yet committed appeared in neither half and a slice
    # whose only code was uncommitted got suppressed. With a marker there is nothing to add — its
    # ref is emitted bare precisely so that `git diff <ref>` already covers the tree.
    if ($touchedOk -and -not $range) {
        $touched += @(git -C $root -c core.quotepath=false diff --name-only --no-renames HEAD -- . 2>$null)
        $touchedOk = ($LASTEXITCODE -eq 0)
    }
    if ($touchedOk) {
        # `$genPat`, NOT `$skipPat`: see step 5b. Only what nobody authored disappears here.
        $touched = @($touched | Where-Object { $_ } |
                     Where-Object { $f = $_; -not (@($genPat | Where-Object { $f -like $_ }).Count) })
        $nonDoc = @($touched | Where-Object { $_ -notmatch '\.md$' -or $_ -match $govern })
        # The untracked half can cost a SHA256 per file (only when a fingerprint exists to compare
        # against), so it is only paid for once the tracked half has come back all prose: a single
        # non-doc file there already answers the question.
        if ($nonDoc.Count -eq 0) {
            $untracked = Get-UntrackedNew
            if ($null -ne $untracked) {
                $untracked = @($untracked | Where-Object { $f = $_; -not (@($genPat | Where-Object { $f -like $_ }).Count) })
                $all = @($touched) + @($untracked)
                $nonDoc = @($all | Where-Object { $_ -notmatch '\.md$' -or $_ -match $govern })
                # An empty slice is not a docs-only slice: with nothing in it there is nothing to
                # judge, so it falls through and fires instead of going quiet. A slice that adds and
                # removes the same code nets out empty here and must still be reviewed.
                if ($all.Count -gt 0 -and $nonDoc.Count -eq 0) { exit 0 }
            }
        }
    }
}

# 6. A commit fires only when the slice close is DECLARED with a `Slice-Close:` trailer.
# The trailer is read from the commit that was just created, not parsed out of the command line,
# so it works the same for `-m`, `-F file`, a heredoc or `--amend`.
# `git commit && git push` is ONE bash command and lights up both flags, so the trailer gate only
# governs a commit that is the sole trigger: the push skips the trailer gate, as it did before A2.
# Step 5c's docs gate can silence a push, but it is not the only thing left: step 7's per-commit
# dedupe runs on EVERY trigger and silences a second push of the same commit.
if ($isCommit -and -not ($isPush -or $isPr)) {
    # The event carries the SESSION cwd, not the directory the command ran in: a `git commit`
    # inside another repo would otherwise be attributed to this one. If this repo's HEAD is not
    # fresh, the commit happened somewhere else.
    #
    # The window is generous on purpose. This is PostToolUse: it runs when the WHOLE bash call
    # ends, so `git commit ... && npm test` seals the commit minutes before the event arrives, and
    # a narrow window would silently swallow a declared close — a false negative nobody sees. A
    # foreign repo's HEAD is hours or days old, so 30 min separates the two just as well, and the
    # SHA dedupe below stops the same commit from firing twice anyway. Abs() so that a clock skewed
    # into the future does not sail past the check.
    $ct = (git log -1 --format=%ct 2>$null)
    if (-not $ct) { exit 0 }
    if ([Math]::Abs([DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - [int64]$ct) -gt 1800) { exit 0 }

    $body = ((git log -1 --format=%B 2>$null) -join "`n")
    if ($body -notmatch '(?m)^\s*Slice-Close:') {
        # Safety net: forgetting the trailer must not leave a huge slice unreviewed. If the
        # UNREVIEWED delta is already over the ~400-line guide of CLAUDE.md, fire anyway.
        # `$range`, `$rangeKnown` and `$root` come from step 5b, which resolves them once for both
        # this net and the docs gate.
        # The marker's contract has three outcomes, and collapsing them is the bug it exists to
        # prevent. Exit 0 + empty means there is genuinely nothing unreviewed: nothing for the net
        # to catch, so do not fire — otherwise every commit right after the loop closes clean would
        # fire again over the whole branch, which is the waste this slice removes.
        if ($rangeKnown -and -not $range) { exit 0 }
        # No marker (older scaffold), exit 2 (undeterminable) or pwsh missing: fall back to the
        # branch range — firing too much is the safe direction.
        if (-not $range) { $range = "$base...HEAD" }
        # The guide counts lines of LOGIC: CLAUDE.md excludes generated files, vendored code,
        # lockfiles and snapshots by name. Counting them fires on slices that honour the rule.
        # `$skipPat` is defined in step 5b and belongs to THIS caller: the docs gate asks a
        # different question and filters by `$genPat`. Handing the gate this list is what made its
        # decision non-monotonic, so do not "unify" them back.
        $skip = $skipPat | ForEach-Object { ":(exclude)$_" }
        $lines = 0
        # `git -C $root` on both counts: pathspecs and `ls-files` resolve against the git process's
        # cwd, and the event carries the SESSION's cwd, which in a monorepo is a subdirectory. Left
        # unanchored, the guide measured that subtree alone and the safety net silently vanished.
        $rows = @(git -C $root diff --numstat $range -- . @skip 2>$null)
        # Whether the count is trustworthy at all. The fallback range `<base>...HEAD` fails outright
        # on unrelated histories (`fatal: no merge base`), and with the error swallowed that read as
        # "0 lines" — the guide silently disappearing on the exact path where the marker had already
        # said it could not determine the range.
        $measurable = ($LASTEXITCODE -eq 0)
        foreach ($row in $rows) {
            $cols = ($row -split "`t")
            if ($cols.Count -ge 2) {
                foreach ($n in $cols[0..1]) { if ($n -match '^\d+$') { $lines += [int]$n } }
            }
        }
        # The untracked half comes from Get-UntrackedNew (step 5b), which discounts the marker's
        # `untracked:<branch>` fingerprint; `$skipPat` is applied HERE, because this is the caller
        # that asks about lines of logic. Both halves of the guide — tracked and untracked — now
        # exclude the same names. The docs gate does NOT: it asks a different question and filters
        # by `$genPat`. $null means git could not be asked at all, which makes the whole count
        # untrustworthy: fail open, like a range that does not resolve.
        $untracked = Get-UntrackedNew
        if ($null -eq $untracked) { $measurable = $false; $untracked = @() }
        foreach ($f in $untracked) {
            if (@($skipPat | Where-Object { $f -like $_ }).Count) { continue }
            $p = Join-Path $root $f
            # Binary files are not lines of logic, and `git diff --numstat` already reports `-` for
            # them on the tracked side, so skipping them here keeps both halves consistent. It also
            # keeps a 12 MB screenshot from costing seconds on EVERY git commit (4.9 s when this
            # guard was written; nobody has re-measured that end-to-end cost since — the attempts
            # timed only the `Get-Content`, at 16-172 ms — so treat the number as unattributed and
            # the guard as cheap insurance).
            # The window is 8000 bytes because that is what git itself scans for a NUL; at 4096 a
            # file whose first NUL sits past that mark counted as text and inflated the guide, while
            # the comment above claimed the two halves agreed.
            $buf = New-Object byte[] 8000
            $fs = $null
            try {
                $fs = [IO.File]::OpenRead($p)
                $n  = $fs.Read($buf, 0, 8000)
            } catch { continue } finally { if ($fs) { $fs.Close() } }
            if ([Array]::IndexOf($buf, [byte]0, 0, $n) -ge 0) { continue }
            $lines += @(Get-Content -LiteralPath $p -TotalCount 401 2>$null).Count
        }
        if ($measurable -and $lines -le 400) { exit 0 }
    }
}

# 7. Dedupe by the branch HEAD SHA (state already loaded in step 3a)
$sha = (git rev-parse HEAD 2>$null)
if (-not $sha) { exit 0 }
if ($state[$branch] -eq $sha) { exit 0 }     # already fired for this commit
$state[$branch] = $sha
# Not written when the quarantine of an unreadable state failed: see step 3a. Firing without the
# dedupe entry is harmless; overwriting a file that could not be backed up is not.
if ($stateWritable) {
    $json = ([pscustomobject]$state) | ConvertTo-Json -Depth 6
    [IO.File]::WriteAllText($statePath, $json, (New-Object Text.UTF8Encoding($false)))
}

# 8. Inject the instruction to Claude
$msg = "You just closed a commit/slice on branch '$branch' (base '$base'). " +
       "Run /review-loop NOW over the slice diff. Do not ask whether to run it: run it. " +
       "The range comes from the marker ('.claude/scripts/review-marker.ps1 -Action range'), not from the whole branch: " +
       "only if that script is missing, use 'git diff $base...HEAD'. " +
       "Do not mark the work complete until the loop closes (zero medium/high-severity findings, or the 5-turn cap)."
@{ hookSpecificOutput = @{ hookEventName = "PostToolUse"; additionalContext = $msg } } |
    ConvertTo-Json -Depth 4 -Compress
exit 0
