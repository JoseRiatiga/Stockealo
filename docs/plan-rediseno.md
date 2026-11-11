# Plan de RE-DISEÑO completo de Stockealo

> **Estado:** **diseño final APROBADO (11 nov 2026).** Falta decidir en qué actualización se construye (sección 7). Solo es un plan: no se toca código.
> **Decisión del dueño (10 nov 2026):** todo lo de diseño y flujo va en **un solo plan de re-diseño completo de la app**. Este documento lo reúne. Los detalles siguen en:
> - `docs/referencias-diseno.md`: los diseños **propuestos** (videos de Instagram) y qué se toma de cada uno;
> - `docs/propuesta-flujo.md`: el análisis del flujo y la propuesta de menú y de «Vender»;
> - `docs/plan-roles.md`, sección 8: cómo funciona la pantalla de roles (su aspecto se decide aquí).
>
> Las referencias son propuestas. Al terminar de recogerlas se arma **un diseño final** y el dueño lo aprueba antes de programar.

## 1. Por qué

- El dueño siente que **el menú y el flujo de Stockealo «se suelen sentir perdidos»**. Le gustan apps donde el menú sigue el día del negocio y cada pantalla hace una sola cosa.
- El diseño V1 se va a reemplazar. Mientras tanto, **no se hacen pantallas nuevas grandes con V1** sin preguntar.

## 2. Decisiones tomadas (10 nov)

1. **El menú actual se siente perdido:** se rehace siguiendo el día del negocio (propuesta en `propuesta-flujo.md`, sección 3).
2. **En el celular, menú lateral** (barra que se abre desde el costado), **igual que en la web**, para que no haya diferencias que confundan. Reemplaza la barra inferior de 5 pestañas.
3. **El flujo nuevo va junto con el diseño final**, no por adelantado.
4. **Caja obligatoria si el negocio la usa:**
   - si la caja está cerrada, **no se puede vender**;
   - la app avisa que hay que abrirla primero y ofrece «Abrir caja» ahí mismo;
   - si el negocio no usa caja, se vende normal.
5. **Modo demo con datos de ejemplo: NO.**
6. **Stocky con tablas y «en qué me basé»: SÍ**, pero hay que **planearlo bien** (sección 5).
7. **Todo lo de diseño y flujo va en este único plan.**

## 2b. Decisiones del diseño final (11 nov)

- **El dueño terminó de mostrar las referencias** (7 en total, ver `referencias-diseno.md`). Ahora se arma **un diseño final**.
- **Tema principal: CLARO.** El oscuro existe completo y se cambia con el botón de sol o luna.
- **Color de lo activo: EL COLOR DE CADA NEGOCIO** (botón principal, Cobrar, opción elegida del menú). El resto en blanco, gris y negro, y el color solo para los estados.
- **Entrega para aprobar:** una página interactiva con el sistema de diseño y las pantallas clave, en celular y computador, en claro y oscuro.

**Diseño final APROBADO por el dueño el 11 nov 2026:** https://claude.ai/artifact/JQtmF7vnoWhwMBujRAMitb

Tiene 4 páginas:
1. **Sistema de diseño:** reglas, colores claro y oscuro, color del negocio, estados, letra, piezas y movimiento.
2. **Computador:** menú lateral, Inicio, Vender (interactiva), Necesita atención → resolver, Roles y permisos (interactiva) y Leer el código.
3. **Celular:** Inicio, menú lateral, Caja cerrada, Vender, comprobante que se imprime (interactivo) e Inicio en oscuro.
4. **Tienda en línea:** plantilla Moda.

## 3. Lo que abarca el re-diseño

| Parte | Qué incluye | Dónde está el detalle |
|---|---|---|
| **Menú y navegación** | Menú que sigue el día. Lateral en la web y en el celular. Encabezado con el negocio o la sede, la pastilla de la caja, el buscador, la campana y «Nueva venta» | `propuesta-flujo.md`, sección 3 |
| **Vender** | Punto de venta: cuadrícula, carrito fijo, escáner y lector USB, F9, se queda lista para la siguiente venta, ventas en espera | `propuesta-flujo.md`, sección 4 |
| **Caja** | Lugar propio en el menú, obligatoria si se usa, cierre con el resultado en grande | Decisión 4 y `propuesta-flujo.md`, sección 5 |
| **Inicio** | Tarjetas tipo «bento» con acciones directas, la tarjeta del día resaltada, mini gráficos y alertas con «Quedan N» | `referencias-diseno.md` (2 y 3) |
| **Stock, Productos, Clientes y proveedores** | Separados por tarea (catálogo, lo que hay y lo que falta, las personas) | `propuesta-flujo.md`, sección 3 |
| **Reportes › Descargar** | Ventana de exportar con formato, rango, casillas con el dato al lado y envío automático | `referencias-diseno.md` (2) |
| **Roles y permisos** | Matriz con interruptores (cómo funciona, ya aprobado) | `plan-roles.md`, sección 8 |
| **Stocky** | Respuestas con tablas y en qué se basó | Sección 5 |
| **Estilo visual** | Colores, letra, tarjetas, pastillas de estado, animaciones cortas, claro y oscuro | Se define en el diseño final |
| **Tienda en línea de cada negocio** | El dueño la ve «muy simple». Va dentro del re-diseño: plantillas según lo que vende el negocio (la de Moda como la referencia 5), categorías con miniatura, filtros (precio, talla, color), tarjetas grandes con oferta y foto protagonista. Sin probador virtual (descartado por costo) | `referencias-diseno.md` (5) |
| **Comprobantes** | Un solo diseño de «tiquete de papel» con sello (PAGADO, FIADO, ANULADA, COTIZACIÓN, CAJA JUSTA, PEDIDO RECIBIDO…), animación de «impresión» y envío como imagen por WhatsApp. También para el **pedido de la tienda en línea** | `referencias-diseno.md` (6) |
| **Marketing** | Video «un día con Stockealo» (idea de la referencia 3) | `referencias-diseno.md` (3) |

## 4. Menú lateral en el celular (decisión 2)

- **Botón ☰ arriba a la izquierda** que abre el menú desde el costado, con las mismas opciones y el mismo orden que en el computador.
- **Arriba del menú:** el negocio o la sede, para cambiarlo. **Abajo:** la persona con su rol, Ajustes y Cerrar sesión.
- **Los pendientes llevan contador:** fiados por cobrar, citas de hoy, traslados por recibir.
- Para no perder lo rápido: el botón **«Nueva venta» queda siempre en el encabezado** (o como botón flotante), y la pastilla de la caja también se ve en el celular.
- En tablets y en el computador, el menú queda **fijo y abierto**, y se puede plegar a solo íconos.
- **Por decidir en el diseño final:** si en el celular el menú se abre deslizando desde el borde, además del botón ☰.

## 5. Stocky con tablas (decisión 6, por planear bien)

Hoy Stocky responde con texto y botones de acción. La idea es que, cuando la pregunta es de números, **responda con una tabla real** y diga **en qué se basó**.

**Cómo se propone que funcione:**
1. **Respuestas con forma:** cuando la pregunta pide datos (más vendidos, qué reponer, quién debe, ventas por día), Stocky arma una **tabla** con columnas claras (Producto · Unidades · Ventas) y una frase corta arriba («Estos cinco fueron lo que más salió este mes»).
2. **«En qué me basé»** debajo de cada tabla: el periodo, qué se contó y qué no («del 1 al 3 de noviembre, ventas netas, sin anuladas»).
3. **Los números salen de la base de datos, no de la IA.** La IA entiende la pregunta y redacta la frase, pero **la tabla se calcula con consultas reales** a las ventas y al stock. Así no se inventan cifras.
4. **Aviso fijo pequeño:** «Stocky puede equivocarse: los números salen de tus ventas y tu stock, revisa siempre las tablas».
5. **Acciones desde la tabla:**
   - «Pedir al proveedor» en la tabla de reponer;
   - «Cobrar por WhatsApp» en la de fiados;
   - «Descargar Excel» en cualquiera.
6. **Respeta los permisos:** a un cajero no le muestra costos ni ganancias.

**Por planear (con el dueño):**
- Lista de **preguntas con tabla** para la primera versión: más vendidos, menos vendidos, qué reponer, quién debe y cuánto, ventas por día o mes, ganancia por producto, y productos sin ventas en 30 días.
- Cómo se ve la tabla en el celular: deslizar de lado, o tarjetas.
- Si las tablas cuentan como pregunta a la IA (límite de 10 o 50 al día) o son gratis cuando las resuelve el motor de reglas.
- Cómo pide Stocky que se aclare el periodo cuando la pregunta no lo dice.

## 6. Ideas pendientes de decidir

De la referencia 3 (el dueño no las mencionó todavía):
- **Actualizar los precios de un proveedor de una vez** (un %, o la lista nueva, con el precio viejo tachado y el nuevo).
- **Lector de código de barras USB** que agrega directo al carrito.
- **Ventas en espera** («Guardar para después»).
- **Video «un día con Stockealo»** para marketing.

## 7. Cómo encaja con el plan de actualizaciones

- El re-diseño **cambia dónde están las cosas y cómo se ven**, no lo que hace la app. Cambia el mapa de «nada duplicado» de la 0.12.0: cada función sigue con un solo lugar, pero ese lugar puede moverse.
- **Pregunta abierta:** ¿en qué actualización va? La 0.13.0 (Pro Servicios) trae pantallas nuevas grandes, como citas y reservas. Hay dos caminos:
  - **A.** Hacer primero el diseño final y el re-diseño, y construir Pro Servicios ya con el diseño nuevo. Pro Servicios sale un poco más tarde, pero no se hace dos veces.
  - **B.** Hacer Pro Servicios con V1 ahora (por si llega la barbería) y rehacer sus pantallas en el re-diseño.

## 8. Pasos del re-diseño

1. **Recoger referencias.** El dueño sigue mandando videos con «Mira Instagram». **No se pasa al paso 2 hasta que el dueño diga que ya mostró todos los diseños y mejoras propuestas** (pedido del 10 nov). Mientras tanto, solo se anotan las referencias.
2. **Armar el diseño final:**
   - colores, letra, tarjetas y estados, en claro y oscuro;
   - menú y encabezado;
   - Inicio, Vender, Caja y una pantalla de lista (Productos).

   Se muestra como página o imágenes para que el dueño apruebe.
3. **Responder las preguntas abiertas:**
   - las de esta página;
   - las de `propuesta-flujo.md`;
   - la de claro u oscuro y la del botón principal (en `referencias-diseno.md`).
4. **Aprobación del dueño.**
5. **Construir** por partes dentro de una rama, con pruebas a 360 y 1200 px y en claro y oscuro, y publicar junto.
6. **Mostrar «Dónde quedó cada cosa»** de nuevo con el menú nuevo.

## 9. Construcción (decisión A, 11 nov): el re-diseño va primero

> **Plan APROBADO el 11 nov.** Antes de programar se hizo el **inventario archivo por archivo**: `docs/inventario-rediseno.md`. Tiene 135 archivos, cada uno con su bloque, y la regla para dar un archivo por terminado. El dueño pidió ser minucioso: ningún archivo puede quedar con el primer diseño.

El dueño eligió **A**: primero el re-diseño completo, y después Pro Servicios ya con el diseño nuevo. **El re-diseño es la 0.13.0.** Se programa por bloques dentro de una rama y se publica todo junto. Cada bloque lleva pruebas a 360 y 1200 px, en claro y en oscuro, y commit con permiso.

**Bloque 1 · Base del diseño nuevo**
- Colores claro y oscuro del tablero aprobado, el color del negocio (oscurecido solo si es muy claro, para que el texto blanco se lea) y los estados.
- Letra Inter y JetBrains Mono, **incluidas en la app** para que funcione sin internet.
- Piezas comunes: botón principal y secundario, campo, buscador, pastilla, interruptor, tarjeta de cifra con mini gráfico, fila de «Necesita atención» y aviso de «hecho».
- Movimiento corto, que respeta «reducir movimiento».
- Reemplaza `app_tokens` y `AppCard`. La prueba de colores fijos sigue bajando.

**Bloque 2 · Navegación nueva**
- **Un solo menú lateral**, el mismo en la web y en el celular: Inicio · Vender · Ventas · Caja · Servicios · Productos · Stock · Clientes y proveedores · Tienda · Reportes · Ajustes.
- **Encabezado** con negocio o sede, pastilla de la caja, buscador (Ctrl K), campana, sol o luna y «Nueva venta».
- Nuevo mapa de lugares: Ventas pasa a ser solo el historial; Caja, Stock y «Clientes y proveedores» tienen lugar propio.
- Se actualizan `app_functions.dart` (buscador y accesos), Stocky «Ir a…» y la hoja «Dónde quedó cada cosa».

**Bloque 3 · Inicio**
- Tarjetas del día: ventas de hoy en el color del negocio, ganancia, fiados y efectivo.
- Gráfico de 14 días, lo más vendido, actividad del equipo y servicios de hoy.
- **«Necesita atención»** con su panel de solución: agotado → pedir al proveedor; fiado vencido → cobrar por WhatsApp; caja sin cerrar; pedido de la tienda por confirmar.

**Bloque 4 · Vender y Caja**
- **Vender como punto de venta:** cuadrícula o lista, carrito fijo, escáner, F9, vuelto, formas de pago (también Nequi, tarjeta y **mixto**), y se queda lista para la siguiente venta.
- **Caja obligatoria si el negocio la usa:** «Abre la caja para vender».
- Pantalla Caja propia, con el cierre en grande («La caja está justa»).
- **Anular sin borrar:** la venta queda «Anulada» en el historial (se mueve aquí desde el plan de ventas, porque Ventas se rehace).

**Bloque 5 · Comprobante**
- Un solo tiquete de papel con sello (PAGADO, FIADO, ANULADA, COTIZACIÓN, CAJA JUSTA…), animación de «impresión» y envío como imagen por WhatsApp.

**Bloque 6 · Leer códigos**
- Cámara · Foto · A mano, comprobación del último dígito con «Usar 8», y aviso si el código ya existe.
- Se usa al crear un producto, al vender, en el buscador y en la entrada de mercancía.

**Bloque 7 · El resto de pantallas al estilo nuevo**
- Productos, Stock (alertas, entradas, conteo), Clientes y proveedores, Ventas (historial), Reportes y Ajustes (incluidos Equipo y Apariencia).
- El tablero de Servicios actual pasa al estilo nuevo, sin funciones nuevas: esas son de la 0.14.0.

**Bloque 8 · Tienda en línea**
- Plantilla «Moda» (y la actual, mejorada, como «Clásica»): categorías con miniatura, filtros por precio, talla y color, ofertas, y el tiquete «Por confirmar» del pedido como imagen.

**Bloque 8b · Panel admin y portada** (decidido el 11 nov)
- El panel admin (19 archivos) pasa al diseño nuevo.
- La portada stockealo.online (`web_site/`) también.

**Bloque 9 · Cierre**
- Pruebas completas, revisión en la web y el APK, novedades y publicación.

**Fuera de la 0.13.0:**
- Stocky con tablas: se planea aparte, como pidió el dueño.
- Las citas y todo Pro Servicios nuevo: van en la 0.14.0.
- Los roles: van en la 0.15.0.

