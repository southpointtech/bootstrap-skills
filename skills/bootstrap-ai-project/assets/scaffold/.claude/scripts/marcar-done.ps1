# .claude/scripts/marcar-done.ps1 — pone `Status: done` en los issues que cierra un slice.
#
# Lo corre `/review-loop` al cerrar el slice, sobre el commit que lleva el `Slice-Close:`. El trailer
# cita los issues por ruta (`.scratch/<feature>/issues/<archivo>.md`): con texto libre, "issue 08" es
# ambiguo en cuanto el repo tiene dos features.
#
#   pwsh -File .claude/scripts/marcar-done.ps1 -RepoDir <repo> [-Sha <commit>]
#
# Salida: un JSON por stdout con `marcados`, `yaDone`, `noEncontrados` y `sinStatus` (rutas relativas al repo).
# Exit 0 aunque no marque nada; exit 1 sólo si git falla.
param(
  [Parameter(Mandatory)][string]$RepoDir,
  [string]$Sha = "HEAD"
)
$ErrorActionPreference = "Stop"
# pwsh decodifica la salida de git con [Console]::OutputEncoding (ibm850 en estas máquinas).
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)

$msg = git -C $RepoDir log -1 --format=%B $Sha
if ($LASTEXITCODE -ne 0) { Write-Error "git log falló en $RepoDir para $Sha"; exit 1 }
$msg = $msg -join "`n"

$rep = [ordered]@{ marcados = @(); yaDone = @(); noEncontrados = @(); sinStatus = @() }
# La línea `Slice-Close:` se detecta como en hub-recolectar.ps1: en el cuerpo entero, no en los
# trailers de git (que sólo ven el último párrafo).
$valores = @([regex]::Matches($msg, '(?im)^[ \t]*Slice-Close:[ \t]*(\S.*?)[ \t\r]*$') | ForEach-Object { $_.Groups[1].Value })
# Sólo `.scratch/<feature>/issues/<archivo>.md`, exactamente esos niveles: ni el PRD ni una
# subcarpeta, y ningún segmento `.`/`..` que saque la ruta del repo. La ruta arranca el token (o sigue
# a una comilla, backtick o paréntesis): `x.scratch/...` no es una cita.
$cita = [regex]'(?<![^\s`''"(\[,])\.scratch/([^/\s`''",;)\]]+)/issues/([^/\s`''",;)\]]+\.md)'
$vistos = [Collections.Generic.HashSet[string]]::new()
foreach ($v in $valores) {
  foreach ($m in $cita.Matches($v)) {
    if ($m.Groups[1].Value -in @('.', '..') -or $m.Groups[2].Value -in @('.', '..')) { continue }
    $rel = $m.Value
    if (-not $vistos.Add($rel)) { continue }
    $p = Join-Path $RepoDir $rel
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { $rep.noEncontrados += $rel; continue }
    # Bytes y no ReadAllText/WriteAllText: éstos se comen el BOM, y el resto del archivo tiene que
    # quedar igual byte a byte (el EOL lo conserva la regex, que no toca el `\r`).
    $bytes = [IO.File]::ReadAllBytes($p)
    $bom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    $utf8 = [Text.UTF8Encoding]::new($bom)
    $txt = $utf8.GetString($bytes, $(if ($bom) { 3 } else { 0 }), $bytes.Length - $(if ($bom) { 3 } else { 0 }))
    $linea = [regex]::Match($txt, '(?m)^Status:[^\r\n]*')
    if (-not $linea.Success) { $rep.sinStatus += $rel; continue }
    if ($linea.Value -match '^Status:[ \t]*done[ \t]*$') { $rep.yaDone += $rel; continue }
    $txt = $txt.Substring(0, $linea.Index) + 'Status: done' + $txt.Substring($linea.Index + $linea.Length)
    [IO.File]::WriteAllBytes($p, $utf8.GetPreamble() + $utf8.GetBytes($txt))
    $rep.marcados += $rel
  }
}
$rep | ConvertTo-Json -Compress
