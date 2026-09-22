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
# Cada llamada deja sus argumentos en `llamadas.txt`.
function New-FakeGh([string]$reposJson, [switch]$SinToken) {
  $d = New-TestWorkspace $script:runRoot "hubtarea-gh"
  if ($SinToken) { [IO.File]::WriteAllText((Join-Path $d "sin-token"), "") }
  if ($reposJson) { [IO.File]::WriteAllText((Join-Path $d "repos.json"), $reposJson) }
  [IO.File]::WriteAllText((Join-Path $d "gh.cmd"), @'
@echo off
echo %*>> "%~dp0llamadas.txt"
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

# --- Una ruta que no existe o un repo sin transporte fallan en el log y no frenan a los demás ---
$bueno = New-HubRepo
$sinScripts = New-HubRepo -SinScripts
$noExiste = Join-Path $script:runRoot "no-existe-xyz"
$bare = New-PmRemote
$state = New-TestWorkspace $script:runRoot "hubtarea-state"
$gh = New-FakeGh (ConvertTo-ReposJson @{ martin = @($noExiste, $sinScripts, $bueno) })
$r = Correr $gh $state $bare "2026-09-22T18:00:00Z"
Assert ($r.exit -eq 1) "repo que no corre: exit 1 (fue $($r.exit); $($r.out))"
Assert ((Get-Inbox $bare) -contains "inbox/martin/$(Split-Path $bueno -Leaf)/20260922T180000Z.json") `
  "repo que no corre: el repo bueno, que va último, igual deja su lote"
$log = Get-Log $state
Assert ($log -match "(?m)^2026-09-22T18:00:00Z\tmartin\t$([regex]::Escape($noExiste))\tfalló: la ruta no existe") `
  "repo que no corre: el log nombra la ruta que no existe ('$log')"
Assert ($log -match "(?m)^2026-09-22T18:00:00Z\tmartin\t$([regex]::Escape($sinScripts))\tfalló: no tiene \.claude/scripts/hub-enviar\.ps1") `
  "repo que no corre: el log nombra el repo sin transporte ('$log')"

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

# --- Sin token de la cuenta, falla antes de pedir la lista: con la cuenta activa, el 404 mentiría ---
$state = New-TestWorkspace $script:runRoot "hubtarea-state"
$gh = New-FakeGh (ConvertTo-ReposJson @{ martin = @() }) -SinToken
$r = Correr $gh $state (New-PmRemote) "2026-09-22T18:00:00Z"
Assert ($r.exit -eq 1) "sin token: exit 1 (fue $($r.exit); $($r.out))"
Assert ((Get-Log $state) -match "(?m)^2026-09-22T18:00:00Z	martin	\*	falló: gh no tiene un token de la cuenta southpointtech") `
  "sin token: el log nombra la cuenta ('$(Get-Log $state)')"
$llamadas = [IO.File]::ReadAllText((Join-Path $gh "llamadas.txt"))
Assert ($llamadas -notmatch '(?m)^api ') "sin token: no pide la lista ($llamadas)"

Remove-TestRunRoot $script:runRoot
if ($script:failures -eq 0) { Write-Host "TODOS LOS TESTS PASARON"; exit 0 }
else { Write-Host "$($script:failures) test(s) FALLARON"; exit 1 }
