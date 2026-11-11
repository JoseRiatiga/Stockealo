# Propuesta de flujo: que Stockealo se use «de corrido»

> **Estado:** propuesta, **sin aprobar**. **Forma parte del plan de RE-DISEÑO completo (`docs/plan-rediseno.md`).** Respuestas del dueño del 10 nov en la sección 9. Solo es un plan: no se toca código.
> Pedido del dueño el 10 nov 2026, después de ver el video de «Diagonal POS» (referencia 3 en `docs/referencias-diseno.md`): «lo veo más fluido e intuitivo, y algunas cosas de lo nuestro suelen ser un poco perdidas».
> Va junto con el diseño final: el **flujo** (qué se hace y en qué orden) se decide aquí, y el **aspecto**, en el diseño final.

## 1. Por qué la otra app se siente fluida

Su menú sigue **el día del negocio, en orden**, y cada opción es **una tarea con nombre de verbo o de cosa concreta**:

> Abrir caja → **Vender** → (se repite todo el día) → ver qué reponer → preguntar → actualizar precios → **cerrar caja** → ver el día.

1. **«Vender» es un lugar, no un botón.** Es la segunda opción del menú y abre una pantalla completa:
   - los productos ya están a la vista en cuadrícula, con su stock;
   - el carrito está siempre al lado;
   - se toca un producto o se escanea y entra al carrito;
   - se cobra con un botón (o F9) y la pantalla **queda lista para la siguiente venta**.
2. **La caja se ve siempre** como pastilla en el encabezado («● Caja cerrada»). Abrirla es lo primero del día y cerrarla lo último. También es una opción del menú.
3. **Cada opción del menú hace una sola cosa:** Ventas es el historial, Productos es el catálogo, Stock es lo que hay y lo que falta, Clientes y proveedores es la gente.
4. **Lo importante del día está en Inicio,** con acciones directas: alertas con «Quedan 4», los más vendidos y las ventas por día.
5. **Pocos pasos y sin ventanas encima de ventanas.** Cada acción termina con un aviso claro («Venta registrada · 5 productos · $9.600 · Débito»).

## 2. Dónde Stockealo se siente «perdido» hoy

Revisado en el código el 10 nov:

| Hoy en Stockealo | Por qué cuesta |
|---|---|
| **Vender no es un lugar.** Hay que ir a la pestaña Ventas y tocar «Nueva venta», que abre una **ventana encima** | La acción más usada del día queda escondida dentro del historial |
| La ventana de venta **empieza vacía** («Selecciona productos para comenzar»). Hay que tocar «Agregar producto», buscar, elegir y volver | No se ven los productos. Son 3 o 4 toques por producto en vez de 1 |
| Al cobrar, **la ventana se cierra** | Para la siguiente venta hay que volver a abrirla |
| La pestaña **Ventas mezcla** el historial, Nueva venta, Clientes y fiados, Cotizaciones y Caja | «Ventas» quiere decir dos cosas: vender y ver lo vendido |
| La **Caja** está dentro de Ventas › Caja. Su estado se ve solo en una tarjeta de Inicio | No es obvio que el día empieza abriendo la caja |
| La pestaña **Inventario mezcla** productos, catálogo, tienda en línea, proveedores e importar | Reponer, editar productos y vender en línea quedan revueltos |
| **Clientes** está dentro de Ventas y **Proveedores** dentro de Inventario | Las personas con las que se trata están en dos lugares distintos |
| Muchas cosas se abren como **ventanas o hojas que suben** encima de la pantalla | Se pierde de vista dónde se está y cómo volver |

## 3. Propuesta: el menú sigue el día

### Menú en el computador (barra lateral)

1. **Inicio:** el resumen del día, con acciones directas (ver sección 5).
2. **Vender:** el punto de venta (sección 4).
3. **Ventas:** solo el historial, con anular, devolver, reimprimir y cotizaciones.
4. **Caja:** abrir, movimientos, cerrar e historial de cierres.
5. **Servicios** (si tiene Pro Servicios): tablero y citas.
6. **Productos:** el catálogo (crear, editar, categorías, tallas y colores, importar Excel).
7. **Stock:** lo que hay y lo que falta. Alertas, reponer, entradas de mercancía, conteo y traslados (sedes).
8. **Clientes y proveedores:** las personas. Fiados y abonos de clientes, proveedores, pedidos y cuentas por pagar.
9. **Tienda en línea** (Pro): pedidos y personalización.
10. **Reportes.**
11. **Ajustes**, abajo del todo, junto a la persona y su rol.

Arriba, en el encabezado y siempre visibles:
- el negocio o la sede;
- la **pastilla de la caja** («● Caja abierta desde 8:05» o «● Caja cerrada»);
- el buscador;
- la campana;
- el botón principal **«Nueva venta»**, que lleva a Vender.

### Menú en el celular (barra inferior, máximo 5)

**Inicio · Vender · Ventas · Productos · Más**

- **«Más»** abre: Caja, Stock, Clientes y proveedores, Servicios, Tienda, Reportes y Ajustes.
- **Vender queda en el centro y resaltado,** porque es lo que más se toca.
- Con Pro Servicios: **Inicio · Vender · Servicios · Ventas · Más**.

### Sigue valiendo «nada duplicado»

Cada función sigue teniendo un solo lugar. Solo cambia **cuál** es ese lugar: Vender sale de Ventas, Caja sale de Ventas, y Proveedores pasa a estar junto a Clientes. Los accesos rápidos de Inicio, el buscador y Stocky siguen llevando a ese único lugar.

## 4. «Vender» como punto de venta

**En el computador (pantalla completa):**
- **A la izquierda:**
  - el buscador grande, con el cursor ya puesto: se escribe o se pasa el lector de código de barras (USB) y **el producto entra al carrito solo**;
  - debajo, chips de categoría (Todas · Bebidas · Aseo…) y la **cuadrícula de productos** con precio y pastilla de stock («62 u.», «Quedan 5», «Sin stock»);
  - un toque y el producto entra al carrito. Si tiene tallas o colores, primero pregunta cuál.
- **A la derecha, el carrito siempre visible:**
  - cada línea con − y +, «Desc.» y la basura;
  - abajo: Subtotal, Descuento a toda la venta, cliente (opcional, obligatorio si es fiado) y el **Total en grande**;
  - **«Cobrar» (F9)** abre la forma de pago: Efectivo (con el vuelto), Nequi, Transferencia, Tarjeta, Fiado y Mixto.
- **Al cobrar:** aviso «✓ Venta registrada · 5 productos · $9.600 · Efectivo», con «Enviar recibo por WhatsApp», y **el carrito queda vacío y listo** para la siguiente venta.
- **Teclado:** F9 cobrar · Esc vaciar · flechas y Enter para elegir del buscador · F2 buscador.

**En el celular:**
- Arriba, el buscador y el botón de **cámara para escanear**; debajo, chips y una lista de productos grande y fácil de tocar.
- El carrito es una **barra fija abajo**, «3 productos · $9.600 · Cobrar». Al tocarla sube el detalle.
- Después de cobrar, se queda en Vender.

**Otras cosas de Vender:**
- **«Guardar para después»:** dejar una venta en espera (un cliente que fue por algo) y atender a otro. Las ventas en espera se ven como pestañas.
- **Cotizar** pasa a ser un botón dentro de Vender, y la cotización queda en Ventas › Cotizaciones.
- **Venta de servicios:** con Pro Servicios, los servicios también salen en la cuadrícula. El tablero sigue en Servicios.

## 5. El día, de principio a fin

| Momento | Qué ve y qué hace la persona |
|---|---|
| Abre la app | **Inicio**: «Hola, Marta · martes 3 de noviembre». Si el negocio usa caja y está cerrada, la primera tarjeta dice «**Abre la caja para empezar** · [Abrir caja]» |
| Abre la caja | Escribe con cuánto efectivo empieza. La pastilla del encabezado pasa a «● Caja abierta desde 8:05» |
| Vende todo el día | **Vender**: tocar o escanear, cobrar y seguir. Sin cerrar ni volver a abrir ventanas |
| Algo se acaba | Aviso en la campana y en Inicio: «Quedan 4 · Cinta aisladora» con «**Pedir al proveedor**», que lleva a Stock › Reponer con el pedido armado |
| Llega la mercancía | **Stock › Entradas**: recibir el pedido y sumar las unidades |
| El proveedor cambia precios | **Clientes y proveedores › el proveedor › Actualizar precios**: subir un % o pegar la lista nueva, ver el precio viejo tachado y el nuevo, marcar y aplicar |
| Quiere saber algo | **Stocky**: «¿qué fue lo más vendido esta semana?». Responde con una tabla y dice en qué se basó |
| Cierra | La pastilla del encabezado o **Caja › Cerrar caja**: efectivo esperado, contado y el resultado en grande («La caja está justa», «Faltan $2.000») |
| Al final | **Inicio** muestra el día completo y el **cierre del día por WhatsApp** (del plan) |

## 6. Ideas que salieron del video y van con este flujo

1. **Actualizar precios de un proveedor de una vez.** Nuevo y muy útil con la inflación.
2. **Modo demo con «Datos de ejemplo»**, para presentar la app sin datos reales.
3. **Lector de código de barras USB en el computador:** escanear agrega directo al carrito.
4. **Stocky responde con tablas** y dice en qué se basó.
5. **«Guardar para después»** en Vender.

## 7. Cómo encaja con el plan

- **No cambia lo que hace la app, cambia dónde está y cuántos pasos toma.** Por eso conviene hacerlo **junto con el diseño final**, para no reorganizar dos veces.
- Toca el mapa de «nada duplicado» aprobado en la 0.12.0 (`docs/plan-0.12.0.md`, sección 7b). Ese mapa se actualiza con este, y la hoja «Dónde quedó cada cosa» se vuelve a mostrar con los cambios.
- La pantalla Vender nueva **le sirve también a Pro Servicios** (cobrar servicios y productos juntos) y a las sedes (la caja por sede).

## 8. Preguntas para el dueño

1. ¿Te gusta el **menú que sigue el día** (Inicio · Vender · Ventas · Caja · Servicios · Productos · Stock · Clientes y proveedores · Tienda · Reportes · Ajustes)?
2. En el celular, ¿**Inicio · Vender · Ventas · Productos · Más** está bien, con Vender al centro?
3. ¿Se hace **junto con el diseño final** (recomendado), o la pantalla Vender se adelanta porque es lo más usado?
4. Si el negocio usa caja, ¿**Vender pide abrir la caja primero** (como la otra app) o **solo avisa** (como hoy)?
5. De las ideas de la sección 6, ¿cuáles entran y en qué actualización?

## 9. Respuestas del dueño (10 nov)

1. **Sí, el menú actual se siente perdido.** Se rehace siguiendo el día.
2. **En el celular, menú lateral como en la web**, en vez de la barra inferior (reemplaza la sección 3, «Menú en el celular»).
3. **Va junto con el diseño final.**
4. **Si el negocio usa caja, hay que abrirla antes de vender.** Si no está abierta, se avisa que la abra primero, con «Abrir caja» ahí mismo.
5. **Modo demo: no.** **Stocky con tablas: sí, y hay que planearlo bien** (`plan-rediseno.md`, sección 5). Las demás ideas (precios del proveedor, lector USB y ventas en espera) siguen sin decidir.
6. **Todo esto va en un solo plan de RE-DISEÑO completo:** `docs/plan-rediseno.md`.

