# tests/marcar-done.tests.ps1 — runner sin Pester. Correr: pwsh -NoProfile -File tests/marcar-done.tests.ps1
# `marcar-done.ps1` (issue hub-sync 07): al cerrar un slice, `/review-loop` pone `Status: done` en los
# issues que el `Slice-Close:` del commit cita por ruta. Fixtures: repos git temporales con `.scratch/`.
$ErrorActionPreference = "Stop"
$repo   = Split-Path $PSScriptRoot -Parent
$marcar = Join-Path $repo "skills/bootstrap-southpoint-project/assets/scaffold/.claude/scripts/marcar-done.ps1"
$script:failures = 0
. (Join-Path $PSScriptRoot "lib\temp-workspace.ps1")
. (Join-Path $PSScriptRoot "lib\consola-propia.ps1")
$script:runRoot = New-TestRunRoot "mdone"
trap { Remove-TestRunRoot $script:runRoot; break }

function Assert($cond, $msg) {
  if ($cond) { Write-Host "ok:   $msg" } else { Write-Host "FAIL: $msg"; $script:failures++ }
}
# Sin el script, `pwsh -File` imprime su usage y sale != 0: los asserts de "no marca nada" pasarían
# en verde sin ejercitar nada.
if (-not (Test-Path -LiteralPath $marcar)) {
  Remove-TestRunRoot $script:runRoot
  Write-Host "FAIL: no existe marcar-done en $marcar"; exit 1
}

# Mismo aislamiento del gitconfig global que hub-recolectar.tests.ps1.
function New-Repo {
  $t = New-TestWorkspace $script:runRoot "mdone-repo"
  git -C $t init -q -b master
  git -C $t config user.email dev@x.io
  git -C $t config user.name dev
  git -C $t config commit.gpgsign false
  git -C $t config core.hooksPath ""
  git -C $t config core.excludesFile ""
  "base" | Set-Content (Join-Path $t "file.txt")
  git -C $t add -A; git -C $t commit -q -m base
  return $t
}
# Un issue en `.scratch/<feature>/issues/`, con CRLF como los `.md` trackeados del repo.
function New-Issue([string]$t, [string]$rel, [string]$status = "ready-for-agent") {
  $p = Join-Path $t $rel
  [IO.Directory]::CreateDirectory((Split-Path $p -Parent)) | Out-Null
  $txt = "# titulo`r`n`r`nStatus: $status`r`nRepo: X`r`n`r`n## What to build`r`n`r`nStatus: no-es-esta`r`n"
  [IO.File]::WriteAllText($p, $txt)
  return $p
}
# El mensaje con la forma real del workflow: el `Slice-Close:` en el penúltimo párrafo.
function Commit([string]$t, [string]$cuerpo) {
  $f = New-TestTempPath $script:runRoot "msg" ".txt"
  [IO.File]::WriteAllText($f, "feat: algo`n`n$cuerpo`n`nCo-Authored-By: Claude <noreply@anthropic.com>")
  git -C $t commit -q --allow-empty -F $f
  return (git -C $t rev-parse HEAD).Trim()
}
# El reporte se decodifica como UTF-8 acá, por `StandardOutputEncoding`, y no con lo que tenga puesto
# la consola: `& pwsh` lo decodifica con [Console]::OutputEncoding, y bajo `run-all.ps1` esa code page
# se la fija cualquier otra suite que corra en paralelo. MEDIDO el 2026-09-20: con la consola en 850
# el assert del em dash de `sinRuta` caía, y el mismo assert pasaba con la consola en 65001 (issue 15).
function Marcar([string]$t, [string]$sha = "") {
  $psi = [Diagnostics.ProcessStartInfo]::new('pwsh')
  foreach ($a in '-NoProfile', '-File', $marcar, '-RepoDir', $t) { $psi.ArgumentList.Add($a) }
  if ($sha) { $psi.ArgumentList.Add('-Sha'); $psi.ArgumentList.Add($sha) }
  $psi.UseShellExecute = $false
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.StandardOutputEncoding = [Text.UTF8Encoding]::new($false)
  $psi.StandardErrorEncoding = [Text.UTF8Encoding]::new($false)
  $p = [Diagnostics.Process]::Start($psi)
  try {
    # En paralelo: leer los dos canales en serie puede trabar al hijo si se le llena el otro buffer.
    $err = $p.StandardError.ReadToEndAsync()
    $salida = $p.StandardOutput.ReadToEnd()
    $p.WaitForExit()
    $r = @{ exit = $p.ExitCode; out = $salida.Trim(); err = $err.Result.Trim(); rep = $null }
  } finally { $p.Dispose() }
  try { $r.rep = $r.out | ConvertFrom-Json } catch { }
  return $r
}

# --- Tracer: el Slice-Close cita un issue → queda done y el resto del archivo intacto ---
$t = New-Repo
$p = New-Issue $t ".scratch/feat-a/issues/01-uno.md"
$antes = [IO.File]::ReadAllText($p)
Commit $t "Slice-Close: .scratch/feat-a/issues/01-uno.md — algo" | Out-Null
$r = Marcar $t
# Bytes y no ReadAllText: éste se come el BOM, y un script que agregara uno pasaría en verde.
$despues = [Convert]::ToBase64String([IO.File]::ReadAllBytes($p))
$esperado = [Convert]::ToBase64String([Text.UTF8Encoding]::new($false).GetBytes($antes.Replace("Status: ready-for-agent`r`n", "Status: done`r`n")))
Assert ($r.exit -eq 0) "tracer: exit 0 (fue $($r.exit); salida: $($r.out))"
Assert ($despues -ceq $esperado) "tracer: sólo la primera línea Status cambia a done, con CRLF intacto y sin BOM agregado"
Assert (@($r.rep.marcados) -contains ".scratch/feat-a/issues/01-uno.md") "tracer: el reporte lista el issue en marcados"
Assert ($r.rep.lineasSliceClose -eq 1 -and @($r.rep.sinRuta).Count -eq 0) "tracer: una línea Slice-Close y ningún valor en sinRuta (cita una ruta)"

# --- Varias rutas: dos en una línea y una en otro Slice-Close del mismo mensaje ---
$t = New-Repo
$a = New-Issue $t ".scratch/feat-a/issues/01-uno.md"
$b = New-Issue $t ".scratch/feat-a/issues/02-dos.md" "ready-for-human"
$c = New-Issue $t ".scratch/feat-b/issues/01-otro.md"
Commit $t "Slice-Close: .scratch/feat-a/issues/01-uno.md y .scratch/feat-a/issues/02-dos.md`nSlice-Close: .scratch/feat-b/issues/01-otro.md" | Out-Null
$r = Marcar $t
Assert ($r.exit -eq 0) "varias: exit 0 (fue $($r.exit))"
foreach ($x in @($a, $b, $c)) {
  Assert ([IO.File]::ReadAllText($x) -match "(?m)^Status: done`r$") "varias: $(Split-Path $x -Leaf) queda done"
}
Assert (@($r.rep.marcados).Count -eq 3) "varias: tres en marcados (fueron: $(@($r.rep.marcados) -join ', '))"

# --- Ruta citada que no existe: se reporta, no rompe, y los demás se marcan igual ---
$t = New-Repo
$a = New-Issue $t ".scratch/feat-a/issues/02-dos.md"
Commit $t "Slice-Close: .scratch/feat-a/issues/01-no-existe.md y .scratch/feat-a/issues/02-dos.md" | Out-Null
$r = Marcar $t
Assert ($r.exit -eq 0) "no existe: exit 0 (fue $($r.exit); salida: $($r.out))"
Assert (@($r.rep.noEncontrados) -contains ".scratch/feat-a/issues/01-no-existe.md") "no existe: va a noEncontrados"
Assert ([IO.File]::ReadAllText($a) -match "(?m)^Status: done`r$") "no existe: el otro citado se marca igual"
Assert (-not (Test-Path -LiteralPath (Join-Path $t ".scratch/feat-a/issues/01-no-existe.md"))) "no existe: no lo crea"

# --- Ya done: va a yaDone y el archivo no se toca (ni su fecha de escritura) ---
$t = New-Repo
$a = New-Issue $t ".scratch/feat-a/issues/01-uno.md" "done"
$viejo = [DateTime]::new(2020, 1, 1, 0, 0, 0, [DateTimeKind]::Utc)
[IO.File]::SetLastWriteTimeUtc($a, $viejo)
Commit $t "Slice-Close: .scratch/feat-a/issues/01-uno.md" | Out-Null
$r = Marcar $t
Assert (@($r.rep.yaDone) -contains ".scratch/feat-a/issues/01-uno.md") "ya done: va a yaDone (salida: $($r.out))"
Assert (@($r.rep.marcados).Count -eq 0) "ya done: no figura en marcados"
Assert ([IO.File]::GetLastWriteTimeUtc($a) -eq $viejo) "ya done: el archivo no se reescribe"

# --- BOM: un issue con BOM UTF-8 lo conserva, y los acentos no se deforman ---
$t = New-Repo
$p = Join-Path $t ".scratch/feat-a/issues/01-bom.md"
[IO.Directory]::CreateDirectory((Split-Path $p -Parent)) | Out-Null
[IO.File]::WriteAllText($p, "# título`r`n`r`nStatus: ready-for-agent`r`n", [Text.UTF8Encoding]::new($true))
Commit $t "Slice-Close: .scratch/feat-a/issues/01-bom.md" | Out-Null
Marcar $t | Out-Null
$esperado = [Text.UTF8Encoding]::new($true).GetPreamble() + [Text.Encoding]::UTF8.GetBytes("# título`r`n`r`nStatus: done`r`n")
Assert ([Convert]::ToBase64String([IO.File]::ReadAllBytes($p)) -ceq [Convert]::ToBase64String($esperado)) "BOM: se conserva byte a byte salvo el Status"

# --- Sin nada que marcar: sin Slice-Close, o con uno de texto libre sin ruta ---
foreach ($caso in @(
    @{ n = "sin Slice-Close"; cuerpo = "cuerpo que nombra .scratch/feat-a/issues/01-uno.md sin trailer" },
    @{ n = "Slice-Close sin ruta"; cuerpo = "Slice-Close: issue 01 — texto libre" })) {
  $t = New-Repo
  $a = New-Issue $t ".scratch/feat-a/issues/01-uno.md"
  $antes = [IO.File]::ReadAllText($a)
  Commit $t $caso.cuerpo | Out-Null
  $r = Marcar $t
  Assert ($r.exit -eq 0 -and $null -ne $r.rep) "$($caso.n): exit 0 con reporte (fue $($r.exit); salida: $($r.out))"
  Assert (@($r.rep.marcados).Count -eq 0 -and [IO.File]::ReadAllText($a) -ceq $antes) "$($caso.n): no marca nada"
}

# --- Issue citado sin línea Status: no se toca y no se reporta como marcado ---
$t = New-Repo
$p = Join-Path $t ".scratch/feat-a/issues/01-sin-status.md"
[IO.Directory]::CreateDirectory((Split-Path $p -Parent)) | Out-Null
[IO.File]::WriteAllText($p, "# titulo`r`n`r`nsin estado`r`n")
Commit $t "Slice-Close: .scratch/feat-a/issues/01-sin-status.md" | Out-Null
$r = Marcar $t
Assert ($r.exit -eq 0) "sin Status: exit 0 (fue $($r.exit); salida: $($r.out))"
Assert (@($r.rep.sinStatus) -contains ".scratch/feat-a/issues/01-sin-status.md" -and @($r.rep.marcados).Count -eq 0) "sin Status: va a sinStatus, no a marcados"
Assert ([IO.File]::ReadAllText($p) -ceq "# titulo`r`n`r`nsin estado`r`n") "sin Status: el archivo queda igual"

# --- Sólo `.scratch/<feature>/issues/<archivo>.md`: ni `..`, ni el PRD, ni otra carpeta ---
$t = New-Repo
$prd  = New-Issue $t ".scratch/feat-a/PRD.md"
$afue = New-Issue $t "fuera.md"
$hond = New-Issue $t ".scratch/feat-a/issues/sub/01-hondo.md"
$ok   = New-Issue $t ".scratch/feat-a/issues/01-uno.md"
$raiz = New-Issue $t "issues/01-raiz.md"
Commit $t ("Slice-Close: .scratch/feat-a/PRD.md, .scratch/feat-a/issues/../../../fuera.md, .scratch/../issues/01-raiz.md, " +
  "x.scratch/feat-a/issues/01-uno.md, .scratch/feat-a/issues/sub/01-hondo.md") | Out-Null
$r = Marcar $t
Assert ($r.exit -eq 0) "fuera: exit 0 (fue $($r.exit); salida: $($r.out))"
foreach ($x in @($prd, $afue, $hond, $ok, $raiz)) {
  Assert ([IO.File]::ReadAllText($x) -match "(?m)^Status: ready-for-agent`r$") "fuera: $($x.Substring($t.Length)) no se toca"
}
Assert ((@($r.rep.marcados) + @($r.rep.noEncontrados) + @($r.rep.yaDone) + @($r.rep.sinStatus)).Count -eq 0) "fuera: ninguna figura en el reporte"

# --- Entre backticks y citada dos veces: se marca una vez ---
$t = New-Repo
$a = New-Issue $t ".scratch/feat-a/issues/01-uno.md"
Commit $t "Slice-Close: ``.scratch/feat-a/issues/01-uno.md`` — algo`nSlice-Close: .scratch/feat-a/issues/01-uno.md" | Out-Null
$r = Marcar $t
Assert ([IO.File]::ReadAllText($a) -match "(?m)^Status: done`r$") "backticks: queda done"
Assert (@($r.rep.marcados).Count -eq 1 -and @($r.rep.yaDone).Count -eq 0) "dos veces: una sola entrada, en marcados (salida: $($r.out))"

# --- -Sha: lee ESE commit, no HEAD; y un SHA inexistente sale 1 sin tocar nada ---
$t = New-Repo
$a = New-Issue $t ".scratch/feat-a/issues/01-uno.md"
$cierre = Commit $t "Slice-Close: .scratch/feat-a/issues/01-uno.md"
Commit $t "sin cierre" | Out-Null
$r = Marcar $t "0000000000000000000000000000000000000000"
Assert ($r.exit -eq 1) "SHA inexistente: exit 1 (fue $($r.exit))"
Assert ([IO.File]::ReadAllText($a) -match "(?m)^Status: ready-for-agent`r$") "SHA inexistente: no toca nada"
$r = Marcar $t $cierre
Assert (@($r.rep.marcados) -contains ".scratch/feat-a/issues/01-uno.md") "-Sha: marca el issue que cita ese commit aunque HEAD no cierre nada"

# --- La línea Slice-Close, con la misma regla que hub-recolectar: sin distinguir mayúsculas, a principio
# de línea (con sangría o no) y con el valor en la MISMA línea ---
foreach ($caso in @(
    @{ n = "minúsculas";      cuerpo = "slice-close: .scratch/feat-a/issues/01-uno.md"; marca = $true },
    @{ n = "con sangría";     cuerpo = "  Slice-Close: .scratch/feat-a/issues/01-uno.md"; marca = $true },
    @{ n = "a mitad de frase"; cuerpo = "ver Slice-Close: .scratch/feat-a/issues/01-uno.md"; marca = $false },
    @{ n = "valor en la línea siguiente"; cuerpo = "Slice-Close:`n.scratch/feat-a/issues/01-uno.md"; marca = $false })) {
  $t = New-Repo
  $a = New-Issue $t ".scratch/feat-a/issues/01-uno.md"
  Commit $t $caso.cuerpo | Out-Null
  $r = Marcar $t
  $done = [IO.File]::ReadAllText($a) -match "(?m)^Status: done`r$"
  Assert ($done -eq $caso.marca) "Slice-Close $($caso.n): $(if ($caso.marca) { 'marca' } else { 'no marca' }) el issue (salida: $($r.out))"
}

# --- Issue que no es UTF-8 válido (cp1252 con acentos): no se reescribe, va a noUtf8 ---
# El decodificador no estricto cambiaba cada byte inválido por U+FFFD y la reescritura lo dejaba así,
# en un archivo gitignoreado sin copia en git.
$t = New-Repo
$p = Join-Path $t ".scratch/feat-a/issues/01-ansi.md"
[IO.Directory]::CreateDirectory((Split-Path $p -Parent)) | Out-Null
$ansi = [Text.Encoding]::GetEncoding(1252).GetBytes("# migración`r`n`r`nStatus: ready-for-agent`r`n")
[IO.File]::WriteAllBytes($p, $ansi)
Commit $t "Slice-Close: .scratch/feat-a/issues/01-ansi.md" | Out-Null
$r = Marcar $t
Assert ($r.exit -eq 0) "no UTF-8: exit 0 (fue $($r.exit); salida: $($r.out))"
Assert (@($r.rep.noUtf8) -contains ".scratch/feat-a/issues/01-ansi.md" -and @($r.rep.marcados).Count -eq 0) "no UTF-8: va a noUtf8, no a marcados"
Assert ([Convert]::ToBase64String([IO.File]::ReadAllBytes($p)) -ceq [Convert]::ToBase64String($ansi)) "no UTF-8: el archivo queda byte a byte igual"

# --- Por qué no marcó nada: el reporte distingue sin trailer, trailer sin ruta y ruta con barras invertidas ---
$t = New-Repo
New-Issue $t ".scratch/feat-a/issues/01-uno.md" | Out-Null
Commit $t "sin cierre" | Out-Null
$r = Marcar $t
Assert ($r.rep.lineasSliceClose -eq 0 -and @($r.rep.sinRuta).Count -eq 0) "sin trailer: lineasSliceClose 0 y sinRuta vacío (salida: $($r.out))"
Commit $t "Slice-Close: issue 01 — texto libre`nSlice-Close: .scratch\feat-a\issues\01-uno.md" | Out-Null
$r = Marcar $t
Assert ($r.rep.lineasSliceClose -eq 2) "trailer sin ruta: lineasSliceClose cuenta las dos líneas (salida: $($r.out))"
Assert (@($r.rep.sinRuta) -contains "issue 01 — texto libre" -and @($r.rep.sinRuta) -contains ".scratch\feat-a\issues\01-uno.md") "trailer sin ruta: sinRuta lista los dos valores, la ruta con barras invertidas incluida"
# Un valor que sólo cita rutas rechazadas (`..`) tampoco cita nada: sin esto, lineasSliceClose 1 con
# todas las listas vacías no dice por qué no se marcó nada.
Commit $t "Slice-Close: .scratch/../issues/01-uno.md`nSlice-Close: .scratch/feat-a/issues/01-uno.md y texto" | Out-Null
$r = Marcar $t
Assert (@($r.rep.sinRuta).Count -eq 1 -and @($r.rep.sinRuta)[0] -ceq ".scratch/../issues/01-uno.md") "sólo rutas rechazadas: ese valor va a sinRuta, el que cita una válida no (salida: $($r.out))"

# --- Estructura: el rol `done` y el paso que lo escribe, en el repo y en los tres scaffolds ---
# Anclas diagnósticas: que el script exista no sirve si ninguna skill lo manda a correr, ni que el loop
# lo corra si el vocabulario no conoce el rol.
$raices = @($repo) + @("bootstrap-ai-project", "bootstrap-personal-project", "bootstrap-southpoint-project" |
  ForEach-Object { Join-Path $repo "skills/$_/assets/scaffold" })
function Texto($p) { if (Test-Path -LiteralPath $p) { [IO.File]::ReadAllText($p) -replace "`r`n", "`n" } else { "" } }
$anclas = [ordered]@{
  ".agents/skills/triage/SKILL.md" = @('- `done`: implemented; the slice that closed it passed `/review-loop`', '`ready-for-agent` and `ready-for-human` move to `done`')
  ".claude/commands/triage.md"     = @('- `done`: implemented; the slice that closed it passed `/review-loop`', '`ready-for-agent` and `ready-for-human` move to `done`')
  "docs/agents/triage-labels.md"   = @('| `done`                     | `done`               |')
  ".agents/skills/setup-matt-pocock-skills/triage-labels.md" = @('| `done`                     | `done`               |')
  ".agents/skills/review-loop/SKILL.md" = @('**Mark the closed issues `done`**', 'if **no High finding is left open**', '.claude/scripts/marcar-done.ps1 -RepoDir . -Sha <the commit noted on turn 1>', 'Also on the first turn, note the commit that', 'Do not collect commits from `-Action slice-base` or a branch range', 'With a High still open, do not run it', 'List the issues marked `done`')
  ".claude/commands/review-loop.md"     = @('**Mark the closed issues `done`**', 'if **no High finding is left open**', '.claude/scripts/marcar-done.ps1 -RepoDir . -Sha <the commit noted on turn 1>', 'Also on the first turn, note the commit that', 'Do not collect commits from `-Action slice-base` or a branch range', 'With a High still open, do not run it', 'List the issues marked `done`')
  ".agents/skills/setup-matt-pocock-skills/SKILL.md" = @('the six canonical triage roles', '`ready-for-human`, `wontfix`, `done`. On **yes**')
  ".claude/commands/setup-matt-pocock-skills.md"     = @('the six canonical triage roles', '`ready-for-human`, `wontfix`, `done`. On **yes**')
  ".agents/skills/tdd/SKILL.md" = @('cite each by its path in the trailer (`Slice-Close: .scratch/<feature>/issues/<NN>-<slug>.md')
  ".claude/commands/tdd.md"     = @('cite each by its path in the trailer (`Slice-Close: .scratch/<feature>/issues/<NN>-<slug>.md')
  "CLAUDE.md" = @('ready-for-human, wontfix, done)')
}
$scriptHash = (Get-FileHash -LiteralPath $marcar).Hash
foreach ($r in $raices) {
  $etq = if ($r -eq $repo) { "repo" } else { Split-Path (Split-Path (Split-Path $r -Parent) -Parent) -Leaf }
  foreach ($f in $anclas.Keys) {
    $txt = Texto (Join-Path $r $f)
    foreach ($a in $anclas[$f]) { Assert ($txt.Contains($a)) "$etq/$f nombra: $a" }
  }
  # El paso muta: no puede tomar su rango del ancla, que ante la duda erra hacia MÁS commits.
  foreach ($f in ".agents/skills/review-loop/SKILL.md", ".claude/commands/review-loop.md") {
    $txt = Texto (Join-Path $r $f)
    $i = $txt.IndexOf('**Mark the closed issues `done`**', [StringComparison]::Ordinal)
    $j = $txt.IndexOf('Run `-Action close` on a **clean**', [StringComparison]::Ordinal)
    $paso = if ($i -ge 0 -and $j -gt $i) { $txt.Substring($i, $j - $i) } else { "" }
    Assert ($paso -and $paso -notmatch 'git rev-list|\$base\.\.HEAD') "$etq/$f el paso de marcar done no arma un rango de commits"
  }
  $s = Join-Path $r ".claude/scripts/marcar-done.ps1"
  Assert ((Test-Path -LiteralPath $s) -and (Get-FileHash -LiteralPath $s).Hash -eq $scriptHash) "$etq tiene marcar-done.ps1 idéntico al de southpoint"
}

# --- En una consola que no es UTF-8: el reporte llega intacto y el encoding no se le pega a nadie ---
# `[Console]::OutputEncoding` es de la CONSOLA, no del proceso: el que la fija se la deja puesta a
# todo lo que arranque después ahí, que con `run-all.ps1` en paralelo son las otras suites (issue 15).
# La sonda corre DESPUÉS del script, en su misma consola privada, y tiene que seguir viendo el 850.
$t = New-Repo
New-Issue $t ".scratch/feat-a/issues/01-uno.md" | Out-Null
Commit $t "Slice-Close: issue 01 — texto libre" | Out-Null
$r = Invoke-EnConsolaPropia -RunRoot $script:runRoot -Script $marcar -ConSonda -Cp 850 -Argumentos @('-RepoDir', $t)
$repEn850 = $null
try { $repEn850 = $r.out | ConvertFrom-Json } catch { }
Assert ($r.exit -eq 0 -and $null -ne $repEn850) "en una consola en 850 marcar-done corre y su reporte es JSON (exit $($r.exit); $($r.err))"
Assert (@($repEn850.sinRuta) -contains "issue 01 — texto libre") `
  "y el reporte sale en UTF-8 aunque la consola esté en 850 (fue '$(@($repEn850.sinRuta) -join ', ')')"
Assert ($r.cpSonda -eq 850) `
  "marcar-done no le cambia el encoding al proceso siguiente de su consola (la sonda arrancó en $($r.cpSonda), esperaba 850)"

Remove-TestRunRoot $script:runRoot
if ($script:failures) { Write-Host "`n$($script:failures) FALLAS"; exit 1 }
Write-Host "`nTodo verde"
