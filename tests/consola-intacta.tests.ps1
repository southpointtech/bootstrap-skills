# tests/consola-intacta.tests.ps1 — runner sin Pester. Correr: pwsh -NoProfile -File tests/consola-intacta.tests.ps1
#
# Ningún .ps1 del repo asigna [Console]::OutputEncoding ni InputEncoding (issue 16). No son del
# proceso sino de la CONSOLA: el valor se lo queda todo lo que arranque después en ella, aunque el que
# lo fijó ya haya muerto, y `chcp.com` no lo informa. Bajo `tests/run-all.ps1`, con suites en paralelo
# en una consola, eso eran rojos cruzados que parecían intermitentes. Leer git, stdin o escribir
# stdout en UTF-8 se hace por llamada (`.claude/scripts/lib/git-utf8.ps1`), y una suite que necesita
# un ambiente en 850 lo pide en una consola propia (`tests/lib/consola-propia.ps1`).
#
# Lo que se prueba acá es estático a propósito: la sonda de la consola propia verifica cada script por
# separado, pero sólo los que tienen un caso; esto cubre también al que se agregue mañana sin uno.
$ErrorActionPreference = "Stop"
$repo = Split-Path $PSScriptRoot -Parent
$script:failures = 0
function Assert($cond, $msg) {
  if ($cond) { Write-Host "ok:   $msg" } else { Write-Host "FAIL: $msg"; $script:failures++ }
}

# El único que puede: el boot de la consola propia, que la fija DENTRO de una consola que abre para
# eso y que muere con el caso.
$permitido = Join-Path $repo "tests\lib\consola-propia-boot.ps1"
$patron = '\[(System\.)?Console\]::(Output|Input)Encoding\s*='

$archivos = @(Get-ChildItem -LiteralPath $repo -Recurse -File -Filter *.ps1 |
  Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' })
Assert ($archivos.Count -gt 50) "se escanean los .ps1 del repo ($($archivos.Count))"

$ofensores = @()
$enPermitido = 0
foreach ($f in $archivos) {
  $hits = @(Select-String -LiteralPath $f.FullName -Pattern $patron)
  if ($f.FullName -eq $permitido) { $enPermitido = $hits.Count; continue }
  foreach ($h in $hits) { $ofensores += "$($f.FullName.Substring($repo.Length + 1)):$($h.LineNumber)" }
}
# Control positivo: si el patrón o la lectura estuvieran rotos, no habría ofensores y el caso de abajo
# pasaría en verde sin mirar nada. El boot tiene las dos asignaciones, salida y entrada.
Assert ($enPermitido -eq 2) "control positivo: el patrón encuentra las dos asignaciones del boot de la consola propia ($enPermitido)"
Assert ($ofensores.Count -eq 0) "ningún otro .ps1 le cambia la code page a la consola ($($ofensores -join ', '))"

Write-Host ""
if ($script:failures -gt 0) { Write-Host "$($script:failures) test(s) FALLARON"; exit 1 } else { Write-Host "TODOS LOS TESTS PASARON"; exit 0 }
