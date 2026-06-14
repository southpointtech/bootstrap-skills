# Session Handoff — 2026-06-14 (README público para la empresa + repo en GitHub)

## ▶ AL RETOMAR — el repo YA ESTÁ EN GITHUB; mañana solo falta "subamos el repo" (push de pendientes + dar acceso a ecardozo)

**LEÉ ESTO PRIMERO para no duplicar trabajo:** el repo **ya fue creado y pusheado hoy** a
`https://github.com/southpointtech/bootstrap-skills` (privado, bajo la cuenta `southpointtech`, que es la **oficial**).
El remote `origin` ya está configurado y `main` ya está pusheada (5 commits de esta sesión incluidos).
**NO crear un repo nuevo.** Todo el trabajo de README está commiteado — el working tree está limpio.

Cuando el usuario diga **"subamos el repo"** mañana, lo que realmente queda es:
1. `git push` de cualquier cambio que se haga mañana (p. ej. el fix de nombre, ver Pendientes).
2. **Dar acceso a `ecardozo`** (hoy el usuario NO pudo iniciar sesión con `ecardozo@south...`). Necesitás el **username de GitHub de ecardozo**. Comando listo:
   ```bash
   gh api --method PUT /repos/southpointtech/bootstrap-skills/collaborators/<USERNAME_ECARDOZO> -f permission=push
   ```
   (gh está logueado con `southpointtech` —activa— y `MartinDele703`. Confirmá la cuenta activa con `gh auth status` antes.)

---

## Qué es el proyecto

`C:\Repos\PERSONAL\Bootstrap Skills` es la **fuente de verdad** de las skills de Claude Code que bootstrapean proyectos:
- `bootstrap-southpoint-project` — proyectos cliente SOUTHPOINTLABS (DOMO/Zoho).
- `bootstrap-personal-project` — proyectos personales.
- `upgrade-bootstrap` — actualiza proyectos ya bootstrapeados al scaffold actual.
- `setup-mcp-workstation` — prepara una PC Windows 1× por máquina.

Editar las skills acá NO tiene efecto hasta deployar con `pwsh -NoProfile -File tools/sync-skills.ps1`.
**Commits con identidad `MartinDele703 <martin.deleon703@gmail.com>`** (esta sesión los hizo con
`git -c user.name="MartinDele703" -c user.email="martin.deleon703@gmail.com" commit ...`). Se trabaja directo en `main`.

## Objetivo de ESTA sesión — publicar el README para toda la empresa

Se reescribió el `README.md` (antes era interno/personal) para que sea **presentable a toda la empresa SOUTHPOINTLABS**:
qué es, por qué sirve, los componentes y cómo se usa. **Idioma elegido: inglés.** Despersonalizado (sin nombres/emails/handles individuales).

### Lo que se hizo (todo commiteado y pusheado)
- **Branding:** se copiaron el ícono y el wordmark de Southpoint a `docs/assets/` (`southpoint-icon.png`, `southpoint-logo.png`).
  El header usa el **ícono azul** (se ve en light y dark mode); el wordmark es texto blanco → invisible en light mode, por eso NO se usa en el header (queda como recurso de marca).
  - Fuentes: `C:\Repos\SOUTHPOINTLABS\Forecasting App\.scratch\presentation-build\assets\sp-logo.png` (wordmark) y `C:\Repos\SOUTHPOINTLABS\Task Manager\design\task-manager\project\assets\Logo.png` (ícono).
- **README reescrito** con secciones: What this is · Why it matters · How it works · The skills (las **4** top-level; antes faltaba `upgrade-bootstrap`) · What gets scaffolded · **The 8-step workflow** · **MCP servers & clients** · Getting started · Repository structure · Maintaining the skills.
- **Sección "The 8-step workflow"**: tabla fase→artefacto→skill (grill-me, PRD/SRS via to-prd, vertical slices via to-issues, tareas Zoho, TDD, QA, review-loop, human approval) + por qué importan los vertical slices.
- **Sección "MCP servers & clients"**: dos capas — clientes machine-level (DOMO client clonado + Playwright) y servers MCP por proyecto (catálogo `domo`/`zoho-projects`/`firebase`/`github` en `.mcp.json`), con la explicación de que los secretos viven en env vars (`${VAR}`) y nunca en el repo.
- **Subsección destacada "The review loop — the automated quality gate"** (pedido explícito del usuario: lo considera la pieza clave de calidad). Aclara que `review-loop` está bien implementada (SKILL + comando `/review-loop` + hook `review-loop-trigger` que la dispara solo en `gh pr create`/`git push`), el ciclo review→fix→re-review hasta cero findings medium/high, guardrails, y que el "5/5" de Greptile acá = "sin findings medium/high" (el reviewer reporta por severidad, no por score).

### Commits de esta sesión (sobre `1032648`)
```
ebfb0bc docs(readme): reescribir el README para publicación a la empresa (inglés + branding)
4c84e4a docs(readme): explicar los MCP servers y clientes (DOMO/Zoho/Firebase/GitHub + Playwright)
253064f docs(readme): explicar el flujo de 8 pasos y sus artefactos
f76370e docs(readme): destacar review-loop como el quality gate del proceso
```
(+ el commit que creó/pusheó el repo). **Nota:** se editaron solo `README.md` y `docs/assets/` — NO se tocaron las skills ni el scaffold, así que NO hace falta correr `sync-skills.ps1`.

## Decisiones de esta sesión
- **Cuenta oficial = `southpointtech`** (no MartinDele703). El repo queda ahí, privado. `ecardozo` solo necesita acceso como colaborador (no es el dueño).
- **Repo privado** (no público): es interno de la empresa; se puede abrir/compartir después.
- README en **inglés**, despersonalizado.

## Pendientes / próximos pasos
1. **(Mañana, "subamos el repo")** `git push` de pendientes + invitar a `ecardozo` como colaborador (comando arriba; falta su username de GitHub).
2. **Unificar el nombre en el README:** conviven "SOUTHPOINT LABS" (con espacio, en el header — lo puso el usuario a mano) y "SOUTHPOINTLABS" (junto, en tablas/prosa). Preguntar al usuario cuál es el oficial y dejarlo consistente (1 commit + push). **No cambiar sin confirmar cuál querés.**
3. (Opcional) ¿Invitar a más del equipo además de ecardozo? ¿Transferir a una org si la empresa crea una en GitHub?
4. (Opcional) El ícono pesa ~1 MB; se puede comprimir si se quiere aligerar el repo.

## Estado de verificación
- ✅ `README.md` + `docs/assets/` commiteados y pusheados a `origin/main`. Working tree limpio.
- ✅ Repo en GitHub: `southpointtech/bootstrap-skills` (privado). Assets verificados en el remoto (`git ls-tree -r origin/main` los lista) → el ícono del header renderiza.
- ✅ Skills y scaffold SIN cambios esta sesión (no requiere deploy).
- ⏳ Acceso de `ecardozo` pendiente (bloqueado hoy por no poder loguearse a esa cuenta).
- ℹ️ Se instaló `grip` (pip) para previsualizar el README local (`http://localhost:6419`); ese proceso muere al cerrar esta terminal. Con el repo en GitHub ya no hace falta.

## Reglas del repo (no olvidar)
- Las dos skills bootstrap se mantienen **espejadas en estructura**; todo cambio de mecánica va en ambas. Solo difieren en DOMO e identidad git.
- Editar skills acá NO tiene efecto hasta `tools\sync-skills.ps1` (regenera los `.bootstrap-manifest.json`).
- NO usar wildcard `scaffold\*` en los copy de PowerShell (anida `.agents\.agents`).
- `gitignore.txt` en assets aterriza como `.gitignore` (no renombrar en el repo).
- El `.bootstrap-manifest.json` es generado; lo regenera `sync-skills.ps1`.
- Rastros de testeo (workspaces de evals/sandboxes temp) se borran al terminar.

## Gotchas técnicos (vigentes)
- `run_loop.py` del skill-creator (optimizador de descripción) está **roto en Windows**.
- El warning git "LF will be replaced by CRLF" en los `.md` es pre-existente (archivos en LF) e inofensivo.
- `gh` tiene dos cuentas logueadas (`southpointtech` activa, `MartinDele703`); verificá la activa antes de operar sobre el repo.
