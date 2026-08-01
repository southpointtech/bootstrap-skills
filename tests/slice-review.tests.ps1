# tests/slice-review.tests.ps1 — runner sin Pester. Correr: pwsh -NoProfile -File tests/slice-review.tests.ps1
# El motor del review-loop tiene que ser invocable POR EL AGENTE. El built-in /code-review está
# marcado disable-model-invocation ("Skill code-review cannot be used with Skill tool"), así que un
# loop que dependa de él nunca puede cerrarse solo — el hook review-loop-trigger ordena algo
# imposible y el slice termina reportado como "revisado" sin que ningún reviewer haya corrido.
# Este test blinda el reemplazo (/slice-review) y evita la regresión a /code-review.
$ErrorActionPreference = "Stop"
$repo = Split-Path $PSScriptRoot -Parent
$skills = @(Get-ChildItem (Join-Path $repo "skills") -Directory | Where-Object Name -like "bootstrap-*-project")
$script:failures = 0
function Assert($cond, $msg) {
  if ($cond) { Write-Host "ok:   $msg" } else { Write-Host "FAIL: $msg"; $script:failures++ }
}

Assert ($skills.Count -ge 2) "hay al menos 2 skills bootstrap-*-project ($($skills.Count))"

# Pares (command para el humano, SKILL.md con triggers para autodescubrimiento) de cada scaffold.
foreach ($s in $skills) {
  $scaffold = Join-Path $s.FullName "assets\scaffold"
  $pairs = @{
    "slice-review" = @(
      (Join-Path $scaffold ".claude\commands\slice-review.md"),
      (Join-Path $scaffold ".agents\skills\slice-review\SKILL.md")
    )
    "review-loop"  = @(
      (Join-Path $scaffold ".claude\commands\review-loop.md"),
      (Join-Path $scaffold ".agents\skills\review-loop\SKILL.md")
    )
  }

  foreach ($name in $pairs.Keys) {
    foreach ($f in $pairs[$name]) {
      $rel = $f.Substring($s.FullName.Length).TrimStart('\')
      if (-not (Test-Path -LiteralPath $f)) { Assert $false "$($s.Name): existe $rel"; continue }
      Assert $true "$($s.Name): existe $rel"
      $txt = [IO.File]::ReadAllText($f)

      # Invocable por el agente: necesita description en el frontmatter y no puede estar bloqueado.
      Assert ($txt -match '(?m)^description:\s*\S') "$($s.Name): $rel declara description (invocable)"
      Assert ($txt -notmatch '(?m)^disable-model-invocation:\s*true') `
        "$($s.Name): $rel no se bloquea con disable-model-invocation"

      # Regresión: nada puede ORDENAR correr /code-review (mencionarlo para explicar por qué no, sí).
      Assert ($txt -notmatch '(?m)^\s*(?:\d+\.\s*)?Run `/code-review`') `
        "$($s.Name): $rel no ordena correr /code-review"
    }
  }

  # El paso 1 del loop tiene que apuntar al reviewer invocable.
  foreach ($f in $pairs["review-loop"]) {
    $rel = $f.Substring($s.FullName.Length).TrimStart('\')
    if (-not (Test-Path -LiteralPath $f)) { continue }
    $txt = [IO.File]::ReadAllText($f)
    Assert ($txt -match '(?m)^1\. Run `/slice-review`') "$($s.Name): $rel corre /slice-review en el paso 1 del loop"
  }
}

if ($script:failures -eq 0) { Write-Host "TODOS LOS TESTS PASARON"; exit 0 }
else { Write-Host "$($script:failures) test(s) FALLARON"; exit 1 }
