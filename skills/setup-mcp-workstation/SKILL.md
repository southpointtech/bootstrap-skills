---
name: setup-mcp-workstation
description: Use ONCE per Windows PC to prepare a machine for SOUTHPOINTLABS work — first-time workstation setup that asks for the user's git identity, DOMO token and Zoho MCP URL, persists them as user env vars, and installs the attached clients (clones the DOMO MCP client + its deps, Playwright browsers). Trigger when someone says "configurá mi máquina", "preparar la compu/workstation", "setup inicial de la PC", "onboarding de un compañero nuevo", "dejá lista la máquina para Southpoint", or when bootstrap-southpoint-project reports the machine is not configured. This is a per-MACHINE setup, run once — NOT a per-project setup. For per-project scaffolding use bootstrap-southpoint-project.
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

El **archivo de config es la señal canónica** (la env var de DOMO puede estar de un setup viejo a mano y no significa que esta skill haya corrido). Si el archivo **existe**: avisá que ya está configurada y ofrecé **re-aplicar** (útil para rotar un token) o salir; si re-aplica, saltá a Step 2 usando el archivo existente. Si el archivo **no existe** (aunque alguna env var ya esté seteada): tratá la máquina como no configurada y seguí con el setup completo desde Step 1.

## Step 1 — Pedir las credenciales

Si el archivo NO existe (o el usuario quiere reconfigurar), pedí los valores con `AskUserQuestion` (o, si no hay interfaz interactiva, indicá al usuario que cree el archivo con la estructura de abajo y vuelva a correr la skill). Pedí:

1. **Identidad git** — nombre y email para sus commits.
2. **Token de DOMO** — el developer token de su cuenta.
3. **URL del MCP de Zoho** — la URL HTTP del MCP de Zoho Projects.

El **host de DOMO** y el **repo del cliente DOMO** son constantes (no se preguntan).

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
$skill = "<base directory of this skill>"
pwsh -NoProfile -File "$skill\scripts\apply-env.ps1" -ConfigPath $cfgPath
```

El script setea `SOUTHPOINT_GIT_NAME`, `SOUTHPOINT_GIT_EMAIL`, `DOMO_SOUTHPOINT_TOKEN`, `ZOHO_SOUTHPOINT_MCP_URL` como variables de usuario persistentes y devuelve un resumen JSON (solo nombres + estado). Si sale con error, reportá el mensaje y no sigas.

## Step 4 — Instalar los clientes

```powershell
$skill = "<base directory of this skill>"
pwsh -NoProfile -File "$skill\scripts\install-clients.ps1"
```

Clona el cliente DOMO —el repo oficial `DomoApps/domo-mcp-server`, que **no es un paquete pip**— a `~/.claude/domo-mcp-server`, instala sus dependencias (`pip install -r requirements.txt`) y **setea `DOMO_MCP_HOME`** apuntando ahí; además instala los browsers de Playwright (chromium). Devuelve un resumen con `installed`, `skipped`, `prereqsMissing` y `domoHome`. **No abortes** si reporta prereqs faltantes (Git/Python/Node): seguí y listalos en el reporte como pasos guiados.

## Step 5 — Reporte

Reportá: qué env vars quedaron seteadas (solo nombres) —incluida `DOMO_MCP_HOME`, que `install-clients` deja apuntando al clone de DOMO—, qué clientes se instalaron, qué prerequisitos faltan (con la instrucción exacta para resolverlos), y el recordatorio de **reiniciar Claude Code** para que tome las env vars nuevas. Cerrá con: "Máquina lista para Southpoint — ya podés usar `bootstrap-southpoint-project` en cualquier proyecto."
