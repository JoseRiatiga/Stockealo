# Referencias de diseño (para el diseño nuevo de Stockealo)

> Forma parte del plan de **RE-DISEÑO completo**: `docs/plan-rediseno.md`.

> **IMPORTANTE (dueño, 10 nov):** todo lo de este documento son **diseños PROPUESTOS**, no decisiones: la matriz de roles, el Command Center y las referencias que vengan. Con todas ellas se arma **un diseño FINAL** al terminar de recogerlas. Nada de esto se programa como diseño definitivo antes de que el dueño apruebe ese diseño final.
>
> El dueño planea reemplazar el diseño V1. Aquí se anotan las referencias que muestra («Mira Instagram»): **cómo está hecho** cada diseño y **qué tomar** para Stockealo. Se dibuja con nuestro propio código, sin copiar el de nadie.
> Cuando haya varias referencias, se arma con ellas la propuesta del diseño nuevo.

---

## 1. Matriz de roles y permisos (10 nov 2026)

Fuente: video de Instagram (moxen.studio). Aplicada en `docs/plan-roles.md`, sección 8.

- Tema oscuro azul petróleo, tarjeta central con bordes suaves.
- Interruptores grandes, de un color por rol, con ✓ y rebote.
- Contador grande «17/32 permisos activos».
- Barra de puntos por rol («6/8»).
- Punto naranja en los cambios sin guardar y barra flotante «N cambios · Descartar · Guardar».
- Leyenda al pie y uso con teclado.

---

## 2. «Command Center» de inventario con exportar reporte (10 nov 2026)

Fuente: video de Instagram (ui.iliasmiah000). Un panel de inventario para varias bodegas, en **tema claro**.

### Estructura de la pantalla

**Barra lateral izquierda (fija, en el computador):**
- **Arriba:** logo y nombre de la app. A su lado, un botón para plegar la barra.
- **Selector del negocio** en una tarjetita: nombre («Harbor & Pine Supply»), detalle debajo («4 bodegas · Columbus, OH») y una flecha para cambiar.
- **Menú agrupado por secciones**, con el título de cada sección en letra pequeña y gris:
  - sin título: Command Center (inicio, resaltado);
  - OPERACIONES CON IA: Centro de agentes, Centro de aprobaciones (con **contador naranja «8»**), Actividad de agentes;
  - INVENTARIO: Productos, Movimientos de stock, Auditoría de inventario;
  - BODEGA: Bodegas, Traslados de stock;
  - COMPRAS: Órdenes de compra, Proveedores;
  - INTELIGENCIA: Pronósticos, Analítica;
  - al final: Equipo y permisos, Ajustes.
- **Abajo del todo:** la persona con foto, nombre y rol («Dana Okafor · Inventory planner»).
- Cada opción lleva un ícono de línea fina, gris, y el texto en gris oscuro. La opción activa tiene un fondo gris claro.

**Encabezado del contenido:**
- **Título grande** («Command Center») y debajo **una línea de contexto**: fecha, cuántos productos y bodegas, y «actualizado 08:42».
- A la derecha:
  - una pastilla de estado con punto verde («5 agentes trabajando»);
  - el **buscador** con el atajo de teclado (⌘K);
  - el botón «Exportar» con borde;
  - el **botón principal oscuro** «+ Nueva orden»;
  - la campana.

**Contenido: tarjetas en cuadrícula (estilo «bento»):**
- **Valor del inventario:**
  - número grande («$4.82M») con una **pastilla verde de variación** («+3.2 %»);
  - una línea pequeña debajo («186.420 unidades disponibles»);
  - un **mini gráfico de barras** gris;
  - enlace al pie («Ver valoración»).
- **Esperando aprobación:**
  - «8 propuestas» y el monto en juego;
  - **barra de estado segmentada** por colores (naranja y azul);
  - leyenda («2 vencen hoy · 6 después»);
  - enlace «Revisar propuestas».
- **Gráfico grande** de recibido contra despachado:
  - **curvas suaves con relleno rayado** entre ellas;
  - selector de periodo («Últimos 6 meses»);
  - leyenda de colores;
  - **tooltip** con el mes y los tres valores.
- **Actividad:**
  - «14 acciones» con la etiqueta «2 nuevas»;
  - barra de progreso verde;
  - lista de eventos con un punto de color, título, detalle gris y fecha a la derecha;
  - enlace «Ver toda la actividad».
- **Por categoría:**
  - lista con un **gráfico de puntos** (dos puntos por fila, recibido y despachado);
  - el número neto a la derecha, en verde o rojo;
  - eje con escala abajo.
- **Ocupación:** filas con nombre, número y porcentaje en una pastilla gris («Parcial 286 · 36 %»).

**Panel completo, sin la ventana encima** (captura que mandó el dueño). Hay 3 filas de tarjetas:

| Fila | Tarjetas |
|---|---|
| 1 | **Valor del inventario** (pequeña) · **Bajo punto de pedido** (pequeña) · **Recibido contra despachado** (grande, ocupa dos filas) |
| 2 | **Esperando aprobación** (pequeña) · **Tasa de aprobación** (pequeña) · *(sigue la grande)* |
| 3 | **Actividad** · **Ocupación de bodega** · **Recibido contra despachado por categoría** (tres medianas) |

- Todas las tarjetas tienen **un menú «⋯»** arriba a la derecha y **un enlace al pie con flecha** («Ver valoración ›», «Ver 38 productos ›», «Ver historial ›»).
- **Bajo punto de pedido:** «38 productos» con la etiqueta roja «-12», el detalle «8 agotados · 30 bajos» y un **mini gráfico de barras** en rojo y gris.
- **Tasa de aprobación:** «84 %» con la variación verde, una **barra de progreso** («Aprobadas contra propuestas · 30 días») y su enlace.
- **Recibido contra despachado** (la grande):
  - número grande («289.640 unidades») con la pastilla verde «+6,8 %»;
  - el detalle debajo;
  - leyenda de 3 colores y selector de periodo;
  - **gráfico de curvas** donde el mes elegido se resalta con **una columna vertical azul** y círculos sobre las curvas.
- **Ocupación de bodega:** un **mapa de panal (hexágonos)** donde cada celda es una ubicación, en azul oscuro, claro o gris según qué tan llena está. Debajo, la leyenda «Llenas 413 · 52 %», «Parcial 286 · 36 %», «Vacías 94 · 12 %».
- **Actividad:** «14 acciones» con «2 nuevas» en naranja, una **barra de progreso de tres colores** (hechas, en curso, esperando revisión), la leyenda con números y la lista de eventos.
- **Por categoría:** gráfico de puntos por fila, recibido en azul oscuro y despachado en claro, con el neto a la derecha en verde o rojo.
- **Encabezado:** la pastilla de estado («8 agentes trabajando», con punto verde) va antes del buscador.

**Detalles que se vieron al revisar el video cuadro por cuadro:**
- **Entrada animada por partes:**
  1. Primero aparece el menú lateral, opción por opción, de arriba abajo, con el contenido vacío.
  2. Luego llegan el título y el encabezado.
  3. Después las tarjetas, una por una, apareciendo desde transparente.
  4. Al final, la ventana Exportar se abre con un acercamiento suave.

  Todo es corto y discreto, no un espectáculo.
- **Los mini gráficos de barras de cada tarjeta resaltan lo reciente:** las últimas barras van en color (azul en Valor del inventario, naranja en Bajo punto de pedido) y las viejas en gris.
- **Las etiquetas junto al número van en color:**
  - verde para lo bueno («+2.3 %», «+3 %»);
  - naranja para el aviso («+5» productos más bajo el punto de pedido, «2 vencen hoy»).
- **Tasa de aprobación:** el gráfico es **de rayas finas, como un código de barras**, con una **marca en la meta** («meta 80 %») y la escala de 0 % a 100 % debajo.
- **Esperando aprobación:** debajo del número va **una fila de cápsulas** (naranja = vencen hoy, azul = después), con su leyenda.
- **Gráfico grande:**
  - **el área entre las dos curvas está rayada**, verde cuando entra más de lo que sale y naranja al revés;
  - eje con valores a la izquierda (40k a 70k) y meses abajo;
  - el mes elegido va en negrita;
  - **tooltip** con la fecha y tres filas, cada una con un cuadrito de color.
- **Ocupación:** el subtítulo dice qué bodega se ve y cuántas ubicaciones tiene («Dallas, TX · 792 ubicaciones»).
- **Por categoría:** al pasar el mouse por una fila, la fila se resalta y **una línea naranja une los dos puntos**, con los valores al lado («6.1k — 7.4k»).
- **Opción activa del menú:** fondo blanco con borde fino, no un color fuerte.
- **El logo** va en un cuadrito oscuro con esquinas redondeadas y el nombre al lado. **El botón de la campana** es un cuadrito con borde.

**Para Stockealo:**
- Esta distribución sirve para el Inicio en el computador:
  - arriba, cuatro tarjetas pequeñas: ventas de hoy, por reponer, fiados por cobrar y caja;
  - a la derecha, el gráfico grande de ventas contra el periodo anterior, con el día o mes resaltado;
  - abajo, la actividad del equipo, lo más vendido y las ventas por categoría.
- El **mapa de hexágonos** podría mostrar el tablero de Servicios (puestos ocupados o libres) o, con sedes, cada sede.
- En el celular, las mismas tarjetas van una debajo de otra.
- **Mini gráficos que resaltan lo reciente:** por ejemplo, ventas de los últimos 14 días con los últimos 3 en color.
- **Barra con meta**, como la de la tasa de aprobación, para la «meta de ventas» del plan (0.15.0).
- **Área entre curvas** para «entró contra salió» (compras contra ventas) en Reportes.
- **Entrada animada por partes** al abrir la app. Corta, y que no se repita en cada cambio de pestaña.

### Ventana «Exportar reporte» (el centro del video)

- **Título** con una línea de contexto («Command Center · datos de hoy a las 08:42») y una ✕ arriba a la derecha.
- **Formato:** 3 tarjetas para elegir, cada una con ícono de archivo, nombre, una línea de explicación y un círculo de selección:
  - PDF: gráficos y resumen;
  - Excel: una hoja por tarjeta;
  - CSV: un archivo por tabla.

  La elegida tiene **borde oscuro y fondo azul muy suave**.
- **Dos selectores lado a lado:** rango de fechas y bodegas.
- **«Incluir»:** lista de casillas en una caja con bordes. Cada fila lleva **el dato real a la derecha** («Valor del inventario · $4,82M», «Bajo punto de pedido · 38 productos»). Arriba a la derecha, el contador «5 de 7 tarjetas». Las desmarcadas se ven en gris.
- **Envío automático:** una cajita gris con «Enviar este reporte cada lunes · a dana@… a las 8:00» y un interruptor.
- **Pie de la ventana:**
  - a la izquierda, **un resumen que cambia en vivo** («Unos 2,4 MB · listo en segundos»);
  - a la derecha, «Cancelar» con borde y el **botón principal oscuro, que cambia de texto según el formato** («Exportar PDF» o «Exportar Excel»).
- **Animación:** al cambiar opciones, el pie y el botón se actualizan en el momento, sin sorpresas («No surprises about what you are sending»).

### Estilo visual

- **Tema claro y limpio:** fondo gris muy claro, tarjetas blancas con borde fino y esquinas redondeadas (unos 12 a 16 px) y **casi sin sombras**.
- **Letra sans moderna** (tipo Inter):
  - títulos en negro;
  - números grandes y en negrita;
  - textos de apoyo en gris.
- **Color con mesura:**
  - casi todo en blanco, gris y negro;
  - el color solo marca estado: verde para lo que sube o va bien, rojo para lo que baja, naranja para lo pendiente, azul y verde azulado en los gráficos.
- **Botón principal negro o azul muy oscuro** y botones secundarios con borde.
- **Mucho aire:** cada tarjeta tiene título pequeño, número grande, detalle y una acción al pie.

### Qué tomar para Stockealo

1. **Barra lateral agrupada por secciones** con títulos pequeños (VENTAS, INVENTARIO, SERVICIOS, COMPRAS, REPORTES), el **selector de negocio arriba** (encaja con sedes) y **la persona con su rol abajo**. Los pendientes llevan un contador (fiados por cobrar, citas de hoy, traslados por recibir).
2. **Encabezado con título y una línea de contexto** («Martes 10 nov · 3 cajas abiertas · actualizado 08:42») y, a la derecha, buscador con atajo, un botón secundario y **un solo botón principal oscuro** («+ Nueva venta»).
3. **Inicio como tarjetas «bento»:**
   - ventas de hoy con su variación;
   - stock bajo con barra segmentada;
   - fiados por cobrar;
   - caja;
   - gráfico de curvas con tooltip;
   - actividad del equipo como lista con puntos de color.

   Cada tarjeta lleva una acción al pie («Ver…»). Esto reemplazaría el Inicio actual.
4. **La ventana de Reportes › Descargar** se parecería a esta:
   - tarjetas para elegir el formato (PDF, Excel, CSV);
   - rango de fechas y sede;
   - casillas con **el dato real al lado**;
   - **envío automático** cada lunes por WhatsApp o correo;
   - pie con el resumen en vivo y el botón que dice «Descargar Excel» o «Descargar PDF».

   Encaja con lo que ya existe en Reportes y con el «cierre del día por WhatsApp» del plan.
5. **Estilo general:** blanco y gris con color solo para estados, pastillas de variación (+3,2 %), números grandes, bordes finos sin sombras y letra tipo Inter. En oscuro se haría la versión equivalente.

### Dudas para el dueño (cuando defina el diseño)

- ¿El diseño nuevo va en **claro por defecto**, como esta referencia, o en oscuro como la de roles? Las dos se pueden tener, pero conviene elegir cuál es la «principal».
- ¿El **botón principal negro** (como aquí) o con el **color del negocio**?

---

## 3. «Diagonal POS»: el día de un comercio en 45 segundos (10 nov 2026)

Fuente: video de Instagram (diagonalsoft, Argentina). Es un **anuncio**: muestra un sistema de ventas, stock y caja contando un día de trabajo, de las 8:30 a las 20:06. Propuesta, no decisión (ver aviso arriba).

### Cómo está contado el video (idea para el marketing de Stockealo)

- **Empieza y termina con una persiana metálica** de local: «¿Hoy te cerró la caja?» con un cartel colgado («Horario: hasta que cierre la caja»). Al final: «Bajás la persiana y te cierran los números».
- **En medio, un escritorio con el monitor y un reloj digital** que avanza (08:30 → 10:15 → 13:40 → 20:06). Cada escena tiene **una frase corta arriba, con la palabra clave resaltada en amarillo**:
  - «Abrís **la caja**»;
  - «Buscás o pasás **el código**»;
  - «Factura electrónica **con ARCA**»;
  - «Te avisa **qué reponer**»;
  - «Le preguntás a **tu negocio**», con IA;
  - «Si tu proveedor cambia los precios, no los cargás **uno por uno**»;
  - «Contás, comparás y **te cierra**»;
  - «Y ves **el día entero**»;
  - «Lo que no está, **lo sumo** para tu comercio».
- **Cierre:** «Decime qué vendés y te lo muestro con tus productos · Escribime por mensaje».
- **Para Stockealo:** un video igual de «un día con Stockealo», con la persiana o la puerta del local, sirve para redes y para la portada. Encaja con «videos cortos de 30 s» de las tareas del dueño.

### Pantallas de la app que se ven

**Marco y menú:**
- **Barra lateral blanca:** arriba, el **logo del negocio con un color e ícono según el tipo** («Tu kiosco» verde, «Tu sanitaria» azul, «Tu ferretería» morado).
- **Menú corto y claro:** Inicio · **Vender** · Ventas · Caja · Productos · Stock · Clientes y proveedores. La opción activa es una **pastilla oscura**.
- **Arriba a la derecha:**
  - el **estado de la caja** como pastilla («● Caja cerrada», con punto amarillo);
  - el avatar;
  - un botón «✨ Asistente IA»;
  - el **botón principal morado «🛒 Nueva venta»**.
- **Etiqueta amarilla «Datos de ejemplo»** arriba: el video usa un **modo demo con productos de prueba**.

**Inicio:**
- Saludo con la fecha arriba: «Martes 3 de noviembre · **Hola, Marta**».
- **3 tarjetas grandes:**
  - la primera, **«Ventas de hoy», en morado lleno** con número blanco y «17 ventas»;
  - las otras blancas: «Ventas de noviembre» y «Ganancia de noviembre», con su explicación: «estimada: ventas menos el costo de lo vendido».
- **Barras de «Ventas de los últimos 14 días»** (por día, sin anuladas), con la etiqueta del día de hoy.
- **«Los 5 más vendidos»** con pestañas Hoy / Noviembre, número de puesto y una barrita.
- **«Alertas de stock bajo»:** cada producto con su código y el **mínimo** («mínimo 10») y una pastilla naranja «Quedan 4».

**Vender (punto de venta):**
- **Buscador grande arriba** («Buscar producto o escanear código») con borde de color.
- **Chips de categoría:** Todas (oscura) · Electricidad · Fijaciones · Herramientas · Pinturería…
- **Cuadrícula de tarjetas de producto:**
  - nombre, código, **precio grande en negrita** y una **pastilla con las unidades** («62 u.»);
  - si queda poco, la pastilla naranja dice «Quedan 5»;
  - si está agotado, la tarjeta se ve gris, con la pastilla roja «Sin stock».
- **Carrito a la derecha:**
  - cada línea con nombre, precio por unidad y código;
  - **botones − y +** para la cantidad;
  - **«Desc.» por línea** y un ícono de basura;
  - abajo: Subtotal, **«Descuento a toda la venta»**, **Total enorme** («$ 9.600») y el **botón morado «Cobrar»** con su atajo de teclado **F9**.
- **Al cobrar, aviso verde abajo:** «✓ Venta registrada · 5 productos · $ 9.600 · Débito».

**Abrir caja:**
- Ventana con ícono, «Abrir caja», la explicación («con el efectivo que tenés para dar vuelto») y el **monto inicial**.
- Ellos **no dejan vender sin caja abierta**. Nosotros decidimos solo avisar, sin bloquear.

**Cierre de caja:**
- «Efectivo esperado $ 86.400» en una caja morada suave.
- Campo «Efectivo contado».
- **Resultado en grande:** «La caja está justa · $ 0», en verde con borde amarillo. Si falta o sobra, sale en otro color.
- Notas opcionales.

**Factura electrónica (en Argentina, ARCA):**
- Ventana «Facturar venta #0016 · Factura C», con «✓ Factura emitida 00001-00000008», la pastilla «Facturada» y los datos: fecha, importe, comprador, CAE y vencimiento.
- Botón «Descargar PDF».
- En Colombia sería la **DIAN** (ya está en «Para después» del plan).

**Asistente con IA:**
- Chat con la pregunta escrita («¿Cuáles son los 5 productos más vendidos…?») y el botón de enviar redondo.
- **La respuesta trae una frase y una TABLA** («Más vendidos», con unidades y ventas) y dice **en qué se basó** («del 1 al 3 de noviembre, ventas netas, sin anuladas»).
- Aviso fijo debajo: «El asistente puede equivocarse: los números salen de tus ventas y tu stock, revisá siempre las tablas».

**Actualizar precios del proveedor de una vez:**
- Lista de productos con casillas, **precio viejo tachado y precio nuevo en verde** al lado. Las filas que cambian se resaltan en verde suave.

### Estilo visual

- Claro, con fondo lila muy suave, tarjetas blancas con esquinas grandes y **un color de marca morado** para lo principal: el botón Cobrar, Nueva venta y la tarjeta de Ventas de hoy.
- Pastillas pequeñas de colores para el estado: naranja «Quedan», rojo «Sin stock», verde «Facturada», amarillo «Caja cerrada».
- Letra redonda y amable, números grandes en negrita.

### Qué tomar para Stockealo

Mucho ya lo tenemos: caja con arqueo, alertas de stock, Stocky con IA, más vendidos y venta rápida. Lo nuevo o mejorable:

1. **Pantalla «Vender» como punto de venta de verdad:**
   - buscador y escáner arriba, chips de categoría;
   - cuadrícula de productos con la pastilla de stock;
   - carrito al lado con − y +, descuento por línea y a toda la venta, total grande;
   - **Cobrar con atajo F9**;
   - aviso «Venta registrada» con el resumen.

   Hoy vendemos en una ventana; en el computador esto sería más rápido.
2. **Actualizar precios de un proveedor de una vez:** subir un % o pegar la lista nueva, ver el precio viejo tachado y el nuevo, y marcar cuáles aplicar. Encaja en Inventario › Proveedores. **Es nuevo y muy útil** para tiendas con inflación.
3. **Respuestas de Stocky con tabla y «en qué me basé»**, más el aviso fijo de que puede equivocarse.
4. **Estado de la caja como pastilla en el encabezado** («● Caja cerrada» o «● Caja abierta desde 8:05»).
5. **Tarjeta principal llena de color** en Inicio (ventas de hoy) y las demás blancas.
6. **Cierre de caja con el resultado en grande:** «La caja está justa», «Faltan $ 2.000» o «Sobran $ 500».
7. **Modo demo con «Datos de ejemplo»** para presentar la app a un interesado (como al dueño del lavadero) sin usar datos reales, y para los videos.
8. **Logo y color por tipo de negocio** cuando no se sube un logo propio (ya tenemos los tipos en `business_identity.dart`).
9. **El video «un día con Stockealo»** para el marketing.

---

## 4. «Lince»: escanear el código del producto sin teclear (10 nov 2026)

Fuente: video de Instagram (moxen.studio, el mismo autor de la matriz de roles). Es una ventana de **«Inventario · Alta de artículo»**, en tema oscuro con acento amarillo. Propuesta, no decisión.

> **Lo que el dueño valora (10 nov):** le gusta **cómo está diseñado lo del código, tanto lo visual como el funcionamiento**. Le parece mejor que lo nuestro en las dos cosas. Para el diseño final, esta referencia es **el modelo para todo lo de escanear o escribir códigos**: crear producto, vender, buscar y entrada de mercancía.

### Cómo funciona (el flujo del video)

1. **Tres formas de leer el código**, en pestañas arriba: **Cámara · Foto · A mano**. En el video se usa «Foto».
2. **Visor con esquinas marcadas** (como el de una cámara) y el texto «Apunta al código · elige un ejemplo, suelta una foto aquí o escribe el código». Se puede **arrastrar una foto** al visor o tocar **«Subir foto»**.
3. Al leer la foto:
   - el código encontrado **se resalta con un recuadro amarillo** y una etiqueta con el formato («EAN-13»);
   - el número **«vuela» al campo «Código del artículo»**;
   - abajo se lee «EAN-13 encontrado: pasando el valor al formulario…».
4. **Los 13 dígitos se muestran en cajitas**, cada una con su peso (×1 o ×3), y **se comprueba el último dígito al instante**:
   - **Si cuadra:** la última cajita se pone en amarillo con ✓, debajo se explica la cuenta («Suma = 105; hasta 110 faltan 5, y el código trae 5: cuadra») y se llenan **Formato: EAN-13** y **Leído con: Lector del navegador**. El botón **«Guardar artículo»** se enciende en amarillo.
   - **Si no cuadra** (un código mal escrito): el campo y la última cajita se ponen en **rojo**, se explica («…el código trae 4: no cuadra») y aparece un botón **«Usar 5»** que **corrige el dígito** con un toque. Mientras no cuadre, Guardar sigue apagado.
5. **Arriba a la derecha, una pastilla** dice con qué se está leyendo: «● Lector del navegador».
6. **Ejemplos para probar:** EAN-13 · QR · Code 128 · EAN erróneo · Subir foto. Es una demo; en una app real no van.
7. Al final, todo vuelve a quedar vacío, listo para el siguiente artículo.

### Estilo

- Tema oscuro casi negro, tarjeta central con borde fino y **un solo color de acento (amarillo)** para lo activo: la pestaña elegida, las esquinas del visor, el código encontrado y el botón Guardar.
- Rojo solo para el error.
- Números en letra de máquina (monoespaciada) dentro de cajitas.
- Una línea gris de ayuda debajo de cada parte, que **cambia según lo que pasa** («Buscando un código en la imagen…», «EAN-13 encontrado…»).

### Qué tiene Stockealo hoy

- Escáner con la cámara del celular (`mobile_scanner`) al crear un producto, al vender y en el buscador de Inventario.

### Qué tomar para Stockealo

1. **Tres formas de leer el código en un solo lugar:** Cámara · **Foto** · A mano. **Leer desde una foto es nuevo:** sirve en la web y en el computador, donde no hay cámara cómoda (foto del producto, captura o archivo arrastrado).
2. **Comprobar el código al instante** (EAN-13, EAN-8 y UPC):
   - si el último dígito no cuadra, avisar en rojo y ofrecer el correcto («¿Quisiste decir …5?»);
   - si cuadra, mostrar el formato.

   Evita productos con el código mal escrito, que luego no se encuentran al vender.
3. **El código «salta» al campo** y el formulario avanza solo al siguiente dato (nombre, precio). Menos toques al crear productos.
4. **Avisar si el código ya existe** en otro producto, antes de guardar. Esto es nuestro, no está en el video.
5. **En el computador, el lector del navegador:** Chrome y Edge pueden leer códigos de una imagen sin nada extra. Junto con el lector USB de la referencia 3, cubre todo.
6. **Una línea de ayuda que cambia según el paso** («Buscando…», «Encontrado», «No cuadra»), en vez de mensajes que salen y se van.

---

## 5. Tienda en línea de ROPA, con «probador» (10 nov 2026)

Fuente: video de Instagram (templatesnextjs), una plantilla de tienda de moda. **Es para la TIENDA EN LÍNEA de cada negocio** (la que ven sus clientes), **no para la app de Stockealo**.

> **Decisión del dueño (10 nov):**
> - **Probador virtual DESCARTADO**, porque cuesta dinero en cada prueba.
> - **Sí le gusta el diseño de la tienda.** La tienda que ofrecemos hoy le parece **muy simple**: el re-diseño debe incluir **la tienda en línea**, no solo la app. Esta referencia es el modelo de cómo debería verse (sin el probador). El dueño la muestra como idea de cómo le gustaría que se viera la tienda de un negocio que vende ropa. Propuesta, no decisión.

### Cómo está hecha

**Encabezado:**
- **A la izquierda, el menú:** INICIO · TIENDA · NOVEDADES · OFERTAS.
- **En el centro, el nombre de la tienda** en mayúsculas con letras espaciadas («S T O R E»).
- **A la derecha:** idioma (bandera + EN), botón de claro u oscuro, buscador, cuenta y **carrito con contador** naranja.

**Portada:** una franja grande con foto de ropa, un título y el botón naranja «Ver colección».

**Catálogo («Novedades · 5 productos»):**
- **Filtros a la izquierda** en una tarjeta:
  - el buscador «Buscar productos…» y «Quitar filtros» en naranja;
  - **CATEGORÍAS con una miniatura de foto por categoría** (Camisetas, Buzos, Chaquetas, Pantalones, Camisas, Zapatos, Gorras). La elegida va resaltada;
  - **RANGO DE PRECIO** con una barra de dos puntas.
- **Orden** arriba a la derecha («Más nuevos»).
- **Tarjetas de producto grandes, fondo oscuro y foto sin fondo** (la prenda «flotando»):
  - arriba a la izquierda, ♡ favorito y un botón de **gancho** (probar);
  - arriba a la derecha, la **calificación** ★ 4.3;
  - abajo, el nombre y el precio. Si está en oferta, el precio va en naranja, con el anterior tachado y la etiqueta «Oferta».
  - **El botón de carrito, al pasar el mouse, se agranda como un cuarto de círculo naranja** desde la esquina. Es un efecto llamativo.

**«Probador» virtual (lo especial):**
- Una pastilla flotante abajo a la izquierda, «Pruébatelo», abre **un panel lateral «Probador»**: «Toca el gancho de cualquier producto para ponértelo».
- Se ve un **maniquí al que se le van poniendo las prendas elegidas, una encima de otra** (abrigo, gorra, pantalón, zapatos). Mientras arma la imagen dice «Vistiendo tu modelo».
- Abajo, «Tus prendas · 5 piezas» con miniaturas que se quitan con ✕, «Agrega otra pieza y va encima» y «Empezar de nuevo».
- **Funciona con IA que genera imágenes.** El video muestra «Tu clave de API»: cada prueba cuesta dinero en un servicio de IA.

### Estilo

- **Oscuro elegante:** fondo casi negro, tarjetas gris oscuro con esquinas muy redondeadas y **un solo color de acento naranja** (botones, ofertas, carrito, filtro elegido).
- Fotos de producto **recortadas sin fondo**, grandes, que son las protagonistas.
- Letra moderna, títulos grandes y mucho espacio.
- Tiene botón de claro u oscuro.

### Qué tiene la tienda de Stockealo hoy

- Catálogo con carrito; los pedidos llegan por WhatsApp; color y logo del negocio (`lib/store_web/store_page.dart`).
- La 0.15.0 del plan ya trae «Personalizar tienda»: portada, color, destacados, secciones por categoría, horario, **modo oscuro** y datos de pago.

### Qué tomar para Stockealo

1. **Plantillas de tienda según lo que vende el negocio:** «Moda» (como esta), «Tienda de barrio», «Servicios»… La de **Moda**: oscura y elegante, fotos grandes, categorías con miniatura, filtros a un lado y precio en oferta en color.
2. **Categorías con miniatura**, tomada de un producto de esa categoría.
3. **Filtros:** buscador, categoría, **rango de precio**, y para ropa también **talla y color** (ya tenemos tallas y colores por producto).
4. **Tarjeta de producto con:**
   - favorito;
   - el precio de oferta en color, con el anterior tachado y la etiqueta «Oferta» (encaja con «Ofertas» de la 0.16.0);
   - el botón de carrito con un efecto llamativo.
5. **Quitar el fondo de la foto del producto** para que la prenda «flote». Puede hacerse al subir la foto, con un servicio que quite el fondo. Hay que revisar cuánto cuesta.
6. ~~**Probador virtual con IA**~~ **DESCARTADO por el dueño.** Era muy llamativo, pero **cada prueba cuesta** (genera imágenes con IA de pago). Si entra, sería **solo Pro**, con un límite de pruebas al mes, y **para después**. Una versión más sencilla y sin costo sería ver el producto puesto en una foto de modelo que suba el negocio.
7. **Carrito con contador y botón de claro u oscuro** para el visitante (ya está en el plan de la tienda).

---

## 6. Comprobante que «se imprime» y se comparte como imagen (10 nov 2026)

Fuente: captura que mandó el dueño (un recibo de carga de un carro eléctrico, «VOLTRA»). Propuesta, no decisión. **Le gusta el diseño y la animación de que el comprobante «se imprime».** Además, quiere usarlo **en la tienda en línea, para el pedido** (que todavía no es una venta).

### Cómo está hecho

- **Arriba, fuera del papel:** «Tu recibo · $19.01 pagado con tarjeta débito».
- **Una ranura de impresora** (una barra con un puntito de luz) de donde **sale el papel hacia abajo**, como una impresora de tiquetes. Esa es la animación.
- **El papel:**
  - blanco, con el **borde de abajo en zigzag** (papel cortado);
  - **letra de máquina** (monoespaciada), alineada en dos columnas: etiqueta a la izquierda y valor a la derecha;
  - **nombre del negocio grande y espaciado** («V O L T R A») y debajo qué es («RECIBO DE CARGA»);
  - **bloques separados por líneas punteadas:** datos del recibo (número, fecha, estación); lo que se compró (cantidades, duración, tarifa); el detalle del cobro (valor, cargo de servicio, impuesto);
  - **TOTAL en grande**;
  - **un sello azul redondo, «PAID» (pagado) con la fecha, puesto un poco torcido**, como un sello de tinta real;
  - forma de pago («MASTERCARD •••• 7310») y estado («APROBADO»);
  - un **código de barras** con el número del recibo debajo;
  - un mensaje de despedida en cursiva («Gracias por cargar con Voltra»).
- **Estilo:** fondo oscuro detrás para que el papel resalte; todo el papel en negro sobre blanco y **un solo color, el del sello**.

### Qué tiene Stockealo hoy

- `lib/features/sales/presentation/widgets/sale_document.dart`: el comprobante de venta y la cotización (`SaleDocumentCard`). **Ya se comparte como imagen** (se toma una foto de la tarjeta y se manda con `share_plus`) y, si no se puede, como texto. También existe `digital_ticket_modal.dart`.
- Hay otros comprobantes por WhatsApp en **texto**: cierre de caja, liquidación de comisiones, mensajes de Servicios y pedidos de la tienda.

### Qué tomar para Stockealo

1. **Un solo diseño de «tiquete de papel» para todos los comprobantes,** con el contenido que cambia:

   | Comprobante | Sello | Dónde se usa |
   |---|---|---|
   | Venta | **PAGADO** (verde o el color del negocio) | Vender, Ventas |
   | Venta fiada | **FIADO** (naranja), con lo que queda debiendo | Vender |
   | Abono a un fiado | **ABONO** con el saldo que queda | Clientes |
   | Venta anulada | **ANULADA** (rojo) | Ventas |
   | Cotización | **COTIZACIÓN · válida hasta…** | Ventas › Cotizaciones |
   | Cierre de caja | **CAJA JUSTA**, **FALTAN $…** o **SOBRAN $…** | Caja |
   | Liquidación de comisiones | **LIQUIDADO** | Servicios |
   | Orden de servicio | Estado del trabajo («LISTO PARA RECOGER») | Servicios |
   | **Pedido de la tienda en línea** | **PEDIDO RECIBIDO**, o **POR CONFIRMAR** (todavía no es venta) | Tienda en línea |

2. **Animación de «impresión»:** el papel sale de la ranura de arriba hacia abajo al terminar la venta o al hacer el pedido. Debe ser corta (menos de 1 segundo) y saltarse si la persona prefiere menos movimiento.
3. **Compartir como imagen por WhatsApp** (ya existe en ventas; se extiende a todos). Con «Copiar como texto» para quien lo prefiera.
4. **En la tienda en línea:** al confirmar un pedido, al cliente le sale su **tiquete de pedido** (número, productos, total, sede para recoger, «Por confirmar») con el botón **«Enviar por WhatsApp»**, que lo manda al negocio **como imagen**, además del texto actual. Así el negocio recibe algo claro y bonito.
5. **Código de barras o QR con el número** del comprobante. Al escanearlo en Stockealo se abre la venta o el pedido (encaja con la referencia 4, escanear).
6. **Datos del negocio arriba** (nombre, logo, NIT, dirección y teléfono si los tiene) y **mensaje de despedida propio** que el negocio escribe («¡Gracias por tu compra!»).
7. **Tamaño de imagen pensado para WhatsApp:** angosto y largo como un tiquete real, legible en el celular.

---

## 7. «Transom»: de la alerta al problema resuelto (11 nov 2026)

Fuente: video de Instagram (ui.iliasmiah000, el mismo autor del «Command Center»). Es un panel para clínicas y el video muestra **una cita doble**: dos pacientes a las 11:00, a 14 minutos de empezar. Propuesta, no decisión.

La idea central, en palabras del autor: **«Una alerta solo sirve si termina con el problema resuelto».**

### El panel (Inicio)

- Saludo con la fecha y un resumen en una línea: «Buenos días, Rachel · martes 27 de octubre · 48 citas en 4 departamentos, 17 terminadas, **4 cosas necesitan atención**».
- Arriba, pestañas **Hoy · Semana · Mes** y «Exportar reporte».
- **4 tarjetas de cifras** (citas de hoy, esperando ahora, notas sin firmar, saldo pendiente). Cada una con su variación en color («↘ −3 min», «↗ +2») y un **mini gráfico de puntos** (una cuadrícula de puntitos de colores, en vez de barras).
- Gráfico de **citas por hora** con barras apiladas por estado (terminadas, en consulta, esperando, no vino) y una **línea de «ahora 10:42»**.
- **«Necesita atención · lo más riesgoso primero»:** lista de problemas con ícono, título, detalle y una **pastilla de estado** (Vencido, Conflicto, Sin firmar, Demora). Al resolverse, el ítem pasa a verde («Cita doble resuelta · Layla movida a las 11:30»).
- Abajo: carga por persona (barras), saldos por antigüedad (dona con el total en el centro) y **actividad en vivo**, con la foto de la persona y lo que pasó.

### El flujo para resolver la alerta

1. Se toca «Cita doble a las 11:00 · Conflicto» y se abre un **panel lateral**:
   - **título** con el ícono y quién está involucrado;
   - **pastillas:** Alta prioridad · «Empieza en 14 min» · Sin asignar.
2. **Se ve el problema dibujado:** la mañana del doctor como una línea de tiempo (10:00, 10:30, 11:00…). **Las dos citas de las 11:00 en rojo** con la etiqueta «Cruce», y **el espacio libre de las 11:30 con borde punteado** («Libre · 30 min»).
3. **«Por qué pasó»:** la reserva en línea mostró las 11:00 libres mientras alguien movía otra cita por teléfono.
4. **«Si nadie hace nada»:** uno de los dos espera unos 50 minutos y el doctor se atrasa.
5. **«Solución sugerida»** en una tarjeta destacada, con la etiqueta «Mejor opción»: «Mover a Layla a las 11:30, mismo doctor, y Grace conserva su hora».
6. **«Evitar que se repita»:** «Bloquear el espacio mientras alguien mueve una cita por teléfono», con el botón «Sugerir esta regla».
7. **Botones:** «Asignar a Maya» (que lo resuelva otra persona) o **«Resolver ahora»**.
8. Al resolver:
   - **ANTES y DESPUÉS lado a lado** (11:00 Grace, 11:00 Layla → 11:00 Grace, 11:30 Layla);
   - **cómo avisarle:** Mensaje · Llamada · Portal;
   - **el mensaje ya escrito** para Layla, con disculpa y la nueva hora, para responder SÍ;
   - **dos interruptores:** «Guardar las 11:30 para Layla por 15 min» y «Si no responde en 15 min, llamarla» (crea una tarea);
   - **el efecto:** el atraso del doctor pasa de 22 a unos 8 minutos;
   - **queda registrado** quién hizo qué.
9. **Un solo «Enviar»:** sale el aviso «Cita doble resuelta» y el panel se actualiza solo.

### Estilo

- Claro y limpio, como el Command Center: tarjetas blancas, bordes finos y colores solo para los estados (rojo conflicto, naranja demora, verde resuelto, morado y azul en los gráficos).
- Fotos pequeñas de las personas en las listas.
- **Mini gráficos de puntos** en vez de barras.
- Panel lateral que se abre sobre el Inicio, sin cambiar de pantalla.

### Qué tomar para Stockealo

1. **«Necesita atención», lo más urgente primero,** en Inicio. Una sola lista con todo lo que hay que resolver hoy, cada cosa con su pastilla:
   - **Agotados** («Cinta aisladora: 0, la vendiste 8 veces esta semana»);
   - **Fiados vencidos** («Juan debe $45.000 hace 30 días»);
   - **Caja sin cerrar** de ayer;
   - **Citas cruzadas** o un empleado que no vino y tiene citas;
   - **Traslados por recibir** (sedes);
   - **Pedidos de la tienda por confirmar**.

   Hoy estos avisos están repartidos entre la campana, tarjetas de Inicio y cada módulo.
2. **Cada alerta abre un panel con la solución, no solo el aviso:** qué pasa, por qué, qué pasa si nadie hace nada, **la solución sugerida** y un botón para hacerla. Ejemplos:
   - **Agotado:** «Pedir 20 al proveedor X» con el mensaje de WhatsApp ya escrito.
   - **Fiado vencido:** «Cobrar por WhatsApp» con el mensaje listo.
   - **Cita cruzada:** «Mover a las 11:30 con el mismo barbero» y avisar al cliente.
3. **Para las citas de Pro Servicios** (reservas en línea, 0.13.0), este flujo es casi exacto:
   - la agenda dibujada con los cruces en rojo y los espacios libres punteados;
   - la sugerencia de mover;
   - el mensaje al cliente ya escrito;
   - **guardar el espacio unos minutos** mientras el cliente responde.
4. **Antes y después** cuando se cambia algo importante (mover una cita, cambiar precios), para que no haya sorpresas.
5. **«Asignar a…» una persona del equipo** para que resuelva un pendiente. Encaja con los roles.
6. **Mini gráficos de puntos** como otra opción para las tarjetas de Inicio.
7. **Actividad en vivo con la foto o inicial de cada persona** (ya existe Actividad del equipo; se vería en Inicio).
