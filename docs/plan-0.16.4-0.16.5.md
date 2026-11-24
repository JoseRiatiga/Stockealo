# Plan para corregir la revisión de la web (0.16.4 y 0.16.5)

Fuente: `docs/revision-web-0.16.3.md`. Cada número (#) es un hallazgo de ese archivo.
Estado: **propuesta, esperando aprobación**. No se ha tocado código ni la nube.

## Resumen

| Fase | Versión | Qué arregla | Nube (Supabase) |
|---|---|---|---|
| 1 | 0.16.4 | Plata y datos: caja, devoluciones, reportes, Stocky, pantallas que no se actualizan | Opcional: corregir la hora de las cajas viejas |
| 2 | 0.16.4 | Vender y buscador: ventas en espera, Cobrar, descuentos, «Nueva venta» | No |
| 3 | 0.16.5 | Diseño viejo, textos cortados y cosas duplicadas | No |
| 4 | 0.16.5 | Mejoras: íconos de categoría, fotos en promociones, avisos, gastos | Sí: columna `icon` en categorías |

Las fases 1 y 2 salen juntas como 0.16.4, y las fases 3 y 4 como 0.16.5. La 0.17.0 queda para sedes, como está en el plan general.

---

## Fase 1 — Plata y datos (0.16.4) · prioridad alta

1. **Hora de la caja (#1).** Guardar en la nube las horas con zona horaria (`toUtc()`) en `cash_session.dart` y en los movimientos de caja. Revisar si las demás tablas tienen el mismo problema. *Opcional:* corregir las cajas ya guardadas (requiere permiso, porque toca la nube).
2. **Salidas de caja (#2).** No dejar sacar más que el efectivo disponible (ver decisión D3) y poner un tope razonable a los valores. El negativo se escribe «-$», no «$-».
3. **Anular un movimiento de caja (#6).** Se anula con un movimiento contrario que diga «Anulado» y quién lo hizo; no se borra.
4. **Devolución de venta mixta (#3).** Preguntar por qué medio se devuelve la plata (efectivo, Nequi…). Restar de ese medio en Ventas y Caja, y que no aparezca «Mixto» en negativo.
5. **Reportes (#29, #30, #31).** Sacar las devoluciones de «ventas por debajo del costo», repartir el pago mixto igual que en Caja y agrupar productos por `product_id`. Que Inicio, Caja, Ventas y Reportes usen un mismo cálculo.
6. **Stocky (#48).** Mostrar todos los medios de pago (Nequi, Tarjeta, Mixto) con el mismo cálculo del punto 5, usar la moneda del negocio y escribir los textos con mayúscula solo al inicio.
7. **Pantallas que no se actualizan (#44, que incluye #26, #32 y #35).** Crear avisos de productos, clientes y stock en `DataEvents`, y que abonos y compras de contado avisen a la caja. Así Vender, Caja, Inicio y Stock se refrescan solos.
8. **Ventas por comprobante (#7).** Mostrar una tarjeta por venta, con «4 productos» adentro, y la devolución con su rótulo «Devolución».
9. **Compra de contado (#35).** Decir en la entrada «Sale de la caja: $116.000» y avisar si el efectivo no alcanza.

## Fase 2 — Vender y buscador (0.16.4)

1. **Ventas en espera y cotizaciones en celular y a 1024 px (#4, #49),** y el contador «En espera» que no baja (#5).
2. **Botón «Cobrar» siempre visible** en el panel del computador (#13), y «Transferencia» completo (#14).
3. **Descuentos (#8).** Avisar si el descuento por línea pasa del total, mostrar el aviso de pérdida junto a esa línea y usar la misma ventana para los dos descuentos.
4. **Hora del recibo en 12 h (#11).**
5. **«Nueva venta» del encabezado (#22)** según la decisión D2. Actualizar «Dónde quedó cada cosa» (#55).
6. **Scroll en toda la pantalla (#61):** que la rueda del mouse funcione en cualquier parte y la barra quede en el borde derecho (`content_width.dart`). Además, barra con diseño propio en un solo lugar (`ScrollbarThemeData` en el tema): delgada y redondeada, en el gris del tema; se ensancha al pasar el mouse, toma el color del negocio al arrastrarla y se esconde sola cuando no se usa. Igual en claro y oscuro.
7. **Buscador.** Que busque clientes (#45), que Ctrl K funcione siempre (#46) y que tenga más funciones con sinónimos (#47).

## Fase 3 — Diseño y duplicados (0.16.5)

1. **Textos cortados** a 1024 y 1280 px y en el celular (#12, #38, #60).
2. **Diseño viejo:**
   - ventana de abono (#33), con los mismos medios de pago que Vender;
   - calendario de vencimiento (#34);
   - Editar producto (#17);
   - íconos de Gestionar categorías (#23);
   - encabezado de «Tu negocio» y la palabra «Tiquete» (#56);
   - chip «Todas» que no se lee (#15);
   - tarjetas de producto con espacio vacío (#16).
3. **Pantallas sin menú lateral (#41):** Detalle y Editar producto, Promociones, Entrada de mercancía, Equipo y Módulos, que se abran dentro del diseño con menú.
4. **Duplicados:**
   - «Vender» y «Registrar venta» en el detalle del producto (#9);
   - «Cerrar sesión» en 3 lugares y «Términos» en 2 (#50, decisión D5);
   - dos formas de invitar (#52);
   - Metas desde Inicio que lleve a Reportes › Metas (#27);
   - encabezado de Stock igual al de Productos (#36).
5. **Cosas que confunden:**
   - «Stock Actual» editable sin dejar historial (#10);
   - «Borrar datos / Eliminar la cuenta» (#54);
   - permisos del Dueño que parecen editables y «Crear rol» sin explicación (#51);
   - «Enviar el cierre» en Metas (#58);
   - huella en la web (#59);
   - «Todo» contra «Todas» y «Sin guardar» en la vista previa (#40);
   - Proveedores angosto (#37);
   - Stocky tapando montos (#18, #60).

## Fase 4 — Mejoras (0.16.5)

1. **Íconos de categoría (#28).** El ícono se sugiere por el nombre y se puede cambiar a mano. Se usa en la tienda, Vender y Productos, con un interruptor en la tienda para mostrarlo u ocultarlo. **Requiere migración:** columna `icon` en `categories`, en SQLite y en Supabase.
2. **Promociones.** Miniatura en «Productos marcados» (#24) y fechas en una ventana emergente con atajos (#25); lo mismo para el filtro de fechas de Ventas.
3. **Nombre del producto en ventas viejas (#26),** según la decisión D1.
4. **Tienda sin WhatsApp:** avisar o no dejar publicar (#39).
5. **Reportes:** restar los gastos de caja de la ganancia neta (#43).
6. **Ajustes › Avisos:** elegir qué notificaciones llegan (#53).
7. **Módulos:** que cada fila se pueda tocar para ir a la función (#57).
8. **Detalles:** pago mixto con una parte fiada (#19), puntos de mil mientras se escribe (#20) y ejemplos de promociones según el tipo de negocio (#21).
9. **Arranque más rápido (#42):** mostrar el último negocio mientras carga.

---

## Decisiones APROBADAS (16 nov)

- **D1.** Listas y reportes con el nombre actual; el recibo con el nombre del día de la venta.
- **D2.** «Nueva venta» se queda: dentro de Vender deja la cuenta en espera y abre una nueva.
- **D3.** No se puede sacar más que el efectivo de la caja; se muestra cuánto hay.
- **D4.** Solo se arregla lo nuevo; las cajas viejas se corrigen después por país, con permiso.
- **D5.** «Cerrar sesión» queda solo en «Salir» del menú lateral; se quitan los repetidos.
- **D6.** Fase 1 sola, publicada como 0.16.4. La Fase 2 pasa a la 0.16.5, y las fases 3 y 4 se corren una versión.

## Opciones que se presentaron

- **D1. Nombre del producto en ventas viejas.** (a) Listas y reportes con el nombre actual, y el recibo con el nombre de ese día. *Recomendado.* (b) Todo con el nombre actual. (c) Dejarlo como está.
- **D2. «Nueva venta» del encabezado.** (a) Quitarlo. (b) Que en Vender deje la cuenta en espera y abra una nueva. *Recomendado.* (c) Ocultarlo dentro de Vender.
- **D3. Salida de caja mayor que el efectivo.** (a) Bloquearla. *Recomendado.* (b) Dejarla, pero pedir confirmación.
- **D4. Horas de las cajas viejas en la nube.** ¿Las corrijo con una migración (restar 5 h a las ya guardadas) o solo arreglo lo nuevo?
- **D5. Dónde queda «Cerrar sesión».** (a) Solo en Ajustes. (b) Solo en el menú lateral, con «Salir». *Recomendado:* menú lateral.
- **D6. Orden de trabajo.** ¿Empiezo por la Fase 1 sola, o hago las fases 1 y 2 juntas para la 0.16.4?

## Cómo se trabaja cada fase

- Rama nueva desde main, por ejemplo `fix/0.16.4`. Nada de commit, push, PR ni migraciones sin tu permiso.
- Pruebas automáticas de cada cálculo que se toque: caja, devoluciones, reportes y Stocky.
- Revisión de Codex (solo lectura) antes de publicar.
- Recorrido en la web publicada para confirmar cada hallazgo cerrado y marcarlo en `revision-web-0.16.3.md`.
