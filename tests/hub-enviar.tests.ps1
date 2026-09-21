# tests/hub-enviar.tests.ps1 — runner sin Pester. Correr: pwsh -NoProfile -File tests/hub-enviar.tests.ps1
# El transporte de hub-sync (issue 04): corre el recolector y empuja los lotes pendientes a
# `inbox/<dev>/<repo>/` del repo PROJECT MANAGEMENT. Fixtures: un repo recolectable y un repo bare
# local que hace de remoto de PROJECT MANAGEMENT. La cuenta southpointtech no se ejercita acá: sólo se
# usa contra github.com, y eso es QA manual.
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
function Enviar([string]$t, [string]$state, [string]$remote, [string]$now, [string]$dev = "martin") {
  $out = & pwsh -NoProfile -File $enviar -RepoDir $t -Dev $dev -StateDir $state -PmRemote $remote -Now $now 2>&1
  return @{ exit = $LASTEXITCODE; out = ($out -join "`n") }
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
# El remoto se cae: el clon privado ya existe, así que lo que falla es el fetch/push, no el clone.
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

Remove-TestRunRoot $script:runRoot
if ($script:failures -eq 0) { Write-Host "TODOS LOS TESTS PASARON"; exit 0 }
else { Write-Host "$($script:failures) test(s) FALLARON"; exit 1 }
