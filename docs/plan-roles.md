# Roles y permisos personalizados

> **Estado:** **APROBADO el 10 nov 2026.** Va en la **0.14.0** (Equipo y planes). Solo es un plan: no se toca código hasta que el dueño lo apruebe.
> Pedido del dueño el 10 nov 2026: que desde un negocio gratis se puedan crear roles y darles permisos personalizados.

## 1. Cómo está hoy

- Hay **3 roles fijos**: Dueño (`OWNER`), Administrador (`ADMIN`) y Cajero (`CASHIER`).
- En la app, los permisos están escritos a mano en 12 archivos: `role == 'OWNER' || role == 'ADMIN'` para ver costos, editar productos, anular ventas, etc.
- En la nube, las reglas de seguridad (RLS) usan `my_business_role()` en 111 lugares. Solo distinguen esos 3 roles.
- No hay forma de crear un rol, ni de dar o quitar un permiso suelto.

## 2. Qué se propone

### 2.1 Roles listos

Se eligen con un toque al invitar a alguien y se pueden ajustar.

| Rol | Para quién | Puede | No puede |
|---|---|---|---|
| **Administrador** | La mano derecha del dueño | Todo, menos borrar el negocio y manejar Pro | — |
| **Cajero** | Quien cobra | Vender, fiar, abrir y cerrar su caja | Ver costos o ganancias, anular, editar productos |
| **Vendedor** | Quien atiende sin manejar plata | Vender y fiar | Abrir o cerrar caja, ver costos |
| **Bodega** | Quien recibe mercancía | Ver y recibir mercancía, ajustar stock, proveedores | Vender, ver ganancias |
| **Solo ver** | Contador o socio | Ver reportes y descargar Excel | Cambiar cualquier cosa |
| **Encargado** | Quien queda a cargo del local | Lo del cajero, más cerrar cajas de otros y recibir traslados (sedes) | Ver ganancias, cambiar precios |
| **Atiende servicios** | Lavador, barbero, técnico | Ver su tablero, sus citas y sus comisiones | Cobrar (si el dueño no lo permite), ver lo de otros |

El rol **Dueño** no se puede cambiar ni quitar.

### 2.2 Crear un rol propio

Pantalla en **Ajustes › Equipo › Roles**, con un nombre y casillas agrupadas por módulo. Se puede **partir de un rol listo** y cambiarle lo que haga falta.

| Módulo | Permisos |
|---|---|
| **Ventas** | Vender · Dar descuento · Fiar · Anular venta · Devolver · Ver solo mis ventas o las de todos · Cotizaciones |
| **Caja** | Abrir y cerrar mi caja · Cerrar la caja de otros · Entradas y salidas de dinero · Ver lo esperado en caja |
| **Inventario** | Ver · Crear y editar productos · Ver costos · Ajustar stock · Recibir mercancía · Proveedores y pedidos · Importar Excel · Catálogo |
| **Clientes** | Ver clientes · Crear y editar · Cobrar fiados · Ver deudas de todos |
| **Reportes** | Ver ventas · Ver ganancias · Descargar Excel |
| **Servicios** | Recibir trabajos · Asignar a otros · Cobrar trabajos · Agendar citas · Ver mis comisiones · Ver las de todos · Liquidar |
| **Ajustes** | Equipo e invitar · Autorizar a otros · Módulos · Datos del negocio · Tienda en línea · Nube y respaldo |

- Cada permiso tiene una frase que explica qué permite, por ejemplo: «Ver costos: el precio al que compras cada producto y cuánto ganas».
- Algunos permisos dependen de otros. Por ejemplo, «Anular venta» necesita «Vender», y la pantalla lo marca sola.

### 2.3 Límites con números

En vez de solo sí o no, algunos permisos llevan un tope:
- descuento máximo, por ejemplo 10 %;
- fiado máximo por cliente, por ejemplo $50.000;
- anular solo ventas del mismo día, o de las últimas N horas;
- salida de caja máxima sin autorización.

### 2.4 Autorización con PIN

Cuando alguien intenta algo que su rol no permite (un descuento más grande, anular una venta vieja):
- la app ofrece **«Pedir autorización»**;
- un administrador o el dueño pone **su PIN** en ese mismo celular;
- se hace la acción **una sola vez**, sin darle el permiso para siempre;
- queda en Actividad del equipo: quién lo pidió, quién autorizó y qué se hizo.

Con Pro Servicios, el dueño también puede **aprobar a distancia**: le llega un aviso al celular y toca «Aprobar».

### 2.5 Otras ideas que entran

- **Arqueo ciego:** si el rol no tiene «Ver lo esperado en caja», el cajero cuenta la plata sin ver cuánto debería haber. Solo el dueño ve la diferencia.
- **Horario de acceso:** la persona solo entra a la app en sus días y horas.
- **«Ver como»:** el dueño ve la app tal como la vería ese rol, antes de asignarlo.
- **Actividad:** cada cambio de rol o de permisos queda registrado: quién, cuándo y qué cambió.

## 3. Gratis, Pro y Pro Servicios

| | Gratis | Pro | Pro Servicios |
|---|---|---|---|
| Roles por defecto: Dueño, Administrador, Cajero | ✔ | ✔ | ✔ |
| Plantillas de la sección 2.1 para crear roles | ✔ | ✔ | ✔ |
| Ajustar las casillas de un rol listo | ✔ | ✔ | ✔ |
| Roles personalizados | **1** | sin límite | sin límite |
| Límites con números | — | ✔ | ✔ |
| Autorización de un solo uso (sección 6) | ✔ | ✔ | ✔ |
| Aprobar desde el celular del administrador (sección 6) | ✔ | ✔ | ✔ |
| Arqueo ciego | ✔ | ✔ | ✔ |
| Horario de acceso | — | — | ✔ |
| «Ver como» | ✔ | ✔ | ✔ |

- La autorización con PIN y el arqueo ciego son gratis porque **protegen la plata del negocio**, y eso le sirve a cualquiera.
- **Si el plan vence**, los roles propios siguen funcionando como estaban; **nunca se le quitan permisos a nadie de golpe**. Solo no se pueden crear roles nuevos ni editar los que pasan del límite. Los límites con números quedan como estaban.

## 4. Cómo se construye

**Una sola lista de permisos.** Igual que `app_functions.dart` para el buscador y los accesos, habrá un archivo con todos los permisos (`permissions.dart`). **Cada módulo o función nueva registra ahí sus permisos** y aparecen solos en la pantalla de roles.

**En la app:**
- Un servicio `Permissions.can(Perm.verCostos)` reemplaza las comparaciones `role == 'OWNER' || ...` de los 12 archivos.
- Los permisos se guardan en la base local, así funcionan **sin internet**.

**En la nube (lo más importante):**
- Tabla nueva `business_roles`: negocio, nombre, rol base (`ADMIN` o `CASHIER`), permisos y límites.
- `business_members` gana `role_id`. Se mantiene `role` (`OWNER`, `ADMIN`, `CASHIER`) como **rol base**, para que las versiones viejas de la app sigan funcionando.
- Función `has_permission(negocio, permiso)` para las reglas de seguridad (RLS). Los permisos **se cumplen también en la nube**, no solo ocultando botones.
- Las 111 reglas actuales **no se tocan de golpe**: siguen usando el rol base. Se cambian por `has_permission` solo donde un rol propio necesita algo distinto: anular, ajustar stock, cerrar caja, ver deudas.
- **Ver costos** es el caso difícil: hoy el costo viene en la misma fila del producto. Para que de verdad no lo vea quien no tiene permiso, la descarga de productos pasa por una función que quita el costo.
- **Toca Supabase:** migración nueva, que se aplica solo con permiso.

**Compatibilidad:**
- Los Administradores y Cajeros que existen hoy pasan solos a los roles listos «Administrador» y «Cajero», con los mismos permisos que tienen ahora.
- Nadie gana ni pierde nada al actualizar.

## 5. Etapas

1. **Lista de permisos y roles listos:**
   - `permissions.dart` y el servicio `Permissions.can`;
   - cambio de los 12 archivos;
   - roles listos, migración y compatibilidad.
2. **Roles propios:** pantalla de roles con casillas, «ver como», límite de 1 en gratis y actividad.
3. **Protección de la plata:** límites con números, autorización con PIN y arqueo ciego.
4. **Pro Servicios:** horario de acceso.

## 6. Respuestas del dueño (10 nov)

1. **Roles por defecto: Dueño, Administrador y Cajero**, los tres de hoy. **En el plan gratis se suma 1 rol personalizado.**
   - Los demás de la sección 2.1 (Vendedor, Bodega, Solo ver, Encargado, Atiende servicios) **no son roles aparte**. Son **plantillas** para crear un rol personalizado más rápido: se elige una, se le cambia lo que haga falta y se guarda.
   - En gratis, ese rol personalizado puede salir de una plantilla. Con Pro y Pro Servicios, sin límite.
   - La sección 2.1 se lee como «plantillas», y la tabla de la sección 3 queda: roles por defecto (3) en todos los planes, roles personalizados 1 / sin límite / sin límite.
2. (Igual que la 1.)
3. **Solo el dueño crea y edita roles.** Con sedes puede haber un administrador en cada una, y ninguno debe poder darse más permisos a sí mismo ni a otros. El administrador solo **asigna** roles que ya existen a las personas de su sede, y nunca el rol Administrador.
4. **Un PIN por persona, pero que no quede fijo.** El riesgo: el cajero ve el PIN que el administrador escribió una vez y una semana después lo usa para algo malo. Por eso **ya no se escribe un PIN fijo en el celular del cajero**:

### Autorización sin PIN fijo (reemplaza la sección 2.4)

**Con internet (lo normal):**
1. El cajero toca «Pedir autorización». Se envía la solicitud con el detalle: qué acción, monto, venta o cliente.
2. Al administrador o al dueño le llega un aviso **en su propio celular** con ese detalle, y toca «Aprobar» o «Rechazar».
3. La aprobación sirve **solo para esa acción** y vence en **5 minutos** si no se usa.

**Sin internet o si el administrador está al lado:**
1. El celular del cajero muestra un **número de solicitud** (por ejemplo, 4821).
2. El administrador abre «Autorizar» en **su** celular, escribe ese número y su app le da un **código de un solo uso** de 6 dígitos.
   - El código sale de la solicitud, de la hora y de una clave secreta de ese administrador. Funciona sin internet, como los códigos de los bancos.
3. El cajero escribe ese código. **Sirve una sola vez, solo para esa solicitud y por 2 minutos.** Si alguien lo ve, no le sirve para nada después.

**Protecciones:**
- El PIN personal del administrador solo se escribe en **su propio** celular, para abrir «Autorizar». Nunca en el del cajero.
- 3 códigos equivocados seguidos bloquean las autorizaciones en ese celular por 15 minutos, y se le avisa al dueño.
- **El dueño recibe un aviso de cada autorización**: quién pidió, quién aprobó y qué se hizo. Todo queda en Actividad del equipo.
- Si un administrador sale del equipo o cambia de rol, su clave de autorización deja de servir al instante.

**Planes:** esto protege la plata del negocio, así que **es gratis para todos**, también la aprobación desde el celular del administrador. Se quita «aprobar a distancia» de Pro Servicios: ya es para todos.

**En la nube:** tabla `auth_requests` (solicitud, acción, detalle, quién pidió, quién aprobó, estado, vence) y una clave secreta por administrador, que solo se descarga en su propio celular.

## 7. Últimas respuestas (10 nov)

1. **Prioridad alta.** Queda en la Fase 5 (0.16.0), antes de las sedes.
2. **Autorizar es un permiso más** del grupo Ajustes: «**Autorizar a otros**».
   - El dueño siempre puede autorizar. Los administradores lo traen encendido por defecto.
   - La plantilla **Encargado** también lo trae encendido, por si acaso.
   - En cualquier rol personalizado el dueño decide si lo da o no.
   - **Cada autorización queda registrada**: quién pidió, quién autorizó, con qué rol, en qué sede y qué se hizo. El dueño recibe un aviso.

No quedan preguntas abiertas en este plan. Falta que el dueño lo apruebe.

## 8. Diseño de la pantalla de roles (referencia del dueño, 10 nov)

El dueño mostró un video de referencia: una **matriz de roles y permisos con interruptores**. La pantalla **Ajustes › Equipo › Roles** seguirá esta idea, hecha por nosotros y sin copiar el código de la referencia. **El funcionamiento quedó aprobado el 10 nov. El aspecto es un diseño PROPUESTO:** se decide en el diseño final (ver `docs/referencias-diseno.md`).

> **No se hace con el diseño V1:** el dueño planea cambiar el diseño de la app. Esta pantalla se dibuja con el diseño nuevo cuando esté definido. Lo que queda fijo es **cómo funciona**: matriz, interruptores, contador, «Seleccionar todo», Dueño bloqueado, cambios marcados y barra para guardar.

**En el computador (matriz):**
- **Encabezado:** título «Roles y permisos», una frase («Define qué puede hacer cada rol; los cambios se aplican a todo el equipo») y, a la derecha, un **contador grande**: «17/32 permisos activos».
- **Una columna por rol.** Cada columna tiene:
  - el ícono del rol y su nombre (Dueño, Administrador, Cajero y los personalizados);
  - **una barra de puntos** que muestra cuántos permisos tiene («6/8»);
  - un botón **«Seleccionar todo»**, que cambia a «Quitar todo» cuando ya los tiene todos.
- **Filas agrupadas por módulo,** con el nombre del grupo en letra pequeña (VENTAS, CAJA, INVENTARIO…). Cada permiso lleva su nombre y una frase debajo («Anular venta · Deshacer una venta y devolver el stock»).
- **Interruptores grandes de un color por rol.** El encendido muestra un ✓ y tiene un pequeño rebote al cambiar.
- **El Dueño tiene todo encendido y bloqueado** (candado y «Siempre todo»): no se puede cambiar.
- **Ayudas al pasar el mouse:**
  - la fila y la columna se iluminan, para saber qué cruce se está tocando;
  - **un punto naranja junto a cada interruptor cambiado** que aún no se ha guardado.
- **Barra flotante abajo** cuando hay cambios: «● 4 cambios · Descartar · **Guardar**». Al guardar, el botón muestra que está trabajando y la barra se va.
- **Pie con leyenda:** ● cambios sin guardar · 🔒 bloqueado · teclas para moverse con el teclado (flechas y espacio).

**En el celular** (la matriz completa no cabe a 360 px):
- Arriba, **un rol a la vez**: chips para elegir el rol (Administrador, Cajero, Vendedor…), con su barra de puntos y «Seleccionar todo».
- Debajo, la misma lista agrupada por módulo, con un interruptor por permiso.
- Arriba a la derecha, el contador «17/32», y abajo la misma barra flotante de cambios y «Guardar».
- Si se prefiere ver todo junto en el celular, la matriz se puede deslizar de lado, con la columna de permisos fija a la izquierda.

**Del plan que se suma a este diseño:**
- Los permisos con **límite** (descuento máximo, fiado máximo) muestran un pequeño campo de número al encender el interruptor (Pro).
- Si un permiso depende de otro («Anular» necesita «Vender»), al encenderlo se enciende el otro y se avisa en una línea.
- **Botón «Ver como»** en cada columna.
- **Solo el dueño** ve esta pantalla con interruptores. Un administrador la ve **solo para leer**.
- Cada cambio guardado queda en **Actividad del equipo**.

