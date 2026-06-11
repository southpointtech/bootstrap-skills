# Session Handoff — 2026-06-11 (actualizado)

## Estado: working tree limpio, dos features grandes CERRADAS

El handoff anterior describía la feature de adopción como "no empezada"; eso quedó obsoleto. Ambas features están **implementadas, mergeadas a `main` y deployadas**. No quedan feature branches.

### ✅ Feature "adopción con merge de CLAUDE.md"
Step 0b (modo adopción) en ambos SKILL.md espejados. Commits: `ced0f02` (eval en TESTING.md), `3128abb` (southpoint), `8db1314` (personal), `39fbea5` (3 fixes post-eval + conteo 47 files). Eval real pasó: 5 assertions OK + `compare-scaffold.ps1` clasifica `CLAUDE.md` como `customized` (sellado emergente confirmado).

### ✅ Feature "MCP por área"
`gen-mcp-json.ps1` + Step 4 en ambas skills + tests (26 asserts). Catálogos: personal = firebase/zoho-personal/github; southpoint = firebase/domo/zoho-projects/github. El `.mcp.json` versionado solo referencia `${VAR}` (secretos por env var, nunca commiteados).

## Follow-ups pendientes (no son código)

1. **Env vars MCP** — ✅ 4/5 seteadas en scope User (2026-06-11): `DOMO_MCP_HOME`, `ZOHO_SOUTHPOINT_MCP_URL`, `DOMO_SOUTHPOINT_TOKEN` (valor actual), `GITHUB_PERSONAL_ACCESS_TOKEN` (valor actual). **Falta `ZOHO_PERSONAL_MCP_URL`** (solo la tiene Martín): `setx ZOHO_PERSONAL_MCP_URL "<url>"`.
2. **Rotar secretos en texto plano** — PAT de GitHub y `DOMO_DEVELOPER_TOKEN`. Tras rotar, re-setear `DOMO_SOUTHPOINT_TOKEN` y `GITHUB_PERSONAL_ACCESS_TOKEN` con los valores nuevos.
3. **Vaciar el user scope global de MCP** — `claude mcp remove firebase|github|domo|zoho-projects`. **BLOQUEADO** hasta que los proyectos activos tengan su `.mcp.json` (ahora ninguno lo tiene → sacar del global rompería todas las sesiones). Backup: `.claude.json.20260611-mcp-cleanup.bak`.
4. **Proyectos legacy** — diferido por decisión de Martín ("lo hago cuando lo vea necesario"). Correr `upgrade-bootstrap` (modo legacy) dentro de cada uno: Flash Audit, Planify AI, Nueva carpeta. Adopción (CLAUDE.md sin scaffold, usar `bootstrap-*`): Outsourcing Dev, Call Center 1/2, Customer Portal, KBS Orders.

### ✅ Follow-up ya resuelto (la memoria lo daba por pendiente)
**Forecasting App CLAUDE.md** YA tiene todas las reglas nuevas (anti supply-chain L76, PRs ≤400 + stacked L77-78, vendor L79, service layer L85, model selection L86, review-loop + hook L63). Nada que hacer.

### Env vars que esperan los catálogos (valores conocidos al 2026-06-11)
- `DOMO_MCP_HOME` = `C:\Repos\SOUTHPOINTLABS\domo-mcp-server` (PYTHONPATH del checkout local)
- `DOMO_SOUTHPOINT_TOKEN` = token DOMO actual (**a rotar** — poner el nuevo)
- `ZOHO_SOUTHPOINT_MCP_URL` = `https://zohoprojectsmcp-924788082.zohomcp.com/mcp/8cb285306e74aa4e506b0e418b6ee9c4/message`
- `ZOHO_PERSONAL_MCP_URL` = (cuenta Zoho personal — no registrada, el usuario la tiene)
- `GITHUB_PERSONAL_ACCESS_TOKEN` = PAT GitHub (**a rotar** — poner el nuevo; Docker debe estar corriendo)

## Reglas del repo (no olvidar)
- Las dos skills bootstrap se mantienen **espejadas en estructura**; todo cambio de mecánica va en ambas. Solo difieren en DOMO e identidad git.
- Editar skills acá NO tiene efecto hasta `tools\sync-skills.ps1` (regenera manifests).
- NO wildcard `scaffold\*` en los copy de PowerShell (anida `.agents\.agents`).
- Identidad de commit: `MartinDele703 <martin.deleon703@gmail.com>`.
- Rastros de testeo (workspaces de evals) se borran al terminar.
