# tests/review-loop-docs-gate.tests.ps1 — runner sin Pester.
# Correr: pwsh -NoProfile -File tests/review-loop-docs-gate.tests.ps1
#
# POR QUE EXISTE ESTE ARCHIVO. El gate de "un slice de solo documentación no se revisa" decide
# CUANDO se revisa el código. Un bug acá no se ve: apaga revisiones en silencio. La v1 del gate en
# SouthPoint-Hub trataba todo `docs/` como documentación y dejaba sin revisar `docs/design-frozen/**`,
# que su CLAUDE.md declara fuente de verdad del frontend; se encontró en review, no en uso
# (commit 21a464e de ese repo). Cada fila de acá fija uno de esos falsos negativos.
#
# A diferencia de la probe original, estos casos NO copian el clasificador: corren el hook REAL
# de punta a punta sobre repos git temporales, así que un cambio en `$govern` que rompa la
# clasificación cae en rojo acá aunque la expresión siga pareciendo razonable.
$ErrorActionPreference = "Stop"
$repoRoot = Split-Path $PSScriptRoot -Parent
$hook = Join-Path $repoRoot "skills/bootstrap-personal-project/assets/scaffold/.claude/hooks/review-loop-trigger.ps1"
$script:failures = 0

function Assert($cond, $msg) {
  if ($cond) { Write-Host "ok:   $msg" } else { Write-Host "FAIL: $msg"; $script:failures++ }
}

function New-Repo {
  $t = Join-Path ([IO.Path]::GetTempPath()) ("rlg-test-" + [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $t | Out-Null
  git -C $t init -q -b master; git -C $t config user.email a@b.c; git -C $t config user.name a
  # Mismo aislamiento del gitconfig global que el resto de la suite: con `commit.gpgsign=true` en la
  # máquina los commits del fixture no se crean y todos los asserts de ausencia pasan en falso.
  git -C $t config commit.gpgsign false; git -C $t config core.hooksPath ""; git -C $t config core.excludesFile ""
  # `core.quotePath` explícito en true: si el dev tiene `false` en su config global, el fixture del
  # path con acento pasaría en verde sobre un hook al que le falta el flag.
  git -C $t config core.quotePath true
  # Y `diff.renames` explícito en true por la razón simétrica: con `false` en la config global del
  # dev, git lista los dos paths de un rename y el caso del rename pasaría en verde sobre un hook al
  # que le falta `--no-renames`.
  git -C $t config diff.renames true
  git -C $t commit --allow-empty -q -m base
  git -C $t checkout -q -b feat/x
  return $t
}

# Commitea los archivos indicados (contenido irrelevante: el gate mira nombres, no contenido).
function Commit-Files($repo, [string[]]$paths) {
  foreach ($p in $paths) {
    $full = Join-Path $repo $p
    $dir = Split-Path $full -Parent
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    Set-Content -LiteralPath $full -Value "contenido" -Encoding UTF8
    git -C $repo add -- $p
  }
  $before = (git -C $repo rev-parse HEAD)
  git -C $repo commit -q -m "slice"
  # Control positivo: si el commit no se crea (gpgsign, hooks, cualquier config global que el
  # aislamiento de New-Repo no haya neutralizado), el repo queda con el diff vacío y los 9 casos que
  # esperan `dispara` pasan igual, en verde, sin ejercitar nada.
  if ((git -C $repo rev-parse HEAD) -eq $before) {
    Write-Host "FAIL: guard: el commit del fixture no se creó ($($paths -join ', '))"; $script:failures++
  }
}

# Deja un archivo SIN trackear (no lo commitea): `git diff` nunca los muestra.
function Add-Untracked($repo, $path) {
  $full = Join-Path $repo $path
  $dir = Split-Path $full -Parent
  if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
  Set-Content -LiteralPath $full -Value "contenido" -Encoding UTF8
}

function Fire($repo, $cmd) {
  $evt = @{ tool_input = @{ command = $cmd }; cwd = $repo } | ConvertTo-Json -Compress
  return ($evt | & pwsh -NoProfile -File $hook)
}

# Instala el marcador en el fixture. SIN esto los casos corren por el fallback `$base...HEAD`, que
# es un camino que NO existe en un repo bootstrapeado: todos traen el marcador. Es justo la lección
# que `review-loop-trigger.tests.ps1` ya dejaba escrita y que la primera versión de esta suite no
# aplicó — con los 15 casos por el fallback, mutar `$docRange` a "$base...HEAD" (el gate ignora el
# marcador) o a "HEAD~1...HEAD" (mira sólo el último commit) sobrevivía la suite entera.
# Se COMMITEA, como en un repo bootstrapeado de verdad. (No porque dejarlo sin trackear rompa el
# caso — `Advance-Marker` corre después y lo ficha en `untracked:<rama>`, así que el hook lo
# descontaría igual — sino porque un repo bootstrapeado lo tiene trackeado y el fixture tiene que
# parecerse a eso.)
function Add-Marker($repo) {
  $mk = Join-Path (Split-Path $PSScriptRoot -Parent) "skills/bootstrap-personal-project/assets/scaffold/.claude/scripts/review-marker.ps1"
  $dst = Join-Path $repo ".claude/scripts"
  New-Item -ItemType Directory -Path $dst -Force | Out-Null
  Copy-Item $mk (Join-Path $dst "review-marker.ps1")
  git -C $repo add -- ".claude/scripts/review-marker.ps1"
  $before = (git -C $repo rev-parse HEAD)
  git -C $repo commit -q -m "chore: marcador"
  if ((git -C $repo rev-parse HEAD) -eq $before) {
    Write-Host "FAIL: guard: el commit del marcador no se creó"; $script:failures++
  }
}

# Corta el marcador acá: lo commiteado hasta ahora queda "ya revisado". Se invoca igual que en
# `review-loop-trigger.tests.ps1` — path ABSOLUTO y `-RepoDir` — y no con `Push-Location` + path
# relativo: este repo tiene su propio `.claude/scripts/review-marker.ps1` en la raíz, y una
# resolución relativa que fallara avanzaría el marcador del usuario en vez del del fixture.
function Advance-Marker($repo) {
  $mk = Join-Path $repo ".claude/scripts/review-marker.ps1"
  $out = (& pwsh -NoProfile -File $mk -Action advance -RepoDir $repo 2>&1)
  $rc = $LASTEXITCODE
  # guard: si `advance` no corta marcador, los casos de abajo miden el fallback y no el marcador.
  if ($rc -ne 0 -or -not $out) {
    Write-Host "FAIL: guard: advance no cortó marcador (exit=$rc out='$out')"; $script:failures++
  }
  return $out
}

# Cada caso: los archivos del slice y si el hook TIENE que disparar el review.
# Se usa `git push` como disparador para aislar el gate de la compuerta del trailer `Slice-Close:`
# (el push dispara incondicionalmente; lo único que puede callarlo es este gate).
$cases = @(
  # --- prosa: NO se revisa ---
  @{ files = @("docs/notas.md");                       fire = $false; label = "slice de solo prosa (.md) no dispara" },
  @{ files = @("HANDOFF.md", "docs/adr/0001-x.md");     fire = $false; label = "varios .md sueltos siguen siendo solo-docs" },
  @{ files = @("docs/Especificación Funcional.md");     fire = $false; label = "un .md con acento sigue clasificando como doc (core.quotePath)" },

  # --- gobierna al agente: SÍ se revisa aunque sea .md ---
  @{ files = @("CLAUDE.md");                            fire = $true; label = "CLAUDE.md dispara: son las reglas duras, no prosa" },
  @{ files = @("sub/CLAUDE.md");                        fire = $true; label = "un CLAUDE.md anidado también dispara (anclaje (^|/), no ^)" },
  @{ files = @(".claude/commands/handoff.md");          fire = $true; label = ".claude/** dispara aunque sea .md" },
  @{ files = @(".agents/skills/tdd/SKILL.md");          fire = $true; label = ".agents/** dispara: las SKILL.md definen el trailer que arma este hook" },
  @{ files = @("docs/ai-workflow/QA_CHECKLIST.md");     fire = $true; label = "docs/ai-workflow/** dispara: lectura obligatoria del workflow" },
  @{ files = @("docs/agents/issue-tracker.md");         fire = $true; label = "docs/agents/** dispara: define las skills" },

  # --- código: SÍ se revisa ---
  @{ files = @("src/a.ts");                             fire = $true; label = "código normal dispara" },
  @{ files = @("docs/design/app.js");                   fire = $true; label = "código que vive bajo docs/ dispara (el falso negativo de la v1)" },
  @{ files = @("docs/notas.md", "src/a.ts");            fire = $true; label = "slice MIXTO dispara: basta un archivo no-doc" }
)

Write-Host "=== gate de slices solo-docs (hook real, end-to-end) ==="
foreach ($c in $cases) {
  $t = New-Repo
  Commit-Files $t $c.files
  $o = Fire $t "git push"
  $fired = [bool]($o -match "additionalContext")
  Assert ($fired -eq $c.fire) ("{0} [esperado={1} obtenido={2}]" -f $c.label, $(if ($c.fire) { "dispara" } else { "silencio" }), $(if ($fired) { "dispara" } else { "silencio" }))
  Remove-Item -Recurse -Force $t
}

# `git diff` NUNCA muestra untracked, así que un slice cuyo código nuevo todavía no se commiteó se
# vería como solo-docs y saldría sin revisar. Es exactamente el caso que el paso 5 del loop fabrica:
# manda escribir un test nuevo, que es untracked hasta que alguien lo commitea.
$t = New-Repo
Commit-Files $t @("docs/notas.md")
Add-Untracked $t "src/nuevo.ts"
$o = Fire $t "git push"
Assert ($o -match "additionalContext") "un .ts NUEVO sin trackear dispara aunque lo commiteado sea solo prosa"
Remove-Item -Recurse -Force $t

# El gate vale para todos los disparadores, no solo para el push: un cierre DECLARADO de un slice
# de prosa tampoco tiene que gastar un loop.
$t = New-Repo
New-Item -ItemType Directory -Path (Join-Path $t "docs") -Force | Out-Null
Set-Content -LiteralPath (Join-Path $t "docs/notas.md") -Value "x" -Encoding UTF8
git -C $t add -- "docs/notas.md"
git -C $t commit -q -m "docs: notas`n`nSlice-Close: notas"
$o = Fire $t "git commit -m x"
Assert ([string]::IsNullOrEmpty($o)) "un cierre DECLARADO de un slice solo-docs tampoco dispara"
Remove-Item -Recurse -Force $t

# Fail-open: si el rango no se puede resolver, se revisa. Nunca al revés.
$t = New-Repo
Commit-Files $t @("docs/notas.md")
git -C $t checkout -q --orphan huerfana
git -C $t commit --allow-empty -q -m "sin ancestro comun"
$o = Fire $t "git push"
Assert ($o -match "additionalContext") "fail-open: con un rango irresoluble (historias sin ancestro) se dispara igual"
Remove-Item -Recurse -Force $t

# --- El camino REAL: con el marcador instalado, que es como está todo repo bootstrapeado ---
# Sin estos dos casos, mutar `$docRange` a `"$base...HEAD"` (el gate ignora el marcador) o a
# `"HEAD~1...HEAD"` (mira sólo el último commit) sobrevive la suite entera, y el ajuste que motivó
# todo el port — decidir sobre el delta sin revisar — queda sin verificar.
Write-Host ""
Write-Host "=== camino del marcador ==="

# El delta sin revisar es solo prosa, aunque la rama YA traiga código de antes del marcador.
$t = New-Repo
Add-Marker $t
Commit-Files $t @("src/viejo.ts")
Advance-Marker $t | Out-Null
Commit-Files $t @("docs/notas.md")
$o = Fire $t "git push"
Assert ([string]::IsNullOrEmpty($o)) "con marcador: delta solo-docs no dispara aunque la rama ya tenga código revisado"
Remove-Item -Recurse -Force $t

# Al revés: el delta sin revisar TRAE código, aunque el último commit sea prosa. Es la frase que el
# comentario del hook afirma ("nunca sobre el último commit solo").
$t = New-Repo
Add-Marker $t
Advance-Marker $t | Out-Null
Commit-Files $t @("src/nuevo.ts")
Commit-Files $t @("docs/notas.md")
$o = Fire $t "git push"
Assert ($o -match "additionalContext") "con marcador: dispara si el delta trae código, aunque el último commit sea solo prosa"
Remove-Item -Recurse -Force $t

# El descuento contra la huella `untracked:<branch>` del marcador: un untracked ya fichado no puede
# mantener el gate apagado para siempre.
$t = New-Repo
Add-Marker $t
Add-Untracked $t "scratch.txt"
Advance-Marker $t | Out-Null
Commit-Files $t @("docs/notas.md")
$o = Fire $t "git push"
Assert ([string]::IsNullOrEmpty($o)) "un untracked YA fichado por el marcador no mantiene el gate apagado"
Remove-Item -Recurse -Force $t

Write-Host ""
Write-Host "=== bordes ==="

# El fallback `$base...HEAD` es un rango de COMMITS: el árbol queda afuera. Sin este caso, un slice
# cuyo único código es una modificación sin commitear de un archivo trackeado salía sin revisar.
# El código tiene que estar commiteado en la BASE, no en el slice: si está en el slice, el rango ya
# lo trae y el caso pasa sin ejercitar nada.
$t = New-Repo
git -C $t checkout -q master
New-Item -ItemType Directory -Path (Join-Path $t "src") -Force | Out-Null
Set-Content -LiteralPath (Join-Path $t "src/a.ts") -Value "codigo" -Encoding UTF8
git -C $t add -- "src/a.ts"; git -C $t commit -q -m "codigo en la base"
git -C $t checkout -q -B feat/x
Commit-Files $t @("docs/notas.md")
Set-Content -LiteralPath (Join-Path $t "src/a.ts") -Value "cambio sin commitear" -Encoding UTF8
# guard: el rango de commits tiene que ser SOLO prosa; si trae el .ts, el caso no prueba nada.
$rango = @(git -C $t diff --name-only "master...HEAD")
Assert ($rango -notcontains "src/a.ts") "guard: el rango de commits del fixture es solo prosa (trae: $($rango -join ', '))"
Assert (@(git -C $t status --porcelain).Count -gt 0) "guard: el fixture dejó la modificación sin commitear"
$o = Fire $t "git push"
Assert ($o -match "additionalContext") "sin marcador: una modificación SIN COMMITEAR de un archivo trackeado dispara"
Remove-Item -Recurse -Force $t

# Lo GENERADO no lo escribió nadie, así que no puede ser lo que haga valioso revisar un slice: sin
# esto, cualquier slice de docs que regenere el manifest dejaba el gate en nada.
$t = New-Repo
Commit-Files $t @("docs/notas.md", ".bootstrap-manifest.json")
$o = Fire $t "git push"
Assert ([string]::IsNullOrEmpty($o)) "un manifest GENERADO junto a la prosa no alcanza para disparar"
Remove-Item -Recurse -Force $t

# Pero un lockfile SÍ dispara, aunque no cuente líneas para el techo: es exactamente donde se
# verifica la regla dura de supply-chain del CLAUDE.md. Cuando el gate usaba la lista del techo, la
# decisión quedaba NO MONOTÓNICA — el lockfile solo disparaba, y el mismo lockfile con un README al
# lado se silenciaba: agregar prosa apagaba la revisión del código.
$t = New-Repo
Commit-Files $t @("docs/notas.md", "package-lock.json")
$o = Fire $t "git push"
Assert ($o -match "additionalContext") "un LOCKFILE junto a la prosa sí dispara (agregar prosa no puede apagar el review)"
Remove-Item -Recurse -Force $t

# Y lo vendorado también: el CLAUDE.md manda vendorear las libs críticas justo para poder mirarlas.
$t = New-Repo
Commit-Files $t @("docs/notas.md", "docs/vendor/lib/index.js")
$o = Fire $t "git push"
Assert ($o -match "additionalContext") "código vendorado junto a la prosa sí dispara"
Remove-Item -Recurse -Force $t

# La misma pregunta por la mitad UNTRACKED: el filtro del gate tiene que ser el mismo de los dos
# lados. Con `$skipPat` adentro de Get-UntrackedNew, un lockfile nuevo sin commitear desaparecía.
$t = New-Repo
Commit-Files $t @("docs/notas.md")
Add-Untracked $t "package-lock.json"
$o = Fire $t "git push"
Assert ($o -match "additionalContext") "un lockfile NUEVO sin trackear junto a la prosa también dispara"
Remove-Item -Recurse -Force $t

# Y la otra mitad de ese filtro: un GENERADO sin trackear tampoco alcanza. Sin este caso, sacar el
# filtro `$genPat` de la mitad untracked del gate sobrevivía la suite entera.
$t = New-Repo
Commit-Files $t @("docs/notas.md")
Add-Untracked $t ".bootstrap-manifest.json"
$o = Fire $t "git push"
Assert ([string]::IsNullOrEmpty($o)) "un manifest generado SIN TRACKEAR junto a la prosa no alcanza para disparar"
Remove-Item -Recurse -Force $t

# `*.snap` es la otra entrada de `$genPat` y no la cubría nadie: sacarla del hook dejaba la suite
# entera en verde.
$t = New-Repo
Commit-Files $t @("docs/notas.md", "__snapshots__/vista.snap")
$o = Fire $t "git push"
Assert ([string]::IsNullOrEmpty($o)) "un snapshot regrabado junto a la prosa no alcanza para disparar"
Remove-Item -Recurse -Force $t

# Camino de silencio que introdujo la separación de listas, fijado a propósito para que un cambio
# futuro lo tenga que declarar: un `.md` VENDORADO es prosa para el gate (el techo no lo cuenta como
# lógica, pero el gate no lo esconde: lo clasifica como documentación, que es lo que es).
$t = New-Repo
Commit-Files $t @("docs/vendor/lib/GUIA.md")
$o = Fire $t "git push"
Assert ([string]::IsNullOrEmpty($o)) "un slice de solo documentación VENDORADA no dispara"
Remove-Item -Recurse -Force $t

# Un slice de delta NETO VACÍO no es un slice solo-docs: no hay nada que juzgar, así que dispara.
$t = New-Repo
Commit-Files $t @("src/a.ts")
git -C $t rm -q -- "src/a.ts"
git -C $t commit -q -m "revierte"
$o = Fire $t "git push"
Assert ($o -match "additionalContext") "un slice de delta neto vacío dispara (vacío no es solo-docs)"
Remove-Item -Recurse -Force $t

# Fail-open CON untracked presente: sin este caso, sacar el guard del exit code del `git diff` deja
# la suite en verde porque el otro guard (colección vacía) lo tapa.
$t = New-Repo
Commit-Files $t @("docs/notas.md")
git -C $t checkout -q --orphan huerfana2
git -C $t commit --allow-empty -q -m "sin ancestro comun"
Add-Untracked $t "docs/suelta.md"
$o = Fire $t "git push"
Assert ($o -match "additionalContext") "fail-open sigue disparando aunque haya un untracked .md que podría taparlo"
Remove-Item -Recurse -Force $t

# Renames: `--name-only` con detección de renames muestra sólo el destino, así que mover código a un
# nombre .md silenciaba la revisión del borrado.
# El archivo se crea en la BASE: si nace y se mueve dentro del slice, el rango solo ve el destino y
# no hay rename que detectar. Y `git mv` falla si el directorio destino no existe — sin el guard,
# el commit queda sin hacer y el caso pasa porque el .ts original sigue en el rango.
$t = New-Repo
git -C $t checkout -q master
New-Item -ItemType Directory -Path (Join-Path $t "src") -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $t "docs") -Force | Out-Null
Set-Content -LiteralPath (Join-Path $t "src/config.ts") -Value ("linea`n" * 40) -Encoding UTF8
git -C $t add -- "src/config.ts"; git -C $t commit -q -m "config en la base"
git -C $t checkout -q -B feat/x
git -C $t mv "src/config.ts" "docs/config.md"
git -C $t commit -q -m "mueve"
# guard: el rename tiene que haber ocurrido de verdad Y git tiene que estar detectándolo (si no,
# este caso no distingue un hook con --no-renames de uno sin él).
$conDeteccion = @(git -C $t diff --name-only "master...HEAD")
# `-eq` sobre un array FILTRA, no compara: `@('a','b') -eq 'a'` devuelve `@('a')`, que es truthy.
# Escrito así, el guard pasaba en verde justo cuando git NO detectaba el rename — imprimiendo los
# dos paths como evidencia de su propia falla. Hay que comparar contra la CANTIDAD también.
Assert ($conDeteccion.Count -eq 1 -and $conDeteccion[0] -eq "docs/config.md") "guard: git detecta el rename y muestra solo el destino (muestra: $($conDeteccion -join ', '))"
$o = Fire $t "git push"
Assert ($o -match "additionalContext") "mover código a un nombre .md sigue disparando (rename no lo esconde)"
Remove-Item -Recurse -Force $t

# --- La prosa de los 4 CLAUDE.md tiene que decir lo que $govern hace ---
# Se LEE el clasificador del hook, no se copia: es lo que evita que esta suite se pruebe a sí misma.
Write-Host ""
Write-Host "=== la prosa coincide con el clasificador ==="
$hookSrc = Get-Content -LiteralPath $hook -Raw

# Las dos listas de exclusión se leen del hook y se fija su relación: `$genPat` (lo que no escribió
# nadie, lo usa el gate) tiene que ser subconjunto ESTRICTO de `$skipPat` (lo que no cuenta como
# líneas de lógica, lo usa el techo). Sin este assert nada detecta que se agregue un patrón a una
# lista y no a la otra — que es la forma de drift que motivó separarlas. Va FUERA del bloque de
# `$govern`: no depende de él, y adentro un cambio de forma de `$govern` se llevaba puesto también
# este chequeo, en silencio.
function Read-Pat($nombre) {
  # El `)` de cierre puede traer un comentario detrás. Sin admitirlo, el `.*?` seguía de largo hasta
  # el próximo `)` a fin de línea — veinte líneas más abajo — y devolvía una lista NO vacía con
  # basura adentro, que el guard de abajo no distinguía de una lectura sana.
  $m = [regex]::Match($hookSrc, "(?ms)^\`$$nombre\s*=\s*@\((.*?)\)\s*(#.*)?$")
  if (-not $m.Success) { return @() }
  $items = @([regex]::Matches($m.Groups[1].Value, "'([^']+)'") | ForEach-Object { $_.Groups[1].Value })
  # Un pathspec no tiene espacios ni saltos de línea: si alguno los tiene, el match se desbordó.
  if ($items | Where-Object { $_ -match '\s' }) { return @() }
  return $items
}
$skipPat = Read-Pat 'skipPat'
$genPat  = Read-Pat 'genPat'
Assert ($skipPat.Count -gt 0 -and $genPat.Count -gt 0) "guard: se leyeron las dos listas del hook (skipPat=$($skipPat.Count), genPat=$($genPat.Count))"
$fuera = $genPat | Where-Object { $skipPat -notcontains $_ }
Assert ($fuera.Count -eq 0) "genPat es subconjunto de skipPat [afuera: $($fuera -join ', ')]"
# Nota: un refactor que exprese la relación en código (`$skipPat = $genPat + @(...)`) va a poner
# esto en rojo porque Read-Pat no lo va a poder leer. Falla nombrándose, que es la dirección buena.
Assert ($genPat.Count -lt $skipPat.Count) "genPat es subconjunto ESTRICTO (genPat=$($genPat.Count) < skipPat=$($skipPat.Count))"
if ($hookSrc -notmatch "(?m)^\s*\`$govern\s*=\s*'([^']+)'") {
  Write-Host "FAIL: guard: no se pudo leer `$govern del hook — ¿cambió de forma?"; $script:failures++
} else {
  $govern = $matches[1]
  $alts = $govern -split '\|(?![^(]*\))'

  # (el chequeo de las dos listas vive fuera de este if: no depende de $govern)
  Assert ($alts.Count -eq 5) "govern tiene 5 alternativas (leídas del hook: $($alts.Count))"
  Assert (($alts | Where-Object { $_ -notmatch '^\(\^\|/\)' }).Count -eq 0) "TODAS las alternativas de govern están ancladas (^|/), ninguna a la raíz sola"

  # Las rutas esperadas se DERIVAN del `$govern` del hook, no se hardcodean: hardcodeadas dejaban
  # sin chequear la alternativa de `CLAUDE.md` (la 3ra) y permitían agregar una rama al clasificador
  # sin tocar la prosa.
  # OJO: la derivación sólo deshace el ancla `(^|/)`, el `$` final y el escape `\.`. Cualquier
  # alternativa que NO sea una ruta literal (una clase de caracteres, un `?`, un grupo `(a|b)`)
  # devuelve un literal con metacaracteres que la prosa nunca va a tener, y este assert queda en
  # rojo permanente: si agregás una así, hay que tocar esta derivación, no la prosa.
  $rutas = $alts | ForEach-Object { ($_ -replace '^\(\^\|/\)', '' -replace '\$$', '').Replace('\.', '.') }
  $root = Split-Path $PSScriptRoot -Parent
  $claudeMds = @((Join-Path $root "CLAUDE.md")) + @(Get-ChildItem (Join-Path $root "skills") -Recurse -Filter "CLAUDE.md" | Where-Object { $_.FullName -match 'assets' } | ForEach-Object { $_.FullName })
  # guard: una colección vacía haría pasar el foreach entero sin chequear nada.
  Assert ($claudeMds.Count -eq 4) "guard: se encontraron los 4 CLAUDE.md (encontrados: $($claudeMds.Count))"
  foreach ($f in $claudeMds) {
    $etiqueta = $f.Substring($root.Length).TrimStart('\', '/')
    Assert (Test-Path -LiteralPath $f) "guard: existe $etiqueta"
    # El bullet se recorta del texto CRUDO por su encabezado, no juntando las líneas que mencionen
    # `review-loop-trigger`: juntando por palabra, cualquier otra línea del archivo que mencione el
    # hook satisfacía el assert desde afuera del bullet, y un reflow del bullet a dos líneas (un
    # `markdownlint --fix` alcanza) lo partía y daba rojo diciendo que faltaban rutas que sí estaban.
    # El corte es `^-\s` sin `\s*`: con `\s*` cualquier sub-lista INDENTADA adentro del bullet lo
    # truncaba ahí, y el resultado dependía de dónde estuviera la indentación — rojo si iba antes de
    # la lista de rutas, verde si iba después. Una sub-lista es markdown legítimo; sólo un bullet de
    # primer nivel cierra el bullet.
    $txt = Get-Content -LiteralPath $f -Raw
    $m = [regex]::Matches($txt, '(?ms)^- After implementation, run .*?(?=^-\s|\z)')
    Assert ($m.Count -eq 1) "guard: $etiqueta tiene exactamente un bullet de review-loop (encontrados: $($m.Count))"
    # Sin este `continue`, un guard en rojo arrastra 3 rojos más por archivo con la misma causa raíz.
    if ($m.Count -ne 1) { continue }
    $bullet = $m[0].Value
    # Las rutas se buscan DENTRO de la lista entre paréntesis, no en el bullet entero: `docs/` está
    # nombrado en el bullet en la frase que dice lo CONTRARIO ("anything else under `docs/` is
    # code"), así que sobre el bullet completo una alternativa `docs/` habría quedado anclada por la
    # frase que la niega.
    $lista = ([regex]::Match($bullet, 'no matter their extension \(([^)]+)\)')).Groups[1].Value
    Assert ($lista) "guard: $etiqueta tiene la lista de rutas entre paréntesis"
    $faltan = $rutas | Where-Object { $lista -notmatch [regex]::Escape('`' + $_ + '`') }
    Assert ($faltan.Count -eq 0) "$etiqueta enumera en su bullet las rutas de govern [faltan: $($faltan -join ', ')]"
    # La DIRECCIÓN de la regla, no sólo las rutas: sin esto, la prosa podía invertirse ("todo lo que
    # está bajo docs/ cuenta como documentación" = el bug exacto de la v1) y quedar en verde.
    Assert ($bullet -match [regex]::Escape('`.md` is the only thing that counts as documentation')) "$etiqueta dice que SOLO .md es documentación"
    Assert ($bullet -match 'never documentation') "$etiqueta dice que lo que gobierna al agente NUNCA es documentación"
  }
}

Write-Host ""
if ($script:failures -eq 0) { Write-Host "TODOS LOS TESTS PASARON"; exit 0 }
Write-Host "$($script:failures) test(s) FALLARON"
exit 1
