# tests/mirror.tests.ps1 — runner sin Pester. Correr: pwsh -NoProfile -File tests/mirror.tests.ps1
# Espejado entre las skills bootstrap-*-project: mismo SET de archivos e identidad de CONTENIDO
# en todo lo que no está en la allowlist de divergencia (archivos de variante).
# El hash se toma sobre el contenido con line-endings normalizados (CRLF/CR -> LF): con
# core.autocrlf=true el working tree puede materializar el MISMO contenido git con bytes
# distintos según cómo llegó cada archivo (checkout=CRLF, escritura de agente=LF, copia=preserva).
# El invariante real es identidad de contenido; el único consumidor de este chequeo es este test.
$ErrorActionPreference = "Stop"
$repo = Split-Path $PSScriptRoot -Parent
$skills = @(Get-ChildItem (Join-Path $repo "skills") -Directory | Where-Object Name -like "bootstrap-*-project")
$script:failures = 0
function Assert($cond, $msg) {
  if ($cond) { Write-Host "ok:   $msg" } else { Write-Host "FAIL: $msg"; $script:failures++ }
}

# Son TRES y el CLAUDE.md las nombra: southpoint, personal, ai-project. Se asertan los NOMBRES, no
# la cantidad: con `-ge 2` una skill podía desaparecer y el espejado seguía verde sobre las dos que
# quedaran, y contando `-ge 3` bastaba con que hubiera una cuarta cualquiera para tapar la ausencia
# de una de éstas (medido las dos veces).
$esperadas = @("bootstrap-ai-project", "bootstrap-personal-project", "bootstrap-southpoint-project")
$ausentes = @($esperadas | Where-Object { $_ -notin $skills.Name })
Assert ($ausentes.Count -eq 0) "están las 3 skills bootstrap-*-project que nombra el CLAUDE.md (faltan: $($ausentes -join ', '))"

# Archivos de variante: PUEDEN divergir entre skills. Todo lo demás debe ser byte-idéntico.
$allow = @(
  "SKILL.md",
  "assets/scaffold/CLAUDE.md",
  "assets/scaffold/.bootstrap-manifest.json",
  "assets/scaffold/docs/ai-workflow/AI_DEVELOPMENT_WORKFLOW.md",
  "assets/scaffold/docs/ai-workflow/DEPLOYMENT_RULES.md",
  "assets/scaffold/docs/ai-workflow/PRD_TEMPLATE.md",
  "assets/scaffold/docs/ai-workflow/QA_CHECKLIST.md",
  "assets/scaffold/docs/ai-workflow/TASK_TEMPLATE.md",
  "assets/scaffold/docs/agents/issue-tracker.md",
  "scripts/gen-mcp-json.ps1"
)

function RelFiles($skillDir) {
  Get-ChildItem $skillDir -Recurse -File -Force | ForEach-Object {
    [IO.Path]::GetRelativePath($skillDir, $_.FullName) -replace '\\', '/'
  } | Sort-Object
}

# Hash del contenido con line-endings normalizados (ver cabecera). Inmune a autocrlf.
function NormHash($path) {
  $text = [IO.File]::ReadAllText($path)
  $norm = $text -replace "`r`n", "`n" -replace "`r", "`n"
  $sha  = [Security.Cryptography.SHA256]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes($norm))
  [BitConverter]::ToString($sha).Replace("-", "")
}

$ref = $skills[0]
$refFiles = @(RelFiles $ref.FullName)
foreach ($other in ($skills | Select-Object -Skip 1)) {
  $otherFiles = @(RelFiles $other.FullName)
  $diffSet = @(Compare-Object $refFiles $otherFiles | ForEach-Object { $_.InputObject })
  Assert ($diffSet.Count -eq 0) "$($other.Name): mismo set de archivos que $($ref.Name) (diff: $($diffSet -join ', '))"
  foreach ($rel in $refFiles) {
    if ($allow -contains $rel) { continue }
    $a = Join-Path $ref.FullName   $rel
    $b = Join-Path $other.FullName $rel
    if (-not (Test-Path -LiteralPath $b)) { continue }  # ya reportado por el diff de set
    $same = (NormHash $a) -eq (NormHash $b)
    Assert $same "$($other.Name): $rel idéntico en contenido a $($ref.Name)"
  }
}

# `SKILL.md` está en la allowlist como archivo ENTERO, así que los hashes de arriba no lo miran. Pero
# la regla del CLAUDE.md ("si cambiás la mecánica, aplicá el mismo cambio en las tres") sí gobierna
# una parte de él, y sin este bloque esa parte no tiene ninguna red: nada en la suite leía el
# contenido de los tres `SKILL.md`, así que una divergencia entre ellos pasaba en silencio.
# Se compara el Step 0b entero, del encabezado al fin: hoy es byte-idéntico en las tres y no tiene
# una palabra de contenido de variante. Empezar más abajo, en el step B, dejaba afuera el step A —
# donde vive "Keep that report", la precondición que B y D consumen— y una divergencia ahí pasaba
# verde (medido). El `## Step 0` sí queda afuera: Southpoint lleva ahí su chequeo de máquina, que es
# una divergencia legítima.
$mecIni = '## Step 0b — Adoption mode'
$mecFin = '## Step 1 — Project info'   # el encabezado ENTERO: ver el comentario de abajo
# Los dos delimitadores se buscan ANCLADOS a principio de línea, y el cierre exige además que el
# encabezado donde termina sea efectivamente el Step 1. Los tres chequeos tapan la misma clase de
# agujero: una frase del propio Step 0b que cite un heading corre el borde, el golden se regraba más
# corto, y lo que queda afuera sale de cobertura sin que nadie lo vea, porque `reseal-step0b.ps1`
# hace el mismo corte y los dos coinciden. Se midieron las tres variantes: la cita a media línea
# (`…continuá con ## Step 1`) sellaba 414 chars menos; la cita a principio de línea sobrevivía al
# anclado y sellaba 1201 menos; y correr el arranque —reescribiendo el bullet del Step 0 que nombra
# la sección— estiraba el tramo hasta tragarse el Step 0, donde southpoint diverge legítimamente, y
# rompía el espejado con una causa equivocada. En los tres casos la suite quedaba verde sobre el
# texto perdido. El corte real no se mueve por anclar; solo se cierran esas puertas.
function MecanicaStep0b($skillDir) {
  $t = [IO.File]::ReadAllText((Join-Path $skillDir "SKILL.md")) -replace "`r`n", "`n" -replace "`r", "`n"
  $i = $t.IndexOf("`n" + $mecIni) + 1       # +1: apunta al `#`, no al `\n` de antes
  if ($i -le 0) { return $null }
  # El tramo cierra en el PRIMER encabezado de nivel 2 que venga después, y ese encabezado tiene que
  # ser el Step 1. Buscar `## Step 1` directamente cerraba en la primera línea que EMPEZARA con él:
  # una cita a principio de línea adentro del Step 0b recortaba el tramo, el reseal sellaba 1201 chars
  # menos y la suite quedaba verde sobre lo que se perdió (medido). Así, una cita adentro pone rojo.
  $j = $t.IndexOf("`n## ", $i) + 1
  if ($j -le 0) { return $null }
  # La línea ENTERA, no un prefijo: con `## Step 1` a secas, una cita que arranque igual
  # (`## Step 1 is where you continue…`) satisface el chequeo y el tramo se corta ahí igual.
  if ((($t.Substring($j) -split "`n")[0]) -cne $mecFin) { return $null }
  return $t.Substring($i, $j - $i)
}
# Los asserts de abajo son la diferencia entre un test que muerde y uno que se autoaprueba: si un
# rename mueve los anclas, `MecanicaStep0b` devuelve $null en las TRES y comparar $null contra $null
# daría verde sobre cero contenido. Ése lo ataja el primero. Los headings se buscan anclados a
# principio de línea porque como substring sueltos una oración que los nombre alcanza, y `#### B.`
# contiene `### B.`.
#
# La red principal es el GOLDEN: el Step 0b entero, congelado en un fixture y comparado por hash
# normalizado. Cualquier edición se pone roja y el arreglo es re-grabar el golden A PROPÓSITO, en el
# mismo commit (`tools/reseal-step0b.ps1`). Es el único instrumento que cubre la EDICIÓN SEMÁNTICA:
# se midió que un chequeo de presencia sobre prosa no distingue una orden de su negación —el ancla
# `apply the map first` la satisfacía igual el texto que decía `do NOT apply the map first`— y que
# revertir cualquiera de los fixes de procedimiento pasaba en verde. Las anclas de prosa además
# resultaron frágiles al revés: una hubo que moverla en el mismo turno en que se escribió, porque el
# fix de al lado reescribió la frase que exigía.
#
# Los dos pisos y las anclas quedan como defensa en profundidad, para el día que alguien re-grabe el
# golden sin mirar el diff. Son ORTOGONALES entre sí — cada uno mata una familia que los otros dejan
# viva, medido ejecutando el mutante contra la suite:
#  - Piso POR SUB-PASO: vaciar un sub-paso mientras los demás compensan el total.
#  - Piso GLOBAL: la amputación uniforme — recortar los seis sub-pasos a poco más del piso deja cada
#    uno sobre su mínimo, los seis encabezados en su línea y las tres skills idénticas entre sí, con
#    el step B cortado a mitad de frase.
#  - ANCLAS: los pisos miden largo, no texto, así que ninguno ve borrar un párrafo concreto mientras
#    el resto del sub-paso lo compense.
# No se anotan los largos: el bloque cambia de tamaño con cada edición de prosa —este mismo comentario
# nació citando números medidos sobre el texto que el commit ya no shippeaba— y un número fijado acá
# deja de reproducir al turno siguiente. Los mutantes se describen, que es lo que no caduca.
#
# Las anclas son solo identificadores y comandos, nunca frases: un nombre de archivo o una línea de
# código no se reformulan sin cambiar la mecánica, y el `Move-Item` va con su path porque el nombre
# del cmdlet suelto lo satisfacía también la advertencia en prosa que habla de él, con el comando
# borrado. El piso por sub-paso es flojo a propósito: distingue "hay procedimiento" de "quedó el
# título", no vigila el largo de la prosa. Ninguna otra suite lee el contenido de estos `SKILL.md`.
$subPasos = @('### A. Copy the scaffold', '### B. Park', '### C. Classify', '### D. Present', '### E. Apply', '### F. Continue')
$anclas = @('docs/agents/legacy-claude.original.md', 'Move-Item "$proj\.bootstrap-backup\CLAUDE.md"')
$goldenPath = Join-Path $repo "tests/fixtures/step0b.golden.md"
$golden = if (Test-Path -LiteralPath $goldenPath) {
  [IO.File]::ReadAllText($goldenPath) -replace "`r`n", "`n" -replace "`r", "`n"
} else { $null }
Assert (-not [string]::IsNullOrWhiteSpace($golden)) "existe el golden del Step 0b y no está vacío (tests/fixtures/step0b.golden.md)"
$mecanicas = @{}
foreach ($s in $skills) {
  $m = MecanicaStep0b $s.FullName
  Assert ($null -ne $m) "$($s.Name): SKILL.md tiene la mecánica del Step 0b entre '$mecIni' y '$mecFin'"
  $faltan  = @()
  $vacios  = @()
  foreach ($p in $subPasos) {
    $k = if ($null -eq $m) { -1 } else { $m.IndexOf("`n$p") }
    if ($k -lt 0) { $faltan += $p; continue }
    # El cuerpo arranca DESPUÉS de la línea del título y llega hasta el próximo `### ` en su propia
    # línea, o hasta el fin del tramo si es el último sub-paso. Medirlo con el encabezado adentro
    # hacía que el piso real fuera de 251 a 277 según el largo del título, y que el mensaje de error
    # reportara el largo del TÍTULO diciendo que reportaba el del cuerpo.
    $ini = $m.IndexOf("`n", $k + 1)
    $sig = $m.IndexOf("`n### ", $k + 1)
    $cuerpo = if ($ini -lt 0) { "" } elseif ($sig -lt 0) { $m.Substring($ini) } else { $m.Substring($ini, $sig - $ini) }
    if ($cuerpo.Length -lt 300) { $vacios += "$p ($($cuerpo.Length))" }
  }
  $faltanAnclas = @($anclas | Where-Object { -not ($null -ne $m -and $m.Contains($_)) })
  Assert ($faltan.Count -eq 0) "$($s.Name): la mecánica del Step 0b abre sus $($subPasos.Count) sub-pasos en su propia línea (faltan: $($faltan -join ', '))"
  Assert ($vacios.Count -eq 0) "$($s.Name): cada sub-paso del Step 0b tiene cuerpo, no solo el título (flacos: $($vacios -join ', '))"
  Assert ($null -ne $m -and $m.Length -gt 5000) "$($s.Name): la mecánica del Step 0b conserva su cuerpo completo, no un resumen de cada sub-paso ($(if ($null -eq $m) { 0 } else { $m.Length }) chars)"
  Assert ($faltanAnclas.Count -eq 0) "$($s.Name): la mecánica del Step 0b conserva el procedimiento del modo adopción (faltan: $($faltanAnclas -join ', '))"
  Assert ($null -ne $golden -and $null -ne $m -and $m -ceq $golden) "$($s.Name): la mecánica del Step 0b es idéntica al golden — si el cambio es deliberado, re-grabalo con tools/reseal-step0b.ps1 en este mismo commit"
  $mecanicas[$s.Name] = $m
}
# Frases que tienen que estar en las TRES y que viven FUERA del tramo que cubre el golden. Los pasos
# de afuera no se pueden comparar enteros —southpoint diverge en el Step 0 (chequeo de máquina) y en
# el Step 4 (catálogo MCP)—, así que se anclan las oraciones concretas cuya pérdida es destructiva.
# Las dos que están acá se ganaron el lugar: cada una se rompió de verdad y la suite quedó verde.
#  - El ruteo al Step 0b: borrarlo en las tres deja el modo adopción INALCANZABLE y el `CLAUDE.md` del
#    proyecto se pisa sin que nadie parquee el original — la falla que todo el Step 0b existe para
#    evitar.
#  - El guard del Step 3: sin él se escribe un stub sobre el `README.md` o el `CONTEXT.md` del
#    proyecto, y esos dos NO están en el scaffold, así que `copy-scaffold.ps1` no los respalda y no hay
#    `overwritten` que los recupere: es la única pérdida irrecuperable que el skill puede causar. Se
#    arregló primero en una sola skill y las otras dos quedaron con el camino destructivo vivo, en
#    verde, porque el golden solo cubre el Step 0b y nada más lee estos archivos.
$invariantes = @(
  'exist but there is **no** `.bootstrap-manifest.json`',
  'do **not** derive to `upgrade-bootstrap`',
  'Instead, enter **Step 0b — Adoption mode** below',
  'Create these **only where they do not already exist**',
  'In adoption mode an existing `README.md` or `CONTEXT.md` is the project''s own',
  'pwsh -NoProfile -File "$skill\scripts\copy-scaffold.ps1" -SkillDir $skill -ProjectDir $proj')
foreach ($s in $skills) {
  $txt = [IO.File]::ReadAllText((Join-Path $s.FullName "SKILL.md")) -replace "`r`n", "`n" -replace "`r", "`n"
  $faltan = @($invariantes | Where-Object { -not $txt.Contains($_) })
  Assert ($faltan.Count -eq 0) "$($s.Name): conserva las frases críticas de fuera del Step 0b — ruteo a adopción y guard del Step 3 (faltan: $($faltan -join ' | '))"
}

$refMec = $mecanicas[$ref.Name]
foreach ($other in ($skills | Select-Object -Skip 1)) {
  $om = $mecanicas[$other.Name]
  Assert ($null -ne $refMec -and $refMec -ceq $om) "$($other.Name): la mecánica del Step 0b es idéntica a la de $($ref.Name)"
}

if ($script:failures -eq 0) { Write-Host "TODOS LOS TESTS PASARON"; exit 0 }
else { Write-Host "$($script:failures) test(s) FALLARON"; exit 1 }
