# tests/review-loop-incremental.tests.ps1 — runner sin Pester.
# Correr: pwsh -NoProfile -File tests/review-loop-incremental.tests.ps1
#
# El loop revisa el DELTA SIN REVISAR, no el rango completo de la rama en cada turno. Eso lo
# sostiene el marcador de revisión (.claude/scripts/review-marker.ps1) y solo sirve si las
# instrucciones del loop realmente lo usan: fijarlo antes del primer turno, pedirle el rango en
# cada corrida de review y avanzarlo al cerrar el turno. Además, los fixes que el propio loop
# escribe tienen que arrancar por un test que falle sin el fix (RED): 59 de 235 reportes de turno
# atribuían sus hallazgos a los fixes del turno anterior.
# Contrato verificado sobre las CUATRO copias: las 3 skills bootstrap y la copia de este repo.
$ErrorActionPreference = "Stop"
$repo = Split-Path $PSScriptRoot -Parent
$script:failures = 0
function Assert($cond, $msg) {
  if ($cond) { Write-Host "ok:   $msg" } else { Write-Host "FAIL: $msg"; $script:failures++ }
}
# [regex]::Match(...).Index vale 0 cuando NO hubo match (Match.Empty), no -1. Sin esto, "no está"
# y "está al principio" son el mismo número y cualquier assert de posición pasa siempre.
function Idx([string]$s, [string]$pattern) {
  $m = [regex]::Match($s, $pattern)
  if ($m.Success) { return $m.Index } else { return -1 }
}

# Las 4 raíces que tienen que llevar el marcador y el loop idénticos.
$roots = @()
foreach ($s in (Get-ChildItem (Join-Path $repo "skills") -Directory | Where-Object Name -like "bootstrap-*-project")) {
  $roots += [pscustomobject]@{ Name = $s.Name; Path = (Join-Path $s.FullName "assets\scaffold") }
}
$roots += [pscustomobject]@{ Name = "repo"; Path = $repo }

Assert ($roots.Count -eq 4) "hay 4 copias del scaffold a verificar ($($roots.Count))"

foreach ($r in $roots) {
  # 1. El script del marcador existe en la copia.
  $script = Join-Path $r.Path ".claude\scripts\review-marker.ps1"
  Assert (Test-Path -LiteralPath $script) "$($r.Name): existe .claude/scripts/review-marker.ps1"

  # 2. Las instrucciones del loop usan los tres verbos y exigen RED.
  $files = @(
    (Join-Path $r.Path ".claude\commands\review-loop.md"),
    (Join-Path $r.Path ".agents\skills\review-loop\SKILL.md")
  )
  foreach ($f in $files) {
    $rel = $f.Substring($r.Path.Length).TrimStart('\') -replace '\\', '/'
    if (-not (Test-Path -LiteralPath $f)) { Assert $false "$($r.Name): existe $rel"; continue }
    $txt = [IO.File]::ReadAllText($f)

    Assert ($txt -match 'review-marker\.ps1')            "$($r.Name): $rel usa el marcador de revisión"
    Assert ($txt -match '-Action\s+advance')             "$($r.Name): $rel avanza el marcador"
    Assert ($txt -match '-Action\s+range')               "$($r.Name): $rel pide el rango al marcador"
    # El delta vacío cierra el loop en vez de inventarse un rango. La regla concreta, no la
    # palabra "empty": aparece 4 veces en el archivo, así que un match suelto pasa aunque se
    # borren las dos frases que mandan.
    Assert ($txt -match '(?i)genuinely nothing new') "$($r.Name): $rel define qué hacer con el rango vacío"
    # \s+ y no un espacio: el archivo va envuelto a 100 columnas y la frase se parte según dónde
    # caiga; un assert atado al ancho de línea da RED espurio en el próximo reflow.
    Assert ($txt -match '(?is)do\s+not\s+fall\s+back\s+to\s+.main\.\.\.HEAD') "$($r.Name): $rel prohíbe volver al rango completo de la rama"
    # Vacío+0 ("no hay delta") y vacío+2 ("no puedo determinar") no son lo mismo: cerrar el loop
    # sobre un exit 2 reporta limpio un slice que nadie miró. Se ancla en la FILA de la tabla, no
    # en la cadena "exit 2" suelta: aparece también en la prosa, así que un match flojo sobrevive
    # a borrar la tabla entera.
    Assert ($txt -match '(?m)^\|\s*2\s*\|\s*empty\s*\|')  "$($r.Name): $rel documenta el exit 2 en la tabla de contrato"
    Assert ($txt -match '(?is)do\s+not\s+close\s+the\s+loop') "$($r.Name): $rel prohíbe cerrar el loop con rango indeterminable"
    # RED obligatorio: el fix arranca por un test que falla sin el fix.
    Assert ($txt -match '(?i)\bfails? without the fix\b') "$($r.Name): $rel exige RED en los fixes del loop"

    # El ORDEN es el invariante que sostiene todo el diseño: el marcador avanza DESPUÉS de la
    # corrida de review y ANTES de los fixes. Al revés, el turno siguiente recibe un rango vacío
    # y los fixes del loop no los revisa nadie.
    #
    # Se ancla dentro de la sección "The loop": los tres verbos aparecen antes, en el bloque de
    # ejemplo de "The range", así que un IndexOf desde el principio del archivo mide el ejemplo y
    # no los pasos — se puede borrar el paso 1 entero y el assert seguía pasando.
    $loopAt = $txt.IndexOf('## The loop')
    Assert ($loopAt -ge 0) "$($r.Name): $rel tiene la sección de los pasos del turno"
    if ($loopAt -ge 0) {
      $steps = $txt.Substring($loopAt)
      # Regex y no literal: el archivo va envuelto a 100 columnas y la frase se parte según dónde
      # caiga. Y el índice pasa por `Idx`, que devuelve -1 cuando no hay match: `Match.Index` es
      # **0** en ese caso (no -1), así que leerlo crudo hacía pasar todos los `-ge 0` y volvía
      # tautológica la comparación de orden — se podía borrar el paso 1 entero y quedaba verde.
      $iRange   = Idx $steps '-Action\s+range'
      $iReview  = Idx $steps 'Run\s+\*{0,2}`?/slice-review'
      $iAdvance = Idx $steps '-Action\s+advance'
      $iFix     = Idx $steps 'fails?\s+without\s+the\s+fix'
      Assert ($iRange -ge 0) "$($r.Name): $rel arranca el turno pidiendo el rango"
      Assert ($iReview -ge 0) "$($r.Name): $rel corre el reviewer dentro del turno"
      Assert ($iAdvance -ge 0) "$($r.Name): $rel avanza el marcador dentro del turno"
      Assert ($iFix -ge 0) "$($r.Name): $rel exige RED dentro del turno"
      Assert (($iRange -ge 0) -and ($iReview -gt $iRange)) "$($r.Name): $rel pide el rango antes de la corrida de review"
      Assert (($iReview -ge 0) -and ($iAdvance -gt $iReview) -and ($iFix -gt $iAdvance)) "$($r.Name): $rel avanza el marcador después del review y antes de los fixes"
      # Los pasos no pueden contradecir a la sección de exit codes, que manda revisar el árbol y
      # dice textualmente "do not reach for `git diff <base>...HEAD`" — en exit 2 la base es
      # justamente lo que no se pudo resolver. El agente ejecuta los pasos numerados, así que la
      # contradicción gana. Assert negativo y acotado a la sección: fuera de ella, el fallback al
      # rango de la rama SÍ es correcto (marcador ausente, o marcador que quedó fuera de la
      # historia tras un rebase). Borrar el paso 1 para satisfacerlo rompe el assert de $iRange.
      Assert (-not ($steps -match '(?is)fall\s+back\s+to\s+the\s+branch\s+range')) "$($r.Name): $rel no manda al rango de la rama cuando la base es indeterminable"
    }
  }

  # 3. El hook del disparo no puede ordenar el rango que el loop prohíbe: es lo primero que el
  # agente lee cuando el loop arranca solo, y ya contradijo al loop una vez. El Test-Path va como
  # assert y no como condición: envuelto en un `if`, borrar el hook dejaba la suite en verde.
  $hook = Join-Path $r.Path ".claude\hooks\review-loop-trigger.ps1"
  Assert (Test-Path -LiteralPath $hook) "$($r.Name): existe .claude/hooks/review-loop-trigger.ps1"
  if (Test-Path -LiteralPath $hook) {
    $htxt = [IO.File]::ReadAllText($hook)
    Assert ($htxt -match 'review-marker\.ps1') "$($r.Name): el hook manda el rango al marcador"
    # El cierre de slice es un acto DECLARADO: sin el trailer, un commit cualquiera no dispara.
    Assert ($htxt -match 'Slice-Close:') "$($r.Name): el hook exige el trailer Slice-Close en un commit"
    # ...pero olvidarse del trailer no puede dejar un slice gigante sin revisar.
    Assert ($htxt -match '(?m)-le\s+400') "$($r.Name): el hook conserva la red de seguridad del techo"
    # El evento trae el cwd de la SESIÓN, no el directorio donde corrió el comando.
    Assert ($htxt -match '--format=%ct') "$($r.Name): el hook verifica que el commit ocurrió en ESTE repo"
  }
}

# Las 4 copias del marcador van byte a byte iguales (normalizando fin de línea por core.autocrlf).
# mirror.tests.ps1 compara las 3 skills ENTRE SÍ: la copia de este repo — la que corre acá — no
# entra en ninguna comparación, así que podría quedar vieja con toda la suite en verde.
function NormHash([string]$p) {
  $t = ([IO.File]::ReadAllText($p)) -replace "`r`n", "`n" -replace "`r", "`n"
  $md5 = [Security.Cryptography.MD5]::Create()
  return [BitConverter]::ToString($md5.ComputeHash([Text.Encoding]::UTF8.GetBytes($t)))
}
# Cada archivo se compara CONSIGO MISMO entre las 4 raíces, nunca contra su par: el comando y el
# SKILL.md difieren a propósito en el frontmatter (el SKILL.md lleva los triggers en español).
$mirrored = @(
  ".claude\scripts\review-marker.ps1",
  ".claude\commands\review-loop.md",
  ".agents\skills\review-loop\SKILL.md",
  ".claude\commands\slice-review.md",
  ".agents\skills\slice-review\SKILL.md"
)
foreach ($rel in $mirrored) {
  $hashes = @{}
  foreach ($r in $roots) {
    $p = Join-Path $r.Path $rel
    if (Test-Path -LiteralPath $p) { $hashes[$r.Name] = NormHash $p }
  }
  $name = $rel -replace '\\', '/'
  Assert ($hashes.Count -eq 4) "las 4 copias de $name existen ($($hashes.Count))"
  Assert ((($hashes.Values | Select-Object -Unique).Count) -eq 1) "las 4 copias de $name son idénticas en contenido"
}

if ($script:failures -eq 0) { Write-Host "TODOS LOS TESTS PASARON"; exit 0 }
else { Write-Host "$($script:failures) test(s) FALLARON"; exit 1 }
