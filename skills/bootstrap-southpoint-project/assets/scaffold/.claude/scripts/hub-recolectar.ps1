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
# Estado por repo en <StateDir>/<repo>/: `foto.json` (los SHA ya vistos) y `lotes/<momento>.json`.
# Vive fuera del repo para no ensuciar el árbol de trabajo del dev.
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
# inválida o git falla.
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

function Write-Utf8([string]$path, $obj) {
  [IO.Directory]::CreateDirectory((Split-Path $path -Parent)) | Out-Null
  [IO.File]::WriteAllText($path, ($obj | ConvertTo-Json -Depth 6), [Text.UTF8Encoding]::new($false))
}

$repoName = Split-Path $RepoDir -Leaf
$dir = Join-Path $StateDir $repoName
$lote = [ordered]@{
  schemaVersion = 1
  dev           = $Dev
  repo          = $repoName
  momento       = $Now
  resultado     = "sin cambios"
  propuestas    = @()
}
$archivo = Join-Path $dir ("lotes/" + ($Now -replace '[:-]', '') + ".json")

# Una corrida que falla también deja su lote: es lo que el tablero de corridas lee para ponerla en
# rojo. La foto no se toca, así que la corrida siguiente retoma desde donde estaba.
function Fallar([string]$motivo) {
  $lote.resultado = "falló"
  $lote.motivo = $motivo
  Write-Utf8 $archivo $lote
  Write-Output $archivo
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
if (-not ($decl.devs -is [pscustomobject])) { Fallar "la declaración no tiene devs" }
if (-not $decl.devs.PSObject.Properties[$Dev]) { exit 0 }
$emails = @($decl.devs.$Dev | Where-Object { $_ -is [string] -and $_.Trim() })
if (-not $emails.Count) { Fallar "el dev '$Dev' no tiene emails en la declaración" }
$lote.hubProject = $decl.hubProject
if ($decl.ongoingSupport) { $lote.ongoingSupport = $decl.ongoingSupport }

# Los commits del dev con `Slice-Close:`, en todas las ramas.
$log = git -C $RepoDir log --all --format="%H%x1f%ae%x1f%aI%x1f%s%x1f%(trailers:key=Slice-Close,valueonly,separator=%x2C)" 2>&1
if ($LASTEXITCODE -ne 0) { Fallar "git log falló en $RepoDir`: $($log -join ' ')" }
$slices = @($log |
  ForEach-Object {
    $c = $_ -split "`u{1f}"
    if ($c.Count -ge 5 -and $c[4].Trim() -and ($emails -contains $c[1])) {
      [pscustomobject]@{ sha = $c[0]; fecha = $c[2]; asunto = $c[3]; sliceClose = $c[4].Trim() }
    }
  })

# Sin foto es la primera corrida: fija la línea de base marcando todo lo existente como visto.
$fotoPath = Join-Path $dir "foto.json"
$propuestas = @()
if (Test-Path -LiteralPath $fotoPath) {
  $vistosAntes = @((Get-Content -LiteralPath $fotoPath -Raw | ConvertFrom-Json).vistos)
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
Write-Utf8 $archivo $lote
Write-Utf8 $fotoPath ([ordered]@{ schemaVersion = 1; vistos = @($slices.sha) })
Write-Output $archivo
