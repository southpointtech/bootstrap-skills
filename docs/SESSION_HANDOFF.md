# Session Handoff — 2026-07-05 (alignment-gate mergeado + pusheado + self-upgrade del repo)

## ▶ AL RETOMAR — estado y qué falta

Rama actual: **`main`**, working tree limpio, sincronizado con `origin/main`.

**NO HAY PENDIENTES INMEDIATOS.** Todo lo de la sesión anterior quedó cerrado. Lo próximo es arrancar el roadmap (abajo), frente #1: **bootstrap compartible**.

Skills sugeridas para la próxima sesión: `/grill-me` o brainstorming (superpowers) para el spec del bootstrap compartible.

## Qué se hizo en esta sesión (2026-07-05)

1. **Merge `feat/alignment-gate-hook` → `main`** (fast-forward hasta `85786cb`), rama borrada.
2. **Push a `origin/main`** (`southpointtech/bootstrap-skills`). Dato nuevo: **MartinDele703 NO tiene permiso de push en este repo (403)** — el remoto es de la org southpointtech y se pushea con esa cuenta (`gh auth switch --user southpointtech`). No existe `MartinDele703/bootstrap-skills`.
3. **Self-upgrade con `/upgrade-bootstrap`** (commit `c35c39f`, directo a main con aprobación explícita — cambio ya revisado en origen, no ameritaba rama+review-loop):
   - Copiado `.claude/hooks/alignment-gate.ps1` (missing).
   - `.claude/settings.json` actualizado (outdated-safe): ahora registra el PreToolUse del gate + conserva el PostToolUse del review-loop-trigger.
   - Bullet del alignment-gate integrado al `CLAUDE.md` real (merge asistido; era el único customized donde el canónico avanzó — los otros 23 customized no tenían delta upstream, quedaron intactos).
   - Manifest resellado a baseline `2026-07-04+ec22e73` (48 archivos). Cero huérfanos.
4. Memoria persistente actualizada (alignment-gate = mergeado; push solo con southpointtech).

**⚠️ El alignment-gate está ACTIVO en este repo desde la próxima sesión:** el primer `Edit`/`Write` de un archivo de *código* por sesión rebota una vez ofreciendo `/grill-me`; si el trabajo ya está alineado, reintentar y seguir. No-código (`.md`, `docs/`, `.scratch/`, `.agents/`, `.claude/`, configs) pasa libre.

## Follow-ups anotados (Minor, del review de la feature — NO urgentes)

1. `merge-settings.ps1` lookup case-sensitive de event keys (settings con `"posttooluse"` no canónico duplica estructura; incidencia ≈ 0).
2. `merge-settings.ps1` crashea con `{"hooks": null}` (preexistente, no regresión).
3. Estado del gate crece sin poda ni locking (~15 bytes/sesión; casi wontfix).
4. Typo "proceds" en el mensaje del deny del hook (cosmético, requiere ciclo mirror→manifest→deploy).
5. Dedup de merge-settings por firma string exacta (command distinto = duplicado funcional; se auto-desactiva en runtime).

## Roadmap acordado (próximos specs, EN ORDEN)

1. **Bootstrap "compartible"** — variante para terceros SIN Zoho/DOMO/identidad de Martín. Dolor confirmado: el scaffold personal filtra Zoho (CLAUDE.md steps 4/7, `docs/agents/issue-tracker.md`, `TASK_TEMPLATE.md`, server `zoho-personal` en gen-mcp-json) y defaultea git a MartinDele703. Decidir: ¿tercera skill espejada vs parametrizar? (ojo al costo de espejado triple).
2. **Descubrir skills/loops nuevos** — auditar `C:\Repos\SOUTHPOINTLABS` y `C:\Repos\PERSONAL` buscando patrones de trabajo aún no capturados como skills.
3. **Mejoras generales del scaffold.**

Follow-up externo pendiente de otras sesiones: Forecasting App (`C:\Repos\SOUTHPOINTLABS\Forecasting App`, repo local en `master`) y KBS necesitan `/upgrade-bootstrap` / bootstrap para recibir review-loop-trigger + alignment-gate; evaluar si el bullet nuevo del CLAUDE.md template aplica al CLAUDE.md real de Forecasting App.

## Reglas del repo (no olvidar)

- Editar skills acá NO tiene efecto hasta `tools\sync-skills.ps1` (deploy al día con HEAD al cierre de esta sesión).
- Espejado byte-idéntico de mecánica entre ambas skills bootstrap.
- La copia del Step 2 vive en `skills/*/scripts/copy-scaffold.ps1` — NO volver a `Copy-Item <dir> -Recurse` ni wildcard `scaffold\*`.
- Manifest generado, nunca a mano (`tools/gen-manifest.ps1` si editás scaffold sin sync). Rastros de testeo se borran. Identidad git local `MartinDele703`.
- El hook `review-loop-trigger` dispara `/review-loop` en cada commit de feature branch: corrélo sin preguntar. Trabajar en feature branches por slice.

## Gotchas técnicos vigentes

- Push a este repo: **solo cuenta `southpointtech`** (MartinDele703 → 403). `gh` tiene las dos cuentas; verificar la activa.
- `run_loop.py` del skill-creator roto en Windows.
- Warning git "LF will be replaced by CRLF" en `.md`/`.ps1` nuevos: inofensivo.
- Este repo está auto-bootstrapeado y al día con el scaffold canónico (baseline `2026-07-04+ec22e73`); futuras features del scaffold llegan con `/upgrade-bootstrap`.

## Próximos 3 pasos recomendados

1. Arrancar el spec del **bootstrap compartible** con `/grill-me` o brainstorming (frente #1 del roadmap). Trabajarlo en feature branch.
2. (Cuando toque contexto Southpoint) `/upgrade-bootstrap` en Forecasting App y bootstrap de KBS.
3. Ir bajando los follow-ups Minor si algún ciclo mirror→manifest→deploy los hace gratis (p. ej. el typo "proceds").
