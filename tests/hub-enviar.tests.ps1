# tests/hub-enviar.tests.ps1 — runner sin Pester. Correr: pwsh -NoProfile -File tests/hub-enviar.tests.ps1
# El transporte de hub-sync (issue 04): corre el recolector y empuja los lotes pendientes a
# `inbox/<dev>/<repo>/` del repo PROJECT MANAGEMENT. Fixtures: un repo recolectable y un repo bare
# local que hace de remoto de PROJECT MANAGEMENT. La cuenta southpointtech no se ejercita acá: sólo se
# usa contra github.com: el caso sin token se prueba (sin red), el push real es QA manual.
$ErrorActionPreference = "Stop"
$repo   = Split-Path $PSScriptRoot -Parent
$enviar = Join-Path $repo "skills/bootstrap-southpoint-project/assets/scaffold/.claude/scripts/hub-enviar.ps1"
$script:failures = 0
. (Join-Path $PSScriptRoot "lib\temp-workspace.ps1")
$script:runRoot = New-TestRunRoot "hubenv"
trap { Remove-TestRunRoot $script:runRoot; break }

function Assert($cond, $msg) {
  if ($cond) { Write-Host "ok:   $msg" } else { Write-Host "FAIL: $msg"; $script:failures++ }
}
# Sin el script, `pwsh -File` imprime su usage y sale con código != 0: los asserts de "no llegó"
# pasarían en verde sin ejercitar nada.
if (-not (Test-Path -LiteralPath $enviar)) {
  Remove-TestRunRoot $script:runRoot
  Write-Host "FAIL: no existe el transporte en $enviar"; exit 1
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
# Un repo recolectable: declaración con el dev `martin` y un commit base.
function New-HubRepo([string]$origin = "") {
  $t = New-TestWorkspace $script:runRoot "hubenv-repo"
  git -C $t init -q -b master
  Set-GitNeutral $t
  if ($origin) { git -C $t remote add origin $origin }
  [IO.Directory]::CreateDirectory((Join-Path $t ".claude")) | Out-Null
  [IO.File]::WriteAllText((Join-Path $t ".claude/hub-sync.json"),
    '{ "schemaVersion": 1, "hubProject": "Proyecto X", "devs": { "martin": ["m@x.io"] } }')
  "base" | Set-Content (Join-Path $t "file.txt")
  git -C $t add -A; git -C $t commit -q -m base
  return $t
}
# El remoto de PROJECT MANAGEMENT: un bare con `main` y un README, como el real.
function New-PmRemote {
  $bare = New-TestWorkspace $script:runRoot "hubenv-pm"
  git init -q --bare -b main $bare
  $seed = New-TestWorkspace $script:runRoot "hubenv-seed"
  git clone -q $bare $seed 2>$null
  Set-GitNeutral $seed
  "# PM" | Set-Content (Join-Path $seed "README.md")
  git -C $seed add -A; git -C $seed commit -q -m seed
  git -C $seed push -q origin HEAD:main 2>$null
  return $bare
}
# Lo que hay en `main` del remoto bajo `inbox/`.
function Get-Inbox([string]$bare) {
  @(git --git-dir $bare ls-tree -r --name-only main -- inbox/ 2>$null)
}
function Enviar([string]$t, [string]$state, [string]$remote, [string]$now, [string]$dev = "martin", [string]$cuenta = "southpointtech") {
  $out = & pwsh -NoProfile -File $enviar -RepoDir $t -Dev $dev -StateDir $state -PmRemote $remote -Now $now -Cuenta $cuenta 2>&1
  return @{ exit = $LASTEXITCODE; out = ($out -join "`n") }
}
# La línea del log de una corrida (por su momento), o "" si no hay.
function Get-LogLine([string]$state, [string]$now) {
  $log = Join-Path $state "hub-sync.log"
  if (-not (Test-Path -LiteralPath $log)) { return "" }
  @([IO.File]::ReadAllText($log) -split "`n" | Where-Object { $_.StartsWith($now) }) -join "`n"
}
# La carpeta de estado del repo que armó el recolector (`<repo>-<hash>`), al lado del clon privado.
function Get-RepoState([string]$state) {
  Get-ChildItem -LiteralPath $state -Directory | Where-Object { $_.Name -ne "pm-repo" } | Select-Object -First 1
}

# --- Tracer: el lote de la corrida llega al remoto bajo inbox/<dev>/<repo>/ ---
$t = New-HubRepo
$bare = New-PmRemote
$state = New-TestWorkspace $script:runRoot "hubenv-state"
$r = Enviar $t $state $bare "2026-09-21T10:00:00Z"
Assert ($r.exit -eq 0) "tracer: exit 0 (fue $($r.exit); $($r.out))"
$nombre = Split-Path $t -Leaf
$inbox = Get-Inbox $bare
Assert ($inbox -contains "inbox/martin/$nombre/20260921T100000Z.json") `
  "tracer: el lote está en el remoto como inbox/martin/$nombre/20260921T100000Z.json (hay: $($inbox -join ', '))"

# --- Un push fallido no pierde el lote: queda en disco, el log dice por qué, y la corrida siguiente lo empuja ---
$t = New-HubRepo
$bare = New-PmRemote
$state = New-TestWorkspace $script:runRoot "hubenv-state"
$nombre = Split-Path $t -Leaf
Enviar $t $state $bare "2026-09-21T10:00:00Z" | Out-Null
# El remoto se cae: el clon privado ya existe, así que lo que falla es el fetch, no el clone. El push
# que falla con el remoto arriba es otro caso, más abajo.
$caido = "$bare-caido"
Move-Item -LiteralPath $bare -Destination $caido
$r = Enviar $t $state $bare "2026-09-22T10:00:00Z"
Assert ($r.exit -ne 0) "remoto caído: exit != 0 (fue $($r.exit))"
$pendiente = Get-ChildItem -LiteralPath $state -Recurse -File -Filter "20260922T100000Z.json" |
  Where-Object { $_.Directory.Name -eq "lotes" }
Assert ($null -ne $pendiente) "remoto caído: el lote queda pendiente en lotes/"
$log = Join-Path $state "hub-sync.log"
$texto = if (Test-Path -LiteralPath $log) { [IO.File]::ReadAllText($log) } else { "" }
$linea = @($texto -split "`n" | Where-Object { $_ -match '^2026-09-22T10:00:00Z' })
Assert ($linea.Count -eq 1 -and $linea[0].Contains($nombre) -and $linea[0] -match 'falló') `
  "remoto caído: el log tiene una línea de la corrida, fallida y con el repo (log: '$texto')"
Assert ($linea.Count -eq 1 -and $linea[0] -match 'falló: .*does not appear to be a git repository') `
  "remoto caído: el log trae el motivo que dio git (log: '$texto')"
Move-Item -LiteralPath $caido -Destination $bare
$r = Enviar $t $state $bare "2026-09-23T10:00:00Z"
Assert ($r.exit -eq 0) "remoto de vuelta: exit 0 (fue $($r.exit); $($r.out))"
$inbox = Get-Inbox $bare
foreach ($m in "20260921T100000Z", "20260922T100000Z", "20260923T100000Z") {
  Assert ($inbox -contains "inbox/martin/$nombre/$m.json") "remoto de vuelta: $m.json está en el remoto"
}
# Lo ya enviado no se vuelve a mandar: el primer lote se agregó en un solo commit.
$veces = @(git --git-dir $bare log --format=%H main -- "inbox/martin/$nombre/20260921T100000Z.json").Count
Assert ($veces -eq 1) "lo ya enviado no se re-commitea (commits que tocan el primer lote: $veces)"
$quedan = @(Get-ChildItem -LiteralPath $state -Recurse -File -Filter *.json | Where-Object { $_.Directory.Name -eq "lotes" })
Assert ($quedan.Count -eq 0) "remoto de vuelta: no quedan lotes pendientes (quedan: $($quedan.Name -join ', '))"

# --- Dos devs en carrera: otro push entra entre el fetch y el push, y ninguno pierde nada ---
# La carrera se fuerza con un `pre-push` en el clon privado: la primera vez que el transporte va a
# pushear, el hook pushea antes un lote de otro dev desde un clon aparte. El push del transporte llega
# entonces sobre un `main` que ya avanzó y el remoto lo rechaza.
$t = New-HubRepo
$bare = New-PmRemote
$state = New-TestWorkspace $script:runRoot "hubenv-state"
$nombre = Split-Path $t -Leaf
Enviar $t $state $bare "2026-09-21T10:00:00Z" | Out-Null
$otro = New-TestWorkspace $script:runRoot "hubenv-otro"
git clone -q $bare $otro 2>$null
Set-GitNeutral $otro
[IO.Directory]::CreateDirectory((Join-Path $otro "inbox/manuel/otro-repo")) | Out-Null
"{}" | Set-Content (Join-Path $otro "inbox/manuel/otro-repo/20260922T095959Z.json")
git -C $otro add -A; git -C $otro commit -q -m "lote de manuel"
$hooks = New-TestWorkspace $script:runRoot "hubenv-hooks"
$flag = (Join-Path $hooks "ya").Replace('\', '/')
$hook = @"
#!/bin/sh
[ -f "$flag" ] && exit 0
touch "$flag"
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
git -C "$($otro.Replace('\', '/'))" push -q origin HEAD:main
"@
[IO.File]::WriteAllText((Join-Path $hooks "pre-push"), $hook.Replace("`r`n", "`n"))
git -C (Join-Path $state "pm-repo") config core.hooksPath $hooks.Replace('\', '/')
$r = Enviar $t $state $bare "2026-09-22T10:00:00Z"
Assert (Test-Path -LiteralPath $flag) "carrera: el hook corrió, así que el push del otro dev entró primero"
Assert ($r.exit -eq 0) "carrera: el transporte reintenta y sale en exit 0 (fue $($r.exit); $($r.out))"
$inbox = Get-Inbox $bare
Assert ($inbox -contains "inbox/manuel/otro-repo/20260922T095959Z.json") "carrera: el lote del otro dev sigue en el remoto"
Assert ($inbox -contains "inbox/martin/$nombre/20260922T100000Z.json") "carrera: el lote propio también llegó"

# --- El push rechazado (no el fetch) deja el lote pendiente, y la corrida siguiente lo empuja una sola vez ---
# El remoto está arriba y el fetch anda; lo que falla es cada intento de push, con un `pre-push` que
# siempre sale 1. Así se ejerce el camino entre el commit local y el push, que es donde el lote podía
# pasar a `enviados/` antes de tiempo.
$t = New-HubRepo
$bare = New-PmRemote
$state = New-TestWorkspace $script:runRoot "hubenv-state"
$nombre = Split-Path $t -Leaf
Enviar $t $state $bare "2026-09-21T10:00:00Z" | Out-Null
$hooks = New-TestWorkspace $script:runRoot "hubenv-hooks"
[IO.File]::WriteAllText((Join-Path $hooks "pre-push"), "#!/bin/sh`nexit 1`n")
$pm = Join-Path $state "pm-repo"
git -C $pm config core.hooksPath $hooks.Replace('\', '/')
$r = Enviar $t $state $bare "2026-09-22T10:00:00Z"
Assert ($r.exit -ne 0) "push rechazado: exit != 0 (fue $($r.exit))"
Assert ((Get-LogLine $state "2026-09-22T10:00:00Z") -match 'falló: .*git push \(intento 3\)') `
  "push rechazado: el log dice que falló el push al tercer intento ('$(Get-LogLine $state "2026-09-22T10:00:00Z")')"
$pendiente = @(Get-ChildItem -LiteralPath (Join-Path (Get-RepoState $state).FullName "lotes") -File -Filter "20260922T100000Z.json" -ErrorAction SilentlyContinue)
Assert ($pendiente.Count -eq 1) "push rechazado: el lote sigue en lotes/"
git -C $pm config --unset core.hooksPath
$r = Enviar $t $state $bare "2026-09-23T10:00:00Z"
Assert ($r.exit -eq 0) "push rechazado, después: exit 0 (fue $($r.exit); $($r.out))"
$veces = @(git --git-dir $bare log --format=%H main -- "inbox/martin/$nombre/20260922T100000Z.json").Count
Assert ($veces -eq 1) "push rechazado, después: el lote pendiente llegó en un solo commit (fueron $veces)"

# --- Un recolector que muere sin lote no es "nada que enviar": el transporte falla y lo deja en el log ---
$t = New-HubRepo
$bare = New-PmRemote
$state = New-TestWorkspace $script:runRoot "hubenv-state"
Enviar $t $state $bare "2026-09-21T10:00:00Z" | Out-Null
# `lotes` como archivo: el recolector no puede crear la carpeta y muere antes de escribir el lote.
$lotesDir = Join-Path (Get-RepoState $state).FullName "lotes"
Remove-Item -LiteralPath $lotesDir -Recurse -Force
[IO.File]::WriteAllText($lotesDir, "no soy una carpeta")
$r = Enviar $t $state $bare "2026-09-22T10:00:00Z"
Assert ($r.exit -ne 0) "recolector muerto: exit != 0 (fue $($r.exit))"
Assert ((Get-LogLine $state "2026-09-22T10:00:00Z") -match 'falló: .*recolector') `
  "recolector muerto: el log tiene la corrida como fallida por el recolector ('$(Get-LogLine $state "2026-09-22T10:00:00Z")')"

# --- Un recolector que falla CON lote: el lote viaja (el tablero lo pone en rojo) y el log no dice ok ---
$t = New-HubRepo
$bare = New-PmRemote
$state = New-TestWorkspace $script:runRoot "hubenv-state"
$nombre = Split-Path $t -Leaf
[IO.File]::WriteAllText((Join-Path $t ".claude/hub-sync.json"), '{ "schemaVersion": 1, "devs": { "martin": [')
$r = Enviar $t $state $bare "2026-09-21T10:00:00Z"
Assert ($r.exit -ne 0) "recolección fallida: exit != 0 (fue $($r.exit))"
Assert ((Get-Inbox $bare) -contains "inbox/martin/$nombre/20260921T100000Z.json") "recolección fallida: su lote igual llega al remoto"
$linea = Get-LogLine $state "2026-09-21T10:00:00Z"
Assert ($linea -match 'falló' -and $linea -notmatch "`tok") "recolección fallida: el log no la da por ok ('$linea')"
Assert ($linea -match 'no es JSON válido') "recolección fallida: el log trae el motivo del lote ('$linea')"

# --- Dos corridas con el mismo momento: la segunda no pisa en el remoto el lote ya enviado ---
# La primera trae una propuesta (`ok`); la segunda, con el mismo -Now, ya no (`sin cambios`). Pisar la
# primera en `inbox/` perdería la propuesta, que la foto ya dio por vista.
$t = New-HubRepo
$bare = New-PmRemote
$state = New-TestWorkspace $script:runRoot "hubenv-state"
$nombre = Split-Path $t -Leaf
Enviar $t $state $bare "2026-09-21T10:00:00Z" | Out-Null
$msg = New-TestTempPath $script:runRoot "msg" ".txt"
[IO.File]::WriteAllText($msg, "slice`n`nSlice-Close: 01 algo")
git -C $t commit -q --allow-empty --author "Dev <m@x.io>" -F $msg
Enviar $t $state $bare "2026-09-22T10:00:00Z" | Out-Null
$r = Enviar $t $state $bare "2026-09-22T10:00:00Z"
Assert ($r.exit -eq 0) "mismo momento: exit 0 (fue $($r.exit); $($r.out))"
$primero = (git --git-dir $bare show "main:inbox/martin/$nombre/20260922T100000Z.json" 2>$null) -join "`n"
Assert ($primero -match '"resultado": "ok"') "mismo momento: el lote ok sigue en el remoto sin pisar"
Assert ((Get-Inbox $bare) -contains "inbox/martin/$nombre/20260922T100000Z-2.json") `
  "mismo momento: el segundo llega con sufijo (hay: $((Get-Inbox $bare) -join ', '))"

# --- Un lote que ya está en el remoto (el push anduvo y la corrida murió antes de moverlo) no traba la cola ---
$t = New-HubRepo
$bare = New-PmRemote
$state = New-TestWorkspace $script:runRoot "hubenv-state"
$nombre = Split-Path $t -Leaf
Enviar $t $state $bare "2026-09-21T10:00:00Z" | Out-Null
$rs = (Get-RepoState $state).FullName
Copy-Item -LiteralPath (Join-Path $rs "enviados/20260921T100000Z.json") -Destination (Join-Path $rs "lotes")
$r = Enviar $t $state $bare "2026-09-22T10:00:00Z"
Assert ($r.exit -eq 0) "ya enviado: exit 0 (fue $($r.exit); $($r.out))"
Assert (@(Get-ChildItem -LiteralPath (Join-Path $rs "lotes") -File).Count -eq 0) "ya enviado: no queda nada pendiente"
Assert ((Get-Inbox $bare) -notcontains "inbox/martin/$nombre/20260921T100000Z-2.json") "ya enviado: no se duplica con sufijo"

# --- Dos corridas con el mismo momento y sin nada nuevo: la segunda no tiene qué commitear y no falla ---
$t = New-HubRepo
$bare = New-PmRemote
$state = New-TestWorkspace $script:runRoot "hubenv-state"
Enviar $t $state $bare "2026-09-21T10:00:00Z" | Out-Null
$antes = @(git --git-dir $bare rev-list main).Count
$r = Enviar $t $state $bare "2026-09-21T10:00:00Z"
Assert ($r.exit -eq 0) "nada nuevo: la segunda corrida sale en exit 0 (fue $($r.exit); $($r.out))"
Assert (@(git --git-dir $bare rev-list main).Count -eq $antes) "nada nuevo: no hay commit en el remoto"

# --- Un clon privado que quedó a mitad de un rebase se recupera solo ---
$t = New-HubRepo
$bare = New-PmRemote
$state = New-TestWorkspace $script:runRoot "hubenv-state"
$nombre = Split-Path $t -Leaf
Enviar $t $state $bare "2026-09-21T10:00:00Z" | Out-Null
$pm = Join-Path $state "pm-repo"
$otro = New-TestWorkspace $script:runRoot "hubenv-otro"
git clone -q $bare $otro 2>$null
Set-GitNeutral $otro
"remoto" | Set-Content (Join-Path $otro "README.md")
git -C $otro commit -q -am "remoto"; git -C $otro push -q origin HEAD:main 2>$null
Set-GitNeutral $pm
"local" | Set-Content (Join-Path $pm "README.md")
git -C $pm commit -q -am "local"; git -C $pm fetch -q origin; git -C $pm rebase -q origin/main 2>$null | Out-Null
Assert (Test-Path -LiteralPath (Join-Path $pm ".git/rebase-merge")) "rebase trabado: el fixture dejó el clon a mitad de un rebase"
$r = Enviar $t $state $bare "2026-09-22T10:00:00Z"
Assert ($r.exit -eq 0) "rebase trabado: la corrida siguiente sale en exit 0 (fue $($r.exit); $($r.out))"
Assert ((Get-Inbox $bare) -contains "inbox/martin/$nombre/20260922T100000Z.json") "rebase trabado: el lote llega igual"
# El checkout -f solo pasa por encima del rebase a medias sin borrarlo; el que queda hace fallar el
# `git rebase` del próximo push rechazado.
Assert (-not (Test-Path -LiteralPath (Join-Path $pm ".git/rebase-merge"))) "rebase trabado: el rebase a medias quedó abortado"

# --- Un lote ilegible en lotes/ no traba la cola: va a invalidos/ y los demás salen ---
$t = New-HubRepo
$bare = New-PmRemote
$state = New-TestWorkspace $script:runRoot "hubenv-state"
$nombre = Split-Path $t -Leaf
Enviar $t $state $bare "2026-09-21T10:00:00Z" | Out-Null
$rs = (Get-RepoState $state).FullName
[IO.File]::WriteAllText((Join-Path $rs "lotes/20260920T000000Z.json"), '{ "schemaVersion": 1, "dev": "mar')
[IO.File]::WriteAllText((Join-Path $rs "lotes/20260920T000001Z.json"), '')
[IO.File]::WriteAllText((Join-Path $rs "lotes/20260920T000002Z.json"), '{ "schemaVersion": 1 }')
[IO.File]::WriteAllText((Join-Path $rs "lotes/20260920T000003Z.json"), '{ "schemaVersion": 1, "dev": "martin" }')
$r = Enviar $t $state $bare "2026-09-22T10:00:00Z"
Assert ($r.exit -eq 0) "lote ilegible: exit 0 (fue $($r.exit); $($r.out))"
Assert ((Get-Inbox $bare) -contains "inbox/martin/$nombre/20260922T100000Z.json") "lote ilegible: el lote bueno llega"
$inv = @(Get-ChildItem -LiteralPath (Join-Path $rs "invalidos") -File -ErrorAction SilentlyContinue | ForEach-Object Name)
Assert ($inv -contains "20260920T000000Z.json" -and $inv -contains "20260920T000001Z.json") `
  "lote ilegible: el cortado y el vacío van a invalidos/ (hay: $($inv -join ', '))"
Assert ($inv -contains "20260920T000002Z.json" -and $inv -contains "20260920T000003Z.json") `
  "lote ilegible: el que no trae dev y el que no trae repo van a invalidos/ (hay: $($inv -join ', '))"
Assert (@(Get-Inbox $bare | Where-Object { $_ -notmatch "^inbox/martin/$([regex]::Escape($nombre))/" }).Count -eq 0) `
  "lote ilegible: nada llega fuera de inbox/martin/$nombre/"
Assert ((Get-LogLine $state "2026-09-22T10:00:00Z") -match 'invalidos') "lote ilegible: el log lo nombra"

# --- Dos corridas sobre el mismo StateDir no se pisan: la segunda espera el candado y, si se vence la
# espera, falla sin correr el recolector ni tocar el clon `pm-repo` que la primera está usando ---
# El test toma el candado compartiendo `ReadWrite`: así lo que rechaza a la corrida es que ELLA pida
# `None`, y no el modo del test. Tomándolo con `None`, un transporte que pidiera `ReadWrite` (o sea, que
# no bloqueara a nadie) sería rechazado igual y el test pasaría en verde sobre un candado que no cierra.
$t = New-HubRepo
$bare = New-PmRemote
$state = New-TestWorkspace $script:runRoot "hubenv-state"
$candado = [IO.File]::Open((Join-Path $state "hub-sync.lock"), 'OpenOrCreate', 'ReadWrite', 'ReadWrite')
try {
  $t0 = [Diagnostics.Stopwatch]::StartNew()
  $out = & pwsh -NoProfile -File $enviar -RepoDir $t -Dev martin -StateDir $state -PmRemote $bare `
    -Now "2026-09-22T10:00:00Z" -EsperaCandado 2 2>&1
  $exit = $LASTEXITCODE
  $t0.Stop()
} finally { $candado.Dispose() }
Assert ($exit -eq 1) "candado tomado: exit 1 (fue $exit; $($out -join ' '))"
Assert ($t0.Elapsed.TotalSeconds -ge 2) "candado tomado: esperó los 2 s antes de rendirse (tardó $([int]$t0.Elapsed.TotalSeconds) s)"
Assert ((Get-LogLine $state "2026-09-22T10:00:00Z") -match 'falló: otra corrida tiene el candado de .+ desde hace más de 2 s') `
  "candado tomado: el log dice por qué ('$(Get-LogLine $state "2026-09-22T10:00:00Z")')"
Assert ((Get-LogLine $state "2026-09-22T10:00:00Z") -match 'esperando el candado') `
  "candado tomado: dijo que estaba esperando antes de rendirse ('$(Get-LogLine $state "2026-09-22T10:00:00Z")')"
Assert (-not (Get-RepoState $state)) "candado tomado: el recolector no corrió (no hay carpeta de estado del repo)"
Assert (-not (Test-Path -LiteralPath (Join-Path $state "pm-repo"))) "candado tomado: no tocó pm-repo"
$r = Enviar $t $state $bare "2026-09-22T10:05:00Z"
Assert ($r.exit -eq 0) "candado liberado: la corrida siguiente anda (exit $($r.exit); $($r.out))"
Assert ((Get-Inbox $bare) -contains "inbox/martin/$(Split-Path $t -Leaf)/20260922T100500Z.json") "candado liberado: su lote llega"

# --- El que encuentra el candado tomado ESPERA: cuando el otro lo suelta, sigue solo ---
# Lo que prueba que hubo contencion es la linea `esperando el candado`, no el reloj: si el transporte
# tarda en arrancar mas de lo que el otro retiene, encuentra el candado libre y el caso no ejercita
# nada. Medir el tiempo no distingue "espero" de "arranco tarde" (los dos dan lo mismo), la linea si.
$t = New-HubRepo
$bare = New-PmRemote
$state = New-TestWorkspace $script:runRoot "hubenv-state"
$lock = Join-Path $state "hub-sync.lock"
$tomado = Join-Path $state "tomado"
$retenedor = Start-Process pwsh -PassThru -WindowStyle Hidden -ArgumentList '-NoProfile', '-Command', `
  "`$f = [IO.File]::Open('$($lock.Replace("'", "''"))', 'OpenOrCreate', 'ReadWrite', 'None'); New-Item -ItemType File '$($tomado.Replace("'", "''"))' | Out-Null; Start-Sleep -Seconds 4; `$f.Dispose()"
try {
  # El tope no es decorativo: un retenedor que muere antes de tomar el candado colgaba la corrida
  # entera en vez de ponerla en rojo (`run-all.ps1` espera a cada suite sin timeout).
  $limite = (Get-Date).AddSeconds(30)
  while (-not (Test-Path -LiteralPath $tomado) -and (Get-Date) -lt $limite -and -not $retenedor.HasExited) {
    Start-Sleep -Milliseconds 100
  }
  if (-not (Test-Path -LiteralPath $tomado)) { throw "el retenedor no tomo el candado (salio: $($retenedor.HasExited))" }
  $out = & pwsh -NoProfile -File $enviar -RepoDir $t -Dev martin -StateDir $state -PmRemote $bare `
    -Now "2026-09-22T11:00:00Z" -EsperaCandado 30 2>&1
  $exit = $LASTEXITCODE
} finally {
  if (-not $retenedor.HasExited) { $retenedor.Kill() }
  $retenedor.WaitForExit()
  $retenedor.Dispose()
}
Assert ($exit -eq 0) "candado esperado: exit 0 (fue $exit; $($out -join ' '))"
Assert ((Get-LogLine $state "2026-09-22T11:00:00Z") -match 'esperando el candado') `
  "candado esperado: encontro el candado tomado y lo dijo ('$(Get-LogLine $state "2026-09-22T11:00:00Z")')"
Assert ((Get-Inbox $bare) -contains "inbox/martin/$(Split-Path $t -Leaf)/20260922T110000Z.json") "candado esperado: su lote llega igual"

# --- El candado sigue tomado durante el push, no sólo al arrancar ---
# Un `pre-push` en el clon privado intenta abrir el candado con `None` en pleno push: si lo consigue, el
# transporte ya lo había soltado y el `pm-repo` queda sin protección justo donde se pisan las corridas.
$t = New-HubRepo
$bare = New-PmRemote
$state = New-TestWorkspace $script:runRoot "hubenv-state"
Enviar $t $state $bare "2026-09-22T12:00:00Z" | Out-Null
$hooks = New-TestWorkspace $script:runRoot "hubenv-hooks"
$veredicto = (Join-Path $hooks "veredicto.txt").Replace('\', '/')
$sonda = Join-Path $hooks "sonda.ps1"
[IO.File]::WriteAllText($sonda, @"
`$estado = try { `$f = [IO.File]::Open('$((Join-Path $state "hub-sync.lock").Replace("'", "''"))', 'Open', 'ReadWrite', 'None'); `$f.Dispose(); 'libre' }
catch [IO.FileNotFoundException] { 'no existe' }
catch { 'tomado' }
Set-Content -LiteralPath '$($veredicto.Replace("'", "''"))' -Value `$estado
"@)
[IO.File]::WriteAllText((Join-Path $hooks "pre-push"),
  "#!/bin/sh`nunset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE`npwsh -NoProfile -File `"$($sonda.Replace('\', '/'))`"`nexit 0`n")
git -C (Join-Path $state "pm-repo") config core.hooksPath $hooks.Replace('\', '/')
$r = Enviar $t $state $bare "2026-09-22T12:05:00Z"
Assert ($r.exit -eq 0) "candado durante el push: la corrida anda (exit $($r.exit); $($r.out))"
Assert (Test-Path -LiteralPath $veredicto) "candado durante el push: la sonda del hook corrió"
Assert ((Get-Content -LiteralPath $veredicto -Raw).Trim() -eq 'tomado') `
  "candado durante el push: el candado seguía tomado ('$(if (Test-Path -LiteralPath $veredicto) { (Get-Content -LiteralPath $veredicto -Raw).Trim() })')"

# --- Un ejecutable que no se puede lanzar (gh sin instalar) deja su línea en el log, no una excepción ---
# El PATH del hijo queda con git y nada más, el mismo recorte que usa review-loop-trigger.tests.ps1:
# así `gh` no se resuelve aunque la máquina lo tenga. El remoto https es lo que hace que el transporte
# llegue a pedirle el token a gh. `pwsh` NO sirve para este caso: Windows lo resuelve por el directorio
# del ejecutable que llama, así que arranca igual con el PATH vacío (medido).
$t = New-HubRepo
$state = New-TestWorkspace $script:runRoot "hubenv-state"
$pwshExe = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
$savedPath = $env:PATH
$env:PATH = Split-Path (Get-Command git).Source
try {
  Assert (-not (Get-Command gh -ErrorAction SilentlyContinue)) "guard: con el PATH recortado gh no se resuelve"
  $out = & $pwshExe -NoProfile -File $enviar -RepoDir $t -Dev martin -StateDir $state `
    -PmRemote "https://github.com/southpointtech/no-existe.git" -Now "2026-09-24T10:00:00Z" 2>&1
  $exit = $LASTEXITCODE
} finally { $env:PATH = $savedPath }
Assert ($exit -eq 1) "gh que no se lanza: exit 1 (fue $exit; $($out -join ' '))"
Assert ((Get-LogLine $state "2026-09-24T10:00:00Z") -match 'falló: no se pudo ejecutar gh') `
  "gh que no se lanza: el log dice que no se pudo ejecutar, no que falte el token ('$(Get-LogLine $state "2026-09-24T10:00:00Z")')"

# --- Contra github.com, sin token de la cuenta pedida: falla antes de tocar la red, y el log dice por qué ---
# El token de la cuenta se le pide a gh. Sin gh instalado este caso no puede correr y se saltea. Los dos
# env vars cortan cualquier prompt de credenciales si un cambio hiciera que la corrida llegue a la red.
if (Get-Command gh -ErrorAction SilentlyContinue) {
  $env:GIT_TERMINAL_PROMPT = '0'; $env:GCM_INTERACTIVE = 'never'
  $t = New-HubRepo
  $state = New-TestWorkspace $script:runRoot "hubenv-state"
  $r = Enviar $t $state "https://github.com/southpointtech/no-existe.git" "2026-09-21T10:00:00Z" -cuenta "cuenta-que-no-existe-xyz"
  Assert ($r.exit -ne 0) "sin token: exit != 0 (fue $($r.exit))"
  Assert ((Get-LogLine $state "2026-09-21T10:00:00Z") -match 'falló: gh no tiene un token de la cuenta cuenta-que-no-existe-xyz') `
    "sin token: el log nombra la cuenta ('$(Get-LogLine $state "2026-09-21T10:00:00Z")')"
  Remove-Item env:GIT_TERMINAL_PROMPT, env:GCM_INTERACTIVE
} else { Write-Host "skip: sin gh no se prueba la cuenta" }

Remove-TestRunRoot $script:runRoot
if ($script:failures -eq 0) { Write-Host "TODOS LOS TESTS PASARON"; exit 0 }
else { Write-Host "$($script:failures) test(s) FALLARON"; exit 1 }
