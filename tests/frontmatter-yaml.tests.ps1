# tests/frontmatter-yaml.tests.ps1 — runner sin Pester.
# Correr: pwsh -NoProfile -File tests/frontmatter-yaml.tests.ps1
#
# POR QUÉ EXISTE: la description de `review-loop` (SKILL.md y comando, en la raíz y en los tres
# scaffolds) nombraba el trailer `Review-Rigor: light` sin comillas. Un ': ' dentro de un escalar
# plano de YAML no se parsea, y Claude Code descarta el frontmatter entero: medido el 2026-09-19,
# la lista de skills de la sesión mostraba `review-loop` con la description "Review Loop" (su
# título), sin ningún trigger. Ningún test lo veía: el de `diagnosing-bugs` chequea esta regla sólo
# para su propia skill.
#
# Esta suite la aplica a TODO `.md` trackeado que abre con frontmatter. No usa PyYAML (no es
# dependencia del repo): chequea las reglas del escalar plano de una línea que rompen el parseo.
$ErrorActionPreference = "Stop"
$repo = Split-Path $PSScriptRoot -Parent
$script:failures = 0
$script:checks   = 0

function Assert($cond, $msg) {
  $script:checks++
  if ($cond) { Write-Host "ok:   $msg" } else { Write-Host "FAIL: $msg"; $script:failures++ }
}

# Cantidad EXACTA de aserciones: sin ella, un mutante que borra asserts sale en verde (0 de 0).
$ExpectedChecks = 9

# Devuelve por qué el valor de una clave de primer nivel no parsea como YAML, o $null si parsea.
# Un valor entre comillas o un bloque (`|`, `>`) se deja pasar: esas formas admiten ': ' adentro.
function Get-ProblemaDeValor([string]$valor) {
  $v = $valor.Trim()
  if ($v.Length -eq 0) { return $null }
  if ($v[0] -in @("'", '"', '|', '>')) { return $null }
  if ($v[0] -in @('@', '`')) { return "empieza con el indicador reservado '$($v[0])'" }
  if ($v.Contains(': ')) { return "tiene ': ' en un escalar plano" }
  if ($v.EndsWith(':'))  { return "termina en ':' en un escalar plano" }
  if ($v.Contains(' #')) { return "tiene ' #' (comentario) en un escalar plano" }
  return $null
}

# Ancla del chequeador: sin estos casos, un chequeador que devuelve siempre $null pasa la suite.
Assert ($null -ne (Get-ProblemaDeValor 'cap (1 when it declares `Review-Rigor: light`).')) "rechaza ': ' en un escalar plano"
Assert ($null -ne (Get-ProblemaDeValor 'termina con clave:')) "rechaza un escalar plano que termina en ':'"
Assert ($null -ne (Get-ProblemaDeValor 'algo #comentario')) "rechaza ' #' en un escalar plano"
Assert ($null -ne (Get-ProblemaDeValor '`codigo` al principio')) "rechaza un escalar plano que empieza con backtick"
Assert ($null -eq (Get-ProblemaDeValor "'cap: entre comillas simples'")) "acepta ': ' entre comillas simples"
Assert ($null -eq (Get-ProblemaDeValor 'Use when X. Trigger con "comillas" y a:b sin espacio.')) "acepta un escalar plano válido"

# Recorre los .md trackeados que abren con frontmatter.
$archivos = @(& git -C $repo -c core.quotepath=off ls-files '*.md' | Where-Object { $_ })
$revisados = 0
$problemas = [System.Collections.Generic.List[string]]::new()
foreach ($rel in $archivos) {
  $ruta = Join-Path $repo $rel
  if (-not (Test-Path -LiteralPath $ruta)) { continue }
  $lineas = ([System.IO.File]::ReadAllText($ruta) -replace "`r`n", "`n") -split "`n"
  if ($lineas.Count -lt 3 -or $lineas[0] -cne '---') { continue }
  $fin = -1
  for ($i = 1; $i -lt $lineas.Count; $i++) { if ($lineas[$i] -ceq '---') { $fin = $i; break } }
  if ($fin -lt 0) { $problemas.Add("${rel}: frontmatter sin cierre '---'"); continue }
  $revisados++
  for ($i = 1; $i -lt $fin; $i++) {
    if ($lineas[$i] -cmatch '^([A-Za-z0-9_-]+):(?: (.*))?$') {
      $p = Get-ProblemaDeValor $Matches[2]
      if ($p) { $problemas.Add("${rel}:$($i + 1) ($($Matches[1])) $p") }
    }
  }
}

# Medido el 2026-09-19: 145 .md trackeados con frontmatter. El piso cubre que el recorrido no se
# quede en cero en silencio (una ruta o un filtro rotos dejan la suite verde sin mirar nada).
Assert ($revisados -ge 140) "recorre los .md con frontmatter (revisados: $revisados, piso 140)"
Assert ($problemas.Count -eq 0) "todo frontmatter parsea como YAML$(if ($problemas.Count) { ":`n        " + ($problemas -join "`n        ") })"

Assert ($script:checks -eq $ExpectedChecks - 1) "corrieron exactamente $ExpectedChecks aserciones"
Write-Host ""
if ($script:failures -gt 0) { Write-Host "$script:failures FALLA(S)"; exit 1 }
Write-Host "OK ($script:checks aserciones)"
