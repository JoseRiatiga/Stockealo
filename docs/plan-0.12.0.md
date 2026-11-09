# Plan de la 0.12.0: módulo Servicios, planes nuevos y pendientes de prioridad alta

> **Estado:** **aprobado** por el dueño el 10 nov 2026, con el pedido de ordenarlo por prioridad (ver «Orden de trabajo»).
> Todo sale en **una sola actualización** (0.12.0). Rama de trabajo: `feat/0.12.0`, creada desde `main`.

## Orden de trabajo (por prioridad)

Todo se publica junto en la 0.12.0. Este es el orden en que se programa:

1. **Arreglos que reportó el dueño:** quitar los botones de Excel (sección 7.2), pasar la ventana Equipo al diseño V1 (7.1) y mostrar el aviso de versión nueva en la web (7.3).
2. **Planes:** Pro Servicios, el apagado de precios y compra, y el interruptor en el panel (sección 1). Sin esto el módulo no puede quedar oculto para los demás.
3. **Núcleo del módulo Servicios** (secciones 2, 3 y 4):
   - pestaña con sub-módulos;
   - plantillas por tipo de negocio y precio por tipo de vehículo (sección 4b);
   - catálogo con quién hace cada servicio;
   - empleados sin comisión propia;
   - asistencia;
   - estados por servicio y reglas;
   - cola con sugerencia;
   - recibir con búsqueda en vivo;
   - cobrar;
   - retroceder y anular un cobro.
4. **Comisiones y liquidaciones** (sección 5).
5. **Arqueo de caja mejorado** (sección 6).
6. **Módulos a la vista** (sección 7b): accesos sin deslizar, Caja visible, pantalla «Módulos», importador guiado de Excel en Inventario, Ajustes › Tu negocio a un toque y buscador de funciones.
7. **Mantenimiento programado** (sección 7c): aviso con días de anticipación, hora de fin libre, hora Colombia, mensajes listos, ventana de aviso y vista previa.
8. **Complementos de Servicios:** mensajes por fase, historial en vivo, tiempo de espera estimado, aviso de demora y cierre del día.
9. **Cierre:** revisar los avisos de la consola (7.4), la verificación completa (sección 9) y la publicación con permiso.

## Contexto

En la 0.11.0 se publicó el primer módulo de servicios: interruptor del negocio, tablero de motos, empleados, cobro con propina e historial por placa. Lo pidió un lavadero de motos que contactó directamente al dueño de Stockealo y que pagará unos **40 mil COP al mes o más**.

Al revisarlo, el dueño pidió rehacer el flujo y ordenar todo en un solo módulo. También decidió que este módulo **no se active a mano para un cliente**: va en una **línea de planes aparte**. Stockealo nació para stock y venta, y quien compra Pro solo para eso no necesita servicios. Un lavadero, una barbería o un taller sí, y para ellos el plan se amplía con más funciones y soporte.

## 1. Planes

| Plan | Para quién | Incluye |
|---|---|---|
| Gratis | Cualquier negocio | Stock y ventas, como hoy |
| Pro (Negocio / Global, ya existe) | Quien vende productos | Gratis + tienda en línea, cobro de fiados, catálogos y más IA |
| **Pro Servicios** (nuevo) | Lavaderos, barberías, talleres, spas… | Todo Pro + el módulo **Servicios** completo + soporte |

- Usa la tabla `subscriptions` con un tipo nuevo (`services`). Se activa como Pro: código canjeable, Wompi o «Dar Pro» en el panel, eligiendo el plan.
- Sin el plan no se ve la pestaña Servicios. Los negocios cuyo tipo es de servicios (Lavadero, Barbería, Peluquería, Taller, Spa, Uñas, Servicio técnico, Lavandería; ver `kBusinessKinds`) ven en su lugar una tarjeta que ofrece el plan.
- Se quita de la pantalla de Pro el beneficio «Empleados sin límite» que se agregó en la 0.11.0.
- Se quita el interruptor «Mi negocio ofrece servicios» de *Editar negocio*: ahora lo controla el plan.
- **Decisiones del dueño (9 nov 2026):**
  1. Nombre: **Pro Servicios**. Es un **plan único** (sin nivel Plus ni cobro por empleados): empleados sin límite.
  2. Periodo: **solo mensual**, con soporte incluido.
  3. Alcance: **un negocio** (como Pro Negocio). Un dueño con dos sedes necesita dos planes.
  4. **Precios y compra de planes desactivados en la app**, también los de Pro Negocio y Pro Global, hasta que el dueño negocie con el lavadero. Mientras tanto, los planes se activan con «Dar Pro» en el panel o con un código canjeable, eligiendo Pro Servicios.
  5. Los precios **se quedan guardados** en `pro_plans`. El panel admin tiene un interruptor **«Mostrar precios y compra en la app»** (apagado). Al encenderlo vuelven los precios y la compra, sin publicar otra versión.
- **Ya aplicado en producción el 10 nov (sin publicar versión):** los 6 planes Pro en COP quedaron con `active = false` en `pro_plans`. La 0.12.0 debe cambiar el texto «Pro aún no está disponible en tu país» y los textos fijos de la portada que hablan de pagar con Wompi.
- El precio de Pro Servicios se define después de la negociación (la referencia era unos $40.000/mes).
- Mientras los precios estén apagados, la pantalla de Pro muestra qué incluye cada plan y el campo para canjear código, sin precios ni botones de compra. La tarjeta de Servicios para negocios de tipo servicios explica el módulo y ofrece escribir por WhatsApp.

## 2. Módulo «Servicios» (una pestaña con sub-módulos)

Menú en el celular con Pro Servicios: Inicio | Ventas | **Servicios** | Inventario | Más (Reportes, Ajustes). En el computador, todas las pestañas en la barra lateral. Ver la sección 7b: cada función vive en un solo lugar.

```
SERVICIOS
├─ Operación
│   ├─ Tablero (cola, en proceso, listas)
│   ├─ Asistencia (quién vino hoy)
│   └─ Historial de trabajos (placa, nombre o teléfono)
├─ Pagos
│   └─ Comisiones y liquidaciones
└─ Configuración
    ├─ Catálogo y precios
    └─ Mensajes por fase
```

- Las personas (alta, baja, acceso a la app, servicios que hace, perfil) viven solo en **Ajustes › Equipo**.
- El **cierre del día** vive solo en **Ventas › Caja**; con Pro Servicios suma los vehículos atendidos, lo que hizo cada empleado y sus comisiones.
- Los clientes viven en **Ventas › Clientes y fiados**; el historial de trabajos abre su ficha allá.

Reemplaza la tarjeta de Inicio y las pantallas sueltas de la 0.11.0 (`work_board_screen.dart`, `services_setup_screen.dart`).

## 3. Flujo y reglas

**Estados de cada servicio** (avanzan por separado dentro de una moto):

- **Pendiente:** espera a alguien habilitado y libre. Es la cola.
- **En proceso:** un empleado lo está haciendo.
- **Terminado:** el empleado queda **libre en ese momento**, aunque a la moto le falten otros servicios.

**Estado de la moto:** En espera → Pendiente (a medias) → En proceso → Lista (todos sus servicios terminados) → Entregada.

**Estado del empleado:** Disponible · Ocupado (con qué moto y desde cuándo) · En pausa · Salió · No vino.

**Reglas obligatorias:**

- Ningún servicio empieza sin un empleado **que haya venido hoy, esté libre y esté habilitado** para ese servicio. El empleado queda vinculado al servicio (en la venta, el historial y las comisiones).
- **Un empleado tiene un solo servicio activo a la vez.**
- Si no hay nadie libre, el servicio queda **en cola** por orden de llegada. Cuando alguien se libera, la app **sugiere** el siguiente servicio que esa persona puede hacer y el cajero **confirma**.
- **Asistencia al inicio del día:** se marca *Llegó* o *No vino*, con salida y pausa. A quien no vino o ya salió no se le puede asignar trabajo. Queda un historial por día.
- **Retroceder** (Lista → En proceso → En espera) con confirmación y nota, siempre que no se haya cobrado. Si ya se cobró, se ofrece **anular el cobro** (las ventas y el fiado) y la moto vuelve a «Lista». Todo queda en la actividad.
- **Recibir:** una búsqueda **en vivo** por placa, nombre o teléfono que completa los datos del cliente si ya vino. La moto toma un número de turno.
- **Cobrar:** efectivo, transferencia o fiado, con descuento y propina. Cada servicio es una línea de venta (`recordServiceSale`).

**Ideas aprobadas por el dueño:**

- Tiempo de espera estimado («turno 3, unos 25 min»), calculado con las duraciones y la cola.
- Aviso de servicio demorado (pasó de su duración estimada).
- **Cierre del día** (en Ventas › Caja, ver sección 7b): vehículos atendidos, lo cobrado, lo que hizo cada empleado y su comisión. Se puede enviar al dueño por WhatsApp.

## 4. Configuración

- **Catálogo y precios:** el precio se edita en la misma lista, junto con la duración, el % de comisión y **quién lo hace** (obligatorio, al menos un empleado). Se puede ocultar un servicio sin borrarlo y cambiar el orden.
- **Empleados** (en Ajustes › Equipo, una sola lista con o sin acceso a la app): se **quita la comisión propia** del empleado; la comisión es solo la del servicio. El perfil muestra los servicios que hace, su estado actual, la asistencia del mes, los servicios hechos y sus comisiones.
- **Mensajes por fase** (Recibida, En proceso, Lista, Entregada): textos editables con {cliente}, {placa}, {servicios}, {empleado}, {total}, {turno} y {negocio}, con vista previa. Se envían a mano por WhatsApp y cada fase se puede apagar.
- **Historial de trabajos** (Servicios › Operación): búsqueda en vivo con visitas, gasto, servicios y quién atendió.

## 4b. Plantillas por tipo de negocio (decisión del dueño, 10 nov)

El módulo sirve para lavaderos, barberías, talleres y otros negocios de servicios. **Stockealo da la plantilla base** y el negocio solo elige su tipo al activar Servicios. No hay opción para renombrar las palabras a mano: si un cliente pide otra palabra, se ajusta la plantilla en una versión siguiente y les llega a todos los negocios de ese tipo.

Cada plantilla define:

- cómo se llama cada trabajo (vehículo, cliente, equipo, pedido);
- qué dato lo identifica (placa, serial o ninguno) y por cuál se busca en el historial;
- el nombre de los estados (por ejemplo «Lavando», «Atendiendo», «En reparación»);
- los servicios de ejemplo con precio, duración y comisión;
- los mensajes de WhatsApp por fase.

| Plantilla | Cada trabajo | Se identifica por | En proceso |
|---|---|---|---|
| Lavadero de motos y carros | Vehículo (con su tipo) | Placa | Lavando |
| Barbería o peluquería | Cliente | — | Atendiendo |
| Spa o uñas | Cliente | — | Atendiendo |
| Taller | Vehículo | Placa | En reparación |
| Servicio técnico | Equipo | Serial | En reparación |
| Lavandería | Pedido | — | En proceso |
| Otro | Orden | — | En proceso |

**Precio según el tipo de vehículo (lavadero):** el mismo servicio cuesta distinto en moto que en carro.

- La plantilla del lavadero trae los tipos *Moto*, *Carro* y *Camioneta*.
- Cada servicio tiene un precio por tipo. Si un tipo queda sin precio, ese servicio no se le ofrece; por ejemplo, el lavado de casco es solo para motos.
- Al recibir un vehículo se elige su tipo, y la lista de servicios muestra los precios de ese tipo.
- La comisión se calcula sobre lo cobrado, como en el resto del módulo.
- El catálogo muestra una columna de precio por cada tipo.

**Reglas:** ninguna pantalla escribe «moto» ni «placa» a mano; todo sale de la plantilla. Los negocios que ya activaron servicios en la 0.11.0 conservan su tipo: «Lavadero de motos» pasa a «Lavadero de motos y carros», con sus servicios actuales como precio de *Moto*.

## 5. Comisiones y liquidaciones

- Cada servicio cobrado guarda una línea de comisión: % del servicio sobre lo cobrado (después del descuento), repartida si lo hicieron varios. La propina va completa al empleado.
- Se **liquida al final del día, de la semana o del mes**. Se ve lo pendiente por empleado; al pagar se marca como pagado y se envía el detalle por WhatsApp.
- En el reporte de ganancias, la ganancia del servicio es el precio menos la comisión.
- Reportes en Excel: *Servicios* y *Comisiones*.

## 6. Arqueo de caja mejorado (para todos los negocios que lo activan)

- **Más visible:** en Inicio («Caja abierta desde 8:05 · $230.000 en efectivo»), un indicador en el encabezado o la barra lateral, y un aviso al cobrar en efectivo con la caja cerrada (sin bloquear la venta).
- **Movimientos de caja:** entradas y salidas con motivo (gasto, retiro, pago a proveedor de contado, propina entregada). Las entradas de mercancía de contado y las propinas se suman solas, y las propinas aparecen como «Propinas por entregar».
- **Cierre:** resumen por forma de pago, conteo opcional por billetes y monedas, nota obligatoria si no cuadra y comprobante por WhatsApp.
- **Avisos:** «La caja quedó abierta desde ayer» y recordatorio de cierre.
- **En la nube:** hoy `cash_sessions` es solo local; necesita una tabla y su sincronización.

## 7. Pendientes de prioridad alta (entran en la 0.12.0)

1. Pasar la ventana de Equipo (`lib/features/team/presentation/screens/employees_screen.dart`) al diseño V1.
2. Quitar los botones de Excel de Inventario (`products_list_screen.dart`) y de Ventas (`sales_history_screen.dart`), y revisar la acción rápida `excel_export` de Inicio y la fila «Reportes en Excel» de Ajustes. La pestaña Reportes ya los reemplaza.
3. Avisar en la web cuando hay una versión nueva («Hay una versión nueva, toca para actualizar»). Hoy `/app` se publica con service worker y `UpdateService` solo funciona en Android, así que los usuarios se quedan con versiones viejas.
4. Los avisos de la consola web (`VideoFrame…`, `[Violation] requestAnimationFrame`) vienen del motor de Flutter 3.24. No rompen nada; se revisan al aligerar la app o al actualizar Flutter.

## 7b. Módulos a la vista (pedido del dueño, 10 nov): que nada quede oculto

> **Aprobada el 10 nov.** El dueño deja el diseño de los módulos, nuevos y existentes, a criterio de quien programa: lo que se vea mejor y sea más intuitivo.

**Regla principal (pedido del dueño, 10 nov; mapa aprobado el 10 nov, incluidos Inicio sin accesos rápidos, encabezado sin «Venta rápida» y sin vender desde Inventario): nada duplicado.** Cada función tiene **un solo lugar** en un módulo o sub-módulo. No hay un segundo botón, acceso rápido o pantalla que haga lo mismo desde otro lado. Solo se permiten tres cosas que llevan a ese lugar sin repetirlo:
- el **buscador** del encabezado;
- los **avisos** (la campana);
- **Stocky**, que responde dónde está algo y ofrece «Ir a…».

Las tres llevan al lugar de la función; ninguna abre una copia.

**Criterios de diseño (para todos los módulos):**

- **Misma estructura en cada pestaña:** título, accesos en cuadrícula y después el contenido. Así quien aprende una pestaña ya sabe usar las demás.
- **Barra inferior del celular con máximo 5 pestañas.** Sin el plan de Servicios no cambia: Inicio · Inventario · Ventas · Reportes · Ajustes. Con Pro Servicios queda Inicio · Ventas · **Servicios** · Inventario · **Más**, y «Más» abre Reportes y Ajustes. En el computador, la barra lateral muestra todas las pestañas.
- **Estados vacíos que enseñan:** cuando una lista está vacía, se explica qué es el módulo y se muestra el botón para empezar.
- **Nombres claros y fijos en toda la app:** «Clientes y fiados», «Caja», «Proveedores y entradas», «Importar desde Excel». El mismo nombre en la pestaña, en el buscador, en Módulos y en lo que dice Stocky.
- **«Dónde quedó cada cosa»:** la primera vez que se abre la 0.12.0 sale una hoja corta con lo que cambió de lugar. Se puede volver a ver desde Ajustes › Acerca de.
- Todo se revisa en el celular (360 px) y en el computador (1200 px), en modo claro y oscuro.

**Lo que se encontró escondido o confuso hoy:**

| Función | Dónde está hoy | Problema |
|---|---|---|
| Arqueo de caja | Se enciende solo al crear o editar el negocio y se usa desde una franja en Ventas | Quien no lo activó al crear el negocio no sabe que existe |
| Importar inventario (Excel) | Ajustes › Nube y respaldo › Excel | Está lejos de Inventario |
| Equipo y Actividad | Ajustes › Tu negocio › ficha del negocio › Equipo | A tres toques |
| Proveedores, entradas, pedidos, tienda, catálogo | Fila de accesos de Inventario que se desplaza hacia el lado | En el celular los últimos no se ven si no se desliza |
| Ganancias | Acceso «Reportes» en Ventas y en Inicio que abre otra pantalla, distinta de la pestaña Reportes | Dos cosas distintas con el mismo nombre |
| Stockealo Pro | Solo en Ajustes | Difícil de encontrar |
| Servicios | Una tarjeta en Inicio | Se resuelve con la pestaña Servicios (sección 2) |

**Lo que hoy está repetido y cómo queda:**

| Función | Hoy está en | Queda solo en |
|---|---|---|
| Nueva venta | Ventas, botón «Venta rápida» del encabezado, acceso «Vender» de Inicio y vender desde un producto en Inventario | **Ventas** (botón principal «Nueva venta») |
| Nuevo producto | Inventario y acceso «Producto» de Inicio | **Inventario** |
| Clientes y fiados | Ventas y acceso «Clientes» de Inicio | **Ventas** |
| Ganancias | Acceso «Reportes» de Ventas y de Inicio | **Reportes › Ganancias** |
| Excel de compras | Botón en Proveedores y pestaña Reportes | **Reportes › Descargar Excel** |
| Catálogo PDF | Inventario y acceso «Catálogo» de Inicio | **Inventario** |
| Pedido a proveedor | Inventario, Proveedores, acceso «Alertas» de Inicio, aviso de visita y Stocky | **Inventario › Proveedores y entradas** (el aviso de visita pasa a la campana) |
| Equipo | Ficha del negocio y acceso «Equipo» de Inicio | **Ajustes › Equipo** |
| Datos del negocio y su resumen | Ajustes y acceso «Mi negocio» de Inicio; la ficha repite cifras de Inicio | **Ajustes › Datos del negocio**, sin cifras (las cifras viven en Inicio) |
| Modo oscuro | Botón del encabezado y Ajustes › Apariencia | **Ajustes › Apariencia** |
| Encender el arqueo de caja | Crear o editar negocio | **Ajustes › Módulos** |
| Últimas ventas | Inicio y Ventas | **Ventas** (Inicio solo muestra cifras) |
| Personas que trabajan | Ajustes › Equipo (con cuenta) y Servicios › Empleados (sin cuenta), dos listas | **Ajustes › Equipo**, una sola lista. Cada persona puede tener o no acceso a la app y, con Pro Servicios, los servicios que hace |
| Cierre del día | Servicios › Cierre del día y cierre de caja en Ventas | **Ventas › Caja › Cierre del día**. Con Pro Servicios suma vehículos atendidos, lo que hizo cada empleado y sus comisiones |

**Inicio deja de tener accesos rápidos.** Todos llevaban a funciones que ya tienen su pestaña. Inicio queda como el **resumen del día**:
- ventas, ganancia, por cobrar y productos por reponer;
- la gráfica del periodo y la comparación con el periodo anterior.

Cada cifra se toca y lleva a su lugar. No muestra listas ni botones de otros módulos.

**Cómo queda cada pestaña:**

- **Inventario:** lista de productos con el botón principal «Nuevo producto». Accesos: Importar desde Excel · Proveedores y entradas (adentro: pedidos, entradas y cuentas por pagar) · Catálogo · Tienda en línea (Pro).
- **Ventas:** historial con el botón principal «Nueva venta». Accesos: Clientes y fiados · Cotizaciones · Caja. Si el arqueo está apagado, la tarjeta Caja explica qué hace y lleva a Ajustes › Módulos para encenderlo.
- **Servicios** (con Pro Servicios):
  - *Operación:* Tablero · Asistencia · Historial de trabajos (por placa, nombre o teléfono; al tocar un cliente se abre su ficha en Clientes y fiados).
  - *Pagos:* Comisiones y liquidaciones.
  - *Configuración:* Catálogo y precios · Mensajes por fase.
  - Las personas se agregan en Ajustes › Equipo. Si no hay nadie, Asistencia lo explica y lleva allá.
- **Reportes:** dos partes, Ganancias y Descargar Excel.
- **Ajustes:**
  - *Tu negocio:* Datos del negocio · Equipo · Actividad del equipo · Módulos · Stockealo Pro.
  - *Personalización:* Apariencia · Avisos.
  - *Datos:* Nube y respaldo.
  - *Privacidad y seguridad* y *Acerca de*.
- **Encabezado:** selector de negocio, buscador y campana de avisos. No tiene accesos a funciones.

**Pantalla «Módulos» (Ajustes › Tu negocio):** es el único lugar donde se encienden y apagan los módulos opcionales:
- Caja (arqueo);
- Servicios (según el plan);
- Tienda en línea (Pro);
- Avisos del celular.

Cada uno muestra qué hace, si está encendido y en qué pestaña aparece. No repite las funciones del módulo.

**Además:**

- El buscador del encabezado también encuentra funciones («caja», «proveedores», «importar») y lleva a su lugar.
- Stocky explica dónde está cada cosa y, en vez de abrir pantallas por su cuenta, ofrece «Ir a…».
- Se borra `sales_quick_modules_bar.dart`, que ya no se usa.
- Prueba: cada módulo se abre desde su pestaña en dos toques o menos, a 360 px y a 1200 px.
- Revisión final: una lista de cada función con su único lugar. Se recorre la app para confirmar que no aparece en otro lado.

### Importador guiado de Excel (en Inventario)

Para quien ya lleva sus productos en un Excel hecho a mano. El importador actual (`excel_import_service.dart`) falla con esos archivos por varias razones:

- exige los títulos en la fila 1;
- con varias hojas, la de productos debe llamarse «Inventario», «Productos» o «Stock»;
- no entiende «PVP», «Valor», «Unidades» ni «Referencia»;
- si no halla el nombre, usa la segunda columna;
- no deja corregir nada;
- solo acepta `.xlsx`.

Pasos del importador nuevo:

1. **Archivo:** `.xlsx` o `.csv`. Si es un `.xls` viejo, la app explica cómo guardarlo como `.xlsx`.
2. **Detección:** encuentra sola la hoja con productos y la fila de los títulos, aunque arriba haya otras cosas. Reconoce más palabras: PVP, valor, unidades, referencia, ref, existencias, etc.
3. **Columnas:** la app propone qué es cada columna y la persona lo cambia con un menú (Nombre, Precio de venta, Costo, Stock, Código, Categoría, Mínimo o Ignorar). Sin columna de nombre no se puede importar.
4. **Vista previa:** las primeras filas tal como quedarán, con avisos por fila (sin nombre, precio no válido, código repetido). Limpia formatos como «$12.500» y «12,500».
5. **Opciones:** si el producto ya existe, actualizarlo u omitirlo; el stock se reemplaza o se suma.
6. **Red de seguridad:** antes de importar se guarda una copia automática; si algo sale mal, se deshace con «Volver a una copia».
7. **Plantilla de ejemplo** descargable.

Pruebas:

- archivo con título y fecha arriba de los encabezados;
- hoja llamada «Hoja1» entre varias;
- columnas «PVP» y «Unidades»;
- precios con «$» y puntos;
- códigos repetidos;
- `.csv` separado por coma y por punto y coma;
- reemplazar o sumar stock.

## 7c. Mantenimiento programado (pedido del dueño, 10 nov)

> **Aprobada el 10 nov.**

**Ya existe desde la 0.11.0** en el panel admin (Mantenimiento):
- Tres niveles: *Solo aviso*, *Nube en pausa* (se sigue vendiendo en el equipo y todo sube al terminar) y *Cierre total*.
- Partes que se pueden poner en mantenimiento: app y web, tiendas en línea y pagos.
- Se activa ya o se programa con fecha, con un mensaje propio y fin automático.
- La app muestra una franja con el horario y los administradores siguen entrando.

**Lo que falta para un aviso como «el 5 de diciembre de 11:00 p. m. a 2:00 a. m., hora Colombia; no recomendamos agregar cosas»:**

1. **Avisar con días de anticipación:** hoy el aviso empieza como máximo 24 h antes. Se agregan *2 días*, *3 días*, *1 semana* y *desde ya*.
2. **Elegir la hora de fin:** hoy solo hay duraciones fijas (30 min, 1, 2, 4, 8 o 24 h), así que 11:00 p. m. a 2:00 a. m. (3 h) no se puede. Se elige la hora de inicio y la de fin, aunque pase de un día al otro, y se muestra la duración.
3. **Hora de Colombia:** el panel programa y muestra la hora de Colombia. La app la muestra así: «5 de diciembre de 11:00 p. m. a 2:00 a. m. (hora Colombia)». Si el equipo está en otro país, se agrega su hora local entre paréntesis.
4. **Mensajes listos para elegir** en el panel, editables:
   - *Recomendación:* «Te recomendamos no agregar ni modificar productos, ventas ni clientes durante ese horario.»
   - *Mejoras:* «Estamos actualizando y mejorando funciones de Stockealo.»
   - *Mensaje propio.*
5. **Aviso más visible:** además de la franja, la primera vez que alguien abre la app con un mantenimiento programado ve una ventana con:
   - la fecha;
   - el horario;
   - qué va a pasar según el nivel;
   - la recomendación.

   Con «Entendido» no vuelve a salir para ese mantenimiento.
6. **Durante el mantenimiento:** la franja dice que se están haciendo cambios y repite la recomendación. Con *Nube en pausa*, la app explica que lo que se haga se guarda en el equipo y se sube al terminar.
7. **Vista previa en el panel:** antes de programar, el dueño ve exactamente la franja y la ventana que verán los usuarios.

Pruebas:
- un mantenimiento que cruza la medianoche;
- el aviso que empieza días antes;
- la hora de Colombia vista desde un equipo con otra zona horaria;
- la ventana sale una sola vez por mantenimiento;
- los administradores siguen entrando.

## 8. Datos (migraciones de Supabase, se aplican solo con permiso)

- `services.staff_ids`: empleados habilitados para cada servicio.
- `services.prices_by_kind`: precio por tipo de vehículo (vacío = el servicio no se ofrece para ese tipo).
- `work_orders.vehicle_kind`: tipo de vehículo de cada trabajo.
- `work_orders.lines`: cada línea con su estado (pendiente, en proceso, terminado), su empleado y sus horas.
- `staff_attendance`: negocio, empleado, día, estado (llegó o no vino), entrada, salida y pausas.
- Mensajes por fase guardados por negocio.
- `commissions` y `staff_payouts`.
- `cash_sessions` y `cash_movements` en la nube.
- `subscriptions.kind = 'services'` (por negocio, solo mensual) y su fila en `pro_plans` (precio pendiente).
- Ajuste de configuración `show_pricing` (apagado) que lee la app y cambia el panel admin.
- `staff.commission_pct`: se deja de usar (no se borra).

## 9. Verificación

- Pruebas de las reglas:
  - no se empieza sin un empleado presente, libre y habilitado;
  - un solo servicio activo por empleado;
  - la cola y la sugerencia al liberarse alguien;
  - retroceder, y anular un cobro;
  - asistencia (no vino, salida, pausa);
  - comisión con descuento y reparto, y liquidación;
  - movimientos y cierre de caja;
  - acceso según el plan (sin plan no se ve el módulo);
  - plantillas: con una barbería de prueba no aparece «moto», «placa» ni «lavando» en ninguna pantalla;
  - precio por tipo de vehículo: moto y carro cobran distinto, y un servicio sin precio para un tipo no se ofrece;
  - un lavadero de la 0.11.0 conserva sus servicios como precios de moto;
  - con `show_pricing` apagado no se ven precios ni compra; al encenderlo vuelven.
- Actualización de la base local de v11 a v12.
- Pantallas probadas a 360 px y 1200 px, en modo claro y oscuro.
- `flutter analyze`, todas las pruebas y la compilación de la app, el panel y la tienda.
- Prueba en la web con un negocio de prueba tipo lavadero antes de publicar.
