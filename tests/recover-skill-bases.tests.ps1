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

# Piso de aserciones del self-test. Sube a mano cuando se agregan checks. Sin este piso, un
# mutante que BORRA asserts sale en verde: 0 fails de 0 checks también es "0 fail".
$MinChecks = 44

# La herramienta tiene que existir: si no, el intérprete escupe su error y un assert de
# "no hubo fails" pasaría en verde sin haber ejercitado nada.
if (-not (Test-Path -LiteralPath $tool)) {
  Write-Host "FAIL: no existe la herramienta en $tool"; exit 1
}

# El intérprete se resuelve, no se asume: en esta máquina hay `python`, pero el doc documenta
# `py` (el launcher de Windows). Si no hay ninguno, es un FAIL explícito y no un falso verde.
$python = $null
foreach ($cand in @("python", "py")) {
  $cmd = Get-Command $cand -ErrorAction SilentlyContinue
  if ($cmd) { $python = $cmd.Source; break }
}
if (-not $python) {
  Write-Host "FAIL: no se encontró intérprete de Python (`python` ni `py`) para correr el self-test"
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
Assert ($m.Success) "el self-test imprime su línea de resumen (`SELF-TEST: N ok, N fail (de N)`)"

if ($m.Success) {
  $ok    = [int]$m.Groups[1].Value
  $fail  = [int]$m.Groups[2].Value
  $total = [int]$m.Groups[3].Value

  Assert ($fail -eq 0) "ninguna aserción del self-test falla (fallaron $fail de $total)"
  Assert ($ok -eq $total) "las aserciones que pasaron son todas las que corrieron ($ok de $total)"
  Assert ($total -ge $MinChecks) "el self-test corre al menos $MinChecks aserciones (corrió $total)"
} else {
  # Sin resumen no se puede afirmar nada sobre las aserciones: se deja constancia del texto real
  # en vez de dar por buenas las tres afirmaciones de arriba.
  Write-Host "----- salida real del self-test -----"
  Write-Host $text
  Write-Host "------------------------------------"
  $script:failures += 3
}

if ($script:failures -gt 0) { Write-Host "`n$($script:failures) FALLAS"; exit 1 }
Write-Host "`nTodo verde"
exit 0
