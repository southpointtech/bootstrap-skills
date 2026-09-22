# tests/hub-sync-tarea.tests.ps1 — runner sin Pester. Correr: pwsh -NoProfile -File tests/hub-sync-tarea.tests.ps1
# La corrida de la tarea por máquina de hub-sync (issue 12): lee la lista de repos del dev en
# `hub-sync/repos.json` de PROJECT MANAGEMENT y corre el `hub-enviar.ps1` de cada repo, de a uno.
# Fixtures: un `gh.cmd` falso que sirve la lista (y anota con qué argumentos lo llamaron), repos
# recolectables con los scripts del scaffold copiados, y un bare local como remoto de PROJECT MANAGEMENT.
$ErrorActionPreference = "Stop"
$repo     = Split-Path $PSScriptRoot -Parent
$tarea    = Join-Path $repo "skills/setup-mcp-workstation/scripts/hub-sync-tarea.ps1"
$scripts  = Join-Path $repo "skills/bootstrap-southpoint-project/assets/scaffold/.claude/scripts"
$script:failures = 0
. (Join-Path $PSScriptRoot "lib\temp-workspace.ps1")
$script:runRoot = New-TestRunRoot "hubtarea"
trap { Remove-TestRunRoot $script:runRoot; break }

function Assert($cond, $msg) {
  if ($cond) { Write-Host "ok:   $msg" } else { Write-Host "FAIL: $msg"; $script:failures++ }
}
# Sin el script, `pwsh -File` imprime su usage y sale con código != 0: los asserts de "no llegó"
# pasarían en verde sin ejercitar nada.
if (-not (Test-Path -LiteralPath $tarea)) {
  Remove-TestRunRoot $script:runRoot
  Write-Host "FAIL: no existe la tarea en $tarea"; exit 1
}

# Los fixtures heredan el gitconfig global: gpgsign, hooksPath y excludesFile se neutralizan (mismo
# motivo que en hub-recolectar.tests.ps1).
function Set-GitNeutral([string]$t) {
  git -C $t config user.email otro@x.io
  git -C $t config user.name otro
  git -C $t config commit.gpgsign false
  git -C $t config core.hooksPath ""
  git -C $t config core.excludesFile ""
}
# Un repo recolectable del dev `martin`, con el transporte y el recolector del scaffold.
function New-HubRepo([switch]$SinDeclaracion, [switch]$SinScripts) {
  $t = New-TestWorkspace $script:runRoot "hubtarea-repo"
  git -C $t init -q -b master
  Set-GitNeutral $t
  [IO.Directory]::CreateDirectory((Join-Path $t ".claude/scripts")) | Out-Null
  if (-not $SinDeclaracion) {
    [IO.File]::WriteAllText((Join-Path $t ".claude/hub-sync.json"),
      '{ "schemaVersion": 1, "hubProject": "Proyecto X", "devs": { "martin": ["m@x.io"] } }')
  }
  if (-not $SinScripts) {
    foreach ($s in 'hub-enviar.ps1', 'hub-recolectar.ps1') { Copy-Item (Join-Path $scripts $s) (Join-Path $t ".claude/scripts/$s") }
  }
  "base" | Set-Content (Join-Path $t "file.txt")
  git -C $t add -A; git -C $t commit -q -m base
  return $t
}
# El remoto de PROJECT MANAGEMENT: un bare con `main` y un README, como el real.
function New-PmRemote {
  $bare = New-TestWorkspace $script:runRoot "hubtarea-pm"
  git init -q --bare -b main $bare
  $seed = New-TestWorkspace $script:runRoot "hubtarea-seed"
  git clone -q $bare $seed 2>$null
  Set-GitNeutral $seed
  "# PM" | Set-Content (Join-Path $seed "README.md")
  git -C $seed add -A; git -C $seed commit -q -m seed
  git -C $seed push -q origin HEAD:main 2>$null
  return $bare
}
# Un `gh` falso: `auth token` imprime un token (o falla, con `-SinToken`) y `api` imprime `repos.json` (o sale en 1 si no hay).
# Cada llamada deja sus argumentos en `llamadas.txt`, y la de `api`, además, el GH_TOKEN con que llegó.
function New-FakeGh([string]$reposJson, [switch]$SinToken) {
  $d = New-TestWorkspace $script:runRoot "hubtarea-gh"
  if ($SinToken) { [IO.File]::WriteAllText((Join-Path $d "sin-token"), "") }
  if ($reposJson) { [IO.File]::WriteAllText((Join-Path $d "repos.json"), $reposJson) }
  [IO.File]::WriteAllText((Join-Path $d "gh.cmd"), @'
@echo off
echo %*>> "%~dp0llamadas.txt"
if "%1"=="api" echo GH_TOKEN=%GH_TOKEN%>> "%~dp0llamadas.txt"
if "%1"=="auth" if exist "%~dp0sin-token" (echo no oauth token found for github.com account 1>&2& exit /b 1)
if "%1"=="auth" (echo token-falso& exit /b 0)
if not exist "%~dp0repos.json" (echo HTTP 404 1>&2& exit /b 1)
type "%~dp0repos.json"
'@)
  return $d
}
function Get-Inbox([string]$bare) {
  @(git --git-dir $bare ls-tree -r --name-only main -- inbox/ 2>$null)
}
function Correr([string]$gh, [string]$state, [string]$remote, [string]$now, [string]$dev = "martin") {
  $out = & pwsh -NoProfile -File $tarea -Action correr -Dev $dev -StateDir $state -PmRemote $remote -Now $now `
    -GhCmd (Join-Path $gh "gh.cmd") 2>&1
  return @{ exit = $LASTEXITCODE; out = ($out -join "`n") }
}
function Get-Log([string]$state) {
  $log = Join-Path $state "hub-sync.log"
  if (Test-Path -LiteralPath $log) { [IO.File]::ReadAllText($log) } else { "" }
}
function ConvertTo-ReposJson([hashtable]$repos) {
  @{ schemaVersion = 1; repos = $repos } | ConvertTo-Json -Depth 5
}

# --- Tracer: el repo de la lista del dev deja su lote en inbox/<dev>/<repo>/ ---
$t = New-HubRepo
$bare = New-PmRemote
$state = New-TestWorkspace $script:runRoot "hubtarea-state"
$gh = New-FakeGh (ConvertTo-ReposJson @{ martin = @($t) })
$r = Correr $gh $state $bare "2026-09-22T18:00:00Z"
Assert ($r.exit -eq 0) "tracer: exit 0 (fue $($r.exit); $($r.out))"
$nombre = Split-Path $t -Leaf
Assert ((Get-Inbox $bare) -contains "inbox/martin/$nombre/20260922T180000Z.json") `
  "tracer: el lote llega a inbox/martin/$nombre/ (hay: $((Get-Inbox $bare) -join ', '))"
$llamadas = [IO.File]::ReadAllText((Join-Path $gh "llamadas.txt"))
Assert ($llamadas -match 'auth token .*-u southpointtech') "tracer: el token de la lista se pide con la cuenta southpointtech ($llamadas)"
Assert ($llamadas -match 'api .*repos/southpointtech/project-management/contents/hub-sync/repos\.json') `
  "tracer: la lista se lee de hub-sync/repos.json de PROJECT MANAGEMENT ($llamadas)"
Assert ($llamadas -match '(?m)^GH_TOKEN=token-falso\s*$') "tracer: la lista se pide con el token de southpointtech, no con la cuenta activa ($llamadas)"
Assert ($llamadas -match 'api .*Accept: application/vnd\.github\.raw') "tracer: la lista se pide cruda, no como objeto de contenidos en base64 ($llamadas)"

# --- La lista es por dev: los repos de otro dev no corren, y un dev sin repos sale en 0 con su línea de log ---
$t = New-HubRepo
$bare = New-PmRemote
$state = New-TestWorkspace $script:runRoot "hubtarea-state"
$gh = New-FakeGh (ConvertTo-ReposJson @{ otro = @($t) })
$r = Correr $gh $state $bare "2026-09-22T18:00:00Z"
Assert ($r.exit -eq 0) "dev sin repos: exit 0 (fue $($r.exit); $($r.out))"
Assert ((Get-Inbox $bare).Count -eq 0) "dev sin repos: el repo de otro dev no corre (hay: $((Get-Inbox $bare) -join ', '))"
Assert ((Get-Log $state) -match "(?m)^2026-09-22T18:00:00Z\tmartin\t\*\tsin repos en la lista") `
  "dev sin repos: el log lo dice ('$(Get-Log $state)')"

# --- Una ruta que no existe o un repo sin transporte fallan en el log y no frenan a los demás. Cada caso en
# su propia corrida, junto a un repo sano: juntos, el exit 1 de uno tapaba que el otro no contara ---
foreach ($caso in @(
    @{ nombre = "ruta que no existe"; motivo = 'falló: la ruta no existe'; ruta = { Join-Path $script:runRoot "no-existe-xyz" } }
    @{ nombre = "repo sin transporte"; motivo = 'falló: no tiene \.claude/scripts/hub-enviar\.ps1'; ruta = { New-HubRepo -SinScripts } })) {
  $malo = & $caso.ruta
  $bueno = New-HubRepo
  $bare = New-PmRemote
  $state = New-TestWorkspace $script:runRoot "hubtarea-state"
  $gh = New-FakeGh (ConvertTo-ReposJson @{ martin = @($malo, $bueno) })
  $r = Correr $gh $state $bare "2026-09-22T18:00:00Z"
  Assert ($r.exit -eq 1) "$($caso.nombre): exit 1 (fue $($r.exit); $($r.out))"
  Assert ((Get-Inbox $bare) -contains "inbox/martin/$(Split-Path $bueno -Leaf)/20260922T180000Z.json") `
    "$($caso.nombre): el repo sano, que va después, igual deja su lote"
  Assert ((Get-Log $state) -match "(?m)^2026-09-22T18:00:00Z\tmartin\t$([regex]::Escape($malo))\t$($caso.motivo)") `
    "$($caso.nombre): el log lo nombra ('$(Get-Log $state)')"
}

# --- Un repo cuyo transporte falla no frena a los demás, y la tarea sale en 1 ---
$roto = New-HubRepo
[IO.File]::WriteAllText((Join-Path $roto ".claude/hub-sync.json"), '{ roto')
$bueno = New-HubRepo
$bare = New-PmRemote
$state = New-TestWorkspace $script:runRoot "hubtarea-state"
$gh = New-FakeGh (ConvertTo-ReposJson @{ martin = @($roto, $bueno) })
$r = Correr $gh $state $bare "2026-09-22T18:00:00Z"
Assert ($r.exit -eq 1) "transporte que falla: exit 1 (fue $($r.exit); $($r.out))"
Assert ((Get-Inbox $bare) -contains "inbox/martin/$(Split-Path $bueno -Leaf)/20260922T180000Z.json") `
  "transporte que falla: el repo siguiente igual deja su lote"

# --- Una lista que no se puede leer es una falla, no una lista vacía: en un repo privado, GitHub da el
# mismo 404 cuando el archivo no existe que cuando la cuenta no lo ve ---
foreach ($caso in @(
    @{ nombre = "sin repos.json"; json = "" ; motivo = 'falló: no se pudo leer hub-sync/repos\.json de southpointtech/project-management: HTTP 404' }
    @{ nombre = "JSON roto";      json = "{ roto"; motivo = 'falló: hub-sync/repos\.json no es JSON válido' }
    @{ nombre = "sin schemaVersion 1"; json = '{ "schemaVersion": 2, "repos": {} }'; motivo = 'falló: hub-sync/repos\.json tiene schemaVersion 2, se esperaba 1' })) {
  $state = New-TestWorkspace $script:runRoot "hubtarea-state"
  $gh = New-FakeGh $caso.json
  $r = Correr $gh $state (New-PmRemote) "2026-09-22T18:00:00Z"
  Assert ($r.exit -eq 1) "lista ilegible ($($caso.nombre)): exit 1 (fue $($r.exit); $($r.out))"
  Assert ((Get-Log $state) -match "(?m)^2026-09-22T18:00:00Z\tmartin\t\*\t$($caso.motivo)") `
    "lista ilegible ($($caso.nombre)): el log dice por qué ('$(Get-Log $state)')"
}

# --- Un repo de la lista que no está en hub-sync no se recolecta, no es una falla, y deja su línea en el
# log: una clave de `devs` que no es el usuario de Windows es el error de configuración más probable ---
$sinDecl = New-HubRepo -SinDeclaracion
$bueno = New-HubRepo
$bare = New-PmRemote
$state = New-TestWorkspace $script:runRoot "hubtarea-state"
$gh = New-FakeGh (ConvertTo-ReposJson @{ martin = @($sinDecl, $bueno) })
$r = Correr $gh $state $bare "2026-09-22T18:00:00Z"
Assert ($r.exit -eq 0) "repo sin declaración: exit 0 (fue $($r.exit); $($r.out))"
Assert (@(Get-Inbox $bare | Where-Object { $_ -match [regex]::Escape((Split-Path $sinDecl -Leaf)) }).Count -eq 0) `
  "repo sin declaración: no deja lote (hay: $((Get-Inbox $bare) -join ', '))"
Assert ((Get-Inbox $bare) -contains "inbox/martin/$(Split-Path $bueno -Leaf)/20260922T180000Z.json") `
  "repo sin declaración: el repo siguiente igual deja su lote"
Assert ((Get-Log $state) -match "(?m)^2026-09-22T18:00:00Z\tmartin\t$([regex]::Escape((Split-Path $sinDecl -Leaf)))\tsin lote: el repo no está en hub-sync o martin no figura en su declaración") `
  "repo sin declaración: el log lo dice ('$(Get-Log $state)')"

# --- Un transporte que muere sin escribir su línea de log igual queda en el log, con su stderr. El
# mensaje va sin acentos: el stderr de un pwsh hijo sale en la code page de la consola, no en UTF-8 ---
$mudo = New-HubRepo -SinScripts
[IO.File]::WriteAllText((Join-Path $mudo ".claude/scripts/hub-enviar.ps1"), "[Console]::Error.WriteLine('murio sin log'); exit 3")
$state = New-TestWorkspace $script:runRoot "hubtarea-state"
$gh = New-FakeGh (ConvertTo-ReposJson @{ martin = @($mudo) })
$r = Correr $gh $state (New-PmRemote) "2026-09-22T18:00:00Z"
Assert ($r.exit -eq 1) "transporte mudo: exit 1 (fue $($r.exit); $($r.out))"
Assert ((Get-Log $state) -match "(?m)^2026-09-22T18:00:00Z\tmartin\t$([regex]::Escape($mudo))\tfalló: el transporte salió con 3: murio sin log") `
  "transporte mudo: el log nombra el repo y el motivo ('$(Get-Log $state)')"

# --- Si gh no se puede ejecutar, es una falla con su línea de log, no una excepción que corta la tarea ---
$state = New-TestWorkspace $script:runRoot "hubtarea-state"
$sinGh = New-TestWorkspace $script:runRoot "hubtarea-singh"
$r = Correr $sinGh $state (New-PmRemote) "2026-09-22T18:00:00Z"
Assert ($r.exit -eq 1) "gh que no corre: exit 1 (fue $($r.exit); $($r.out))"
Assert ((Get-Log $state) -match "(?m)^2026-09-22T18:00:00Z\tmartin\t\*\tfalló: no se pudo ejecutar .*gh\.cmd") `
  "gh que no corre: el log lo dice ('$(Get-Log $state)')"

# --- Sin token de la cuenta, falla antes de pedir la lista: con la cuenta activa, el 404 mentiría ---
$state = New-TestWorkspace $script:runRoot "hubtarea-state"
$gh = New-FakeGh (ConvertTo-ReposJson @{ martin = @() }) -SinToken
$r = Correr $gh $state (New-PmRemote) "2026-09-22T18:00:00Z"
Assert ($r.exit -eq 1) "sin token: exit 1 (fue $($r.exit); $($r.out))"
Assert ((Get-Log $state) -match "(?m)^2026-09-22T18:00:00Z	martin	\*	falló: gh no tiene un token de la cuenta southpointtech") `
  "sin token: el log nombra la cuenta ('$(Get-Log $state)')"
$llamadas = [IO.File]::ReadAllText((Join-Path $gh "llamadas.txt"))
Assert ($llamadas -notmatch '(?m)^api ') "sin token: no pide la lista ($llamadas)"

# --- Los verbos del Scheduled Task (12b) ---------------------------------------------------------
# Un `schtasks` falso que guarda cada tarea como un archivo en `tasks\<nombre>.xml`: así "instalar dos
# veces deja una sola tarea" se prueba por lo que queda registrado, no por lo que se llamó. Copia el XML
# en binario (`/b`) para no tocar los bytes, que es lo que mira el caso de la codificación.
function New-FakeSchtasks([string]$FallaEn) {
  $d = New-TestWorkspace $script:runRoot "hubtarea-sch"
  if ($FallaEn) { [IO.File]::WriteAllText((Join-Path $d "falla-$FallaEn"), "") }
  [IO.File]::WriteAllText((Join-Path $d "schtasks.cmd"), @'
@echo off
setlocal enabledelayedexpansion
rem `shift` tambien corre %0, asi que el directorio del script se guarda ANTES del loop.
set "HERE=%~dp0"
rem Una ruta con & rompe `echo %*`: se guarda en una variable (las comillas la protegen) y se
rem imprime con expansion retardada, que ya no re-parsea el &.
set "ARGS=%*"
echo !ARGS!>> "%HERE%llamadas.txt"
set "ACTION=%~1"
set "TN="
set "XML="
set "FORCE="
:parse
if "%~1"=="" goto done
if /I "%~1"=="/TN" set "TN=%~2"
if /I "%~1"=="/XML" set "XML=%~2"
if /I "%~1"=="/F" set "FORCE=1"
shift
goto parse
:done
if not exist "%HERE%tasks" mkdir "%HERE%tasks"
set "VERBO=%ACTION:/=%"
if exist "%HERE%falla-%VERBO%" echo ERROR: Access is denied. 1>&2& exit /b 1
if /I "%ACTION%"=="/Create" goto create
if /I "%ACTION%"=="/Delete" goto delete
if /I "%ACTION%"=="/Query" goto query
echo ERROR: verbo desconocido %ACTION% 1>&2
exit /b 1
:create
if not exist "%XML%" echo ERROR: no existe el XML %XML% 1>&2& exit /b 1
if not exist "%HERE%tasks\%TN%.xml" goto write
if not defined FORCE echo ERROR: the task already exists 1>&2& exit /b 1
:write
copy /y /b "%XML%" "%HERE%tasks\%TN%.xml" >nul
echo SUCCESS: The scheduled task "%TN%" has successfully been created.
exit /b 0
:delete
if not exist "%HERE%tasks\%TN%.xml" echo ERROR: The system cannot find the file specified. 1>&2& exit /b 1
del "%HERE%tasks\%TN%.xml"
echo SUCCESS: The scheduled task "%TN%" was successfully deleted.
exit /b 0
:query
if not exist "%HERE%tasks\%TN%.xml" echo ERROR: The system cannot find the file specified. 1>&2& exit /b 1
echo %TN%
exit /b 0
'@)
  return $d
}
# Corre un bloque con variables de ambiente stubbeadas y las restaura siempre: los casos del ejecutable
# dependen de cómo instaló PowerShell la máquina, y la suite no puede depender de eso.
function Con-Ambiente([hashtable]$vars, [scriptblock]$bloque) {
  $previas = @{}
  foreach ($k in $vars.Keys) { $previas[$k] = [Environment]::GetEnvironmentVariable($k) }
  try {
    foreach ($k in $vars.Keys) { Set-Item -Path "Env:$k" -Value $vars[$k] }
    & $bloque
  } finally { foreach ($k in $previas.Keys) { Set-Item -Path "Env:$k" -Value $previas[$k] } }
}
# El parser real de Windows (el mismo que usa el Programador al lanzar la tarea): un assert sobre el texto
# de la línea no distingue una comilla que cierra de una escapada por una barra invertida.
Add-Type -Namespace Win32 -Name Shell -MemberDefinition @'
[DllImport("shell32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
public static extern IntPtr CommandLineToArgvW(string lpCmdLine, out int pNumArgs);
[DllImport("kernel32.dll")]
public static extern IntPtr LocalFree(IntPtr hMem);
'@
function ConvertTo-Argv([string]$linea) {
  $n = 0
  $p = [Win32.Shell]::CommandLineToArgvW($linea, [ref]$n)
  if ($p -eq [IntPtr]::Zero) { return @() }
  try {
    $salida = for ($i = 0; $i -lt $n; $i++) {
      [Runtime.InteropServices.Marshal]::PtrToStringUni(
        [Runtime.InteropServices.Marshal]::ReadIntPtr($p, $i * [IntPtr]::Size))
    }
    return @($salida)
  } finally { [void][Win32.Shell]::LocalFree($p) }
}
function Get-TareaXml([string]$sch, [string]$nombre = "hub-sync") {
  $p = Join-Path $sch "tasks\$nombre.xml"
  if (Test-Path -LiteralPath $p) { [IO.File]::ReadAllText($p) } else { "" }
}
# Los verbos del Task no tocan git ni gh: sólo el Programador y el log.
function Verbo([string]$accion, [string]$sch, [string]$state, [string]$dev = "martin") {
  $a = @('-NoProfile', '-File', $tarea, '-Action', $accion, '-Dev', $dev, '-StateDir', $state,
    '-SchtasksCmd', (Join-Path $sch "schtasks.cmd"))
  $out = & pwsh @a 2>&1
  $texto = ($out -join "`n")
  $codigo = $LASTEXITCODE
  $json = try { $texto | ConvertFrom-Json } catch { $null }
  return @{ exit = $codigo; out = $texto; json = $json }
}

# --- install registra la tarea con el pwsh que el Programador SÍ encuentra (spike 01: el de la Store
# da 0x80070002) y con la corrida completa, para que agregar un repo no obligue a reinstalar ---
$sch = New-FakeSchtasks
$state = New-TestWorkspace $script:runRoot "hubtarea-state"
$r = Verbo install $sch $state
Assert ($r.exit -eq 0) "install: exit 0 (fue $($r.exit); $($r.out))"
Assert ($r.json -and $r.json.instalada -eq $true) "install: el resumen JSON dice que quedó instalada ($($r.out))"
$llamadas = [IO.File]::ReadAllText((Join-Path $sch "llamadas.txt"))
Assert ($llamadas -match '/Create .*/TN hub-sync') "install: crea la tarea hub-sync ($llamadas)"
$xml = Get-TareaXml $sch
Assert ($xml -match [regex]::Escape('\Microsoft\WindowsApps\pwsh.exe')) `
  "install: el ejecutable es el alias de WindowsApps, no 'pwsh' pelado ($xml)"
Assert ($xml -match '-Action correr') "install: la tarea corre la recolección de todos los repos de la lista ($xml)"
Assert ($xml -match [regex]::Escape($state)) "install: la tarea lleva el StateDir con el que se instaló ($xml)"

# --- El disparador: diario a las 18:00, corre si se perdió (la PC apagada a esa hora es el caso normal)
# y sin instancias superpuestas (todas las corridas comparten el clon pm-repo del transporte) ---
Assert ($xml -match '<ScheduleByDay>\s*<DaysInterval>1</DaysInterval>') "disparador: es diario ($xml)"
# La serie arranca MAÑANA: con el StartBoundary de hoy, instalar después de las 18:00 deja la ocurrencia
# de hoy en el pasado, y `StartWhenAvailable` la puede disparar a los minutos — en pleno onboarding, con
# gh todavía sin loguear, dejando una falla en el log de una máquina recién configurada.
Assert ($xml -match "<StartBoundary>$([DateTime]::Now.AddDays(1).ToString('yyyy-MM-dd'))T18:00:00</StartBoundary>") `
  "disparador: a las 18:00, arrancando mañana ($xml)"
Assert ($xml -match '<DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>') `
  "disparador: un laptop a batería a las 18:00 igual recolecta ($xml)"
Assert ($xml -match '<StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>') `
  "disparador: pasar a batería no corta la corrida ($xml)"
Assert ($xml -match '<StartWhenAvailable>true</StartWhenAvailable>') `
  "disparador: corre si se perdió el horario ($xml)"
Assert ($xml -match '<MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>') `
  "disparador: no arranca una segunda instancia si la anterior sigue corriendo ($xml)"

# --- El XML llega en UTF-16 con BOM: schtasks rechaza el XML en UTF-8 ("The task XML contains a value
# which is incorrectly formatted"), y el falso lo copia en binario justamente para poder mirar los bytes.
# Y el archivo que se le pasó no queda tirado en el StateDir ---
$bytes = [IO.File]::ReadAllBytes((Join-Path $sch "tasks\hub-sync.xml"))
Assert ($bytes.Count -gt 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) `
  "codificación: el XML va en UTF-16 con BOM (primeros bytes: $($bytes[0..1] -join ','))"
Assert (@(Get-ChildItem -LiteralPath $state -Filter "*.xml").Count -eq 0) `
  "install: no deja el XML tirado en el StateDir ($((Get-ChildItem -LiteralPath $state).Name -join ', '))"

# --- Instalar dos veces deja UNA sola tarea: la skill se corre de nuevo para rotar credenciales, y el
# Programador rechaza un /Create sobre una tarea que ya existe si no se lo fuerza ---
$sch = New-FakeSchtasks
$state = New-TestWorkspace $script:runRoot "hubtarea-state"
$r1 = Verbo install $sch $state
$r2 = Verbo install $sch $state
Assert ($r1.exit -eq 0 -and $r2.exit -eq 0) "install x2: las dos salen en 0 (fueron $($r1.exit) y $($r2.exit); $($r2.out))"
Assert ($r2.json -and $r2.json.instalada -eq $true) "install x2: la segunda también deja la tarea instalada ($($r2.out))"
Assert (@(Get-ChildItem -LiteralPath (Join-Path $sch "tasks")).Count -eq 1) `
  "install x2: queda una sola tarea ($((Get-ChildItem -LiteralPath (Join-Path $sch 'tasks')).Name -join ', '))"

# --- uninstall saca la tarea del Programador; desinstalar lo que no está no es una falla (el dev que
# reinstala la máquina, o que corre el verbo dos veces, no tiene por qué ver un error) ---
$sch = New-FakeSchtasks
$state = New-TestWorkspace $script:runRoot "hubtarea-state"
Verbo install $sch $state | Out-Null
$r = Verbo uninstall $sch $state
Assert ($r.exit -eq 0) "uninstall: exit 0 (fue $($r.exit); $($r.out))"
Assert ($r.json -and $r.json.instalada -eq $false) "uninstall: el resumen dice que ya no está instalada ($($r.out))"
Assert ((Get-TareaXml $sch) -eq "") "uninstall: la tarea ya no está en el Programador"
$r2 = Verbo uninstall $sch $state
Assert ($r2.exit -eq 0) "uninstall x2: desinstalar lo que no está no es una falla (fue $($r2.exit); $($r2.out))"
Assert ($r2.json -and $r2.json.instalada -eq $false) "uninstall x2: el resumen lo dice igual ($($r2.out))"

# --- Y un Programador que no se puede ejecutar tampoco es "ya no está": sin este caso, sacar la guarda
# de `lanzado` del uninstall deja la suite verde mientras el verbo declara que desinstaló una tarea a la
# que nunca le habló (mutante sobreviviente del turno 1 del review-loop) ---
$state = New-TestWorkspace $script:runRoot "hubtarea-state"
$r = Verbo uninstall (New-TestWorkspace $script:runRoot "hubtarea-sinsch") $state
Assert ($r.exit -eq 1) "uninstall sin schtasks: exit 1 (fue $($r.exit); $($r.out))"
Assert ((Get-Log $state) -match "(?m)\tmartin\t\*\tfalló: no se pudo ejecutar .*schtasks\.cmd") `
  "uninstall sin schtasks: el log lo dice ('$(Get-Log $state)')"

# --- status informa si la tarea está instalada, preguntándoselo al Programador y no a un archivo propio:
# el dev la puede borrar desde el Programador sin pasar por acá ---
$sch = New-FakeSchtasks
$state = New-TestWorkspace $script:runRoot "hubtarea-state"
$r = Verbo status $sch $state
Assert ($r.exit -eq 0) "status sin tarea: exit 0 (fue $($r.exit); $($r.out))"
Assert ($r.json -and $r.json.instalada -eq $false) "status sin tarea: dice que no está instalada ($($r.out))"
Verbo install $sch $state | Out-Null
$r = Verbo status $sch $state
Assert ($r.json -and $r.json.instalada -eq $true) "status con tarea: dice que está instalada ($($r.out))"

# --- status informa la ÚLTIMA corrida, con una línea por repo: es lo que contesta "¿está andando?".
# La corrida vieja, con su falla, no tiene que ensuciar la foto de la última ---
$sch = New-FakeSchtasks
$state = New-TestWorkspace $script:runRoot "hubtarea-state"
[IO.File]::WriteAllText((Join-Path $state "hub-sync.log"), @"
2026-09-21T18:00:00Z`tmartin`tForecasting App`tfalló: la ruta no existe
2026-09-22T18:00:00Z`tmartin`tC:\Repos\Forecasting App`tok (1 lotes)
2026-09-22T18:00:00Z`tmartin`totro-repo`tsin cambios
"@)
$r = Verbo status $sch $state
Assert ($r.exit -eq 0) "status con log: exit 0 (fue $($r.exit); $($r.out))"
# Sobre el texto del JSON: `ConvertFrom-Json` coacciona el ISO a un DateTime en la zona local, así que
# comparar el objeto compararía otra cosa que la que el consumidor lee.
Assert ($r.out -match '"ultimaCorrida":"2026-09-22T18:00:00Z"') "status con log: informa el momento de la última corrida ($($r.out))"
Assert (@($r.json.repos).Count -eq 2) "status con log: sólo las líneas de esa corrida ($($r.out))"
Assert ((@($r.json.repos) | Where-Object { $_.repo -eq "otro-repo" }).resultado -eq "sin cambios") `
  "status con log: cada repo con su resultado ($($r.out))"
# Sobre el texto, igual que `ultimaCorrida`: `-eq $false` contra el objeto también pasa si el campo sale
# como el número 0, y el consumidor lee el JSON.
Assert ($r.out -match '"conFallas":false') "status con log: la falla de la corrida vieja no cuenta, y el tipo es booleano ($($r.out))"

# --- Una falla en la última corrida sí se informa: es el caso que el dev tiene que ver ---
$state2 = New-TestWorkspace $script:runRoot "hubtarea-state"
[IO.File]::WriteAllText((Join-Path $state2 "hub-sync.log"),
  "2026-09-22T18:00:00Z`tmartin`t*`tfalló: no se pudo leer hub-sync/repos.json de southpointtech/project-management: HTTP 404`n")
$r = Verbo status $sch $state2
Assert ($r.json.conFallas -eq $true) "status con falla: la última corrida falló ($($r.out))"

# --- Sin log todavía (recién instalada), status no falla: dice que nunca corrió ---
$state3 = New-TestWorkspace $script:runRoot "hubtarea-state"
$r = Verbo status $sch $state3
Assert ($r.exit -eq 0) "status sin log: exit 0 (fue $($r.exit); $($r.out))"
Assert ($null -eq $r.json.ultimaCorrida) "status sin log: no inventa una última corrida ($($r.out))"

# --- Un Programador que rechaza la instalación no puede salir en verde: la PC quedaría sin recolectar
# y nadie se enteraría hasta que el PM note que faltan propuestas ---
$state = New-TestWorkspace $script:runRoot "hubtarea-state"
$r = Verbo install (New-FakeSchtasks -FallaEn Create) $state
Assert ($r.exit -eq 1) "install rechazado: exit 1 (fue $($r.exit); $($r.out))"
Assert ((Get-Log $state) -match "(?m)\tmartin\t\*\tfalló: .*Access is denied") `
  "install rechazado: el log dice por qué ('$(Get-Log $state)')"

# --- Y un Programador que no se puede ejecutar tampoco: mismo criterio que con gh en la corrida ---
$state = New-TestWorkspace $script:runRoot "hubtarea-state"
$r = Verbo install (New-TestWorkspace $script:runRoot "hubtarea-sinsch") $state
Assert ($r.exit -eq 1) "install sin schtasks: exit 1 (fue $($r.exit); $($r.out))"
Assert ((Get-Log $state) -match "(?m)\tmartin\t\*\tfalló: no se pudo ejecutar .*schtasks\.cmd") `
  "install sin schtasks: el log lo dice ('$(Get-Log $state)')"

# --- uninstall se cree por EVIDENCIA, no por el exit del /Delete: si la tarea sigue ahí, falló. Es la
# diferencia con "desinstalar lo que no está", donde el /Delete también devuelve error ---
$sch = New-FakeSchtasks -FallaEn Delete
$state = New-TestWorkspace $script:runRoot "hubtarea-state"
Verbo install $sch $state | Out-Null
$r = Verbo uninstall $sch $state
Assert ($r.exit -eq 1) "uninstall que no pudo: exit 1 (fue $($r.exit); $($r.out))"
Assert ((Get-TareaXml $sch) -ne "") "uninstall que no pudo: la tarea sigue instalada (el fixture es válido)"
Assert ((Get-Log $state) -match "(?m)\tmartin\t\*\tfalló: la tarea hub-sync sigue instalada") `
  "uninstall que no pudo: el log lo dice ('$(Get-Log $state)')"

# --- Un valor con `&` (un repo en `C:\Repos\R&D`) no puede romper el XML: el Programador lo rechazaría
# entero con un mensaje que no nombra el ampersand. El `&` entra por `-Dev` y no por el `-StateDir`, que
# es el portador natural, porque el fixture es un `.cmd`: cmd.exe parte el argumento en el `&` antes de
# que el script lo vea. El `schtasks.exe` real es un exe y lo recibe entero, así que el límite es del
# fixture, no del producto. ---
$sch = New-FakeSchtasks
$state = New-TestWorkspace $script:runRoot "hubtarea-state"
$r = Verbo install $sch $state 'R&D'
Assert ($r.exit -eq 0) "ruta con &: exit 0 (fue $($r.exit); $($r.out))"
$xmlCrudo = Get-TareaXml $sch
$doc = try { [xml]$xmlCrudo } catch { $null }
Assert ($null -ne $doc -and $null -ne $doc.Task) "ruta con &: el XML sigue siendo XML válido ($xmlCrudo)"
Assert ($doc -and $doc.Task.Actions.Exec.Arguments -match [regex]::Escape('-Dev "R&D"')) `
  "ruta con &: el valor llega entero al Programador ($($doc.Task.Actions.Exec.Arguments))"

# --- En una PC donde PowerShell NO vino de la Store, el alias de WindowsApps no existe. Lo que la tarea
# NO puede quedar apuntando es a la ruta del PAQUETE de la Store (`...\WindowsApps\Microsoft.PowerShell_
# 7.6.6.0_x64__...`), que es a donde resuelve `[Environment]::ProcessPath` en una máquina con PowerShell
# de la Store (medido): lleva la versión adentro y se rompe sola con el próximo update.
# `LOCALAPPDATA` se stubbea para sacar el alias del medio; `ProgramFiles` NO se puede stubbear (medido:
# Windows la repone en el proceso hijo), así que el caso cubre las dos salidas legítimas — el pwsh de
# Program Files, o la falla declarada — y ninguna de las dos es la ruta versionada.
$sch = New-FakeSchtasks
$state = New-TestWorkspace $script:runRoot "hubtarea-state"
$r = Con-Ambiente @{ LOCALAPPDATA = (New-TestWorkspace $script:runRoot "hubtarea-sinalias") } {
  Verbo install $sch $state
}
if ($r.exit -eq 0) {
  $cmdTarea = ([xml](Get-TareaXml $sch)).Task.Actions.Exec.Command
  Assert ($cmdTarea -notmatch '\WindowsApps\Microsoft\.') `
    "sin alias de la Store: no clava la ruta versionada del paquete ('$cmdTarea')"
  Assert (Test-Path -LiteralPath $cmdTarea -PathType Leaf) "sin alias de la Store: el ejecutable existe ('$cmdTarea')"
}
else {
  Assert ($r.out -match 'no se encontró un pwsh\.exe de ruta estable') `
    "sin alias de la Store ni pwsh estable: falla con su motivo en vez de instalar una tarea rota ($($r.out))"
  Assert ((Get-TareaXml $sch) -eq "") "sin alias de la Store ni pwsh estable: no registra la tarea"
}

# --- Un valor terminado en `\` (la raíz `D:\`, o el completado de PowerShell, que agrega la barra) no
# puede comerse los parámetros que siguen: en la línea de comandos de Windows `\"` es una comilla
# ESCAPADA, así que sin cuidado `-StateDir "D:\hub\"` se traga -PmRepo, -PmRemote y -Cuenta ---
$sch = New-FakeSchtasks
$stateBarra = (New-TestWorkspace $script:runRoot "hubtarea-state") + "\"
$r = Verbo install $sch $stateBarra
Assert ($r.exit -eq 0) "StateDir con barra final: exit 0 (fue $($r.exit); $($r.out))"
$argv = @(ConvertTo-Argv ([xml](Get-TareaXml $sch)).Task.Actions.Exec.Arguments)
Assert ($argv -contains '-PmRepo' -and $argv -contains '-PmRemote' -and $argv -contains '-Cuenta') `
  "StateDir con barra final: los parámetros que siguen no se los come el valor ($($argv -join ' | '))"
Assert ($argv[([array]::IndexOf($argv, '-StateDir') + 1)] -eq $stateBarra) `
  "StateDir con barra final: y el valor llega con su barra, no recortado ($($argv -join ' | '))"

# --- Un Programador que no se puede ejecutar no puede salir como "no está instalada": status es EL verbo
# de diagnóstico, y decir "no está" cuando en realidad no se pudo preguntar manda a reinstalar. Tampoco
# escribe su falla en el log: esa línea sería la "última corrida" que el status siguiente informa ---
$state = New-TestWorkspace $script:runRoot "hubtarea-state"
$r = Verbo status (New-TestWorkspace $script:runRoot "hubtarea-sinsch") $state
Assert ($r.exit -eq 1) "status sin schtasks: exit 1 (fue $($r.exit); $($r.out))"
Assert ($r.out -match 'no se pudo ejecutar .*schtasks\.cmd') "status sin schtasks: dice por qué ($($r.out))"
Assert ((Get-Log $state) -eq "") `
  "status sin schtasks: no ensucia el log que el propio status lee ('$(Get-Log $state)')"

# --- La última corrida es la del momento MÁS NUEVO, no la de la última línea: dos corridas se intercalan
# (una espera el candado mientras la otra trabaja) y cada una congela su propio momento, así que la última
# línea del archivo puede ser de la corrida vieja ---
$sch = New-FakeSchtasks
$state = New-TestWorkspace $script:runRoot "hubtarea-state"
[IO.File]::WriteAllText((Join-Path $state "hub-sync.log"), @"
2026-09-22T18:00:00Z`tmartin`tRepoB`tok (1 lotes)
2026-09-22T18:20:00Z`tmartin`tRepoA`tfalló: la ruta no existe
2026-09-22T18:20:00Z`tmartin`tRepoC`tok (2 lotes)
2026-09-22T18:00:00Z`tmartin`tRepoD`tok (3 lotes)
"@)
$r = Verbo status $sch $state
Assert ($r.out -match '"ultimaCorrida":"2026-09-22T18:20:00Z"') `
  "corridas intercaladas: informa la corrida nueva, aunque su línea no sea la última ($($r.out))"
Assert (@($r.json.repos).Count -eq 2) "corridas intercaladas: sólo las líneas de esa corrida ($($r.out))"
Assert ($r.out -match '"conFallas":true') `
  "corridas intercaladas: la falla de la corrida nueva se informa, y el tipo es booleano ($($r.out))"

# --- status lee el log mientras una corrida lo está escribiendo: `AppendAllText` lo tiene abierto sin
# compartir escritura, y un lector que no la comparta muere sin emitir el JSON que el Step 6 reporta ---
$sch = New-FakeSchtasks
$state = New-TestWorkspace $script:runRoot "hubtarea-state"
$logPath = Join-Path $state "hub-sync.log"
[IO.File]::WriteAllText($logPath, "2026-09-22T18:00:00Z`tmartin`tRepoA`tok (1 lotes)`n")
$handle = [IO.File]::Open($logPath, [IO.FileMode]::Append, [IO.FileAccess]::Write, [IO.FileShare]::Read)
try { $r = Verbo status $sch $state } finally { $handle.Dispose() }
Assert ($r.exit -eq 0) "log en escritura: status igual sale 0 (fue $($r.exit); $($r.out))"
Assert ($r.out -match '"ultimaCorrida":"2026-09-22T18:00:00Z"') `
  "log en escritura: status igual informa la última corrida ($($r.out))"

Remove-TestRunRoot $script:runRoot
if ($script:failures -eq 0) { Write-Host "TODOS LOS TESTS PASARON"; exit 0 }
else { Write-Host "$($script:failures) test(s) FALLARON"; exit 1 }
