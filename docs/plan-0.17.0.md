# Plan de la 0.17.0 — para vender más y con menos trabajo

Estado: **APROBADO el 22 nov con las recomendadas**: la 0.17.0 trae A, B, C y D; venta por peso (E) en su propia versión justo después; impresora (G) solo formato web por ahora; combos (F) después; Sedes pasa a la 0.18.0.

Antes la 0.17.0 era «Sedes y negocio». Propuesta: Sedes pasa a la 0.18.0 y se hace cuando un cliente la necesite (faltan 4 respuestas, ver `docs/plan-sedes.md`). La 0.17.0 trae lo que sirve a todos los negocios desde ya.

## Qué hay hoy (revisado en el código)

| Idea | Hoy |
|---|---|
| Primera venta | «Primeros pasos» en Inicio (producto, caja, venta, equipo, tienda) |
| Pedido al proveedor | Existe; sugiere el doble del mínimo menos lo que hay, sin mirar lo que se vende |
| Ajustar stock | Uno por uno con «Ajustar»; no hay conteo de todo el inventario |
| Precios al por mayor, por peso, combos | No existen |
| Impresora | El recibo se comparte o se imprime como PDF; no hay impresora térmica |

## Bloques propuestos

### A. La primera venta (idea de Loliando: creó 7 productos y no volvió)
- En Inicio, con productos y sin ventas: tarjeta «Haz tu primera venta» que abre Vender con un producto ya puesto.
- «Venta de práctica»: se hace, se ve el recibo y se anula sola; no cuenta en Reportes ni Caja.
- En el APK: un aviso a los 2 días si hay productos y ninguna venta («¿Te ayudamos con tu primera venta?»), que se puede apagar en Avisos.
- Panel admin: lista «Negocios sin primera venta» con días desde que se registraron y botón de WhatsApp, para que tú los contactes.

### B. Precios al por mayor (Pro)
- En Editar producto: «Precio por cantidad», por ejemplo «desde 12 unidades: $1.800». Hasta 3 escalones.
- Vender aplica el precio solo al llegar a la cantidad y lo muestra («Precio por mayor»). La tienda en línea lo muestra en el producto.
- **Migración:** escalones en el producto (local y nube); la nube valida el precio igual que hoy valida descuentos.

### C. Conteo de inventario
- Stock › «Contar inventario»: lista por categoría con «Hay en la app» y un campo «Contaste». Se puede guardar a medias y seguir después.
- Al terminar, un resumen: cuánto sobró, cuánto faltó y en cuánta plata a costo. Cada diferencia queda como ajuste en el historial, con motivo «Conteo del [fecha]».
- Lector de códigos para contar rápido: cada lectura suma 1.
- Sin migración: usa los ajustes de stock que ya existen.

### D. Pedido sugerido al proveedor
- El pedido sugiere según lo que se vendió en los últimos 30 días y los días hasta la próxima visita del proveedor, no solo el doble del mínimo.
- Muestra por qué: «Vendes 4 por semana; te alcanza para 3 días».

### E. Venta por peso o medida
- Productos que se venden por kilo, gramo, litro o metro, con cantidades como 0,75 kg; el precio se calcula solo.
- **Es grande:** hoy el stock es un número entero en la app, en la nube y en los reportes; hay que cambiarlo en todas partes, con migración.

### F. Combos y kits
- Un producto hecho de otros («Combo desayuno» = café + pan). Al venderlo, salen los componentes del stock.
- Sirve también para insumos de servicios (lavado = shampoo + cera).
- Mediano: toca Vender, devoluciones, anulaciones y la tienda.

### G. Impresora térmica
- **Web:** recibo en formato de 58 u 80 mm para imprimir desde el navegador (funciona con impresoras USB instaladas en el computador).
- **APK:** impresora Bluetooth de 58/80 mm, que es lo que usan las tiendas. Necesita una librería nueva y probar con una impresora real.

## Decisiones

- **D1. Qué entra en la 0.17.0.** *Recomendado:* A, B, C y D (útiles para todos y sin cambios grandes de datos). E, F y G pasan a la 0.17.1 o 0.18.0.
- **D2. Venta por peso (E).** (a) Hacerla en la 0.17.0 aunque sea grande; (b) en su propia versión justo después, *recomendado*, porque toca el stock de toda la app.
- **D3. Impresora (G).** (a) Solo el formato de la web por ahora, *recomendado* si no tienes una impresora Bluetooth para probar; (b) web y Bluetooth (necesito que tengas una impresora para probar).
- **D4. Sedes.** ¿Pasa a la 0.18.0 como se propone arriba?

## Cómo quedó (22 nov, rama feat/0.17.0, sin commit)

- **A.** Dentro de «Primeros pasos» (sin tarjeta duplicada), el paso de la primera venta trae «Vender» (abre Vender con un producto con stock ya puesto) y «Venta de práctica». Si todo está en 0, manda a Stock. La práctica **no guarda nada** en vez de guardar y anular: así no deja movimientos de stock, caja ni nube. El recibo sale con el sello PRÁCTICA. «Primera venta» cuenta solo ventas de verdad (sin anular y sin devoluciones), con una sola definición (`FirstSale`). El aviso del APK sale una vez a los 2 días a las 10 a. m., se cancela con la primera venta y se apaga en Avisos. En el panel queda un grupo nuevo en «Salud › A quién conviene escribirle hoy», con WhatsApp si el negocio puso teléfono en Datos del recibo y el correo si no.
- **B.** Hasta 3 escalones en Editar producto (con Pro; sin Pro se guardan pero no se aplican). Vender los aplica solo («Precio por mayor» en la línea). Con promoción se queda lo mejor para el cliente y no se suman las dos. Un precio cotizado no se toca. La tienda muestra «Desde 12: $1.800 c/u» y cobra así en el carrito. Base local v32. **Diferencia con el plan:** la nube no revisa el precio unitario (tampoco lo revisaba antes; solo descuentos). Revisarlo contra el precio actual rechazaría ventas hechas sin conexión antes de un cambio de precio. Queda anotado para después.
- **C.** Stock › «Contar inventario». Vacío significa no contado. La diferencia se aplica sobre el stock del momento, así que lo vendido mientras se contaba no se pierde. Motivo «Conteo del dd/mm/aaaa». Lector de códigos (+1 por lectura). El borrador queda en este celular.
- **D.** El pedido sugerido mira lo vendido en 30 días (sin anuladas y restando devoluciones, por talla y color). Alcanza hasta la próxima visita del proveedor más una semana, o 14 días si no tiene día de visita. Muestra «Vendes 4 por semana; te alcanza para 3 días». Sin ventas se queda la regla del doble del mínimo.
- **Revisión (Codex y mía):** corregidas 4 fallas:
  - un conteo que falla a la mitad ya no suma dos veces al reintentar;
  - «En la app» se pone al día con ventas de otro celular;
  - retomar una venta en espera sale de la práctica, así no se pierde una venta real;
  - el aviso de primera venta también se programa al crear productos.

  Anotado, sin cambiar:
  - sin conexión al abrir la app, Pro no se sabe todavía y Vender cobra el precio normal hasta que conecte;
  - si se publicara la web antes de aplicar la migración, los escalones quedarían solo en el celular. Por eso la migración va primero.
- **Migración** `20261208000000_price_tiers_first_sale.sql`: ENSAYADA OK con rollback (la tienda «miselanea» responde con 13 productos) y **SIN APLICAR**. Hay que aplicarla antes de publicar la web.

## Cómo se trabaja

- Rama `feat/0.17.0` desde main. Pruebas de lo que toque plata (precios por mayor, conteo, venta de práctica).
- Migraciones ensayadas antes y aplicadas con tu permiso, antes de publicar la web.
- Revisión de Codex antes de publicar. Web primero; el APK cuando la revises.
