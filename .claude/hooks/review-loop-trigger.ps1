# Hook PostToolUse (matcher Bash). Si el comando ejecutado fue `gh pr create` o `git push`
# en un branch que NO es la base, inyecta a Claude la orden de correr /review-loop sobre el
# diff del branch. Deduplica por SHA en .git/review-loop-state.json para no disparar dos
# veces sobre el mismo commit. Cualquier camino que no aplique termina en exit 0 silencioso.
$ErrorActionPreference = "SilentlyContinue"

# 1. Leer el evento del hook por stdin
$raw = [Console]::In.ReadToEnd()
if (-not $raw) { exit 0 }
try { $evt = $raw | ConvertFrom-Json } catch { exit 0 }
$cmd = $evt.tool_input.command
if (-not $cmd) { exit 0 }

# 2. Filtrar: gh pr create / git push / git commit
$isPr     = $cmd -match '\bgh\s+pr\s+create\b'
$isPush   = $cmd -match '\bgit\s+push\b'
$isCommit = $cmd -match '\bgit\s+commit(?![\w-])'   # excluye git commit-graph y similares
if (-not ($isPr -or $isPush -or $isCommit)) { exit 0 }

# 3. Ubicarse en el repo (cwd del evento)
$cwd = if ($evt.cwd) { $evt.cwd } else { (Get-Location).Path }
Set-Location -LiteralPath $cwd
$gitDir = (git rev-parse --git-dir 2>$null)
if (-not $gitDir) { exit 0 }                 # no es repo git
if (-not [System.IO.Path]::IsPathRooted($gitDir)) { $gitDir = Join-Path $cwd $gitDir }
$branch = (git rev-parse --abbrev-ref HEAD 2>$null)
if (-not $branch -or $branch -eq "HEAD") { exit 0 }

# 4. Resolver la base branch (NO hardcodear main)
$base = $null
if ($isPr -and $cmd -match '--base[ =]+([^\s''"]+)') { $base = $matches[1] }
if (-not $base) {
    $head = (git symbolic-ref --short refs/remotes/origin/HEAD 2>$null)
    if ($head) {
        # Pelar `origin/` solo si la rama local existe de verdad. Un clon de una sola rama tiene
        # `origin/main` y ningún `main` local, y con el nombre pelado falla el rango de fallback
        # que este hook sugiere (`git diff <base>...HEAD`).
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

# 5. No revisar la base contra sí misma (la base puede ser un ref remoto)
if (($branch -eq $base) -or ($base -eq "origin/$branch")) { exit 0 }

# 6. Un commit dispara solo cuando el cierre de slice está DECLARADO con un trailer `Slice-Close:`.
# El trailer se lee del commit recién creado, no se parsea del comando, así que funciona igual con
# `-m`, `-F archivo`, un heredoc o `--amend`.
if ($isCommit) {
    # El evento trae el cwd de la SESIÓN, no el directorio donde corrió el comando: sin esto, un
    # `git commit` dentro de otro repo se le atribuye a éste. Si el HEAD de este repo no es
    # reciente, el commit ocurrió en otro lado.
    $ct = (git log -1 --format=%ct 2>$null)
    if (-not $ct) { exit 0 }
    if (([DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - [int64]$ct) -gt 120) { exit 0 }

    $body = ((git log -1 --format=%B 2>$null) -join "`n")
    if ($body -notmatch '(?m)^\s*Slice-Close:') {
        # Red de seguridad: olvidarse del trailer no puede dejar un slice gigante sin revisar. Si
        # el delta SIN REVISAR ya pasa el techo de ~400 líneas del CLAUDE.md, dispara igual.
        $range = $null
        $root = (git rev-parse --show-toplevel 2>$null)
        if ($root) {
            $marker = Join-Path $root ".claude/scripts/review-marker.ps1"
            if (Test-Path -LiteralPath $marker) {
                $r = (& pwsh -NoProfile -File $marker -Action range -RepoDir $root 2>$null)
                if ($LASTEXITCODE -eq 0 -and $r) { $range = ([string]$r).Trim() }
            }
        }
        # Sin marcador (scaffold viejo) o sin rango todavía: se cae al rango de la rama.
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

# 7. Dedupe por SHA del HEAD del branch
$sha = (git rev-parse HEAD 2>$null)
if (-not $sha) { exit 0 }
$statePath = Join-Path $gitDir "review-loop-state.json"
$state = @{}
# Es el mismo archivo que escribe el marcador de revisión. Se lee y se escribe UTF-8 explícito:
# Get-Content / Set-Content usan la code page ANSI bajo Windows PowerShell 5.1, y eso convierte la
# huella acentuada de untracked del marcador en mojibake — esa rama no puede volver a cerrar nunca.
if (Test-Path $statePath) {
    try {
        ([IO.File]::ReadAllText($statePath) | ConvertFrom-Json).PSObject.Properties |
            ForEach-Object { $state[$_.Name] = $_.Value }
    } catch { $state = @{} }
}
if ($state[$branch] -eq $sha) { exit 0 }     # ya disparado para este commit
$state[$branch] = $sha
$json = ([pscustomobject]$state) | ConvertTo-Json -Depth 6
[IO.File]::WriteAllText($statePath, $json, (New-Object Text.UTF8Encoding($false)))

# 8. Inyectar la instrucción a Claude
$msg = "Cerraste un commit/slice en el branch '$branch' (base '$base'). " +
       "Ejecuta /review-loop AHORA sobre el diff del slice. No preguntes si querés correrlo: corrélo. " +
       "El rango sale del marcador ('.claude/scripts/review-marker.ps1 -Action range'), no del branch entero: " +
       "solo si ese script no existe, usá 'git diff $base...HEAD'. " +
       "No marques el trabajo como completo hasta que el loop cierre (cero hallazgos de severidad media/alta, o el tope de 5 turnos)."
@{ hookSpecificOutput = @{ hookEventName = "PostToolUse"; additionalContext = $msg } } |
    ConvertTo-Json -Depth 4 -Compress
exit 0
