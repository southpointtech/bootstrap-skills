# Design — `setup-mcp-workstation` (setup de PC, una vez por máquina)

**Fecha:** 2026-06-14
**Estado:** aprobado (brainstorming) → pendiente de plan de implementación
**Origen:** compartir las Bootstrap Skills con un compañero nuevo de trabajo. Hoy el setup de credenciales/MCPs es manual y está atado al entorno de Martín (identidad git hardcodeada, env vars seteadas a mano, prerequisitos manuales). Esta feature mueve ese setup a una skill dedicada que corre **una vez por máquina** y deja todo listo para que el compañero solo use `bootstrap-southpoint-project` normalmente.

---

## 1. Objetivo y no-objetivos

**Objetivo:** que un compañero, en una PC nueva (Windows), ejecute una skill, ingrese sus credenciales una sola vez (respondiendo preguntas o llenando un archivo), y quede con la máquina lista para trabajar en proyectos Southpoint: identidad git propia, tokens de DOMO/Zoho persistidos, y los MCPs/clientes (DOMO vía pip, Playwright browsers) instalados. De ahí en más, no toca nunca la terminal.

**No-objetivos:**
- No es un setup por-proyecto (eso lo sigue haciendo `bootstrap-*-project` Step 4 con `.mcp.json`).
- No cubre github ni firebase del catálogo MCP (quedan con env vars manuales, como hoy).
- No hay wizard de credenciales personal (solo se mirrorea la parametrización de identidad git en `bootstrap-personal-project`).
- No instala dependencias de sistema que requieren admin/interacción de forma silenciosa (Docker Desktop, Python, Node, `firebase login`): las **verifica y guía**.

---

## 2. Decisiones de diseño (y por qué)

| Decisión | Elegido | Por qué |
|---|---|---|
| Dónde vive el setup | **Skill aparte** `setup-mcp-workstation` | Frecuencia distinta (1×/PC vs 1×/proyecto); se testea aislada; se escribe una vez (no se duplica en las dos bootstrap); reutilizable para cualquier compañero. |
| Persistencia de secretos | **Archivo único como fuente de verdad** (`~/.claude/mcp-workstation.local.json`) + la skill aplica **env vars persistentes de usuario** | El usuario quiere "que sea un archivo y listo", sin correr comandos. El `.mcp.json` resuelve `${VAR}` desde el **entorno del proceso** (confirmado: `settings.json`→`env` NO está documentado para expandir en `.mcp.json`), así que la vía verificada son env vars de usuario. La skill las aplica vía API .NET (`SetEnvironmentVariable(...,'User')`), sin admin, sin que el usuario tipee `setx`. |
| Agresividad de instalación | **Híbrido** | Auto-hace lo no-admin/no-interactivo (env vars, `pip install`, `npx playwright install`, identidad git); verifica+guía lo que necesita admin/interacción (Python, Node). |
| Alcance de credenciales | **git + DOMO + Zoho** | Lo que el usuario pidió. github/firebase fuera. |
| Origen de `domo_mcp` | **`pip install`** | El módulo es pip-installable; no hay checkout ni clone. Elimina la confusión git↔domo y simplifica el catálogo. |

---

## 3. Arquitectura

Tres piezas, con responsabilidades aisladas:

### 3.1 La skill `setup-mcp-workstation`
`skills/setup-mcp-workstation/SKILL.md` + scripts. Orquesta el flujo:

1. **Detectar estado de la máquina** (first-run vs ya-configurada): existencia del archivo de config + de las env vars esperadas.
2. **Obtener valores**: si el archivo no existe, preguntar los 4 valores con `AskUserQuestion` y escribir el archivo. Si existe, leerlo. (El usuario también puede editar el archivo a mano y re-correr.)
3. **Aplicar** (idempotente): persistir env vars, instalar/verificar clientes.
4. **Reportar**: qué quedó seteado, qué falta (ej. reiniciar Claude Code para tomar las env vars; instalar Python/Node si faltaban), y "máquina lista".

### 3.2 El archivo de config (fuente de verdad)
`~/.claude/mcp-workstation.local.json` — fuera de todo repo, nunca commiteado:

```json
{
  "git":  { "name": "Nombre Apellido", "email": "nombre@agtium.com" },
  "domo": { "token": "<DOMO developer token>" },
  "zoho": { "mcpUrl": "https://..." }
}
```

- El **host de DOMO** y el **comando/fuente del pip** son constantes de la skill, no van en el archivo.
- El archivo es el registro persistente: para rotar un token, se edita y se re-corre la skill.

### 3.3 Script de aplicación
`skills/setup-mcp-workstation/scripts/apply-workstation.ps1` — toma el archivo de config y:

- Setea las env vars persistentes de usuario:
  - `SOUTHPOINT_GIT_NAME`, `SOUTHPOINT_GIT_EMAIL`
  - `DOMO_SOUTHPOINT_TOKEN`
  - `ZOHO_SOUTHPOINT_MCP_URL`
- Devuelve un resumen JSON (qué seteó, qué prerequisitos faltan) para que la SKILL arme el reporte.

> Nota de implementación: el script NO debe imprimir los valores de los tokens en su salida (solo nombres de vars + estado), para no filtrarlos en logs/transcripts.

---

## 4. Flujo de instalación (híbrido)

| Cliente | Acción de la skill | Si falta el prerequisito |
|---|---|---|
| **DOMO MCP** | `pip install <paquete-domo>` (fuente exacta = constante de la skill, provista al implementar) | Verifica Python en PATH; si falta, lo reporta como paso guiado (no instala Python). |
| **Zoho MCP** | Nada que instalar (solo la env var `ZOHO_SOUTHPOINT_MCP_URL`). | — |
| **Playwright** | `npx playwright install chromium` (browsers machine-level, cacheados en `~/AppData/Local/ms-playwright`). Solo chromium por defecto. | Verifica Node/npx; si falta, lo reporta como paso guiado. |
| **Git** | No instala nada; deja la identidad como env vars que el bootstrap leerá. | — |

Idempotencia: `pip install` y `npx playwright install` son seguros de re-correr; el script detecta lo ya hecho y no rehace de más.

---

## 5. Cambios en las skills de bootstrap

### 5.1 Identidad git parametrizada (ambas, espejadas)
Step 5 deja de hardcodear la identidad. Lee env vars **por área** con fallback a la identidad actual de cada skill:

- `bootstrap-southpoint-project`:
  ```powershell
  git config user.name  "$($env:SOUTHPOINT_GIT_NAME  ?? 'southpointtech')"
  git config user.email "$($env:SOUTHPOINT_GIT_EMAIL ?? 'mdeleon@agtium.com')"
  ```
- `bootstrap-personal-project`:
  ```powershell
  git config user.name  "$($env:PERSONAL_GIT_NAME  ?? 'MartinDele703')"
  git config user.email "$($env:PERSONAL_GIT_EMAIL ?? 'martin.deleon703@gmail.com')"
  ```

Esto respeta la hard rule de skills espejadas (mismo mecanismo en ambas, solo difieren las constantes de fallback) y permite compartir cualquiera de las dos a futuro. Si nadie corre el wizard, el comportamiento actual no cambia (cae al fallback).

### 5.2 Derivación desde `bootstrap-southpoint-project` Step 0
Chequeo liviano: "¿la máquina está configurada para Southpoint?" (heurística: existen `SOUTHPOINT_GIT_NAME` y `DOMO_SOUTHPOINT_TOKEN`, o existe el archivo de config). Si no → no bloquear el bootstrap, pero **avisar y recomendar** correr `setup-mcp-workstation` primero, y notarlo en el reporte del Step 6. No se mete el wizard adentro del bootstrap.

### 5.3 Catálogo MCP — quitar `DOMO_MCP_HOME`
Con `domo_mcp` instalado por pip en el entorno, `python -m domo_mcp` corre sin `PYTHONPATH`. Cambios:

- `skills/bootstrap-southpoint-project/scripts/gen-mcp-json.ps1`: el server `domo` pierde `PYTHONPATH=${DOMO_MCP_HOME}` de su `env` y `DOMO_MCP_HOME` de `requiredEnvVars`. El prereq "checkout local de domo-mcp-server" se reemplaza por "domo_mcp instalado (lo hace setup-mcp-workstation)".
- `skills/bootstrap-personal-project/scripts/gen-mcp-json.ps1`: idem si tiene el mismo bloque (verificar al implementar; mantener espejado).
- `tests/gen-mcp-json.tests.ps1`: actualizar las aserciones que esperan `DOMO_MCP_HOME` en `requiredEnvVars`/`env` del server domo.

---

## 6. Manejo de errores

- **Archivo de config malformado / faltante de campos** → la skill lo detecta, dice qué campo falta y vuelve a preguntar (no aplica nada a medias).
- **`pip` / `npx` ausentes** → no es error fatal: se reporta como prerequisito guiado y se sigue con el resto (env vars sí se aplican).
- **`pip install` o `npx playwright install` fallan** (red, índice privado sin acceso) → se reporta el comando exacto que falló y el error, sin abortar las env vars ya aplicadas. La skill termina con un reporte de "parcialmente listo: falta X".
- **Re-run** → seguro; detecta lo ya hecho.
- **Secretos en logs** → los scripts nunca imprimen valores de tokens, solo nombres de vars y estado.

---

## 7. Testing (evals con skill-creator)

Skill nueva `setup-mcp-workstation`:
- (a) **PC limpia** (sin archivo, sin env vars) → crea el archivo con los valores ingresados y aplica las env vars (aplicación mockeada/dry-run para no ensuciar el entorno real del eval).
- (b) **Re-run idempotente** → con archivo y env vars ya presentes, no rehace de más, reporta "ya configurada".
- (c) **Rotación de token** → archivo editado con token nuevo → re-aplica solo esa var.
- (d) **Prerequisito faltante** (Python/Node ausente) → reporta paso guiado sin abortar el resto.

Cambios en bootstrap:
- (e) Step 5 toma `SOUTHPOINT_GIT_NAME`/`EMAIL` si existen; cae al fallback `southpointtech` si no.
- (f) Mismo para personal con `PERSONAL_GIT_*` → fallback `MartinDele703`.
- (g) `gen-mcp-json.ps1` genera el server domo sin `DOMO_MCP_HOME`; tests verdes.

Más los evals mínimos de siempre del repo (directorio vacío + archivos preexistentes) para ambas bootstrap, por el cambio de Step 5.

---

## 8. Deploy y reglas del repo

- Deploy con `tools/sync-skills.ps1` (copia repo → `~/.claude/skills/`), que ahora también copia `setup-mcp-workstation`.
- Regenerar manifests de las bootstrap (cambian SKILL.md y scripts) — lo hace el propio `sync-skills.ps1`.
- Commit con identidad local `MartinDele703 <martin.deleon703@gmail.com>` (regla del repo).
- Actualizar `README.md` y `docs/HISTORIA.md` con la nueva skill y el flujo de onboarding para un compañero nuevo.

---

## 9. Detalles a definir al implementar (no bloquean el diseño)

1. **Comando/fuente exacto del `pip install`** de `domo_mcp` (PyPI público / índice privado / `git+https`). Martín lo provee; va como constante en la skill.
2. Confirmar que `bootstrap-personal-project` tiene el mismo bloque domo en su `gen-mcp-json.ps1` (para espejar el cambio de `DOMO_MCP_HOME`).
3. Confirmar la heurística exacta de "máquina configurada" del Step 0 (qué env var/archivo se chequea).
