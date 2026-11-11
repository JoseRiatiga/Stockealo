# Pro Servicios para cada tipo de negocio

> **Estado:** **APROBADO el 10 nov 2026.** Va en la **0.13.0**, con prioridad máxima (ver `docs/plan-fases.md`). Antes decía: propuesta, sin aprobar. Solo es un plan: no se toca código hasta que el dueño responda las preguntas de la sección 5 y lo apruebe.
> Pedido del dueño el 10 nov 2026: Pro Servicios no es solo para el lavadero, también para barberías y otros negocios, y eso no quedó bien planeado.

## 1. Cómo quedó en la 0.12.0

Hay 7 plantillas (`service_template.dart`): lavadero, barbería o peluquería, spa o uñas, taller, servicio técnico, lavandería y otro.

Cada plantilla **solo cambia**:
- los nombres: «Vehículo», «Cliente», «Equipo», «Pedido»;
- si se pide placa o serial;
- el texto de «en proceso»: «Lavando», «Atendiendo», «En reparación»;
- los servicios de ejemplo;
- los tipos de vehículo, solo en el lavadero.

Pero **el trabajo es igual para todos**:
- El cliente **llega y espera**: Espera → En proceso → Lista → Entregada.
- Se cobra al final, todo de una vez.
- No hay citas, abonos, repuestos ni fecha de entrega.

Eso sirve para el lavadero y la barbería **sin citas**. A los demás les faltan piezas.

## 2. Qué le falta a cada tipo

| Tipo | Cómo trabaja | Le falta |
|---|---|---|
| **Lavadero** | Llega, espera, se va | Casi nada (insumos, en la fase 8) |
| **Barbería o peluquería** | Por turno **o con cita**; cada cliente prefiere a «su» barbero | **Citas**, barbero preferido, historial del cliente, precio según el largo del cabello, **alquiler de silla** |
| **Spa o uñas** | Casi siempre **con cita**, servicios largos | **Citas** con duración, recordatorio por WhatsApp, abono para apartar |
| **Taller** | Se deja el vehículo días; hay que aprobar el arreglo | Recepción con fotos y estado, **presupuesto que el cliente aprueba**, **repuestos que salen del inventario**, «esperando repuesto», **abono**, fecha de entrega, garantía |
| **Servicio técnico** | Igual que el taller, con equipos | Lo mismo que el taller, más los accesorios recibidos (cargador, funda) y la clave o patrón (opcional) |
| **Lavandería** | Se deja la ropa y se recoge otro día | Cobro **por kilo o por prenda**, **fecha de entrega**, ticket con número, **abono**, aviso de ropa sin recoger |

## 3. Piezas que se comparten

En vez de programar cada tipo por separado, se hacen **piezas** y cada plantilla enciende las suyas.

1. **Precio por variante.** Hoy solo existe el tipo de vehículo. Se generaliza a cualquier cosa: «Moto / Carro» en el lavadero, «Corto / Largo» en la peluquería, «Pequeño / Grande» en la lavandería.
2. **Cantidad con decimales:** kilos o metros. Lavandería por kilo.
3. **Agenda de citas:**
   - calendario por día y por persona del equipo, con la duración de cada servicio;
   - estados «Confirmada» y «No vino»;
   - recordatorio por WhatsApp;
   - al llegar el cliente, la cita pasa al tablero.
4. **Reservar en línea, opcional:** el cliente aparta su cita desde un enlace del negocio (como la tienda en línea).
5. **Abono o anticipo:** se cobra una parte al recibir y el resto al entregar. Cuadra con la caja y los reportes.
6. **Fecha de entrega** y aviso de «Listo para recoger» por WhatsApp. Ya existen los mensajes por fase; solo falta la fecha.
7. **Presupuesto que se aprueba:**
   - nuevo estado «Esperando aprobación»;
   - el cliente recibe el presupuesto por WhatsApp;
   - se marca aprobado o rechazado.
8. **Repuestos o productos usados en el trabajo:** salen del inventario y se cobran en la misma orden. Ejemplos: el repuesto del taller, la pomada que se vende en la barbería.
9. **Recepción con fotos y notas:** estado del vehículo o del equipo y accesorios recibidos. Sirve para evitar reclamos.
10. **Estados según el tipo:** cada plantilla trae su camino. El taller suma «Esperando aprobación» y «Esperando repuesto». La lavandería suma «Lista para recoger».
11. **Garantía:** días de garantía por servicio y aviso si el cliente vuelve dentro de ese plazo.
12. **Historial del cliente:** hoy el historial va por placa. Se suma por teléfono, para la barbería y el spa: qué se hizo, con quién y cada cuánto viene.
13. **Alquiler de silla (barbería):** en vez de comisión, el barbero paga un arriendo fijo por día o por semana. Se maneja en Comisiones y liquidaciones.

### Qué piezas usa cada plantilla

| Pieza | Lavadero | Barbería | Spa | Taller | Técnico | Lavandería |
|---|---|---|---|---|---|---|
| Precio por variante | ✔ vehículo | ✔ largo | — | ✔ vehículo | — | ✔ tamaño |
| Cantidad con decimales | — | — | — | — | — | ✔ |
| Citas | opcional | ✔ | ✔ | opcional | — | — |
| Abono | — | opcional | ✔ | ✔ | ✔ | ✔ |
| Fecha de entrega | — | — | — | ✔ | ✔ | ✔ |
| Presupuesto | — | — | — | ✔ | ✔ | — |
| Repuestos o productos | insumos | ✔ productos | ✔ productos | ✔ | ✔ | — |
| Recepción con fotos | opcional | — | — | ✔ | ✔ | opcional |
| Garantía | — | — | — | ✔ | ✔ | — |
| Historial | placa | teléfono | teléfono | placa | serial | teléfono |
| Alquiler de silla | — | ✔ | ✔ | — | — | — |

En **Ajustes › Módulos** el dueño puede encender o apagar las piezas opcionales. La plantilla solo trae las recomendadas.

## 4. Etapas propuestas

1. **Base para todos:** precio por variante generalizado, estados según el tipo, fecha de entrega, abono e historial por teléfono. Con esto ya quedan bien la lavandería y la barbería sin citas.
2. **Taller y servicio técnico:** presupuesto que se aprueba, repuestos del inventario, recepción con fotos y garantía.
3. **Citas:** agenda, recordatorios y «No vino». Barbería y spa.
4. **Extras:** reservar en línea y alquiler de silla.

## 5. Respuestas del dueño (10 nov)

1. **Multifuncional desde ya.** Por ahora solo hay un lavadero interesado, pero se diseña para que sirva igual a una barbería, un taller o cualquier otro negocio de servicios. Las 4 etapas se mantienen.
2. **Citas:**
   - Las crea el negocio.
   - **Si el negocio tiene la tienda en línea, el cliente también puede agendar desde ahí.** Antes se valida que ese horario esté disponible (ver sección 6).
3. **Alquiler de silla:** se explica en la sección 8. Falta confirmar si entra.
4. **Presupuesto (taller y técnico):**
   - Si el cliente **no está en el local**, se le envía por WhatsApp y la orden queda «Esperando aprobación» hasta que responda.
   - Si **está en el taller**, el negocio lo aprueba ahí mismo con un toque y queda registrado quién lo aprobó y cuándo.
5. **Planes:** va en Pro Servicios, pero con algunas cosas gratis. Se propone el reparto completo en la sección 7.

## 6. Reservar en línea (con la tienda)

- En la tienda del negocio aparece **«Agendar cita»**.
- El cliente elige:
  - el servicio;
  - la persona que lo atiende, o «la que esté libre», si el negocio lo permite;
  - el día y la hora.
- **Solo se muestran horas libres.** La app calcula:
  - el horario de atención del negocio;
  - los días y horas que trabaja cada persona;
  - la duración del servicio;
  - las citas ya agendadas y un margen entre citas, que elige el dueño (por ejemplo, 10 min).
- Nunca se dan dos citas a la misma persona a la misma hora. Si dos clientes eligen el mismo horario al mismo tiempo, **la nube solo deja guardar una** y al otro se le pide elegir otra hora.
- El cliente deja nombre y WhatsApp.
- El negocio elige cómo se confirman:
  - **automática:** queda agendada de una vez;
  - **por aprobar:** el negocio la acepta o la rechaza.
- El negocio recibe un aviso en el celular. Al cliente le llega la confirmación y un recordatorio el día antes o unas horas antes.
- El cliente puede **cancelar desde el enlace** hasta cierto tiempo antes, por ejemplo 2 horas. Lo decide el dueño.
- Si la cita pide abono, se muestran los datos de pago del negocio. **El dinero nunca pasa por Stockealo.**

## 7. Gratis, Pro y Pro Servicios

**Idea:** lo gratis deja que cualquier negocio de servicios **empiece y se enganche**. Pro **automatiza y pone el negocio en línea**. Pro Servicios es para **manejar un equipo de trabajo**.

| Función | Gratis | Pro | Pro Servicios |
|---|---|---|---|
| Ventas, inventario, tallas y colores, caja, reportes, proveedores, importar Excel | ✔ | ✔ | ✔ |
| Clientes y fiados (manual) | ✔ | ✔ | ✔ |
| Cobro automático de fiados | — | ✔ | ✔ |
| Tienda en línea | — | ✔ | ✔ |
| Catálogos personalizados | básico | ✔ | ✔ |
| Stocky con IA | 10 al día | 50 al día | 50 al día |
| **Catálogo de servicios** y cobrarlos en Ventas | ✔ | ✔ | ✔ |
| Precio por variante (moto/carro, corto/largo) | ✔ | ✔ | ✔ |
| **Tablero de trabajos** | ✔ hasta 3 personas | ✔ hasta 3 personas | ✔ sin límite |
| **Agenda de citas** hecha por el negocio | ✔ hasta 3 personas | ✔ hasta 3 personas | ✔ sin límite |
| Historial por placa, serial o teléfono | ✔ | ✔ | ✔ |
| Fecha de entrega y abono | ✔ | ✔ | ✔ |
| Mensajes por WhatsApp por fase («Listo para recoger») | a mano, un toque | a mano | **automáticos** |
| Recordatorio de cita por WhatsApp | — | — | ✔ |
| **Reservar en línea** desde la tienda | — | — | ✔ |
| Presupuesto por WhatsApp para aprobar | — | — | ✔ |
| Repuestos y productos usados en la orden | ✔ | ✔ | ✔ |
| Recepción con fotos y garantía | — | — | ✔ |
| Asistencia del equipo | — | — | ✔ |
| **Comisiones, liquidaciones y alquiler de silla** | — | — | ✔ |
| Reportes por persona y por servicio | — | — | ✔ |
| Sedes (Principal + 2; extra de a una o varias, con descuento) | — | — | ✔ (ver plan de sedes) |
| Soporte para configurarlo | — | — | ✔ |

Notas:
- **«Hasta 3 personas»** (decidido el 10 nov; primero se propusieron 2) quiere decir 3 personas del equipo que atienden servicios. Una barbería pequeña usa el tablero y la agenda gratis. Cuando crece o quiere comisiones y reservas en línea, pasa a Pro Servicios.
- **Pro (sin Servicios)** da lo mismo que lo gratis en servicios, porque Pro está pensado para tiendas.
- Lo que dejan de dar los planes nunca se borra (misma regla de las sedes): si el plan vence, el negocio sigue viendo sus citas, órdenes y reportes, y puede descargarlos.
- **«Elegir el plan por lo que se necesita»** (plan de sedes, sección 6b) usa esta tabla para sugerir el plan.

### Cosas de las otras fases y su plan

| Función (plan de fases) | Gratis | Pro | Pro Servicios |
|---|---|---|---|
| Anular sin borrar, devolución parcial, pago mixto, vuelto | ✔ | ✔ | ✔ |
| Cierre del día por WhatsApp | a mano | automático | automático |
| Pedidos de la tienda, QR, personalizar tienda, estadísticas | — | ✔ | ✔ |
| Meta de ventas, gastos y ganancia real, conteo de inventario, impresora, widget | ✔ | ✔ | ✔ |
| Combos o kits, precios por cantidad, ofertas, precio al por mayor | — | ✔ | ✔ |
| Clientes frecuentes y tarjeta de puntos | — | ✔ | ✔ |
| Facturación electrónica DIAN (cuando llegue) | — | ✔ | ✔ |

## 8. Alquiler de silla (qué es)

En muchas barberías y salones el barbero **no es empleado**: «alquila la silla». Le paga al dueño una cuota fija (por ejemplo, $150.000 a la semana) y se queda con lo que cobra. Otros trabajan **por comisión**: el dueño cobra y le da al barbero un porcentaje. Algunos negocios mezclan las dos formas.

En Stockealo sería una opción por persona en **Comisiones y liquidaciones**:
- **Por comisión:** lo que existe hoy.
- **Alquiler de silla:**
  - la persona paga una cuota fija por día, semana o mes;
  - la app lleva lo que debe y lo que ya pagó;
  - sus servicios **no suman a la caja del dueño**, o suman y se le devuelven en la liquidación, según cómo lo maneje el negocio.

## 9. Segunda ronda de respuestas (10 nov)

1. **Alquiler de silla: SÍ entra**, como opción por persona en Comisiones y liquidaciones, para quien lo necesite.
2. **Límite gratis de 2 personas:** el dueño pidió que se lo expliquen (ver abajo). Falta que lo confirme.
3. **Reservas en línea: confirmación automática.** El dueño ve todo de cada cita:
   - quién la creó: el cliente desde la tienda, o qué persona del negocio;
   - fecha y hora en que se creó;
   - cada cambio: quién la movió, la canceló o marcó «No vino», y cuándo;
   - los datos del cliente: nombre, WhatsApp, servicio, persona elegida y nota.
   Todo queda también en **Ajustes › Actividad del equipo**.
4. **Se elimina Pro Global.** Quedan solo **Pro** y **Pro Servicios**. Revisado en Supabase el 10 nov: **nadie ha tenido nunca Pro Global** y no hay códigos de ese plan, así que quitarlo no afecta a nadie.
   - Los 4 planes Global de `pro_plans` se borran o quedan inactivos para siempre.
   - Se quita «Global» de la app, el panel, la portada y los textos legales.
   - El código acepta el tipo `global` viejo como `business`, por seguridad.
   - **Quien tenga varios negocios paga Pro en cada uno.** Para varios locales del mismo negocio están las **sedes** (Pro Servicios).
5. **Orden en las fases:** sin respuesta todavía. La propuesta sigue siendo justo después de la 0.12.1.

### Qué es el límite gratis de 2 personas

En el plan gratis, el tablero de trabajos y la agenda de citas funcionan completos, pero **solo se les puede asignar trabajo a 2 personas del equipo**. Por ejemplo, el dueño y un barbero, o dos lavadores.

- **Clientes, trabajos y citas: sin límite.** Lo único limitado es cuántas personas atienden.
- **Cuando el negocio agrega a la 3.ª persona** para hacer servicios, la app explica que eso es de Pro Servicios y lo sugiere. La persona puede quedar en Equipo (por ejemplo, como cajero), pero no recibe trabajos ni citas.
- **Si un negocio con Pro Servicios vence** y tiene 5 personas, no se borra nada: todos sus trabajos, citas y comisiones se ven y se descargan. Solo 2 personas, elegidas por el dueño, siguen recibiendo trabajos nuevos.
- **Por qué con personas y no con cantidad de trabajos:** un negocio pequeño, de una o dos personas, usa la app gratis sin frenos. El que crece y tiene equipo es el que necesita comisiones, reservas y control, y por eso paga.

Otra forma sería limitar por cantidad, por ejemplo 100 trabajos al mes gratis. Es más difícil de entender y castiga al negocio pequeño que trabaja mucho. **Se recomienda el límite por personas.**

## 10. Tercera ronda de respuestas (10 nov)

1. **Límite gratis: 3 personas** que atienden, no 2. Lo demás queda como se explicó en la sección 9: sin límite de clientes, trabajos ni citas, y al vencer el plan el dueño elige quiénes 3 siguen recibiendo trabajos.
2. **Orden: es prioridad.** En `docs/plan-fases.md` quedó así:
   - etapa 1, junto con «ventas que no se pierden», en la **0.13.0**, porque el abono necesita el pago mixto y la caja;
   - etapa 2 y alquiler de silla en la **0.14.0**;
   - citas y reservas en línea en la **0.15.0**.
3. **Sedes: solo en Pro Servicios**, con Principal + 2. Pro (tiendas) no trae sedes. Si un negocio necesita más, **elige cuántas sedes extra comprar, desde +1**. Si compra varias de una vez, tiene descuento. Detalle en `docs/plan-sedes.md`, sección 6.

Ya no quedan preguntas abiertas en este plan. Falta que el dueño lo apruebe.

## 11. Orden final (aprobado el 10 nov)

El dueño pidió acelerarlo por si llega una barbería en menos de una semana. Todo va en la **0.13.0**:
- **Bloque A, barbería y spa, primero:** citas, reservas en línea, precio por variante, historial por teléfono, productos en el servicio, alquiler de silla, abono con pago mixto, anular sin borrar y gratis hasta 3 personas.
- **Bloque B:** taller, técnico y lavandería.

Si la barbería llega antes, el Bloque A sale como 0.13.0 y el B como 0.13.1.
