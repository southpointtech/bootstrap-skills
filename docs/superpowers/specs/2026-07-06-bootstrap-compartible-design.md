# Bootstrap compartible — Design

**Fecha:** 2026-07-06
**Estado:** aprobado en sesión de brainstorming
**Frente:** #1 del roadmap (handoff 2026-07-05)

## Problema

El scaffold de `bootstrap-personal-project` filtra datos de Martín y de Southpoint:
Zoho en `CLAUDE.md` (steps 4/7 + sección issue tracker), `AI_DEVELOPMENT_WORKFLOW.md` §4,
`TASK_TEMPLATE.md`, `docs/agents/issue-tracker.md`, server `zoho-personal` en
`gen-mcp-json.ps1`, e identidad git default `MartinDele703`. No hay forma de regalarle
la metodología a un tercero sin regalarle también esos datos.

## Decisiones tomadas (con el usuario, 2026-07-06)

1. **Audiencia:** el tercero corre el bootstrap en SU máquina → la skill debe ser
   100% autocontenida (sin env vars de Martín, sin Zoho/DOMO, sin identidad hardcodeada).
2. **Distribución:** repo público en GitHub; actualizaciones vía `git pull` + re-install.
3. **Zoho →** genericizado a "your issue tracker" (GitHub Issues, Jira, …). La mecánica
   de vertical slices y el tracker local en `.scratch/` se preservan.
4. **Identidad git:** el Step 5 NO toca la identidad — usa la config global del tercero;
   si falta `user.name`/`user.email`, avisa y espera (no inventa una).
5. **Catálogo MCP:** `firebase` + `github` (sin `zoho-personal`). Mecánica `${VAR}` intacta.
6. **Idioma:** inglés puro (repo público → audiencia global).
7. **Alcance del repo público:** bootstrap + `upgrade-bootstrap` (ciclo de vida completo).
8. **Enfoque:** A — tercera skill espejada en este repo + export al repo público.
   Se descartó parametrizar con flavors (refactor de maquinaria probada, invalida
   manifests sellados) y el fork one-time (drift garantizado entre repos).

## Datos que sostienen el enfoque A

- Las dos skills existentes comparten **43/52 archivos byte-idénticos**; el costo real
  del espejado es ~7-9 archivos de contenido, no 52.
- `sync-skills.ps1` y `gen-manifest.ps1` operan sobre el glob `bootstrap-*-project` →
  la tercera skill obtiene deploy + manifest gratis.
- `upgrade-bootstrap` lee `generatedFrom` del manifest → integra la tercera variante
  sin cambios estructurales.

## Diseño

### 1. Nombres y ubicación

- **Skill nueva:** `skills/bootstrap-ai-project` (matchea el glob `bootstrap-*-project`;
  nombre autodescriptivo para el tercero — "shareable" no significa nada para él).
- **Repo público:** `MartinDele703/ai-project-bootstrap`:

  ```
  README.md            ← qué es, requisitos (Claude Code, pwsh 7+), instalación
  install.ps1          ← copia skills/* a $HOME/.claude/skills (borrado previo)
  skills/
    bootstrap-ai-project/
    upgrade-bootstrap/
  ```

- **Fuente de verdad:** este repo. El público es espejo de publicación alimentado por
  `tools/export-shareable.ps1`. Push al repo público con la cuenta `MartinDele703`
  (a diferencia de este repo, que se pushea con `southpointtech`).
- Flujo del tercero: clonar → `install.ps1` → "bootstrap this project" en Claude Code.
  Para actualizar: `git pull` → `install.ps1` → `/upgrade-bootstrap` en sus proyectos.

### 2. Contenido del scaffold compartible

Diverge **por diseño** en ~6 archivos:

| Archivo | Cambio |
|---|---|
| `CLAUDE.md` | Steps 4/7 → "task formatting for your issue tracker"; sección issue tracker sin Zoho; todo en inglés |
| `docs/ai-workflow/AI_DEVELOPMENT_WORKFLOW.md` | §4 genericizado (era "Zoho Task Formatting") |
| `docs/ai-workflow/TASK_TEMPLATE.md` | "Notes for Zoho" → "Notes for your tracker" |
| `docs/agents/issue-tracker.md` | Secundario: "your high-level tracker (GitHub Issues, Jira, …)" |
| `scripts/gen-mcp-json.ps1` | Catálogo: `firebase`, `github` |
| `SKILL.md` | Nuevo (ver §3) |

`PRD_TEMPLATE.md`, `QA_CHECKLIST.md`, `DEPLOYMENT_RULES.md`: la versión personal ya está
limpia → byte-idénticos en la compartible.

**Anglicización del canónico (aprobada):** hay 31 ocurrencias de español en 14 archivos
compartidos del scaffold (concentradas en el ecosistema review-loop: hook, comando,
SKILL.md). Se traducen **también en personal y southpoint**, así los 3 scaffolds quedan
byte-idénticos en todo lo no-variante y el espejado triple cuesta lo mismo que el doble.
Llega a los proyectos existentes vía `/upgrade-bootstrap` como outdated-safe.

**Plataforma:** el tooling es PowerShell; v1 declara `pwsh` 7+ como requisito en el
README (corre en Mac/Linux). No se porta a bash.

**Regla de espejado:** el bullet del `CLAUDE.md` de este repo pasa de "las dos skills"
a "las tres", aclarando que la compartible solo difiere en: tracker genérico, catálogo
MCP, identidad git y `SKILL.md`.

### 3. SKILL.md de `bootstrap-ai-project` + upgrade-bootstrap

Steps 0–6 idénticos a la variante personal (incluido el modo adopción 0b), con tres desvíos:

- **Step 4:** catálogo `firebase`/`github`. `GITHUB_PERSONAL_TOKEN` ya es genérico.
- **Step 5:** `git init -b main` + commit, sin identidad local. Verifica que exista
  `user.name`/`user.email` global; si falta, pide configurarla y espera.
- **Frontmatter:** inglés, triggers neutros ("bootstrap this project", "set up the AI
  workflow scaffolding", …). Cero referencias a Martín/Southpoint/Zoho.

**Colisión de triggers en la máquina de Martín** (las 3 skills instaladas): riesgo menor
aceptado — personal/southpoint tienen triggers muy específicos y la nueva queda neutra.
Si molesta, se agrega exclusión de deploy local después (YAGNI).

**`upgrade-bootstrap` (una sola skill, sin espejo, compartida con el repo público):**
(1) heurística legacy y descripción pasan de nombrar las dos skills a `bootstrap-*-project`;
(2) redacción en inglés genérico servible para ambas audiencias.

### 4. Export, install y testing

- **`public/`** en este repo: fuente del `README.md` e `install.ps1` públicos.
  El README dice "clone this repository" sin URL absoluta (el lector ya está en el
  repo) — así no incluye `MartinDele703` y el gate anti-fuga puede mantenerse estricto
  sobre TODO el árbol exportado, sin excepciones.
- **`tools/export-shareable.ps1 -PublicRepoDir <clon>`:**
  1. Regenera manifest de `bootstrap-ai-project`.
  2. Copia limpio (borra destino primero) las 2 skills + README + install.ps1 al clon.
  3. **Gate anti-fuga:** greppea el árbol exportado por marcadores prohibidos
     (`Zoho`, `DOMO`, `MartinDele703`, `martin.deleon`, `southpointtech`, `ZOHO_`,
     `Southpoint`) y falla si aparece alguno. La lista vive en UN solo lugar,
     compartida con el test de leaks.
  4. Martín revisa el diff en el clon, commitea y pushea.
- **Tests nuevos en `tests/`:**
  - `mirror.tests.ps1` — byte-identidad de los archivos no-variante entre las 3 skills,
    con lista explícita de los que pueden divergir. Convierte el espejado de disciplina
    a chequeo determinístico.
  - `shareable-leaks.tests.ps1` — marcadores prohibidos ausentes en `bootstrap-ai-project`
    (misma lista que el gate del export).
- **Eval de cierre:** bootstrapear un proyecto descartable con la skill nueva (conteo de
  archivos, `.mcp.json`, git sin identidad local, cero fugas) y borrarlo al terminar.

## Fuera de alcance (v1)

- Port de hooks/scripts a bash (se exige pwsh 7+).
- Publicar `setup-mcp-workstation` u otras skills (intrínsecamente Southpoint).
- Exclusión de deploy local de la skill compartible en la máquina de Martín.
- Creación efectiva del repo público en GitHub (el export lo asume clonado; crear el
  repo es un paso manual de Martín al momento de publicar).

## Riesgos

- **Espejado triple de mecánica:** mitigado por anglicización (byte-identidad) +
  `mirror.tests.ps1` determinístico.
- **Fugas de datos personales en el repo público:** mitigado por doble gate (test en CI
  local + gate del export) con lista única de marcadores.
- **Colisión de triggers:** aceptado, ver §3.
