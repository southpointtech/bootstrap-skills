# tools/context-metric.ps1 — caracteres que un scaffold carga en el contexto de cada request.
#
# Dos usos:
#   Dot-sourceado:  . tools/context-metric.ps1 ; Measure-ContextLoad -Files <{Path, Content}[]>
#                   (Path relativo a la raíz del scaffold, con `/`). Función pura: no lee disco ni git.
#   CLI:            pwsh -NoProfile -File tools/context-metric.ps1 -Ref <commit|tag> [-Variant personal|southpoint|ai]
#                   Lee el árbol del scaffold de ese ref con `git show`: no hace checkout, no escribe
#                   nada y no usa la red.
#
# Existe porque la versión a mano de este número se publicó una vez con un método nunca declarado
# (issue 02 de `.scratch/medicion-v2/`). Por eso el método va en `$ContextMetricMethod`, que sale en
# el objeto que devuelve la función y en la salida de la CLI. Oráculo independiente para regrabar los
# literales de la suite: `tests/oracles/context-metric.py`.
param(
  [string]$Ref,
  [ValidateSet('personal', 'southpoint', 'ai')][string]$Variant = 'personal'
)

$ContextMetricMethod = @'
Suma, en code points Unicode (CRLF y CR cuentan como un salto; el BOM no cuenta):
  - CLAUDE.md de la raíz del scaffold, entero.
  - El valor de `description:` de cada .claude/commands/**/*.md que NO lleve
    `disable-model-invocation: true` (el flag saca la description del contexto).
  - El valor de `description:` de cada .claude/agents/**/*.md.
No suma: `name:`, `argument-hint:`, la línea del flag ni ninguna otra clave; los cuerpos de comandos
y agents (cargan al invocarlos); .agents/skills/ (Claude Code no lo lee); los CLAUDE.md de
subdirectorios (cargan bajo demanda); settings.json, los hooks ni su salida; las skills y plugins de
la máquina; el system prompt de Claude Code.
Tira, en vez de medir mal:
  - En todo .md de .claude/commands y .claude/agents: un frontmatter sin apertura o sin cierre.
  - En todo .md de .claude/commands: un flag que esté y sea vacío, entre comillas, en bloque, con
    un comentario, repetido o que siga en la línea de abajo. Los agents no leen el flag.
  - En la description de lo que carga (comandos sin el flag y agents): las mismas formas, y además
    ausente. De un comando con el flag no se lee la description, porque no carga.
  - Cualquier archivo bajo .claude/skills/.
'@

# Cuenta code points, no unidades UTF-16: un carácter fuera del BMP es un par de surrogates en .NET.
function Get-CodePointCount([string]$Text) {
  $n = 0
  foreach ($c in $Text.ToCharArray()) { if (-not [char]::IsLowSurrogate($c)) { $n++ } }
  return $n
}

# Valor de una clave del frontmatter, en una sola línea y sin comillas. Lo que no es esa forma tira:
# un YAML a medio parsear daría un número equivocado sin avisar.
function Get-FrontmatterField([string]$Path, [string]$Text, [string]$Key) {
  $lines = ($Text -replace "`r`n", "`n" -replace "`r", "`n") -split "`n"
  if ($lines[0] -ne '---') { throw "${Path}: no arranca con frontmatter" }
  $end = [Array]::IndexOf($lines, '---', 1)
  if ($end -lt 0) { throw "${Path}: el frontmatter no cierra" }
  $found = $null
  # `for` y no `$lines[1..($end - 1)]`: con el frontmatter vacío ($end = 1) ese rango es 1..0, que
  # PowerShell recorre al revés en vez de dejarlo vacío.
  for ($i = 1; $i -lt $end; $i++) {
    $l = $lines[$i]
    if (-not $l.StartsWith("${Key}:", [StringComparison]::Ordinal)) { continue }
    if ($null -ne $found) { throw "${Path}: '${Key}' está repetida (YAML no la admite, y la métrica no elige cuál vale)" }
    $v = $l.Substring($Key.Length + 1).Trim()
    if ($v -eq '' -or $v[0] -in '"', "'", '>', '|') {
      throw "${Path}: '${Key}' no es un valor plano de una línea, y la métrica no mide esa forma"
    }
    # Ya recortado: un valor que es solo un comentario arranca con `#` (YAML lo lee vacío).
    if ($v -match '(^|\s)#') { throw "${Path}: '${Key}' tiene un comentario al final, o un # después de otro blanco, y la métrica no mide esa forma" }
    # Un valor plano sigue en las líneas indentadas de abajo (YAML las pliega); las vacías no cortan.
    $j = $i + 1
    while ($j -lt $end -and $lines[$j].Trim() -eq '') { $j++ }
    if ($j -lt $end -and $lines[$j] -match '^\s+#') {
      throw "${Path}: '${Key}' tiene un comentario en la línea siguiente, y la métrica no mide esa forma"
    }
    if ($j -lt $end -and $lines[$j] -match '^\s') {
      throw "${Path}: '${Key}' sigue en la línea siguiente, y la métrica solo lee una"
    }
    $found = $v
  }
  return $found
}

# Las rutas (relativas a la raíz del scaffold) que la CLI le pasa a Measure-ContextLoad: lo que mide y
# lo que tiene que rechazar. Dejar afuera .claude/skills/ haría que la CLI imprima un número menor.
function Select-ScaffoldPaths([string[]]$Paths) {
  $Paths | Where-Object {
    $_ -eq 'CLAUDE.md' -or $_ -like '.claude/commands/*' -or $_ -like '.claude/agents/*' -or $_ -like '.claude/skills/*'
  }
}

function Measure-ContextLoad {
  param([Parameter(Mandatory)][object[]]$Files)
  $claudeMd = 0; $commands = 0; $loaded = 0; $flagged = 0; $agents = 0; $agentsLoaded = 0
  foreach ($f in $Files) {
    if ($f.Path -eq 'CLAUDE.md') {
      $t = $f.Content.TrimStart([char]0xFEFF) -replace "`r`n", "`n" -replace "`r", "`n"
      $claudeMd = Get-CodePointCount $t
    } elseif ($f.Path -like '.claude/skills/*') {
      throw "$($f.Path): hay un .claude/skills/ y la métrica todavía no lo suma"
    } elseif ($f.Path -like '.claude/commands/*.md' -or $f.Path -like '.claude/agents/*.md') {
      $isCommand = $f.Path -like '.claude/commands/*'
      if ($isCommand -and (Get-FrontmatterField $f.Path $f.Content 'disable-model-invocation') -eq 'true') {
        $flagged++; continue
      }
      $d = Get-FrontmatterField $f.Path $f.Content 'description'
      if ($null -eq $d) { throw "$($f.Path): no tiene description (Claude Code usaría el cuerpo)" }
      if ($isCommand) { $commands += Get-CodePointCount $d; $loaded++ }
      else            { $agents   += Get-CodePointCount $d; $agentsLoaded++ }
    }
  }
  [pscustomobject]@{
    ClaudeMd = $claudeMd
    Commands = $commands; CommandsLoaded = $loaded; CommandsFlagged = $flagged
    Agents = $agents; AgentsLoaded = $agentsLoaded
    Total = $claudeMd + $commands + $agents
    Method = $ContextMetricMethod
  }
}

# `git` con la salida decodificada como UTF-8: `& git` en pwsh decodifica con la code page de la
# consola y deforma los acentos de los archivos (memoria `pwsh-decodifica-git-en-cp850`).
function Invoke-GitUtf8([string]$RepoRoot, [string[]]$GitArgs) {
  $psi = [Diagnostics.ProcessStartInfo]::new('git')
  $psi.ArgumentList.Add('-C'); $psi.ArgumentList.Add($RepoRoot)
  foreach ($a in $GitArgs) { $psi.ArgumentList.Add($a) }
  $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
  $psi.StandardOutputEncoding = [Text.UTF8Encoding]::new($false)
  $p = [Diagnostics.Process]::Start($psi)
  $out = $p.StandardOutput.ReadToEnd(); $err = $p.StandardError.ReadToEnd(); $p.WaitForExit()
  if ($p.ExitCode -ne 0) { throw "git $($GitArgs -join ' '): $err" }
  return $out
}

if ($MyInvocation.InvocationName -ne '.') {
  $ErrorActionPreference = 'Stop'
  if (-not $Ref) { throw "falta -Ref <commit|tag>" }
  $repoRoot = Split-Path $PSScriptRoot -Parent
  $root = "skills/bootstrap-$Variant-project/assets/scaffold"
  $sha = (Invoke-GitUtf8 $repoRoot @('rev-parse', '--short', "$Ref^{commit}")).Trim()
  $paths = @(Select-ScaffoldPaths @(
    (Invoke-GitUtf8 $repoRoot @('ls-tree', '-r', '-z', '--name-only', $sha, '--', $root)) -split "`0" |
      Where-Object { $_ } | ForEach-Object { $_.Substring($root.Length + 1) }))
  # Sin CLAUDE.md no hay scaffold en ese ref (variante que todavía no existía, ruta movida): medir
  # igual daría un número chico y creíble.
  if ('CLAUDE.md' -notin $paths) { throw "no hay CLAUDE.md en $root @ $Ref ($sha)" }
  $files = foreach ($p in $paths) {
    [pscustomobject]@{ Path = $p; Content = Invoke-GitUtf8 $repoRoot @('show', "${sha}:$root/$p") }
  }
  $r = Measure-ContextLoad -Files @($files)
  "Contexto cargado por request - scaffold $Variant @ $Ref ($sha)"
  "{0,-40} {1,7}" -f 'CLAUDE.md', $r.ClaudeMd
  "{0,-40} {1,7}" -f "Comandos ($($r.CommandsLoaded) cargan, $($r.CommandsFlagged) con el flag)", $r.Commands
  "{0,-40} {1,7}" -f "Agents ($($r.AgentsLoaded))", $r.Agents
  "{0,-40} {1,7}" -f 'Total', $r.Total
  ""
  "Método:"
  $r.Method
}
