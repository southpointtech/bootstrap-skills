# tests/hub-recolectar.tests.ps1 — runner sin Pester. Correr: pwsh -NoProfile -File tests/hub-recolectar.tests.ps1
# El recolector de hub-sync (issues 03 y 08): lee los commits del dev con trailer `Slice-Close:` y las
# transiciones de `Status:` de `.scratch/`, y escribe un lote JSON por corrida. Fixtures: repos git temporales con su declaración `.claude/hub-sync.json`.
$ErrorActionPreference = "Stop"
$repo  = Split-Path $PSScriptRoot -Parent
$recol = Join-Path $repo "skills/bootstrap-southpoint-project/assets/scaffold/.claude/scripts/hub-recolectar.ps1"
$script:failures = 0
. (Join-Path $PSScriptRoot "lib\temp-workspace.ps1")
. (Join-Path $PSScriptRoot "lib\consola-propia.ps1")
$script:runRoot = New-TestRunRoot "hubrec"
trap { Remove-TestRunRoot $script:runRoot; break }

function Assert($cond, $msg) {
  if ($cond) { Write-Host "ok:   $msg" } else { Write-Host "FAIL: $msg"; $script:failures++ }
}
# Sin el script, `pwsh -File` imprime su usage y sale con código != 0: los asserts de "sin lote"
# pasarían en verde sin ejercitar nada.
if (-not (Test-Path -LiteralPath $recol)) {
  Remove-TestRunRoot $script:runRoot
  Write-Host "FAIL: no existe el recolector en $recol"; exit 1
}

# Los fixtures heredan el gitconfig global: gpgsign, hooksPath y excludesFile se neutralizan (mismo
# motivo que en review-marker.tests.ps1).
# `-SinDeclaracion` y no `-decl ""`: un `[string]` nunca es $null en PowerShell (se coacciona a ""),
# así que "sin declaración" necesita su propio switch.
# `-Dir` fija la carpeta del repo: el caso de dos repos con el mismo nombre de carpeta la necesita.
function New-HubRepo([string]$decl = "", [switch]$SinDeclaracion, [string]$Dir = "") {
  $t = if ($Dir) { [IO.Directory]::CreateDirectory($Dir).FullName } else { New-TestWorkspace $script:runRoot "hubrec-repo" }
  git -C $t init -q -b master
  git -C $t config user.email otro@x.io
  git -C $t config user.name otro
  git -C $t config commit.gpgsign false
  git -C $t config core.hooksPath ""
  git -C $t config core.excludesFile ""
  if (-not $decl) {
    $decl = '{ "schemaVersion": 1, "hubProject": "Proyecto X", "devs": { "martin": ["m@x.io", "m.alt@x.io"] } }'
  }
  if (-not $SinDeclaracion) {
    [IO.Directory]::CreateDirectory((Join-Path $t ".claude")) | Out-Null
    [IO.File]::WriteAllText((Join-Path $t ".claude/hub-sync.json"), $decl)
  }
  "base" | Set-Content (Join-Path $t "file.txt")
  git -C $t add -A; git -C $t commit -q -m base
  return $t
}
# Un commit vacío con autor explícito y, opcionalmente, el trailer. Por defecto con la forma real del
# workflow: `Slice-Close:` y después, tras una línea en blanco, el `Co-Authored-By:`. Ahí el
# `Slice-Close:` queda en el penúltimo párrafo, donde el parser de trailers de git no lo ve. Con
# `-TrailerAlFinal` va en el último párrafo, la forma que sí ve.
function Commit([string]$t, [string]$subject, [string]$email = "m@x.io", [string]$slice = $null, [switch]$TrailerAlFinal) {
  $msg = if (-not $slice) { $subject }
         elseif ($TrailerAlFinal) { "$subject`n`nSlice-Close: $slice" }
         else { "$subject`n`nSlice-Close: $slice`n`nCo-Authored-By: Claude <noreply@anthropic.com>" }
  $f = New-TestTempPath $script:runRoot "msg" ".txt"
  [IO.File]::WriteAllText($f, $msg)
  git -C $t commit -q --allow-empty --author "Dev <$email>" -F $f
  return (git -C $t rev-parse HEAD).Trim()
}
# Corre el recolector y devuelve el lote que escribió (o $null), con exit code y stdout.
# La salida se decodifica como UTF-8 acá, por `StandardOutputEncoding`, y NO fijando
# `[Console]::OutputEncoding`: esa propiedad es de la CONSOLA, no del proceso, y bajo `run-all.ps1`
# —cuatro suites en paralelo en la misma consola— se la deja puesta a las demás (issue 15).
# El caso que necesita un ambiente que no sea UTF-8, el del asunto con acentos, usa
# `Invoke-EnConsolaPropia`: le da al hijo una consola propia que muere con él.
function Recolectar([string]$t, [string]$state, [string]$now, [string]$dev = "martin") {
  $psi = [Diagnostics.ProcessStartInfo]::new('pwsh')
  foreach ($a in '-NoProfile', '-File', $recol, '-RepoDir', $t, '-Dev', $dev, '-StateDir', $state, '-Now', $now) {
    $psi.ArgumentList.Add($a)
  }
  $psi.UseShellExecute = $false
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.StandardOutputEncoding = [Text.UTF8Encoding]::new($false)
  $psi.StandardErrorEncoding = [Text.UTF8Encoding]::new($false)
  $p = [Diagnostics.Process]::Start($psi)
  try {
    # En paralelo: leer los dos canales en serie puede trabar al hijo si se le llena el otro buffer.
    $err = $p.StandardError.ReadToEndAsync()
    $salida = $p.StandardOutput.ReadToEnd()
    $p.WaitForExit()
    $r = @{ exit = $p.ExitCode; out = $salida.Trim(); err = $err.Result.Trim(); lote = $null }
  } finally { $p.Dispose() }
  if ($r.out -and (Test-Path -LiteralPath $r.out)) {
    $r.lote = [IO.File]::ReadAllText($r.out) | ConvertFrom-Json -DateKind String
  }
  return $r
}

# El mismo lote, pero con el recolector corriendo en una consola que NO es UTF-8 (lo que ve una
# Scheduled Task en una máquina en 850). Es lo que mata el mutante de la decodificación: sin el
# `Invoke-GitUtf8` del script, el asunto con acentos llega deformado al lote.
function Recolectar-En850([string]$t, [string]$state, [string]$now, [string]$dev = "martin") {
  $r = Invoke-EnConsolaPropia -RunRoot $script:runRoot -Script $recol -Cp 850 `
    -Argumentos @('-RepoDir', $t, '-Dev', $dev, '-StateDir', $state, '-Now', $now)
  $res = @{ exit = $r.exit; out = $r.out.Trim(); err = $r.err; lote = $null }
  if ($res.out -and (Test-Path -LiteralPath $res.out)) {
    $res.lote = [IO.File]::ReadAllText($res.out) | ConvertFrom-Json -DateKind String
  }
  return $res
}

# --- Tracer: la primera corrida fija la línea de base y no propone el histórico ---
$t = New-HubRepo
Commit $t "slice viejo" -slice "01 algo" | Out-Null
$state = New-TestWorkspace $script:runRoot "hubrec-state"
$r = Recolectar $t $state "2026-09-19T10:00:00Z"
Assert ($r.exit -eq 0) "primera corrida: exit 0 (fue $($r.exit))"
Assert ($null -ne $r.lote) "primera corrida: escribe un lote e imprime su ruta (stdout: '$($r.out)')"
Assert ($r.lote.resultado -eq "sin cambios") "primera corrida: resultado 'sin cambios' (fue '$($r.lote.resultado)')"
Assert (@($r.lote.propuestas).Count -eq 0) "primera corrida: no propone el Slice-Close previo a la línea de base"
Assert ($r.lote.schemaVersion -eq 1 -and $r.lote.dev -eq "martin" -and $r.lote.momento -eq "2026-09-19T10:00:00Z") `
  "el lote lleva schemaVersion, dev y momento"
Assert ($r.lote.hubProject -eq "Proyecto X" -and $r.lote.repo -eq (Split-Path $t -Leaf)) `
  "el lote lleva el repo y el hubProject de la declaración (fue '$($r.lote.hubProject)')"
# El nombre del lote sale del momento: es lo que el transporte (issue 04) usa para no pisar lotes.
Assert ((Split-Path $r.out -Leaf) -eq "20260919T100000Z.json" -and (Split-Path (Split-Path $r.out -Parent) -Leaf) -eq "lotes") `
  "el lote se llama por su momento, dentro de lotes/ (fue '$($r.out)')"
Assert ($null -eq $r.lote.PSObject.Properties['ongoingSupport']) "sin ongoingSupport declarado, el lote no lo lleva"

# --- Un Slice-Close del dev después de la línea de base es una propuesta `update` ---
# El asunto lleva acentos a propósito y esta corrida va en una consola en 850: pwsh decodifica la
# salida de git con la página de códigos de la consola, así que sin el `Invoke-GitUtf8` del script el
# asunto llega deformado al lote. Es el único caso que necesita ese ambiente, y por eso es el único
# que paga una consola propia.
$sha = Commit $t "recolección de años" -slice "03 recolector"
$r = Recolectar-En850 $t $state "2026-09-20T10:00:00Z"
$p = @($r.lote.propuestas)
Assert ($r.exit -eq 0 -and $r.lote.resultado -eq "ok") "slice nuevo: resultado 'ok' (fue '$($r.lote.resultado)', exit $($r.exit))"
Assert ($p.Count -eq 1) "slice nuevo: una propuesta (fueron $($p.Count))"
Assert ($p[0].id -eq "commit:$sha") "la propuesta tiene id estable derivado del SHA (fue '$($p[0].id)')"
Assert ($p[0].tipo -eq "update" -and $p[0].destino -eq "delivery" -and $p[0].estado -eq "nueva") `
  "la propuesta es un update nuevo con destino delivery"
Assert ($p[0].hechos.sha -eq $sha -and $p[0].hechos.sliceClose -eq "03 recolector") "los hechos traen el SHA y el trailer"
Assert ($p[0].hechos.asunto -ceq "recolección de años") "el asunto llega sin deformar (fue '$($p[0].hechos.asunto)')"
Assert ($p[0].hechos.fecha -match '^\d{4}-\d{2}-\d{2}T') "los hechos traen la fecha del commit (fue '$($p[0].hechos.fecha)')"

# --- Qué entra y qué no: trailer, autor, email secundario; y no se repite lo ya propuesto ---
# Varios días sin correr (la PC apagada) salen juntos en el lote siguiente.
$sinTrailer = Commit $t "sin trailer"
$ajeno      = Commit $t "de otro dev" -email "otro@x.io" -slice "04 ajeno"
$alt        = Commit $t "desde la otra cuenta" -email "m.alt@x.io" -slice "05 alt" -TrailerAlFinal
$propio     = Commit $t "otro slice" -slice "06 propio"
$r = Recolectar $t $state "2026-09-23T10:00:00Z"
$ids = @(@($r.lote.propuestas) | ForEach-Object { $_.id })
Assert ($ids -notcontains "commit:$sinTrailer") "un commit del dev sin Slice-Close no se propone"
Assert ($ids -notcontains "commit:$ajeno") "un Slice-Close de otro autor no se propone"
Assert ($ids -contains "commit:$alt") "un Slice-Close con el email secundario del dev se propone"
Assert ($ids -contains "commit:$propio") "los slices de varios días salen juntos en un lote"
Assert ($ids -notcontains "commit:$sha") "lo propuesto en una corrida anterior no se repite"
Assert ($ids.Count -eq 2) "el lote trae exactamente los dos slices nuevos (fueron $($ids.Count))"

# --- Otra rama: la recolección no depende de la rama en la que está parado el repo ---
git -C $t checkout -q -b feat/otra
$enRama = Commit $t "slice en otra rama" -slice "07 rama"
git -C $t checkout -q master
$r = Recolectar $t $state "2026-09-24T10:00:00Z"
Assert (@(@($r.lote.propuestas) | ForEach-Object { $_.id }) -contains "commit:$enRama") `
  "un Slice-Close en una rama que no es la actual se propone"
$r = Recolectar $t $state "2026-09-25T10:00:00Z"
Assert ($r.lote.resultado -eq "sin cambios" -and @($r.lote.propuestas).Count -eq 0) `
  "sin commits nuevos: lote 'sin cambios' (fue '$($r.lote.resultado)')"

# --- Sin declaración, o un dev que no figura en ella: el repo se saltea sin lote ---
# Se mira el StateDir entero, no sólo el stdout: un lote escrito sin imprimir su ruta también es un
# lote de más.
$t2 = New-HubRepo -SinDeclaracion
$st2 = New-TestWorkspace $script:runRoot "hubrec-state"
$r = Recolectar $t2 $st2 "2026-09-19T10:00:00Z"
Assert ($r.exit -eq 0 -and -not $r.out) "sin declaración: exit 0 y nada en stdout (exit $($r.exit), stdout '$($r.out)')"
Assert (@(Get-ChildItem -LiteralPath $st2 -Recurse -File).Count -eq 0) "sin declaración: no escribe nada en el StateDir"
$t3 = New-HubRepo
$st3 = New-TestWorkspace $script:runRoot "hubrec-state"
$r = Recolectar $t3 $st3 "2026-09-19T10:00:00Z" -dev "manuel"
Assert ($r.exit -eq 0 -and -not $r.out) "dev ausente de la declaración: exit 0 y nada en stdout (exit $($r.exit), stdout '$($r.out)')"
Assert (@(Get-ChildItem -LiteralPath $st3 -Recurse -File).Count -eq 0) "dev ausente: no escribe nada en el StateDir"

# --- Declaración inválida: lote `falló` con un motivo que nombra el problema, y exit 1 ---
# Cada caso lleva la palabra que el motivo tiene que nombrar: un motivo genérico ("declaración
# inválida") no le dice al PM qué arreglar.
$invalidas = @(
  @{ caso = "JSON roto";            decl = '{ "schemaVersion": 1, "hubProject": ';                               nombra = "JSON" }
  @{ caso = "sin hubProject";       decl = '{ "schemaVersion": 1, "devs": { "martin": ["m@x.io"] } }';          nombra = "hubProject" }
  @{ caso = "sin devs";             decl = '{ "schemaVersion": 1, "hubProject": "P" }';                          nombra = "devs" }
  @{ caso = "dev sin emails";       decl = '{ "schemaVersion": 1, "hubProject": "P", "devs": { "martin": [] } }'; nombra = "martin" }
  @{ caso = "schemaVersion ajeno";  decl = '{ "schemaVersion": 2, "hubProject": "P", "devs": { "martin": ["m@x.io"] } }'; nombra = "schemaVersion" }
  # Un devs que no es objeto no puede pasar por "dev ausente" (exit 0 sin lote): sería una declaración
  # rota que nunca se pone en rojo.
  @{ caso = "devs como lista";      decl = '{ "schemaVersion": 1, "hubProject": "P", "devs": ["m@x.io"] }';     nombra = "devs" }
  @{ caso = "devs como texto";      decl = '{ "schemaVersion": 1, "hubProject": "P", "devs": "martin" }';       nombra = "devs" }
  # Emails en blanco no matchean ningún commit: sin esto la corrida daría `sin cambios` para siempre.
  @{ caso = "email vacío";          decl = '{ "schemaVersion": 1, "hubProject": "P", "devs": { "martin": [""] } }';  nombra = "martin" }
  @{ caso = "email en blanco";      decl = '{ "schemaVersion": 1, "hubProject": "P", "devs": { "martin": ["  "] } }'; nombra = "martin" }
  @{ caso = "ongoingSupport objeto"; decl = '{ "schemaVersion": 1, "hubProject": "P", "ongoingSupport": { "a": 1 }, "devs": { "martin": ["m@x.io"] } }'; nombra = "ongoingSupport" }
)
foreach ($c in $invalidas) {
  $ti = New-HubRepo $c.decl
  $sti = New-TestWorkspace $script:runRoot "hubrec-state"
  $r = Recolectar $ti $sti "2026-09-19T10:00:00Z"
  Assert ($r.exit -eq 1) "$($c.caso): exit 1 (fue $($r.exit))"
  Assert ($r.lote.resultado -eq "falló" -and @($r.lote.propuestas).Count -eq 0) "$($c.caso): lote 'falló' sin propuestas (fue '$($r.lote.resultado)')"
  Assert ("$($r.lote.motivo)" -match [regex]::Escape($c.nombra)) "$($c.caso): el motivo nombra '$($c.nombra)' (fue '$($r.lote.motivo)')"
  # Se busca en todo el StateDir: la carpeta del repo adentro no es su nombre a secas.
  Assert (@(Get-ChildItem -LiteralPath $sti -Recurse -Filter foto.json).Count -eq 0) "$($c.caso): no fija línea de base"
}
# Declaración válida en un directorio que no es un repo git: el motivo es de git, no de la declaración.
$noGit = New-TestWorkspace $script:runRoot "hubrec-repo"
[IO.Directory]::CreateDirectory((Join-Path $noGit ".claude")) | Out-Null
[IO.File]::WriteAllText((Join-Path $noGit ".claude/hub-sync.json"), '{ "schemaVersion": 1, "hubProject": "P", "devs": { "martin": ["m@x.io"] } }')
$r = Recolectar $noGit (New-TestWorkspace $script:runRoot "hubrec-state") "2026-09-19T10:00:00Z"
Assert ($r.exit -eq 1 -and $r.lote.resultado -eq "falló" -and "$($r.lote.motivo)" -match 'git') `
  "sin repo git: lote 'falló' con motivo de git (exit $($r.exit), motivo '$($r.lote.motivo)')"

# --- ongoingSupport declarado llega al lote ---
$tos = New-HubRepo '{ "schemaVersion": 1, "hubProject": "P", "ongoingSupport": "OS X", "devs": { "martin": ["m@x.io"] } }'
$r = Recolectar $tos (New-TestWorkspace $script:runRoot "hubrec-state") "2026-09-19T10:00:00Z"
Assert ($r.exit -eq 0 -and $r.lote.ongoingSupport -eq "OS X") "el ongoingSupport declarado llega al lote (fue '$($r.lote.ongoingSupport)')"

# --- Una foto ilegible es una corrida fallida con lote, no una muerte sin rastro ---
# Una foto a medio escribir (la PC se apagó) no puede trabar el repo en silencio: el tablero sólo ve
# lotes. Y la foto rota no se pisa: re-fijar la línea de base en silencio perdería los slices pendientes.
$tf = New-HubRepo
$stf = New-TestWorkspace $script:runRoot "hubrec-state"
Recolectar $tf $stf "2026-09-19T10:00:00Z" | Out-Null
$foto = @(Get-ChildItem -LiteralPath $stf -Recurse -Filter foto.json)[0].FullName
[IO.File]::WriteAllText($foto, '{ "schemaVersion": 1, "vistos": [')
Commit $tf "slice pendiente" -slice "08 pendiente" | Out-Null
$r = Recolectar $tf $stf "2026-09-20T10:00:00Z"
Assert ($r.exit -eq 1 -and $r.lote.resultado -eq "falló" -and "$($r.lote.motivo)" -match 'foto') `
  "foto ilegible: lote 'falló' con motivo que nombra la foto (exit $($r.exit), motivo '$($r.lote.motivo)')"
Assert ([IO.File]::ReadAllText($foto) -eq '{ "schemaVersion": 1, "vistos": [') "foto ilegible: no se pisa"

# --- Dos repos con el mismo nombre de carpeta no comparten la foto ---
$pa = New-TestWorkspace $script:runRoot "hubrec-pa"
$pb = New-TestWorkspace $script:runRoot "hubrec-pb"
$ra = New-HubRepo -Dir (Join-Path $pa "app")
$rb = New-HubRepo -Dir (Join-Path $pb "app")
Commit $rb "histórico de b" -slice "01 b viejo" | Out-Null
$stab = New-TestWorkspace $script:runRoot "hubrec-state"
Recolectar $ra $stab "2026-09-19T10:00:00Z" | Out-Null
$r = Recolectar $rb $stab "2026-09-19T10:00:01Z"
Assert ($r.lote.resultado -eq "sin cambios") "otro repo con el mismo nombre de carpeta fija su propia línea de base (fue '$($r.lote.resultado)', $(@($r.lote.propuestas).Count) propuestas)"
$nuevoA = Commit $ra "slice de a" -slice "02 a"
$r = Recolectar $ra $stab "2026-09-20T10:00:00Z"
$ids = @(@($r.lote.propuestas) | ForEach-Object { $_.id })
Assert ($ids.Count -eq 1 -and $ids[0] -eq "commit:$nuevoA") "cada repo propone sólo lo suyo nuevo (fueron: $($ids -join ', '))"

# --- Agregar un email a la declaración no re-propone el histórico de esa cuenta ---
$td = New-HubRepo
Commit $td "slice viejo desde otra cuenta" -email "c@d.io" -slice "01 viejo" | Out-Null
$std = New-TestWorkspace $script:runRoot "hubrec-state"
Recolectar $td $std "2026-09-19T10:00:00Z" | Out-Null
[IO.File]::WriteAllText((Join-Path $td ".claude/hub-sync.json"), '{ "schemaVersion": 1, "hubProject": "Proyecto X", "devs": { "martin": ["m@x.io", "c@d.io"] } }')
$r = Recolectar $td $std "2026-09-20T10:00:00Z"
Assert ($r.lote.resultado -eq "sin cambios") "un email agregado después de la línea de base no re-propone su histórico (fue '$($r.lote.resultado)')"

# --- Dos corridas con el mismo momento no se pisan el lote ---
# Si la segunda (`sin cambios`) pisara a la primera (`ok`), sus propuestas se perderían: la foto ya las
# marcó como vistas.
$te = New-HubRepo
$ste = New-TestWorkspace $script:runRoot "hubrec-state"
Recolectar $te $ste "2026-09-19T10:00:00Z" | Out-Null
Commit $te "slice" -slice "09 mismo segundo" | Out-Null
$r1 = Recolectar $te $ste "2026-09-20T10:00:00Z"
$r2 = Recolectar $te $ste "2026-09-20T10:00:00Z"
Assert ($r1.out -and $r2.out -and $r1.out -ne $r2.out) "dos corridas con el mismo momento escriben dos lotes ('$($r1.out)' / '$($r2.out)')"
Assert ((([IO.File]::ReadAllText($r1.out)) | ConvertFrom-Json).resultado -eq "ok") "el primer lote sigue intacto"

# --- Cómo se lee el Slice-Close: como el hook review-loop-trigger, sin distinguir mayúsculas, y sólo
# con un valor en la misma línea ---
$tr = New-HubRepo
$str = New-TestWorkspace $script:runRoot "hubrec-state"
Recolectar $tr $str "2026-09-19T10:00:00Z" | Out-Null
$f = New-TestTempPath $script:runRoot "msg" ".txt"
[IO.File]::WriteAllText($f, "en minúscula`n`nslice-close: 10 minúscula`n`nCo-Authored-By: Claude <noreply@anthropic.com>")
git -C $tr commit -q --allow-empty --author "Dev <m@x.io>" -F $f; $minus = (git -C $tr rev-parse HEAD).Trim()
# Un Slice-Close vacío no es un cierre: sin esto el nombre del slice sería la línea siguiente.
[IO.File]::WriteAllText($f, "vacío con coautor`n`nSlice-Close:`n`nCo-Authored-By: Claude <noreply@anthropic.com>")
git -C $tr commit -q --allow-empty --author "Dev <m@x.io>" -F $f; $vacio1 = (git -C $tr rev-parse HEAD).Trim()
[IO.File]::WriteAllText($f, "vacío con rigor`n`nSlice-Close:`nReview-Rigor: light`n`nCo-Authored-By: Claude <noreply@anthropic.com>")
git -C $tr commit -q --allow-empty --author "Dev <m@x.io>" -F $f; $vacio2 = (git -C $tr rev-parse HEAD).Trim()
$r = Recolectar $tr $str "2026-09-20T10:00:00Z"
$p = @($r.lote.propuestas)
Assert (@($p | Where-Object { $_.id -eq "commit:$minus" }).Count -eq 1) "un 'slice-close:' en minúscula se propone, como lo detecta el hook"
Assert (@($p | Where-Object { $_.id -eq "commit:$vacio1" -or $_.id -eq "commit:$vacio2" }).Count -eq 0) `
  "un Slice-Close sin valor no se propone (propuestas: $(@($p | ForEach-Object { $_.hechos.sliceClose }) -join ' | '))"

# --- Lo que git escribe en stderr con exit 0 no se mezcla con los commits ---
# Un repo con `.git/info/grafts` hace que git log imprima hints de deprecación y salga 0.
$tg = New-HubRepo
$stg = New-TestWorkspace $script:runRoot "hubrec-state"
Recolectar $tg $stg "2026-09-19T10:00:00Z" | Out-Null
$conGrafts = Commit $tg "slice con grafts" -slice "11 grafts"
[IO.File]::WriteAllText((Join-Path $tg ".git/info/grafts"), "$conGrafts`n")
$r = Recolectar $tg $stg "2026-09-20T10:00:00Z"
$ids = @(@($r.lote.propuestas) | ForEach-Object { $_.id })
Assert ($ids.Count -eq 1 -and $ids[0] -ceq "commit:$conGrafts") "con hints de git en stderr, el id sigue siendo el SHA limpio (fue: $($ids -join ' | '))"

# --- Los worktrees de un mismo repo comparten la foto ---
# Si cada worktree tuviera su propia línea de base, un slice commiteado en uno se perdería para el
# otro, o se propondría dos veces.
$tw = New-HubRepo
$stw = New-TestWorkspace $script:runRoot "hubrec-state"
Recolectar $tw $stw "2026-09-19T10:00:00Z" | Out-Null
$wt = Join-Path (New-TestWorkspace $script:runRoot "hubrec-wt") "carril"
git -C $tw worktree add -q -b feat/carril $wt 2>$null
$enWt = Commit $wt "slice en el worktree" -slice "12 worktree"
$r = Recolectar $wt $stw "2026-09-20T10:00:00Z"
$ids = @(@($r.lote.propuestas) | ForEach-Object { $_.id })
Assert ($r.lote.resultado -eq "ok" -and $ids.Count -eq 1 -and $ids[0] -eq "commit:$enWt") `
  "desde un worktree se propone el slice nuevo contra la línea de base del repo (fue '$($r.lote.resultado)': $($ids -join ', '))"
Assert ($r.lote.repo -eq (Split-Path $tw -Leaf)) "el repo del lote es el del checkout principal, no el del worktree (fue '$($r.lote.repo)')"
Assert (@(Get-ChildItem -LiteralPath $stw -Directory).Count -eq 1) "un solo directorio de estado para el repo y su worktree"

# ===== Issue 08: transiciones de `Status:` en `.scratch/` =====
# Un issue de `.scratch/<feature>/issues/`, con el formato real: título, línea en blanco, `Status:`.
function Set-Issue([string]$t, [string]$rel, [string]$status, [string]$titulo = "Un issue") {
  $p = Join-Path $t ".scratch/$rel"
  [IO.Directory]::CreateDirectory((Split-Path $p -Parent)) | Out-Null
  [IO.File]::WriteAllText($p, "# $titulo`r`n`r`nStatus: $status`r`nRepo: X`r`n")
}
function Ids($r) { @(@($r.lote.propuestas) | ForEach-Object { $_.id }) }

# --- Tracer: un issue que pasa a `done` entre dos corridas es una propuesta `hito` ---
$ts = New-HubRepo
Set-Issue $ts "feat-a/issues/01-uno.md" "ready-for-agent" "01 — el primero"
$sts = New-TestWorkspace $script:runRoot "hubrec-state"
Recolectar $ts $sts "2026-09-19T10:00:00Z" | Out-Null
Set-Issue $ts "feat-a/issues/01-uno.md" "done" "01 — el primero"
$r = Recolectar $ts $sts "2026-09-20T10:00:00Z"
$p = @($r.lote.propuestas)
Assert ($r.exit -eq 0 -and $r.lote.resultado -eq "ok" -and $p.Count -eq 1) "→ done: una propuesta y resultado 'ok' (fue '$($r.lote.resultado)', $($p.Count) propuestas, exit $($r.exit))"
Assert ($p[0].id -ceq "issue:feat-a/01-uno.md:done") "→ done: id estable issue + transición (fue '$($p[0].id)')"
Assert ($p[0].tipo -eq "hito" -and $p[0].destino -eq "delivery" -and $p[0].estado -eq "nueva") "→ done: hito nuevo con destino delivery (fue '$($p[0].tipo)'/'$($p[0].destino)'/'$($p[0].estado)')"
Assert ($p[0].hechos.issue -ceq "feat-a/01-uno.md" -and $p[0].hechos.titulo -ceq "01 — el primero" -and
        $p[0].hechos.de -ceq "ready-for-agent" -and $p[0].hechos.a -ceq "done") "→ done: los hechos traen issue, título, de y a"

# --- `→ needs-info` es un `riesgo`: interno hasta que el PM lo reclasifique ---
Set-Issue $ts "feat-a/issues/02-dos.md" "ready-for-agent"
Recolectar $ts $sts "2026-09-21T10:00:00Z" | Out-Null
Set-Issue $ts "feat-a/issues/02-dos.md" "needs-info"
$r = Recolectar $ts $sts "2026-09-22T10:00:00Z"
$p = @($r.lote.propuestas)
Assert ($p.Count -eq 1 -and $p[0].id -ceq "issue:feat-a/02-dos.md:needs-info" -and $p[0].tipo -eq "riesgo" -and $p[0].destino -eq "delivery") `
  "→ needs-info: una propuesta riesgo con destino delivery (fue: $(@($p | ForEach-Object { "$($_.id)/$($_.tipo)" }) -join ', '))"

# --- Lo que no es una transición propuesta ---
# Un issue nuevo no tiene transición aunque ya llegue en `done`: no hay estado anterior con qué
# compararlo. Otros estados, el PRD de la feature (que también lleva `Status:`) y un issue sin
# `Status:` no proponen nada. Uno borrado no rompe la corrida.
Set-Issue $ts "feat-b/issues/01-nuevo.md" "done"
Set-Issue $ts "feat-a/issues/03-tres.md" "ready-for-agent"
Set-Issue $ts "feat-a/issues/04-cuatro.md" "ready-for-agent"
Set-Issue $ts "feat-a/PRD.md" "ready-for-agent"
$r = Recolectar $ts $sts "2026-09-23T10:00:00Z"
Assert ($r.lote.resultado -eq "sin cambios") "un issue nuevo no se propone, aunque ya llegue en done (fue '$($r.lote.resultado)': $((Ids $r) -join ', '))"
$r = Recolectar $ts $sts "2026-09-24T10:00:00Z"
Assert ($r.lote.resultado -eq "sin cambios") "sin transiciones nuevas, lo ya propuesto no se repite (fue '$($r.lote.resultado)': $((Ids $r) -join ', '))"
Set-Issue $ts "feat-a/issues/03-tres.md" "ready-for-human"
Set-Issue $ts "feat-a/PRD.md" "done"
[IO.File]::WriteAllText((Join-Path $ts ".scratch/feat-a/issues/04-cuatro.md"), "# sin estado`r`n")
Remove-Item -LiteralPath (Join-Path $ts ".scratch/feat-a/issues/02-dos.md")
$r = Recolectar $ts $sts "2026-09-25T10:00:00Z"
Assert ($r.exit -eq 0 -and $r.lote.resultado -eq "sin cambios") `
  "otro estado, el PRD, un issue sin Status y uno borrado no proponen nada (fue '$($r.lote.resultado)', exit $($r.exit): $((Ids $r) -join ', '))"
Set-Issue $ts "feat-b/issues/01-nuevo.md" "needs-info"
$r = Recolectar $ts $sts "2026-09-26T10:00:00Z"
Assert ((Ids $r) -contains "issue:feat-b/01-nuevo.md:needs-info") "un issue que nació en la corrida anterior ya se sigue en la siguiente (fue: $((Ids $r) -join ', '))"

# --- Una foto del tramo anterior (sin sección de `.scratch/`) fija la línea de base de `.scratch/` ---
# Los issues que ya estaban en `done` antes de actualizar el recolector no se proponen de golpe.
$tv = New-HubRepo
Set-Issue $tv "feat-a/issues/01-uno.md" "done"
Set-Issue $tv "feat-a/issues/02-dos.md" "ready-for-agent"
$stv = New-TestWorkspace $script:runRoot "hubrec-state"
Recolectar $tv $stv "2026-09-19T10:00:00Z" | Out-Null
$fotoV = @(Get-ChildItem -LiteralPath $stv -Recurse -Filter foto.json)[0].FullName
$vistos = @(([IO.File]::ReadAllText($fotoV) | ConvertFrom-Json).vistos)
[IO.File]::WriteAllText($fotoV, (@{ schemaVersion = 1; vistos = $vistos } | ConvertTo-Json))
$r = Recolectar $tv $stv "2026-09-20T10:00:00Z"
Assert ($r.exit -eq 0 -and $r.lote.resultado -eq "sin cambios") "foto sin sección de .scratch/: fija la línea de base sin proponer (fue '$($r.lote.resultado)', exit $($r.exit): $((Ids $r) -join ', '))"
Set-Issue $tv "feat-a/issues/02-dos.md" "done"
$r = Recolectar $tv $stv "2026-09-21T10:00:00Z"
Assert (((Ids $r) -join ',') -ceq "issue:feat-a/02-dos.md:done") "tras esa línea de base, la transición siguiente se propone (fue: $((Ids $r) -join ', '))"

# --- Con Ongoing Support declarado, el destino sugerido sigue siendo delivery: lo confirma el PM ---
$to = New-HubRepo '{ "schemaVersion": 1, "hubProject": "P", "ongoingSupport": "OS X", "devs": { "martin": ["m@x.io"] } }'
Set-Issue $to "feat-a/issues/01-uno.md" "ready-for-agent"
$sto = New-TestWorkspace $script:runRoot "hubrec-state"
Recolectar $to $sto "2026-09-19T10:00:00Z" | Out-Null
Set-Issue $to "feat-a/issues/01-uno.md" "needs-info"
$r = Recolectar $to $sto "2026-09-20T10:00:00Z"
Assert (@($r.lote.propuestas).Count -eq 1 -and @($r.lote.propuestas)[0].destino -eq "delivery") "con ongoingSupport declarado, el destino sugerido es delivery (fue '$(@($r.lote.propuestas)[0].destino)')"

# --- El hito trae los commits que cerraron el issue: es la misma obra que su `update` ---
# El `Slice-Close:` cita el issue por ruta (issue 07). Sólo los commits del dev, como los `update`.
$tk = New-HubRepo
Set-Issue $tk "feat-a/issues/01-uno.md" "ready-for-agent"
$stk = New-TestWorkspace $script:runRoot "hubrec-state"
Recolectar $tk $stk "2026-09-19T10:00:00Z" | Out-Null
$c1 = Commit $tk "cierra el 01" -slice ".scratch/feat-a/issues/01-uno.md — el uno"
$cAjeno = Commit $tk "otro dev cita el 01" -email "otro@x.io" -slice ".scratch/feat-a/issues/01-uno.md — ajeno"
$cOtro = Commit $tk "cierra otro" -slice ".scratch/feat-a/issues/01-uno.mdx — no es el 01"
Set-Issue $tk "feat-a/issues/01-uno.md" "done"
$r = Recolectar $tk $stk "2026-09-20T10:00:00Z"
$h = @(@($r.lote.propuestas) | Where-Object { $_.tipo -eq "hito" })
Assert ($h.Count -eq 1 -and (@($h[0].hechos.commits) -join ',') -ceq $c1) `
  "el hito trae sólo los commits del dev cuyo Slice-Close cita el issue (fue: $(@($h[0].hechos.commits) -join ', '))"

# --- `.scratch/` es por worktree: se leen todos los del repo, cada uno contra su propia sección ---
# `marcar-done` escribe en el worktree donde corrió el loop, y la tarea programada corre en uno solo.
$tm = New-HubRepo
Set-Issue $tm "feat-a/issues/01-uno.md" "ready-for-agent"
$wtBase = New-TestWorkspace $script:runRoot "hubrec-wt"
$wa = Join-Path $wtBase "carril-a"
git -C $tm worktree add -q -b feat/a $wa 2>$null
Set-Issue $wa "feat-w/issues/01-w.md" "ready-for-agent"
Set-Issue $wa "feat-a/issues/01-uno.md" "ready-for-agent"
$stm = New-TestWorkspace $script:runRoot "hubrec-state"
Recolectar $tm $stm "2026-09-19T10:00:00Z" | Out-Null
Set-Issue $wa "feat-w/issues/01-w.md" "done"
$r = Recolectar $tm $stm "2026-09-20T10:00:00Z"
Assert (((Ids $r) -join ',') -ceq "issue:feat-w/01-w.md:done") "una transición en el .scratch/ de otro worktree se propone (fue: $((Ids $r) -join ', '))"
# Un issue que sólo existe en un worktree nuevo no tiene estado anterior con qué compararlo.
$wb = Join-Path $wtBase "carril-b"
git -C $tm worktree add -q -b feat/b $wb 2>$null
Set-Issue $wb "feat-n/issues/01-n.md" "done"
$r = Recolectar $wa $stm "2026-09-21T10:00:00Z"
Assert ($r.lote.resultado -eq "sin cambios") "un issue que sólo existe en un carril nuevo no se propone, corra desde donde corra (fue '$($r.lote.resultado)': $((Ids $r) -join ', '))"
# La misma transición en dos worktrees es una sola propuesta.
Set-Issue $tm "feat-a/issues/01-uno.md" "needs-info"
Set-Issue $wa "feat-a/issues/01-uno.md" "needs-info"
$r = Recolectar $tm $stm "2026-09-22T10:00:00Z"
Assert (((Ids $r) -join ',') -ceq "issue:feat-a/01-uno.md:needs-info") "la misma transición en dos worktrees sale una sola vez (fue: $((Ids $r) -join ', '))"

# --- Cada worktree contra SU sección, aunque el mismo issue diverja entre worktrees ---
# `marcar-done` escribe sólo en el carril: el mismo issue queda en estados distintos. Main en
# `needs-info` y el carril en `done`, cada uno con su propia sección en la foto: una corrida quieta no
# propone nada, y cuando main cambia se propone SU transición, con su propio `de`.
$td2 = New-HubRepo
Set-Issue $td2 "feat-d/issues/01-div.md" "needs-info"
$wd = Join-Path (New-TestWorkspace $script:runRoot "hubrec-wt") "carril-d"
git -C $td2 worktree add -q -b feat/d $wd 2>$null
Set-Issue $wd "feat-d/issues/01-div.md" "done"
$std2 = New-TestWorkspace $script:runRoot "hubrec-state"
Recolectar $td2 $std2 "2026-09-19T10:00:00Z" | Out-Null
$r = Recolectar $td2 $std2 "2026-09-20T10:00:00Z"
Assert ($r.lote.resultado -eq "sin cambios") "el mismo issue en estados distintos en dos worktrees: una corrida quieta no propone (fue: $((Ids $r) -join ', '))"
Set-Issue $td2 "feat-d/issues/01-div.md" "done"
$r = Recolectar $td2 $std2 "2026-09-21T10:00:00Z"
$p = @($r.lote.propuestas)
Assert (((Ids $r) -join ',') -ceq "issue:feat-d/01-div.md:done") "la transición del worktree principal se propone aunque el carril ya estuviera en done (fue: $((Ids $r) -join ', '))"
Assert ($p.Count -eq 1 -and $p[0].hechos.de -ceq "needs-info") "su 'de' es el estado que registraba SU sección, no el del carril (fue '$($p[0].hechos.de)')"

# --- Un carril que se abre y se cierra entre dos corridas no pierde su hito ---
# `abrir-carril` copia `.scratch/` al carril, y `marcar-done` escribe `done` sólo ahí. La primera vez
# que la corrida ve el carril, el issue ya está en `done`: su estado anterior es el de los otros
# worktrees. Un carril copiado de un main que ya estaba en `done` no propone nada; un issue que sólo
# existe en el carril tampoco (no hay estado anterior con qué compararlo).
$tl = New-HubRepo
Set-Issue $tl "feat-l/issues/01-l.md" "ready-for-agent" "01 — del carril"
Set-Issue $tl "feat-l/issues/02-ya.md" "done"
$stl = New-TestWorkspace $script:runRoot "hubrec-state"
Recolectar $tl $stl "2026-09-19T10:00:00Z" | Out-Null
$wl = Join-Path (New-TestWorkspace $script:runRoot "hubrec-wt") "carril-l"
git -C $tl worktree add -q -b feat/l $wl 2>$null
Set-Issue $wl "feat-l/issues/01-l.md" "done" "01 — del carril"
Set-Issue $wl "feat-l/issues/02-ya.md" "done"
Set-Issue $wl "feat-l/issues/03-solo.md" "done"
$r = Recolectar $tl $stl "2026-09-20T10:00:00Z"
$p = @($r.lote.propuestas)
Assert (((Ids $r) -join ',') -ceq "issue:feat-l/01-l.md:done") "un carril nuevo propone su done contra el estado de los otros worktrees, y nada más (fue: $((Ids $r) -join ', '))"
Assert ($p.Count -eq 1 -and $p[0].hechos.de -ceq "ready-for-agent") "el 'de' de un carril nuevo es el estado que registraba otro worktree (fue '$($p[0].hechos.de)')"
$r = Recolectar $tl $stl "2026-09-21T10:00:00Z"
Assert ($r.lote.resultado -eq "sin cambios") "la corrida siguiente no lo repite (fue: $((Ids $r) -join ', '))"

# --- El estado como lo escriben los repos reales: con backticks, con una nota detrás, en mayúsculas ---
# Los repos mezclan la forma plana (`Status: done`) con la de backticks y nota; `marcar-done` escribe
# siempre la plana, así que sin canonizar su reescritura sería una transición fantasma.
$tb = New-HubRepo
$fb = Join-Path $tb ".scratch/feat-b/issues/01-bt.md"
[IO.Directory]::CreateDirectory((Split-Path $fb -Parent)) | Out-Null
[IO.File]::WriteAllText($fb, "# con backticks`r`n`r`nStatus: ``ready-for-agent`` — arranca el lunes`r`n")
$stb = New-TestWorkspace $script:runRoot "hubrec-state"
Recolectar $tb $stb "2026-09-19T10:00:00Z" | Out-Null
[IO.File]::WriteAllText($fb, "# con backticks`r`n`r`nStatus: ``needs-info`` — esperando al cliente`r`n")
$r = Recolectar $tb $stb "2026-09-20T10:00:00Z"
$p = @($r.lote.propuestas)
Assert ($p.Count -eq 1 -and $p[0].id -ceq "issue:feat-b/01-bt.md:needs-info" -and $p[0].tipo -eq "riesgo" -and $p[0].hechos.de -ceq "ready-for-agent") `
  "un Status con backticks y nota es el estado de su primera palabra (fue: $(@($p | ForEach-Object { "$($_.id) de '$($_.hechos.de)'" }) -join ', '))"
[IO.File]::WriteAllText($fb, "# con backticks`r`n`r`nStatus: ``needs-info`` — sigue esperando`r`n")
$r = Recolectar $tb $stb "2026-09-21T10:00:00Z"
Assert ($r.lote.resultado -eq "sin cambios") "cambiar sólo la nota del Status no es una transición (fue: $((Ids $r) -join ', '))"
[IO.File]::WriteAllText($fb, "# con backticks`r`n`r`nStatus: Done`r`n")
$r = Recolectar $tb $stb "2026-09-22T10:00:00Z"
Assert (((Ids $r) -join ',') -ceq "issue:feat-b/01-bt.md:done") "un Status en mayúsculas da el id canónico en minúsculas (fue: $((Ids $r) -join ', '))"
[IO.File]::WriteAllText($fb, "# con backticks`r`n`r`nStatus: done`r`n")
$r = Recolectar $tb $stb "2026-09-23T10:00:00Z"
Assert ($r.lote.resultado -eq "sin cambios") "cambiar sólo las mayúsculas no es una transición (fue: $((Ids $r) -join ', '))"

# --- `commits` es siempre una lista en el JSON del lote: la ingesta es otro proceso ---
# Se mira el texto crudo: ConvertFrom-Json + @() no distingue `["sha"]` de `"sha"`, ni `[]` de `null`.
Set-Issue $tk "feat-a/issues/01-uno.md" "needs-info"
$r = Recolectar $tk $stk "2026-09-22T10:00:00Z"
Assert ([IO.File]::ReadAllText($r.out) -match ('"commits":\s*\[\s*"' + $c1 + '"\s*\]')) "commits con un solo SHA sale como lista en el JSON"
Set-Issue $ts "feat-a/issues/01-uno.md" "needs-info"
$r = Recolectar $ts $sts "2026-09-28T10:00:00Z"
Assert ([IO.File]::ReadAllText($r.out) -match '"commits":\s*\[\s*\]') "commits sin ningún SHA sale como lista vacía en el JSON"

# --- Un estado CALIFICADO no es ese estado: se registra, pero no propone nada ---
# Formas medidas en `C:\Repos\Outsourcing Development\.scratch\feedback-ali-2026-07-28\issues\`:
# `Status: \`done, pendiente QA manual en web\` (…)` y `\`done en código, pendiente validación\` (…)`.
# El calificador dice que el issue NO está cerrado, así que su primera palabra no es su estado. Y
# saltear el archivo perdería su cierre real: queda registrado con el valor crudo, que no mapea a
# ningún tipo, y su paso posterior a un estado limpio sí se propone.
$tq = New-HubRepo
$fq = Join-Path $tq ".scratch/feat-q/issues/01-q.md"
[IO.Directory]::CreateDirectory((Split-Path $fq -Parent)) | Out-Null
[IO.File]::WriteAllText($fq, "# calificado`r`n`r`nStatus: ``ready-for-agent```r`n")
$stq = New-TestWorkspace $script:runRoot "hubrec-state"
Recolectar $tq $stq "2026-09-19T10:00:00Z" | Out-Null
[IO.File]::WriteAllText($fq, "# calificado`r`n`r`nStatus: ``done, pendiente QA manual en web`` (2026-08-07)`r`n")
$r = Recolectar $tq $stq "2026-09-20T10:00:00Z"
Assert ($r.lote.resultado -eq "sin cambios") "pasar a un done CALIFICADO no propone un hito (fue: $((Ids $r) -join ', '))"
[IO.File]::WriteAllText($fq, "# calificado`r`n`r`nStatus: ``done en código, pendiente validación`` (branch x)`r`n")
$r = Recolectar $tq $stq "2026-09-21T10:00:00Z"
Assert ($r.lote.resultado -eq "sin cambios") "pasar de un calificado a otro tampoco (fue: $((Ids $r) -join ', '))"
[IO.File]::WriteAllText($fq, "# calificado`r`n`r`nStatus: ``done`` (2026-09-22)`r`n")
$r = Recolectar $tq $stq "2026-09-22T10:00:00Z"
$p = @($r.lote.propuestas)
Assert (((Ids $r) -join ',') -ceq "issue:feat-q/01-q.md:done") "el cierre real posterior a un estado calificado sí se propone (fue: $((Ids $r) -join ', '))"
Assert ($p.Count -eq 1 -and $p[0].hechos.de -ceq "``done en código, pendiente validación`` (branch x)") `
  "el 'de' de esa transición es el valor crudo que el estado calificado dejó registrado (fue '$($p[0].hechos.de)')"

# --- Un `Status:` que no es un token limpio se registra crudo, no se descarta ---
# Forma medida en `C:\Repos\SOUTHPOINTLABS\Forecasting App\.scratch\bug-report-form\issues\`:
# `Status: **§2 IMPLEMENTADA** (2026-08-16, …)`. Descartar el archivo lo haría parecer nuevo cuando
# después pase a `done`, y ese hito se perdería en silencio.
$tn2 = New-HubRepo
$fn2 = Join-Path $tn2 ".scratch/feat-n2/issues/01-n2.md"
[IO.Directory]::CreateDirectory((Split-Path $fn2 -Parent)) | Out-Null
[IO.File]::WriteAllText($fn2, "# en negrita`r`n`r`nStatus: **§2 IMPLEMENTADA** (2026-08-16)`r`n")
$stn2 = New-TestWorkspace $script:runRoot "hubrec-state"
Recolectar $tn2 $stn2 "2026-09-19T10:00:00Z" | Out-Null
[IO.File]::WriteAllText($fn2, "# en negrita`r`n`r`nStatus: done`r`n")
$r = Recolectar $tn2 $stn2 "2026-09-20T10:00:00Z"
$p = @($r.lote.propuestas)
Assert (((Ids $r) -join ',') -ceq "issue:feat-n2/01-n2.md:done") "un Status en negrita queda registrado: su done posterior se propone (fue: $((Ids $r) -join ', '))"
Assert ($p.Count -eq 1 -and $p[0].hechos.de -ceq "**§2 IMPLEMENTADA** (2026-08-16)") "el 'de' es el valor crudo del Status que no era un token (fue '$($p[0].hechos.de)')"

# --- La plantilla sin completar (`Status:` en blanco) no es un estado ---
# No fue RED: fija la decisión y mata el mutante que cruza el salto de línea (si el estado se tomara
# de la línea siguiente, `Repo: X`, el paso a `done` sería una transición `repo → done`, un hito falso).
$te = New-HubRepo
Set-Issue $te "feat-e/issues/01-e.md" ""
$ste = New-TestWorkspace $script:runRoot "hubrec-state"
Recolectar $te $ste "2026-09-19T10:00:00Z" | Out-Null
Set-Issue $te "feat-e/issues/01-e.md" "done"
$r = Recolectar $te $ste "2026-09-20T10:00:00Z"
Assert ($r.lote.resultado -eq "sin cambios") "un issue con el Status en blanco no deja estado anterior: su done no se propone (fue: $((Ids $r) -join ', '))"

# --- Una foto de otra versión no se compara contra el formato de hoy ---
# Hasta la v1 la foto guardaba la línea `Status:` entera; hoy guarda el token canónico. Compararlas
# daría un hito por cada issue ya cerrado. Se re-fija la línea de base de `.scratch/` y los SHA ya
# vistos se conservan: rechazar la foto entera re-propondría el histórico de slices completo.
$tf = New-HubRepo
$cf = Commit $tf "cierra el f" -slice ".scratch/feat-f/issues/01-f.md — el f"
Set-Issue $tf "feat-f/issues/01-f.md" "done"
$stf = New-TestWorkspace $script:runRoot "hubrec-state"
Recolectar $tf $stf "2026-09-19T10:00:00Z" | Out-Null
$fotoF = @(Get-ChildItem -LiteralPath $stf -Recurse -Filter foto.json)[0].FullName
$jf = [IO.File]::ReadAllText($fotoF) | ConvertFrom-Json
$wtF = @($jf.scratch.PSObject.Properties)[0].Name
[IO.File]::WriteAllText($fotoF, (@{ schemaVersion = 1; vistos = @($jf.vistos)
  scratch = @{ $wtF = @{ "feat-f/01-f.md" = "``done`` — cerrado el viernes" } } } | ConvertTo-Json -Depth 5))
$r = Recolectar $tf $stf "2026-09-20T10:00:00Z"
Assert ($r.lote.resultado -eq "sin cambios") `
  "una foto de otra versión re-fija la línea de base de .scratch/ sin re-proponer, y no repite los SHA vistos (fue: $((Ids $r) -join ', '))"
Set-Issue $tf "feat-f/issues/01-f.md" "needs-info"
$r = Recolectar $tf $stf "2026-09-21T10:00:00Z"
Assert (((Ids $r) -join ',') -ceq "issue:feat-f/01-f.md:needs-info") "tras re-fijar esa línea de base, la transición siguiente sí se propone (fue: $((Ids $r) -join ', '))"

# --- Con varios worktrees viejos: la guarda mira a TODOS y el `de` sale del principal ---
# Con un solo "otro" worktree no se distingue "ninguno ya registraba el estado nuevo" de "el primero no
# lo registraba", ni "el `de` sale del principal" de "sale del último". Acá el `done` del 01 lo registra
# un worktree que NO es el primero, y en el 02 el principal y el carril viejo discrepan.
$tz = New-HubRepo
Set-Issue $tz "feat-z/issues/01-guard.md" "ready-for-agent"
Set-Issue $tz "feat-z/issues/02-de.md" "ready-for-agent"
$wz1 = Join-Path (New-TestWorkspace $script:runRoot "hubrec-wt") "carril-z1"
git -C $tz worktree add -q -b feat/z1 $wz1 2>$null
Set-Issue $wz1 "feat-z/issues/01-guard.md" "done"
Set-Issue $wz1 "feat-z/issues/02-de.md" "needs-info"
$stz = New-TestWorkspace $script:runRoot "hubrec-state"
Recolectar $tz $stz "2026-09-19T10:00:00Z" | Out-Null
$wz2 = Join-Path (New-TestWorkspace $script:runRoot "hubrec-wt") "carril-z2"
git -C $tz worktree add -q -b feat/z2 $wz2 2>$null
Set-Issue $wz2 "feat-z/issues/01-guard.md" "done"
Set-Issue $wz2 "feat-z/issues/02-de.md" "done"
$r = Recolectar $tz $stz "2026-09-20T10:00:00Z"
$p = @($r.lote.propuestas)
Assert (((Ids $r) -join ',') -ceq "issue:feat-z/02-de.md:done") `
  "el carril nuevo no re-propone el done que ya registraba otro worktree, aunque no sea el primero (fue: $((Ids $r) -join ', '))"
Assert ($p.Count -eq 1 -and $p[0].hechos.de -ceq "ready-for-agent") "el 'de' de un carril nuevo sale del worktree principal, no de cualquiera (fue '$($p[0].hechos.de)')"

# --- Sin `.scratch/` no hay nada que proponer, y no es una falla ---
$tn = New-HubRepo
$stn = New-TestWorkspace $script:runRoot "hubrec-state"
Recolectar $tn $stn "2026-09-19T10:00:00Z" | Out-Null
$r = Recolectar $tn $stn "2026-09-20T10:00:00Z"
Assert ($r.exit -eq 0 -and $r.lote.resultado -eq "sin cambios") "sin .scratch/: lote 'sin cambios' y exit 0 (fue '$($r.lote.resultado)', exit $($r.exit))"

# --- El recolector no le deja su encoding a los procesos que arranquen después (issue 15) ---
# `[Console]::OutputEncoding` es de la CONSOLA, no del proceso: el que lo fija se lo deja puesto a
# todo lo que se lance después ahí. Con las suites en paralelo eso son rojos cruzados. La sonda corre
# DESPUÉS del recolector, en su misma consola privada, y tiene que seguir viendo el ambiente del caso.
$tc = New-HubRepo
Commit $tc "recolección de años" -slice "03 recolector" | Out-Null
$stc = New-TestWorkspace $script:runRoot "hubrec-state"
$r = Invoke-EnConsolaPropia -RunRoot $script:runRoot -Script $recol -ConSonda -Cp 850 `
  -Argumentos @('-RepoDir', $tc, '-Dev', 'martin', '-StateDir', $stc, '-Now', '2026-09-19T10:00:00Z')
Assert ($r.exit -eq 0) "en una consola que no es UTF-8 el recolector corre igual (exit $($r.exit); $($r.err))"
Assert ($r.cpSonda -eq 850) `
  "el recolector no le cambia el encoding al proceso siguiente de su consola (la sonda arrancó en $($r.cpSonda), esperaba 850)"

Remove-TestRunRoot $script:runRoot
if ($script:failures -eq 0) { Write-Host "TODOS LOS TESTS PASARON"; exit 0 }
else { Write-Host "$($script:failures) test(s) FALLARON"; exit 1 }
