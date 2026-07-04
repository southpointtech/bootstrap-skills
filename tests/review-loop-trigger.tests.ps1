# tests/review-loop-trigger.tests.ps1 — runner sin Pester. Correr: pwsh -NoProfile -File tests/review-loop-trigger.tests.ps1
# Fixtures determinísticos (repos git temporales) para el hook review-loop-trigger y el merge de settings.
$ErrorActionPreference = "Stop"
$repo  = Split-Path $PSScriptRoot -Parent
$hook  = Join-Path $repo "skills/bootstrap-personal-project/assets/scaffold/.claude/hooks/review-loop-trigger.ps1"
$canon = Join-Path $repo "skills/bootstrap-personal-project/assets/scaffold/.claude/settings.json"
$ms    = Join-Path $repo "skills/upgrade-bootstrap/scripts/merge-settings.ps1"
$script:failures = 0

function Assert($cond, $msg) {
  if ($cond) { Write-Host "ok:   $msg" } else { Write-Host "FAIL: $msg"; $script:failures++ }
}
function New-Repo {
  $t = Join-Path ([IO.Path]::GetTempPath()) ("rlt-test-" + [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $t | Out-Null
  git -C $t init -q -b master; git -C $t config user.email a@b.c; git -C $t config user.name a
  git -C $t commit --allow-empty -q -m base
  git -C $t checkout -q -b feat/x; git -C $t commit --allow-empty -q -m slice
  return $t
}
# Invoca el hook con un evento PostToolUse; cwd debe ser un path Windows real (como lo pasa Claude Code).
function Fire($repo, $cmd) {
  $evt = @{ tool_input = @{ command = $cmd }; cwd = $repo } | ConvertTo-Json -Compress
  return ($evt | & pwsh -NoProfile -File $hook)
}

# --- Hook ---
$t = New-Repo; $o = Fire $t "ls -la"
Assert ([string]::IsNullOrEmpty($o)) "no-op (comando no-git) no emite nada"; Remove-Item -Recurse -Force $t

$t = New-Repo; $o = Fire $t "git push"
Assert ($o -match "additionalContext") "git push en feature branch dispara"; Remove-Item -Recurse -Force $t

$t = New-Repo; $o = Fire $t "git commit -m slice"
Assert (($o -match "additionalContext") -and ($o -match "review-loop AHORA")) "git commit en feature branch dispara con mensaje imperativo"; Remove-Item -Recurse -Force $t

$t = New-Repo; $o = Fire $t "git commit-graph write"
Assert ([string]::IsNullOrEmpty($o)) "git commit-graph (falso positivo) NO dispara"; Remove-Item -Recurse -Force $t

$t = New-Repo; git -C $t checkout -q master; $o = Fire $t "git push"
Assert ([string]::IsNullOrEmpty($o)) "estar en la base no dispara"; Remove-Item -Recurse -Force $t

$t = New-Repo; git -C $t branch develop | Out-Null; $o = Fire $t "gh pr create --base develop"
Assert (($o -match "additionalContext") -and ($o -match "develop")) "gh pr create --base develop usa develop (no hardcodea main)"; Remove-Item -Recurse -Force $t

$t = New-Repo
Fire $t "git commit -m slice" | Out-Null
$o = Fire $t "git commit -m slice"
Assert ([string]::IsNullOrEmpty($o)) "dedupe: segundo disparo sobre el mismo SHA no emite"
git -C $t commit --allow-empty -q -m slice2
$o2 = Fire $t "git commit -m slice2"
Assert ($o2 -match "additionalContext") "dedupe: un commit nuevo vuelve a disparar"
Remove-Item -Recurse -Force $t

# --- Merge de settings (proyecto con settings.json propio, p. ej. enabledPlugins) ---
$t = Join-Path ([IO.Path]::GetTempPath()) ("rlt-ms-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $t | Out-Null
$sp = Join-Path $t "settings.json"
'{ "enabledPlugins": { "domo-skills@martin-local": true } }' | Set-Content $sp -Encoding UTF8
& pwsh -NoProfile -File $ms -ProjectSettings $sp -CanonicalSettings $canon | Out-Null
$txt = Get-Content $sp -Raw
Assert (($txt -match "enabledPlugins") -and ($txt -match "review-loop-trigger")) "merge preserva config propia y agrega review-loop-trigger"
Assert ($txt -match "alignment-gate") "merge agrega tambien el hook alignment-gate (PreToolUse)"
& pwsh -NoProfile -File $ms -ProjectSettings $sp -CanonicalSettings $canon | Out-Null
$txt2 = Get-Content $sp -Raw
Assert ((([regex]::Matches($txt2, "review-loop-trigger")).Count -eq 1) -and (([regex]::Matches($txt2, "alignment-gate")).Count -eq 1)) "merge es idempotente (no duplica ningun hook)"
Remove-Item -Recurse -Force $t

if ($script:failures -gt 0) { Write-Host "$($script:failures) test(s) FALLARON"; exit 1 } else { Write-Host "TODOS LOS TESTS PASARON"; exit 0 }
