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
  $envs['GIT_CONFIG_GLOBAL'] = $script:gitGlobalVacio
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

# --- Los emails salen de la identidad git del repo y de SOUTHPOINT_GIT_EMAIL, sin repetir ---
function Emails-De([string]$t, [string]$dev) {
  $j = [IO.File]::ReadAllText((Ruta-Decl $t)) | ConvertFrom-Json
  return @($j.devs.$dev)
}
$t = New-Repo "m@x.io"
$r = Declarar $t @('-HubProject', 'P', '-Agregarme', '-Dev', 'martin') @{ SOUTHPOINT_GIT_EMAIL = 'm.alt@x.io' }
$e = @(Emails-De $t 'martin')
Assert ($r.exit -eq 0 -and $e.Count -eq 2 -and $e[0] -eq 'm@x.io' -and $e[1] -eq 'm.alt@x.io') `
  "emails: el del repo y el de SOUTHPOINT_GIT_EMAIL, en ese orden (fue '$($e -join ', ')'; exit $($r.exit); $($r.err))"
Assert ((@($r.rep.emails) -join ',') -eq 'm@x.io,m.alt@x.io') "emails: el reporte lista los mismos (fue '$($r.out)')"

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

Remove-TestRunRoot $script:runRoot
if ($script:failures -eq 0) { Write-Host "TODOS LOS TESTS PASARON"; exit 0 }
else { Write-Host "$($script:failures) test(s) FALLARON"; exit 1 }
