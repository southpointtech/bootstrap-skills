# .claude/scripts/marcar-done.ps1 — pone `Status: done` en los issues que cierra un slice.
#
# Lo corre `/review-loop` al cerrar el slice, sobre el commit que lleva el `Slice-Close:`. El trailer
# cita los issues por ruta (`.scratch/<feature>/issues/<archivo>.md`): con texto libre, "issue 08" es
# ambiguo en cuanto el repo tiene dos features.
#
#   pwsh -File .claude/scripts/marcar-done.ps1 -RepoDir <repo> [-Sha <commit>]
#
# Salida: un JSON por stdout —en bytes UTF-8, no en la codificación de la consola— con
# `marcados`, `yaDone`, `noEncontrados`, `sinStatus` y `noUtf8` (rutas relativas al repo), más
# `lineasSliceClose` (cuántas líneas `Slice-Close:` trae el commit) y `sinRuta`
# (los valores de esas líneas que no citan ninguna ruta): así quien lo corre puede decir POR QUÉ no se
# marcó nada — un commit sin cierre no es lo mismo que un cierre escrito en texto libre.
# Exit 0 aunque no marque nada; exit 1 si git falla.
param(
  [Parameter(Mandatory)][string]$RepoDir,
  [string]$Sha = "HEAD"
)
$ErrorActionPreference = "Stop"
# git emite UTF-8 y pwsh decodifica la salida de un hijo con [Console]::OutputEncoding, que en estas
# máquinas es ibm850. Fijar esa propiedad sería lo obvio, pero NO es del proceso sino de la CONSOLA:
# el valor se lo queda cualquier proceso que arranque después ahí, y bajo `tests/run-all.ps1` —suites
# en paralelo en una consola— eso son rojos cruzados (issue 15, medido el 2026-09-20; `chcp.com` ni
# siquiera lo informa). Así que la decodificación se declara por llamada, sin tocarle nada a nadie.
function Invoke-GitUtf8([string[]]$Argumentos) {
  $psi = [Diagnostics.ProcessStartInfo]::new('git')
  foreach ($a in $Argumentos) { $psi.ArgumentList.Add($a) }
  $psi.UseShellExecute = $false
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.StandardOutputEncoding = [Text.UTF8Encoding]::new($false)
  $psi.StandardErrorEncoding = [Text.UTF8Encoding]::new($false)
  $p = [Diagnostics.Process]::Start($psi)
  try {
    # En paralelo: leer los dos canales en serie puede trabar al hijo si se le llena el otro buffer.
    $err = $p.StandardError.ReadToEndAsync()
    $salida = $p.StandardOutput.ReadToEnd()
    $p.WaitForExit()
    [pscustomobject]@{ stdout = $salida; stderr = $err.Result.Trim(); exit = $p.ExitCode }
  } finally { $p.Dispose() }
}

# El reporte sale por stdout en bytes UTF-8, por lo mismo: `ConvertTo-Json` por la tubería se
# codificaría con [Console]::OutputEncoding, y dejarlo en UTF-8 exige cambiársela a toda la consola.
# Quien lo lee decodifica UTF-8, que es lo que este script promete escribir.
function Write-Stdout([string]$texto) {
  $s = [Console]::OpenStandardOutput()
  $b = [Text.UTF8Encoding]::new($false).GetBytes($texto + "`n")
  $s.Write($b, 0, $b.Length)
  $s.Flush()
}

$g = Invoke-GitUtf8 @('-C', $RepoDir, 'log', '-1', '--format=%B', $Sha)
# El motivo que da git va en el mensaje: con `RedirectStandardError` su `fatal: bad object …` ya no
# llega solo a la consola del operador, y sin interpolarlo se pierde lo único que distingue un SHA
# inexistente de un repo corrupto. Colapsado en una línea, igual que en `hub-recolectar.ps1`.
# `[Console]::Error` y no `Write-Error`: PowerShell renderiza el ErrorRecord con el ancho del host y
# corta el texto en el límite de palabra, con una canaleta `|` en la línea de continuación. MEDIDO:
# el mensaje se parte —y un lector que busque "bad object" no lo encuentra— cuando el largo del
# RepoDir cae en [ancho-89, ancho-83]; a 164 columnas la suite se ponía roja con el código correcto.
# Mismo criterio que `Write-Stdout`: el diagnóstico no depende de cómo esté configurado el host.
if ($g.exit -ne 0) {
  [Console]::Error.WriteLine("git log falló en $RepoDir para $Sha`: $($g.stderr -replace '\s+', ' ')")
  exit 1
}
$msg = $g.stdout

$rep = [ordered]@{ marcados = @(); yaDone = @(); noEncontrados = @(); sinStatus = @(); noUtf8 = @(); lineasSliceClose = 0; sinRuta = @() }
# La línea `Slice-Close:` se detecta como en hub-recolectar.ps1: en el cuerpo entero, no en los
# trailers de git (que sólo ven el último párrafo).
$valores = @([regex]::Matches($msg, '(?im)^[ \t]*Slice-Close:[ \t]*(\S.*?)[ \t\r]*$') | ForEach-Object { $_.Groups[1].Value })
# Sólo `.scratch/<feature>/issues/<archivo>.md`, exactamente esos niveles: ni el PRD ni una
# subcarpeta, y ningún segmento `.`/`..` que saque la ruta del repo. La ruta arranca el token (o sigue
# a una comilla, backtick o paréntesis): `x.scratch/...` no es una cita.
$cita = [regex]'(?<![^\s`''"(\[,])\.scratch/([^/\s`''",;)\]]+)/issues/([^/\s`''",;)\]]+\.md)'
$vistos = [Collections.Generic.HashSet[string]]::new()
$rep.lineasSliceClose = $valores.Count
foreach ($v in $valores) {
  $citas = @($cita.Matches($v) | Where-Object { $_.Groups[1].Value -notin @('.', '..') })
  if ($citas.Count -eq 0) { $rep.sinRuta += $v; continue }
  foreach ($m in $citas) {
    $rel = $m.Value
    if (-not $vistos.Add($rel)) { continue }
    $p = Join-Path $RepoDir $rel
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { $rep.noEncontrados += $rel; continue }
    # Bytes y no ReadAllText/WriteAllText: éstos se comen el BOM, y el resto del archivo tiene que
    # quedar igual byte a byte (el EOL lo conserva la regex, que no toca el `\r`).
    $bytes = [IO.File]::ReadAllBytes($p)
    $bom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    # Decodificador estricto: el tolerante cambia cada byte inválido (un issue guardado en cp1252) por
    # U+FFFD, y reescribirlo corrompería un archivo gitignoreado que no tiene copia en git.
    $utf8 = [Text.UTF8Encoding]::new($bom, $true)
    try { $txt = $utf8.GetString($bytes, $(if ($bom) { 3 } else { 0 }), $bytes.Length - $(if ($bom) { 3 } else { 0 })) }
    catch [Text.DecoderFallbackException] { $rep.noUtf8 += $rel; continue }
    $linea = [regex]::Match($txt, '(?m)^Status:[^\r\n]*')
    if (-not $linea.Success) { $rep.sinStatus += $rel; continue }
    if ($linea.Value -match '^Status:[ \t]*done[ \t]*$') { $rep.yaDone += $rel; continue }
    $txt = $txt.Substring(0, $linea.Index) + 'Status: done' + $txt.Substring($linea.Index + $linea.Length)
    [IO.File]::WriteAllBytes($p, $utf8.GetPreamble() + $utf8.GetBytes($txt))
    $rep.marcados += $rel
  }
}
Write-Stdout ($rep | ConvertTo-Json -Compress)
