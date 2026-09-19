# tests/gitattributes-scaffold.tests.ps1 — runner sin Pester.
# Correr: pwsh -NoProfile -File tests/gitattributes-scaffold.tests.ps1
#
# POR QUÉ EXISTE (issue v2 22): `tests/sh-eol.tests.ps1` cubre los `.sh` de ESTE repo, que tiene su
# `.gitattributes` en la raíz. Afuera de este repo nada los protegía: un proyecto bootstrapeado, o un
# clon del repo público, en Windows con `core.autocrlf=true` escribe los `.sh` con CRLF, y un bash de
# Linux o WSL corta en `set -euo pipefail\r`. Cada scaffold lleva ahora su propio `.gitattributes`.
#
# Se mide sobre el comportamiento, no sobre el texto: se commitea el árbol con autocrlf, se clona con
# autocrlf y se cuentan los `\r` de cada `.sh` del clon. Los dos casos:
#   A. el proyecto bootstrapeado: `copy-scaffold.ps1` a un directorio vacío, que pasa a ser el repo;
#   B. el repo público: la skill entera en `skills/<skill>/` de un repo que NO tiene `.gitattributes`
#      en la raíz, así que el único que puede proteger los `.sh` es el del scaffold anidado.
# Cada caso tiene su control positivo: el mismo recorrido sin el `.gitattributes` TIENE que dejar CR.
# Sin él, un git que no convierte (autocrlf ignorado, un `.sh` que ya no existe) daría verde vacío.
$ErrorActionPreference = "Stop"
$repo = Split-Path $PSScriptRoot -Parent
$script:failures = 0
$script:checks   = 0

function Assert($cond, $msg) {
  $script:checks++
  if ($cond) { Write-Host "ok:   $msg" } else { Write-Host "FAIL: $msg"; $script:failures++ }
}

. (Join-Path $PSScriptRoot "lib\temp-workspace.ps1")
$script:runRoot = New-TestRunRoot "ga"
trap { Remove-TestRunRoot $script:runRoot; break }

$skills = @("bootstrap-personal-project", "bootstrap-southpoint-project", "bootstrap-ai-project")

# git con identidad y autocrlf fijos: el resultado no puede depender de la config global de la máquina.
function Invoke-Git([string]$dir, [string[]]$argv) {
  & git -C $dir -c core.autocrlf=true -c user.name=t -c user.email=t@t -c commit.gpgsign=false @argv 2>&1 | Out-Null
  return $LASTEXITCODE
}

# Commitea $src como repo nuevo, lo clona con autocrlf=true y devuelve cuántos `.sh` hay en el clon
# y cuántos tienen al menos un CR. `-c core.autocrlf=true` en el clone queda en la config del clon
# ANTES del checkout, que es cuando se escribe el disco.
function Measure-ClonedSh([string]$src, [string]$name) {
  $code = (Invoke-Git $src @("init", "-q")) + (Invoke-Git $src @("add", "-A")) + (Invoke-Git $src @("commit", "-q", "-m", "x"))
  $clone = Join-Path $script:runRoot "$name-clone"
  & git -c core.autocrlf=true clone -q $src $clone 2>&1 | Out-Null
  $code += $LASTEXITCODE
  $shs = @(Get-ChildItem -LiteralPath $clone -Recurse -File -Force -Filter "*.sh" |
    Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' })
  $conCr = @($shs | Where-Object { @([IO.File]::ReadAllBytes($_.FullName) | Where-Object { $_ -eq 13 }).Count -gt 0 })
  return @{ code = $code; total = $shs.Count; conCr = $conCr.Count }
}

# --- 0. Cada scaffold lleva la regla --------------------------------------------------------------
foreach ($s in $skills) {
  $ga = Join-Path $repo "skills/$s/assets/scaffold/.gitattributes"
  $lineas = if (Test-Path -LiteralPath $ga) { @(Get-Content -LiteralPath $ga) } else { @() }
  Assert ($lineas -ccontains "*.sh text eol=lf") "${s}: el scaffold trae .gitattributes con '*.sh text eol=lf'"
}

# --- A. Proyecto bootstrapeado --------------------------------------------------------------------
$skillP = Join-Path $repo "skills/bootstrap-personal-project"
foreach ($conAtributos in @($true, $false)) {
  $nombre = if ($conAtributos) { "proj" } else { "proj-control" }
  $p = New-TestWorkspace $script:runRoot $nombre
  & pwsh -NoProfile -File (Join-Path $skillP "scripts/copy-scaffold.ps1") -SkillDir $skillP -ProjectDir $p | Out-Null
  Assert ($LASTEXITCODE -eq 0) "A/${nombre}: copy-scaffold salió con exit 0"
  if (-not $conAtributos) { Remove-Item -LiteralPath (Join-Path $p ".gitattributes") -Force -ErrorAction SilentlyContinue }
  $m = Measure-ClonedSh $p $nombre
  Assert ($m.code -eq 0 -and $m.total -ge 2) "A/${nombre}: commit y clon sin error, con .sh en el clon (exit $($m.code), $($m.total) .sh)"
  if ($conAtributos) {
    Assert ($m.conCr -eq 0) "A: con el .gitattributes del scaffold, ningún .sh del clon tiene CR ($($m.conCr) de $($m.total))"
  } else {
    Assert ($m.conCr -gt 0) "A/control: sin .gitattributes el clon SÍ escribe CR ($($m.conCr) de $($m.total)); si no, el caso A no mide nada"
  }
}

# --- B. Repo público: la skill anidada en skills/, sin .gitattributes en la raíz ------------------
$skillA = Join-Path $repo "skills/bootstrap-ai-project"
foreach ($conAtributos in @($true, $false)) {
  $nombre = if ($conAtributos) { "pub" } else { "pub-control" }
  $r = New-TestWorkspace $script:runRoot $nombre
  $dest = Join-Path $r "skills/bootstrap-ai-project"
  [IO.Directory]::CreateDirectory((Split-Path $dest -Parent)) | Out-Null
  Copy-Item -LiteralPath $skillA -Destination $dest -Recurse
  if (-not $conAtributos) { Remove-Item -LiteralPath (Join-Path $dest "assets/scaffold/.gitattributes") -Force -ErrorAction SilentlyContinue }
  Assert (-not (Test-Path -LiteralPath (Join-Path $r ".gitattributes"))) "B/${nombre}: la raíz del repo simulado no tiene .gitattributes"
  $m = Measure-ClonedSh $r $nombre
  Assert ($m.code -eq 0 -and $m.total -ge 2) "B/${nombre}: commit y clon sin error, con .sh en el clon (exit $($m.code), $($m.total) .sh)"
  if ($conAtributos) {
    Assert ($m.conCr -eq 0) "B: con el .gitattributes anidado del scaffold, ningún .sh del clon tiene CR ($($m.conCr) de $($m.total))"
  } else {
    Assert ($m.conCr -gt 0) "B/control: sin .gitattributes el clon SÍ escribe CR ($($m.conCr) de $($m.total)); si no, el caso B no mide nada"
  }
}

Remove-TestRunRoot $script:runRoot
Write-Host ""
$esperadas = $skills.Count + 2 * 3 + 2 * 3
if ($script:checks -ne $esperadas) {
  Write-Host "FAIL: corrieron $($script:checks) aserciones y se esperaban $esperadas"
  $script:failures++
}
Write-Host "$($script:checks) aserciones, $($script:failures) fallidas"
exit ([int]($script:failures -gt 0))
