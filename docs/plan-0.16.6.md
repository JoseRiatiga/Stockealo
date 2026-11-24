# Plan 0.16.6 — Fase 2: Vender, buscador y hora del negocio

Fuente: `docs/revision-web-0.16.3.md` (cada # es un hallazgo) y `docs/plan-0.16.4-0.16.5.md`.
Estado: **APROBADO por el dueño el 17 nov 2026**, con la hora del negocio DENTRO de esta versión.
Rama: `fix/0.16.6` en Desktop/Stockealo (una sola carpeta, sin worktrees).

## Vender
1. Ventas en espera y cotizaciones visibles en celular y a 1024 px (#4, #49): fila de botones arriba de los productos en todos los tamaños (hoy solo desde 900 px, `SellScreen.wideFrom`).
2. El contador «En espera» baja al retomar (#5).
3. «Cobrar» fijo abajo del panel de la cuenta (#13).
4. «Transferencia» completa (#14).
5. Descuentos (#8): aviso si el de línea pasa el total, aviso de pérdida junto a la línea, misma ventana para ambos con «Máximo sin perder».
6. «Nueva venta» (D2, #22): en Vender deja la cuenta en espera y abre una vacía. Actualizar «Dónde quedó cada cosa» (#55).
7. Recibo en 12 h (#11, `sale_document.dart:181`).

## Ventas
8. «Ventas registradas» cuenta comprobantes: «4 ventas · 1 devolución»; la devolución es tarjeta aparte que no suma (N3).

## Buscador
9. Clientes (#45), Ctrl K global (#46), más funciones con sinónimos (#47).

## Toda la app
10. Scroll en toda la pantalla y barra con diseño propio (#61): `content_width.dart` + `ScrollbarThemeData` (22 archivos usan ContentWidth).

## Datos y nube
11. Comprobante, vendedor y descuento en la nube: columnas nuevas en `sales` (`invoice_number`, `seller_name`, `discount_amount`). Al actualizar, cada equipo sube los comprobantes que tiene guardados (N1).
12. **Hora del negocio (reemplaza N2 y cubre el #62). Camino simple, decidido el 17 nov:**
    - La nube sigue guardando la hora del reloj del negocio, como hasta ahora (no hay UTC real ni corrección de horas guardadas ni freno a la app vieja; la base del equipo no cambia y `wallClockIso` se queda).
    - Cada negocio guarda su zona (`businesses.time_zone`); por defecto, la de su país. EE. UU. y México la eligen (por defecto Nueva York y Ciudad de México).
    - La app toma «ahora» y «hoy» con la zona del negocio aunque el equipo tenga otra.
    - Regla del servidor para anular: compara con la hora del negocio, no con UTC.
    - «Metas por vendedor» manda el periodo con la hora del negocio.
    - UTC real queda para cuando se planee la facturación electrónica, con su propio plan.
13. Hallazgo 63: prueba primero. Si el stock queda bien (según el código, sí), solo juntar los movimientos en uno claro: «Venta anulada: vuelven N».

## Arreglo agregado (17 nov)
14. Panel admin: bucle al iniciar sesión (la verificación en dos pasos se borraba y creaba sin parar hasta que la nube frenaba la sesión). Va con la 0.16.6.

## Nube (cada una con permiso, ensayada antes)
- Migración A: columnas de comprobante, vendedor y descuento en `sales`, y `time_zone` en `businesses`.
- Migración B: la regla de anular usa la hora del negocio.

## Cómo se trabaja
Pruebas automáticas de cada cálculo; revisión de Codex de solo lectura; recorrido en la web publicada; nada de commit, push, PR ni migraciones sin permiso.
