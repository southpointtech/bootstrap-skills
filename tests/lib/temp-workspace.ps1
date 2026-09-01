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
#    saltea. El trap tiene que vivir en el scope del SCRIPT que se está corriendo, no acá adentro
#    (un trap declarado dentro de una función solo atrapa lo de esa función), así que este archivo
#    NO lo declara y cada suite pone el suyo. `tests/temp-hygiene.tests.ps1` verifica que lo tenga:
#    sin esa verificación, olvidarlo deja la parte 2 muerta y nada se pone rojo.
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
  $root = Join-Path $temp ("$Prefix-run-$PID-" + [guid]::NewGuid().ToString('N'))
  # CreateDirectory y no New-Item: el path es literal y no se interpreta como wildcard, que es lo
  # que necesita el caso de los proyectos con corchetes en el nombre.
  [IO.Directory]::CreateDirectory($root) | Out-Null
  # Por edad y excluyendo la propia: sin el filtro de fecha esto es el glob incondicional que mata
  # corridas concurrentes. CreationTime y no LastWriteTime: una corrida viva y larga toca sus
  # archivos, pero su raíz se creó cuando arrancó.
  Get-ChildItem $temp -Directory -Filter "$Prefix-run-*" -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -ne $root -and $_.CreationTime -lt (Get-Date).AddDays(-1) } |
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
  return $root
}

# Borra la raíz de esta corrida. Idempotente y silenciosa: la llaman el trap Y el final de la
# suite, y en el camino de aborto las dos llegan.
function Remove-TestRunRoot {
  param([string]$Root)
  if ($Root -and (Test-Path -LiteralPath $Root)) {
    Remove-Item -LiteralPath $Root -Recurse -Force -ErrorAction SilentlyContinue
  }
}

# Un workspace de un caso, colgado de la raíz. El GUID mantiene los casos independientes entre sí
# dentro de la misma corrida.
function New-TestWorkspace {
  param(
    [Parameter(Mandatory)][string]$Root,
    [string]$Name = "ws"
  )
  $d = Join-Path $Root ("$Name-" + [guid]::NewGuid().ToString('N'))
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
  return (Join-Path $Root ("$Name-" + [guid]::NewGuid().ToString('N') + $Extension))
}
