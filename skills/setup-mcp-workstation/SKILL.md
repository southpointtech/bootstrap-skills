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
