# tests/contrato-de-handoff.tests.ps1 — runner sin Pester.
# Correr: pwsh -NoProfile -File tests/contrato-de-handoff.tests.ps1
#
# POR QUÉ EXISTE (.scratch/handoff-pocock, issue 01): convivían dos contratos de handoff —`handoff`
# de Pocock, efímero en el temp del SO pero sin nombre fijo, y `session-handoff`, que acumulaba un
# `SESSION_HANDOFF.md` en cada repo—. Queda uno solo, el de Pocock, y la skill NO se toca (ADR-0005:
# su cuerpo lo sella el lockfile, en tests/skills-lock.tests.ps1). Lo que se agrega es la convención
# de ruta en el `CLAUDE.md`, para que una terminal nueva encuentre el handoff de su worktree sin que
# nadie le pase la ruta.
#
# `mirror.tests.ps1` tiene `assets/scaffold/CLAUDE.md` en su allowlist (los 4 divergen entre
# variantes), así que nadie más mira esta sección: esta suite exige que esté en los 4 y que sea la
# MISMA en los 4. Ancla tokens (la ruta, el comando, la clase de caracteres, el `.prev`), no frases:
# reescribir la regla con otras palabras conservándolos no da rojo, y queda declarado.
$ErrorActionPreference = "Stop"
$repo = Split-Path $PSScriptRoot -Parent
$script:failures = 0
function Assert($cond, $msg) {
  if ($cond) { Write-Host "ok:   $msg" } else { Write-Host "FAIL: $msg"; $script:failures++ }
}

$variantes = @("bootstrap-ai-project", "bootstrap-personal-project", "bootstrap-southpoint-project")
$copias = @(@{ label = "repo"; path = (Join-Path $repo "CLAUDE.md") })
foreach ($v in $variantes) {
  $copias += @{ label = $v; path = (Join-Path $repo "skills\$v\assets\scaffold\CLAUDE.md") }
}

# La sección va de su título hasta el próximo `## `/`### ` o el fin del archivo.
function Seccion([string]$txt) {
  $m = [regex]::Match($txt, '(?ms)^### Handoff\r?\n(.*?)(?=^#{2,3} |\z)')
  if ($m.Success) { return $m.Groups[1].Value.Trim() } else { return $null }
}

$secciones = @()
foreach ($c in $copias) {
  $n = $c.label
  $txt = if (Test-Path -LiteralPath $c.path) { [IO.File]::ReadAllText($c.path) } else { "" }
  Assert ($txt -ne "") "${n}: existe el CLAUDE.md"
  $veces = ([regex]::Matches($txt, '(?m)^### Handoff\s*$')).Count
  Assert ($veces -eq 1) "${n}: la sección '### Handoff' aparece exactamente una vez ($veces)"
  $s = Seccion $txt
  $secciones += ,$s
  $s = "$s"
  # La ruta completa, con el prefijo: sin él, mover el handoff adentro del repo (el contrato que
  # esto retira) quedaba verde.
  Assert ($s.Contains('<OS temp dir>/claude-handoff/<key>.md')) "${n}: nombra la ruta fija <OS temp dir>/claude-handoff/<key>.md"
  # La clave tiene que salir igual desde cualquier shell, y lo que decide eso es si la salida de git se
  # lee como UTF-8, no la herramienta. Medido el 2026-10-02 con `ó`: `sed` sin locale da `--` y con
  # `LC_ALL=C.UTF-8` da `-`; `-replace` de pwsh da `--` con la consola en cp850 y `-` con
  # `[Console]::OutputEncoding` en UTF-8. La regla nombra las dos recetas, y cada ejemplo `x` → `y`
  # de la sección se recalcula acá: uno con acento es obligatorio, para que la diferencia quede a la vista.
  Assert ($s -match '(?i)per character, not per byte') "${n}: la clave se cuenta por carácter, no por byte"
  Assert ($s.Contains('[Console]::OutputEncoding')) "${n}: dice cómo leer git como UTF-8 desde PowerShell"
  Assert ($s.Contains('LC_ALL=C.UTF-8')) "${n}: dice cómo contar por carácter desde bash"
  # La frase del turno 1 recomendaba pwsh sin condición, y pwsh en cp850 da lo mismo que sed (medido).
  Assert (-not ($s -match '(?i)gets it right')) "${n}: no recomienda una herramienta sin condición de encoding"
  $ejemplos = @([regex]::Matches($s, '`([^`]+)` → `([^`]+)`'))
  Assert ($ejemplos.Count -ge 2) "${n}: trae al menos dos ejemplos de clave ($($ejemplos.Count))"
  $conAcento = @($ejemplos | Where-Object { $_.Groups[1].Value -match '[^\x00-\x7F]' })
  Assert ($conAcento.Count -ge 1) "${n}: al menos un ejemplo con un carácter no ASCII"
  foreach ($e in $ejemplos) {
    $de = $e.Groups[1].Value; $a = $e.Groups[2].Value
    $calc = $de -replace '[^A-Za-z0-9]', '-'
    Assert ($calc -ceq $a) "${n}: el ejemplo '$de' da '$a' por la regla (calculado: '$calc')"
  }
  Assert ($s.Contains('git rev-parse --show-toplevel')) "${n}: la clave sale del toplevel del worktree"
  Assert ($s.Contains('[A-Za-z0-9]')) "${n}: declara la clase de caracteres que sobrevive a la sanitización"
  Assert ($s.Contains('<key>.prev.md')) "${n}: el anterior se mueve a <key>.prev.md"
  Assert ($s -match '(?i)one previous generation') "${n}: una sola generación previa"
  Assert ($s -match '(?i)if it does not exist, say so and stop') "${n}: sin handoff, lo dice y frena"
  Assert ($s -match '(?i)\bgit diff\b') "${n}: la continuación lee también el git diff"
  Assert ($s -match '(?i)commits, issues, ADRs (or|and) memory') "${n}: lo durable va a commits/issues/ADRs/memoria"
  # El contrato viejo no puede sobrevivir en ningún lado del CLAUDE.md.
  Assert (-not ($txt -match 'SESSION_HANDOFF')) "${n}: no nombra SESSION_HANDOFF"
  Assert (-not ($txt -match '(?i)session[- ]handoff')) "${n}: no nombra session-handoff ni 'the session handoff'"
}

$distintas = @($secciones | Where-Object { $_ -ne $secciones[0] })
Assert ($null -ne $secciones[0] -and $distintas.Count -eq 0) "la sección '### Handoff' es idéntica en los 4 CLAUDE.md"

if ($script:failures -gt 0) { Write-Host "`n$($script:failures) FALLARON"; exit 1 }
Write-Host "`nTODOS LOS TESTS PASARON"; exit 0
