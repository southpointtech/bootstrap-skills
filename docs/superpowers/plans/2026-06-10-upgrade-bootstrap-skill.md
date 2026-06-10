# Skill `upgrade-bootstrap` + versionado del scaffold — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Dar al repo un sistema de versionado por manifest (hash por archivo) en el scaffold, y una skill `upgrade-bootstrap` que actualice proyectos ya bootstrapeados con lógica merge-base, sin pisar lo personalizado.

**Architecture:** Un script de build `tools/gen-manifest.ps1` genera `.bootstrap-manifest.json` (hashes por archivo de destino) dentro del scaffold de cada skill; el bootstrap lo entrega al proyecto. La skill `upgrade-bootstrap` corre dos scripts deterministas (`compare-scaffold.ps1` clasifica por merge-base de 3 hashes; `reseal-manifest.ps1` re-sella el manifest del proyecto) y orquesta el reporte + aplicación con aprobación del usuario.

**Tech Stack:** PowerShell 7, JSON, git. Skills de Claude Code (skill-creator para evals).

**Spec:** `docs/superpowers/specs/2026-06-09-upgrade-bootstrap-skill-design.md`

---

## File Structure

Rutas relativas a la raíz del repo `C:\Repos\PERSONAL\Bootstrap Skills`.

**Nuevos:**
- `tools/gen-manifest.ps1` — genera el manifest canónico de una skill bootstrap (build-time).
- `skills/upgrade-bootstrap/SKILL.md` — la skill (orquesta detección, reporte, aplicación).
- `skills/upgrade-bootstrap/scripts/compare-scaffold.ps1` — clasificación merge-base (runtime).
- `skills/upgrade-bootstrap/scripts/reseal-manifest.ps1` — re-sella el manifest del proyecto (runtime).
- `skills/bootstrap-personal-project/assets/scaffold/.bootstrap-manifest.json` — generado (Task 1).
- `skills/bootstrap-southpoint-project/assets/scaffold/.bootstrap-manifest.json` — generado (Task 1).

**Modificados:**
- `tools/sync-skills.ps1` — regenerar manifests antes de copiar.
- `CLAUDE.md` (raíz del repo) — documentar el flujo del manifest + agregar `upgrade-bootstrap`.
- `skills/bootstrap-personal-project/SKILL.md` y `skills/bootstrap-southpoint-project/SKILL.md` — línea "This delivers" incluye el manifest.
- `docs/TESTING.md` — assertion del manifest + casos de `upgrade-bootstrap`.

**Convención de rutas del manifest:** las claves de `files` son rutas **de destino en el proyecto**, con `/` como separador. Único caso especial: `gitignore.txt` (en el scaffold) se registra como `.gitignore` (como aterriza en el proyecto). El propio `.bootstrap-manifest.json` se auto-excluye.

---

## Task 0: Branch e identidad

**Files:** ninguno.

- [ ] **Step 1: Crear branch desde main**

Run: `git checkout main; git checkout -b feat/upgrade-bootstrap`
Expected: `Switched to a new branch 'feat/upgrade-bootstrap'`

- [ ] **Step 2: Asegurar identidad local**

Run:
```powershell
git config user.name "MartinDele703"; git config user.email "martin.deleon703@gmail.com"
git config user.name; git config user.email
```
Expected: `MartinDele703` / `martin.deleon703@gmail.com`

---

## Task 1: `gen-manifest.ps1` + generar manifests canónicos

**Files:**
- Create: `tools/gen-manifest.ps1`

- [ ] **Step 1: Escribir `tools/gen-manifest.ps1`**

```powershell
# Genera el manifest canónico (.bootstrap-manifest.json) de una skill bootstrap.
# Uso: pwsh -File tools/gen-manifest.ps1 -SkillDir <ruta a la skill que contiene assets\scaffold>
param([Parameter(Mandatory)][string]$SkillDir)
$ErrorActionPreference = "Stop"

$scaffold = Join-Path $SkillDir "assets\scaffold"
if (-not (Test-Path $scaffold)) { throw "No existe el scaffold: $scaffold" }
$skillName = Split-Path $SkillDir -Leaf
$variant = if ($skillName -like "*southpoint*") { "southpoint" } else { "personal" }
$scaffoldFull = (Resolve-Path $scaffold).Path

$files = @{}
Get-ChildItem $scaffold -Recurse -File -Force | ForEach-Object {
    $rel = $_.FullName.Substring($scaffoldFull.Length).TrimStart('\','/').Replace('\','/')
    if ($rel -eq ".bootstrap-manifest.json") { return }            # auto-exclusión
    $dest = if ($rel -eq "gitignore.txt") { ".gitignore" } else { $rel }  # mapeo a ruta de destino
    $files[$dest] = (Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLower()
}

# version = fecha + hash corto del conjunto (rutas+hashes ordenados)
$concat = ($files.GetEnumerator() | Sort-Object Name | ForEach-Object { "$($_.Name):$($_.Value)" }) -join "`n"
$sha = [System.Security.Cryptography.SHA256]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes($concat))
$setHash = ([System.BitConverter]::ToString($sha).Replace("-","").ToLower()).Substring(0,7)
$date = (Get-Date -Format "yyyy-MM-dd")

$ordered = [ordered]@{}
$files.GetEnumerator() | Sort-Object Name | ForEach-Object { $ordered[$_.Name] = $_.Value }
$manifest = [ordered]@{
    variant       = $variant
    generatedFrom = $skillName
    version       = "$date+$setHash"
    files         = $ordered
}

$out = Join-Path $scaffold ".bootstrap-manifest.json"
$manifest | ConvertTo-Json -Depth 5 | Set-Content $out -Encoding UTF8
Write-Host "Manifest generado: $out ($($files.Count) archivos, version $date+$setHash)"
```

- [ ] **Step 2: Test — generar el manifest de la skill personal y validar**

Run:
```powershell
pwsh -File tools/gen-manifest.ps1 -SkillDir "skills/bootstrap-personal-project"
$m = Get-Content "skills/bootstrap-personal-project/assets/scaffold/.bootstrap-manifest.json" -Raw | ConvertFrom-Json
"variant: $($m.variant)"
"files count: $($m.files.PSObject.Properties.Count)"
"tiene .gitignore?: $([bool]($m.files.PSObject.Properties.Name -contains '.gitignore'))"
"tiene gitignore.txt? (debe ser False): $([bool]($m.files.PSObject.Properties.Name -contains 'gitignore.txt'))"
"se auto-excluye? (debe ser False): $([bool]($m.files.PSObject.Properties.Name -contains '.bootstrap-manifest.json'))"
"tiene review-loop?: $([bool]($m.files.PSObject.Properties.Name -contains '.agents/skills/review-loop/SKILL.md'))"
```
Expected: `variant: personal`; `files count: 45`; `.gitignore` True; `gitignore.txt` False; auto-exclusión False; review-loop True.

- [ ] **Step 3: Generar el manifest de la skill southpoint**

Run:
```powershell
pwsh -File tools/gen-manifest.ps1 -SkillDir "skills/bootstrap-southpoint-project"
$m = Get-Content "skills/bootstrap-southpoint-project/assets/scaffold/.bootstrap-manifest.json" -Raw | ConvertFrom-Json
"variant: $($m.variant) (debe ser southpoint)"; "files: $($m.files.PSObject.Properties.Count)"
```
Expected: `variant: southpoint`; `files: 45`.

- [ ] **Step 4: Commit**

```powershell
git add tools/gen-manifest.ps1 skills/bootstrap-personal-project/assets/scaffold/.bootstrap-manifest.json skills/bootstrap-southpoint-project/assets/scaffold/.bootstrap-manifest.json
git commit -m "feat(tools): gen-manifest.ps1 y manifests canonicos del scaffold"
```

---

## Task 2: Integrar la regeneración en `sync-skills.ps1`

**Files:**
- Modify: `tools/sync-skills.ps1`

- [ ] **Step 1: Agregar la regeneración del manifest antes de copiar**

En `tools/sync-skills.ps1`, después de la línea `$installed = Join-Path $env:USERPROFILE ".claude\skills"` e inmediatamente antes del `foreach`, insertar:

```powershell
# Regenerar el manifest canónico de cada skill bootstrap antes de deployar,
# para que el scaffold instalado siempre lleve hashes actualizados.
foreach ($bs in (Get-ChildItem $repoSkills -Directory | Where-Object Name -like "bootstrap-*-project")) {
    & (Join-Path $PSScriptRoot "gen-manifest.ps1") -SkillDir $bs.FullName
}
```

- [ ] **Step 2: Test — correr sync y verificar que el manifest se regenera y deploya**

Run:
```powershell
pwsh -File tools/sync-skills.ps1
Test-Path "$env:USERPROFILE/.claude/skills/bootstrap-personal-project/assets/scaffold/.bootstrap-manifest.json"
(Get-Content "$env:USERPROFILE/.claude/skills/bootstrap-personal-project/assets/scaffold/.bootstrap-manifest.json" -Raw | ConvertFrom-Json).files.PSObject.Properties.Count
```
Expected: salida `Deployada: ...`, `True`, y `45`.

- [ ] **Step 3: Commit** (incluye cualquier cambio de manifest por la regeneración)

```powershell
git add tools/sync-skills.ps1 skills/*/assets/scaffold/.bootstrap-manifest.json
git commit -m "feat(tools): sync-skills regenera los manifests antes de deployar"
```

---

## Task 3: `SKILL.md` bootstrap entrega el manifest + verificar gitignore

**Files:**
- Modify: `skills/bootstrap-personal-project/SKILL.md`
- Modify: `skills/bootstrap-southpoint-project/SKILL.md`

- [ ] **Step 1: Verificar que `gitignore.txt` no ignora el manifest**

Run:
```powershell
Select-String -Path skills/bootstrap-personal-project/assets/scaffold/gitignore.txt -Pattern "bootstrap-manifest"
```
Expected: **sin resultados** (no está ignorado). Si apareciera, sería un bug a corregir; no debería.

- [ ] **Step 2: Actualizar la línea "This delivers" en ambos `SKILL.md`**

En AMBOS `SKILL.md`, reemplazar:

```
This delivers: `CLAUDE.md`, `.gitignore`, `skills-lock.json`, `.agents/skills/` (10 skills — 9 synced via `skills-lock.json` + `review-loop`, bundled here), `.claude/commands/` (10 commands), `docs/ai-workflow/` (5 docs), `docs/agents/` (3 docs).
```

por:

```
This delivers: `CLAUDE.md`, `.gitignore`, `skills-lock.json`, `.bootstrap-manifest.json` (scaffold version manifest, used by `upgrade-bootstrap`), `.agents/skills/` (10 skills — 9 synced via `skills-lock.json` + `review-loop`, bundled here), `.claude/commands/` (10 commands), `docs/ai-workflow/` (5 docs), `docs/agents/` (3 docs).
```

- [ ] **Step 3: Verificar**

Run:
```powershell
Select-String -Path skills/bootstrap-personal-project/SKILL.md,skills/bootstrap-southpoint-project/SKILL.md -Pattern "scaffold version manifest" | ForEach-Object { $_.Filename }
```
Expected: los dos archivos listados.

- [ ] **Step 4: Commit**

```powershell
git add skills/bootstrap-personal-project/SKILL.md skills/bootstrap-southpoint-project/SKILL.md
git commit -m "docs(scaffold): el bootstrap entrega .bootstrap-manifest.json"
```

---

## Task 4: `compare-scaffold.ps1` (clasificación merge-base)

**Files:**
- Create: `skills/upgrade-bootstrap/scripts/compare-scaffold.ps1`

- [ ] **Step 1: Escribir `compare-scaffold.ps1`**

```powershell
# Clasifica los archivos del proyecto contra el scaffold canónico (merge-base de 3 hashes).
# Uso: pwsh -File compare-scaffold.ps1 -ProjectDir <ruta> -CanonicalScaffold <ruta a assets\scaffold instalado>
# Emite JSON a stdout: { hasProjectManifest, canonicalVersion, variant, missing[], outdated[], customized[], orphan[], uptodate[] }
param(
    [Parameter(Mandatory)][string]$ProjectDir,
    [Parameter(Mandatory)][string]$CanonicalScaffold
)
$ErrorActionPreference = "Stop"

function Get-Hash($path) { if (Test-Path $path) { (Get-FileHash $path -Algorithm SHA256).Hash.ToLower() } else { $null } }

$canonManifestPath = Join-Path $CanonicalScaffold ".bootstrap-manifest.json"
if (-not (Test-Path $canonManifestPath)) { throw "Scaffold canónico sin manifest: $canonManifestPath" }
$canon = Get-Content $canonManifestPath -Raw | ConvertFrom-Json

$projManifestPath = Join-Path $ProjectDir ".bootstrap-manifest.json"
$hasProjManifest = Test-Path $projManifestPath
$projBase = @{}
if ($hasProjManifest) {
    (Get-Content $projManifestPath -Raw | ConvertFrom-Json).files.PSObject.Properties | ForEach-Object { $projBase[$_.Name] = $_.Value }
}

$missing = @(); $outdated = @(); $customized = @(); $uptodate = @()
foreach ($p in $canon.files.PSObject.Properties) {
    $rel = $p.Name; $canonHash = $p.Value
    $actual = Get-Hash (Join-Path $ProjectDir $rel)
    if ($null -eq $actual)        { $missing += $rel; continue }
    if ($actual -eq $canonHash)   { $uptodate += $rel; continue }
    if ($hasProjManifest -and $projBase.ContainsKey($rel)) {
        $base = $projBase[$rel]
        if ($actual -eq $base) { $outdated += $rel }                                   # no tocado; canónico avanzó
        else { $customized += [ordered]@{ file = $rel; threeWay = ($canonHash -ne $base) } }  # tocado
    } else {
        $customized += [ordered]@{ file = $rel; threeWay = $true }                      # sin base: diferente, decide el usuario
    }
}

# Huérfanos: solo determinables con manifest del proyecto (sabemos qué pertenecía al scaffold).
$orphan = @()
if ($hasProjManifest) {
    $canonNames = $canon.files.PSObject.Properties.Name
    foreach ($k in $projBase.Keys) {
        if (($canonNames -notcontains $k) -and (Test-Path (Join-Path $ProjectDir $k))) { $orphan += $k }
    }
}

[ordered]@{
    hasProjectManifest = $hasProjManifest
    canonicalVersion   = $canon.version
    variant            = $canon.variant
    missing            = $missing
    outdated           = $outdated
    customized         = $customized
    orphan             = $orphan
    uptodate           = $uptodate
} | ConvertTo-Json -Depth 6
```

- [ ] **Step 2: Test — fixture con manifest (los 4 casos clave)**

Crear y correr este script de verificación temporal (`$env:TEMP/cmp-test.ps1`) y ejecutarlo:

```powershell
$ErrorActionPreference = "Stop"
$root = Join-Path $env:TEMP ("cmp-" + [guid]::NewGuid().ToString("N").Substring(0,8))
$canon = Join-Path $root "canon"; $proj = Join-Path $root "proj"
New-Item -ItemType Directory -Force $canon,$proj | Out-Null

# Scaffold canónico: 4 archivos
Set-Content "$canon/keep.md"      "v2-content"   -NoNewline   # estará al día en el proyecto
Set-Content "$canon/outdated.md"  "v2-content"   -NoNewline   # proyecto lo tiene en v1 sin tocar
Set-Content "$canon/custom.md"    "v2-content"   -NoNewline   # proyecto lo tocó
Set-Content "$canon/new.md"       "v2-content"   -NoNewline   # falta en el proyecto
# Manifest canónico
$ch = {param($f) (Get-FileHash "$canon/$f" -Algorithm SHA256).Hash.ToLower()}
@{ variant="personal"; generatedFrom="bootstrap-personal-project"; version="2026-06-10+aaaaaaa"; files=[ordered]@{
    "keep.md"=(& $ch keep.md); "outdated.md"=(& $ch outdated.md); "custom.md"=(& $ch custom.md); "new.md"=(& $ch new.md)
}} | ConvertTo-Json -Depth 5 | Set-Content "$canon/.bootstrap-manifest.json" -Encoding UTF8

# Proyecto: keep al día (v2), outdated en v1, custom tocado, new ausente, y un orphan
Set-Content "$proj/keep.md"     "v2-content" -NoNewline
Set-Content "$proj/outdated.md" "v1-content" -NoNewline
Set-Content "$proj/custom.md"   "mi-cambio"  -NoNewline
Set-Content "$proj/orphan.md"   "viejo"      -NoNewline
# Manifest del proyecto: base = v1 para outdated/custom/keep/orphan
$ph = {param($p,$c) (Get-FileHash $p -Algorithm SHA256).Hash.ToLower()}
@{ variant="personal"; generatedFrom="bootstrap-personal-project"; version="2026-01-01+0000000"; files=[ordered]@{
    "keep.md"=(& $ch keep.md);                                   # base ya en v2
    "outdated.md"=((Get-FileHash "$proj/outdated.md" -Algorithm SHA256).Hash.ToLower());  # base=v1=actual
    "custom.md"="0000000000000000000000000000000000000000000000000000000000000000";        # base distinta del actual -> personalizado
    "orphan.md"="1111111111111111111111111111111111111111111111111111111111111111"
}} | ConvertTo-Json -Depth 5 | Set-Content "$proj/.bootstrap-manifest.json" -Encoding UTF8

$out = pwsh -File "skills/upgrade-bootstrap/scripts/compare-scaffold.ps1" -ProjectDir $proj -CanonicalScaffold $canon | ConvertFrom-Json
"missing (esperado new.md):        $($out.missing -join ',')"
"outdated (esperado outdated.md):  $($out.outdated -join ',')"
"customized (esperado custom.md):  $(($out.customized | ForEach-Object { $_.file }) -join ',')"
"uptodate (esperado keep.md):      $($out.uptodate -join ',')"
"orphan (esperado orphan.md):      $($out.orphan -join ',')"
Remove-Item $root -Recurse -Force
```
Expected:
```
missing (esperado new.md):        new.md
outdated (esperado outdated.md):  outdated.md
customized (esperado custom.md):  custom.md
uptodate (esperado keep.md):      keep.md
orphan (esperado orphan.md):      orphan.md
```

- [ ] **Step 3: Test — fixture legacy (sin manifest del proyecto)**

Agregar al final del script de verificación (antes del `Remove-Item`) un segundo proyecto sin manifest, o correr aparte:

```powershell
$proj2 = Join-Path $env:TEMP ("cmp2-" + [guid]::NewGuid().ToString("N").Substring(0,8))
New-Item -ItemType Directory -Force $proj2 | Out-Null
# reusar el mismo $canon del test anterior (regenerarlo si hace falta); aquí asumimos uno con keep.md y new.md
Set-Content "$proj2/keep.md" "v2-content" -NoNewline       # igual al canónico -> uptodate
Set-Content "$proj2/custom.md" "algo-distinto" -NoNewline  # difiere -> customized (threeWay=true), sin base
# (sin .bootstrap-manifest.json)
$o2 = pwsh -File "skills/upgrade-bootstrap/scripts/compare-scaffold.ps1" -ProjectDir $proj2 -CanonicalScaffold $canon | ConvertFrom-Json
"hasProjectManifest (esperado False): $($o2.hasProjectManifest)"
"missing incluye new.md/outdated.md (faltan): $($o2.missing -join ',')"
"customized incluye custom.md: $(($o2.customized | ForEach-Object { $_.file }) -join ',')"
"orphan vacío en legacy (esperado): '$($o2.orphan -join ',')'"
Remove-Item $proj2 -Recurse -Force
```
Expected: `hasProjectManifest` False; `missing` incluye los canónicos ausentes; `custom.md` en customized; `orphan` vacío.

- [ ] **Step 4: Commit**

```powershell
git add skills/upgrade-bootstrap/scripts/compare-scaffold.ps1
git commit -m "feat(upgrade-bootstrap): compare-scaffold.ps1 (clasificacion merge-base)"
```

---

## Task 5: `reseal-manifest.ps1`

**Files:**
- Create: `skills/upgrade-bootstrap/scripts/reseal-manifest.ps1`

- [ ] **Step 1: Escribir `reseal-manifest.ps1`**

```powershell
# Re-sella el manifest del proyecto tras un upgrade.
# Uso: pwsh -File reseal-manifest.ps1 -ProjectDir <ruta> -CanonicalScaffold <ruta a assets\scaffold instalado>
# Regla de base por archivo:
#   actual == canónico            -> base = canónico (reconciliado)
#   actual != canónico, hay base  -> base = base previa (personalizado: sigue detectable)
#   actual != canónico, sin base  -> base = actual (legacy: sembrar)
#   archivo ausente en proyecto   -> no se registra (el usuario lo saltó)
param(
    [Parameter(Mandatory)][string]$ProjectDir,
    [Parameter(Mandatory)][string]$CanonicalScaffold
)
$ErrorActionPreference = "Stop"
function Get-Hash($path) { if (Test-Path $path) { (Get-FileHash $path -Algorithm SHA256).Hash.ToLower() } else { $null } }

$canon = Get-Content (Join-Path $CanonicalScaffold ".bootstrap-manifest.json") -Raw | ConvertFrom-Json
$projManifestPath = Join-Path $ProjectDir ".bootstrap-manifest.json"
$oldBase = @{}
if (Test-Path $projManifestPath) {
    (Get-Content $projManifestPath -Raw | ConvertFrom-Json).files.PSObject.Properties | ForEach-Object { $oldBase[$_.Name] = $_.Value }
}

$files = [ordered]@{}
foreach ($p in ($canon.files.PSObject.Properties | Sort-Object Name)) {
    $rel = $p.Name; $canonHash = $p.Value
    $actual = Get-Hash (Join-Path $ProjectDir $rel)
    if ($null -eq $actual) { continue }
    if ($actual -eq $canonHash)        { $files[$rel] = $canonHash }
    elseif ($oldBase.ContainsKey($rel)) { $files[$rel] = $oldBase[$rel] }
    else                                { $files[$rel] = $actual }
}

$manifest = [ordered]@{
    variant       = $canon.variant
    generatedFrom = $canon.generatedFrom
    version       = $canon.version
    files         = $files
}
$manifest | ConvertTo-Json -Depth 5 | Set-Content $projManifestPath -Encoding UTF8
Write-Host "Manifest del proyecto re-sellado: version $($canon.version), $($files.Count) archivos"
```

- [ ] **Step 2: Test — fixture de re-sellado**

```powershell
$ErrorActionPreference = "Stop"
$root = Join-Path $env:TEMP ("rsl-" + [guid]::NewGuid().ToString("N").Substring(0,8))
$canon = Join-Path $root "canon"; $proj = Join-Path $root "proj"
New-Item -ItemType Directory -Force $canon,$proj | Out-Null
Set-Content "$canon/a.md" "canon" -NoNewline      # proyecto lo reconcilió (igual)
Set-Content "$canon/b.md" "canon" -NoNewline      # proyecto lo dejó personalizado
$ch = {param($f) (Get-FileHash "$canon/$f" -Algorithm SHA256).Hash.ToLower()}
@{ variant="personal"; generatedFrom="bootstrap-personal-project"; version="2026-06-10+bbbbbbb"; files=[ordered]@{
    "a.md"=(& $ch a.md); "b.md"=(& $ch b.md) }} | ConvertTo-Json -Depth 5 | Set-Content "$canon/.bootstrap-manifest.json" -Encoding UTF8
Set-Content "$proj/a.md" "canon" -NoNewline        # == canónico
Set-Content "$proj/b.md" "mio"   -NoNewline         # personalizado
@{ variant="personal"; generatedFrom="bootstrap-personal-project"; version="2026-01-01+0000000"; files=[ordered]@{
    "b.md"="0000000000000000000000000000000000000000000000000000000000000000" }} | ConvertTo-Json -Depth 5 | Set-Content "$proj/.bootstrap-manifest.json" -Encoding UTF8

pwsh -File "skills/upgrade-bootstrap/scripts/reseal-manifest.ps1" -ProjectDir $proj -CanonicalScaffold $canon
$m = Get-Content "$proj/.bootstrap-manifest.json" -Raw | ConvertFrom-Json
"version (esperado 2026-06-10+bbbbbbb): $($m.version)"
"a.md base == canónico (esperado True): $($m.files.'a.md' -eq (& $ch a.md))"
"b.md base preservada vieja (esperado True): $($m.files.'b.md' -eq '0000000000000000000000000000000000000000000000000000000000000000')"
Remove-Item $root -Recurse -Force
```
Expected: version `2026-06-10+bbbbbbb`; `a.md` base == canónico True; `b.md` base preservada True.

- [ ] **Step 3: Commit**

```powershell
git add skills/upgrade-bootstrap/scripts/reseal-manifest.ps1
git commit -m "feat(upgrade-bootstrap): reseal-manifest.ps1 (re-sella base del proyecto)"
```

---

## Task 6: La skill `upgrade-bootstrap/SKILL.md`

**Files:**
- Create: `skills/upgrade-bootstrap/SKILL.md`

- [ ] **Step 1: Escribir `SKILL.md`**

```markdown
---
name: upgrade-bootstrap
description: Use to update a project that was already bootstrapped with bootstrap-personal-project or bootstrap-southpoint-project when the scaffold has since changed (new files, edited rules, new skills like review-loop). Detects what is missing, outdated, or customized using the project's .bootstrap-manifest.json (with a fallback for legacy projects without one), and applies the delta with your approval — never overwriting your customizations. Trigger whenever the user wants to "actualizar el bootstrap", "traer los cambios nuevos del scaffold", "sync the workflow scaffolding", or mentions a bootstrapped project being on an older version.
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

- **missing** → copy from the canonical scaffold into the project (same relative path). Special case: the canonical key `.gitignore` is sourced from `gitignore.txt` in the scaffold.
- **outdated** → overwrite the project file with the canonical version.
- **customized / different** → show the diff (canonical vs project). Offer, per file: skip (keep yours), or an assisted merge where you help integrate the new bits into the user's version. Never overwrite without per-file consent.
- **orphan** → list only; do not delete. Mention the user can remove them by hand.

When copying `.gitignore`, read from `<canonical scaffold>/gitignore.txt`.

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
```

- [ ] **Step 2: Verificar estructura de la skill**

Run:
```powershell
Test-Path "skills/upgrade-bootstrap/SKILL.md","skills/upgrade-bootstrap/scripts/compare-scaffold.ps1","skills/upgrade-bootstrap/scripts/reseal-manifest.ps1"
```
Expected: tres `True`.

- [ ] **Step 3: Commit**

```powershell
git add skills/upgrade-bootstrap/SKILL.md
git commit -m "feat(upgrade-bootstrap): SKILL.md que orquesta deteccion y upgrade"
```

---

## Task 7: Documentar en `CLAUDE.md` del repo y `docs/TESTING.md`

**Files:**
- Modify: `CLAUDE.md` (raíz del repo)
- Modify: `docs/TESTING.md`

- [ ] **Step 1: Leer las secciones a tocar**

Run: `Get-Content CLAUDE.md | Select-Object -First 20`
(Para ubicar la lista de skills del repo y el flujo de trabajo; insertar de forma coherente con el estilo existente.)

- [ ] **Step 2: Agregar `upgrade-bootstrap` a la descripción del repo en `CLAUDE.md`**

En `CLAUDE.md` (raíz), en la lista inicial de skills del repo, después de la línea de `bootstrap-personal-project`, agregar:

```
- `skills/upgrade-bootstrap/` — actualiza proyectos ya bootstrapeados al scaffold actual (merge-base por `.bootstrap-manifest.json`)
```

- [ ] **Step 3: Documentar el manifest en el flujo de trabajo de `CLAUDE.md`**

En `CLAUDE.md` (raíz), en la sección "Hard rules", agregar al final:

```
- El `.bootstrap-manifest.json` del scaffold es **generado**, no se edita a mano. `tools/sync-skills.ps1` lo regenera antes de deployar; si editás el scaffold y commiteás sin correr sync, regeneralo con `tools/gen-manifest.ps1` y commitealo, para que `upgrade-bootstrap` compare contra hashes correctos.
```

- [ ] **Step 4: Actualizar `docs/TESTING.md`**

En `docs/TESTING.md`, en la línea de assertion "Scaffold completo", agregar `.bootstrap-manifest.json` a la lista. Reemplazar:

```
`skills-lock.json`, README, CONTEXT.md stub, `docs/adr/`.
```

por:

```
`skills-lock.json`, `.bootstrap-manifest.json`, README, CONTEXT.md stub, `docs/adr/`.
```

- [ ] **Step 5: Verificar**

Run:
```powershell
Select-String -Path CLAUDE.md -Pattern "upgrade-bootstrap","manifest.*generado" | ForEach-Object { $_.Line.Trim() }
Select-String -Path docs/TESTING.md -Pattern "bootstrap-manifest" | ForEach-Object { $_.Line.Trim() }
```
Expected: las líneas nuevas presentes.

- [ ] **Step 6: Commit**

```powershell
git add CLAUDE.md docs/TESTING.md
git commit -m "docs: documentar upgrade-bootstrap y el manifest en el flujo del repo"
```

---

## Task 8: Evals de la skill + deploy + merge

**Files:** ninguno (testing + deploy).

- [ ] **Step 1: Eval funcional — proyecto legacy (adopción)**

Crear un proyecto de prueba bootstrapeado con la versión SIN manifest (simular legacy borrando el manifest), correr `upgrade-bootstrap` manualmente y verificar:

```powershell
$proj = Join-Path $env:TEMP ("up-legacy-" + [guid]::NewGuid().ToString("N").Substring(0,8))
$canon = "$env:USERPROFILE/.claude/skills/bootstrap-personal-project/assets/scaffold"
# Sembrar el proyecto = copia del scaffold actual PERO sin review-loop y sin manifest (simula versión vieja)
New-Item -ItemType Directory -Force $proj | Out-Null
Get-ChildItem $canon -Force | Where-Object Name -ne "gitignore.txt" | ForEach-Object { Copy-Item $_.FullName (Join-Path $proj $_.Name) -Recurse -Force }
Copy-Item "$canon/gitignore.txt" (Join-Path $proj ".gitignore")
Remove-Item (Join-Path $proj ".bootstrap-manifest.json") -Force
Remove-Item (Join-Path $proj ".agents/skills/review-loop") -Recurse -Force
Remove-Item (Join-Path $proj ".claude/commands/review-loop.md") -Force
# Comparar
$o = pwsh -File "skills/upgrade-bootstrap/scripts/compare-scaffold.ps1" -ProjectDir $proj -CanonicalScaffold $canon | ConvertFrom-Json
"hasProjectManifest (esperado False): $($o.hasProjectManifest)"
"missing incluye review-loop (esperado): $(($o.missing | Where-Object { $_ -like '*review-loop*' }) -join ', ')"
Remove-Item $proj -Recurse -Force
```
Expected: `hasProjectManifest` False; `missing` incluye `.agents/skills/review-loop/SKILL.md` y `.claude/commands/review-loop.md`.

- [ ] **Step 2: Eval funcional — proyecto al día (nada que hacer)**

```powershell
$proj = Join-Path $env:TEMP ("up-current-" + [guid]::NewGuid().ToString("N").Substring(0,8))
$canon = "$env:USERPROFILE/.claude/skills/bootstrap-personal-project/assets/scaffold"
New-Item -ItemType Directory -Force $proj | Out-Null
Get-ChildItem $canon -Force | Where-Object Name -ne "gitignore.txt" | ForEach-Object { Copy-Item $_.FullName (Join-Path $proj $_.Name) -Recurse -Force }
Copy-Item "$canon/gitignore.txt" (Join-Path $proj ".gitignore")
$o = pwsh -File "skills/upgrade-bootstrap/scripts/compare-scaffold.ps1" -ProjectDir $proj -CanonicalScaffold $canon | ConvertFrom-Json
"missing (esperado vacío): '$($o.missing -join ',')'"
"outdated (esperado vacío): '$($o.outdated -join ',')'"
"customized (esperado vacío): '$(($o.customized | ForEach-Object { $_.file }) -join ',')'"
"uptodate count (esperado 45): $($o.uptodate.Count)"
Remove-Item $proj -Recurse -Force
```
Expected: missing/outdated/customized vacíos; `uptodate count: 45`.

- [ ] **Step 3: (Opcional) Evals con skill-creator**

Si se desea cobertura de triggering/cualitativa, invocar `skill-creator:skill-creator` con los casos del spec (manifest+desactualizado, manifest+personalizado, legacy, al día) y la skill `upgrade-bootstrap`. Borrar el workspace al terminar (regla del repo).

- [ ] **Step 4: Deploy + merge** (requiere confirmación del usuario — efecto en instalación activa)

```powershell
pwsh -File tools/sync-skills.ps1
Test-Path "$env:USERPROFILE/.claude/skills/upgrade-bootstrap/SKILL.md"
git checkout main; git merge --ff-only feat/upgrade-bootstrap; git branch -d feat/upgrade-bootstrap
```
Expected: `upgrade-bootstrap` deployada (`True`), merge fast-forward, branch borrada.

---

## Self-review notes

- El `gen-manifest.ps1` mapea `gitignore.txt` → `.gitignore` y se auto-excluye; la skill al copiar `.gitignore` lee de `gitignore.txt`. Consistente en gen/compare/reseal/SKILL.
- Conteos 10/10 de skills bootstrap NO cambian (el manifest es archivo de raíz).
- `compare-scaffold.ps1` y `reseal-manifest.ps1` comparten la convención de claves de `files` (rutas de destino).
