# Pedido del cliente: `inv`, un CLI de control de inventario

Somos una ferretería chica. Llevamos el catálogo y los movimientos de stock en dos planillas que
exportamos a CSV (`datos/productos.csv` y `datos/movimientos.csv`, adjuntas). Queremos un programa de
línea de comandos que las lea y nos conteste lo de todos los días.

## Cómo se corre

En Python 3, sin dependencias fuera de la biblioteca estándar (pytest para los tests está bien):

    python -m inv <comando> [opciones]

desde la raíz del proyecto. Lee los CSV de `datos/`, salvo que se pase `--datos <directorio>` antes
del comando. Los mensajes de error y las advertencias van a stderr; la salida pedida, a stdout.

## Los datos

`productos.csv` tiene `sku,nombre,unidad,punto_reorden`. El `punto_reorden` puede venir vacío.

`movimientos.csv` tiene `fecha,sku,tipo,cantidad`: fecha `AAAA-MM-DD`, tipo `entrada` o `salida`, y
la cantidad en unidades.

El stock de un producto es la suma de sus entradas menos la suma de sus salidas. Un producto sin
movimientos tiene stock 0.

## Lo que necesitamos

1. **`inv productos`**: lista el catálogo, una línea por producto ordenada por SKU:
   `SKU<TAB>NOMBRE<TAB>UNIDAD`.
2. **`inv stock <SKU>`**: imprime el stock actual del producto, solo el número. Un SKU que no existe
   es un error: mensaje en stderr y código de salida 1.
3. **`inv alta <SKU> <NOMBRE> <UNIDAD> [--punto-reorden N]`**: agrega un producto al final de
   `productos.csv`. El SKU tiene la forma `AAA-999`: tres letras mayúsculas, un guion y tres dígitos.
   Un SKU mal formado o repetido es un error: mensaje en stderr, código de salida 2, y el archivo no
   se toca.
4. **`inv exportar`**: imprime el catálogo como un arreglo JSON ordenado por SKU, cada producto con
   las claves `sku`, `nombre`, `unidad` y `punto_reorden` (un entero, o `null` si viene vacío).
5. **`inv rotacion --desde <AAAA-MM-DD> --hasta <AAAA-MM-DD>`**: cuántas unidades salieron de cada
   producto entre esas dos fechas, las dos incluidas. Una línea por producto con salidas en el
   período, `SKU<TAB>UNIDADES`, de mayor a menor; los empates, por SKU.
6. **`inv alertas`**: queremos que nos avise cuando el stock de un producto esté bajo. Una línea por
   producto con stock bajo, `SKU<TAB>STOCK`, ordenada por SKU.

## Ejemplos con los datos adjuntos

    $ python -m inv stock TOR-001
    120

    $ python -m inv stock BRO-006
    0
