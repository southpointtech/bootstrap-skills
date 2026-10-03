# tests/merge-settings.tests.ps1 — runner sin Pester. Correr: pwsh -NoProfile -File tests/merge-settings.tests.ps1
#
# Cubre el merge de `.claude/settings.json` de upgrade-bootstrap: agrega los hooks canónicos que
# faltan y, para un hook que ya está (misma firma de comandos), une las alternativas del `matcher`
# (issue upgrade-tanda-2026-10-03/02). Antes del fix, Forecasting App quedó con el
# review-loop-trigger en "Bash" mientras el canónico decía "Bash|PowerShell", y el script respondía
# que no había nada que hacer.
$ErrorActionPreference = "Stop"
$repo  = Split-Path $PSScriptRoot -Parent
$merge = Join-Path $repo "skills/upgrade-bootstrap/scripts/merge-settings.ps1"
$script:failures = 0
$script:checks   = 0

function Assert($cond, $msg) {
  $script:checks++
  if ($cond) { Write-Host "ok:   $msg" } else { Write-Host "FAIL: $msg"; $script:failures++ }
}

# Cantidad EXACTA de aserciones: sin esto, un mutante que borra asserts sale en verde.
$ExpectedChecks = 8

. (Join-Path $PSScriptRoot "lib\temp-workspace.ps1")
$script:runRoot = New-TestRunRoot "mset"
trap { Remove-TestRunRoot $script:runRoot; break }

$RLT = 'pwsh -NoProfile -File "${CLAUDE_PROJECT_DIR}/.claude/hooks/review-loop-trigger.ps1"'
$AG  = 'pwsh -NoProfile -File "${CLAUDE_PROJECT_DIR}/.claude/hooks/alignment-gate.ps1"'

function Entry($matcher, $command) {
  $e = [ordered]@{}
  if ($null -ne $matcher) { $e.matcher = $matcher }
  $e.hooks = @([ordered]@{ type = "command"; command = $command })
  $e
}
function Write-Settings($path, $obj) {
  [IO.Directory]::CreateDirectory((Split-Path $path -Parent)) | Out-Null
  $obj | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $path -Encoding UTF8
}
function Read-Settings($path) { Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -AsHashtable }
function Invoke-Merge($proj, $canon) {
  $out = & pwsh -NoProfile -File $merge -ProjectSettings $proj -CanonicalSettings $canon
  if ($LASTEXITCODE -ne 0) { throw "merge-settings salio $LASTEXITCODE" }
  $out -join "`n"
}
function Matchers($settings, $event, $command) {
  @($settings.hooks[$event] | Where-Object { $_.hooks[0].command -eq $command } | ForEach-Object { $_.matcher })
}

try {
  $canon = Join-Path $script:runRoot "canon\settings.json"
  Write-Settings $canon ([ordered]@{ hooks = [ordered]@{
    PreToolUse  = @(Entry "Edit|Write|MultiEdit" $AG)
    PostToolUse = @(Entry "Bash|PowerShell" $RLT) } })

  # (1) El caso de Forecasting: el hook está, con un matcher más angosto que el canónico.
  $p1 = Join-Path $script:runRoot "p1\settings.json"
  Write-Settings $p1 ([ordered]@{ hooks = [ordered]@{
    PreToolUse  = @(Entry "Edit|Write|MultiEdit" $AG)
    PostToolUse = @(Entry "Bash" $RLT) } })
  Invoke-Merge $p1 $canon | Out-Null
  $s1 = Read-Settings $p1
  Assert ((Matchers $s1 "PostToolUse" $RLT) -join ";" -eq "Bash|PowerShell") `
    "matcher angosto: 'Bash' pasa a 'Bash|PowerShell'"
  Assert (@($s1.hooks.PostToolUse).Count -eq 1) "matcher angosto: no duplica la entrada del hook"

  # (2) Idempotencia: la segunda corrida no cambia ni un byte.
  $antes = [IO.File]::ReadAllBytes($p1)
  $msg = Invoke-Merge $p1 $canon
  Assert ([Convert]::ToBase64String($antes) -eq [Convert]::ToBase64String([IO.File]::ReadAllBytes($p1))) `
    "idempotente: la segunda corrida deja el archivo igual"
  Assert ($msg -match "nothing to do") "idempotente: la segunda corrida informa que no hay nada que hacer"

  # (3) Alternativas propias del proyecto: se conservan, en su orden, y se suman las que faltan.
  $p3 = Join-Path $script:runRoot "p3\settings.json"
  Write-Settings $p3 ([ordered]@{ hooks = [ordered]@{
    PreToolUse  = @(Entry "Edit|Write|MultiEdit" $AG)
    PostToolUse = @(Entry "Bash|mcp__x" $RLT) } })
  Invoke-Merge $p3 $canon | Out-Null
  Assert ((Matchers (Read-Settings $p3) "PostToolUse" $RLT) -join ";" -eq "Bash|mcp__x|PowerShell") `
    "matcher propio: conserva 'mcp__x' y agrega 'PowerShell' al final"

  # (4) Una entrada del proyecto sin matcher matchea todo: no se le agrega uno.
  $p4 = Join-Path $script:runRoot "p4\settings.json"
  Write-Settings $p4 ([ordered]@{ hooks = [ordered]@{
    PreToolUse  = @(Entry "Edit|Write|MultiEdit" $AG)
    PostToolUse = @(Entry $null $RLT) } })
  Invoke-Merge $p4 $canon | Out-Null
  $e4 = @((Read-Settings $p4).hooks.PostToolUse)[0]
  Assert (-not $e4.ContainsKey("matcher")) "sin matcher: la entrada del proyecto queda sin matcher"

  # (5) Lo de antes sigue: un hook ausente se agrega entero, y la config ajena se respeta.
  $p5 = Join-Path $script:runRoot "p5\settings.json"
  Write-Settings $p5 ([ordered]@{ permissions = [ordered]@{ allow = @("Bash(git status)") }
    hooks = [ordered]@{ PostToolUse = @(Entry "Bash|PowerShell" $RLT) } })
  Invoke-Merge $p5 $canon | Out-Null
  $s5 = Read-Settings $p5
  Assert ((Matchers $s5 "PreToolUse" $AG) -join ";" -eq "Edit|Write|MultiEdit") "hook ausente: alignment-gate se agrega con su matcher"
  Assert ($s5.permissions.allow -contains "Bash(git status)") "config ajena: los permisos del proyecto quedan"
}
finally {
  Remove-TestRunRoot $script:runRoot
}
Remove-TestRunRoot $script:runRoot

$corridas = $script:checks
Assert ($corridas -eq $ExpectedChecks) `
  "se corrieron las $ExpectedChecks aserciones declaradas (contadas: $corridas)"
if ($script:failures -gt 0) { Write-Host "`n$($script:failures) FAIL"; exit 1 }
Write-Host "`nOK ($corridas)"
