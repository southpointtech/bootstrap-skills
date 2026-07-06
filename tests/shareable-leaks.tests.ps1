# tests/shareable-leaks.tests.ps1 — runner sin Pester. Correr: pwsh -NoProfile -File tests/shareable-leaks.tests.ps1
# Lo que se publica al repo público (bootstrap-ai-project, upgrade-bootstrap, public/) no puede
# contener marcadores de fuga (datos de Martín / Southpoint). Fuente única: tools/leak-markers.txt.
$ErrorActionPreference = "Stop"
$repo = Split-Path $PSScriptRoot -Parent
$script:failures = 0
function Assert($cond, $msg) {
  if ($cond) { Write-Host "ok:   $msg" } else { Write-Host "FAIL: $msg"; $script:failures++ }
}

$markers = @(Get-Content (Join-Path $repo "tools/leak-markers.txt") | Where-Object { $_.Trim() })
Assert ($markers.Count -eq 5) "leak-markers.txt tiene 5 marcadores"

$targets = @("skills/bootstrap-ai-project", "skills/upgrade-bootstrap", "public") |
  ForEach-Object { Join-Path $repo $_ }

# Los dos targets de skills siempre existen tras Slice 2 y deben escanearse: si uno faltara
# (typo, export parcial), el filtro Test-Path de abajo lo saltearía en silencio y el test pasaría
# sin cubrir lo que debe proteger. 'public' es opcional: lo crea Slice 3 y se escanea cuando existe.
Assert (Test-Path (Join-Path $repo "skills/bootstrap-ai-project")) "skills/bootstrap-ai-project existe"
Assert (Test-Path (Join-Path $repo "skills/upgrade-bootstrap")) "skills/upgrade-bootstrap existe"

foreach ($t in ($targets | Where-Object { Test-Path $_ })) {
  $hits = @()
  foreach ($f in (Get-ChildItem $t -Recurse -File -Force)) {
    $text = Get-Content -LiteralPath $f.FullName -Raw
    foreach ($m in $markers) {
      if ($text -match [regex]::Escape($m)) {
        $hits += "$([IO.Path]::GetRelativePath($repo, $f.FullName)): '$m'"
      }
    }
  }
  $hits | ForEach-Object { Write-Host "  LEAK: $_" }
  Assert ($hits.Count -eq 0) "$([IO.Path]::GetRelativePath($repo, $t)) sin marcadores de fuga"
}

if ($script:failures -eq 0) { Write-Host "TODOS LOS TESTS PASARON"; exit 0 }
else { Write-Host "$($script:failures) test(s) FALLARON"; exit 1 }
