# hub-sync-tarea.ps1 — la tarea por máquina de hub-sync (issue 12; ver docs/adr/0012 en Bootstrap Skills).
#
# `-Action correr` lee la lista de repos del dev en `hub-sync/repos.json` de PROJECT MANAGEMENT (la carga
# el PM desde la bandeja) y corre el `.claude/scripts/hub-enviar.ps1` de cada repo, de a uno.
# `install` / `uninstall` / `status` son los verbos de la Scheduled Task que hace eso cada día a las 18:00.
#
#   pwsh -File hub-sync-tarea.ps1 -Action correr [-Dev <usuario de Windows>] [-StateDir <dir>]
#        [-PmRepo <owner/repo>] [-PmRemote <url>] [-Cuenta <cuenta de gh>] [-GhCmd <gh>] [-Now <iso>]
#   pwsh -File hub-sync-tarea.ps1 -Action install|uninstall|status [-TaskName <nombre>] [-SchtasksCmd <schtasks>]
#
# Los tres verbos imprimen un resumen JSON (como install-clients.ps1) y salen != 0 si no pudieron: una
# instalación que falla en silencio deja la PC sin recolectar y nadie se entera hasta que faltan propuestas.
param(
  [Parameter(Mandatory)][ValidateSet('correr', 'install', 'uninstall', 'status')][string]$Action,
  [string]$Dev = $env:USERNAME,
  [string]$StateDir = (Join-Path $env:LOCALAPPDATA "hub-sync"),
  [string]$PmRepo = "southpointtech/project-management",
  [string]$PmRemote = "https://github.com/southpointtech/project-management.git",
  [string]$Cuenta = "southpointtech",
  [string]$GhCmd = "gh",
  [string]$SchtasksCmd = "schtasks",
  [string]$TaskName = "hub-sync",
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
# Un valor con `&` (un repo en C:\Repos\R&D) rompería el XML entero, y el Programador lo rechaza con un
# mensaje que no nombra el ampersand.
function Esc([string]$v) { [Security.SecurityElement]::Escape($v) }
# Un valor citado que termina en `\` se come los parámetros que siguen: en la línea de comandos de Windows
# `\"` es una comilla ESCAPADA, no el cierre del valor (medido con CommandLineToArgvW). La corrida de
# barras finales se duplica, que preserva el valor; recortarla cambiaría `D:\` por `D:`, que es otra ruta.
function Cit([string]$v) {
  $sinBarras = $v.TrimEnd('\')
  '"' + $sinBarras + ('\' * (($v.Length - $sinBarras.Length) * 2)) + '"'
}

if ($Action -eq 'install') {
  # El Programador de tareas NO encuentra el `pwsh.exe` de la Store por nombre (medido en el spike 01:
  # LastTaskResult 0x80070002, sin escribir nada); el alias de WindowsApps sí funciona. Si no está, el
  # de Program Files. Lo que NO se usa es `[Environment]::ProcessPath` cuando apunta al paquete de la
  # Store: esa ruta lleva la versión adentro (`Microsoft.PowerShell_7.6.6.0_x64__...`, medido acá), así
  # que la tarea se rompería sola con el próximo update de PowerShell.
  $pwshExe = @(
    (Join-Path $env:LOCALAPPDATA "Microsoft\WindowsApps\pwsh.exe")
    (Join-Path $env:ProgramFiles "PowerShell\7\pwsh.exe")
    [Environment]::ProcessPath
  ) | Where-Object { $_ -and $_ -notmatch '\\WindowsApps\\Microsoft\.' -and (Test-Path -LiteralPath $_ -PathType Leaf) } |
  Select-Object -First 1
  # Fallar es mejor que registrar una tarea que va a morir todos los días sin escribir una línea.
  if (-not $pwshExe) { Fallar "no se encontró un pwsh.exe de ruta estable (ni el alias de WindowsApps ni el de Program Files)" }
  # La tarea corre la lista entera, así que agregar un repo no obliga a reinstalarla: los valores
  # con que se instaló quedan congelados en el XML, no se releen del ambiente de la sesión.
  $argumentos = "-NoProfile -File $(Cit $PSCommandPath) -Action correr -Dev $(Cit $Dev) -StateDir $(Cit $StateDir)" +
  " -PmRepo $(Cit $PmRepo) -PmRemote $(Cit $PmRemote) -Cuenta $(Cit $Cuenta)"
  # La serie arranca MAÑANA: con la de hoy, instalar después de la hora deja esa ocurrencia en el pasado
  # y `StartWhenAvailable` la puede disparar a los minutos — en pleno onboarding, con gh todavía sin
  # loguear, dejando una falla en el log de una máquina recién configurada.
  $desde = [DateTime]::Now.AddDays(1).ToString("yyyy-MM-dd", [Globalization.CultureInfo]::InvariantCulture)
  $xml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Description>hub-sync: recolecta los slices cerrados del dev y los envía a la bandeja de PROJECT MANAGEMENT.</Description>
  </RegistrationInfo>
  <Triggers>
    <CalendarTrigger>
      <StartBoundary>${desde}T18:00:00</StartBoundary>
      <Enabled>true</Enabled>
      <ScheduleByDay>
        <DaysInterval>1</DaysInterval>
      </ScheduleByDay>
    </CalendarTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <UserId>$(Esc "$env:USERDOMAIN\$env:USERNAME")</UserId>
      <LogonType>InteractiveToken</LogonType>
      <RunLevel>LeastPrivilege</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <Enabled>true</Enabled>
    <!-- La PC apagada a las 18:00 es el caso normal, no la excepción: la corrida perdida se recupera. -->
    <StartWhenAvailable>true</StartWhenAvailable>
    <!-- Todas las corridas comparten el clon pm-repo del transporte; el candado de hub-enviar.ps1 las
         serializa, pero apilar instancias sólo dejaría procesos esperando. -->
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <!-- Un laptop sin enchufar a las 18:00 también es el caso normal. -->
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <ExecutionTimeLimit>PT2H</ExecutionTimeLimit>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>$(Esc $pwshExe)</Command>
      <Arguments>$(Esc $argumentos)</Arguments>
    </Exec>
  </Actions>
</Task>
"@
  [IO.Directory]::CreateDirectory($StateDir) | Out-Null
  $xmlPath = Join-Path $StateDir "$TaskName.tarea.xml"
  # schtasks quiere el XML en UTF-16 con BOM; en UTF-8 lo rechaza con "The task XML contains a value
  # which is incorrectly formatted or out of range", que no dice nada del encoding.
  [IO.File]::WriteAllText($xmlPath, $xml, [Text.UnicodeEncoding]::new($false, $true))
  try {
    $cr = Invoke-Utf8 $SchtasksCmd @('/Create', '/TN', $TaskName, '/XML', $xmlPath, '/F')
  } finally { [IO.File]::Delete($xmlPath) }
  # Una instalación rechazada que saliera en 0 dejaría la PC sin recolectar, y nadie se enteraría hasta
  # que el PM note que faltan propuestas.
  if (-not $cr.lanzado) { Fallar $cr.stderr }
  if ($cr.exit -ne 0) { Fallar "el Programador rechazó la tarea ${TaskName}: $($cr.stderr)" }
  [pscustomobject]@{ accion = 'install'; tarea = $TaskName; instalada = $true
    ejecutable = $pwshExe; argumentos = $argumentos } | ConvertTo-Json -Compress
  exit 0
}

if ($Action -eq 'uninstall') {
  # Desinstalar lo que no está no es una falla: el verbo declara el estado final, no la transición, y
  # el /Delete del Programador también devuelve error cuando la tarea no existía. Por eso el resultado
  # se toma de la EVIDENCIA (¿sigue estando?) y no del exit del /Delete, que no distingue los dos casos.
  $del = Invoke-Utf8 $SchtasksCmd @('/Delete', '/TN', $TaskName, '/F')
  $q = Invoke-Utf8 $SchtasksCmd @('/Query', '/TN', $TaskName)
  if (-not $q.lanzado) { Fallar $q.stderr }
  if ($q.exit -eq 0) { Fallar "la tarea $TaskName sigue instalada: $($del.stderr)" }
  [pscustomobject]@{ accion = 'uninstall'; tarea = $TaskName; instalada = $false } | ConvertTo-Json -Compress
  exit 0
}

if ($Action -eq 'status') {
  # Si está instalada se lo pregunta al Programador, no a un archivo propio: el dev puede borrar la
  # tarea desde el Programador sin pasar por este script.
  $q = Invoke-Utf8 $SchtasksCmd @('/Query', '/TN', $TaskName)
  # Un Programador que no se puede ejecutar no es "no está instalada": eso manda a reinstalar una tarea
  # que quizá esté. Sale != 0 con el motivo por stderr y SIN escribir en el log, porque esa línea sería
  # la "última corrida" que informaría el status siguiente.
  if (-not $q.lanzado) { [Console]::Error.WriteLine("hub-sync-tarea: $($q.stderr)"); exit 1 }
  # Las líneas de la última corrida se juntan por momento: cada corrida escribe las suyas con el mismo.
  # NO se agrupa por repo: esa columna no es homogénea (la tarea escribe la ruta de la lista y el
  # transporte el nombre del repo), agruparla juntaría cosas distintas.
  $log = Join-Path $StateDir "hub-sync.log"
  $momento = $null
  $lineas = @()
  if (Test-Path -LiteralPath $log) {
    # Compartiendo escritura: una corrida puede estar apendeando en este mismo instante (`AppendAllText`
    # abre sin compartir escritura), y un lector exclusivo moriría sin emitir el JSON del reporte.
    $fs = [IO.File]::Open($log, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
    $texto = try { ([IO.StreamReader]::new($fs, $utf8)).ReadToEnd() } finally { $fs.Dispose() }
    $todas = @($texto -split "`r?`n" | Where-Object { $_ })
    if ($todas.Count) {
      # El momento MÁS NUEVO, no el de la última línea: dos corridas se intercalan y cada una congela su
      # propio momento al arrancar, así que la última línea del archivo puede ser de la corrida vieja. Los
      # momentos son ISO UTC de ancho fijo, así que el orden de string es el orden temporal.
      $momento = @($todas | ForEach-Object { ($_ -split "`t")[0] } | Where-Object { $_ -match '^\d{4}-' } | Sort-Object)[-1]
      $lineas = @($todas | Where-Object { $_.StartsWith("$momento`t") } | ForEach-Object {
          $c = $_ -split "`t"
          [pscustomobject]@{ repo = $c[2]; resultado = ($c[3..($c.Count - 1)] -join "`t") }
        })
    }
  }
  [pscustomobject]@{ accion = 'status'; tarea = $TaskName; instalada = ($q.exit -eq 0)
    ultimaCorrida = $momento; repos = $lineas
    conFallas = [bool](@($lineas | Where-Object { $_.resultado -like 'fall*' }).Count)
  } | ConvertTo-Json -Compress -Depth 5
  exit 0
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
