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
# `git show` de los mismos árboles: `tests/oracles/context-metric.py`, que no corre en la suite.
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
$ExpectedChecks = 44

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

# --- El método viaja con el número ----------------------------------------------------------------
# Lo que el método tiene que nombrar: lo que suma, la unidad, y las exclusiones que ya dieron un
# número falso una vez (la línea del flag y el argument-hint sumados a mano el 2026-08-28).
$m = (Measure-ContextLoad -Files @((F "CLAUDE.md" "x"))).Method
foreach ($frase in 'CLAUDE.md', '.claude/commands', '.claude/agents', 'disable-model-invocation',
                   'argument-hint', 'code points', '.agents/skills') {
  Assert ($m -and $m.Contains($frase)) "el método declarado nombra '$frase'"
}

# --- CLI por ref, contra los oráculos de tests/oracles/context-metric.py ------------------------
# Se corre como proceso aparte con -File (con -Command un script que no existe da exit 0). La salida
# se lee por anclas ASCII: el pwsh hijo escribe en la code page de la consola.
function Run-Cli([string[]]$cliArgs) {
  $out = & pwsh -NoProfile -File $tool @cliArgs 2>&1 | Out-String
  return @{ Code = $LASTEXITCODE; Out = $out }
}
function Num($out, $label) {
  if ($out -match "(?m)^$([regex]::Escape($label))\b[^\r\n]*?(\d+)\s*$") { return [int]$Matches[1] } else { return $null }
}
$antes = git -C $repo status --porcelain -- skills | Out-String

# Scaffold 2026-09-11 (manifest `2026-09-11+567c77a`, sellado en f7ae28f), variante personal.
$c = Run-Cli @('-Ref', 'f7ae28f')
Assert ($c.Code -eq 0) "CLI sobre f7ae28f sale 0 (salió $($c.Code): $($c.Out))"
Assert ((Num $c.Out 'CLAUDE.md') -eq 7724) "f7ae28f: CLAUDE.md 7724 (dio $(Num $c.Out 'CLAUDE.md'))"
Assert ((Num $c.Out 'Comandos') -eq 2121) "f7ae28f: comandos 2121 (dio $(Num $c.Out 'Comandos'))"
Assert ($c.Out -match '9 cargan, 2 con el flag') "f7ae28f: 9 comandos cargan y 2 llevan el flag"
Assert ((Num $c.Out 'Agents') -eq 0) "f7ae28f: agents 0 (dio $(Num $c.Out 'Agents'))"
Assert ((Num $c.Out 'Total') -eq 9845) "f7ae28f: total 9845 (dio $(Num $c.Out 'Total'))"
Assert ($c.Out -match 'disable-model-invocation') "la salida de la CLI incluye el método"

$c = Run-Cli @('-Ref', 'v2.1.0', '-Variant', 'personal')
Assert ($c.Code -eq 0) "CLI sobre v2.1.0 sale 0 (salió $($c.Code): $($c.Out))"
Assert ((Num $c.Out 'CLAUDE.md') -eq 7556) "v2.1.0: CLAUDE.md 7556 (dio $(Num $c.Out 'CLAUDE.md'))"
Assert ((Num $c.Out 'Comandos') -eq 9217) "v2.1.0: comandos 9217 (dio $(Num $c.Out 'Comandos'))"
Assert ($c.Out -match '21 cargan, 0 con el flag') "v2.1.0: 21 comandos cargan y ninguno lleva el flag"
Assert ((Num $c.Out 'Agents') -eq 599) "v2.1.0: agents 599 (dio $(Num $c.Out 'Agents'))"
Assert ((Num $c.Out 'Total') -eq 17372) "v2.1.0: total 17372 (dio $(Num $c.Out 'Total'))"

# La variante cambia el árbol medido: southpoint tiene su propio CLAUDE.md (oráculo: 7690).
$c = Run-Cli @('-Ref', 'v2.1.0', '-Variant', 'southpoint')
Assert ((Num $c.Out 'CLAUDE.md') -eq 7690) "v2.1.0 southpoint: CLAUDE.md 7690 (dio $(Num $c.Out 'CLAUDE.md'))"

$c = Run-Cli @('-Ref', 'no-existe-este-ref')
Assert ($c.Code -ne 0) "un ref inexistente sale distinto de 0 (salió $($c.Code))"
Assert ($c.Out -match 'git rev-parse') "y el error nombra el comando git que falló, no un síntoma posterior"

# 8df1b98 es el padre del commit que creó la variante ai: el ref existe pero ese scaffold no.
$c = Run-Cli @('-Ref', '8df1b98', '-Variant', 'ai')
Assert ($c.Code -ne 0 -and $c.Out -match 'no hay CLAUDE.md') "un ref sin el scaffold de la variante tira, no mide 0 (salió $($c.Code): $($c.Out))"

$despues = git -C $repo status --porcelain -- skills | Out-String
Assert ($antes -eq $despues) "la CLI no toca el árbol de trabajo de skills/"

Write-Host ""
if ($script:checks -ne $ExpectedChecks) {
  Write-Host "FAIL: se esperaban $ExpectedChecks checks y corrieron $($script:checks)"; $script:failures++
}
Write-Host "$($script:checks) checks, $($script:failures) fail"
exit $script:failures
