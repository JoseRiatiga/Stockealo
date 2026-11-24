# Plan: sedes (un negocio con varios locales)

> **Estado (23 nov): EN PRIORIDAD. Etapa 1 APROBADA, con el ajuste «la Principal se queda donde está».** Las preguntas de la sección 9 están resueltas. Falta el boceto y la aprobación final; no se toca código hasta entonces.
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

**Cambio de diseño (23 nov, antes de programar): la Principal se queda donde está**
- Lo que había antes era que el stock de todas las sedes iba a `branch_stock` y `products.stock` era la suma. Eso es frágil: un celular con la app vieja escribe el stock completo (no por sede) y descuadra la suma. Además obliga a cambiar los ~51 lugares que tocan el stock en todos los negocios.
- **Nuevo:** las columnas de hoy (`products.current_stock`, `product_variants.stock`, ventas, cajas…) siguen siendo **de la sede Principal**. `branch_stock` guarda **solo las sedes extra**. En ventas, cajas y movimientos, `branch_id` vacío quiere decir **Principal**.
- **Así:**
  - un negocio con una sola sede funciona exactamente igual que hoy;
  - no hay que mover datos;
  - una app vieja que escriba sin sede escribe en la Principal, que es lo correcto.
- **Regla:** antes de crear la segunda sede, la pantalla Sedes pide que todos los celulares del equipo actualicen la app. Una app vieja solo ve y vende en la Principal.

**Decisiones de la Etapa 1 (propuestas)**
- **Lotes y vencimientos (respuesta del dueño, 23 nov):** **en todas las sedes desde la Etapa 1.** Cada sede puede tener productos distintos que vencen; los lotes son de la sede donde entraron.
- **Contar inventario, pedido sugerido y avisos de stock bajo:** de la sede elegida (aprobado).
- **Importar Excel:** carga a la sede elegida (aprobado).
- **Tienda en línea (respuesta del dueño, 23 nov):** una sola tienda con todas las sedes. Quien compra **elige qué sede ver** (por cercanía o comodidad) y ve el stock de esa sede. Por confirmar si entra en la Etapa 1 o en la 3.
- **Pro sin conexión:** se guarda el último estado de Pro en el celular, para que una sede no se bloquee al abrir la app sin internet.
- **Si vence el plan:** las sedes extra quedan inactivas desde la Etapa 1. El límite (Principal + 2 + extra) lo hace cumplir la nube, no solo la app.
- **Caja:** una caja abierta por sede, no por negocio.
- **Cajero:** la nube revisa que venda y abra caja solo en su sede. En la Etapa 1, **ver** lo de otras sedes se filtra en la app; la nube lo cierra del todo en la Etapa 2.
- **Copias y datos:** las tablas nuevas entran en la copia diaria, en «Descargar todos mis datos» y en el borrado de cuenta.

**Orden de trabajo de la Etapa 1:**
1. ~~Ordenar todo el código del stock en un solo lugar~~ **Cambio (23 nov):** lo de la Principal se deja **intacto** y solo se agrega el camino de las sedes extra (con una prueba que vigila que no se escape ninguna escritura a la Principal).
2. Tablas nuevas en la nube y en el celular, sin tocar lo de hoy.
3. Pantalla Sedes en Módulos y selector.
4. Stock, ventas y caja por sede.
5. Reportes por sede y «Todas las sedes».

**Avance (23 nov, rama feat/0.18.0, sin commit):**
- Migración `20261210000000_branches.sql` **ensayada OK y SIN APLICAR**:
  - tablas `branches`, `branch_stock` y `branch_slots`;
  - columna `branch_id` en ventas, cajas, entradas, lotes y equipo;
  - límite de cupos en la nube y regla de que el cajero solo venda en su sede;
  - cierre de sede en un solo paso.
- **La app vieja no ve nada de las sedes extra:** solo las ve una app que manda la cabecera `x-stockealo-branches` (0.18.0).
- Pro guardado en el celular para cuando se abre sin internet. Base local versión 33.

**0.18.0 hecha en código (24 nov, rama feat/0.18.0, sin commit), versión 0.18.0+60:**
- **Celular:** sedes (`BranchRepository`); stock, lotes, ventas, devoluciones, anulaciones, entradas, ajustes, conteo, importar y caja por sede; vista `sales_here` para Inicio, reportes, cierre del día y Stocky (el Excel de Reportes trae todas las sedes).
- **Pantallas:** selector en el botón del negocio (sedes, «Todas las sedes» para ver, «Otro negocio…»); Módulos › Sedes (abrir con cupo, editar, cerrar eligiendo a dónde pasa la mercancía, reabrir, renombrar la Principal); sede de cada persona en Equipo; «Cupos de sede» en el panel; «Sedes» en el buscador.
- **Pruebas:** 697 pasan, con una prueba de sedes (venta, devolución, anulación, entrada y ajuste en una sede extra sin tocar la Principal) y un candado que cuenta dónde se escribe el stock de la Principal.
- **Codex: 2 hallazgos corregidos:**
  - las funciones de stock por sede ahora revisan que la sede esté en uso y sea la de la persona;
  - los movimientos de caja revisan la sede de la persona y la de su caja.
- Migración ensayada completa (cerrar una sede pasó 4 unidades a la Principal) y **SIN APLICAR**.
- **Falta:**
  - en Stock, la línea pequeña «Norte 14 · Sur 6» del boceto;
  - probar con el negocio LAVADERO en la web publicada.

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

## 9. Preguntas: todas resueltas (23 nov)

El dueño puso Sedes **en prioridad** el 23 nov y aceptó las recomendaciones:

1. ~~Qué planes incluyen sedes~~ **Solo Pro Servicios** (10 nov).
2. ~~Paquete adicional~~ Se compran **de a una o varias** (10 nov). **Precio (23 nov):** **$29.900 al mes cada sede extra**, o **$24.900 cada una si se compran 3 o más** en la misma compra. Pro Servicios ($79.900) incluye la Principal y 2 sedes.
3. **Encargado de turno: SÍ.** Un cajero queda a cargo de su sede hasta una hora de fin.
   - **Puede:** abrir y cerrar caja, confirmar traslados, recibir mercancía (recepción «por verificar»).
   - **No puede:** ver costos ni ganancias, ni anular ventas.
4. **Ideas (sección 5):**
   - **Sí:** sugerir un traslado antes de pedir al proveedor (se apoya en el pedido sugerido de la 0.17.0), recoger en la sede que tiene el producto y horario por sede.
   - **Después:** metas por sede.
5. ~~Elegir el plan por lo que se necesita~~ **Ya existe** (PlanFinder, pantalla Pro, desde la 0.15.0). Solo hay que agregarle «Varias sedes».
6. **Entrega: por etapas.**
   1. **Etapa 1 (0.18.0):**
      - sedes con la Principal automática;
      - cambiar de sede con el selector que ya existe;
      - stock, ventas y caja por sede;
      - equipo por sede (cajero de una sede; traslado de cajero);
      - reportes por sede y «Todas las sedes»;
      - la migración deja todo en «Principal».
   2. **Etapa 2 (0.18.1):** traslados de mercancía con confirmación, encargado de turno y sugerencia de traslado antes de pedir al proveedor.
   3. **Etapa 3 (0.18.2):**
      - fiados por sede, con aviso;
      - precios por sede;
      - Servicios por sede;
      - tienda con stock por sede y recogida en la sede, horario por sede;
      - compra de sedes extra.

**Respuestas del 23 nov (noche):**
- **Tienda por sede en la Etapa 1, solo el stock:**
  - quien compra elige la sede y ve lo que hay ahí, con su dirección, su horario y «Cómo llegar»;
  - la tienda recuerda la sede elegida;
  - los precios por sede llegan en la Etapa 3.
- **Pro también puede tener sedes:**
  - con Pro ($24.900) cada sede extra se paga aparte ($29.900, o $24.900 cada una desde 3), sin sedes incluidas;
  - Pro Servicios sigue trayendo la Principal + 2.
- **Solo el dueño** crea, cierra y reabre sedes. Los administradores las manejan, pero no las crean.
- **Cupos de sede:**
  - se paga un cupo, no una sede;
  - al cerrar una sede el cupo queda libre y pagado hasta que termine el mes, y ahí se puede abrir otra sede o reabrir la misma;
  - si no se renueva, el cupo desaparece.
- **Cerrar, nunca borrar:** la sede cerrada conserva su historial (se ve y se descarga) y se puede reabrir con todo. La Principal no se cierra; solo se renombra.
- **Al cerrar una sede, la app pide:**
  - cerrar su caja;
  - pasar las personas a otra sede;
  - pasar la mercancía: **el dueño elige si va a la Principal o a otra sede**.

  Los fiados pendientes se cobran desde la Principal.

**Precio de cada sede extra (corregido y aprobado el 23 nov):** una sede debe costar bastante menos que el plan; si no, conviene abrir otro negocio.

| Plan | Sede extra al mes | Al año | Desde 3 extra (cada una, al mes) |
|---|---|---|---|
| Pro ($24.900, solo Principal) | $14.900 | $149.000 | $12.900 |
| Pro Servicios ($79.900, Principal + 2) | $24.900 | $249.000 | $21.900 |

(Reemplaza a los $29.900/$24.900 de antes.)

**Cobro de los cupos (aprobado el 23 nov):**
- **Un solo pago:** en la pantalla Pro, «Sedes extra – 1 +» bajo cada plan. Ejemplo: Pro + 1 sede = $39.800 al mes. La nube calcula el precio.
- **Todo vence el mismo día:** los cupos vencen con el plan (mensual o anual) y se renuevan juntos.
- **Agregar a mitad de periodo:** se pagan solo los días que faltan (precio × días que faltan / días del periodo, redondeado a $100). Si faltan **menos de 7 días**, se suma el periodo siguiente.
- **Cupo anual** = 10 meses.

**Entregas:**
- **0.18.0:**
  - sedes en Módulos: crear, cerrar, reabrir y cupos;
  - selector;
  - stock, lotes, ventas, caja y equipo por sede;
  - reportes por sede y «Todas las sedes»;
  - los cupos se dan desde el panel;
  - se prueba con el negocio de prueba LAVADERO.
- **0.18.1:** tienda con selector de sede, y compra de plan + sedes en un solo pago con Wompi.
- **0.18.2:** traslados con confirmación, encargado de turno y sugerencia de traslado.
- **0.18.3:** fiados por sede, precios por sede y Servicios por sede.
