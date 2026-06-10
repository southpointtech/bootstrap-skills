# Genera el manifest canónico (.bootstrap-manifest.json) de una skill bootstrap.
# Uso: pwsh -File tools/gen-manifest.ps1 -SkillDir <ruta a la skill que contiene assets\scaffold>
param([Parameter(Mandatory)][string]$SkillDir)
$ErrorActionPreference = "Stop"

$scaffold = Join-Path $SkillDir "assets\scaffold"
if (-not (Test-Path $scaffold)) { throw "No existe el scaffold: $scaffold" }
$skillName = Split-Path $SkillDir -Leaf
$variant = if ($skillName -like "*southpoint*") { "southpoint" } else { "personal" }
$scaffoldFull = (Resolve-Path $scaffold).Path

$files = @{}
Get-ChildItem $scaffold -Recurse -File -Force | ForEach-Object {
    $rel = $_.FullName.Substring($scaffoldFull.Length).TrimStart('\','/').Replace('\','/')
    if ($rel -eq ".bootstrap-manifest.json") { return }            # auto-exclusión
    $dest = if ($rel -eq "gitignore.txt") { ".gitignore" } else { $rel }  # mapeo a ruta de destino
    $files[$dest] = (Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLower()
}

# version = fecha + hash corto del conjunto (rutas+hashes ordenados)
$concat = ($files.GetEnumerator() | Sort-Object Name | ForEach-Object { "$($_.Name):$($_.Value)" }) -join "`n"
$sha = [System.Security.Cryptography.SHA256]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes($concat))
$setHash = ([System.BitConverter]::ToString($sha).Replace("-","").ToLower()).Substring(0,7)
$date = (Get-Date -Format "yyyy-MM-dd")

$ordered = [ordered]@{}
$files.GetEnumerator() | Sort-Object Name | ForEach-Object { $ordered[$_.Name] = $_.Value }
$manifest = [ordered]@{
    variant       = $variant
    generatedFrom = $skillName
    version       = "$date+$setHash"
    files         = $ordered
}

$out = Join-Path $scaffold ".bootstrap-manifest.json"
$manifest | ConvertTo-Json -Depth 5 | Set-Content $out -Encoding UTF8
Write-Host "Manifest generado: $out ($($files.Count) archivos, version $date+$setHash)"
