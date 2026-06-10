# Auto-trigger de review-loop vía hook — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Que cada proyecto bootstrapeado, al abrir/actualizar un PR, inyecte determinísticamente la orden de correr `/review-loop` sobre el diff del branch — vía un hook `PostToolUse` nativo, espejado en ambas variantes, detectado por `upgrade-bootstrap` y con merge idempotente de `settings.json`.

**Architecture:** Un script PowerShell (`.claude/hooks/review-loop-trigger.ps1`) se registra como hook `PostToolUse` (matcher `Bash`) en `.claude/settings.json`. El script lee el evento por stdin, filtra `gh pr create`/`git push`, resuelve la base branch dinámicamente, deduplica por SHA en `.git/review-loop-state.json`, y emite `hookSpecificOutput.additionalContext` con la instrucción de correr `/review-loop`. Ambos archivos entran al manifest del scaffold; `upgrade-bootstrap` gana un `merge-settings.ps1` para integrarlos sin pisar config previa.

**Tech Stack:** PowerShell 7, JSON, git, gh CLI. Hooks de Claude Code. Espejado ×2 (personal + southpoint).

**Spec:** `docs/superpowers/specs/2026-06-10-auto-trigger-review-loop-hook-design.md`

---

## File Structure

Rutas relativas a la raíz del repo `C:\Repos\PERSONAL\Bootstrap Skills`. `PVar` = `skills/bootstrap-personal-project/assets/scaffold`, `SVar` = `skills/bootstrap-southpoint-project/assets/scaffold`.

**Nuevos (idénticos byte a byte en ambas variantes — es infraestructura, no contenido DOMO):**
- `PVar/.claude/hooks/review-loop-trigger.ps1` y `SVar/.claude/hooks/review-loop-trigger.ps1`
- `PVar/.claude/settings.json` y `SVar/.claude/settings.json`
- `skills/upgrade-bootstrap/scripts/merge-settings.ps1`

**Modificados:**
- `PVar/.agents/skills/review-loop/SKILL.md` y `SVar/...` — modo PR (diff del branch).
- `PVar/.claude/commands/review-loop.md` y `SVar/...` — modo PR.
- `PVar/CLAUDE.md` y `SVar/CLAUDE.md` — nota del auto-trigger.
- `skills/upgrade-bootstrap/SKILL.md` — caso especial `settings.json` (merge idempotente).
- `PVar/.bootstrap-manifest.json` y `SVar/...` — regenerados (Task 7).
- `skills/bootstrap-personal-project/SKILL.md` y `skills/bootstrap-southpoint-project/SKILL.md` — línea "This delivers" + verificación de Step 2.
- `docs/TESTING.md` — conteo 45→47, assertions y casos de regresión nuevos.

**Conteo de archivos del scaffold:** hoy 45; tras agregar `settings.json` + `review-loop-trigger.ps1` → **47**.

---

## Task 0: Branch e identidad

**Files:** ninguno.

- [ ] **Step 1: Crear branch desde main**

Run: `git checkout main; git checkout -b feat/auto-trigger-review-loop`
Expected: `Switched to a new branch 'feat/auto-trigger-review-loop'`

- [ ] **Step 2: Asegurar identidad local**

Run:
```powershell
git config user.name "MartinDele703"; git config user.email "martin.deleon703@gmail.com"
git config user.name; git config user.email
```
Expected: `MartinDele703` / `martin.deleon703@gmail.com`

---

## Task 1: Script del hook `review-loop-trigger.ps1`

**Files:**
- Create: `skills/bootstrap-personal-project/assets/scaffold/.claude/hooks/review-loop-trigger.ps1`
- Create: `skills/bootstrap-southpoint-project/assets/scaffold/.claude/hooks/review-loop-trigger.ps1` (idéntico)

- [ ] **Step 1: Escribir el script (en la ruta personal primero)**

Contenido completo de `review-loop-trigger.ps1`:

```powershell
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

# 2. Filtrar: solo gh pr create / git push
$isPr   = $cmd -match '\bgh\s+pr\s+create\b'
$isPush = $cmd -match '\bgit\s+push\b'
if (-not ($isPr -or $isPush)) { exit 0 }

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
    if ($head) { $base = ($head -replace '^origin/', '') }
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

# 5. No revisar la base contra sí misma
if ($branch -eq $base) { exit 0 }

# 6. Dedupe por SHA del HEAD del branch
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
if ($state[$branch] -eq $sha) { exit 0 }     # ya disparado para este commit
$state[$branch] = $sha
([pscustomobject]$state) | ConvertTo-Json | Set-Content -LiteralPath $statePath -Encoding UTF8

# 7. Inyectar la instrucción a Claude
$msg = "Acabas de abrir o actualizar un PR (branch '$branch' sobre base '$base'). " +
       "Antes de dar el trabajo por terminado, ejecuta /review-loop revisando el diff del " +
       "branch con: git diff $base...HEAD. No marques el trabajo como completo hasta que el " +
       "loop cierre (cero hallazgos de severidad media/alta, o el tope de 5 turnos)."
@{ hookSpecificOutput = @{ hookEventName = "PostToolUse"; additionalContext = $msg } } |
    ConvertTo-Json -Depth 4 -Compress
exit 0
```

- [ ] **Step 2: Test — no-op en comando no-git**

Run:
```powershell
$ev = @{ tool_name="Bash"; tool_input=@{ command="ls -la" }; cwd=(Get-Location).Path } | ConvertTo-Json -Compress
$out = $ev | pwsh -NoProfile -File "skills/bootstrap-personal-project/assets/scaffold/.claude/hooks/review-loop-trigger.ps1"
"salida (esperado vacío): '$out'"
```
Expected: `salida (esperado vacío): ''`

- [ ] **Step 3: Test — dispara en git push (base main), dedupe y re-dispara tras nuevo commit**

Run:
```powershell
$ErrorActionPreference = "Stop"
$hook = (Resolve-Path "skills/bootstrap-personal-project/assets/scaffold/.claude/hooks/review-loop-trigger.ps1").Path
$repo = Join-Path $env:TEMP ("hk-" + [guid]::NewGuid().ToString("N").Substring(0,8))
New-Item -ItemType Directory -Force $repo | Out-Null
Push-Location $repo
git init -b main *>$null
git config user.email "t@t.t"; git config user.name "t"
Set-Content README.md "v1"; git add .; git commit -m "init" *>$null
git checkout -b feature-x *>$null
Set-Content f.txt "a"; git add .; git commit -m "c1" *>$null
$ev = @{ tool_name="Bash"; tool_input=@{ command="git push origin feature-x" }; cwd=$repo } | ConvertTo-Json -Compress
$o1 = $ev | pwsh -NoProfile -File $hook
$o2 = $ev | pwsh -NoProfile -File $hook                 # mismo SHA -> dedupe
Set-Content g.txt "b"; git add .; git commit -m "c2" *>$null
$o3 = $ev | pwsh -NoProfile -File $hook                 # nuevo SHA -> re-dispara
Pop-Location
"dispara con push (esperado contiene additionalContext): $([bool]($o1 -match 'additionalContext'))"
"usa base main (esperado True): $([bool]($o1 -match 'git diff main\.\.\.HEAD'))"
"dedupe en segundo push (esperado vacío): '$o2'"
"re-dispara tras nuevo commit (esperado True): $([bool]($o3 -match 'additionalContext'))"
Remove-Item $repo -Recurse -Force
```
Expected: dispara True; base main True; dedupe vacío; re-dispara True.

- [ ] **Step 4: Test — no dispara estando en la base; respeta `--base develop`**

Run:
```powershell
$ErrorActionPreference = "Stop"
$hook = (Resolve-Path "skills/bootstrap-personal-project/assets/scaffold/.claude/hooks/review-loop-trigger.ps1").Path
$repo = Join-Path $env:TEMP ("hk2-" + [guid]::NewGuid().ToString("N").Substring(0,8))
New-Item -ItemType Directory -Force $repo | Out-Null
Push-Location $repo
git init -b main *>$null
git config user.email "t@t.t"; git config user.name "t"
Set-Content README.md "v1"; git add .; git commit -m "init" *>$null
# a) push estando en main (la base) -> no-op
$evMain = @{ tool_name="Bash"; tool_input=@{ command="git push" }; cwd=$repo } | ConvertTo-Json -Compress
$oMain = $evMain | pwsh -NoProfile -File $hook
# b) gh pr create --base develop desde un feature -> base develop
git checkout -b feature-y *>$null
Set-Content h.txt "x"; git add .; git commit -m "c" *>$null
$evPr = @{ tool_name="Bash"; tool_input=@{ command="gh pr create --base develop --fill" }; cwd=$repo } | ConvertTo-Json -Compress
$oPr = $evPr | pwsh -NoProfile -File $hook
Pop-Location
"en base main no dispara (esperado vacío): '$oMain'"
"--base develop usa develop (esperado True): $([bool]($oPr -match 'git diff develop\.\.\.HEAD'))"
Remove-Item $repo -Recurse -Force
```
Expected: en base no dispara (vacío); `--base develop` usa develop True.

- [ ] **Step 5: Copiar el script idéntico a la variante southpoint**

Run:
```powershell
$src = "skills/bootstrap-personal-project/assets/scaffold/.claude/hooks/review-loop-trigger.ps1"
$dstDir = "skills/bootstrap-southpoint-project/assets/scaffold/.claude/hooks"
New-Item -ItemType Directory -Force $dstDir | Out-Null
Copy-Item $src (Join-Path $dstDir "review-loop-trigger.ps1") -Force
(Get-FileHash $src).Hash -eq (Get-FileHash "$dstDir/review-loop-trigger.ps1").Hash
```
Expected: `True` (byte-idénticos).

- [ ] **Step 6: Commit**

```powershell
git add skills/bootstrap-personal-project/assets/scaffold/.claude/hooks/review-loop-trigger.ps1 skills/bootstrap-southpoint-project/assets/scaffold/.claude/hooks/review-loop-trigger.ps1
git commit -m "feat(scaffold): hook review-loop-trigger.ps1 (auto-dispara review-loop post-PR)"
```

---

## Task 2: `settings.json` que registra el hook (ambas variantes)

**Files:**
- Create: `skills/bootstrap-personal-project/assets/scaffold/.claude/settings.json`
- Create: `skills/bootstrap-southpoint-project/assets/scaffold/.claude/settings.json` (idéntico)

- [ ] **Step 1: Escribir `settings.json` (variante personal)**

Contenido completo:

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "pwsh -NoProfile -File \"${CLAUDE_PROJECT_DIR}/.claude/hooks/review-loop-trigger.ps1\""
          }
        ]
      }
    ]
  }
}
```

- [ ] **Step 2: Test — JSON válido y estructura correcta**

Run:
```powershell
$s = Get-Content "skills/bootstrap-personal-project/assets/scaffold/.claude/settings.json" -Raw | ConvertFrom-Json
"matcher (esperado Bash): $($s.hooks.PostToolUse[0].matcher)"
"command apunta al trigger (esperado True): $([bool]($s.hooks.PostToolUse[0].hooks[0].command -match 'review-loop-trigger'))"
```
Expected: `matcher: Bash`; command apunta al trigger True.

- [ ] **Step 3: Copiar idéntico a southpoint**

Run:
```powershell
Copy-Item "skills/bootstrap-personal-project/assets/scaffold/.claude/settings.json" "skills/bootstrap-southpoint-project/assets/scaffold/.claude/settings.json" -Force
(Get-FileHash "skills/bootstrap-personal-project/assets/scaffold/.claude/settings.json").Hash -eq (Get-FileHash "skills/bootstrap-southpoint-project/assets/scaffold/.claude/settings.json").Hash
```
Expected: `True`.

- [ ] **Step 4: Commit**

```powershell
git add skills/bootstrap-personal-project/assets/scaffold/.claude/settings.json skills/bootstrap-southpoint-project/assets/scaffold/.claude/settings.json
git commit -m "feat(scaffold): settings.json registra el hook PostToolUse de review-loop"
```

---

## Task 3: Modo PR en la skill `review-loop` (ambas variantes)

**Files:**
- Modify: `skills/bootstrap-personal-project/assets/scaffold/.agents/skills/review-loop/SKILL.md`
- Modify: `skills/bootstrap-southpoint-project/assets/scaffold/.agents/skills/review-loop/SKILL.md`
- Modify: `skills/bootstrap-personal-project/assets/scaffold/.claude/commands/review-loop.md`
- Modify: `skills/bootstrap-southpoint-project/assets/scaffold/.claude/commands/review-loop.md`

- [ ] **Step 1: Agregar la sección "Modo PR" en los 4 archivos**

En los CUATRO archivos, insertar el siguiente bloque inmediatamente después de la sección `## Pre-flight: is the diff small enough?` (antes de `## The loop`):

```markdown
## Modo PR (cuando lo dispara el hook)

Si llegaste acá porque el hook `review-loop-trigger` te lo pidió tras un `gh pr create` / `git push`, revisá el **diff del branch** (lo que el PR introduce sobre su base), no el working-tree:

```powershell
git diff <base>...HEAD --stat   # <base> es la rama base del PR (main/develop/etc., la que indicó el hook)
```

Usá ese mismo rango (`git diff <base>...HEAD`) como entrada de cada `/code-review` del loop. El modo working-tree (`git diff` sin rango) sigue siendo el default para invocación manual sobre cambios sin commitear.
```

- [ ] **Step 2: Verificar en los 4 archivos**

Run:
```powershell
$f = @(
 "skills/bootstrap-personal-project/assets/scaffold/.agents/skills/review-loop/SKILL.md",
 "skills/bootstrap-southpoint-project/assets/scaffold/.agents/skills/review-loop/SKILL.md",
 "skills/bootstrap-personal-project/assets/scaffold/.claude/commands/review-loop.md",
 "skills/bootstrap-southpoint-project/assets/scaffold/.claude/commands/review-loop.md")
$f | ForEach-Object { "{0}: {1}" -f (Split-Path $_ -Leaf), [bool]((Get-Content $_ -Raw) -match 'Modo PR \(cuando lo dispara el hook\)') }
```
Expected: los 4 con `True`.

- [ ] **Step 3: Commit**

```powershell
git add skills/bootstrap-personal-project/assets/scaffold/.agents/skills/review-loop/SKILL.md skills/bootstrap-southpoint-project/assets/scaffold/.agents/skills/review-loop/SKILL.md skills/bootstrap-personal-project/assets/scaffold/.claude/commands/review-loop.md skills/bootstrap-southpoint-project/assets/scaffold/.claude/commands/review-loop.md
git commit -m "feat(scaffold): review-loop soporta modo PR (diff del branch)"
```

---

## Task 4: Nota del auto-trigger en el `CLAUDE.md` template (ambas variantes)

**Files:**
- Modify: `skills/bootstrap-personal-project/assets/scaffold/CLAUDE.md`
- Modify: `skills/bootstrap-southpoint-project/assets/scaffold/CLAUDE.md`

- [ ] **Step 1: Localizar el ancla en ambos CLAUDE.md**

Run:
```powershell
Select-String -Path skills/bootstrap-personal-project/assets/scaffold/CLAUDE.md,skills/bootstrap-southpoint-project/assets/scaffold/CLAUDE.md -Pattern "review-loop" | ForEach-Object { "{0}:{1}: {2}" -f (Split-Path $_.Path -Leaf), $_.LineNumber, $_.Line.Trim() }
```
Expected: la línea de transición `- After implementation, suggest QA and the clean-context review via \`/review-loop\`` en ambos.

- [ ] **Step 2: Reemplazar esa línea en AMBOS CLAUDE.md**

Reemplazar:
```
- After implementation, suggest QA and the clean-context review via `/review-loop`
```
por:
```
- After implementation, suggest QA and the clean-context review via `/review-loop`. Además, al abrir o actualizar un PR (`gh pr create` / `git push`), el hook `review-loop-trigger` inyecta automáticamente la orden de correr `/review-loop` sobre el diff del branch; no depende de que el agente lo recuerde. El `/review-loop` manual sigue disponible para revisar cambios locales sin commitear.
```

- [ ] **Step 3: Verificar**

Run:
```powershell
Select-String -Path skills/bootstrap-personal-project/assets/scaffold/CLAUDE.md,skills/bootstrap-southpoint-project/assets/scaffold/CLAUDE.md -Pattern "el hook .review-loop-trigger. inyecta" | ForEach-Object { Split-Path $_.Path -Leaf }
```
Expected: los dos archivos listados.

- [ ] **Step 4: Commit**

```powershell
git add skills/bootstrap-personal-project/assets/scaffold/CLAUDE.md skills/bootstrap-southpoint-project/assets/scaffold/CLAUDE.md
git commit -m "docs(scaffold): documentar el auto-trigger del review-loop en CLAUDE.md"
```

---

## Task 5: `merge-settings.ps1` en upgrade-bootstrap

**Files:**
- Create: `skills/upgrade-bootstrap/scripts/merge-settings.ps1`

- [ ] **Step 1: Escribir `merge-settings.ps1`**

```powershell
# Integra (idempotente) el hook review-loop-trigger en el settings.json del proyecto, sin
# pisar la config previa. Si el proyecto no tiene settings.json, copia el canónico entero.
# Uso: pwsh -File merge-settings.ps1 -ProjectSettings <ruta> -CanonicalSettings <ruta>
param(
    [Parameter(Mandatory)][string]$ProjectSettings,
    [Parameter(Mandatory)][string]$CanonicalSettings
)
$ErrorActionPreference = "Stop"

if (-not (Test-Path $ProjectSettings)) {
    New-Item -ItemType Directory -Force (Split-Path $ProjectSettings -Parent) | Out-Null
    Copy-Item $CanonicalSettings $ProjectSettings -Force
    Write-Host "settings.json no existia: copiado el canonico."
    exit 0
}

$canon = Get-Content $CanonicalSettings -Raw | ConvertFrom-Json -AsHashtable
$proj  = Get-Content $ProjectSettings  -Raw | ConvertFrom-Json -AsHashtable
if ($null -eq $proj)        { $proj = @{} }
if (-not $proj.ContainsKey('hooks'))            { $proj['hooks'] = @{} }
if (-not $proj.hooks.ContainsKey('PostToolUse')) { $proj.hooks['PostToolUse'] = @() }

function Has-Trigger($entries) {
    foreach ($e in @($entries)) {
        foreach ($h in @($e.hooks)) {
            if ($h.command -and ($h.command -match 'review-loop-trigger')) { return $true }
        }
    }
    return $false
}

if (Has-Trigger $proj.hooks.PostToolUse) {
    Write-Host "Hook review-loop-trigger ya presente: nada que hacer (idempotente)."
    exit 0
}

# Agregar solo las entradas canonicas que traen el hook review-loop-trigger
$toAdd = @()
foreach ($e in @($canon.hooks.PostToolUse)) {
    if (Has-Trigger @($e)) { $toAdd += $e }
}
$proj.hooks['PostToolUse'] = @($proj.hooks.PostToolUse) + $toAdd
$proj | ConvertTo-Json -Depth 12 | Set-Content $ProjectSettings -Encoding UTF8
Write-Host "Hook review-loop-trigger agregado al settings.json del proyecto ($($toAdd.Count) entrada/s)."
```

- [ ] **Step 2: Test — settings.json ausente → copia el canónico**

Run:
```powershell
$ErrorActionPreference = "Stop"
$root = Join-Path $env:TEMP ("ms-" + [guid]::NewGuid().ToString("N").Substring(0,8))
$proj = Join-Path $root "proj/.claude"; New-Item -ItemType Directory -Force $proj | Out-Null
$canon = "skills/bootstrap-personal-project/assets/scaffold/.claude/settings.json"
pwsh -NoProfile -File "skills/upgrade-bootstrap/scripts/merge-settings.ps1" -ProjectSettings "$proj/settings.json" -CanonicalSettings $canon
$s = Get-Content "$proj/settings.json" -Raw | ConvertFrom-Json
"copiado y tiene el trigger (esperado True): $([bool]($s.hooks.PostToolUse[0].hooks[0].command -match 'review-loop-trigger'))"
Remove-Item $root -Recurse -Force
```
Expected: copiado y tiene el trigger True.

- [ ] **Step 3: Test — settings.json propio preexistente → mergea sin pisar, e idempotente**

Run:
```powershell
$ErrorActionPreference = "Stop"
$root = Join-Path $env:TEMP ("ms2-" + [guid]::NewGuid().ToString("N").Substring(0,8))
$proj = Join-Path $root "proj/.claude"; New-Item -ItemType Directory -Force $proj | Out-Null
$canon = "skills/bootstrap-personal-project/assets/scaffold/.claude/settings.json"
# settings propio del usuario: tiene un permiso y OTRO hook PostToolUse no relacionado
@{
  permissions = @{ allow = @("Bash(npm run test)") }
  hooks = @{ PostToolUse = @(@{ matcher="Write"; hooks=@(@{ type="command"; command="echo hola" }) }) }
} | ConvertTo-Json -Depth 8 | Set-Content "$proj/settings.json" -Encoding UTF8
pwsh -NoProfile -File "skills/upgrade-bootstrap/scripts/merge-settings.ps1" -ProjectSettings "$proj/settings.json" -CanonicalSettings $canon
$s1 = Get-Content "$proj/settings.json" -Raw | ConvertFrom-Json
"conserva el permiso propio (esperado True): $([bool]($s1.permissions.allow -contains 'Bash(npm run test)'))"
"conserva el hook Write propio (esperado True): $([bool](@($s1.hooks.PostToolUse | Where-Object { $_.matcher -eq 'Write' }).Count -ge 1))"
"agrega el trigger (esperado True): $([bool](($s1.hooks.PostToolUse | ForEach-Object { $_.hooks.command }) -match 'review-loop-trigger'))"
# Idempotencia: correr de nuevo no duplica
pwsh -NoProfile -File "skills/upgrade-bootstrap/scripts/merge-settings.ps1" -ProjectSettings "$proj/settings.json" -CanonicalSettings $canon
$s2 = Get-Content "$proj/settings.json" -Raw | ConvertFrom-Json
$cnt = @($s2.hooks.PostToolUse | Where-Object { ($_.hooks.command -match 'review-loop-trigger') }).Count
"entradas con trigger tras 2da corrida (esperado 1): $cnt"
Remove-Item $root -Recurse -Force
```
Expected: conserva permiso True; conserva hook Write True; agrega trigger True; entradas con trigger = 1.

- [ ] **Step 4: Commit**

```powershell
git add skills/upgrade-bootstrap/scripts/merge-settings.ps1
git commit -m "feat(upgrade-bootstrap): merge-settings.ps1 (integra el hook idempotente)"
```

---

## Task 6: Caso especial `settings.json` en `upgrade-bootstrap/SKILL.md`

**Files:**
- Modify: `skills/upgrade-bootstrap/SKILL.md`

- [ ] **Step 1: Reemplazar la viñeta de `customized` en el paso "4. Apply"**

En `skills/upgrade-bootstrap/SKILL.md`, reemplazar:
```
- **customized / different** → show the diff (canonical vs project). Offer, per file: skip (keep yours), or an assisted merge where you help integrate the new bits into the user's version. Never overwrite without per-file consent.
```
por:
```
- **customized / different** → show the diff (canonical vs project). Offer, per file: skip (keep yours), or an assisted merge where you help integrate the new bits into the user's version. Never overwrite without per-file consent. **Special case `.claude/settings.json`:** do NOT diff-merge by hand — run `merge-settings.ps1` (below), which adds the `review-loop-trigger` hook idempotently without touching the rest of the user's config.
```

- [ ] **Step 2: Agregar el manejo de `settings.json` en la viñeta `missing` y un bloque de comando**

En el mismo paso "4. Apply", reemplazar:
```
- **missing** → copy from the canonical scaffold into the project (same relative path). Special case: the canonical key `.gitignore` is sourced from `gitignore.txt` in the scaffold.
```
por:
```
- **missing** → copy from the canonical scaffold into the project (same relative path). Special case: the canonical key `.gitignore` is sourced from `gitignore.txt` in the scaffold. Special case `.claude/settings.json`: copy it only if absent; if the project already has its own, treat it as the `settings.json` merge below instead of a plain copy.
```

Y al final del paso "4. Apply" (después de la línea `When copying \`.gitignore\`, read from ...`), agregar:
```

**Merge of `.claude/settings.json`** (whenever it appears in `missing` with a pre-existing file, or in `customized`):

```powershell
pwsh -File <this-skill>/scripts/merge-settings.ps1 -ProjectSettings "<project>/.claude/settings.json" -CanonicalSettings "<canonical scaffold>/.claude/settings.json"
```

It is idempotent — running it twice never duplicates the hook. If the project had no `settings.json`, it copies the canonical one verbatim.
```

- [ ] **Step 3: Verificar**

Run:
```powershell
Select-String -Path skills/upgrade-bootstrap/SKILL.md -Pattern "merge-settings.ps1","Special case .\.claude/settings.json" | ForEach-Object { $_.LineNumber }
```
Expected: al menos 3 líneas (las dos viñetas + el bloque de comando).

- [ ] **Step 4: Commit**

```powershell
git add skills/upgrade-bootstrap/SKILL.md
git commit -m "feat(upgrade-bootstrap): merge idempotente de settings.json en el flujo apply"
```

---

## Task 7: Regenerar manifests + verificar conteo 47

**Files:**
- Modify: `skills/bootstrap-personal-project/assets/scaffold/.bootstrap-manifest.json` (regenerado)
- Modify: `skills/bootstrap-southpoint-project/assets/scaffold/.bootstrap-manifest.json` (regenerado)

- [ ] **Step 1: Regenerar ambos manifests**

Run:
```powershell
pwsh -File tools/gen-manifest.ps1 -SkillDir "skills/bootstrap-personal-project"
pwsh -File tools/gen-manifest.ps1 -SkillDir "skills/bootstrap-southpoint-project"
```
Expected: `Manifest generado: ... (47 archivos, ...)` para cada uno.

- [ ] **Step 2: Verificar que el manifest incluye los 2 nuevos y el conteo**

Run:
```powershell
$m = Get-Content "skills/bootstrap-personal-project/assets/scaffold/.bootstrap-manifest.json" -Raw | ConvertFrom-Json
"files count (esperado 47): $($m.files.PSObject.Properties.Count)"
"tiene settings.json (esperado True): $([bool]($m.files.PSObject.Properties.Name -contains '.claude/settings.json'))"
"tiene el hook (esperado True): $([bool]($m.files.PSObject.Properties.Name -contains '.claude/hooks/review-loop-trigger.ps1'))"
```
Expected: count 47; settings.json True; hook True.

- [ ] **Step 3: Commit**

```powershell
git add skills/bootstrap-personal-project/assets/scaffold/.bootstrap-manifest.json skills/bootstrap-southpoint-project/assets/scaffold/.bootstrap-manifest.json
git commit -m "chore(scaffold): regenerar manifests con el hook y settings.json (47 archivos)"
```

---

## Task 8: Actualizar `docs/TESTING.md`

**Files:**
- Modify: `docs/TESTING.md`

- [ ] **Step 1: Actualizar la assertion "Scaffold completo"**

En `docs/TESTING.md`, reemplazar:
```
`skills-lock.json`, `.bootstrap-manifest.json`, README, CONTEXT.md stub, `docs/adr/`.
```
por:
```
`skills-lock.json`, `.bootstrap-manifest.json`, `.claude/settings.json`, `.claude/hooks/review-loop-trigger.ps1`, README, CONTEXT.md stub, `docs/adr/`.
```

- [ ] **Step 2: Actualizar el conteo `uptodate` de 45 a 47 en el caso "Al día"**

En `docs/TESTING.md`, en la sección "Testeo de `upgrade-bootstrap`", reemplazar:
```
4. **Al día** — proyecto recién bootstrapeado: `missing/outdated/customized` vacíos, `uptodate` == 45.
```
por:
```
4. **Al día** — proyecto recién bootstrapeado: `missing/outdated/customized` vacíos, `uptodate` == 47.
```

- [ ] **Step 3: Agregar la subsección de casos de regresión del hook**

En `docs/TESTING.md`, al final del archivo, agregar:
```markdown

## Testeo del hook `review-loop-trigger` y del merge de settings

El script del hook y `merge-settings.ps1` se testean con fixtures determinísticos (repos git temporales en `$env:TEMP`), no con skill-creator. Casos de regresión (implementados en `docs/superpowers/plans/2026-06-10-auto-trigger-review-loop-hook.md`, Tasks 1 y 5):

- **No-op no-git** — un comando Bash que no es `gh pr create`/`git push` no emite nada.
- **Dispara post-PR** — `git push` en un branch de feature emite `additionalContext` con `git diff <base>...HEAD`.
- **Dedupe por SHA** — segundo disparo sobre el mismo commit no emite; tras un commit nuevo vuelve a disparar.
- **Base dinámica** — estar en la base no dispara; `gh pr create --base develop` usa `develop` (no hardcodea `main`).
- **Merge de settings** — `settings.json` ausente → copia el canónico; preexistente propio → agrega el hook sin pisar permisos/otros hooks; correrlo dos veces no duplica la entrada.
```

- [ ] **Step 4: Verificar**

Run:
```powershell
Select-String -Path docs/TESTING.md -Pattern "review-loop-trigger.ps1","uptodate.*== 47","Merge de settings" | ForEach-Object { $_.LineNumber }
```
Expected: al menos 3 líneas.

- [ ] **Step 5: Commit**

```powershell
git add docs/TESTING.md
git commit -m "docs: casos de regresion del hook y merge de settings en TESTING.md"
```

---

## Task 9: Actualizar "This delivers" + verificación de Step 2 en ambos `SKILL.md` bootstrap

**Files:**
- Modify: `skills/bootstrap-personal-project/SKILL.md`
- Modify: `skills/bootstrap-southpoint-project/SKILL.md`

- [ ] **Step 1: Actualizar la verificación de Step 2 en AMBOS**

En ambos `SKILL.md`, reemplazar:
```
Before committing, verify the copy landed cleanly: `.agents\skills` has 10 skill directories, `.claude\commands` has 10 files, and neither `.agents\.agents` nor `.claude\.claude` exists.
```
por:
```
Before committing, verify the copy landed cleanly: `.agents\skills` has 10 skill directories, `.claude\commands` has 10 files, `.claude\settings.json` and `.claude\hooks\review-loop-trigger.ps1` exist, and neither `.agents\.agents` nor `.claude\.claude` exists.
```

- [ ] **Step 2: Actualizar la línea "This delivers" en AMBOS**

En ambos `SKILL.md`, reemplazar:
```
`.claude/commands/` (10 commands), `docs/ai-workflow/` (5 docs), `docs/agents/` (3 docs).
```
por:
```
`.claude/commands/` (10 commands), `.claude/settings.json` + `.claude/hooks/review-loop-trigger.ps1` (auto-dispara `review-loop` al abrir/actualizar un PR), `docs/ai-workflow/` (5 docs), `docs/agents/` (3 docs).
```

- [ ] **Step 3: Verificar**

Run:
```powershell
Select-String -Path skills/bootstrap-personal-project/SKILL.md,skills/bootstrap-southpoint-project/SKILL.md -Pattern "auto-dispara .review-loop. al abrir","review-loop-trigger.ps1. exist" | ForEach-Object { Split-Path $_.Path -Leaf } | Sort-Object -Unique
```
Expected: los dos archivos.

- [ ] **Step 4: Commit**

```powershell
git add skills/bootstrap-personal-project/SKILL.md skills/bootstrap-southpoint-project/SKILL.md
git commit -m "docs(scaffold): el bootstrap entrega settings.json + hook del review-loop"
```

---

## Task 10: Eval end-to-end + deploy + merge

**Files:** ninguno (verificación + deploy).

- [ ] **Step 1: Eval — bootstrap en directorio vacío entrega los 2 archivos nuevos**

Simular el Step 2 del bootstrap personal sobre un dir vacío y verificar:

```powershell
$ErrorActionPreference = "Stop"
$skill = (Resolve-Path "skills/bootstrap-personal-project").Path
$proj  = Join-Path $env:TEMP ("bs-" + [guid]::NewGuid().ToString("N").Substring(0,8))
New-Item -ItemType Directory -Force $proj | Out-Null
Get-ChildItem "$skill\assets\scaffold" -Force | Where-Object Name -ne "gitignore.txt" |
  ForEach-Object { Copy-Item $_.FullName (Join-Path $proj $_.Name) -Recurse -Force }
Copy-Item "$skill\assets\scaffold\gitignore.txt" (Join-Path $proj ".gitignore")
"settings.json (esperado True): $(Test-Path "$proj/.claude/settings.json")"
"hook (esperado True): $(Test-Path "$proj/.claude/hooks/review-loop-trigger.ps1")"
"sin anidados .claude\.claude (esperado False): $(Test-Path "$proj/.claude/.claude")"
"commands sigue en 10 (esperado 10): $(@(Get-ChildItem "$proj/.claude/commands" -File).Count)"
Remove-Item $proj -Recurse -Force
```
Expected: settings.json True; hook True; anidados False; commands 10.

- [ ] **Step 2: Eval — upgrade-bootstrap detecta los 2 nuevos como `missing` en un proyecto sin ellos**

```powershell
$ErrorActionPreference = "Stop"
$canon = (Resolve-Path "skills/bootstrap-personal-project/assets/scaffold").Path
$proj  = Join-Path $env:TEMP ("up-" + [guid]::NewGuid().ToString("N").Substring(0,8))
New-Item -ItemType Directory -Force $proj | Out-Null
# Sembrar = copia del scaffold actual PERO sin settings.json ni el hook (simula versión previa)
Get-ChildItem $canon -Force | Where-Object Name -ne "gitignore.txt" | ForEach-Object { Copy-Item $_.FullName (Join-Path $proj $_.Name) -Recurse -Force }
Copy-Item "$canon/gitignore.txt" (Join-Path $proj ".gitignore")
Remove-Item (Join-Path $proj ".claude/settings.json") -Force
Remove-Item (Join-Path $proj ".claude/hooks") -Recurse -Force
$o = pwsh -File "skills/upgrade-bootstrap/scripts/compare-scaffold.ps1" -ProjectDir $proj -CanonicalScaffold $canon | ConvertFrom-Json
"missing incluye settings.json (esperado True): $([bool]($o.missing -contains '.claude/settings.json'))"
"missing incluye el hook (esperado True): $([bool]($o.missing -contains '.claude/hooks/review-loop-trigger.ps1'))"
Remove-Item $proj -Recurse -Force
```
Expected: ambos `True`.

- [ ] **Step 3: (Opcional) Evals con skill-creator**

Si se desea cobertura de triggering/cualitativa de los bootstrap, invocar `skill-creator:skill-creator` con los casos canónicos de `docs/TESTING.md` (directorio vacío + preexistentes) y verificar que el scaffold ahora incluye `settings.json` + el hook. Borrar el workspace al terminar (regla del repo).

- [ ] **Step 4: Deploy + merge** (requiere confirmación del usuario — efecto en instalación activa)

```powershell
pwsh -File tools/sync-skills.ps1
Test-Path "$env:USERPROFILE/.claude/skills/bootstrap-personal-project/assets/scaffold/.claude/hooks/review-loop-trigger.ps1"
git checkout main; git merge --ff-only feat/auto-trigger-review-loop; git branch -d feat/auto-trigger-review-loop
```
Expected: hook deployado (`True`); merge fast-forward; branch borrada.

---

## Self-review notes

- **Spec coverage:** gatillo híbrido `gh pr create`+`git push` (Task 1, Steps 3-4) ✓; dedupe por SHA (Task 1, Step 3) ✓; base dinámica no-hardcodeada (Task 1, Step 4) ✓; `settings.json`+hook nuevos espejados (Tasks 1-2) ✓; modo PR en review-loop (Task 3) ✓; nota en CLAUDE.md (Task 4) ✓; manifest +2 (Task 7) ✓; merge idempotente de settings en upgrade-bootstrap (Tasks 5-6) ✓; casos de regresión en TESTING.md (Task 8) ✓.
- **Espejado:** el script y settings.json se escriben una vez y se copian byte-idénticos a la otra variante (Tasks 1-2, verificado por hash). El resto de ediciones se aplica explícitamente a ambas rutas.
- **Conteo:** 45 → 47 (consistente en Task 7, Task 8 y los evals).
- **Límite asumido del hook:** inyecta la instrucción determinísticamente; la ejecución del loop la hace el modelo (documentado en el spec; no se testea la ejecución, solo la inyección).
- **`gh repo view` en fixtures:** los tests de Task 1 no tienen remoto; la resolución de base cae al fallback `main/master/develop` (o a `--base` explícito), por eso `gh repo view` puede emitir error silenciado (`2>$null`) sin afectar el resultado.
- **Nombres consistentes:** `review-loop-trigger.ps1`, `review-loop-state.json`, `merge-settings.ps1`, `additionalContext`, `hookSpecificOutput` usados igual en script, settings, tests y docs.
