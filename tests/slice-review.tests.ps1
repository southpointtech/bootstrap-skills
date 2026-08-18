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

  # La corrida de review del loop tiene que apuntar al reviewer invocable. El número de paso no
  # se fija acá: desde el review incremental, el paso 1 es pedirle el rango al marcador y la
  # corrida de review es el paso 2. Lo que este test blinda es el MOTOR, no el orden.
  foreach ($f in $pairs["review-loop"]) {
    $rel = $f.Substring($s.FullName.Length).TrimStart('\')
    if (-not (Test-Path -LiteralPath $f)) { continue }
    $txt = [IO.File]::ReadAllText($f)
    Assert ($txt -match '(?m)^\d+\. Run `/slice-review`') "$($s.Name): $rel corre /slice-review como paso numerado del loop"
  }
}

# --- A3: corrida de review incremental ---------------------------------------------------------
# El contenido del prompt de slice-review se verifica en las 3 skills bootstrap Y en la copia del
# repo (AC: "verificados en las 3 skills bootstrap y en la copia del repo"). Los dos artefactos de
# cada ubicacion (command para el humano + SKILL.md para autodescubrimiento) comparten el CUERPO,
# asi que las mismas aserciones corren sobre ambos.
$slicePairs = @(
  @{ label = "repo"; files = @(
      (Join-Path $repo ".claude\commands\slice-review.md"),
      (Join-Path $repo ".agents\skills\slice-review\SKILL.md")
  ) }
)
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

    # Cambio 1 — el objetivo por DEFECTO (sin args) es el delta sin revisar, resuelto del marcador.
    Assert ($txt -match 'review-marker\.ps1 -Action range') `
      "$($p.label)/${rel}: el default resuelve el delta desde el marcador (-Action range)"
    # El rango completo del slice queda reservado al pase de coherencia (A4), no es el default.
    Assert ($txt -match '(?i)reserved for the coherence pass') `
      "$($p.label)/${rel}: el rango completo del slice queda reservado al pase de coherencia"

    # Cambio 2 — con delta vacio (exit 0) reporta 'nada que revisar' en vez de inventar un rango.
    Assert ($txt -match '(?i)everything up to the marker was already reviewed') `
      "$($p.label)/${rel}: delta vacio del marcador => nada que revisar, sin inventar rango"

    # Cambio 3 — la prohibicion de escritura viaja en el contexto compartido, una sola vez.
    Assert ($txt -match '(?i)reviewer, not an editor') `
      "$($p.label)/${rel}: declara la prohibicion de escritura en el contexto compartido"

    # Cambio 4 — cada foco declara su modelo: Sonnet 5 (reglas, historia), Opus 5 (bugs, contratos, tests).
    Assert ($txt -match '(?i)project rules and historical context on \*\*Sonnet 5\*\*') `
      "$($p.label)/${rel}: reglas e historia declaran Sonnet 5"
    Assert ($txt -match '(?i)bugs, contracts and tests on \*\*Opus 5\*\*') `
      "$($p.label)/${rel}: bugs, contratos y tests declaran Opus 5"

    # Cambio 5 — el pase de confianza sigue en Opus 5, con la misma rubrica y el mismo corte en 60.
    Assert ($txt -match '(?i)the confidence pass runs on Opus 5') `
      "$($p.label)/${rel}: el pase de confianza corre en Opus 5"
    Assert ($txt -match 'Drop everything below 60') `
      "$($p.label)/${rel}: el pase de confianza mantiene el corte en 60 (regresion)"

    # AC6 (regresion) — el reporte sigue diciendo cuantos descarto la confianza y que rango se reviso.
    Assert ($txt -match '(?i)dropped by the confidence pass') `
      "$($p.label)/${rel}: el reporte dice cuantos hallazgos descarto la confianza"
    Assert ($txt -match '(?i)diff range that was actually reviewed') `
      "$($p.label)/${rel}: el reporte dice que rango se reviso"
  }
}

if ($script:failures -eq 0) { Write-Host "TODOS LOS TESTS PASARON"; exit 0 }
else { Write-Host "$($script:failures) test(s) FALLARON"; exit 1 }
