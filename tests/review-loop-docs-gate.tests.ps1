# tests/review-loop-docs-gate.tests.ps1 — runner sin Pester.
# Correr: pwsh -NoProfile -File tests/review-loop-docs-gate.tests.ps1
#
# POR QUE EXISTE ESTE ARCHIVO. El gate de "un slice de solo documentación no se revisa" decide
# CUANDO se revisa el código. Un bug acá no se ve: apaga revisiones en silencio. La v1 del gate en
# SouthPoint-Hub trataba todo `docs/` como documentación y dejaba sin revisar `docs/design-frozen/**`,
# que su CLAUDE.md declara fuente de verdad del frontend; se encontró en review, no en uso
# (commit 21a464e de ese repo). Cada fila de acá fija uno de esos falsos negativos.
#
# A diferencia de la probe original, estos casos NO copian el clasificador: corren el hook REAL
# de punta a punta sobre repos git temporales, así que un cambio en `$govern` que rompa la
# clasificación cae en rojo acá aunque la expresión siga pareciendo razonable.
$ErrorActionPreference = "Stop"
$repoRoot = Split-Path $PSScriptRoot -Parent
$hook = Join-Path $repoRoot "skills/bootstrap-personal-project/assets/scaffold/.claude/hooks/review-loop-trigger.ps1"
$script:failures = 0

function Assert($cond, $msg) {
  if ($cond) { Write-Host "ok:   $msg" } else { Write-Host "FAIL: $msg"; $script:failures++ }
}

function New-Repo {
  $t = Join-Path ([IO.Path]::GetTempPath()) ("rlg-test-" + [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $t | Out-Null
  git -C $t init -q -b master; git -C $t config user.email a@b.c; git -C $t config user.name a
  # Mismo aislamiento del gitconfig global que el resto de la suite: con `commit.gpgsign=true` en la
  # máquina los commits del fixture no se crean y todos los asserts de ausencia pasan en falso.
  git -C $t config commit.gpgsign false; git -C $t config core.hooksPath ""; git -C $t config core.excludesFile ""
  # `core.quotePath` explícito en true: si el dev tiene `false` en su config global, el fixture del
  # path con acento pasaría en verde sobre un hook al que le falta el flag.
  git -C $t config core.quotePath true
  git -C $t commit --allow-empty -q -m base
  git -C $t checkout -q -b feat/x
  return $t
}

# Commitea los archivos indicados (contenido irrelevante: el gate mira nombres, no contenido).
function Commit-Files($repo, [string[]]$paths) {
  foreach ($p in $paths) {
    $full = Join-Path $repo $p
    $dir = Split-Path $full -Parent
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    Set-Content -LiteralPath $full -Value "contenido" -Encoding UTF8
    git -C $repo add -- $p
  }
  git -C $repo commit -q -m "slice"
}

# Deja un archivo SIN trackear (no lo commitea): `git diff` nunca los muestra.
function Add-Untracked($repo, $path) {
  $full = Join-Path $repo $path
  $dir = Split-Path $full -Parent
  if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
  Set-Content -LiteralPath $full -Value "contenido" -Encoding UTF8
}

function Fire($repo, $cmd) {
  $evt = @{ tool_input = @{ command = $cmd }; cwd = $repo } | ConvertTo-Json -Compress
  return ($evt | & pwsh -NoProfile -File $hook)
}

# Cada caso: los archivos del slice y si el hook TIENE que disparar el review.
# Se usa `git push` como disparador para aislar el gate de la compuerta del trailer `Slice-Close:`
# (el push dispara incondicionalmente; lo único que puede callarlo es este gate).
$cases = @(
  # --- prosa: NO se revisa ---
  @{ files = @("docs/notas.md");                       fire = $false; label = "slice de solo prosa (.md) no dispara" },
  @{ files = @("HANDOFF.md", "docs/adr/0001-x.md");     fire = $false; label = "varios .md sueltos siguen siendo solo-docs" },
  @{ files = @("docs/Especificación Funcional.md");     fire = $false; label = "un .md con acento sigue clasificando como doc (core.quotePath)" },

  # --- gobierna al agente: SÍ se revisa aunque sea .md ---
  @{ files = @("CLAUDE.md");                            fire = $true; label = "CLAUDE.md dispara: son las reglas duras, no prosa" },
  @{ files = @("sub/CLAUDE.md");                        fire = $true; label = "un CLAUDE.md anidado también dispara (anclaje (^|/), no ^)" },
  @{ files = @(".claude/commands/handoff.md");          fire = $true; label = ".claude/** dispara aunque sea .md" },
  @{ files = @(".agents/skills/tdd/SKILL.md");          fire = $true; label = ".agents/** dispara: las SKILL.md definen el trailer que arma este hook" },
  @{ files = @("docs/ai-workflow/QA_CHECKLIST.md");     fire = $true; label = "docs/ai-workflow/** dispara: lectura obligatoria del workflow" },
  @{ files = @("docs/agents/issue-tracker.md");         fire = $true; label = "docs/agents/** dispara: define las skills" },

  # --- código: SÍ se revisa ---
  @{ files = @("src/a.ts");                             fire = $true; label = "código normal dispara" },
  @{ files = @("docs/design/app.js");                   fire = $true; label = "código que vive bajo docs/ dispara (el falso negativo de la v1)" },
  @{ files = @("docs/notas.md", "src/a.ts");            fire = $true; label = "slice MIXTO dispara: basta un archivo no-doc" }
)

Write-Host "=== gate de slices solo-docs (hook real, end-to-end) ==="
foreach ($c in $cases) {
  $t = New-Repo
  Commit-Files $t $c.files
  $o = Fire $t "git push"
  $fired = [bool]($o -match "additionalContext")
  Assert ($fired -eq $c.fire) ("{0} [esperado={1} obtenido={2}]" -f $c.label, $(if ($c.fire) { "dispara" } else { "silencio" }), $(if ($fired) { "dispara" } else { "silencio" }))
  Remove-Item -Recurse -Force $t
}

# `git diff` NUNCA muestra untracked, así que un slice cuyo código nuevo todavía no se commiteó se
# vería como solo-docs y saldría sin revisar. Es exactamente el caso que el paso 5 del loop fabrica:
# manda escribir un test nuevo, que es untracked hasta que alguien lo commitea.
$t = New-Repo
Commit-Files $t @("docs/notas.md")
Add-Untracked $t "src/nuevo.ts"
$o = Fire $t "git push"
Assert ($o -match "additionalContext") "un .ts NUEVO sin trackear dispara aunque lo commiteado sea solo prosa"
Remove-Item -Recurse -Force $t

# El gate vale para todos los disparadores, no solo para el push: un cierre DECLARADO de un slice
# de prosa tampoco tiene que gastar un loop.
$t = New-Repo
New-Item -ItemType Directory -Path (Join-Path $t "docs") -Force | Out-Null
Set-Content -LiteralPath (Join-Path $t "docs/notas.md") -Value "x" -Encoding UTF8
git -C $t add -- "docs/notas.md"
git -C $t commit -q -m "docs: notas`n`nSlice-Close: notas"
$o = Fire $t "git commit -m x"
Assert ([string]::IsNullOrEmpty($o)) "un cierre DECLARADO de un slice solo-docs tampoco dispara"
Remove-Item -Recurse -Force $t

# Fail-open: si el rango no se puede resolver, se revisa. Nunca al revés.
$t = New-Repo
Commit-Files $t @("docs/notas.md")
git -C $t checkout -q --orphan huerfana
git -C $t commit --allow-empty -q -m "sin ancestro comun"
$o = Fire $t "git push"
Assert ($o -match "additionalContext") "fail-open: con un rango irresoluble (historias sin ancestro) se dispara igual"
Remove-Item -Recurse -Force $t

Write-Host ""
if ($script:failures -eq 0) { Write-Host "TODOS LOS TESTS PASARON" } else { Write-Host "FALLOS: $($script:failures)"; exit 1 }
