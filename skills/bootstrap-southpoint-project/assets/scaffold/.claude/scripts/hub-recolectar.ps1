# .claude/scripts/hub-recolectar.ps1 — recolección de hub-sync (ver docs/adr/0012 en Bootstrap Skills).
#
# Lee los commits del dev con trailer `Slice-Close:` y escribe un LOTE JSON por corrida con una
# propuesta de tipo `update` por slice cerrado. No toca el Hub ni usa un LLM: el lote lo lleva el
# transporte a `inbox/` y sólo el PM decide qué se publica.
#
#   pwsh -File .claude/scripts/hub-recolectar.ps1 -RepoDir <repo> -Dev <nombre> [-StateDir <dir>] [-Now <iso>]
#
# Declaración, commiteada en el repo: `.claude/hub-sync.json`. Sin ella el repo no se recolecta.
#
#   { "schemaVersion": 1,
#     "hubProject": "<proyecto del Hub>",
#     "ongoingSupport": "<Ongoing Support, opcional>",
#     "devs": { "<nombre>": ["<email>", "<otro email del mismo dev>"] } }
#
# Estado por repo en <StateDir>/<repo>-<hash>/: `foto.json` (los SHA ya vistos) y
# `lotes/<momento>.json`. Vive fuera del repo para no ensuciar el árbol de trabajo del dev. El hash es
# del directorio git común del repo, así que dos repos con el mismo nombre de carpeta no comparten
# foto, y los worktrees de un mismo repo sí.
#
# La primera corrida fija la línea de base: marca como vistos los slices que ya existen y no propone
# el histórico. Se recorren todas las refs (`git log --all`: ramas locales y las remotas que ya estén
# fetcheadas; el script no hace fetch) y la foto guarda SHA, no una
# posición en una rama, así que cambiar de rama no pierde ni repite slices.
# Límite conocido: un squash-merge crea un SHA nuevo con el mismo trailer y se propone dos veces;
# el PM descarta el duplicado al aprobar.
#
# Salida: la ruta del lote por stdout. Exit 0 con lote `ok` o `sin cambios`; exit 0 sin lote si no
# hay declaración o el dev no figura en ella; exit 1 con lote `falló` + motivo si la declaración es
# inválida, la foto es ilegible o git falla.
param(
  [Parameter(Mandatory)][string]$RepoDir,
  [Parameter(Mandatory)][string]$Dev,
  [string]$StateDir = (Join-Path $env:LOCALAPPDATA "hub-sync"),
  [string]$Now = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
)
$ErrorActionPreference = "Stop"
# pwsh decodifica la salida de git con [Console]::OutputEncoding, que en estas máquinas es ibm850: sin
# esto un asunto con acentos llega deformado al lote. git emite UTF-8 (i18n.logOutputEncoding).
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$utf8 = [Text.UTF8Encoding]::new($false)

# La identidad del repo es su directorio git común, no el nombre de la carpeta: dos clones con el
# mismo nombre compartirían la foto y se re-propondrían el histórico uno al otro en cada corrida. Si
# no es un repo git, la ruta de la carpeta (la corrida va a fallar igual, pero su lote tiene dónde ir).
$comun = git -C $RepoDir rev-parse --path-format=absolute --git-common-dir 2>$null
if ($LASTEXITCODE -eq 0 -and $comun) {
  $identidad = [IO.Path]::GetFullPath(([string]$comun).Trim())
  $repoName = if ((Split-Path $identidad -Leaf) -eq ".git") { Split-Path (Split-Path $identidad -Parent) -Leaf } else { Split-Path $identidad -Leaf }
} else {
  $identidad = [IO.Path]::GetFullPath($RepoDir)
  $repoName = Split-Path $identidad.TrimEnd('\', '/') -Leaf
}
$hash = [BitConverter]::ToString([Security.Cryptography.SHA256]::HashData(
  $utf8.GetBytes($identidad.TrimEnd('\', '/').ToLowerInvariant()))).Replace("-", "").Substring(0, 8).ToLowerInvariant()
$dir = Join-Path $StateDir "$repoName-$hash"
$lote = [ordered]@{
  schemaVersion = 1
  dev           = $Dev
  repo          = $repoName
  momento       = $Now
  resultado     = "sin cambios"
  propuestas    = @()
}

# El lote se crea con CreateNew: dos corridas con el mismo momento (una manual y la programada) no se
# pisan, la segunda lleva sufijo. Pisar un `ok` con un `sin cambios` perdería sus propuestas, porque
# la foto ya las marcó como vistas.
function Write-Lote {
  $lotes = Join-Path $dir "lotes"
  [IO.Directory]::CreateDirectory($lotes) | Out-Null
  $base = Join-Path $lotes ($Now -replace '[:-]', '')
  $bytes = $utf8.GetBytes(($lote | ConvertTo-Json -Depth 6))
  for ($i = 1; $i -le 100; $i++) {
    $p = if ($i -eq 1) { "$base.json" } else { "$base-$i.json" }
    try { $fs = [IO.File]::Open($p, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write) }
    catch [IO.IOException] { if (Test-Path -LiteralPath $p) { continue } else { throw } }
    try { $fs.Write($bytes, 0, $bytes.Length) } finally { $fs.Dispose() }
    return $p
  }
  throw "100 lotes con el momento $Now en $lotes"
}

# Una corrida que falla también deja su lote: es lo que el tablero de corridas lee para ponerla en
# rojo. La foto no se toca, así que la corrida siguiente retoma desde donde estaba.
function Fallar([string]$motivo) {
  $lote.resultado = "falló"
  $lote.motivo = $motivo
  Write-Output (Write-Lote)
  exit 1
}

# Sin declaración el repo no se recolecta; y un dev que no figura en ella no tiene nada que proponer.
# Los dos salen sin lote y en exit 0: no son fallas, son repos o devs fuera de hub-sync.
$declPath = Join-Path $RepoDir ".claude/hub-sync.json"
if (-not (Test-Path -LiteralPath $declPath)) { exit 0 }
try { $decl = Get-Content -LiteralPath $declPath -Raw | ConvertFrom-Json }
catch { Fallar "la declaración .claude/hub-sync.json no es JSON válido: $($_.Exception.Message)" }
if ($decl.schemaVersion -ne 1) { Fallar "schemaVersion de la declaración no soportado: '$($decl.schemaVersion)' (se espera 1)" }
if (-not ($decl.hubProject -is [string]) -or -not $decl.hubProject.Trim()) { Fallar "la declaración no nombra el hubProject" }
if ($null -ne $decl.PSObject.Properties['ongoingSupport'] -and
    (-not ($decl.ongoingSupport -is [string]) -or -not $decl.ongoingSupport.Trim())) {
  Fallar "el ongoingSupport de la declaración tiene que ser un texto no vacío"
}
if (-not ($decl.devs -is [pscustomobject])) { Fallar "la declaración no tiene devs" }
if (-not $decl.devs.PSObject.Properties[$Dev]) { exit 0 }
$emails = @($decl.devs.$Dev | Where-Object { $_ -is [string] -and $_.Trim() })
if (-not $emails.Count) { Fallar "el dev '$Dev' no tiene emails en la declaración" }
$lote.hubProject = $decl.hubProject
if ($decl.ongoingSupport) { $lote.ongoingSupport = $decl.ongoingSupport }

# Los commits con `Slice-Close:`, en todas las ramas.
# El cuerpo entero (%B) y no `%(trailers)`: el parser de trailers de git sólo lee el ÚLTIMO párrafo, y
# el commit estándar del workflow cierra con `Co-Authored-By:` tras una línea en blanco, así que el
# `Slice-Close:` queda en el penúltimo y git no lo ve. Detecta la línea como el hook
# review-loop-trigger (a principio de línea, sin distinguir mayúsculas), pero además exige un valor en
# la misma línea: un `Slice-Close:` vacío no es un cierre, y con `\s*` el valor sería la línea
# siguiente. Un registro por commit, separado por \x1e, porque el cuerpo trae saltos de línea.
$log = git -C $RepoDir log --all --format="%H%x1f%ae%x1f%aI%x1f%s%x1f%B%x1e" 2>&1
if ($LASTEXITCODE -ne 0) { Fallar "git log falló en $RepoDir`: $($log -join ' ')" }
# Sólo stdout: con `2>&1` lo que git escribe en stderr aunque salga 0 (p.ej. los hints de grafts)
# llega como ErrorRecord, y unido al texto quedaría pegado delante de un SHA.
$stdout = @($log | Where-Object { $_ -is [string] })
$todos = @(($stdout -join "`n") -split "`u{1e}" |
  ForEach-Object {
    $c = $_.TrimStart("`n") -split "`u{1f}"
    if ($c.Count -lt 5 -or $c[0] -notmatch '^[0-9a-f]{40}$') { return }
    $valores = @([regex]::Matches($c[4], '(?im)^[ \t]*Slice-Close:[ \t]*(\S.*?)[ \t\r]*$') | ForEach-Object { $_.Groups[1].Value })
    if ($valores.Count) {
      [pscustomobject]@{ sha = $c[0]; email = $c[1]; fecha = $c[2]; asunto = $c[3]; sliceClose = $valores -join ", " }
    }
  })
# Sólo los del dev se proponen, pero la foto guarda los de TODOS los autores: si más tarde se agrega un
# email a la declaración, el histórico de esa cuenta ya está visto y no se re-propone entero.
$slices = @($todos | Where-Object { $emails -contains $_.email })

# Sin foto es la primera corrida: fija la línea de base marcando todo lo existente como visto.
# Una foto ilegible falla con lote y no se pisa: re-fijar la línea de base en silencio perdería los
# slices que estaban pendientes.
$fotoPath = Join-Path $dir "foto.json"
$propuestas = @()
if (Test-Path -LiteralPath $fotoPath) {
  try { $foto = Get-Content -LiteralPath $fotoPath -Raw | ConvertFrom-Json }
  catch { Fallar "la foto $fotoPath es ilegible: $($_.Exception.Message)" }
  if ($null -eq $foto -or $null -eq $foto.PSObject.Properties['vistos']) { Fallar "la foto $fotoPath no tiene la lista de vistos" }
  $vistosAntes = @($foto.vistos)
  $propuestas = @($slices | Where-Object { $vistosAntes -notcontains $_.sha } | ForEach-Object {
    [ordered]@{
      id      = "commit:$($_.sha)"
      tipo    = "update"
      destino = "delivery"
      estado  = "nueva"
      hechos  = [ordered]@{ sha = $_.sha; asunto = $_.asunto; sliceClose = $_.sliceClose; fecha = $_.fecha }
    }
  })
}

if ($propuestas.Count) { $lote.resultado = "ok"; $lote.propuestas = $propuestas }
# El lote antes que la foto: si la corrida muere entre las dos, la próxima vuelve a proponer lo mismo
# y la ingesta lo deduplica por id. Al revés, se perdería.
$archivo = Write-Lote
# La foto se escribe aparte y se mueve encima: WriteAllText trunca antes de escribir, y una PC que se
# apaga a mitad dejaría una foto cortada.
$tmp = "$fotoPath.tmp"
[IO.File]::WriteAllText($tmp, ([ordered]@{ schemaVersion = 1; vistos = @($todos | ForEach-Object { $_.sha }) } | ConvertTo-Json -Depth 3), $utf8)
[IO.File]::Move($tmp, $fotoPath, $true)
Write-Output $archivo
