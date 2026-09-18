# tests/regla-de-afirmaciones.tests.ps1 — runner sin Pester.
# Correr: pwsh -NoProfile -File tests/regla-de-afirmaciones.tests.ps1
#
# A6 — Regla de afirmaciones. Una afirmacion (enunciado verificable en un comentario, docstring o
# mensaje de commit) se escribe SOLO si se verifico; si no se verifico, no se escribe. La disciplina
# se ataca en dos puntos, con CERO agentes dedicados:
#   1. una regla dura en las reglas del proyecto, para que aplique desde el primer commit;
#   2. una linea en el reviewer de contratos (foco 4, que YA corre), para cazar las que igual se
#      escriban dentro de una corrida existente, sin sumar un foco.
# Este test blinda ambos puntos.
$ErrorActionPreference = "Stop"
$repo = Split-Path $PSScriptRoot -Parent
$skills = @(Get-ChildItem (Join-Path $repo "skills") -Directory | Where-Object Name -like "bootstrap-*-project")
$script:failures = 0
function Assert($cond, $msg) {
  if ($cond) { Write-Host "ok:   $msg" } else { Write-Host "FAIL: $msg"; $script:failures++ }
}

# --- Punto 1: la regla vive en las reglas del proyecto de los 3 scaffolds + el propio repo (4
#     archivos, NO espejados: las CLAUDE.md divergen legitimamente y estan en la allowlist del mirror,
#     asi que son 4 ediciones separadas). ---
$claudeFiles = @(@{ label = "repo"; path = (Join-Path $repo "CLAUDE.md") })
foreach ($s in $skills) {
  $claudeFiles += @{ label = $s.Name; path = (Join-Path $s.FullName "assets\scaffold\CLAUDE.md") }
}
Assert ($claudeFiles.Count -ge 4) "hay al menos 4 CLAUDE.md donde vive la regla ($($claudeFiles.Count))"

foreach ($c in $claudeFiles) {
  if (-not (Test-Path -LiteralPath $c.path)) { Assert $false "$($c.label): existe CLAUDE.md"; continue }
  $txt = [IO.File]::ReadAllText($c.path)
  # La mitad positiva: la afirmacion se escribe solo si se verifico.
  Assert ($txt -match '(?i)written only if it was verified') `
    "$($c.label): CLAUDE.md tiene la regla de afirmaciones (se escribe solo si se verifico)"
  # La mitad negativa, que es el punto: si no se verifico, no se escribe.
  Assert ($txt -match '(?i)do not write it') `
    "$($c.label): CLAUDE.md dice que una afirmacion sin verificar no se escribe"
}

# --- Punto 2: la deteccion barata es una linea en el reviewer de contratos (foco 4 de Step 4), sin
#     foco nuevo. La byte-identidad de las 4 copias de slice-review (repo + 3 scaffolds) la verifica
#     review-loop-incremental.tests.ps1 (mirror.tests.ps1 solo compara los 3 scaffolds ENTRE SI, no la
#     copia del repo); aca solo se verifica la PRESENCIA de la linea en cada copia y que no haya un
#     foco de lectura extra. ---
function Section([string]$txt, [string]$header) {
  $m = [regex]::Match($txt, "(?im)^##\s+$([regex]::Escape($header)).*?(?=^##\s|\z)", 'Singleline')
  if ($m.Success) { return $m.Value } else { return "" }
}

$slicePairs = @(@{ label = "repo"; files = @(
    (Join-Path $repo ".claude\commands\slice-review.md"),
    (Join-Path $repo ".agents\skills\slice-review\SKILL.md")
) })
foreach ($s in $skills) {
  $scaffold = Join-Path $s.FullName "assets\scaffold"
  $slicePairs += @{ label = $s.Name; files = @(
      (Join-Path $scaffold ".claude\commands\slice-review.md"),
      (Join-Path $scaffold ".agents\skills\slice-review\SKILL.md")
  ) }
}

foreach ($p in $slicePairs) {
  foreach ($f in $p.files) {
    $rel = Split-Path $f -Leaf
    if (-not (Test-Path -LiteralPath $f)) { Assert $false "$($p.label): existe slice-review ($rel)"; continue }
    $txt = [IO.File]::ReadAllText($f)
    $s4 = Section $txt 'Step 4 — Fan out parallel reviewers'
    # Sin foco dedicado: siguen los 5 focos de lectura numerados (el unico 6to condicional es el de
    # mutacion, que EJECUTA, no es de lectura, y vive en su propia seccion, no como item 6 de Step 4).
    Assert ($s4 -match '(?im)^5\.\s') `
      "$($p.label)/${rel}: siguen los 5 focos de lectura numerados"
    Assert (-not ($s4 -match '(?im)^6\.\s')) `
      "$($p.label)/${rel}: no se agrego un 6to foco de lectura numerado para afirmaciones"
  }
}

# --- La instruccion vive en el AGENT de contratos, no en Step 4: desde el issue 15 el brief de cada
#     foco esta en su declaracion, y en Step 4 queda solo una linea-resumen que nombra el tema. Anclar
#     ahi dejaba que borrar la instruccion real pasara verde. Se ancla la ORDEN, no el tema. ---
foreach ($p in $slicePairs) {
  $agent = Join-Path (Split-Path (Split-Path (Split-Path $p.files[0] -Parent) -Parent) -Parent) ".claude\agents\slice-review-contracts.md"
  if (-not (Test-Path -LiteralPath $agent)) { Assert $false "$($p.label): existe .claude/agents/slice-review-contracts.md"; continue }
  $body = [IO.File]::ReadAllText($agent) -replace "`r`n", "`n"
  Assert ($body -cmatch '(?m)^Also flag \*\*unverified assertions\*\* — a comment, docstring, or commit message that states as fact') `
    "$($p.label): el agent de contratos ordena marcar afirmaciones no verificadas"
}

if ($script:failures -gt 0) { Write-Host "`n$($script:failures) FALLARON"; exit 1 }
Write-Host "`nTODOS LOS TESTS PASARON"; exit 0
