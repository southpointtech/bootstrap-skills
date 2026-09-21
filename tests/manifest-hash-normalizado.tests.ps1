# tests/manifest-hash-normalizado.tests.ps1 — runner sin Pester. Correr: pwsh -NoProfile -File tests/manifest-hash-normalizado.tests.ps1
#
# Cubre la mitad del issue 03 que quedó sin hacer (03b): los tres consumidores del hash de manifest
# —`tools/gen-manifest.ps1`, y `compare-scaffold.ps1` / `reseal-manifest.ps1` de upgrade-bootstrap—
# hashean con la función normalizada (`Get-NormalizedHash`) y no con los bytes crudos. Sin eso, el
# mismo árbol sellado desde dos checkouts con fines de línea distintos da manifests distintos (medido
# el 2026-09-21: 6 archivos entre el worktree v2 y `main`), y un proyecto con el archivo canónico
# intacto pero en CRLF se reporta como customizado.
#
# La transición es parte del contrato: los proyectos ya bootstrapeados tienen manifests sellados con
# el hash CRUDO. Un hash crudo coincide con el normalizado solo si el archivo era LF; para un base
# crudo de un archivo CRLF, la regla es "el base coincide si coincide el hash crudo O el normalizado
# del archivo actual". Coincidir en crudo es tener los mismos bytes, así que no puede marcar como
# intacto un archivo tocado. Los casos "legacy" de abajo fijan esa regla.
$ErrorActionPreference = "Stop"
$repo = Split-Path $PSScriptRoot -Parent
$genManifest = Join-Path $repo "tools/gen-manifest.ps1"
$compare     = Join-Path $repo "skills/upgrade-bootstrap/scripts/compare-scaffold.ps1"
$reseal      = Join-Path $repo "skills/upgrade-bootstrap/scripts/reseal-manifest.ps1"
$nhTools     = Join-Path $repo "tools/normalized-hash.ps1"
$nhSkill     = Join-Path $repo "skills/upgrade-bootstrap/scripts/normalized-hash.ps1"
$script:failures = 0
$script:checks   = 0

function Assert($cond, $msg) {
  $script:checks++
  if ($cond) { Write-Host "ok:   $msg" } else { Write-Host "FAIL: $msg"; $script:failures++ }
}

# Cantidad EXACTA de aserciones (ver normalized-hash.tests.ps1: sin esto, un mutante que borra
# asserts sale en verde).
$ExpectedChecks = 16

. (Join-Path $PSScriptRoot "lib\temp-workspace.ps1")
$script:runRoot = New-TestRunRoot "mhn"
trap { Remove-TestRunRoot $script:runRoot; break }

. (Join-Path $PSScriptRoot "..\tools\normalized-hash.ps1")

# Literales CONGELADOS, calculados fuera de la función bajo prueba (hashlib.sha256 de Python):
#   b"uno\ndos\n"     -> 3286d72d...
#   b"uno\r\ndos\r\n" -> daf05a2d...  (el hash CRUDO del mismo contenido en CRLF)
$H_LF   = "3286d72d1182cc61f3b0a26662e6d0e1c769e0001a3d98c921e517ab49eb81ec"
$H_CRLF = "daf05a2d5f69dbf8b25c3624d6aeea5f19fa34c1347ba24168ababc3a6618ac2"
$LF     = [Text.Encoding]::ASCII.GetBytes("uno`ndos`n")
$CRLF   = [Text.Encoding]::ASCII.GetBytes("uno`r`ndos`r`n")
$OTRO   = [Text.Encoding]::ASCII.GetBytes("otro`n")
$OTRO_CRLF = [Text.Encoding]::ASCII.GetBytes("otro`r`n")
$TOCADO = [Text.Encoding]::ASCII.GetBytes("uno`r`ndos`r`nlocal`r`n")

# Bytes crudos: Set-Content reescribiría el fin de línea, que es justo lo que se mide.
function Write-Raw($dir, $rel, [byte[]]$bytes) {
  $p = Join-Path $dir $rel
  [IO.Directory]::CreateDirectory((Split-Path $p -Parent)) | Out-Null
  [IO.File]::WriteAllBytes($p, $bytes)
}
function Read-Manifest($path) { Get-Content -LiteralPath $path -Raw | ConvertFrom-Json }
function Write-Manifest($dir, [hashtable]$files) {
  $m = [ordered]@{ variant = "ai"; generatedFrom = "bootstrap-ai-project"; version = "vieja"; files = $files }
  $m | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $dir ".bootstrap-manifest.json") -Encoding UTF8
}
# Un scaffold canónico sintético, sellado por gen-manifest (el mismo camino que sync-skills).
function New-Canon([hashtable]$files) {
  $skill = New-TestWorkspace -Root $script:runRoot -Name "skill"
  $scaf = Join-Path $skill "assets\scaffold"
  foreach ($k in $files.Keys) { Write-Raw $scaf $k $files[$k] }
  & pwsh -NoProfile -File $genManifest -SkillDir $skill | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "gen-manifest salio $LASTEXITCODE" }
  return $scaf
}
function Compare-Project($proj, $scaf) {
  $out = & pwsh -NoProfile -File $compare -ProjectDir $proj -CanonicalScaffold $scaf
  if ($LASTEXITCODE -ne 0) { throw "compare-scaffold salio $LASTEXITCODE" }
  return ($out -join "`n" | ConvertFrom-Json)
}
function Names($list) { @($list | ForEach-Object { if ($_ -is [string]) { $_ } else { $_.file } }) }

try {
  # ---- La función del skill es la de tools: una sola función, dos copias por el deploy. ----
  # upgrade-bootstrap corre desde ~/.claude/skills y no ve tools/, así que lleva su copia. Se compara
  # normalizado: con autocrlf, cada checkout puede escribir las dos copias con otro fin de línea.
  Assert ((Test-Path -LiteralPath $nhSkill) -and
          ((Get-NormalizedHash -Path $nhSkill) -eq (Get-NormalizedHash -Path $nhTools))) `
    "skills/upgrade-bootstrap/scripts/normalized-hash.ps1 es idéntica a tools/normalized-hash.ps1 (salvo fin de línea)"

  # ---- gen-manifest ----
  $scafLF   = New-Canon @{ "a.md" = $LF }
  $scafCRLF = New-Canon @{ "a.md" = $CRLF }
  $hLF   = (Read-Manifest (Join-Path $scafLF ".bootstrap-manifest.json")).files.'a.md'
  $hCRLF = (Read-Manifest (Join-Path $scafCRLF ".bootstrap-manifest.json")).files.'a.md'
  Assert ($hLF -eq $H_LF) "gen-manifest: el contenido LF sella el sha256 congelado (fija el algoritmo)"
  Assert ($hCRLF -eq $H_LF) "gen-manifest: el mismo contenido en CRLF sella el MISMO hash (era $H_CRLF crudo)"
  $vLF   = (Read-Manifest (Join-Path $scafLF ".bootstrap-manifest.json")).version
  $vCRLF = (Read-Manifest (Join-Path $scafCRLF ".bootstrap-manifest.json")).version
  Assert ($vLF -eq $vCRLF) "gen-manifest: la version (hash del conjunto) no depende del fin de línea"

  # ---- compare-scaffold ----
  # Canónico: a.md ("uno dos"); b.md, c.md, d.md y e.md ("otro"). La base vieja de c.md y d.md es
  # "uno dos": el canónico se movió desde ahí.
  $scaf = New-Canon @{ "a.md" = $LF; "b.md" = $OTRO; "c.md" = $OTRO; "d.md" = $OTRO; "e.md" = $OTRO }

  # (1) Proyecto con manifest NUEVO (normalizado), archivos en CRLF.
  $p1 = New-TestWorkspace -Root $script:runRoot -Name "p1"
  Write-Raw $p1 "a.md" $CRLF          # igual al canónico, en CRLF          -> uptodate
  Write-Raw $p1 "c.md" $CRLF          # intacto desde su base ("uno dos")   -> outdated
  Write-Raw $p1 "d.md" $TOCADO        # tocado                              -> customized
  Write-Manifest $p1 @{ "a.md" = $H_LF; "c.md" = $H_LF; "d.md" = $H_LF }
  $r1 = Compare-Project $p1 $scaf
  Assert ((Names $r1.uptodate) -contains "a.md") "compare: el archivo canónico en CRLF es uptodate, no customized"
  Assert ((Names $r1.outdated) -contains "c.md") "compare: base normalizada + archivo intacto en CRLF es outdated"
  Assert ((Names $r1.customized) -contains "d.md") "compare: un archivo tocado sigue siendo customized"
  Assert ((Names $r1.missing) -contains "b.md") "compare: el que falta sigue siendo missing"

  # (2) Proyecto LEGACY: manifest sellado con el hash CRUDO de archivos CRLF.
  $p2 = New-TestWorkspace -Root $script:runRoot -Name "p2"
  Write-Raw $p2 "c.md" $CRLF          # intacto, mismos bytes que su base cruda   -> outdated
  Write-Raw $p2 "d.md" $TOCADO        # tocado respecto de su base cruda          -> customized
  Write-Raw $p2 "e.md" $OTRO_CRLF     # igual al canónico nuevo, base cruda vieja -> uptodate
  Write-Manifest $p2 @{ "c.md" = $H_CRLF; "d.md" = $H_CRLF; "e.md" = $H_CRLF }
  $r2 = Compare-Project $p2 $scaf
  Assert ((Names $r2.outdated) -contains "c.md") "compare legacy: base cruda CRLF + archivo intacto es outdated, no customized"
  Assert ((Names $r2.customized) -contains "d.md") "compare legacy: base cruda + archivo tocado es customized"
  Assert ((Names $r2.uptodate) -contains "e.md") "compare legacy: el archivo ya igual al canónico es uptodate"

  # ---- reseal-manifest ----
  # Sobre el proyecto legacy: a.md llega actualizado en CRLF, c.md se saltea (queda viejo e intacto),
  # d.md queda customizado.
  Write-Raw $p2 "a.md" $CRLF
  & pwsh -NoProfile -File $reseal -ProjectDir $p2 -CanonicalScaffold $scaf | Out-Null
  Assert ($LASTEXITCODE -eq 0) "reseal: sale 0"
  $m2 = (Read-Manifest (Join-Path $p2 ".bootstrap-manifest.json")).files
  Assert ($m2.'a.md' -eq $H_LF) "reseal: el archivo reconciliado en CRLF sella el hash normalizado del canónico"
  Assert ($m2.'c.md' -eq $H_LF) "reseal: la base cruda de un archivo intacto se convierte a su hash normalizado"
  Assert ($m2.'d.md' -eq $H_CRLF) "reseal: la base cruda de un archivo customizado se conserva (no se siembra con lo tocado)"

  # Ida y vuelta: después del reseal, el proyecto no reporta drift falso.
  $r3 = Compare-Project $p2 $scaf
  Assert (((Names $r3.uptodate) -contains "a.md") -and ((Names $r3.outdated) -contains "c.md") -and
          ((Names $r3.customized) -contains "d.md")) `
    "compare tras reseal: a.md uptodate, c.md outdated y d.md customized (sin drift falso)"
}
finally {
  Remove-TestRunRoot $script:runRoot
}
Remove-TestRunRoot $script:runRoot

$corridas = $script:checks
Assert ($corridas -eq $ExpectedChecks) `
  "se corrieron las $ExpectedChecks aserciones declaradas (contadas: $corridas)"

if ($script:failures -gt 0) { Write-Host "`n$($script:failures) FAIL"; exit 1 }
Write-Host "`nTodo verde ($corridas aserciones + el guard de conteo)"
