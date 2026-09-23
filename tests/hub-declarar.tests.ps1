# tests/hub-declarar.tests.ps1 — runner sin Pester. Correr: pwsh -NoProfile -File tests/hub-declarar.tests.ps1
# La declaración de hub-sync (issue 14a): `hub-declarar.ps1` crea o actualiza `.claude/hub-sync.json`
# y anota al dev que lo corre. El juez del formato es el recolector real, no una copia de sus reglas:
# una declaración que escribe hub-declarar tiene que darle un lote, no un `falló`.
$ErrorActionPreference = "Stop"
$repo   = Split-Path $PSScriptRoot -Parent
$scripts = Join-Path $repo "skills/bootstrap-southpoint-project/assets/scaffold/.claude/scripts"
$decl   = Join-Path $scripts "hub-declarar.ps1"
$recol  = Join-Path $scripts "hub-recolectar.ps1"
$script:failures = 0
. (Join-Path $PSScriptRoot "lib\temp-workspace.ps1")
$script:runRoot = New-TestRunRoot "hubdecl"
trap { Remove-TestRunRoot $script:runRoot; break }

function Assert($cond, $msg) {
  if ($cond) { Write-Host "ok:   $msg" } else { Write-Host "FAIL: $msg"; $script:failures++ }
}
# Sin el script, `pwsh -File` sale != 0 con su usage: los casos de falla pasarían en verde sin
# ejercitar nada.
if (-not (Test-Path -LiteralPath $decl)) {
  Remove-TestRunRoot $script:runRoot
  Write-Host "FAIL: no existe hub-declarar en $decl"; exit 1
}

# Repo git temporal con la identidad local `$email` (vacío = sin user.email local). Los fixtures
# heredan el gitconfig global: gpgsign, hooksPath y excludesFile se neutralizan.
function New-Repo([string]$email = "m@x.io") {
  $t = New-TestWorkspace $script:runRoot "hubdecl-repo"
  git -C $t init -q -b master
  if ($email) { git -C $t config user.email $email }
  git -C $t config user.name dev
  git -C $t config commit.gpgsign false
  git -C $t config core.hooksPath ""
  git -C $t config core.excludesFile ""
  "base" | Set-Content (Join-Path $t "file.txt")
  git -C $t add -A; git -C $t commit -q -m base
  return $t
}
$script:gitGlobalVacio = New-TestTempPath $script:runRoot "gitconfig" ".txt"
[IO.File]::WriteAllText($script:gitGlobalVacio, "")
function Ruta-Decl([string]$t) { Join-Path $t ".claude/hub-sync.json" }

# Corre un script con el ambiente controlado. `SOUTHPOINT_GIT_EMAIL` se fija SIEMPRE (vacío = se
# borra): la máquina que corre la suite normalmente la tiene seteada, y heredarla haría que los
# asserts sobre los emails dependan de quién corre los tests.
function Invoke-Pwsh([string]$script, [string[]]$argumentos, [hashtable]$envs = @{}) {
  $psi = [Diagnostics.ProcessStartInfo]::new('pwsh')
  foreach ($a in @('-NoProfile', '-File', $script) + $argumentos) { $psi.ArgumentList.Add($a) }
  $psi.UseShellExecute = $false
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.StandardOutputEncoding = [Text.UTF8Encoding]::new($false)
  $psi.StandardErrorEncoding = [Text.UTF8Encoding]::new($false)
  if (-not $envs.ContainsKey('SOUTHPOINT_GIT_EMAIL')) { $envs['SOUTHPOINT_GIT_EMAIL'] = '' }
  # Lo mismo con el gitconfig global: un repo sin user.email local cae al email global de la
  # máquina, y el caso "sin email" dejaría de serlo.
  if (-not $envs.ContainsKey('GIT_CONFIG_GLOBAL')) { $envs['GIT_CONFIG_GLOBAL'] = $script:gitGlobalVacio }
  $envs['GIT_CONFIG_NOSYSTEM'] = '1'
  foreach ($k in $envs.Keys) {
    if ($envs[$k]) { $psi.Environment[$k] = $envs[$k] } else { [void]$psi.Environment.Remove($k) }
  }
  $p = [Diagnostics.Process]::Start($psi)
  try {
    $err = $p.StandardError.ReadToEndAsync()
    $salida = $p.StandardOutput.ReadToEnd()
    $p.WaitForExit()
    return @{ exit = $p.ExitCode; out = $salida.Trim(); err = $err.Result.Trim() }
  } finally { $p.Dispose() }
}
# Corre hub-declarar y parsea su reporte JSON (o deja `rep` en $null si no lo hay).
function Declarar([string]$t, [string[]]$argumentos, [hashtable]$envs = @{}) {
  $r = Invoke-Pwsh $decl (@('-RepoDir', $t) + $argumentos) $envs
  $r.rep = $null
  if ($r.out) { try { $r.rep = $r.out | ConvertFrom-Json } catch { } }
  return $r
}
# El recolector real sobre la declaración: exit 0 y un lote que no es `falló`.
function Recolector-Acepta([string]$t, [string]$dev) {
  $state = New-TestWorkspace $script:runRoot "hubdecl-state"
  $r = Invoke-Pwsh $recol @('-RepoDir', $t, '-Dev', $dev, '-StateDir', $state, '-Now', '2026-09-23T10:00:00Z')
  if ($r.exit -ne 0 -or -not $r.out -or -not (Test-Path -LiteralPath $r.out)) { return $false }
  $lote = [IO.File]::ReadAllText($r.out) | ConvertFrom-Json -DateKind String
  return ($lote.resultado -ne 'falló')
}

# --- Tracer: sin declaración, -HubProject + -Agregarme la crea y el recolector la acepta ---
$t = New-Repo "m@x.io"
$r = Declarar $t @('-HubProject', 'Proyecto X', '-Agregarme', '-Dev', 'martin')
Assert ($r.exit -eq 0) "crear: exit 0 (fue $($r.exit); $($r.err))"
Assert (Test-Path -LiteralPath (Ruta-Decl $t)) "crear: escribe .claude/hub-sync.json"
Assert ($r.rep.accion -eq 'creada' -and $r.rep.dev -eq 'martin') "crear: reporta accion 'creada' y el dev (fue '$($r.out)')"
Assert (Recolector-Acepta $t 'martin') "crear: el recolector acepta la declaración y le da un lote al dev"

# --- Los emails salen de la identidad git efectiva del repo y de SOUTHPOINT_GIT_EMAIL, sin repetir ---
function Emails-De([string]$t, [string]$dev) {
  $j = [IO.File]::ReadAllText((Ruta-Decl $t)) | ConvertFrom-Json
  return @($j.devs.$dev)
}
# Sin email local, la identidad efectiva es la global: ese es el caso legítimo de dos emails distintos.
$t = New-Repo ""
$global = New-TestTempPath $script:runRoot "gitconfig-global" ".txt"
[IO.File]::WriteAllText($global, "[user]`n`temail = m@x.io`n")
$r = Declarar $t @('-HubProject', 'P', '-Agregarme', '-Dev', 'martin') @{ SOUTHPOINT_GIT_EMAIL = 'm.alt@x.io'; GIT_CONFIG_GLOBAL = $global }
$e = @(Emails-De $t 'martin')
Assert ($r.exit -eq 0 -and $e.Count -eq 2 -and $e[0] -eq 'm@x.io' -and $e[1] -eq 'm.alt@x.io') `
  "emails: el global y el de SOUTHPOINT_GIT_EMAIL, en ese orden (fue '$($e -join ', ')'; exit $($r.exit); $($r.err))"
Assert ((@($r.rep.emails) -join ',') -eq 'm@x.io,m.alt@x.io') "emails: el reporte lista los mismos (fue '$($r.out)')"

# Un email LOCAL distinto de SOUTHPOINT_GIT_EMAIL es la identidad que el Step 5 fijó antes de que la
# PC tuviera la variable: la de servicio, compartida. Declararla le asignaría a este dev los commits
# de cualquiera que la use, así que falla nombrando las dos y no escribe nada.
$t = New-Repo "svc@x.io"
$r = Declarar $t @('-HubProject', 'P', '-Agregarme', '-Dev', 'martin') @{ SOUTHPOINT_GIT_EMAIL = 'dev@x.io' }
Assert ($r.exit -ne 0 -and $r.err -cmatch '^hub-declarar: .*svc@x\.io.*dev@x\.io' -and -not (Test-Path -LiteralPath (Ruta-Decl $t))) `
  "email local distinto de SOUTHPOINT_GIT_EMAIL: falla nombrando los dos y no escribe (exit $($r.exit); '$($r.err)')"
$t = New-Repo "Dev@X.io"
$r = Declarar $t @('-HubProject', 'P', '-Agregarme', '-Dev', 'martin') @{ SOUTHPOINT_GIT_EMAIL = 'dev@x.io' }
Assert ($r.exit -eq 0) "email local igual a SOUTHPOINT_GIT_EMAIL salvo mayúsculas: declara ($($r.err))"

$t = New-Repo "m@x.io"
$r = Declarar $t @('-HubProject', 'P', '-Agregarme', '-Dev', 'martin') @{ SOUTHPOINT_GIT_EMAIL = 'M@X.io' }
$e = @(Emails-De $t 'martin')
Assert ($e.Count -eq 1) "emails: el mismo email con otras mayúsculas no se repite (fue '$($e -join ', ')')"
# Un email solo queda como ARRAY, que es el formato declarado de `devs.<dev>`. El recolector lo lee
# con `@(...)` y aceptaría un texto suelto: lo que este assert cuida es el formato, no al recolector.
$crudo = [IO.File]::ReadAllText((Ruta-Decl $t))
Assert ($crudo -match '"martin":\s*\[') "emails: un solo email queda como array en el archivo (fue: $crudo)"

$t = New-Repo ""
$r = Declarar $t @('-HubProject', 'P', '-Agregarme', '-Dev', 'martin') @{ SOUTHPOINT_GIT_EMAIL = 'solo@env.io' }
$e = @(Emails-De $t 'martin')
Assert ($r.exit -eq 0 -and $e.Count -eq 1 -and $e[0] -eq 'solo@env.io') `
  "emails: sin user.email local alcanza con SOUTHPOINT_GIT_EMAIL (fue '$($e -join ', ')'; exit $($r.exit); $($r.err))"

# --- Agregarse a una declaración que ya existe no toca lo demás ---
function Escribir-Decl([string]$t, [string]$json) {
  [IO.Directory]::CreateDirectory((Join-Path $t ".claude")) | Out-Null
  [IO.File]::WriteAllText((Ruta-Decl $t), $json)
}
$t = New-Repo "m@x.io"
Escribir-Decl $t '{ "schemaVersion": 1, "hubProject": "Proyecto X", "ongoingSupport": "Soporte X", "devs": { "otro": ["o@x.io"] } }'
$r = Declarar $t @('-Agregarme', '-Dev', 'martin')
$j = [IO.File]::ReadAllText((Ruta-Decl $t)) | ConvertFrom-Json
Assert ($r.exit -eq 0 -and $r.rep.accion -eq 'actualizada') "agregarse: exit 0 y accion 'actualizada' (fue '$($r.out)'; $($r.err))"
Assert ((@($j.devs.otro) -join ',') -eq 'o@x.io') "agregarse: el otro dev queda igual (fue '$(@($j.devs.otro) -join ',')')"
Assert ((@($j.devs.martin) -join ',') -eq 'm@x.io') "agregarse: el dev queda anotado con su email"
Assert ($j.hubProject -eq 'Proyecto X' -and $j.ongoingSupport -eq 'Soporte X') `
  "agregarse: hubProject y ongoingSupport se conservan (fue '$($j.hubProject)' / '$($j.ongoingSupport)')"
Assert ((Recolector-Acepta $t 'martin') -and (Recolector-Acepta $t 'otro')) "agregarse: el recolector acepta la declaración para los dos devs"

# Un dev que ya estaba suma los emails nuevos después de los que tenía, sin perder ninguno.
$t = New-Repo "m@x.io"
Escribir-Decl $t '{ "schemaVersion": 1, "hubProject": "P", "devs": { "martin": ["viejo@x.io"] } }'
$r = Declarar $t @('-Agregarme', '-Dev', 'martin')
$e = @(Emails-De $t 'martin')
Assert ($r.exit -eq 0 -and ($e -join ',') -eq 'viejo@x.io,m@x.io') `
  "agregarse de nuevo: suma el email nuevo después de los que ya tenía (fue '$($e -join ',')'; $($r.err))"

# --- Correrlo de nuevo sin nada nuevo no reescribe el archivo ---
# Por bytes y por fecha: si reescribe lo mismo, el bytes-iguales pasa en verde igual, y el costo
# real (un diff de EOL o de formato en un archivo commiteado) no se vería.
$t = New-Repo "m@x.io"
Escribir-Decl $t "{`"schemaVersion`":1,`"hubProject`":`"P`",`"devs`":{`"martin`":[`"m@x.io`"]}}"
$antes = [IO.File]::ReadAllBytes((Ruta-Decl $t))
[IO.File]::SetLastWriteTimeUtc((Ruta-Decl $t), [DateTime]::new(2020, 1, 1, 0, 0, 0, [DateTimeKind]::Utc))
$r = Declarar $t @('-Agregarme', '-Dev', 'martin')
$despues = [IO.File]::ReadAllBytes((Ruta-Decl $t))
Assert ($r.exit -eq 0 -and $r.rep.accion -eq 'sin-cambios') "sin cambios: exit 0 y accion 'sin-cambios' (fue '$($r.out)'; $($r.err))"
Assert ([Convert]::ToBase64String($antes) -eq [Convert]::ToBase64String($despues)) "sin cambios: el archivo queda byte a byte igual"
Assert ([IO.File]::GetLastWriteTimeUtc((Ruta-Decl $t)).Year -eq 2020) "sin cambios: el archivo no se reescribe"

# --- -OngoingSupport y -HubProject fijan esos campos; vacíos no escriben nada ---
$t = New-Repo "m@x.io"
$r = Declarar $t @('-HubProject', 'P', '-OngoingSupport', 'Soporte P', '-Agregarme', '-Dev', 'martin')
$j = [IO.File]::ReadAllText((Ruta-Decl $t)) | ConvertFrom-Json
Assert ($r.exit -eq 0 -and $j.ongoingSupport -eq 'Soporte P') "ongoingSupport: se escribe si viene (fue '$($j.ongoingSupport)'; $($r.err))"
Assert (Recolector-Acepta $t 'martin') "ongoingSupport: el recolector acepta la declaración que lo trae"

# Vacío no se escribe: el recolector rechaza un ongoingSupport vacío como declaración inválida.
$t = New-Repo "m@x.io"
$r = Declarar $t @('-HubProject', 'P', '-OngoingSupport', '', '-Agregarme', '-Dev', 'martin')
$j = [IO.File]::ReadAllText((Ruta-Decl $t)) | ConvertFrom-Json
Assert ($r.exit -eq 0 -and $null -eq $j.PSObject.Properties['ongoingSupport']) "ongoingSupport vacío: no se escribe ($($r.err))"
Assert (Recolector-Acepta $t 'martin') "ongoingSupport vacío: el recolector acepta la declaración"

$t = New-Repo "m@x.io"
Escribir-Decl $t '{ "schemaVersion": 1, "hubProject": "Viejo", "devs": { "otro": ["o@x.io"] } }'
$r = Declarar $t @('-HubProject', 'Nuevo')
$j = [IO.File]::ReadAllText((Ruta-Decl $t)) | ConvertFrom-Json
Assert ($r.exit -eq 0 -and $r.rep.accion -eq 'actualizada' -and $j.hubProject -eq 'Nuevo') `
  "hubProject: se actualiza sobre una declaración existente (fue '$($j.hubProject)', '$($r.out)'; $($r.err))"
Assert ((@($j.devs.otro) -join ',') -eq 'o@x.io' -and $null -eq $j.devs.PSObject.Properties['martin']) `
  "hubProject: sin -Agregarme, los devs quedan como estaban"

# --- Lo que no puede declararse falla sin escribir ---
# Cada caso chequea exit != 0, un motivo en stderr y el archivo intacto (o ausente): un exit != 0
# solo lo da también un script que tira por cualquier otra cosa.
$t = New-Repo "m@x.io"
$r = Declarar $t @('-Agregarme', '-Dev', 'martin')
Assert ($r.exit -ne 0 -and $r.err -match 'HubProject' -and -not (Test-Path -LiteralPath (Ruta-Decl $t))) `
  "sin declaración ni -HubProject: falla nombrando -HubProject y no crea nada (exit $($r.exit); '$($r.err)')"

$t = New-Repo "m@x.io"
Escribir-Decl $t '{ "schemaVersion": 1, "hubProject": '
$antes = [IO.File]::ReadAllBytes((Ruta-Decl $t))
$r = Declarar $t @('-Agregarme', '-Dev', 'martin')
# `-cmatch` anclado al prefijo del script: un `-match 'JSON'` también lo cumple el error sin atrapar de
# ConvertFrom-Json, y la ruta del archivo (`hub-sync.json`). El acento pide que stderr salga en UTF-8.
Assert ($r.exit -ne 0 -and $r.err -cmatch '^hub-declarar: .*no es JSON válido' -and
        [Convert]::ToBase64String($antes) -eq [Convert]::ToBase64String([IO.File]::ReadAllBytes((Ruta-Decl $t)))) `
  "JSON roto: falla diciendo que no es JSON válido y no lo pisa (exit $($r.exit); '$($r.err)')"

$t = New-Repo "m@x.io"
Escribir-Decl $t '{ "schemaVersion": 1, "hubProject": "P", "devs": ["m@x.io"] }'
$r = Declarar $t @('-Agregarme', '-Dev', 'martin')
Assert ($r.exit -ne 0 -and $r.err -match 'devs') "devs que no es un objeto: falla nombrando devs (exit $($r.exit); '$($r.err)')"

$t = New-Repo ""
$r = Declarar $t @('-HubProject', 'P', '-Agregarme', '-Dev', 'martin')
Assert ($r.exit -ne 0 -and $r.err -match 'email' -and -not (Test-Path -LiteralPath (Ruta-Decl $t))) `
  "sin ningún email: falla nombrando el email y no crea nada (exit $($r.exit); '$($r.err)')"

# --- Un texto de solo espacios cuenta como vacío ---
# Con `''` pasa igual con o sin `.Trim()`: sólo los espacios distinguen la guarda.
$t = New-Repo "m@x.io"
$r = Declarar $t @('-HubProject', '   ', '-Agregarme', '-Dev', 'martin')
Assert ($r.exit -ne 0 -and -not (Test-Path -LiteralPath (Ruta-Decl $t))) `
  "hubProject de espacios al crear: falla y no crea nada (exit $($r.exit); '$($r.err)')"

$t = New-Repo "m@x.io"
Escribir-Decl $t '{"schemaVersion":1,"hubProject":"Viejo","devs":{"martin":["m@x.io"]}}'
$antes = [IO.File]::ReadAllBytes((Ruta-Decl $t))
$r = Declarar $t @('-HubProject', '   ', '-OngoingSupport', '   ', '-Agregarme', '-Dev', 'martin')
Assert ($r.exit -eq 0 -and $r.rep.accion -eq 'sin-cambios' -and
        [Convert]::ToBase64String($antes) -eq [Convert]::ToBase64String([IO.File]::ReadAllBytes((Ruta-Decl $t)))) `
  "hubProject y ongoingSupport de espacios: no tocan la declaración (fue '$($r.out)'; $($r.err))"

$t = New-Repo "m@x.io"
$r = Declarar $t @('-HubProject', ' P ', '-Agregarme', '-Dev', 'martin')
$j = [IO.File]::ReadAllText((Ruta-Decl $t)) | ConvertFrom-Json
Assert ($j.hubProject -ceq 'P') "hubProject con espacios alrededor: se escribe recortado (fue '$($j.hubProject)')"

# --- Sin -Dev, la clave es el usuario de Windows: la misma que usa la tarea diaria ---
$t = New-Repo "m@x.io"
$r = Declarar $t @('-HubProject', 'P', '-Agregarme') @{ USERNAME = 'fulano' }
Assert ($r.exit -eq 0 -and $r.rep.dev -eq 'fulano' -and (Recolector-Acepta $t 'fulano')) `
  "sin -Dev: anota al usuario de Windows y el recolector lo acepta (fue '$($r.out)'; $($r.err))"

# --- Las claves se buscan sin distinguir mayúsculas, como el recolector ---
# Una segunda clave que sólo difiere en mayúsculas hace que ConvertFrom-Json rechace el archivo
# entero, y el recolector falla para TODOS los devs del repo.
$t = New-Repo "m@x.io"
Escribir-Decl $t '{ "schemaVersion": 1, "HubProject": "P", "Devs": { "Marti": ["viejo@x.io"] } }'
$r = Declarar $t @('-HubProject', 'Nuevo', '-Agregarme', '-Dev', 'marti')
$crudo = [IO.File]::ReadAllText((Ruta-Decl $t))
$j = $crudo | ConvertFrom-Json
Assert ($r.exit -eq 0 -and $j.HubProject -eq 'Nuevo' -and (@($j.Devs.Marti) -join ',') -eq 'viejo@x.io,m@x.io') `
  "mayúsculas: reusa las claves que ya estaban (fue: $crudo; $($r.err))"
Assert ((Recolector-Acepta $t 'marti')) "mayúsculas: el recolector acepta el resultado"

# --- Lo que el recolector rechazaría no se da por declarado ---
# Aunque el dev ya figure (el camino de `sin-cambios`), y sin tocar el archivo.
$t = New-Repo "m@x.io"
Escribir-Decl $t '{ "schemaVersion": 1, "devs": { "martin": ["m@x.io"] } }'
$antes = [IO.File]::ReadAllBytes((Ruta-Decl $t))
$r = Declarar $t @('-Agregarme', '-Dev', 'martin')
Assert ($r.exit -ne 0 -and $r.err -cmatch '^hub-declarar: .*hubProject' -and
        [Convert]::ToBase64String($antes) -eq [Convert]::ToBase64String([IO.File]::ReadAllBytes((Ruta-Decl $t)))) `
  "declaración sin hubProject: falla nombrándolo y no la toca (exit $($r.exit); '$($r.err)')"
$r = Declarar $t @('-HubProject', 'P', '-Agregarme', '-Dev', 'martin')
Assert ($r.exit -eq 0 -and (Recolector-Acepta $t 'martin')) "declaración sin hubProject: -HubProject la repara ($($r.err))"

# Un fixture por regla: con dos reglas rotas a la vez, borrar cualquiera de las dos deja la otra
# fallando y el caso en verde. Sin -HubProject ni -OngoingSupport, que pisarían el campo roto.
foreach ($caso in @(
    @{ regla = 'schemaVersion';  json = '{ "schemaVersion": 2, "hubProject": "P", "devs": { "martin": ["m@x.io"] } }' }
    @{ regla = 'ongoingSupport'; json = '{ "schemaVersion": 1, "hubProject": "P", "ongoingSupport": "", "devs": { "martin": ["m@x.io"] } }' }
    @{ regla = 'hubProject';     json = '{ "schemaVersion": 1, "hubProject": "   ", "devs": { "martin": ["m@x.io"] } }' })) {
  $t = New-Repo "m@x.io"
  Escribir-Decl $t $caso.json
  $antes = [IO.File]::ReadAllBytes((Ruta-Decl $t))
  $r = Declarar $t @('-Agregarme', '-Dev', 'martin')
  Assert ($r.exit -ne 0 -and $r.err -cmatch "^hub-declarar: .*$($caso.regla)" -and
          [Convert]::ToBase64String($antes) -eq [Convert]::ToBase64String([IO.File]::ReadAllBytes((Ruta-Decl $t)))) `
    "$($caso.regla) inválido en la declaración: falla nombrándolo y no la toca (exit $($r.exit); '$($r.err)')"
}

# --- upgrade-bootstrap trae la recolección a un repo bootstrapeado antes de hub-sync ---
# El proyecto sale del scaffold real (copy-scaffold) y se lo retrocede a "antes de hub-sync": sin los
# scripts y sin sus entradas en el manifest. compare-scaffold tiene que listarlos como `missing`, que
# es lo que el paso 4 de upgrade-bootstrap copia. Si uno falta del manifest canónico (un gen-manifest
# olvidado), el upgrade no lo trae y este caso se pone rojo.
$skillSp = Join-Path $repo "skills/bootstrap-southpoint-project"
$proj = New-TestWorkspace $script:runRoot "hubdecl-proj"
pwsh -NoProfile -File (Join-Path $skillSp "scripts/copy-scaffold.ps1") -SkillDir $skillSp -ProjectDir $proj | Out-Null
$hubScripts = @('.claude/scripts/hub-declarar.ps1', '.claude/scripts/hub-enviar.ps1', '.claude/scripts/hub-recolectar.ps1')
$manPath = Join-Path $proj ".bootstrap-manifest.json"
$man = [IO.File]::ReadAllText($manPath) | ConvertFrom-Json -AsHashtable
foreach ($h in $hubScripts) {
  [void]$man.files.Remove($h)
  Remove-Item -LiteralPath (Join-Path $proj $h) -ErrorAction SilentlyContinue
}
[IO.File]::WriteAllText($manPath, (ConvertTo-Json -InputObject $man -Depth 5))
$cmp = pwsh -NoProfile -File (Join-Path $repo "skills/upgrade-bootstrap/scripts/compare-scaffold.ps1") `
  -ProjectDir $proj -CanonicalScaffold (Join-Path $skillSp "assets/scaffold") | Out-String | ConvertFrom-Json
foreach ($h in $hubScripts) {
  Assert (@($cmp.missing) -contains $h) "upgrade: compare-scaffold lista $h como missing"
}
Assert (@($cmp.missing).Count -eq $hubScripts.Count) `
  "upgrade: lo único que falta son los scripts de hub-sync (missing: $(@($cmp.missing) -join ', '))"

Remove-TestRunRoot $script:runRoot
if ($script:failures -eq 0) { Write-Host "TODOS LOS TESTS PASARON"; exit 0 }
else { Write-Host "$($script:failures) test(s) FALLARON"; exit 1 }
