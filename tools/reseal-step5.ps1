# Golden por hash de un bloque de instrucciones espejado en 8 copias: lo sella y lo verifica.
#   pwsh -NoProfile -File tools/reseal-step5.ps1 [-Block <nombre>]           # resella (tras mirar el diff)
#   pwsh -NoProfile -File tools/reseal-step5.ps1 [-Block <nombre>] -Check    # verifica; exit 0 si coincide, 1 si no
#
# Bloques (-Block, default step5):
#   step5     el bloque "Score the FIX" del Step 5 de /slice-review.
#   tdd-loop  el cuerpo entero de la skill tdd, del titulo al final del archivo: la doctrina red -> green
#             de ADR-0004 (el refactor no es parte del ciclo) y el cierre de slice con su trailer.
#   fan-out   Step 3 y Step 4 de /slice-review enteros: el contexto compartido, el ruteo de cada foco a
#             su agent declarado, los modelos por foco y la orden de no pasar el modelo en el dispatch.
#   agents    los 7 .claude/agents/slice-review-*.md enteros (frontmatter y cuerpo), uno por raiz: lo que
#             cada foco revisa vive en el cuerpo de su agent, y el fan-out solo congela el nombre.
#
# Por que existe: los asserts semanticos de tests/slice-review.tests.ps1 muerden mutantes que EDITAN o
# BORRAN una oracion anclada, pero son ciegos a los que AÑADEN (medido en el turno 2 del review-loop del
# 2026-09-15: sobrevivio una clausula "In practice the scorer skips (2) and (3) whenever (1) scores 90 or
# above" que deja intactas las 19 oraciones y desarma la regla). Un golden por hash no impide reescribir
# el bloque: lo hace VISIBLE. Si cambia, el test se pone rojo, mirás el diff y resellás a proposito con
# este script — nunca pegandole el hash a mano al fixture.
#
# Una sola implementacion, dos modos: el test invoca este mismo script con -Check, asi el sello y la
# verificacion no pueden divergir (y la suite no necesita dot-sourcear un helper propio, que es lo que
# tests/temp-hygiene.tests.ps1 prohibe para que nadie cuele un stub).
param([switch]$Check, [ValidateSet('step5', 'tdd-loop', 'fan-out', 'agents')][string]$Block = 'step5')
$ErrorActionPreference = "Stop"
$repo = Split-Path $PSScriptRoot -Parent

if ($Block -eq 'agents') {
  # Un bloque por RAIZ, no por archivo: los 7 agents son documentos distintos, asi que se concatenan
  # ordenados por nombre (con el nombre adelante, para que un rename tambien cambie el hash) y se
  # comparan las 4 raices entre si y contra un solo golden.
  $goldenPath = Join-Path $repo "tests\fixtures\agents.golden.sha256"
  $rels = @(".claude\agents")
  $rx = $null
  $normalizar = { param($t) $t }
} elseif ($Block -eq 'fan-out') {
  $goldenPath = Join-Path $repo "tests\fixtures\fan-out.golden.sha256"
  $rels = @(".claude\commands\slice-review.md", ".agents\skills\slice-review\SKILL.md")
  # Del titulo de Step 3 hasta el de Step 5, excluido: una frase agregada en cualquier punto del fan-out
  # (una orden de pasar el modelo, un foco ruteado al agent de otro) tiene que cambiar el hash.
  $rx = '(?sm)^## Step 3 — Gather shared context \(once\)\r?\n.*?(?=^## Step 5 — )'
  $normalizar = { param($t) $t }
} elseif ($Block -eq 'tdd-loop') {
  $goldenPath = Join-Path $repo "tests\fixtures\tdd-loop.golden.sha256"
  $rels = @(".claude\commands\tdd.md", ".agents\skills\tdd\SKILL.md")
  # Del titulo al final del archivo: la doctrina tambien vive en la intro ("TDD is the red -> green loop")
  # y en Seams, y un parrafo agregado al final del archivo tiene que cambiar el hash igual que uno
  # agregado en el medio. El frontmatter queda afuera porque la description difiere a proposito entre el
  # command (la de upstream) y el SKILL.md; la fija el test con igualdad exacta. Lo otro que difiere son
  # los links del command, que llevan el prefijo `.agents/skills/tdd/` y se normalizan antes del hash.
  $rx = '(?sm)^# Test-Driven Development\r?\n.*\z'
  $normalizar = { param($t) $t -replace '\]\(\.agents/skills/tdd/', '](' }
} else {
  $goldenPath = Join-Path $repo "tests\fixtures\step5-score-the-fix.golden.sha256"
  $rels = @(".claude\commands\slice-review.md", ".agents\skills\slice-review\SKILL.md")
  # Del titulo del bloque hasta el parrafo de la consecuencia inclusive: es la MECANICA que el golden
  # congela (las tres preguntas, la modalidad, el orden y el destino de la sugerencia). El resto del Step 5
  # —rubrica, dedup, prosa-es-Low— queda afuera a proposito: lo cubren sus propios asserts y cambia por
  # otras razones.
  $rx = '(?s)\*\*Score the FIX, not only the finding\.\*\*.*?judges findings and writes its own fix behind a RED test, so a rejected suggestion plus the reason\r?\nis more useful to it than silence\.'
  $normalizar = { param($t) $t }
}

# Las 8 copias del documento: el repo (auto-bootstrapeado) + las 3 skills, command y SKILL.md en cada una.
$files = @()
foreach ($r in $rels) { $files += (Join-Path $repo $r) }
foreach ($s in @("bootstrap-ai-project", "bootstrap-personal-project", "bootstrap-southpoint-project")) {
  foreach ($r in $rels) { $files += (Join-Path $repo "skills\$s\assets\scaffold\$r") }
}

$hashes = [ordered]@{}
$faltan = @()
foreach ($f in $files) {
  $rel = $f.Substring($repo.Length).TrimStart('\')
  if (-not (Test-Path -LiteralPath $f)) { $faltan += $rel; continue }
  if ($Block -eq 'agents') {
    $agentes = @(Get-ChildItem -LiteralPath $f -File -Filter 'slice-review-*.md' | Sort-Object Name)
    if ($agentes.Count -eq 0) { $faltan += "$rel (sin agents)"; continue }
    $texto = ($agentes | ForEach-Object { "==> $($_.Name)`n" + [IO.File]::ReadAllText($_.FullName) }) -join "`n"
  } else {
    $m = [regex]::Match([IO.File]::ReadAllText($f), $rx)
    if (-not $m.Success) { $faltan += "$rel (sin bloque)"; continue }
    $texto = $m.Value
  }
  # EOL normalizado: con autocrlf=true el disco y el blob difieren, y un golden atado al EOL da rojo por
  # maquina (el bug de los manifests con hashes mixtos, CLAUDE.md).
  $norm = (& $normalizar $texto) -replace "`r`n", "`n"
  $sha = [System.Security.Cryptography.SHA256]::Create()
  $bytes = $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($norm))
  $hashes[$rel] = ([System.BitConverter]::ToString($bytes).Replace("-", "").ToLower())
}

if ($faltan.Count -gt 0) {
  Write-Host "No se pudo leer el bloque en: $($faltan -join ', ')"
  exit 1
}

$distinct = @($hashes.Values | Sort-Object -Unique)
if ($distinct.Count -ne 1) {
  Write-Host "El bloque NO es identico en las $($files.Count) copias:"
  $hashes.GetEnumerator() | ForEach-Object { Write-Host ("  {0}  {1}" -f $_.Value.Substring(0, 12), $_.Key) }
  exit 1
}

if ($Check) {
  if (-not (Test-Path -LiteralPath $goldenPath)) { Write-Host "Falta el golden: $goldenPath"; exit 1 }
  $golden = (Get-Content $goldenPath -Raw).Trim()
  if ($golden -notmatch '^[0-9a-f]{64}$') { Write-Host "El golden no es un sha256: '$golden'"; exit 1 }
  if ($golden -ne $distinct[0]) {
    Write-Host "El bloque cambio: sello $($golden.Substring(0,12)) vs actual $($distinct[0].Substring(0,12))."
    Write-Host "Si el cambio es a proposito, mira el diff y resella: pwsh -NoProfile -File tools/reseal-step5.ps1 -Block $Block"
    exit 1
  }
  Write-Host "OK: bloque $Block, las $($files.Count) copias coinciden con el golden ($($golden.Substring(0,12)))."
  exit 0
}

$prev = if (Test-Path -LiteralPath $goldenPath) { (Get-Content $goldenPath -Raw).Trim() } else { "(no habia)" }
[IO.File]::WriteAllText($goldenPath, $distinct[0] + "`n")
Write-Host "Golden del bloque $Block resellado en $goldenPath"
Write-Host "  antes:  $prev"
Write-Host "  ahora:  $($distinct[0])"
