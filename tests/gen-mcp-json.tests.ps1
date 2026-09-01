# tests/gen-mcp-json.tests.ps1 — runner sin Pester. Correr: pwsh -NoProfile -File tests/gen-mcp-json.tests.ps1
$ErrorActionPreference = "Stop"
$repo       = Split-Path $PSScriptRoot -Parent
$personal   = Join-Path $repo "skills/bootstrap-personal-project/scripts/gen-mcp-json.ps1"
$southpoint = Join-Path $repo "skills/bootstrap-southpoint-project/scripts/gen-mcp-json.ps1"
$shareable  = Join-Path $repo "skills/bootstrap-ai-project/scripts/gen-mcp-json.ps1"
$script:failures = 0
. (Join-Path $PSScriptRoot "lib\temp-workspace.ps1")
$script:runRoot = New-TestRunRoot "mcp"
trap { Remove-TestRunRoot $script:runRoot; break }

function Assert($cond, $msg) {
  if ($cond) { Write-Host "ok:   $msg" } else { Write-Host "FAIL: $msg"; $script:failures++ }
}
# Esta suite era el caso medido más claro de la fuga: contados sobre la versión anterior, 8 llamadas
# a NewTmp y 2 Remove-Item, o sea 6 workspaces filtrados por corrida.
function NewTmp {
  return (New-TestWorkspace $script:runRoot "mcp-test")
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

# --- SOUTHPOINT: domo + zoho-projects ---
$ts = NewTmp
$rs = RunScript $southpoint @("domo","zoho-projects") $ts
Assert ($rs.exit -eq 0) "southpoint happy: exit 0"
$sd = Get-Content (Join-Path $ts ".mcp.json") -Raw | ConvertFrom-Json
Assert ($null -ne $sd.mcpServers.domo) "southpoint happy: tiene domo"
Assert ($sd.mcpServers.domo.env.DOMO_DEVELOPER_TOKEN -eq '${DOMO_SOUTHPOINT_TOKEN}') "southpoint happy: token domo por env var"
Assert ($sd.mcpServers.domo.env.PYTHONPATH -eq '${DOMO_MCP_HOME}') "southpoint happy: PYTHONPATH domo apunta a DOMO_MCP_HOME (clone)"
Assert ($sd.mcpServers.'zoho-projects'.url -eq '${ZOHO_SOUTHPOINT_MCP_URL}') "southpoint happy: url zoho southpoint"
$ss = $rs.out | ConvertFrom-Json
Assert ($ss.requiredEnvVars -contains "DOMO_SOUTHPOINT_TOKEN") "southpoint happy: reporta DOMO_SOUTHPOINT_TOKEN"
Assert ($ss.requiredEnvVars -contains "DOMO_MCP_HOME") "southpoint happy: reporta DOMO_MCP_HOME"

# --- SOUTHPOINT: zoho-personal NO existe en este catalogo ---
$ts2 = NewTmp
$rs2 = RunScript $southpoint @("zoho-personal") $ts2
Assert ($rs2.exit -ne 0) "southpoint: zoho-personal invalida en area southpoint"

# --- SHAREABLE: happy path firebase+github ---
$tsh = NewTmp
$rsh = RunScript $shareable @("firebase","github") $tsh
Assert ($rsh.exit -eq 0) "shareable happy: exit 0"
$shd = Get-Content (Join-Path $tsh ".mcp.json") -Raw | ConvertFrom-Json
Assert ($null -ne $shd.mcpServers.firebase -and $null -ne $shd.mcpServers.github) "shareable happy: firebase y github presentes"
Remove-Item -Recurse -Force $tsh

# --- SHAREABLE: zoho-personal NO existe en este catalogo ---
$tsh2 = NewTmp
$rsh2 = RunScript $shareable @("zoho-personal") $tsh2
Assert ($rsh2.exit -ne 0) "shareable: zoho-personal invalido en el catalogo compartible"
Remove-Item -Recurse -Force $tsh2

Remove-TestRunRoot $script:runRoot

Write-Host ""
if ($script:failures -gt 0) { Write-Host "$($script:failures) test(s) FALLARON"; exit 1 } else { Write-Host "TODOS LOS TESTS PASARON"; exit 0 }
