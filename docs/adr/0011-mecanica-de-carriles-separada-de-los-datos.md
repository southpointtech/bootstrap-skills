# ADR 0011 — La mecánica de carriles va separada de los datos del proyecto

Status: accepted
Fecha: 2026-09-17

## Contexto

El kit de paralelismo por carriles (`C:\Repos\PERSONAL\kit-paralelismo-carriles\`) trae la norma
como una sola plantilla, `PARALELISMO.template.md`, con marcas `{{…}}` en 8 de sus 12 secciones.
Además funciona como memoria viva («La ola vigente», «Lo que dejó la ola N»). Su prompt de adopción
pide dejar `PLAN-DE-OLA.md` y `BRIEF-DE-CARRIL.md` «con rutas y comandos de este repo ya puestos», y
`abrir-carril.ps1` «con -Copy por defecto ajustado a este repo».

`upgrade-bootstrap` decide por hash: un archivo del scaffold que el proyecto editó queda
**customized**, y cada upgrade posterior lo muestra como diff y pide un merge asistido archivo por
archivo. Con el kit como venía, los cuatro archivos se editan al adoptarlo. Entonces cualquier cambio
posterior a la mecánica (por ejemplo, relajar la regla de review cuando se arregle
`.scratch/issue-hook-review-loop-cwd-de-worktree.md`) llegaría a cada proyecto como un merge a mano
sobre archivos llenos de datos propios, y nunca solo.

## Decisión

1. **Mecánica pura, sin editar**: `docs/ai-workflow/PARALELISMO.md`, `PLAN-DE-OLA.md`,
   `BRIEF-DE-CARRIL.md` y `.claude/scripts/abrir-carril.ps1`. Ningún proyecto los edita, así que un
   upgrade los actualiza limpio como `outdated`. Las marcas `{{…}}` de `PLAN-DE-OLA` y
   `BRIEF-DE-CARRIL` se rellenan **en el chat** cada vez que se usan, no en el archivo.
2. **Datos del proyecto** en un archivo aparte, `docs/ai-workflow/PARALELISMO-DEL-PROYECTO.md`, que
   llega con marcas `{{…}}` y queda customized cuando se rellena. Es correcto: son datos. La mecánica
   apunta a sus secciones **por nombre**.
3. **`abrir-carril.ps1` no se edita por proyecto**: lo que copia y dónde abre los worktrees sale del
   archivo de datos o de un parámetro.
4. **Una marca sin rellenar bloquea la ola, y lo hace cumplir el script**: `abrir-carril.ps1` se
   niega a abrir un worktree si el archivo de datos falta o todavía tiene `{{` (con `-DryRun` lo
   avisa y sale 0). Los datos que el script necesita viven en un bloque cercado ` ```carriles ` de
   líneas `clave: valor`, con precedencia parámetro > bloque > default. Por eso:
   - un dato que no aplica se escribe «no aplica», nunca se deja la marca;
   - la nota de instrucciones del archivo no contiene `{{` literal;
   - «Lo que dejó la ola N» arranca vacía, sin marcas, para que un proyecto sin olas cerradas no
     quede bloqueado.
5. **Las lecciones tienen dos destinos**: «Lo que dejó la ola N» se escribe en el archivo de datos, y
   una lección que vale para cualquier proyecto (como la del puerto fijo o la del junction) se sube a
   la mecánica en Bootstrap Skills, desde donde llega a todos por upgrade. La mecánica lo dice.
6. **Al bootstrapear no se rellenan las marcas**: el proyecto todavía no tiene issues ni ola.

## Opciones descartadas

- **Un solo archivo, como el kit.** Es más simple hoy, y cada cambio de mecánica se paga con un merge
  a mano en cada proyecto.
