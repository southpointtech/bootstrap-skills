# .claude/scripts/hub-recolectar.ps1 — recolección de hub-sync (ver docs/adr/0012 en Bootstrap Skills).
#
# Lee los commits del dev con trailer `Slice-Close:` y las transiciones de `Status:` de los issues de
# `.scratch/`, y escribe un LOTE JSON por corrida: una propuesta `update` por slice cerrado, un `hito`
# por issue que pasó a `done` y un `riesgo` por issue que pasó a `needs-info`. No toca el Hub ni usa
# un LLM: el lote lo lleva el transporte a `inbox/` y sólo el PM decide qué se publica.
#
#   pwsh -File .claude/scripts/hub-recolectar.ps1 -RepoDir <repo> -Dev <nombre> [-StateDir <dir>] [-Now <iso>]
#
# Declaración, commiteada en el repo: `.claude/hub-sync.json`. Sin ella el repo no se recolecta.
#
#   { "schemaVersion": 1,
#     "hubProject": "<proyecto del Hub>",
#     "ongoingSupport": "<Ongoing Support, opcional>",
#     "devs": { "<nombre>": ["<email>", "<otro email del mismo dev>"] } }
#
# Estado por repo en <StateDir>/<repo>-<hash>/: `foto.json` (su `schemaVersion`, los SHA ya vistos y,
# por worktree, el estado de cada issue de su `.scratch/` tal como lo dejó `Read-Scratch`) y
# `lotes/<momento>.json`. Vive fuera del repo para no ensuciar el árbol de trabajo del dev. El hash es
# del directorio git común del repo, así que dos repos con el mismo nombre de carpeta no comparten
# foto, y los worktrees de un mismo repo sí.
#
# La primera corrida fija la línea de base: marca como vistos los slices que ya existen y no propone
# el histórico. Se recorren todas las refs (`git log --all`: ramas locales y las remotas que ya estén
# fetcheadas; el script no hace fetch) y la foto guarda SHA, no una
# posición en una rama, así que cambiar de rama no pierde ni repite slices.
# Límite conocido: un squash-merge crea un SHA nuevo con el mismo trailer y se propone dos veces;
# el PM descarta el duplicado al aprobar.
#
# Salida: la ruta del lote por stdout, en bytes UTF-8 y no en la codificación de la consola.
# Exit 0 con lote `ok` o `sin cambios`; exit 0 sin lote si no hay declaración o el dev no figura
# en ella; exit 1 con lote `falló` + motivo si la declaración es
# inválida, la foto es ilegible o git falla.
param(
  [Parameter(Mandatory)][string]$RepoDir,
  [Parameter(Mandatory)][string]$Dev,
  [string]$StateDir = (Join-Path $env:LOCALAPPDATA "hub-sync"),
  [string]$Now = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
)
$ErrorActionPreference = "Stop"
$utf8 = [Text.UTF8Encoding]::new($false)

# git emite UTF-8 (i18n.logOutputEncoding) y pwsh decodifica la salida de un hijo con
# [Console]::OutputEncoding, que en estas máquinas es ibm850: sin hacer nada, un asunto con acentos
# llega deformado al lote. La forma OBVIA de arreglarlo —fijar [Console]::OutputEncoding en UTF-8— es
# un efecto global: esa propiedad no es del proceso sino de la CONSOLA, y el valor que fija este
# script se lo queda cualquier proceso que arranque después ahí (medido el 2026-09-20; `chcp.com`
# ni siquiera lo informa). Bajo `tests/run-all.ps1`, que corre suites en paralelo en una consola, eso
# son rojos cruzados (issue 15). Así que la decodificación se declara por llamada, sin tocar a nadie.
function Invoke-GitUtf8([string[]]$Argumentos) {
  $psi = [Diagnostics.ProcessStartInfo]::new('git')
  foreach ($a in $Argumentos) { $psi.ArgumentList.Add($a) }
  $psi.UseShellExecute = $false
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.StandardOutputEncoding = [Text.UTF8Encoding]::new($false)
  # El stderr también: el motivo de una corrida fallida trae rutas, y deformadas no sirven.
  $psi.StandardErrorEncoding = [Text.UTF8Encoding]::new($false)
  $p = [Diagnostics.Process]::Start($psi)
  try {
    # En paralelo: leer los dos canales en serie puede trabar al hijo si se le llena el otro buffer.
    $err = $p.StandardError.ReadToEndAsync()
    $salida = $p.StandardOutput.ReadToEnd()
    $p.WaitForExit()
    [pscustomobject]@{ stdout = $salida; stderr = $err.Result.Trim(); exit = $p.ExitCode }
  } finally { $p.Dispose() }
}

# La ruta del lote sale por stdout en bytes UTF-8, por la misma razón: `Write-Output` la codificaría
# con [Console]::OutputEncoding, y dejarla en UTF-8 exige cambiársela a toda la consola. Quien llama
# decodifica UTF-8, que es lo que este script promete escribir.
function Write-Stdout([string]$texto) {
  $s = [Console]::OpenStandardOutput()
  $b = $utf8.GetBytes($texto + "`n")
  $s.Write($b, 0, $b.Length)
  $s.Flush()
}

# La identidad del repo es su directorio git común, no el nombre de la carpeta: dos clones con el
# mismo nombre compartirían la foto y se re-propondrían el histórico uno al otro en cada corrida. Si
# no es un repo git, la ruta de la carpeta (la corrida va a fallar igual, pero su lote tiene dónde ir).
$g = Invoke-GitUtf8 @('-C', $RepoDir, 'rev-parse', '--path-format=absolute', '--git-common-dir')
if ($g.exit -eq 0 -and $g.stdout.Trim()) {
  $identidad = [IO.Path]::GetFullPath($g.stdout.Trim())
  $repoName = if ((Split-Path $identidad -Leaf) -eq ".git") { Split-Path (Split-Path $identidad -Parent) -Leaf } else { Split-Path $identidad -Leaf }
} else {
  $identidad = [IO.Path]::GetFullPath($RepoDir)
  $repoName = Split-Path $identidad.TrimEnd('\', '/') -Leaf
}
$hash = [BitConverter]::ToString([Security.Cryptography.SHA256]::HashData(
  $utf8.GetBytes($identidad.TrimEnd('\', '/').ToLowerInvariant()))).Replace("-", "").Substring(0, 8).ToLowerInvariant()
$dir = Join-Path $StateDir "$repoName-$hash"
# `repo` es para leer; `repoId` es para agrupar. El nombre de la carpeta no identifica un repo entre
# PCs (dos repos distintos pueden llamarse igual), su origin sí: se normaliza para que la forma https
# y la ssh (con esquema o scp), con o sin `.git`, con o sin puerto, con credenciales en la URL o con
# otras mayúsculas, den el mismo id en las tres PCs. Las dos formas se separan porque el `:` significa
# cosas distintas: con esquema, lo que sigue al host es un puerto; en la scp (`git@host:dueño/repo`),
# es el comienzo de la ruta, aunque el dueño empiece con un dígito. Sin origin no hay identidad
# compartida y el id es la del directorio git común.
$o = Invoke-GitUtf8 @('-C', $RepoDir, 'remote', 'get-url', 'origin')
$repoId = if ($o.exit -eq 0 -and $o.stdout.Trim()) {
  $url = $o.stdout.Trim()
  $url = if ($url -match '^[a-z][a-z0-9+.-]*://') {
    $url -replace '^[a-z][a-z0-9+.-]*://', '' -replace '^[^@/]+@', '' -replace '^([^/:]+):\d+(/|$)', '$1$2'
  } else {
    $url -replace '^[^@/]+@', '' -replace '^([^/:]+):', '$1/'
  }
  $url -replace '/+$', '' -replace '\.git$', '' | ForEach-Object ToLowerInvariant
} else { $identidad.TrimEnd('\', '/').Replace('\', '/').ToLowerInvariant() }
$lote = [ordered]@{
  schemaVersion = 1
  dev           = $Dev
  repo          = $repoName
  repoId        = $repoId
  momento       = $Now
  resultado     = "sin cambios"
  propuestas    = @()
}

# El lote se crea con CreateNew: dos corridas con el mismo momento (una manual y la programada) no se
# pisan, la segunda lleva sufijo. Pisar un `ok` con un `sin cambios` perdería sus propuestas, porque
# la foto ya las marcó como vistas.
function Write-Lote {
  $lotes = Join-Path $dir "lotes"
  [IO.Directory]::CreateDirectory($lotes) | Out-Null
  $base = Join-Path $lotes ($Now -replace '[:-]', '')
  $bytes = $utf8.GetBytes(($lote | ConvertTo-Json -Depth 6))
  for ($i = 1; $i -le 100; $i++) {
    $p = if ($i -eq 1) { "$base.json" } else { "$base-$i.json" }
    try { $fs = [IO.File]::Open($p, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write) }
    catch [IO.IOException] { if (Test-Path -LiteralPath $p) { continue } else { throw } }
    try { $fs.Write($bytes, 0, $bytes.Length) } finally { $fs.Dispose() }
    return $p
  }
  throw "100 lotes con el momento $Now en $lotes"
}

# Una corrida que falla también deja su lote: es lo que el tablero de corridas lee para ponerla en
# rojo. La foto no se toca, así que la corrida siguiente retoma desde donde estaba.
function Fallar([string]$motivo) {
  $lote.resultado = "falló"
  $lote.motivo = $motivo
  Write-Stdout (Write-Lote)
  exit 1
}

# Sin declaración el repo no se recolecta; y un dev que no figura en ella no tiene nada que proponer.
# Los dos salen sin lote y en exit 0: no son fallas, son repos o devs fuera de hub-sync.
$declPath = Join-Path $RepoDir ".claude/hub-sync.json"
if (-not (Test-Path -LiteralPath $declPath)) { exit 0 }
try { $decl = Get-Content -LiteralPath $declPath -Raw | ConvertFrom-Json }
catch { Fallar "la declaración .claude/hub-sync.json no es JSON válido: $($_.Exception.Message)" }
if ($decl.schemaVersion -ne 1) { Fallar "schemaVersion de la declaración no soportado: '$($decl.schemaVersion)' (se espera 1)" }
if (-not ($decl.hubProject -is [string]) -or -not $decl.hubProject.Trim()) { Fallar "la declaración no nombra el hubProject" }
if ($null -ne $decl.PSObject.Properties['ongoingSupport'] -and
    (-not ($decl.ongoingSupport -is [string]) -or -not $decl.ongoingSupport.Trim())) {
  Fallar "el ongoingSupport de la declaración tiene que ser un texto no vacío"
}
if (-not ($decl.devs -is [pscustomobject])) { Fallar "la declaración no tiene devs" }
if (-not $decl.devs.PSObject.Properties[$Dev]) { exit 0 }
$emails = @($decl.devs.$Dev | Where-Object { $_ -is [string] -and $_.Trim() })
if (-not $emails.Count) { Fallar "el dev '$Dev' no tiene emails en la declaración" }
$lote.hubProject = $decl.hubProject
if ($decl.ongoingSupport) { $lote.ongoingSupport = $decl.ongoingSupport }

# Los commits con `Slice-Close:`, en todas las ramas.
# El cuerpo entero (%B) y no `%(trailers)`: el parser de trailers de git sólo lee el ÚLTIMO párrafo, y
# el commit estándar del workflow cierra con `Co-Authored-By:` tras una línea en blanco, así que el
# `Slice-Close:` queda en el penúltimo y git no lo ve. Detecta la línea como el hook
# review-loop-trigger (a principio de línea, sin distinguir mayúsculas), pero además exige un valor en
# la misma línea: un `Slice-Close:` vacío no es un cierre, y con `\s*` el valor sería la línea
# siguiente. Un registro por commit, separado por \x1e, porque el cuerpo trae saltos de línea.
$log = Invoke-GitUtf8 @('-C', $RepoDir, 'log', '--all', '--format=%H%x1f%ae%x1f%aI%x1f%s%x1f%B%x1e')
if ($log.exit -ne 0) { Fallar "git log falló en $RepoDir`: $($log.stderr -replace '\s+', ' ')" }
# Sólo stdout: lo que git escribe en stderr aunque salga 0 (p. ej. los hints de grafts) viene por
# su propio canal y no se mezcla con los registros, que es lo que pasaba con `2>&1`.
$todos = @($log.stdout -split "`u{1e}" |
  ForEach-Object {
    $c = $_.TrimStart("`n") -split "`u{1f}"
    if ($c.Count -lt 5 -or $c[0] -notmatch '^[0-9a-f]{40}$') { return }
    $valores = @([regex]::Matches($c[4], '(?im)^[ \t]*Slice-Close:[ \t]*(\S.*?)[ \t\r]*$') | ForEach-Object { $_.Groups[1].Value })
    if ($valores.Count) {
      [pscustomobject]@{ sha = $c[0]; email = $c[1]; fecha = $c[2]; asunto = $c[3]; sliceClose = $valores -join ", " }
    }
  })
# Sólo los del dev se proponen, pero la foto guarda los de TODOS los autores: si más tarde se agrega un
# email a la declaración, el histórico de esa cuenta ya está visto y no se re-propone entero.
$slices = @($todos | Where-Object { $emails -contains $_.email })

# Sin foto es la primera corrida: fija la línea de base marcando todo lo existente como visto.
# Una foto ilegible falla con lote y no se pisa: re-fijar la línea de base en silencio perdería los
# slices que estaban pendientes.
$fotoPath = Join-Path $dir "foto.json"
$propuestas = @()
if (Test-Path -LiteralPath $fotoPath) {
  try { $foto = Get-Content -LiteralPath $fotoPath -Raw | ConvertFrom-Json }
  catch { Fallar "la foto $fotoPath es ilegible: $($_.Exception.Message)" }
  if ($null -eq $foto -or $null -eq $foto.PSObject.Properties['vistos']) { Fallar "la foto $fotoPath no tiene la lista de vistos" }
  $vistosAntes = @($foto.vistos)
  $propuestas = @($slices | Where-Object { $vistosAntes -notcontains $_.sha } | ForEach-Object {
    [ordered]@{
      id      = "commit:$($_.sha)"
      tipo    = "update"
      destino = "delivery"
      estado  = "nueva"
      hechos  = [ordered]@{ sha = $_.sha; asunto = $_.asunto; sliceClose = $_.sliceClose; fecha = $_.fecha }
    }
  })
}

# Los `Status:` de `.scratch/<feature>/issues/*.md` de un checkout, por `<feature>/<archivo>`. Sólo los
# issues: el PRD de la feature también lleva `Status:` y no es un avance. Un archivo sin `Status:` no es
# un issue del workflow.
function Read-Scratch([string]$raiz) {
  $issues = [ordered]@{}
  $sc = Join-Path $raiz ".scratch"
  if (-not (Test-Path -LiteralPath $sc -PathType Container)) { return $issues }
  foreach ($feat in Get-ChildItem -LiteralPath $sc -Directory) {
    $dirIssues = Join-Path $feat.FullName "issues"
    if (-not (Test-Path -LiteralPath $dirIssues -PathType Container)) { continue }
    foreach ($f in Get-ChildItem -LiteralPath $dirIssues -File | Where-Object { $_.Extension -eq ".md" }) {
      $txt = [IO.File]::ReadAllText($f.FullName)
      # El estado se compara como un TOKEN CANÓNICO —sin los backticks, sin la nota que lo sigue, en
      # minúsculas— para que cambiar sólo la nota o las mayúsculas no cuente como transición. Los dos
      # corpus de esta máquina mezclan las dos formas (`Status: done` y `Status: \`done\` (…)`), y
      # `marcar-done` escribe siempre la plana, así que sin canonizar su reescritura sería una
      # transición fantasma.
      # La nota empieza donde termina el token: el backtick de cierre, un paréntesis o una raya. Una
      # coma o una palabra suelta NO la abren, porque CALIFICAN el estado en vez de anotarlo:
      # `done, pendiente QA manual` dice que el issue no está cerrado, y publicarlo como hito es lo
      # contrario de lo que su autor escribió. Un valor así —y cualquiera que no sea un token, como
      # `**§2 IMPLEMENTADA**`— se guarda CRUDO: no mapea a ningún tipo, así que nunca propone nada,
      # pero queda registrado y su paso posterior a un estado limpio sí se propone. Saltear el archivo
      # en cambio lo haría parecer nuevo entonces, y ese hito se perdería en silencio.
      $st = [regex]::Match($txt, '(?m)^Status:([^\r\n]*)')
      if (-not $st.Success) { continue }
      $val = $st.Groups[1].Value.Trim()
      if (-not $val) { continue }
      $tok = [regex]::Match($val, '^`?([A-Za-z][A-Za-z-]*)`?[ \t]*(?:$|\(|[—–])')
      $tit = [regex]::Match($txt, '(?m)^#[ \t]+([^\r\n]+)')
      $issues["$($feat.Name)/$($f.Name)"] = [pscustomobject]@{
        status = if ($tok.Success) { $tok.Groups[1].Value.ToLowerInvariant() } else { $val }
        titulo = if ($tit.Success) { $tit.Groups[1].Value.Trim() } else { $f.BaseName }
      }
    }
  }
  return $issues
}

# Las transiciones de `.scratch/` contra la foto. `.scratch/` no se versiona, así que cada worktree
# tiene el suyo: se leen los de TODOS los worktrees del repo (`marcar-done` escribe en el worktree donde
# corrió el loop, y la tarea programada corre en uno solo), y cada uno se compara con SU sección de la
# foto. Sin foto, o con una de otra versión, todo fija su línea de base y no se propone nada. Un
# worktree recién creado (un carril) no tiene sección, pero `abrir-carril` le copia `.scratch/` salvo
# que el proyecto declare otra lista: el estado anterior de cada issue es el que registran los otros
# worktrees, y se propone sólo si NINGUNO ya registraba el estado nuevo. Así un carril abierto y
# cerrado entre dos corridas no pierde su hito mientras su worktree siga en disco (uno borrado sale de
# la foto, y con él lo que no se haya leído todavía), y uno copiado de un main que ya estaba en `done`
# no lo repite. Un issue que sólo existe en el carril nuevo no tiene estado anterior y no se propone.
$wtList = Invoke-GitUtf8 @('-C', $RepoDir, 'worktree', 'list', '--porcelain')
if ($wtList.exit -ne 0) { Fallar "git worktree list falló en $RepoDir`: $($wtList.stderr -replace '\s+', ' ')" }
$scratchAhora = [ordered]@{}
foreach ($l in @($wtList.stdout -split "`r?`n" | Where-Object { $_.StartsWith("worktree ") })) {
  $raiz = [IO.Path]::GetFullPath($l.Substring(9)).TrimEnd('\', '/')
  if (-not (Test-Path -LiteralPath $raiz -PathType Container)) { continue }
  $scratchAhora[$raiz.ToLowerInvariant()] = Read-Scratch $raiz
}
# La sección `scratch` de una foto de otra versión NO se compara: la v1 guardaba la línea `Status:`
# entera y la v2 guarda el token canónico, así que compararlas daría una transición por cada issue.
# Se re-fija su línea de base. `vistos` se conserva igual: rechazar la foto entera re-propondría el
# histórico de slices completo, que es mucho peor que perder una transición de `.scratch/`.
$scratchAntes = if ($foto -and $foto.schemaVersion -eq 2 -and $foto.PSObject.Properties['scratch']) { $foto.scratch } else { $null }
foreach ($k in $scratchAhora.Keys) {
  if (-not $scratchAntes) { break }
  $antes = $scratchAntes.PSObject.Properties[$k]
  foreach ($rel in $scratchAhora[$k].Keys) {
    $i = $scratchAhora[$k][$rel]
    if ($antes) {
      $previo = $antes.Value.PSObject.Properties[$rel]
      if (-not $previo -or $previo.Value -ceq $i.status) { continue }
      $de = $previo.Value
    } else {
      $conIssue = @($scratchAntes.PSObject.Properties | Where-Object { $_.Value.PSObject.Properties[$rel] })
      $otros = @($conIssue | ForEach-Object { $_.Value.PSObject.Properties[$rel].Value })
      if (-not $otros.Count -or $otros -ccontains $i.status) { continue }
      # La guarda mira a TODOS los worktrees, pero el `de` que el PM va a leer sale de UNO: el
      # principal, que `git worktree list` lista primero (git-worktree(1)), y si él no registra el
      # issue, el primero que lo registre. Sin este criterio el `de` lo decidiría el orden de las
      # claves de la foto, que nadie declara.
      $principal = @($scratchAhora.Keys)[0]
      $delPrincipal = @($conIssue | Where-Object { $_.Name -eq $principal })
      $de = if ($delPrincipal.Count) { $delPrincipal[0].Value.PSObject.Properties[$rel].Value } else { $otros[0] }
    }
    # `needs-info` es un riesgo y no un action item: sin LLM no se distinguen, y un riesgo es interno,
    # así que nada llega al cliente si el PM no lo reclasifica.
    $tipo = @{ "done" = "hito"; "needs-info" = "riesgo" }[$i.status]
    if (-not $tipo) { continue }
    # La misma transición vista en dos worktrees es una sola propuesta: el id no nombra el worktree.
    $id = "issue:${rel}:$($i.status)"
    if (@($propuestas | Where-Object { $_.id -ceq $id }).Count) { continue }
    # Los commits del dev cuyo `Slice-Close:` cita este issue por ruta: el hito y el `update` de esos
    # commits son la misma obra, y el PM los ve juntos. `.md` no puede seguir con `x`, `.x` ni `-`, para
    # que `01-uno.mdx` no cite a `01-uno.md`; un punto final de oración sí puede seguir.
    $feat, $archivo = $rel -split '/', 2
    $cita = '(?<![^\s`''"(\[,])' + [regex]::Escape(".scratch/$feat/issues/$archivo") + '(?!\w|\.\w|-)'
    $commits = @($slices | Where-Object { $_.sliceClose -match $cita } | ForEach-Object { $_.sha })
    $propuestas += [ordered]@{
      id      = $id
      tipo    = $tipo
      destino = "delivery"
      estado  = "nueva"
      hechos  = [ordered]@{ issue = $rel; titulo = $i.titulo; de = $de; a = $i.status; commits = $commits }
    }
  }
}

if ($propuestas.Count) { $lote.resultado = "ok"; $lote.propuestas = $propuestas }
# El lote antes que la foto: si la corrida muere entre las dos, la próxima vuelve a proponer lo mismo
# y la ingesta lo deduplica por id. Al revés, se perdería.
$archivo = Write-Lote
# La foto se escribe aparte y se mueve encima: WriteAllText trunca antes de escribir, y una PC que se
# apaga a mitad dejaría una foto cortada.
$tmp = "$fotoPath.tmp"
$scratchFoto = [ordered]@{}
foreach ($k in $scratchAhora.Keys) {
  $s = [ordered]@{}
  foreach ($rel in $scratchAhora[$k].Keys) { $s[$rel] = $scratchAhora[$k][$rel].status }
  $scratchFoto[$k] = $s
}
[IO.File]::WriteAllText($tmp, ([ordered]@{ schemaVersion = 2; vistos = @($todos | ForEach-Object { $_.sha }); scratch = $scratchFoto } | ConvertTo-Json -Depth 5), $utf8)
[IO.File]::Move($tmp, $fotoPath, $true)
Write-Stdout $archivo
