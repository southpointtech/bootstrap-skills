# tools/context-metric.ps1 — caracteres que un scaffold carga en el contexto de cada request.

function Get-FrontmatterField([string]$Text, [string]$Key) {
  $lines = ($Text -replace "`r`n", "`n" -replace "`r", "`n") -split "`n"
  $end = [Array]::IndexOf($lines, '---', 1)
  foreach ($l in $lines[1..($end - 1)]) {
    if ($l.StartsWith("${Key}:", [StringComparison]::Ordinal)) { return $l.Substring($Key.Length + 1).Trim() }
  }
  return $null
}

function Get-CodePointCount([string]$Text) {
  $n = 0
  foreach ($c in $Text.ToCharArray()) { if (-not [char]::IsLowSurrogate($c)) { $n++ } }
  return $n
}

function Measure-ContextLoad {
  param([Parameter(Mandatory)][object[]]$Files)
  $claudeMd = 0; $commands = 0; $loaded = 0; $flagged = 0
  foreach ($f in $Files) {
    if ($f.Path -eq 'CLAUDE.md') {
      $t = $f.Content.TrimStart([char]0xFEFF) -replace "`r`n", "`n" -replace "`r", "`n"
      $claudeMd = Get-CodePointCount $t
    } elseif ($f.Path -like '.claude/commands/*.md') {
      if ((Get-FrontmatterField $f.Content 'disable-model-invocation') -eq 'true') { $flagged++; continue }
      $commands += (Get-FrontmatterField $f.Content 'description').Length
      $loaded++
    }
  }
  [pscustomobject]@{
    ClaudeMd = $claudeMd
    Commands = $commands; CommandsLoaded = $loaded; CommandsFlagged = $flagged
    Total = $claudeMd + $commands
  }
}
