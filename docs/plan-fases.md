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

## 0.14.0 · Pro Servicios para cualquier negocio (antes 0.13.0)

**Objetivo:** que Pro Servicios sirva igual a un lavadero, una barbería, un spa, un taller, un servicio técnico o una lavandería. Detalle en `docs/plan-servicios-tipos.md`.
**Si llega una barbería antes de terminar,** se publica el Bloque A como 0.13.0 apenas esté listo, y el Bloque B sale como 0.13.1.

### Bloque A · Barbería, peluquería y spa (primero)

1. **Agenda de citas:**
   - por persona y por día, con la duración de cada servicio;
   - «Confirmada» y «No vino»;
   - recordatorio por WhatsApp (Pro Servicios);
   - al llegar el cliente, la cita pasa al tablero.
2. **Reservas en línea desde la tienda** (Pro Servicios):
   - solo horas libres, según horario, duración, citas existentes y margen;
   - la nube nunca deja dos citas a la vez;
   - confirmación automática y el cliente puede cancelar hasta cierto tiempo antes;
   - el dueño ve quién creó o cambió cada cita y cuándo.
3. **Precio por variante para todos:** corto/largo, moto/carro, pequeño/grande.
4. **Historial del cliente por teléfono:** qué se hizo, con quién y cada cuánto viene.
5. **Productos vendidos dentro del servicio:** pomada, shampoo. Salen del inventario.
6. **Alquiler de silla:** opción por persona, además de la comisión (Pro Servicios).
7. **Abono y pago mixto:** por ejemplo, efectivo + Nequi. Cuadra con la caja y los reportes.
8. **Anular sin borrar:** la venta queda «Anulada» en el historial y en los reportes, con el stock repuesto. Hoy «anular el cobro» de Servicios la borra.
9. **Servicios gratis hasta 3 personas:** catálogo, tablero, agenda y cobro. Pro Servicios: sin límite.

### Bloque B · Taller, servicio técnico y lavandería

10. **Estados según el tipo de negocio**, por ejemplo «Esperando aprobación», «Esperando repuesto» o «Lista para recoger». También fecha de entrega y cantidad con decimales (por kilo).
11. **Presupuesto:** por WhatsApp si el cliente no está, o aprobado en el local. Queda quién lo aprobó y cuándo.
12. **Recepción con fotos**, accesorios recibidos y garantía.
13. **Repuestos que salen del inventario** y se cobran en la orden.

### Para todos los tipos

14. **Revisar cada plantilla:** nombres, servicios de ejemplo, mensajes de WhatsApp y precios de referencia.
15. **Una prueba completa por tipo de negocio**, en el celular (360 px) y en el computador (1200 px), en claro y en oscuro.

**Supabase:** sí (citas, reservas, pagos, ventas anuladas, órdenes). Cada migración, con permiso.

## 0.15.0 · Equipo y planes (antes 0.14.0)

### Roles y permisos (`docs/plan-roles.md`)

1. Una sola lista de permisos (`permissions.dart`). Cada función nueva registra ahí los suyos.
2. Roles por defecto: Dueño, Administrador y Cajero. Plantillas para crear roles: Vendedor, Bodega, Solo ver, Encargado y Atiende servicios.
3. Roles personalizados: gratis 1, Pro y Pro Servicios sin límite. **Solo el dueño** los crea y edita.
4. Límites con números (Pro).
5. Autorización de un solo uso, nunca con PIN fijo, y arqueo ciego. Las dos cosas, gratis.
6. Horario de acceso (Pro Servicios).
7. Permisos que se cumplen también en Supabase.

### Planes, ingresos y seguridad

8. Quitar Pro Global: quedan Pro y Pro Servicios.
9. Elegir el plan por lo que se necesita.
10. Precio de Pro Servicios, cuando termine la negociación, y encender «Mostrar precios».
11. Aviso de vencimiento de Pro y renovar en un toque.
12. Recordatorios de cobro en pausa sin Pro.
13. MFA del panel admin.
14. Bloqueo opcional con PIN o huella para abrir la app.
15. Limpieza de seguridad: contraseña vieja, `crypto` y `legacy-login`.

### Ventas (movidas desde la 0.13.0)

16. Devolución parcial.
17. Cálculo del vuelto.
18. Precio sugerido por margen.
19. Cierre del día por WhatsApp: a mano en gratis, automático con Pro.
20. Recordatorio en el celular para cerrar la caja.

## 0.16.0 · Tienda y crecimiento (antes 0.15.0)

### Calidad y confianza

1. Todo en español (`flutter_localizations`).
2. Reporte automático de errores en el panel.
3. Indicador de sincronización.
4. «Descargar todos mis datos» (Ley 1581).
5. Primeros pasos para negocios nuevos.
6. Alerta de productos sin ventas en 30 días.
7. Revisión de Supabase y copia diaria verificada.

### Tienda y pedidos (Pro)

8. Pedidos con número, sección Pedidos y «Convertir en venta».
9. Aviso de pedido nuevo.
10. Nombre obligatorio y precio por unidad en el mensaje.
11. QR de la tienda y compartir un producto.
12. «Personalizar tienda»: portada, color, destacados, horario, modo oscuro, datos de pago y vista previa.
13. Estadísticas de la tienda.

### Crecimiento

14. Guías de instalación para Android, web e iPhone.
15. Página de novedades.
16. Meta de ventas.
17. Entrar con Google (y Apple).
18. Cupones desde el panel.

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
