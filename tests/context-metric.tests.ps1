# tests/context-metric.tests.ps1 — runner sin Pester. Correr: pwsh -NoProfile -File tests/context-metric.tests.ps1
#
# Cubre tools/context-metric.ps1 — la métrica de contexto cargado por request del PRD de medición
# (`.scratch/medicion-v2/issues/02-metrica-de-contexto.md`). Existe porque la versión a mano ya dio una
# vez un número con un método nunca declarado (memoria `dieta-de-contexto-invocacion-no-largo`).
#
# Dos seams, acordados con el usuario:
#   1. `Measure-ContextLoad`, función pura dot-sourceada: recibe los archivos del scaffold en memoria.
#   2. La CLI `tools/context-metric.ps1 -Ref <commit>`, que lee el árbol con `git show`.
#
# Los literales de la CLI son oráculos calculados FUERA de la función bajo prueba, con Python sobre
# `git show` de los mismos árboles (el script está citado en el issue 02).
$ErrorActionPreference = "Stop"
$repo = Split-Path $PSScriptRoot -Parent
$tool = Join-Path $repo "tools/context-metric.ps1"
$script:failures = 0
$script:checks   = 0

function Assert($cond, $msg) {
  $script:checks++
  if ($cond) { Write-Host "ok:   $msg" } else { Write-Host "FAIL: $msg"; $script:failures++ }
}

# Cantidad EXACTA de aserciones: sin este número un mutante que borra asserts sale en verde.
$ExpectedChecks = 7

if (-not (Test-Path -LiteralPath $tool)) {
  Write-Host "FAIL: no existe la herramienta en $tool"; exit 1
}
. $tool

function F($path, $content) { [pscustomobject]@{ Path = $path; Content = $content } }

# --- Comandos: suma la description de los que NO llevan disable-model-invocation: true ----------
$r = Measure-ContextLoad -Files @(
  (F ".claude/commands/a.md" "---`nname: a`ndescription: abcde`nargument-hint: <xyz>`n---`n`ncuerpo largo que no carga")
  (F ".claude/commands/b.md" "---`nname: b`ndescription: 1234567`ndisable-model-invocation: true`n---`n")
  (F ".claude/commands/c.md" "---`ndescription: xyz`n---`n")
)
Assert ($r.Commands -eq 8) "comandos: 5 + 3; el flag excluye a b, y ni name, ni argument-hint, ni el cuerpo suman (dio $($r.Commands))"
Assert ($r.CommandsLoaded -eq 2) "comandos que cargan: 2 de 3 (dio $($r.CommandsLoaded))"
Assert ($r.CommandsFlagged -eq 1) "comandos excluidos por el flag: 1 (dio $($r.CommandsFlagged))"
Assert ($r.Total -eq 8) "total sin CLAUDE.md ni agents = comandos (dio $($r.Total))"

# Un flag en false no excluye: se mira el valor, no la presencia de la clave.
$r = Measure-ContextLoad -Files @((F ".claude/commands/a.md" "---`ndescription: abcd`ndisable-model-invocation: false`n---`n"))
Assert ($r.Commands -eq 4) "disable-model-invocation: false carga igual (dio $($r.Commands))"

# --- CLAUDE.md de la raíz: entero, en code points, con CRLF/CR como un solo salto y sin BOM --------
# "😀" es un code point fuera del BMP: .Length de .NET lo cuenta 2, el oráculo de Python 1.
$r = Measure-ContextLoad -Files @(
  (F "CLAUDE.md" ([char]0xFEFF + "a`r`nb`rc😀"))
  (F "docs/CLAUDE.md" "no es el de la raíz")
  (F ".claude/commands/a.md" "---`ndescription: xy`n---`n")
)
Assert ($r.ClaudeMd -eq 6) "CLAUDE.md: a LF b LF c 😀 = 6 code points; el BOM no cuenta y docs/CLAUDE.md no carga (dio $($r.ClaudeMd))"
Assert ($r.Total -eq 8) "total = CLAUDE.md + comandos = 6 + 2 (dio $($r.Total))"

Write-Host ""
if ($script:checks -ne $ExpectedChecks) {
  Write-Host "FAIL: se esperaban $ExpectedChecks checks y corrieron $($script:checks)"; $script:failures++
}
Write-Host "$($script:checks) checks, $($script:failures) fail"
exit $script:failures
