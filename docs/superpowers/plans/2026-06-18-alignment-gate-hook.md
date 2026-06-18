# Alignment Gate Hook — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Agregar un hook `PreToolUse` (`alignment-gate.ps1`) al scaffold que frena el primer `Edit`/`Write` de código de la sesión y le ofrece al usuario alinear (grill) antes de codear, cerrando la asimetría con el `review-loop-trigger` (paso 7) que ya es enforcement duro.

**Architecture:** Speed bump por sesión. El hook lee el evento `PreToolUse` por stdin; si el archivo es no-código (allowlist) pasa libre; si es código y la sesión aún no fue avisada (dedup por `session_id` en `.git/alignment-gate-state.json`), responde `permissionDecision: "deny"` con un mensaje que instruye al agente a **ofrecer** el grill (nunca auto-ejecutarlo) y marca la sesión, de modo que el reintento pasa. Espejado byte-idéntico en ambas skills de bootstrap.

**Tech Stack:** PowerShell 7 (`pwsh`), hooks de Claude Code (`PreToolUse`), JSON. Tests: runner sin Pester (patrón de `tests/review-loop-trigger.tests.ps1`).

## Global Constraints

- **Espejado obligatorio:** todo cambio en `bootstrap-personal-project` se replica byte-idéntico en `bootstrap-southpoint-project` (hard rule del `CLAUDE.md` del repo). El hook y el bloque de `settings.json` son idénticos en ambos; solo difieren contenidos DOMO/identidad que NO toca este plan.
- **Contrato del hook PreToolUse (Claude Code v2.1+):** stdin trae `session_id`, `cwd`, `tool_name`, `tool_input`. Para `Edit`/`Write` el path está en `tool_input.file_path`; para `MultiEdit` está en cada `tool_input.edits[].file_path`. Para bloquear + inyectar razón: imprimir a stdout `{ "hookSpecificOutput": { "hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": "<texto>" } }` y `exit 0`.
- **Estado en `.git/`:** mismo patrón y ubicación que `review-loop-state.json` (resuelto vía `git rev-parse --git-dir`). Dedup por `session_id`.
- **`exit 0` silencioso** en todo camino que no aplica (deja pasar la herramienta), igual que `review-loop-trigger.ps1`.
- **El manifest es generado:** no se edita a mano; se regenera con `tools/gen-manifest.ps1` (o vía `tools/sync-skills.ps1`).
- **No usar wildcard `scaffold\*`** en copias (bug de duplicados anidados). No aplica directamente acá pero respetarlo si se toca el flujo de copia.
- **Identidad de commits en este repo:** `MartinDele703 <martin.deleon703@gmail.com>` (config local, no global).

**Paths base (se repiten en todo el plan):**
- Scaffold personal: `skills/bootstrap-personal-project/assets/scaffold/`
- Scaffold southpoint: `skills/bootstrap-southpoint-project/assets/scaffold/`

---

### Task 1: Hook `alignment-gate.ps1` (scaffold personal) + test unitario

Construye el corazón: el hook y su test runner. Se implementa primero en el scaffold personal; el espejado a southpoint es la Task 2.

**Files:**
- Create: `tests/alignment-gate.tests.ps1`
- Create: `skills/bootstrap-personal-project/assets/scaffold/.claude/hooks/alignment-gate.ps1`

**Interfaces:**
- Consumes: evento `PreToolUse` por stdin (ver Global Constraints).
- Produces: el hook `alignment-gate.ps1` (invocado como `pwsh -NoProfile -File <hook>`, lee stdin, emite JSON a stdout o nada). El test `tests/alignment-gate.tests.ps1` imprime `TODOS LOS TESTS PASARON` / `N test(s) FALLARON` y setea exit code acorde.

- [ ] **Step 1: Escribir el test que falla**

Crear `tests/alignment-gate.tests.ps1`. La función `Fire` invoca SOLO el hook del scaffold personal (`$hookP`); la assertion de espejado contra southpoint (`$hookS`) se agrega en la Task 2 (acá ese archivo todavía no existe, así que el último Assert queda comentado con un TODO que la Task 2 destapa).

```powershell
# tests/alignment-gate.tests.ps1 — runner sin Pester. Correr: pwsh -NoProfile -File tests/alignment-gate.tests.ps1
# Fixtures determinísticos (repos git temporales) para el hook alignment-gate (PreToolUse).
# El hook resuelve el repo desde cwd; cwd y file_path deben ser paths Windows reales (como los pasa Claude Code).
$ErrorActionPreference = "Stop"
$repo  = Split-Path $PSScriptRoot -Parent
$hookP = Join-Path $repo "skills/bootstrap-personal-project/assets/scaffold/.claude/hooks/alignment-gate.ps1"
$hookS = Join-Path $repo "skills/bootstrap-southpoint-project/assets/scaffold/.claude/hooks/alignment-gate.ps1"
$script:failures = 0

function Assert($cond, $msg) {
  if ($cond) { Write-Host "ok:   $msg" } else { Write-Host "FAIL: $msg"; $script:failures++ }
}
function New-Repo {
  $t = Join-Path ([IO.Path]::GetTempPath()) ("ag-test-" + [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $t | Out-Null
  git -C $t init -q -b master; git -C $t config user.email a@b.c; git -C $t config user.name a
  git -C $t commit --allow-empty -q -m base
  return $t
}
# Invoca el hook personal con un evento PreToolUse.
function Fire($repoDir, $tool, $file, $sid) {
  $ti = if ($tool -eq 'MultiEdit') { @{ edits = @(@{ file_path = $file }) } } else { @{ file_path = $file } }
  $evt = @{ session_id = $sid; cwd = $repoDir; tool_name = $tool; tool_input = $ti } | ConvertTo-Json -Compress -Depth 6
  return ($evt | & pwsh -NoProfile -File $hookP)
}

# 1. Código en sesión nueva -> deny + ofrece grill
$t = New-Repo
$o = Fire $t 'Write' (Join-Path $t 'src/app.py') 's1'
Assert (($o -match 'deny') -and ($o -match 'grill')) "Write de código en sesión nueva: deny + ofrece grill"
Remove-Item -Recurse -Force $t

# 2. Archivo .md pasa libre (no emite, no marca)
$t = New-Repo
$o = Fire $t 'Write' (Join-Path $t 'docs/nota.md') 's1'
Assert ([string]::IsNullOrEmpty($o)) "archivo .md no dispara (pasa libre)"
Remove-Item -Recurse -Force $t

# 3. CLAUDE.md pasa libre
$t = New-Repo
$o = Fire $t 'Edit' (Join-Path $t 'CLAUDE.md') 's1'
Assert ([string]::IsNullOrEmpty($o)) "CLAUDE.md no dispara"
Remove-Item -Recurse -Force $t

# 4. .scratch/ pasa libre (clave: no romper la escritura del PRD)
$t = New-Repo
$o = Fire $t 'Write' (Join-Path $t '.scratch/feat/PRD.md') 's1'
Assert ([string]::IsNullOrEmpty($o)) ".scratch/ no dispara"
Remove-Item -Recurse -Force $t

# 5. Dedup: segundo Edit de código en la misma sesión pasa libre
$t = New-Repo
Fire $t 'Write' (Join-Path $t 'src/a.py') 'sDup' | Out-Null
$o = Fire $t 'Write' (Join-Path $t 'src/b.py') 'sDup'
Assert ([string]::IsNullOrEmpty($o)) "dedup: segundo Edit de código en la misma sesión no dispara"
Remove-Item -Recurse -Force $t

# 6. Otra sesión vuelve a disparar
$t = New-Repo
Fire $t 'Write' (Join-Path $t 'src/a.py') 'sA' | Out-Null
$o = Fire $t 'Write' (Join-Path $t 'src/a.py') 'sB'
Assert ($o -match 'deny') "otra sesión vuelve a disparar"
Remove-Item -Recurse -Force $t

# 7. MultiEdit de código dispara (file_path dentro de edits[])
$t = New-Repo
$o = Fire $t 'MultiEdit' (Join-Path $t 'src/c.ts') 's1'
Assert ($o -match 'deny') "MultiEdit de código dispara"
Remove-Item -Recurse -Force $t

# 8. Config (.json) pasa libre
$t = New-Repo
$o = Fire $t 'Write' (Join-Path $t 'tsconfig.json') 's1'
Assert ([string]::IsNullOrEmpty($o)) "archivo .json no dispara"
Remove-Item -Recurse -Force $t

# 9. Espejado: hook personal y southpoint byte-idénticos (DESTAPAR en Task 2)
# Assert ((Get-FileHash $hookP).Hash -eq (Get-FileHash $hookS).Hash) "alignment-gate.ps1 idéntico en ambos scaffolds"

if ($script:failures -gt 0) { Write-Host "$($script:failures) test(s) FALLARON"; exit 1 } else { Write-Host "TODOS LOS TESTS PASARON"; exit 0 }
```

- [ ] **Step 2: Correr el test para verificar que falla**

Run: `pwsh -NoProfile -File tests/alignment-gate.tests.ps1`
Expected: FALLA — el hook `alignment-gate.ps1` no existe, así que `Fire` no produce el `deny` esperado (varios `FAIL:` y exit 1).

- [ ] **Step 3: Escribir el hook**

Crear `skills/bootstrap-personal-project/assets/scaffold/.claude/hooks/alignment-gate.ps1`:

```powershell
# Hook PreToolUse (matcher Edit|Write|MultiEdit). Frena el PRIMER Edit/Write de CODIGO de la sesion
# y le ofrece al usuario alinear (grill) antes de codear. Speed bump: una sola vez por sesion
# (dedup por session_id en .git/alignment-gate-state.json). Los archivos de NO-codigo (docs, *.md,
# .scratch, .agents, .claude, configs, CONTEXT.md, CLAUDE.md, .gitignore) pasan SIEMPRE libres, asi
# alinear/documentar nunca se traba. Cualquier camino que no aplica termina en exit 0 silencioso.
$ErrorActionPreference = "SilentlyContinue"

# 1. Leer el evento del hook por stdin
$raw = [Console]::In.ReadToEnd()
if (-not $raw) { exit 0 }
try { $evt = $raw | ConvertFrom-Json } catch { exit 0 }

# 2. Juntar el/los file_path segun la tool (Edit/Write: tool_input.file_path; MultiEdit: edits[].file_path)
$paths = @()
if ($evt.tool_input.file_path) { $paths += [string]$evt.tool_input.file_path }
foreach ($e in @($evt.tool_input.edits)) { if ($e.file_path) { $paths += [string]$e.file_path } }
if ($paths.Count -eq 0) { exit 0 }

$cwd = if ($evt.cwd) { $evt.cwd } else { (Get-Location).Path }

# 3. Clasificar cada path: no-codigo (allowlist) vs codigo. Solo se frena si hay AL MENOS un path de codigo.
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
if (-not $hasCode) { exit 0 }   # todo no-codigo: pasa libre, sin marcar la sesion

# 4. Dedup por session_id (una sola vez por sesion). Estado junto a review-loop-state.json.
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
if ($state[$sid]) { exit 0 }     # ya avisado en esta sesion
$state[$sid] = $true
([pscustomobject]$state) | ConvertTo-Json | Set-Content -LiteralPath $statePath -Encoding UTF8

# 5. Frenar este Edit y OFRECER alinear (el hook NO ejecuta el grill; lo decide el usuario)
$msg = "Antes de escribir codigo en este trabajo: en esta sesion todavia no se hizo el alignment/grill " +
       "(paso 1 del workflow: Alignment/Grill -> PRD -> task planning; ver CLAUDE.md). No sigas codeando en " +
       "piloto automatico. Ofrecele al usuario: hacemos /grill-me o /grill-with-docs primero, o seguimos " +
       "porque es trivial / ya se alinearon para esto? Espera su decision: NO ejecutes el grill por tu cuenta. " +
       "Si el usuario dice que sigamos, reintenta el Edit y proceds (este aviso no se repite en esta sesion)."
@{ hookSpecificOutput = @{ hookEventName = "PreToolUse"; permissionDecision = "deny"; permissionDecisionReason = $msg } } |
    ConvertTo-Json -Depth 4 -Compress
exit 0
```

- [ ] **Step 4: Correr el test para verificar que pasa**

Run: `pwsh -NoProfile -File tests/alignment-gate.tests.ps1`
Expected: PASA — `TODOS LOS TESTS PASARON`, exit 0 (el Assert de espejado sigue comentado).

- [ ] **Step 5: Commit**

```bash
git add tests/alignment-gate.tests.ps1 "skills/bootstrap-personal-project/assets/scaffold/.claude/hooks/alignment-gate.ps1"
git -c user.name=MartinDele703 -c user.email=martin.deleon703@gmail.com commit -m "feat(hook): alignment-gate (PreToolUse) en scaffold personal + test"
```

---

### Task 2: Espejar el hook a southpoint + assertion de identidad

**Files:**
- Create: `skills/bootstrap-southpoint-project/assets/scaffold/.claude/hooks/alignment-gate.ps1`
- Modify: `tests/alignment-gate.tests.ps1` (destapar el Assert de espejado del Step 9)

**Interfaces:**
- Consumes: el hook personal de la Task 1 (fuente a copiar).
- Produces: el hook southpoint byte-idéntico; test que garantiza la identidad.

- [ ] **Step 1: Destapar el test de espejado (falla)**

En `tests/alignment-gate.tests.ps1`, reemplazar la línea comentada del Step 9 por la activa:

```powershell
# 9. Espejado: hook personal y southpoint byte-idénticos
Assert ((Get-FileHash $hookP).Hash -eq (Get-FileHash $hookS).Hash) "alignment-gate.ps1 idéntico en ambos scaffolds"
```

- [ ] **Step 2: Correr el test para verificar que falla**

Run: `pwsh -NoProfile -File tests/alignment-gate.tests.ps1`
Expected: FALLA en `alignment-gate.ps1 idéntico en ambos scaffolds` (el archivo southpoint no existe; `Get-FileHash` sobre path inexistente da error/hash distinto → exit 1).

- [ ] **Step 3: Copiar el hook a southpoint**

Copiar byte-a-byte el archivo de personal a southpoint:

```bash
cp "skills/bootstrap-personal-project/assets/scaffold/.claude/hooks/alignment-gate.ps1" "skills/bootstrap-southpoint-project/assets/scaffold/.claude/hooks/alignment-gate.ps1"
```

- [ ] **Step 4: Correr el test para verificar que pasa**

Run: `pwsh -NoProfile -File tests/alignment-gate.tests.ps1`
Expected: PASA — `TODOS LOS TESTS PASARON`, incluyendo la assertion de identidad.

- [ ] **Step 5: Commit**

```bash
git add "skills/bootstrap-southpoint-project/assets/scaffold/.claude/hooks/alignment-gate.ps1" tests/alignment-gate.tests.ps1
git -c user.name=MartinDele703 -c user.email=martin.deleon703@gmail.com commit -m "feat(hook): espejar alignment-gate a southpoint + assertion de identidad"
```

---

### Task 3: Registrar el `PreToolUse` en ambos `settings.json`

**Files:**
- Modify: `skills/bootstrap-personal-project/assets/scaffold/.claude/settings.json`
- Modify: `skills/bootstrap-southpoint-project/assets/scaffold/.claude/settings.json`
- Modify: `tests/alignment-gate.tests.ps1` (agregar test de que ambos `settings.json` declaran el hook y son JSON válido)

**Interfaces:**
- Consumes: el hook de Tasks 1-2.
- Produces: ambos `settings.json` con bloque `PreToolUse` (matcher `Edit|Write|MultiEdit`) además del `PostToolUse` existente.

- [ ] **Step 1: Escribir el test que falla**

Agregar antes del bloque final (`if ($script:failures ...)`) de `tests/alignment-gate.tests.ps1`:

```powershell
# 10. Ambos settings.json declaran el PreToolUse del alignment-gate y son JSON válido
foreach ($s in @(
    (Join-Path $repo "skills/bootstrap-personal-project/assets/scaffold/.claude/settings.json"),
    (Join-Path $repo "skills/bootstrap-southpoint-project/assets/scaffold/.claude/settings.json")
)) {
    $j = $null
    try { $j = Get-Content $s -Raw | ConvertFrom-Json } catch {}
    Assert ($null -ne $j) "settings.json es JSON válido: $s"
    Assert (($j.hooks.PreToolUse | ConvertTo-Json -Depth 8) -match 'alignment-gate') "settings.json declara el hook alignment-gate en PreToolUse: $s"
    Assert (($j.hooks.PostToolUse | ConvertTo-Json -Depth 8) -match 'review-loop-trigger') "settings.json conserva review-loop-trigger en PostToolUse: $s"
}
```

- [ ] **Step 2: Correr el test para verificar que falla**

Run: `pwsh -NoProfile -File tests/alignment-gate.tests.ps1`
Expected: FALLA en `settings.json declara el hook alignment-gate en PreToolUse` (todavía no está el bloque).

- [ ] **Step 3: Editar ambos `settings.json`**

Dejar cada archivo (idéntico en ambos scaffolds) así:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Edit|Write|MultiEdit",
        "hooks": [
          {
            "type": "command",
            "command": "pwsh -NoProfile -File \"${CLAUDE_PROJECT_DIR}/.claude/hooks/alignment-gate.ps1\""
          }
        ]
      }
    ],
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

- [ ] **Step 4: Correr el test para verificar que pasa**

Run: `pwsh -NoProfile -File tests/alignment-gate.tests.ps1`
Expected: PASA — `TODOS LOS TESTS PASARON`.

- [ ] **Step 5: Commit**

```bash
git add "skills/bootstrap-personal-project/assets/scaffold/.claude/settings.json" "skills/bootstrap-southpoint-project/assets/scaffold/.claude/settings.json" tests/alignment-gate.tests.ps1
git -c user.name=MartinDele703 -c user.email=martin.deleon703@gmail.com commit -m "feat(hook): registrar PreToolUse alignment-gate en ambos settings.json"
```

---

### Task 4: Generalizar `merge-settings.ps1` (upgrade-bootstrap) para integrar ambos hooks

El `merge-settings.ps1` actual está hardcodeado a `PostToolUse` + `review-loop-trigger`. Hay que generalizarlo para que `upgrade-bootstrap` también integre el `PreToolUse`/`alignment-gate` en proyectos legacy, sin pisar config previa y de forma idempotente.

**Files:**
- Modify: `skills/upgrade-bootstrap/scripts/merge-settings.ps1`
- Modify: `tests/review-loop-trigger.tests.ps1` (extender el bloque de merge para cubrir ambos hooks)

**Interfaces:**
- Consumes: `settings.json` canónico (ahora con `PreToolUse` + `PostToolUse`) y el `settings.json` del proyecto.
- Produces: `merge-settings.ps1` que integra TODA entrada de hook canónica ausente, en cualquier evento, deduplicando por la firma de comandos.

- [ ] **Step 1: Escribir el test que falla**

Reemplazar el bloque `# --- Merge de settings ...` de `tests/review-loop-trigger.tests.ps1` (líneas ~55-66) por esta versión, que verifica que el merge ahora trae AMBOS hooks y sigue siendo idempotente:

```powershell
# --- Merge de settings (proyecto con settings.json propio, p. ej. enabledPlugins) ---
$t = Join-Path ([IO.Path]::GetTempPath()) ("rlt-ms-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $t | Out-Null
$sp = Join-Path $t "settings.json"
'{ "enabledPlugins": { "domo-skills@martin-local": true } }' | Set-Content $sp -Encoding UTF8
& pwsh -NoProfile -File $ms -ProjectSettings $sp -CanonicalSettings $canon | Out-Null
$txt = Get-Content $sp -Raw
Assert (($txt -match "enabledPlugins") -and ($txt -match "review-loop-trigger")) "merge preserva config propia y agrega review-loop-trigger"
Assert ($txt -match "alignment-gate") "merge agrega tambien el hook alignment-gate (PreToolUse)"
& pwsh -NoProfile -File $ms -ProjectSettings $sp -CanonicalSettings $canon | Out-Null
$txt2 = Get-Content $sp -Raw
Assert ((([regex]::Matches($txt2, "review-loop-trigger")).Count -eq 1) -and (([regex]::Matches($txt2, "alignment-gate")).Count -eq 1)) "merge es idempotente (no duplica ningun hook)"
Remove-Item -Recurse -Force $t
```

- [ ] **Step 2: Correr el test para verificar que falla**

Run: `pwsh -NoProfile -File tests/review-loop-trigger.tests.ps1`
Expected: FALLA en `merge agrega tambien el hook alignment-gate` (el merge actual solo toca `PostToolUse`).

- [ ] **Step 3: Generalizar `merge-settings.ps1`**

Reemplazar el cuerpo del script (de la línea `try { $canon = ... }` en adelante; conservar el `param(...)`, el `$ErrorActionPreference` y el bloque inicial de "no existe → copiar canónico") por esta versión generalizada:

```powershell
try { $canon = Get-Content $CanonicalSettings -Raw | ConvertFrom-Json -AsHashtable }
catch { throw "settings.json canonico no es JSON valido: $CanonicalSettings" }
try { $proj  = Get-Content $ProjectSettings  -Raw | ConvertFrom-Json -AsHashtable }
catch { throw "settings.json del proyecto no es JSON valido: $ProjectSettings" }
if ($null -eq $proj) { $proj = @{} }
if (-not $proj.ContainsKey('hooks')) { $proj['hooks'] = @{} }
if ($null -eq $canon.hooks) { Write-Host "El settings.json canonico no tiene hooks: nada que hacer."; exit 0 }

# Firma de una entrada de hook: la concatenacion de los command de sus hooks.
function Get-Sig($entry) { (@($entry.hooks) | ForEach-Object { $_.command }) -join '|' }

$added = 0
foreach ($event in @($canon.hooks.Keys)) {
    if (-not $proj.hooks.ContainsKey($event)) { $proj.hooks[$event] = @() }
    $present = @($proj.hooks[$event]) | ForEach-Object { Get-Sig $_ }
    foreach ($entry in @($canon.hooks[$event])) {
        if ((Get-Sig $entry) -notin $present) {
            $proj.hooks[$event] = @($proj.hooks[$event]) + $entry
            $present += (Get-Sig $entry)
            $added++
        }
    }
}
if ($added -gt 0) {
    $proj | ConvertTo-Json -Depth 12 | Set-Content $ProjectSettings -Encoding UTF8
    Write-Host "Hooks integrados al settings.json del proyecto: $added entrada/s nueva/s."
} else {
    Write-Host "Todos los hooks canonicos ya presentes: nada que hacer (idempotente)."
}
exit 0
```

Actualizar también el comentario de cabecera del script (líneas 1-2) para que diga que integra **los hooks canónicos** (review-loop-trigger y alignment-gate), no solo el primero.

- [ ] **Step 4: Correr ambos test runners para verificar que pasan**

Run: `pwsh -NoProfile -File tests/review-loop-trigger.tests.ps1`
Expected: PASA — `TODOS LOS TESTS PASARON` (merge trae ambos hooks, idempotente).

Run: `pwsh -NoProfile -File tests/alignment-gate.tests.ps1`
Expected: PASA (regresión: no se rompió nada).

- [ ] **Step 5: Commit**

```bash
git add skills/upgrade-bootstrap/scripts/merge-settings.ps1 tests/review-loop-trigger.tests.ps1
git -c user.name=MartinDele703 -c user.email=martin.deleon703@gmail.com commit -m "feat(upgrade): merge-settings integra todos los hooks canonicos (incluye alignment-gate)"
```

---

### Task 5: Mención del hook en el `CLAUDE.md` template (ambos scaffolds)

**Files:**
- Modify: `skills/bootstrap-personal-project/assets/scaffold/CLAUDE.md` (sección `## Workflow State Machine`, tras la línea de "Recommended transitions")
- Modify: `skills/bootstrap-southpoint-project/assets/scaffold/CLAUDE.md` (misma sección)

**Interfaces:**
- Consumes: nada de código; documenta el enforcement determinístico del paso 1.
- Produces: una línea simétrica a la del `review-loop-trigger` (que cierra la sección de transiciones), reforzando el paso 1.

- [ ] **Step 1: Agregar la línea en el `CLAUDE.md` personal**

Justo después del bullet que arranca con "- After implementation, run `/review-loop` ..." (el que menciona el `review-loop-trigger` hook), agregar un bullet nuevo:

```markdown
- Before the first code edit of a session, the `alignment-gate` hook (`PreToolUse` on `Edit`/`Write`/`MultiEdit`) deterministically reinforces step 1: it blocks the first edit of a *code* file once per session and tells the agent to OFFER alignment (`/grill-me` or `/grill-with-docs`) before coding — it never runs the grill on its own, and non-code files (`*.md`, `docs/`, `.scratch/`, `.agents/`, `.claude/`, config) pass through untouched. If the work is trivial or already aligned, just retry the edit and proceed. This breaks the "fix→implement" autopilot that text rules alone do not stop.
```

- [ ] **Step 2: Replicar byte-idéntico en el `CLAUDE.md` southpoint**

Agregar exactamente el mismo bullet, en la misma posición, en `skills/bootstrap-southpoint-project/assets/scaffold/CLAUDE.md`.

- [ ] **Step 3: Verificar que ambos quedaron consistentes**

Run: `pwsh -NoProfile -Command "$p=Get-Content 'skills/bootstrap-personal-project/assets/scaffold/CLAUDE.md' -Raw; $s=Get-Content 'skills/bootstrap-southpoint-project/assets/scaffold/CLAUDE.md' -Raw; if (($p -match 'alignment-gate') -and ($s -match 'alignment-gate')) { 'OK ambos mencionan alignment-gate' } else { 'FALTA en alguno'; exit 1 }"`
Expected: `OK ambos mencionan alignment-gate`

- [ ] **Step 4: Commit**

```bash
git add "skills/bootstrap-personal-project/assets/scaffold/CLAUDE.md" "skills/bootstrap-southpoint-project/assets/scaffold/CLAUDE.md"
git -c user.name=MartinDele703 -c user.email=martin.deleon703@gmail.com commit -m "docs(scaffold): documentar alignment-gate hook en CLAUDE.md (ambos)"
```

---

### Task 6: Regenerar manifest, actualizar TESTING.md y deployar

Cierra el ciclo: el manifest generado debe incluir el nuevo hook, la doc de testing debe reflejar el nuevo runner y los conteos de upgrade, y la versión instalada en `~/.claude/skills/` debe quedar al día.

**Files:**
- Modify (generado): `skills/bootstrap-personal-project/assets/scaffold/.bootstrap-manifest.json` y el de southpoint (vía `tools/gen-manifest.ps1`)
- Modify: `docs/TESTING.md`

**Interfaces:**
- Consumes: todo lo anterior.
- Produces: manifest regenerado (incluye `alignment-gate.ps1`), TESTING.md actualizado, skills deployadas.

- [ ] **Step 1: Regenerar el manifest**

Run: `pwsh -NoProfile -File tools/gen-manifest.ps1`
Expected: regenera ambos `.bootstrap-manifest.json` sin error. Verificar que `alignment-gate.ps1` aparece en el manifest:

Run: `pwsh -NoProfile -Command "(Get-Content 'skills/bootstrap-personal-project/assets/scaffold/.bootstrap-manifest.json' -Raw) -match 'alignment-gate' | Out-Null; if ($Matches) {'OK manifest incluye alignment-gate'} else {'FALTA'; exit 1}"`
Expected: `OK manifest incluye alignment-gate`

- [ ] **Step 2: Correr los tests de upgrade-bootstrap y ajustar conteos en TESTING.md**

El nuevo hook agrega archivos al scaffold; los casos de `upgrade-bootstrap` en `docs/TESTING.md` que citan números absolutos ("uptodate == 47", "missing los 2 de review-loop") quedan desfasados. Correr los tests/fixtures de upgrade para obtener los números reales y actualizarlos.

Run: `pwsh -NoProfile -File tests/review-loop-trigger.tests.ps1` y los runners de upgrade si existen (ver `docs/TESTING.md` sección upgrade-bootstrap).
Luego editar `docs/TESTING.md`:
- En "Assertions clave", agregar `.claude/hooks/alignment-gate.ps1` a la lista de archivos del scaffold completo, junto a `review-loop-trigger.ps1`.
- En "Testeo del hook `review-loop-trigger` y del merge de settings": agregar una línea apuntando al nuevo runner `pwsh -NoProfile -File tests/alignment-gate.tests.ps1` y describir sus casos (deny en código sesión nueva, allowlist no-código pasa, dedup por sesión, MultiEdit, espejado idéntico).
- En "Testeo de `upgrade-bootstrap`", actualizar el conteo de "Al día" (era 47) al valor real tras regenerar el manifest, y notar que el caso legacy ahora detecta también `alignment-gate.ps1` como `missing`.

- [ ] **Step 3: Deployar a `~/.claude/skills/`**

Run: `pwsh -NoProfile -File tools/sync-skills.ps1`
Expected: copia repo → `~/.claude/skills/` (borra la versión instalada primero), regenera el manifest. Sin error.

- [ ] **Step 4: Smoke test del hook deployado**

Verificar que el hook instalado responde `deny` ante un archivo de código en sesión nueva:

Run:
```bash
pwsh -NoProfile -Command "$ti=@{file_path='C:/tmp/x/src/app.py'}; $evt=@{session_id='smoke1';cwd='C:/tmp/x';tool_name='Write';tool_input=$ti}|ConvertTo-Json -Compress; New-Item -ItemType Directory -Force C:/tmp/x | Out-Null; cd C:/tmp/x; git init -q 2>$null; $evt | & \"$env:USERPROFILE/.claude/skills/bootstrap-personal-project/assets/scaffold/.claude/hooks/alignment-gate.ps1\""
```
Expected: imprime un JSON con `"permissionDecision":"deny"`. (Limpiar `C:/tmp/x` después.)

- [ ] **Step 5: Commit**

```bash
git add docs/TESTING.md "skills/bootstrap-personal-project/assets/scaffold/.bootstrap-manifest.json" "skills/bootstrap-southpoint-project/assets/scaffold/.bootstrap-manifest.json"
git -c user.name=MartinDele703 -c user.email=martin.deleon703@gmail.com commit -m "chore(scaffold): regenerar manifest + documentar testeo del alignment-gate"
```

---

### Task 7: Eval end-to-end del bootstrap (skill-creator)

Verificación final con los evals canónicos mínimos del repo. No produce código nuevo; valida que el bootstrap aterriza el hook y el `settings.json` correctos sin romper nada.

**Files:**
- (Solo lectura del scaffold; workspaces de eval temporales que se borran al terminar.)

**Interfaces:**
- Consumes: las skills deployadas.
- Produces: evidencia de que el scaffold completo (con alignment-gate) aterriza bien.

- [ ] **Step 1: Eval directorio vacío (personal)**

Usar skill-creator con el caso canónico 2 de `docs/TESTING.md` ("Personal, directorio vacío"). Assertion adicional sobre el output: el proyecto generado contiene `.claude/hooks/alignment-gate.ps1` y su `.claude/settings.json` tiene el bloque `PreToolUse` con `alignment-gate` además del `PostToolUse` con `review-loop-trigger`.

- [ ] **Step 2: Eval archivos preexistentes (southpoint)**

Usar el caso canónico 3 ("Southpoint, archivos preexistentes"). Assertions: preexistentes intactos byte a byte; sin duplicados anidados (`.claude\.claude`, `.agents\.agents`); el hook `alignment-gate.ps1` y el `settings.json` con ambos bloques presentes.

- [ ] **Step 3: Limpiar y reportar**

Borrar los workspaces de eval (regla del repo). Reportar: archivos del scaffold confirmados, ambos hooks presentes, evals pasados/fallados con evidencia.

- [ ] **Step 4: Commit (si hubo ajustes de doc por el eval)**

```bash
git -c user.name=MartinDele703 -c user.email=martin.deleon703@gmail.com commit -am "test(scaffold): evals del bootstrap con alignment-gate OK"
```

---

## Notas de cierre

- **Fuera de alcance** (del spec): re-armado más fino del gate (por commit/feature) y detección semántica de trivialidad. No implementar acá.
- Tras mergear, los proyectos ya bootstrapeados reciben el gate corriendo `upgrade-bootstrap` (gracias a la Task 4). Proyectos como Forecasting App (local) y KBS (nunca bootstrapeado) lo recibirán al hacer upgrade/bootstrap.
