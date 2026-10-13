# tests/resolve-canonical.tests.ps1 — runner sin Pester. Correr: pwsh -NoProfile -File tests/resolve-canonical.tests.ps1
#
# Cubre skills/upgrade-bootstrap/scripts/resolve-canonical.ps1: el paso 1 de upgrade-bootstrap, que
# ubica el scaffold canónico de un proyecto. Antes era prosa en el SKILL.md: "leé generatedFrom; el
# canónico es ~/.claude/skills/<generatedFrom>/assets/scaffold", y si esa skill no estaba instalada
# compare-scaffold moría con "Canonical scaffold has no manifest". Es el caso de un proyecto que se
# bootstrapeó con una variante (personal) y se actualiza en una máquina que sólo tiene otra
# (ai-project): el manifest nombra una skill que no existe ahí, y el usuario tenía que editarlo a mano.
#
# CONTRATO: emite JSON { skill, scaffold, generatedFrom, resolvedBy, candidates[] } con exit 0, o un
# mensaje con exit != 0.
#   - la skill del manifest está instalada con scaffold      -> ella, resolvedBy = "manifest"
#   - no está (o no hay manifest) y hay UNA instalada         -> ésa, resolvedBy = "only-installed"
#   - no está (o no hay manifest) y hay varias o ninguna      -> exit != 0, listando las candidatas
# Candidata = <SkillsRoot>/bootstrap-*-project con assets/scaffold/.bootstrap-manifest.json: un
# directorio bootstrap-* sin manifest de scaffold no cuenta (bootstrap-multistage-project no es un
# bootstrap de esta familia).
$ErrorActionPreference = "Stop"
$repo   = Split-Path $PSScriptRoot -Parent
$script = Join-Path $repo "skills/upgrade-bootstrap/scripts/resolve-canonical.ps1"
$script:failures = 0
$script:checks   = 0

function Assert($cond, $msg) {
  $script:checks++
  if ($cond) { Write-Host "ok:   $msg" } else { Write-Host "FAIL: $msg"; $script:failures++ }
}

# Cantidad EXACTA de aserciones: sin esto, un mutante que borra asserts sale en verde.
$ExpectedChecks = 22

. (Join-Path $PSScriptRoot "lib\temp-workspace.ps1")
$script:runRoot = New-TestRunRoot "rcanon"
trap { Remove-TestRunRoot $script:runRoot; break }

function New-Skill($root, $name, [switch]$SinManifest) {
  $scaffold = Join-Path $root "$name\assets\scaffold"
  [IO.Directory]::CreateDirectory($scaffold) | Out-Null
  if (-not $SinManifest) {
    ([ordered]@{ variant = $name; generatedFrom = $name; version = "test"; files = @{} } | ConvertTo-Json) |
      Set-Content -LiteralPath (Join-Path $scaffold ".bootstrap-manifest.json") -Encoding UTF8
  }
  $scaffold
}
function New-Project($root, $name, $generatedFrom) {
  $p = Join-Path $root $name
  [IO.Directory]::CreateDirectory($p) | Out-Null
  if ($null -ne $generatedFrom) {
    ([ordered]@{ variant = "x"; generatedFrom = $generatedFrom; version = "test"; files = @{} } | ConvertTo-Json) |
      Set-Content -LiteralPath (Join-Path $p ".bootstrap-manifest.json") -Encoding UTF8
  }
  $p
}
# Corre el script y devuelve @{ exit; json (o $null); text }.
function Resolve($proj, $skillsRoot) {
  $out = & pwsh -NoProfile -File $script -ProjectDir $proj -SkillsRoot $skillsRoot 2>&1 | Out-String
  $json = $null
  if ($LASTEXITCODE -eq 0) { $json = $out | ConvertFrom-Json }
  @{ exit = $LASTEXITCODE; json = $json; text = $out }
}

# (1) La skill del manifest está instalada: se usa ella, aunque haya otras.
$r1 = Join-Path $script:runRoot "r1"
$sPersonal = New-Skill $r1 "bootstrap-personal-project"
New-Skill $r1 "bootstrap-ai-project" | Out-Null
$p1 = New-Project $r1 "proj" "bootstrap-personal-project"
$x = Resolve $p1 $r1
Assert ($x.exit -eq 0) "(1) manifest instalada: exit 0"
Assert ($x.json.skill -eq "bootstrap-personal-project") "(1) manifest instalada: skill = la del manifest"
Assert ($x.json.scaffold -eq $sPersonal) "(1) manifest instalada: scaffold = assets/scaffold de esa skill"
Assert ($x.json.resolvedBy -eq "manifest") "(1) manifest instalada: resolvedBy = manifest"
Assert ($x.json.generatedFrom -eq "bootstrap-personal-project") "(1) manifest instalada: generatedFrom reportado"

# (2) El caso del hermano: el manifest nombra una skill que no está, y hay UNA instalada.
$r2 = Join-Path $script:runRoot "r2"
$sAi = New-Skill $r2 "bootstrap-ai-project"
New-Skill $r2 "bootstrap-multistage-project" -SinManifest | Out-Null   # bootstrap-* sin scaffold: no es candidata
$p2 = New-Project $r2 "proj" "bootstrap-personal-project"
$x = Resolve $p2 $r2
Assert ($x.exit -eq 0) "(2) manifest no instalada + una candidata: exit 0"
Assert ($x.json.skill -eq "bootstrap-ai-project") "(2) manifest no instalada + una candidata: skill = la única instalada"
Assert ($x.json.scaffold -eq $sAi) "(2) manifest no instalada + una candidata: scaffold = el de la única instalada"
Assert ($x.json.resolvedBy -eq "only-installed") "(2) manifest no instalada + una candidata: resolvedBy = only-installed"
Assert ($x.json.generatedFrom -eq "bootstrap-personal-project") "(2) manifest no instalada + una candidata: generatedFrom sigue siendo el del manifest (para el reporte)"
Assert (@($x.json.candidates).Count -eq 1 -and $x.json.candidates[0] -eq "bootstrap-ai-project") "(2) un bootstrap-* sin manifest de scaffold no cuenta como candidata"

# (3) El manifest nombra una skill que no está, y hay VARIAS instaladas: no adivina.
$r3 = Join-Path $script:runRoot "r3"
New-Skill $r3 "bootstrap-ai-project" | Out-Null
New-Skill $r3 "bootstrap-southpoint-project" | Out-Null
$p3 = New-Project $r3 "proj" "bootstrap-personal-project"
$x = Resolve $p3 $r3
Assert ($x.exit -ne 0) "(3) manifest no instalada + varias candidatas: exit != 0"
Assert ($x.text -match "bootstrap-personal-project") "(3) el mensaje nombra la skill del manifest que falta"
Assert ($x.text -match "bootstrap-ai-project" -and $x.text -match "bootstrap-southpoint-project") "(3) el mensaje lista las candidatas"

# (4) Proyecto legacy (sin manifest) con UNA instalada: se usa ésa.
$r4 = Join-Path $script:runRoot "r4"
$s4 = New-Skill $r4 "bootstrap-ai-project"
$p4 = New-Project $r4 "proj" $null
$x = Resolve $p4 $r4
Assert ($x.exit -eq 0) "(4) legacy + una candidata: exit 0"
Assert ($x.json.scaffold -eq $s4) "(4) legacy + una candidata: scaffold = el de la única instalada"
Assert ($x.json.resolvedBy -eq "only-installed") "(4) legacy + una candidata: resolvedBy = only-installed"
Assert ($null -eq $x.json.generatedFrom) "(4) legacy: generatedFrom nulo"

# (5) Proyecto legacy con varias instaladas: no adivina.
$r5 = Join-Path $script:runRoot "r5"
New-Skill $r5 "bootstrap-ai-project" | Out-Null
New-Skill $r5 "bootstrap-personal-project" | Out-Null
$p5 = New-Project $r5 "proj" $null
$x = Resolve $p5 $r5
Assert ($x.exit -ne 0) "(5) legacy + varias candidatas: exit != 0"

# (6) Ninguna instalada: exit != 0 y lo dice.
$r6 = Join-Path $script:runRoot "r6"
[IO.Directory]::CreateDirectory($r6) | Out-Null
$p6 = New-Project $r6 "proj" "bootstrap-personal-project"
$x = Resolve $p6 $r6
Assert ($x.exit -ne 0) "(6) ninguna instalada: exit != 0"
Assert ($x.text -match "no bootstrap-\*-project skill") "(6) ninguna instalada: el mensaje lo dice"

# (7) Sin -SkillsRoot el default es ~/.claude/skills. El manifest nombra una skill que no existe
#     en ninguna máquina, así que la respuesta (JSON o mensaje) tiene que mencionar esa raíz, sea
#     porque resolvió a una instalada ahí o porque listó lo que hay ahí.
$p7 = New-Project (Join-Path $script:runRoot "r7") "proj" "bootstrap-inexistente-project"
$out7 = & pwsh -NoProfile -File $script -ProjectDir $p7 2>&1 | Out-String
$esperado = Join-Path $HOME ".claude" "skills"
Assert ($out7 -match [regex]::Escape($esperado)) "(7) sin -SkillsRoot, el JSON o el mensaje apuntan a ~/.claude/skills"

Remove-TestRunRoot $script:runRoot

Assert ($script:checks -eq $ExpectedChecks) "cantidad exacta de aserciones: $($script:checks) de $ExpectedChecks"
if ($script:failures -eq 0) { Write-Host "TODOS LOS TESTS PASARON"; exit 0 }
else { Write-Host "$($script:failures) test(s) FALLARON"; exit 1 }
