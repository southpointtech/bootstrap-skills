# tests/export-changelog.tests.ps1 — runner sin Pester. Correr: pwsh -NoProfile -File tests/export-changelog.tests.ps1
#
# Cubre tools/export-changelog.ps1: la copia del CHANGELOG.md al repo público. El changelog del
# repo tiene entradas que sólo existen para la variante Southpoint (secciones "(Southpoint only)",
# bullets "Southpoint bootstrap: …") y el gate anti-fuga del export las frena. El filtro saca lo que
# es de esa variante POR ESTRUCTURA — una sección `###` cuyo título pega con un marcador, con todo
# su cuerpo hasta el próximo `##`/`###`; un ítem de lista cuyo texto (con sus líneas de
# continuación indentadas) pega con un marcador — y nada más: un marcador en un párrafo suelto de
# una sección que se queda NO se toca, para que lo frene el gate del export y se arregle en la
# fuente. Lo que saca lo lista por stdout, así el que revisa el diff del clon ve qué no viajó.
$ErrorActionPreference = "Stop"
$repo   = Split-Path $PSScriptRoot -Parent
$script = Join-Path $repo "tools/export-changelog.ps1"
$script:failures = 0
$script:checks   = 0

function Assert($cond, $msg) {
  $script:checks++
  if ($cond) { Write-Host "ok:   $msg" } else { Write-Host "FAIL: $msg"; $script:failures++ }
}

# Cantidad EXACTA de aserciones: sin esto, un mutante que borra asserts sale en verde.
$ExpectedChecks = 19

. (Join-Path $PSScriptRoot "lib\temp-workspace.ps1")
$script:runRoot = New-TestRunRoot "xchlog"
trap { Remove-TestRunRoot $script:runRoot; break }

$markers = Join-Path $script:runRoot "markers.txt"
"zoho`nsouthpoint`nMartinDele703`n" | Set-Content -LiteralPath $markers -Encoding UTF8

$src = Join-Path $script:runRoot "CHANGELOG.md"
@'
# Changelog

## v2.2.1 — 2026-10-02

### Fixed — reporting

- The report now covers every outcome.
  Second line of the kept bullet.
- Southpoint bootstrap: the item is back inside the Step 0 checklist
  and this continuation line goes with it.
- `upgrade-bootstrap` keeps this one.

### Added — hub-sync declaration (Southpoint only)

`.claude/scripts/hub-declarar.ps1` creates the declaration.
The body mentions zoho and goes away with its heading.

- a bullet inside the dropped section

### Changed — the handoff lives outside the repo

There is one handoff contract now.

### Changed — zoho sync (Southpoint only)

Body of the dropped section that closes the version block.

## v2.1.0 — 2026-09-23

Intro paragraph directly under the version heading.

- contact MartinDele703 for details
- every scaffold skill is agent-invocable again

## v2.0.0 — 2026-09-10

A paragraph that names SouthPoint stays, for the gate to catch.
'@ | Set-Content -LiteralPath $src -Encoding UTF8

$dest = Join-Path $script:runRoot "out\CHANGELOG.md"
$out = & pwsh -NoProfile -File $script -Source $src -Dest $dest -Markers $markers 2>&1 | Out-String
Assert ($LASTEXITCODE -eq 0) "exit 0"
Assert (Test-Path -LiteralPath $dest) "escribe el destino (creando el directorio)"
$text = Get-Content -LiteralPath $dest -Raw
$lines = @(Get-Content -LiteralPath $dest)

# Lo que se queda.
Assert ($text -match '(?m)^## v2\.2\.1 ') "la sección de versión se queda"
Assert ($text -match '(?m)^### Fixed — reporting') "una sección ### sin marcador se queda"
Assert ($text -match "every outcome\.\r?\n  Second line of the kept bullet\.") "un bullet sin marcador se queda con su continuación"
Assert ($text -match '(?m)^- `upgrade-bootstrap` keeps this one\.') "el bullet que sigue a uno borrado se queda"
Assert ($text -match '(?m)^### Changed — the handoff') "la sección ### que sigue a una borrada se queda"
Assert ($text -match "There is one handoff contract now\.") "el cuerpo de la sección que sigue a una borrada se queda"
Assert ($text -match '(?m)^- every scaffold skill is agent-invocable again') "un bullet sin marcador en una sección ## se queda"

# Lo que se va, y cómo.
Assert ($text -notmatch "Southpoint bootstrap") "el bullet con marcador se va (sin distinguir mayúsculas)"
Assert ($text -notmatch "this continuation line goes with it") "la continuación indentada del bullet borrado se va con él"
Assert ($text -notmatch "hub-sync declaration" -and $text -notmatch "hub-declarar" -and $text -notmatch "a bullet inside the dropped section") "la sección ### con marcador en el título se va con todo su cuerpo"
Assert ($text -notmatch "MartinDele703") "un bullet con marcador bajo una sección ## se va"
Assert (-not ($lines -match '^### ' | Where-Object { $_ -match 'Southpoint' })) "no queda ningún título ### con marcador"

# Una sección ### borrada que cierra el bloque de versión: el `##` siguiente corta el borrado. Sin
# ese reset (el mutante que sobrevivió en el turno 1 del review-loop) todo lo que sigue al `##` hasta
# el próximo `###` se iba en silencio.
Assert ($text -notmatch "Body of the dropped section that closes the version block") "la sección ### borrada justo antes de un ## se va con su cuerpo"
Assert ($text -match "Intro paragraph directly under the version heading\.") "el párrafo bajo el ## que sigue a una sección borrada se queda"

# El límite del filtro: un párrafo suelto con marcador NO se toca (es del gate).
Assert ($text -match "A paragraph that names SouthPoint stays") "un párrafo suelto con marcador se queda para que lo frene el gate"

# Lo que sacó lo lista, para el que revisa el diff del clon.
Assert ($out -match "Southpoint bootstrap: the item" -and $out -match "hub-sync declaration" -and $out -match "contact MartinDele703") "stdout lista cada ítem y sección que sacó"

# Idempotente sobre su propia salida: filtrar lo filtrado no cambia nada.
$dest2 = Join-Path $script:runRoot "out2\CHANGELOG.md"
& pwsh -NoProfile -File $script -Source $dest -Dest $dest2 -Markers $markers | Out-Null
Assert ((Get-Content -LiteralPath $dest2 -Raw) -ceq $text) "filtrar la salida otra vez la deja igual"

Remove-TestRunRoot $script:runRoot

Assert ($script:checks -eq $ExpectedChecks) "cantidad exacta de aserciones: $($script:checks) de $ExpectedChecks"
if ($script:failures -eq 0) { Write-Host "TODOS LOS TESTS PASARON"; exit 0 }
else { Write-Host "$($script:failures) test(s) FALLARON"; exit 1 }
