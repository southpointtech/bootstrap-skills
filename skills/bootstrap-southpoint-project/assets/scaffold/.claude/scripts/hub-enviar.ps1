# .claude/scripts/hub-enviar.ps1 — transporte de hub-sync (ver docs/adr/0012 en Bootstrap Skills).
#
# Corre el recolector sobre un repo y empuja sus lotes pendientes a `inbox/<dev>/<repo>/` del repo
# PROJECT MANAGEMENT, que es el único canal entre la PC del dev y la del PM.
#
#   pwsh -File .claude/scripts/hub-enviar.ps1 -RepoDir <repo> -Dev <nombre> [-StateDir <dir>]
#        [-PmRemote <url>] [-PmClone <dir>] [-Now <iso>]
#
# El clon de PROJECT MANAGEMENT es privado del transporte (`<StateDir>/pm-repo`): nadie trabaja en él,
# así que se alinea con el remoto en cada corrida sin miedo a pisar nada.
param(
  [Parameter(Mandatory)][string]$RepoDir,
  [Parameter(Mandatory)][string]$Dev,
  [string]$StateDir = (Join-Path $env:LOCALAPPDATA "hub-sync"),
  [string]$PmRemote = "https://github.com/southpointtech/project-management.git",
  [string]$PmClone = "",
  [string]$Cuenta = "southpointtech",
  [string]$Now = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
)
$ErrorActionPreference = "Stop"
$utf8 = [Text.UTF8Encoding]::new($false)
if (-not $PmClone) { $PmClone = Join-Path $StateDir "pm-repo" }

# Un hijo con stdout y stderr decodificados como UTF-8 por llamada, sin tocar [Console]::OutputEncoding
# (es de la consola, no del proceso: ver el issue 15 y `Invoke-GitUtf8` en hub-recolectar.ps1).
function Invoke-Utf8([string]$exe, [string[]]$Argumentos, [hashtable]$Entorno = @{}) {
  $psi = [Diagnostics.ProcessStartInfo]::new($exe)
  foreach ($a in $Argumentos) { $psi.ArgumentList.Add($a) }
  foreach ($k in $Entorno.Keys) { $psi.Environment[$k] = $Entorno[$k] }
  $psi.UseShellExecute = $false
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.StandardOutputEncoding = $utf8
  $psi.StandardErrorEncoding = $utf8
  $p = [Diagnostics.Process]::Start($psi)
  try {
    $err = $p.StandardError.ReadToEndAsync()
    $salida = $p.StandardOutput.ReadToEnd()
    $p.WaitForExit()
    [pscustomobject]@{ stdout = $salida.Trim(); stderr = $err.Result.Trim(); exit = $p.ExitCode }
  } finally { $p.Dispose() }
}
# Todo git contra PROJECT MANAGEMENT lleva este entorno (ver la cuenta, más abajo).
$script:gitEnv = @{}
function Git([string[]]$Argumentos) {
  $r = Invoke-Utf8 'git' $Argumentos $script:gitEnv
  if ($r.exit -ne 0) { throw "git $($Argumentos -join ' '): $($r.stderr)" }
  $r.stdout
}

$recol = Join-Path $PSScriptRoot "hub-recolectar.ps1"
$r = Invoke-Utf8 'pwsh' @('-NoProfile', '-File', $recol, '-RepoDir', $RepoDir, '-Dev', $Dev, '-StateDir', $StateDir, '-Now', $Now)
# Sin lote: el repo no está en hub-sync o el dev no figura en su declaración. No hay nada que enviar.
if (-not $r.stdout) { exit 0 }
$lotes = Split-Path $r.stdout -Parent
$repoName = ([IO.File]::ReadAllText($r.stdout) | ConvertFrom-Json -DateKind String).repo

# Una línea por corrida en `<StateDir>/hub-sync.log`: es lo que el dev mira cuando el tablero del PM
# le marca una corrida en rojo.
function Write-Log([string]$resultado) {
  [IO.Directory]::CreateDirectory($StateDir) | Out-Null
  [IO.File]::AppendAllText((Join-Path $StateDir "hub-sync.log"), "$Now`t$Dev`t$repoName`t$resultado`n", $utf8)
}

# La cuenta va explícita, sin depender de la que esté activa en gh: el token de `$Cuenta` se pide a gh
# y viaja como header de autorización por variables de entorno de git (GIT_CONFIG_*), no por la línea
# de comandos, donde lo vería cualquiera que liste procesos. Sólo contra github.com: un remoto local
# (los tests) no lo necesita.
if ($PmRemote -match '^https://github\.com/') {
  $tk = Invoke-Utf8 'gh' @('auth', 'token', '-h', 'github.com', '-u', $Cuenta)
  if ($tk.exit -ne 0 -or -not $tk.stdout) {
    Write-Log "falló: gh no tiene un token de la cuenta $Cuenta ($($tk.stderr -replace '\s+', ' '))"
    [Console]::Error.WriteLine("hub-enviar: gh no tiene un token de la cuenta $Cuenta. Corré: gh auth login")
    exit 1
  }
  $basic = [Convert]::ToBase64String($utf8.GetBytes("x-access-token:$($tk.stdout)"))
  $script:gitEnv = @{
    GIT_CONFIG_COUNT   = '1'
    GIT_CONFIG_KEY_0   = 'http.https://github.com/.extraheader'
    GIT_CONFIG_VALUE_0 = "AUTHORIZATION: basic $basic"
  }
}
# El commit y el rebase no dependen de la identidad git de la PC.
$identidad = @('-c', "user.name=hub-sync $Dev", '-c', 'user.email=hub-sync@noreply', '-c', 'commit.gpgsign=false')

# Se envían TODOS los lotes de `lotes/`, no sólo el de esta corrida: los que un push fallido dejó
# ahí salen en la siguiente. Recién con el push confirmado pasan a `enviados/`.
$pendientes = @(Get-ChildItem -LiteralPath $lotes -Filter *.json -File | Sort-Object Name)
try {
  if (-not (Test-Path -LiteralPath (Join-Path $PmClone ".git"))) { Git @('clone', '-q', $PmRemote, $PmClone) | Out-Null }
  Git @('-C', $PmClone, 'fetch', '-q', 'origin') | Out-Null
  Git @('-C', $PmClone, 'checkout', '-q', '-B', 'main', 'origin/main') | Out-Null
  foreach ($f in $pendientes) {
    $lote = [IO.File]::ReadAllText($f.FullName) | ConvertFrom-Json -DateKind String
    $destDir = Join-Path $PmClone "inbox/$($lote.dev)/$($lote.repo)"
    [IO.Directory]::CreateDirectory($destDir) | Out-Null
    Copy-Item -LiteralPath $f.FullName -Destination (Join-Path $destDir $f.Name) -Force
  }
  Git @('-C', $PmClone, 'add', '-A', 'inbox') | Out-Null
  Git (@('-C', $PmClone) + $identidad + @('commit', '-q', '-m', "hub-sync: lotes de $Dev")) | Out-Null
  # Los tres devs pushean al mismo `main`: si otro entró entre el fetch y el push, el remoto rechaza.
  # Cada dev escribe sólo bajo su `inbox/<dev>/`, así que el rebase sobre lo nuevo nunca conflictúa.
  for ($intento = 1; ; $intento++) {
    $p = Invoke-Utf8 'git' @('-C', $PmClone, 'push', '-q', 'origin', 'HEAD:main') $script:gitEnv
    if ($p.exit -eq 0) { break }
    if ($intento -ge 3) { throw "git push (intento $intento): $($p.stderr)" }
    Git @('-C', $PmClone, 'fetch', '-q', 'origin') | Out-Null
    Git (@('-C', $PmClone) + $identidad + @('rebase', '-q', 'origin/main')) | Out-Null
  }
} catch {
  Write-Log "falló: $($_.Exception.Message -replace '\s+', ' ')"
  [Console]::Error.WriteLine("hub-enviar: $($_.Exception.Message)")
  exit 1
}
$enviados = Join-Path (Split-Path $lotes -Parent) "enviados"
[IO.Directory]::CreateDirectory($enviados) | Out-Null
foreach ($f in $pendientes) { Move-Item -LiteralPath $f.FullName -Destination (Join-Path $enviados $f.Name) -Force }
Write-Log "ok ($($pendientes.Count) lotes)"
