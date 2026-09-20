# tests/dieta-del-claude-md.tests.ps1 — runner sin Pester.
# Correr: pwsh -NoProfile -File tests/dieta-del-claude-md.tests.ps1
#
# Issue 14 — dieta del CLAUDE.md. El CLAUDE.md se carga ENTERO en cada request de cada proyecto
# bootstrapeado; dos de sus bullets contaban en prosa el mecanismo que un hook ya enforza solo
# (cache de mecanismo). Ese mecanismo se muda a docs/ai-workflow/AI_DEVELOPMENT_WORKFLOW.md, que el
# CLAUDE.md ya declara lectura obligatoria, y en el CLAUDE.md queda la REGLA mas un puntero.
#
# El criterio del corte, que es lo que esta suite fija: se muda lo que un hook enforza (que dispara
# el loop, que cuenta como documentacion, cual es el delta sin revisar, que archivo frena el primer
# Edit). NO se muda lo que ningun hook puede enforzar y el agente igual tiene que obedecer: declarar
# el cierre con el trailer, elegir el rigor, y puntuar la prosa segun el Step 5 de /slice-review.
#
# Por que existe: sin la mitad NEGATIVA (el CLAUDE.md ya no trae el mecanismo) la dieta se revierte
# sola en el primer turno que "aclare" algo, y nada se pone rojo. Y sin la mitad POSITIVA el
# mecanismo se puede borrar del doc destino y el CLAUDE.md queda apuntando a nada.
#
# QUE ESTA PROBADO NO-VACUO Y QUE NO. La suite se corrio contra 8d857a3 (el arbol de antes del
# cambio) en un worktree aparte: 16 FAIL y 5 ok. Los 5 verdes son guards (las 4 raices, y el bullet
# unico de review-loop en cada CLAUDE.md), asi que TODA asercion de contenido del bloque del loop
# esta probada por ese RED. Las del bloque del gate NO lo estan una por una: alla el guard de la
# seccion cae primero y el `continue` se lleva las demas. Estan cubiertas por construccion (la
# seccion no existia en 8d857a3), no por medicion.
$ErrorActionPreference = "Stop"
$repo = Split-Path $PSScriptRoot -Parent
$skills = @(Get-ChildItem (Join-Path $repo "skills") -Directory | Where-Object Name -like "bootstrap-*-project")
$script:failures = 0
function Assert($cond, $msg) {
  if ($cond) { Write-Host "ok:   $msg" } else { Write-Host "FAIL: $msg"; $script:failures++ }
}

# Las 4 raices: el repo (que se auto-bootstrapeo) y los 3 scaffolds. Se arma igual que en
# slice-review.tests.ps1 para que agregar una variante no deje una raiz sin mirar.
$raices = @(@{ label = "repo"; pre = $repo }) + @($skills | ForEach-Object {
  @{ label = $_.Name; pre = (Join-Path $_.FullName "assets\scaffold") }
})
Assert ($raices.Count -eq 4) "guard: se arman las 4 raices (armadas: $($raices.Count))"

$DOC = "docs/ai-workflow/AI_DEVELOPMENT_WORKFLOW.md"

# La lista de rutas que gobiernan al agente, tal como la recorta review-loop-docs-gate.tests.ps1:
# entre parentesis, detras de "no matter their extension". Es el corazon del mecanismo mudado.
function Get-ListaDeGobierno([string]$txt) {
  ([regex]::Match($txt, 'no matter their extension \(([^)]+)\)')).Groups[1].Value
}

Write-Host ""
Write-Host "=== el mecanismo del review-loop vive en el doc del flujo, no en el CLAUDE.md ==="
foreach ($r in $raices) {
  $cF = Join-Path $r.pre "CLAUDE.md"
  $dF = Join-Path $r.pre ($DOC -replace '/', '\')
  if (-not (Test-Path -LiteralPath $cF)) { Assert $false "$($r.label): existe CLAUDE.md"; continue }
  if (-not (Test-Path -LiteralPath $dF)) { Assert $false "$($r.label): existe $DOC"; continue }
  $c = [IO.File]::ReadAllText($cF)
  $d = [IO.File]::ReadAllText($dF)

  # POSITIVA: el mecanismo esta COMPLETO en el doc destino. Se mide por la lista de gobierno, que es
  # lo unico del bullet que otra suite ya sabe comparar contra el clasificador del hook.
  Assert ((Get-ListaDeGobierno $d) -ne '') "$($r.label): $DOC trae la lista de rutas que gobiernan al agente"

  # NEGATIVA: el CLAUDE.md ya no la cachea.
  Assert ((Get-ListaDeGobierno $c) -eq '') "$($r.label): el CLAUDE.md ya no enumera esa lista (dieta)"

  # El puntero: sin el, la regla que queda en el CLAUDE.md manda a ningun lado. Se ancla DENTRO del
  # bullet del loop, no en el archivo entero: el CLAUDE.md nombra el doc tambien en «Required
  # workflow docs», asi que un match suelto sobrevive a borrar el puntero.
  $m = [regex]::Matches($c, '(?ms)^- After implementation, run .*?(?=^-\s|\z)')
  Assert ($m.Count -eq 1) "$($r.label): guard: el CLAUDE.md tiene exactamente un bullet de review-loop (encontrados: $($m.Count))"
  if ($m.Count -ne 1) { continue }
  Assert ($m[0].Value -match [regex]::Escape($DOC)) "$($r.label): el bullet del loop remite a $DOC"
}

Write-Host ""
Write-Host "=== el mecanismo del alignment-gate vive en el doc del flujo, no en el CLAUDE.md ==="
# La lista de archivos que el gate deja pasar es el mecanismo: la computa el hook, no el agente.
# El `\r?` va porque estos archivos van en CRLF y el `$` de .NET ancla solo ante `\n`.
$SEC_GATE = '(?ms)^### The `alignment-gate` hook\r?$.*?(?=^#{2,4}\s|\z)'
foreach ($r in $raices) {
  $cF = Join-Path $r.pre "CLAUDE.md"
  $dF = Join-Path $r.pre ($DOC -replace '/', '\\')
  if (-not (Test-Path -LiteralPath $cF) -or -not (Test-Path -LiteralPath $dF)) { Assert $false "$($r.label): existen CLAUDE.md y $DOC"; continue }
  $c = [IO.File]::ReadAllText($cF)
  $d = [IO.File]::ReadAllText($dF)

  $sec = [regex]::Matches($d, $SEC_GATE)
  Assert ($sec.Count -eq 1) "$($r.label): $DOC tiene exactamente una seccion del alignment-gate (encontradas: $($sec.Count))"
  if ($sec.Count -ne 1) { continue }
  # POSITIVA: la lista de lo que pasa libre esta en el doc, entera.
  foreach ($ruta in @('*.md', 'docs/', '.scratch/', '.agents/', '.claude/')) {
    Assert ($sec[0].Value -match [regex]::Escape('`' + $ruta + '`')) "$($r.label): la seccion del gate nombra $ruta entre lo que pasa libre"
  }
  Assert ($sec[0].Value -match 'PreToolUse') "$($r.label): la seccion del gate dice en que evento engancha"

  # NEGATIVA: el CLAUDE.md ya no cachea esa lista. Se mira el bullet del gate, no el archivo entero:
  # `.claude/` y `docs/` aparecen en otros bullets con otro sentido y un match suelto da falso rojo.
  $bg = [regex]::Matches($c, '(?ms)^- Before the first code edit of a session.*?(?=^-\s|\z)')
  Assert ($bg.Count -eq 1) "$($r.label): guard: el CLAUDE.md tiene exactamente un bullet del gate (encontrados: $($bg.Count))"
  if ($bg.Count -ne 1) { continue }
  Assert ($bg[0].Value -notmatch '\.scratch/') "$($r.label): el bullet del gate ya no enumera los archivos que pasan libres (dieta)"
  # El puntero, dentro del bullet: el CLAUDE.md nombra el doc tambien en «Required workflow docs».
  Assert ($bg[0].Value -match [regex]::Escape($DOC)) "$($r.label): el bullet del gate remite a $DOC"
  # La REGLA se queda: ningun hook puede obligar a ofrecer la alineacion, solo frena el primer Edit.
  Assert ($bg[0].Value -match '(?i)OFFER alignment') "$($r.label): el bullet del gate conserva la regla (ofrecer alineacion antes de codear)"
}

Write-Host ""
if ($script:failures -eq 0) { Write-Host "TODOS LOS TESTS PASARON"; exit 0 }
Write-Host "$($script:failures) test(s) FALLARON"
exit 1
