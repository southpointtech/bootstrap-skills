# tests/mirror.tests.ps1 — runner sin Pester. Correr: pwsh -NoProfile -File tests/mirror.tests.ps1
# Espejado entre las skills bootstrap-*-project: mismo SET de archivos e identidad de CONTENIDO
# en todo lo que no está en la allowlist de divergencia (archivos de variante).
# El hash se toma sobre el contenido con line-endings normalizados (CRLF/CR -> LF): con
# core.autocrlf=true el working tree puede materializar el MISMO contenido git con bytes
# distintos según cómo llegó cada archivo (checkout=CRLF, escritura de agente=LF, copia=preserva).
# El invariante real es identidad de contenido; el único consumidor de este chequeo es este test.
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

# Hash del contenido con line-endings normalizados (ver cabecera). Inmune a autocrlf.
function NormHash($path) {
  $text = [IO.File]::ReadAllText($path)
  $norm = $text -replace "`r`n", "`n" -replace "`r", "`n"
  $sha  = [Security.Cryptography.SHA256]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes($norm))
  [BitConverter]::ToString($sha).Replace("-", "")
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
    $same = (NormHash $a) -eq (NormHash $b)
    Assert $same "$($other.Name): $rel idéntico en contenido a $($ref.Name)"
  }
}

# El Step 2 de cada SKILL.md le pide al agente verificar la copia contando directorios y
# comandos. Ese conteo está escrito a mano y se desincronizó del scaffold: los tres decían 10
# cuando ya eran 11, así que una copia CORRECTA fallaba la verificación — y el peor desenlace
# es que el agente "arregle" borrando la skill de más. El espejo no lo agarra porque los tres
# mienten idéntico. Acá el número se ata a lo que el scaffold tiene de verdad.
foreach ($s in $skills) {
  $scaffold = Join-Path $s.FullName "assets/scaffold"
  $nSkills  = @(Get-ChildItem (Join-Path $scaffold ".agents/skills") -Directory).Count
  $nCmds    = @(Get-ChildItem (Join-Path $scaffold ".claude/commands") -File).Count
  $texto    = Get-Content (Join-Path $s.FullName "SKILL.md") -Raw
  $m = [regex]::Match($texto,
    '`\.agents\\skills` has (\d+) skill directories, `\.claude\\commands` has (\d+) files')
  Assert $m.Success "$($s.Name): el SKILL.md declara el conteo de la verificación del Step 2"
  if ($m.Success) {
    Assert ([int]$m.Groups[1].Value -eq $nSkills) `
      "$($s.Name): el SKILL.md dice $($m.Groups[1].Value) skills y el scaffold tiene $nSkills"
    Assert ([int]$m.Groups[2].Value -eq $nCmds) `
      "$($s.Name): el SKILL.md dice $($m.Groups[2].Value) comandos y el scaffold tiene $nCmds"
  }

  # El mismo conteo se repite un párrafo más abajo, en `This delivers:`, y atar sólo la primera
  # aparición dejaba la segunda libre de despegarse igual — que es exactamente el bug que este
  # guard existe para atajar.
  $nWf   = @(Get-ChildItem (Join-Path $scaffold "docs/ai-workflow") -File).Count
  $nAg   = @(Get-ChildItem (Join-Path $scaffold "docs/agents") -File).Count
  $d = [regex]::Match($texto,
    '\.agents/skills/` \((\d+) skills.*?\.claude/commands/` \((\d+) commands\)')
  Assert $d.Success "$($s.Name): el SKILL.md declara el conteo del párrafo 'This delivers'"
  if ($d.Success) {
    Assert ([int]$d.Groups[1].Value -eq $nSkills) `
      "$($s.Name): 'This delivers' dice $($d.Groups[1].Value) skills y el scaffold tiene $nSkills"
    Assert ([int]$d.Groups[2].Value -eq $nCmds) `
      "$($s.Name): 'This delivers' dice $($d.Groups[2].Value) comandos y el scaffold tiene $nCmds"
  }
  $wf = [regex]::Match($texto, '`docs/ai-workflow/` \((\d+) docs\)')
  $ag = [regex]::Match($texto, '`docs/agents/` \((\d+) docs\)')
  Assert ($wf.Success -and [int]$wf.Groups[1].Value -eq $nWf) `
    "$($s.Name): 'This delivers' declara los $nWf docs de ai-workflow (dice: $($wf.Groups[1].Value))"
  Assert ($ag.Success -and [int]$ag.Groups[1].Value -eq $nAg) `
    "$($s.Name): 'This delivers' declara los $nAg docs de agents (dice: $($ag.Groups[1].Value))"
}

if ($script:failures -eq 0) { Write-Host "TODOS LOS TESTS PASARON"; exit 0 }
else { Write-Host "$($script:failures) test(s) FALLARON"; exit 1 }
