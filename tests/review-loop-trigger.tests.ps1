# tests/review-loop-trigger.tests.ps1 — runner sin Pester. Correr: pwsh -NoProfile -File tests/review-loop-trigger.tests.ps1
# Fixtures determinísticos (repos git temporales) para el hook review-loop-trigger y el merge de settings.
$ErrorActionPreference = "Stop"
$repo  = Split-Path $PSScriptRoot -Parent
$hook  = Join-Path $repo "skills/bootstrap-personal-project/assets/scaffold/.claude/hooks/review-loop-trigger.ps1"
$canon = Join-Path $repo "skills/bootstrap-personal-project/assets/scaffold/.claude/settings.json"
$ms    = Join-Path $repo "skills/upgrade-bootstrap/scripts/merge-settings.ps1"
$script:failures = 0

function Assert($cond, $msg) {
  if ($cond) { Write-Host "ok:   $msg" } else { Write-Host "FAIL: $msg"; $script:failures++ }
}
function New-Repo {
  $t = Join-Path ([IO.Path]::GetTempPath()) ("rlt-test-" + [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $t | Out-Null
  git -C $t init -q -b master; git -C $t config user.email a@b.c; git -C $t config user.name a
  # Aislar el gitconfig global: con `commit.gpgsign=true` en la máquina, los commits del fixture no
  # se crean y TODOS los asserts de ausencia pasan en verde sin ejercitar nada.
  git -C $t config commit.gpgsign false; git -C $t config core.hooksPath ""; git -C $t config core.excludesFile ""
  git -C $t commit --allow-empty -q -m base
  git -C $t checkout -q -b feat/x; git -C $t commit --allow-empty -q -m slice
  return $t
}
# Commit que DECLARA el cierre de slice con el trailer. Sin el trailer el hook no dispara.
function Close-Slice($repo, $subject) {
  git -C $repo commit --allow-empty -q -m "$subject`n`nSlice-Close: $subject"
}
# Invoca el hook con un evento PostToolUse; cwd debe ser un path Windows real (como lo pasa Claude Code).
# $cwd separado del repo: el evento trae el cwd de la SESION, que en un monorepo es un subdirectorio.
function Fire($repo, $cmd, $cwd) {
  if (-not $cwd) { $cwd = $repo }
  $evt = @{ tool_input = @{ command = $cmd }; cwd = $cwd } | ConvertTo-Json -Compress
  return ($evt | & pwsh -NoProfile -File $hook)
}

# --- Hook ---
$t = New-Repo; $o = Fire $t "ls -la"
Assert ([string]::IsNullOrEmpty($o)) "no-op (comando no-git) no emite nada"; Remove-Item -Recurse -Force $t

$t = New-Repo; $o = Fire $t "git push"
Assert ($o -match "additionalContext") "git push en feature branch dispara"; Remove-Item -Recurse -Force $t

$t = New-Repo; $o = Fire $t "git commit -m slice"
Assert ([string]::IsNullOrEmpty($o)) "git commit SIN trailer Slice-Close no dispara"; Remove-Item -Recurse -Force $t

$t = New-Repo; $o = Fire $t "git commit-graph write"
Assert ([string]::IsNullOrEmpty($o)) "git commit-graph (falso positivo) NO dispara"; Remove-Item -Recurse -Force $t

$t = New-Repo; git -C $t checkout -q master; $o = Fire $t "git push"
Assert ([string]::IsNullOrEmpty($o)) "estar en la base no dispara"; Remove-Item -Recurse -Force $t

# Sin crear la rama a proposito: el hook NO valida que la base exista — toma el valor de `--base`
# tal cual y lo pone en el mensaje inyectado. Los tres fixtures de `--base` creaban `develop` como
# setup, y medido (las tres formas, con y sin la rama) los seis asserts pasan igual: el setup no
# ejercitaba nada y hacia leer el caso como si la existencia estuviera cubierta. Que la base no se
# verifique esta declarado como limite conocido en docs/TESTING.md y se arregla en A2b, junto con la
# resolucion de base del hook.
$t = New-Repo; $o = Fire $t "gh pr create --base develop"
Assert (($o -match "additionalContext") -and ($o -match "develop")) "gh pr create --base develop usa develop (no hardcodea main)"; Remove-Item -Recurse -Force $t

$t = New-Repo; Close-Slice $t "slice"; $o = Fire $t "git commit -m slice"
Assert (($o -match "additionalContext") -and ($o -match "review-loop NOW")) "git commit CON trailer Slice-Close dispara con mensaje imperativo"
Assert (($o -match "review-marker\.ps1") -and ($o -match "-Action range")) "el mensaje inyectado manda el ciclo al delta sin revisar, no al rango completo de la rama"
Remove-Item -Recurse -Force $t

# Alta A (A2b): en un repo cuya base NO se llama main/master/develop, el hook resolvia la base con
# `exit 0` ANTES del gate del trailer (paso 4), quedando MUDO y perdiendo un cierre DECLARADO — el
# falso negativo que este hook existe para eliminar, escondido justo en GitHub donde `gh repo view`
# lo rescataba. Ahora delega la base al marcador CO-UBICADO (-Action base), que resuelve `trunk`/`dev`/
# `release` via for-each-ref + merge-base --octopus. Mutante: revertir el bloque de delegacion (volver
# al `exit 0`) deja este assert en rojo y el resto de la suite en verde.
$mk = Join-Path $repo "skills/bootstrap-personal-project/assets/scaffold/.claude/scripts/review-marker.ps1"
$t = Join-Path ([IO.Path]::GetTempPath()) ("rlt-test-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $t | Out-Null
git -C $t init -q -b trunk; git -C $t config user.email a@b.c; git -C $t config user.name a
git -C $t config commit.gpgsign false; git -C $t config core.hooksPath ""; git -C $t config core.excludesFile ""
git -C $t commit --allow-empty -q -m base
git -C $t checkout -q -b feat/y
# En un proyecto bootstrapeado el marcador esta presente: el hook delega en el.
New-Item -ItemType Directory -Path (Join-Path $t ".claude/scripts") -Force | Out-Null
Copy-Item $mk (Join-Path $t ".claude/scripts/review-marker.ps1")
Close-Slice $t "la feature y"
$o = Fire $t "git commit -m cierre"
Assert (($o -match "additionalContext") -and ($o -match "review-loop NOW")) "Alta A: cierre declarado en repo con base 'trunk' dispara (el hook delega la base al marcador)"
Remove-Item -Recurse -Force $t

# El evento dice `git commit` y trae el cwd de la sesion, pero el comando corrio en OTRO repo:
# el HEAD de ESTE repo quedo viejo. Reproducido en vivo el 2026-08-11 con un repo de mktemp -d.
$t = New-Repo
$env:GIT_COMMITTER_DATE = "2020-01-01T00:00:00 +0000"
Close-Slice $t "slice viejo"
Remove-Item Env:GIT_COMMITTER_DATE
$o = Fire $t "git commit -m commit-en-otro-repo"
Assert ([string]::IsNullOrEmpty($o)) "un commit ejecutado en otro repo no dispara aca (el HEAD de este repo no es reciente)"; Remove-Item -Recurse -Force $t

# Los dos bordes de la ventana. Sin ellos el valor no queda fijado: el fixture de arriba usa 2020,
# asi que cualquier ventana menor a 6 años lo satisface y mutar 900 -> 86400 sobrevive.
# El borde de abajo es el caso real: el hook es PostToolUse y corre cuando termina TODA la llamada
# de Bash, asi que `git commit ... && npm test` sella el commit varios minutos antes del evento.
function Commit-At($repo, $secondsAgo, $subject) {
  $env:GIT_COMMITTER_DATE = ([DateTimeOffset]::UtcNow.AddSeconds(-$secondsAgo).ToString("yyyy-MM-ddTHH:mm:ss zzz"))
  git -C $repo commit --allow-empty -q -m "$subject`n`nSlice-Close: $subject"
  Remove-Item Env:GIT_COMMITTER_DATE
}
$t = New-Repo; Commit-At $t 600 "cierre tras una suite larga"
$o = Fire $t "git commit -m x && pwsh tests/suite.ps1"
Assert ($o -match "additionalContext") "un cierre declarado hace 10 min sigue disparando (el comando tardo, el commit es de aca)"; Remove-Item -Recurse -Force $t

$t = New-Repo; Commit-At $t 5400 "commit viejo"
$o = Fire $t "git commit -m x"
Assert ([string]::IsNullOrEmpty($o)) "un HEAD de hace 90 min ya no cuenta como commit de esta corrida"; Remove-Item -Recurse -Force $t

# El Abs() de la ventana: sin el, un reloj adelantado da diferencia negativa, nunca supera los 1800
# y cualquier commit ajeno pasa de largo. Sin este fixture, sacar Abs() sobrevive.
$t = New-Repo; Commit-At $t -7200 "commit fechado en el futuro"
$o = Fire $t "git commit -m x"
Assert ([string]::IsNullOrEmpty($o)) "un HEAD fechado 2 h en el FUTURO tampoco cuenta como commit de esta corrida"; Remove-Item -Recurse -Force $t

$t = New-Repo
Set-Content (Join-Path $t "big.txt") ((1..500 | ForEach-Object { "linea $_" }) -join "`n") -Encoding UTF8
git -C $t add -A; git -C $t commit -q -m "slice gigante sin declarar"
$o = Fire $t "git commit -m slice"
Assert ($o -match "additionalContext") "red de seguridad: delta sin revisar por encima del techo dispara aunque no haya trailer"; Remove-Item -Recurse -Force $t

# El borde de ABAJO del techo. Todos los fixtures que deben disparar miden 500/600 y todos los que
# no, 0 o 1: mutar `-le 400` a `-le 100` sobrevivia a la suite entera y solo lo cazaba un grep de
# literal en review-loop-incremental.tests.ps1, que no es conducta.
$t = New-Repo
Set-Content (Join-Path $t "medio.txt") ((1..200 | ForEach-Object { "linea $_" }) -join "`n") -Encoding UTF8
git -C $t add -A; git -C $t commit -q -m "200 lineas sin declarar cierre"
$o = Fire $t "git commit -m medio"
Assert ([string]::IsNullOrEmpty($o)) "el techo no dispara por debajo de las 400 lineas (el valor queda fijado por conducta)"; Remove-Item -Recurse -Force $t

# `git commit && git push` es un solo comando de Bash y prende los dos disparadores. La puerta del
# trailer no puede llevarse puesto al push, que dispara incondicionalmente desde antes de A2.
$t = New-Repo
git -C $t commit --allow-empty -q -m "sin declarar cierre"
$o = Fire $t "git add -A && git commit -m wip && git push"
Assert ($o -match "additionalContext") "commit sin trailer encadenado con push: dispara igual (el push es disparador propio)"; Remove-Item -Recurse -Force $t

# COSTO DECLARADO de haber borrado la atribucion por parseo (decision del 2026-08-14): un push
# corrido en OTRO repo desde una sesion abierta aca dispara igual. Es un falso positivo — un
# review-loop de mas — y se acepta a cambio de la clase de bug que se llevo por delante: tres turnos
# de review seguidos encontraron altas en ese parser (1 -> 3 -> 4), TODAS falsos negativos que
# descartaban cierres declarados en silencio. Este fixture existe para que reintroducir el bloque no
# pase inadvertido: si alguien lo vuelve a agregar, este assert se pone rojo y hay que discutirlo.
# Un repo nuevo por caso: comparten SHA y el dedupe haria pasar el segundo sin ejercitar nada.
$otro = New-Repo
$t = New-Repo; $o = Fire $t "cd '$otro' && git push"
Assert ($o -match "additionalContext") "costo aceptado: un push corrido en otro repo dispara aca (no se parsea el comando)"; Remove-Item -Recurse -Force $t
Remove-Item -Recurse -Force $otro
# El GEMELO del de arriba, y hace falta uno por forma: el bloque borrado probaba PRIMERO `git -C
# <ruta>` y solo despues caia al `cd`, asi que el fixture del `cd` no fija mas que la mitad del
# costo. Medido: reintroducir unicamente la rama `git -C` deja la suite entera en verde — o sea que
# el unico assert que declara "este bloque se borro" no protege la forma que el bloque probaba
# primero. Este es el que la cubre. (El otro fixture que menciona `-C`, mas abajo, usa `git -C '$t'`
# con $t = ESTE repo: resuelve al mismo toplevel y no discrimina entre haber parseado o no.)
$otro = New-Repo
$t = New-Repo; $o = Fire $t "git -C '$otro' push"
Assert ($o -match "additionalContext") "costo aceptado: un push escrito con git -C sobre otro repo tambien dispara aca"; Remove-Item -Recurse -Force $t
Remove-Item -Recurse -Force $otro
# Lo que SI sigue protegiendo a los commits es la frescura del HEAD, que es una señal observable y
# no depende de leer la linea de comando (fixture del commit viejo, mas arriba).
$t = New-Repo
New-Item -ItemType Directory -Path (Join-Path $t "sub") -Force | Out-Null
$o = Fire $t "cd sub && git push"
Assert ($o -match "additionalContext") "moverse a un subdirectorio del mismo repo sigue disparando"; Remove-Item -Recurse -Force $t

# `git diff` nunca muestra untracked, y el paso 5 del loop ORDENA escribir un test nuevo, que nace
# sin trackear: un slice hecho de archivos nuevos media 0 y se escapaba de la red.
$t = New-Repo
git -C $t commit --allow-empty -q -m "commit chico sin declarar"
Set-Content (Join-Path $t "nuevo.ps1") ((1..600 | ForEach-Object { "linea $_" }) -join "`n") -Encoding UTF8
$o = Fire $t "git commit -m chico"
Assert ($o -match "additionalContext") "la red de seguridad cuenta los archivos sin trackear"; Remove-Item -Recurse -Force $t

# El techo es de lineas de LOGICA: el CLAUDE.md excluye textualmente generados, vendored, lockfiles
# y snapshots. Contarlos hace que un slice que cumple la regla dispare igual en cada commit.
$t = New-Repo
Set-Content (Join-Path $t ".bootstrap-manifest.json") ((1..500 | ForEach-Object { "  `"linea $_`": 1," }) -join "`n") -Encoding UTF8
New-Item -ItemType Directory -Path (Join-Path $t "docs/vendor") -Force | Out-Null
Set-Content (Join-Path $t "docs/vendor/lib.js") ((1..500 | ForEach-Object { "linea $_" }) -join "`n") -Encoding UTF8
git -C $t add -A; git -C $t commit -q -m "regenerar manifest y vendorear"
$o = Fire $t "git commit -m generados"
Assert ([string]::IsNullOrEmpty($o)) "la red de seguridad no cuenta generados ni vendored (la regla del techo los excluye)"; Remove-Item -Recurse -Force $t

# La ruta que corre de verdad: todo repo bootstrapeado TRAE el marcador, asi que el caso sin
# marcador de arriba no existe en produccion. Con marcador puesto y mas de 400 lineas sin revisar,
# la red tiene que disparar igual (mutar la rama del marcador a algo que siempre mida 0 sobrevivia).
$t = New-Repo
New-Item -ItemType Directory -Path (Join-Path $t ".claude/scripts") -Force | Out-Null
Copy-Item (Join-Path $repo "skills/bootstrap-personal-project/assets/scaffold/.claude/scripts/review-marker.ps1") (Join-Path $t ".claude/scripts/review-marker.ps1")
git -C $t add -A; git -C $t commit -q -m "traer el marcador"
& pwsh -NoProfile -File (Join-Path $t ".claude/scripts/review-marker.ps1") -Action advance -RepoDir $t | Out-Null
Set-Content (Join-Path $t "grande.txt") ((1..500 | ForEach-Object { "linea $_" }) -join "`n") -Encoding UTF8
git -C $t add -A; git -C $t commit -q -m "500 lineas sin declarar cierre"
$r = (& pwsh -NoProfile -File (Join-Path $t ".claude/scripts/review-marker.ps1") -Action range -RepoDir $t)
Assert ((-not [string]::IsNullOrEmpty($r)) -and ($LASTEXITCODE -eq 0)) "guard: el marcador da un rango no vacio en este fixture"
$o = Fire $t "git commit -m grande"
Assert ($o -match "additionalContext") "red de seguridad con marcador presente: mas de 400 sin revisar dispara"; Remove-Item -Recurse -Force $t

# El marcador distingue tres cosas y el hook tiene que respetarlas: exit 0 CON ref es "revisá esto",
# exit 0 VACÍO es "no hay nada sin revisar" (no disparar), exit 2 es "no puedo determinar" (recién
# ahí vale medir el rango de la rama). Colapsar las dos últimas hace que el hook dispare justo
# después de que el loop cerró limpio, que es el gasto que este slice vino a eliminar.
$t = New-Repo
New-Item -ItemType Directory -Path (Join-Path $t ".claude/scripts") -Force | Out-Null
Copy-Item (Join-Path $repo "skills/bootstrap-personal-project/assets/scaffold/.claude/scripts/review-marker.ps1") (Join-Path $t ".claude/scripts/review-marker.ps1")
Set-Content (Join-Path $t "big.txt") ((1..500 | ForEach-Object { "linea $_" }) -join "`n") -Encoding UTF8
git -C $t add -A; git -C $t commit -q -m "slice grande ya revisado"
& pwsh -NoProfile -File (Join-Path $t ".claude/scripts/review-marker.ps1") -Action advance -RepoDir $t | Out-Null
git -C $t commit --allow-empty -q -m "retoque sin declarar cierre"
$r = (& pwsh -NoProfile -File (Join-Path $t ".claude/scripts/review-marker.ps1") -Action range -RepoDir $t)
Assert (([string]::IsNullOrEmpty($r)) -and ($LASTEXITCODE -eq 0)) "guard: el marcador da vacío+exit 0 (nada sin revisar) en este fixture"
$o = Fire $t "git commit -m retoque"
Assert ([string]::IsNullOrEmpty($o)) "marcador vacío con exit 0 = nada sin revisar: no dispara ni por la red de seguridad"; Remove-Item -Recurse -Force $t

# El techo se mide sobre el delta SIN REVISAR (marcador), no sobre el rango completo de la rama:
# una rama grande ya revisada + un commit chico sin trailer no debe disparar.
$t = New-Repo
New-Item -ItemType Directory -Path (Join-Path $t ".claude/scripts") -Force | Out-Null
Copy-Item (Join-Path $repo "skills/bootstrap-personal-project/assets/scaffold/.claude/scripts/review-marker.ps1") (Join-Path $t ".claude/scripts/review-marker.ps1")
Set-Content (Join-Path $t "big.txt") ((1..500 | ForEach-Object { "linea $_" }) -join "`n") -Encoding UTF8
git -C $t add -A; git -C $t commit -q -m "slice grande ya revisado"
& pwsh -NoProfile -File (Join-Path $t ".claude/scripts/review-marker.ps1") -Action advance -RepoDir $t | Out-Null
Set-Content (Join-Path $t "chico.txt") "una linea" -Encoding UTF8
git -C $t add -A; git -C $t commit -q -m "retoque chico sin declarar cierre"
$o = Fire $t "git commit -m retoque"
Assert ([string]::IsNullOrEmpty($o)) "el techo mira el delta sin revisar (marcador), no el rango completo de la rama"; Remove-Item -Recurse -Force $t

# Sin `pwsh` en el PATH el marcador no se puede consultar, y eso es "indeterminable": la red tiene
# que caer al rango de la rama y disparar igual, no quedarse muda.
# OJO con lo que este fixture NO prueba: borrar el centinela `$global:LASTEXITCODE = 99` lo
# SOBREVIVE (verificado por mutacion). Cuando el comando no existe, PowerShell deja $LASTEXITCODE
# en un valor distinto de 0 por su cuenta, asi que en ESTE escenario el centinela es redundante.
# Se deja porque protege contra cualquier otra falla de la llamada que no toque $LASTEXITCODE, pero
# no hay que leer este assert como cobertura del centinela. Declarado en docs/TESTING.md.
$t = New-Repo
New-Item -ItemType Directory -Path (Join-Path $t ".claude/scripts") -Force | Out-Null
Copy-Item (Join-Path $repo "skills/bootstrap-personal-project/assets/scaffold/.claude/scripts/review-marker.ps1") (Join-Path $t ".claude/scripts/review-marker.ps1")
Set-Content (Join-Path $t "grande.txt") ((1..500 | ForEach-Object { "linea $_" }) -join "`n") -Encoding UTF8
git -C $t add -A; git -C $t commit -q -m "500 lineas sin declarar cierre"
$pwshExe = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
$savedPath = $env:PATH
# PATH minimo con git y NADA mas: filtrar por nombre no alcanza, porque pwsh se resuelve por el
# alias de ejecucion de WindowsApps, cuya ruta no dice ni "pwsh" ni "powershell" (verificado: el
# filtro no quitaba ninguna entrada y el test pasaba sin ejercitar el centinela). Git tiene que
# quedar: sin git el hook sale mucho antes, por otro camino.
$env:PATH = Split-Path (Get-Command git).Source
Assert (-not (Get-Command pwsh -ErrorAction SilentlyContinue)) "guard: con el PATH recortado pwsh no se resuelve"
$evt = @{ tool_input = @{ command = "git commit -m grande" }; cwd = $t } | ConvertTo-Json -Compress
$o = ($evt | & $pwshExe -NoProfile -File $hook)
$env:PATH = $savedPath
Assert ($o -match "additionalContext") "sin pwsh en el PATH el marcador es indeterminable: la red cae al rango de la rama y dispara igual"
Remove-Item -Recurse -Force $t

# Exit 2 del marcador = "no puedo determinar el rango", que NO es "no hay nada sin revisar". En una
# rama huerfana no hay base comun, asi que el fallback `<base>...HEAD` que el hook usa falla con
# `fatal: no merge base`; con el error tragado eso se leia como 0 lineas y la red desaparecia justo
# en el caso donde el marcador ya habia dicho que no sabe.
$t = New-Repo
# El marcador se copia DESPUES del `--orphan` + `reset --hard`: copiarlo antes es setup muerto,
# porque el reset se lo lleva puesto y el hook nunca veria ese archivo.
git -C $t checkout -q --orphan huerfana
git -C $t reset -q --hard
New-Item -ItemType Directory -Path (Join-Path $t ".claude/scripts") -Force | Out-Null
Copy-Item (Join-Path $repo "skills/bootstrap-personal-project/assets/scaffold/.claude/scripts/review-marker.ps1") (Join-Path $t ".claude/scripts/review-marker.ps1")
Set-Content (Join-Path $t "grande.txt") ((1..500 | ForEach-Object { "linea $_" }) -join "`n") -Encoding UTF8
git -C $t add -A; git -C $t commit -q -m "500 lineas en rama huerfana, sin declarar cierre"
& pwsh -NoProfile -File (Join-Path $t ".claude/scripts/review-marker.ps1") -Action range -RepoDir $t | Out-Null
Assert ($LASTEXITCODE -eq 2) "guard: el marcador da exit 2 (indeterminable) en este fixture"
$o = Fire $t "git commit -m huerfano"
Assert ($o -match "additionalContext") "con el rango indeterminable y el conteo imposible, la red dispara igual"
Remove-Item -Recurse -Force $t

$t = New-Repo
Close-Slice $t "slice"
Fire $t "git commit -m slice" | Out-Null
$o = Fire $t "git commit -m slice"
Assert ([string]::IsNullOrEmpty($o)) "dedupe: segundo disparo sobre el mismo SHA no emite"
Close-Slice $t "slice2"
$o2 = Fire $t "git commit -m slice2"
Assert ($o2 -match "additionalContext") "dedupe: un commit nuevo vuelve a disparar"
Remove-Item -Recurse -Force $t

# El hook reescribe el MISMO review-loop-state.json que usa el marcador. Bajo Windows PowerShell 5.1
# Get-Content/Set-Content lo leen y lo escriben con la code page ANSI, y la huella de untracked
# acentuada del marcador vuelve como mojibake: esa rama no puede volver a cerrar nunca.
$t = New-Repo; Close-Slice $t "slice"
$sp = Join-Path $t ".git/review-loop-state.json"
[IO.File]::WriteAllText($sp, '{"marker:feat/x":"cafe","untracked:feat/x":["ñandú.txt|abc123"]}', (New-Object Text.UTF8Encoding($false)))
$evt = @{ tool_input = @{ command = "git commit -m slice" }; cwd = $t } | ConvertTo-Json -Compress
$evt | & powershell.exe -NoProfile -File $hook | Out-Null
$after = [IO.File]::ReadAllText($sp)
# Control positivo: sin esto el assert de abajo pasa igual cuando el hook NO escribe nada (sale
# antes por cualquier motivo y el literal sigue en el archivo intacto). Verificado: con el gate del
# trailer roto, el assert de la huella pasaba sin que el hook tocara el archivo.
Assert ((($after | ConvertFrom-Json).'feat/x') -eq (git -C $t rev-parse HEAD)) "guard: el hook realmente reescribió el estado bajo PowerShell 5.1"
Assert ($after -match ([regex]::Escape("ñandú.txt"))) "el hook no corrompe la huella acentuada del marcador al reescribir el estado (PowerShell 5.1)"
Remove-Item -Recurse -Force $t

# Estado ilegible: el hook comparte el archivo con el marcador. Reescribirlo con solo su clave de
# dedupe borra `marker:*` y `untracked:*` de TODAS las ramas, en silencio. El original tiene que
# quedar a mano para recuperarlo.
$t = New-Repo; Close-Slice $t "slice"
$sp = Join-Path $t ".git/review-loop-state.json"
[IO.File]::WriteAllText($sp, '{"marker:feat/x":"abc123","untracked:otra":[', (New-Object Text.UTF8Encoding($false)))
$o = Fire $t "git commit -m slice"
# Control positivo: los dos asserts de abajo miran solo el efecto lateral, asi que un `exit 0`
# agregado despues del Move-Item los deja verdes mientras el hook deja de disparar en silencio —
# y el estado ilegible es justo donde eso puede pasar sin que nadie lo note.
Assert ($o -match "additionalContext") "estado ilegible: el hook se recupera y dispara igual"
Assert (Test-Path -LiteralPath "$sp.bad") "estado ilegible: el hook lo aparta como .bad en vez de pisarlo"
# La lectura va afuera del Assert (no adentro de un `if`): si el archivo no está, el assert igual
# se evalúa y falla, en vez de abortar la corrida y llevarse los tests de abajo.
$bad = if (Test-Path -LiteralPath "$sp.bad") { [IO.File]::ReadAllText("$sp.bad") } else { '' }
Assert ($bad -match 'marker:feat/x') "estado ilegible: el contenido original queda recuperable"
Remove-Item -Recurse -Force $t

# Un repo bajo una ruta con corchetes: `Test-Path` sin -LiteralPath los toma como comodín y da
# False, asi que el estado se lee como inexistente y el dedupe deja de existir en CADA corrida.
$t = Join-Path ([IO.Path]::GetTempPath()) ("rlt-[test]-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $t | Out-Null
git -C $t init -q -b master; git -C $t config user.email a@b.c; git -C $t config user.name a
git -C $t config commit.gpgsign false
git -C $t commit --allow-empty -q -m base
git -C $t checkout -q -b feat/x
Close-Slice $t "slice"
$o = Fire $t "git commit -m slice"
Assert ($o -match "additionalContext") "guard: en una ruta con corchetes el primer disparo ocurre"
$o2 = Fire $t "git commit -m slice"
Assert ([string]::IsNullOrEmpty($o2)) "el dedupe sigue funcionando en una ruta con corchetes"
Remove-Item -Recurse -Force -LiteralPath $t

# `$isPush` / `$isPr` se evaluaban sobre el comando ENTERO, y el comando incluye el texto del `-m`.
# Un commit cuyo mensaje menciona `git push` prendia la bandera y salteaba la puerta del trailer
# COMPLETA: sin gate, sin ventana de frescura y sin techo. En este repo los mensajes hablan de
# `git push` todo el tiempo, asi que era un commit perfectamente normal.
$t = New-Repo
git -C $t commit --allow-empty -q -m "sin declarar cierre"
$o = Fire $t 'git commit -m "docs: explicar que el hook dispara en git push"'
Assert ([string]::IsNullOrEmpty($o)) "un commit cuyo MENSAJE menciona 'git push' no saltea la puerta del trailer"
Remove-Item -Recurse -Force $t

# Variante con comillas ESCAPADAS: un blanqueo ingenuo (`"[^"]*"`) corta en la comilla escapada y
# deja el texto de adentro expuesto, asi que la bandera del push se prende igual.
$t = New-Repo
git -C $t commit --allow-empty -q -m "sin declarar cierre"
$o = Fire $t 'git commit -m "fix: manejo de comillas para detectar \"git push\""'
Assert ([string]::IsNullOrEmpty($o)) "comillas ESCAPADAS en el mensaje tampoco saltean la puerta del trailer"
Remove-Item -Recurse -Force $t

# Y el simetrico, que falla en la direccion insegura: dos apostrofes sueltos dentro de comillas
# dobles hacen que `'[^']*'` empareje de uno al otro y se coma el `git push` REAL del medio.
$t = New-Repo
$o = Fire $t 'git commit -m "don''t" && git push && echo "it''s ok"'
Assert ($o -match "additionalContext") "un apostrofe en el mensaje no se traga el git push que viene despues"
Remove-Item -Recurse -Force $t

# A2b fix 2: sustitucion de comando `$(...)`. Una comilla doble dentro de comillas simples dentro de
# `$(...)` deja el total de dobles IMPAR, Hide-Literals se desincroniza y se traga el resto de la
# linea, PERDIENDO el `git push` REAL que viene despues. Con el fix, un comando que contiene `$(` o
# backtick recalcula las banderas sobre el comando crudo y las combina con OR: el falso negativo se
# vuelve falso positivo (la direccion segura). Mutante: sacar el bloque del OR deja este assert rojo.
$t = New-Repo
$o = Fire $t 'git commit -m "$(sed ''s/"/x/'' f)" && git push'
Assert ($o -match "additionalContext") "un `$(...)` con comilla desbalanceada no se traga el git push que viene despues"
Remove-Item -Recurse -Force $t

# La direccion segura tambien para el cierre declarado perdido: `echo "$(...)"` antes del commit no
# debe volver mudo al hook. Aca el disparador es el commit CON trailer.
$t = New-Repo; Close-Slice $t "cierre con substitucion"
$o = Fire $t 'echo "$(sed ''s/"/x/'' f)" && git commit -m cierre'
Assert ($o -match "additionalContext") "un `echo `$(...)` antes de un commit declarado no impide el disparo"
Remove-Item -Recurse -Force $t

# COSTO ACEPTADO del OR sobre el crudo (F7): un commit SIN trailer cuyo MENSAJE menciona "git push"
# DENTRO de un `$(...)` ahora prende $isPush sobre el crudo y saltea la puerta del trailer, disparando.
# Es un falso positivo (la direccion segura: un review-loop de mas), pero se FIJA para que no cambie
# de conducta en silencio. Sin `$(`, la misma frase entrecomillada NO dispara (ver el fixture de
# arriba, "un commit cuyo MENSAJE menciona 'git push'..."): ese contraste es justo lo que este fija.
$t = New-Repo
git -C $t commit --allow-empty -q -m "sin declarar cierre"
$o = Fire $t 'git commit -m "recorda: $(echo git push) al terminar"'
Assert ($o -match "additionalContext") "costo aceptado: un `$(...)` en el mensaje que dice git push dispara (falso positivo, direccion segura)"
Remove-Item -Recurse -Force $t

# El evento trae el cwd de la SESION, que puede ser un subdirectorio (monorepo: la sesion abierta en
# `apps/web` con el git root arriba). El pathspec `.` del techo y `ls-files` son relativos a ese cwd,
# asi que la red de seguridad medía solo ese subarbol y desaparecia en silencio.
$t = New-Repo
New-Item -ItemType Directory -Path (Join-Path $t "app") -Force | Out-Null
Set-Content (Join-Path $t "raiz.txt") ((1..600 | ForEach-Object { "linea $_" }) -join "`n") -Encoding UTF8
git -C $t add -A; git -C $t commit -q -m "600 lineas en la raiz, sin declarar cierre"
$o = Fire $t "git commit -m chico" (Join-Path $t "app")
Assert ($o -match "additionalContext") "red de seguridad: cuenta el repo entero aunque la sesion este en un subdirectorio"
Remove-Item -Recurse -Force $t

$t = New-Repo
New-Item -ItemType Directory -Path (Join-Path $t "app") -Force | Out-Null
git -C $t commit --allow-empty -q -m "commit chico sin declarar"
Set-Content (Join-Path $t "nuevo.ps1") ((1..600 | ForEach-Object { "linea $_" }) -join "`n") -Encoding UTF8
$o = Fire $t "git commit -m chico" (Join-Path $t "app")
Assert ($o -match "additionalContext") "red de seguridad: cuenta untracked de la raiz con la sesion en un subdirectorio"
Remove-Item -Recurse -Force $t

# Las exclusiones del techo se aplicaban SOLO a la mitad trackeada. Un `npm install` reciente dejaba
# el hook disparando en cada commit sin trailer, que es el gasto que este slice vino a eliminar.
$t = New-Repo
git -C $t commit --allow-empty -q -m "commit chico sin declarar"
Set-Content (Join-Path $t "package-lock.json") ((1..600 | ForEach-Object { "  `"linea $_`": 1," }) -join "`n") -Encoding UTF8
$o = Fire $t "git commit -m chico"
Assert ([string]::IsNullOrEmpty($o)) "la red de seguridad tampoco cuenta un lockfile SIN TRACKEAR"
Remove-Item -Recurse -Force $t

# Lo que cuenta es untracked SIN REVISAR, no "cualquier untracked": el marcador guarda su huella en
# `untracked:<rama>` justo para eso. Contarlos en absoluto hacia que un test nuevo ya revisado
# disparara la red en cada commit posterior, para siempre.
$t = New-Repo
New-Item -ItemType Directory -Path (Join-Path $t ".claude/scripts") -Force | Out-Null
Copy-Item (Join-Path $repo "skills/bootstrap-personal-project/assets/scaffold/.claude/scripts/review-marker.ps1") (Join-Path $t ".claude/scripts/review-marker.ps1")
git -C $t add -A; git -C $t commit -q -m "traer el marcador"
Set-Content (Join-Path $t "test-nuevo.ps1") ((1..600 | ForEach-Object { "linea $_" }) -join "`n") -Encoding UTF8
& pwsh -NoProfile -File (Join-Path $t ".claude/scripts/review-marker.ps1") -Action advance -RepoDir $t | Out-Null
# Con contenido real, no `--allow-empty`: un commit vacio deja el rango vacio y el hook sale por el
# guard de "nada sin revisar" sin llegar nunca al conteo (el assert pasaba sin ejercitar nada).
Set-Content (Join-Path $t "retoque.txt") "una linea" -Encoding UTF8
# `add` del archivo puntual, no `add -A`: con -A el untracked que el marcador cubrio se trackea y
# pasa a contar por el diff, que es otro camino y deja el test verificando otra cosa.
git -C $t add retoque.txt; git -C $t commit -q -m "retoque sin declarar cierre"
$r = (& pwsh -NoProfile -File (Join-Path $t ".claude/scripts/review-marker.ps1") -Action range -RepoDir $t)
Assert ((-not [string]::IsNullOrEmpty($r)) -and ($LASTEXITCODE -eq 0)) "guard: hay delta sin revisar, el hook llega al conteo del techo"
$o = Fire $t "git commit -m retoque"
Assert ([string]::IsNullOrEmpty($o)) "un untracked que el marcador ya cubrio no vuelve a contar para el techo"
Remove-Item -Recurse -Force $t

# ...pero si ese mismo archivo CRECIO despues del marcador, si es delta sin revisar. El marcador
# guarda `path|sha256` y compara la entrada entera justamente por esto (review-marker.ps1): si el
# hook compara solo el path, un archivo fichado con 1 linea y reescrito a 600 se salta la red
# para siempre, que es exactamente el caso para el que la red existe.
$t = New-Repo
New-Item -ItemType Directory -Path (Join-Path $t ".claude/scripts") -Force | Out-Null
Copy-Item (Join-Path $repo "skills/bootstrap-personal-project/assets/scaffold/.claude/scripts/review-marker.ps1") (Join-Path $t ".claude/scripts/review-marker.ps1")
git -C $t add -A; git -C $t commit -q -m "traer el marcador"
Set-Content (Join-Path $t "test-nuevo.ps1") "una linea" -Encoding UTF8
& pwsh -NoProfile -File (Join-Path $t ".claude/scripts/review-marker.ps1") -Action advance -RepoDir $t | Out-Null
Set-Content (Join-Path $t "test-nuevo.ps1") ((1..600 | ForEach-Object { "linea $_" }) -join "`n") -Encoding UTF8
Set-Content (Join-Path $t "retoque.txt") "una linea" -Encoding UTF8
git -C $t add retoque.txt; git -C $t commit -q -m "retoque sin declarar cierre"
$o = Fire $t "git commit -m retoque"
Assert ($o -match "additionalContext") "un untracked que CRECIO despues del marcador si cuenta para el techo"
Remove-Item -Recurse -Force $t

# Un untracked con nombre acentuado tiene que contar igual que uno ASCII: git emite UTF-8 y
# PowerShell decodifica la salida del hijo con la code page de consola, asi que sin forzar el
# encoding el path vuelve como mojibake, `Test-Path` da False y el archivo suma CERO. El marcador
# ya hace este mismo ajuste alrededor de su `ls-files`; el hook no lo tenia.
$t = New-Repo
git -C $t commit --allow-empty -q -m "commit chico sin declarar"
Set-Content (Join-Path $t "revisión.ps1") ((1..600 | ForEach-Object { "linea $_" }) -join "`n") -Encoding UTF8
# La code page se fuerza a OEM: en una consola que ya esta en UTF-8 el bug no se manifiesta y el
# assert pasa sin ejercitar nada (verificado: en esta maquina pasaba en verde sin el fix). El hook
# corre como proceso hijo y hereda la code page de la consola.
# El `catch {}` del GetEncoding se traga la falla, asi que sin el control positivo de abajo el caso
# pasaria en verde con la code page intacta, sin ejercitar nada.
$prevCp = [Console]::OutputEncoding
$cpSet = $false
try {
  try { [Console]::OutputEncoding = [Text.Encoding]::GetEncoding(850); $cpSet = ([Console]::OutputEncoding.CodePage -eq 850) } catch { }
  $o = Fire $t "git commit -m chico"
} finally { try { [Console]::OutputEncoding = $prevCp } catch { } }
Assert $cpSet "guard: la code page se forzo a 850 de verdad (si no, el caso no ejercita el bug)"
Assert ($o -match "additionalContext") "la red de seguridad cuenta un untracked con nombre acentuado"
Remove-Item -Recurse -Force $t

# El caso de arriba ejercita el nombre de ARCHIVO acentuado; este ejercita la RUTA DEL REPO. El evento
# llega por STDIN, que se decodifica con [Console]::InputEncoding — y un hook corrido como proceso
# hijo con la consola en code page OEM (lo normal en Windows) NO hereda UTF-8 en la entrada. Sin
# forzar InputEncoding, el `cwd` con `ñ` vuelve mojibake, `Set-Location` falla en silencio y el hook
# opera sobre el repo AMBIENTE y dispara mal. Este caso invoca el hook como `pwsh -File` (igual que
# Claude Code), alimenta el evento como bytes UTF-8 por redireccion y fuerza la consola a 850 con
# `chcp`, que es el escenario real de produccion: bytes UTF-8 en stdin, consola OEM.
# CONTROL POSITIVO: el repo temporal trae un cierre DECLARADO fresco, asi que si el hook resuelve el
# cwd no-ASCII, dispara nombrando SU rama (feat/x). Con el bug, mojibakea, cae al ambiente y nombra
# la rama de ESTE repo (o el hardening lo saca con exit 0): en cualquier caso no aparece 'feat/x'.
function Fire-File($repo, $cmd) {
  $enye2 = [string][char]0x00F1
  $rt = Join-Path ([IO.Path]::GetTempPath()) ("rlt-test-" + $enye2 + "andu-" + [guid]::NewGuid().ToString('N'))
  Rename-Item -LiteralPath $repo -NewName (Split-Path $rt -Leaf) -ErrorAction SilentlyContinue
  if (-not (Test-Path -LiteralPath $rt)) { $rt = $repo }   # si el rename fallo, seguimos con el original
  $evt = @{ tool_input = @{ command = $cmd }; cwd = $rt } | ConvertTo-Json -Compress
  # El padre escribe bytes UTF-8 (como Claude Code manda el JSON del evento); el hijo arranca con la
  # consola de ENTRADA en OEM (850), como una maquina Windows tipica. El hook debe forzar
  # InputEncoding a UTF-8 para leer bien el cwd acentuado; sin eso, mojibakea y opera sobre el
  # ambiente. Se restaura el OutputEncoding del runner al salir.
  $prev = [Console]::OutputEncoding
  try {
    [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
    $out = ($evt | & pwsh -NoProfile -Command "[Console]::InputEncoding = [Text.Encoding]::GetEncoding(850); & '$hook'") | Out-String
  } finally { [Console]::OutputEncoding = $prev }
  return @{ out = $out; path = $rt }
}
$t = New-Repo   # feat/x con un commit 'slice'
Close-Slice $t "cierre bajo ruta acentuada"   # HEAD fresco con trailer Slice-Close
$r = Fire-File $t "git commit -m cierre"
Assert (($r.out -match "additionalContext") -and ($r.out -match "'feat/x'")) "bajo ruta de repo no-ASCII y consola OEM, el hook resuelve el cwd de stdin y dispara sobre SU repo (fuerza InputEncoding)"
Remove-Item -Recurse -Force -LiteralPath $r.path

# HARDENING: un cwd que NO resuelve nunca debe hacer que el hook opere sobre el repo donde fue lanzado.
# Sin el guard, `Set-Location` falla en silencio (SilentlyContinue) y el hook corre sobre el cwd de
# lanzamiento y dispara un cierre falso. El caso es SELF-CONTAINED: se lanza el hook con el cwd del
# proceso en un repo temporal FRESCO con cierre declarado (que dispararia sin el guard, HEAD reciente
# + trailer), y el evento trae un cwd inexistente (un subdir del temporal que no existe). Sin el guard
# -> opera sobre el repo de lanzamiento -> dispara (RED); con el guard -> exit 0 -> silencio. Asi el
# caso NO depende de la frescura ni del trailer de ESTE repo, que a los 30 min ya no dispararia y
# volveria el test vacio (verificado: mide 122 min en una corrida tipica).
$t = New-Repo; Close-Slice $t "cierre para el hardening"   # HEAD fresco con trailer en el repo de lanzamiento
$evtBad = @{ tool_input = @{ command = "git commit -m x" }; cwd = (Join-Path $t "no-existe-subdir-xyz") } | ConvertTo-Json -Compress
$ob = ($evtBad | & pwsh -NoProfile -Command "Set-Location -LiteralPath '$t'; & '$hook'") | Out-String
Assert ([string]::IsNullOrWhiteSpace($ob)) "un cwd de evento que no resuelve hace exit 0, no dispara sobre el repo de lanzamiento (self-contained)"
Remove-Item -Recurse -Force $t

# Un binario sin trackear no es delta de logica (del lado trackeado `--numstat` ya reporta `-`).
# Sin este fixture, borrar el bloque entero de deteccion de binarios sobrevive la suite.
$t = New-Repo
git -C $t commit --allow-empty -q -m "commit chico sin declarar"
# Con saltos de linea: un blob de ceros sin ellos cuenta como UNA linea y el caso pasa con o sin
# la deteccion de binarios, sin distinguir nada. Asi, leido como texto son 500 lineas — o sea que
# el assert de abajo solo puede pasar si el archivo se descarta por tener un byte nulo.
$txt = ((1..500 | ForEach-Object { "linea $_" }) -join "`n")
$bytes = [Text.Encoding]::UTF8.GetBytes($txt)
$bytes[3] = 0
[IO.File]::WriteAllBytes((Join-Path $t "captura.png"), $bytes)
$o = Fire $t "git commit -m chico"
Assert ([string]::IsNullOrEmpty($o)) "un binario sin trackear no cuenta para el techo"
Remove-Item -Recurse -Force $t

# Y el TAMAÑO de esa ventana, que el fixture de arriba no fija: pone el NUL en el offset 3, asi que
# cualquier ventana lo encuentra y revertir 8000 -> 4096 sobrevive la suite entera. El valor es 8000
# porque es lo que git escanea para decidir binario; con 4096 un archivo cuyo primer NUL cae mas
# alla contaba como TEXTO, sumaba sus lineas al techo y disparaba el loop en cada commit — mientras
# el comentario del hook afirmaba que las dos mitades (trackeada y untracked) coincidian con git.
# Las 420 lineas son deliberadas: leido como texto pasa el techo, asi que este assert solo puede
# pasar si el archivo se descarto por binario.
$t = New-Repo
git -C $t commit --allow-empty -q -m "commit chico sin declarar"
$txt = ((1..420 | ForEach-Object { "linea-{0:d6}" -f $_ }) -join "`n") + "`n"   # 5460 B antes del NUL
$bytes = [byte[]]([Text.Encoding]::ASCII.GetBytes($txt) + [byte]0 + [Text.Encoding]::ASCII.GetBytes("cola"))
[IO.File]::WriteAllBytes((Join-Path $t "captura.bin"), $bytes)
$o = Fire $t "git commit -m chico"
Assert ([string]::IsNullOrEmpty($o)) "un untracked con el primer NUL pasado los 4096 B tambien se detecta binario (la ventana es de 8000, como git)"
Remove-Item -Recurse -Force $t

# El push escrito con `git -C <ruta>`: `\bgit\s+push\b` no lo matcheaba, asi que un push legitimo
# nunca cerraba el loop. El plegado de opciones globales ($folded) es lo que lo arregla, y sigue en
# pie despues de borrar la atribucion — es lo unico que quedo de leer `-C`.
$t = New-Repo; $o = Fire $t "git -C '$t' push"
Assert ($o -match "additionalContext") "un push escrito con git -C dispara (el plegado de opciones globales)"
Remove-Item -Recurse -Force $t

# El apostrofe escrito a la manera de bash: `'\''` cierra el literal, mete una comilla escapada y
# vuelve a abrir. Recorriendo los literales sin mirar el escape de AFUERA, la comilla suelta se toma
# por apertura, el literal siguiente se lee corrido y el resto del mensaje queda EXPUESTO: `git push`
# aparece en el comando normalizado, prende $isPush y se saltea la puerta del trailer entera —
# sin gate, sin ventana de frescura y sin techo.
$t = New-Repo
git -C $t commit --allow-empty -q -m "sin declarar cierre"
$o = Fire $t "git commit -m 'fix: it'\''s ready to git push now'"
Assert ([string]::IsNullOrEmpty($o)) "un apostrofe escrito a la bash ('\'') no saltea la puerta del trailer"
Remove-Item -Recurse -Force $t

# `--base` se leia del comando CRUDO, que es justo lo que el paso 2 prohibe. Entrecomillado no
# matcheaba (`[^\s'\"]+` corta en la comilla) y el hook caia al fallback: el rango sugerido apuntaba
# a otra rama sin que nada lo dijera.
$t = New-Repo
$o = Fire $t 'gh pr create --base "develop" --title wip'
Assert ($o -match "base 'develop'") "un --base ENTRECOMILLADO se lee igual que uno pelado"
Remove-Item -Recurse -Force $t

# Y el simetrico: un `--base` citado dentro de otro flag ganaba por ser el PRIMER match, asi que el
# mensaje inyectado mandaba a un rango contra una rama que no existe.
$t = New-Repo
$o = Fire $t 'gh pr create --title "no confundir con --base inexistente" --base develop'
Assert ($o -match "base 'develop'") "un --base citado dentro de otro flag no le gana al --base real"
Remove-Item -Recurse -Force $t

# La cuarentena del estado ilegible: si el `Move-Item` falla, el hook NO puede seguir hasta el paso 7
# y reescribir el archivo, porque eso destruye exactamente lo que la cuarentena existe para preservar
# (`marker:*` y `untracked:*` de todas las ramas). Pero tampoco puede callarse: perder un cierre
# declarado es el lado peligroso. Tiene que saltear la ESCRITURA y disparar igual.
# El fallo se fuerza bloqueando el destino: con el archivo `.bad` abierto en FileShare.None, el
# Move-Item no puede reemplazarlo.
$t = New-Repo; Close-Slice $t "slice"
$sp = Join-Path $t ".git/review-loop-state.json"
[IO.File]::WriteAllText($sp, '{"marker:feat/x":"abc123","untracked:otra":[', (New-Object Text.UTF8Encoding($false)))
$lock = [IO.File]::Open("$sp.bad", [IO.FileMode]::Create, [IO.FileAccess]::Write, [IO.FileShare]::None)
try { $o = Fire $t "git commit -m slice" } finally { $lock.Close(); $lock.Dispose() }
Assert ($o -match "additionalContext") "con la cuarentena bloqueada el hook dispara igual (perder el cierre es el lado peligroso)"
$still = [IO.File]::ReadAllText($sp)
Assert ($still -match 'marker:feat/x') "con la cuarentena bloqueada el hook NO pisa el estado original"
Remove-Item -Recurse -Force $t

# --- Merge de settings (proyecto con settings.json propio, p. ej. enabledPlugins) ---
$t = Join-Path ([IO.Path]::GetTempPath()) ("rlt-ms-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $t | Out-Null
$sp = Join-Path $t "settings.json"
'{ "enabledPlugins": { "domo-skills@martin-local": true } }' | Set-Content $sp -Encoding UTF8
& pwsh -NoProfile -File $ms -ProjectSettings $sp -CanonicalSettings $canon | Out-Null
$txt = Get-Content $sp -Raw
Assert (($txt -match "enabledPlugins") -and ($txt -match "review-loop-trigger")) "merge preserva config propia y agrega review-loop-trigger"
Assert ($txt -match "alignment-gate") "merge agrega tambien el hook alignment-gate (PreToolUse)"
& pwsh -NoProfile -File $ms -ProjectSettings $sp -CanonicalSettings $canon | Out-Null
$txt2 = Get-Content $sp -Raw
Assert ((([regex]::Matches($txt2, "review-loop-trigger")).Count -eq 1) -and (([regex]::Matches($txt2, "alignment-gate")).Count -eq 1)) "merge es idempotente (no duplica ningun hook)"
Remove-Item -Recurse -Force $t

if ($script:failures -gt 0) { Write-Host "$($script:failures) test(s) FALLARON"; exit 1 } else { Write-Host "TODOS LOS TESTS PASARON"; exit 0 }
