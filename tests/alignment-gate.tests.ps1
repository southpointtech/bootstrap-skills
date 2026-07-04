# tests/alignment-gate.tests.ps1 — runner sin Pester. Correr: pwsh -NoProfile -File tests/alignment-gate.tests.ps1
# Fixtures determinísticos (repos git temporales) para el hook alignment-gate (PreToolUse).
# El hook resuelve el repo desde cwd; cwd y file_path deben ser paths Windows reales (como los pasa Claude Code).
$ErrorActionPreference = "Stop"
$repo  = Split-Path $PSScriptRoot -Parent
$hookP = Join-Path $repo "skills/bootstrap-personal-project/assets/scaffold/.claude/hooks/alignment-gate.ps1"
$hookS = Join-Path $repo "skills/bootstrap-southpoint-project/assets/scaffold/.claude/hooks/alignment-gate.ps1"
$script:failures = 0

function Assert($cond, $msg) {
  if ($cond) { Write-Host "ok:   $msg" } else { Write-Host "FAIL: $msg"; $script:failures++ }
}
function New-Repo {
  $t = Join-Path ([IO.Path]::GetTempPath()) ("ag-test-" + [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $t | Out-Null
  git -C $t init -q -b master; git -C $t config user.email a@b.c; git -C $t config user.name a
  git -C $t commit --allow-empty -q -m base
  return $t
}
# Invoca el hook personal con un evento PreToolUse.
function Fire($repoDir, $tool, $file, $sid) {
  $ti = if ($tool -eq 'MultiEdit') { @{ edits = @(@{ file_path = $file }) } } else { @{ file_path = $file } }
  $evt = @{ session_id = $sid; cwd = $repoDir; tool_name = $tool; tool_input = $ti } | ConvertTo-Json -Compress -Depth 6
  return ($evt | & pwsh -NoProfile -File $hookP)
}

# 1. Código en sesión nueva -> deny + ofrece grill
$t = New-Repo
$o = Fire $t 'Write' (Join-Path $t 'src/app.py') 's1'
Assert (($o -match 'deny') -and ($o -match 'grill')) "Write de código en sesión nueva: deny + ofrece grill"
Remove-Item -Recurse -Force $t

# 2. Archivo .md pasa libre (no emite, no marca)
$t = New-Repo
$o = Fire $t 'Write' (Join-Path $t 'docs/nota.md') 's1'
Assert ([string]::IsNullOrEmpty($o)) "archivo .md no dispara (pasa libre)"
Remove-Item -Recurse -Force $t

# 3. CLAUDE.md pasa libre
$t = New-Repo
$o = Fire $t 'Edit' (Join-Path $t 'CLAUDE.md') 's1'
Assert ([string]::IsNullOrEmpty($o)) "CLAUDE.md no dispara"
Remove-Item -Recurse -Force $t

# 4. .scratch/ pasa libre (clave: no romper la escritura del PRD)
$t = New-Repo
$o = Fire $t 'Write' (Join-Path $t '.scratch/feat/PRD.md') 's1'
Assert ([string]::IsNullOrEmpty($o)) ".scratch/ no dispara"
Remove-Item -Recurse -Force $t

# 5. Dedup: segundo Edit de código en la misma sesión pasa libre
$t = New-Repo
Fire $t 'Write' (Join-Path $t 'src/a.py') 'sDup' | Out-Null
$o = Fire $t 'Write' (Join-Path $t 'src/b.py') 'sDup'
Assert ([string]::IsNullOrEmpty($o)) "dedup: segundo Edit de código en la misma sesión no dispara"
Remove-Item -Recurse -Force $t

# 6. Otra sesión vuelve a disparar
$t = New-Repo
Fire $t 'Write' (Join-Path $t 'src/a.py') 'sA' | Out-Null
$o = Fire $t 'Write' (Join-Path $t 'src/a.py') 'sB'
Assert ($o -match 'deny') "otra sesión vuelve a disparar"
Remove-Item -Recurse -Force $t

# 7. MultiEdit de código dispara (file_path dentro de edits[])
$t = New-Repo
$o = Fire $t 'MultiEdit' (Join-Path $t 'src/c.ts') 's1'
Assert ($o -match 'deny') "MultiEdit de código dispara"
Remove-Item -Recurse -Force $t

# 8. Config (.json) pasa libre
$t = New-Repo
$o = Fire $t 'Write' (Join-Path $t 'tsconfig.json') 's1'
Assert ([string]::IsNullOrEmpty($o)) "archivo .json no dispara"
Remove-Item -Recurse -Force $t

# 9. Espejado: hook personal y southpoint byte-idénticos (DESTAPAR en Task 2)
# Assert ((Get-FileHash $hookP).Hash -eq (Get-FileHash $hookS).Hash) "alignment-gate.ps1 idéntico en ambos scaffolds"

if ($script:failures -gt 0) { Write-Host "$($script:failures) test(s) FALLARON"; exit 1 } else { Write-Host "TODOS LOS TESTS PASARON"; exit 0 }
