# tools/normalized-hash.ps1 — la forma canónica de hashear contenido en este repo.
#
# Se usa dot-sourceando el archivo:  . (Join-Path $repo "tools/normalized-hash.ps1")
#
# Por qué existe: el hash con el que se sellan los manifests del scaffold se calculaba sobre los
# bytes crudos del archivo, o sea sobre cómo el checkout de cada máquina escribió los fines de
# línea. Consecuencia medida: un manifest sellado en una máquina rutea archivos idénticos a
# `customized` en otra, y regenerarlo desde un worktree fresco produce hashes distintos para el
# mismo contenido (memoria `bug-autocrlf-manifests-hashes-mixtos`). Lo usan los tres consumidores
# del manifest: `tools/gen-manifest.ps1` y, desde una copia idéntica en
# `skills/upgrade-bootstrap/scripts/normalized-hash.ps1` (la skill deployada no ve `tools/`),
# `compare-scaffold.ps1` y `reseal-manifest.ps1`. `tests/manifest-hash-normalizado.tests.ps1` verifica
# que las dos copias sean la misma. Las dos variantes de NormHash de los tests (mirror.tests y la MD5
# de review-loop-incremental) siguen con su propio cálculo.
#
# El contrato, en una línea: **sha256 hex minúscula de los BYTES del contenido con las secuencias de
# fin de línea (CRLF y CR) unificadas a LF.**
#
# La normalización opera **sobre bytes y NO decodifica a texto**. Esto es deliberado y reciente
# (ADR-0007, 2026-08-31): decodificar a texto haría desaparecer un BOM y colapsaría dos bytes
# inválidos cualesquiera en `U+FFFD`, y ambos son cambios reales que quedarían sellados como iguales.
# Este módulo existe para detectar drift de contenido sin perder cambios en silencio, así que el BOM
# y la corrupción SÍ cuentan. Lo único que se trata como ruido de plataforma es el fin de línea, la
# misma línea que ADR-0007 traza para copy-scaffold.
#
# La técnica: los bytes se ven a través de Latin1 (ISO-8859-1, code page 28591), que es una
# biyección total byte↔char — cada byte 0x00-0xFF es exactamente un carácter U+0000-U+00FF, sin
# pérdida ni en decode ni en encode. Eso permite normalizar el EOL y separar el frontmatter con las
# operaciones de string de siempre, sin arriesgar la decodificación destructiva que UTF-8 haría con
# un BOM o un byte inválido. Como todos los caracteres quedan por debajo de U+0100, las comparaciones
# se hacen igualmente en modo Ordinal, no cultural.
#
# Lo que deliberadamente NO hace, porque acá se SELLA contenido en vez de compararlo por similitud —
# es la diferencia con la métrica de `tools/recover-skill-bases.py`, que sí recorta:
#   - No recorta espacios ni líneas en blanco, ni al principio ni al final.
#   - No colapsa saltos de línea repetidos.
#   - No toca el salto de línea final: un archivo que termina sin salto es otro contenido.
#
# `-Scope Body` hashea el cuerpo sin el frontmatter. Sirve para preguntar "¿cambió el contenido de
# esta skill?" ignorando la `description`, que es donde vive casi todo nuestro drift propio
# (ADR-0005). Reglas del frontmatter, declaradas y cubiertas por test:
#   - Solo hay frontmatter si el documento ARRANCA con una línea `---`. Un `---` en el medio es una
#     regla horizontal de markdown y no abre nada.
#   - Lo cierra la primera línea posterior que sea EXACTAMENTE `---`. Un `----` no cierra.
#   - Si no hay línea de cierre, no hay frontmatter: el cuerpo es todo el contenido. Es el caso de
#     un documento truncado, y recortar ahí se comería texto real en silencio.

# Latin1: biyección byte<->char sin pérdida. Se crea una sola vez al dot-sourcear.
$script:NHLatin1 = [Text.Encoding]::GetEncoding(28591)

function Get-NormalizedHash {
  [CmdletBinding(DefaultParameterSetName = 'Content')]
  param(
    # Archivo a hashear. Se resuelve a ruta absoluta antes de leer: `[IO.File]` usa el CWD del
    # proceso y no el `Set-Location` de PowerShell, así que una ruta relativa leería otro archivo.
    # Se leen los BYTES crudos: un BOM o un byte inválido son parte del contenido, no ruido.
    [Parameter(Mandatory, ParameterSetName = 'Path')][string]$Path,

    # Contenido ya en memoria. Un string de PowerShell ya está decodificado (no tiene BOM ni bytes
    # inválidos); su representación canónica en bytes es UTF-8, que es lo que se hashea.
    [Parameter(Mandatory, ParameterSetName = 'Content')][AllowEmptyString()][string]$Content,

    [ValidateSet('File', 'Body')][string]$Scope = 'File'
  )

  if ($PSCmdlet.ParameterSetName -eq 'Path') {
    # Resolve-Path tira si el archivo no existe, que es el comportamiento que queremos: devolver el
    # hash del contenido vacío dejaría pasar en verde un sellado con la ruta mal escrita.
    $full  = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).ProviderPath
    $bytes = [IO.File]::ReadAllBytes($full)
  } else {
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes($Content)
  }

  # A string byte-fiel: cada byte -> un char U+00xx, sin pérdida. NO es decodificación de texto.
  $s = $script:NHLatin1.GetString($bytes)

  # Normalización del fin de línea. El orden importa: primero CRLF, después los CR que hayan quedado
  # sueltos. Sobre el string byte-fiel es equivalente a hacerlo sobre los bytes, porque `\r` y `\n`
  # son ASCII y Latin1 los mapea a sí mismos.
  $s = $s -replace "`r`n", "`n"
  $s = $s -replace "`r", "`n"

  if ($Scope -eq 'Body') {
    $target = $s
    # Ordinal en las tres comparaciones: aunque todos los chars son < U+0100 tras Latin1, el default
    # cultural de .NET no tiene por qué ser una comparación de bytes, y este sello debe ser idéntico
    # entre máquinas y culturas.
    if ($s.StartsWith("---`n", [StringComparison]::Ordinal)) {
      # Se busca desde el índice 3 (justo después del delimitador de apertura) una línea que sea
      # exactamente `---`: por eso el patrón incluye el salto de los dos lados. Buscar `---` pelado
      # con IndexOf tomaría la apertura misma, o cualquier `----` del cuerpo.
      $cierre = $s.IndexOf("`n---`n", 3, [StringComparison]::Ordinal)
      if ($cierre -ge 0) {
        $target = $s.Substring($cierre + 5)
      } elseif ($s.EndsWith("`n---", [StringComparison]::Ordinal)) {
        # Cierre en la última línea, sin salto final: el cuerpo es vacío.
        $target = ""
      }
    }
  } else {
    $target = $s
  }

  # De vuelta a los bytes exactos (Latin1 es biyección, así que reconstruye los bytes normalizados
  # tal cual, BOM y bytes inválidos incluidos) y se hashea eso.
  $bytesOut = $script:NHLatin1.GetBytes($target)
  $sha = [Security.Cryptography.SHA256]::Create()
  try { $digest = $sha.ComputeHash($bytesOut) } finally { $sha.Dispose() }
  return [BitConverter]::ToString($digest).Replace('-', '').ToLowerInvariant()
}

# ---- Regla de coincidencia del manifest (la usan compare-scaffold.ps1 y reseal-manifest.ps1) ----
#
# Viven acá y no en cada script para que haya una sola definición: la copia de este archivo en
# `skills/upgrade-bootstrap/scripts/` está verificada idéntica por test, y una regla escrita dos veces
# a mano puede divergir y hacer que compare y reseal no coincidan sobre el mismo archivo.
#
# Los manifests canónicos se sellan con `Get-NormalizedHash`. Los de proyecto sellados antes guardan
# el hash CRUDO de los bytes que tenía ese checkout, así que un hash sellado coincide con un archivo si
# es cualquiera de: su hash normalizado, su hash crudo, o el hash de su contenido con todos los fines
# de línea escritos como CRLF (una base cruda sellada desde un checkout CRLF, para un archivo que hoy
# es LF). Cada uno significa el mismo contenido con a lo sumo los fines de línea cambiados, así que
# ninguno puede marcar como intacto un archivo tocado. El crudo es el único que reconoce un archivo
# con fines de línea mezclados: ni el normalizado ni el CRLF reconstruyen esos bytes.

# sha256 del contenido con todos los fines de línea como CRLF (CRLF y CR sueltos pasan primero a LF).
function Get-CrlfHash([Parameter(Mandatory)][string]$Path) {
  $full = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).ProviderPath
  $s = $script:NHLatin1.GetString([IO.File]::ReadAllBytes($full))
  $s = (($s -replace "`r`n", "`n") -replace "`r", "`n") -replace "`n", "`r`n"
  $sha = [Security.Cryptography.SHA256]::Create()
  try { $digest = $sha.ComputeHash($script:NHLatin1.GetBytes($s)) } finally { $sha.Dispose() }
  return [BitConverter]::ToString($digest).Replace('-', '').ToLowerInvariant()
}

# Los tres hashes de un archivo (n normalizado, r crudo, c CRLF), o $null si no existe.
function Get-Hashes([Parameter(Mandatory)][string]$Path) {
  if (-not (Test-Path -LiteralPath $Path)) { return $null }
  @{ n = Get-NormalizedHash -Path $Path
     r = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
     c = Get-CrlfHash -Path $Path }
}

function Test-Sealed($Hashes, $Sealed) {
  ($Sealed -eq $Hashes.n) -or ($Sealed -eq $Hashes.r) -or ($Sealed -eq $Hashes.c)
}
