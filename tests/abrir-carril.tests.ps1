# tests/abrir-carril.tests.ps1 — runner sin Pester. Correr: pwsh -NoProfile -File tests/abrir-carril.tests.ps1
# El script que abre el worktree de un carril (ADR-0011), contra repos git temporales.
$ErrorActionPreference = "Stop"
$repo   = Split-Path $PSScriptRoot -Parent
$script:abrir = Join-Path $repo "skills/bootstrap-personal-project/assets/scaffold/.claude/scripts/abrir-carril.ps1"
$script:failures = 0
. (Join-Path $PSScriptRoot "lib\temp-workspace.ps1")
$script:runRoot = New-TestRunRoot "ac"
trap { Remove-TestRunRoot $script:runRoot; break }

function Assert($cond, $msg) {
  if ($cond) { Write-Host "ok:   $msg" } else { Write-Host "FAIL: $msg"; $script:failures++ }
}

# Sin el script, `pwsh -File` imprime un error y sale distinto de 0: los casos de rechazo pasarían
# en verde sin ejercitar nada.
if (-not (Test-Path -LiteralPath $script:abrir)) {
  Remove-TestRunRoot $script:runRoot
  Write-Host "FAIL: no existe el script en $script:abrir"; exit 1
}

# Los datos válidos mínimos: sin marcas y con el bloque que lee el script.
$script:datosOk = @'
# Paralelismo — datos del proyecto

## El camino crítico

01 → 02

```carriles
copiar: .env, .scratch
```
'@

# Un repo en `main` con `.env` y `.scratch/` gitignoreados y el archivo de datos commiteado.
# El gitconfig global se neutraliza como en review-marker.tests.ps1.
function New-Repo([string]$datos = $script:datosOk, [string]$nombre = "proyecto") {
  $ws = New-TestWorkspace $script:runRoot "ac"
  $t = Join-Path $ws $nombre
  [IO.Directory]::CreateDirectory($t) | Out-Null
  git -C $t init -q -b main
  git -C $t config user.email a@b.c
  git -C $t config user.name a
  git -C $t config commit.gpgsign false
  git -C $t config core.hooksPath ""
  git -C $t config core.excludesFile ""
  git -C $t config core.autocrlf false
  Set-Content (Join-Path $t ".gitignore") ".env`n.scratch/`n" -NoNewline
  "base" | Set-Content (Join-Path $t "file.txt")
  if ($datos) {
    $d = Join-Path $t "docs/ai-workflow"
    [IO.Directory]::CreateDirectory($d) | Out-Null
    [IO.File]::WriteAllText((Join-Path $d "PARALELISMO-DEL-PROYECTO.md"), $datos)
  }
  git -C $t add -A; git -C $t commit -q -m base
  "SECRETO=1" | Set-Content (Join-Path $t ".env")
  [IO.Directory]::CreateDirectory((Join-Path $t ".scratch/issues")) | Out-Null
  "# issue 07" | Set-Content (Join-Path $t ".scratch/issues/07.md")
  return $t
}

# Corre el script con la cwd en el repo. Deja el exit code en $script:lastExit y devuelve la salida
# entera (stdout, stderr y avisos) como un solo string.
function Abrir([string]$dir, [string[]]$argumentos) {
  Push-Location -LiteralPath $dir
  try {
    $out = & pwsh -NoProfile -File $script:abrir @argumentos 2>&1
    $script:lastExit = $LASTEXITCODE
  } finally { Pop-Location }
  return (@($out | ForEach-Object { "$_" }) -join "`n")
}

# --- Tracer bullet: -DryRun no crea nada y dice qué copiaría ---
$t = New-Repo
$root = Join-Path (Split-Path $t -Parent) "carriles"
$out = Abrir $t @("-Slice", "07", "-Slug", "padron", "-Root", $root, "-DryRun")
Assert ($script:lastExit -eq 0) "dry run sale 0 (salió $script:lastExit)"
Assert (-not (Test-Path -LiteralPath $root)) "dry run no crea la carpeta de worktrees"
git -C $t show-ref --verify --quiet "refs/heads/slice/07-padron"
Assert ($LASTEXITCODE -ne 0) "dry run no crea la rama"
Assert ($out -match '(?m)^Copiaria: \.scratch\s+\(existe\)') "dry run lista lo que copiaría, con su estado"

# --- Sin el archivo de datos, se niega a abrir ---
$t = New-Repo -datos ""
$root = Join-Path (Split-Path $t -Parent) "carriles"
$out = Abrir $t @("-Slice", "07", "-Slug", "padron", "-Root", $root)
Assert ($script:lastExit -ne 0) "sin datos del proyecto sale distinto de 0"
Assert (-not (Test-Path -LiteralPath $root)) "sin datos del proyecto no abre el worktree"
Assert ($out -match 'PARALELISMO-DEL-PROYECTO\.md') "el rechazo nombra el archivo de datos que falta"

# --- Con marcas sin rellenar, se niega y lista las líneas ---
$conMarcas = $script:datosOk -replace '01 → 02', "{{01 -> 03}}`n`n| {{modulo}} | x |"
$t = New-Repo -datos $conMarcas
$root = Join-Path (Split-Path $t -Parent) "carriles"
$out = Abrir $t @("-Slice", "07", "-Slug", "padron", "-Root", $root)
Assert ($script:lastExit -ne 0) "con marcas sale distinto de 0"
Assert (-not (Test-Path -LiteralPath $root)) "con marcas no abre el worktree"
Assert ($out -match '(?m)^\s*5: \{\{01 -> 03\}\}') "el rechazo lista la primera marca con su número de línea"
Assert ($out -match '(?m)^\s*7: \| \{\{modulo\}\} \| x \|') "el rechazo lista la segunda marca con su número de línea"

# --- Con marcas y -DryRun: avisa, lista y sale 0 ---
$out = Abrir $t @("-Slice", "07", "-Slug", "padron", "-Root", $root, "-DryRun")
Assert ($script:lastExit -eq 0) "con marcas y dry run sale 0 (salió $script:lastExit)"
Assert ($out -match '(?m)^\s*5: \{\{01 -> 03\}\}') "con dry run también lista las marcas"
Assert ($out -match 'DryRun: no se creo nada') "con marcas, el dry run llega hasta el final"

# --- Precedencia: parámetro > bloque > default ---
# Cada dato se lee de la salida del dry run: `Worktree:` dice dónde, `Rama:` sobre qué base, y las
# líneas `Copiaria:` qué copia. `-match` sobre la salida entera, y `-notmatch` para lo que no debe
# estar: sin el negativo, un script que copiara la unión de las dos listas pasaría.
$ws = New-TestWorkspace $script:runRoot "ac-dest"
$enBloque = Join-Path $ws "del bloque"
$enParam  = Join-Path $ws "del parametro"
$conBloque = $script:datosOk -replace 'copiar: \.env, \.scratch', "copiar: .scratch`nworktrees: $enBloque`nbase: desarrollo"
$t = New-Repo -datos $conBloque
git -C $t branch desarrollo
git -C $t branch otra

$out = Abrir $t @("-Slice", "07", "-Slug", "padron", "-DryRun")
Assert ($out -match '(?m)^Rama:.*\(desde desarrollo @') "sin parámetro, la base sale del bloque"
Assert ($out.Contains("Worktree: " + (Join-Path $enBloque "slice-07"))) "sin parámetro, la carpeta de worktrees sale del bloque"
Assert (($out -match '(?m)^Copiaria: \.scratch ') -and ($out -notmatch '(?m)^Copiaria: \.env')) "sin parámetro, lo que se copia sale del bloque"

$out = Abrir $t @("-Slice", "07", "-Slug", "padron", "-Base", "otra", "-Root", $enParam, "-Copy", ".env", "-DryRun")
Assert ($out -match '(?m)^Rama:.*\(desde otra @') "el parámetro -Base gana sobre el bloque"
Assert ($out.Contains("Worktree: " + (Join-Path $enParam "slice-07"))) "el parámetro -Root gana sobre el bloque"
Assert (($out -match '(?m)^Copiaria: \.env ') -and ($out -notmatch '(?m)^Copiaria: \.scratch')) "el parámetro -Copy gana sobre el bloque"

# Sin parámetro ni clave (o con 'no aplica'), el default.
$sinClaves = $script:datosOk -replace 'copiar: \.env, \.scratch', "copiar: no aplica"
$t = New-Repo -datos $sinClaves
$out = Abrir $t @("-Slice", "07", "-Slug", "padron", "-DryRun")
$porDefecto = Join-Path (Split-Path $t -Parent) (Join-Path "carriles" (Join-Path "proyecto" "slice-07"))
Assert ($out -match '(?m)^Rama:.*\(desde main @') "sin parámetro ni clave, la base es main"
Assert ($out.Contains("Worktree: $porDefecto")) "sin parámetro ni clave, los worktrees van a <padre>\carriles\<repo>"
Assert (($out -match '(?m)^Copiaria: \.env ') -and ($out -match '(?m)^Copiaria: \.scratch ')) "'no aplica' en copiar deja la lista por defecto"

# --- Una clave desconocida en el bloque es un error, con o sin -DryRun ---
$claveMala = $script:datosOk -replace 'copiar: \.env, \.scratch', "copiar: .env`ncopia: .scratch"
$t = New-Repo -datos $claveMala
$root = Join-Path (Split-Path $t -Parent) "carriles"
$out = Abrir $t @("-Slice", "07", "-Slug", "padron", "-Root", $root)
Assert ($script:lastExit -ne 0) "una clave desconocida sale distinto de 0"
Assert ($out -match "'copia'") "el rechazo nombra la clave desconocida"
Assert (-not (Test-Path -LiteralPath $root)) "con una clave desconocida no abre el worktree"
$out = Abrir $t @("-Slice", "07", "-Slug", "padron", "-Root", $root, "-DryRun")
Assert ($script:lastExit -ne 0) "una clave desconocida también rechaza el dry run"

# --- Apertura real: copia la carpeta gitignoreada por contenido, sin anidarla, y queda limpio ---
# `-Copy` va como UNA cadena con coma: así llega con `pwsh -File`, y el script la parte.
$t = New-Repo
$root = Join-Path (Split-Path $t -Parent) "carriles"
$out = Abrir $t @("-Slice", "07", "-Slug", "padron", "-Root", $root, "-Copy", ".env,.scratch")
$wt = Join-Path $root "slice-07"
Assert ($script:lastExit -eq 0) "la apertura sale 0 (salió $script:lastExit)"
Assert ((git -C $wt branch --show-current) -eq "slice/07-padron") "el worktree queda en la rama slice/07-padron"
Assert (Test-Path -LiteralPath (Join-Path $wt ".scratch/issues/07.md")) "la issue gitignoreada llega al worktree"
Assert (-not (Test-Path -LiteralPath (Join-Path $wt ".scratch/.scratch"))) "la carpeta copiada no queda anidada"
Assert (Test-Path -LiteralPath (Join-Path $wt ".env")) "la lista por comas copia también el primer elemento"
Assert (-not (git -C $wt status --porcelain)) "lo copiado no ensucia el worktree"
Assert ($out -match 'Worktree limpio') "la salida confirma que el worktree quedó limpio"

# --- Rama repetida: se niega ---
$out = Abrir $t @("-Slice", "07", "-Slug", "padron", "-Root", (Join-Path $root "otra"))
Assert ($script:lastExit -ne 0) "una rama que ya existe sale distinto de 0"
Assert ($out -match "La rama 'slice/07-padron' ya existe") "el rechazo nombra la rama repetida"
Assert (-not (Test-Path -LiteralPath (Join-Path $root "otra"))) "con la rama repetida no abre otro worktree"

# --- Base inexistente: se niega ---
$out = Abrir $t @("-Slice", "08", "-Slug", "otro", "-Root", $root, "-Base", "no-existe")
Assert ($script:lastExit -ne 0) "una base inexistente sale distinto de 0"
Assert ($out -match "La base 'no-existe' no existe") "el rechazo nombra la base"
git -C $t show-ref --verify --quiet "refs/heads/slice/08-otro"
Assert ($LASTEXITCODE -ne 0) "con la base inexistente no crea la rama"

# --- Lo copiado que no está ignorado se avisa ---
$t = New-Repo
"suelto" | Set-Content (Join-Path $t "suelto.txt")
$root = Join-Path (Split-Path $t -Parent) "carriles"
$out = Abrir $t @("-Slice", "09", "-Slug", "suelto", "-Root", $root, "-Copy", "suelto.txt")
Assert ($script:lastExit -eq 0) "copiar algo no ignorado no es un rechazo (salió $script:lastExit)"
# El aviso se ancla en la línea de `git status --porcelain` que trae adentro, no en el nombre del
# archivo suelto: ese nombre también aparece en la línea `Copiado:`, así que un aviso que dejara de
# incluir el status pasaba igual (medido).
Assert ($out -match 'no esta limpio' -and $out -match '(?m)^\?\? suelto\.txt') "avisa que lo copiado no está ignorado y muestra la línea de status"

# --- La plantilla REAL del scaffold, con marcas en el bloque, sale 0 con -DryRun ---
# El fixture de más arriba tiene las marcas FUERA del bloque, así que no cubría el caso que ve un
# proyecto recién bootstrapeado: sus tres claves llegan con marca, y una marca tomada como valor
# ('base: {{main}}') hacía fallar el chequeo de la base con exit 1, justo lo contrario de lo que
# prometen el ADR-0011 y la nota del archivo.
$plantilla = [IO.File]::ReadAllText((Join-Path $repo "skills/bootstrap-personal-project/assets/scaffold/docs/ai-workflow/PARALELISMO-DEL-PROYECTO.md"))
$t = New-Repo -datos $plantilla
$out = Abrir $t @("-Slice", "07", "-Slug", "padron", "-DryRun")
Assert ($script:lastExit -eq 0) "la plantilla recién bootstrapeada sale 0 con dry run (salió $script:lastExit)"
Assert ($out -match 'marcas sin rellenar') "avisa que la plantilla tiene marcas sin rellenar"
Assert ($out -match '(?m)^Rama:.*\(desde main @') "una marca en el bloque no se toma como base: rige el default"
Assert (($out -match '(?m)^Copiaria: \.env ') -and ($out -match '(?m)^Copiaria: \.scratch ')) "una marca en copiar no se toma como lista: rige el default"
Assert ($out -match 'DryRun: no se creo nada') "con la plantilla real, el dry run llega hasta el final"

# El default de la base es la rama ACTUAL, no el literal 'main': un repo adoptado que vive en
# 'master' salía 1 en el dry run («La base 'main' no existe»), que es el mismo fallo que el chequeo
# de marcas quiere evitar, ahora causado por el default.
$t = New-Repo -datos $plantilla
git -C $t branch -m master
$out = Abrir $t @("-Slice", "07", "-Slug", "padron", "-DryRun")
Assert ($script:lastExit -eq 0) "la plantilla en un repo que vive en master sale 0 con dry run (salió $script:lastExit)"
Assert ($out -match '(?m)^Rama:.*\(desde master @') "sin base declarada, el default es la rama actual"

# --- Un -Root relativo se resuelve en un solo lugar, aunque la cwd no sea la raíz del repo ---
# git -C lo resuelve contra el repo y los cmdlets contra la cwd: si no se normaliza, el worktree
# queda en un lado y lo copiado en otro.
$t = New-Repo
$sub = Join-Path $t "docs"
[IO.Directory]::CreateDirectory($sub) | Out-Null
$out = Abrir $sub @("-Slice", "07", "-Slug", "padron", "-Root", "wt-rel", "-Copy", ".scratch")
Assert ($script:lastExit -eq 0) "con -Root relativo desde un subdirectorio sale 0 (salió $script:lastExit)"
Assert (Test-Path -LiteralPath (Join-Path $sub "wt-rel/slice-07/.scratch/issues/07.md")) "el worktree y lo copiado caen en el mismo lugar, resuelto contra la cwd"
Assert (-not (Test-Path -LiteralPath (Join-Path $t "wt-rel"))) "no queda una carpeta suelta resuelta contra la raíz del repo"

# --- El worktrees relativo del BLOQUE se resuelve contra el repo, no contra la cwd ---
# Es la rama hermana del caso de arriba: el parámetro se resuelve contra la cwd (lo que escribió el
# usuario) y la clave del bloque contra el repo (el archivo de datos habla del repo). Sin el
# Join-Path, un carril abierto desde un subdirectorio caía en otro lado.
$relBloque = $script:datosOk -replace 'copiar: \.env, \.scratch', "copiar: .scratch`nworktrees: wt-bloque"
$t = New-Repo -datos $relBloque
$sub = Join-Path $t "docs"
[IO.Directory]::CreateDirectory($sub) | Out-Null
$out = Abrir $sub @("-Slice", "07", "-Slug", "padron")
Assert ($script:lastExit -eq 0) "con worktrees relativo en el bloque sale 0 (salió $script:lastExit)"
Assert (Test-Path -LiteralPath (Join-Path $t "wt-bloque/slice-07/.scratch/issues/07.md")) "el worktrees relativo del bloque cuelga del repo"
Assert (-not (Test-Path -LiteralPath (Join-Path $sub "wt-bloque"))) "el worktrees del bloque no se resuelve contra la cwd"

# --- Un repo con acentos en la ruta, con la consola en cp850 ---
# git escribe UTF-8 y PowerShell decodifica la salida del hijo con Console::OutputEncoding. Con un
# code page OEM, `rev-parse --show-toplevel` llega deformado y el script muere con un error crudo.
# Control positivo antes del caso: si el `GetEncoding(850)` del hijo fallara en silencio, el caso
# quedaría verde sin ejercitar el code page OEM, que es todo lo que prueba. Y el nombre se arma por
# punto de código y no como literal, para que el caso no dependa de con qué encoding se guardó ESTE
# archivo. Las dos cosas son las que ya fijó tests/review-marker.tests.ps1 para su propio caso.
$cp = ((& pwsh -NoProfile -Command "[Console]::OutputEncoding = [Text.Encoding]::GetEncoding(850); [Console]::OutputEncoding.CodePage") | Out-String).Trim()
Assert ($cp -eq "850") "control positivo: el pwsh hijo del fixture corre en code page 850 (dio '$cp')"
$t = New-Repo -nombre ("proyecto-acentuado-" + [string][char]0x00F1)
Assert ($t -match '[^\x00-\x7F]') "control positivo: la ruta del fixture tiene un caracter no ASCII"
$cmd = "[Console]::OutputEncoding = [Text.Encoding]::GetEncoding(850); Set-Location -LiteralPath '$t'; & '$script:abrir' -Slice 07 -Slug padron -DryRun; exit `$LASTEXITCODE"
$out = (@((& pwsh -NoProfile -Command $cmd 2>&1) | ForEach-Object { "$_" }) -join "`n")
Assert ($LASTEXITCODE -eq 0) "un repo con acentos en la ruta sale 0 con la consola en cp850 (salió $LASTEXITCODE)"
Assert ($out -match 'DryRun: no se creo nada') "con acentos y cp850 el dry run llega hasta el final"

# --- El bloque mal formado es un error, con y sin -DryRun ---
# Las tres guardas fallan ABIERTO si se las saca: dos bloques hace que se ignore el bloque entero,
# una clave repetida deja ganar a la última en silencio, y un bloque sin cerrar sigue leyendo el
# markdown de abajo. Cada caso ancla su mensaje: todos los rechazos salen 1, así que el exit code
# solo no distingue cuál guarda disparó.
$cerca = '```'
$malformados = @(
  @{ nombre = "dos bloques";     datos = $script:datosOk + "`n$cerca" + "carriles`nbase: otra`n$cerca"; mensaje = "2 bloques 'carriles'" },
  @{ nombre = "clave repetida";  datos = $script:datosOk -replace 'copiar: \.env, \.scratch', "copiar: .env`ncopiar: .scratch"; mensaje = "'copiar' aparece dos veces" },
  @{ nombre = "bloque sin cerrar"; datos = "# Datos`n`n$cerca" + "carriles`ncopiar: .env`n"; mensaje = "no esta cerrado" },
  @{ nombre = "linea sin dos puntos"; datos = $script:datosOk -replace 'copiar: \.env, \.scratch', "copiar: .env`nesto no es una clave"; mensaje = "sin forma 'clave: valor'" }
)
foreach ($caso in $malformados) {
  $t = New-Repo -datos $caso.datos
  $root = Join-Path (Split-Path $t -Parent) "carriles"
  foreach ($extra in @(@(), @("-DryRun"))) {
    $etiqueta = if ($extra) { "$($caso.nombre) con dry run" } else { $caso.nombre }
    $out = Abrir $t (@("-Slice", "07", "-Slug", "padron", "-Root", $root) + $extra)
    Assert ($script:lastExit -ne 0) "$($etiqueta): sale distinto de 0"
    Assert ($out -match [regex]::Escape($caso.mensaje)) "$($etiqueta): el rechazo dice «$($caso.mensaje)»"
  }
  Assert (-not (Test-Path -LiteralPath $root)) "$($caso.nombre): no abre el worktree"
}

Remove-TestRunRoot $script:runRoot

if ($script:failures -gt 0) { Write-Host "$($script:failures) test(s) FALLARON"; exit 1 } else { Write-Host "TODOS LOS TESTS PASARON"; exit 0 }
