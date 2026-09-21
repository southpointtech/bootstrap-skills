# ADR-0005 — El lockfile de skills externas se verifica o no existe

- **Estado**: aceptada
- **Fecha**: 2026-08-28
- **Contexto de la decisión**: grill de la próxima versión del bootstrap (2026-08-28).

## Contexto

`skills-lock.json` declara, para cada una de las 9 skills tomadas de `mattpocock/skills`, un
`computedHash`. Nunca hubo en este repo un script que los compute ni un test que los verifique.

Medido el 2026-08-28, no razonado:

- `git log -S computedHash --all` sobre `mattpocock/skills` **no devuelve nada**: el campo no existió
  jamás en upstream, así que no lo generó ninguna herramienta suya.
- Se barrió **toda la historia publicada de upstream**: 1178 blobs `.md` únicos × 7 normalizaciones
  (crudo, LF, CRLF, recortado, sin frontmatter, cuerpo recortado, path+contenido) × sha256/sha1/md5 =
  **24.738 hashes probados, cero coincidencias**.
- Tampoco coinciden con ninguna versión histórica de nuestros propios archivos, ni con los actuales.

Los nueve hashes son **fabricados**. Entraron con el lockfile el 2026-06-23 (`f67331f`) y sobrevivieron
dos meses sin que nada los tocara, precisamente porque nada los leía. Es el caso exacto que la regla de
afirmaciones del `CLAUDE.md` prohíbe: un enunciado verificable escrito sin verificar.

El daño concreto: la ausencia de base de merge se leyó como un hecho y bloqueó la actualización de las
skills durante semanas ("no hay base para merge de tres vías" quedó anotado como conclusión firme).

**La base sí existía**, y se recupera sin el lockfile: nuestra copia salió de alguna versión histórica
de upstream, y esa versión es la que minimiza el diff contra la nuestra. Medido sobre el cuerpo, sin
frontmatter: 7 de 9 dan similitud **1.000** contra una versión histórica exacta (cuerpo intacto, drift
solo en la `description`), `to-issues` da 0.947 y `tdd` 0.863 — las dos únicas con drift real, y
coinciden con las dos modificaciones que ya estaban documentadas.

## Decisión

El lockfile pasa a registrar lo que hace falta para un merge de verdad — commit de upstream de la base,
path upstream (incluido el rename), hash computado por un script de este repo, y marca explícita de
**fork propio** donde no hay upstream — y **un test de la suite recomputa esos hashes y falla si
mienten**. Un lockfile que nadie verifica no se conserva: o tiene test, o se borra.

## Alternativas descartadas

**Borrarlo y documentar la relación con upstream en prosa.** Cero mantenimiento, y honesto. Descartada
porque tira el método junto con la ficción: la recuperación de la base por similitud es cara de
redescubrir y merece quedar anotada en una estructura, no en un párrafo.

**Reemplazarlo por un submodule o un pin del repo de upstream.** La base quedaría garantizada por
construcción. Descartada por el costo de sumar una dependencia externa a este repo y a todo proyecto
que reciba el scaffold, para un set de 9 archivos de texto.

## Consecuencias

- **La suite gana un test que depende de un clon de upstream.** Hay que resolver que no requiera red en
  cada corrida (hashes propios verificables offline; la comparación contra upstream, bajo demanda).
- **El método de recuperación por similitud queda disponible** para la próxima vez que una base se
  pierda, que es el escenario probable si alguien vuelve a editar skills externas sin sellar. Vive
  implementado en `tools/recover-skill-bases.py`, documentado en
  `docs/agents/recuperar-base-de-skills.md`; su salida es la entrada del lockfile y es un artefacto
  generado, no editable a mano.
- **Deja de haber una excusa para no actualizar.** El bloqueo era la premisa falsa, no el trabajo.
