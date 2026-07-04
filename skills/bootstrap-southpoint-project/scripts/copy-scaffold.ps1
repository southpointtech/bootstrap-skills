# copy-scaffold.ps1 — copia assets\scaffold\ al proyecto archivo por archivo, mergeando en
# directorios preexistentes. Nunca copia un directorio como unidad: Copy-Item -Recurse sobre un
# destino existente anida (docs -> docs\docs, .agents -> .agents\.agents) en vez de mergear.
# gitignore.txt aterriza como .gitignore (en assets se llama así para que el repo de la skill
# no lo trate como ignore propio).
# Uso: pwsh -NoProfile -File copy-scaffold.ps1 -SkillDir <dir de esta skill> -ProjectDir <raíz del proyecto>
param(
  [Parameter(Mandatory)][string]$SkillDir,
  [Parameter(Mandatory)][string]$ProjectDir
)
$ErrorActionPreference = "Stop"

$scaffold = Join-Path $SkillDir "assets\scaffold"
if (-not (Test-Path $scaffold -PathType Container))   { throw "No existe el scaffold: $scaffold" }
if (-not (Test-Path $ProjectDir -PathType Container)) { throw "No existe el proyecto: $ProjectDir" }
$scaffold = (Resolve-Path $scaffold).Path

Get-ChildItem $scaffold -Recurse -File -Force | ForEach-Object {
  $rel = [IO.Path]::GetRelativePath($scaffold, $_.FullName)
  if ($rel -eq "gitignore.txt") { $rel = ".gitignore" }
  $dest    = Join-Path $ProjectDir $rel
  $destDir = Split-Path $dest -Parent
  if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
  Copy-Item $_.FullName $dest -Force
}
