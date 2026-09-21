# tests/lib/consola-propia.ps1 — correr un script en SU PROPIA consola, sin tocar la de la suite.
#
# Por qué existe (issue 15): `[Console]::OutputEncoding` NO es estado del proceso, es de la CONSOLA.
# Un proceso que lo fija le cambia el encoding con el que ARRANCAN los procesos que se lancen después
# en esa misma consola. MEDIDO el 2026-09-20, con la consola en 65001: después de un hijo que fija
# 850, el proceso siguiente arranca en 850 — y `chcp.com` sigue informando 65001, así que el
# diagnóstico "corré chcp" no lo ve. Bajo `tests/run-all.ps1`, que corre 4 suites en paralelo en la
# MISMA consola, eso es un rojo espurio cruzado: la suite que fija 850 para emular una máquina que no
# está en UTF-8 se lo deja puesto a cualquier suite que arranque en esa ventana.
#
# La salida NO se decodifica con la code page del caso: el hijo escribe sus bytes a un archivo por
# redirección del sistema operativo y acá se leen como UTF-8. Lo que el caso ejercita es el ambiente
# que ve el hijo, no cómo lo lee quien lo llama.
#
# Uso (después de dot-sourcear lib\temp-workspace.ps1, de donde sale New-TestTempPath):
#
#     . (Join-Path $PSScriptRoot "lib\consola-propia.ps1")
#     $r = Invoke-EnConsolaPropia -RunRoot $script:runRoot -Script $recol -Argumentos @('-RepoDir', $t) -ConSonda
#     $r.out       # stdout del script, decodificado como UTF-8
#     $r.err       # stderr, idem
#     $r.exit      # exit code del script
#     $r.cpSonda   # con qué encoding arranca un proceso lanzado DESPUÉS del script ($null sin -ConSonda)

function Invoke-EnConsolaPropia {
  param(
    [Parameter(Mandatory)][string]$RunRoot,
    [Parameter(Mandatory)][string]$Script,
    [string[]]$Argumentos = @(),
    # El ambiente del caso: 850 es el de una máquina que no está en UTF-8, lo que ve una Scheduled Task.
    [int]$Cp = 850,
    [switch]$ConSonda
  )
  $boot = Join-Path $PSScriptRoot "consola-propia-boot.ps1"
  if (-not (Test-Path -LiteralPath $boot -PathType Leaf)) { throw "falta el boot de la consola propia: $boot" }
  $plan     = New-TestTempPath $RunRoot "cp-plan"  ".json"
  $rawOut   = New-TestTempPath $RunRoot "cp-out"   ".txt"
  $rawErr   = New-TestTempPath $RunRoot "cp-err"   ".txt"
  $sondaOut = New-TestTempPath $RunRoot "cp-sonda" ".txt"
  $meta     = New-TestTempPath $RunRoot "cp-meta"  ".json"
  $utf8 = [Text.UTF8Encoding]::new($false)
  $p = [ordered]@{
    cp         = $Cp
    script     = $Script
    argumentos = @($Argumentos)
    rawOut     = $rawOut
    rawErr     = $rawErr
    sondaOut   = $sondaOut
    meta       = $meta
    conSonda   = [bool]$ConSonda
  }
  [IO.File]::WriteAllText($plan, ($p | ConvertTo-Json -Depth 5), $utf8)

  # SIN -NoNewWindow: eso es lo que le da al boot una consola propia. `-WindowStyle Hidden` la deja
  # invisible, pero existe, y con ella muere el `[Console]::OutputEncoding` que el boot le fije.
  # Las rutas van entrecomilladas a mano: `Start-Process -ArgumentList` pega los elementos con un
  # espacio y NO los entrecomilla, así que una ruta con espacio (este repo tiene uno en el nombre)
  # llega partida en dos argumentos y pwsh sale 64 sin correr nada.
  $bootErr = New-TestTempPath $RunRoot "cp-boot-err" ".txt"
  $b = Start-Process pwsh -ArgumentList '-NoProfile', '-File', "`"$boot`"", '-Plan', "`"$plan`"" `
    -WindowStyle Hidden -Wait -PassThru -RedirectStandardError $bootErr
  if ($b.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $meta -PathType Leaf)) {
    $detalle = @((Read-TextoUtf8 $bootErr), (Read-TextoUtf8 $rawErr)) -ne "" -join " | "
    throw "la consola propia falló (exit $($b.ExitCode)): $detalle"
  }
  $m = [IO.File]::ReadAllText($meta, $utf8) | ConvertFrom-Json
  @{
    out     = (Read-TextoUtf8 $rawOut)
    err     = (Read-TextoUtf8 $rawErr)
    exit    = [int]$m.exit
    cpSonda = $(if ($null -ne $m.cpSonda -and "$($m.cpSonda)") { [int]$m.cpSonda } else { $null })
  }
}

# Los bytes del archivo leídos como UTF-8, sin el salto final: lo que escribió el hijo, decodificado
# acá y no por la code page de nadie.
function Read-TextoUtf8([string]$ruta) {
  if (-not (Test-Path -LiteralPath $ruta -PathType Leaf)) { return "" }
  ([IO.File]::ReadAllText($ruta, [Text.UTF8Encoding]::new($false))).TrimEnd("`r", "`n")
}
