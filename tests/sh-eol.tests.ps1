# tests/sh-eol.tests.ps1 — runner sin Pester.
# Correr: pwsh -NoProfile -File tests/sh-eol.tests.ps1
#
# POR QUÉ EXISTE (review-loop del issue v2 11): con `core.autocrlf=true` y sin `.gitattributes`, un
# checkout en Windows escribe los `.sh` con CRLF. `tools/sync-skills.ps1` y `copy-scaffold.ps1` copian
# bytes crudos, así que el CRLF llega al proyecto, y un bash de Linux o WSL corta en
# `set -euo pipefail\r` ("invalid option name"). El `.gitattributes` de la raíz fija `*.sh` en LF.
#
# Para CADA `.sh` trackeado verifica las dos puntas: que el atributo resuelva a `eol=lf`, y que lo que
# un checkout escribiría (`git cat-file --filters HEAD:<f>`) no tenga ni un `\r`. Mira HEAD: un `.sh`
# nuevo sin commitear no entra hasta que se commitea.
#
# QUÉ NO CUBRE: los `.gitattributes` de los proyectos bootstrapeados. El scaffold no lleva uno.
$ErrorActionPreference = "Stop"
$repo = Split-Path $PSScriptRoot -Parent
$script:failures = 0
$script:checks   = 0

function Assert($cond, $msg) {
  $script:checks++
  if ($cond) { Write-Host "ok:   $msg" } else { Write-Host "FAIL: $msg"; $script:failures++ }
}

# git con la salida en BYTES: decodificarla como texto se come justo el `\r` que se busca, y pwsh
# decodifica la salida de git con la página de códigos de la consola.
function GitBytes([string[]]$argv) {
  $psi = [Diagnostics.ProcessStartInfo]::new("git")
  foreach ($a in (@("-C", $repo) + $argv)) { $psi.ArgumentList.Add($a) }
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.UseShellExecute = $false
  $p = [Diagnostics.Process]::Start($psi)
  $ms = [IO.MemoryStream]::new()
  $errTask = $p.StandardError.ReadToEndAsync()
  $p.StandardOutput.BaseStream.CopyTo($ms)
  $p.WaitForExit()
  [void]$errTask.Result
  return @{ code = $p.ExitCode; bytes = $ms.ToArray() }
}
function GitText([string[]]$argv) {
  $r = GitBytes $argv
  return @{ code = $r.code; text = [Text.Encoding]::UTF8.GetString($r.bytes) }
}

$ls = GitText @("ls-files", "-z", "--", "*.sh")
$shs = @($ls.text -split "`0" | Where-Object { $_ -ne "" })
# Sin un piso, un ls-files que no devuelve nada daría verde vacío.
Assert ($ls.code -eq 0 -and $shs.Count -ge 4) "git ls-files encuentra los .sh trackeados (encontró $($shs.Count), piso 4)"

foreach ($f in $shs) {
  $attr = GitText @("check-attr", "eol", "--", $f)
  Assert ($attr.code -eq 0 -and $attr.text.TrimEnd() -ceq "${f}: eol: lf") "${f}: el atributo eol resuelve a lf ($($attr.text.TrimEnd()))"
  $blob = GitBytes @("cat-file", "--filters", "HEAD:$f")
  $cr = @($blob.bytes | Where-Object { $_ -eq 13 }).Count
  Assert ($blob.code -eq 0 -and $blob.bytes.Length -gt 0 -and $cr -eq 0) "${f}: lo que un checkout escribe no tiene CR (exit $($blob.code), $($blob.bytes.Length) bytes, $cr CR)"
}

Write-Host ""
# El total depende de cuántos .sh haya: 1 + 2 por archivo.
$esperadas = 1 + 2 * $shs.Count
if ($script:checks -ne $esperadas) {
  Write-Host "FAIL: corrieron $($script:checks) aserciones y se esperaban $esperadas"
  $script:failures++
}
Write-Host "$($script:checks) aserciones, $($script:failures) fallidas"
exit ([int]($script:failures -gt 0))
