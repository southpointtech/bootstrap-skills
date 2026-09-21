# Paralelismo por carriles — datos del proyecto

> **Datos de este repo para [`PARALELISMO.md`](PARALELISMO.md)**, que es mecánica y no se edita.
> Este archivo sí se edita, y la norma nombra sus secciones por su título: no las renombres.
>
> - **Cuándo se rellena**: cuando el proyecto ya tiene issues y va a abrir su primera ola. **No
>   se rellena al bootstrapear ni al correr `upgrade-bootstrap`**: el proyecto todavía no tiene
>   camino crítico ni ola, y un dato inventado pasa por medido.
> - **Las marcas**: cada dato sin rellenar va entre dobles llaves. Mientras quede una en este
>   archivo, `.claude/scripts/abrir-carril.ps1` se niega a abrir un carril y lista las líneas
>   (con `-DryRun` las muestra como aviso).
> - **«no aplica» es un valor válido**: un dato que no corresponde a este repo se escribe así,
>   nunca se deja la marca. En el bloque `carriles`, «no aplica» equivale a no declarar la clave
>   y rige el valor por defecto del script.
> - **«Lo que dejó la ola N» arranca vacía** y crece al cerrar cada ola.

## Encabezado

**Fecha**: {{AAAA-MM-DD}} · **Decidido con**: {{persona}} · **Alcance**: {{épica / PRD / lista de slices}}

## El camino crítico

```
{{01 → 03 → 07 → …}}
```

{{N}} eslabones: se pasa de {{M}} slices en fila a ~{{N}} niveles.

## Contratos fijados

| Módulo | Firma fijada |
|---|---|
| {{módulo}} | {{entrada → salida}} |

## Archivos calientes

{{entrypoint, router, `main.*`, `App.tsx`, registro de rutas}}

## Config compartida

{{perfil, `.env.example`, constantes}}

## Recursos compartidos

| Recurso | Aislamiento por carril |
|---|---|
| {{carpeta de datos de dev / bucket}} | {{subcarpeta propia (`…/dev/carril-a`, `-b`, `-c`) con su copia de los datos semilla}} |
| {{base de datos / emulador}} | {{instancia o archivo propio}} |
| {{puertos del dev server / emulador}} | {{puerto propio por carril (A, B, C), o los E2E sólo los corre el orquestador}} |

## Lo que un worktree no hereda

| Qué | Cómo se resuelve |
|---|---|
| {{`node_modules/`, venv, artefactos generados}} | {{instalar por worktree / compartir el venv — medir cuál}} |

## Guardas transversales

{{lista de guardas transversales, con su ruta}}

## El bloque que lee el script

`abrir-carril.ps1` lee sólo este bloque. Claves: `copiar` (rutas gitignoreadas, separadas por
coma), `worktrees` (carpeta de los worktrees, fuera del repo) y `base` (rama de la que salen los
carriles y donde se integran). Una clave distinta es un error. Un parámetro del script gana sobre
el bloque.

```carriles
copiar: {{.env, .scratch}}
worktrees: {{C:\Repos\…\carriles\<repo>}}
base: {{main}}
```

## La ola vigente

{{Se completa al planear la primera ola, con el plan aprobado de PLAN-DE-OLA.}}

## Lo que dejó la ola N
