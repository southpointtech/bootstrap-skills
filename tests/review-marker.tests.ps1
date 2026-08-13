# tests/review-marker.tests.ps1 — runner sin Pester. Correr: pwsh -NoProfile -File tests/review-marker.tests.ps1
# Fixtures determinísticos (repos git temporales) para el marcador de revisión.
$ErrorActionPreference = "Stop"
$repo   = Split-Path $PSScriptRoot -Parent
$marker = Join-Path $repo "skills/bootstrap-personal-project/assets/scaffold/.claude/scripts/review-marker.ps1"
$script:failures = 0

function Assert($cond, $msg) {
  if ($cond) { Write-Host "ok:   $msg" } else { Write-Host "FAIL: $msg"; $script:failures++ }
}
function New-Repo {
  $t = Join-Path ([IO.Path]::GetTempPath()) ("rm-test-" + [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $t | Out-Null
  git -C $t init -q -b master; git -C $t config user.email a@b.c; git -C $t config user.name a
  "base" | Set-Content (Join-Path $t "file.txt")
  git -C $t add -A; git -C $t commit -q -m base
  git -C $t checkout -q -b feat/x
  return $t
}
# Devuelve "" si el script no existe: sin este guard pwsh imprime su usage a STDOUT y el
# test lo confundiría con una salida legítima del marcador.
function Marker($dir, $action) {
  if (-not (Test-Path -LiteralPath $marker)) { return "" }
  $out = & pwsh -NoProfile -File $marker -Action $action -RepoDir $dir
  if ($null -eq $out) { return "" }
  return (($out -join "`n")).Trim()
}

# --- Tracer bullet: advance fija un punto de corte resoluble y get lo devuelve ---
$t = New-Repo
$adv = Marker $t advance
Assert ($adv -and ((git -C $t cat-file -t $adv 2>$null) -eq "commit")) "advance devuelve un objeto git resoluble"
Assert (($adv -ne "") -and ((Marker $t get) -eq $adv)) "get devuelve el marcador que fijó advance"
Remove-Item -Recurse -Force $t

# --- El árbol sucio entra en el punto de corte ---
# Tras avanzar con cambios sin commitear, no queda delta entre el marcador y el árbol actual:
# lo sucio quedó del lado ya revisado. Con HEAD como marcador, ese diff NO estaría vacío.
$t = New-Repo
"sucio" | Set-Content (Join-Path $t "file.txt")
$adv = Marker $t advance
git -C $t diff --quiet $adv 2>$null
Assert ($LASTEXITCODE -eq 0) "el marcador con árbol sucio incluye los cambios sin commitear"
Remove-Item -Recurse -Force $t

# --- advance es no-invasivo: no commitea, no mueve HEAD, no toca el árbol ---
$t = New-Repo
"sucio" | Set-Content (Join-Path $t "file.txt")
$countBefore  = (git -C $t rev-list --count HEAD)
$headBefore   = (git -C $t rev-parse HEAD)
$statusBefore = ((git -C $t status --porcelain) -join "`n")
Marker $t advance | Out-Null
Assert ((git -C $t rev-list --count HEAD) -eq $countBefore) "advance no crea un commit"
Assert ((git -C $t rev-parse HEAD) -eq $headBefore) "advance no mueve HEAD"
Assert (((git -C $t status --porcelain) -join "`n") -eq $statusBefore) "advance no toca el árbol de trabajo"
Remove-Item -Recurse -Force $t

# --- Sin marcador previo, el rango arranca en la base del slice ---
# `range` emite el marcador PELADO: el contrato es `git diff <lo que emite range>`, no `<x>..HEAD`,
# porque la forma con ..HEAD solo cubre commits y dejaría afuera lo no commiteado.
$t = New-Repo
"slice" | Set-Content (Join-Path $t "file.txt")
git -C $t add -A; git -C $t commit -q -m slice1
$base = (git -C $t merge-base master HEAD)
Assert ((Marker $t range) -eq $base) "sin marcador previo, el rango arranca en la base del slice"
Remove-Item -Recurse -Force $t

# --- Tras avanzar, el rango trae lo nuevo y no repite lo ya revisado ---
$t = New-Repo
"revisado" | Set-Content (Join-Path $t "a.txt")
git -C $t add -A; git -C $t commit -q -m revisado
Marker $t advance | Out-Null
"nuevo" | Set-Content (Join-Path $t "b.txt")
git -C $t add -A; git -C $t commit -q -m nuevo
$names = ((git -C $t diff --name-only (Marker $t range)) -join "`n")
Assert ($names -match "b\.txt") "el rango incluye el delta sin revisar"
Assert ($names -notmatch "a\.txt") "el rango no repite lo ya revisado"
Remove-Item -Recurse -Force $t

# --- Con el árbol sin cambios: advance idempotente y rango vacío ---
# El rango vacío es la señal de que el loop cierra sin corrida de review, en vez de inventarse un rango.
$t = New-Repo
"slice" | Set-Content (Join-Path $t "file.txt")
git -C $t add -A; git -C $t commit -q -m slice1
$a1 = Marker $t advance
$a2 = Marker $t advance
Assert (($a1 -ne "") -and ($a1 -eq $a2)) "con árbol limpio, advance es idempotente"
Assert ((Marker $t range) -eq "") "sin delta sin revisar, el rango queda vacío"
Remove-Item -Recurse -Force $t

# --- Fuera de un repo git: vacío y sin romper, para los tres verbos ---
$t = Join-Path ([IO.Path]::GetTempPath()) ("rm-nogit-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $t | Out-Null
foreach ($a in @("get", "range", "advance")) {
  $o = Marker $t $a
  Assert (($o -eq "") -and ($LASTEXITCODE -eq 0)) "fuera de un repo git, '$a' devuelve vacío sin romper"
}
Remove-Item -Recurse -Force $t

# --- Detached HEAD: vacío, igual que hace el hook del disparo ---
$t = New-Repo
git -C $t checkout -q --detach
foreach ($a in @("get", "range", "advance")) {
  $o = Marker $t $a
  Assert (($o -eq "") -and ($LASTEXITCODE -eq 0)) "con HEAD detached, '$a' devuelve vacío sin romper"
}
Remove-Item -Recurse -Force $t

# --- El estado del marcador no aparece en el diff del slice ---
# Vive en el directorio de git, no en el árbol: ni se commitea ni lo ve el reviewer.
$t = New-Repo
"slice" | Set-Content (Join-Path $t "file.txt")
git -C $t add -A; git -C $t commit -q -m slice1
Marker $t advance | Out-Null
Assert (((git -C $t status --porcelain) -join "`n") -eq "") "el estado del marcador no ensucia el árbol"
$sliceDiff = ((git -C $t diff --name-only master...HEAD) -join "`n")
Assert ($sliceDiff -notmatch "review-loop-state") "el estado del marcador no aparece en el diff del slice"
Assert (Test-Path (Join-Path $t ".git/review-loop-state.json")) "el estado se persiste en el directorio de git"
Remove-Item -Recurse -Force $t

# --- Marcador podado por git gc: cae a la base del slice, nunca revisa de menos ---
$t = New-Repo
# El árbol sucio fuerza un marcador de `git stash create`, que es un objeto INALCANZABLE
# (con el árbol limpio el marcador cae a HEAD, que ningún gc poda).
"revisado" | Set-Content (Join-Path $t "a.txt")
git -C $t add -A
$adv = Marker $t advance
git -C $t commit -q -m revisado
git -C $t reflog expire --expire-unreachable=now --all 2>$null | Out-Null
git -C $t gc --prune=now -q 2>$null | Out-Null
git -C $t cat-file -e "$adv^{commit}" 2>$null
Assert ($LASTEXITCODE -ne 0) "el gc efectivamente podó el objeto del marcador (guard del fixture)"
"nuevo" | Set-Content (Join-Path $t "b.txt")
git -C $t add -A; git -C $t commit -q -m nuevo
$r = Marker $t range
Assert ($r -eq (git -C $t merge-base master HEAD)) "con el marcador podado, el rango cae a la base del slice"
Remove-Item -Recurse -Force $t

# --- Coexiste con el dedupe del hook en el mismo archivo de estado ---
# El hook guarda bajo `<rama>`; el marcador bajo `marker:<rama>`. Git prohíbe ':' en nombres de
# rama, así que las claves no pueden colisionar — pero ninguno debe pisar el estado del otro.
$t = New-Repo
$sp = Join-Path $t ".git/review-loop-state.json"
'{ "feat/x": "deadbeef" }' | Set-Content $sp -Encoding UTF8
"slice" | Set-Content (Join-Path $t "file.txt")
$adv = Marker $t advance
$state = (Get-Content $sp -Raw | ConvertFrom-Json)
Assert ($state.'feat/x' -eq "deadbeef") "advance preserva el estado del dedupe del hook"
Assert ($state.'marker:feat/x' -eq $adv) "advance persiste el marcador bajo la clave marker:<rama>"
Remove-Item -Recurse -Force $t

if ($script:failures -gt 0) { Write-Host "$($script:failures) test(s) FALLARON"; exit 1 } else { Write-Host "TODOS LOS TESTS PASARON"; exit 0 }
