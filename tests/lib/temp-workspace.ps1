# tests/lib/temp-workspace.ps1 — raíz temporal por corrida, compartida por todas las suites.
#
# La regla del repo dice que cualquier rastro de testeo se borra al terminar. No se cumplía: al
# medirlo el 2026-08-31 había 62 rastros en la raíz de %TEMP%, de al menos seis suites; al
# re-medirlo el 2026-09-01, después de una sola corrida completa, 106. La causa raíz es que cada
# suite creaba sus workspaces sueltos en la raíz de %TEMP% y los borraba uno por uno, así que
# cualquier error terminante entre medio los filtraba para siempre.
#
# El patrón (validado primero en copy-scaffold.tests.ps1) tiene tres partes, y las tres importan:
#
# 1. UN solo directorio raíz por corrida, con PID + GUID, del que cuelga todo. Un único borrado al
#    final se lleva todo, incluso lo que un camino intermedio no alcanzó a limpiar.
# 2. Un `trap` que borra esa raíz también en el camino de aborto. La limpieza del final es una
#    sentencia suelta: con $ErrorActionPreference=Stop, un error terminante fuera de un Assert la
#    saltea. El trap tiene que vivir en el scope del SCRIPT que se está corriendo, no acá adentro:
#    un trap queda atado al frame que lo ejecuta, y el frame de este archivo termina cuando el
#    dot-source vuelve, así que desde acá no atraparía nada de lo que pase después en la suite
#    (verificado: un `throw` en el script llamador pasa de largo). Por eso este archivo NO lo
#    declara y cada suite pone el suyo. `tests/temp-hygiene.tests.ps1` verifica que lo tenga: sin
#    esa verificación, olvidarlo deja la parte 2 muerta y nada se pone rojo.
#    El trap NO cubre `exit` ni que maten el proceso; para esos está la parte 3.
# 3. Recolección de huérfanos POR EDAD, nunca por glob incondicional. En este repo las corridas
#    concurrentes son la norma (el review-loop lanza reviewers en paralelo), y un glob
#    incondicional les borra los fixtures en pleno uso — es lo que hacía export-shareable.tests.ps1.
#    Un `<prefijo>-run-*` de hace más de un día no puede ser de una corrida viva.
#
# Uso, en tres líneas por suite:
#
#     . (Join-Path $PSScriptRoot "lib\temp-workspace.ps1")
#     $script:runRoot = New-TestRunRoot "rm"
#     trap { Remove-TestRunRoot $script:runRoot; break }
#
# y `Remove-TestRunRoot $script:runRoot` al final. `break` re-lanza el error, así que el trap no
# cambia el exit code de la suite.

# Crea la raíz de esta corrida y recolecta las raíces viejas del mismo prefijo.
function New-TestRunRoot {
  param([Parameter(Mandatory)][string]$Prefix)
  $temp = [IO.Path]::GetTempPath()
  # 8 hex y no un GUID entero: el anidado suma al largo del path y los fixtures más profundos de
  # `export-shareable` llegaban a 249 de los 260 de MAX_PATH — once caracteres de margen, o sea que
  # pasaba en esta máquina y reventaba en la de alguien con un usuario más largo. Medido. El PID
  # es lo que separa corridas concurrentes; los 8 hex separan corridas sucesivas del mismo proceso.
  $root = Join-Path $temp ("$Prefix-run-$PID-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
  # CreateDirectory y no New-Item: el path es literal y no se interpreta como wildcard, que es lo
  # que necesita el caso de los proyectos con corchetes en el nombre.
  [IO.Directory]::CreateDirectory($root) | Out-Null
  # Por edad: sin el filtro de fecha esto es el glob incondicional que mata corridas concurrentes.
  #
  # LastWriteTime y no CreationTime. Medido en esta máquina: crear un hijo actualiza el
  # LastWriteTime del directorio padre y deja su CreationTime congelado en el arranque. O sea que
  # con CreationTime una corrida VIVA de más de un día —un review-loop largo, una suite colgada
  # esperando un prompt de git— se borra a sí misma los fixtures en pleno uso; con LastWriteTime
  # una corrida activa se rejuvenece sola cada vez que escribe. Y los huérfanos de verdad no se
  # tocan más, así que igual envejecen y se recolectan. La versión anterior elegía CreationTime
  # con un comentario que describía, exactamente, la ventaja de LastWriteTime.
  #
  # -LiteralPath y no posicional: `-Path` interpreta wildcards, y si %TEMP% resolviera bajo un path
  # con corchetes la enumeración devolvería vacío y la recolección moriría en silencio — con
  # `-ErrorAction SilentlyContinue` tapando cualquier rastro. Es la misma razón por la que arriba
  # se usa CreateDirectory.
  Get-ChildItem -LiteralPath $temp -Directory -Filter "$Prefix-run-*" -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -ne $root -and $_.LastWriteTime -lt (Get-Date).AddDays(-1) } |
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
  return $root
}

# Borra la raíz de esta corrida. Idempotente: la llaman el trap Y el final de la suite, y en el
# camino de aborto las dos llegan.
function Remove-TestRunRoot {
  param([string]$Root)
  if (-not $Root -or -not (Test-Path -LiteralPath $Root)) { return }
  Remove-Item -LiteralPath $Root -Recurse -Force -ErrorAction SilentlyContinue
  # Un reintento, porque en Windows el borrado puede quedar PENDIENTE mientras otro proceso
  # sostiene un handle: medido, `review-loop-docs-gate` dejaba su raíz en disco en 3 de 3 corridas
  # verdes porque el proceso de fondo de git todavía tenía abierto el `.git` del fixture, y el
  # árbol desaparecía solo unos segundos después. Sin el reintento no hay forma de distinguir
  # "borrado pendiente" de "nunca se borró", y `-ErrorAction SilentlyContinue` se come la
  # diferencia. El Warning no rompe la suite: es una fuga, no un test fallado, y hacerla fallar
  # convertiría un handle ajeno en un rojo que nadie puede arreglar desde acá.
  if (Test-Path -LiteralPath $Root) {
    Start-Sleep -Milliseconds 300
    Remove-Item -LiteralPath $Root -Recurse -Force -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $Root) {
      Write-Warning "no se pudo borrar la raíz temporal $Root (queda para la recolección por edad)"
    }
  }
}

# Un workspace de un caso, colgado de la raíz. El GUID mantiene los casos independientes entre sí
# dentro de la misma corrida.
# El nombre puede traer corchetes (el fixture de paths con wildcards de review-loop-trigger), así
# que la creación va por CreateDirectory, que los toma literales.
function New-TestWorkspace {
  param(
    [Parameter(Mandatory)][string]$Root,
    [string]$Name = "ws"
  )
  # 8 hex por lo mismo que el run root: MAX_PATH. Con tan pocos, dos workspaces de la misma corrida
  # pueden chocar, así que se reintenta en vez de devolver uno ya usado — un fixture compartido por
  # dos casos es un test que miente.
  do {
    $d = Join-Path $Root ("$Name-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
  } while (Test-Path -LiteralPath $d)
  [IO.Directory]::CreateDirectory($d) | Out-Null
  return $d
}

# Un path de archivo dentro de la raíz. Devuelve el path, NO crea el archivo: hay casos que
# necesitan justamente que no exista.
function New-TestTempPath {
  param(
    [Parameter(Mandatory)][string]$Root,
    [string]$Name = "f",
    [string]$Extension = ""
  )
  do {
    $p = Join-Path $Root ("$Name-" + [guid]::NewGuid().ToString('N').Substring(0, 8) + $Extension)
  } while (Test-Path -LiteralPath $p)
  return $p
}
