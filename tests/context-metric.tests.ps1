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
$ExpectedChecks = 19

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

# --- Agents: suman todos (no hay flag de invocación para un agent); descriptions en code points -----
# Un comando en subdirectorio también carga (Claude Code lo lista con namespace).
$r = Measure-ContextLoad -Files @(
  (F ".claude/agents/r1.md" "---`nname: r1`ndescription: Revisa 😀`ntools: Read`n---`n`nprompt largo")
  (F ".claude/agents/r2.md" "---`nname: r2`ndescription: ab`n---`n")
  (F ".claude/commands/sub/x.md" "---`ndescription: x😀`n---`n")
  (F ".agents/skills/s/SKILL.md" "---`nname: s`ndescription: Claude Code no lee .agents/skills`n---`n")
)
Assert ($r.Agents -eq 10) "agents: 'Revisa 😀' (8) + 'ab' (2) = 10 code points; tools y el prompt no suman (dio $($r.Agents))"
Assert ($r.AgentsLoaded -eq 2) "agents que cargan: 2 (dio $($r.AgentsLoaded))"
Assert ($r.Commands -eq 2) "comando anidado 'x😀' = 2 code points (dio $($r.Commands))"
Assert ($r.Total -eq 12) "total = 0 + 2 + 10; .agents/skills no suma (dio $($r.Total))"

# --- Lo que la métrica no sabe medir tira, en vez de dar un número equivocado en silencio --------
function Tira($files, $patron, $msg) {
  $err = $null
  try { Measure-ContextLoad -Files $files | Out-Null } catch { $err = $_.Exception.Message }
  Assert ($err -and $err -like "*$patron*") "$msg (error: $err)"
}
Tira @((F ".claude/commands/q.md" "---`ndescription: `"entre comillas`"`n---`n")) "q.md" "description entre comillas dobles tira nombrando el archivo"
Tira @((F ".claude/commands/q.md" "---`ndescription: 'simples'`n---`n")) "q.md" "description entre comillas simples tira"
Tira @((F ".claude/agents/m.md" "---`ndescription: >`n  multilínea`n---`n")) "m.md" "description en bloque (>) tira"
Tira @((F ".claude/agents/m.md" "---`ndescription: |`n  multilínea`n---`n")) "m.md" "description en bloque (|) tira"
Tira @((F ".claude/commands/n.md" "---`nname: n`n---`n`ncuerpo")) "n.md" "comando sin description tira (Claude Code usaría el cuerpo)"
Tira @((F ".claude/commands/f.md" "sin frontmatter")) "f.md" "comando sin frontmatter tira"
Tira @((F ".claude/commands/t.md" "---`ndescription: sin cierre`n")) "t.md" "frontmatter sin cierre tira"
Tira @((F ".claude/skills/s/SKILL.md" "---`ndescription: x`n---`n")) ".claude/skills" "un .claude/skills/ tira: la métrica todavía no lo suma"

Write-Host ""
if ($script:checks -ne $ExpectedChecks) {
  Write-Host "FAIL: se esperaban $ExpectedChecks checks y corrieron $($script:checks)"; $script:failures++
}
Write-Host "$($script:checks) checks, $($script:failures) fail"
exit $script:failures
