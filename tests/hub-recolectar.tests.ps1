# tests/hub-recolectar.tests.ps1 — runner sin Pester. Correr: pwsh -NoProfile -File tests/hub-recolectar.tests.ps1
# El recolector de hub-sync (issue 03): lee los commits del dev con trailer `Slice-Close:` y escribe
# un lote JSON por corrida. Fixtures: repos git temporales con su declaración `.claude/hub-sync.json`.
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
function New-HubRepo([string]$decl = "", [switch]$SinDeclaracion) {
  $t = New-TestWorkspace $script:runRoot "hubrec-repo"
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
# Un commit vacío con autor explícito y, opcionalmente, el trailer.
function Commit([string]$t, [string]$subject, [string]$email = "m@x.io", [string]$slice = $null) {
  $msg = if ($slice) { "$subject`n`nSlice-Close: $slice" } else { $subject }
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
$alt        = Commit $t "desde la otra cuenta" -email "m.alt@x.io" -slice "05 alt"
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
)
foreach ($c in $invalidas) {
  $ti = New-HubRepo $c.decl
  $sti = New-TestWorkspace $script:runRoot "hubrec-state"
  $r = Recolectar $ti $sti "2026-09-19T10:00:00Z"
  Assert ($r.exit -eq 1) "$($c.caso): exit 1 (fue $($r.exit))"
  Assert ($r.lote.resultado -eq "falló" -and @($r.lote.propuestas).Count -eq 0) "$($c.caso): lote 'falló' sin propuestas (fue '$($r.lote.resultado)')"
  Assert ("$($r.lote.motivo)" -match [regex]::Escape($c.nombra)) "$($c.caso): el motivo nombra '$($c.nombra)' (fue '$($r.lote.motivo)')"
  Assert (-not (Test-Path -LiteralPath (Join-Path $sti "$(Split-Path $ti -Leaf)/foto.json"))) "$($c.caso): no fija línea de base"
}
# Declaración válida en un directorio que no es un repo git: el motivo es de git, no de la declaración.
$noGit = New-TestWorkspace $script:runRoot "hubrec-repo"
[IO.Directory]::CreateDirectory((Join-Path $noGit ".claude")) | Out-Null
[IO.File]::WriteAllText((Join-Path $noGit ".claude/hub-sync.json"), '{ "schemaVersion": 1, "hubProject": "P", "devs": { "martin": ["m@x.io"] } }')
$r = Recolectar $noGit (New-TestWorkspace $script:runRoot "hubrec-state") "2026-09-19T10:00:00Z"
Assert ($r.exit -eq 1 -and $r.lote.resultado -eq "falló" -and "$($r.lote.motivo)" -match 'git') `
  "sin repo git: lote 'falló' con motivo de git (exit $($r.exit), motivo '$($r.lote.motivo)')"

Remove-TestRunRoot $script:runRoot
if ($script:failures -eq 0) { Write-Host "TODOS LOS TESTS PASARON"; exit 0 }
else { Write-Host "$($script:failures) test(s) FALLARON"; exit 1 }
