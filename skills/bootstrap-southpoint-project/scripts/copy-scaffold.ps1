# copy-scaffold.ps1 — copia assets\scaffold\ al proyecto archivo por archivo, mergeando en
# directorios preexistentes. Nunca copia un directorio como unidad: Copy-Item -Recurse sobre un
# destino existente anida (docs -> docs\docs, .agents -> .agents\.agents) en vez de mergear.
# Paths siempre literales (-LiteralPath / APIs .NET): un proyecto con corchetes en el nombre
# (app[v2]) rompe los cmdlets que interpretan wildcards.
# gitignore.txt aterriza como .gitignore (en assets se llama así para que el repo de la skill
# no lo trate como ignore propio). Este mapeo debe coincidir con el de tools/gen-manifest.ps1:
# las rutas que aterrizan acá son las claves del .bootstrap-manifest.json que consume upgrade-bootstrap.
# Uso: pwsh -NoProfile -File copy-scaffold.ps1 -SkillDir <dir de esta skill> -ProjectDir <raíz del proyecto>
param(
  [Parameter(Mandatory)][string]$SkillDir,
  [Parameter(Mandatory)][string]$ProjectDir
)
$ErrorActionPreference = "Stop"

$scaffold = Join-Path $SkillDir "assets\scaffold"
if (-not (Test-Path -LiteralPath $scaffold -PathType Container))   { throw "No existe el scaffold: $scaffold" }
if (-not (Test-Path -LiteralPath $ProjectDir -PathType Container)) { throw "No existe el proyecto: $ProjectDir" }
$scaffold   = (Resolve-Path -LiteralPath $scaffold).Path
$ProjectDir = (Resolve-Path -LiteralPath $ProjectDir).Path

Get-ChildItem -LiteralPath $scaffold -Recurse -File -Force | ForEach-Object {
  $rel = [IO.Path]::GetRelativePath($scaffold, $_.FullName)
  if ($rel -eq "gitignore.txt") { $rel = ".gitignore" }
  $dest = Join-Path $ProjectDir $rel
  [IO.Directory]::CreateDirectory((Split-Path $dest -Parent)) | Out-Null
  # File.Copy con overwrite no pisa destinos read-only/ocultos (Copy-Item -Force sí lo hacía)
  if ([IO.File]::Exists($dest)) { [IO.File]::SetAttributes($dest, 'Normal') }
  [IO.File]::Copy($_.FullName, $dest, $true)
}
