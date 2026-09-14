# tests/skills-lock.tests.ps1 — runner sin Pester. Correr: pwsh -NoProfile -File tests/skills-lock.tests.ps1
#
# Cubre tools/skills-lock.ps1 — el módulo M2 del PRD de bootstrap-v2: sellar y verificar el lockfile
# de las skills que vinieron de `mattpocock/skills`.
#
# POR QUÉ EXISTE: el lockfile anterior declaraba un `computedHash` por skill que **nunca fue computado
# por nada**. Medido el 2026-08-28 (ADR-0005): 24.738 hashes probados contra toda la historia publicada
# de upstream, cero coincidencias. Los nueve eran fabricados, sobrevivieron dos meses sin que nada los
# tocara —precisamente porque nada los leía— y la premisa falsa que sostenían ("no hay base para un
# merge de tres vías") bloqueó la actualización de las skills durante semanas. ADR-0005 decidió: o el
# lockfile tiene un test que recomputa y falla si miente, o se borra. Este archivo es ese test.
$ErrorActionPreference = "Stop"
$repo = Split-Path $PSScriptRoot -Parent
$tool = Join-Path $repo "tools/skills-lock.ps1"
$script:failures = 0
$script:checks   = 0

function Assert($cond, $msg) {
  $script:checks++
  if ($cond) { Write-Host "ok:   $msg" } else { Write-Host "FAIL: $msg"; $script:failures++ }
}

# Cantidad EXACTA de aserciones. Se actualiza a mano al agregar o quitar checks. Sin este número un
# mutante que BORRA asserts sale en verde: 0 fails de 0 checks también es "0 fail".
$ExpectedChecks = 70

if (-not (Test-Path -LiteralPath $tool)) {
  Write-Host "FAIL: no existe la herramienta en $tool"; exit 1
}
# El módulo M1, para poder comparar contra el hash canónico sin reimplementarlo acá: una segunda
# implementación del hash en el test comprobaría que las dos coinciden entre sí, no que sellan bien.
. (Join-Path $repo "tools/normalized-hash.ps1")

# Directorio propio. Se limpia SOLO el directorio propio, sin barrer `$env:TEMP` por prefijo: barrer
# por glob es lo que hacía que dos suites concurrentes se borraran los workspaces entre sí.
$script:tmp = Join-Path ([IO.Path]::GetTempPath()) ("sl-run-$PID-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $script:tmp -Force | Out-Null

# Corre la herramienta como proceso aparte para observar EL EXIT CODE, que es la interfaz que usa la
# suite. Dot-sourcearla la mediría por dentro y dejaría pasar un exit code equivocado.
function Run-Tool([string[]]$toolArgs) {
  $out = & pwsh -NoProfile -File $tool @toolArgs 2>&1 | Out-String
  return [pscustomobject]@{ Code = $LASTEXITCODE; Out = $out }
}

# La misma corrida, pero con la cultura del proceso forzada. `-File` no deja fijarla antes de que
# arranque el script, así que se entra por `-Command` y se re-emite el exit code del script.
function Run-ToolInCulture([string]$culture, [string[]]$toolArgs) {
  # Los nombres de parámetro van SIN comillas: `'-Action'` entre comillas es un valor posicional, el
  # binding falla y el script no corre. Y `$LASTEXITCODE` se siembra en 99 para que un script que no
  # llegó a correr no salga con el 0 de un `exit $null`.
  $quoted = ($toolArgs | ForEach-Object { if ($_ -like '-*') { $_ } else { "'" + ($_ -replace "'", "''") + "'" } }) -join ' '
  $cmd = "[cultureinfo]::CurrentCulture = [cultureinfo]::new('$culture'); `$global:LASTEXITCODE = 99; & '$tool' $quoted; exit `$LASTEXITCODE"
  $out = & pwsh -NoProfile -Command $cmd 2>&1 | Out-String
  return [pscustomobject]@{ Code = $LASTEXITCODE; Out = $out }
}

# Escribe un árbol sintético: <raíz>/.agents/skills/<skill>/<archivo>.
# $skills es un hashtable  nombre -> (hashtable  rutaRelativa -> contenido).
function New-Tree([string]$root, [hashtable]$skills) {
  foreach ($name in $skills.Keys) {
    foreach ($rel in $skills[$name].Keys) {
      $p = Join-Path $root ".agents/skills/$name/$rel"
      New-Item -ItemType Directory -Path (Split-Path $p -Parent) -Force | Out-Null
      # WriteAllText y no Set-Content: Set-Content agrega un salto final propio y reescribe el EOL,
      # y estos casos miden exactamente el contenido que se sella.
      [IO.File]::WriteAllText($p, $skills[$name][$rel], [Text.UTF8Encoding]::new($false))
    }
  }
}

# El `skill-bases.json` que produce tools/recover-skill-bases.py, en versión mínima: la herramienta
# solo lee `upstream.url`, `upstream.head` y, por skill, `name` / `base` / `upstreamRelation` /
# `upstreamHead.path`. El fixture trae los tres estados que el lockfile no puede colapsar.
function New-Bases([string]$path, [scriptblock]$mutar) {
  $bases = @{
    upstream = @{ url = "https://github.com/ejemplo/skills.git"; head = "0123456789abcdef0123456789abcdef01234567" }
    skills   = @(
      @{ name = "viva"; status = "recovered"; upstreamRelation = "in-upstream-head"
         upstreamHead = @{ status = "renamed"; path = "skills/nuevo/viva/SKILL.md" }
         base = @{ blob = "aaaa111"; upstreamPath = "viejo/viva/SKILL.md"; commit = "c0ffee1"; commitDate = "2026-03-26T14:28:04Z" } },
      @{ name = "huerfana"; status = "recovered"; upstreamRelation = "gone-from-upstream-head"
         upstreamHead = @{ status = "gone"; path = $null }
         base = @{ blob = "bbbb222"; upstreamPath = "viejo/huerfana/SKILL.md"; commit = "c0ffee2"; commitDate = "2026-05-06T09:26:48+01:00" } },
      @{ name = "propia"; status = "unmatched"; upstreamRelation = "no-match-above-threshold"; base = $null }
    )
  }
  # Para los casos que necesitan una entrada que el productor emite pero el fixture base no trae.
  if ($mutar) { & $mutar $bases }
  [IO.File]::WriteAllText($path, ($bases | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
}

# Una raíz sintética recién sellada, con las tres skills y los tres estados de upstream. Tira si el
# sellado falla: un fixture roto que devolviera una raíz sin lockfile haría pasar en verde a los
# casos rojos por el motivo equivocado.
function New-SealedRoot([string]$nombre) {
  $r = Join-Path $script:tmp $nombre
  New-Tree $r @{
    viva     = @{ "SKILL.md" = "cuerpo de viva`n" }
    huerfana = @{ "SKILL.md" = "cuerpo de huerfana`n" }
    propia   = @{ "SKILL.md" = "cuerpo de propia`n" }
  }
  $b = Join-Path $script:tmp "bases-$nombre.json"
  New-Bases $b
  $res = Run-Tool @("-Action", "Seal", "-Repo", $r, "-Bases", $b)
  if ($res.Code -ne 0) { throw "el fixture $nombre no sello: $($res.Out)" }
  return $r
}

# Una raíz con la forma del repo real: la raíz misma más el scaffold de una skill bootstrap-*, con
# el MISMO árbol de skills en las dos (que es lo que garantiza mirror.tests.ps1 en el repo).
function New-MultiRoot([string]$nombre) {
  $r = Join-Path $script:tmp $nombre
  $tree = @{
    viva     = @{ "SKILL.md" = "cuerpo de viva`n" }
    huerfana = @{ "SKILL.md" = "cuerpo de huerfana`n" }
    propia   = @{ "SKILL.md" = "cuerpo de propia`n" }
  }
  New-Tree $r $tree
  New-Tree (Join-Path $r "skills/bootstrap-x-project/assets/scaffold") $tree
  $b = Join-Path $script:tmp "bases-$nombre.json"
  New-Bases $b
  $res = Run-Tool @("-Action", "Seal", "-Repo", $r, "-Bases", $b)
  if ($res.Code -ne 0) { throw "el fixture $nombre no sello: $($res.Out)" }
  return $r
}

function Read-Lock([string]$root) {
  return ([IO.File]::ReadAllText((Join-Path $root "skills-lock.json")) | ConvertFrom-Json -AsHashtable)
}

try {

  # --- A. Tracer: sellar desde las bases y después verificar da verde --------------------------
  # Es el AC "sellar y después verificar da verde". Por sí solo NO prueba que la verificación mire
  # nada (una que siempre devuelva 0 lo pasa); eso lo fuerzan los casos rojos de más abajo.
  $rootA = Join-Path $script:tmp "A"
  New-Tree $rootA @{
    viva     = @{ "SKILL.md" = "cuerpo de viva`n" }
    huerfana = @{ "SKILL.md" = "cuerpo de huerfana`n" }
    propia   = @{ "SKILL.md" = "cuerpo de propia`n" }
  }
  $basesA = Join-Path $script:tmp "bases-A.json"
  New-Bases $basesA

  $sellado = Run-Tool @("-Action", "Seal", "-Repo", $rootA, "-Bases", $basesA)
  Assert ($sellado.Code -eq 0) "sellar desde skill-bases.json sale con codigo 0 (salida: $($sellado.Out))"

  $verificado = Run-Tool @("-Action", "Verify", "-Repo", $rootA)
  Assert ($verificado.Code -eq 0) "verificar lo recien sellado sale con codigo 0 (salida: $($verificado.Out))"

  # --- B. La verificación se pone en ROJO -----------------------------------------------------
  # Cada caso muta UNA cosa sobre una raíz recién sellada propia. Se asertan dos cosas: el exit code
  # (la interfaz que usa la suite) y un fragmento que ATRIBUYE el problema al archivo correcto —
  # contar problemas sin atribuirlos deja pasar una verificación que se queja de otra cosa.
  $rootB1 = New-SealedRoot "B1"
  [IO.File]::WriteAllText((Join-Path $rootB1 ".agents/skills/viva/SKILL.md"), "otro cuerpo`n")
  $r = Run-Tool @("-Action", "Verify", "-Repo", $rootB1)
  Assert ($r.Code -eq 1) "alterar el contenido de una skill sellada sale con codigo 1"
  Assert ($r.Out -match 'viva/SKILL\.md') "y el reporte nombra el archivo alterado (salida: $($r.Out))"

  # El AC lo separa en dos, pero es la MISMA comparación mirada desde los dos lados: en B1 se movió
  # el archivo, acá se mueve el lockfile. Vale la pena igual, porque es el caso que ADR-0005
  # describe: una entrada escrita a mano que afirma un hash que nadie computó.
  $rootB2 = New-SealedRoot "B2"
  $lockB2 = Join-Path $rootB2 "skills-lock.json"
  [IO.File]::WriteAllText($lockB2, ([IO.File]::ReadAllText($lockB2) -replace '"SKILL\.md": "[0-9a-f]{64}"', '"SKILL.md": "0000000000000000000000000000000000000000000000000000000000000000"'))
  $r = Run-Tool @("-Action", "Verify", "-Repo", $rootB2)
  Assert ($r.Code -eq 1) "una entrada cuyo hash miente sale con codigo 1"

  $rootB3 = New-SealedRoot "B3"
  Remove-Item -LiteralPath (Join-Path $rootB3 ".agents/skills/propia/SKILL.md") -Force
  $r = Run-Tool @("-Action", "Verify", "-Repo", $rootB3)
  Assert ($r.Code -eq 1) "un archivo sellado que ya no esta en el arbol sale con codigo 1"
  Assert ($r.Out -match 'propia/SKILL\.md' -and $r.Out -match 'no esta en el arbol') `
    "y el reporte dice que falta en el arbol, no que el hash no coincide (salida: $($r.Out))"

  # El caso `tdd/mocking.md` del handoff: un archivo NUEVO dentro de una skill sellada. Si la
  # verificación solo recorre lo que el lockfile lista, este archivo entra sin que nada lo mire.
  $rootB4 = New-SealedRoot "B4"
  [IO.File]::WriteAllText((Join-Path $rootB4 ".agents/skills/viva/extra.md"), "archivo nuevo`n")
  $r = Run-Tool @("-Action", "Verify", "-Repo", $rootB4)
  Assert ($r.Code -eq 1) "un archivo nuevo dentro de una skill sellada sale con codigo 1"
  Assert ($r.Out -match 'viva/extra\.md' -and $r.Out -match 'no esta en el lockfile') `
    "y el reporte lo nombra como ausente del lockfile (salida: $($r.Out))"

  $rootB5 = New-SealedRoot "B5"
  New-Item -ItemType Directory -Path (Join-Path $rootB5 ".agents/skills/nueva") -Force | Out-Null
  [IO.File]::WriteAllText((Join-Path $rootB5 ".agents/skills/nueva/SKILL.md"), "skill sin entrada`n")
  $r = Run-Tool @("-Action", "Verify", "-Repo", $rootB5)
  Assert ($r.Code -eq 1) "una skill presente en el repo pero ausente del lockfile sale con codigo 1"
  Assert ($r.Out -match 'nueva' -and $r.Out -match 'no esta en el lockfile') `
    "y el reporte nombra la skill sin entrada (salida: $($r.Out))"

  $rootB6 = New-SealedRoot "B6"
  Remove-Item -LiteralPath (Join-Path $rootB6 ".agents/skills/propia") -Recurse -Force
  $r = Run-Tool @("-Action", "Verify", "-Repo", $rootB6)
  Assert ($r.Code -eq 1) "una entrada del lockfile cuya skill ya no esta en el arbol sale con codigo 1"
  Assert ($r.Out -match 'propia' -and $r.Out -match 'no esta en el arbol') `
    "y el reporte dice que la skill falta en el arbol (salida: $($r.Out))"

  # --- C. Los tres estados de upstream, sin colapsar ------------------------------------------
  # Colapsar `upstream-huerfano` (upstream la borró, pero la recuperación por similitud SÍ encontró
  # su commit base) dentro de `fork-propio` (nunca hubo upstream) tira justo el dato que ADR-0005
  # costó 24.738 hashes recuperar. Por eso se aserta el estado Y el commit base de cada uno.
  $rootC = New-SealedRoot "C"
  $docC = Read-Lock $rootC

  Assert ($docC.skills['propia'].upstreamState -eq 'fork-propio') "una skill sin upstream queda marcada como fork-propio"
  Assert ($null -eq $docC.skills['propia'].base) "el fork propio no exige commit base: queda en null"
  Assert ($null -eq $docC.skills['propia'].source) "y tampoco declara origen upstream"

  Assert ($docC.skills['viva'].upstreamState -eq 'upstream-vivo') "una skill que sigue en el HEAD de upstream queda como upstream-vivo"
  Assert ($docC.skills['viva'].base.commit -eq 'c0ffee1') "y transcribe el commit base que la recuperacion encontro"
  # El blob es lo que el próximo merge de tres vías usa para traer el contenido de la base. Los valores
  # del fixture son todos distintos entre sí, para que transcribir un campo en lugar de otro se note.
  Assert ($docC.skills['viva'].base.blob -eq 'aaaa111') "y el blob base, no otro campo de la base"
  Assert ($docC.skills['viva'].source -eq 'https://github.com/ejemplo/skills.git') "y declara el origen upstream"
  Assert ($docC.skills['viva'].base.upstreamPath -eq 'viejo/viva/SKILL.md') "y el path que tenia EN el commit base"
  # El rename queda registrado por el PAR de paths: dónde vivía en la base y dónde vive en el HEAD.
  # Sin el segundo, el próximo merge compararía contra un path que ya no existe.
  Assert ($docC.skills['viva'].upstreamHeadPath -eq 'skills/nuevo/viva/SKILL.md') "y el path donde vive hoy en upstream, que es el renombre"

  Assert ($docC.skills['huerfana'].upstreamState -eq 'upstream-huerfano') "una skill que upstream borro queda como upstream-huerfano, no como fork propio"
  Assert ($docC.skills['huerfana'].base.commit -eq 'c0ffee2') "y CONSERVA su commit base: es lo que se perderia al colapsarla en fork-propio"
  Assert ($docC.skills['huerfana'].base.blob -eq 'bbbb222') "y su blob base"
  Assert ($null -eq $docC.skills['huerfana'].upstreamHeadPath) "pero no declara path en el HEAD, porque ahi ya no esta"

  # El fixture trae `2026-05-06T09:26:48+01:00`. El lockfile lo guarda en UTC: `ConvertFrom-Json`
  # convierte las fechas a la zona LOCAL, así que sin normalizar, la misma corrida en otra máquina
  # produciría otros bytes. La aserción está escrita en UTC justamente para no depender de la zona
  # de quien corra la suite.
  # Se aserta sobre el TEXTO del lockfile y no sobre el objeto releído: `ConvertFrom-Json` vuelve a
  # coaccionar la fecha a `[datetime]` al leerla, así que comparar el objeto mediría el parser del
  # test, no lo que quedó escrito en disco.
  $textoC = [IO.File]::ReadAllText((Join-Path $rootC "skills-lock.json"))
  Assert ($textoC -match '"commitDate": "2026-05-06T08:26:48Z"') `
    "la fecha del commit base queda escrita en UTC canonica, no en la zona de la maquina que sello"

  Assert ($docC.upstream.url -eq 'https://github.com/ejemplo/skills.git') "el lockfile registra la url de upstream a nivel documento"
  Assert ($docC.upstream.head -eq '0123456789abcdef0123456789abcdef01234567') "y el HEAD de upstream contra el que se midio"

  # El AC del handoff: sellar solo el SKILL.md dejaría pasar en verde una edición de `tdd/mocking.md`.
  $rootC2 = Join-Path $script:tmp "C2"
  New-Tree $rootC2 @{
    viva     = @{ "SKILL.md" = "cuerpo`n"; "mocking.md" = "anexo`n"; "sub/nota.md" = "anidado`n" }
    huerfana = @{ "SKILL.md" = "h`n" }
    propia   = @{ "SKILL.md" = "p`n" }
  }
  $basesC2 = Join-Path $script:tmp "bases-C2.json"; New-Bases $basesC2
  $r = Run-Tool @("-Action", "Seal", "-Repo", $rootC2, "-Bases", $basesC2)
  Assert ($r.Code -eq 0) "sella un arbol con varios archivos por skill (salida: $($r.Out))"
  $docC2 = Read-Lock $rootC2
  # Sin re-ordenar: se aserta el orden CON EL QUE QUEDÓ SELLADO, que tiene que ser ordinal y no
  # cultural. Con `Sort-Object` (cultural, es-AR) "mocking.md" iría antes que "SKILL.md" y el
  # lockfile dejaría de ser byte-idéntico entre máquinas con culturas distintas.
  $clavesC2 = @($docC2.skills['viva'].files.Keys) -join ','
  Assert ($clavesC2 -eq 'SKILL.md,mocking.md,sub/nota.md') `
    "sella TODOS los archivos de la skill en orden ordinal, no solo el SKILL.md (sellados: $clavesC2)"

  # --- C3/C4. El sellado se niega cuando las bases y el arbol no describen el mismo conjunto ----
  # Sin esto, sellar produce un lockfile que falla su propia verificación un segundo después.
  $rootC3 = Join-Path $script:tmp "C3"
  New-Tree $rootC3 @{
    viva     = @{ "SKILL.md" = "v`n" }
    huerfana = @{ "SKILL.md" = "h`n" }
    propia   = @{ "SKILL.md" = "p`n" }
    intrusa  = @{ "SKILL.md" = "sin entrada en las bases`n" }
  }
  $basesC3 = Join-Path $script:tmp "bases-C3.json"; New-Bases $basesC3
  $r = Run-Tool @("-Action", "Seal", "-Repo", $rootC3, "-Bases", $basesC3)
  # Se asertan exit code Y mensaje: sin el mensaje, un crash por null-reference también daría
  # distinto de 0 y la aserción pasaría sin que exista el chequeo (pasó, antes de agregarlo).
  Assert ($r.Code -ne 0) "sellar con una skill del arbol ausente de las bases NO sale con codigo 0"
  Assert ($r.Out -match "intrusa" -and $r.Out -match "no se sello nada") `
    "y explica cual es la skill sin entrada, sin sellar nada (salida: $($r.Out))"
  Assert (-not (Test-Path -LiteralPath (Join-Path $rootC3 "skills-lock.json"))) `
    "y no deja un lockfile a medias escrito"

  $rootC4 = Join-Path $script:tmp "C4"
  New-Tree $rootC4 @{ viva = @{ "SKILL.md" = "v`n" }; huerfana = @{ "SKILL.md" = "h`n" } }
  $basesC4 = Join-Path $script:tmp "bases-C4.json"; New-Bases $basesC4
  $r = Run-Tool @("-Action", "Seal", "-Repo", $rootC4, "-Bases", $basesC4)
  Assert ($r.Code -ne 0) "sellar con una skill de las bases ausente del arbol NO sale con codigo 0"
  # "no esta en el arbol" solo NO alcanza: la verificación posterior al sellado dice lo mismo, así que
  # sin la guarda el test pasaría igual y dejaría escrito el lockfile. Lo que distingue a la guarda es
  # que se niega ANTES de escribir.
  Assert ($r.Out -match "propia" -and $r.Out -match "no esta en el arbol" -and $r.Out -match "no se sello nada") `
    "y nombra la skill de las bases que el arbol no tiene, sin sellar nada (salida: $($r.Out))"
  Assert (-not (Test-Path -LiteralPath (Join-Path $rootC4 "skills-lock.json"))) `
    "y no deja un lockfile a medias escrito"

  # --- C5/C6. El sellado se niega a transcribir una base que la recuperación no resolvió ---------
  # recover-skill-bases.py emite `unresolved-commit` (hay blob, pero ningún commit fechado que citar) y
  # empates entre cuerpos distintos (`tieOnIdenticalBodies: false`, "la base la decide un humano").
  # Sellarlos como `upstream-vivo` dejaría en el lockfile una base que nadie resolvió: la afirmación no
  # verificada de ADR-0005.
  $rootC5 = Join-Path $script:tmp "C5"
  New-Tree $rootC5 @{ viva = @{ "SKILL.md" = "v`n" }; huerfana = @{ "SKILL.md" = "h`n" }; propia = @{ "SKILL.md" = "p`n" } }
  $basesC5 = Join-Path $script:tmp "bases-C5.json"
  New-Bases $basesC5 { param($b) $b.skills[0].status = "unresolved-commit"; $b.skills[0].base.commit = $null; $b.skills[0].base.commitDate = $null }
  $r = Run-Tool @("-Action", "Seal", "-Repo", $rootC5, "-Bases", $basesC5)
  Assert ($r.Code -eq 1) "sellar una base con status unresolved-commit sale con codigo 1 (salida: $($r.Out))"
  Assert ($r.Out -match "'viva'" -and $r.Out -match "unresolved-commit" -and $r.Out -match "no se sello nada") `
    "y nombra la skill y su status, sin sellar nada (salida: $($r.Out))"
  Assert (-not (Test-Path -LiteralPath (Join-Path $rootC5 "skills-lock.json"))) "y no escribe el lockfile"

  $rootC6 = Join-Path $script:tmp "C6"
  New-Tree $rootC6 @{ viva = @{ "SKILL.md" = "v`n" }; huerfana = @{ "SKILL.md" = "h`n" }; propia = @{ "SKILL.md" = "p`n" } }
  $basesC6 = Join-Path $script:tmp "bases-C6.json"
  New-Bases $basesC6 { param($b) $b.skills[1].base.tieOnIdenticalBodies = $false }
  $r = Run-Tool @("-Action", "Seal", "-Repo", $rootC6, "-Bases", $basesC6)
  Assert ($r.Code -eq 1) "sellar una base empatada entre cuerpos distintos sale con codigo 1 (salida: $($r.Out))"
  Assert ($r.Out -match "'huerfana'" -and $r.Out -match "empate" -and $r.Out -match "no se sello nada") `
    "y nombra la skill empatada, sin sellar nada (salida: $($r.Out))"
  Assert (-not (Test-Path -LiteralPath (Join-Path $rootC6 "skills-lock.json"))) "y no escribe el lockfile"

  # --- C7. La fecha canónica no depende de la cultura de la máquina que sella -------------------
  # Un formato personalizado sin InvariantCulture usa el calendario de la cultura: en th-TH el año sale
  # 2569. Las cuatro copias saldrían iguales entre sí —se escriben en la misma corrida— y Verify no
  # lo vería nunca.
  $rootC7 = Join-Path $script:tmp "C7"
  New-Tree $rootC7 @{ viva = @{ "SKILL.md" = "v`n" }; huerfana = @{ "SKILL.md" = "h`n" }; propia = @{ "SKILL.md" = "p`n" } }
  $basesC7 = Join-Path $script:tmp "bases-C7.json"; New-Bases $basesC7
  $r = Run-ToolInCulture "th-TH" @("-Action", "Seal", "-Repo", $rootC7, "-Bases", $basesC7)
  Assert ($r.Code -eq 0) "sellar con la cultura th-TH sale con codigo 0 (salida: $($r.Out))"
  $textoC7 = if (Test-Path -LiteralPath (Join-Path $rootC7 "skills-lock.json")) { [IO.File]::ReadAllText((Join-Path $rootC7 "skills-lock.json")) } else { "" }
  Assert ($textoC7 -match '"commitDate": "2026-05-06T08:26:48Z"') `
    "y la fecha del commit base sale en el calendario gregoriano, igual que en cualquier otra cultura"

  # --- D. Las cuatro copias -------------------------------------------------------------------
  # El lockfile vive en la raíz del repo (self-bootstrap) y en el scaffold de cada skill bootstrap-*.
  # Verificar las cuatro es red extra gratis: ya están todas en disco.
  $rootD = New-MultiRoot "D"
  $scaffoldD = Join-Path $rootD "skills/bootstrap-x-project/assets/scaffold"
  $r = Run-Tool @("-Action", "Verify", "-Repo", $rootD)
  Assert ($r.Code -eq 0) "una raiz con scaffold verifica en verde (salida: $($r.Out))"
  Assert ($r.Out -match '2 copia') "y declara que verifico las 2 copias, no una (salida: $($r.Out))"

  # La copia del scaffold NO es decorativa: es la que se le entrega a cada proyecto.
  [IO.File]::WriteAllText((Join-Path $scaffoldD ".agents/skills/viva/SKILL.md"), "mutado solo en el scaffold`n")
  $r = Run-Tool @("-Action", "Verify", "-Repo", $rootD)
  Assert ($r.Code -eq 1) "alterar una skill SOLO en la copia del scaffold sale con codigo 1"
  Assert ($r.Out -match 'bootstrap-x-project') "y el reporte atribuye el problema a esa copia (salida: $($r.Out))"

  # Los metadatos de base apuntan a upstream y son inverificables offline por definición. Lo único
  # que los cuida es que las copias sean el mismo documento.
  $rootD2 = New-MultiRoot "D2"
  $lockD2 = Join-Path $rootD2 "skills/bootstrap-x-project/assets/scaffold/skills-lock.json"
  [IO.File]::WriteAllText($lockD2, ([IO.File]::ReadAllText($lockD2) -replace 'c0ffee1', 'deadbee'))
  $r = Run-Tool @("-Action", "Verify", "-Repo", $rootD2)
  Assert ($r.Code -eq 1) "editar a mano el commit base en UNA copia sale con codigo 1"
  Assert ($r.Out -match 'no es el mismo documento') `
    "y lo reporta como copias divergentes, no como hash de archivo (salida: $($r.Out))"

  $rootD3 = New-MultiRoot "D3"
  Remove-Item -LiteralPath (Join-Path $rootD3 "skills/bootstrap-x-project/assets/scaffold/skills-lock.json") -Force
  $r = Run-Tool @("-Action", "Verify", "-Repo", $rootD3)
  Assert ($r.Code -eq 1) "una copia a la que le falta el lockfile sale con codigo 1"
  Assert ($r.Out -match 'falta skills-lock\.json') "y dice que falta el lockfile (salida: $($r.Out))"

  $rootD4 = New-MultiRoot "D4"
  Remove-Item -LiteralPath (Join-Path $rootD4 "skills/bootstrap-x-project/assets/scaffold/.agents/skills") -Recurse -Force
  $r = Run-Tool @("-Action", "Verify", "-Repo", $rootD4)
  Assert ($r.Code -eq 1) "una copia con lockfile pero sin arbol de skills sale con codigo 1"
  Assert ($r.Out -match 'no existe \.agents/skills') "y dice que no existe el arbol (salida: $($r.Out))"

  # Sellar sobre raíces cuyo árbol de skills difiere: el documento se arma con el árbol de la primera
  # raíz y se copia a todas, así que tiene que negarse ANTES de escribir. Negarse después dejaría las
  # cuatro copias commiteadas ya pisadas.
  $rootD5 = Join-Path $script:tmp "D5"
  New-Tree $rootD5 @{ viva = @{ "SKILL.md" = "v`n" }; huerfana = @{ "SKILL.md" = "h`n" }; propia = @{ "SKILL.md" = "p`n" } }
  New-Tree (Join-Path $rootD5 "skills/bootstrap-x-project/assets/scaffold") @{
    viva = @{ "SKILL.md" = "distinta en el scaffold`n" }; huerfana = @{ "SKILL.md" = "h`n" }; propia = @{ "SKILL.md" = "p`n" }
  }
  $basesD5 = Join-Path $script:tmp "bases-D5.json"; New-Bases $basesD5
  $r = Run-Tool @("-Action", "Seal", "-Repo", $rootD5, "-Bases", $basesD5)
  Assert ($r.Code -eq 1) "sellar raices con arboles de skills distintos sale con codigo 1 (salida: $($r.Out))"
  Assert ($r.Out -match 'bootstrap-x-project' -and $r.Out -match 'no se sello nada') `
    "y nombra la raiz que difiere, sin sellar nada (salida: $($r.Out))"
  Assert (-not (Test-Path -LiteralPath (Join-Path $rootD5 "skills-lock.json")) -and
          -not (Test-Path -LiteralPath (Join-Path $rootD5 "skills/bootstrap-x-project/assets/scaffold/skills-lock.json"))) `
    "y no escribe ninguna de las dos copias"

  # --- E. Re-sellar sin las bases -------------------------------------------------------------
  # `skill-bases.json` es la salida de una herramienta que necesita RED y un clon de upstream, y vive
  # fuera del repo. Si sellar lo exigiera siempre, actualizar el cuerpo de una skill sería imposible
  # desde un clon limpio y el lockfile volvería a pudrirse: exactamente lo que ADR-0005 castiga. Por
  # eso el re-sellado conserva los metadatos de base del lockfile que ya está y solo recomputa hashes.
  $rootE = New-SealedRoot "E"
  $commitAntes = (Read-Lock $rootE).skills['huerfana'].base.commit
  [IO.File]::WriteAllText((Join-Path $rootE ".agents/skills/viva/SKILL.md"), "cuerpo nuevo de viva`n")
  $r = Run-Tool @("-Action", "Seal", "-Repo", $rootE)
  Assert ($r.Code -eq 0) "re-sellar sin -Bases sale con codigo 0 (salida: $($r.Out))"
  $docE = Read-Lock $rootE
  Assert ($docE.skills['huerfana'].base.commit -eq $commitAntes) `
    "y conserva el commit base que ya estaba registrado"
  Assert ($docE.skills['viva'].files['SKILL.md'] -eq (Get-NormalizedHash -Path (Join-Path $rootE ".agents/skills/viva/SKILL.md"))) `
    "y actualiza el hash del archivo que cambio"

  # Una skill nueva no tiene base que conservar. Registrarla en silencio como fork propio sería
  # inventar una afirmación sobre upstream que nadie verificó.
  $rootE2 = New-SealedRoot "E2"
  New-Item -ItemType Directory -Path (Join-Path $rootE2 ".agents/skills/recien-llegada") -Force | Out-Null
  [IO.File]::WriteAllText((Join-Path $rootE2 ".agents/skills/recien-llegada/SKILL.md"), "sin base`n")
  $r = Run-Tool @("-Action", "Seal", "-Repo", $rootE2)
  Assert ($r.Code -ne 0) "re-sellar sin -Bases con una skill nueva en el arbol NO sale con codigo 0"
  Assert ($r.Out -match 'recien-llegada') "y nombra la skill que no tiene base registrada (salida: $($r.Out))"

  $rootE3 = Join-Path $script:tmp "E3"
  New-Tree $rootE3 @{ viva = @{ "SKILL.md" = "v`n" } }
  $r = Run-Tool @("-Action", "Seal", "-Repo", $rootE3)
  Assert ($r.Code -ne 0) "sellar sin -Bases y sin lockfile previo NO sale con codigo 0: no hay de donde sacar la base"

  # El re-sellado tiene que ser idempotente BYTE A BYTE: el hash crudo del lockfile entra al
  # `.bootstrap-manifest.json` del scaffold, así que un re-sellado que solo reordena claves rutearía
  # el archivo a `customized` en cada proyecto que reciba el scaffold.
  $rootE4 = New-SealedRoot "E4"
  $bytesAntes = [IO.File]::ReadAllBytes((Join-Path $rootE4 "skills-lock.json"))
  $r = Run-Tool @("-Action", "Seal", "-Repo", $rootE4)
  $bytesDespues = [IO.File]::ReadAllBytes((Join-Path $rootE4 "skills-lock.json"))
  Assert ($r.Code -eq 0 -and ([Convert]::ToBase64String($bytesAntes) -eq [Convert]::ToBase64String($bytesDespues))) `
    "re-sellar sin cambios deja el lockfile byte-identico"

  # El lockfile viejo (version 1) no tiene metadatos de base. Re-sellarlo sin `-Bases` los dejaría a
  # todos en null, que es volver a la afirmacion no verificada que ADR-0005 borro.
  $rootE5 = Join-Path $script:tmp "E5"
  New-Tree $rootE5 @{ viva = @{ "SKILL.md" = "v`n" } }
  [IO.File]::WriteAllText((Join-Path $rootE5 "skills-lock.json"),
    '{ "version": 1, "skills": { "viva": { "source": "x", "computedHash": "fabricado" } } }')
  $r = Run-Tool @("-Action", "Seal", "-Repo", $rootE5)
  Assert ($r.Code -ne 0) "re-sellar un lockfile version 1 sin -Bases NO sale con codigo 0"
  Assert ($r.Out -match "version '1'" -and $r.Out -match '-Bases') `
    "y dice que hay que migrarlo con -Bases (salida: $($r.Out))"

  # --- F. El repo de verdad -------------------------------------------------------------------
  # Este es el AC "la verificación corre sin red y forma parte de la suite": acá la suite verifica
  # el lockfile real. Todo lo de arriba corrió sobre directorios de %TEMP% que no son repositorios
  # git ni tienen remoto, que es la evidencia práctica de que la verificación es offline.
  $rReal = Run-Tool @("-Action", "Verify")
  Assert ($rReal.Code -eq 0) "el lockfile del repo verifica contra su arbol (salida: $($rReal.Out))"

  $docReal = Read-Lock $repo
  Assert ($docReal.version -eq 2) "y es un lockfile version 2, con metadatos de base por entrada"

  # El conteo no se hardcodea —agregar una cuarta variante de bootstrap es legítimo—: se compara
  # contra las copias que git trackea. Lo que se fija es que el descubrimiento de la herramienta no se
  # saltee ninguna. Se cuenta lo trackeado y no lo que hay en disco: un worktree anidado o un
  # `.bootstrap-backup/` traen copias que no son del repo y pondrían la suite en rojo sin motivo.
  $copias = @(git -C $repo ls-files -- 'skills-lock.json' '*/skills-lock.json').Count
  Assert ($rReal.Out -match "OK: $copias copia") `
    "y verifica TODAS las copias que hay en el repo ($copias), no solo la de la raiz (salida: $($rReal.Out))"

} finally {
  Remove-Item -LiteralPath $script:tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ""
if ($script:checks -ne $ExpectedChecks) {
  Write-Host "FAIL: corrieron $($script:checks) aserciones y se esperaban $ExpectedChecks"
  $script:failures++
}
Write-Host "$($script:checks) aserciones, $($script:failures) fallidas"
exit ([int]($script:failures -gt 0))
