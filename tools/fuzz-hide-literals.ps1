# tools/fuzz-hide-literals.ps1 — ¿alguna rama de la gramática de PowerShell de `Hide-Literals` es
# observable en lo que el hook DECIDE? Correr antes de tocar el walker del paso 2 de
# `.claude/hooks/review-loop-trigger.ps1`:
#
#     pwsh -NoProfile -File tools/fuzz-hide-literals.ps1
#
# Por qué existe: una rama cuyo mutante sobrevive puede ser (a) código muerto que conviene sacar,
# (b) una rama observable a la que le falta un test, o (c) fidelidad de gramática que se mantiene a
# propósito y se declara. Distinguirlas a ojo no funcionó — ver la lección de abajo —, así que se
# miden por fuerza bruta.
#
# LECCIÓN, y la razón de que se mida en DOS canales. La primera versión de esta búsqueda miraba sólo
# las tres banderas del paso 2 ($isPr/$isPush/$isCommit) y concluyó que el escape de afuera del
# literal y el backtick dentro de comillas dobles no eran observables. Era falso: las dos son
# observables por el OTRO lector del enmascarado, la lectura de `--base` del paso 4, que la búsqueda
# no modelaba. Las dos sobrevivían a su mutante con la suite entera en verde. Antes de declarar una
# rama "no observable", chequeá contra qué se midió.
#
# `Hide-Literals` se EXTRAE del hook real por parseo, nunca se copia acá: una copia se desincroniza y
# la medición pasa a hablar de otro código. Si el hook cambia de forma, esa parte falla ruidoso (las
# tres anclas se verifican y tiran).
#
# Sus CONSUMIDORES no: `$fold`, `Decidir` (los pasos 2 y 4) y `Cerrado` son copias a mano del hook,
# sin guarda. Si alguien mueve el regex de plegado, el predicado del recomputo crudo o la lectura de
# `--base`, este script sigue en verde midiendo un hook que ya no existe. Revisalos a mano cuando
# toques esas partes; es el límite conocido de esta herramienta, no un descuido.
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path $PSScriptRoot -Parent
$hook = Join-Path $repoRoot 'skills\bootstrap-personal-project\assets\scaffold\.claude\hooks\review-loop-trigger.ps1'
if (-not (Test-Path -LiteralPath $hook)) { throw "no se encontró el hook: $hook" }
$src = [IO.File]::ReadAllText($hook)

$ini = $src.IndexOf('function Hide-Literals')
if ($ini -lt 0) { throw "no se encontró 'function Hide-Literals' en $hook" }
$fin = $src.IndexOf("`n}", $ini)
if ($fin -lt 0) { throw "no se encontró el cierre de Hide-Literals en $hook" }
$fn = $src.Substring($ini, $fin - $ini + 2)

# Las tres ramas que bash no tiene. Cada ancla se verifica: un `-replace` que no matchea no cambia
# nada y sale con exit 0, y la corrida entera pasaría a comparar la función consigo misma — verde
# vacío. Es el modo de falla clásico de una edición por patrón, así que acá aborta.
$ramas = @(
  @{ Id = 'esc-afuera'; Desc = 'el backtick es el escape AFUERA del literal'
     Ancla = '$esc = if ($psQuoting) { ''`'' } else { ''\'' }'
     Mutante = '$esc = if ($psQuoting) { [char]0 } else { ''\'' }' },
  @{ Id = 'comilla-duplicada'; Desc = 'la comilla DUPLICADA (`""` / `''''`) no cierra el literal'
     Ancla = 'if ($s[$j] -eq $q -and $j + 1 -lt $s.Length -and $s[$j + 1] -eq $q) { $j += 2; continue }'
     Mutante = '' },
  @{ Id = 'backtick-interno'; Desc = 'el backtick escapa ADENTRO de comillas dobles'
     Ancla = 'if ($q -eq ''"'' -and $s[$j] -eq ''`'' -and $j + 1 -lt $s.Length) { $j += 2; continue }'
     Mutante = '' }
)

Invoke-Expression $fn                                   # la versión real, tal cual vive en el hook
foreach ($r in $ramas) {
  if (-not $fn.Contains($r.Ancla)) { throw "ancla no encontrada para '$($r.Id)': el hook cambió de forma, actualizá este script" }
  Invoke-Expression (($fn.Replace($r.Ancla, $r.Mutante)) -replace 'function Hide-Literals', "function HL-$($r.Id)")
}

# Los dos consumidores del enmascarado, copiados del hook: el paso 2 (las tres banderas, con el
# recomputo crudo) y el paso 4 (la lectura de `--base`).
$fold = '(?i)\bgit\s+(?:(?:-C|-c|--git-dir|--work-tree)(?:\s+|=)\S+\s+|--no-pager\s+|--paginate\s+)+'
function Decidir([string]$cmd, [string]$scan) {
    $f  = $scan -replace $fold, 'git '
    $pr = $f -match '\bgh\s+pr\s+create\b'; $pu = $f -match '\bgit\s+push\b'; $co = $f -match '\bgit\s+commit(?![\w-])'
    if ($cmd.Contains('$(') -or $cmd.Contains('`')) {
        $rf = $cmd -replace $fold, 'git '
        $pr = $pr -or ($rf -match '\bgh\s+pr\s+create\b')
        $pu = $pu -or ($rf -match '\bgit\s+push\b')
        $co = $co -or ($rf -match '\bgit\s+commit(?![\w-])')
    }
    # El hook sale acá cuando no hay disparador. Sin esto, la comparación seguiría al paso 4 para
    # comandos que el hook descarta, y el contraejemplo que este script imprime sería uno que la
    # conducta real nunca alcanza: evidencia falsa, que es justo lo que la herramienta viene a evitar.
    if (-not ($pr -or $pu -or $co)) { return 'sin-disparador' }
    # Paso 4: la bandera se ubica sobre $scan y el valor se lee de $cmd en el mismo índice. Va
    # DENTRO de `if ($isPr)`, como en el hook: `--base` sólo se lee para un `gh pr create`.
    $base = ''
    if ($pr) {
        $bm = [regex]::Match($scan, '--base(?:\s+|=)')
        if ($bm.Success) {
            $tail = $cmd.Substring($bm.Index + $bm.Length)
            if ($tail -match '^(?:''([^'']*)''|"([^"]*)"|([^\s;&|]+))') {
                foreach ($g in 1, 2, 3) { if ($matches[$g]) { $base = $matches[$g]; break } }
            }
        }
    }
    return "$pr|$pu|$co|$base"
}

# Piezas, no caracteres: sin un token disparador real ninguna bandera se mueve, y sin `--base` el
# paso 4 no tiene nada que leer.
$piezas = @('"', "'", '`', '\', 'git push', 'git commit', 'gh pr create', '--base develop', 'x', ' ')
$profundidad = 5      # 10 piezas => 111.110 comandos. Medido: 14 s.

$hallazgos = @{}; foreach ($r in $ramas) { $hallazgos[$r.Id] = $null }
$total = 0; $bienFormados = 0

# "Bien formado" = la gramática REAL cierra todos sus literales. Un comando roto no es algo que
# PowerShell haya podido ejecutar, así que una diferencia que sólo aparece ahí no dice nada sobre
# lo que el hook ve en la vida real.
function Cerrado([string]$s) {
    $n = $s.Length; $i = 0
    while ($i -lt $n) {
        $q = $s[$i]
        if ($q -eq '`') { $i += 2; continue }
        if ($q -ne "'" -and $q -ne '"') { $i++; continue }
        $j = $i + 1
        while ($j -lt $n) {
            if ($s[$j] -eq $q -and $j + 1 -lt $n -and $s[$j + 1] -eq $q) { $j += 2; continue }
            if ($q -eq '"' -and $s[$j] -eq '`' -and $j + 1 -lt $n) { $j += 2; continue }
            if ($s[$j] -eq $q) { break }
            $j++
        }
        if ($j -ge $n) { return $false }
        $i = $j + 1
    }
    return $true
}

function Probar([string]$s) {
    $script:total++
    if (-not (Cerrado $s)) { return }
    $script:bienFormados++
    $ref = Decidir $s (Hide-Literals $s $true)
    foreach ($r in $script:ramas) {
        if ($null -ne $script:hallazgos[$r.Id]) { continue }
        $mut = Decidir $s (& "HL-$($r.Id)" $s $true)
        if ($mut -ne $ref) { $script:hallazgos[$r.Id] = [pscustomobject]@{ Cmd = $s; Real = $ref; Mutante = $mut } }
    }
}
function Generar([string]$pref, [int]$resto) {
    if ($resto -eq 0) { Probar $pref; return }
    foreach ($p in $script:piezas) { Generar ($pref + $p) ($resto - 1) }
}

foreach ($n in 1..$profundidad) { Generar '' $n }

# SEMILLAS. Un contraejemplo ÚTIL tiene que ser un comando que el hook no descarte antes: necesita
# un disparador (`gh pr create`) Y el `--base`, porque el canal por el que estas ramas se observan es
# el paso 4. Con eso ya gastadas dos piezas, la forma de comillas que activa la rama no entra en el
# barrido. Sin estas semillas el script diría "sin contraejemplo" para una rama que SÍ es observable,
# que es la conclusión de más que esta herramienta existe para no repetir. Son los comandos de los dos
# fixtures `gh pr create` de la suite: acá sirven de regresión de la medición, no de cobertura.
$semillas = @(
  'gh pr create --title `"arreglo de comillas`" --base develop',
  'gh pr create --title "arreglo de `"comillas`" varias" --base develop'
)
foreach ($s in $semillas) {
    if (-not (Cerrado $s)) { throw "semilla mal formada, revisala: $s" }
    Probar $s
}

Write-Host "(barrido ciego hasta $profundidad piezas, mas 2 semillas: un contraejemplo util necesita disparador + --base, y eso no entra en el barrido)"
Write-Host "alfabeto: $($piezas.Count) piezas, hasta $profundidad de largo"
Write-Host "comandos probados: $total (incluye las 2 semillas)   bien formados: $bienFormados"
Write-Host ""
$observables = 0
foreach ($r in $ramas) {
    $h = $hallazgos[$r.Id]
    if ($h) {
        $observables++
        Write-Host "OBSERVABLE  $($r.Id) — $($r.Desc)"
        Write-Host "   comando : $($h.Cmd)"
        Write-Host "   real    : $($h.Real)"
        Write-Host "   mutante : $($h.Mutante)    (pr|push|commit|base)"
        Write-Host "   -> necesita un test que la fije, o el mutante sobrevive con la suite en verde."
    } else {
        Write-Host "sin contraejemplo  $($r.Id) — $($r.Desc)"
    }
}
Write-Host ""
Write-Host "ramas con contraejemplo: $observables de $($ramas.Count)"
Write-Host "Ojo: 'sin contraejemplo' es 'no lo encontró ESTA búsqueda', no 'no existe'. El alfabeto no"
Write-Host "tiene here-strings (@\"...\"@), ni el token --%, ni rutas UNC."
