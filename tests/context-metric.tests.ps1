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
$ExpectedChecks = 60

if (-not (Test-Path -LiteralPath $tool)) {
  Write-Host "FAIL: no existe la herramienta en $tool"; exit 1
}
. $tool

function F($path, $content) { [pscustomobject]@{ Path = $path; Content = $content } }

# --- Comandos: suma la description de los que NO llevan disable-model-invocation: true ----------
$r = Measure-ContextLoad -Files @(
  (F ".claude/commands/a.md" "---`nname: a`ndescription: abcde`nargument-hint: <xyz>`n---`n`ncuerpo largo que no carga")
  (F ".claude/commands/b.md" "---`nname: b`ndescription: `"1234567`"`ndisable-model-invocation: true`n---`n")
  (F ".claude/commands/c.md" "---`ndescription: xyz`n---`n")
)
# b.md lleva una description entre comillas, que tiraría si se leyera: el flag se mira antes y la
# description de un comando que no carga no se lee.
Assert ($r.Commands -eq 8) "comandos: 5 + 3; el flag excluye a b, y ni name, ni argument-hint, ni el cuerpo suman (dio $($r.Commands))"
Assert ($r.CommandsLoaded -eq 2) "comandos que cargan: 2 de 3 (dio $($r.CommandsLoaded))"
Assert ($r.CommandsFlagged -eq 1) "comandos excluidos por el flag: 1 (dio $($r.CommandsFlagged))"
Assert ($r.Total -eq 8) "total sin CLAUDE.md ni agents = comandos (dio $($r.Total))"

# Un flag en false no excluye: se mira el valor, no la presencia de la clave.
$r = Measure-ContextLoad -Files @((F ".claude/commands/a.md" "---`ndescription: abcd`ndisable-model-invocation: false`n---`n"))
Assert ($r.Commands -eq 4) "disable-model-invocation: false carga igual (dio $($r.Commands))"

# El frontmatter con CRLF o con CR sueltos mide lo mismo que con LF, flag incluido.
$r = Measure-ContextLoad -Files @(
  (F ".claude/commands/lf.md"   "---`ndescription: abcd`n---`n")
  (F ".claude/commands/crlf.md" "---`r`ndescription: abcd`r`n---`r`n")
  (F ".claude/commands/cr.md"   "---`rdescription: abcd`r---`r")
  (F ".claude/commands/fl.md"   "---`r`ndescription: zz`r`ndisable-model-invocation: true`r`n---`r`n")
)
Assert ($r.Commands -eq 12 -and $r.CommandsFlagged -eq 1) "LF, CRLF y CR: 4 + 4 + 4, y el flag con CRLF excluye (dio $($r.Commands), $($r.CommandsFlagged) con flag)"

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
  # Fija el método declarado (todos los agents suman), no un comportamiento verificado de Claude Code.
  (F ".claude/agents/r3.md" "---`ndescription: abc`ndisable-model-invocation: true`n---`n")
  # Solo los .md: un archivo de otro tipo en esas carpetas no suma ni tira.
  (F ".claude/commands/notas.txt" "sin frontmatter")
  (F ".claude/agents/datos.json" "{}")
)
Assert ($r.Agents -eq 13) "agents: 'Revisa 😀' (8) + 'ab' (2) + 'abc' con el flag (3) = 13; tools y el prompt no suman (dio $($r.Agents))"
Assert ($r.AgentsLoaded -eq 3 -and $r.CommandsFlagged -eq 0) "agents que cargan: 3, el flag no excluye a un agent (dio $($r.AgentsLoaded))"
Assert ($r.Commands -eq 2) "comando anidado 'x😀' = 2 code points (dio $($r.Commands))"
Assert ($r.Total -eq 15) "total = 0 + 2 + 13; .agents/skills, .txt y .json no suman (dio $($r.Total))"

# --- Lo que la métrica no sabe medir tira, en vez de dar un número equivocado en silencio --------
# Mira el archivo Y el motivo: con solo el archivo, un error de otra rama (p. ej. "no cierra" en vez
# de "no arranca") deja pasar el test aunque la guarda que se quería probar no exista.
function Tira($files, $archivo, $motivo, $msg) {
  $err = $null
  try { Measure-ContextLoad -Files $files | Out-Null } catch { $err = $_.Exception.Message }
  Assert ($err -and $err -like "*$archivo*" -and $err -like "*$motivo*") "$msg (error: $err)"
}
Tira @((F ".claude/commands/q.md" "---`ndescription: `"entre comillas`"`n---`n")) "q.md" "no es un valor plano" "description entre comillas dobles tira"
Tira @((F ".claude/commands/q.md" "---`ndescription: 'simples'`n---`n")) "q.md" "no es un valor plano" "description entre comillas simples tira"
Tira @((F ".claude/agents/m.md" "---`ndescription: >`n  multilínea`n---`n")) "m.md" "no es un valor plano" "description en bloque (>) tira"
Tira @((F ".claude/agents/m.md" "---`ndescription: |`n  multilínea`n---`n")) "m.md" "no es un valor plano" "description en bloque (|) tira"
Tira @((F ".claude/commands/e.md" "---`ndescription: `n---`n")) "e.md" "no es un valor plano" "description vacía tira"
Tira @((F ".claude/commands/n.md" "---`nname: n`n---`n`ncuerpo")) "n.md" "no tiene description" "comando sin description tira (Claude Code usaría el cuerpo)"
# Sin `---` de apertura pero con uno más abajo: sin la guarda de apertura, esto se mediría.
Tira @((F ".claude/commands/f.md" "hola`ndescription: x`n---`ncuerpo")) "f.md" "no arranca" "comando sin frontmatter tira"
Tira @((F ".claude/commands/t.md" "---`ndescription: sin cierre`n")) "t.md" "no cierra" "frontmatter sin cierre tira"
Tira @((F ".claude/skills/s/SKILL.md" "---`ndescription: x`n---`n")) ".claude/skills" "todavía no lo suma" "un .claude/skills/ tira: la métrica todavía no lo suma"
# YAML que una lectura por línea mediría mal: valor que sigue en la línea de abajo, comentario al
# final y clave repetida.
Tira @((F ".claude/commands/w.md" "---`ndescription: abc`n  defgh`n---`n")) "w.md" "sigue en la línea" "description que continúa en la línea siguiente tira"
Tira @((F ".claude/commands/w.md" "---`ndescription: abc`n`n  defgh`n---`n")) "w.md" "sigue en la línea" "una línea vacía en el medio no corta la continuación"
Tira @((F ".claude/commands/w.md" "---`ndescription: abc # nota`n---`n")) "w.md" "comentario" "description con comentario al final tira"
Tira @((F ".claude/commands/w.md" "---`ndescription: # nota`n---`n")) "w.md" "comentario" "description que es solo un comentario tira (YAML la lee vacía)"
Tira @((F ".claude/commands/w.md" "---`ndescription: abc`ndisable-model-invocation: true # off`n---`n")) "w.md" "comentario" "flag con comentario al final tira, no se lee como otro valor"
Tira @((F ".claude/commands/w.md" "---`ndescription: abc`ndescription: otra`n---`n")) "w.md" "repetida" "description repetida tira"
# Una línea indentada que es un comentario no es una continuación: el motivo tiene que decir comentario.
Tira @((F ".claude/commands/w.md" "---`ndescription: abc`n  # nota`n---`n")) "w.md" "comentario" "un comentario indentado bajo la description tira como comentario, no como continuación"
# En YAML solo el espacio y el tab abren un comentario; `abc<NBSP>#x` es un valor plano. La métrica
# tira igual ante cualquier blanco antes del `#`: tirar de más no da un número falso, medir un
# comentario sí. El oráculo tiene que igualarlo.
Tira @((F ".claude/commands/w.md" "---`ndescription: abc$([char]0xA0)#x`n---`n")) "w.md" "comentario" "un NBSP antes del # también tira, aunque YAML no lo lea como comentario"

# --- Lo que se mide aunque se parezca a lo que tira ------------------------------------------------
# Un `#` pegado a una palabra no es un comentario en YAML: `C#` es parte del valor.
$r = Measure-ContextLoad -Files @((F ".claude/commands/c.md" "---`ndescription: C# y abc#def`n---`n"))
Assert ($r.Commands -eq 12) "un # pegado a una palabra se mide: 'C# y abc#def' = 12 (dio $($r.Commands))"
# Un comentario en columna 0 bajo la description no la continúa (la continuación va indentada), y
# YAML lo descarta: se mide el valor de arriba. El oráculo tiene que medirlo igual, no rechazarlo.
$err = $null
try { $r = Measure-ContextLoad -Files @((F ".claude/commands/c.md" "---`ndescription: abc`n# nota`n---`n")) } catch { $err = $_.Exception.Message }
Assert (-not $err -and $r.Commands -eq 3) "un comentario en columna 0 bajo la description se mide: 'abc' = 3 (dio $($r.Commands), error: $err)"
# El BOM no cuenta tampoco en un comando. Hoy pasa porque el `-ne '---'` de Get-FrontmatterField
# compara con la cultura, que ignora U+FEFF; una comparación ordinal lo haría tirar con 'no arranca'.
$err = $null
try { $r = Measure-ContextLoad -Files @((F ".claude/commands/b.md" ([char]0xFEFF + "---`ndescription: ab`n---`n"))) } catch { $err = $_.Exception.Message }
Assert (-not $err -and $r.Commands -eq 2) "un comando con BOM se mide: 'ab' = 2 (dio $($r.Commands), error: $err)"
# Los agents no leen el flag: uno entre comillas, que en un comando tiraría, en un agent no molesta.
$err = $null
try { $r = Measure-ContextLoad -Files @((F ".claude/agents/a.md" "---`ndescription: abc`ndisable-model-invocation: `"x`"`n---`n")) } catch { $err = $_.Exception.Message }
Assert (-not $err -and $r.Agents -eq 3) "un agent con el flag entre comillas se mide: 'abc' = 3 (dio $($r.Agents), error: $err)"

# --- El filtro de rutas de la CLI deja pasar lo que la función mide o rechaza ---------------------
# Si dejara afuera .claude/skills/, la CLI imprimiría un número menor en vez de tirar.
$sel = @(Select-ScaffoldPaths @('CLAUDE.md', '.claude/commands/a.md', '.claude/agents/b.md', '.claude/skills/s/SKILL.md',
                                '.claude/settings.json', 'docs/x.md', '.agents/skills/y/SKILL.md'))
Assert (($sel -join '|') -eq 'CLAUDE.md|.claude/commands/a.md|.claude/agents/b.md|.claude/skills/s/SKILL.md') "el filtro de la CLI pasa CLAUDE.md, commands, agents y skills, y nada más (dio $($sel -join '|'))"

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
# v2.1.0 es un tag anotado: sin pelarlo a commit, el header mostraría el sha del objeto tag (79a8844).
Assert ($c.Out -match '\(4d205ec[0-9a-f]*\)') "v2.1.0: el header nombra el commit 4d205ec, no el objeto del tag"

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
