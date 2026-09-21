# Paralelismo por carriles — norma del proyecto

> **Mecánica: este archivo no se edita en el proyecto.** Los datos de este repo (camino crítico,
> archivos calientes, recursos, guardas, la ola vigente y lo que dejó cada ola) viven en
> [`PARALELISMO-DEL-PROYECTO.md`](PARALELISMO-DEL-PROYECTO.md), y esta norma los nombra **por
> sección**. Así una mejora de la mecánica llega por `upgrade-bootstrap` sin pisar datos
> (ADR-0011 de Bootstrap Skills).
> La mecánica viene de un proyecto que corrió cuatro olas con tres carriles, y cada regla se
> aprendió en carne propia. No la suavices sin una razón medida en este repo.

**Fecha, decidido con y alcance**: sección «Encabezado» de los datos del proyecto.

**La forma de trabajo**: el humano habla con **una sola terminal**. Esa terminal es el
**orquestador**: planea la ola, abre los worktrees, despacha un subagente por carril,
revisa, integra y reporta. Los carriles no hablan con el humano ni entre ellos.

**El techo son 3 carriles.** No es un límite de la herramienta: es lo que aguanta un grafo
de dependencias real sin que dos agentes se pisen, y lo que aguantan la memoria de la
máquina y la atención del orquestador.

**La base** es la rama donde se integran las olas: la clave `base` del bloque `carriles` de los
datos del proyecto (`main` si no está).

---

## 1. Lo que el paralelismo NO va a lograr

El camino crítico de este alcance está en la sección «El camino crítico» de los datos del
proyecto.

**Sus eslabones son los que ningún agente extra acorta.** Se pasa de todos los slices en fila
a tantos niveles como eslabones tenga el camino crítico. Esperá un **2×**, no un 5×. El ancho
de 3 carriles se usa en pocas olas; el resto del tiempo sobran agentes. **Es lo esperado, no
una falla.** No inventes trabajo para llenar carriles: un agente ocioso cuesta menos que un
merge conflictivo.

## 2. Las olas

- Una **ola** es un conjunto de hasta 3 slices que corren a la vez. Termina cuando **todas
  sus ramas están integradas en la base** y la suite completa pasó ahí.
- **Ningún carril vive a través de dos olas.** Es lo que mantiene los conflictos acotados.
- **Un carril se abre sólo si la ola tiene al menos dos slices listas.** Tres carriles son
  ~3× los tokens: el paralelismo compra tiempo de reloj, no trabajo gratis.
- **El slice fundacional va solo.** El que fija la estructura de módulos, el runner de
  tests, el naming y los tokens no se paraleliza: dos agentes fundando convenciones a la
  vez dan dos proyectos pegados con cinta.
- Cada ola se planea con [`PLAN-DE-OLA`](PLAN-DE-OLA.md) y el humano la aprueba **antes** de
  despachar. El plan aprobado se escribe en la sección «La ola vigente» de los datos del
  proyecto.
- Al cerrar cada ola, el orquestador escribe las lecciones que la próxima no puede ignorar.
  Tienen **dos destinos**:
  - lo propio de este repo va a la sección «Lo que dejó la ola N» de los datos del proyecto,
    que es memoria viva, no historia;
  - una lección que vale para cualquier proyecto (como la del puerto fijo o la del junction)
    **se sube a esta mecánica en Bootstrap Skills**, desde donde llega a todos los proyectos
    por `upgrade-bootstrap`. No se escribe acá: este archivo no se edita en el proyecto.

## 3. Los contratos existen como código antes de paralelizar

Los carriles de una ola codean **contra firmas que ya existen**, no contra firmas que cada
uno imagina. Las fronteras entre módulos quedan escritas como tipos/interfaces (con
implementaciones vacías si hace falta) antes de la primera ola paralela.

Las firmas fijadas están en la sección «Contratos fijados» de los datos del proyecto.

- Un carril que necesita otro módulo **importa el tipo y stubbea la implementación**.
- Si un carril necesita el **comportamiento** de otro carril de su misma ola, no es un
  stub que falta: es **un error de rebanado**. Para y se re-rebanan las dos slices.
- **Los nombres compartidos se fijan antes de despachar** (claves de config, nombres de
  constantes, rutas). Caso real: un carril esperaba `CUENTA_BANCO`, el otro declaró `CUENTA`,
  y un test condicionado con `skipif` quedó dormido para siempre, verde y sin verificar
  nada. **Un test condicionado a un nombre que nadie declara es un test que no existe.**

## 4. Dueño único por archivo

**Ningún carril edita un archivo que no es suyo.** El plan de cada ola nombra, por carril,
los archivos de los que es dueño.

| Zona | Dueño | Regla |
|---|---|---|
| Tokens de diseño · estilos base · layout | el slice fundacional | **Sólo lectura** para los carriles. Un cambio ahí vuelve al orquestador |
| Cada módulo | el slice que lo implementa | Un módulo, un dueño, una ola |
| Cada pantalla / ruta | el slice de esa pantalla | Dos slices que editan la misma pantalla van **en olas distintas** |
| **El archivo caliente**: los de la sección «Archivos calientes» de los datos del proyecto | **un solo carril por ola**, nombrado en el plan | Quien no es dueño **no lo edita**: escribe el diff que necesita en su reporte y lo aplica el orquestador al integrar |
| Config compartida: la de la sección «Config compartida» de los datos del proyecto | quien la crea | **Append-only**: cada slice agrega sus claves al final, nadie reordena ni reescribe las ajenas |
| Migraciones / esquemas | quien crea la primera | **Una por slice, prefijada con el número de slice.** Nunca dos slices en la misma |
| Suite E2E | quien arma el runner | **Un archivo por escenario.** Nadie toca escenarios ajenos; si tiene que cambiar uno, el plan lo nombra dueño de ese archivo |
| **Dependencias** (manifest + lockfile) | **el orquestador, nadie más** | Ver abajo |
| PRD, ADRs, `CONTEXT.md`, `DESIGN.md`, `CLAUDE.md` | el orquestador, con el humano | Un carril que necesita cambiarlos ya salió de su alcance |

### Las dependencias las agrega el orquestador, entre olas

Tres carriles agregando paquetes escriben el mismo lockfile y se pisan. Además, la regla de
supply chain (**nada publicado hace menos de 14 días sin aprobación explícita**) necesita
un ojo que un carril no tiene. Un carril que necesita una librería **la pide en su reporte
y sigue con un stub**. El orquestador verifica la fecha, la agrega, y la ola siguiente ya
la tiene.

## 5. Recursos compartidos: aislar cada carril

El fallo por recurso compartido **parece un bug del código** y cuesta un turno entero de
diagnóstico. Cada carril trabaja con lo suyo. Qué recursos tiene este repo y cómo se aíslan
por carril (carpeta de datos de dev, base de datos o emulador, puertos) está en la sección
«Recursos compartidos» de los datos del proyecto.

**Ojo con el servidor reutilizado.** Si el runner de E2E reutiliza un servidor que ya está
escuchando (Playwright `reuseExistingServer`, puerto fijo), el carril B corre sus tests
**contra el servidor del carril A** y da verde sobre código ajeno. O cada carril tiene su
puerto, o los E2E los corre sólo el orquestador, en serie.

Si existe una guarda que aborta cuando la config no es la de desarrollo, **se extiende al
carril**: aborta también si el carril apunta a los recursos de otro. **Nada de esto toca
jamás recursos del cliente ni de producción.**

## 6. Worktrees: cómo se abren

- **Rama por slice**: `slice/NN-slug`, en su propio worktree, salida de la base actual.
  Los worktrees viven **fuera del repo**, en la carpeta de la clave `worktrees` del bloque
  `carriles` de los datos del proyecto.
- Se abren con [`abrir-carril.ps1`](../../.claude/scripts/abrir-carril.ps1). El script lee del
  bloque `carriles` qué copiar, dónde abrir y sobre qué base (un parámetro gana sobre el
  bloque), y **se niega a abrir** si los datos del proyecto faltan o les queda una marca sin
  rellenar. Con `-DryRun` las muestra como aviso.

### Lo que un worktree NO hereda, y hay que copiarle

**Todo lo que está en el `.gitignore` nace ausente en un worktree nuevo.** Las dos que ya
costaron caro:

| Qué | Por qué duele |
|---|---|
| **`.env`** | Los tests que miran la config fallan por una causa ajena al carril |
| **`.scratch/`** (o donde vivan las issues) | **Ahí está la especificación del carril.** Un carril sin su issue inventa el alcance. Pasó con la ola ya despachada |

Lo demás que este repo no hereda (dependencias instaladas, artefactos generados) y cómo se
resuelve está en la sección «Lo que un worktree no hereda» de los datos del proyecto.

Ninguna ensucia el diff: siguen gitignoreadas del otro lado.

**Dependencias instaladas (`node_modules`, venv): instalación propia por worktree, sin
junction/symlink**, salvo que midas lo contrario. Con un junction,
`git worktree remove --force` **borra el `node_modules` del árbol original** a través del
link. Si igual usás uno, borrá el link antes de remover el worktree.

### Una rama vive en un solo worktree

Git no deja tener la misma rama en dos worktrees. Si el árbol principal tiene la base
checkouteada, ningún otro worktree puede mergear en la base: **integra una sola terminal,
el orquestador**. Los carriles dejan la rama rebasada y lista; el fast-forward lo hace él.

**No dejes el árbol principal parado en la rama de un slice mientras hay carriles**: los
hooks leen la rama del árbol de la sesión y disparan sobre la rama equivocada.

## 7. Los hooks no disparan dentro del worktree de un carril

Medido, no deducido: `review-loop-trigger` lee el **`cwd` de la sesión**, no el directorio
donde corrió el comando. La herramienta Bash resetea el `cwd` al árbol principal después de
cada llamada, así que un `cd <worktree> && git commit` le entrega al hook el `cwd` de la
base y el hook sale en silencio. (Un subagente despachado con aislamiento por worktree del
harness sí lo dispara, porque su `cwd` de sesión es su worktree — pero ese worktree no es
el que abriste ni tiene los archivos que copiaste.)

**Regla: el `/review-loop` de cada carril lo corre el orquestador al integrar, sin
excepción.** Con la cwd en el worktree del carril, y el marcador de review
(`.claude/scripts/review-marker.ps1`) también corrido desde ahí. Si un review lo hizo un
subagente revisor en vez del comando, **avanzá el marcador a mano** o el hook va a creer
que ese delta nunca se revisó. Los reviews pasan a ser seriales: es el costo.

El arreglo del hook está abierto en Bootstrap Skills
(`.scratch/issue-hook-review-loop-cwd-de-worktree.md`). Mientras siga abierto, esta regla
rige. Cuando se cierre, el cambio llega a esta sección por `upgrade-bootstrap`.

## 8. Tests y memoria: la suite completa va en serie

- **El carril corre**: los tests de su slice **más las guardas transversales** (tests que
  barren todo el código buscando fugas o violaciones de fronteras), las de la sección
  «Guardas transversales» de los datos del proyecto.
  Caso real: un carril corrió «sólo sus tests», la guarda transversal estaba fuera de su
  lista, y entregó una regla rota sin saberlo.
- **El orquestador corre**: la suite completa, los E2E y el `/review-loop`, **de a un
  carril y sin subagentes vivos**.
- **Antes de la suite, mirá la memoria libre**
  (`(Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory/1024`). Con subagentes vivos
  los tests de navegador dan **rojos falsos**, y a veces el sistema mata la corrida. Si hay
  poca memoria, pedile al humano que cierre cosas: no mates sus procesos.
- **Un rojo en un test de navegador con agentes vivos se reproduce aislado antes de
  creerle.**
- Si un carril no es dueño del archivo caliente, sus tests **no** instalan el cableado a
  mano: eso tapa que el entrypoint se olvide de hacerlo. Su cableado se prueba contra la
  app real **después de integrar**.

## 9. Protocolo de integración

1. Un carril **no integra** hasta tener: tests de su slice y guardas transversales verdes,
   y su reporte entregado.
2. El orquestador, por carril y en serie: corre el `/review-loop` en el worktree hasta que
   cierre, corre la suite, y recién ahí integra.
3. **Orden de merge**: primero el carril del camino crítico. Los otros **rebasan sobre la
   base nueva**, vuelven a correr su suite, y recién ahí integran.
4. **Después de cada merge, buscá lo que sólo aparece con las piezas juntas**: tests
   `skip`eados que deberían haber despertado, guardas que ahora ven código de otro carril,
   nombres de contrato que no coinciden. Los problemas más caros de una ola están **entre**
   dos slices, no dentro de uno: es la razón de que integre un orquestador y no los
   carriles solos.
5. Si el carril es dueño del archivo caliente, se integra primero; los diffs que pidieron
   los demás los aplica el orquestador después.
6. **Cerrada la ola**: suite completa (E2E incluido) sobre la base. Una ola no se
   declara cerrada con un rojo. Se escriben las lecciones en sus dos destinos (§2).
7. Cada commit de cierre lleva su trailer `Slice-Close: <qué cerró>`.
8. Los worktrees se limpian con `git worktree remove`. **Las ramas no se borran** hasta que
   el humano lo pida: todo queda reversible.

## 10. Tamaño

- **Medí antes de repartir**: cuántos llamadores tiene la función que cambia, cuántos tests
  la tocan, qué archivos edita de verdad. Una issue que dice «no entra en 400 líneas» sin
  haberlo medido no es un dato.
- El carril **vuelve a medir antes del primer test**; si se proyecta muy por encima de ~400
  líneas de lógica, **para y reporta** en vez de seguir.
- El rebanado tiende a subestimar. Si un slice terminado se pasó, integrarlo suele ser
  mejor que partirlo: registralo y ajustá el rebanado de lo que falta.

## 11. Lo que nunca se paraleliza

- **Las decisiones de negocio.** Un carril que encuentra una contradicción, un requisito
  que falta o un dato del negocio que no está **se detiene y reporta**. No asume, no
  «resuelve por ahora».
- Las decisiones **técnicas** sí las toma el carril, y las **registra en su reporte** para
  que el orquestador las vea.
- Los slices con humano en el medio (HITL): credenciales, datos reales, consolas.
- Todo lo que toca al cliente o a producción: deploy, datos reales, secretos. Siempre con
  aprobación humana explícita (`DEPLOYMENT_RULES.md`).

## 12. Higiene de git en carriles

- **`git add` por archivo, nunca `git add -A`.** Caso real: un `add -A` barrió un cambio
  sin commitear que no era del carril. El carril frenó a preguntar, que es lo correcto.
- Antes de despachar, el orquestador mira `git status` del árbol principal y de cada
  worktree: un cambio sin commitear previo **no es de nadie** hasta que se aclare.
- **Texto con tildes: herramientas Edit/Write, no heredocs del Bash tool.** Un heredoc
  puede romper los acentos, y el reemplazo falla en silencio.
- Si el hook dispara sobre algo que no corresponde, **no se ignora en silencio**: se
  verifica el delta, se registra la desviación y su razón, y se avanza el marcador sólo si
  todo el delta ya pasó por un review.

---

## Anexos

- [`PLAN-DE-OLA.md`](PLAN-DE-OLA.md) — cómo se planea y aprueba una ola.
- [`BRIEF-DE-CARRIL.md`](BRIEF-DE-CARRIL.md) — lo único que lee un carril además de su issue.
- [`PARALELISMO-DEL-PROYECTO.md`](PARALELISMO-DEL-PROYECTO.md) — los datos de este repo.
