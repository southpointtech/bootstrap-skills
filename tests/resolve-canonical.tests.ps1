# tests/resolve-canonical.tests.ps1 — runner sin Pester. Correr: pwsh -NoProfile -File tests/resolve-canonical.tests.ps1
#
# Cubre skills/upgrade-bootstrap/scripts/resolve-canonical.ps1: el paso 1 de upgrade-bootstrap, que
# ubica el scaffold canónico de un proyecto. Antes era prosa en el SKILL.md: "leé generatedFrom; el
# canónico es ~/.claude/skills/<generatedFrom>/assets/scaffold", y si esa skill no estaba instalada
# compare-scaffold moría con "Canonical scaffold has no manifest". Es el caso de un proyecto que se
# bootstrapeó con una variante (personal) y se actualiza en una máquina que sólo tiene otra
# (ai-project): el manifest nombra una skill que no existe ahí, y el usuario tenía que editarlo a mano.
#
# CONTRATO: emite JSON { skill, scaffold, generatedFrom, resolvedBy, variantSwitch, candidates[] } con
# exit 0, o un mensaje con exit != 0. variantSwitch es true solo en only-installed con un manifest
# que nombraba otra skill: las bases del manifest son de la OTRA variante, así que un archivo intacto
# que difiere del canónico puede diferir por la variante y no por una actualización, y el SKILL.md
# lo pone a consentimiento por archivo en vez de pisarlo como "outdated".
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
$ExpectedChecks = 41

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
# Corre el script y devuelve @{ exit; json (o $null); text }. Con -Skill, pasa la elección del usuario.
function Resolve($proj, $skillsRoot, $skill) {
  $extra = @(); if ($skill) { $extra = @("-Skill", $skill) }
  $out = & pwsh -NoProfile -File $script -ProjectDir $proj -SkillsRoot $skillsRoot @extra 2>&1 | Out-String
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
Assert ($x.json.variantSwitch -eq $false) "(1) manifest instalada: variantSwitch false"

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
Assert ($x.json.variantSwitch -eq $true) "(2) manifest de otra variante resuelto a la única instalada: variantSwitch true"

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
Assert ($x.json.variantSwitch -eq $false) "(4) legacy: sin manifest no hay variante previa, variantSwitch false"

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

# (8) -Skill: la respuesta del usuario cuando el script no pudo decidir. Vuelve a correrse con la
#     skill elegida para que el JSON lleve variantSwitch: con varias instaladas y un manifest de otra
#     variante, la elegida es por definición otra variante (turno 2 del review-loop).
$r8 = Join-Path $script:runRoot "r8"
$s8ai = New-Skill $r8 "bootstrap-ai-project"
New-Skill $r8 "bootstrap-southpoint-project" | Out-Null
New-Skill $r8 "bootstrap-multistage-project" -SinManifest | Out-Null
$p8 = New-Project $r8 "proj" "bootstrap-personal-project"
$x = Resolve $p8 $r8 "bootstrap-ai-project"
Assert ($x.exit -eq 0) "(8) -Skill con scaffold: exit 0"
Assert ($x.json.resolvedBy -eq "user" -and $x.json.skill -eq "bootstrap-ai-project" -and $x.json.scaffold -eq $s8ai) "(8) -Skill: resolvedBy user, skill y scaffold los elegidos"
Assert ($x.json.variantSwitch -eq $true) "(8) -Skill distinta de la del manifest: variantSwitch true"
$x = Resolve $p8 $r8 "bootstrap-multistage-project"
Assert ($x.exit -ne 0 -and $x.text -match "bootstrap-multistage-project") "(8) -Skill sin manifest de scaffold: exit != 0 y la nombra"
$p8b = New-Project $r8 "proj-ai" "bootstrap-ai-project"
$x = Resolve $p8b $r8 "bootstrap-ai-project"
Assert ($x.json.resolvedBy -eq "user" -and $x.json.variantSwitch -eq $false) "(8) -Skill igual a la del manifest: variantSwitch false"
$p8c = New-Project $r8 "proj-legacy" $null
$x = Resolve $p8c $r8 "bootstrap-ai-project"
Assert ($x.json.resolvedBy -eq "user" -and $x.json.variantSwitch -eq $false) "(8) -Skill en un proyecto legacy: variantSwitch false"

# (9) El flujo completo del cambio de variante: el usuario conserva un archivo (su contenido es el de
#     la otra variante) y el reseal del paso 5 con -VariantSwitch lo deja FUERA del manifest, así que
#     el upgrade siguiente lo ve customized y no outdated. Sin el switch, el reseal lo re-basaba con
#     su hash actual (intacto desde su base) y el próximo upgrade lo pisaba con una sola aprobación.
$reseal  = Join-Path $repo "skills/upgrade-bootstrap/scripts/reseal-manifest.ps1"
$compare = Join-Path $repo "skills/upgrade-bootstrap/scripts/compare-scaffold.ps1"
. (Join-Path $PSScriptRoot "..\tools\normalized-hash.ps1")   # Get-Hashes; la forma 3 que admite temp-hygiene, después del helper
$r9 = Join-Path $script:runRoot "r9"
$canonSkill = Join-Path $r9 "bootstrap-ai-project"
$canon = Join-Path $canonSkill "assets\scaffold"
[IO.Directory]::CreateDirectory($canon) | Out-Null
"tracker: generic`n"  | Set-Content -LiteralPath (Join-Path $canon "a.md") -NoNewline
"same everywhere`n"   | Set-Content -LiteralPath (Join-Path $canon "b.md") -NoNewline
& (Join-Path $repo "tools/gen-manifest.ps1") -SkillDir $canonSkill | Out-Null
$canonManifest = Get-Content -LiteralPath (Join-Path $canon ".bootstrap-manifest.json") -Raw | ConvertFrom-Json
function New-SwitchedProject($name) {
  # a.md intacto desde su base (la otra variante), b.md igual al canónico.
  $p = Join-Path $r9 $name
  [IO.Directory]::CreateDirectory($p) | Out-Null
  "tracker: personal`n" | Set-Content -LiteralPath (Join-Path $p "a.md") -NoNewline
  "same everywhere`n"   | Set-Content -LiteralPath (Join-Path $p "b.md") -NoNewline
  $baseA = (Get-Hashes (Join-Path $p "a.md")).n
  ([ordered]@{ variant = "personal"; generatedFrom = "bootstrap-personal-project"; version = "old"
               files = [ordered]@{ "a.md" = $baseA; "b.md" = $canonManifest.files.'b.md' } } | ConvertTo-Json) |
    Set-Content -LiteralPath (Join-Path $p ".bootstrap-manifest.json") -Encoding UTF8
  $p
}
$p9 = New-SwitchedProject "proj"
& pwsh -NoProfile -File $reseal -ProjectDir $p9 -CanonicalScaffold $canon -VariantSwitch | Out-Null
Assert ($LASTEXITCODE -eq 0) "(9) reseal -VariantSwitch: exit 0"
$m9 = Get-Content -LiteralPath (Join-Path $p9 ".bootstrap-manifest.json") -Raw | ConvertFrom-Json
Assert ($null -eq $m9.files.'a.md') "(9) reseal -VariantSwitch: el archivo conservado (de la otra variante) queda fuera del manifest"
Assert ($m9.files.'b.md' -eq $canonManifest.files.'b.md') "(9) reseal -VariantSwitch: el archivo igual al canónico se sella igual que siempre"
Assert ($m9.generatedFrom -eq "bootstrap-ai-project") "(9) reseal -VariantSwitch: generatedFrom pasa a la skill usada"
$c9raw = & pwsh -NoProfile -File $compare -ProjectDir $p9 -CanonicalScaffold $canon | Out-String
$c9 = if ($LASTEXITCODE -eq 0) { $c9raw | ConvertFrom-Json } else { $null }
Assert (@($c9.customized | ForEach-Object { $_.file }) -contains "a.md" -and @($c9.outdated).Count -eq 0) "(9) el upgrade siguiente ve el archivo conservado como customized, no outdated"
# Control: sin el switch, el reseal lo re-basa y el upgrade siguiente lo pisaría (outdated).
$p9c = New-SwitchedProject "proj-control"
& pwsh -NoProfile -File $reseal -ProjectDir $p9c -CanonicalScaffold $canon | Out-Null
$c9c = (& pwsh -NoProfile -File $compare -ProjectDir $p9c -CanonicalScaffold $canon | Out-String) | ConvertFrom-Json
Assert (@($c9c.outdated) -contains "a.md") "(9) control: sin -VariantSwitch el reseal re-basa el archivo y el siguiente upgrade lo ve outdated"

# (10) El SKILL.md consume el contrato: lo que frena el pisado es prosa del paso 4, y sin ancla se
#      podía borrar con toda la suite en verde (mismo patrón que carriles-scaffold.tests.ps1).
$up = Get-Content -LiteralPath (Join-Path $repo "skills/upgrade-bootstrap/SKILL.md") -Raw
function Paso($n) { [regex]::Match($up, "(?ms)^### $n\. .*?(?=^### |\z)").Value }
Assert ((Paso 1) -cmatch '-Skill ') "(10) el paso 1 reintenta el script con -Skill cuando hay que preguntar"
Assert ((Paso 3) -cmatch 'variantSwitch') "(10) el paso 3 reporta variantSwitch"
Assert ((Paso 4) -cmatch 'variantSwitch: true' -and (Paso 4) -cmatch 'outdated') "(10) el paso 4 condiciona el pisado de outdated a variantSwitch"
Assert ((Paso 5) -cmatch '-VariantSwitch') "(10) el paso 5 pasa -VariantSwitch al reseal"

Remove-TestRunRoot $script:runRoot

Assert ($script:checks -eq $ExpectedChecks) "cantidad exacta de aserciones: $($script:checks) de $ExpectedChecks"
if ($script:failures -eq 0) { Write-Host "TODOS LOS TESTS PASARON"; exit 0 }
else { Write-Host "$($script:failures) test(s) FALLARON"; exit 1 }
