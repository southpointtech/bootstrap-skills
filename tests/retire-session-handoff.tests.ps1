# tests/retire-session-handoff.tests.ps1 — runner sin Pester. Correr: pwsh -NoProfile -File tests/retire-session-handoff.tests.ps1
# El script que saca el SESSION_HANDOFF.md heredado (raíz y docs/) de un proyecto bootstrapeado, contra
# repos git temporales: lo trackeado sale con `git rm`, lo demás va a .bootstrap-backup/ (ADR-0007).
$ErrorActionPreference = "Stop"
$repo    = Split-Path $PSScriptRoot -Parent
$retire  = Join-Path $repo "skills/bootstrap-personal-project/scripts/retire-session-handoff.ps1"
$script:failures = 0

function Assert($cond, $msg) {
  if ($cond) { Write-Host "ok:   $msg" } else { Write-Host "FAIL: $msg"; $script:failures++ }
}

. (Join-Path $PSScriptRoot "lib\temp-workspace.ps1")
$script:runRoot = New-TestRunRoot "rsh"
trap { Remove-TestRunRoot $script:runRoot; break }

# Un repo git con un commit inicial. Identidad y autocrlf por config local: la suite no depende de la
# config global de quien la corre.
function New-Repo([string]$name = "rsh-test") {
  $d = New-TestWorkspace $script:runRoot $name
  & git -C $d init -q
  & git -C $d config user.name "t"
  & git -C $d config user.email "t@t"
  & git -C $d config core.autocrlf false
  [IO.File]::WriteAllText((Join-Path $d "README.md"), "x`n")
  & git -C $d add README.md
  & git -C $d commit -q -m init
  return $d
}
function Write-File([string]$root, [string]$rel, [string]$text) {
  $p = Join-Path $root $rel
  [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($p)) | Out-Null
  [IO.File]::WriteAllText($p, $text)
}
function Commit-File([string]$root, [string]$rel, [string]$text) {
  Write-File $root $rel $text
  & git -C $root add -- $rel
  & git -C $root commit -q -m "add $rel"
}
function Invoke-Retire([string]$proj) {
  $out = & pwsh -NoProfile -File $retire -ProjectDir $proj
  $code = $LASTEXITCODE
  $json = $null
  try { $json = ($out -join "`n") | ConvertFrom-Json } catch { }
  return [pscustomobject]@{ exit = $code; json = $json; raw = ($out -join "`n") }
}
# Lo que `git status` ve, una línea por entrada. Es el estado observable del repo, no un detalle interno.
function Get-Status([string]$root) { return @(& git -C $root status --porcelain --untracked-files=all) }

# 1. Trackeado en la raíz -> git rm (queda staged como borrado, sin commitear)
$t = New-Repo
Commit-File $t "SESSION_HANDOFF.md" "# handoff viejo`n"
$r = Invoke-Retire $t
Assert ($r.exit -eq 0) "1: exit 0 (salida: $($r.raw))"
Assert (@($r.json.removed) -contains "SESSION_HANDOFF.md") "1: el reporte lista SESSION_HANDOFF.md en removed"
Assert (@($r.json.backedUp).Count -eq 0) "1: nada en backedUp"
Assert (-not (Test-Path -LiteralPath (Join-Path $t "SESSION_HANDOFF.md"))) "1: el archivo ya no está en disco"
$st = Get-Status $t
Assert ($st -contains "D  SESSION_HANDOFF.md") "1: git status lo muestra como borrado staged (status: $($st -join ' | '))"
Assert ((& git -C $t rev-list --count HEAD) -eq "2") "1: el script no commiteó"

# 2. Trackeado en docs/ -> git rm, con el path en barras normales
$t = New-Repo
Commit-File $t "docs/SESSION_HANDOFF.md" "# handoff viejo`n"
$r = Invoke-Retire $t
Assert ($r.exit -eq 0) "2: exit 0 (salida: $($r.raw))"
Assert (@($r.json.removed) -contains "docs/SESSION_HANDOFF.md") "2: el reporte lista docs/SESSION_HANDOFF.md en removed"
$st = Get-Status $t
Assert ($st -contains "D  docs/SESSION_HANDOFF.md") "2: git status lo muestra como borrado staged (status: $($st -join ' | '))"

# 3. Sin trackear -> a .bootstrap-backup/ con el mismo path relativo; git no lo toca
$t = New-Repo
Write-File $t "docs/SESSION_HANDOFF.md" "# suelto`n"
$r = Invoke-Retire $t
Assert ($r.exit -eq 0) "3: exit 0 (salida: $($r.raw))"
Assert (@($r.json.removed).Count -eq 0) "3: nada en removed"
$b = @($r.json.backedUp)
Assert ($b.Count -eq 1 -and $b[0].file -eq "docs/SESSION_HANDOFF.md" -and $b[0].backup -eq ".bootstrap-backup/docs/SESSION_HANDOFF.md") `
  "3: backedUp declara file y backup (reporte: $($r.raw))"
Assert (-not (Test-Path -LiteralPath (Join-Path $t "docs/SESSION_HANDOFF.md"))) "3: el original ya no está"
$bak = Join-Path $t ".bootstrap-backup/docs/SESSION_HANDOFF.md"
Assert ((Test-Path -LiteralPath $bak) -and [IO.File]::ReadAllText($bak) -eq "# suelto`n") "3: el respaldo tiene el contenido original"

# 4. Ignorado por .gitignore -> respaldo, y el .gitignore queda como estaba
$t = New-Repo
Commit-File $t ".gitignore" "SESSION_HANDOFF.md`n"
Write-File $t "SESSION_HANDOFF.md" "# ignorado`n"
$r = Invoke-Retire $t
Assert ($r.exit -eq 0) "4: exit 0 (salida: $($r.raw))"
$b = @($r.json.backedUp)
Assert ($b.Count -eq 1 -and $b[0].file -eq "SESSION_HANDOFF.md" -and $b[0].backup -eq ".bootstrap-backup/SESSION_HANDOFF.md") `
  "4: backedUp declara el ignorado (reporte: $($r.raw))"
Assert (@($r.json.removed).Count -eq 0) "4: nada en removed"
Assert (-not (Test-Path -LiteralPath (Join-Path $t "SESSION_HANDOFF.md"))) "4: el original ya no está"

# 5. Respaldo previo ocupado -> el nuevo va a .2, el viejo queda intacto, y el reporte nombra el .2
$t = New-Repo
Write-File $t ".bootstrap-backup/SESSION_HANDOFF.md" "# respaldo de otra corrida`n"
Write-File $t "SESSION_HANDOFF.md" "# el de ahora`n"
$r = Invoke-Retire $t
Assert ($r.exit -eq 0) "5: exit 0 (salida: $($r.raw))"
$b = @($r.json.backedUp)
Assert ($b.Count -eq 1 -and $b[0].backup -eq ".bootstrap-backup/SESSION_HANDOFF.md.2") "5: el backup del reporte es el .2 (reporte: $($r.raw))"
Assert ([IO.File]::ReadAllText((Join-Path $t ".bootstrap-backup/SESSION_HANDOFF.md")) -eq "# respaldo de otra corrida`n") "5: el respaldo viejo no se pisó"
$bak2 = Join-Path $t ".bootstrap-backup/SESSION_HANDOFF.md.2"
Assert ((Test-Path -LiteralPath $bak2) -and [IO.File]::ReadAllText($bak2) -eq "# el de ahora`n") "5: el .2 tiene el archivo de esta corrida"

# 6. Trackeado con cambios sin commitear -> git rm igual, pero lo que no estaba en HEAD se respalda antes:
#    un `git rm -f` pelado perdería justo la parte que nadie commiteó.
$t = New-Repo
Commit-File $t "SESSION_HANDOFF.md" "# commiteado`n"
Write-File $t "SESSION_HANDOFF.md" "# commiteado`n# y editado sin commitear`n"
$r = Invoke-Retire $t
Assert ($r.exit -eq 0) "6: exit 0 (salida: $($r.raw))"
Assert (@($r.json.removed) -contains "SESSION_HANDOFF.md") "6: está en removed"
$b = @($r.json.backedUp)
Assert ($b.Count -eq 1 -and $b[0].file -eq "SESSION_HANDOFF.md" -and $b[0].backup -eq ".bootstrap-backup/SESSION_HANDOFF.md") `
  "6: y en backedUp, con su backup (reporte: $($r.raw))"
$bak = Join-Path $t ".bootstrap-backup/SESSION_HANDOFF.md"
Assert ((Test-Path -LiteralPath $bak) -and [IO.File]::ReadAllText($bak) -eq "# commiteado`n# y editado sin commitear`n") "6: el respaldo tiene la versión editada"
$st = Get-Status $t
Assert ($st -contains "D  SESSION_HANDOFF.md") "6: git status lo muestra como borrado staged (status: $($st -join ' | '))"

# 6b. Agregado al índice pero nunca commiteado -> mismo trato: su contenido sólo vive en el árbol
$t = New-Repo
Write-File $t "docs/SESSION_HANDOFF.md" "# staged nunca commiteado`n"
& git -C $t add -- "docs/SESSION_HANDOFF.md"
$r = Invoke-Retire $t
Assert ($r.exit -eq 0) "6b: exit 0 (salida: $($r.raw))"
$b = @($r.json.backedUp)
Assert ($b.Count -eq 1 -and $b[0].file -eq "docs/SESSION_HANDOFF.md") "6b: se respaldó (reporte: $($r.raw))"
Assert (-not (Test-Path -LiteralPath (Join-Path $t "docs/SESSION_HANDOFF.md"))) "6b: el original ya no está"
# Path exacto y no un glob: `*docs/SESSION_HANDOFF.md` matchea también el respaldo, que git ve sin trackear.
Assert (@(Get-Status $t | Where-Object { $_.Substring(3) -eq "docs/SESSION_HANDOFF.md" }).Count -eq 0) "6b: git ya no lo ve (ni en el índice)"

# 7. Ningún archivo -> reporte vacío, exit 0, repo intacto y sin .bootstrap-backup/
$t = New-Repo
$antes = Get-Status $t
$r = Invoke-Retire $t
Assert ($r.exit -eq 0) "7: exit 0 (salida: $($r.raw))"
Assert ($null -ne $r.json -and @($r.json.removed).Count -eq 0 -and @($r.json.backedUp).Count -eq 0) "7: reporte vacío pero JSON válido (salida: $($r.raw))"
Assert ((@(Get-Status $t) -join '|') -eq ($antes -join '|')) "7: git status idéntico"
Assert (-not (Test-Path -LiteralPath (Join-Path $t ".bootstrap-backup"))) "7: no crea .bootstrap-backup/"

# 8. Proyecto con espacios y corchetes en el path: los dos caminos (git rm y respaldo) andan
$t = New-Repo "my app [v2]"
Commit-File $t "SESSION_HANDOFF.md" "# raíz`n"
Write-File $t "docs/SESSION_HANDOFF.md" "# docs suelto`n"
$r = Invoke-Retire $t
Assert ($r.exit -eq 0) "8: exit 0 (salida: $($r.raw))"
Assert (@($r.json.removed) -contains "SESSION_HANDOFF.md") "8: git rm del trackeado"
Assert (@($r.json.backedUp | ForEach-Object { $_.file }) -contains "docs/SESSION_HANDOFF.md") "8: respaldo del suelto"
Assert (Test-Path -LiteralPath (Join-Path $t ".bootstrap-backup/docs/SESSION_HANDOFF.md")) "8: el respaldo existe"

# 9. upgrade-bootstrap lo invoca desde la skill bootstrap del proyecto, sin cuarta copia, y con la
#    migración del agente ANTES del script, dentro de la aprobación que el upgrade ya pide.
$upgrade = Join-Path $repo "skills/upgrade-bootstrap"
$md = [IO.File]::ReadAllText((Join-Path $upgrade "SKILL.md"))
$invocacion = 'pwsh -File ~/.claude/skills/<generatedFrom>/scripts/retire-session-handoff.ps1 -ProjectDir "<project>"'
$iInv = $md.IndexOf($invocacion)
Assert ($iInv -ge 0) "9: SKILL.md invoca el script desde ~/.claude/skills/<generatedFrom>/scripts/"
Assert (-not (Test-Path -LiteralPath (Join-Path $upgrade "scripts/retire-session-handoff.ps1"))) "9: upgrade-bootstrap no trae una cuarta copia del script"
Assert (-not $md.Contains("<this-skill>/scripts/retire-session-handoff")) "9: ni lo busca en su propio scripts/"
# La sección que contiene la invocación: desde su `###` hasta el siguiente.
$iSec = $md.LastIndexOf("`n### ", [Math]::Max($iInv, 0))
$iFin = $md.IndexOf("`n### ", [Math]::Max($iInv, 0))
if ($iFin -lt 0) { $iFin = $md.Length }
$sec = if ($iInv -ge 0) { $md.Substring($iSec, $iFin - $iSec) } else { '' }
$iMig = $sec.IndexOf("migrate")
Assert ($iMig -ge 0 -and $iMig -lt $sec.IndexOf($invocacion)) "9: la sección dice que el agente migra antes de invocar el script"
Assert ($sec.Contains("no separate question")) "9: y que no hay pregunta aparte de la aprobación del upgrade"
# El plan (paso 3) los lista junto con el resto del delta.
$iP3 = $md.IndexOf("### 3. Report")
$p3 = if ($iP3 -ge 0) { $md.Substring($iP3, $md.IndexOf("`n### ", $iP3 + 1) - $iP3) } else { '' }
Assert ($p3.Contains("SESSION_HANDOFF.md")) "9: el reporte del paso 3 lista los SESSION_HANDOFF.md en el plan"

Remove-TestRunRoot $script:runRoot
if ($script:failures -gt 0) { Write-Host "`n$($script:failures) FAIL"; exit 1 }
Write-Host "`nTodo verde"
exit 0
