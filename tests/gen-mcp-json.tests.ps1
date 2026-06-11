# tests/gen-mcp-json.tests.ps1 — runner sin Pester. Correr: pwsh -NoProfile -File tests/gen-mcp-json.tests.ps1
$ErrorActionPreference = "Stop"
$repo       = Split-Path $PSScriptRoot -Parent
$personal   = Join-Path $repo "skills/bootstrap-personal-project/scripts/gen-mcp-json.ps1"
$southpoint = Join-Path $repo "skills/bootstrap-southpoint-project/scripts/gen-mcp-json.ps1"
$script:failures = 0

function Assert($cond, $msg) {
  if ($cond) { Write-Host "ok:   $msg" } else { Write-Host "FAIL: $msg"; $script:failures++ }
}
function NewTmp {
  $d = Join-Path ([IO.Path]::GetTempPath()) ("mcp-test-" + [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $d | Out-Null; $d
}
# Corre el script como subproceso; devuelve @{ exit; out } (out = stdout crudo)
function RunScript($scriptPath, [string[]]$ServerArgs, $ProjectDir, [switch]$Force) {
  $a = @("-NoProfile","-File",$scriptPath,"-ProjectDir",$ProjectDir)
  if ($ServerArgs.Count) { $a += @("-Servers"); $a += ($ServerArgs -join ",") }
  if ($Force) { $a += "-Force" }
  $out = & pwsh @a 2>$null
  @{ exit = $LASTEXITCODE; out = ($out | Out-String) }
}

# --- PERSONAL: happy path ---
$t = NewTmp
$r = RunScript $personal @("firebase","zoho-personal") $t
Assert ($r.exit -eq 0) "personal happy: exit 0"
$mcpPath = Join-Path $t ".mcp.json"
Assert (Test-Path $mcpPath) "personal happy: .mcp.json existe"
$doc = Get-Content $mcpPath -Raw | ConvertFrom-Json
Assert ($null -ne $doc.mcpServers.firebase) "personal happy: tiene firebase"
Assert ($null -ne $doc.mcpServers.'zoho-personal') "personal happy: tiene zoho-personal"
Assert ($null -eq $doc.mcpServers.github) "personal happy: NO tiene github"
Assert ($doc.mcpServers.'zoho-personal'.url -eq '${ZOHO_PERSONAL_MCP_URL}') "personal happy: url literal con env var"
$summary = $r.out | ConvertFrom-Json
Assert ($summary.written -eq $true) "personal happy: summary.written=true"
Assert ($summary.requiredEnvVars -contains "ZOHO_PERSONAL_MCP_URL") "personal happy: reporta ZOHO_PERSONAL_MCP_URL"

# --- PERSONAL: ninguna seleccion ---
$t2 = NewTmp
$r2 = RunScript $personal @() $t2
Assert ($r2.exit -eq 0) "personal none: exit 0"
Assert (-not (Test-Path (Join-Path $t2 ".mcp.json"))) "personal none: no crea archivo"
$s2 = $r2.out | ConvertFrom-Json
Assert ($s2.written -eq $false) "personal none: summary.written=false"

# --- PERSONAL: clave invalida ---
$t3 = NewTmp
$r3 = RunScript $personal @("firebase","no-existe") $t3
Assert ($r3.exit -ne 0) "personal invalida: exit != 0 (error)"
Assert (-not (Test-Path (Join-Path $t3 ".mcp.json"))) "personal invalida: no escribe archivo"

# --- PERSONAL: no pisa sin -Force ---
$t4 = NewTmp
RunScript $personal @("firebase") $t4 | Out-Null
Set-Content (Join-Path $t4 ".mcp.json") -Value '{"mcpServers":{"SENTINEL":{}}}' -Encoding UTF8
$r4 = RunScript $personal @("zoho-personal") $t4
Assert ($r4.exit -ne 0) "personal no-force: exit != 0 (error)"
$keep = Get-Content (Join-Path $t4 ".mcp.json") -Raw | ConvertFrom-Json
Assert ($null -ne $keep.mcpServers.SENTINEL) "personal no-force: no piso el archivo existente"

# --- PERSONAL: -Force sobrescribe ---
$r5 = RunScript $personal @("zoho-personal") $t4 -Force
Assert ($r5.exit -eq 0) "personal force: exit 0"
$ovr = Get-Content (Join-Path $t4 ".mcp.json") -Raw | ConvertFrom-Json
Assert ($null -eq $ovr.mcpServers.SENTINEL) "personal force: reemplazo el contenido"
Assert ($null -ne $ovr.mcpServers.'zoho-personal') "personal force: nuevo server presente"

Write-Host ""
if ($script:failures -gt 0) { Write-Host "$($script:failures) test(s) FALLARON"; exit 1 } else { Write-Host "TODOS LOS TESTS PASARON"; exit 0 }
