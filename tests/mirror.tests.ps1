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
$mecFin = '## Step 1'
function MecanicaStep0b($skillDir) {
  $t = [IO.File]::ReadAllText((Join-Path $skillDir "SKILL.md")) -replace "`r`n", "`n" -replace "`r", "`n"
  $i = $t.IndexOf($mecIni)
  if ($i -lt 0) { return $null }
  $j = $t.IndexOf($mecFin, $i)
  if ($j -lt 0) { return $null }
  return $t.Substring($i, $j - $i)
}
# Los asserts de abajo son la diferencia entre un test que muerde y uno que se autoaprueba: si un
# rename mueve los anclas, `MecanicaStep0b` devuelve $null en las TRES y comparar $null contra $null
# daría verde sobre cero contenido. Ése lo ataja el primero. El segundo ataja el tramo mutilado en
# las tres a la vez, que es la otra familia: un Step 0b reducido a sus seis encabezados sin cuerpo,
# o a una sola línea que los enumere, pasaba el chequeo de presencia (medido). Los headings se buscan
# anclados a principio de línea porque como substring sueltos una oración que los nombre alcanza, y
# `#### B.` contiene `### B.`.
# El cuerpo se mide POR SUB-PASO, no sobre el bloque entero: un piso global tolera que se borre
# cualquier sub-paso completo mientras los demás lo compensen — con 5000 sobre un bloque de ~8400,
# vaciar el step B (o D+E+F) pasaba en verde (medido). El piso por sub-paso es flojo a propósito:
# distingue "hay procedimiento" de "quedó el título", no vigila el largo de la prosa.
$subPasos = @('### A. Copy the scaffold', '### B. Park', '### C. Classify', '### D. Present', '### E. Apply', '### F. Continue')
$mecanicas = @{}
foreach ($s in $skills) {
  $m = MecanicaStep0b $s.FullName
  Assert ($null -ne $m) "$($s.Name): SKILL.md tiene la mecánica del Step 0b entre '$mecIni' y '$mecFin'"
  $lineas = @(if ($null -ne $m) { $m -split "`n" })
  $faltan  = @()
  $vacios  = @()
  foreach ($p in $subPasos) {
    $k = if ($null -eq $m) { -1 } else { $m.IndexOf("`n$p") }
    if ($k -lt 0) { $faltan += $p; continue }
    # Hasta el próximo `### ` en su propia línea, o hasta el fin del tramo si es el último sub-paso.
    $sig = $m.IndexOf("`n### ", $k + 1)
    $cuerpo = if ($sig -lt 0) { $m.Substring($k) } else { $m.Substring($k, $sig - $k) }
    if ($cuerpo.Length -lt 300) { $vacios += "$p ($($cuerpo.Length))" }
  }
  Assert ($faltan.Count -eq 0) "$($s.Name): la mecánica del Step 0b abre sus $($subPasos.Count) sub-pasos en su propia línea (faltan: $($faltan -join ', '))"
  Assert ($vacios.Count -eq 0) "$($s.Name): cada sub-paso del Step 0b tiene cuerpo, no solo el título (flacos: $($vacios -join ', '))"
  $mecanicas[$s.Name] = $m
}
$refMec = $mecanicas[$ref.Name]
foreach ($other in ($skills | Select-Object -Skip 1)) {
  $om = $mecanicas[$other.Name]
  Assert ($null -ne $refMec -and $refMec -ceq $om) "$($other.Name): la mecánica del Step 0b es idéntica a la de $($ref.Name)"
}

if ($script:failures -eq 0) { Write-Host "TODOS LOS TESTS PASARON"; exit 0 }
else { Write-Host "$($script:failures) test(s) FALLARON"; exit 1 }
