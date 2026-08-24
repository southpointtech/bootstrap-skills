# tests/review-marker.tests.ps1 — runner sin Pester. Correr: pwsh -NoProfile -File tests/review-marker.tests.ps1
# Fixtures determinísticos (repos git temporales) para el marcador de revisión.
$ErrorActionPreference = "Stop"
$repo   = Split-Path $PSScriptRoot -Parent
$marker = Join-Path $repo "skills/bootstrap-personal-project/assets/scaffold/.claude/scripts/review-marker.ps1"
$script:failures = 0

function Assert($cond, $msg) {
  if ($cond) { Write-Host "ok:   $msg" } else { Write-Host "FAIL: $msg"; $script:failures++ }
}
# Los fixtures heredan el gitconfig global de la máquina. Tres opciones lo rompen: `commit.gpgsign`
# hace fallar todo commit sin llave, `core.hooksPath` corre hooks ajenos, y `core.excludesFile`
# altera `--exclude-standard`, que es justo lo que ejercitan los casos de untracked.
function Init-Repo([string]$t, [string]$branch) {
  git -C $t init -q -b $branch
  git -C $t config user.email a@b.c
  git -C $t config user.name a
  git -C $t config commit.gpgsign false
  git -C $t config core.hooksPath ""
  git -C $t config core.excludesFile ""
}
function New-Repo {
  $t = Join-Path ([IO.Path]::GetTempPath()) ("rm-test-" + [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $t | Out-Null
  Init-Repo $t "master"
  "base" | Set-Content (Join-Path $t "file.txt")
  git -C $t add -A; git -C $t commit -q -m base
  git -C $t checkout -q -b feat/x
  return $t
}
# El script tiene que existir: si no, `pwsh -File` imprime su usage a STDOUT y todo assert de
# "salida vacía" pasaría en verde sin ejercitar nada.
if (-not (Test-Path -LiteralPath $marker)) {
  Write-Host "FAIL: no existe el script del marcador en $marker"; exit 1
}
# Guarda el exit code en $script:lastExit: el contrato distingue vacío+0 ("no hay delta") de
# vacío+2 ("no puedo determinar el rango"), y sin el código las dos serían el mismo assert.
function Marker($dir, $action) {
  $out = & pwsh -NoProfile -File $marker -Action $action -RepoDir $dir
  $script:lastExit = $LASTEXITCODE
  if ($null -eq $out) { return "" }
  return (($out -join "`n")).Trim()
}
function New-RepoOn([string]$branch) {
  $t = Join-Path ([IO.Path]::GetTempPath()) ("rm-test-" + [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $t | Out-Null
  Init-Repo $t $branch
  "base" | Set-Content (Join-Path $t "file.txt")
  git -C $t add -A; git -C $t commit -q -m base
  return $t
}

# --- Tracer bullet: advance fija un punto de corte resoluble y get lo devuelve ---
$t = New-Repo
$adv = Marker $t advance
Assert ($adv -and ((git -C $t cat-file -t $adv 2>$null) -eq "commit")) "advance devuelve un objeto git resoluble"
Assert (($adv -ne "") -and ((Marker $t get) -eq $adv)) "get devuelve el marcador que fijó advance"
Remove-Item -Recurse -Force $t

# --- El árbol sucio entra en el punto de corte ---
# Tras avanzar con cambios sin commitear, no queda delta entre el marcador y el árbol actual:
# lo sucio quedó del lado ya revisado. Con HEAD como marcador, ese diff NO estaría vacío.
$t = New-Repo
"sucio" | Set-Content (Join-Path $t "file.txt")
$adv = Marker $t advance
git -C $t diff --quiet $adv 2>$null
Assert ($LASTEXITCODE -eq 0) "el marcador con árbol sucio incluye los cambios sin commitear"
Remove-Item -Recurse -Force $t

# --- advance es no-invasivo: no commitea, no mueve HEAD, no toca el árbol ---
$t = New-Repo
"sucio" | Set-Content (Join-Path $t "file.txt")
$countBefore  = (git -C $t rev-list --count HEAD)
$headBefore   = (git -C $t rev-parse HEAD)
$statusBefore = ((git -C $t status --porcelain) -join "`n")
Marker $t advance | Out-Null
Assert ((git -C $t rev-list --count HEAD) -eq $countBefore) "advance no crea un commit"
Assert ((git -C $t rev-parse HEAD) -eq $headBefore) "advance no mueve HEAD"
Assert (((git -C $t status --porcelain) -join "`n") -eq $statusBefore) "advance no toca el árbol de trabajo"
Remove-Item -Recurse -Force $t

# --- Sin marcador previo, el rango arranca en la base del slice ---
# `range` emite el marcador PELADO: el contrato es `git diff <lo que emite range>`, no `<x>..HEAD`,
# porque la forma con ..HEAD solo cubre commits y dejaría afuera lo no commiteado.
$t = New-Repo
"slice" | Set-Content (Join-Path $t "file.txt")
git -C $t add -A; git -C $t commit -q -m slice1
$base = (git -C $t merge-base master HEAD)
Assert ((Marker $t range) -eq $base) "sin marcador previo, el rango arranca en la base del slice"
Remove-Item -Recurse -Force $t

# --- Tras avanzar, el rango trae lo nuevo y no repite lo ya revisado ---
$t = New-Repo
"revisado" | Set-Content (Join-Path $t "a.txt")
git -C $t add -A; git -C $t commit -q -m revisado
Marker $t advance | Out-Null
"nuevo" | Set-Content (Join-Path $t "b.txt")
git -C $t add -A; git -C $t commit -q -m nuevo
$names = ((git -C $t diff --name-only (Marker $t range)) -join "`n")
Assert ($names -match "b\.txt") "el rango incluye el delta sin revisar"
Assert ($names -notmatch "a\.txt") "el rango no repite lo ya revisado"
Remove-Item -Recurse -Force $t

# --- Con el árbol sin cambios: advance idempotente y rango vacío ---
# El rango vacío es la señal de que el loop cierra sin corrida de review, en vez de inventarse un rango.
$t = New-Repo
"slice" | Set-Content (Join-Path $t "file.txt")
git -C $t add -A; git -C $t commit -q -m slice1
$a1 = Marker $t advance
$a2 = Marker $t advance
Assert (($a1 -ne "") -and ($a1 -eq $a2)) "con árbol limpio, advance es idempotente"
Assert ((Marker $t range) -eq "") "sin delta sin revisar, el rango queda vacío"
Remove-Item -Recurse -Force $t

# --- Fuera de un repo git: vacío y sin romper, para los tres verbos ---
# Exit 2, no 0: "no puedo determinar el rango" es distinto de "no hay nada nuevo que revisar".
# Con 0 el loop cerraría reportando limpio un slice que nadie miró.
$t = Join-Path ([IO.Path]::GetTempPath()) ("rm-nogit-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $t | Out-Null
foreach ($a in @("get", "range", "advance")) {
  $o = Marker $t $a
  Assert ($o -eq "") "fuera de un repo git, '$a' no imprime nada"
  Assert ($script:lastExit -eq 2) "fuera de un repo git, '$a' señaliza no-aplicable con exit 2"
}
Remove-Item -Recurse -Force $t

# --- Detached HEAD: vacío y no-aplicable, igual que hace el hook del disparo ---
# El árbol sucio es a propósito: con el árbol limpio el rango saldría vacío con o sin el guard,
# y el test pasaría sin ejercitarlo.
$t = New-Repo
git -C $t checkout -q --detach
"sucio" | Set-Content (Join-Path $t "file.txt")
foreach ($a in @("get", "range", "advance")) {
  $o = Marker $t $a
  Assert ($o -eq "") "con HEAD detached, '$a' no imprime nada"
  Assert ($script:lastExit -eq 2) "con HEAD detached, '$a' señaliza no-aplicable con exit 2"
}
Remove-Item -Recurse -Force $t

# --- El estado del marcador no aparece en el diff del slice ---
# Vive en el directorio de git, no en el árbol: ni se commitea ni lo ve el reviewer.
$t = New-Repo
"slice" | Set-Content (Join-Path $t "file.txt")
git -C $t add -A; git -C $t commit -q -m slice1
Marker $t advance | Out-Null
Assert (((git -C $t status --porcelain) -join "`n") -eq "") "el estado del marcador no ensucia el árbol"
$sliceDiff = ((git -C $t diff --name-only master...HEAD) -join "`n")
Assert ($sliceDiff -notmatch "review-loop-state") "el estado del marcador no aparece en el diff del slice"
Assert (Test-Path (Join-Path $t ".git/review-loop-state.json")) "el estado se persiste en el directorio de git"
Remove-Item -Recurse -Force $t

# --- Marcador podado por git gc: cae a la base del slice, nunca revisa de menos ---
$t = New-Repo
# El árbol sucio fuerza un marcador de `git stash create`, que es un objeto INALCANZABLE
# (con el árbol limpio el marcador cae a HEAD, que ningún gc poda).
"revisado" | Set-Content (Join-Path $t "a.txt")
git -C $t add -A
$adv = Marker $t advance
git -C $t commit -q -m revisado
git -C $t reflog expire --expire-unreachable=now --all 2>$null | Out-Null
git -C $t gc --prune=now -q 2>$null | Out-Null
git -C $t cat-file -e "$adv^{commit}" 2>$null
Assert ($LASTEXITCODE -ne 0) "el gc efectivamente podó el objeto del marcador (guard del fixture)"
"nuevo" | Set-Content (Join-Path $t "b.txt")
git -C $t add -A; git -C $t commit -q -m nuevo
$r = Marker $t range
Assert ($r -eq (git -C $t merge-base master HEAD)) "con el marcador podado, el rango cae a la base del slice"
Remove-Item -Recurse -Force $t

# --- Coexiste con el dedupe del hook en el mismo archivo de estado ---
# El hook guarda bajo `<rama>`; el marcador bajo `marker:<rama>`. Git prohíbe ':' en nombres de
# rama, así que las claves no pueden colisionar — pero ninguno debe pisar el estado del otro.
$t = New-Repo
$sp = Join-Path $t ".git/review-loop-state.json"
'{ "feat/x": "deadbeef" }' | Set-Content $sp -Encoding UTF8
"slice" | Set-Content (Join-Path $t "file.txt")
$adv = Marker $t advance
$state = (Get-Content $sp -Raw | ConvertFrom-Json)
Assert ($state.'feat/x' -eq "deadbeef") "advance preserva el estado del dedupe del hook"
Assert ($state.'marker:feat/x' -eq $adv) "advance persiste el marcador bajo la clave marker:<rama>"
Remove-Item -Recurse -Force $t

# --- Los fixes del loop, sin commitear, entran en el rango del turno siguiente ---
# Es la conducta por la que existe el diseño: el paso de fixes escribe sin commitear, y el turno
# que sigue tiene que verlos. Sin este pin, `git diff --quiet <marcador> HEAD` (que ignora el
# árbol) pasaría todos los demás tests.
$t = New-Repo
"slice" | Set-Content (Join-Path $t "file.txt")
git -C $t add -A; git -C $t commit -q -m slice1
Marker $t advance | Out-Null
Add-Content (Join-Path $t "file.txt") -Value "fix del loop, sin commitear"
$r = Marker $t range
Assert ($r -ne "") "un fix sin commitear deja rango para el turno siguiente"
Assert (((git -C $t diff --name-only $r) -join "`n") -match "file\.txt") "el rango nombra el archivo del fix sin commitear"
Remove-Item -Recurse -Force $t

# --- Un archivo nuevo sin trackear cuenta como delta sin revisar ---
# El paso de fixes del loop ordena escribir un test que falle antes del fix: ese archivo nace
# untracked. `git stash create` y `git diff` lo ignoran, así que sin este caso el rango sale
# vacío y el loop cierra reportando limpio un fix que nadie revisó.
$t = New-Repo
"slice" | Set-Content (Join-Path $t "file.txt")
git -C $t add -A; git -C $t commit -q -m slice1
Marker $t advance | Out-Null
"# test nuevo del fix" | Set-Content (Join-Path $t "nuevo.tests.ps1")
Assert ((Marker $t range) -ne "") "un archivo nuevo sin trackear deja rango para el turno siguiente"
Remove-Item -Recurse -Force $t

# --- La base sale del remoto cuando no hay rama local con ese nombre ---
# `origin/HEAD` apunta a `origin/main`; pelarle el prefijo da `main`, que en un clon de una sola
# rama no existe. Si la base no resuelve, el rango se vacía y el slice entero queda sin revisar.
$up = New-Repo
git -C $up checkout -q master
$cl = Join-Path ([IO.Path]::GetTempPath()) ("rm-clone-" + [guid]::NewGuid().ToString('N'))
git clone -q $up $cl 2>$null
git -C $cl config user.email a@b.c; git -C $cl config user.name a
git -C $cl checkout -q -b feat/y
"slice" | Set-Content (Join-Path $cl "file.txt")
git -C $cl add -A; git -C $cl commit -q -m slice1
git -C $cl branch -D master 2>$null | Out-Null
Assert ((git -C $cl rev-parse --verify --quiet master 2>$null) -eq $null) "el fixture no tiene rama local master (guard)"
$r = Marker $cl range
Assert ($r -eq (git -C $cl merge-base origin/master HEAD)) "sin rama local, la base sale de la rama remota"
Remove-Item -Recurse -Force $up, $cl

# --- Un nombre conocido que YA CONTIENE HEAD no puede ganar la elección de base ---
# Cuando la feature se mergeó a `develop` y el trabajo sigue en la rama, `merge-base develop HEAD`
# es HEAD y su distancia es 0. Elegir el candidato más cercano lo convierte en ganador seguro, la
# base colapsa a HEAD y `git diff HEAD` ya no muestra ni un commit del slice — con exit 0, que para
# el caller significa "rango confiable". Es el modo de falla más grave del script: el loop cierra
# reportando limpio un slice que nadie leyó. HEAD sólo vale como base cuando ningún otro candidato
# ofrece algo mejor.
$t = New-RepoOn "main"
git -C $t checkout -q -b develop
git -C $t checkout -q -b feat/m
"uno" | Set-Content (Join-Path $t "s1.txt")
git -C $t add -A; git -C $t commit -q -m slice1
"dos" | Set-Content (Join-Path $t "s2.txt")
git -C $t add -A; git -C $t commit -q -m slice2
git -C $t checkout -q develop
git -C $t merge -q --no-ff -m "merge del slice" feat/m
git -C $t checkout -q feat/m
Assert ((git -C $t merge-base develop HEAD) -eq (git -C $t rev-parse HEAD)) "el fixture tiene una rama nombrada que contiene HEAD (guard)"
$r = Marker $t range
# El orden de estos asserts importa: `$r -ne HEAD` también se cumple con el rango VACÍO, así que
# comprobar primero que hay rango es lo que impide que este test pase sin verificar nada.
Assert ($r -ne "") "con la rama ya mergeada a develop, el rango no queda vacío"
Assert ($script:lastExit -eq 0) "con la rama ya mergeada a develop, el rango es aplicable (exit 0)"
Assert ($r -ne (git -C $t rev-parse HEAD)) "un candidato que contiene HEAD no colapsa la base a HEAD"
$names = if ($r) { ((git -C $t diff --name-only $r) -join "`n") } else { "" }
Assert (($names -match "s1\.txt") -and ($names -match "s2\.txt")) "con la rama ya mergeada a develop, el rango sigue trayendo los commits del slice"
Remove-Item -Recurse -Force $t

# --- La base no tiene por qué llamarse main/master/develop ---
# Con la rama base llamada `trunk` no hay nombre conocido que probar, pero sí hay otra ref en el
# repo: el punto de bifurcación contra ella ES la base del slice. Rendirse acá (exit 2) mandaba
# al caller a revisar el rango entero de la rama, que es justo lo que este marcador evita.
$t = New-RepoOn "trunk"
$bifurcacion = (git -C $t rev-parse HEAD)
git -C $t checkout -q -b feat/z
"slice" | Set-Content (Join-Path $t "file.txt")
git -C $t add -A; git -C $t commit -q -m slice1
$r = Marker $t range
Assert ($r -eq $bifurcacion) "con una base de nombre propio, el rango arranca en la bifurcación"
Assert ($script:lastExit -eq 0) "con una base de nombre propio, el rango es aplicable (exit 0)"
Remove-Item -Recurse -Force $t

# --- Sobre la propia rama base, el trabajo sin commitear sigue siendo revisable ---
# Acá no hay slice contra el que sacar merge-base (la base ES la rama actual), pero el trabajo
# sin commitear existe y alguien tiene que revisarlo: el rango cae a HEAD.
$t = New-Repo
git -C $t checkout -q master
Add-Content (Join-Path $t "file.txt") -Value "trabajo sin commitear"
$r = Marker $t range
Assert ($r -eq (git -C $t rev-parse HEAD)) "en la rama base, el rango cae a HEAD para cubrir lo no commiteado"
Assert ($script:lastExit -eq 0) "en la rama base con árbol sucio, el rango es aplicable (exit 0)"
Remove-Item -Recurse -Force $t

# --- advance nunca persiste algo que no sea un sha ---
# `git stash create` falla durante un merge conflictivo y escribe "<archivo>: needs merge" en
# STDOUT, no en STDERR: sin validar la forma, esa línea queda guardada como marcador.
$t = New-Repo
git -C $t checkout -q -b otra master
"otra rama" | Set-Content (Join-Path $t "file.txt")
git -C $t add -A; git -C $t commit -q -m otra
git -C $t checkout -q master
"master" | Set-Content (Join-Path $t "file.txt")
git -C $t add -A; git -C $t commit -q -m master
git -C $t merge otra 2>$null | Out-Null
Assert (((git -C $t status --porcelain) -join "") -match "^UU") "el fixture está en conflicto de merge (guard)"
$adv = Marker $t advance
Assert ($adv -match '^[0-9a-f]{40}$') "advance emite un sha, no la salida de error de stash create"
# Sin este guard, si advance dejara de persistir el archivo no existe, `Get-Content` tira bajo
# ErrorActionPreference=Stop, los asserts que siguen nunca corren y el repo temporal queda colgado
# en %TEMP% con un merge conflictivo adentro.
$sp = Join-Path $t ".git/review-loop-state.json"
Assert (Test-Path -LiteralPath $sp) "advance persistió el archivo de estado"
if (Test-Path -LiteralPath $sp) {
  $state = (Get-Content $sp -Raw | ConvertFrom-Json)
  Assert ($state.'marker:master' -match '^[0-9a-f]{40}$') "advance no persiste basura como marcador"
}
Remove-Item -Recurse -Force $t

# --- Un untracked que el marcador ya cubrió no vuelve a contar como delta ---
# `git stash create` no captura untracked, así que preguntar "¿hay algún untracked?" deja el rango
# no-vacío para siempre: el loop no puede cerrar por "no hay delta" y le pasa al reviewer los
# mismos archivos en cada turno. Lo que cuenta es untracked NUEVO desde el marcador.
$t = New-Repo
"slice" | Set-Content (Join-Path $t "file.txt")
git -C $t add -A; git -C $t commit -q -m slice1
"nota suelta" | Set-Content (Join-Path $t "nota.txt")       # untracked, ya existe al avanzar
Marker $t advance | Out-Null
Assert ((Marker $t range) -eq "") "un untracked ya cubierto por el marcador no deja rango"
Assert ($script:lastExit -eq 0) "sin delta nuevo, el rango cierra el loop (exit 0)"
"otro archivo nuevo" | Set-Content (Join-Path $t "nuevo.txt")
Assert ((Marker $t range) -ne "") "un untracked NUEVO después del marcador sí deja rango"
Remove-Item -Recurse -Force $t

# --- Solo un untracked nuevo, sobre la rama base, sin cambios tracked ---
# Cubre la mitad del guard que el árbol sucio no ejercita: acá lo tracked está limpio.
$t = New-Repo
git -C $t checkout -q master
"archivo nuevo" | Set-Content (Join-Path $t "nuevo.txt")
$r = Marker $t range
Assert ($r -eq (git -C $t rev-parse HEAD)) "en la rama base, un untracked nuevo hace caer el rango a HEAD"
Assert ($script:lastExit -eq 0) "en la rama base con un untracked nuevo, el rango es aplicable (exit 0)"
Remove-Item -Recurse -Force $t

# --- Editar un untracked ya cubierto vuelve a dejar rango ---
# La huella guarda ruta Y contenido: si guardara solo la ruta, el fix que el loop escribe encima
# de un archivo nuevo que el marcador ya cubrió se iría sin revisar.
$t = New-Repo
"v1" | Set-Content (Join-Path $t "nota.txt")
Marker $t advance | Out-Null
Assert ((Marker $t range) -eq "") "recién avanzado, el untracked ya cubierto no deja rango (guard)"
"v2 distinto" | Set-Content (Join-Path $t "nota.txt")
Assert ((Marker $t range) -ne "") "editar un untracked ya cubierto vuelve a dejar rango"
Remove-Item -Recurse -Force $t

# --- Lo mismo con un nombre no ASCII ---
# `git ls-files --others` respeta core.quotepath: sin desactivarlo devuelve "\303\261andu.txt"
# escapado, la ruta no existe en disco, el hash queda vacío y toda edición posterior es invisible.
$t = New-Repo
"v1" | Set-Content (Join-Path $t "ñandú.txt")
Marker $t advance | Out-Null
Assert ((Marker $t range) -eq "") "recién avanzado, el untracked con tilde no deja rango (guard)"
"v2 distinto" | Set-Content (Join-Path $t "ñandú.txt")
Assert ((Marker $t range) -ne "") "editar un untracked con tilde vuelve a dejar rango"
Remove-Item -Recurse -Force $t

# --- El estado sobrevive el cruce entre pwsh y Windows PowerShell ---
# El archivo de estado lo puede escribir un shell y leer el otro (una sesión con `pwsh`, un hook o
# una corrida a mano con `powershell.exe`). `Set-Content -Encoding UTF8` escribe SIN BOM en pwsh 7
# y CON BOM en 5.1, y `Get-Content -Raw` en 5.1 decodifica un archivo sin BOM con la code page
# ANSI: la huella del untracked acentuado se lee como mojibake, nunca vuelve a matchear, y el rango
# queda no-vacío PARA SIEMPRE — esa rama ya no puede cerrar el loop por "no hay delta" y quema los
# 5 turnos re-entregando los mismos archivos. El guard va como Assert y no como `if`: saltear el
# caso en silencio es cómo un test deja de cubrir lo único que le tocaba cubrir.
$ps5 = Join-Path $env:WINDIR "System32\WindowsPowerShell\v1.0\powershell.exe"
Assert (Test-Path -LiteralPath $ps5) "existe Windows PowerShell 5.1 para probar el cruce de shells (guard)"
if (Test-Path -LiteralPath $ps5) {
  $t = New-Repo
  "v1" | Set-Content (Join-Path $t "ñandú.txt")
  Marker $t advance | Out-Null                        # escribe el estado con pwsh 7
  $out = & $ps5 -NoProfile -File $marker -Action range -RepoDir $t
  $cruzado = if ($null -eq $out) { "" } else { (($out -join "`n")).Trim() }
  Assert ($cruzado -eq "") "el estado escrito por pwsh se lee igual desde Windows PowerShell"
  Remove-Item -Recurse -Force $t
}

# --- Lo gitignoreado no es delta ---
# Sin `--exclude-standard` cualquier artefacto ignorado quedaría como delta permanente y el loop
# no podría cerrar nunca.
$t = New-Repo
"*.log`nbuild/" | Set-Content (Join-Path $t ".gitignore")
git -C $t add -A; git -C $t commit -q -m ignore
Marker $t advance | Out-Null
"ruido" | Set-Content (Join-Path $t "salida.log")
Assert ((Marker $t range) -eq "") "un archivo gitignoreado no cuenta como delta"
Assert ($script:lastExit -eq 0) "con solo archivos ignorados, el rango cierra el loop (exit 0)"
Remove-Item -Recurse -Force $t

# --- Sobre una rama base con nombre propio, con otras ramas en el repo ---
# La base no siempre se llama main/master/develop. Estar parado en `dev` con una feature branch
# encima es la rama base igual, y el trabajo sin commitear tiene que llegar a un reviewer: el
# rango cae a HEAD. Cualquier otra ref sirve de referencia para saberlo.
$t = New-RepoOn "dev"
git -C $t checkout -q -b feature/a
git -C $t checkout -q dev
Add-Content (Join-Path $t "file.txt") -Value "sin commitear"
$r = Marker $t range
Assert ($r -eq (git -C $t rev-parse HEAD)) "en una rama base de nombre propio, el rango cae a HEAD"
Assert ($script:lastExit -eq 0) "en una rama base de nombre propio, el rango es aplicable (exit 0)"
Remove-Item -Recurse -Force $t

# --- Una rama hermana nacida del slice no puede hacer de base ---
# Sin nombres conocidos que resolver, cualquier ref sirve de referencia — pero una rama creada a
# mitad del slice (un `git branch wip`, un worktree, un backup) está SIEMPRE más cerca de HEAD que
# la base real. Tomar la más cercana achica el rango y esconde los commits ya hechos detrás de un
# exit 0. Entre refs cualesquiera hay que quedarse con el ancestro común más lejano.
$t = New-RepoOn "trunk"
$bifurcacion = (git -C $t rev-parse HEAD)
git -C $t checkout -q -b feat/z
"uno" | Set-Content (Join-Path $t "a.txt")
git -C $t add -A; git -C $t commit -q -m slice1
git -C $t branch wip                                  # backup a mitad del slice
"dos" | Set-Content (Join-Path $t "b.txt")
git -C $t add -A; git -C $t commit -q -m slice2
$r = Marker $t range
Assert ($r -eq $bifurcacion) "con una rama hermana del slice, la base sigue siendo la bifurcación"
$names = ((git -C $t diff --name-only $r) -join "`n")
Assert (($names -match "a\.txt") -and ($names -match "b\.txt")) "el rango no pierde los commits anteriores a la rama hermana"
Remove-Item -Recurse -Force $t

# --- Un upstream pusheado con otro nombre tampoco puede hacer de base ---
# `git push -u origin otra-cosa` deja una ref remota que sigue a la propia rama: es el mismo
# problema que la hermana, y la exclusión de `origin/<rama>` no lo cubre porque el nombre difiere.
$up = New-RepoOn "trunk"
git -C $up config receive.denyCurrentBranch ignore
$cl = Join-Path ([IO.Path]::GetTempPath()) ("rm-push-" + [guid]::NewGuid().ToString('N'))
git clone -q $up $cl 2>$null
git -C $cl config user.email a@b.c; git -C $cl config user.name a; git -C $cl config commit.gpgsign false
git -C $cl checkout -q -b feat/w
$bifurcacion = (git -C $cl rev-parse HEAD)
"uno" | Set-Content (Join-Path $cl "a.txt")
git -C $cl add -A; git -C $cl commit -q -m slice1
git -C $cl push -q origin feat/w:refs/heads/otra-cosa 2>$null
git -C $cl fetch -q origin 2>$null
$r = Marker $cl range
Assert ($r -eq $bifurcacion) "un upstream con otro nombre no se convierte en la base del slice"
Remove-Item -Recurse -Force $up, $cl

# --- Una rama sola en el repo: indeterminable, nunca HEAD ---
# Sin ninguna otra ref no hay con qué decidir si esta rama es la base o un slice: emitir HEAD
# escondería sus commits. El caller decide (y si el árbol está sucio puede revisarlo entero).
$t = New-Repo
git -C $t checkout -q feat/x
"uno" | Set-Content (Join-Path $t "a.txt")
git -C $t add -A; git -C $t commit -q -m "commit del slice"
git -C $t branch -D master 2>$null | Out-Null
Add-Content (Join-Path $t "file.txt") -Value "sin commitear"
$r = Marker $t range
Assert ($r -eq "") "con una sola rama en el repo, el rango no emite HEAD"
Assert ($script:lastExit -eq 2) "con una sola rama en el repo, el rango es indeterminable"
Remove-Item -Recurse -Force $t

# --- Con base de nombre propio y árbol sucio, el rango NUNCA es HEAD ---
# HEAD solo muestra lo no commiteado: emitirlo acá escondería los dos commits del slice detrás de
# un exit 0, que es la señal de "rango confiable". El rango tiene que traer las tres cosas.
$t = New-RepoOn "trunk"
git -C $t checkout -q -b feat/z
"uno" | Set-Content (Join-Path $t "a.txt")
git -C $t add -A; git -C $t commit -q -m slice1
"dos" | Set-Content (Join-Path $t "b.txt")
git -C $t add -A; git -C $t commit -q -m slice2
Add-Content (Join-Path $t "file.txt") -Value "y algo sin commitear"
$r = Marker $t range
Assert ($r -ne (git -C $t rev-parse HEAD)) "con árbol sucio, el rango no se queda en HEAD"
$names = ((git -C $t diff --name-only $r) -join "`n")
Assert (($names -match "a\.txt") -and ($names -match "b\.txt")) "el rango incluye los commits del slice"
Assert ($names -match "file\.txt") "el rango incluye además lo no commiteado"
Remove-Item -Recurse -Force $t

# --- Rama nueva sin commits propios: no hay delta, el loop cierra ---
# El merge-base contra la base ES HEAD. Eso no es "no puedo determinar": es "no hay nada nuevo".
$t = New-Repo
git -C $t checkout -q -b feat/nueva master
$r = Marker $t range
Assert ($r -eq "") "en una rama sin delta contra su base, el rango queda vacío"
Assert ($script:lastExit -eq 0) "una rama sin delta cierra el loop (exit 0), no queda indeterminable"
Remove-Item -Recurse -Force $t

# `advance` corrido desde un SUBDIRECTORIO (monorepo: la sesión abierta en `app/`) tiene que fichar
# los untracked con la ruta relativa a la RAÍZ del repo. `ls-files` lista sólo el subárbol del cwd y
# con rutas relativas a él, así que la huella quedaba con otra base que la que lee el hook — que sí
# ancla a la raíz — y ninguna de las dos volvía a matchear: un untracked ya revisado seguía contando
# como delta sin revisar para siempre.
$t = New-Repo
New-Item -ItemType Directory -Path (Join-Path $t "app") -Force | Out-Null
"nuevo" | Set-Content (Join-Path $t "app/nuevo.txt")
Marker (Join-Path $t "app") advance | Out-Null
# La lectura va afuera del Assert y con Test-Path: con $ErrorActionPreference = "Stop", un
# ReadAllText sobre un archivo inexistente aborta la corrida entera y se lleva los tests de abajo.
$stPath = Join-Path $t ".git/review-loop-state.json"
Assert (Test-Path -LiteralPath $stPath) "guard: el advance desde el subdirectorio escribió el estado"
$st = if (Test-Path -LiteralPath $stPath) { [IO.File]::ReadAllText($stPath) | ConvertFrom-Json } else { $null }
# El guard mira la PROPIEDAD, no el Count: `@($null).Count` vale 1, así que preguntarle el Count a
# una clave inexistente daba 1 y el guard pasaba en verde justo cuando el advance no fichó nada.
$prop = if ($st) { $st.PSObject.Properties["untracked:feat/x"] } else { $null }
Assert ($null -ne $prop) "guard: el estado tiene la huella de untracked de la rama"
# El filtro no es cosmético: `@($null).Count` vale 1, así que una clave presente pero con valor
# nulo daba Count 1 y este guard imprimía "fichó un untracked (1)" justo cuando no se fichó nada.
# Con el filtro, un valor nulo cuenta 0 y el assert muerde.
$hu = @($prop.Value | Where-Object { $_ })
Assert ($hu.Count -eq 1) "guard: el advance desde el subdirectorio fichó un untracked ($($hu.Count))"
Assert ($hu[0] -like "app/nuevo.txt|*") "la huella de untracked se ficha relativa a la raíz del repo, no al cwd"
Remove-Item -Recurse -Force $t

# --- Ruta no-ASCII: el marcador resuelve el repo aunque la code page NO sea UTF-8 ---
# git escribe UTF-8 y PowerShell decodifica la salida del hijo con Console::OutputEncoding. Un pwsh
# hijo con stdout redirigido — que es exactamente como el hook invoca al marcador — no hereda el
# 65001 del padre, así que `rev-parse --show-toplevel` volvía mojibake: $dir dejaba de ser un repo y
# las TRES acciones salían con exit 2 en silencio. `advance` no avanzaba nunca y el loop volvía a
# revisar la rama entera en cada turno, sin que nada lo dijera.
# El fixture fuerza la code page DENTRO del hijo para que el caso sea determinístico en cualquier
# máquina. El control positivo va primero: si `GetEncoding(850)` fallara, el `catch` se lo tragaría y
# el caso pasaría en verde sin ejercitar nada — que es la trampa que ya apareció tres veces.
$cp = ((& pwsh -NoProfile -Command "[Console]::OutputEncoding = [Text.Encoding]::GetEncoding(850); [Console]::OutputEncoding.CodePage") | Out-String).Trim()
Assert ($cp -eq "850") "control positivo: el pwsh hijo del fixture corre en code page 850 (dio '$cp')"
# El nombre se arma por punto de código y no como literal: así el caso no depende de con qué
# encoding se guardó ESTE archivo ni de con cuál lo lea el runner.
$enye = [string][char]0x00F1
$uacc = [string][char]0x00FA
$t = Join-Path ([IO.Path]::GetTempPath()) ("rm-test-" + $enye + "and" + $uacc + "-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $t | Out-Null
Init-Repo $t "master"
"base" | Set-Content (Join-Path $t "file.txt")
git -C $t add -A; git -C $t commit -q -m base
git -C $t checkout -q -b feat/x
# El `exit $LASTEXITCODE` final es necesario: sin él, `pwsh -Command` devuelve su propio código (1
# ante cualquier error) y el assert no distinguiría el exit 2 del marcador de un fallo del host.
$acc = & pwsh -NoProfile -Command "[Console]::OutputEncoding = [Text.Encoding]::GetEncoding(850); & '$marker' -Action advance -RepoDir '$t'; exit `$LASTEXITCODE"
$accExit = $LASTEXITCODE
$acc = (($acc | Out-String)).Trim()
Assert ($accExit -eq 0) "bajo ruta no-ASCII y code page OEM, advance no sale con exit 2 (dio $accExit)"
Assert ($acc -match '^[0-9a-f]{40}$') "bajo ruta no-ASCII, advance emite un marcador ('$acc')"
# El estado tiene que aterrizar DENTRO del repo: con $gitDir mojibake se escribía en una ruta
# paralela inexistente, así que el marcador se perdía entre turnos aunque advance dijera que sí.
Assert (Test-Path -LiteralPath (Join-Path $t ".git/review-loop-state.json")) "bajo ruta no-ASCII, el estado se escribe dentro del repo"
Remove-Item -Recurse -Force -LiteralPath $t

# --- `-Action base` resuelve la base del slice para el hook (Alta A: repos con base no estándar) ---
# El hook delega acá la resolución de base cuando las ramas nombradas (main/master/develop/origin-HEAD)
# fallan, para no quedar mudo en un repo cuya base se llama `trunk`, `dev`, etc. Devuelve el
# merge-base (un commit), con el mismo contrato de exit codes que `range`: 0+ref resoluble / 2+vacío.
$t = Join-Path ([IO.Path]::GetTempPath()) ("rm-test-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $t | Out-Null
Init-Repo $t "trunk"
"base" | Set-Content (Join-Path $t "file.txt")
git -C $t add -A; git -C $t commit -q -m base
$trunkTip = (git -C $t rev-parse trunk).Trim()
git -C $t checkout -q -b feat/y
"y" | Set-Content (Join-Path $t "y.txt")
git -C $t add -A; git -C $t commit -q -m y
$b = Marker $t base
Assert ($script:lastExit -eq 0) "base en repo 'trunk' sale con exit 0 (dio $($script:lastExit))"
Assert ($b -eq $trunkTip) "base delega en Get-SliceBase y devuelve el merge-base contra 'trunk'"
Remove-Item -Recurse -Force $t

# Repo con una sola rama y ninguna otra ref: no hay base determinable -> exit 2, vacío (nunca 0+vacío,
# que el hook leería como 'no hay nada que revisar' y dejaría pasar un cierre declarado).
$t = New-RepoOn "solo"
$b = Marker $t base
Assert ($script:lastExit -eq 2) "base sin ninguna ref candidata sale con exit 2 (dio $($script:lastExit))"
Assert ($b -eq "") "base indeterminable no emite ningún ref"
Remove-Item -Recurse -Force $t

# --- advance pone en cuarentena un estado ilegible antes de pisarlo (A2b fix 3) ---
# El estado compartido guarda las claves `marker:<rama>` / `untracked:<rama>` de TODAS las ramas y el
# dedupe del hook. Si el archivo queda ilegible (una escritura no atomica pisada a mitad, otra
# herramienta), advance leia @{} y reescribia solo su clave, borrando las de las demas ramas SIN
# rastro. El hook ya implementa el `.bad` para este mismo archivo; el marcador era la mitad
# asimetrica. Ahora advance mueve el archivo corrupto a `.bad` (recuperable) antes de escribir.
$t = New-Repo
$gitDir = (git -C $t rev-parse --git-dir)
$statePath = Join-Path $t (Join-Path $gitDir "review-loop-state.json")
# JSON invalido que ADEMAS contiene la clave de otra rama: es lo que hay que poder recuperar.
Set-Content -LiteralPath $statePath -Value '{ "marker:otra-rama": "deadbeef", NO_ES_JSON' -Encoding UTF8
$adv = Marker $t advance
Assert ($adv -match '^[0-9a-f]{40}$') "advance sobre estado ilegible igual fija un marcador"
Assert (Test-Path -LiteralPath "$statePath.bad") "advance movio el estado ilegible a .bad (no lo destruyo)"
$badContent = if (Test-Path -LiteralPath "$statePath.bad") { [IO.File]::ReadAllText("$statePath.bad") } else { "" }
Assert ($badContent -match 'otra-rama') "el .bad conserva la clave de la otra rama (recuperable)"
$newState = [IO.File]::ReadAllText($statePath) | ConvertFrom-Json
Assert ($newState.'marker:feat/x' -eq $adv) "el estado nuevo tiene el marcador de la rama actual"
Remove-Item -Recurse -Force $t

# Rama $writable=$false: si el Move-Item a `.bad` FALLA (destino bloqueado), advance NO debe pisar el
# estado ilegible — reescribirlo destruye justo lo que la cuarentena preserva. Saltea la escritura y
# AUN ASI imprime el marcador (el punto de corte se comunica). Gemelo del test del hook (:587-594).
# Sin el guard `if ($writable)`, el archivo original se pisa: el assert de que sigue ilegible cae.
$t = New-Repo
$gitDir = (git -C $t rev-parse --git-dir)
$statePath = Join-Path $t (Join-Path $gitDir "review-loop-state.json")
Set-Content -LiteralPath $statePath -Value '{ "marker:otra-rama": "deadbeef", ROTO' -Encoding UTF8
$lock = [IO.File]::Open("$statePath.bad", [IO.FileMode]::Create, [IO.FileAccess]::Write, [IO.FileShare]::None)
try { $adv = Marker $t advance } finally { $lock.Close(); $lock.Dispose() }
Assert ($adv -match '^[0-9a-f]{40}$') "con la cuarentena bloqueada, advance igual imprime el marcador"
$origStill = [IO.File]::ReadAllText($statePath)
Assert ($origStill -match 'otra-rama') "con la cuarentena bloqueada, advance NO pisa el estado original (queda recuperable)"
Remove-Item -Recurse -Force $t

# ============ A4b — anclaje del pase de coherencia al slice que cierra ============
# En una rama con slices APILADOS, `slice-base` ancla en el inicio del slice que cierra —el marcador
# capturado por `open` al arrancar el loop— no en la base de la rama. `base` sigue devolviendo la base
# de rama. Sin esto la coherencia sobre-scopeaba a toda la rama (medido: 9613/56) en vez del slice
# (248/5). Este tracer prueba las dos mitades a la vez: slice-base ajustado, base intacto.
$t = New-Repo                                       # feat/x sobre master, con file.txt commiteado
"s1" | Set-Content (Join-Path $t "s1.txt")          # slice-1
git -C $t add -A; git -C $t commit -q -m slice1
Marker $t advance | Out-Null                        # el loop del slice-1 avanza el marcador a su cierre
$m1 = Marker $t get
"s2" | Set-Content (Join-Path $t "s2.txt")           # slice-2 apilado encima
git -C $t add -A; git -C $t commit -q -m slice2
Marker $t open | Out-Null                            # loop del slice-2 turno 1: open captura fin-de-slice-1
$sb = Marker $t 'slice-base'
Assert ($sb -eq $m1) "slice-base ancla en el marcador capturado por open (inicio del slice que cierra)"
$sbNames = ((git -C $t diff --name-only $sb) -join "`n")
Assert (($sbNames -match "s2\.txt") -and ($sbNames -notmatch "s1\.txt")) "en rama apilada, slice-base lee solo el slice que cierra"
$baseNames = ((git -C $t diff --name-only (Marker $t base)) -join "`n")
Assert (($baseNames -match "s1\.txt") -and ($baseNames -match "s2\.txt")) "base sigue devolviendo la base de rama (rama entera), sin cambios"
Remove-Item -Recurse -Force $t

# --- open SÓLO escribe slice-open: no avanza el marcador ni pierde las otras claves del estado ---
# Dos invariantes que sin assert propio pasan mudos (mutación demostrable): (D) si open avanzara
# marker:<branch>, el próximo `range` no vería delta y cerraría el slice SIN revisar —el falso negativo
# que toda esta máquina existe para evitar—; (C) si open reserializara sólo {slice-open}, borraría el
# dedupe del hook (clave de nombre pelado) y untracked: de otras ramas, que advance NO reescribe.
$t = New-Repo                                        # rama feat/x sobre master
"s1" | Set-Content (Join-Path $t "s1.txt")
git -C $t add -A; git -C $t commit -q -m slice1
Marker $t advance | Out-Null                         # deja marker:feat/x + untracked:feat/x
$m1 = Marker $t get
# sembrar claves que open NO debe tocar: dedupe del hook para feat/x (nombre pelado) y otra rama
$gitDir = (git -C $t rev-parse --git-dir)
$statePath = Join-Path $t (Join-Path $gitDir "review-loop-state.json")
$st = Get-Content -Raw -LiteralPath $statePath | ConvertFrom-Json
$st | Add-Member -NotePropertyName 'feat/x' -NotePropertyValue 'hookdedupe123' -Force
$st | Add-Member -NotePropertyName 'untracked:otra-rama' -NotePropertyValue 'unt456' -Force
($st | ConvertTo-Json) | Set-Content -LiteralPath $statePath -Encoding UTF8
"s2" | Set-Content (Join-Path $t "s2.txt")
git -C $t add -A; git -C $t commit -q -m slice2
Marker $t open | Out-Null                            # turno 1 del slice-2: sólo captura slice-open
Assert ((Marker $t get) -eq $m1) "open no avanza el marcador (marker:<branch> intacto)"
$after = Get-Content -Raw -LiteralPath $statePath | ConvertFrom-Json
Assert ($after.'slice-open:feat/x' -eq $m1) "open registra el marcador como slice-open:<branch> (invariante positivo)"
Assert ($after.'feat/x' -eq 'hookdedupe123') "open preserva el dedupe del hook (clave de nombre pelado)"
Assert ($after.'untracked:otra-rama' -eq 'unt456') "open preserva claves untracked: de otras ramas"
Remove-Item -Recurse -Force $t

# --- Primer slice de la rama: sin marcador, open no escribe y slice-base cae a la base de rama ---
# Es el AC del primer slice: no hay slice anterior del cual arrancar, así que la coherencia mira desde
# la base de rama. open leído sin marcador previo no debe dejar un slice-open espurio.
$t = New-Repo
"slice" | Set-Content (Join-Path $t "file.txt")
git -C $t add -A; git -C $t commit -q -m slice1
Marker $t open | Out-Null                            # no hay marcador previo → no escribe slice-open
$base = (git -C $t merge-base master HEAD)
Assert ((Marker $t 'slice-base') -eq $base) "primer slice (sin marcador previo), slice-base cae a la base de rama"
Remove-Item -Recurse -Force $t

# --- slice-base ignora un slice-open que ya no resuelve (rebase/gc) y cae a la base de rama ---
# Si un rebase reescribió la historia o gc podó el objeto, el snapshot deja de resolver: la dirección
# segura es revisar de más (la rama), nunca leer un diff con hunks fantasma contra un ref muerto.
$t = New-Repo
"slice" | Set-Content (Join-Path $t "file.txt")
git -C $t add -A; git -C $t commit -q -m slice1
$gitDir = (git -C $t rev-parse --git-dir)
$statePath = Join-Path $t (Join-Path $gitDir "review-loop-state.json")
Set-Content -LiteralPath $statePath -Value '{ "slice-open:feat/x": "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef" }' -Encoding UTF8
$base = (git -C $t merge-base master HEAD)
Assert ((Marker $t 'slice-base') -eq $base) "slice-base ignora un slice-open irresoluble y cae a la base de rama"
Remove-Item -Recurse -Force $t

# --- slice-base sin base determinable: exit 2, no 0 ---
# Misma razón que range/base: exit 0 vacío significaría "nada que revisar" y cerraría el pase de
# coherencia sobre un slice que nadie ancló. Repo de una sola rama, sin refs contra las cuales medir.
$t = New-RepoOn "master"
Marker $t 'slice-base' | Out-Null
Assert ($script:lastExit -eq 2) "slice-base sin base determinable sale con exit 2"
Remove-Item -Recurse -Force $t

# ============ A4c — limpieza del ancla slice-open al cierre limpio ============
# `close` borra slice-open:<branch> para que el slice siguiente arranque fresco. Solo el cierre LIMPIO
# del loop lo llama; el cierre por cap lo conserva, para que una re-corrida manual del mismo slice sin
# cerrar siga anclando en su arranque real (write-once no-op) en vez de under-scopear. ADR-0002.

# --- Tracer: close borra slice-open, sale 0 y no toca el marcador ---
$t = New-Repo
"s1" | Set-Content (Join-Path $t "s1.txt")
git -C $t add -A; git -C $t commit -q -m slice1
Marker $t advance | Out-Null                          # marker:feat/x
$m1 = Marker $t get
Marker $t open | Out-Null                             # slice-open:feat/x = $m1
$gitDir = (git -C $t rev-parse --git-dir)
$statePath = Join-Path $t (Join-Path $gitDir "review-loop-state.json")
$before = Get-Content -Raw -LiteralPath $statePath | ConvertFrom-Json
Assert ($before.'slice-open:feat/x' -eq $m1) "precondición: open dejó slice-open:feat/x"
Marker $t close | Out-Null
Assert ($script:lastExit -eq 0) "close sale con exit 0"
$after = Get-Content -Raw -LiteralPath $statePath | ConvertFrom-Json
Assert (-not ($after.PSObject.Properties.Name -contains 'slice-open:feat/x')) "close borra slice-open:<branch>"
Assert ((Marker $t get) -eq $m1) "close no avanza ni toca el marcador (marker:<branch> intacto)"
Remove-Item -Recurse -Force $t

# --- open es write-once: NO mueve slice-open hacia adelante dentro del mismo slice ---
# El bug de under-scope (hallazgo B de A4b): si el loop capea sin cerrar y alguien re-corre
# /review-loop sobre el MISMO slice, el open de la re-corrida NO debe re-snapshotear el marcador ya
# avanzado. Con slice-open ya fijado y resolviendo, open es no-op y el ancla queda en el arranque real.
$t = New-Repo
"s1" | Set-Content (Join-Path $t "s1.txt")
git -C $t add -A; git -C $t commit -q -m slice1
Marker $t advance | Out-Null                          # marker en fin-de-slice-1 = arranque real del slice-2
$start = Marker $t get
Marker $t open | Out-Null                             # slice-2 turno 1: slice-open = $start
"s2" | Set-Content (Join-Path $t "s2.txt")            # el loop del slice-2 avanza (turnos)
git -C $t add -A; git -C $t commit -q -m s2fix
Marker $t advance | Out-Null                          # marker AHORA más adelante que $start
$advanced = Marker $t get
Assert ($advanced -ne $start) "precondición: el marcador avanzó respecto del arranque del slice"
Marker $t open | Out-Null                             # re-corrida turno 1: NO debe pisar slice-open
$statePath = Join-Path $t (Join-Path (git -C $t rev-parse --git-dir) "review-loop-state.json")
$after = Get-Content -Raw -LiteralPath $statePath | ConvertFrom-Json
Assert ($after.'slice-open:feat/x' -eq $start) "open write-once: no re-snapshotea el marcador avanzado (ancla en el arranque real)"
Remove-Item -Recurse -Force $t

# --- Tras close (cierre limpio), el open del slice siguiente SÍ re-snapshotea (flujo multi-slice) ---
# El write-once no rompe el flujo apilado: cuando un slice cierra limpio, close borra el ancla y el open
# del slice siguiente escribe el arranque nuevo. Es el AC que garantiza que write-once + close conviven.
$t = New-Repo
"s1" | Set-Content (Join-Path $t "s1.txt")
git -C $t add -A; git -C $t commit -q -m slice1
Marker $t advance | Out-Null
$startA = Marker $t get
Marker $t open | Out-Null                             # slice A: slice-open = $startA
Marker $t close | Out-Null                            # cierre LIMPIO de A: borra el ancla
"s2" | Set-Content (Join-Path $t "s2.txt")
git -C $t add -A; git -C $t commit -q -m slice2
Marker $t advance | Out-Null                          # marcador ahora en fin-de-A = arranque de B
$startB = Marker $t get
Assert ($startB -ne $startA) "precondición: el arranque del slice B difiere del de A"
Marker $t open | Out-Null                             # slice B turno 1: ancla vacía → escribe fresco
$statePath = Join-Path $t (Join-Path (git -C $t rev-parse --git-dir) "review-loop-state.json")
$after = Get-Content -Raw -LiteralPath $statePath | ConvertFrom-Json
Assert ($after.'slice-open:feat/x' -eq $startB) "tras close, el open del slice siguiente re-snapshotea el arranque nuevo (no rompe multi-slice)"
Remove-Item -Recurse -Force $t

# --- close borra slice-open pero preserva las demás claves, y es idempotente ---
# (C) si close reserializara solo {} o la clave equivocada, borraría el dedupe del hook (nombre pelado),
# los marcadores de otras ramas y el propio marker:<branch> — mutaciones que sin este assert pasan mudas.
$t = New-Repo
"s1" | Set-Content (Join-Path $t "s1.txt")
git -C $t add -A; git -C $t commit -q -m slice1
Marker $t advance | Out-Null
$m1 = Marker $t get
Marker $t open | Out-Null                             # slice-open:feat/x = $m1
$statePath = Join-Path $t (Join-Path (git -C $t rev-parse --git-dir) "review-loop-state.json")
$st = Get-Content -Raw -LiteralPath $statePath | ConvertFrom-Json
$st | Add-Member -NotePropertyName 'feat/x' -NotePropertyValue 'hookdedupe123' -Force
$st | Add-Member -NotePropertyName 'marker:otra-rama' -NotePropertyValue 'deadbeef' -Force
($st | ConvertTo-Json) | Set-Content -LiteralPath $statePath -Encoding UTF8
Marker $t close | Out-Null
$after = Get-Content -Raw -LiteralPath $statePath | ConvertFrom-Json
Assert (-not ($after.PSObject.Properties.Name -contains 'slice-open:feat/x')) "close borra slice-open aun con otras claves presentes"
Assert ($after.'feat/x' -eq 'hookdedupe123') "close preserva el dedupe del hook (clave de nombre pelado)"
Assert ($after.'marker:otra-rama' -eq 'deadbeef') "close preserva marcadores de otras ramas"
Assert ($after.'marker:feat/x' -eq $m1) "close preserva el marcador de la propia rama"
Marker $t close | Out-Null                            # segunda vez, sin slice-open: no-op
Assert ($script:lastExit -eq 0) "close es idempotente (segunda llamada sin slice-open sale 0)"
Remove-Item -Recurse -Force $t

if ($script:failures -gt 0) { Write-Host "$($script:failures) test(s) FALLARON"; exit 1 } else { Write-Host "TODOS LOS TESTS PASARON"; exit 0 }
