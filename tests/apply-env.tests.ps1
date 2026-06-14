# tests/apply-env.tests.ps1 — runner sin Pester. Correr: pwsh -NoProfile -File tests/apply-env.tests.ps1
$ErrorActionPreference = "Stop"
$repo   = Split-Path $PSScriptRoot -Parent
$script = Join-Path $repo "skills/setup-mcp-workstation/scripts/apply-env.ps1"
$script:failures = 0

function Assert($cond, $msg) {
  if ($cond) { Write-Host "ok:   $msg" } else { Write-Host "FAIL: $msg"; $script:failures++ }
}
function NewCfg([string]$json) {
  $p = Join-Path ([IO.Path]::GetTempPath()) ("wscfg-" + [guid]::NewGuid().ToString('N') + ".json")
  Set-Content -Path $p -Value $json -Encoding UTF8; $p
}
function Run($cfgPath) {
  $out = & pwsh -NoProfile -File $script -ConfigPath $cfgPath -DryRun 2>$null
  @{ exit = $LASTEXITCODE; out = ($out | Out-String) }
}

$validJson = @'
{ "git": { "name": "Ada Lovelace", "email": "ada@agtium.com" },
  "domo": { "token": "SECRET-DOMO-123" },
  "zoho": { "mcpUrl": "https://zoho.example/mcp/abc" } }
'@

# --- happy path (dry-run) ---
$cfg = NewCfg $validJson
$r = Run $cfg
Assert ($r.exit -eq 0) "happy: exit 0"
$sum = $r.out | ConvertFrom-Json
Assert ($sum.dryRun -eq $true) "happy: dryRun=true"
$names = @($sum.vars | ForEach-Object { $_.name })
Assert ($names -contains "SOUTHPOINT_GIT_NAME")     "happy: setea SOUTHPOINT_GIT_NAME"
Assert ($names -contains "SOUTHPOINT_GIT_EMAIL")    "happy: setea SOUTHPOINT_GIT_EMAIL"
Assert ($names -contains "DOMO_SOUTHPOINT_TOKEN")   "happy: setea DOMO_SOUTHPOINT_TOKEN"
Assert ($names -contains "ZOHO_SOUTHPOINT_MCP_URL") "happy: setea ZOHO_SOUTHPOINT_MCP_URL"
Assert ($names.Count -eq 4) "happy: exactamente 4 vars"

# --- NO filtra valores de secretos en la salida ---
Assert (-not ($r.out -match "SECRET-DOMO-123")) "seguridad: no imprime el token domo"
Assert (-not ($r.out -match "zoho.example"))    "seguridad: no imprime la url zoho"

# --- config con campo faltante ---
$bad = NewCfg '{ "git": { "name": "X", "email": "x@y.z" }, "domo": { "token": "t" } }'
$rb = & pwsh -NoProfile -File $script -ConfigPath $bad -DryRun 2>&1
Assert ($LASTEXITCODE -ne 0) "faltante: exit != 0"
Assert ("$rb" -match "zoho")  "faltante: el error menciona el campo zoho"

# --- config inexistente ---
& pwsh -NoProfile -File $script -ConfigPath (Join-Path ([IO.Path]::GetTempPath()) "no-existe-xyz.json") -DryRun 2>&1 | Out-Null
Assert ($LASTEXITCODE -ne 0) "inexistente: exit != 0"

Write-Host ""
if ($script:failures -gt 0) { Write-Host "$($script:failures) test(s) FALLARON"; exit 1 } else { Write-Host "TODOS LOS TESTS PASARON"; exit 0 }
