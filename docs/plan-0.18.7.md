# Plan 0.18.7: tallas y scroll (25 nov)

Lo que el dueño notó probando la app en su negocio real. Es prioridad: va antes de la web de escritorio, que pasa a la 0.18.8, y de fiados, precios y Servicios por sede, que pasan a la 0.18.9.

Boceto aprobado: https://claude.ai/artifact/72efD5Sg3CrWdhFiwGTXBP

## A. Lo que pidió el dueño

### A1. Ordenar tallas arrastrando
- **Dónde:** en «Existencias», al crear o editar un producto, se mantiene presionado el bloque de una talla y se mueve.
- **Mientras se mueve:** la lista se encoge a una línea por talla para que quepa en la pantalla.
- **Arriba:** las tallas de «Tallas» siguen el mismo orden.
- **Computador:** se arrastra con el mouse.
- **Dónde se respeta el orden:** Vender, Stock, detalle del producto, tienda en línea, catálogo PDF y reportes.
- **Cómo se guarda:** columna `sort_order` en `product_variants`.
  - En la base del celular sube de la v33 a la v34.
  - En la nube va con una migración, que pide permiso aparte.
  - Los productos que ya existen toman el orden de hoy (`created_at`), así que nada se ve distinto hasta que alguien mueva una talla.
- **Lecturas:** pasan a `ORDER BY sort_order, created_at` en `product_repository.dart` y en la tienda pública.

### A2. Botón rápido «Pantalón»
- Al tocarlo pregunta para quién es:
  - Hombre: 28, 30, 32, 34, 36, 38
  - Dama: 4, 6, 8, 10, 12, 14, 16
  - Niños: 2, 4, 6, 8, 10, 12, 14, 16
- Se pueden agregar o quitar tallas a mano, como hoy.
- Va en `VariantPreset`, en `product_templates.dart`.

### A3. La talla nueva se acomoda sola
- Si la talla es conocida, se ubica donde va:
  - letras: XXS, XS, S, M, L, XL, XXL, 3XL;
  - números de menor a mayor, solo si todas las tallas de la lista son números.
- Una talla que no se conoce, por ejemplo «Única» o «32 largo», va al final.
- No se reordena lo que la persona ya movió a mano: solo se ubica la talla nueva.

### A4. Scroll en todo el ancho (computador)
- **Problema:** en algunas pantallas la lista está dentro de una columna centrada. La rueda del mouse solo funciona encima de la columna y la barra sale en el medio.
- **Arreglo:** usar `ContentListView`, el mismo de la 0.16.6. El contenido sigue centrado, pero el scroll funciona en todo el ancho.
- **Pantallas:**
  - Traslados y Nuevo traslado
  - Crear o editar producto
  - Detalle del producto
  - Roles
  - Panel admin: comentarios y listas que se actualizan al bajar
- **Prueba de candado:** falla si una pantalla vuelve a meter una lista en una columna de ancho fijo. Las ventanas y hojas quedan por fuera.

### A5. Botones − y + en la cantidad (boceto pendiente de aprobar)
- En cada fila de «Existencias», − y + a los lados del número.
- Cada toque suma o resta 1. Si se deja presionado, sigue sumando cada vez más rápido.
- En 0, el − queda apagado.
- El número se puede seguir escribiendo, y «Llenar todas» sigue igual.
- En el computador, las flechas ↑ y ↓ también suben y bajan el número.
- Las tallas ya guardadas no llevan − y +: su cantidad se cambia con «Ajustar stock físico», como hoy.

## B. Pendientes ya aprobados que entran en esta versión
1. **Enlace de la portada:** abre la app directo en «Crear cuenta».
2. **Términos:** corregir el texto que dice que Pro Servicios es «mensual (30 días)».
3. **Planes en la app:**
   - mostrar los precios de las sedes en la comparación;
   - agregar «Principal + 2 sedes incluidas» y «Traslados entre sedes» a lo que trae Pro Servicios.
4. **Cobro:** `pro-checkout` no cobra si `show_pricing` está apagado. Es una función de la nube y se despliega con permiso.

## Orden de trabajo
1. Rama `release/0.18.7` desde `main`.
2. A4, que es lo más corto.
3. A2 y A3.
4. A1: base del celular, editor y lecturas. La migración se ensaya con rollback y se aplica con permiso.
5. B1 a B4.
6. Pruebas, revisión de Codex y, después de tu permiso, commit, PR, unir y etiqueta.

## Lo que queda por fuera
- Ordenar colores dentro de una talla: se puede agregar después si hace falta.
