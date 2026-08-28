# tests/export-shareable.tests.ps1 — runner sin Pester. Correr: pwsh -NoProfile -File tests/export-shareable.tests.ps1
# El export al repo público debe: copiar limpio las 2 skills + README + install.ps1,
# y abortar (exit != 0) si el árbol exportado contiene un marcador de fuga.
$ErrorActionPreference = "Stop"
$repo   = Split-Path $PSScriptRoot -Parent
$script = Join-Path $repo "tools/export-shareable.ps1"
$script:failures = 0
function Assert($cond, $msg) {
  if ($cond) { Write-Host "ok:   $msg" } else { Write-Host "FAIL: $msg"; $script:failures++ }
}
function NewClone {
  $d = Join-Path ([IO.Path]::GetTempPath()) ("export-test-" + [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $d | Out-Null
  git -C $d init -b main --quiet
  $d
}

# Workspaces huérfanos de corridas anteriores abortadas
Get-ChildItem ([IO.Path]::GetTempPath()) -Directory -Filter "export-test-*" | Remove-Item -Recurse -Force

# 1. Happy path: estructura completa en el clon
$t = NewClone
& pwsh -NoProfile -File $script -PublicRepoDir $t | Out-Null
Assert ($LASTEXITCODE -eq 0) "export happy: exit 0"
Assert (Test-Path "$t\README.md") "export: README.md presente"
Assert (Test-Path "$t\install.ps1") "export: install.ps1 presente"
Assert (Test-Path "$t\skills\bootstrap-ai-project\SKILL.md") "export: bootstrap-ai-project presente"
Assert (Test-Path "$t\skills\upgrade-bootstrap\SKILL.md") "export: upgrade-bootstrap presente"
$manifest = Get-Content "$t\skills\bootstrap-ai-project\assets\scaffold\.bootstrap-manifest.json" -Raw | ConvertFrom-Json
Assert ($manifest.generatedFrom -eq "bootstrap-ai-project") "export: manifest generatedFrom correcto"

# 2. Re-export sobre clon sucio: borra huérfanos dentro de skills/
"orphan" | Set-Content "$t\skills\bootstrap-ai-project\HUERFANO.txt"
& pwsh -NoProfile -File $script -PublicRepoDir $t | Out-Null
Assert ($LASTEXITCODE -eq 0) "re-export: exit 0"
Assert (-not (Test-Path "$t\skills\bootstrap-ai-project\HUERFANO.txt")) "re-export: huérfano eliminado (copia limpia)"
Remove-Item -Recurse -Force $t

# 3. Gate anti-fuga: marcador en el payload de la FUENTE -> aborta.
#    La fuente se copia a temp y se corre ESA copia del script (el exportador deriva su raiz de la
#    ubicacion del script), asi el senuelo nunca se planta dentro del arbol del repo: la suite corre
#    sin ensuciar el working tree, con trabajo real en vuelo y en paralelo con los OTROS archivos de
#    test (cada uno usa su prefijo en temp). Dos corridas de ESTE archivo siguen sin poder solaparse:
#    la limpieza de arriba barre "export-test-*" incluso de una corrida viva.
$t2  = NewClone
$src = Join-Path ([IO.Path]::GetTempPath()) ("export-test-src-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $src | Out-Null
# Huella de un arbol: ruta relativa + tamano + mtime de cada archivo. El mtime es lo que importa:
# gen-manifest.ps1 es idempotente, asi que reescribir el manifest da bytes identicos y un hash de
# contenido no ve la escritura. Se compara como texto y no con -eq entre arrays, que filtra.
function Huella($raiz) {
  Get-ChildItem $raiz -Recurse -File -Force | Sort-Object FullName |
    ForEach-Object { "$($_.FullName.Substring($raiz.Length)) $($_.Length) $($_.LastWriteTimeUtc.Ticks)" }
}
try {
  # Cada destino de Copy-Item ($src\skills y sus hermanos) tiene que no existir todavia: sobre un
  # destino preexistente, -Recurse anida (skills\skills). Por eso $src se crea vacio recien aca.
  foreach ($d in @("skills", "public", "tools")) { Copy-Item (Join-Path $repo $d) (Join-Path $src $d) -Recurse }
  "contact MartinDele703 for details" | Set-Content (Join-Path $src "skills\bootstrap-ai-project\LEAK-TEST.md")
  $fuenteAntes = (Huella $src) -join "`n"
  $salida = & pwsh -NoProfile -File (Join-Path $src "tools\export-shareable.ps1") -PublicRepoDir $t2 2>&1 | Out-String
  $fuenteDespues = (Huella $src) -join "`n"
  Assert ($LASTEXITCODE -ne 0) "gate: export con marcador inyectado aborta (exit != 0)"
  # Sin esto, cualquier rotura de la copia (una dependencia del exportador fuera de los 3 directorios
  # copiados) aborta con exit != 0 y el caso pasa en verde sin que el gate llegue a correr.
  Assert ($salida -match "LEAK:.*LEAK-TEST\.md") "gate: aborta POR el marcador de fuga, no por otra falla"
  # El exportador no escribe en su arbol fuente: es la propiedad que hace que correr la suite no
  # ensucie el repo, y la que a2313ee dejo asentada al mover la generacion del manifest al clon.
  # Se mide sobre la copia, no sobre el repo: misma propiedad, sin acoplarse a un working tree vivo
  # que puede estar cambiando por otro trabajo (un reselado concurrente daria un rojo enganoso).
  Assert ($fuenteAntes -eq $fuenteDespues) "el exportador no escribe en su arbol fuente (ni un archivo nuevo, ni una reescritura identica)"
} finally {
  Remove-Item -Recurse -Force $src, $t2 -ErrorAction SilentlyContinue
}

# 4. No es un clon git -> aborta
$t3 = Join-Path ([IO.Path]::GetTempPath()) ("export-test-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $t3 | Out-Null
& pwsh -NoProfile -File $script -PublicRepoDir $t3 2>&1 | Out-Null
Assert ($LASTEXITCODE -ne 0) "PublicRepoDir sin .git: aborta"
Remove-Item -Recurse -Force $t3

# Guard contra una regresion de ESTE archivo, no del exportador: que el caso 3 vuelva a plantar su
# senuelo dentro del repo, como hacia antes de este slice.
Assert (-not (Test-Path (Join-Path $repo "skills\bootstrap-ai-project\LEAK-TEST.md"))) "el senuelo del caso 3 no se planta dentro del arbol del repo"

if ($script:failures -eq 0) { Write-Host "TODOS LOS TESTS PASARON"; exit 0 }
else { Write-Host "$($script:failures) test(s) FALLARON"; exit 1 }
