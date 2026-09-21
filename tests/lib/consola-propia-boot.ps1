# tests/lib/consola-propia-boot.ps1 — el lado de adentro de `Invoke-EnConsolaPropia`.
#
# Corre DENTRO de la consola privada que abre el helper. Fija ahí la code page del caso y lanza el
# script bajo prueba con `-NoNewWindow`, o sea en esa misma consola: así el hijo hereda un ambiente
# que no es UTF-8, que es lo que el caso quiere ejercitar, sin que eso toque la consola de la suite.
#
# El stdout del hijo se redirige a un archivo a nivel del sistema operativo (`-RedirectStandardOutput`),
# no por la tubería de PowerShell: la tubería lo decodificaría con la code page que acabamos de fijar
# y devolvería el mojibake que el caso quiere descartar. El archivo queda con los BYTES que el hijo
# emitió, y quien llama los decodifica como quiera.
#
# Toda la entrada llega por un JSON en disco y toda la salida se devuelve por archivos: pasar rutas y
# argumentos por la línea de comandos entre tres procesos es exactamente donde se rompen las comillas.
param([Parameter(Mandatory)][string]$Plan)
$ErrorActionPreference = "Stop"

# -DateKind String: sin eso `ConvertFrom-Json` convierte a [datetime] cualquier argumento que parezca
# ISO-8601 (`-Now 2026-09-19T10:00:00Z`), y al volver a texto sale con la cultura de la máquina.
$p = [IO.File]::ReadAllText($Plan, [Text.UTF8Encoding]::new($false)) | ConvertFrom-Json -DateKind String

# Éste es el ambiente del caso. En esta consola no hay nadie más: muere con este proceso.
[Console]::OutputEncoding = [Text.Encoding]::GetEncoding([int]$p.cp)

# Entrecomillado a mano, y no `@()` pelado: `Start-Process -ArgumentList` pega los elementos con un
# espacio sin entrecomillar ninguno, así que una ruta con espacio llega partida (pwsh sale 64).
function Citar([string]$a) { if ($a -match '[\s"]') { '"' + ($a -replace '"', '\"') + '"' } else { $a } }
$argumentos = @('-NoProfile', '-File', (Citar $p.script)) + @($p.argumentos | ForEach-Object { Citar "$_" })
$proc = Start-Process pwsh -ArgumentList $argumentos -NoNewWindow -Wait -PassThru `
  -RedirectStandardOutput $p.rawOut -RedirectStandardError $p.rawErr

# La sonda mide lo único que no se ve desde afuera: con qué encoding ARRANCA un proceso lanzado
# después del script. Si el script fijó `[Console]::OutputEncoding`, la sonda hereda ese valor
# aunque `chcp.com` siga informando el viejo (medido el 2026-09-20).
$cpSonda = $null
if ($p.conSonda) {
  $s = Start-Process pwsh -ArgumentList '-NoProfile', '-Command', '[Console]::OutputEncoding.CodePage' `
    -NoNewWindow -Wait -PassThru -RedirectStandardOutput $p.sondaOut
  if ($s.ExitCode -eq 0) { $cpSonda = ([IO.File]::ReadAllText($p.sondaOut)).Trim() }
}

$meta = [ordered]@{ exit = $proc.ExitCode; cpSonda = $cpSonda }
[IO.File]::WriteAllText($p.meta, ($meta | ConvertTo-Json -Compress), [Text.UTF8Encoding]::new($false))
