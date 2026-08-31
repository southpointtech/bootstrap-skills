# tests/gen-mcp-json.tests.ps1 — runner sin Pester. Correr: pwsh -NoProfile -File tests/gen-mcp-json.tests.ps1
$ErrorActionPreference = "Stop"
$repo       = Split-Path $PSScriptRoot -Parent
$personal   = Join-Path $repo "skills/bootstrap-personal-project/scripts/gen-mcp-json.ps1"
$southpoint = Join-Path $repo "skills/bootstrap-southpoint-project/scripts/gen-mcp-json.ps1"
$shareable  = Join-Path $repo "skills/bootstrap-ai-project/scripts/gen-mcp-json.ps1"
$script:failures = 0

function Assert($cond, $msg) {
  if ($cond) { Write-Host "ok:   $msg" } else { Write-Host "FAIL: $msg"; $script:failures++ }
}
# Todo temporal que se cree queda registrado acá, para que la limpieza no dependa de que
# alguien se acuerde de listarlo abajo ni de que la corrida llegue al final.
$script:tmps = [System.Collections.Generic.List[string]]::new()
function NewTmp {
  $d = Join-Path ([IO.Path]::GetTempPath()) ("mcp-test-" + [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $d | Out-Null
  $script:tmps.Add($d) | Out-Null
  $d
}
function Cleanup-Tmps {
  foreach ($d in $script:tmps) {
    if ($d -and (Test-Path $d)) { Remove-Item -Recurse -Force $d -ErrorAction SilentlyContinue }
  }
}
# `$ErrorActionPreference = "Stop"` (arriba) convierte cualquier error en terminante: sin este
# trap, una excepción a mitad del archivo abortaba el script y se filtraban TODOS los temporales
# vivos. Ese es el mecanismo que dejó 606 huérfanos en TEMP, no el olvido de listar uno.
trap { Cleanup-Tmps; break }
# Corre el script como subproceso; devuelve @{ exit; out } (out = stdout crudo)
function RunScript($scriptPath, [string[]]$ServerArgs, $ProjectDir, [switch]$Force) {
  $a = @("-NoProfile","-File",$scriptPath,"-ProjectDir",$ProjectDir)
  if ($ServerArgs.Count) { $a += @("-Servers"); $a += ($ServerArgs -join ",") }
  if ($Force) { $a += "-Force" }
  $out = & pwsh @a 2>$null
  @{ exit = $LASTEXITCODE; out = ($out | Out-String) }
}

# --- PERSONAL: happy path ---
$t = NewTmp
$r = RunScript $personal @("firebase","zoho-personal") $t
Assert ($r.exit -eq 0) "personal happy: exit 0"
$mcpPath = Join-Path $t ".mcp.json"
Assert (Test-Path $mcpPath) "personal happy: .mcp.json existe"
$doc = Get-Content $mcpPath -Raw | ConvertFrom-Json
Assert ($null -ne $doc.mcpServers.firebase) "personal happy: tiene firebase"
Assert ($null -ne $doc.mcpServers.'zoho-personal') "personal happy: tiene zoho-personal"
Assert ($null -eq $doc.mcpServers.github) "personal happy: NO tiene github"
Assert ($doc.mcpServers.'zoho-personal'.url -eq '${ZOHO_PERSONAL_MCP_URL}') "personal happy: url literal con env var"
$summary = $r.out | ConvertFrom-Json
Assert ($summary.written -eq $true) "personal happy: summary.written=true"
Assert ($summary.requiredEnvVars -contains "ZOHO_PERSONAL_MCP_URL") "personal happy: reporta ZOHO_PERSONAL_MCP_URL"

# --- PERSONAL: ninguna seleccion ---
$t2 = NewTmp
$r2 = RunScript $personal @() $t2
Assert ($r2.exit -eq 0) "personal none: exit 0"
Assert (-not (Test-Path (Join-Path $t2 ".mcp.json"))) "personal none: no crea archivo"
$s2 = $r2.out | ConvertFrom-Json
Assert ($s2.written -eq $false) "personal none: summary.written=false"

# --- PERSONAL: clave invalida ---
$t3 = NewTmp
$r3 = RunScript $personal @("firebase","no-existe") $t3
Assert ($r3.exit -ne 0) "personal invalida: exit != 0 (error)"
Assert (-not (Test-Path (Join-Path $t3 ".mcp.json"))) "personal invalida: no escribe archivo"

# --- PERSONAL: no pisa sin -Force ---
$t4 = NewTmp
RunScript $personal @("firebase") $t4 | Out-Null
Set-Content (Join-Path $t4 ".mcp.json") -Value '{"mcpServers":{"SENTINEL":{}}}' -Encoding UTF8
$r4 = RunScript $personal @("zoho-personal") $t4
Assert ($r4.exit -ne 0) "personal no-force: exit != 0 (error)"
$keep = Get-Content (Join-Path $t4 ".mcp.json") -Raw | ConvertFrom-Json
Assert ($null -ne $keep.mcpServers.SENTINEL) "personal no-force: no piso el archivo existente"

# --- PERSONAL: -Force sobrescribe ---
$r5 = RunScript $personal @("zoho-personal") $t4 -Force
Assert ($r5.exit -eq 0) "personal force: exit 0"
$ovr = Get-Content (Join-Path $t4 ".mcp.json") -Raw | ConvertFrom-Json
Assert ($null -eq $ovr.mcpServers.SENTINEL) "personal force: reemplazo el contenido"
Assert ($null -ne $ovr.mcpServers.'zoho-personal') "personal force: nuevo server presente"

# --- SOUTHPOINT: domo + zoho-projects ---
$ts = NewTmp
$rs = RunScript $southpoint @("domo","zoho-projects") $ts
Assert ($rs.exit -eq 0) "southpoint happy: exit 0"
$sd = Get-Content (Join-Path $ts ".mcp.json") -Raw | ConvertFrom-Json
Assert ($null -ne $sd.mcpServers.domo) "southpoint happy: tiene domo"
Assert ($sd.mcpServers.domo.env.DOMO_DEVELOPER_TOKEN -eq '${DOMO_SOUTHPOINT_TOKEN}') "southpoint happy: token domo por env var"
Assert ($sd.mcpServers.domo.env.PYTHONPATH -eq '${DOMO_MCP_HOME}') "southpoint happy: PYTHONPATH domo apunta a DOMO_MCP_HOME (clone)"
Assert ($sd.mcpServers.'zoho-projects'.url -eq '${ZOHO_SOUTHPOINT_MCP_URL}') "southpoint happy: url zoho southpoint"
$ss = $rs.out | ConvertFrom-Json
Assert ($ss.requiredEnvVars -contains "DOMO_SOUTHPOINT_TOKEN") "southpoint happy: reporta DOMO_SOUTHPOINT_TOKEN"
Assert ($ss.requiredEnvVars -contains "DOMO_MCP_HOME") "southpoint happy: reporta DOMO_MCP_HOME"

# --- SOUTHPOINT: zoho-personal NO existe en este catalogo ---
$ts2 = NewTmp
$rs2 = RunScript $southpoint @("zoho-personal") $ts2
Assert ($rs2.exit -ne 0) "southpoint: zoho-personal invalida en area southpoint"

# --- SHAREABLE: happy path firebase+github ---
$tsh = NewTmp
$rsh = RunScript $shareable @("firebase","github") $tsh
Assert ($rsh.exit -eq 0) "shareable happy: exit 0"
$shd = Get-Content (Join-Path $tsh ".mcp.json") -Raw | ConvertFrom-Json
Assert ($null -ne $shd.mcpServers.firebase -and $null -ne $shd.mcpServers.github) "shareable happy: firebase y github presentes"
Remove-Item -Recurse -Force $tsh

# --- SHAREABLE: zoho-personal NO existe en este catalogo ---
$tsh2 = NewTmp
$rsh2 = RunScript $shareable @("zoho-personal") $tsh2
Assert ($rsh2.exit -ne 0) "shareable: zoho-personal invalido en el catalogo compartible"
Remove-Item -Recurse -Force $tsh2

# --- FIREBASE: en los 3 catalogos, parametrizado por env var y sin credencial en el archivo ---
# La credencial de Firebase NUNCA entra al .mcp.json: firebase-tools usa las credenciales de
# 'firebase login' o las Application Default Credentials del ambiente. Lo unico parametrizado es
# el directorio que contiene firebase.json, por si no esta en la raiz del proyecto (monorepo).
# Se usa la forma con default (${VAR:-.}) y no ${VAR} a secas: con la variable sin definir,
# Claude Code deja el texto ${VAR} literal en la config, y un --dir literal no existiria.
foreach ($case in @(
  @{ name = "personal";   script = $personal   },
  @{ name = "southpoint"; script = $southpoint },
  @{ name = "shareable";  script = $shareable  }
)) {
  $tfb = NewTmp
  $rfb = RunScript $case.script @("firebase") $tfb
  Assert ($rfb.exit -eq 0) "$($case.name) firebase: exit 0"
  $fdoc = Get-Content (Join-Path $tfb ".mcp.json") -Raw | ConvertFrom-Json
  $fb   = $fdoc.mcpServers.firebase
  Assert ($null -ne $fb) "$($case.name) firebase: presente en el catalogo"
  $fbArgs = @($fb.args)
  Assert ($fbArgs -contains "--dir") "$($case.name) firebase: pasa --dir"
  $dirIdx = [array]::IndexOf($fbArgs, "--dir")
  Assert ($dirIdx -ge 0 -and $dirIdx + 1 -lt $fbArgs.Count -and $fbArgs[$dirIdx + 1] -eq '${FIREBASE_PROJECT_DIR:-.}') `
    "$($case.name) firebase: el valor de --dir es la env var expandida con default"
  Assert ($null -eq $fb.env) "$($case.name) firebase: sin bloque env (la credencial no entra al archivo)"
  Remove-Item -Recurse -Force $tfb
}

# --- FIREBASE_PROJECT_DIR es por proyecto, no una perilla global de la maquina ---
# El .mcp.json sale con el MISMO literal '${FIREBASE_PROJECT_DIR:-.}' en todos los proyectos, asi que
# una user variable de Windows apuntaria el MCP de todos ellos al mismo directorio. (Que firebase-tools
# ademas no lo detecte es plausible pero NO esta verificado contra su fuente desde este repo, asi que
# no se afirma: alcanza con que el literal sea compartido para que la variable no deba ser global.)
foreach ($case in @(
  @{ name = "personal";   script = $personal   },
  @{ name = "southpoint"; script = $southpoint },
  @{ name = "shareable";  script = $shareable  }
)) {
  $tsc = NewTmp
  $rsc = RunScript $case.script @("firebase") $tsc
  $ssc = $rsc.out | ConvertFrom-Json
  # Punta 1: no viaja por el canal que el SKILL.md manda persistir como user variable.
  Assert (@($ssc.requiredEnvVars) -notcontains "FIREBASE_PROJECT_DIR") `
    "$($case.name) firebase dir: no se pide como env var obligatoria (seria global a la maquina)"
  # Punta 2: y el prereq dice de que alcance es, para que nadie la persista a nivel usuario.
  $pf = @($ssc.prereqs) | Where-Object { $_ -match 'FIREBASE_PROJECT_DIR' }
  Assert ($pf -and ($pf -join ' ') -match '(?i)por proyecto|per-project') `
    "$($case.name) firebase dir: el prereq declara que es por proyecto ($pf)"
  Remove-Item -Recurse -Force $tsc
}

# --- INVARIANTE B1: ninguna credencial literal viaja en el .mcp.json ---
# El .mcp.json se commitea, asi que un secreto literal ahi es una fuga. El barrido cubre TODO el
# bloque del servidor y no solo 'env', porque el secreto de mas valor del catalogo no vive en 'env':
# la URL del MCP de Zoho es un secreto ENTERO (README.md la lista entre los secretos) y viaja en 'url'.

# Campos que el detector sabe inspeccionar. La lista es fail-closed a proposito: un campo nuevo hace
# fallar el barrido hasta que alguien le de tratamiento, en vez de viajar sin mirar.
$CamposConocidos = @('type','command','args','env','url','headers')

# Los 20 literales que los tres catalogos llevan hoy en claro, derivados de los .mcp.json generados
# (18 valores sueltos + los 2 defaults de ${VAR:-default}, que tambien se escriben en claro).
# Es un ALLOWLIST, no una heuristica de "esto parece un secreto", y la diferencia importa: un valor
# nuevo hace fallar el barrido hasta que alguien lo mire y lo apruebe con una linea. Sobre un archivo
# que se commitea, que un humano mire el literal nuevo es la garantia, no el costo; el costo son las
# dos o tres ediciones por anio en que el catalogo cambia de verdad.
# Se probo antes con entropia (un run alfanumerico largo con digitos) y se descarto midiendo: sobre
# las 5 formas de fuga que habia entonces agarraba 2, y su umbral de 14 quedaba por debajo de
# literales legitimos del catalogo ('ghcr.io/github/github-mcp-server', 32; 'GITHUB_PERSONAL_ACCESS_TOKEN',
# 28). Lo unico que evitaba el falso positivo era la condicion de digito -- ningun residuo legitimo
# tiene un run con digitos -- o sea el numero estaba justificado con la variable equivocada.
$LiteralesAprobados = @(
  'stdio','http',                                # type
  'npx','docker',                                # command
  '-y','-i','-e','-m','--rm','--dir','run',      # flags y subcomandos
  'firebase-tools@latest','experimental:mcp',    # firebase
  'ghcr.io/github/github-mcp-server',            # imagen del MCP de github
  'GITHUB_PERSONAL_ACCESS_TOKEN',                # NOMBRE de la env var que docker reenvia con -e
  'domo_mcp','utf-8','hssstaffing.domo.com',     # domo
  '.','python'                                   # defaults de ${FIREBASE_PROJECT_DIR:-.} y ${DOMO_MCP_PYTHON:-python}
)
# Esquemas de auth que pueden acompaniar a una ${VAR} en un header: 'Bearer ${TOKEN}' es correcto.
# Solo valen SI el valor trae una ${VAR}: un 'Bearer' suelto sin variable no es una forma valida.
$EsquemasAuth = @('bearer','basic','token','apikey')

# Devuelve @{ leaks; checked; desconocidos } para un servidor: 'leaks' son los valores que serian una
# fuga si el .mcp.json se commitea.
#
# El criterio es POR VALOR, no por campo, y esa es la leccion cara de este bloque: separar "url va por
# una regla" de "args va por otra" abre un bypass, porque un MCP hosted colgado de stdio PUEDE llevar
# la url y el header dentro de args (forma 'npx mcp-remote <url> --header ...', no verificada contra
# su fuente desde este repo; el fixture 'remote-fuga' la fija como amenaza a cubrir, no como hecho).
# El mismo secreto cambiaba de campo y pasaba en verde.
#
# Como se evalua cada string: se le quitan las ${VAR} (que son la forma correcta de parametrizar) y el
# residuo -- lo que realmente queda escrito en claro en el archivo -- tiene que estar aprobado.
function Find-CredentialLeaks($srvName, $srv) {
  $leaks = @(); $checked = 0

  $desconocidos = @($srv.PSObject.Properties.Name | Where-Object { $CamposConocidos -notcontains $_ })

  # Cada par nombre/valor del servidor, venga del campo que venga.
  $pares = @()
  if (-not [string]::IsNullOrEmpty($srv.type))    { $pares += @{ n = "type";    v = "$($srv.type)" } }
  if (-not [string]::IsNullOrEmpty($srv.command)) { $pares += @{ n = "command"; v = "$($srv.command)" } }
  if (-not [string]::IsNullOrEmpty($srv.url))     { $pares += @{ n = "url";     v = "$($srv.url)" } }
  if ($null -ne $srv.env) {
    foreach ($p in $srv.env.PSObject.Properties) { $pares += @{ n = "env.$($p.Name)"; v = "$($p.Value)" } }
  }
  if ($null -ne $srv.headers) {
    foreach ($p in $srv.headers.PSObject.Properties) { $pares += @{ n = "headers.$($p.Name)"; v = "$($p.Value)" } }
  }
  # $argv, no $args: $args es una variable automatica de PowerShell; pisarla no rompe nada aca, pero
  # el nombre propio evita que un futuro splat (@args) lea lo que no es.
  # Y la asignacion va en dos lineas, NO como 'if (...) { @(...) } else { @() }': un if usado como
  # expresion emite por el pipeline, que DESENROLLA un array de un elemento. Con un solo arg -- que es
  # una forma viva ('mcp-remote <url>', 'node server.js') -- $argv quedaba String y $argv[0] era su
  # primer CARACTER, asi que el arg entero no se inspeccionaba nunca.
  $argv = @()
  if ($null -ne $srv.args) { $argv = @($srv.args) }
  for ($i = 0; $i -lt $argv.Count; $i++) { $pares += @{ n = "args[$i]"; v = "$($argv[$i])" } }

  foreach ($par in $pares) {
    $checked++
    $v = "$($par.v)"
    $tieneVar = $v -match '\$\{[A-Za-z_][A-Za-z0-9_]*(:-[^}]*)?\}'
    # El DEFAULT de ${VAR:-default} se escribe en claro igual que cualquier literal, asi que se
    # conserva y se inspecciona; borrarlo junto con la variable dejaba un punto ciego donde el mismo
    # secreto pasaba con solo envolverlo: '${ZOHO_URL:-https://host/mcp/<token>/sse}'.
    $conDefault = [regex]::Replace($v, '\$\{[A-Za-z_][A-Za-z0-9_]*:-([^}]*)\}', '$1')
    # Y ahora si, fuera las ${VAR} sin default: queda lo que se escribe en claro en el archivo.
    $residuo = ([regex]::Replace($conDefault, '\$\{[A-Za-z_][A-Za-z0-9_]*\}', '')).Trim()
    if ($residuo -eq '') { continue }                                            # todo parametrizado
    if ($LiteralesAprobados -contains $residuo) { continue }                     # literal conocido
    if ($tieneVar -and ($EsquemasAuth -contains $residuo)) { continue }          # 'Bearer ${TOKEN}'
    $leaks += "$srvName.$($par.n)=$v"
  }

  return @{ leaks = $leaks; checked = $checked; desconocidos = $desconocidos }
}

# El detector tiene que MORDER, y hay que ATRIBUIR cada fuga a su rama, no contarlas. Contar el total
# deja pasar el reparto equivocado: con una rama borrada y otra que cubre de mas, el total sigue dando
# el numero esperado y el barrido queda verde con un campo entero sin mirar.
# La url de 'zoho-fuga' lleva el secreto como segmento de path: la forma que una heuristica de
# "contiene la palabra token" no reconoce, y que solo cae al mirar el residuo sin ${VAR}.
$envenenado = [pscustomobject]@{
  'zoho-fuga'     = [pscustomobject]@{ type = "http"; url = 'https://mcp.zoho.com/mcp/9f3a1c7d2b8e4f0a5d6b/sse' }
  'github-fuga'   = [pscustomobject]@{ type = "stdio"; command = "docker"; env = [pscustomobject]@{ GITHUB_PERSONAL_ACCESS_TOKEN = 'ghp_literal_del_usuario' } }
  'firebase-fuga' = [pscustomobject]@{ type = "stdio"; command = "npx"; args = @("-y","firebase-tools","--token","AIzaSyLiteralEmbebido") }
  'header-fuga'   = [pscustomobject]@{ type = "http"; url = '${MCP_URL_OK}'; headers = [pscustomobject]@{ Authorization = 'Bearer sk_live_LITERALFUGA' } }
  # El bypass que costo dos intentos: el MISMO secreto de 'zoho-fuga', mudado de 'url' a 'args'.
  'remote-fuga'   = [pscustomobject]@{ type = "stdio"; command = "npx"; args = @("-y","mcp-remote","https://mcp.zoho.com/mcp/9f3a1c7d2b8e4f0a5d6b/sse","--header","Authorization: Bearer ntn_LITERALFUGA0001") }
  # Un SOLO arg: fija el desenrollado del pipeline, que hacia leer el arg como un unico caracter.
  'unarg-fuga'    = [pscustomobject]@{ type = "stdio"; command = "mcp-remote"; args = @("https://mcp.zoho.com/mcp/9f3a1c7d2b8e4f0a5d6b/sse") }
  # El MISMO secreto de 'zoho-fuga', envuelto en el default de una ${VAR}: el default se escribe en
  # claro, asi que borrarlo con la variable dejaba pasar cualquier secreto con solo envolverlo.
  'default-fuga'  = [pscustomobject]@{ type = "http"; url = '${ZOHO_URL:-https://mcp.zoho.com/mcp/9f3a1c7d2b8e4f0a5d6b/sse}' }
}
# Se assertea el CAMPO y el SECRETO, no la cantidad de hallazgos: contar deja pasar el reparto
# equivocado (una rama de menos y otra que cubre de mas dan el mismo total). Los literales de utileria
# del fixture que no estan aprobados ('mcp-remote', '--token', 'firebase-tools' —el literal aprobado
# es 'firebase-tools@latest'—, entre otros) tambien caen, y esta bien que caigan:
# lo que se verifica aca es que el secreto cae, y en su campo.
$esperados = @(
  @{ srv = 'zoho-fuga';     campo = 'url';                              secreto = '9f3a1c7d2b8e4f0a5d6b'   },
  @{ srv = 'github-fuga';   campo = 'env.GITHUB_PERSONAL_ACCESS_TOKEN'; secreto = 'ghp_literal_del_usuario' },
  @{ srv = 'firebase-fuga'; campo = 'args[3]';                          secreto = 'AIzaSyLiteralEmbebido'   },
  @{ srv = 'header-fuga';   campo = 'headers.Authorization';            secreto = 'sk_live_LITERALFUGA'     },
  @{ srv = 'remote-fuga';   campo = 'args[2]';                          secreto = '9f3a1c7d2b8e4f0a5d6b'   },
  @{ srv = 'unarg-fuga';    campo = 'args[0]';                          secreto = '9f3a1c7d2b8e4f0a5d6b'   },
  @{ srv = 'default-fuga';  campo = 'url';                              secreto = '9f3a1c7d2b8e4f0a5d6b'   }
)
foreach ($esperado in $esperados) {
  $l   = @((Find-CredentialLeaks $esperado.srv $envenenado.($esperado.srv)).leaks)
  $hit = @($l | Where-Object { $_.StartsWith("$($esperado.srv).$($esperado.campo)=") -and $_.Contains($esperado.secreto) })
  Assert ($hit.Count -eq 1) "detector: '$($esperado.srv)' delata el secreto en '$($esperado.campo)' ($($l -join '; '))"
}
# Cerrar el lazo de verdad: comparar los nombres, no contra un entero. Con un entero, agregar un
# servidor al catalogo envenenado y actualizar el numero deja el servidor sin expectativa y en verde.
# La lista se DERIVA de $esperados en vez de copiarse a mano: escrita a mano, el camino natural de
# copy-paste —agregar el servidor, agregarlo aca, olvidar la fila de $esperados— lo dejaba sin
# expectativa y en verde igual. Es el mismo desfasaje que el entero, mudado a una lista de nombres.
$conExpectativa = @($esperados | ForEach-Object { $_.srv })
$sinExpectativa = @($envenenado.PSObject.Properties.Name | Where-Object { $conExpectativa -notcontains $_ })
Assert ($sinExpectativa.Count -eq 0) "detector: toda forma de fuga del catalogo envenenado tiene su expectativa (sin expectativa: $($sinExpectativa -join ', '))"

# Control negativo: un servidor legitimo NO debe dar hallazgos. Sin esto, un detector que marca todo
# pasaria igual los asserts de arriba. 'Bearer ${VAR}' es la forma canonica de un header autenticado y
# tiene que ser aceptada; el criterio anterior la rechazaba.
$limpio = [pscustomobject]@{ type = "http"; url = '${MCP_URL}'; headers = [pscustomobject]@{ Authorization = 'Bearer ${GITHUB_PERSONAL_TOKEN}' } }
$lLimpio = @((Find-CredentialLeaks "hosted-ok" $limpio).leaks)
Assert ($lLimpio.Count -eq 0) "detector: un servidor legitimo con 'Bearer `${VAR}' no da falso positivo ($($lLimpio -join '; '))"

# Y el reverso del mismo control: el esquema de auth solo vale ACOMPANIANDO a una ${VAR}. Un 'Bearer'
# con el token literal al lado no puede colarse por la puerta que abre 'Bearer ${TOKEN}'.
$falsoEsquema = [pscustomobject]@{ type = "http"; url = '${MCP_URL}'; headers = [pscustomobject]@{ Authorization = 'Bearer ghp_TokenLiteralSinVariable' } }
$lFalso = @((Find-CredentialLeaks "hosted-fuga" $falsoEsquema).leaks)
Assert ($lFalso.Count -eq 1) "detector: 'Bearer <literal>' no se cuela por la puerta del esquema de auth ($($lFalso -join '; '))"

# La lista de servidores se DERIVA del catalogo real en vez de hardcodearse, para que un servidor
# nuevo entre al barrido solo. La fuente es el LITERAL $Catalog del fuente del script, no el mensaje
# de error: el mensaje lo renderiza PowerShell envuelto al ancho de la consola, con prefijos y colores
# (verificado), asi que derivarlo de ahi ataba el barrido al ancho de la terminal y una lista larga
# PODIA cortarse en silencio, dejando servidores sin inspeccionar con el test en verde. Al largo de
# hoy no llegaba a cortarse: era un riesgo, no un bug que se estuviera viendo.
# Se lee con el parser de PowerShell y no con una regex sobre el texto: una regex ata el barrido al
# FORMATO del catalogo -- una clave sin comillas, u otra indentacion, devuelven una lista PARCIAL, y
# una lista parcial pasa el assert de abajo dejando servidores sin barrer. El parser no se inmuta.
function Get-CatalogServers($scriptPath) {
  $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$null, [ref]$null)
  $asg = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq '$Catalog' }, $true)
  if ($null -eq $asg) { return @() }
  $ht = $asg.Right.Find({ param($n) $n -is [System.Management.Automation.Language.HashtableAst] }, $true)
  if ($null -eq $ht) { return @() }
  return @($ht.KeyValuePairs | ForEach-Object { $_.Item1.Extent.Text.Trim("'").Trim('"') })
}
foreach ($case in @(
  @{ name = "personal";   script = $personal   },
  @{ name = "southpoint"; script = $southpoint },
  @{ name = "shareable";  script = $shareable  }
)) {
  $servers = @(Get-CatalogServers $case.script)
  # Fail-closed: si el parser AST deja de devolver servidores (un catalogo movido de lugar), esto da 0
  # y el barrido para, en vez de correr sobre una lista vacia y reportar "ninguna fuga".
  Assert ($servers.Count -gt 0) "$($case.name) invariante: el catalogo se pudo leer del fuente ($($servers -join ', '))"
  if ($servers.Count -eq 0) { continue }   # sin lista no hay nada que barrer; seguir con las otras variantes

  $tinv = NewTmp
  $rinv = RunScript $case.script $servers $tinv
  Assert ($rinv.exit -eq 0) "$($case.name) invariante: exit 0 generando todo el catalogo"
  $idoc = Get-Content (Join-Path $tinv ".mcp.json") -Raw | ConvertFrom-Json

  # Lo generado tiene que ser exactamente lo leido del catalogo: si el script rechaza o ignora alguno,
  # ese servidor no se inspecciona y el barrido quedaria en verde sin haberlo mirado.
  $generados = @($idoc.mcpServers.PSObject.Properties.Name)
  $noLlegaron = @($servers | Where-Object { $generados -notcontains $_ })
  Assert ($noLlegaron.Count -eq 0) "$($case.name) invariante: todo el catalogo aterrizo en el .mcp.json (no llegaron: $($noLlegaron -join ', '))"

  $offenders    = @()
  $ciegos       = @()
  $sinTratar    = @()
  foreach ($srvName in $generados) {
    $res = Find-CredentialLeaks $srvName $idoc.mcpServers.$srvName
    $offenders += $res.leaks
    # Un servidor del que no se inspecciono NADA no es "esta limpio": o su forma no la entiende el
    # detector, o todos sus campos inspeccionables vinieron vacios. En los dos casos hay que mirarlo.
    if ($res.checked -eq 0) { $ciegos += $srvName }
    # Y un campo que el detector no conoce viaja sin mirar aunque el resto del servidor se haya
    # inspeccionado: el contador agregado no lo delata, hay que preguntarlo aparte.
    foreach ($d in $res.desconocidos) { $sinTratar += "$srvName.$d" }
  }
  Assert ($ciegos.Count -eq 0) "$($case.name) invariante: el detector inspecciono algo de cada servidor (ciegos: $($ciegos -join ', '))"
  Assert ($sinTratar.Count -eq 0) "$($case.name) invariante: ningun campo viaja sin tratamiento en el detector (sin tratar: $($sinTratar -join ', '))"
  Assert ($offenders.Count -eq 0) "$($case.name) invariante: ninguna credencial literal ($($offenders -join '; '))"
  Remove-Item -Recurse -Force $tinv
}

# Sin rastros de testeo (regla del repo). No es cosmetico: varios casos de arriba no borraban su
# workspace, y ~100 corridas dejaron 606 directorios huerfanos en TEMP (medido). Lo que NO esta
# verificado es que eso rompa a otro test: copy-scaffold.tests.ps1 barre TEMP filtrando por su propio
# prefijo 'cs-test-*', que no matchea estos 'mcp-test-*'. Se limpia porque la regla del repo lo pide,
# no por una causa que nadie probo.
# La lista ya no se escribe a mano: `NewTmp` registra cada temporal, asi que uno nuevo se limpia
# sin que nadie lo agregue aca, y el `trap` de arriba cubre el camino de excepcion.
Cleanup-Tmps
# Y se asserta que la limpieza PASO: `-ErrorAction SilentlyContinue` se traga un borrado fallido,
# asi que sin este assert un temporal que sobrevive es invisible.
$sobrevivientes = @($script:tmps | Where-Object { $_ -and (Test-Path $_) })
Assert ($sobrevivientes.Count -eq 0) "sin rastros: los $($script:tmps.Count) temporales quedaron borrados (sobrevivieron: $($sobrevivientes -join ', '))"

Write-Host ""
if ($script:failures -gt 0) { Write-Host "$($script:failures) test(s) FALLARON"; exit 1 } else { Write-Host "TODOS LOS TESTS PASARON"; exit 0 }
