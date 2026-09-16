# tests/run-all.ps1 — corre todas las suites (*.tests.ps1) en paralelo y agrega el resultado.
# Correr: pwsh -NoProfile -File tests/run-all.ps1 [-ThrottleLimit 4]
#
# Rojo (exit 1) si cualquier suite sale con exit != 0, si no encuentra ninguna suite, o si al
# terminar el árbol de trabajo de -RepoRoot no quedó igual que al arrancar. De cada suite roja
# imprime la salida completa (stdout y stderr) entre dos marcas con su nombre.
#
# El árbol se COMPARA, no se exige limpio: un repo con residuo ajeno (p. ej. lo que siembra Codex)
# sigue pudiendo correr la suite. La comparación mira `git status` y además el hash de cada archivo
# que figura ahí, porque un archivo que ya estaba sucio y un test vuelve a tocar no cambia su línea
# de status. Lo que git ignora (.gitignore) no se mira.
#
# -Path y -RepoRoot existen para que tests/run-all.tests.ps1 lo pruebe con suites de juguete.
param(
  [string]$Path = $PSScriptRoot,
  [string]$RepoRoot = (Split-Path $PSScriptRoot -Parent),
  # 4 por prudencia, no por una medición de estas suites: el techo de 4-6 que cita el issue 02 se
  # midió con olas de agentes de review. Con estas suites, el 2026-09-16, una corrida con 6 carriles
  # tardó 219 s y una con 4, 296 s (una corrida de cada una).
  [ValidateRange(1, 64)][int]$ThrottleLimit = 4
)
$ErrorActionPreference = "Stop"

# La salida cruda de `git status -z`, decodificada como UTF-8 por un Process propio. Con `& git`
# pwsh la decodifica con [Console]::OutputEncoding, que en esta máquina es ibm850 (medido el
# 2026-09-16): una ruta con acento llegaba deformada, Test-Path daba falso, el hash quedaba "-"
# antes y después, y re-escribir ese archivo pasaba en verde (caso L del test).
function Get-GitStatusZ([string]$repo) {
  $psi = [Diagnostics.ProcessStartInfo]::new('git')
  # -z: rutas sin comillas ni escapes, aunque tengan espacios.
  foreach ($a in '-C', $repo, 'status', '--porcelain=v1', '--untracked-files=all', '-z') {
    $psi.ArgumentList.Add($a)
  }
  $psi.UseShellExecute = $false
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.StandardOutputEncoding = [Text.UTF8Encoding]::new($false)
  $p = [Diagnostics.Process]::Start($psi)
  # stderr en paralelo: leer los dos canales en serie puede trabar al hijo si llena el otro buffer.
  $err = $p.StandardError.ReadToEndAsync()
  $salida = $p.StandardOutput.ReadToEnd()
  $p.WaitForExit()
  if ($p.ExitCode -ne 0) { throw "git status falló en $repo : $($err.Result.Trim())" }
  $salida
}

# Mapa "XY ruta" -> hash del archivo ("-" si no existe, p. ej. un borrado).
function Get-EstadoDelArbol([string]$repo) {
  $estado = @{}
  $partes = @(((Get-GitStatusZ $repo) -split "`0") | Where-Object { $_ })
  for ($i = 0; $i -lt $partes.Count; $i++) {
    $xy = $partes[$i].Substring(0, 2)
    $ruta = $partes[$i].Substring(3)
    # En un rename/copy el token siguiente es la ruta de origen, no una entrada propia.
    if ($xy -match '[RC]') { $i++ }
    $completa = Join-Path $repo $ruta
    $hash = if (Test-Path -LiteralPath $completa -PathType Leaf) {
      (Get-FileHash -LiteralPath $completa -Algorithm SHA256).Hash
    } else { '-' }
    $estado["$xy $ruta"] = $hash
  }
  $estado
}

$suites = @(Get-ChildItem -LiteralPath $Path -Filter '*.tests.ps1' -File | Sort-Object Name)
if ($suites.Count -eq 0) {
  Write-Host "FAIL  no hay suites (*.tests.ps1) en $Path"
  exit 1
}

$antes = Get-EstadoDelArbol $RepoRoot
$reloj = [Diagnostics.Stopwatch]::StartNew()
Write-Host "Corriendo $($suites.Count) suites, de a $ThrottleLimit en paralelo..."

# Cada renglón se imprime cuando su suite termina, no al final: en una corrida de minutos se ve
# el avance.
$resultados = @($suites | ForEach-Object -ThrottleLimit $ThrottleLimit -Parallel {
  $t = [Diagnostics.Stopwatch]::StartNew()
  # "$_" y no Out-String directo: las líneas de stderr llegan como ErrorRecord, y así salen como
  # el texto que la suite escribió.
  $salida = (& pwsh -NoProfile -File $_.FullName 2>&1 | ForEach-Object { "$_" }) -join "`n"
  [pscustomobject]@{
    Nombre   = $_.Name
    Exit     = $LASTEXITCODE
    Segundos = [math]::Round($t.Elapsed.TotalSeconds, 1)
    Salida   = $salida
  }
} | ForEach-Object {
  $etiqueta = if ($_.Exit -eq 0) { 'PASS' } else { 'FAIL' }
  Write-Host ("{0}  {1}  ({2} s, exit {3})" -f $etiqueta, $_.Nombre, $_.Segundos, $_.Exit)
  $_
})

$rojas = @($resultados | Where-Object { $_.Exit -ne 0 })
foreach ($r in $rojas) {
  Write-Host ""
  Write-Host "===== $($r.Nombre) (exit $($r.Exit)) ====="
  Write-Host $r.Salida
  Write-Host "===== fin $($r.Nombre) ====="
}

$despues = Get-EstadoDelArbol $RepoRoot
$cambios = @(
  $despues.Keys | Where-Object { -not $antes.ContainsKey($_) } | ForEach-Object { "apareció:   $_" }
  $antes.Keys | Where-Object { -not $despues.ContainsKey($_) } | ForEach-Object { "desapareció: $_" }
  $antes.Keys | Where-Object { $despues.ContainsKey($_) -and $antes[$_] -ne $despues[$_] } |
    ForEach-Object { "cambió:     $_" }
) | Sort-Object
if ($cambios.Count -gt 0) {
  Write-Host ""
  Write-Host "FAIL  las suites ensuciaron el árbol de $RepoRoot :"
  $cambios | ForEach-Object { Write-Host "  $_" }
}

Write-Host ""
$total = "{0} suites, {1} rojas, {2:N0} s" -f $suites.Count, $rojas.Count, $reloj.Elapsed.TotalSeconds
if ($rojas.Count -gt 0 -or $cambios.Count -gt 0) {
  Write-Host "SUITE ROJA — $total"
  exit 1
}
Write-Host "SUITE VERDE — $total"
exit 0
