"""La tabla de brazos del A/B. Re-apuntar un brazo a otra versión es cambiar su línea acá.

`ref` es lo que se le pasa a git (commit o tag). `version` es el `version` que tiene que traer el
`.bootstrap-manifest.json` materializado desde ese ref: su sufijo (`+567c77a`) no es un commit y no
sirve como ref.
"""
from dataclasses import dataclass


@dataclass(frozen=True)
class Brazo:
    nombre: str
    ref: str
    version: str
    modo: str  # "serie" u "olas"


BRAZOS = {
    b.nombre: b
    for b in (
        Brazo("v1-serie", "f7ae28f", "2026-09-11+567c77a", "serie"),
        Brazo("v2-serie", "v2.1.0", "2026-09-23+3b3d849", "serie"),
        Brazo("v2-olas", "v2.1.0", "2026-09-23+3b3d849", "olas"),
    )
}
