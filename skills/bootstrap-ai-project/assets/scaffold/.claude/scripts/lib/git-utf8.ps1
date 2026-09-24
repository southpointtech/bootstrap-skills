# .claude/scripts/lib/git-utf8.ps1 — leer git y stdin, y escribir stdout y stderr, en UTF-8 sin tocar la consola.
#
# git escribe UTF-8 y pwsh decodifica la salida de un hijo con [Console]::OutputEncoding, que en un
# pwsh con stdout redirigido (un hook, un script que otro lanza) es la code page OEM de la máquina.
# Fijar esa propiedad a UTF-8 sería lo obvio, pero NO es del proceso sino de la CONSOLA: el valor se
# lo queda cualquier proceso que arranque después ahí, aunque el que la fijó ya haya muerto, y
# `chcp.com` ni siquiera lo informa (issue 16, medido el 2026-09-20). Bajo `tests/run-all.ps1`, con
# suites en paralelo en una consola, eso eran rojos cruzados; en la terminal de quien corre Claude
# Code, un cambio de code page que nadie pidió. Así que la decodificación se declara por llamada.
#
# Uso: dot-sourcear al principio del script, antes de la primera llamada a git.
#
#     . (Join-Path $PSScriptRoot "lib\git-utf8.ps1")

# Tapa al git.exe: una función le gana a un comando externo del mismo nombre, así que TODA llamada
# `git ...` del script que dot-sourcea esto pasa por acá, sin que haya que acordarse de cambiar
# ninguna. Imita lo que el script espera del exe:
# - un renglón por línea de stdout, sin la vacía final (nada si no hubo salida);
# - `$LASTEXITCODE` con el exit de git;
# - el cwd es la ubicación de PowerShell, no la del proceso: `Set-Location` no mueve la segunda, y
#   el hook resuelve su repo con `git rev-parse` sin `-C` después de un `Set-Location`;
# - un array pasado como argumento se aplana y un `$null` se omite, como con un exe.
# Lo que NO puede imitar: un `--` pelado. PowerShell lo consume como fin de parámetros antes de llamar
# a una función, así que nunca llega a `$args`; al exe sí le llegaba. Va entre comillas: `'--'`.
# El stderr de git se descarta: todas las llamadas que pasan por acá lo tiraban con `2>$null` o
# usaban `--quiet`. Una llamada que necesite mostrarlo tiene que ir al ejecutable, resuelto con
# `Get-Command git -CommandType Application` (como el `worktree add` de abrir-carril): `git.exe` por
# su nombre no existe fuera de Windows.
function git {
  $lista = @()
  foreach ($a in $args) {
    if ($null -eq $a) { continue }
    if ($a -is [Collections.IEnumerable] -and $a -isnot [string]) {
      foreach ($x in $a) { if ($null -ne $x) { $lista += [string]$x } }
    } else { $lista += [string]$a }
  }
  $psi = New-Object Diagnostics.ProcessStartInfo 'git'
  # `.Arguments` y no `.ArgumentList`: ésa no existe en Windows PowerShell 5.1 (.NET Framework), y
  # estos scripts corren en los dos shells.
  $psi.Arguments = (@($lista | ForEach-Object { ConvertTo-ArgumentoWindows $_ }) -join ' ')
  $psi.WorkingDirectory = (Get-Location -PSProvider FileSystem).ProviderPath
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
    $null = $err.Result
    $global:LASTEXITCODE = $p.ExitCode
  } finally { $p.Dispose() }
  if ($salida) { $salida -replace '\r?\n$', '' -split '\r?\n' }
}

# Un argumento entrecomillado con las reglas con que un programa de Windows parte su línea de
# comandos: comillas si está vacío o trae espacio o comilla; una comilla adentro va escapada, y las
# barras que la preceden, o que cierran el argumento, se duplican.
function ConvertTo-ArgumentoWindows([string]$a) {
  if ($a -ne '' -and $a -notmatch '[\s"]') { return $a }
  '"' + (($a -replace '(\\*)"', '$1$1\"') -replace '(\\+)$', '$1$1') + '"'
}

# El stdin entero, decodificado como UTF-8 desde los bytes: `[Console]::In` lo decodificaría con
# [Console]::InputEncoding, que también es de la consola.
function Read-StdinUtf8 {
  $s = [Console]::OpenStandardInput()
  $m = [IO.MemoryStream]::new()
  try { $s.CopyTo($m); [Text.UTF8Encoding]::new($false).GetString($m.ToArray()) } finally { $m.Dispose() }
}

# Un texto a stdout, más un salto. Redirigido va en bytes UTF-8: por la tubería se codificaría con
# [Console]::OutputEncoding, y quien lo lee (Claude Code, con el JSON de un hook) decodifica UTF-8.
# A una consola de verdad, en cambio, va por `[Console]::Out`: la consola decodifica los bytes crudos
# con SU code page, y en cp850 la ñ se veía `├▒` (medido leyendo el buffer de pantalla).
function Write-Stdout([string]$texto) {
  if (-not [Console]::IsOutputRedirected) { [Console]::Out.WriteLine($texto); return }
  $s = [Console]::OpenStandardOutput()
  $b = [Text.UTF8Encoding]::new($false).GetBytes($texto + "`n")
  $s.Write($b, 0, $b.Length)
  $s.Flush()
}

# Lo mismo sobre stderr: `[Console]::Error` también codifica con la code page de la consola.
function Write-Stderr([string]$texto) {
  if (-not [Console]::IsErrorRedirected) { [Console]::Error.WriteLine($texto); return }
  $s = [Console]::OpenStandardError()
  $b = [Text.UTF8Encoding]::new($false).GetBytes($texto + "`n")
  $s.Write($b, 0, $b.Length)
  $s.Flush()
}
