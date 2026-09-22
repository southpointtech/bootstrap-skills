# hub-sync-tarea.ps1 — la tarea por máquina de hub-sync (issue 12; ver docs/adr/0012 en Bootstrap Skills).
#
# `-Action correr` lee la lista de repos del dev en `hub-sync/repos.json` de PROJECT MANAGEMENT (la carga
# el PM desde la bandeja) y corre el `.claude/scripts/hub-enviar.ps1` de cada repo, de a uno.
#
#   pwsh -File hub-sync-tarea.ps1 -Action correr [-Dev <usuario de Windows>] [-StateDir <dir>]
#        [-PmRepo <owner/repo>] [-PmRemote <url>] [-Cuenta <cuenta de gh>] [-GhCmd <gh>] [-Now <iso>]
param(
  [Parameter(Mandatory)][ValidateSet('correr')][string]$Action,
  [string]$Dev = $env:USERNAME,
  [string]$StateDir = (Join-Path $env:LOCALAPPDATA "hub-sync"),
  [string]$PmRepo = "southpointtech/project-management",
  [string]$PmRemote = "https://github.com/southpointtech/project-management.git",
  [string]$Cuenta = "southpointtech",
  [string]$GhCmd = "gh",
  [string]$Now = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
)
$ErrorActionPreference = "Stop"
$utf8 = [Text.UTF8Encoding]::new($false)

# Un hijo con stdout y stderr decodificados como UTF-8 por llamada, sin tocar [Console]::OutputEncoding
# (es de la consola, no del proceso: ver `Invoke-Utf8` en hub-enviar.ps1, del que esto salió porque
# esta skill no viaja con el scaffold; las dos se mantienen a la par, no son idénticas).
function Invoke-Utf8([string]$exe, [string[]]$Argumentos, [hashtable]$Entorno = @{}) {
  $psi = [Diagnostics.ProcessStartInfo]::new($exe)
  foreach ($a in $Argumentos) { $psi.ArgumentList.Add($a) }
  foreach ($k in $Entorno.Keys) { $psi.Environment[$k] = $Entorno[$k] }
  $psi.UseShellExecute = $false
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.StandardOutputEncoding = $utf8
  $psi.StandardErrorEncoding = $utf8
  # Un ejecutable que no se encuentra (gh sin instalar) vuelve como una corrida fallida con su motivo, no
  # como una excepción que corta la tarea sin línea de log. `lanzado` lo separa del hijo que sí corrió
  # y salió mal. Ojo: un `pwsh` por nombre NO entra por acá aunque no esté en el PATH (medido: Windows
  # lo busca primero en el directorio del ejecutable que llama, que acá es pwsh).
  $p = try { [Diagnostics.Process]::Start($psi) } catch {
    return [pscustomobject]@{ stdout = ""; stderr = "no se pudo ejecutar ${exe}: $($_.Exception.Message)"; exit = -1; lanzado = $false }
  }
  try {
    $err = $p.StandardError.ReadToEndAsync()
    $salida = $p.StandardOutput.ReadToEnd()
    $p.WaitForExit()
    [pscustomobject]@{ stdout = $salida.Trim(); stderr = $err.Result.Trim(); exit = $p.ExitCode; lanzado = $true }
  } finally { $p.Dispose() }
}

# Las líneas de la tarea van al mismo `<StateDir>/hub-sync.log` que las del transporte, con el mismo
# formato; en la columna del repo llevan `*` cuando no son de un repo en particular.
function Write-Log([string]$repoCol, [string]$resultado) {
  [IO.Directory]::CreateDirectory($StateDir) | Out-Null
  [IO.File]::AppendAllText((Join-Path $StateDir "hub-sync.log"), "$Now`t$Dev`t$repoCol`t$resultado`n", $utf8)
}

# La lista se lee con el token de `$Cuenta`, sin depender de la cuenta activa en gh (igual que el push
# del transporte), y sin tocar el clon `pm-repo` del transporte.
function Fallar([string]$motivo) {
  Write-Log '*' "falló: $($motivo -replace '\s+', ' ')"
  [Console]::Error.WriteLine("hub-sync-tarea: $motivo")
  exit 1
}
$tk = Invoke-Utf8 $GhCmd @('auth', 'token', '-h', 'github.com', '-u', $Cuenta)
# Sin token, gh pediría la lista con la cuenta activa, y su 404 diría "no existe" en vez de "no hay cuenta".
# gh que no arranca y gh sin token piden cosas distintas: instalarlo, o `gh auth login`.
if (-not $tk.lanzado) { Fallar $tk.stderr }
if ($tk.exit -ne 0 -or -not $tk.stdout) { Fallar "gh no tiene un token de la cuenta $Cuenta ($($tk.stderr)). Corré: gh auth login" }
$lista = Invoke-Utf8 $GhCmd @('api', '-H', 'Accept: application/vnd.github.raw+json',
  "repos/$PmRepo/contents/hub-sync/repos.json") @{ GH_TOKEN = $tk.stdout }
# Una lista que no se lee es una falla, no una lista vacía: en un repo privado GitHub da el mismo 404
# si el archivo no existe que si la cuenta no lo ve, y las dos cosas dejan a la PC sin recolectar.
if ($lista.exit -ne 0) { Fallar "no se pudo leer hub-sync/repos.json de ${PmRepo}: $($lista.stderr)" }
$doc = try { $lista.stdout | ConvertFrom-Json } catch { $null }
if (-not $doc) { Fallar "hub-sync/repos.json no es JSON válido" }
if ($doc.schemaVersion -ne 1) { Fallar "hub-sync/repos.json tiene schemaVersion $($doc.schemaVersion), se esperaba 1" }
$repos = @($doc.repos.$Dev | Where-Object { $_ })
if (-not $repos.Count) {
  Write-Log '*' "sin repos en la lista"
  exit 0
}

# De a uno: todas las corridas comparten el clon `pm-repo` del transporte. Un repo que falla no frena a
# los demás; la tarea sale en 1 si falló alguno.
$fallidos = 0
foreach ($ruta in $repos) {
  $enviar = Join-Path $ruta ".claude/scripts/hub-enviar.ps1"
  if (-not (Test-Path -LiteralPath $ruta -PathType Container)) { Write-Log $ruta "falló: la ruta no existe"; $fallidos++; continue }
  if (-not (Test-Path -LiteralPath $enviar -PathType Leaf)) { Write-Log $ruta "falló: no tiene .claude/scripts/hub-enviar.ps1"; $fallidos++; continue }
  # El transporte escribe su propia línea de log cuando falla por un camino que conoce, pero puede morir
  # antes (un error no manejado, un pwsh que no arranca): por eso una salida != 0 deja además esta línea,
  # con su stderr. Si el transporte ya había escrito la suya, el repo queda con dos.
  $e = Invoke-Utf8 'pwsh' @('-NoProfile', '-File', $enviar, '-RepoDir', $ruta, '-Dev', $Dev, '-StateDir', $StateDir,
    '-PmRemote', $PmRemote, '-Cuenta', $Cuenta, '-Now', $Now)
  if ($e.exit -ne 0) {
    $motivo = if ($e.lanzado) { "el transporte salió con $($e.exit): $($e.stderr)" } else { $e.stderr }
    Write-Log $ruta "falló: $($motivo -replace '\s+', ' ')"
    $fallidos++
  }
}
if ($fallidos) { exit 1 }
