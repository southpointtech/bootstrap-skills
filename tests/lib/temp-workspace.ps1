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
#    un `trap` se aplica al bloque de script donde está escrito, así que uno declarado en este
#    archivo no cubre lo que pase después en la suite (verificado: un `throw` en el script llamador
#    pasa de largo), y uno declarado dentro de una función sólo cubre esa función. Por eso este
#    archivo NO lo declara y cada suite pone el suyo, en el cuerpo del script.
#    `tests/temp-hygiene.tests.ps1` lo verifica por el AST, justamente para distinguir el trap del
#    cuerpo de uno metido en una función, que está muerto y se lee igual.
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
  # 8 hex y no un GUID entero: el anidado suma al largo del path. Medido con el payload real de
  # `export-shareable` (que copia sólo bootstrap-ai-project y upgrade-bootstrap) y este %TEMP%, el
  # peor caso daba 241 de los 260 de MAX_PATH; 19 caracteres de margen los consume un nombre de
  # usuario un poco más largo. Con 8 hex quedan 67. El PID separa corridas concurrentes; los 8 hex,
  # corridas sucesivas del mismo proceso. Sin test: pediría fabricar un %TEMP% profundo.
  $root = Join-Path $temp ("$Prefix-run-$PID-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
  # CreateDirectory y no New-Item: el path es literal y no se interpreta como wildcard, que es lo
  # que necesita el caso de los proyectos con corchetes en el nombre.
  [IO.Directory]::CreateDirectory($root) | Out-Null
  # Por edad: sin el filtro de fecha esto es el glob incondicional que mata corridas concurrentes.
  #
  # LastWriteTime y no CreationTime. Medido: crear o borrar una entrada DIRECTA del run root
  # actualiza su LastWriteTime; escribir más adentro, no. Así que LastWriteTime marca la última vez
  # que la corrida creó un workspace, y CreationTime el momento en que arrancó. Bajo las
  # operaciones que un run root sufre de verdad —crearlo, crearle hijos, moverlo— la primera nunca
  # queda más vieja que la segunda (sólo la atrasaría un seteo explícito hacia atrás, que acá no se
  # hace fuera de los fixtures), así que protege igual o mejor a una corrida larga. No es
  # autorrefresco: una corrida que ya creó todos sus workspaces envejece igual.
  # `tests/temp-hygiene.tests.ps1` cubre la diferencia con un fixture de tres días que escribió
  # recién; sin él, revertir esta línea a CreationTime pasaba en verde.
  #
  # -LiteralPath y no posicional: `-Path` interpreta wildcards, y si %TEMP% resolviera bajo un path
  # con corchetes la enumeración devolvería vacío y la recolección moriría en silencio — con
  # `-ErrorAction SilentlyContinue` tapando cualquier rastro. Es la misma razón por la que arriba
  # se usa CreateDirectory. Sin test: haría falta un %TEMP% con corchetes.
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
  # Un reintento, porque en Windows el borrado puede quedar PENDIENTE mientras otro proceso sostiene
  # un handle — con fixtures git es el proceso de fondo de git el que lo sostiene. Se observó al
  # menos una vez que la raíz sobrevivía a un `Remove-Item` verde y desaparecía después; el
  # reintento no reproduce hoy en corridas quiescentes. Su valor es el aviso: sin él,
  # `-ErrorAction SilentlyContinue` hace indistinguible "quedó pendiente" de "nunca se borró".
  # No se hace fallar la suite: es una fuga, no un test fallado, y un handle ajeno sería un rojo
  # que nadie puede arreglar desde acá.
  if (Test-Path -LiteralPath $Root) {
    Start-Sleep -Milliseconds 300
    Remove-Item -LiteralPath $Root -Recurse -Force -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $Root) {
      # -WarningAction Continue explícito: con `$WarningPreference = 'Stop'` un Write-Warning suelto
      # LANZA (medido), y esta función se llama desde el trap y desde un finally, donde eso taparía
      # el error original. Una fuga no es un test fallado.
      Write-Warning -WarningAction Continue -Message "no se pudo borrar la raíz temporal $Root (queda para la recolección por edad)"
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
  # dos casos es un test que miente. El tope de intentos NO es decorativo: sin él, un nombre que se
  # genere siempre igual convierte esto en un cuelgue en vez de un fallo, y medido eso dejó una
  # corrida colgada dos minutos y su árbol entero en %TEMP%.
  $d = $null
  for ($i = 0; $i -lt 20; $i++) {
    $cand = Join-Path $Root ("$Name-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    if (-not (Test-Path -LiteralPath $cand)) { $d = $cand; break }
  }
  if (-not $d) { throw "New-TestWorkspace: 20 intentos sin un nombre libre bajo $Root (¿nombre determinístico?)" }
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
  # El chequeo sólo descarta nombres que YA existen en disco. Como esta función no crea el archivo
  # a propósito, dos llamadas seguidas antes de que se escriba ninguno pueden devolver el mismo
  # nombre: no da unicidad, sólo evita pisar algo existente. Mismo tope que arriba, por la misma
  # razón.
  for ($i = 0; $i -lt 20; $i++) {
    $p = Join-Path $Root ("$Name-" + [guid]::NewGuid().ToString('N').Substring(0, 8) + $Extension)
    if (-not (Test-Path -LiteralPath $p)) { return $p }
  }
  throw "New-TestTempPath: 20 intentos sin un nombre libre bajo $Root (¿nombre determinístico?)"
}
