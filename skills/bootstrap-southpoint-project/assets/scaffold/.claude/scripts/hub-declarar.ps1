# .claude/scripts/hub-declarar.ps1 — crea o actualiza la declaración de hub-sync del repo.
#
#   pwsh -File .claude/scripts/hub-declarar.ps1 -RepoDir <repo> [-HubProject <texto>] [-Agregarme] [-Dev <usuario>]
param(
  [Parameter(Mandatory)][string]$RepoDir,
  [string]$HubProject,
  [switch]$Agregarme,
  [string]$Dev = $env:USERNAME
)
$ErrorActionPreference = "Stop"
$utf8 = [Text.UTF8Encoding]::new($false)

function Write-Stdout([string]$texto) {
  $s = [Console]::OpenStandardOutput()
  $b = $utf8.GetBytes($texto + "`n")
  $s.Write($b, 0, $b.Length)
  $s.Flush()
}

$declPath = Join-Path $RepoDir ".claude/hub-sync.json"
# Los emails con los que este dev commitea en el repo: la identidad git efectiva (la local que fija
# el Step 5 del bootstrap, o la global si no hay) y la de `setup-mcp-workstation`. El recolector
# filtra los commits por estos emails, así que uno que falte es un slice que no se propone.
$propios = @((& git -C $RepoDir config user.email 2>$null), $env:SOUTHPOINT_GIT_EMAIL)

# La declaración que ya existe se lee como tabla ORDENADA: reescribirla conserva el orden de sus
# claves y cualquier campo que este script no conoce.
$existe = Test-Path -LiteralPath $declPath
if ($existe) { $decl = [IO.File]::ReadAllText($declPath) | ConvertFrom-Json -AsHashtable }
else { $decl = [ordered]@{ schemaVersion = 1; hubProject = $HubProject; devs = [ordered]@{} } }

# Los emails que el dev ya tenía van primero; los nuevos se suman al final, sin repetir. Sin
# distinguir mayúsculas, igual que el recolector, que filtra los commits con `-contains`.
$emails = [Collections.Generic.List[string]]::new()
if ($Agregarme) {
  foreach ($e in @($decl.devs[$Dev]) + $propios) {
    $e = "$e".Trim()
    if ($e -and -not ($emails | Where-Object { $_ -ieq $e })) { $emails.Add($e) }
  }
  $decl.devs[$Dev] = $emails.ToArray()
}
[IO.Directory]::CreateDirectory((Split-Path $declPath -Parent)) | Out-Null
[IO.File]::WriteAllText($declPath, (ConvertTo-Json -InputObject $decl -Depth 5) + "`n", $utf8)
$accion = if ($existe) { 'actualizada' } else { 'creada' }
Write-Stdout (ConvertTo-Json -Compress -InputObject ([ordered]@{ accion = $accion; dev = $Dev; emails = $emails.ToArray() }))
exit 0
