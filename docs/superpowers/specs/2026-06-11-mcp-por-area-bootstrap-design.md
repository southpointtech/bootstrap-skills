# Spec — MCP servers por área en el bootstrap

- **Fecha:** 2026-06-11
- **Estado:** aprobado (brainstorming) — pendiente de plan de implementación
- **Repo:** Bootstrap Skills (fuente de verdad de las skills de bootstrap)
- **Skills afectadas:** `bootstrap-personal-project`, `bootstrap-southpoint-project` (espejadas), nota menor en `upgrade-bootstrap`

## Problema

Los MCP servers son el costo fijo de tokens dominante al arrancar cada sesión de Claude Code. Hoy viven en el **user scope** (`~/.claude.json`), así que cargan en TODOS los proyectos aunque ese proyecto no use esa herramienta. Además, Martín usa **distintas cuentas/tokens según el área**: Zoho personal vs Zoho Southpoint, Domo solo en Southpoint. El objetivo es **gastar tokens de MCP solo donde corresponde**, asociando cada herramienta al proyecto que la usa.

Claude Code soporta MCP de scope **project** (`.mcp.json` en la raíz del repo, commiteado): solo carga cuando abrís Claude Code dentro de ese proyecto, y **no consume tokens en otros proyectos**. Esa es la palanca.

## Objetivo

Que el bootstrap, al crear un proyecto, **pregunte qué herramientas MCP usa** (menú del catálogo del área) y materialice un `.mcp.json` commiteado con solo esos servers, usando `${VAR}` para secretos. El user scope global queda vacío.

## Decisiones tomadas (brainstorming)

1. **Catálogo total, global vacío** (no "menú complementa al global"). Ningún MCP en user scope; todo se elige por proyecto.
2. **Menú por proyecto** (no "siempre Zoho"): el bootstrap ofrece el catálogo completo del área y el usuario tilda lo que aplica.
3. **`.mcp.json` se commitea** (project scope canónico). Sin secretos dentro (solo `${VAR}`), seguro de versionar; habilita "clone and go" para los proyectos en equipo que vienen.
4. **Secretos por env var** `${VAR}` / `${VAR:-default}`, leídas del environment del shell. No se commitean tokens.
5. **Mecanismo: script determinístico** `gen-mcp-json.ps1` (Enfoque 3), consistente con el patrón del repo (`gen-manifest.ps1`, `merge-settings.ps1`, `compare-scaffold.ps1`). Claude solo muestra el menú; el script arma el JSON.

## Diseño

### Modelo general

- **Global (`~/.claude.json` user scope) → vacío.** Vaciarlo es un follow-up con stopgap (ver "Follow-ups"), no código de la skill.
- Cada bootstrap muestra el **menú del catálogo de su área**; lo seleccionado se escribe en `<proyecto>/.mcp.json` (commiteado), con `${VAR}` para secretos.
- `.mcp.json` es **archivo per-proyecto generado** (categoría "Step 3 — project-specific files", como `README.md`/`CONTEXT.md`): NO va en `assets/scaffold/`, NO lo trackea el `.bootstrap-manifest.json`, NO lo toca `upgrade-bootstrap`.

### Catálogos por área (data embebida en el script)

Cada entrada define: `key`, el bloque de config del server (con `${VAR}` para secretos y paths machine-specific), `requiredEnvVars` y `prereqs`.

| key | Áreas | Config (resumen) | requiredEnvVars | prereqs |
|---|---|---|---|---|
| `firebase` | personal + southpoint | `npx -y firebase-tools@latest experimental:mcp` | — | `firebase login` una vez |
| `zoho-personal` | personal | `type: http`, `url: ${ZOHO_PERSONAL_MCP_URL}` | `ZOHO_PERSONAL_MCP_URL` | — |
| `zoho-projects` | southpoint | `type: http`, `url: ${ZOHO_SOUTHPOINT_MCP_URL}` | `ZOHO_SOUTHPOINT_MCP_URL` | — |
| `github` | personal + southpoint | `docker run -i --rm -e GITHUB_PERSONAL_ACCESS_TOKEN ghcr.io/github/github-mcp-server`, `env.GITHUB_PERSONAL_ACCESS_TOKEN: ${GITHUB_PERSONAL_ACCESS_TOKEN}` | `GITHUB_PERSONAL_ACCESS_TOKEN` | Docker corriendo |
| `domo` | southpoint | `command: ${DOMO_MCP_PYTHON:-python}`, `args: [-m, domo_mcp]`, `env: { DOMO_DEVELOPER_TOKEN: ${DOMO_SOUTHPOINT_TOKEN}, DOMO_HOST: hssstaffing.domo.com, PYTHONPATH: ${DOMO_MCP_HOME}, PYTHONIOENCODING: utf-8 }` | `DOMO_SOUTHPOINT_TOKEN`, `DOMO_MCP_HOME` | checkout local de `domo-mcp-server` |

Notas:
- **Personal**: `firebase`, `zoho-personal`, `github`. **Southpoint**: `firebase`, `domo`, `zoho-projects`, `github`.
- Los paths machine-specific de `domo` (python, checkout de `domo-mcp-server`) van por `${VAR}` (`DOMO_MCP_PYTHON` con default `python`, `DOMO_MCP_HOME`) para que el `.mcp.json` commiteado sea portable entre máquinas/equipo.
- `firebase` usa `experimental:mcp` (la forma que conecta OK hoy en el `.claude.json` real).

### Script `gen-mcp-json.ps1`

- **Ubicación:** `skills/<skill>/scripts/gen-mcp-json.ps1` (fuera de `assets/scaffold/`, igual que `upgrade-bootstrap/scripts/`). Una copia por skill; difieren solo en la data del catálogo del área.
- **Firma:** `-ProjectDir <ruta> -Servers <string[] de claves> [-Force]`.
- **Comportamiento:**
  - Valida cada clave de `-Servers` contra el catálogo del área; si una no existe, error claro (no escribe nada).
  - Arma el objeto `{ "mcpServers": { ... } }` con las entradas elegidas y lo escribe a `<ProjectDir>/.mcp.json` como JSON válido (UTF-8, sin BOM).
  - Si `-Servers` está vacío → no escribe archivo (sale informando "ningún server seleccionado").
  - Si `<ProjectDir>/.mcp.json` ya existe y no se pasó `-Force` → no pisa; error/aviso.
  - **Emite a stdout un resumen estructurado** (JSON) de: servers escritos, `requiredEnvVars` (unión de los elegidos), `prereqs`. Claude lo usa para el reporte final.
- **Determinístico:** mismas entradas → mismo `.mcp.json`. Testeable de forma aislada.

### Cambio en el SKILL.md (espejado en ambas skills)

Los Steps actuales son: 0 Safety · 1 Project info · 2 Copy scaffold · 3 Project-specific files · 4 Git · 5 Report. Se inserta un **nuevo Step 4 — MCP servers** entre el actual Step 3 (project-specific files) y el commit, y se renumera: Git 4→5, Report 5→6. Idéntico en las dos skills. El nuevo step:

1. Claude presenta el catálogo del área con `AskUserQuestion` (multiSelect): "¿Qué herramientas MCP usa este proyecto?".
2. Corre `gen-mcp-json.ps1 -ProjectDir $proj -Servers <elegidas>`.
3. Captura el resumen del script (env vars + prereqs) para el reporte de cierre.
4. Si el usuario no elige ninguna → no se crea `.mcp.json`; se sigue.

El `.mcp.json` queda incluido en el commit del scaffolding (Step Git).

### Reporte de cierre

Lista, para lo seleccionado, las **env vars a setear como variables de usuario de Windows** (persistentes) y los prerequisitos. Ejemplo (southpoint con domo + zoho + github):
- `ZOHO_SOUTHPOINT_MCP_URL=<url completa>`
- `DOMO_SOUTHPOINT_TOKEN=<token>`, `DOMO_MCP_HOME=<ruta a domo-mcp-server>`
- `GITHUB_PERSONAL_ACCESS_TOKEN=<pat>` + Docker Desktop corriendo
- `firebase login` (una vez) si se eligió firebase

**No** se shipea `.env.example`: Claude Code expande `${VAR}` desde el environment del shell, no desde un `.env` del proyecto — un `.env.example` confundiría.

## Fuera de alcance (YAGNI, v1)

- `.env.example` o doc de catálogo shipeado al proyecto.
- Merge automático de `.mcp.json` en `upgrade-bootstrap`.
- Comando para "agregar un server del catálogo" a un proyecto existente.

## Interacción con el resto del sistema

- **Manifest / scaffold:** no se agrega nada a `assets/scaffold/` ni a `gitignore.txt`. El `.bootstrap-manifest.json` no cambia (el script vive fuera del scaffold; `.mcp.json` es generado per-proyecto). `gitignore.txt` no ignora `.mcp.json`, así que se commitea.
- **`upgrade-bootstrap`:** como `.mcp.json` no está en el manifest, `compare-scaffold.ps1` no lo ve → no lo pisa nunca. Para que un proyecto **ya** bootstrapeado obtenga un `.mcp.json`, el usuario corre el menú a mano. Opcional v1: una nota en `upgrade-bootstrap` mencionando la capacidad nueva.

## Testing (regla del repo: testear antes de deployar)

1. **Eval de directorio vacío:** el bootstrap corre, aparece el menú, se escribe un `.mcp.json` válido con lo elegido, y el reporte lista las env vars correctas.
2. **Eval de archivos preexistentes:** si ya hay un `.mcp.json`, no se pisa (sin `-Force`).
3. **Chequeo aislado del script:** varias selecciones (incl. "ninguna" → sin archivo; clave inválida → error; selección con domo → env vars de domo en el resumen). Validar que el `.mcp.json` parsea como JSON.
4. Tras pasar: `tools/sync-skills.ps1` (regenera manifests y deploya) y commit con identidad local `MartinDele703`.

## Follow-ups (fuera de esta feature)

- **Vaciar el user scope global** una vez que los proyectos activos tengan su `.mcp.json` y las env vars estén seteadas: `claude mcp remove` de firebase, github, domo, zoho-projects. Hasta entonces, el global queda como stopgap (ya se sacó blender y el bloque muerto de `settings.json`).
- **Rotar secretos en texto plano** del `.claude.json` actual (PAT de GitHub, tokens de DOMO) al migrarlos a env vars.

## Espejado y hard rules del repo

- Las dos skills deben quedar **espejadas en estructura**: mismo Step nuevo, mismo script; difieren solo en la data del catálogo (personal vs southpoint) e identidad git.
- No usar wildcard `scaffold\*` (no aplica acá: no tocamos la copia del scaffold).
- Cualquier rastro de testeo se borra al terminar.
