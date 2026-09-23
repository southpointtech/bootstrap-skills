# tools/context-metric.ps1 — caracteres que un scaffold carga en el contexto de cada request.

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
  foreach ($l in $lines[1..($end - 1)]) {
    if (-not $l.StartsWith("${Key}:", [StringComparison]::Ordinal)) { continue }
    $v = $l.Substring($Key.Length + 1).Trim()
    if ($v -eq '' -or $v[0] -in '"', "'", '>', '|') {
      throw "${Path}: '${Key}' no es un valor plano de una línea, y la métrica no mide esa forma"
    }
    return $v
  }
  return $null
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
  }
}
