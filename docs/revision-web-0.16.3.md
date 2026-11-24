# Revisión de la web publicada — Stockealo 0.16.3+51 

Fecha: 16 nov 2026. Negocio de prueba «Minimercado La Esquina». Navegador de la app, 1024×768 y 1280×800, tema oscuro.
Solo revisión: no se corrigió nada. Código consultado en `Desktop/Stockealo-0.16.3` (main con la 0.16.3).

**Alcance cubierto:** Inicio, Caja, Vender, Ventas, Productos, Promociones, Stock, Clientes y proveedores, Tienda (vista previa), Reportes y metas, Ajustes, buscador, Stocky, selector de negocio; celular 390×844 y tema claro (muestras).
**Falta:** ver el final del archivo.

**Datos de prueba que quedaron en la nube:** en Caja, una entrada de $5.000 («Prueba revision») y 4 movimientos que se anulan entre sí (salida de $999.999, entrada de $999.999.999.999, salida de $999.999.999.999 y entrada de $999.999). Además: 1 cotización COT-5164018, 1 venta fiada de $4.200 a «Cliente Prueba», 1 venta mixta de $8.400 y la devolución de 1 Papas fritas.

## 1. Errores (graves primero)

1. **La hora de apertura de la caja sale 5 horas antes.** El encabezado y Caja dicen «abierta desde 12:04 p. m.», pero en Inicio › Actividad la apertura figura a las 5:04 p. m.
   *Cómo verlo:* abrir la caja y recargar la página (los datos vuelven de la nube).
   *Causa probable:* `CashSession.toMap()` guarda `openedAt.toIso8601String()` sin zona horaria (`lib/features/cash/models/cash_session.dart:75`). La nube lo toma como UTC, y al bajar, `localIso` (`supabase_service.dart:1891`) le resta 5 h. Hay que revisar si `cash_movements.date` y otras tablas tienen el mismo problema.
2. **Se puede sacar de la caja más plata de la que hay.** Una salida de $999.999 dejó la caja en «$-872.699». Tampoco hay tope de valor: aceptó una entrada de $999.999.999.999. Además, el negativo se escribe «$-», no «-$».
   *Archivos:* hoja de entrada y salida en `lib/features/cash/`.
3. **La devolución de una venta mixta descuadra la caja.** Al devolver 1 producto de una venta mixta (efectivo y Nequi):
   - en Ventas, el total baja, pero Efectivo y Nequi siguen igual;
   - en Caja aparece una forma de pago «Mixto $-4.500»;
   - el efectivo que debería haber no baja.

   La hoja dice «Devuélvele $4.500 por Mixto» y no dice de qué medio sale la plata.
4. **A 1024 px de ancho no se pueden retomar las ventas en espera.** En Vender no aparecen el botón «En espera» ni el acceso a cotizaciones; a 1280 px sí aparecen.
   *Archivo:* `sell_screen.dart` (diseño intermedio).
5. **El contador «En espera 1» no baja** al retomar la venta, aunque la lista ya está vacía. Solo se actualiza al cobrar.
6. **Los movimientos de caja no se pueden anular ni corregir.** Un error de digitación queda para siempre en el turno.

## 2. Cosas que confunden

7. **Ventas: el número de arriba y el de la lista no coinciden.** Arriba dice «4 ventas» (comprobantes de hoy) y la lista dice «Ventas registradas 9», porque muestra una tarjeta por producto. Todas son de hoy. La devolución aparece en la lista como otra venta de «$-4.500», sin decir que es una devolución.
8. **Descuento por línea mayor que el total.** La app lo baja al total sin avisar y deja «Cobrar $0». El aviso «pierdes $29.000» sale debajo de «Descuento a toda la venta», aunque el descuento es de la línea. Las dos hojas de descuento son distintas: la de línea no tiene «Máximo sin perder» y sus botones cambian.
9. **El detalle de producto tiene dos botones que hacen lo mismo:** «Vender» y «Registrar venta». Esto va contra la regla de no duplicar.
10. **Editar producto deja cambiar «Stock Actual» directo,** sin pasar por «Ajustar stock» y sin dejar historial.
11. **El recibo usa la hora en 24 h** («19:27»); el resto de la app ya usa 12 h.

## 3. Diseño viejo o roto

12. **A 1024 px se cortan títulos y buscador** («Mi…», «Ve…», «Ctr»). En el menú lateral también se cortan «Clientes y proveedore…» y el botón Salir.
13. **Con 2 productos a 1280×800, «Cobrar» queda debajo del borde.** El panel de la cuenta no deja el botón fijo abajo.
14. **«Transferen…» sale cortado** en los medios de pago a 1280 px.
15. **El chip «Todas» seleccionado no se lee** en Productos (blanco sobre blanco, en oscuro).
16. **Las tarjetas de producto en cuadrícula** tienen mucho espacio vacío debajo del texto.
17. **Detalle de producto, Editar producto y Promociones** se abren a pantalla completa, sin menú lateral. Editar producto mezcla mayúsculas como en el diseño viejo («Editar Producto», «Precio de Compra», «Agregar Foto», «Stock Actual»).
18. **El consejo de Stocky tapa los montos** de «Entradas y salidas» en Caja, y su botón tapa la etiqueta «Hoy» del gráfico de Inicio.

## 4. Mejoras

19. Que el pago mixto permita una parte fiada.
20. Que el campo de valor muestre los puntos de mil mientras se escribe (hoy se ve «999999»).
21. En Promociones, poner ejemplos del tipo de negocio (en un minimercado sale «20 % en camisetas»).

**Consola:** sin errores en lo recorrido; solo aparecen el aviso de sqflite y «Realtime: Escuchando ventas».

## 5. Puntos del dueño (16 nov, revisados en el código)

22. **«Nueva venta» del encabezado sobra.** Lo único que hace es `_navigateToTab(AppPlace.vender)` (`main_navigation_screen.dart:468`), lo mismo que «Vender» del menú lateral. Ya estando en Vender, tocarlo no hace nada: no vacía la cuenta ni empieza otra.
    *Antes de quitarlo hay que revisar dónde más aparece:*
    - `app_header_bar.dart:62-67` (el botón y `onNewSale`);
    - `where_things_moved_sheet.dart:23` («Siempre arriba, en el encabezado»);
    - `app_functions.dart:40` (`new_sale`, que usa el buscador Ctrl K);
    - el acceso rápido «Nueva venta» de Inicio (excepción permitida);
    - el botón «Nueva venta» del recibo recién cobrado (`digital_ticket_modal.dart:51`).

    *Opciones:* (a) quitarlo del encabezado y dejar Vender en el menú y Ctrl K; (b) dejarlo, pero que dentro de Vender pase la cuenta actual a espera y empiece una vacía; (c) ocultarlo cuando ya se está en Vender.
23. **«Gestionar categorías» tiene íconos del diseño viejo.** Editar está en azul (`info`) y eliminar en rojo, como `IconButton` sueltos de colores, y la inicial va en un círculo verde (`manage_categories_modal.dart:209-252`). En el diseño nuevo deberían ser íconos grises de acción, o un menú «…».
24. **Promociones › Productos marcados:** la lista para elegir productos (`CheckboxListTile`, `promotions_screen.dart:268`) muestra solo el nombre y la categoría. Mejora: una miniatura del producto, o sus iniciales si no tiene foto, como en Vender.
25. **Promociones › Fechas:** «Cambiar» abre `showDateRangePicker` (`promotions_screen.dart:247`), que ocupa toda la pantalla. Mejora: una ventana emergente con un calendario de rango y atajos («Esta semana», «Este mes», «Fin de semana»). El selector de fechas de Ventas (`sales_history_screen.dart:372`) tiene el mismo problema.
26. **Cambiar el nombre de un producto no se ve en el resto de la app.**
    - *Vender:* carga los productos una sola vez al abrir (`sell_screen.dart:192`). La pantalla queda viva entre pestañas, y `DataEvents` (`lib/core/services/data_events.dart`) solo avisa de ventas y caja, no de productos. El nombre nuevo solo sale al recargar. Lo mismo pasa con precio, foto y categoría. *Arreglo probable:* agregar `productsVersion` en `DataEvents`, llamarlo al guardar, borrar o ajustar un producto, y que Vender, Stock, Inicio y la tienda escuchen.
    - *Ventas ya hechas:* cada venta guarda una copia del nombre (`sale.dart`, `product_name`). Por eso un recibo viejo dice «test». Decisión pendiente: (a) mostrar el nombre actual en listas y reportes, uniendo por `product_id`, y dejar en el recibo el nombre de ese día; (b) mostrar siempre el nombre actual; (c) dejarlo como está. Recomiendo la (a), porque el recibo es un documento de ese momento.
27. **Metas se abre dos veces.** En Inicio, la tarjeta de metas abre `GoalsView.open` como pantalla aparte (`goals_widgets.dart:436` y `quick_actions_section.dart:100`). Reportes › pestaña Metas muestra la misma `GoalsView` (`reports_screen.dart:354`). El código no está duplicado, pero la pantalla sí, y eso va contra la regla de «una función, un lugar». *Arreglo:* que Inicio lleve a Reportes › Metas; para eso `ReportsScreen` necesita poder abrir en una pestaña dada. Crear la primera meta (`GoalSheet`) puede quedarse en Inicio.
28. **Tienda › categorías con foto de un producto.** En el filtro de categorías (`store_page.dart:1331-1352`), «Todas» sale con un cuadro gris vacío, y cada categoría toma la primera foto de uno de sus productos. El modelo `Category` (`lib/features/products/models/category.dart`) solo tiene `name` y `colorHex`, sin ícono.
    *Propuesta:*
    - agregar un campo `icon` a la categoría (columna en SQLite y en Supabase: requiere migración);
    - al crear una categoría, sugerir el ícono por el nombre (Bebidas → vaso, Aseo → spray…) y dejar cambiarlo a mano;
    - «Todas» con su propio ícono;
    - en la configuración de la tienda, un interruptor «Mostrar íconos de categoría» (si se apaga, solo el nombre);
    - usar el mismo ícono en los chips de Vender y Productos.

## 6. Segunda pasada (Stock, Clientes, Proveedores, Tienda, Reportes)

29. **Error: Reportes cuenta la devolución como venta con pérdida.** «Ventas por debajo del costo $1.300» es justo la ganancia de las Papas devueltas. La línea de la devolución tiene `net_profit` negativo y la consulta la suma como pérdida (`profit_report_repository.dart:151`). Hay que excluir las devoluciones.
30. **Error: Reportes no reparte el pago mixto.** «Cómo te pagaron» agrupa por `payment_method` (`profit_report_repository.dart:161`) y muestra «Mixto $3.900» aparte. Caja y Ventas sí reparten con `PaymentMethod.amounts` (`cash_register_repository.dart:166`). Resultado: el efectivo de hoy es $22.300 en Reportes y $27.300 en Caja y Ventas.
31. **Error: «Lo que más te dejó» agrupa por nombre del producto** (`profit_report_repository.dart:181`, `GROUP BY product_name`). Si se renombra un producto («test» → «Blusa 1»), aparece en dos filas. Hay que agrupar por `product_id`. Va junto con el hallazgo 26.
32. **Caja no se actualiza después de un abono.** Al registrar un abono de $2.100 en efectivo, Caja seguía en $132.300 hasta recargar la página; después mostró $134.400. El abono no avisa a `DataEvents.cashChanged()`.
    *Archivos:* `record_payment_modal.dart` y `customer_repository.dart:173`.
33. **Ventana de abono en diseño viejo.** «Registrar Abono a Fiado», «Deuda Pendiente Actual», «Monto a Abonar ($)», «Notas / Observaciones (Opcional)», todo con mayúsculas en cada palabra. El ejemplo es «Ej. 20000» aunque la deuda sea de $4.200. Solo deja pagar en Efectivo o Transferencia; Vender también tiene Nequi y Tarjeta.
    *Archivo:* `lib/features/customers/presentation/widgets/record_payment_modal.dart`. La validación de abono mayor que la deuda funciona bien.
34. **Entrada de mercancía con lote:** el vencimiento es obligatorio en productos con lote, pero solo se avisa al guardar, y el calendario abre un año adelante (16 nov 2027), aunque sean huevos. El título «Fecha de venci…» sale cortado y «ACEPTAR» va en mayúsculas (calendario por defecto de Flutter).
    *Archivo:* `lots_widgets.dart:55`.
35. **«De contado» en la entrada de mercancía sí descuenta de la caja** («Mercancía de contado $-116.000»), pero la pantalla no lo avisa, y Caja e Inicio no se actualizaron hasta recargar. La caja pasó de $134.400 a $18.400 sin que nadie lo notara. Mejora: decir en la entrada «Sale de la caja: $116.000», o preguntar si se pagó con la plata de la caja, y avisar si el efectivo no alcanza.
36. **Stock repite el encabezado de Productos.** Mismas 4 tarjetas (Productos, Stock bajo, Agotados, Valor del inventario) y la misma cuadrícula de fotos grandes. Para Stock serviría más una lista con la cantidad, el mínimo y un botón de ajustar.
37. **Proveedores sale centrado y angosto,** mientras «Clientes y fiados», en la pestaña de al lado, ocupa todo el ancho.
38. **Títulos todavía cortados a 1280 px:** «Clientes y pro…» y el nombre del negocio en el menú lateral («Minimercado La Es…»).
39. **Tienda encendida sin WhatsApp de pedidos:** no aparece ningún aviso. Mejora: avisar «Sin WhatsApp no te llegan los pedidos» o no dejar publicar.
40. **Tienda › Vista previa:** el chip dice «Todo» y en la app dice «Todas». La etiqueta «Sin guardar» aparece aunque no se haya cambiado nada.
41. **Pantallas que se abren sin el menú lateral:** Entrada de mercancía, Vista previa, Detalle de producto, Editar producto y Promociones.
42. **Arranque lento:** al recargar, la app tarda más de 8 s mostrando «Elegir negocio» y bloques grises antes de cargar el negocio.
43. **Reportes no descuenta los gastos de caja:** la ganancia neta es igual a la bruta, aunque en Caja haya salidas de tipo «Gasto». La nota al pie dice que no incluye arriendo ni sueldos, pero los gastos que sí se registran en caja tampoco cuentan. Mejora: restar las salidas de tipo Gasto.

## 7. Tercera pasada (Ajustes, buscador, Stocky, negocios, celular y claro)

44. **Error de fondo: las pantallas no se actualizan cuando cambia algo en otra.** `DataEvents` (`lib/core/services/data_events.dart`) solo avisa de ventas y caja, y las pantallas quedan vivas entre pestañas. Casos vistos:
    - Caja no cambia después de un abono ni de una compra de contado;
    - Inicio sigue diciendo «Quedan 2 de Huevos» después de entrar 8;
    - Vender no muestra el nombre nuevo de un producto (hallazgo 26).

    *Arreglo único:* avisos `productsVersion`, `customersVersion` y `stockVersion`, más `cashChanged()` en abonos y entradas de contado; las pantallas los escuchan. Esto resuelve los hallazgos 26, 32 y 35 juntos.
45. **Error: el buscador no encuentra clientes** («prueba» no trae a «Cliente Prueba»), aunque el campo dice «Busca producto, cliente o función». `global_search_dialog.dart` no consulta clientes.
46. **Error probable: Ctrl K deja de funcionar** después de volver de pantallas como Ajustes › Equipo. El atajo depende de `Focus(autofocus)` en `main_navigation_screen.dart:583-587` y el foco se pierde. Lo vi con el navegador automático; falta confirmarlo a mano en Chrome. *Arreglo:* registrar el atajo en `MaterialApp.shortcuts` o en un `Shortcuts` global.
47. **El buscador encuentra pocas funciones:** «caja» solo trae «Caja»; faltan «Cerrar caja», «Entrada de dinero» y «Salida de dinero». Revisar los sinónimos en `app_functions.dart`.
48. **Error: Stocky da los medios de pago incompletos.** «Ventas de hoy» solo muestra Efectivo, Transferencia y Fiado; faltan Nequi, Tarjeta y Mixto, así que las cifras no suman el total ($27.300 + $0 + $4.200 contra $52.600). Además usa `formatCOP` fijo para cualquier moneda y textos con mayúsculas en cada palabra («Total Facturado», «Ver Historial de Ventas»).
    *Archivo:* `stocky_assistant_service.dart:826-861` y la otra versión en la línea 908.
49. **Vender en el celular tampoco tiene acceso a ventas en espera ni a cotizaciones** (mismo problema que el hallazgo 4 a 1024 px).
50. **«Cerrar sesión» en tres lugares:** el botón «Salir» del menú lateral, Ajustes › Cerrar sesión y el selector de negocios. «Términos y privacidad» aparece en dos (Ajustes y el selector). Va contra la regla de no duplicar.
51. **Roles y permisos:** los interruptores del Dueño se ven activos, como si se pudieran cambiar, aunque dice «Siempre todo»; deberían verse bloqueados. «Crear rol» sale apagado sin decir por qué (¿es de Pro?). El ícono para entrar a Roles en Equipo no tiene texto.
52. **Equipo tiene dos formas de invitar:** el botón «Invitar» de arriba y la tarjeta «Código · Ver QR».
53. **Ajustes no tiene Avisos:** no hay dónde elegir qué notificaciones recibir (stock bajo, fiados, pedidos de la tienda).
54. **Ajustes › «Borrar datos» dice abajo «Eliminar la cuenta»:** no es lo mismo y asusta. Debe decir con claridad qué se borra.
55. **«Dónde quedó cada cosa» habla de la 0.12.0** y dice que «Nueva venta» está «siempre arriba». Hay que actualizarlo o quitarlo (ver hallazgo 22).
56. **«Tu negocio» usa otro encabezado** (flecha en círculo y título centrado) y la palabra «Tiquete»; en el resto de la app se dice recibo o comprobante.
57. **Módulos:** cada fila dice dónde está la función («Caja, en el menú»), pero no se puede tocar para ir allá.
58. **Reportes › Metas** muestra el enlace «Enviar el cierre del día», que es de Ganancias.
59. **«Bloquear la app: Pide PIN o huella»** en la web, donde no hay huella.
60. **Celular:**
    - «Caja abierta desde …» sale cortado en el encabezado;
    - el botón de Stocky tapa el monto de «Abonos en efectivo» en Caja;
    - Escape no cierra el menú lateral.

    En tema claro, Vender e Inicio se ven bien, y la barra de cobro ya no queda tapada por Stocky.

**Datos de prueba que se sumaron:** un abono de $2.100 de «Cliente Prueba» (ahora debe $2.100); una entrada de 8 Huevos de contado por $116.000 (vencen el 23 nov 2027); y un Arroz en la cuenta de Vender en el celular, sin cobrar (queda solo en este navegador). La caja dice ahora $18.400 en efectivo.

**Sin revisar:** anular una venta completa, el cierre de caja (para no dejarla cerrada), variantes y promociones creadas de verdad, el catálogo PDF y crear un negocio (para no llenar la cuenta).

## 8. Hallazgo del dueño (16 nov)

61. **En el computador solo se puede hacer scroll con el puntero sobre la columna del centro.** En Ajustes, Proveedores, Reportes, la Tienda, Pro y Legal, la barra de desplazamiento queda en medio de la pantalla y la rueda del mouse no hace nada sobre los costados vacíos.
    *Causa:* `ContentWidth` (`lib/core/design/content_width.dart`) envuelve toda la lista en un ancho máximo de 720 px centrado, y así la zona que hace scroll mide solo esos 720 px.
    *Arreglo en un solo lugar:* que la lista ocupe todo el ancho y que el contenido se centre dentro de ella, con un relleno a los lados. Por ejemplo, un `ContentWidth.sliver` o un `padding` calculado según el ancho. Se usa en unos 20 archivos.

## 9. Encontrado al arreglar la Fase 1 (16 nov)

62. **La nube guarda la hora del reloj como si fuera UTC.** La app sube las horas sin zona («17:04») y Supabase las guarda como «17:04+00». Las ventas se leen tal cual y se ven bien; la caja era la única que restaba la diferencia (hallazgo 1, ya arreglado en 0.16.4 leyendo la hora del reloj).
    *Riesgo pendiente:* las reglas del servidor que comparan con `now()` ven las ventas 5 h más viejas en Colombia. Por ejemplo, el límite de horas para anular (`sale_date < now() - …`, en `20261202500000_permissions_in_cloud.sql:209`) se cumple 5 h antes.
    *Arreglo de fondo* (más adelante, con migración y permiso): subir todas las horas en UTC real y corregir las guardadas según el país de cada negocio.

63. **Anular una venta que ya tuvo una devolución «llegó dañado»** (visto en la revisión de Codex de la 0.16.4, de antes y sin cambiar): al anular, también se anula la devolución, que comparte el número de comprobante, y la anulación resta del stock unidades que nunca volvieron al inventario.
    *Archivo:* `sales_repository.dart`, `voidSale`. Revisar en la Fase 2.
