# export-shareable.ps1 — publica las skills compartibles a un clon local del repo público.
# Copia limpia (borra el destino de cada skill primero) + gate anti-fuga: si el árbol exportado
# contiene un marcador de tools/leak-markers.txt, aborta con exit != 0 y lista los hits.
# El commit/push en el clon es SIEMPRE manual (revisar el diff antes).
# Uso: pwsh -NoProfile -File tools/export-shareable.ps1 -PublicRepoDir <clon local del repo publico>
param([Parameter(Mandatory)][string]$PublicRepoDir)
$ErrorActionPreference = "Stop"
$repo = Split-Path $PSScriptRoot -Parent

if (-not (Test-Path (Join-Path $PublicRepoDir ".git"))) {
    throw "PublicRepoDir is not a git clone: $PublicRepoDir"
}

# 1. Manifest fresco para que el scaffold exportado lleve hashes actuales
& (Join-Path $PSScriptRoot "gen-manifest.ps1") -SkillDir (Join-Path $repo "skills/bootstrap-ai-project")

# 2. Copia limpia del payload
$skillsDest = Join-Path $PublicRepoDir "skills"
[IO.Directory]::CreateDirectory($skillsDest) | Out-Null
foreach ($name in @("bootstrap-ai-project", "upgrade-bootstrap")) {
    $dest = Join-Path $skillsDest $name
    if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
    Copy-Item (Join-Path $repo "skills/$name") $dest -Recurse
}
Copy-Item (Join-Path $repo "public/README.md")   (Join-Path $PublicRepoDir "README.md")   -Force
Copy-Item (Join-Path $repo "public/install.ps1") (Join-Path $PublicRepoDir "install.ps1") -Force

# 3. Gate anti-fuga sobre TODO el árbol exportado (menos .git)
$markers = @(Get-Content (Join-Path $PSScriptRoot "leak-markers.txt") | Where-Object { $_.Trim() })
$hits = @()
foreach ($f in (Get-ChildItem $PublicRepoDir -Recurse -File -Force | Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' })) {
    $text = Get-Content -LiteralPath $f.FullName -Raw
    foreach ($m in $markers) {
        if ($text -match [regex]::Escape($m)) { $hits += "$($f.FullName): '$m'" }
    }
}
if ($hits.Count) {
    $hits | ForEach-Object { Write-Host "LEAK: $_" }
    throw "Export aborted: $($hits.Count) leak marker hit(s). Fix the source in this repo and re-export."
}

Write-Host "Export complete. Review the diff in $PublicRepoDir, then commit and push manually."
