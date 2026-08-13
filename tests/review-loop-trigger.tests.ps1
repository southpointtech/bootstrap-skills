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
# Commit que DECLARA el cierre de slice con el trailer. Sin el trailer el hook no dispara.
function Close-Slice($repo, $subject) {
  git -C $repo commit --allow-empty -q -m "$subject`n`nSlice-Close: $subject"
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
Assert ([string]::IsNullOrEmpty($o)) "git commit SIN trailer Slice-Close no dispara"; Remove-Item -Recurse -Force $t

$t = New-Repo; $o = Fire $t "git commit-graph write"
Assert ([string]::IsNullOrEmpty($o)) "git commit-graph (falso positivo) NO dispara"; Remove-Item -Recurse -Force $t

$t = New-Repo; git -C $t checkout -q master; $o = Fire $t "git push"
Assert ([string]::IsNullOrEmpty($o)) "estar en la base no dispara"; Remove-Item -Recurse -Force $t

$t = New-Repo; git -C $t branch develop | Out-Null; $o = Fire $t "gh pr create --base develop"
Assert (($o -match "additionalContext") -and ($o -match "develop")) "gh pr create --base develop usa develop (no hardcodea main)"; Remove-Item -Recurse -Force $t

$t = New-Repo; Close-Slice $t "slice"; $o = Fire $t "git commit -m slice"
Assert (($o -match "additionalContext") -and ($o -match "review-loop NOW")) "git commit CON trailer Slice-Close dispara con mensaje imperativo"
Assert (($o -match "review-marker\.ps1") -and ($o -match "-Action range")) "el mensaje inyectado manda el ciclo al delta sin revisar, no al rango completo de la rama"
Remove-Item -Recurse -Force $t

# El evento dice `git commit` y trae el cwd de la sesion, pero el comando corrio en OTRO repo:
# el HEAD de ESTE repo quedo viejo. Reproducido en vivo el 2026-08-11 con un repo de mktemp -d.
$t = New-Repo
$env:GIT_COMMITTER_DATE = "2020-01-01T00:00:00 +0000"
Close-Slice $t "slice viejo"
Remove-Item Env:GIT_COMMITTER_DATE
$o = Fire $t "git commit -m commit-en-otro-repo"
Assert ([string]::IsNullOrEmpty($o)) "un commit ejecutado en otro repo no dispara aca (el HEAD de este repo no es reciente)"; Remove-Item -Recurse -Force $t

$t = New-Repo
Set-Content (Join-Path $t "big.txt") ((1..500 | ForEach-Object { "linea $_" }) -join "`n") -Encoding UTF8
git -C $t add -A; git -C $t commit -q -m "slice gigante sin declarar"
$o = Fire $t "git commit -m slice"
Assert ($o -match "additionalContext") "red de seguridad: delta sin revisar por encima del techo dispara aunque no haya trailer"; Remove-Item -Recurse -Force $t

# El techo se mide sobre el delta SIN REVISAR (marcador), no sobre el rango completo de la rama:
# una rama grande ya revisada + un commit chico sin trailer no debe disparar.
$t = New-Repo
New-Item -ItemType Directory -Path (Join-Path $t ".claude/scripts") -Force | Out-Null
Copy-Item (Join-Path $repo "skills/bootstrap-personal-project/assets/scaffold/.claude/scripts/review-marker.ps1") (Join-Path $t ".claude/scripts/review-marker.ps1")
Set-Content (Join-Path $t "big.txt") ((1..500 | ForEach-Object { "linea $_" }) -join "`n") -Encoding UTF8
git -C $t add -A; git -C $t commit -q -m "slice grande ya revisado"
& pwsh -NoProfile -File (Join-Path $t ".claude/scripts/review-marker.ps1") -Action advance -RepoDir $t | Out-Null
Set-Content (Join-Path $t "chico.txt") "una linea" -Encoding UTF8
git -C $t add -A; git -C $t commit -q -m "retoque chico sin declarar cierre"
$o = Fire $t "git commit -m retoque"
Assert ([string]::IsNullOrEmpty($o)) "el techo mira el delta sin revisar (marcador), no el rango completo de la rama"; Remove-Item -Recurse -Force $t

$t = New-Repo
Close-Slice $t "slice"
Fire $t "git commit -m slice" | Out-Null
$o = Fire $t "git commit -m slice"
Assert ([string]::IsNullOrEmpty($o)) "dedupe: segundo disparo sobre el mismo SHA no emite"
Close-Slice $t "slice2"
$o2 = Fire $t "git commit -m slice2"
Assert ($o2 -match "additionalContext") "dedupe: un commit nuevo vuelve a disparar"
Remove-Item -Recurse -Force $t

# El hook reescribe el MISMO review-loop-state.json que usa el marcador. Bajo Windows PowerShell 5.1
# Get-Content/Set-Content lo leen y lo escriben con la code page ANSI, y la huella de untracked
# acentuada del marcador vuelve como mojibake: esa rama no puede volver a cerrar nunca.
$t = New-Repo; Close-Slice $t "slice"
$sp = Join-Path $t ".git/review-loop-state.json"
[IO.File]::WriteAllText($sp, '{"marker:feat/x":"cafe","untracked:feat/x":["ñandú.txt|abc123"]}', (New-Object Text.UTF8Encoding($false)))
$evt = @{ tool_input = @{ command = "git commit -m slice" }; cwd = $t } | ConvertTo-Json -Compress
$evt | & powershell.exe -NoProfile -File $hook | Out-Null
$after = [IO.File]::ReadAllText($sp)
Assert ($after -match ([regex]::Escape("ñandú.txt"))) "el hook no corrompe la huella acentuada del marcador al reescribir el estado (PowerShell 5.1)"
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
