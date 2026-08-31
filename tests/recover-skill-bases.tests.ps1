# tests/recover-skill-bases.tests.ps1 — runner sin Pester. Correr: pwsh -NoProfile -File tests/recover-skill-bases.tests.ps1
# Mete el self-test offline de tools/recover-skill-bases.py en la suite. Antes existía y no lo
# corría nadie: la herramienta podía romperse sin que ninguna corrida de tests lo notara.
$ErrorActionPreference = "Stop"
$repo = Split-Path $PSScriptRoot -Parent
$tool = Join-Path $repo "tools/recover-skill-bases.py"
$script:failures = 0

function Assert($cond, $msg) {
  if ($cond) { Write-Host "ok:   $msg" } else { Write-Host "FAIL: $msg"; $script:failures++ }
}

# Cantidad EXACTA de aserciones del self-test. Se actualiza a mano al agregar o quitar
# checks. Sin este número, un mutante que BORRA asserts sale en verde: 0 fails de 0 checks
# también es "0 fail". No se llama `$MinChecks` justamente porque no es un mínimo: con
# holgura, un mutante puede borrar tantos checks como holgura haya y seguir pasando —
# quedó en 59 mientras el self-test ya corría 62, o sea que los tres checks recién agregados
# eran borrables en verde.
$ExpectedChecks = 84

# La herramienta tiene que existir: si no, el intérprete escupe su error y un assert de
# "no hubo fails" pasaría en verde sin haber ejercitado nada.
if (-not (Test-Path -LiteralPath $tool)) {
  Write-Host "FAIL: no existe la herramienta en $tool"; exit 1
}

# El intérprete se resuelve, no se asume: en esta máquina hay `python`, pero el doc documenta
# `py` (el launcher de Windows). Si no hay ninguno, es un FAIL explícito y no un falso verde.
# No alcanza con Get-Command: en Windows `python` suele ser el alias de ejecución de la Store, que
# EXISTE como comando y no corre Python — quedarse con el primero que aparece daba un rojo espurio
# en vez de caer a `py`. Por eso cada candidato se valida corriéndolo.
$python = $null
foreach ($cand in @("python", "py")) {
  $cmd = Get-Command $cand -ErrorAction SilentlyContinue
  if (-not $cmd) { continue }
  $ver = & $cand --version 2>&1
  if ($LASTEXITCODE -eq 0 -and "$ver" -match 'Python \d') { $python = $cmd.Source; break }
}
if (-not $python) {
  Write-Host 'FAIL: no se encontró intérprete de Python (`python` ni `py`) para correr el self-test'
  exit 1
}

# --- El self-test offline corre entero y sale limpio ---
$out = & $python $tool --self-test 2>&1
$exit = $LASTEXITCODE
$text = ($out | Out-String)

Assert ($exit -eq 0) "el self-test sale con exit code 0 (fue $exit)"

# Las dos puntas: que haya una línea de resumen parseable, y que diga lo que tiene que decir.
# Assertar sólo el exit code deja pasar un mutante que devuelve 0 sin correr ninguna aserción.
$m = [regex]::Match($text, 'SELF-TEST:\s+(\d+)\s+ok,\s+(\d+)\s+fail\s+\(de\s+(\d+)\)')
Assert ($m.Success) 'el self-test imprime su línea de resumen (`SELF-TEST: N ok, N fail (de N)`)'

if ($m.Success) {
  $ok    = [int]$m.Groups[1].Value
  $fail  = [int]$m.Groups[2].Value
  $total = [int]$m.Groups[3].Value

  Assert ($fail -eq 0) "ninguna aserción del self-test falla (fallaron $fail de $total)"
  # `$ok -eq $total` no es redundante con la de arriba por accidente: hoy el resumen imprime
  # `ok = checks - fails`, así que las dos caen juntas. Cubre que ese cómputo siga siendo cierto.
  Assert ($ok -eq $total) "las aserciones que pasaron son todas las que corrieron ($ok de $total)"
  # `-eq`, no `-ge`. Con `-ge` el piso acumula holgura EN SILENCIO: quien agrega un check y no
  # toca el literal no se entera, y a partir de ahí se pueden borrar tantos asserts como holgura
  # haya sin que nada se ponga en rojo. Ya pasó: quedó en 59 con el self-test en 62, y los tres
  # checks recién agregados eran borrables en verde. Con `-eq` la deriva es roja al instante, en
  # las dos direcciones, y el mensaje dice qué hacer.
  Assert ($total -eq $ExpectedChecks) "el self-test corre exactamente $ExpectedChecks aserciones (corrió $total) — si agregaste o quitaste un check, actualizá `$ExpectedChecks"
} else {
  # Sin resumen no se puede afirmar nada sobre las aserciones: se deja constancia del texto real
  # en vez de dar por buenas las de arriba. Se falla explícito en vez de sumar un literal, que
  # mentía en cuanto alguien agregara una cuarta aserción al bloque de al lado.
  Write-Host "----- salida real del self-test -----"
  Write-Host $text
  Write-Host "------------------------------------"
  Write-Host "FAIL: sin línea de resumen no se puede verificar ninguna aserción del self-test"
  $script:failures++
}

if ($script:failures -gt 0) { Write-Host "`n$($script:failures) FALLAS"; exit 1 }
Write-Host "`nTodo verde"
exit 0
