# Plan: tienda, pedidos, «por entregar» y modo sin conexión

**Fecha:** 14 nov 2026.
**Origen:** anotaciones del dueño después de la 0.13.2.
**Estado:** PLAN, sin aprobar. No se toca código hasta aprobarlo.

## Lo que hay hoy

- **Portada de la tienda:** la plantilla pone un banner de 1 producto con «Ver la colección» que ocupa toda la pantalla, y hay que bajar mucho para ver los productos.
- **Botones arriba:** «Inicio» y «Tienda» llevan a la misma página y no se leen bien.
- **Existencias:** «N disponibles» solo sale si el negocio activa «Mostrar existencias», que está apagado por defecto.
- **Talla y color:** la opción elegida se ve como una tarjeta blanca, sin marcar.
- **Nombre del cliente:** es opcional.
- **El pedido de la tienda NO se guarda en ningún lado.**
  - El cliente ve el tiquete «Por confirmar».
  - Al negocio le llega solo el WhatsApp, sin número de pedido.
  - En la app no aparece.
- **Venta pagada sin entregar:** al registrar la venta el stock se descuenta, pero la app no sabe que falta entregar el producto.
- **Sin conexión:**
  - La venta se guarda en el aparato y entra a la cola `pending_sync`. Se envía en orden cuando vuelve la conexión.
  - **Faltan tres cosas:**
    1. La venta no muestra que está pendiente de subir.
    2. No hay aviso general de «sin conexión».
    3. Tras 20 intentos fallidos la operación **se descarta de la cola**. El dato sigue en el aparato, pero no sube solo: hay que usar la sincronización manual.

## Fases propuestas

### Fase A · Arreglos rápidos de la tienda (0.13.3) — HECHA en código el 14 nov (rama feat/0.13.3, sin commit). Migración `20261130000000_store_stock_hints.sql` APLICADA en la nube (14 nov). Ojo: la tienda publicada (0.13.2) muestra las tallas agotadas como elegibles hasta publicar la 0.13.3

1. **Portada baja:** una franja con el título, una foto pequeña y el buscador. Los productos quedan a la vista sin bajar, también en el celular.
2. **Barra de arriba:** se quitan «Inicio» y «Tienda». Quedan el nombre del negocio, el buscador y el carrito.
3. **Existencias:**
   - Con «Mostrar existencias» encendido: «N disponibles».
   - Apagado: solo «Quedan pocos» o «Agotado».
   - La talla o el color elegido se marca con el color del negocio.
5. **Carrito como en las tiendas grandes** (pedido del dueño, 14 nov), HECHO: en el computador, panel a la derecha (`AppSidePanel`); en el celular, página completa con el total y «Hacer el pedido» fijos abajo. Toma el tema de la plantilla.
4. **Nombre obligatorio** para hacer el pedido. El celular es opcional, pero se recomienda.

Solo cambia la tienda (`lib/store_web/store_page.dart`). No hay cambios en la nube.

### Fase B · Modo sin conexión visible y sin pérdidas (0.13.3 o 0.13.4)

1. **Aviso arriba** de «Sin conexión»: «Tus ventas se guardan y se suben solas al volver».
2. **Cada venta muestra su estado** en Ventas y en el tiquete:
   - «Pendiente de subir», con un ícono de nube tachada, mientras está en la cola;
   - «Guardada» cuando sube.
3. **Al recuperar la conexión** se envía la cola sola. Hoy se envía al hacer cambios y cada cierto tiempo.
4. **No se descarta nada:** después de muchos intentos fallidos, la operación queda marcada «con error» y se avisa en Ajustes › Sincronización, con «Reintentar». No se borra de la cola.
5. **Pruebas:** venta sin conexión, aparece pendiente, vuelve la conexión, sube y queda «Guardada».

### Fase C · Pedido de la tienda como cotización con código (0.14.x / 0.16.0)

1. **El cliente hace el pedido** y se guarda en la nube con un código corto por negocio, por ejemplo **T-0012**.
   - Lo hace una función pública segura: el cliente no tiene cuenta y solo puede crear su pedido.
2. **El código va en el tiquete y en el WhatsApp:** «Hola, soy Ana. Pedido **T-0012**: …».
3. **En la app:**
   - aparece en **Ventas › Cotizaciones** con la marca «Tienda»;
   - Inicio muestra «Pedido de la tienda por confirmar».
4. **El negocio la pasa a venta** con un toque, igual que cualquier cotización, o la rechaza.

Necesita una migración en la nube, que no se aplica sin permiso.

### Fase D · Venta «Por entregar» (con la Fase C)

1. **Al cobrar** se puede marcar «Por entregar», o «Apartado» si el cliente pagó una parte. El stock se descuenta igual.
2. **Ventas › Por entregar:** la lista de lo pendiente. En Inicio sale «N pedidos por entregar» en «Necesita atención».
3. **«Entregado»** con un toque, que guarda la fecha y quién lo entregó.
4. **Pedidos de la tienda:** el que se cobra pasa directo a «Por entregar».

### Fase E · Promociones y descuentos (pedido del dueño, 14 nov)

**Para TODOS los planes.** Con Pro se ve más vistoso en la tienda en línea y en los catálogos.

1. **Crear una promoción:** nombre, fechas de inicio y fin, y a qué aplica: productos marcados, una categoría o todo.
2. **Tipos:**
   - **% de descuento**, por ejemplo 20 %;
   - **lleva X, paga Y**, por ejemplo 2×1 o 3×2.
3. **Vender:** la aplica sola al agregar el producto. El 2×1 se aplica cuando se completa la cantidad. El tiquete muestra «Promo Black Friday −$5.000».
4. **Se apaga sola** al terminar las fechas. Los precios normales no se tocan.
5. **Reportes:** cuánto se vendió y cuánto se descontó con cada promoción.
6. **Con Pro, más vistoso:**
   - **Tienda en línea:** cinta «−20 %» o «2×1» en la foto, precio tachado y una franja arriba: «Black Friday · termina en 3 días».
   - **Catálogos** (PDF e historias): la misma cinta y el precio tachado.
7. **Nube:** una tabla nueva de promociones, con su sincronización, y la tienda pública la recibe. Es una migración que no se aplica sin permiso.
8. **El «Precio de antes» actual se queda** para ofertas sueltas.

## Orden recomendado

1. **A, en la 0.13.3:** la tienda (lista para publicar).
2. **B, en la 0.13.4:** sin conexión. Perder ventas es lo más grave.
3. **E, en la 0.13.5:** promociones. Va antes de los pedidos para que el pedido de la tienda ya guarde el precio con la promoción.
4. **C y D juntas, en la 0.13.6:** pedido de la tienda como cotización con código, y «Por entregar».

## Decisiones del dueño (14 nov)

1. **Código del pedido:** contador por negocio, sin fecha: **T-0001, T-0002…** (CONFIRMADO).
2. **Existencias, como Nike (CONFIRMADO):**
   - **Agotado:** la talla o el color se ve **tachado** y no se puede elegir. Si todo el producto está agotado: «Agotado».
   - **Pocas, 3 o menos:** «Quedan pocas, pide pronto». No se dice el número.
   - **Hay de sobra:** no se dice nada.
   - Con «Mostrar existencias» encendido, además «N disponibles».
3. **«Por entregar» solo para pedidos.** Cada pedido (cotización) guarda **de dónde vino**:
   - **En el local**, es decir, una cotización hecha en Vender.
   - **WhatsApp**: el negocio la crea a mano y marca «WhatsApp».
   - **Tienda en línea**: se marca sola.

   Al cobrar un pedido, la app pregunta **«¿Cómo se entrega?»**:
   - **Ya se lo llevó:** queda entregado.
   - **Lo recoge después:** pasa a «Por entregar».
   - **Envío:** pasa a «Por entregar», con la dirección.

   Las ventas normales de mostrador no preguntan nada.
4. **Pedido sin confirmar:** se vence a los **7 días** y queda como «Vencido», sin borrarse.
