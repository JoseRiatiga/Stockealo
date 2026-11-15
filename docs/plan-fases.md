# Plan de actualizaciones de Stockealo (desde la 0.12.1)

> **Estado:** **APROBADO por el dueño el 10 nov 2026.** Cada actualización se programa por bloques dentro de una rama, con pruebas y commit (con permiso) en cada bloque, y se publica junta.
> Junta las fases viejas (F1 a F7, del 3 nov) con lo pendiente. Va de mayor a menor prioridad.
> Planes de detalle: `docs/plan-servicios-tipos.md`, `docs/plan-roles.md` y `docs/plan-sedes.md`.
> Regla de versiones: se sigue en 0.x hasta estar en Google Play o App Store.
> Si aparece un error urgente en lo publicado, sale un arreglo pequeño (0.13.1, por ejemplo) sin esperar la actualización grande.

## Ya hecho de las fases viejas (no se repite)

- La tienda en línea (0.9.2).
- Vista en lista o cuadrícula.
- «Sugerencias y fallos» (0.12.0).
- Comparar con el periodo anterior en Inicio.
- Proveedores y cuentas por pagar (0.10.1).
- Caja con arqueo (0.12.0).
- El cajero no ve costos.
- Mantenimiento programado.

## Descartado por el dueño

Invita y gana, contador de cupos de fundador, prueba gratis de Pro.

---

## 0.12.1 · Arreglos (se publica ya)

1. **Ya hecho, sin commit:**
   - modo claro u oscuro con un solo interruptor y botón junto a la campana;
   - accesos rápidos de vuelta en Inicio (salen de la lista del buscador);
   - «N por reponer · Ver cuáles» baja hasta la lista filtrada.
2. **Buscador en el diseño V1.** Hoy tiene fondo morado y colores fijos.
3. **Aviso «VideoFrame» y primera carga de la web** (prioridad del dueño), en una **rama aparte**:
   - actualizar Flutter desde la 3.24.5 y revisar la app, el APK, el panel y las tiendas;
   - si el aviso sigue, cambiar la forma en que la web decodifica las imágenes;
   - carga más rápida: medir antes y después, pantalla con el logo, partes que bajan solo al usarlas (panel, Reportes, importador), fuentes, íconos y caché.
   - **No frena la 0.12.1:** si se complica, se publica sin esto y llega con la 0.13.0.

## 0.13.0 · RE-DISEÑO completo (decisión A del dueño, 11 nov)

Va antes que Pro Servicios, para no hacer pantallas dos veces. Bloques y detalle: `docs/plan-rediseno.md`, sección 9. Diseño final aprobado: https://claude.ai/artifact/JQtmF7vnoWhwMBujRAMitb
Absorbe de la 0.14.0: pago mixto, vuelto y anular sin borrar (porque Vender y Ventas se rehacen).

## PRIORIDAD · Re-diseño del panel admin (antes de la 0.14.0, pedido del dueño el 14 nov) — HECHO el 14 nov (rama feat/0.14.0)

- En la 0.13.2 el panel admin solo pasó la letra y las ventanas al sistema de diseño (bloque 8b). **La distribución sigue siendo la vieja.**
- Rehacerlo con el diseño aprobado de la app:
  - menú lateral como el de la app;
  - cifras en tarjetas (`StatCard`) en Resumen y Salud;
  - pestañas `FilterTabs` en los filtros;
  - listas de usuarios, negocios, suscripciones, pagos y tiendas con el estilo de Clientes;
  - el detalle en panel lateral (`AppSidePanel`);
  - modo oscuro, y probado a 1200 px y en el celular.

## 0.14.0 · Pro Servicios para cualquier negocio (antes 0.13.0)

**Objetivo:** que Pro Servicios sirva igual a un lavadero, una barbería, un spa, un taller, un servicio técnico o una lavandería. Detalle en `docs/plan-servicios-tipos.md`.
**Si llega una barbería antes de terminar,** se publica el Bloque A como 0.13.0 apenas esté listo, y el Bloque B sale como 0.13.1.

### Bloque A · Barbería, peluquería y spa (primero)

1. HECHO (14 nov). **Agenda de citas:**
   - por persona y por día, con la duración de cada servicio;
   - «Confirmada» y «No vino»;
   - recordatorio por WhatsApp (Pro Servicios);
   - al llegar el cliente, la cita pasa al tablero.
2. HECHO (14 nov). **Reservas en línea desde la tienda** (Pro Servicios):
   - solo horas libres, según horario, duración, citas existentes y margen;
   - la nube nunca deja dos citas a la vez;
   - confirmación automática y el cliente puede cancelar hasta cierto tiempo antes;
   - el dueño ve quién creó o cambió cada cita y cuándo.
3. HECHO (14 nov). **Precio por variante para todos:** corto/largo, moto/carro, pequeño/grande.
4. HECHO (14 nov). **Historial del cliente por teléfono:** qué se hizo, con quién y cada cuánto viene.
5. HECHO (14 nov), al cobrar. **Productos vendidos dentro del servicio:** pomada, shampoo. Salen del inventario.
6. HECHO (14 nov). **Alquiler de silla:** opción por persona, además de la comisión (Pro Servicios).
7. HECHO (14 nov). **Abono y pago mixto:** por ejemplo, efectivo + Nequi. Cuadra con la caja y los reportes.
8. HECHO (14 nov). **Anular sin borrar:** la venta queda «Anulada» en el historial y en los reportes, con el stock repuesto. Hoy «anular el cobro» de Servicios la borra.
9. HECHO (14 nov). **Servicios gratis hasta 3 personas:** catálogo, tablero, agenda y cobro. Pro Servicios: sin límite.

### Bloque B · Taller, servicio técnico y lavandería

10. HECHO (14 nov). **Estados según el tipo de negocio**, por ejemplo «Esperando aprobación», «Esperando repuesto» o «Lista para recoger». También fecha de entrega y cantidad con decimales (por kilo).
11. HECHO (14 nov). **Presupuesto:** por WhatsApp si el cliente no está, o aprobado en el local. Queda quién lo aprobó y cuándo.
12. HECHO (14 nov). **Recepción con fotos**, accesorios recibidos y garantía.
13. HECHO (14 nov), al cobrar. **Repuestos que salen del inventario** y se cobran en la orden.

### Para todos los tipos

14. HECHO (14 nov). **Revisar cada plantilla:** nombres, servicios de ejemplo, mensajes de WhatsApp y precios de referencia.
15. HECHO (14 nov). **Una prueba completa por tipo de negocio**, en el celular (360 px) y en el computador (1200 px), en claro y en oscuro.

**Supabase:** sí (citas, reservas, pagos, ventas anuladas, órdenes). Cada migración, con permiso.

### Pendientes que se suman (14 nov)

16. HECHO (14 nov). **Cada servicio con su propia tarjeta en el tablero:** se mueve cada servicio, no el vehículo completo. Lo pidió el lavadero. **Prioridad.**
17. HECHO (14 nov). **«Habilitar múltiples servicios» en la nube:** hoy se guarda solo en el aparato.
18. HECHO (14 nov). **Liquidación de comisiones y orden de servicio como tiquete.**
19. HECHO (14 nov): preguntar «solo este servicio o todo el cobro». **Antes de programar, preguntar al dueño:** ¿anular un servicio desde Ventas anula todo el cobro de esa orden?
20. HECHO (14 nov). **«¿Para qué usarás Stockealo?» al crear un negocio nuevo** (decidido el 14 nov):
    - **La respuesta queda guardada** en el negocio. Se puede saltar con «Ahora no» y responder después en Ajustes › Tu negocio.
    - **Si compra Pro Servicios**, al abrir Servicios la plantilla que corresponde sale **marcada por defecto como sugerencia**. Por ejemplo, quien eligió «Lavadero» ve «Lavadero» ya marcado, y puede cambiarlo.
    - Si eligió un tipo de productos, Servicios no marca ninguna.
    - Las plantillas de productos (licorera, vapers…) llegan en la 0.16.0 (punto 16).

## 0.15.0 · Equipo y planes (antes 0.14.0)

### Roles y permisos (`docs/plan-roles.md`)

1. HECHO (14 nov). Una sola lista de permisos (`permissions.dart`). Cada función nueva registra ahí los suyos.
2. HECHO (14 nov). Roles por defecto: Dueño, Administrador y Cajero. Plantillas para crear roles: Vendedor, Bodega, Solo ver, Encargado y Atiende servicios.
3. HECHO (14 nov), con «Ver como» y la matriz de interruptores. Roles personalizados: gratis 1, Pro y Pro Servicios sin límite. **Solo el dueño** los crea y edita.
4. HECHO (14 nov). Límites con números (Pro).
5. HECHO (14 nov). Autorización de un solo uso (solo con internet, decisión del dueño) y arqueo ciego. Las dos cosas, gratis. También: cada acción revisa el permiso del rol.
6. HECHO (15 nov). Horario de acceso (Pro Servicios): por persona, la app avisa 10 minutos antes y bloquea fuera de turno. Migración access_schedule aplicada con permiso.
7. HECHO (14 nov), opción A de `docs/plan-permisos-nube.md`: migraciones permissions_in_cloud y limit_cashier_updates_roles aplicadas y probadas con un cajero simulado. «Ver costos»: opción 1 del dueño (15 nov): se oculta en las pantallas y la nube pone el costo de cada venta desde el producto (migración sale_cost_from_product aplicada). Permisos que se cumplen también en Supabase. La revisión con Codex del 14 nov lo confirmó: hoy los límites y permisos se cumplen solo en la app; las ventas y los movimientos de caja se pueden insertar directo en la nube.

### Planes, ingresos y seguridad

8. HECHO (15 nov). Quitar Pro Global: quedan Pro y Pro Servicios (no había suscripciones Global).
9. HECHO (15 nov). Elegir el plan por lo que se necesita («¿Qué necesitas para tu negocio?» en la pantalla de Pro; sin sedes por ahora).
10. Precio de Pro Servicios, cuando termine la negociación, y encender «Mostrar precios».
11. HECHO (15 nov). Aviso de vencimiento de Pro (7 días antes y hasta 15 después, en Inicio) y renovar en un toque.
12. HECHO (15 nov). Recordatorios de cobro en pausa sin Pro (vuelven solos al renovar).
13. MOVIDO a la 0.16.0 (decisión del dueño, 15 nov). MFA del panel admin.
14. MOVIDO a la 0.16.0 (decisión del dueño, 15 nov). Bloqueo opcional con PIN o huella para abrir la app.
15. MOVIDO a la 0.16.0 (decisión del dueño, 15 nov). Limpieza de seguridad: contraseña vieja, `crypto` y `legacy-login`.

### Ventas (movidas desde la 0.13.0)

16. HECHO (15 nov). Devolución parcial: cuántas, si vuelven al inventario o llegaron dañadas, y el dinero según cómo pagó (efectivo sale de la caja, fiado baja la deuda). La nube pide «Devolver» y no deja devolver de más.
17. HECHO (ya estaba: «Recibí» con atajos y el vuelto en grande). Cálculo del vuelto.
18. HECHO (15 nov). Precio sugerido por margen (20, 30, 40 y 50 % en el formulario del producto).
19. HECHO (15 nov). Cierre del día por WhatsApp: a mano en Reportes; con Pro, el aviso de la noche lo deja listo.
20. HECHO (15 nov). Recordatorio en el celular para cerrar la caja (7:00 p. m., se cambia en Ajustes › Avisos).

### Pendientes que se suman (14 nov)

18. HECHO (15 nov). **Descuento por línea en Vender**, además del descuento a toda la venta.
19. HECHO (15 nov). **Las ventas en espera no se pierden al cerrar la app:** hoy viven solo en memoria.
20. **El tiquete con NIT, dirección y despedida propia del negocio.**
21. **Stocky:** límite mayor para Pro (50 preguntas al día) y las claves de respaldo (Gemini y OpenRouter).
22. **Seguridad:** el código del correo vence a los 10 minutos (revisar en Supabase).
23. HECHO (14 nov). **Portada propia en la tienda en línea** (pedido del dueño): «Fotos de productos», «Mi propia foto» o «Sin fotos». Migración store_cover aplicada con permiso.
24. HECHO (14 nov). **Tallas y colores en la tarjeta de la tienda**, con lo agotado tachado en diagonal y el carrito que agrega directo.
25. HECHO (14 nov). **Carrito en dos pasos:** el pedido con foto, talla y color; después los datos del comprador.
26. HECHO (14 nov). **Una foto por color** en los productos, en la tarjeta y en el carrito. Migración variant_color_photos aplicada con permiso.
27. HECHO (14 nov). **Tienda en línea:** la tarjeta de tienda publicada con el diseño nuevo.

## 0.16.0 · Tienda y crecimiento (antes 0.15.0)

### Movidos desde la 0.15.0 (15 nov)

- MFA del panel admin (necesita la app de códigos en el celular del dueño).
- Bloqueo opcional con PIN o huella para abrir la app (librería local_auth y cambio en Android; probar en un celular real).
- Limpieza de seguridad: contraseña vieja, `crypto` y `legacy-login` (antes, revisar si alguien todavía los usa).

### Calidad y confianza

1. Todo en español (`flutter_localizations`).
2. Reporte automático de errores en el panel.
3. Indicador de sincronización.
4. «Descargar todos mis datos» (Ley 1581).
5. Primeros pasos para negocios nuevos.
6. Alerta de productos sin ventas en 30 días.
7. Revisión de Supabase y copia diaria verificada.

### Tienda y pedidos (Pro)

8. ~~Pedidos con número, sección Pedidos y «Convertir en venta».~~ HECHO en la 0.13.4 (T-0001, Cotizaciones «Tienda», «Por entregar»).
9. ~~Aviso de pedido nuevo.~~ HECHO en la 0.13.5 con la app abierta o en segundo plano (`docs/plan-avisos.md`).
10. ~~Nombre obligatorio y precio por unidad en el mensaje.~~ HECHO en la 0.13.3.
11. **Avisos con la app cerrada (Firebase), fase D de `docs/plan-avisos.md`:**
    - el pedido de la tienda avisa aunque la app esté cerrada del todo;
    - sirve también para los demás avisos que lleguen de la nube.
    - Hace falta:
      - crear el proyecto de Firebase;
      - poner `google-services.json` en la app;
      - guardar el token de cada celular en la nube;
      - una función que mande el aviso al crearse un pedido (`create_store_order`).
12. QR de la tienda y compartir un producto.
13. **Plantillas de tienda nuevas** (decidido el 14 nov; van todas):
    - **Mercado:** lista compacta con botón +, para tiendas de barrio, misceláneas y droguerías.
    - **Menú:** cada categoría como sección de una carta, para comidas, panaderías y heladerías.
    - **Boutique:** fotos grandes y mucho espacio, para joyería, cosméticos y artesanías.
    - Con Clásica y Moda quedan 5, con vista previa usando los productos del negocio.
14. **Catálogos al día y a juego con la tienda:**
    - las 4 plantillas actuales (Clásica, Vitrina, Lista de precios y Promoción) pasan al diseño nuevo, con la cinta de promociones;
    - se agregan **Moda** y **Menú**;
    - el catálogo sale por defecto con el mismo estilo de la tienda.
15. **Instagram** (decidido el 14 nov). Hoy solo hay historias 9:16:
    - **Formatos:** historia 9:16, publicación cuadrada 1:1, vertical 4:5 y **carrusel** (hasta 10 imágenes, una por producto).
    - **Enlace:** el link o el QR de la tienda en la imagen («Pide en stockealo.online/tienda/…»).
    - **Texto listo para copiar:** nombre, precios, promoción, link y hashtags del negocio.
    - **Compartir directo:** «Compartir en Instagram» abre Instagram con la imagen; en Android, directo a la historia.
    - **Estilo:** las mismas plantillas de la tienda y del catálogo, y con Pro la cinta de promociones.
16. **Plantillas por tipo de negocio que vende productos** (decidido el 14 nov):
    - **Cómo se activa:** es una opción, igual que el módulo Servicios, que la primera vez pregunta «¿Qué tipo de negocio es?». La pregunta es **«¿Para qué usarás Stockealo?»**, y según la respuesta se carga la plantilla.
    - **Qué carga:** categorías sugeridas (se pueden quitar), variantes útiles, avisos y el estilo de la tienda y del catálogo.
    - **Primeros tipos:**
      - **Licorera:** categorías, presentación en ml, aviso +18 y tienda «Mercado».
      - **Vapers** (tipo nuevo): desechables, pods, líquidos y accesorios; sabor y nicotina en mg como variantes; aviso +18; tienda «Boutique».
      - **Droguería:** categorías, vencimiento por lote y tienda «Mercado».
      - **Ropa y calzado:** tallas y colores como variantes, y tienda «Moda».
      - **Comidas y panadería:** categorías tipo carta y tienda «Menú».
      - **Tienda de barrio o miscelánea:** categorías de barrio y tienda «Mercado».
    - La pregunta «¿Para qué usarás Stockealo?» al crear el negocio se hace en la **0.14.0** (punto 20). Aquí solo se suman las opciones de productos.
    - Las plantillas de servicios (Lavadero, Barbería, Spa, Taller, Servicio técnico y Lavandería) ya funcionan así y se revisan en la 0.14.0.
17. «Personalizar tienda»: portada, color, destacados, horario, modo oscuro, datos de pago y vista previa.
18. Estadísticas de la tienda.

### Crecimiento

19. Guías de instalación para Android, web e iPhone.
20. Página de novedades.
21. Meta de ventas.
22. Entrar con Google (y Apple).
23. Cupones desde el panel.

### Pendientes que se suman (14 nov)

24. **Dirección limpia de la tienda:** quitar el `?t=` de la barra con `history.replaceState`.
25. **Panel «Resolver» de Inicio:** los interruptores «Recordarme si no llega» y «Ocultarlo en Vender».
26. **Lector de códigos:** arrastrar o pegar una foto.
27. **Correo propio (SMTP)**, cuando crezcan los usuarios o haya errores de límite de envío.

## 0.17.0 · Sedes y negocio (antes 0.16.0)

### Sedes (Pro Servicios, `docs/plan-sedes.md`)

1. Antes de programar, responder las 4 preguntas que quedan.
2. Principal y 2 sedes incluidas. Extra desde +1, con descuento por cantidad.
3. Traslados con confirmación, fiados por sede, encargado de turno (usa los roles de la 0.14.0) y una sola tienda.

### Lo que piden las tiendas y los servicios

4. Combos o kits e insumos de servicios.
5. Precios por cantidad y al por mayor (Pro).
6. Ofertas (Pro).
7. Gastos y ganancia real.
8. Venta por peso o medida.
9. Vencimiento por lote.
10. Conteo de inventario.
11. Pedido sugerido al proveedor.
12. Impresora térmica.
13. Widget del celular.

### Clientes e IA

14. Clientes frecuentes.
15. Puntos (Pro).
16. Stocky que avisa solo.
17. Productos por voz o foto.
18. Mensajes desde el panel.
19. Centro de ayuda.
20. App más liviana.

---

## Para después (sin actualización asignada)

- Facturación electrónica DIAN (cada negocio conecta su cuenta).
- Mercado Pago.
- Vista previa al compartir la tienda.
- Reporte semanal.
- Lector de facturas con IA.
- Google Play (ahí se pasa a 1.0.0).

## Tareas del dueño (fuera del código)

- Probar la 0.12.0 con «LAVADERO» y Pro Servicios.
- Negociar con el lavadero (define el precio).
- Perfil de Google Business y videos cortos.
