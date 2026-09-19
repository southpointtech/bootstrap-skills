# tests/lib/solo-southpoint.ps1 — archivos que existen SÓLO en bootstrap-southpoint-project.
#
# Las tres skills bootstrap tienen el mismo SET de archivos (mirror.tests.ps1); lo que varía entre
# ellas vive DENTRO de archivos de variante. Estos son la excepción: la recolección de hub-sync
# (ADR-0012) es de Southpoint y no puede aparecer en las otras dos, y menos en bootstrap-ai-project,
# que se publica. Fuente única para mirror.tests.ps1 y shareable-leaks.tests.ps1: agregar un archivo
# acá es declarar la diferencia en los dos a la vez.
#
# Rutas relativas a la carpeta de la skill, con `/`.
$soloSouthpoint = @(
  "assets/scaffold/.claude/scripts/hub-recolectar.ps1"
)
