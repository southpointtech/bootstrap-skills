<#
.SYNOPSIS
  Abre el worktree de un carril: rama slice/<Slice>-<Slug> salida de la base, fuera del repo,
  con los archivos gitignoreados que el carril necesita copiados adentro.

.DESCRIPTION
  Un worktree nuevo no trae nada de lo que esta en el .gitignore. Si el carril no tiene su
  .env los tests de config fallan por una causa ajena, y si no tiene la carpeta de issues
  inventa el alcance. Este script abre el worktree y copia esas rutas.

  Mecanica del scaffold: no se edita por proyecto (docs/adr/0011 del repo de origen). Lo que
  cambia por proyecto se lee del archivo de datos (-Datos), que es obligatorio.

.EXAMPLE
  pwsh -File .claude/scripts/abrir-carril.ps1 -Slice 15b -Slug el-reparto
  pwsh -File .claude/scripts/abrir-carril.ps1 -Slice 07 -Slug padron -Root C:\Repos\carriles -Copy .env,.scratch -DryRun
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)] [string] $Slice,
  [Parameter(Mandatory)] [string] $Slug,
  # Carpeta donde viven los worktrees. Por defecto: <padre del repo>\carriles\<nombre del repo>
  [string] $Root,
  [string] $Base,
  # Rutas relativas al repo, gitignoreadas, que el carril necesita. Las que no existen se informan y se saltean.
  [string[]] $Copy,
  # Datos del proyecto, relativo al repo o absoluto.
  [string] $Datos = 'docs/ai-workflow/PARALELISMO-DEL-PROYECTO.md',
  [switch] $DryRun
)

$ErrorActionPreference = 'Stop'

# git escribe UTF-8 y PowerShell decodifica la salida del hijo con Console::OutputEncoding, que en
# un pwsh con stdout redirigido es el code page OEM de la maquina. Sin esto, `rev-parse
# --show-toplevel` llega deformado en un repo con acentos en la ruta y el script muere con un error
# crudo en vez de abrir el carril. Es el mismo arreglo que ya tiene review-marker.ps1. Se setea y no
# se restaura: este script siempre corre como proceso hijo y efimero.
try { [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false) } catch { }

# Un rechazo sale con 1 y el motivo en stderr. `throw` tambien saldria con 1, pero con el
# motivo enterrado en el formato de error de PowerShell.
function Rechazar([string] $motivo) {
  [Console]::Error.WriteLine("abrir-carril: $motivo")
  exit 1
}

$repo = (git rev-parse --show-toplevel 2>$null)
if (-not $repo) { Rechazar 'No estoy dentro de un repo git.' }
$repo = (Resolve-Path $repo).Path
$repoName = Split-Path $repo -Leaf

# --- Datos del proyecto ---
$datosPath = if ([IO.Path]::IsPathRooted($Datos)) { $Datos } else { Join-Path $repo $Datos }
# Un dato que falta bloquea la ola: sin -DryRun se rechaza, con -DryRun se avisa y se sigue.
function Bloqueo([string] $motivo) {
  if (-not $DryRun) { Rechazar $motivo }
  Write-Warning $motivo
}

$lineas = @()
if (Test-Path -LiteralPath $datosPath -PathType Leaf) {
  $lineas = @([IO.File]::ReadAllLines($datosPath))
} else {
  Bloqueo "No existe el archivo de datos del proyecto: $datosPath. Rellenalo antes de abrir un carril."
}

# Una marca `{{` es un dato sin rellenar. Se listan todas, con su numero de linea.
$marcas = @(for ($i = 0; $i -lt $lineas.Count; $i++) {
  if ($lineas[$i].Contains('{{')) { "  {0}: {1}" -f ($i + 1), $lineas[$i] }
})
if ($marcas) {
  Bloqueo ("Los datos del proyecto tienen marcas sin rellenar ($datosPath). Un dato que no aplica se escribe 'no aplica'.`n" + ($marcas -join "`n"))
}

# El bloque cercado ```carriles: lineas `clave: valor`, formato cerrado. Se lee solo el bloque, no
# el markdown libre de alrededor. Un bloque mal formado es un error aun con -DryRun: no es un dato
# que falta, es un archivo que el script no sabe leer.
$claves = @('copiar', 'worktrees', 'base')
$bloque = @{}
$inicios = @(for ($i = 0; $i -lt $lineas.Count; $i++) { if ($lineas[$i] -match '^\s*```carriles\s*$') { $i } })
if ($inicios.Count -gt 1) { Rechazar "Los datos del proyecto tienen $($inicios.Count) bloques 'carriles'; tiene que haber uno solo." }
if ($inicios.Count -eq 1) {
  $cerrado = $false
  for ($i = $inicios[0] + 1; $i -lt $lineas.Count; $i++) {
    $l = $lineas[$i]
    if ($l -match '^\s*```') { $cerrado = $true; break }
    if (-not $l.Trim()) { continue }
    if ($l -notmatch '^\s*([^:]+?)\s*:\s*(.*?)\s*$') { Rechazar "Linea $($i + 1) del bloque 'carriles' sin forma 'clave: valor': $l" }
    $clave = $Matches[1]; $valor = $Matches[2]
    if ($clave -notin $claves) { Rechazar "Clave desconocida '$clave' en la linea $($i + 1) del bloque 'carriles'. Las validas: $($claves -join ', ')." }
    if ($bloque.ContainsKey($clave)) { Rechazar "La clave '$clave' aparece dos veces en el bloque 'carriles'." }
    # 'no aplica' es un valor valido y equivale a no declarar la clave: rige el default. Un valor
    # con marca vale lo mismo: la plantilla recien bootstrapeada trae las tres claves con marca, y
    # tomarlas como valor hacia fallar el -DryRun ('La base {{main}} no existe'), que es justo lo
    # que tiene que salir 0 para mostrar que faltan los datos.
    if ($valor -and $valor -ne 'no aplica' -and -not $valor.Contains('{{')) { $bloque[$clave] = $valor }
  }
  if (-not $cerrado) { Rechazar "El bloque 'carriles' de los datos del proyecto no esta cerrado con ```." }
}

# Precedencia: parametro > bloque > default.
if (-not $Base) { $Base = if ($bloque.base) { $bloque.base } else { 'main' } }
if (-not $Copy) { $Copy = if ($bloque.copiar) { @($bloque.copiar) } else { @('.env', '.env.local', '.scratch') } }
if (-not $Root -and $bloque.worktrees) {
  $Root = if ([IO.Path]::IsPathRooted($bloque.worktrees)) { $bloque.worktrees } else { Join-Path $repo $bloque.worktrees }
}

# Con `pwsh -File`, `-Copy .env,.scratch` llega como una sola cadena
$Copy = @($Copy | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })

if (-not $Root) { $Root = Join-Path (Split-Path $repo -Parent) (Join-Path 'carriles' $repoName) }
# Absoluto antes de usarlo: `git -C $repo worktree add` resuelve un relativo contra el REPO y los
# cmdlets de copia contra la cwd, asi que con la cwd en un subdirectorio el worktree quedaba en un
# lado y lo copiado en otro. GetUnresolvedProviderPathFromPSPath y no Resolve-Path: la carpeta
# todavia no existe.
$Root = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Root)
$branch = "slice/$Slice-$Slug"
$path = Join-Path $Root "slice-$Slice"

git -C $repo rev-parse --verify --quiet "$Base^{commit}" | Out-Null
if ($LASTEXITCODE -ne 0) { Rechazar "La base '$Base' no existe." }
git -C $repo show-ref --verify --quiet "refs/heads/$branch"
if ($LASTEXITCODE -eq 0) { Rechazar "La rama '$branch' ya existe. Un carril no vive dos olas: elegi otro slug o revisa la rama vieja." }
if (Test-Path -LiteralPath $path) { Rechazar "La carpeta '$path' ya existe." }

$baseSha = (git -C $repo rev-parse --short $Base).Trim()
Write-Host "Repo:     $repo"
Write-Host "Worktree: $path"
Write-Host "Rama:     $branch  (desde $Base @ $baseSha)"

if ($DryRun) {
  foreach ($rel in $Copy) {
    $src = Join-Path $repo $rel
    Write-Host ("Copiaria: {0}  {1}" -f $rel, $(if (Test-Path -LiteralPath $src) { '(existe)' } else { '(no existe, se saltea)' }))
  }
  Write-Host 'DryRun: no se creo nada.'
  return
}

New-Item -ItemType Directory -Force $Root | Out-Null
git -C $repo worktree add -b $branch $path $Base
if ($LASTEXITCODE -ne 0) { Rechazar 'git worktree add fallo.' }

$copied = @(); $skipped = @()
foreach ($rel in $Copy) {
  $src = Join-Path $repo $rel
  if (-not (Test-Path -LiteralPath $src)) { $skipped += $rel; continue }
  $dst = Join-Path $path $rel
  $parent = Split-Path $dst -Parent
  if ($parent) { New-Item -ItemType Directory -Force $parent | Out-Null }
  if ((Get-Item -LiteralPath $src -Force).PSIsContainer) {
    # Copia el contenido sobre la carpeta destino (si la rama ya trae una, se completa)
    New-Item -ItemType Directory -Force $dst | Out-Null
    Copy-Item -Path (Join-Path $src '*') -Destination $dst -Recurse -Force
  } else {
    Copy-Item -LiteralPath $src -Destination $dst -Force
  }
  $copied += $rel
}

Write-Host ''
Write-Host ("Copiado:  {0}" -f $(if ($copied) { $copied -join ', ' } else { '(nada)' }))
if ($skipped) { Write-Host ("Salteado: {0}  (no existen en el repo)" -f ($skipped -join ', ')) }

# Lo copiado tiene que seguir fuera del diff del carril
$dirty = git -C $path status --porcelain
if ($dirty) {
  Write-Warning "El worktree nuevo no esta limpio: algo de lo copiado no esta gitignoreado.`n$dirty"
} else {
  Write-Host 'Worktree limpio: lo copiado no entra en el diff.'
}
