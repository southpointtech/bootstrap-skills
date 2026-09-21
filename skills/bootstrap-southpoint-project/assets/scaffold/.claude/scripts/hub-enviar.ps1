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
$repoName = Split-Path $RepoDir.TrimEnd('\', '/') -Leaf

# Una línea por corrida en `<StateDir>/hub-sync.log`: es lo que el dev mira cuando el tablero del PM
# le marca una corrida en rojo.
function Write-Log([string]$resultado) {
  [IO.Directory]::CreateDirectory($StateDir) | Out-Null
  [IO.File]::AppendAllText((Join-Path $StateDir "hub-sync.log"), "$Now`t$Dev`t$repoName`t$resultado`n", $utf8)
}
function Fallar([string]$motivo) {
  Write-Log "falló: $($motivo -replace '\s+', ' ')"
  [Console]::Error.WriteLine("hub-enviar: $motivo")
  exit 1
}

# Sin lote y en exit 0: el repo no está en hub-sync o el dev no figura en su declaración, y no hay
# nada que enviar. Sin lote y en exit != 0, el recolector murió antes de escribirlo: eso es una falla,
# no un repo fuera de hub-sync. Los lotes que haya pendientes salen en la próxima corrida que ande.
if (-not $r.stdout) {
  if ($r.exit -eq 0) { exit 0 }
  Fallar "el recolector salió con $($r.exit) sin lote: $($r.stderr)"
}
$lotes = Split-Path $r.stdout -Parent
# Un recolector que sale en 1 CON lote dejó un lote `falló`: viaja igual (es lo que el tablero pone en
# rojo), pero la corrida no es un `ok`.
$recoleccionFallida = $r.exit -ne 0

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

# El primer nombre libre para `$nombre` en `$dir`: el mismo, o con sufijo `-2`, `-3`... Un lote no se
# pisa nunca, por la misma razón que el recolector lo crea con CreateNew: dos corridas con el mismo
# momento dan el mismo nombre, y pisar un `ok` con un `sin cambios` pierde sus propuestas. Si el que ya
# está tiene los mismos bytes, es este mismo lote ya enviado, y se devuelve $null.
function Get-NombreLibre([string]$dir, [IO.FileInfo]$f) {
  $bytes = [IO.File]::ReadAllBytes($f.FullName)
  for ($i = 1; ; $i++) {
    $n = if ($i -eq 1) { $f.Name } else { "$($f.BaseName)-$i$($f.Extension)" }
    $p = Join-Path $dir $n
    if (-not (Test-Path -LiteralPath $p)) { return $n }
    if ([Linq.Enumerable]::SequenceEqual([byte[]][IO.File]::ReadAllBytes($p), [byte[]]$bytes)) { return $null }
  }
}

# Un lote que no se puede leer (cortado por un apagón, vacío, sin `dev` o `repo`) va a `invalidos/`:
# si se quedara en la cola, cada corrida siguiente fallaría en él y no saldría nada más.
$pendientes = @()
$invalidos = @()
foreach ($f in @(Get-ChildItem -LiteralPath $lotes -Filter *.json -File | Sort-Object Name)) {
  $lote = try { [IO.File]::ReadAllText($f.FullName) | ConvertFrom-Json -DateKind String } catch { $null }
  if ($lote -and $lote.dev -and $lote.repo) { $pendientes += [pscustomobject]@{ archivo = $f; lote = $lote }; continue }
  $dirInv = Join-Path (Split-Path $lotes -Parent) "invalidos"
  [IO.Directory]::CreateDirectory($dirInv) | Out-Null
  $n = Get-NombreLibre $dirInv $f
  if ($n) { Move-Item -LiteralPath $f.FullName -Destination (Join-Path $dirInv $n) } else { Remove-Item -LiteralPath $f.FullName }
  $invalidos += $f.Name
}
if ($pendientes.Count) { $repoName = $pendientes[-1].lote.repo }
$nota = if ($invalidos.Count) { "; a invalidos/: $($invalidos -join ', ')" } else { "" }

# Se envían TODOS los lotes de `lotes/`, no sólo el de esta corrida: los que un push fallido dejó
# ahí salen en la siguiente. Recién con el push confirmado pasan a `enviados/`.
try {
  if (-not (Test-Path -LiteralPath (Join-Path $PmClone ".git"))) { Git @('clone', '-q', $PmRemote, $PmClone) | Out-Null }
  Git @('-C', $PmClone, 'fetch', '-q', 'origin') | Out-Null
  # Una corrida anterior pudo morir a mitad de un rebase: sin abortarlo, el checkout de abajo falla en
  # esta y en todas las siguientes. Si no había rebase, el abort falla y no importa.
  Invoke-Utf8 'git' @('-C', $PmClone, 'rebase', '--abort') | Out-Null
  Git @('-C', $PmClone, 'checkout', '-q', '-f', '-B', 'main', 'origin/main') | Out-Null
  Git @('-C', $PmClone, 'clean', '-fdq', '--', 'inbox') | Out-Null
  foreach ($p in $pendientes) {
    $destDir = Join-Path $PmClone "inbox/$($p.lote.dev)/$($p.lote.repo)"
    [IO.Directory]::CreateDirectory($destDir) | Out-Null
    $n = Get-NombreLibre $destDir $p.archivo
    if ($n) { Copy-Item -LiteralPath $p.archivo.FullName -Destination (Join-Path $destDir $n) }
  }
  Git @('-C', $PmClone, 'add', '-A', 'inbox') | Out-Null
  # Sin nada nuevo (todo lo pendiente ya estaba en el remoto) no hay commit ni push.
  $cambios = Invoke-Utf8 'git' @('-C', $PmClone, 'diff', '--cached', '--quiet')
  if ($cambios.exit -ne 0) {
    Git (@('-C', $PmClone) + $identidad + @('commit', '-q', '-m', "hub-sync: lotes de $Dev")) | Out-Null
    # Los tres devs pushean al mismo `main`: si otro entró entre el fetch y el push, el remoto rechaza.
    # Cada dev escribe sólo bajo su `inbox/<dev>/`, así que el rebase sobre lo nuevo no conflictúa
    # mientras un mismo `<dev>` no corra en dos PCs a la vez.
    for ($intento = 1; ; $intento++) {
      $push = Invoke-Utf8 'git' @('-C', $PmClone, 'push', '-q', 'origin', 'HEAD:main') $script:gitEnv
      if ($push.exit -eq 0) { break }
      if ($intento -ge 3) { throw "git push (intento $intento): $($push.stderr)" }
      Git @('-C', $PmClone, 'fetch', '-q', 'origin') | Out-Null
      Git (@('-C', $PmClone) + $identidad + @('rebase', '-q', 'origin/main')) | Out-Null
    }
  }
} catch {
  Fallar "$($_.Exception.Message)$nota"
}
$enviados = Join-Path (Split-Path $lotes -Parent) "enviados"
[IO.Directory]::CreateDirectory($enviados) | Out-Null
foreach ($p in $pendientes) {
  $n = Get-NombreLibre $enviados $p.archivo
  if ($n) { Move-Item -LiteralPath $p.archivo.FullName -Destination (Join-Path $enviados $n) } else { Remove-Item -LiteralPath $p.archivo.FullName }
}
if ($recoleccionFallida) { Fallar "la recolección falló; su lote se envió con el motivo ($($pendientes.Count) lotes)$nota" }
Write-Log "ok ($($pendientes.Count) lotes)$nota"
