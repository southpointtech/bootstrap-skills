# tests/hub-recolectar.tests.ps1 — runner sin Pester. Correr: pwsh -NoProfile -File tests/hub-recolectar.tests.ps1
# El recolector de hub-sync (issues 03 y 08): lee los commits del dev con trailer `Slice-Close:` y las
# transiciones de `Status:` de `.scratch/`, y escribe un lote JSON por corrida. Fixtures: repos git temporales con su declaración `.claude/hub-sync.json`.
$ErrorActionPreference = "Stop"
$repo  = Split-Path $PSScriptRoot -Parent
$recol = Join-Path $repo "skills/bootstrap-southpoint-project/assets/scaffold/.claude/scripts/hub-recolectar.ps1"
$script:failures = 0
. (Join-Path $PSScriptRoot "lib\temp-workspace.ps1")
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
# Bajo el code page 850 de consola, que el hijo hereda: es el de una máquina que no está en UTF-8 (lo
# que ve una Scheduled Task) y el que deforma los acentos. Esta terminal está en 65001, y sin forzarlo
# el assert del asunto con acentos pasaba en verde con la decodificación UTF-8 sacada (medido).
function Recolectar([string]$t, [string]$state, [string]$now, [string]$dev = "martin") {
  $prev = [Console]::OutputEncoding
  try {
    [Console]::OutputEncoding = [Text.Encoding]::GetEncoding(850)
    $out = & pwsh -NoProfile -File $recol -RepoDir $t -Dev $dev -StateDir $state -Now $now
  } finally { [Console]::OutputEncoding = $prev }
  $r = @{ exit = $LASTEXITCODE; out = (($out | Where-Object { $_ }) -join "`n").Trim(); lote = $null }
  if ($r.out -and (Test-Path -LiteralPath $r.out)) {
    $r.lote = [IO.File]::ReadAllText($r.out) | ConvertFrom-Json -DateKind String
  }
  return $r
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
# El asunto lleva acentos a propósito: pwsh decodifica la salida de git con la página de códigos de la
# consola (ibm850 en estas máquinas) y el asunto llegaría deformado al lote.
$sha = Commit $t "recolección de años" -slice "03 recolector"
$r = Recolectar $t $state "2026-09-20T10:00:00Z"
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
# Un worktree nuevo fija su línea de base: sus `done` no son transiciones.
$wb = Join-Path $wtBase "carril-b"
git -C $tm worktree add -q -b feat/b $wb 2>$null
Set-Issue $wb "feat-n/issues/01-n.md" "done"
$r = Recolectar $wa $stm "2026-09-21T10:00:00Z"
Assert ($r.lote.resultado -eq "sin cambios") "un worktree nuevo fija su línea de base, corra desde donde corra (fue '$($r.lote.resultado)': $((Ids $r) -join ', '))"
# La misma transición en dos worktrees es una sola propuesta.
Set-Issue $tm "feat-a/issues/01-uno.md" "needs-info"
Set-Issue $wa "feat-a/issues/01-uno.md" "needs-info"
$r = Recolectar $tm $stm "2026-09-22T10:00:00Z"
Assert (((Ids $r) -join ',') -ceq "issue:feat-a/01-uno.md:needs-info") "la misma transición en dos worktrees sale una sola vez (fue: $((Ids $r) -join ', '))"

# --- Sin `.scratch/` no hay nada que proponer, y no es una falla ---
$tn = New-HubRepo
$stn = New-TestWorkspace $script:runRoot "hubrec-state"
Recolectar $tn $stn "2026-09-19T10:00:00Z" | Out-Null
$r = Recolectar $tn $stn "2026-09-20T10:00:00Z"
Assert ($r.exit -eq 0 -and $r.lote.resultado -eq "sin cambios") "sin .scratch/: lote 'sin cambios' y exit 0 (fue '$($r.lote.resultado)', exit $($r.exit))"

Remove-TestRunRoot $script:runRoot
if ($script:failures -eq 0) { Write-Host "TODOS LOS TESTS PASARON"; exit 0 }
else { Write-Host "$($script:failures) test(s) FALLARON"; exit 1 }
