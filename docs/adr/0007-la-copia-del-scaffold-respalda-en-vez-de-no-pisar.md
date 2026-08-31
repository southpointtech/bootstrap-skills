# ADR-0007 — La copia del scaffold pisa y respalda, en vez de no pisar

- **Estado**: aceptada
- **Fecha**: 2026-08-31
- **Contexto de la decisión**: grill del 2026-08-31, disparado por el bootstrap de `Profitability App`
  en modo adopción, donde la copia se llevó puestas reglas propias del `.gitignore` sin avisar.
- **Numeración**: se saltea 0004–0006, que existen en el worktree de la línea B
  (`feat/bootstrap-v2`) y todavía no están en `main`.

## Contexto

`copy-scaffold.ps1` copiaba con `[IO.File]::Copy(..., $true)`: sobrescritura incondicional, sin
declarar nada. En un directorio vacío eso es inocuo, y ese era el caso para el que se escribió.

Dos cosas lo volvieron un problema real:

1. **El modo adopción** (Step 0b) corre la misma copia sobre proyectos que ya tienen archivos. Su
   único resguardo era stashear el `CLAUDE.md` a mano; todo lo demás quedaba sin red.
2. **La contradicción con el Step 0**, que promete por escrito *"Never overwrite an existing file;
   scaffold around it"* — algo que el script nunca hizo.

En `Profitability App` el costo fue medible: de 52 archivos del scaffold, 6 tenían contraparte
distinta en el destino. Uno era el `.gitignore` del proyecto, con `~$*` (temporales de Excel de los
workbooks de HSS) y `SESSION_HANDOFF.md`, reglas que el scaffold no trae y que la copia borró. Se
recuperaron porque se hashearon los 52 archivos **a mano antes de copiar**; sin ese paso manual se
perdían en silencio. El síntoma ya estaba anotado como deuda abierta —*"`copy-scaffold.ps1` pisa el
`.gitignore` del destino"*— en unos 20 handoffs seguidos, clasificado Low.

## Decisión

La copia **sigue pisando**, pero antes respalda y después lo declara.

1. **Respaldo automático**: todo archivo preexistente cuyo contenido difiere se copia a
   `.bootstrap-backup/` **antes** de ser sobrescrito, con el mismo path relativo (salvo la
   desambiguación del punto 4). No va gitignoreado: aparece en el primer `git status` y el usuario
   decide si lo commitea o lo borra.
2. **Reporte JSON en stdout**: `{ created[], overwritten[{file, backup}] }`, mismo estilo que
   `compare-scaffold.ps1`. `overwritten` es el término propio de este script y **no** reusa
   `customized` de `upgrade-bootstrap`, que responde otra pregunta (ver Vocabulario).
3. **Comparación normalizada por fin de línea, sobre los BYTES**: un archivo que solo difiere en
   CRLF vs LF no se respalda ni se reporta. Es ruido de `core.autocrlf`, no un cambio: en
   `Profitability App` era 2 de las 6 diferencias aparentes, un tercio de falsos positivos. La
   normalización **no** decodifica a texto: decodificar hace que un BOM desaparezca y que dos bytes
   inválidos cualesquiera colapsen en `U+FFFD`, y ambos son cambios reales que se pisarían sin
   respaldo ni entrada en el reporte — justo la pérdida silenciosa que esto viene a evitar.
4. **El respaldo más viejo gana, pero el nuevo no se tira**: si ya hay un respaldo de una corrida
   anterior, ese conserva el original y la versión que se pisa ahora va al lado (`.2`, `.3`). El
   `backup` del reporte nombra siempre la copia que contiene lo recién pisado, nunca la vieja:
   prometer una copia que no tiene lo destruido es peor que no prometer nada.

   Es robustez del script, **no** un camino que la skill recorra: el Step 0 frena en seco cuando ya
   existe `.bootstrap-manifest.json`, y la copia del Step 2 lo deja, así que una segunda corrida no
   ocurre por el flujo normal. Se llega ahí invocando el script a mano, o borrando el manifest para
   rehacer una adopción que abortó — que es justamente lo que una adopción abortada invita a hacer.

   ⚠️ **`CLAUDE.md` es la excepción, y va al revés.** El Step 0b no busca lo último que se pisó sino
   el original del proyecto. El orden es: **primero `docs/agents/legacy-claude.md`** — si existe, una
   corrida anterior ya lo parqueó y ése es el original, no se toca; **después** el respaldo **sin
   numerar**. Nunca los numerados: contienen el template canónico (con las ediciones que haya
   recibido), no el texto del proyecto. Saltarse el primer paso destruye el original con un
   `Move-Item -Force` cuando se re-corre sobre una adopción ya completa; saltarse el segundo lo deja
   huérfano y hace que el paso C clasifique el contenido equivocado. Para todos los demás archivos,
   leer el `backup` del reporte sigue siendo lo correcto.
5. **Siempre activo, sin flags**: el script no sabe en qué modo lo invocan, y en un destino vacío no
   hay nada que respaldar, así que ni siquiera crea el directorio.
6. **El punto de aprobación queda solo en adopción**: el Step 0b/D debe cubrir cada entrada de
   `overwritten` en el mapa de cobertura. En bootstrap normal el agente reporta la lista y sigue.
7. **`.bootstrap-backup/` no entra al commit del bootstrap**: el Step 5 lo excluye explícitamente.
   Commitearlo sería tomar por el usuario justo la decisión que el punto 1 le deja a él, y además
   mete en el historial una copia de `CLAUDE.md` y de `.claude/`, que por la regla del gate solo-docs
   nunca son documentación y dejarían el review-loop disparando sobre una copia.

## Alternativas descartadas

**No pisar: saltear el archivo y reportar conflicto.** Es lo que promete el Step 0 y lo más seguro en
apariencia, pero rompe el modo adopción, que **necesita** que el `CLAUDE.md` canónico aterrice para
después mergearle las reglas propias. Habría obligado a reescribir el Step 0b de las tres skills y el
test que fija la semántica actual, a cambio de un resguardo que el respaldo ya da.

**No tocar el script y medir antes desde el Step 0b**, corriendo `compare-scaffold.ps1` de
`upgrade-bootstrap` para armar el mapa. Reusaba una pieza probada y clasifica exactamente igual (sin
manifest previo, todo lo que difiere cae en `customized`). Descartada porque crea una dependencia de
las tres skills bootstrap hacia una cuarta que se deploya por separado: si `upgrade-bootstrap` no
está instalada, el bootstrap se queda sin red justo en el caso que la necesita.

**Unir automáticamente el `.gitignore`**, que es el archivo que más veces se pisó. Descartada por
uniformidad: mete lógica especial por nombre de archivo y produce un resultado que no es ni el del
proyecto ni el del scaffold, con el orden de las líneas por definir. El respaldo más el reporte
alcanzan, y el merge lo decide una persona.

**Frenar y pedir aprobación también en bootstrap normal.** Cumpliría el Step 0 al pie de la letra,
pero mete un punto de espera en un flujo que hoy es de un solo comando, para un caso donde el
respaldo ya evita la pérdida.

## Consecuencias

**A favor:**

- Cierra una deuda que estuvo abierta ~20 handoffs, y la cierra para todos los archivos, no solo
  para el `.gitignore` que la hizo visible.
- El agente ya no tiene que hashear el árbol a mano para saber qué costó la copia: el script se lo
  dice. Ese paso manual fue lo único que salvó el `.gitignore` de `Profitability App`.
- La semántica de copia no cambia, así que el contrato del Step 2 y su test siguen valiendo.

**En contra / riesgos asumidos:**

- **`.bootstrap-backup/` queda en el árbol del proyecto** y alguien lo va a commitear sin querer. Se
  acepta: es el precio de que sea visible, y un respaldo invisible no sirve de red.
- **Pisar sigue siendo el default.** Si nadie lee el reporte, el resultado es igual al de antes salvo
  que los originales existen. Por eso el mapa de cobertura del Step 0b es obligatorio y no opcional.
- **La normalización de EOL puede ocultar un cambio real** que consista solo en fines de línea. Se
  acepta: nadie edita un archivo para cambiarle el EOL a propósito, y el ruido que evita es mucho
  mayor que el caso que pierde.

## Vocabulario

Suma cuatro términos al glosario de `CONTEXT.md`: **scaffold**, **modo adopción**, **archivo propio**
y **pisado**.

Y desambigua uno: `customized`, en `compare-scaffold.ps1`, significa *"vino del scaffold y lo
tocaste"*. En adopción no hay manifest previo, así que ahí cae también todo archivo que nunca fue
canónico — el `.gitignore` de `Profitability App` no era un scaffold personalizado, era un **archivo
propio**. Por eso el reporte de la copia dice **`overwritten`** y no `customized`: responde
*"¿qué pisé recién?"*, no *"¿qué difiere del canónico?"*.
