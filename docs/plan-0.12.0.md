# Plan de la 0.12.0: módulo Servicios, planes nuevos y pendientes de prioridad alta

> **Estado:** propuesto, **sin aprobar**. No se toca código hasta que el dueño apruebe este plan.
> Todo sale en **una sola actualización** (0.12.0). Rama de trabajo: `feat/0.12.0`, creada desde `main`.

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
- **Preguntas abiertas para el dueño:**
  1. Nombres de los planes. Se propone *Pro Servicios* y *Pro Servicios Plus*.
  2. ¿Cobro por número de empleados (por ejemplo, hasta 5 y sin límite) o un plan único?
  3. ¿Solo mensual (incluye soporte) o también semanal y permanente?
  4. ¿Cubre un negocio o todos los del dueño (como Pro Negocio y Pro Global)?
- Propuesta de precio: desde **$39.900/mes** con hasta 5 empleados; Plus cerca de **$59.900**.

## 2. Módulo «Servicios» (una pestaña con sub-módulos)

Menú: Inicio | Inventario | Ventas | **Servicios** | Reportes | Ajustes

```
SERVICIOS
├─ Operación del día
│   ├─ Tablero (cola, en proceso, listas)
│   ├─ Asistencia (quién vino hoy)
│   └─ Cierre del día
├─ Equipo
│   ├─ Empleados (estado, perfil)
│   └─ Comisiones y liquidaciones
└─ Configuración
    ├─ Catálogo y precios
    ├─ Mensajes por fase
    └─ Historial de clientes y placas
```

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
- **Cierre del día:** motos atendidas, lo cobrado, lo que hizo cada empleado y su comisión. Se puede enviar al dueño por WhatsApp.

## 4. Configuración

- **Catálogo y precios:** el precio se edita en la misma lista, junto con la duración, el % de comisión y **quién lo hace** (obligatorio, al menos un empleado). Se puede ocultar un servicio sin borrarlo y cambiar el orden.
- **Empleados:** se **quita la comisión propia** del empleado; la comisión es solo la del servicio. El perfil muestra los servicios que hace, su estado actual, la asistencia del mes, los servicios hechos y sus comisiones.
- **Mensajes por fase** (Recibida, En proceso, Lista, Entregada): textos editables con {cliente}, {placa}, {servicios}, {empleado}, {total}, {turno} y {negocio}, con vista previa. Se envían a mano por WhatsApp y cada fase se puede apagar.
- **Historial:** búsqueda en vivo con visitas, gasto, servicios y quién atendió.

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

## 8. Datos (migraciones de Supabase, se aplican solo con permiso)

- `services.staff_ids`: empleados habilitados para cada servicio.
- `work_orders.lines`: cada línea con su estado (pendiente, en proceso, terminado), su empleado y sus horas.
- `staff_attendance`: negocio, empleado, día, estado (llegó o no vino), entrada, salida y pausas.
- Mensajes por fase guardados por negocio.
- `commissions` y `staff_payouts`.
- `cash_sessions` y `cash_movements` en la nube.
- `subscriptions.kind = 'services'` y los precios del plan nuevo en `pro_plans`.
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
  - acceso según el plan (sin plan no se ve el módulo).
- Actualización de la base local de v11 a v12.
- Pantallas probadas a 360 px y 1200 px, en modo claro y oscuro.
- `flutter analyze`, todas las pruebas y la compilación de la app, el panel y la tienda.
- Prueba en la web con un negocio de prueba tipo lavadero antes de publicar.
