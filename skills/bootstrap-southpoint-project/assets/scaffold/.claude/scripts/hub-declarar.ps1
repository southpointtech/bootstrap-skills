# .claude/scripts/hub-declarar.ps1 — crea o actualiza la declaración de hub-sync del repo.
#
#   pwsh -File .claude/scripts/hub-declarar.ps1 -RepoDir <repo> [-HubProject <texto>] [-OngoingSupport <texto>] [-Agregarme] [-Dev <usuario>]
param(
  [Parameter(Mandatory)][string]$RepoDir,
  [string]$HubProject,
  [string]$OngoingSupport,
  [switch]$Agregarme,
  [string]$Dev = $env:USERNAME
)
$ErrorActionPreference = "Stop"
$utf8 = [Text.UTF8Encoding]::new($false)

function Write-Stdout([string]$texto) {
  $s = [Console]::OpenStandardOutput()
  $b = $utf8.GetBytes($texto + "`n")
  $s.Write($b, 0, $b.Length)
  $s.Flush()
}

# El motivo va por stderr en bytes UTF-8, por lo mismo que stdout: `[Console]::Error` lo codifica con
# la code page de la consola, y un motivo con acentos llega deformado a quien lo lee como UTF-8.
function Fallar([string]$motivo) {
  $s = [Console]::OpenStandardError()
  $b = $utf8.GetBytes("hub-declarar: $motivo`n")
  $s.Write($b, 0, $b.Length)
  $s.Flush()
  exit 1
}

# La clave de `$tabla` que coincide con `$nombre` sin distinguir mayúsculas, o `$nombre` si no hay.
# El recolector busca las claves así, y una segunda clave que sólo difiere en mayúsculas hace que
# ConvertFrom-Json rechace el archivo entero: reusar la que ya está evita escribirla.
function Get-Clave($tabla, [string]$nombre) {
  $c = @($tabla.Keys | Where-Object { $_ -ieq $nombre } | Select-Object -First 1)
  if ($c.Count) { $c[0] } else { $nombre }
}

# Las reglas con las que el recolector (hub-recolectar.ps1) rechaza una declaración, sobre el texto
# que quedaría escrito. Un motivo, o $null si la acepta. Es una copia: si cambian allá, hay que
# cambiarlas acá.
function Get-MotivoRechazo([string]$texto) {
  try { $d = $texto | ConvertFrom-Json } catch { return "no es JSON válido: $($_.Exception.Message)" }
  if ($d.schemaVersion -ne 1) { return "schemaVersion no soportado: '$($d.schemaVersion)' (se espera 1)" }
  if (-not ($d.hubProject -is [string]) -or -not $d.hubProject.Trim()) { return "no nombra el hubProject: pasá -HubProject" }
  if ($null -ne $d.PSObject.Properties['ongoingSupport'] -and
      (-not ($d.ongoingSupport -is [string]) -or -not $d.ongoingSupport.Trim())) {
    return "el ongoingSupport tiene que ser un texto no vacío"
  }
  if (-not ($d.devs -is [pscustomobject])) { return "no tiene un objeto devs" }
  return $null
}

$declPath = Join-Path $RepoDir ".claude/hub-sync.json"
# Los emails con los que este dev commitea en el repo: la identidad git efectiva (la local que fija
# el Step 5 del bootstrap, o la global si no hay) y la de `setup-mcp-workstation`. El recolector
# filtra los commits por estos emails, así que uno que falte es un slice que no se propone.
$propios = @((& git -C $RepoDir config user.email 2>$null), $env:SOUTHPOINT_GIT_EMAIL)

# La declaración que ya existe se lee como tabla ORDENADA: reescribirla conserva el orden de sus
# claves y cualquier campo que este script no conoce.
$existe = Test-Path -LiteralPath $declPath
if ($existe) {
  try { $decl = [IO.File]::ReadAllText($declPath) | ConvertFrom-Json -AsHashtable }
  catch { Fallar "$declPath no es JSON válido: $($_.Exception.Message)" }
  if (-not ($decl -is [Collections.IDictionary]) -or -not ($decl[(Get-Clave $decl 'devs')] -is [Collections.IDictionary])) {
    Fallar "$declPath no tiene un objeto devs; corregila a mano"
  }
} else {
  if (-not $HubProject.Trim()) { Fallar "el repo no tiene declaración: pasá -HubProject con el proyecto del Hub" }
  $decl = [ordered]@{ schemaVersion = 1; hubProject = $HubProject; devs = [ordered]@{} }
}
# El contenido de partida, para no reescribir un archivo que no cambió: se compara el contenido y no
# el texto, así que una declaración escrita a mano con otro formato tampoco se reformatea.
$inicial = ConvertTo-Json -InputObject $decl -Depth 5 -Compress

# Un texto vacío no escribe el campo: el recolector rechaza un ongoingSupport vacío.
if ($HubProject.Trim()) { $decl[(Get-Clave $decl 'hubProject')] = $HubProject.Trim() }
if ($OngoingSupport.Trim()) { $decl[(Get-Clave $decl 'ongoingSupport')] = $OngoingSupport.Trim() }
$devs = $decl[(Get-Clave $decl 'devs')]

# Los emails que el dev ya tenía van primero; los nuevos se suman al final, sin repetir. Sin
# distinguir mayúsculas, igual que el recolector, que filtra los commits con `-contains`.
$emails = [Collections.Generic.List[string]]::new()
if ($Agregarme) {
  $Dev = Get-Clave $devs $Dev
  foreach ($e in @($devs[$Dev]) + $propios) {
    $e = "$e".Trim()
    if ($e -and -not ($emails | Where-Object { $_ -ieq $e })) { $emails.Add($e) }
  }
  if (-not $emails.Count) { Fallar "no hay email para '$Dev': ni git config user.email ni SOUTHPOINT_GIT_EMAIL" }
  $devs[$Dev] = $emails.ToArray()
}
# Nada se da por declarado si el recolector lo rechazaría, tampoco lo que ya estaba en el archivo.
$texto = (ConvertTo-Json -InputObject $decl -Depth 5) + "`n"
$motivo = Get-MotivoRechazo $texto
if ($motivo) { Fallar "la declaración quedaría inválida para el recolector: $motivo" }
if (-not $existe) { $accion = 'creada' }
elseif ((ConvertTo-Json -InputObject $decl -Depth 5 -Compress) -ceq $inicial) { $accion = 'sin-cambios' }
else { $accion = 'actualizada' }
if ($accion -ne 'sin-cambios') {
  [IO.Directory]::CreateDirectory((Split-Path $declPath -Parent)) | Out-Null
  [IO.File]::WriteAllText($declPath, $texto, $utf8)
}
Write-Stdout (ConvertTo-Json -Compress -InputObject ([ordered]@{ accion = $accion; dev = $Dev; emails = $emails.ToArray() }))
exit 0
