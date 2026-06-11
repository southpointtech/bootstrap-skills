# MCP por área en el bootstrap — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Que cada bootstrap pregunte qué herramientas MCP usa el proyecto y genere un `.mcp.json` commiteado con solo esos servers (secretos por `${VAR}`), dejando el user scope global vacío.

**Architecture:** Un script PowerShell determinístico (`gen-mcp-json.ps1`, uno por skill con su catálogo de área embebido) arma el `.mcp.json` a partir de las claves elegidas. El `SKILL.md` agrega un Step que muestra el menú (`AskUserQuestion` multiSelect) y corre el script. `.mcp.json` es archivo per-proyecto generado: no va al scaffold, no lo trackea el manifest, no lo toca `upgrade-bootstrap`.

**Tech Stack:** PowerShell 7 (pwsh), JSON, Claude Code MCP project scope (`.mcp.json` con expansión `${VAR}`).

**Spec:** `docs/superpowers/specs/2026-06-11-mcp-por-area-bootstrap-design.md`

**Convención de commits:** identidad local del repo — `git -c user.name="MartinDele703" -c user.email="martin.deleon703@gmail.com" commit ...`

---

### Task 1: Script personal — happy path (selección → `.mcp.json` + resumen)

**Files:**
- Create: `skills/bootstrap-personal-project/scripts/gen-mcp-json.ps1`
- Create: `tests/gen-mcp-json.tests.ps1`

- [ ] **Step 1: Escribir el test que falla**

Crear `tests/gen-mcp-json.tests.ps1`:

```powershell
# tests/gen-mcp-json.tests.ps1 — runner sin Pester. Correr: pwsh -NoProfile -File tests/gen-mcp-json.tests.ps1
$ErrorActionPreference = "Stop"
$repo       = Split-Path $PSScriptRoot -Parent
$personal   = Join-Path $repo "skills/bootstrap-personal-project/scripts/gen-mcp-json.ps1"
$southpoint = Join-Path $repo "skills/bootstrap-southpoint-project/scripts/gen-mcp-json.ps1"
$script:failures = 0

function Assert($cond, $msg) {
  if ($cond) { Write-Host "ok:   $msg" } else { Write-Host "FAIL: $msg"; $script:failures++ }
}
function NewTmp {
  $d = Join-Path ([IO.Path]::GetTempPath()) ("mcp-test-" + [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $d | Out-Null; $d
}
# Corre el script como subproceso; devuelve @{ exit; out } (out = stdout crudo)
function RunScript($scriptPath, [string[]]$ServerArgs, $ProjectDir, [switch]$Force) {
  $a = @("-NoProfile","-File",$scriptPath,"-ProjectDir",$ProjectDir)
  if ($ServerArgs.Count) { $a += @("-Servers"); $a += ($ServerArgs -join ",") }
  if ($Force) { $a += "-Force" }
  $out = & pwsh @a 2>$null
  @{ exit = $LASTEXITCODE; out = ($out | Out-String) }
}

# --- PERSONAL: happy path ---
$t = NewTmp
$r = RunScript $personal @("firebase","zoho-personal") $t
Assert ($r.exit -eq 0) "personal happy: exit 0"
$mcpPath = Join-Path $t ".mcp.json"
Assert (Test-Path $mcpPath) "personal happy: .mcp.json existe"
$doc = Get-Content $mcpPath -Raw | ConvertFrom-Json
Assert ($null -ne $doc.mcpServers.firebase) "personal happy: tiene firebase"
Assert ($null -ne $doc.mcpServers.'zoho-personal') "personal happy: tiene zoho-personal"
Assert ($null -eq $doc.mcpServers.github) "personal happy: NO tiene github"
Assert ($doc.mcpServers.'zoho-personal'.url -eq '${ZOHO_PERSONAL_MCP_URL}') "personal happy: url literal con env var"
$summary = $r.out | ConvertFrom-Json
Assert ($summary.written -eq $true) "personal happy: summary.written=true"
Assert ($summary.requiredEnvVars -contains "ZOHO_PERSONAL_MCP_URL") "personal happy: reporta ZOHO_PERSONAL_MCP_URL"

# --- PERSONAL: ninguna seleccion ---
$t2 = NewTmp
$r2 = RunScript $personal @() $t2
Assert ($r2.exit -eq 0) "personal none: exit 0"
Assert (-not (Test-Path (Join-Path $t2 ".mcp.json"))) "personal none: no crea archivo"
$s2 = $r2.out | ConvertFrom-Json
Assert ($s2.written -eq $false) "personal none: summary.written=false"

Write-Host ""
if ($script:failures -gt 0) { Write-Host "$($script:failures) test(s) FALLARON"; exit 1 } else { Write-Host "TODOS LOS TESTS PASARON"; exit 0 }
```

- [ ] **Step 2: Correr el test y verificar que falla**

Run: `pwsh -NoProfile -File tests/gen-mcp-json.tests.ps1`
Expected: FAIL — el script `gen-mcp-json.ps1` no existe todavía (exit ≠ 0, "FAIL: personal happy: ...").

- [ ] **Step 3: Implementar el script mínimo (happy path + none)**

Crear `skills/bootstrap-personal-project/scripts/gen-mcp-json.ps1`:

```powershell
# gen-mcp-json.ps1 — genera el .mcp.json del proyecto a partir del catalogo MCP del area (PERSONAL).
# Uso: pwsh -NoProfile -File gen-mcp-json.ps1 -ProjectDir <ruta> -Servers firebase,zoho-personal [-Force]
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$ProjectDir,
  [string[]]$Servers = @(),
  [switch]$Force
)
$ErrorActionPreference = "Stop"

$Catalog = [ordered]@{
  "firebase" = [ordered]@{
    config          = [ordered]@{ type = "stdio"; command = "npx"; args = @("-y","firebase-tools@latest","experimental:mcp") }
    requiredEnvVars = @()
    prereqs         = @("firebase login (una vez)")
  }
  "zoho-personal" = [ordered]@{
    config          = [ordered]@{ type = "http"; url = '${ZOHO_PERSONAL_MCP_URL}' }
    requiredEnvVars = @("ZOHO_PERSONAL_MCP_URL")
    prereqs         = @()
  }
  "github" = [ordered]@{
    config          = [ordered]@{ type = "stdio"; command = "docker"; args = @("run","-i","--rm","-e","GITHUB_PERSONAL_ACCESS_TOKEN","ghcr.io/github/github-mcp-server"); env = [ordered]@{ GITHUB_PERSONAL_ACCESS_TOKEN = '${GITHUB_PERSONAL_ACCESS_TOKEN}' } }
    requiredEnvVars = @("GITHUB_PERSONAL_ACCESS_TOKEN")
    prereqs         = @("Docker Desktop corriendo")
  }
}

if (-not (Test-Path $ProjectDir)) { throw "No existe ProjectDir: $ProjectDir" }

# -File puede entregar "-Servers a,b" como un unico string "a,b": separar por coma nosotros.
$selected = @($Servers | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" })

if ($selected.Count -eq 0) {
  [pscustomobject]@{ written = $false; reason = "no servers selected" } | ConvertTo-Json -Compress
  return
}

$target = Join-Path $ProjectDir ".mcp.json"

$servers = [ordered]@{}
$envVars = New-Object System.Collections.Generic.List[string]
$prereqs = New-Object System.Collections.Generic.List[string]
foreach ($key in $Catalog.Keys) {
  if ($selected -contains $key) {
    $servers[$key] = $Catalog[$key].config
    foreach ($e in $Catalog[$key].requiredEnvVars) { if (-not $envVars.Contains($e)) { $envVars.Add($e) } }
    foreach ($p in $Catalog[$key].prereqs)         { if (-not $prereqs.Contains($p)) { $prereqs.Add($p) } }
  }
}

$doc = [ordered]@{ mcpServers = $servers }
$doc | ConvertTo-Json -Depth 10 | Set-Content -Path $target -Encoding UTF8

[pscustomobject]@{
  written         = $true
  path            = $target
  servers         = @($servers.Keys)
  requiredEnvVars = @($envVars)
  prereqs         = @($prereqs)
} | ConvertTo-Json -Depth 5
```

- [ ] **Step 4: Correr el test y verificar que pasa**

Run: `pwsh -NoProfile -File tests/gen-mcp-json.tests.ps1`
Expected: PASS — "TODOS LOS TESTS PASARON", exit 0.

- [ ] **Step 5: Commit**

```bash
git add skills/bootstrap-personal-project/scripts/gen-mcp-json.ps1 tests/gen-mcp-json.tests.ps1
git -c user.name="MartinDele703" -c user.email="martin.deleon703@gmail.com" commit -m "feat(bootstrap): gen-mcp-json.ps1 personal (happy path + sin seleccion)"
```

---

### Task 2: Script personal — guards (clave inválida, no pisar sin -Force)

**Files:**
- Modify: `skills/bootstrap-personal-project/scripts/gen-mcp-json.ps1`
- Modify: `tests/gen-mcp-json.tests.ps1`

- [ ] **Step 1: Agregar los tests que fallan**

En `tests/gen-mcp-json.tests.ps1`, insertar ANTES del bloque final (`Write-Host ""` / resumen):

```powershell
# --- PERSONAL: clave invalida ---
$t3 = NewTmp
$r3 = RunScript $personal @("firebase","no-existe") $t3
Assert ($r3.exit -ne 0) "personal invalida: exit != 0 (error)"
Assert (-not (Test-Path (Join-Path $t3 ".mcp.json"))) "personal invalida: no escribe archivo"

# --- PERSONAL: no pisa sin -Force ---
$t4 = NewTmp
RunScript $personal @("firebase") $t4 | Out-Null
Set-Content (Join-Path $t4 ".mcp.json") -Value '{"mcpServers":{"SENTINEL":{}}}' -Encoding UTF8
$r4 = RunScript $personal @("zoho-personal") $t4
Assert ($r4.exit -ne 0) "personal no-force: exit != 0 (error)"
$keep = Get-Content (Join-Path $t4 ".mcp.json") -Raw | ConvertFrom-Json
Assert ($null -ne $keep.mcpServers.SENTINEL) "personal no-force: no piso el archivo existente"

# --- PERSONAL: -Force sobrescribe ---
$r5 = RunScript $personal @("zoho-personal") $t4 -Force
Assert ($r5.exit -eq 0) "personal force: exit 0"
$ovr = Get-Content (Join-Path $t4 ".mcp.json") -Raw | ConvertFrom-Json
Assert ($null -eq $ovr.mcpServers.SENTINEL) "personal force: reemplazo el contenido"
Assert ($null -ne $ovr.mcpServers.'zoho-personal') "personal force: nuevo server presente"
```

- [ ] **Step 2: Correr y verificar que falla**

Run: `pwsh -NoProfile -File tests/gen-mcp-json.tests.ps1`
Expected: FAIL — "personal invalida" y "personal no-force" fallan (el script todavía no valida claves ni chequea existencia: con `firebase,no-existe` escribe el `.mcp.json` con firebase, ignora la clave inválida y sale 0; sobre un archivo existente lo pisa).

- [ ] **Step 3: Agregar validación y guarda de existencia**

En `gen-mcp-json.ps1`, agregar la validación de claves JUSTO DESPUÉS de calcular `$selected` y la guarda de existencia JUSTO DESPUÉS de calcular `$target`:

Después de `$selected = @(...)` y antes del chequeo `if ($selected.Count -eq 0)`:

```powershell
foreach ($s in $selected) {
  if (-not $Catalog.Contains($s)) {
    throw "Server desconocido: '$s'. Validos: $(($Catalog.Keys) -join ', ')"
  }
}
```

Después de `$target = Join-Path $ProjectDir ".mcp.json"`:

```powershell
if ((Test-Path $target) -and -not $Force) {
  throw ".mcp.json ya existe en $ProjectDir (usa -Force para sobrescribir)"
}
```

- [ ] **Step 4: Correr y verificar que pasa**

Run: `pwsh -NoProfile -File tests/gen-mcp-json.tests.ps1`
Expected: PASS — "TODOS LOS TESTS PASARON".

- [ ] **Step 5: Commit**

```bash
git add skills/bootstrap-personal-project/scripts/gen-mcp-json.ps1 tests/gen-mcp-json.tests.ps1
git -c user.name="MartinDele703" -c user.email="martin.deleon703@gmail.com" commit -m "feat(bootstrap): gen-mcp-json valida claves y no pisa sin -Force"
```

---

### Task 3: Script southpoint — espejo con catálogo de área (domo + zoho-projects)

**Files:**
- Create: `skills/bootstrap-southpoint-project/scripts/gen-mcp-json.ps1`
- Modify: `tests/gen-mcp-json.tests.ps1`

- [ ] **Step 1: Agregar los tests que fallan**

En `tests/gen-mcp-json.tests.ps1`, insertar antes del bloque final:

```powershell
# --- SOUTHPOINT: domo + zoho-projects ---
$ts = NewTmp
$rs = RunScript $southpoint @("domo","zoho-projects") $ts
Assert ($rs.exit -eq 0) "southpoint happy: exit 0"
$sd = Get-Content (Join-Path $ts ".mcp.json") -Raw | ConvertFrom-Json
Assert ($null -ne $sd.mcpServers.domo) "southpoint happy: tiene domo"
Assert ($sd.mcpServers.domo.env.DOMO_DEVELOPER_TOKEN -eq '${DOMO_SOUTHPOINT_TOKEN}') "southpoint happy: token domo por env var"
Assert ($sd.mcpServers.domo.env.PYTHONPATH -eq '${DOMO_MCP_HOME}') "southpoint happy: PYTHONPATH domo por env var"
Assert ($sd.mcpServers.'zoho-projects'.url -eq '${ZOHO_SOUTHPOINT_MCP_URL}') "southpoint happy: url zoho southpoint"
$ss = $rs.out | ConvertFrom-Json
Assert ($ss.requiredEnvVars -contains "DOMO_SOUTHPOINT_TOKEN") "southpoint happy: reporta DOMO_SOUTHPOINT_TOKEN"
Assert ($ss.requiredEnvVars -contains "DOMO_MCP_HOME") "southpoint happy: reporta DOMO_MCP_HOME"

# --- SOUTHPOINT: zoho-personal NO existe en este catalogo ---
$ts2 = NewTmp
$rs2 = RunScript $southpoint @("zoho-personal") $ts2
Assert ($rs2.exit -ne 0) "southpoint: zoho-personal invalida en area southpoint"
```

- [ ] **Step 2: Correr y verificar que falla**

Run: `pwsh -NoProfile -File tests/gen-mcp-json.tests.ps1`
Expected: FAIL — el script southpoint no existe.

- [ ] **Step 3: Crear el script southpoint (lógica idéntica, catálogo de área)**

Crear `skills/bootstrap-southpoint-project/scripts/gen-mcp-json.ps1` idéntico al personal EXCEPTO el bloque `$Catalog` y el comentario de cabecera, que son:

```powershell
# gen-mcp-json.ps1 — genera el .mcp.json del proyecto a partir del catalogo MCP del area (SOUTHPOINT).
# Uso: pwsh -NoProfile -File gen-mcp-json.ps1 -ProjectDir <ruta> -Servers firebase,domo,zoho-projects [-Force]
```

```powershell
$Catalog = [ordered]@{
  "firebase" = [ordered]@{
    config          = [ordered]@{ type = "stdio"; command = "npx"; args = @("-y","firebase-tools@latest","experimental:mcp") }
    requiredEnvVars = @()
    prereqs         = @("firebase login (una vez)")
  }
  "domo" = [ordered]@{
    config          = [ordered]@{ type = "stdio"; command = '${DOMO_MCP_PYTHON:-python}'; args = @("-m","domo_mcp"); env = [ordered]@{ DOMO_DEVELOPER_TOKEN = '${DOMO_SOUTHPOINT_TOKEN}'; DOMO_HOST = "hssstaffing.domo.com"; PYTHONPATH = '${DOMO_MCP_HOME}'; PYTHONIOENCODING = "utf-8" } }
    requiredEnvVars = @("DOMO_SOUTHPOINT_TOKEN","DOMO_MCP_HOME")
    prereqs         = @("checkout local de domo-mcp-server")
  }
  "zoho-projects" = [ordered]@{
    config          = [ordered]@{ type = "http"; url = '${ZOHO_SOUTHPOINT_MCP_URL}' }
    requiredEnvVars = @("ZOHO_SOUTHPOINT_MCP_URL")
    prereqs         = @()
  }
  "github" = [ordered]@{
    config          = [ordered]@{ type = "stdio"; command = "docker"; args = @("run","-i","--rm","-e","GITHUB_PERSONAL_ACCESS_TOKEN","ghcr.io/github/github-mcp-server"); env = [ordered]@{ GITHUB_PERSONAL_ACCESS_TOKEN = '${GITHUB_PERSONAL_ACCESS_TOKEN}' } }
    requiredEnvVars = @("GITHUB_PERSONAL_ACCESS_TOKEN")
    prereqs         = @("Docker Desktop corriendo")
  }
}
```

El resto del archivo (param block, `Test-Path $ProjectDir`, `$selected`, validación de claves, `if count -eq 0`, `$target`, guarda de existencia, loop de armado, `ConvertTo-Json`, resumen) es **idéntico byte a byte** al personal del Task 1+2.

- [ ] **Step 4: Correr y verificar que pasa**

Run: `pwsh -NoProfile -File tests/gen-mcp-json.tests.ps1`
Expected: PASS — "TODOS LOS TESTS PASARON".

- [ ] **Step 5: Commit**

```bash
git add skills/bootstrap-southpoint-project/scripts/gen-mcp-json.ps1 tests/gen-mcp-json.tests.ps1
git -c user.name="MartinDele703" -c user.email="martin.deleon703@gmail.com" commit -m "feat(bootstrap): gen-mcp-json.ps1 southpoint (catalogo domo + zoho-projects)"
```

---

### Task 4: SKILL.md personal — nuevo Step 4 (MCP servers) + renumeración

**Files:**
- Modify: `skills/bootstrap-personal-project/SKILL.md`

- [ ] **Step 1: Insertar el nuevo Step 4 y renumerar**

En `skills/bootstrap-personal-project/SKILL.md`, INSERTAR este bloque nuevo entre el actual "## Step 3 — Project-specific files" (completo) y "## Step 4 — Git":

```markdown
## Step 4 — MCP servers (.mcp.json)

Ask which MCP tools this project will use, then generate a committed `.mcp.json` (project scope). Tokens are referenced via `${VAR}` — never written into the file.

Present the personal catalog with `AskUserQuestion` (multiSelect): **firebase**, **zoho-personal**, **github**. Let the user pick zero or more.

Then run the generator (adjust `$skill` to this skill's directory and `$proj` to the project root):

```powershell
$skill = "<base directory of this skill>"
$proj  = "<project root>"
pwsh -NoProfile -File "$skill\scripts\gen-mcp-json.ps1" -ProjectDir $proj -Servers <comma-separated picks>
```

The script writes `<proj>/.mcp.json` with only the chosen servers and prints a JSON summary with `requiredEnvVars` and `prereqs`. If the user picks nothing, it writes no file — that's fine, skip it.

`.mcp.json` is a per-project generated file (like README/CONTEXT): it is NOT part of the scaffold, NOT tracked by `.bootstrap-manifest.json`, and `upgrade-bootstrap` never touches it. It is committed with the rest of the scaffolding in the Git step.

Keep the script's `requiredEnvVars` / `prereqs` output for the final report (Step 6).
```

Luego RENUMERAR los headers siguientes: `## Step 4 — Git` → `## Step 5 — Git`, y `## Step 5 — Report and hand off` → `## Step 6 — Report and hand off`.

- [ ] **Step 2: Ampliar el reporte (Step 6) con las env vars**

En el ahora "## Step 6 — Report and hand off", agregar al final del primer párrafo:

```markdown
If a `.mcp.json` was generated, also report the **environment variables to set** (as persistent Windows user variables) and prerequisites from the script's summary — e.g. `ZOHO_PERSONAL_MCP_URL`, `GITHUB_PERSONAL_ACCESS_TOKEN` (+ Docker running), or `firebase login` once. The MCP servers won't connect until those env vars exist; this is expected, not an error.
```

- [ ] **Step 3: Verificar coherencia**

Run: `pwsh -NoProfile -Command "Select-String -Path 'skills/bootstrap-personal-project/SKILL.md' -Pattern '^## Step' | ForEach-Object { $_.Line }"`
Expected: headers en orden `Step 0, 1, 2, 3, 4 — MCP servers, 5 — Git, 6 — Report` sin duplicados ni saltos.

- [ ] **Step 4: Commit**

```bash
git add skills/bootstrap-personal-project/SKILL.md
git -c user.name="MartinDele703" -c user.email="martin.deleon703@gmail.com" commit -m "feat(bootstrap-personal): Step 4 MCP servers (menu + .mcp.json)"
```

---

### Task 5: SKILL.md southpoint — mismo Step espejado (catálogo southpoint)

**Files:**
- Modify: `skills/bootstrap-southpoint-project/SKILL.md`

- [ ] **Step 1: Insertar el Step 4 espejado y renumerar**

Hacer EXACTAMENTE lo mismo que en Task 4 sobre `skills/bootstrap-southpoint-project/SKILL.md`, con una sola diferencia en el texto del catálogo: la línea del menú dice

```markdown
Present the southpoint catalog with `AskUserQuestion` (multiSelect): **firebase**, **domo**, **zoho-projects**, **github**. Let the user pick zero or more.
```

El resto del bloque del Step 4 (intro, comando `pwsh ... gen-mcp-json.ps1`, nota de per-project/no-manifest, "keep the summary for Step 6") es idéntico al personal. Renumerar igual: Git → Step 5, Report → Step 6.

- [ ] **Step 2: Ampliar el reporte (Step 6) con las env vars**

Igual que Task 4 Step 2, pero el ejemplo de env vars usa las de southpoint:

```markdown
If a `.mcp.json` was generated, also report the **environment variables to set** (as persistent Windows user variables) and prerequisites from the script's summary — e.g. `ZOHO_SOUTHPOINT_MCP_URL`, `DOMO_SOUTHPOINT_TOKEN`, `DOMO_MCP_HOME`, `GITHUB_PERSONAL_ACCESS_TOKEN` (+ Docker running), or `firebase login` once. The MCP servers won't connect until those env vars exist; this is expected, not an error.
```

- [ ] **Step 3: Verificar coherencia**

Run: `pwsh -NoProfile -Command "Select-String -Path 'skills/bootstrap-southpoint-project/SKILL.md' -Pattern '^## Step' | ForEach-Object { $_.Line }"`
Expected: `Step 0, 1, 2, 3, 4 — MCP servers, 5 — Git, 6 — Report`.

- [ ] **Step 4: Commit**

```bash
git add skills/bootstrap-southpoint-project/SKILL.md
git -c user.name="MartinDele703" -c user.email="martin.deleon703@gmail.com" commit -m "feat(bootstrap-southpoint): Step 4 MCP servers (menu + .mcp.json)"
```

---

### Task 6: Nota en upgrade-bootstrap (capacidad nueva, sin merge automático)

**Files:**
- Modify: `skills/upgrade-bootstrap/SKILL.md`

- [ ] **Step 1: Agregar la nota en Guardrails**

En `skills/upgrade-bootstrap/SKILL.md`, agregar al final de la sección `## Guardrails`:

```markdown
- `.mcp.json` no es parte del scaffold ni del manifest, así que `compare-scaffold.ps1` no lo ve y este upgrade nunca lo toca. Si el proyecto fue bootstrapeado antes de la feature de MCP-por-área y querés agregarle un `.mcp.json`, corré el menú a mano con `~/.claude/skills/<generatedFrom>/scripts/gen-mcp-json.ps1` (no es parte del flujo de upgrade).
```

- [ ] **Step 2: Commit**

```bash
git add skills/upgrade-bootstrap/SKILL.md
git -c user.name="MartinDele703" -c user.email="martin.deleon703@gmail.com" commit -m "docs(upgrade-bootstrap): nota sobre .mcp.json fuera del manifest"
```

---

### Task 7: Evals del bootstrap (dir vacío + archivos preexistentes)

**Files:**
- Reference: `docs/TESTING.md` (procedimiento de evals del repo)

- [ ] **Step 1: Eval de directorio vacío**

Crear un workspace temporal vacío y correr el flujo del `gen-mcp-json.ps1` personal como lo haría el Step 4 (simulando una selección):

```powershell
$ws = Join-Path $env:TEMP ("eval-mcp-" + [guid]::NewGuid().ToString('N')); New-Item -ItemType Directory $ws | Out-Null
pwsh -NoProfile -File "skills/bootstrap-personal-project/scripts/gen-mcp-json.ps1" -ProjectDir $ws -Servers firebase,zoho-personal
Get-Content (Join-Path $ws ".mcp.json") -Raw | ConvertFrom-Json | Out-Null   # debe parsear sin error
Write-Host "OK eval vacio"; Remove-Item $ws -Recurse -Force
```

Expected: imprime el resumen JSON con `requiredEnvVars=[ZOHO_PERSONAL_MCP_URL]`, el `.mcp.json` parsea OK, "OK eval vacio".

- [ ] **Step 2: Eval de `.mcp.json` preexistente (no pisar)**

```powershell
$ws = Join-Path $env:TEMP ("eval-mcp-" + [guid]::NewGuid().ToString('N')); New-Item -ItemType Directory $ws | Out-Null
Set-Content (Join-Path $ws ".mcp.json") -Value '{"mcpServers":{"MIO":{}}}' -Encoding UTF8
pwsh -NoProfile -File "skills/bootstrap-southpoint-project/scripts/gen-mcp-json.ps1" -ProjectDir $ws -Servers domo
Write-Host "exit=$LASTEXITCODE (esperado != 0)"
(Get-Content (Join-Path $ws ".mcp.json") -Raw | ConvertFrom-Json).mcpServers.MIO  # sigue presente
Remove-Item $ws -Recurse -Force
```

Expected: exit ≠ 0 y el server `MIO` sigue intacto (no se pisó).

- [ ] **Step 3: Registrar el resultado**

Anotar en `docs/TESTING.md` (sección de casos) una línea con los dos evals corridos y su resultado (sin dejar workspaces de prueba: ya se borran arriba).

- [ ] **Step 4: Commit**

```bash
git add docs/TESTING.md
git -c user.name="MartinDele703" -c user.email="martin.deleon703@gmail.com" commit -m "docs(testing): evals de gen-mcp-json (dir vacio + .mcp.json preexistente)"
```

---

### Task 8: Deploy (sync-skills) y verificación final

**Files:**
- Run: `tools/sync-skills.ps1`

- [ ] **Step 1: Correr la suite completa una última vez**

Run: `pwsh -NoProfile -File tests/gen-mcp-json.tests.ps1`
Expected: "TODOS LOS TESTS PASARON", exit 0.

- [ ] **Step 2: Deploy a ~/.claude/skills**

Run: `pwsh -NoProfile -File tools/sync-skills.ps1`
Expected: copia las skills al destino y regenera manifests. Como NO tocamos `assets/scaffold/`, los `.bootstrap-manifest.json` no deberían cambiar (verificar con `git status` que no aparecen modificados; si aparecen, revisar que no se haya tocado el scaffold por error).

- [ ] **Step 3: Verificar que los scripts llegaron al destino**

Run: `pwsh -NoProfile -Command "Test-Path \"$env:USERPROFILE\.claude\skills\bootstrap-personal-project\scripts\gen-mcp-json.ps1\"; Test-Path \"$env:USERPROFILE\.claude\skills\bootstrap-southpoint-project\scripts\gen-mcp-json.ps1\""`
Expected: `True` y `True`.

- [ ] **Step 4: Commit de cierre (si sync dejó cambios)**

Si `git status` muestra cambios (p. ej. manifests regenerados o archivos de deploy trackeados), revisarlos y:

```bash
git add -A
git -c user.name="MartinDele703" -c user.email="martin.deleon703@gmail.com" commit -m "chore(bootstrap): deploy de la feature MCP-por-area"
```

Si no hay cambios, no hay commit — la feature ya está commiteada por tareas anteriores.

---

## Notas de cierre (fuera del plan de código)

- **Follow-up del usuario:** vaciar el user scope global (`claude mcp remove firebase|github|domo|zoho-projects`) recién cuando los proyectos activos tengan su `.mcp.json` y las env vars estén seteadas. Hasta entonces el global queda como stopgap.
- **Rotar secretos** en texto plano del `.claude.json` (PAT de GitHub, tokens DOMO) al pasarlos a env vars.
- Las env vars de Windows se setean persistentes (System → Environment Variables, o `setx NOMBRE valor` en una terminal nueva).
