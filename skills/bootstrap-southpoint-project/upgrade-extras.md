# Upgrade extras — bootstrap-southpoint-project

`upgrade-bootstrap` sigue este archivo después de re-sellar el manifest (su paso 5).

## Declaración de hub-sync

La recolección diaria de hub-sync (ADR-0012) solo recolecta un repo que tiene `.claude/hub-sync.json`,
y dentro de él solo al dev que figura en `devs`. Un repo sin declaración no produce lotes: solo deja
una línea `sin lote` en el log local de la PC, y a la bandeja no llega nada. Por eso el upgrade se la ofrece:

1. Si falta `.claude/scripts/hub-declarar.ps1`, este upgrade no lo trajo: reportalo y terminá acá. Si
   `SOUTHPOINT_GIT_EMAIL` no está seteada, tampoco sigas: la identidad git del repo puede ser la de
   servicio, compartida, y el script la anotaría como propia de este dev. Reportá que falta correr
   `setup-mcp-workstation` en esta PC y terminá acá.
2. Si **no existe** `.claude/hub-sync.json`, preguntale al usuario si el repo entra en hub-sync y, si
   entra, cuál es su proyecto del Hub y su Ongoing Support (opcional). Son texto libre: el PM confirma
   el destino al aprobar. Con la respuesta, corré desde la raíz del proyecto:

   ```powershell
   pwsh -NoProfile -File .claude/scripts/hub-declarar.ps1 -RepoDir . -HubProject "<proyecto>" [-OngoingSupport "<soporte>"] -Agregarme
   ```

   Si **ya existe**, corré solo `-Agregarme`: anota al dev de esta PC si faltaba, y si no, responde
   `sin-cambios`.
3. Leé el JSON que imprime el script. `accion` es `creada`, `actualizada` o `sin-cambios`. Un exit
   distinto de 0 trae el motivo en stderr: reportalo tal cual y no edites la declaración a mano.

Hecho cuando el reporte final del upgrade dice qué `accion` dio el script (o que el usuario dejó el repo
fuera de hub-sync) y recuerda los dos pasos que el upgrade no hace:

- commitear `.claude/hub-sync.json`;
- avisarle al PM que cargue la ruta de este repo en la bandeja, para el usuario de Windows de cada dev
  que trabaja en él. Hasta entonces, la tarea diaria no lo recolecta.
