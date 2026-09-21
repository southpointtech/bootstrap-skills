# tools/skills-lock.ps1 — sella y verifica el lockfile de las skills tomadas de upstream.
#
#   pwsh -NoProfile -File tools/skills-lock.ps1 -Action Seal   [-Bases <skill-bases.json>] [-ForkFile <skill>/<archivo>[,<skill>/<archivo>...]]
#   pwsh -NoProfile -File tools/skills-lock.ps1 -Action Verify
#
# Por qué existe: el lockfile anterior declaraba un `computedHash` por skill que nunca fue computado
# por nada (ADR-0005, medido el 2026-08-28: 24.738 hashes probados contra toda la historia publicada
# de upstream, cero coincidencias). Los nueve eran fabricados y sobrevivieron dos meses precisamente
# porque nada los leía. La decisión de ADR-0005: o el lockfile se verifica, o se borra.
#
# `Verify` es OFFLINE —recomputa contra los archivos del repo, sin red— y por eso puede vivir en la
# suite. La comparación contra upstream necesita red y es otra herramienta,
# `tools/recover-skill-bases.py`, cuya salida (`skill-bases.json`) es lo que `-Bases` importa.
#
# Exit codes: 0 todo bien | 1 el lockfile y el árbol no concuerdan | 2 no se puede correr.
param(
  [Parameter(Mandatory)][ValidateSet('Seal', 'Verify')][string]$Action,
  # Raíz del repo. Existe para que el test pueda apuntar a un árbol sintético.
  [string]$Repo,
  # Solo para Seal: la salida de tools/recover-skill-bases.py, de donde salen los metadatos de base.
  [string]$Bases,
  # Solo para Seal: archivos NUESTROS dentro de una skill que sí viene de upstream (`tdd/deep-modules.md`:
  # upstream lo retiró y lo conservamos). Es una decisión humana, como marcar una skill entera como fork
  # propio, y el lockfile es generado: entra por acá y el re-sellado la conserva.
  [string[]]$ForkFile = @()
)
$ErrorActionPreference = "Stop"

# `pwsh -File` no deja repetir el parámetro y entrega `a,b` como un solo string: se separa acá.
$ForkFile = @($ForkFile | ForEach-Object { $_ -split ',' } | Where-Object { $_ })
foreach ($spec in $ForkFile) {
  if ($spec -notmatch '^[^/\\]+/[^/\\].*$') {
    Write-Host "ERROR: -ForkFile '$spec' no tiene la forma <skill>/<archivo relativo a la skill>"
    exit 2
  }
}

. (Join-Path $PSScriptRoot "normalized-hash.ps1")

if (-not $Repo) { $Repo = Split-Path $PSScriptRoot -Parent }
$Repo = (Resolve-Path -LiteralPath $Repo).ProviderPath

$LOCK       = "skills-lock.json"
$SKILLS_DIR = ".agents/skills"

# Orden ORDINAL, no cultural. `Sort-Object` compara según la cultura del proceso: ordena
# "mocking.md" antes que "SKILL.md" en es-AR y podría ordenarlo distinto en otra. El lockfile se
# escribe en cuatro copias que tienen que quedar byte-idénticas y su hash crudo entra al manifest
# del scaffold, así que el orden de las claves no puede depender de la máquina que selló.
# La fecha del commit base, en UTC canónica. `ConvertFrom-Json` NO devuelve las fechas ISO-8601 como
# strings: las convierte a `[datetime]` en la zona LOCAL del proceso. Re-serializarlas tal cual hace
# que el mismo lockfile sellado en Londres y en Buenos Aires salga con bytes distintos (medido:
# `2026-05-13T14:05:18+01:00` salió `2026-05-13T10:05:18-03:00`), y las cuatro copias tienen que ser
# el mismo documento. Normalizar a UTC preserva el instante y da la misma cadena en cualquier máquina.
# Es una normalización DECLARADA: el lockfile no transcribe el offset con el que git imprimió la fecha.
function ConvertTo-UtcIso($v) {
  if ($null -eq $v) { return $null }
  # InvariantCulture: sin ella el formato usa el calendario de la cultura del proceso (th-TH escribe
  # el año 2569) y el separador de hora de esa cultura.
  $inv = [Globalization.CultureInfo]::InvariantCulture
  if ($v -is [datetimeoffset]) { return $v.ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", $inv) }
  if ($v -is [datetime])       { return $v.ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", $inv) }
  # Si el deserializador no la coaccionó, se deja tal cual: inventarle un formato a algo que no
  # entendemos es peor que conservarlo.
  return [string]$v
}

function Sort-Ordinal([string[]]$items) {
  $a = [string[]]@($items)
  [Array]::Sort($a, [StringComparer]::Ordinal)
  # Sin `,` a propósito, y el llamador envuelve en `@()`. El idioma `return ,$a` protege el array de
  # UN elemento pero rompe el VACÍO: devuelve un array de un elemento que contiene el array vacío, y
  # `@()` alrededor deja `Count = 1`. Se reportó un problema fantasma con mensaje vacío hasta que un
  # test lo cazó. Devolver pelado y envolver en el llamador funciona en los tres casos.
  return $a
}

# Las raíces: el repo mismo (self-bootstrap) y el scaffold de cada skill bootstrap-*. Se descubren,
# no se listan: una cuarta variante de bootstrap entra sola. Una raíz participa si tiene el lockfile
# O el árbol de skills; tener solo uno de los dos es un problema que Verify reporta, no un motivo
# para saltearla en silencio.
function Get-LockRoots([string]$repo) {
  $cands = @($repo)
  $skillsHome = Join-Path $repo "skills"
  if (Test-Path -LiteralPath $skillsHome) {
    $cands += @(Get-ChildItem -LiteralPath $skillsHome -Directory |
                ForEach-Object { Join-Path $_.FullName "assets\scaffold" } |
                Where-Object { Test-Path -LiteralPath $_ })
  }
  return @($cands | Where-Object {
    (Test-Path -LiteralPath (Join-Path $_ $LOCK)) -or (Test-Path -LiteralPath (Join-Path $_ $SKILLS_DIR))
  })
}

# El árbol de skills de una raíz, ya hasheado: nombre -> (ruta relativa a la skill -> hash).
# TODOS los archivos de cada directorio de skill, no solo el SKILL.md: sellando solo el SKILL.md,
# editar `tdd/mocking.md` pasaría la verificación en verde.
function Get-SkillTree([string]$root) {
  $dir = Join-Path $root $SKILLS_DIR
  $tree = [ordered]@{}
  if (-not (Test-Path -LiteralPath $dir)) { return $tree }
  foreach ($nombre in (Sort-Ordinal @(Get-ChildItem -LiteralPath $dir -Directory | ForEach-Object Name))) {
    $skillDir = Join-Path $dir $nombre
    $prefix = (Resolve-Path -LiteralPath $skillDir).ProviderPath.Length
    $files = @{}
    foreach ($f in (Get-ChildItem -LiteralPath $skillDir -Recurse -File -Force)) {
      $rel = $f.FullName.Substring($prefix).TrimStart('\', '/').Replace('\', '/')
      $files[$rel] = Get-NormalizedHash -Path $f.FullName
    }
    $ordered = [ordered]@{}
    foreach ($k in (Sort-Ordinal @($files.Keys))) { $ordered[$k] = $files[$k] }
    $tree[$nombre] = $ordered
  }
  return $tree
}

# Las marcas de fork propio de una entrada de un lockfile ya sellado. Un lockfile sellado antes de que
# existiera el campo no lo trae, y `@($null)` tiene UN elemento: por eso el caso nulo va aparte.
function Get-ForkFiles($entry) {
  if ($null -eq $entry -or $null -eq $entry.forkFiles) { return [string[]]@() }
  return [string[]]@($entry.forkFiles)
}

# Traduce `skill-bases.json` (salida de recover-skill-bases.py) a los metadatos que el lockfile
# registra. Los tres estados NO se colapsan: `upstream-huerfano` conserva el commit base que la
# recuperación por similitud encontró, y colapsarlo en `fork-propio` tiraría justo ese dato.
#
# Ojo con la procedencia de `fork-propio`: la herramienta de recuperación no afirma que la skill
# nunca haya salido de upstream, solo que ninguna versión histórica superó su umbral de similitud.
# Marcarla como fork propio es una decisión humana (ADR-0005) que este import transcribe.
function Import-Bases([string]$path) {
  $raw = [IO.File]::ReadAllText((Resolve-Path -LiteralPath $path -ErrorAction Stop).ProviderPath)
  $b = $raw | ConvertFrom-Json -AsHashtable
  $meta = [ordered]@{}
  # Solo se transcriben las dos formas que la recuperación resolvió: `recovered` con una relación
  # upstream conocida, y `unmatched`. Lo demás que el productor emite (`unresolved-commit`: hay blob
  # pero ningún commit fechado; un empate entre cuerpos distintos, cuya base decide un humano) sellado
  # como `upstream-vivo` dejaría una base que nadie resolvió.
  $rechazos = @()
  foreach ($s in $b.skills) {
    $resuelta = ($s.status -eq "recovered" -and $null -ne $s.base -and
                 $s.upstreamRelation -in @("in-upstream-head", "gone-from-upstream-head")) -or
                ($s.status -eq "unmatched" -and $null -eq $s.base -and
                 $s.upstreamRelation -eq "no-match-above-threshold")
    # Además de la etiqueta, los hechos que la etiqueta resume: `recovered` sin commit es lo que el
    # productor llama `unresolved-commit`, y un empate solo se transcribe si el productor midió que
    # los cuerpos son idénticos. Las dos formas solo llegan editando a mano el archivo generado.
    # Cada rechazo lleva su propio remedio: re-correr el productor solo arregla lo que el productor no
    # emite. Lo que sí emite (una base sin resolver, un empate entre cuerpos distintos) sale igual.
    if (-not $resuelta) {
      $rechazos += "la skill '$($s.name)' tiene status '$($s.status)' y relacion '$($s.upstreamRelation)': la recuperacion no resolvio su base, y re-correr tools/recover-skill-bases.py no lo cambia (ver docs/agents/recuperar-base-de-skills.md)"
    } elseif ($s.status -eq "recovered" -and ($null -eq $s.base.blob -or $null -eq $s.base.commit -or $null -eq $s.base.commitDate)) {
      $rechazos += "la skill '$($s.name)' figura recovered pero su base esta sin commit, sin fecha o sin blob: volve a correr tools/recover-skill-bases.py"
    } elseif ($null -ne $s.base -and ($null -ne $s.base.tiedCandidates -or $null -ne $s.base.tieOnIdenticalBodies) -and
              -not ($s.base.tieOnIdenticalBodies -is [bool] -and $s.base.tieOnIdenticalBodies)) {
      if ($s.base.tieOnIdenticalBodies -is [bool]) {
        $rechazos += "la skill '$($s.name)' tiene un empate entre cuerpos distintos: su base la decide un humano, y este sellado no tiene como transcribir esa decision"
      } else {
        $rechazos += "la skill '$($s.name)' tiene un empate sin un tieOnIdenticalBodies booleano: volve a correr tools/recover-skill-bases.py"
      }
    }
  }
  if ($rechazos.Count -gt 0) {
    foreach ($m in $rechazos) { Write-Host "ERROR: $m" }
    Write-Host "No se sello nada: $path no resuelve esas bases. Es salida generada y no se edita a mano."
    exit 1
  }
  foreach ($s in $b.skills) {
    $tieneBase = $null -ne $s.base
    $estado = if (-not $tieneBase) { "fork-propio" }
              elseif ($s.upstreamRelation -eq "gone-from-upstream-head") { "upstream-huerfano" }
              else { "upstream-vivo" }
    $entry = [ordered]@{
      source           = if ($tieneBase) { $b.upstream.url } else { $null }
      upstreamState    = $estado
      # Dónde vive hoy en el HEAD de upstream. Junto con `base.upstreamPath` (dónde vivía en el
      # commit base) deja registrado el rename, que es lo que el próximo merge de tres vías necesita
      # para comparar contra el archivo correcto y no contra ninguno (ADR-0006).
      upstreamHeadPath = if ($estado -eq "upstream-vivo") { $s.upstreamHead.path } else { $null }
      base             = $null
      forkFiles        = [string[]]@()
      files            = [ordered]@{}
    }
    if ($tieneBase) {
      $entry.base = [ordered]@{
        blob         = $s.base.blob
        upstreamPath = $s.base.upstreamPath
        commit       = $s.base.commit
        commitDate   = ConvertTo-UtcIso $s.base.commitDate
      }
    }
    $meta[$s.name] = $entry
  }
  return @{ Upstream = [ordered]@{ url = $b.upstream.url; head = $b.upstream.head }; Skills = $meta }
}

# La verificación, offline: cada raíz contra su propio árbol. Devuelve la lista de problemas.
function Test-Lock([string[]]$roots) {
  $problemas = @()
  foreach ($root in $roots) {
    $lockPath = Join-Path $root $LOCK
    if (-not (Test-Path -LiteralPath $lockPath)) {
      $problemas += "$root : falta $LOCK"
      continue
    }
    if (-not (Test-Path -LiteralPath (Join-Path $root $SKILLS_DIR))) {
      $problemas += "$root : hay $LOCK pero no existe $SKILLS_DIR"
      continue
    }
    $doc  = [IO.File]::ReadAllText($lockPath) | ConvertFrom-Json -AsHashtable
    $tree = Get-SkillTree $root

    # Los dos conjuntos se comparan en las DOS direcciones, y no solo los hashes de lo que el
    # lockfile ya lista: recorrer solo el lockfile deja entrar un archivo nuevo dentro de una skill
    # sellada —o una skill entera— sin que nada lo mire, que es la misma clase de agujero que
    # ADR-0005. La comparación de nombres es insensible a mayúsculas, como el filesystem debajo.
    $selladas = @($doc.skills.Keys)
    $enArbol  = @($tree.Keys)
    foreach ($name in @($selladas | Where-Object { $enArbol -notcontains $_ } | Sort-Object)) {
      $problemas += "$root : la skill '$name' esta sellada pero no esta en el arbol"
    }
    foreach ($name in @($enArbol | Where-Object { $selladas -notcontains $_ } | Sort-Object)) {
      $problemas += "$root : la skill '$name' esta en el arbol pero no esta en el lockfile"
    }

    foreach ($name in @($selladas | Where-Object { $enArbol -contains $_ } | Sort-Object)) {
      $sellados = @($doc.skills[$name].files.Keys)
      $reales   = @($tree[$name].Keys)
      foreach ($rel in @($sellados | Where-Object { $reales -notcontains $_ } | Sort-Object)) {
        $problemas += "$root : $name/$rel esta sellado pero no esta en el arbol"
      }
      foreach ($rel in @($reales | Where-Object { $sellados -notcontains $_ } | Sort-Object)) {
        $problemas += "$root : $name/$rel esta en el arbol pero no esta en el lockfile"
      }
      foreach ($rel in @(Get-ForkFiles $doc.skills[$name] | Where-Object { $sellados -notcontains $_ } | Sort-Object)) {
        $problemas += "$root : $name/$rel esta marcado como fork propio pero no esta sellado"
      }
      foreach ($rel in @($sellados | Where-Object { $reales -contains $_ } | Sort-Object)) {
        if ($tree[$name][$rel] -ne $doc.skills[$name].files[$rel]) {
          $problemas += "$root : $name/$rel el hash sellado no coincide con el archivo"
        }
      }
    }
  }

  # Las copias del lockfile tienen que ser el mismo documento. Cada una ya se verificó contra su
  # propio árbol, pero los metadatos de base (commit, blob, path upstream) apuntan a upstream y son
  # inverificables offline por definición: si alguien edita a mano el commit base de UNA copia, sin
  # esta comparación no lo ve nadie — que es exactamente el fallo que ADR-0005 documenta. Se compara
  # por hash normalizado y no por bytes crudos, porque el fin de línea es ruido de plataforma.
  $conLock = @($roots | Where-Object { Test-Path -LiteralPath (Join-Path $_ $LOCK) })
  if ($conLock.Count -gt 1) {
    $ref = Get-NormalizedHash -Path (Join-Path $conLock[0] $LOCK)
    foreach ($otro in $conLock[1..($conLock.Count - 1)]) {
      if ((Get-NormalizedHash -Path (Join-Path $otro $LOCK)) -ne $ref) {
        $problemas += "$otro : su $LOCK no es el mismo documento que el de $($conLock[0])"
      }
    }
  }
  return $problemas
}

# ---------------------------------------------------------------------------------------------
# El `@()` es obligatorio y no es ruido: PowerShell DESENROLLA un array de un elemento al salir de
# una función, así que con una sola raíz `$roots` sería el string y `$roots[0]` su primer carácter
# ("C" de "C:\..."). Se selló un lockfile con `files: {}` antes de que un test lo cazara.
$roots = @(Get-LockRoots $Repo)
if ($roots.Count -eq 0) {
  Write-Host "ERROR: no hay ninguna raiz con $LOCK ni $SKILLS_DIR bajo $Repo"
  exit 2
}

if ($Action -eq 'Seal') {
  # De dónde salen los metadatos de base. Con `-Bases`, de la recuperación por similitud: es el
  # camino de migración, y el que se usa cuando aparece una skill nueva. Sin `-Bases`, del lockfile
  # que ya está: `skill-bases.json` es salida de una herramienta que necesita red y un clon de
  # upstream, y vive fuera del repo — si sellar lo exigiera siempre, actualizar el cuerpo de una
  # skill sería imposible desde un clon limpio y el lockfile volvería a pudrirse sin que nadie lo
  # pueda regenerar, que es el escenario de ADR-0005.
  if ($Bases) {
    $imported = Import-Bases $Bases
    $fuente = $Bases
    # Re-migrar con -Bases no puede tirar las marcas de fork propio: la recuperación no las emite,
    # porque son una decisión humana. Se conservan las del lockfile que ya está, si hay uno v2.
    $prevPath = Join-Path $roots[0] $LOCK
    if (Test-Path -LiteralPath $prevPath) {
      # `-Bases` es el camino de recuperación, y un lockfile ilegible (un conflicto de merge en el archivo
      # generado) es justo cuando se lo usa. Seguir sin las marcas las perdería en silencio: se frena.
      # Un archivo vacío (lo que deja una escritura cortada), `null` o `[]` NO tiran: `ConvertFrom-Json`
      # los devuelve como `$null` sin error. Por eso además del try se exige un objeto, y en un v2, sus skills.
      $motivo = $null
      try { $prev = [IO.File]::ReadAllText($prevPath) | ConvertFrom-Json -AsHashtable }
      catch { $motivo = $_.Exception.Message }
      if (-not $motivo -and $prev -isnot [Collections.IDictionary]) { $motivo = "no es un objeto JSON" }
      if (-not $motivo -and $prev.version -eq 2 -and $prev.skills -isnot [Collections.IDictionary]) { $motivo = "es version 2 pero no tiene skills" }
      if ($motivo) {
        Write-Host "ERROR: no se puede leer $prevPath ($motivo)"
        Write-Host "Resolvelo, o borralo y volve a sellar con -Bases y con -ForkFile para cada marca de fork propio que tenia."
        exit 2
      }
      if ($prev.version -eq 2) {
        foreach ($k in @($imported.Skills.Keys)) {
          if ($prev.skills.Contains($k)) { $imported.Skills[$k].forkFiles = Get-ForkFiles $prev.skills[$k] }
        }
      }
    }
  } else {
    $prevPath = Join-Path $roots[0] $LOCK
    if (-not (Test-Path -LiteralPath $prevPath)) {
      Write-Host "ERROR: no hay $LOCK en $($roots[0]) del cual conservar los metadatos de base."
      Write-Host "Para sellar por primera vez, pasa -Bases con la salida de tools/recover-skill-bases.py"
      exit 2
    }
    $prev = [IO.File]::ReadAllText($prevPath) | ConvertFrom-Json -AsHashtable
    # Un lockfile v1 no tiene `base`: re-sellarlo sin darse cuenta dejaría todas las entradas sin
    # commit base, o sea volvería a la afirmación no verificada que ADR-0005 borró.
    if ($prev.version -ne 2) {
      Write-Host "ERROR: $prevPath es version '$($prev.version)' y no tiene metadatos de base que conservar."
      Write-Host "Migralo con -Bases (la salida de tools/recover-skill-bases.py) antes de re-sellar."
      exit 2
    }
    $meta = [ordered]@{}
    foreach ($k in $prev.skills.Keys) {
      $e = $prev.skills[$k]
      # Los campos se re-arman uno por uno, en el mismo orden que Import-Bases: copiar el objeto
      # entero dejaría el orden de claves a merced de cómo lo parseó el deserializador, y el
      # re-sellado tiene que ser idempotente byte a byte (su hash crudo entra al manifest).
      $meta[$k] = [ordered]@{
        source           = $e.source
        upstreamState    = $e.upstreamState
        upstreamHeadPath = $e.upstreamHeadPath
        base             = if ($null -ne $e.base) {
                             [ordered]@{
                               blob         = $e.base.blob
                               upstreamPath = $e.base.upstreamPath
                               commit       = $e.base.commit
                               commitDate   = ConvertTo-UtcIso $e.base.commitDate
                             }
                           } else { $null }
        forkFiles        = Get-ForkFiles $e
        files            = [ordered]@{}
      }
    }
    $imported = @{ Upstream = [ordered]@{ url = $prev.upstream.url; head = $prev.upstream.head }; Skills = $meta }
    $fuente = $prevPath
  }
  $tree = Get-SkillTree $roots[0]

  # El conjunto de skills del árbol y el de las bases tienen que ser el mismo. Sin este chequeo,
  # sellar produce un lockfile que falla su propia verificación un segundo después: una skill de las
  # bases sin directorio queda sellada con `files: {}` (verde vacuo) y una del árbol sin entrada
  # simplemente no entra al lockfile.
  $enBases = @($imported.Skills.Keys)
  $enArbol = @($tree.Keys)
  $desajuste = @()
  foreach ($n in @($enArbol | Where-Object { $enBases -notcontains $_ } | Sort-Object)) {
    $desajuste += "la skill '$n' esta en el arbol pero no esta en $fuente"
  }
  foreach ($n in @($enBases | Where-Object { $enArbol -notcontains $_ } | Sort-Object)) {
    $desajuste += "la skill '$n' esta en $fuente pero no esta en el arbol"
  }
  if ($desajuste.Count -gt 0) {
    foreach ($d in $desajuste) { Write-Host "ERROR: $d" }
    Write-Host "No se sello nada: la fuente de metadatos y el arbol tienen que describir el mismo conjunto de skills."
    exit 1
  }

  # Las marcas de fork propio: las conservadas más las de -ForkFile, siempre sobre archivos del árbol.
  # Una pedida que no está en el árbol es un tipeo y frena todo; una conservada cuyo archivo se borró
  # dejó de ser un fork, así que se quita, y se dice cuál.
  $noEncontrados = @()
  foreach ($spec in $ForkFile) {
    $skill, $rel = $spec -split '/', 2
    # El `@()` de afuera no es ruido: un `if` usado como expresión desenrolla el array de un elemento,
    # y `$real[0]` pasaba a ser la primera LETRA del nombre.
    $real = @(if ($tree.Contains($skill)) { $tree[$skill].Keys | Where-Object { $_ -eq $rel.Replace('\', '/') } })
    if ($real.Count -eq 0) { $noEncontrados += $spec; continue }
    $marcas = @(Get-ForkFiles $imported.Skills[$skill])
    if ($marcas -notcontains $real[0]) { $imported.Skills[$skill].forkFiles = [string[]]@($marcas + $real[0]) }
  }
  if ($noEncontrados.Count -gt 0) {
    foreach ($n in $noEncontrados) { Write-Host "ERROR: -ForkFile '$n' no esta en el arbol de $($roots[0])" }
    Write-Host "No se sello nada: solo se marca como fork propio un archivo que existe."
    exit 1
  }
  foreach ($name in $enArbol) {
    $vivas = @()
    foreach ($rel in @(Get-ForkFiles $imported.Skills[$name])) {
      if (@($tree[$name].Keys) -contains $rel) { $vivas += $rel }
      else { Write-Host "AVISO: se quito la marca de fork propio de $name/$rel`: el archivo ya no esta en el arbol" }
    }
    $imported.Skills[$name].forkFiles = [string[]]@(Sort-Ordinal $vivas)
  }

  # El documento se arma con el árbol de la primera raíz y se escribe en todas. Si otra raíz tiene un
  # árbol distinto, la verificación posterior lo delataría, pero recién DESPUÉS de haber pisado todas
  # las copias: la comparación va antes de escribir.
  $refTree = $tree | ConvertTo-Json -Depth 5 -Compress
  $distintas = @($roots | Select-Object -Skip 1 | Where-Object { (Get-SkillTree $_ | ConvertTo-Json -Depth 5 -Compress) -ne $refTree })
  if ($distintas.Count -gt 0) {
    foreach ($d in $distintas) { Write-Host "ERROR: el arbol de skills de $d no es el mismo que el de $($roots[0])" }
    Write-Host "No se sello nada: todas las copias tienen que tener el mismo arbol de skills."
    exit 1
  }

  foreach ($name in $enArbol) { $imported.Skills[$name].files = $tree[$name] }

  $skills = [ordered]@{}
  foreach ($k in (Sort-Ordinal $enBases)) { $skills[$k] = $imported.Skills[$k] }
  $doc = [ordered]@{
    version         = 2
    doNotEditByHand = "generado por tools/skills-lock.ps1 -Action Seal; verificado por tests/skills-lock.tests.ps1"
    hash            = [ordered]@{
      algorithm     = "sha256"
      normalization = "tools/normalized-hash.ps1 :: Get-NormalizedHash -Scope File"
    }
    upstream        = $imported.Upstream
    skills          = $skills
  }
  $json = $doc | ConvertTo-Json -Depth 8
  foreach ($r in $roots) { Set-Content -LiteralPath (Join-Path $r $LOCK) -Value $json -Encoding UTF8 }

  # Sellar y verificar es un solo acto: si lo recién escrito no verifica en verde, el sellado no
  # sirvió. Las raíces con árboles de skills distintos NO llegan hasta acá: las rechaza la
  # comparación de antes de escribir, que es la que evita pisar las copias. Esta relee lo escrito.
  $problemas = @(Test-Lock $roots)
  if ($problemas.Count -gt 0) {
    foreach ($p in $problemas) { Write-Host "ROJO: $p" }
    Write-Host "Se sellaron $($skills.Count) skills pero la verificacion posterior no dio verde."
    exit 1
  }
  Write-Host "Sellado y verificado: $($skills.Count) skills en $($roots.Count) copia(s) de $LOCK"
  exit 0
}

# --- Verify ----------------------------------------------------------------------------------
$problemas = @(Test-Lock $roots)
foreach ($p in $problemas) { Write-Host "ROJO: $p" }
if ($problemas.Count -gt 0) {
  Write-Host "$($problemas.Count) problema(s) en $($roots.Count) copia(s) de $LOCK"
  exit 1
}
Write-Host "OK: $($roots.Count) copia(s) de $LOCK verificadas contra el arbol"
exit 0
