# Plan: sedes (un negocio con varios locales)

> **Estado:** pendiente, **sin aprobar**. Solo es un plan: no se toca código hasta que el dueño lo apruebe y resuelva las preguntas de la sección 9.
> Pedido del dueño el 10 nov 2026, después de publicar la 0.12.0. El mismo día eligió la **opción A** (sedes dentro del mismo negocio) y respondió dos rondas de preguntas (secciones 2 y 6). Antes de decidir cómo se entrega, quiere seguir afinando el plan.

## 1. El problema

Un negocio que crece abre otro local: un lavadero con dos puntos, una tienda en dos barrios, una barbería en dos lugares.

**Hoy** Stockealo no tiene sedes. El stock es una sola cifra por producto, así que la única salida es crear otro negocio por cada local. Eso causa varios problemas:

- El catálogo se repite y los precios se desordenan.
- No hay un reporte de todo el negocio.
- No se puede pasar mercancía de un local a otro.
- Los clientes y sus deudas quedan sueltos.

## 2. Decisiones del dueño

1. **Opción A:** las sedes viven dentro del mismo negocio. El catálogo es uno solo y cada sede tiene su stock, sus ventas y su caja.
2. **Es parte de Pro.** Si el negocio pierde el plan, las sedes extra quedan **«Inactivas»** (ver sección 6).
3. **Nunca se retiene la información de nadie.** Aunque el plan venza, el dueño siempre puede ver y descargar los reportes y los datos de todas sus sedes.
4. **Límite:** el plan incluye la sede **Principal y 2 sedes más**. Para tener más, el dueño compra **sedes extra desde +1**, con descuento si compra varias de una vez. Solo en Pro Servicios. Ver sección 6.
5. **Elegir el plan por lo que se necesita:** en vez de que la persona adivine qué plan le sirve, ella marca lo que necesita (sedes, servicios, tienda…) y la app le sugiere el plan que más le conviene. Ver la sección 6b.
6. **Una sola tienda en línea por negocio.** Una sede no puede tener tienda propia.
7. **El dueño decide los precios por sede.** Por defecto cada sede cobra el precio del negocio, pero el dueño puede darle a una sede un **precio propio**: más barato en el barrio popular, un poco más caro en el de estrato alto. **La tienda en línea también muestra el precio de cada sede**, si es distinto.
8. **Clientes del negocio, fiados por sede.** Un cliente compra en la sede que más le convenga. Cada deuda pertenece a la sede donde se fió. Si el cliente debe en otra sede, la app se lo **avisa a quien atiende**. El dueño y los administradores ven las deudas de todas las sedes.
9. **Un cajero se puede trasladar** de una sede a otra.
10. **La tienda muestra el stock de cualquier sede** y dice **en qué sede** está cada producto.
11. **Los traslados de mercancía se confirman:** quedan «Pendiente de entrega» hasta que el **administrador** de la sede de destino confirma que llegó. Si no está, confirma el **encargado temporal** (ver «Encargado de turno» en la sección 4).
12. **Los fiados de una sede inactiva se cobran desde la Principal.**

## 3. Qué se comparte y qué va por sede

Todo negocio actual pasa a tener una sede **«Principal»**. A quien tiene un solo local no le cambia nada, y no ve nada nuevo hasta crear una segunda sede.

| Lo comparte el negocio | Va por cada sede |
|---|---|
| Catálogo de productos y servicios (nombre, código, categoría, fotos, costo) | Stock de cada producto, talla y color, y su stock mínimo |
| Precio del negocio (cada sede puede tener el suyo) | Ventas y cotizaciones |
| Clientes (con sus datos) | Fiados y abonos |
| Proveedores y lo que se les debe | Entradas de mercancía (llegan a una sede) |
| Tienda en línea (una sola) | Caja y cierre del día |
| Plan, configuración, módulos y mensajes | Tablero de Servicios, cola, asistencia y comisiones |
| Reportes de todas las sedes o de una | Equipo: cada persona trabaja en una sede |

## 4. Cómo funcionaría

### Sedes y selector
- **Dónde se crean:** Ajustes › Tu negocio › Módulos › **Sedes** (Pro Servicios), con nombre, dirección, teléfono y horario. La primera es «Principal» y se puede renombrar.
- **Cambiar de sede:** se usa el selector de negocio que ya existe, que muestra «Negocio · Sede». No hay un selector nuevo.
- **Quién ve qué:** el cajero trabaja en su sede fija. El dueño y los administradores eligen una sede o «Todas las sedes» para ver los resultados juntos. Para vender o abrir caja hay que elegir una sede.

### Inventario y precios
- **Stock:** el producto es uno solo, con su stock en cada sede. La lista muestra el de la sede elegida. Al abrir el producto se ve una tabla con el stock y el precio de cada sede.
- **Stock mínimo y reposición:** el stock mínimo y «por reponer» son de cada sede. Cuando a una sede le falta algo y a otra le sobra, la app sugiere un traslado antes de pedirle al proveedor.
- **Precio propio:**
  - En la ficha del producto o del servicio, el dueño o un administrador pone un precio propio para una sede. Queda marcado y se puede volver al precio del negocio.
  - Si cambia el precio del negocio, las sedes con precio propio no cambian.
  - El cajero cobra el precio de su sede.

### Traslados de mercancía (con confirmación)
Se hacen en Inventario › Proveedores y entradas › **Traslados**. Estados:

1. **Enviado («Pendiente de entrega»):** la sede de origen elige el producto (y la talla o el color), la cantidad y el destino. Las unidades **salen del stock de origen** y quedan «en camino». No se pueden vender en ninguna de las dos sedes.
2. **Recibido:** el administrador de la sede de destino (o el encargado de turno) cuenta lo que llegó y confirma. Las unidades **entran a su stock**. Si llegó menos, escribe cuánto recibió y una nota, y la diferencia queda registrada como faltante.
3. **Cancelado:** mientras esté pendiente, quien lo envió puede cancelarlo y las unidades vuelven al origen.

Los traslados pendientes se ven en las dos sedes y en la campana de avisos. Todo queda en la actividad, con quién envió y quién recibió.

### Clientes y fiados
- **Clientes del negocio:** cualquier sede encuentra al cliente y le vende. Sus datos son los mismos en todas las sedes.
- **Fiados por sede:** cada deuda pertenece a la sede donde se fió, y el abono se registra en esa sede.
- **Aviso a quien atiende:** al elegir un cliente que debe en otra sede, la venta muestra «Carlos debe $45.000 en Sede Norte». La venta no se bloquea.
  - Si se intenta fiar de nuevo, el aviso es más visible y pide confirmar. Por ejemplo: «Ya debe en otra sede. ¿Fiar de todas formas?».
- **Dueño y administradores:** en Ventas › Clientes y fiados, el filtro «Todas las sedes» muestra cada deuda con su sede y el total por cliente.

### Ventas, caja y cierre
Ventas, cotizaciones y caja quedan en la sede elegida. El cierre del día es por sede.

### Servicios (Pro Servicios)
- Cada sede tiene su tablero, su cola, su asistencia y sus personas.
- El catálogo de servicios es del negocio. Cada sede puede tener precio propio o apagar un servicio que no ofrece.
- Las comisiones y liquidaciones van por sede. El dueño las ve todas.

### Encargado de turno (cuando el administrador no está)

Muchas veces el cajero queda a cargo del local por un rato. Para no frenar la sede:

- **Nombrar encargado:** el dueño o el administrador marca a un cajero como **encargado de turno** de una sede: «hasta las 6:00 p. m.», «hasta mañana» o «hasta que lo quite».
- **Lo que puede hacer el encargado:** confirmar traslados que llegan, cerrar la caja de otros y recibir mercancía de proveedores. **No ve costos ni ganancias** y no cambia precios, igual que un cajero.
- **Se termina solo** al cumplirse la hora. Todo lo que hace queda en la actividad marcado «como encargado».
- **Si no hay encargado:** el cajero puede **recibir provisionalmente**. Las unidades entran al stock y se pueden vender, pero el traslado queda «Recibido, por verificar» hasta que el administrador lo revise. Así la mercancía no se queda parada.

### Equipo y traslado de cajero
- Cada persona tiene una sede. Los administradores pueden ver todas.
- **Trasladar:** en Ajustes › Equipo, el dueño elige «Trasladar a otra sede». La persona sigue en el negocio con el mismo rol y empieza a ver la otra sede.
- Si tiene caja abierta, debe cerrarla antes del traslado.
- Sus ventas y cajas pasadas se quedan en la sede donde las hizo, y el traslado queda en la actividad.

### Tienda en línea (una sola)
- La tienda es del negocio y muestra el catálogo.
- **Precios por sede:**
  - Si una sede tiene precio propio, la tienda lo muestra.
  - Al elegir la sede de recogida, se ven los precios de esa sede.
  - Antes de elegir, el producto muestra el precio del negocio o el rango («desde $8.000»).
  - El pedido se cobra con el precio de la sede elegida, que es el que el cliente vio.
- **Disponibilidad:** un producto se ve disponible si hay stock en **cualquier** sede, y la tienda dice **dónde**: «Disponible en Centro y Norte» o «Solo en Norte».
- **Recogida:** al pedir, el cliente elige en qué sede recoge. Solo aparecen las sedes que tienen todo el pedido. Si es a domicilio, la tienda propone la sede que tiene todo.
- **Convertir en venta:** el pedido llega como hoy, con el código o el QR por WhatsApp. Lo convierte en venta la sede elegida, que descuenta su stock.

### Reportes e Inicio
- **Reportes:** dueño y administradores eligen una sede o «Todas las sedes». Ganancias trae una comparación por sede y el Excel lleva una columna «Sede».
- **Inicio:** muestra el resumen de la sede elegida o de todas.

## 5. Ideas para mejorar el plan (para aprobar)

1. **Sugerencia de traslado antes de pedir al proveedor:** si a una sede le falta un producto y otra lo tiene de sobra, la app lo sugiere al revisar «Por reponer».
2. **Recogida en la sede que tiene el producto:** en la tienda, el cliente elige dónde recoger según el stock.
3. **Aviso de deuda en otra sede** al cobrar o fiar, sin bloquear la venta.
4. **Horario por sede**, para la tienda y para el mantenimiento de cada local.
5. **Metas por sede** en Inicio: ventas del día contra el promedio de esa sede.

## 6. Plan, límite de sedes e «Inactivo»

**Qué incluye** (decidido el 10 nov):
- Las sedes son **solo de Pro Servicios**. Pro (tiendas) no trae sedes, y Pro Global se elimina.
- Pro Servicios incluye la sede **Principal y 2 sedes más** (3 locales en total).
- **Sedes extra:** el dueño elige cuántas comprar, **desde +1**. Cuantas más compre de una vez, más descuento. Por ejemplo:
  - 1 sede: precio normal;
  - de 2 a 3 sedes en la misma compra: 10 % menos cada una;
  - 4 o más: 20 % menos.

  Los porcentajes y el precio se definen después, como el de Pro Servicios.
- Se activan igual que Pro: con un código, un pago o «Dar Pro» en el panel, que también deja dar sedes extra.
- En el panel admin se ve cuántas sedes tiene cada negocio y cuántas le permite su plan.

**Si el plan vence o se cancela:**
- La sede **Principal** sigue funcionando como hoy, con lo gratis de Stockealo.
- Las demás quedan **«Inactivas»**: en ellas no se vende, no se abre caja y no se reciben trabajos.
- **Toda su información se sigue viendo y se puede descargar** en Excel: reportes, ventas, fiados, inventario y caja.
- Los fiados de una sede inactiva **se cobran desde la Principal**, para que nadie pierda lo que le deben.
- El stock de las sedes inactivas se puede trasladar a la Principal.
- **Nunca se borra ni se bloquea información.** Al renovar el plan, las sedes vuelven a quedar activas con todo lo que tenían.
- Las personas de una sede inactiva pasan a la Principal o quedan sin sede hasta renovar. Lo decide el dueño.
- **Si se vencen solo las sedes extra**, quedan inactivas las que pasan del límite. El dueño elige cuáles.

## 6b. Elegir el plan por lo que se necesita

Hoy la pantalla de Pro muestra los planes y la persona tiene que adivinar cuál le sirve. La propuesta es preguntarle qué necesita:

1. En Stockealo Pro, «**¿Qué necesitas para tu negocio?**», con casillas:
   - Vender en línea con mi propia tienda.
   - Cobrar fiados automáticamente.
   - Ofrecer servicios (lavadero, barbería, taller…).
   - Tener varias sedes o locales.
   - Manejar varios negocios con una sola cuenta.
   - Más preguntas a Stocky.
2. La app **sugiere el plan que más le conviene** y explica por qué. Por ejemplo: «Pro Servicios: incluye servicios y hasta 3 sedes».
3. Si ninguno encaja exacto, muestra la combinación más barata. Por ejemplo, Pro Servicios más 2 sedes extra.
4. Si los precios están apagados, el resultado lleva a «Escríbenos por WhatsApp» con lo que marcó, para que tú le respondas con la oferta.

Esto también resuelve **qué plan da sedes**: la sugerencia muestra qué planes incluyen sedes (sección 9, pregunta 1).

## 7. Datos (Supabase y base local), cuando se haga

**Tablas nuevas**
- `branches`: sedes, con nombre, dirección, teléfono, horario, cuál es la principal y si está activa.
- `branch_stock`: stock por sede y por producto o variante, con su stock mínimo.
- `branch_prices`: precio propio de una sede para un producto o un servicio.
- `stock_transfers`: traslados, con origen, destino, líneas, estado (pendiente, recibido o cancelado), cantidades enviada y recibida, y quién envió y recibió.

**Columna `branch_id`** en: ventas, cotizaciones, movimientos, entradas de mercancía, cajas y sus movimientos, fiados y abonos, trabajos y asistencia de Servicios, comisiones, miembros del equipo y pedidos de la tienda (sede de recogida).

**Migración y seguridad**
- **Sin pérdida de datos:** todo lo que existe queda en la sede «Principal».
- **El stock es lo más delicado:** hoy es una sola cifra por producto. `products.stock` se mantiene como la suma de todas las sedes, para que la app vieja siga funcionando mientras la gente actualiza.
- **Reglas de Supabase:**
  - el cajero solo ve y escribe en su sede;
  - una sede inactiva solo permite leer y descargar;
  - los traslados se confirman con una función del servidor que mueve el stock de forma segura.

## 8. Verificación (cuando se programe)

**Funcionamiento general**
- Un negocio con una sola sede funciona igual que hoy y no ve nada nuevo.
- La venta descuenta solo el stock de su sede y cobra el precio de esa sede.
- Cambiar el precio del negocio no toca las sedes con precio propio.

**Traslados**
- Al enviar, las unidades salen del origen y no se venden en ninguna sede.
- Al confirmar, entran al destino. Si llega menos, queda el faltante.
- Si se cancela, las unidades vuelven al origen.

**Fiados y equipo**
- Al vender a un cliente que debe en otra sede, sale el aviso. Los fiados de «Todas las sedes» suman lo mismo que cada sede por separado.
- El cajero solo ve su sede. Tras trasladarlo ve la nueva, y sus ventas viejas siguen en la anterior.

**Tienda**
- Muestra en qué sedes hay cada producto.
- El pedido descuenta el stock de la sede de recogida.

**Plan vencido**
- Las sedes extra quedan inactivas, pero se pueden ver y descargar.
- Al renovar vuelven con todo.

**Migración y pantallas**
- La migración deja todo en «Principal» sin perder datos.
- Pantallas probadas a 360 px y 1200 px, en modo claro y oscuro.

## 9. Preguntas que quedan

1. ~~Qué planes incluyen sedes~~ **Resuelta (10 nov):** solo Pro Servicios.
2. ~~Paquete adicional~~ **Resuelta (10 nov):** se compran de a una (+1) o varias, con descuento por cantidad.
3. **Encargado de turno:** ¿te sirve la propuesta (encargado con hora de fin y recepción provisional «por verificar»)? ¿Qué más puede hacer el encargado: abrir y cerrar caja, anular ventas?
4. **Ideas de la sección 5:** ¿cuáles entran?
5. **Elegir el plan por lo que se necesita (sección 6b):** ¿se hace junto con las sedes o antes, por separado? Sirve desde ya para vender Pro Servicios.
6. **Entrega:** se decide cuando el plan esté afinado. Etapas propuestas:
   1. sedes, ventas, caja, equipo y encargado de turno;
   2. stock, precios y traslados;
   3. fiados y Servicios;
   4. reportes y tienda.
