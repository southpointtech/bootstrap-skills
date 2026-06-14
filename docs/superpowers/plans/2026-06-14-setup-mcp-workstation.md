# setup-mcp-workstation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Crear una skill `setup-mcp-workstation` que prepara una PC Windows (una vez) para trabajo Southpoint —persiste credenciales (git/DOMO/Zoho) e instala clientes (DOMO vía pip, Playwright browsers)— y parametrizar la identidad git en las dos skills de bootstrap.

**Architecture:** La skill orquesta (`SKILL.md`) y delega en dos scripts PowerShell aislados y testeables: `apply-env.ps1` (lee el archivo de config, setea env vars persistentes de usuario, nunca imprime valores de tokens) e `install-clients.ps1` (verifica Python/Node, corre `pip install`/`npx playwright install`). La fuente de verdad es un único archivo `~/.claude/mcp-workstation.local.json`. El `.mcp.json` por proyecto resuelve `${VAR}` desde esas env vars. Los bootstrap leen la identidad git de env vars por área con fallback a la identidad actual.

**Tech Stack:** PowerShell 7 (pwsh), `[Environment]::SetEnvironmentVariable(...,'User')`, runner de tests sin Pester (estilo `tests/gen-mcp-json.tests.ps1`), skill-creator para evals de la skill.

**Spec:** `docs/superpowers/specs/2026-06-14-setup-mcp-workstation-design.md`

---

## File Structure

**Crear:**
- `skills/setup-mcp-workstation/SKILL.md` — orquestación (instrucciones para Claude).
- `skills/setup-mcp-workstation/scripts/apply-env.ps1` — aplica env vars de usuario desde el config; resumen JSON sin secretos.
- `skills/setup-mcp-workstation/scripts/install-clients.ps1` — instala/verifica DOMO (pip) y Playwright (browsers).
- `tests/apply-env.tests.ps1` — runner sin Pester para `apply-env.ps1`.
- `tests/install-clients.tests.ps1` — runner sin Pester para `install-clients.ps1`.

**Modificar:**
- `skills/bootstrap-southpoint-project/scripts/gen-mcp-json.ps1` — quitar `PYTHONPATH=${DOMO_MCP_HOME}` y `DOMO_MCP_HOME` de `requiredEnvVars` del server domo.
- `tests/gen-mcp-json.tests.ps1` — actualizar aserciones de domo.
- `skills/bootstrap-southpoint-project/SKILL.md` — Step 5 (identidad git por env var) + Step 0 (chequeo de máquina).
- `skills/bootstrap-personal-project/SKILL.md` — Step 5 (identidad git por env var).
- `README.md`, `docs/HISTORIA.md`, `docs/TESTING.md` — documentar la skill nueva y el onboarding.

**Nota sobre identidad de commits:** este repo se commitea como `MartinDele703 <martin.deleon703@gmail.com>` (regla del repo). El repo ya tiene esa identidad local configurada.

---

## Task 1: `apply-env.ps1` — aplicar env vars desde el config

**Files:**
- Create: `skills/setup-mcp-workstation/scripts/apply-env.ps1`
- Test: `tests/apply-env.tests.ps1`

Interfaz: `apply-env.ps1 -ConfigPath <archivo> [-DryRun]`. Lee JSON, valida campos, y por cada env var llama `[Environment]::SetEnvironmentVariable($name,$value,'User')` (salvo `-DryRun`). Imprime un resumen JSON con **solo nombres** de vars y estado (`set`/`unchanged`), nunca valores. `-DryRun` calcula el estado sin escribir (para tests, sin ensuciar el entorno real).

- [ ] **Step 1: Escribir el test que falla**

Create `tests/apply-env.tests.ps1`:

```powershell
# tests/apply-env.tests.ps1 — runner sin Pester. Correr: pwsh -NoProfile -File tests/apply-env.tests.ps1
$ErrorActionPreference = "Stop"
$repo   = Split-Path $PSScriptRoot -Parent
$script = Join-Path $repo "skills/setup-mcp-workstation/scripts/apply-env.ps1"
$script:failures = 0

function Assert($cond, $msg) {
  if ($cond) { Write-Host "ok:   $msg" } else { Write-Host "FAIL: $msg"; $script:failures++ }
}
function NewCfg([string]$json) {
  $p = Join-Path ([IO.Path]::GetTempPath()) ("wscfg-" + [guid]::NewGuid().ToString('N') + ".json")
  Set-Content -Path $p -Value $json -Encoding UTF8; $p
}
function Run($cfgPath) {
  $out = & pwsh -NoProfile -File $script -ConfigPath $cfgPath -DryRun 2>$null
  @{ exit = $LASTEXITCODE; out = ($out | Out-String) }
}

$validJson = @'
{ "git": { "name": "Ada Lovelace", "email": "ada@agtium.com" },
  "domo": { "token": "SECRET-DOMO-123" },
  "zoho": { "mcpUrl": "https://zoho.example/mcp/abc" } }
'@

# --- happy path (dry-run) ---
$cfg = NewCfg $validJson
$r = Run $cfg
Assert ($r.exit -eq 0) "happy: exit 0"
$sum = $r.out | ConvertFrom-Json
Assert ($sum.dryRun -eq $true) "happy: dryRun=true"
$names = @($sum.vars | ForEach-Object { $_.name })
Assert ($names -contains "SOUTHPOINT_GIT_NAME")     "happy: setea SOUTHPOINT_GIT_NAME"
Assert ($names -contains "SOUTHPOINT_GIT_EMAIL")    "happy: setea SOUTHPOINT_GIT_EMAIL"
Assert ($names -contains "DOMO_SOUTHPOINT_TOKEN")   "happy: setea DOMO_SOUTHPOINT_TOKEN"
Assert ($names -contains "ZOHO_SOUTHPOINT_MCP_URL") "happy: setea ZOHO_SOUTHPOINT_MCP_URL"
Assert ($names.Count -eq 4) "happy: exactamente 4 vars"

# --- NO filtra valores de secretos en la salida ---
Assert (-not ($r.out -match "SECRET-DOMO-123")) "seguridad: no imprime el token domo"
Assert (-not ($r.out -match "zoho.example"))    "seguridad: no imprime la url zoho"

# --- config con campo faltante ---
$bad = NewCfg '{ "git": { "name": "X", "email": "x@y.z" }, "domo": { "token": "t" } }'
$rb = & pwsh -NoProfile -File $script -ConfigPath $bad -DryRun 2>&1
Assert ($LASTEXITCODE -ne 0) "faltante: exit != 0"
Assert ("$rb" -match "zoho")  "faltante: el error menciona el campo zoho"

# --- config inexistente ---
& pwsh -NoProfile -File $script -ConfigPath (Join-Path ([IO.Path]::GetTempPath()) "no-existe-xyz.json") -DryRun 2>&1 | Out-Null
Assert ($LASTEXITCODE -ne 0) "inexistente: exit != 0"

Write-Host ""
if ($script:failures -gt 0) { Write-Host "$($script:failures) test(s) FALLARON"; exit 1 } else { Write-Host "TODOS LOS TESTS PASARON"; exit 0 }
```

- [ ] **Step 2: Correr el test y verificar que falla**

Run: `pwsh -NoProfile -File tests/apply-env.tests.ps1`
Expected: FAIL — el script `apply-env.ps1` no existe todavía (errores de "no se encuentra el archivo").

- [ ] **Step 3: Escribir la implementación mínima**

Create `skills/setup-mcp-workstation/scripts/apply-env.ps1`:

```powershell
# apply-env.ps1 — aplica las credenciales del workstation como env vars persistentes de usuario.
# Uso: pwsh -NoProfile -File apply-env.ps1 -ConfigPath <archivo.json> [-DryRun]
# NUNCA imprime valores de tokens: el resumen JSON lleva solo nombres de variables y estado.
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$ConfigPath,
  [switch]$DryRun
)
$ErrorActionPreference = "Stop"

if (-not (Test-Path $ConfigPath)) { throw "No existe el archivo de config: $ConfigPath" }

try { $cfg = Get-Content $ConfigPath -Raw | ConvertFrom-Json } catch { throw "Config JSON malformado: $ConfigPath" }

# Mapa: env var -> valor desde el config (con la ruta del campo para el mensaje de error)
$map = [ordered]@{
  "SOUTHPOINT_GIT_NAME"     = @{ value = $cfg.git.name;     field = "git.name" }
  "SOUTHPOINT_GIT_EMAIL"    = @{ value = $cfg.git.email;    field = "git.email" }
  "DOMO_SOUTHPOINT_TOKEN"   = @{ value = $cfg.domo.token;   field = "domo.token" }
  "ZOHO_SOUTHPOINT_MCP_URL" = @{ value = $cfg.zoho.mcpUrl;  field = "zoho.mcpUrl" }
}

foreach ($k in $map.Keys) {
  $v = $map[$k].value
  if ([string]::IsNullOrWhiteSpace([string]$v)) { throw "Falta el campo '$($map[$k].field)' en $ConfigPath" }
}

$vars = New-Object System.Collections.Generic.List[object]
foreach ($k in $map.Keys) {
  $new = [string]$map[$k].value
  $cur = [Environment]::GetEnvironmentVariable($k, 'User')
  $status = if ($cur -eq $new) { "unchanged" } else { "set" }
  if (-not $DryRun) { [Environment]::SetEnvironmentVariable($k, $new, 'User') }
  $vars.Add([ordered]@{ name = $k; status = $status })
}

[pscustomobject]@{
  applied = (-not $DryRun)
  dryRun  = [bool]$DryRun
  vars    = @($vars)
} | ConvertTo-Json -Depth 5
```

- [ ] **Step 4: Correr el test y verificar que pasa**

Run: `pwsh -NoProfile -File tests/apply-env.tests.ps1`
Expected: PASS — "TODOS LOS TESTS PASARON".

- [ ] **Step 5: Commit**

```bash
git add skills/setup-mcp-workstation/scripts/apply-env.ps1 tests/apply-env.tests.ps1
git commit -m "feat(setup-mcp-workstation): apply-env.ps1 + tests (env vars sin filtrar secretos)"
```

---

## Task 2: `install-clients.ps1` — instalar DOMO (pip) y Playwright

**Files:**
- Create: `skills/setup-mcp-workstation/scripts/install-clients.ps1`
- Test: `tests/install-clients.tests.ps1`

Interfaz: `install-clients.ps1 [-DomoPipSource <pkg>] [-PythonCmd python] [-NpxCmd npx] [-DryRun]`. Verifica presencia de Python y npx vía `Get-Command`; corre `pip install` y `npx playwright install chromium` (salvo `-DryRun`). Los params `-PythonCmd`/`-NpxCmd` permiten simular ausencia en los tests pasando un comando inexistente. Imprime resumen JSON con `installed`, `skipped`, `prereqsMissing` y `commands` (los comandos que correría/corrió).

> **ENTRADA EXTERNA (Martín):** el valor por defecto de `-DomoPipSource` es `"domo-mcp"` como marcador. Antes del deploy, reemplazalo por el nombre/fuente real del paquete pip de `domo_mcp` (PyPI público, índice privado, o `pip install git+https://...`). Es el único dato del entorno que el plan no puede conocer.

- [ ] **Step 1: Escribir el test que falla**

Create `tests/install-clients.tests.ps1`:

```powershell
# tests/install-clients.tests.ps1 — runner sin Pester. Correr: pwsh -NoProfile -File tests/install-clients.tests.ps1
$ErrorActionPreference = "Stop"
$repo   = Split-Path $PSScriptRoot -Parent
$script = Join-Path $repo "skills/setup-mcp-workstation/scripts/install-clients.ps1"
$script:failures = 0
function Assert($cond, $msg) {
  if ($cond) { Write-Host "ok:   $msg" } else { Write-Host "FAIL: $msg"; $script:failures++ }
}

# --- ambos presentes (pwsh siempre existe -> lo usamos como stand-in de python y npx) ---
$out = & pwsh -NoProfile -File $script -DomoPipSource "domo-pkg-test" -PythonCmd "pwsh" -NpxCmd "pwsh" -DryRun 2>$null
Assert ($LASTEXITCODE -eq 0) "ambos: exit 0"
$sum = $out | Out-String | ConvertFrom-Json
$cmds = ($sum.commands -join " || ")
Assert ($cmds -match "domo-pkg-test") "ambos: el comando pip referencia el paquete domo"
Assert ($cmds -match "pip install")   "ambos: corre pip install"
Assert ($cmds -match "playwright install chromium") "ambos: instala chromium de playwright"
Assert (@($sum.prereqsMissing).Count -eq 0) "ambos: sin prereqs faltantes"

# --- python ausente -> reporta prereq, no aborta ---
$out2 = & pwsh -NoProfile -File $script -PythonCmd "no-existe-python-xyz" -NpxCmd "pwsh" -DryRun 2>$null
Assert ($LASTEXITCODE -eq 0) "sin python: exit 0 (no aborta)"
$sum2 = $out2 | Out-String | ConvertFrom-Json
Assert (($sum2.prereqsMissing -join " ") -match "[Pp]ython") "sin python: reporta Python faltante"
Assert (($sum2.commands -join " ") -notmatch "pip install") "sin python: NO intenta pip"
Assert (($sum2.commands -join " ") -match "playwright") "sin python: igual sigue con playwright"

# --- npx ausente -> reporta prereq de node ---
$out3 = & pwsh -NoProfile -File $script -PythonCmd "pwsh" -NpxCmd "no-existe-npx-xyz" -DryRun 2>$null
Assert ($LASTEXITCODE -eq 0) "sin npx: exit 0"
$sum3 = $out3 | Out-String | ConvertFrom-Json
Assert (($sum3.prereqsMissing -join " ") -match "[Nn]ode") "sin npx: reporta Node/npx faltante"

Write-Host ""
if ($script:failures -gt 0) { Write-Host "$($script:failures) test(s) FALLARON"; exit 1 } else { Write-Host "TODOS LOS TESTS PASARON"; exit 0 }
```

- [ ] **Step 2: Correr el test y verificar que falla**

Run: `pwsh -NoProfile -File tests/install-clients.tests.ps1`
Expected: FAIL — `install-clients.ps1` no existe.

- [ ] **Step 3: Escribir la implementación mínima**

Create `skills/setup-mcp-workstation/scripts/install-clients.ps1`:

```powershell
# install-clients.ps1 — instala/verifica los clientes machine-level de Southpoint: DOMO (pip) y Playwright (browsers).
# Uso: pwsh -NoProfile -File install-clients.ps1 [-DomoPipSource <pkg>] [-PythonCmd python] [-NpxCmd npx] [-DryRun]
[CmdletBinding()]
param(
  [string]$DomoPipSource = "domo-mcp",   # <-- REEMPLAZAR por el paquete/fuente real antes del deploy
  [string]$PythonCmd = "python",
  [string]$NpxCmd = "npx",
  [switch]$DryRun
)
$ErrorActionPreference = "Stop"

$installed       = New-Object System.Collections.Generic.List[string]
$skipped         = New-Object System.Collections.Generic.List[string]
$prereqsMissing  = New-Object System.Collections.Generic.List[string]
$commands        = New-Object System.Collections.Generic.List[string]

function Have($cmd) { [bool](Get-Command $cmd -ErrorAction SilentlyContinue) }

# --- DOMO via pip ---
if (Have $PythonCmd) {
  $cmd = "$PythonCmd -m pip install --upgrade $DomoPipSource"
  $commands.Add($cmd)
  if (-not $DryRun) { & $PythonCmd -m pip install --upgrade $DomoPipSource; if ($LASTEXITCODE -ne 0) { $prereqsMissing.Add("pip install de domo fallo: $cmd") } else { $installed.Add("domo ($DomoPipSource)") } }
  else { $installed.Add("domo ($DomoPipSource)") }
} else {
  $skipped.Add("domo")
  $prereqsMissing.Add("Python no encontrado en PATH (comando '$PythonCmd'): instalalo y re-corre la skill.")
}

# --- Playwright browsers (chromium) ---
if (Have $NpxCmd) {
  $cmd = "$NpxCmd --yes playwright install chromium"
  $commands.Add($cmd)
  if (-not $DryRun) { & $NpxCmd --yes playwright install chromium; if ($LASTEXITCODE -ne 0) { $prereqsMissing.Add("playwright install fallo: $cmd") } else { $installed.Add("playwright (chromium)") } }
  else { $installed.Add("playwright (chromium)") }
} else {
  $skipped.Add("playwright")
  $prereqsMissing.Add("Node/npx no encontrado en PATH (comando '$NpxCmd'): instala Node y re-corre la skill.")
}

[pscustomobject]@{
  dryRun         = [bool]$DryRun
  installed      = @($installed)
  skipped        = @($skipped)
  prereqsMissing = @($prereqsMissing)
  commands       = @($commands)
} | ConvertTo-Json -Depth 5
```

- [ ] **Step 4: Correr el test y verificar que pasa**

Run: `pwsh -NoProfile -File tests/install-clients.tests.ps1`
Expected: PASS — "TODOS LOS TESTS PASARON".

- [ ] **Step 5: Commit**

```bash
git add skills/setup-mcp-workstation/scripts/install-clients.ps1 tests/install-clients.tests.ps1
git commit -m "feat(setup-mcp-workstation): install-clients.ps1 + tests (DOMO pip + Playwright chromium, hibrido)"
```

---

## Task 3: `SKILL.md` — orquestación del wizard

**Files:**
- Create: `skills/setup-mcp-workstation/SKILL.md`

No tiene test unitario (se evalúa a nivel skill con skill-creator, ver Task 7). Es el documento de instrucciones que Claude sigue.

- [ ] **Step 1: Escribir el SKILL.md**

Create `skills/setup-mcp-workstation/SKILL.md`:

````markdown
---
name: setup-mcp-workstation
description: Use ONCE per Windows PC to prepare a machine for SOUTHPOINTLABS work — first-time workstation setup that asks for the user's git identity, DOMO token and Zoho MCP URL, persists them as user env vars, and installs the attached clients (DOMO via pip, Playwright browsers). Trigger when someone says "configurá mi máquina", "preparar la compu/workstation", "setup inicial de la PC", "onboarding de un compañero nuevo", "dejá lista la máquina para Southpoint", or when bootstrap-southpoint-project reports the machine is not configured. This is a per-MACHINE setup, run once — NOT a per-project setup. For per-project scaffolding use bootstrap-southpoint-project.
---

# setup-mcp-workstation

Prepara una PC Windows **una sola vez** para trabajar en proyectos Southpoint. Después de correrla, el usuario solo usa `bootstrap-southpoint-project` y todo resuelve (la identidad git, los MCP de DOMO/Zoho, y Playwright quedan listos).

Define `$skill` = directorio base de esta skill. El archivo de config es `"$env:USERPROFILE\.claude\mcp-workstation.local.json"` (fuera de todo repo, nunca se commitea).

## Step 0 — Detectar estado de la máquina

Chequeá si la máquina ya está configurada:

```powershell
$cfgPath = Join-Path $env:USERPROFILE ".claude\mcp-workstation.local.json"
$alreadyVar = [bool][Environment]::GetEnvironmentVariable("DOMO_SOUTHPOINT_TOKEN","User")
"config existe: $([bool](Test-Path $cfgPath)) | env var domo: $alreadyVar"
```

Si el archivo existe y las env vars están: avisá que ya está configurada y ofrecé **re-aplicar** (útil para rotar un token) o salir. Si re-aplica, saltá a Step 2 usando el archivo existente.

## Step 1 — Pedir las credenciales

Si el archivo NO existe (o el usuario quiere reconfigurar), pedí los valores con `AskUserQuestion` (o, si no hay interfaz interactiva, indicá al usuario que cree el archivo con la estructura de abajo y vuelva a correr la skill). Pedí:

1. **Identidad git** — nombre y email para sus commits.
2. **Token de DOMO** — el developer token de su cuenta.
3. **URL del MCP de Zoho** — la URL HTTP del MCP de Zoho Projects.

El **host de DOMO** y la **fuente del paquete pip** son constantes (no se preguntan).

## Step 2 — Escribir el archivo de config

Escribí `$cfgPath` con los valores (UTF-8):

```json
{
  "git":  { "name": "<nombre>", "email": "<email>" },
  "domo": { "token": "<token>" },
  "zoho": { "mcpUrl": "<url>" }
}
```

Nunca commitees este archivo ni lo muestres en pantalla con el token visible.

## Step 3 — Aplicar las env vars

```powershell
pwsh -NoProfile -File "$skill\scripts\apply-env.ps1" -ConfigPath $cfgPath
```

El script setea `SOUTHPOINT_GIT_NAME`, `SOUTHPOINT_GIT_EMAIL`, `DOMO_SOUTHPOINT_TOKEN`, `ZOHO_SOUTHPOINT_MCP_URL` como variables de usuario persistentes y devuelve un resumen JSON (solo nombres + estado). Si sale con error, reportá el mensaje y no sigas.

## Step 4 — Instalar los clientes

```powershell
pwsh -NoProfile -File "$skill\scripts\install-clients.ps1"
```

Instala DOMO (`pip install`) y los browsers de Playwright (chromium). Devuelve un resumen con `installed`, `skipped` y `prereqsMissing`. **No abortes** si reporta prereqs faltantes (Python/Node): seguí y listalos en el reporte como pasos guiados.

## Step 5 — Reporte

Reportá: qué env vars quedaron seteadas (solo nombres), qué clientes se instalaron, qué prerequisitos faltan (con la instrucción exacta para resolverlos), y el recordatorio de **reiniciar Claude Code** para que tome las env vars nuevas. Cerrá con: "Máquina lista para Southpoint — ya podés usar `bootstrap-southpoint-project` en cualquier proyecto."
````

- [ ] **Step 2: Verificar el frontmatter y los paths**

Run: `pwsh -NoProfile -Command "Test-Path 'skills/setup-mcp-workstation/scripts/apply-env.ps1'; Test-Path 'skills/setup-mcp-workstation/scripts/install-clients.ps1'"`
Expected: `True` y `True` — los scripts que el SKILL.md referencia existen.

- [ ] **Step 3: Commit**

```bash
git add skills/setup-mcp-workstation/SKILL.md
git commit -m "feat(setup-mcp-workstation): SKILL.md (wizard de setup de PC, 1x por maquina)"
```

---

## Task 4: Quitar `DOMO_MCP_HOME` del catálogo MCP de southpoint

**Files:**
- Modify: `tests/gen-mcp-json.tests.ps1` (aserciones de domo)
- Modify: `skills/bootstrap-southpoint-project/scripts/gen-mcp-json.ps1:18-20` (server domo)

Con `domo_mcp` instalado por pip, `python -m domo_mcp` corre sin `PYTHONPATH`. (La skill personal no tiene server domo: no se toca.)

- [ ] **Step 1: Actualizar el test para esperar la ausencia de DOMO_MCP_HOME**

En `tests/gen-mcp-json.tests.ps1`, reemplazá las dos aserciones de domo. Quitá la línea 76 (`PYTHONPATH ... DOMO_MCP_HOME`) y la 80 (`requiredEnvVars -contains "DOMO_MCP_HOME"`), y en su lugar afirmá lo contrario:

```powershell
Assert ($null -eq $sd.mcpServers.domo.env.PYTHONPATH) "southpoint happy: domo SIN PYTHONPATH (pip-installed)"
Assert (-not ($ss.requiredEnvVars -contains "DOMO_MCP_HOME")) "southpoint happy: NO reporta DOMO_MCP_HOME"
```

(Mantené la aserción de la línea 75 `DOMO_DEVELOPER_TOKEN -eq '${DOMO_SOUTHPOINT_TOKEN}'` y la 79 de `DOMO_SOUTHPOINT_TOKEN`.)

- [ ] **Step 2: Correr el test y verificar que falla**

Run: `pwsh -NoProfile -File tests/gen-mcp-json.tests.ps1`
Expected: FAIL — el script todavía emite `PYTHONPATH`/`DOMO_MCP_HOME`, así que las dos aserciones nuevas fallan.

- [ ] **Step 3: Editar el catálogo del generador**

En `skills/bootstrap-southpoint-project/scripts/gen-mcp-json.ps1`, en la entrada `"domo"` (líneas 17-21):
- Sacá `PYTHONPATH = '${DOMO_MCP_HOME}'` del bloque `env`.
- Sacá `"DOMO_MCP_HOME"` de `requiredEnvVars` (queda `requiredEnvVars = @("DOMO_SOUTHPOINT_TOKEN")`).
- Cambiá el prereq de `"checkout local de domo-mcp-server"` a `"domo_mcp instalado por setup-mcp-workstation"`.

El bloque `env` de domo queda:
```powershell
env = [ordered]@{ DOMO_DEVELOPER_TOKEN = '${DOMO_SOUTHPOINT_TOKEN}'; DOMO_HOST = "hssstaffing.domo.com"; PYTHONIOENCODING = "utf-8" }
```

- [ ] **Step 4: Correr el test y verificar que pasa**

Run: `pwsh -NoProfile -File tests/gen-mcp-json.tests.ps1`
Expected: PASS — "TODOS LOS TESTS PASARON".

- [ ] **Step 5: Commit**

```bash
git add tests/gen-mcp-json.tests.ps1 skills/bootstrap-southpoint-project/scripts/gen-mcp-json.ps1
git commit -m "refactor(mcp): domo via pip, sin DOMO_MCP_HOME/PYTHONPATH en el catalogo southpoint"
```

---

## Task 5: Identidad git parametrizada en las dos bootstrap

**Files:**
- Modify: `skills/bootstrap-southpoint-project/SKILL.md:131-134`
- Modify: `skills/bootstrap-personal-project/SKILL.md:131-134`

- [ ] **Step 1: Southpoint — leer la identidad de env var con fallback**

En `skills/bootstrap-southpoint-project/SKILL.md`, reemplazá el bloque (líneas 131-134):

```powershell
git config user.name "southpointtech"
git config user.email "mdeleon@agtium.com"
```

por:

```powershell
git config user.name  "$($env:SOUTHPOINT_GIT_NAME  ?? 'southpointtech')"
git config user.email "$($env:SOUTHPOINT_GIT_EMAIL ?? 'mdeleon@agtium.com')"
```

Y justo antes del bloque, agregá una línea de contexto:

```markdown
La identidad se toma de las env vars que deja `setup-mcp-workstation` (`SOUTHPOINT_GIT_NAME` / `SOUTHPOINT_GIT_EMAIL`), con fallback a la identidad de servicio si no están seteadas:
```

- [ ] **Step 2: Personal — mismo patrón con sus constantes**

En `skills/bootstrap-personal-project/SKILL.md`, reemplazá el bloque (líneas 131-134):

```powershell
git config user.name "MartinDele703"
git config user.email "martin.deleon703@gmail.com"
```

por:

```powershell
git config user.name  "$($env:PERSONAL_GIT_NAME  ?? 'MartinDele703')"
git config user.email "$($env:PERSONAL_GIT_EMAIL ?? 'martin.deleon703@gmail.com')"
```

Y la línea de contexto antes:

```markdown
La identidad se toma de las env vars `PERSONAL_GIT_NAME` / `PERSONAL_GIT_EMAIL`, con fallback a la identidad personal si no están seteadas:
```

- [ ] **Step 3: Verificar el fallback con un smoke test**

Run:
```powershell
pwsh -NoProfile -Command "$env:SOUTHPOINT_GIT_NAME=$null; \"$($env:SOUTHPOINT_GIT_NAME ?? 'southpointtech')\"; $env:SOUTHPOINT_GIT_NAME='Ada'; \"$($env:SOUTHPOINT_GIT_NAME ?? 'southpointtech')\""
```
Expected: imprime `southpointtech` (sin var) y luego `Ada` (con var) — confirma que el patrón `??` cae al fallback y toma la env var cuando existe.

- [ ] **Step 4: Commit**

```bash
git add skills/bootstrap-southpoint-project/SKILL.md skills/bootstrap-personal-project/SKILL.md
git commit -m "feat(bootstrap): identidad git por env var con fallback (espejado en ambas skills)"
```

---

## Task 6: Chequeo de máquina en el Step 0 de southpoint

**Files:**
- Modify: `skills/bootstrap-southpoint-project/SKILL.md` (Step 0, alrededor de la línea 14-20)

Avisar (sin bloquear) si la máquina no fue configurada con `setup-mcp-workstation`.

- [ ] **Step 1: Agregar el aviso al final del Step 0**

En `skills/bootstrap-southpoint-project/SKILL.md`, al final de la sección `## Step 0 — Safety check` (antes de `## Step 0b`), agregá:

```markdown
**Chequeo de máquina (no bloqueante):** si no existe la env var `SOUTHPOINT_GIT_NAME` ni el archivo `"$env:USERPROFILE\.claude\mcp-workstation.local.json"`, esta PC probablemente no fue preparada para Southpoint. No frenes el bootstrap, pero avisá al usuario que conviene correr la skill `setup-mcp-workstation` una vez (deja la identidad git, los tokens de DOMO/Zoho y Playwright listos), y anotalo en el reporte del Step 6. Si la env var o el archivo existen, no digas nada.
```

- [ ] **Step 2: Verificar que no rompió la estructura del SKILL.md**

Run: `pwsh -NoProfile -Command "(Select-String -Path 'skills/bootstrap-southpoint-project/SKILL.md' -Pattern '## Step ').Count"`
Expected: el mismo número de headers de Step que antes (8: 0, 0b, 1, 2, 3, 4, 5, 6) — confirma que solo agregamos texto dentro de Step 0, sin romper headers.

- [ ] **Step 3: Commit**

```bash
git add skills/bootstrap-southpoint-project/SKILL.md
git commit -m "feat(bootstrap-southpoint): Step 0 avisa si la maquina no fue configurada (setup-mcp-workstation)"
```

---

## Task 7: Documentación

**Files:**
- Modify: `README.md`
- Modify: `docs/HISTORIA.md`
- Modify: `docs/TESTING.md`

- [ ] **Step 1: README — agregar la skill y el onboarding**

En `README.md`, agregá `setup-mcp-workstation` a la tabla de skills y una sección corta "Onboarding de una PC nueva (compañero nuevo)" que diga: clonar/recibir el repo → `tools\sync-skills.ps1` → abrir Claude Code y decir "configurá mi máquina para Southpoint" (corre `setup-mcp-workstation`, pide git/DOMO/Zoho una vez) → reiniciar Claude Code → ya puede usar `bootstrap-southpoint-project`. Aclarar que Python (DOMO) y Node (Playwright) son prerequisitos que la skill verifica y guía si faltan.

- [ ] **Step 2: HISTORIA — registrar la feature**

En `docs/HISTORIA.md`, agregá una entrada fechada 2026-06-14 resumiendo: motivación (compartir con compañero nuevo), la skill `setup-mcp-workstation` (archivo de config + env vars + pip/playwright híbrido), la identidad git parametrizada en ambas bootstrap, y el cambio de catálogo (domo por pip, sin `DOMO_MCP_HOME`).

- [ ] **Step 3: TESTING — documentar cómo correr los tests nuevos**

En `docs/TESTING.md`, agregá una sección "Testeo de setup-mcp-workstation": los dos runners sin Pester (`pwsh -NoProfile -File tests/apply-env.tests.ps1` y `tests/install-clients.tests.ps1`), qué cubren (validación de config, no-filtrado de secretos, prereqs faltantes, dry-run), y que el flujo end-to-end de la skill se evalúa con skill-creator usando el caso "configurá mi máquina para Southpoint".

- [ ] **Step 4: Commit**

```bash
git add README.md docs/HISTORIA.md docs/TESTING.md
git commit -m "docs: setup-mcp-workstation (README onboarding + HISTORIA + TESTING)"
```

---

## Task 8: Reemplazar el paquete pip real, correr todo y deployar

**Files:**
- Modify: `skills/setup-mcp-workstation/scripts/install-clients.ps1` (valor real de `-DomoPipSource`)

- [ ] **Step 1: Poner el paquete pip real de DOMO**

Pedile a Martín el nombre/fuente real del paquete `domo_mcp` y reemplazá el default `"domo-mcp"` en `install-clients.ps1`. Si es un índice privado o `git+https`, dejá el comando completo como default del param.

- [ ] **Step 2: Correr toda la batería de tests**

Run:
```powershell
pwsh -NoProfile -File tests/apply-env.tests.ps1
pwsh -NoProfile -File tests/install-clients.tests.ps1
pwsh -NoProfile -File tests/gen-mcp-json.tests.ps1
```
Expected: las tres imprimen "TODOS LOS TESTS PASARON".

- [ ] **Step 3: Eval de la skill con skill-creator (mínimo)**

Seguí `docs/TESTING.md`: corré el caso "configurá mi máquina para Southpoint" con skill-creator y verificá que la skill pide git/DOMO/Zoho, escribe el archivo de config, y llama a los dos scripts. Usá `-DryRun` o un `$env:USERPROFILE` temporal para no tocar el entorno real. Borrá el workspace de evals al terminar (regla del repo).

- [ ] **Step 4: Deploy**

Run: `pwsh -NoProfile -File tools/sync-skills.ps1`
Expected: imprime "Deployada: setup-mcp-workstation (N archivos)" junto con las demás. (`sync-skills.ps1` enumera todas las skills de `skills/`, así que la nueva entra sola; los manifests de las bootstrap se regeneran porque cambiaron sus SKILL.md/scripts.)

- [ ] **Step 5: Verificar el deploy**

Run: `pwsh -NoProfile -Command "Test-Path \"$env:USERPROFILE\.claude\skills\setup-mcp-workstation\SKILL.md\""`
Expected: `True` — la skill quedó instalada.

- [ ] **Step 6: Commit final (manifests regenerados)**

```bash
git add -A
git commit -m "chore(setup-mcp-workstation): paquete pip real + manifests regenerados tras deploy"
```

---

## Self-Review

**Spec coverage:**
- §3.1 skill orquestadora → Task 3. ✅
- §3.2 archivo de config → Task 3 (Step 2). ✅
- §3.3 apply-env (env vars, sin secretos en logs) → Task 1. ✅
- §4 instalación híbrida (DOMO pip, Playwright chromium, verificar Python/Node) → Task 2. ✅
- §5.1 identidad git en ambas bootstrap → Task 5. ✅
- §5.2 derivación Step 0 (no bloqueante) → Task 6. ✅
- §5.3 quitar DOMO_MCP_HOME del catálogo + tests → Task 4. ✅
- §6 manejo de errores (config malformado, prereqs faltantes no abortan, sin secretos en logs) → Tasks 1-2 (tests cubren). ✅
- §7 testing → Tasks 1,2,4 (unit) + Task 8 Step 3 (skill-creator). ✅
- §8 deploy + docs → Tasks 7-8. ✅
- §9.1 pip source como entrada externa → Task 2 (marcador) + Task 8 Step 1 (valor real). ✅
- §9.2 personal no tiene domo → confirmado, Task 4 solo toca southpoint. ✅
- §9.3 heurística Step 0 → definida en Task 6 (env var `SOUTHPOINT_GIT_NAME` o archivo de config). ✅

**Placeholder scan:** sin TODO/TBD. El único valor diferido (paquete pip) está explícito como entrada externa con un marcador concreto (`"domo-mcp"`) y un step dedicado para reemplazarlo (Task 8 Step 1).

**Type consistency:** nombres de env vars consistentes entre Task 1 (apply-env), Task 5 (bootstrap) y Task 6 (Step 0): `SOUTHPOINT_GIT_NAME`, `SOUTHPOINT_GIT_EMAIL`, `DOMO_SOUTHPOINT_TOKEN`, `ZOHO_SOUTHPOINT_MCP_URL`, `PERSONAL_GIT_NAME`, `PERSONAL_GIT_EMAIL`. Campos del config (`git.name`, `git.email`, `domo.token`, `zoho.mcpUrl`) consistentes entre el SKILL.md (Task 3) y `apply-env.ps1` (Task 1). Nombres de scripts (`apply-env.ps1`, `install-clients.ps1`) consistentes entre SKILL.md y las tasks.
