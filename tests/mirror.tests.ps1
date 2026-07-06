# tests/mirror.tests.ps1 — runner sin Pester. Correr: pwsh -NoProfile -File tests/mirror.tests.ps1
# Espejado entre las skills bootstrap-*-project: mismo SET de archivos y byte-identidad
# en todo lo que no está en la allowlist de divergencia (archivos de variante).
$ErrorActionPreference = "Stop"
$repo = Split-Path $PSScriptRoot -Parent
$skills = @(Get-ChildItem (Join-Path $repo "skills") -Directory | Where-Object Name -like "bootstrap-*-project")
$script:failures = 0
function Assert($cond, $msg) {
  if ($cond) { Write-Host "ok:   $msg" } else { Write-Host "FAIL: $msg"; $script:failures++ }
}

Assert ($skills.Count -ge 2) "hay al menos 2 skills bootstrap-*-project ($($skills.Count))"

# Archivos de variante: PUEDEN divergir entre skills. Todo lo demás debe ser byte-idéntico.
$allow = @(
  "SKILL.md",
  "assets/scaffold/CLAUDE.md",
  "assets/scaffold/.bootstrap-manifest.json",
  "assets/scaffold/docs/ai-workflow/AI_DEVELOPMENT_WORKFLOW.md",
  "assets/scaffold/docs/ai-workflow/DEPLOYMENT_RULES.md",
  "assets/scaffold/docs/ai-workflow/PRD_TEMPLATE.md",
  "assets/scaffold/docs/ai-workflow/QA_CHECKLIST.md",
  "assets/scaffold/docs/ai-workflow/TASK_TEMPLATE.md",
  "assets/scaffold/docs/agents/issue-tracker.md",
  "scripts/gen-mcp-json.ps1"
)

function RelFiles($skillDir) {
  Get-ChildItem $skillDir -Recurse -File -Force | ForEach-Object {
    [IO.Path]::GetRelativePath($skillDir, $_.FullName) -replace '\\', '/'
  } | Sort-Object
}

$ref = $skills[0]
$refFiles = @(RelFiles $ref.FullName)
foreach ($other in ($skills | Select-Object -Skip 1)) {
  $otherFiles = @(RelFiles $other.FullName)
  $diffSet = @(Compare-Object $refFiles $otherFiles | ForEach-Object { $_.InputObject })
  Assert ($diffSet.Count -eq 0) "$($other.Name): mismo set de archivos que $($ref.Name) (diff: $($diffSet -join ', '))"
  foreach ($rel in $refFiles) {
    if ($allow -contains $rel) { continue }
    $a = Join-Path $ref.FullName   $rel
    $b = Join-Path $other.FullName $rel
    if (-not (Test-Path -LiteralPath $b)) { continue }  # ya reportado por el diff de set
    $same = (Get-FileHash -LiteralPath $a).Hash -eq (Get-FileHash -LiteralPath $b).Hash
    Assert $same "$($other.Name): $rel byte-idéntico a $($ref.Name)"
  }
}

if ($script:failures -eq 0) { Write-Host "TODOS LOS TESTS PASARON"; exit 0 }
else { Write-Host "$($script:failures) test(s) FALLARON"; exit 1 }
