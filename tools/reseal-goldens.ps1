# tools/reseal-goldens.ps1 — re-graba los goldens de una sola linea (`tests/fixtures/*.golden.md`).
#
# Hermano de `tools/reseal-step0b.ps1`, que sella un TRAMO entero del `SKILL.md`. Este sella
# parrafos sueltos que viven en varias copias y tienen que decir exactamente lo mismo en todas:
#
#   - Los dos parrafos del Step 2 (`SKILL.md` de las tres skills): la frase que manda verificar la
#     copia y el parrafo del reporte JSON con la orden de reportar `overwritten` (ADR-0007), que es
#     la precondicion que el Step 0b/A consume (`Keep that report`).
#   - Los dos parrafos del techo de `docs/ai-workflow/` (repo + los 3 scaffolds): el del
#     AI_DEVELOPMENT_WORKFLOW y el de DEPLOYMENT_RULES.
#
# Por que un golden y no una ancla de prosa: se midio tres veces en este repo que un chequeo de
# presencia sobre texto no expresa semantica —la negacion satisface el ancla, y comentar la linea
# en HTML tambien—, y que parchar la prosa del ancla no converge. El golden no IMPIDE la
# reescritura: la vuelve visible: la suite se pone roja y re-grabar es el paso donde un humano mira
# el diff y decide. Editar el fixture a mano, en cambio, sella el bug sin que nadie lo mire.
#
#   1. Edita el parrafo en la copia de referencia.
#   2. Propagalo a las otras (el CLAUDE.md pide el mismo cambio en las tres/cuatro copias).
#   3. Mira `git diff tests/fixtures/`. Si el cambio es el que quisiste, commitea fixture y fuentes
#      JUNTOS; si no lo es, ahi esta el bug.
#
# Los goldens se graban en LF y sin BOM, que es como los tests los normalizan antes de comparar.
[CmdletBinding()]
param([switch]$Check)
$ErrorActionPreference = "Stop"

$repo = Split-Path $PSScriptRoot -Parent

# Cada golden declara donde vive el parrafo, como se lo reconoce y en que copias tiene que coincidir.
# `seccion` acota la busqueda a un tramo del archivo: sin eso, mover el parrafo a un apendice
# titulado "historical wording (DO NOT FOLLOW)" dejaba el golden verde (medido).
$goldens = @(
  @{
    fixture = "tests\fixtures\step2-parrafos.golden.md"
    copias  = @("skills\bootstrap-ai-project\SKILL.md", "skills\bootstrap-personal-project\SKILL.md",
                "skills\bootstrap-southpoint-project\SKILL.md")
    seccion = "## Step 2 "
    anclas  = @("Before committing, verify the copy landed cleanly:", "The script prints a JSON report on stdout:")
  }
  @{
    fixture = "tests\fixtures\techo-ai-development-workflow.golden.md"
    copias  = @("docs\ai-workflow\AI_DEVELOPMENT_WORKFLOW.md") + @("ai", "personal", "southpoint" |
                ForEach-Object { "skills\bootstrap-$_-project\assets\scaffold\docs\ai-workflow\AI_DEVELOPMENT_WORKFLOW.md" })
    seccion = $null
    anclas  = @("ceiling is measured when the slice opens")
  }
  @{
    fixture = "tests\fixtures\techo-deployment-rules.golden.md"
    copias  = @("docs\ai-workflow\DEPLOYMENT_RULES.md") + @("ai", "personal", "southpoint" |
                ForEach-Object { "skills\bootstrap-$_-project\assets\scaffold\docs\ai-workflow\DEPLOYMENT_RULES.md" })
    seccion = $null
    anclas  = @("measured when the slice opens")
  }
)

# Devuelve las lineas ancladas de UNA copia, en el orden de `anclas`. Tira si alguna no aparece
# exactamente una vez dentro de la seccion: un golden grabado sobre cero o dos coincidencias sella
# cualquier cosa.
function LineasAncladas([string]$path, $g) {
  if (-not (Test-Path -LiteralPath $path)) { throw "no existe $path" }
  $t = [IO.File]::ReadAllText($path) -replace "`r`n", "`n" -replace "`r", "`n"
  if ($g.seccion) {
    # El encabezado tiene que ser UNICO: `IndexOf` toma el primero, asi que un encabezado señuelo
    # puesto antes del real sellaria una copia decorativa dejando el procedimiento verdadero libre.
    $veces = $t.Split(@("`n" + $g.seccion), [StringSplitOptions]::None).Length - 1
    if ($veces -ne 1) { throw "$path : la seccion '$($g.seccion)' aparece $veces veces donde tiene que aparecer una" }
    $i = $t.IndexOf("`n" + $g.seccion) + 1
    $j = $t.IndexOf("`n## ", $i) + 1
    $t = if ($j -le 0) { $t.Substring($i) } else { $t.Substring($i, $j - $i) }
  }
  $out = @()
  $pos = @()
  foreach ($a in $g.anclas) {
    $hits = @($t -split "`n" | Where-Object { $_.Contains($a) })
    if ($hits.Count -ne 1) { throw "$path : el ancla '$a' aparece $($hits.Count) veces donde tiene que aparecer una" }
    $out += $hits[0]
    $pos += $t.IndexOf($hits[0])
  }
  # El ORDEN tambien: la lista se arma iterando las anclas, no el documento, asi que intercambiar
  # dos parrafos daba un `-join` identico y el reseal decia "sin cambios" mientras la suite ya
  # estaba roja por su propio assert de orden. Sin esto, el reseal certificaba un documento que la
  # suite rechazaba. Si el reorden es DELIBERADO, esto tampoco lo sella: hay que reordenar las dos
  # listas de anclas (la de aca y `$anclas2` en `tests/mirror.tests.ps1`) y despues re-grabar.
  for ($k = 1; $k -lt $pos.Count; $k++) {
    if ($pos[$k] -eq $pos[$k - 1]) { throw "$path : dos anclas caen en la MISMA linea (posicion $($pos[$k])): el parrafo se fusiono con el de al lado" }
    if ($pos[$k] -lt $pos[$k - 1]) { throw "$path : los parrafos anclados no estan en el orden declarado (posiciones: $($pos -join ', '))" }
  }
  return $out -join "`n"
}

# Cada golden se procesa aislado: un `throw` global cortaba el bucle y dejaba los que siguen sin
# chequear, asi que una corrida podia reportar un problema y esconder otro. Se acumulan y se sale
# distinto de cero al final.
$fallo = 0
foreach ($g in $goldens) {
  # Se graba desde la primera copia, pero solo si TODAS coinciden: sellar una divergencia dejaria el
  # golden certificando un espejado roto, que es justo lo que el test existe para ver. No se nombra
  # a la divergente: si la rota es la primera, el mensaje mandaria a propagar desde la equivocada.
  try {
    $bloques = @($g.copias | ForEach-Object { LineasAncladas (Join-Path $repo $_) $g })
  } catch {
    Write-Host "ERROR en $($g.fixture): $($_.Exception.Message)"
    $fallo = 1
    continue
  }
  $ref = $bloques[0]
  if (@($bloques | Where-Object { $_ -cne $ref }).Count -gt 0) {
    Write-Host "ERROR en $($g.fixture): el parrafo no coincide entre las $($g.copias.Count) copias; compara y propaga antes de sellar"
    $fallo = 1
    continue
  }

  $destino = Join-Path $repo $g.fixture
  $previo = if (Test-Path -LiteralPath $destino) {
    ([IO.File]::ReadAllText($destino) -replace "`r`n", "`n" -replace "`r", "`n").TrimEnd("`n")
  } else { $null }

  if ($previo -ceq $ref) { "sin cambios: $($g.fixture) ($($ref.Length) chars)"; continue }

  # `-Check` sale ANTES de escribir: un flag de chequeo que ensucia el `git status` de quien lo corre
  # para verificar deja de servir para verificar.
  if ($Check) {
    Write-Host "desactualizado: $($g.fixture) -- el parrafo cambio y nadie lo re-grabo"
    $fallo = 1
    continue
  }

  $dir = Split-Path $destino -Parent
  if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
  [IO.File]::WriteAllText($destino, $ref + "`n", (New-Object Text.UTF8Encoding($false)))
  $verbo = if ($null -eq $previo) { "creado" } else { "actualizado" }
  "golden $verbo ($($ref.Length) chars) -> $($g.fixture)"
}

if ($fallo) { exit 1 }
if (-not $Check) { "revisa 'git diff tests/fixtures/' antes de commitear" }
exit 0
