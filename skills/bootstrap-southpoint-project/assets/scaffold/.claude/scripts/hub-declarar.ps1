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
$email = (& git -C $RepoDir config user.email).Trim()
$decl = [ordered]@{ schemaVersion = 1; hubProject = $HubProject; devs = [ordered]@{ $Dev = @($email) } }
[IO.Directory]::CreateDirectory((Split-Path $declPath -Parent)) | Out-Null
[IO.File]::WriteAllText($declPath, ($decl | ConvertTo-Json -Depth 5) + "`n", $utf8)
Write-Stdout ([ordered]@{ accion = 'creada'; dev = $Dev; emails = @($email) } | ConvertTo-Json -Compress)
