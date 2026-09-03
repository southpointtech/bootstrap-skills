# tests/normalized-hash.tests.ps1 — runner sin Pester. Correr: pwsh -NoProfile -File tests/normalized-hash.tests.ps1
#
# Cubre tools/normalized-hash.ps1 — el módulo M1 del PRD de bootstrap-v2: la forma canónica de
# hashear del repo, que los cálculos crudos replicados hoy en gen-manifest, compare-scaffold y
# reseal-manifest —más las dos variantes de NormHash (mirror.tests y review-loop-incremental)—
# todavía NO usan (migrarlos es un slice aparte, issue 03). Existe porque el hash con
# el que se sellan los manifests dependía de cómo el checkout de cada máquina escribió los fines de
# línea, y un manifest sellado en una máquina reportaba drift falso en otra (memoria
# `bug-autocrlf-manifests-hashes-mixtos`).
#
# CONTRATO: sha256 hex minúscula de los BYTES del contenido, con las secuencias de fin de línea
# (CRLF y CR) unificadas a LF. La normalización opera sobre bytes y NO decodifica a texto: decodificar
# haría desaparecer un BOM y colapsaría dos bytes inválidos distintos en `U+FFFD`, y ambos son cambios
# reales que quedarían ocultos — la misma pérdida silenciosa que ADR-0007 midió y rechazó para la
# comparación de copy-scaffold. Este módulo sella contenido para detectar drift; ese drift incluye el
# BOM y la corrupción, así que NO los descarta.
#
# Tres trampas que este archivo evita a propósito:
#
# 1. **Asertar solo "igual" y "distinto" no fija el algoritmo.** Una función que devolviera sha1, o
#    que hasheara la longitud, pasaría todos los pares igual/distinto. Por eso hay literales hex
#    CONGELADOS, calculados fuera de la función bajo prueba (`hashlib.sha256` de Python sobre los
#    mismos bytes), contra los que se compara directo.
# 2. **Un normalizador que BORRA los saltos de línea pasaría toda la batería de CRLF/LF.** Por eso se
#    verifica también que "ab" y "a<LF>b" sigan dando hashes distintos: unifica el salto, no lo elimina.
# 3. **Un normalizador que decodifica a texto colapsa el BOM y los bytes inválidos.** Por eso se
#    verifica que un BOM cambie el hash y que dos secuencias de bytes inválidos distintas no colapsen.
$ErrorActionPreference = "Stop"
$repo = Split-Path $PSScriptRoot -Parent
$tool = Join-Path $repo "tools/normalized-hash.ps1"
$script:failures = 0
$script:checks   = 0

function Assert($cond, $msg) {
  $script:checks++
  if ($cond) { Write-Host "ok:   $msg" } else { Write-Host "FAIL: $msg"; $script:failures++ }
}

# Cantidad EXACTA de aserciones. Se actualiza a mano al agregar o quitar checks. Sin este número un
# mutante que BORRA asserts sale en verde: 0 fails de 0 checks también es "0 fail". No es un mínimo:
# con holgura, un mutante puede borrar tantos checks como holgura haya y seguir pasando.
$ExpectedChecks = 34

# La herramienta tiene que existir: si no, el dot-source explota con su propio error y un assert de
# "no hubo fails" pasaría en verde sin haber ejercitado nada.
if (-not (Test-Path -LiteralPath $tool)) {
  Write-Host "FAIL: no existe la herramienta en $tool"; exit 1
}
. $tool

# Directorio propio para los casos que necesitan disco. Se limpia SOLO el directorio propio, sin
# barrer `$env:TEMP` por prefijo: barrer por glob es exactamente lo que hacía que dos suites
# concurrentes se borraran los workspaces entre sí.
$script:tmp = Join-Path ([IO.Path]::GetTempPath()) ("nh-run-$PID-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $script:tmp -Force | Out-Null

# Escribe bytes crudos: ni Set-Content ni Out-File, que reescriben los fines de línea y el encoding
# según la plataforma y arruinarían justamente lo que estos casos miden.
function Write-Raw($rel, [byte[]]$bytes) {
  $p = Join-Path $script:tmp $rel
  [IO.File]::WriteAllBytes($p, $bytes)
  return $p
}
# Sin parámetro de BOM: `GetBytes` nunca emite el preámbulo aunque el flag del constructor sea
# $true, así que un "BOM por flag" sería un no-op silencioso. El único caso con BOM lo antepone a
# mano (más abajo), que es la forma honesta de meterlo.
function Utf8Bytes($text) {
  [Text.UTF8Encoding]::new($false).GetBytes($text)
}

try {

  # --- Literales congelados -------------------------------------------------------------------
  # sha256 hex de los bytes del contenido YA normalizado a LF (ninguno de estos lleva BOM).
  $H_a_nl_b  = "7e18f737311b2dc3b2f269dd78396b0351f14fb66efa879f768cb23181883c78"  # "a<LF>b"
  $H_ab      = "fb8e20fc2e4c3f248c60c39bd652f3c1347298bb977b8b4d5903b85055620603"  # "ab"
  $H_cuerpo  = "c743db13ab5f6d009ac9f54e5cef8274aa9f5cb84c27453dd4c321235bce0d80"  # "cuerpo<LF>"
  $H_vacio   = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"  # ""
  $H_cafe    = "7b49b9e063bd91a4f9252b413261f5557b9c570aa61516989499f64a62dbcdd6"  # "café<LF>" (UTF-8)

  # --- A. La normalizacion unifica los tres estilos de fin de linea ---------------------------
  $lf   = "a`nb"
  $crlf = "a`r`nb"
  $cr   = "a`rb"
  Assert ((Get-NormalizedHash -Content $crlf) -eq (Get-NormalizedHash -Content $lf)) `
    "CRLF y LF del mismo contenido dan el mismo hash"
  Assert ((Get-NormalizedHash -Content $cr) -eq (Get-NormalizedHash -Content $lf)) `
    "CR solo y LF del mismo contenido dan el mismo hash"
  Assert ((Get-NormalizedHash -Content "a`r`nb`nc`rd") -eq (Get-NormalizedHash -Content "a`nb`nc`nd")) `
    "una mezcla de los tres estilos colapsa al mismo hash que todo LF"
  $fmCrlf = "---`r`nname: x`r`n---`r`ncuerpo`r`n"
  $fmLf   = "---`nname: x`n---`ncuerpo`n"
  Assert ((Get-NormalizedHash -Content $fmCrlf -Scope Body) -eq (Get-NormalizedHash -Content $fmLf -Scope Body)) `
    "la normalizacion tambien aplica al hash de cuerpo, no solo al de archivo completo"

  # --- B. La normalizacion no colapsa lo que tiene que distinguir ------------------------------
  Assert ((Get-NormalizedHash -Content "a`nb") -ne (Get-NormalizedHash -Content "a`nc")) `
    "contenido distinto da hashes distintos"
  Assert ((Get-NormalizedHash -Content "ab") -ne (Get-NormalizedHash -Content "a`nb")) `
    "unifica el salto de linea pero no lo elimina: 'ab' y 'a<LF>b' siguen distintos"
  Assert ((Get-NormalizedHash -Content "a`n") -ne (Get-NormalizedHash -Content "a")) `
    "el salto final NO se recorta: 'a<LF>' y 'a' siguen distintos"
  Assert ((Get-NormalizedHash -Content "a`nb ") -ne (Get-NormalizedHash -Content "a`nb")) `
    "los espacios al final NO se recortan"
  Assert ((Get-NormalizedHash -Content "") -ne (Get-NormalizedHash -Content "`n")) `
    "el contenido vacio y un solo salto de linea no colapsan"

  # --- C. El algoritmo queda fijado contra literales, no contra si mismo ----------------------
  Assert ((Get-NormalizedHash -Content "a`nb") -eq $H_a_nl_b) `
    "el hash de archivo es sha256 de los bytes normalizados (literal congelado)"
  Assert ((Get-NormalizedHash -Content "a`r`nb") -eq $H_a_nl_b) `
    "el CRLF hashea al literal de la version LF, no a uno propio"
  Assert ((Get-NormalizedHash -Content "ab") -eq $H_ab) `
    "un segundo literal congelado, para que el primero no se pueda satisfacer por constante"
  Assert ((Get-NormalizedHash -Content $fmLf -Scope Body) -eq $H_cuerpo) `
    "el hash de cuerpo es el del cuerpo solo, sin el frontmatter (literal congelado)"
  $formato = Get-NormalizedHash -Content "a`nb"
  Assert ($formato -cmatch '^[0-9a-f]{64}$') `
    "el hash sale en hex minuscula de 64 caracteres"

  # --- D. Frontmatter contra cuerpo ------------------------------------------------------------
  $docA = "---`nname: alpha`ndescription: una`n---`ncuerpo comun`n"
  $docB = "---`nname: beta`ndescription: otra distinta y mas larga`n---`ncuerpo comun`n"
  Assert ((Get-NormalizedHash -Content $docA -Scope Body) -eq (Get-NormalizedHash -Content $docB -Scope Body)) `
    "cambiar solo el frontmatter NO cambia el hash de cuerpo"
  Assert ((Get-NormalizedHash -Content $docA) -ne (Get-NormalizedHash -Content $docB)) `
    "cambiar solo el frontmatter SI cambia el hash de archivo completo"
  $docC = "---`nname: alpha`ndescription: una`n---`ncuerpo cambiado`n"
  Assert ((Get-NormalizedHash -Content $docA -Scope Body) -ne (Get-NormalizedHash -Content $docC -Scope Body)) `
    "cambiar el cuerpo cambia el hash de cuerpo"
  Assert ((Get-NormalizedHash -Content $docA) -ne (Get-NormalizedHash -Content $docC)) `
    "cambiar el cuerpo tambien cambia el hash de archivo completo"

  # Sin frontmatter, el cuerpo es todo el contenido: los dos alcances coinciden. Es la unica forma
  # de verificar que la extraccion no se come nada cuando no hay delimitadores.
  $sinFm = "titulo`n`ntexto`n"
  Assert ((Get-NormalizedHash -Content $sinFm -Scope Body) -eq (Get-NormalizedHash -Content $sinFm)) `
    "sin frontmatter, el hash de cuerpo es igual al de archivo completo"

  # Una regla horizontal markdown en el medio no abre ni cierra frontmatter: el frontmatter solo
  # existe si el documento ARRANCA con el delimitador. `IndexOf` toma la primera aparicion, asi que
  # una implementacion que busque `---` sin anclar al inicio se come medio documento.
  $regla = "titulo`n`n---`n`ntexto`n"
  Assert ((Get-NormalizedHash -Content $regla -Scope Body) -eq (Get-NormalizedHash -Content $regla)) `
    "un '---' en el medio sin frontmatter arriba no se toma como delimitador"

  # Delimitador de apertura sin cierre: no hay frontmatter. Declarado, no accidental.
  $abierto = "---`nname: x`nsin cierre`n"
  Assert ((Get-NormalizedHash -Content $abierto -Scope Body) -eq (Get-NormalizedHash -Content $abierto)) `
    "un frontmatter abierto y nunca cerrado no se recorta: el cuerpo es todo el contenido"

  # El cierre tiene que ser una linea EXACTAMENTE '---'. Un '----' no cierra.
  $malCierre = "---`nname: x`n----`ncuerpo`n"
  Assert ((Get-NormalizedHash -Content $malCierre -Scope Body) -eq (Get-NormalizedHash -Content $malCierre)) `
    "una linea '----' no cierra el frontmatter"

  $soloFm = "---`nname: x`n---`n"
  Assert ((Get-NormalizedHash -Content $soloFm -Scope Body) -eq $H_vacio) `
    "un documento que es solo frontmatter tiene cuerpo vacio (literal congelado)"

  # Cierre del frontmatter en la ULTIMA linea, sin salto final: el cuerpo es vacio. Esta es la rama
  # `elseif EndsWith` del modulo; sin este caso ningun test la ejercita y un mutante que la rompa
  # sobrevive en verde (medido: el foco de mutacion lo confirmo). Ojo, este no termina en `<LF>`.
  $cierreUltimaLinea = "---`nname: x`n---"
  Assert ((Get-NormalizedHash -Content $cierreUltimaLinea -Scope Body) -eq $H_vacio) `
    "frontmatter que cierra en la ultima linea sin salto final tiene cuerpo vacio (literal congelado)"

  # El cuerpo NO se recorta en los extremos. Es una diferencia deliberada con la metrica de
  # similitud de recover-skill-bases.py, que si recorta: aca sellamos contenido, no lo comparamos.
  $conBlanco = "---`nname: x`n---`ncuerpo`n`n"
  Assert ((Get-NormalizedHash -Content $conBlanco -Scope Body) -ne (Get-NormalizedHash -Content $fmLf -Scope Body)) `
    "el cuerpo no se recorta: una linea en blanco de mas al final cambia el hash"

  # --- E. La interfaz de archivo ---------------------------------------------------------------
  $pLf   = Write-Raw "lf.md"   (Utf8Bytes "a`nb")
  $pCrlf = Write-Raw "crlf.md" (Utf8Bytes "a`r`nb")
  Assert ((Get-NormalizedHash -Path $pCrlf) -eq (Get-NormalizedHash -Path $pLf)) `
    "dos archivos con el mismo contenido y distinto fin de linea dan el mismo hash"
  Assert ((Get-NormalizedHash -Path $pLf) -eq (Get-NormalizedHash -Content "a`nb")) `
    "un archivo sin BOM y su contenido dan el mismo hash (la ruta no entra al hash)"

  # El BOM es un cambio real, no ruido (ADR-0007): decodificar a texto lo haria desaparecer, y este
  # modulo existe para NO perder cambios en silencio. Por eso un archivo con BOM hashea distinto que
  # el mismo contenido sin BOM, por las dos entradas.
  # Los 3 bytes del BOM (EF BB BF) se anteponen a mano: `UTF8Encoding::GetBytes` NUNCA emite el
  # preambulo (el flag del constructor solo controla GetPreamble/los writers), asi que "generar con
  # BOM" via GetBytes daria los mismos bytes que sin BOM y el caso no probaria nada.
  $pBom = Write-Raw "bom.md" ([byte[]](0xEF, 0xBB, 0xBF) + (Utf8Bytes "a`nb"))
  Assert ((Get-NormalizedHash -Path $pBom) -ne (Get-NormalizedHash -Path $pLf)) `
    "un archivo con BOM UTF-8 hashea distinto que el mismo contenido sin BOM"
  $conBom = [string][char]0xFEFF + "a`nb"
  Assert ((Get-NormalizedHash -Content $conBom) -ne (Get-NormalizedHash -Content "a`nb")) `
    "un BOM al inicio del contenido tambien cambia el hash: no se descarta"

  # Dos secuencias de bytes INVALIDOS UTF-8 distintas no deben colapsar. `[IO.File]::ReadAllText`
  # las decodificaria ambas a U+FFFD y darian el mismo hash — corrupcion distinta, sello identico.
  # Operar sobre bytes las mantiene separadas. Es el segundo filo del mismo hallazgo que el BOM.
  $pInv1 = Write-Raw "inv1.bin" ([byte[]](0xFF, 0xFE))
  $pInv2 = Write-Raw "inv2.bin" ([byte[]](0xFE, 0xFF))
  Assert ((Get-NormalizedHash -Path $pInv1) -ne (Get-NormalizedHash -Path $pInv2)) `
    "dos secuencias de bytes invalidos UTF-8 distintas no colapsan en el mismo hash"

  # Encoding fijado: el acento se hashea como sus bytes UTF-8, no como la codepage de la consola
  # (cp1252 en esta maquina), para que el sello sea portable.
  $cafe  = "caf" + [char]0xE9 + "`n"
  $pCafe = Write-Raw "cafe.md" (Utf8Bytes $cafe)
  Assert ((Get-NormalizedHash -Path $pCafe) -eq $H_cafe) `
    "los acentos se hashean como sus bytes UTF-8, no como la codepage de la consola (literal congelado)"

  # `-Path` + `-Scope Body` combinados: es el caso de uso REAL del modulo (hashear un archivo de
  # skill por su cuerpo, ignorando la `description`), y ningun otro caso lo ejercita — los `-Scope
  # Body` de arriba usan `-Content`, y los `-Path` de aca usan el `File` por defecto. Se escribe un
  # archivo con frontmatter y se verifica que por disco el cuerpo se recorta igual (anclado a
  # literal, no auto-comparacion).
  $pFm = Write-Raw "confrontmatter.md" (Utf8Bytes $fmLf)
  Assert ((Get-NormalizedHash -Path $pFm -Scope Body) -eq $H_cuerpo) `
    "-Path con -Scope Body recorta el frontmatter del archivo en disco (literal congelado)"
  Assert ((Get-NormalizedHash -Path $pFm -Scope Body) -ne (Get-NormalizedHash -Path $pFm)) `
    "-Path: el hash de cuerpo difiere del de archivo completo cuando hay frontmatter"

  # Un archivo que no existe tiene que ser un error, no el hash del vacio: si devolviera el hash de
  # "", sellar un manifest con una ruta mal escrita saldria en verde.
  $tiro = $false
  try { Get-NormalizedHash -Path (Join-Path $script:tmp "no-existe.md") | Out-Null }
  catch { $tiro = $true }
  Assert $tiro "un archivo inexistente tira error en vez de devolver el hash del contenido vacio"

}
finally {
  Remove-Item -LiteralPath $script:tmp -Recurse -Force -ErrorAction SilentlyContinue
}

# El conteo se captura ANTES de llamar al Assert que lo verifica: PowerShell evalua los argumentos
# antes de entrar a la funcion, asi que `$script:checks` leido adentro de la llamada todavia no
# incluye a este guard. La captura en un statement previo — no `$ExpectedChecks + 1` — es lo que
# mantiene honesto el numero del mensaje.
$corridas = $script:checks
Assert ($corridas -eq $ExpectedChecks) `
  "se corrieron las $ExpectedChecks aserciones declaradas (contadas: $corridas)"

if ($script:failures -gt 0) { Write-Host "`n$($script:failures) FAIL"; exit 1 }
Write-Host "`nTodo verde ($corridas aserciones + el guard de conteo)"
