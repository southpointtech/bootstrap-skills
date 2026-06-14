# Session Handoff — 2026-06-14 (e2e setup-mcp-workstation + enriquecimiento de descripciones)

## ▶ AL RETOMAR — trabajo cerrado y commiteado; solo queda `README.md` sin commitear (el usuario lo está editando)

No hay tarea de código pendiente. Esta sesión: (1) corrió un **e2e completo de `setup-mcp-workstation`** (todo verde) y (2) **enriqueció las descripciones de las 14 skills** del repo con más enunciados de trigger, ya deployadas y commiteadas (`023cb05`).

**Lo único en el working tree:** `README.md` modificado (`SOUTHPOINTLABS` → `SOUTHPOINT LABS`, 2 líneas). **NO lo toques** — Martín lo está editando a mano. Ese cambio NO lo generó esta sesión ni `sync-skills.ps1`. Dejarlo como está salvo que Martín pida otra cosa.

---

## Qué es el proyecto

`C:\Repos\PERSONAL\Bootstrap Skills` es la **fuente de verdad** de las skills de Claude Code que bootstrapean proyectos:
- `bootstrap-southpoint-project` — proyectos cliente SOUTHPOINTLABS (DOMO/Zoho).
- `bootstrap-personal-project` — proyectos personales de Martín.
- `upgrade-bootstrap` — actualiza proyectos ya bootstrapeados al scaffold actual.
- `setup-mcp-workstation` — prepara una PC Windows 1× por máquina.

Editar acá NO tiene efecto hasta deployar con `pwsh -NoProfile -File tools/sync-skills.ps1` (copia repo → `~/.claude/skills/`, borra la instalada primero, y **regenera los `.bootstrap-manifest.json` de las bootstrap**). Identidad de commit: `MartinDele703 <martin.deleon703@gmail.com>` (ya local). Se trabaja directo en `main`.

## Trabajo de esta sesión

### 1. E2E de `setup-mcp-workstation` (aislado + verificación del estado real) — TODO VERDE
- **Tests unitarios:** 3 suites pasan (`tests/apply-env.tests.ps1` 12, `tests/install-clients.tests.ps1` 17, `tests/gen-mcp-json.tests.ps1` 26).
- **Cadena aislada (DryRun + temp):** apply-env (no filtra secretos; detecta `set`/`unchanged` contra el estado real), install-clients (modelo clone correcto), gen-mcp-json (genera `.mcp.json` con `PYTHONPATH=${DOMO_MCP_HOME}`, `command=${DOMO_MCP_PYTHON:-python}`, `args=-m domo_mcp`, token/host/zoho OK).
- **Integración cruzada:** lo que apply-env + install-clients proveen ⊇ lo que gen-mcp-json requiere (`DOMO_SOUTHPOINT_TOKEN`, `DOMO_MCP_HOME`, `ZOHO_SOUTHPOINT_MCP_URL`).
- **Estado real de la PC de Martín:** el clone DOMO que usa hoy (`C:\Repos\SOUTHPOINTLABS\domo-mcp-server`) es git repo sano y `python -m domo_mcp` importa. Instalada (`~/.claude/skills/setup-mcp-workstation`) == repo, hash a hash.
- **Triggering (skill-creator, juez-router):** 15/16 queries OK.

### 2. Enriquecimiento de descripciones (pedido de Martín) — DEPLOYADO + COMMITEADO `023cb05`
**Motivación:** el e2e detectó que "rotar el token de DOMO" NO disparaba `setup-mcp-workstation` (la descripción decía solo "ONCE/first-time"). Martín pidió agregar varios enunciados a TODAS las descripciones, no solo rotar token.

Se agregaron frases de trigger realistas (es/en) a **14 descripciones únicas → 24 archivos `SKILL.md`**:
- **4 top-level:** `setup-mcp-workstation`, `bootstrap-southpoint-project`, `bootstrap-personal-project`, `upgrade-bootstrap`.
- **10 del scaffold (espejadas en personal/southpoint):** `grill-me`, `grill-with-docs`, `zoom-out`, `tdd`, `to-prd`, `review-loop`, `setup-matt-pocock-skills`, `handoff`, `triage`, `to-issues`.

**Verificación:** diff toca SOLO líneas `description:` (24 ins/24 del); 24/24 frontmatters YAML válidos (chequeado con `python -c "import yaml"` vía `os.walk`); 3 suites verdes tras el cambio. Deploy regeneró los 2 manifests (de ahí las 46 líneas del commit: 24 SKILL.md + hashes en manifests).

## Decisiones / cómo se aplicó (para reproducir)
- Las parejas personal/southpoint del scaffold tienen **descripción idéntica** → se aplica el mismo texto a ambas.
- Para editar 24 archivos sin romper EOL/encoding se usó un script PowerShell con `[regex]'(?m)^description:.*$'` (reemplaza solo esa línea, preserva el resto), leyendo cada descripción nueva de un `.txt` temporal (evita escaping). Validó 1 reemplazo por archivo. Sandbox temporal borrado.
- El warning git "LF will be replaced by CRLF" en los `.md` es pre-existente (archivos en LF) e inofensivo; el `--stat` confirma 1 línea cambiada por archivo.

## Estado de verificación
- ✅ Todo lo de código commiteado en `023cb05` (sobre `1032648`).
- ✅ Skills deployadas y activas en `~/.claude/skills/` (Claude Code las recargó en la sesión).
- ⏳ `README.md` modificado sin commitear (de Martín, NO tocar).
- ⚠️ La PC de Martín está configurada "a mano": el config canónico `~/.claude/mcp-workstation.local.json` NO existe, `SOUTHPOINT_GIT_NAME/EMAIL` no están, y `DOMO_MCP_HOME` apunta a `C:\Repos\SOUTHPOINTLABS\domo-mcp-server` (no a `~/.claude/...`). El Step 0 de la skill lo trataría como "no configurado" (comportamiento correcto). No es un bug; solo se migra al layout canónico si corre la skill.

## Reglas del repo (no olvidar)
- Las dos skills bootstrap se mantienen **espejadas en estructura**; todo cambio de mecánica va en ambas. Solo difieren en DOMO e identidad git.
- Editar skills acá NO tiene efecto hasta `tools\sync-skills.ps1` (regenera manifests).
- NO usar wildcard `scaffold\*` en los copy de PowerShell (anida `.agents\.agents`).
- `gitignore.txt` en assets aterriza como `.gitignore` (no renombrar en el repo).
- El `.bootstrap-manifest.json` es generado; lo regenera `sync-skills.ps1`.
- Rastros de testeo (workspaces de evals/sandboxes temp) se borran al terminar.

## Gotchas técnicos (vigentes)
- `run_loop.py` del skill-creator (optimizador de descripción) está **roto en Windows** → el eval de triggering se hizo a mano con un subagente-juez que actúa de router de skills. Funcionó bien.
- Eval de una skill que muta la máquina: SIEMPRE aislar (`-DryRun`, config y `-DomoHome` en temp). Documentado en `docs/TESTING.md`.
- pwsh: `$PSNativeCommandUseErrorActionPreference=$false` en install-clients para que prereqs faltantes no aborten; `.ToArray()` (no `@()`) al serializar `List[object]` de `[ordered]` hashtables.

## Próximos pasos recomendados
1. (Usuario) Terminar de editar `README.md` y commitearlo aparte cuando quiera.
2. No hay tarea de código pendiente. Si surge, arrancar con `superpowers:brainstorming` antes de tocar código.
3. Si se evoluciona el scaffold, deployar con `sync-skills.ps1` y commitear los manifests regenerados.
4. (Opcional) Re-evaluar el triggering de alguna skill con el juez-router si se sospecha over/under-triggering por los enunciados nuevos.
