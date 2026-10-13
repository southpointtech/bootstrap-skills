# export-changelog.ps1 — copia el CHANGELOG.md al repo público sin las entradas de la variante Southpoint.
# Saca por ESTRUCTURA, nada más: una sección `###` cuyo título pega con un marcador de
# tools/leak-markers.txt (con todo su cuerpo, hasta el próximo `##`/`###`), y un ítem de lista cuyo
# texto —con sus líneas de continuación indentadas— pega con uno. Un marcador en un párrafo suelto
# NO se toca: lo frena el gate anti-fuga de export-shareable.ps1 y se arregla en la fuente.
# Lo que saca lo lista por stdout, para el que revisa el diff del clon.
# Uso: pwsh -NoProfile -File tools/export-changelog.ps1 -Source <CHANGELOG.md> -Dest <ruta> [-Markers <leak-markers.txt>]
param(
    [Parameter(Mandatory)][string]$Source,
    [Parameter(Mandatory)][string]$Dest,
    [string]$Markers = (Join-Path $PSScriptRoot "leak-markers.txt")
)
$ErrorActionPreference = "Stop"

# $markerList y no $markers: los nombres no distinguen mayúsculas, y asignarle un array a $Markers
# (el parámetro, tipado [string]) lo coacciona a un solo string unido por espacios que nunca pega.
$markerList = @(Get-Content -LiteralPath $Markers | ForEach-Object { $_.Trim() } | Where-Object { $_ })
function Hit($text) { foreach ($m in $markerList) { if ($text -imatch [regex]::Escape($m)) { return $true } }; $false }

$raw = Get-Content -LiteralPath $Source -Raw
$eol = if ($raw -match "`r`n") { "`r`n" } else { "`n" }
$lines = $raw -split "`r?`n"

$kept = [Collections.Generic.List[string]]::new()
$dropped = [Collections.Generic.List[string]]::new()
$inDroppedSection = $false
$i = 0
while ($i -lt $lines.Count) {
    $line = $lines[$i]
    if ($line -match '^### ') {
        $inDroppedSection = Hit $line
        if ($inDroppedSection) { $dropped.Add("section: $line") } else { $kept.Add($line) }
        $i++; continue
    }
    if ($line -match '^##? ') { $inDroppedSection = $false; $kept.Add($line); $i++; continue }
    if ($inDroppedSection) { $i++; continue }
    if ($line -match '^[-*] ') {
        # El ítem es esta línea más las de continuación indentadas que la siguen.
        $item = [Collections.Generic.List[string]]::new(); $item.Add($line); $j = $i + 1
        while ($j -lt $lines.Count -and $lines[$j] -match '^\s+\S') { $item.Add($lines[$j]); $j++ }
        if (Hit ($item -join "`n")) { $dropped.Add("item: $line") } else { $kept.AddRange($item) }
        $i = $j; continue
    }
    $kept.Add($line); $i++
}

[IO.Directory]::CreateDirectory((Split-Path -Parent $Dest)) | Out-Null
[IO.File]::WriteAllText($Dest, ($kept -join $eol), [Text.UTF8Encoding]::new($false))
Write-Host "Changelog exported to $Dest ($($dropped.Count) dropped):"
$dropped | ForEach-Object { Write-Host "  - $_" }
