# Plan: avisos de pedidos y notificaciones

**Fecha:** 14 nov 2026. Lo pidió el dueño después de probar la 0.13.4.
**Estado:** A, B y C HECHAS en código (14 nov, rama feat/0.13.5). D (Firebase) quedó en la **0.16.0 · Tienda y crecimiento**, punto 11 de `docs/plan-fases.md`. Tiempo real: `store_orders` agregada a `supabase_realtime` (migración aplicada).

## Lo que hay hoy

- **Avisos en el celular** (`PhoneAlertsService`, solo Android): stock bajo, resumen del día, visita del proveedor y cobro de fiados.
  - Vienen **apagados**.
  - El permiso se pide solo al encender uno.
  - Todo se calcula en el celular, sin servidor.
- **Campana de arriba** (`NotificationService`): escucha las ventas en tiempo real. Casi no se usa.
- **No hay notificaciones desde el servidor** (Firebase): con la app **cerrada del todo** no puede llegar un aviso de algo que pasó en la nube, como un pedido nuevo de la tienda.

## Lo que pidió el dueño

1. Avisar cuando llega un pedido de la tienda, y poner un contador en Ventas › Cotizaciones que se quite al revisarlas.
2. **Todas las opciones de aviso encendidas por defecto.**
3. **En el celular, pedir el permiso de notificaciones al abrir la app la primera vez.**

## Propuesta

### A · Pedido nuevo de la tienda

- **Aviso al llegar:** «Nuevo pedido T-0003 de Ana · $45.000».
  - En tiempo real, igual que las ventas, con la tabla `store_orders`.
  - Con la app abierta o en segundo plano reciente sale una notificación del celular.
  - Con la app **cerrada del todo** llega al abrirla. Para que llegue estando cerrada hace falta **Firebase**: es un proyecto aparte y está en la fase D.
- **Campana:** «Pedido T-0003 de Ana». Al tocarlo se abre ese pedido.

### B · Contador «sin ver»

- **Dónde va el número de pedidos sin ver:**
  - en **Ventas**, en el menú lateral y en la barra del celular;
  - en el acceso **Cotizaciones**.
- **Cuándo se quita:** al abrir Cotizaciones.
- **Dentro de la lista:** «Nuevo» en cada pedido que no se ha abierto. Se quita al abrirlo.
- **«Visto» no es «atendido»:** el pedido sigue «Por confirmar» hasta cobrarlo o rechazarlo, y vence a los 7 días.
- **Recordatorio:** si un pedido lleva más de 2 horas sin abrir, se recuerda una vez: «Ana sigue esperando tu respuesta (T-0003)».

### C · Todo encendido y permiso al empezar

- **Encendido por defecto:**
  - stock bajo, resumen del día, visita del proveedor y pedidos de la tienda;
  - el sonido de los pedidos;
  - el cobro de fiados sigue siendo por cliente, como hoy.
- **Al abrir la app en el celular por primera vez:** una pantalla corta que explica para qué son los avisos. El botón «Activar avisos» pide el permiso del sistema.
  - Si la persona dice que no, no se vuelve a insistir.
  - En Ajustes › Avisos queda «Activar avisos del celular».
- **Ajustes › Avisos:** se pueden apagar uno por uno, y se agrega «Pedidos de la tienda (con sonido)».

### D · Opcional, más adelante: avisos con la app cerrada (Firebase)

- **Qué hace falta:**
  - crear el proyecto de Firebase;
  - poner `google-services.json` en la app;
  - una función en la nube que mande el aviso al llegar un pedido.
- **Qué permite:** que el pedido avise aunque la app esté cerrada del todo.
- **Por qué va aparte:** necesita configuración y cuentas fuera del código.

## Preguntas

1. ¿A, B y C juntas en la próxima versión, y D después?
2. ¿Te sirve el recordatorio de 2 horas, o prefieres otro tiempo?
