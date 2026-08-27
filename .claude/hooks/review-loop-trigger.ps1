# Hook PostToolUse (matcher Bash). Inyecta a Claude la orden de correr /review-loop sobre el delta
# sin revisar cuando se cierra un slice en un branch que NO es la base. Dispara en `gh pr create`,
# en `git push`, y en un `git commit` que DECLARA el cierre con un trailer `Slice-Close:` — un
# commit sin el trailer dispara sólo como red de seguridad, cuando el delta sin revisar pasa el
# techo de ~400 líneas. A los commits se les verifica además la frescura, porque el evento trae el
# cwd de la sesión y un commit hecho en otro repo se le atribuiría a éste.
# Comparte .git/review-loop-state.json con el marcador de revisión: deduplica por SHA ahí y nunca
# destruye las claves del marcador. Cualquier camino que no aplique termina en exit 0 silencioso.
#
# Lo que este hook a propósito NO hace: averiguar en qué repo corrió el comando parseando la línea
# de comando de bash. Ese bloque existía para no disparar cuando un `git push` se corría en otro
# lado desde una sesión abierta acá, y en tres turnos de revisión produjo ocho hallazgos altos
# propios — todos FALSOS NEGATIVOS que descartaban un cierre de slice declarado en silencio. Las
# señales que quedan son observables en vez de parseadas: la frescura del HEAD
# (`git log -1 --format=%ct`) para los commits y el dedupe por SHA para todo lo demás. El costo
# aceptado es un review-loop de más cuando el push sí corrió en otro repo, que es la dirección segura.
$ErrorActionPreference = "SilentlyContinue"

# git escribe UTF-8 y PowerShell decodifica la salida del hijo con Console::OutputEncoding. Un hook
# corre como proceso hijo con stdout redirigido, así que no hereda una consola en UTF-8: lo necesita
# TODA llamada a git cuya salida pueda traer una ruta, no sólo el `ls-files` del techo. Bajo una ruta
# no-ASCII, `rev-parse --show-toplevel` volvía mojibake y el marcador ya no se podía encontrar.
try { [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false) } catch { }
# El JSON del evento llega por STDIN, decodificado con Console::InputEncoding — y un hook lanzado con
# la consola en OEM (el default de Windows) tampoco hereda UTF-8 en la entrada. Sin esto, un evento
# cuyo `cwd` trae una ruta no-ASCII (`C:\Users\Martín\…`) volvía mojibake, el `Set-Location` de abajo
# fallaba en silencio, y el hook corría sobre el repo AMBIENTE y disparaba — desubicando todo. Se
# fuerza antes de la primera lectura de [Console]::In para que el reader se (re)construya con UTF-8.
try { [Console]::InputEncoding = [Text.UTF8Encoding]::new($false) } catch { }

# 1. Leer el evento del hook por stdin
$raw = [Console]::In.ReadToEnd()
if (-not $raw) { exit 0 }
try { $evt = $raw | ConvertFrom-Json } catch { exit 0 }
$cmd = $evt.tool_input.command
if (-not $cmd) { exit 0 }

# 2. Filtrar: gh pr create / git push / git commit
# Todas las decisiones de acá abajo leen el comando NORMALIZADO, nunca el crudo: el comando crudo
# trae el texto del `-m`, así que un commit cuyo mensaje apenas menciona `git push` prendía $isPush
# y salteaba la puerta del trailer entera del paso 6: sin gate, sin ventana de frescura y sin techo.
#
# Neutralizar el texto entrecomillado con un `-replace` pelado no alcanza, y las dos formas en que
# falla están reproducidas: `-m "... \"git push\" ..."` corta el match en la comilla escapada y deja
# el texto expuesto (dispara cuando no debe), y un apóstrofe adentro de comillas dobles
# (`-m "don't" && git push`) hace que el patrón de comilla simple empareje de un apóstrofe al otro y
# se coma el push REAL del medio (no dispara cuando debe). Por eso los literales se recorren: bash
# escapa con `\` adentro de comillas dobles, y adentro de comillas simples no escapa nada.
#
# El resultado conserva la LONGITUD ORIGINAL — el interior se reemplaza carácter por carácter con
# U+0001 —, así que un índice de $scan también es un índice de $cmd, que es como el paso 4 recupera
# el valor real de `--base` de adentro de un literal que esta función a propósito no puede leer.
function Hide-Literals([string]$s) {
    $out = [char[]]$s
    $i = 0
    while ($i -lt $s.Length) {
        $q = $s[$i]
        # AFUERA de un literal, la barra invertida escapa al carácter siguiente, y saltear esa regla
        # no es cosmético: `'\''` es como bash escribe un apóstrofe (cierra, comilla escapada, vuelve
        # a abrir). Leída como comilla de apertura, la comilla suelta empareja con la SIGUIENTE, el
        # resto del mensaje queda expuesto, y un `-m "... git push ..."` prende $isPush y saltea la
        # puerta del trailer entera. Verificado con `git commit -m 'fix: it'\''s ready to git push now'`.
        if ($q -eq '\') { $i += 2; continue }
        if ($q -ne "'" -and $q -ne '"') { $i++; continue }
        $j = $i + 1
        while ($j -lt $s.Length) {
            if ($q -eq '"' -and $s[$j] -eq '\' -and $j + 1 -lt $s.Length) { $j += 2; continue }
            if ($s[$j] -eq $q) { break }
            $j++
        }
        # Dos finales distintos, separados a propósito: un literal cerrado termina EN la comilla de
        # cierre, y uno sin cerrar se come el resto de la línea — la lectura segura de un comando
        # roto. Colapsarlos en un solo `Min($j, longitud - 1)` dejaba el último carácter sin
        # enmascarar, que no es lo que decía el comentario.
        $end = if ($j -lt $s.Length) { $j } else { $s.Length }
        for ($k = $i + 1; $k -lt $end; $k++) { $out[$k] = [char]1 }
        $i = $end + 1
    }
    return (-join $out)
}
$scan = Hide-Literals $cmd
# `git -C <path> push` no matcheaba ningún patrón, así que un push legítimo nunca cerraba el ciclo.
# Las opciones globales de git se pliegan para que el subcomando quede pegado a `git`. Esta copia
# del comando se usa SOLO para las banderas: el plegado corre los offsets, así que el paso 4
# trabaja sobre $scan.
$folded   = $scan -replace '(?i)\bgit\s+(?:(?:-C|-c|--git-dir|--work-tree)(?:\s+|=)\S+\s+|--no-pager\s+|--paginate\s+)+', 'git '
$isPr     = $folded -match '\bgh\s+pr\s+create\b'
$isPush   = $folded -match '\bgit\s+push\b'
$isCommit = $folded -match '\bgit\s+commit(?![\w-])'   # excluye git commit-graph y similares
# La sustitución de comando `$(...)` y los backticks reinician el contexto de comillas de bash
# adentro, algo que Hide-Literals no modela: una comilla doble dentro de comillas simples dentro de
# `$(...)` deja el total de dobles IMPAR, el walker de literales se desincroniza y se traga el resto
# de la línea, PERDIENDO disparadores reales — `git commit -m "$(sed 's/"/x/' f)" && git push` salía
# con $isPush FALSE, el push perdido. En vez de modelar `$()` (el pozo del parseo de bash que produjo
# ocho altas), cuando el comando contiene `$(` o un backtick se recalculan las banderas sobre el
# comando CRUDO y se combinan con OR: todo falso negativo se vuelve falso positivo, la dirección que
# el proyecto ya declaró segura (un review-loop de más, nunca un cierre perdido). Los usos naturales
# (`date +"%F"`, `basename "$PWD"`) mantienen un número PAR de comillas, se re-alinean solos y no
# llegan a esta rama.
if ($cmd.Contains('$(') -or $cmd.Contains('`')) {
    $rawFolded = $cmd -replace '(?i)\bgit\s+(?:(?:-C|-c|--git-dir|--work-tree)(?:\s+|=)\S+\s+|--no-pager\s+|--paginate\s+)+', 'git '
    $isPr     = $isPr     -or ($rawFolded -match '\bgh\s+pr\s+create\b')
    $isPush   = $isPush   -or ($rawFolded -match '\bgit\s+push\b')
    $isCommit = $isCommit -or ($rawFolded -match '\bgit\s+commit(?![\w-])')
}
if (-not ($isPr -or $isPush -or $isCommit)) { exit 0 }

# 3. Ubicarse en el repo (cwd del evento)
# Si el evento trae un cwd que no resuelve en disco, salir en vez de seguir de largo: con
# $ErrorActionPreference = SilentlyContinue un Set-Location fallido es mudo, y el hook seguiría
# corriendo sobre el directorio donde se lanzó — el repo AMBIENTE — inyectando ahí un cierre falso. El
# forzado de encoding de arriba es el fix principal para un cwd no-ASCII; esto es la red que evita que
# CUALQUIER cwd irresoluble (mojibake, una ruta vieja, un dir borrado) dispare sobre el repo equivocado.
$cwd = if ($evt.cwd) { $evt.cwd } else { (Get-Location).Path }
if (-not (Test-Path -LiteralPath $cwd)) { exit 0 }
Set-Location -LiteralPath $cwd
$gitDir = (git rev-parse --git-dir 2>$null)
if (-not $gitDir) { exit 0 }                 # no es repo git
if (-not [System.IO.Path]::IsPathRooted($gitDir)) { $gitDir = Join-Path $cwd $gitDir }
$branch = (git rev-parse --abbrev-ref HEAD 2>$null)
if (-not $branch -or $branch -eq "HEAD") { exit 0 }

# 3a. Cargar el estado compartido. Se lee antes del paso 6 porque el techo necesita la huella de
# untracked del marcador, y otra vez en el paso 7 para el dedupe por SHA: leerlo una sola vez
# mantiene los dos en sincronía.
# Es el mismo archivo que escribe el marcador de revisión. Se lee y se escribe UTF-8 explícito:
# Get-Content / Set-Content usan la code page ANSI bajo Windows PowerShell 5.1, y eso convierte la
# huella acentuada de untracked del marcador en mojibake — esa rama no puede volver a cerrar nunca.
# -LiteralPath: sin eso, un repo bajo una ruta con corchetes se lee como "no hay archivo de estado"
# en CADA corrida, así que el dedupe deja de existir en silencio y el estado se pisa entero.
$statePath = Join-Path $gitDir "review-loop-state.json"
$state = @{}
$stateWritable = $true
if (Test-Path -LiteralPath $statePath) {
    try {
        ([IO.File]::ReadAllText($statePath) | ConvertFrom-Json).PSObject.Properties |
            ForEach-Object { $state[$_.Name] = $_.Value }
    } catch {
        # Estado ilegible: las claves `marker:*` / `untracked:*` del marcador viven en este mismo
        # archivo, y reescribirlo con sólo la clave de dedupe las borraría de todas las ramas sin
        # dejar rastro. Se aparta para que siga siendo recuperable, y se arranca limpio.
        $state = @{}
        # Si la cuarentena misma falla — la causa más probable es el marcador teniendo el archivo
        # tomado a mitad de una reescritura, porque esa escritura no es atómica — hay que dejar el
        # archivo QUIETO: pisarlo en el paso 7 destruye justo lo que la cuarentena preserva. Saltear
        # la escritura es todo el remedio; saltear el DISPARO, como hacía la versión anterior
        # (`catch { exit 0 }`), cambiaba un archivo recuperable por un cierre de slice descartado en
        # silencio, que es la dirección peligrosa. Perder el dedupe sólo implica que el commit
        # siguiente puede disparar dos veces.
        # -ErrorAction Stop es lo que hace alcanzable este catch: con $ErrorActionPreference en
        # SilentlyContinue, la falla del Move-Item no es terminante y el catch nunca corría.
        try { Move-Item -LiteralPath $statePath -Destination "$statePath.bad" -Force -ErrorAction Stop }
        catch { $stateWritable = $false }
    }
}

# 4. Resolver la base branch (NO hardcodear main)
# La BANDERA se ubica sobre $scan y su valor se lee de $cmd en el mismo índice — el único lugar
# donde hay que recuperar un valor real de atrás de la máscara. Matchear el comando crudo fallaba
# de las dos maneras: un `--base "develop"` entrecomillado no matcheaba nada (la clase de caracteres
# corta en la comilla) y caía al fallback, y un `--base` apenas mencionado adentro de `--title`
# ganaba por ser el primer match, así que el mensaje inyectado apuntaba a un rango contra una rama
# que no existe.
$base = $null
if ($isPr) {
    $bm = [regex]::Match($scan, '--base(?:\s+|=)')
    if ($bm.Success) {
        $tail = $cmd.Substring($bm.Index + $bm.Length)
        if ($tail -match '^(?:''([^'']*)''|"([^"]*)"|([^\s;&|]+))') {
            foreach ($g in 1, 2, 3) { if (-not $base -and $matches[$g]) { $base = $matches[$g] } }
        }
    }
}
if (-not $base) {
    $head = (git symbolic-ref --short refs/remotes/origin/HEAD 2>$null)
    if ($head) {
        # Pelar `origin/` solo si la rama local existe de verdad. Un clon de una sola rama tiene
        # `origin/main` y ningún `main` local, y con el nombre pelado falla el rango de fallback
        # que este hook sugiere (`git diff <base>...HEAD`).
        $short = ($head -replace '^origin/', '')
        git rev-parse --verify --quiet "$short^{commit}" 2>$null | Out-Null
        $base = if ($LASTEXITCODE -eq 0) { $short } else { ([string]$head).Trim() }
    }
}
if (-not $base) {
    foreach ($cand in @("main", "master", "develop")) {
        git rev-parse --verify --quiet "$cand" 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) { $base = $cand; break }
    }
}
# Bases con nombre no estándar (`trunk`, `dev`, `release`): se delega en el marcador, cuyo resolvedor
# ya las maneja (for-each-ref + merge-base --octopus). Esto cierra la ASIMETRÍA que hacía a este hook
# la mitad muda del motor — el código viejo hacía `exit 0` acá, ANTES del gate del trailer de abajo,
# así que en un repo cuya base no es main/master/develop se perdía un cierre DECLARADO en silencio,
# justo el falso negativo que este hook existe para eliminar, escondido en GitHub donde `gh repo
# view` lo rescataba. Ese `gh repo view` también se fue: era una llamada de red en cada commit cuando
# origin/HEAD no está seteado (el caso `git init` + `remote add`), y corría ANTES del fallback local
# que resuelve gratis. La rama default de un clon ya la cubre origin/HEAD de arriba; un repo no-clon
# cae a las ramas nombradas y luego acá. El marcador emite un commit (el merge-base), usado solo como
# extremo del diff y en el mensaje, nunca como guarda de nombre de rama. Sin marcador (repo no
# bootstrapeado, así que tampoco hay /review-loop que correr) $base queda nulo y el hook calla.
if (-not $base) {
    $root = (git rev-parse --show-toplevel 2>$null)
    if ($root) {
        $mk = Join-Path $root ".claude/scripts/review-marker.ps1"
        if (Test-Path -LiteralPath $mk) {
            # Centinela: si `pwsh` no está en el PATH el error tragado dejaría $LASTEXITCODE en el 0
            # de la llamada a git de arriba, que se leería como un exit 0 exitoso del marcador.
            $global:LASTEXITCODE = 99
            $rb = (& pwsh -NoProfile -File $mk -Action base -RepoDir $root 2>$null)
            if (($LASTEXITCODE -eq 0) -and $rb) { $base = ([string]$rb).Trim() }
        }
    }
}
if (-not $base) { exit 0 }

# 5. No revisar la base contra sí misma (la base puede ser un ref remoto)
if (($branch -eq $base) -or ($base -eq "origin/$branch")) { exit 0 }

# 5b. Resolver UNA vez el rango sin revisar, para el gate de docs de abajo y para la red de
# seguridad del paso 6. Antes se resolvía dentro del paso 6, donde sólo llegaba un commit sin
# trailer. El gate de docs necesita el mismo rango en TODOS los disparadores, y resolverlo dos
# veces dejaría que las dos mitades discrepen sobre qué es el slice.
$range = $null
$rangeKnown = $false
$root = (git rev-parse --show-toplevel 2>$null)
if ($root) {
    $marker = Join-Path $root ".claude/scripts/review-marker.ps1"
    if (Test-Path -LiteralPath $marker) {
        # Centinela: si `pwsh` no está en el PATH el error se traga y $LASTEXITCODE seguiría con el
        # 0 de la llamada a git de arriba, leyéndose como una salida exitosa.
        $global:LASTEXITCODE = 99
        $r = (& pwsh -NoProfile -File $marker -Action range -RepoDir $root 2>$null)
        if ($LASTEXITCODE -eq 0) {
            $rangeKnown = $true
            if ($r) { $range = ([string]$r).Trim() }
        }
    }
}

# 5c. Un slice que es ENTERAMENTE documentación no se gana un turno de review. Este bloque tiene
# esta forma por dos bugs encontrados a los golpes en un proyecto que corrió una versión anterior, y
# los dos eran falsos NEGATIVOS — el gate apagando revisiones, que es la única forma en que hace
# daño.
#
# DOC = termina en `.md` Y NADA MÁS. La primera versión trataba todo `docs/` como documentación. En
# un repo que guarda archivos no-`.md` ahí adentro — diseño congelado, fuentes de un portal, lo que
# su CLAUDE.md declare fuente de verdad del frontend — un slice de sólo frontend salía sin ninguna
# revisión y sin ningún síntoma por el cual notarlo.
#
# NO cuentan como doc aunque sean `.md` los archivos que gobiernan al agente: `.claude/**` y
# `.agents/**` (hooks, comandos y los SKILL.md — la skill tdd es donde se define el trailer
# `Slice-Close:` que este mismo hook lee), cualquier `CLAUDE.md` (las reglas duras), y
# `docs/ai-workflow/**` + `docs/agents/**`, que el CLAUDE.md declara lectura obligatoria. Romper una
# regla de ahí tiene el mismo efecto que romper código. Los anclajes son `(^|/)` y no `^`: Claude
# Code auto-carga el `CLAUDE.md` del directorio en que se trabaja, así que un `^` pelado cubría sólo
# el de la raíz y dejaba pasar todos los anidados.
#
# Se decide sobre el mismo rango que revisaría el loop, nunca sobre el último commit solo: un slice
# que ya trae código sigue disparando aunque el commit que acaba de entrar sea sólo-docs. Los
# untracked se suman porque `git diff` nunca los muestra y el paso 5 del loop MANDA escribir un test
# nuevo, que queda sin trackear hasta que alguien lo commitea — sin ellos, un slice cuyo único
# código todavía no se commiteó se leía como sólo-docs y salía sin revisar.
#
# Conservador a propósito: basta UN archivo no-doc para disparar, y un diff que no resuelve dispara
# igual (fail-open). `core.quotePath=false` es necesario: git C-quotea los paths no-ASCII y los
# envuelve en comillas literales, y esas comillas rompen el anclaje `$` de abajo, así que un `.md`
# con acento se leía como no-doc y cualquier slice de prosa que tuviera uno disparaba igual.
if ($root) {
    $govern = '(^|/)\.claude/|(^|/)\.agents/|(^|/)CLAUDE\.md$|^docs/ai-workflow/|^docs/agents/'
    $docRange = if ($range) { $range } else { "$base...HEAD" }
    $touched = @(git -C $root -c core.quotePath=false diff --name-only $docRange 2>$null)
    if ($LASTEXITCODE -eq 0) {
        $touched += @(git -C $root -c core.quotePath=false ls-files --others --exclude-standard 2>$null)
        $touched = @($touched | Where-Object { $_ })
        if ($touched.Count -gt 0) {
            $nonDoc = $touched | Where-Object { $_ -notmatch '\.md$' -or $_ -match $govern }
            if (-not $nonDoc) { exit 0 }   # slice sólo-docs: no hay nada que valga un turno de review
        }
    }
}

# 6. Un commit dispara solo cuando el cierre de slice está DECLARADO con un trailer `Slice-Close:`.
# El trailer se lee del commit recién creado, no se parsea del comando, así que funciona igual con
# `-m`, `-F archivo`, un heredoc o `--amend`.
# `git commit && git push` es UN solo comando de Bash y prende las dos banderas, así que la puerta
# del trailer sólo gobierna al commit cuando es el único disparador: el push dispara
# incondicionalmente, como lo hacía antes de A2.
if ($isCommit -and -not ($isPush -or $isPr)) {
    # El evento trae el cwd de la SESIÓN, no el directorio donde corrió el comando: sin esto, un
    # `git commit` dentro de otro repo se le atribuye a éste. Si el HEAD de este repo no es
    # reciente, el commit ocurrió en otro lado.
    #
    # La ventana es generosa a propósito. Esto es PostToolUse: corre cuando termina TODA la llamada
    # de Bash, así que `git commit ... && npm test` sella el commit minutos antes de que llegue el
    # evento, y una ventana angosta se tragaría un cierre declarado — un falso negativo que nadie
    # ve. El HEAD de un repo ajeno tiene horas o días, así que 30 min los separa igual, y el dedupe
    # por SHA de abajo evita que el mismo commit dispare dos veces. Abs() para que un reloj
    # adelantado no pase de largo el chequeo.
    $ct = (git log -1 --format=%ct 2>$null)
    if (-not $ct) { exit 0 }
    if ([Math]::Abs([DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - [int64]$ct) -gt 1800) { exit 0 }

    $body = ((git log -1 --format=%B 2>$null) -join "`n")
    if ($body -notmatch '(?m)^\s*Slice-Close:') {
        # Red de seguridad: olvidarse del trailer no puede dejar un slice gigante sin revisar. Si
        # el delta SIN REVISAR ya pasa el techo de ~400 líneas del CLAUDE.md, dispara igual.
        # `$range`, `$rangeKnown` y `$root` vienen del paso 5b, que los resuelve una sola vez para
        # esta red y para el gate de docs.
        # El contrato del marcador tiene tres salidas y colapsarlas es el bug que existe para
        # evitar. Exit 0 + vacío significa que no hay NADA sin revisar: no hay nada que la red deba
        # atrapar, así que no se dispara — si no, cada commit apenas el loop cierra limpio volvería
        # a disparar sobre la rama entera, que es justo el gasto que este slice elimina.
        if ($rangeKnown -and -not $range) { exit 0 }
        # Sin marcador (scaffold viejo), exit 2 (indeterminable) o pwsh ausente: se cae al rango de
        # la rama — disparar de más es la dirección segura.
        if (-not $range) { $range = "$base...HEAD" }
        # El techo cuenta líneas de LÓGICA: el CLAUDE.md excluye por nombre los generados, el código
        # vendored, los lockfiles y los snapshots. Contarlos hace disparar slices que sí cumplen.
        # `*` pelado y no `**`: los comodines de pathspec ya cruzan `/`, mientras que `**/nombre` no
        # matchea ese nombre en la raíz del repo — verificado, el manifest se seguía contando.
        $skipPat = @('*.bootstrap-manifest.json', 'docs/vendor/*', '*.lock', '*lock.json',
                     '*lock.yaml', '*.lockb', 'go.sum', '*.snap')
        $skip = $skipPat | ForEach-Object { ":(exclude)$_" }
        $lines = 0
        # `git -C $root` en los dos conteos: los pathspec y `ls-files` se resuelven contra el cwd del
        # proceso git, y el evento trae el cwd de la SESIÓN, que en un monorepo es un subdirectorio.
        # Sin anclar, el techo medía sólo ese subárbol y la red de seguridad desaparecía en silencio.
        $rows = @(git -C $root diff --numstat $range -- . @skip 2>$null)
        # Si el conteo es confiable siquiera. El rango de fallback `<base>...HEAD` falla de plano en
        # historias no relacionadas (`fatal: no merge base`), y con el error tragado eso se leía como
        # "0 líneas": el techo desapareciendo justo en el camino donde el marcador ya había dicho que
        # no puede determinar el rango.
        $measurable = ($LASTEXITCODE -eq 0)
        foreach ($row in $rows) {
            $cols = ($row -split "`t")
            if ($cols.Count -ge 2) {
                foreach ($n in $cols[0..1]) { if ($n -match '^\d+$') { $lines += [int]$n } }
            }
        }
        # `git diff` nunca muestra los untracked, y el paso 5 del loop ORDENA escribir un test
        # nuevo, que nace sin trackear: un slice hecho de archivos nuevos medía 0. Pero lo que
        # cuenta es untracked DESDE EL MARCADOR: el marcador guarda su propia huella en
        # `untracked:<rama>` justo para eso. Contarlos en absoluto hacía que un archivo nuevo ya
        # revisado volviera a disparar la red en cada commit posterior, para siempre.
        # La huella se indexa por la entrada ENTERA `path|sha256`, igual que la compara el propio
        # Test-NewUntracked del marcador. Indexar sólo por el path hacía que un archivo fichado con
        # una línea y crecido después a 600 se salteara para siempre: la red perdiéndose justo el
        # caso para el que existe. Un archivo sin cambios hashea igual y sigue matcheando, así que el
        # bug de "el test nuevo ya revisado vuelve a disparar para siempre" sigue muerto.
        # Y la huella sólo significa algo mientras su marcador viva: si `git gc` podó el objeto del
        # marcador, el rango vuelve a la base del slice, así que descontar contra una huella muerta
        # sería contar de menos justo cuando el rango se agrandó.
        $seen = @{}
        $mk = [string]$state["marker:$branch"]
        if ($mk) {
            git -C $root cat-file -e "$mk^{commit}" 2>$null | Out-Null
            if ($LASTEXITCODE -eq 0) {
                foreach ($e in @($state["untracked:$branch"])) { if ($e) { $seen[[string]$e] = $true } }
            }
        }
        # core.quotepath apagado para que git no C-quotee un nombre no-ASCII ("\303\261andu.txt"),
        # que fallaría el Test-Path y sumaría CERO al techo. La otra mitad del mismo problema — la
        # decodificación — se resuelve una sola vez al tope de este archivo.
        $others = @(git -C $root -c core.quotepath=false ls-files --others --exclude-standard 2>$null |
                    Where-Object { $_ })
        foreach ($f in $others) {
            # Las mismas exclusiones de arriba: se aplicaban sólo a la mitad trackeada, así que un
            # `package-lock.json` sin trackear disparaba sobre un slice que sí cumple la regla.
            if (@($skipPat | Where-Object { $f -like $_ }).Count) { continue }
            $p = Join-Path $root $f
            if (-not (Test-Path -LiteralPath $p)) { continue }
            # Los binarios no son líneas de lógica, y `git diff --numstat` ya reporta `-` para ellos
            # del lado trackeado, así que saltearlos acá deja las dos mitades consistentes. Además
            # evita que una captura de 12 MB cueste segundos en CADA git commit (medido: 4,9 s).
            # La ventana es de 8000 bytes porque es lo que escanea el propio git buscando un NUL; con
            # 4096, un archivo cuyo primer NUL cae más allá contaba como texto e inflaba el techo,
            # mientras el comentario de arriba afirmaba que las dos mitades coincidían.
            $buf = New-Object byte[] 8000
            $fs = $null
            try {
                $fs = [IO.File]::OpenRead($p)
                $n  = $fs.Read($buf, 0, 8000)
            } catch { continue } finally { if ($fs) { $fs.Close() } }
            if ([Array]::IndexOf($buf, [byte]0, 0, $n) -ge 0) { continue }
            # Hasheado igual que lo hace el marcador, para que las entradas comparen byte a byte.
            $h = ""
            try { $h = (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash } catch { }
            if ($seen[("{0}|{1}" -f $f, $h)]) { continue }
            $lines += @(Get-Content -LiteralPath $p -TotalCount 401 2>$null).Count
        }
        if ($measurable -and $lines -le 400) { exit 0 }
    }
}

# 7. Dedupe por SHA del HEAD del branch (el estado ya se cargó en el paso 3a)
$sha = (git rev-parse HEAD 2>$null)
if (-not $sha) { exit 0 }
if ($state[$branch] -eq $sha) { exit 0 }     # ya disparado para este commit
$state[$branch] = $sha
# No se escribe si falló la cuarentena de un estado ilegible: ver el paso 3a. Disparar sin dejar la
# entrada de dedupe es inofensivo; pisar un archivo que no se pudo respaldar, no.
if ($stateWritable) {
    $json = ([pscustomobject]$state) | ConvertTo-Json -Depth 6
    [IO.File]::WriteAllText($statePath, $json, (New-Object Text.UTF8Encoding($false)))
}

# 8. Inyectar la instrucción a Claude
$msg = "Cerraste un commit/slice en el branch '$branch' (base '$base'). " +
       "Ejecuta /review-loop AHORA sobre el diff del slice. No preguntes si querés correrlo: corrélo. " +
       "El rango sale del marcador ('.claude/scripts/review-marker.ps1 -Action range'), no del branch entero: " +
       "solo si ese script no existe, usá 'git diff $base...HEAD'. " +
       "No marques el trabajo como completo hasta que el loop cierre (cero hallazgos de severidad media/alta, o el tope de 5 turnos)."
@{ hookSpecificOutput = @{ hookEventName = "PostToolUse"; additionalContext = $msg } } |
    ConvertTo-Json -Depth 4 -Compress
exit 0
