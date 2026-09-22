---
name: setup-mcp-workstation
description: Use ONCE per Windows PC (and again to rotate credentials or to install, repair or check the daily hub-sync task) to prepare a machine for SOUTHPOINTLABS work — first-time workstation setup that asks for the user's git identity, DOMO developer token and Zoho MCP URL, persists them as user env vars, installs the machine-level clients (clones the DOMO MCP client + its deps, Playwright browsers), and installs the daily hub-sync Scheduled Task that collects this dev's closed slices and pushes them to the PROJECT MANAGEMENT inbox. Trigger when someone says "configurá/prepará mi máquina o la compu", "dejá lista la workstation", "setup inicial de la PC", "máquina/laptop nueva del laburo", "onboarding de un compañero nuevo", "dejá lista la máquina para Southpoint/HSS", "persistí mi token de DOMO y la URL del MCP de Zoho como variables de entorno", "instalá el cliente de DOMO o los browsers de Playwright a nivel máquina", "quiero rotar/actualizar el token de DOMO ya configurado", "instalá/repará la tarea de hub-sync en mi PC", "la tarea diaria no está recolectando", "por qué no llegan mis propuestas a la bandeja", or when bootstrap-southpoint-project reports the machine is not configured / the DOMO env vars are missing. This is a per-MACHINE setup (run once, plus credential rotation and the hub-sync task) — NOT a per-project setup. For per-project scaffolding use bootstrap-southpoint-project; debugging a broken MCP inside one project is a project/debug task, not this.
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

**Si el pedido es sobre la tarea de hub-sync** —instalarla, repararla, o entender por qué no está recolectando— no re-configures la máquina: saltá derecho al **Step 5**, corré primero `-Action status` y actuá según lo que informe (no instalada → `-Action install`; instalada pero con fallas → el motivo está en el log que `status` devuelve). Re-aplicar desde el Step 2 vuelve a pedir credenciales y a reinstalar clientes para nada.

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

## Step 5 — Instalar la tarea diaria de hub-sync

```powershell
$skill = "<base directory of this skill>"
pwsh -NoProfile -File "$skill\scripts\hub-sync-tarea.ps1" -Action install
```

Registra la Scheduled Task `hub-sync`: todos los días a las 18:00 —y al iniciar sesión, si a esa hora la PC estaba apagada o con la sesión cerrada— recorre los repos que el PM cargó para este dev en `hub-sync/repos.json` de PROJECT MANAGEMENT y manda los slices cerrados a la bandeja. **La serie arranca mañana**: el día que se instala no recolecta (así el onboarding no dispara una corrida con `gh` todavía sin loguear), y si el dev quiere ver una corrida hoy, `-Action correr`.

Devuelve un JSON con `instalada`, `ejecutable` y `argumentos`. Sale con código != 0 en dos casos, y hay que distinguirlos en el reporte: si **el Programador la rechaza**, el motivo queda en `%LOCALAPPDATA%\hub-sync\hub-sync.log`; si **no encuentra un `pwsh.exe` de ruta estable**, falla antes de tocar el Programador y lo dice por stderr — ahí el dev tiene que instalar PowerShell 7 (MSI) o rehabilitar el alias de ejecución de la Store, y recién después re-correr el paso. Instalarla dos veces deja una sola tarea, así que re-correr la skill es seguro.

La tarea **necesita `gh` logueado con la cuenta `southpointtech`** (`gh auth login`) para leer esa lista: sin token no recolecta y lo dice en el log. Si el dev todavía no está en la lista, la tarea igual queda instalada y cada corrida anota `sin repos en la lista`.

Los otros verbos, para el reporte y para diagnosticar: `-Action status` (si está instalada + cómo fue la última corrida, por repo), `-Action uninstall` (la saca) y `-Action correr` (la corre a mano, sin esperar las 18:00).

## Step 6 — Reporte

Reportá: qué env vars quedaron seteadas (solo nombres) —incluida `DOMO_MCP_HOME`, que `install-clients` deja apuntando al clone de DOMO—, qué clientes se instalaron, qué prerequisitos faltan (con la instrucción exacta para resolverlos), si la tarea `hub-sync` quedó instalada (y, si falta la cuenta `southpointtech` en `gh`, que hasta arreglarlo no va a recolectar), y el recordatorio de **reiniciar Claude Code** para que tome las env vars nuevas. Cerrá con: "Máquina lista para Southpoint — ya podés usar `bootstrap-southpoint-project` en cualquier proyecto."
