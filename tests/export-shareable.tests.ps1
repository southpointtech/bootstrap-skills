# tests/export-shareable.tests.ps1 — runner sin Pester. Correr: pwsh -NoProfile -File tests/export-shareable.tests.ps1
# El export al repo público debe: copiar limpio las 2 skills + README + install.ps1,
# y abortar (exit != 0) si el árbol exportado contiene un marcador de fuga.
$ErrorActionPreference = "Stop"
$repo   = Split-Path $PSScriptRoot -Parent
$script = Join-Path $repo "tools/export-shareable.ps1"
$script:failures = 0
. (Join-Path $PSScriptRoot "lib\temp-workspace.ps1")
# La recolección de huérfanos de esta suite era un `Remove-Item` por glob INCONDICIONAL sobre la raíz
# de %TEMP%: le borraba los fixtures en pleno uso a cualquier corrida concurrente, y en este repo las
# corridas concurrentes son la norma (el review-loop lanza reviewers en paralelo). New-TestRunRoot
# recolecta por edad y solo lo que tiene más de un día.
$script:runRoot = New-TestRunRoot "export-test"
trap { Remove-TestRunRoot $script:runRoot; break }

function Assert($cond, $msg) {
  if ($cond) { Write-Host "ok:   $msg" } else { Write-Host "FAIL: $msg"; $script:failures++ }
}
function NewClone {
  $d = New-TestWorkspace $script:runRoot "export-test"
  git -C $d init -b main --quiet
  # El remote del repo publico real: su URL lleva un marcador de fuga, asi que el clon queda con uno
  # dentro de .git. Es lo que da cobertura a la exclusion de .git del gate -- sin esto, borrarla deja
  # la suite entera en verde mientras rompe todo export real.
  git -C $d remote add origin "https://github.com/MartinDele703/ai-project-bootstrap.git"
  $d
}

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
#    test (cada uno usa su prefijo en temp).
$t2  = NewClone
$src = New-TestWorkspace $script:runRoot "export-test-src"
# Huella de un arbol: ruta relativa + tamano + mtime de cada archivo, en orden estable. El mtime es
# lo que la vuelve sensible a la ESCRITURA y no solo al contenido: gen-manifest.ps1 estampa la fecha
# del dia en "version", asi que una reescritura cambia los bytes solo si el sello es de otro dia o el
# scaffold drifteo -- comparar contenido deja pasar la reescritura del mismo dia. Se compara como
# texto (no con -eq entre arrays, que filtra) y con -ceq, porque -eq entre strings ignora mayusculas
# y un rename que solo cambia capitalizacion compararia igual.
function Huella($raiz) {
  Get-ChildItem $raiz -Recurse -File -Force | Sort-Object FullName |
    ForEach-Object { "$($_.FullName.Substring($raiz.Length)) $($_.Length) $($_.LastWriteTimeUtc.Ticks)" }
}
try {
  # $src se creo vacio arriba y cada destino de Copy-Item ($src\skills y sus hermanos) todavia no
  # existe: sobre un destino preexistente, -Recurse anida (skills\skills).
  foreach ($d in @("skills", "public", "tools")) { Copy-Item (Join-Path $repo $d) (Join-Path $src $d) -Recurse }

  # 3a. Corrida que llega hasta el final: el exportador no escribe en su arbol fuente. Es la propiedad
  #     que hace que correr la suite no ensucie el repo, y la que a2313ee dejo asentada al mover la
  #     generacion del manifest al clon. Va sin senuelo a proposito: con el senuelo el exportador
  #     muere en el gate y nada de lo que viene despues llegaria a medirse.
  #     Se mide sobre la copia y no sobre el repo -- misma propiedad, porque el exportador deriva su
  #     raiz de la ubicacion del script y es el mismo codigo -- para no acoplar la suite a un working
  #     tree vivo, donde un reselado concurrente daria un rojo que acusaria al exportador.
  #     Se mide DOS veces porque el exportador toma caminos distintos segun el destino: la primera
  #     corrida lo encuentra virgen, la segunda ya poblado, y solo ahi corre la rama que borra el
  #     destino previo. Medir una sola deja la otra sin cubrir.
  $fuenteAntes = (Huella $src) -join "`n"
  Assert ($fuenteAntes.Length -gt 0) "huella: la copia de la fuente no esta vacia"
  & pwsh -NoProfile -File (Join-Path $src "tools\export-shareable.ps1") -PublicRepoDir $t2 | Out-Null
  Assert ($LASTEXITCODE -eq 0) "export sobre destino virgen: exit 0"
  Assert (((Huella $src) -join "`n") -ceq $fuenteAntes) "el exportador no escribe en su arbol fuente con el destino virgen"
  & pwsh -NoProfile -File (Join-Path $src "tools\export-shareable.ps1") -PublicRepoDir $t2 | Out-Null
  Assert ($LASTEXITCODE -eq 0) "export sobre destino poblado: exit 0"
  Assert (((Huella $src) -join "`n") -ceq $fuenteAntes) "el exportador no escribe en su arbol fuente con el destino poblado (ni un archivo nuevo, ni un borrado, ni una reescritura identica)"

  # 3b. Con el senuelo en el payload de la fuente, el gate aborta. La huella se vuelve a tomar aca
  #     -- despues de plantar el senuelo -- porque la rama del gate solo corre en esta pasada.
  "contact MartinDele703 for details" | Set-Content (Join-Path $src "skills\bootstrap-ai-project\LEAK-TEST.md")
  Assert (-not (Test-Path (Join-Path $repo "skills\bootstrap-ai-project\LEAK-TEST.md"))) "ningun senuelo se planto en el arbol del repo"
  $fuenteAntesGate = (Huella $src) -join "`n"
  $salida = & pwsh -NoProfile -File (Join-Path $src "tools\export-shareable.ps1") -PublicRepoDir $t2 2>&1 | Out-String
  Assert ($LASTEXITCODE -ne 0) "gate: export con marcador inyectado aborta (exit != 0)"
  # Sin esto, cualquier rotura de la copia (una dependencia del exportador fuera de los 3 directorios
  # copiados) aborta con exit != 0 y el caso pasa en verde sin que el gate llegue a correr.
  Assert ($salida -match "LEAK:.*LEAK-TEST\.md") "gate: aborta POR el marcador de fuga, no por otra falla"
  Assert (((Huella $src) -join "`n") -ceq $fuenteAntesGate) "el exportador tampoco escribe en su arbol fuente cuando aborta por el gate"
} finally {
  Remove-Item -Recurse -Force $src, $t2 -ErrorAction SilentlyContinue
}

# 4. No es un clon git -> aborta
# Sin NewClone a propósito: este caso necesita el directorio SIN `git init`.
$t3 = New-TestWorkspace $script:runRoot "export-test"
$salida4 = & pwsh -NoProfile -File $script -PublicRepoDir $t3 2>&1 | Out-String
Assert ($LASTEXITCODE -ne 0) "PublicRepoDir sin .git: aborta"
Assert ($salida4 -match "not a git clone") "PublicRepoDir sin .git: aborta POR el guard, no por otra falla"
Remove-Item -Recurse -Force $t3

# Guard contra una regresion de ESTE archivo, no del exportador: nada crea LEAK-TEST.md salvo el caso
# 3. Detecta el senuelo que QUEDA en el repo; el que se plante y se limpie lo detecta el assert de 3b.
Assert (-not (Test-Path (Join-Path $repo "skills\bootstrap-ai-project\LEAK-TEST.md"))) "ningun senuelo quedo dentro del arbol del repo"

Remove-TestRunRoot $script:runRoot

if ($script:failures -eq 0) { Write-Host "TODOS LOS TESTS PASARON"; exit 0 }
else { Write-Host "$($script:failures) test(s) FALLARON"; exit 1 }
