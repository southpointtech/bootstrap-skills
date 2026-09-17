# tests/carriles-scaffold.tests.ps1 — runner sin Pester. Correr: pwsh -NoProfile -File tests/carriles-scaffold.tests.ps1
# La mecánica de carriles y sus datos llegan en los tres scaffolds (ADR-0011): presencia, manifest,
# marcas donde van y sólo donde van, y las instrucciones de no rellenarlas. La identidad de
# contenido entre los tres scaffolds la cubre mirror.tests.ps1.
$ErrorActionPreference = "Stop"
$repo = Split-Path $PSScriptRoot -Parent
$script:failures = 0
function Assert($cond, $msg) {
  if ($cond) { Write-Host "ok:   $msg" } else { Write-Host "FAIL: $msg"; $script:failures++ }
}

$variantes = @("bootstrap-ai-project", "bootstrap-personal-project", "bootstrap-southpoint-project")
$mecanica = @(
  "docs/ai-workflow/PARALELISMO.md",
  "docs/ai-workflow/PLAN-DE-OLA.md",
  "docs/ai-workflow/BRIEF-DE-CARRIL.md",
  ".claude/scripts/abrir-carril.ps1"
)
$datos = "docs/ai-workflow/PARALELISMO-DEL-PROYECTO.md"

function Leer([string]$p) { [IO.File]::ReadAllText($p) -replace "`r`n", "`n" }

# sha256 de los bytes con los fines de línea llevados a LF y a CRLF. El manifest guarda el hash de
# los bytes crudos de la máquina que lo generó, y con core.autocrlf=true el checkout de otra
# máquina puede escribir el mismo contenido con el otro fin de línea: se acepta cualquiera de los
# dos, que es la misma identidad de contenido que exige mirror.tests.ps1.
function Hashes([string]$p) {
  $lat = [Text.Encoding]::Latin1
  $lf = $lat.GetString([IO.File]::ReadAllBytes($p)) -replace "`r`n", "`n"
  $sha = [Security.Cryptography.SHA256]::Create()
  foreach ($t in @($lf, ($lf -replace "`n", "`r`n"))) {
    [BitConverter]::ToString($sha.ComputeHash($lat.GetBytes($t))).Replace("-", "").ToLower()
  }
}

# Las secciones `## ` de un markdown, con el texto previo al primer encabezado bajo la clave "".
function Secciones([string]$texto) {
  $s = [ordered]@{}; $actual = ""; $s[$actual] = ""
  foreach ($l in ($texto -split "`n")) {
    if ($l -match '^## (.+?)\s*$') { $actual = $Matches[1]; $s[$actual] = ""; continue }
    $s[$actual] += "$l`n"
  }
  return $s
}

foreach ($v in $variantes) {
  $sc = Join-Path $repo "skills/$v/assets/scaffold"
  $manifest = (Get-Content -Raw (Join-Path $sc ".bootstrap-manifest.json") | ConvertFrom-Json).files
  foreach ($rel in ($mecanica + $datos)) {
    $p = Join-Path $sc $rel
    $existe = Test-Path -LiteralPath $p
    Assert $existe "${v}: tiene $rel"
    if (-not $existe) { continue }
    $sellado = $manifest.$rel
    Assert ($sellado -and ($sellado -in @(Hashes $p))) "${v}: el manifest sella $rel con su hash actual"
  }
  if (-not (Test-Path -LiteralPath (Join-Path $sc $datos))) { continue }

  # La mecánica no lleva marcas. PLAN y BRIEF sí, y dicen que se rellenan en el chat. El script
  # queda afuera del chequeo: contiene la marca porque es lo que busca.
  Assert (-not (Leer (Join-Path $sc "docs/ai-workflow/PARALELISMO.md")).Contains("{{")) "${v}: PARALELISMO.md no tiene marcas"
  foreach ($rel in @("docs/ai-workflow/PLAN-DE-OLA.md", "docs/ai-workflow/BRIEF-DE-CARRIL.md")) {
    $txt = Leer (Join-Path $sc $rel)
    Assert ($txt.Contains("{{") -and $txt -match 'se rellenan \*\*en el chat\*\*') "${v}: $rel tiene marcas y dice que se rellenan en el chat"
  }

  $sec = Secciones (Leer (Join-Path $sc $datos))
  Assert (-not $sec[""].Contains("{{")) "${v}: la nota de los datos no tiene la marca literal"
  Assert ($sec[""] -match 'No[\s>]+se rellena al bootstrapear' -and $sec[""] -match '«no aplica» es un valor válido') "${v}: la nota dice que no se rellena al bootstrapear y que «no aplica» es un valor"
  foreach ($n in @("Encabezado", "El camino crítico", "Contratos fijados", "Archivos calientes", "Config compartida",
                   "Recursos compartidos", "Lo que un worktree no hereda", "Guardas transversales", "La ola vigente")) {
    Assert ($sec.Contains($n) -and $sec[$n].Contains("{{")) "${v}: la sección «$n» de los datos existe y tiene marcas"
  }
  Assert ($sec.Contains("Lo que dejó la ola N") -and -not $sec["Lo que dejó la ola N"].Trim()) "${v}: «Lo que dejó la ola N» existe y está vacía"
  $b = [regex]::Match($sec["El bloque que lee el script"], '(?ms)^```carriles\n(.*?)^```')
  $claves = @($b.Groups[1].Value -split "`n" | Where-Object { $_.Trim() } | ForEach-Object { ($_ -split ':', 2)[0].Trim() })
  Assert ($b.Success -and (($claves -join ",") -eq "copiar,worktrees,base")) "${v}: el bloque carriles trae copiar, worktrees y base (trae: $($claves -join ','))"

  # La norma dice adónde va una lección general.
  Assert ((Leer (Join-Path $sc "docs/ai-workflow/PARALELISMO.md")) -match 'se sube a esta mecánica en Bootstrap Skills') "${v}: la norma dice que una lección general se sube a la mecánica"
}

# La raíz adoptó la mecánica tal cual y rellenó sus datos: sin marcas y con el bloque del script.
$sc = Join-Path $repo "skills/bootstrap-personal-project/assets/scaffold"
foreach ($rel in $mecanica) {
  $p = Join-Path $repo $rel
  Assert ((Test-Path -LiteralPath $p) -and ((Leer $p) -eq (Leer (Join-Path $sc $rel)))) "raíz: $rel es la mecánica del scaffold, sin editar"
}
$raiz = Join-Path $repo $datos
Assert ((Test-Path -LiteralPath $raiz) -and -not (Leer $raiz).Contains("{{")) "raíz: los datos del proyecto están rellenados, sin marcas"
Assert ((Test-Path -LiteralPath $raiz) -and (Leer $raiz) -match '(?m)^base: feat/bootstrap-v2$') "raíz: el bloque carriles apunta a la base feat/bootstrap-v2"

# La línea condicional del CLAUDE.md, dentro de «Required workflow docs», en los tres scaffolds y
# en la raíz.
$claudes = @($variantes | ForEach-Object { Join-Path $repo "skills/$_/assets/scaffold/CLAUDE.md" }) + @(Join-Path $repo "CLAUDE.md")
foreach ($c in $claudes) {
  $req = (Secciones (Leer $c))["Required workflow docs"]
  $linea = @($req -split "`n" | Where-Object { $_ -match 'PARALELISMO\.md' })
  Assert ($linea.Count -eq 1 -and $linea[0] -match 'PARALELISMO-DEL-PROYECTO\.md' -and $linea[0] -match 'more than one lane') `
    "$([IO.Path]::GetRelativePath($repo, $c)): «Required workflow docs» tiene la línea condicional de carriles"
}

# La instrucción de no rellenar: en el Step 6 de las tres bootstrap y en el paso 4 del upgrade.
$noRellenar = 'Do not fill in the placeholders of `docs/ai-workflow/PARALELISMO-DEL-PROYECTO.md`'
foreach ($v in $variantes) {
  $t = Leer (Join-Path $repo "skills/$v/SKILL.md")
  $step6 = [regex]::Match($t, '(?ms)^## Step 6 .*?(?=^## |\z)').Value
  Assert ($step6.Contains($noRellenar)) "${v}: el Step 6 dice que no se rellenan las marcas de los datos"
}
$up = Leer (Join-Path $repo "skills/upgrade-bootstrap/SKILL.md")
$paso4 = [regex]::Match($up, '(?ms)^### 4\. .*?(?=^### |\z)').Value
Assert ($paso4.Contains($noRellenar)) "upgrade-bootstrap: el paso 4 dice que no se rellenan las marcas de los datos"

if ($script:failures -eq 0) { Write-Host "TODOS LOS TESTS PASARON"; exit 0 }
else { Write-Host "$($script:failures) test(s) FALLARON"; exit 1 }
