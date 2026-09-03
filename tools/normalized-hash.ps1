# tools/normalized-hash.ps1 — la unica forma de hashear contenido en este repo.
#
# Se usa dot-sourceando el archivo:  . (Join-Path $repo "tools/normalized-hash.ps1")
#
# Por que existe: el hash con el que se sellan los manifests del scaffold se calculaba sobre los
# bytes crudos del archivo, o sea sobre como el checkout de cada maquina escribio los fines de
# linea. Consecuencia medida: un manifest sellado en una maquina rutea archivos identicos a
# `customized` en otra, y regenerarlo desde un worktree fresco produce hashes distintos para el
# mismo contenido (memoria `bug-autocrlf-manifests-hashes-mixtos`). El calculo estaba ademas
# replicado en tres consumidores, cada uno con su propia variante.
#
# El contrato, en una linea: **sha256 hex minuscula de los bytes UTF-8 del contenido con los fines
# de linea unificados a LF y el BOM descartado.**
#
# Lo que la normalizacion SI hace:
#   - CRLF y CR sueltos pasan a LF (un archivo no cambia de identidad por el `autocrlf` del clon).
#   - El BOM UTF-8 inicial se descarta (es un artefacto del editor, no contenido).
#   - El texto se codifica siempre como UTF-8, nunca como la codepage de la consola.
#
# Lo que deliberadamente NO hace, porque aca se SELLA contenido en vez de compararlo — es la
# diferencia con la metrica de similitud de `tools/recover-skill-bases.py`, que si recorta:
#   - No recorta espacios ni lineas en blanco, ni al principio ni al final.
#   - No colapsa saltos de linea repetidos.
#   - No toca el salto de linea final: un archivo que termina sin salto es otro contenido.
#
# `-Scope Body` hashea el cuerpo sin el frontmatter. Sirve para preguntar "cambio el contenido de
# esta skill?" ignorando la `description`, que es donde vive casi todo nuestro drift propio
# (ADR-0005). Reglas del frontmatter, declaradas y cubiertas por test:
#   - Solo hay frontmatter si el documento ARRANCA con una linea `---`. Un `---` en el medio es una
#     regla horizontal de markdown y no abre nada.
#   - Lo cierra la primera linea posterior que sea EXACTAMENTE `---`. Un `----` no cierra.
#   - Si no hay linea de cierre, no hay frontmatter: el cuerpo es todo el contenido. Es el caso de
#     un documento truncado, y recortar ahi se comeria texto real en silencio.

function Get-NormalizedHash {
  [CmdletBinding(DefaultParameterSetName = 'Content')]
  param(
    # Archivo a hashear. Se resuelve a ruta absoluta antes de leer: `[IO.File]` usa el CWD del
    # proceso y no el `Set-Location` de PowerShell, asi que una ruta relativa leeria otro archivo.
    [Parameter(Mandatory, ParameterSetName = 'Path')][string]$Path,

    # Contenido ya en memoria. Mismo contrato que `-Path`: la ruta nunca entra al hash.
    [Parameter(Mandatory, ParameterSetName = 'Content')][AllowEmptyString()][string]$Content,

    [ValidateSet('File', 'Body')][string]$Scope = 'File'
  )

  if ($PSCmdlet.ParameterSetName -eq 'Path') {
    # Resolve-Path tira si el archivo no existe, que es el comportamiento que queremos: devolver el
    # hash del contenido vacio dejaria pasar en verde un sellado con la ruta mal escrita.
    $full = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).ProviderPath
    $text = [IO.File]::ReadAllText($full)
  } else {
    $text = $Content
  }

  # Normalizacion. El orden importa: primero CRLF, despues los CR que hayan quedado sueltos.
  $norm = $text -replace "`r`n", "`n"
  $norm = $norm -replace "`r", "`n"
  if ($norm.Length -gt 0 -and $norm[0] -eq [char]0xFEFF) { $norm = $norm.Substring(1) }

  if ($Scope -eq 'Body') {
    $target = $norm
    if ($norm.StartsWith("---`n")) {
      # Se busca desde el indice 3 (justo despues del delimitador de apertura) una linea que sea
      # exactamente `---`: por eso el patron incluye el salto de los dos lados. Buscar `---` pelado
      # con IndexOf tomaria la apertura misma, o cualquier `----` del cuerpo.
      $cierre = $norm.IndexOf("`n---`n", 3)
      if ($cierre -ge 0) {
        $target = $norm.Substring($cierre + 5)
      } elseif ($norm.EndsWith("`n---")) {
        # Cierre en la ultima linea, sin salto final: el cuerpo es vacio.
        $target = ""
      }
    }
  } else {
    $target = $norm
  }

  $bytes = [Text.UTF8Encoding]::new($false).GetBytes($target)
  $sha = [Security.Cryptography.SHA256]::Create()
  try { $digest = $sha.ComputeHash($bytes) } finally { $sha.Dispose() }
  return [BitConverter]::ToString($digest).Replace('-', '').ToLowerInvariant()
}
