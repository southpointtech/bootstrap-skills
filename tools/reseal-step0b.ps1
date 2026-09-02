# tools/reseal-step0b.ps1 — re-graba el golden del Step 0b (`tests/fixtures/step0b.golden.md`).
#
# El golden congela la mecánica del modo adopción: `tests/mirror.tests.ps1` compara contra él el
# tramo `## Step 0b` -> `## Step 1` de las TRES skills, así que cualquier edición de ese tramo pone
# la suite en rojo hasta que alguien re-grabe el golden. Eso es deliberado: la prosa del Step 0b es
# un procedimiento que un agente ejecuta sobre el `CLAUDE.md` de un proyecto ajeno, y los chequeos
# de presencia sobre texto no distinguen una orden de su negación. Re-grabar es el paso donde un
# humano mira el diff y decide.
#
#   1. Editá el Step 0b en `skills/bootstrap-ai-project/SKILL.md`.
#   2. Propagalo a las otras dos (el CLAUDE.md pide copiar el bloque entero, no editar tres veces).
#   3. Mirá `git diff` del golden que este script genera. Si el cambio es el que quisiste, commiteá
#      golden y skills JUNTOS; si no lo es, ahí está el bug.
#
# El golden se graba en LF y sin BOM, que es como el test lo normaliza antes de comparar.
[CmdletBinding()]
param([switch]$Check)
$ErrorActionPreference = "Stop"

$repo = Split-Path $PSScriptRoot -Parent
$ini = '## Step 0b — Adoption mode'
$fin = '## Step 1 — Project info'   # el encabezado ENTERO, no `## Step 1`: un prefijo lo satisface una cita
$esperadas = @("bootstrap-ai-project", "bootstrap-personal-project", "bootstrap-southpoint-project")

function Step0b($skill) {
  $p = Join-Path $repo "skills\$skill\SKILL.md"
  if (-not (Test-Path -LiteralPath $p)) { throw "no existe $p" }
  # Los dos bordes anclados a principio de línea, y el cierre es el PRIMER `## ` que venga después,
  # que además tiene que ser el Step 1. Tiene que ser idéntico al de `mirror.tests.ps1`: si los cortes
  # difieren, el reseal sella algo distinto de lo que el test compara y el golden no converge nunca.
  # Como substring suelto, una frase del Step 0b que cite cualquiera de los dos headings movía el
  # borde y sellaba un tramo recortado sin que nada avisara (medido en las dos puntas).
  $t = [IO.File]::ReadAllText($p) -replace "`r`n", "`n" -replace "`r", "`n"
  $i = $t.IndexOf("`n" + $ini) + 1
  if ($i -le 0) { throw "$skill : no se encontró '$ini' como encabezado" }
  $j = $t.IndexOf("`n## ", $i) + 1
  if ($j -le 0) { throw "$skill : no se encontró ningún encabezado '## ' después del Step 0b" }
  $cierre = ($t.Substring($j) -split "`n")[0]
  if ($cierre -cne $fin) {
    throw "$skill : el Step 0b no cierra en '$fin' sino en '$cierre' — ¿una cita a principio de línea adentro del tramo?"
  }
  return $t.Substring($i, $j - $i)
}

# Se graba desde ai-project, pero solo si las tres coinciden: sellar una divergencia dejaría el
# golden certificando un espejado roto, que es justo lo que el test existe para ver.
$bloques = @{}
foreach ($s in $esperadas) { $bloques[$s] = Step0b $s }
$ref = $bloques[$esperadas[0]]
# No se nombra a las divergentes: se comparan todas contra la primera, así que si la rota es JUSTO
# la primera el mensaje lista a las dos sanas y manda a propagar desde la equivocada — que es la
# forma de esparcir el bug a las tres. Se dice que no coinciden y listo.
if (@($esperadas | Where-Object { $bloques[$_] -cne $ref }).Count -gt 0) {
  $largos = ($esperadas | ForEach-Object { "$_ $($bloques[$_].Length)" }) -join ' | '
  throw "el Step 0b no coincide entre las tres skills; compará y propagá el bloque antes de sellar ($largos)"
}

$destino = Join-Path $repo "tests\fixtures\step0b.golden.md"

$previo = if (Test-Path -LiteralPath $destino) {
  [IO.File]::ReadAllText($destino) -replace "`r`n", "`n" -replace "`r", "`n"
} else { $null }

if ($previo -ceq $ref) { "golden sin cambios ($($ref.Length) chars)"; exit 0 }

# `-Check` sale ANTES de crear nada: un flag de chequeo que ensucia el `git status` de quien lo corre
# para verificar deja de servir para verificar.
if ($Check) {
  Write-Host "el golden esta desactualizado: el Step 0b cambio y nadie lo re-grabo"
  exit 1
}

$dir = Split-Path $destino -Parent
if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
[IO.File]::WriteAllText($destino, $ref, (New-Object Text.UTF8Encoding($false)))
$verbo = if ($null -eq $previo) { "creado" } else { "actualizado" }
"golden $verbo ($($ref.Length) chars) -> tests/fixtures/step0b.golden.md"
"revisa 'git diff tests/fixtures/step0b.golden.md' antes de commitear"
