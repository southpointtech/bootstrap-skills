# Spec — Skill `upgrade-bootstrap` + versionado del scaffold

- **Fecha:** 2026-06-09
- **Estado:** aprobado para planificar
- **Motivación:** Permitir actualizar proyectos ya bootstrapeados cuando el scaffold de las skills `bootstrap-*-project` cambia (archivos nuevos o ediciones), sin pisar lo que el proyecto personalizó. Hoy re-correr la skill no sirve: su Step 0 (safety check) se frena si `CLAUDE.md`/`docs/ai-workflow/` ya existen.

## Objetivo

Dos componentes acoplados:

- **(A) Versionado del scaffold** — el bootstrap deja un *manifest* (`.bootstrap-manifest.json`) en cada proyecto nuevo, con el hash de cada archivo canónico al momento de instalar.
- **(B) Skill `upgrade-bootstrap`** — corre en un proyecto, compara contra el scaffold canónico actual y aplica el delta con aprobación; usa el manifest para distinguir con precisión *desactualizado* de *personalizado*, con fallback a comparación directa en proyectos legacy sin manifest.

## Decisiones de diseño (cerradas en brainstorming)

1. **Detección:** híbrida — manifest cuando existe, fallback a comparación directa cuando no.
2. **Comportamiento:** reporte + aplicar con aprobación (no dry-run puro, no automático sin confirmar).
3. **Versionado:** auto (etiqueta `fecha+hash-corto`); la comparación real es por hash de archivo, sin bumpeo manual.
4. **Estructura:** una sola skill que detecta la variante (no dos espejadas).
5. **Borrados:** los archivos huérfanos solo se reportan, no se borran.

## Lógica central: merge-base (3 hashes)

Para cada archivo se consideran hasta tres hashes:

- **base** — hash registrado en el manifest del proyecto (lo que se instaló / la última base sellada).
- **actual** — hash del archivo tal como está hoy en el proyecto.
- **canónico** — hash del archivo en el scaffold canónico actual (la versión nueva, instalada en `~/.claude/skills/...`).

El propio `.bootstrap-manifest.json` queda **excluido de esta clasificación** (no es un archivo de contenido del proyecto): nunca se reporta como Falta/Diferente; en cambio, siempre se (re)escribe en el paso de re-sellado.

Clasificación **con manifest**:

| Categoría | Condición | Acción |
|---|---|---|
| Falta | el archivo canónico no existe en el proyecto | copiar |
| Al día | `actual == canónico` | nada |
| Desactualizado-seguro | `actual == base` y `base != canónico` | actualizar |
| Personalizado | `actual != base` | no pisar; mostrar diff (si además `canónico != base`, es personalizado+desactualizado → diff de 3 vías informativo) |
| Huérfano | existe en el proyecto, no en el canónico | solo reportar |

Clasificación **sin manifest (fallback)** — sin *base*, solo:

| Categoría | Condición | Acción |
|---|---|---|
| Falta | no existe en el proyecto | copiar |
| Al día | `actual == canónico` | nada |
| Diferente | `actual != canónico` | mostrar diff; el usuario decide (no se puede saber si viejo o personalizado) |

## Componente A — El manifest y su generación

**Formato** (`.bootstrap-manifest.json`, en la raíz del proyecto):

```json
{
  "variant": "personal",
  "generatedFrom": "bootstrap-personal-project",
  "version": "2026-06-09+a1b2c3d",
  "files": {
    "CLAUDE.md": "<sha256>",
    ".agents/skills/review-loop/SKILL.md": "<sha256>",
    "...": "..."
  }
}
```

- `variant`: `personal` | `southpoint`.
- `generatedFrom`: nombre de la skill bootstrap fuente.
- `version`: etiqueta legible `YYYY-MM-DD+<hash-corto>`, donde el hash corto deriva del conjunto de hashes de archivos. Sin bumpeo manual.
- `files`: mapa ruta-relativa → sha256. La ruta es relativa a la raíz del scaffold/proyecto y usa `/` como separador (portable).

**Generación** — nuevo script `tools/gen-manifest.ps1`:

- Recibe la ruta de una skill bootstrap; recorre su `assets/scaffold/` recursivamente.
- Hashea cada archivo con sha256. **Se excluye a sí mismo** (`.bootstrap-manifest.json`) del cálculo y del mapa, para evitar auto-referencia.
- Escribe el manifest en `assets/scaffold/.bootstrap-manifest.json` de esa skill.
- Se corre para ambas skills (personal y southpoint).

**Distribución al proyecto:** como el manifest vive dentro de `assets/scaffold/`, el Step 2 del bootstrap (copia por enumeración top-level) lo lleva al proyecto automáticamente, sin tocar el comando de copia.

## Componente B — La skill `upgrade-bootstrap`

Vive en el repo como tercera skill: `skills/upgrade-bootstrap/SKILL.md` (+ scripts si hacen falta). Se instala vía `sync-skills.ps1` a `~/.claude/skills`.

**Flujo cuando se corre en un proyecto (cwd = raíz del proyecto):**

1. **Determinar scaffold fuente y variante:**
   - Si existe `.bootstrap-manifest.json`: leer `variant`/`generatedFrom` → fuente = `~/.claude/skills/<generatedFrom>/assets/scaffold`.
   - Si no existe (legacy): detectar variante por presencia de menciones DOMO en `CLAUDE.md` (southpoint) vs ausencia (personal); si es ambiguo, preguntar al usuario.
2. **Cargar manifest canónico** del scaffold fuente (`assets/scaffold/.bootstrap-manifest.json`).
3. **Clasificar** cada archivo según la matriz merge-base (con o sin manifest del proyecto).
4. **Reporte** agrupado: Faltan / Desactualizados-seguros / Personalizados (o Diferentes) / Huérfanos / Al día. Incluir conteos.
5. **Aplicar con aprobación del usuario:**
   - Faltan → copiar del scaffold fuente.
   - Desactualizados-seguros → sobrescribir con la versión canónica.
   - Personalizados / Diferentes → mostrar diff; ofrecer skip o merge asistido (Claude ayuda a integrar el delta sin perder lo propio). Nunca sobrescribir sin consentimiento explícito por archivo.
   - Huérfanos → solo listar; no borrar.
6. **Re-sellar el manifest del proyecto:** escribir `.bootstrap-manifest.json` con la nueva base por archivo:
   - Archivos actualizados a canónico → base = hash canónico nuevo.
   - Archivos dejados como personalizados → base = la base previa (la versión de la que partió la personalización), para seguir distinguiéndolos a futuro.
   - Archivos nuevos copiados → base = hash canónico.
   - `version` del manifest = la del scaffold canónico aplicado.

**Caso legacy (primera corrida sin manifest):** la skill detecta Faltan (los 2 de `review-loop`) y Diferentes (`CLAUDE.md` + 3 docs), aplica con aprobación, y **siembra el manifest por primera vez** — "adopta" el proyecto al sistema de versionado para que la próxima corrida tenga detección precisa.

## Componente C — Cambios al flujo del repo

- Nuevo `tools/gen-manifest.ps1` (descrito arriba).
- `tools/sync-skills.ps1`: regenerar el manifest de ambas skills **antes** de copiar a `~/.claude/skills` (llamar a `gen-manifest.ps1`), así el manifest deployado siempre refleja el scaffold actual.
- `CLAUDE.md` del repo: documentar que al editar el scaffold se regenera el manifest (o que `sync-skills.ps1` lo hace), y agregar `upgrade-bootstrap` a la lista de skills del repo.
- Ambas skills bootstrap: el scaffold pasa a incluir `.bootstrap-manifest.json`; el `SKILL.md` de cada una menciona que se entrega en la línea de "This delivers". **Los conteos 10 skills / 10 commands NO cambian** (el manifest es un archivo de raíz, no una skill ni un comando).
- Verificar que `gitignore.txt` del scaffold no ignore `.bootstrap-manifest.json` (debe quedar trackeado en el proyecto destino para que la próxima corrida lo lea).
- `docs/TESTING.md`: agregar el manifest a la assertion de scaffold completo, y casos de regresión para `upgrade-bootstrap`.

## Testing (evals con skill-creator)

Casos canónicos para `upgrade-bootstrap`:

1. **Manifest + desactualizado-no-tocado:** sembrar proyecto con manifest viejo y un archivo idéntico a su base pero distinto del canónico → se clasifica Desactualizado-seguro y se actualiza.
2. **Manifest + personalizado:** archivo cuyo hash actual != base → se clasifica Personalizado y NO se pisa.
3. **Legacy sin manifest:** proyecto bootstrapeado con la versión vieja (sin manifest) → fallback detecta `review-loop` faltante + diffs en CLAUDE.md/docs; tras aplicar, queda sembrado el manifest.
4. **Al día:** proyecto recién bootstrapeado con la versión actual → "nada que hacer".

Más una regresión de que el bootstrap ahora entrega `.bootstrap-manifest.json` y los conteos siguen 10/10.

## Fuera de alcance (YAGNI)

- Merge automático "inteligente" de 3 vías (solo mostramos diff y asistimos manualmente).
- Rollback de upgrades.
- Soporte para scaffolds de terceros (solo las dos skills bootstrap propias).
- Borrado automático de huérfanos.

## Archivos afectados

Nuevos:
- `skills/upgrade-bootstrap/SKILL.md` (+ scripts si hacen falta).
- `tools/gen-manifest.ps1`.
- `assets/scaffold/.bootstrap-manifest.json` en ambas skills (generado).

Modificados:
- `tools/sync-skills.ps1` (regenerar manifest antes de copiar).
- `CLAUDE.md` del repo (flujo + lista de skills).
- `skills/bootstrap-personal-project/SKILL.md` y `skills/bootstrap-southpoint-project/SKILL.md` (línea "This delivers" incluye el manifest).
- `docs/TESTING.md` (assertion + casos upgrade).
- Verificación de `gitignore.txt` (ambas variantes).
