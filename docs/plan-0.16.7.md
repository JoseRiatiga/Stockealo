# Plan 0.16.7 — Fase 3: diseño y duplicados

Fuente: `docs/revision-web-0.16.3.md` (cada # es un hallazgo) y la Fase 3 de `docs/plan-0.16.4-0.16.5.md`.
Estado: **APROBADO por el dueño el 17 nov 2026**, con E1 (a), E2 (a) y E3 (a).
Rama: `fix/0.16.7` en Desktop/Stockealo. No necesita migraciones en la nube.

## 1. Textos cortados (#12, #38, #60)
- Títulos y buscador del encabezado a 1024 y 1280 px.
- Menú lateral: «Clientes y proveedores», el nombre del negocio y «Salir».
- En el celular, «Caja abierta desde…» en el encabezado.
- En el celular, Escape cierra el menú lateral.

## 2. Pantallas con el diseño viejo
- Ventana de abono (#33): textos del diseño nuevo, ejemplo según la deuda y los mismos medios de pago que Vender (Nequi y Tarjeta incluidos).
- Calendario de vencimiento en Entrada de mercancía (#34): abre en una fecha cercana, avisa antes de guardar y usa el calendario con el diseño de la app.
- Editar producto (#17): textos sin mayúsculas en cada palabra.
- Gestionar categorías (#23): íconos grises de acción, sin colores sueltos.
- «Tu negocio» (#56): el mismo encabezado que el resto y «recibo» en lugar de «tiquete».
- Productos (#15, #16): el chip «Todas» se lee en modo oscuro y las tarjetas no dejan espacio vacío.

## 3. Pantallas sin menú lateral (#41, decisión E1)
Detalle y Editar producto, Promociones, Entrada de mercancía, Vista previa de la tienda, Equipo y Módulos.

## 4. Duplicados
- Detalle de producto: queda solo «Vender» y se quita «Registrar venta» (#9).
- «Cerrar sesión» solo en «Salir» del menú lateral (decisión D5). «Términos y privacidad» queda solo en Ajustes (#50).
- Equipo: una sola forma de invitar (#52, decisión E3).
- Metas desde Inicio lleva a Reportes › Metas; crear la primera meta sigue en Inicio (#27).
- Stock deja de repetir el encabezado de Productos (#36, decisión E2).

## 5. Cosas que confunden
- «Stock Actual» en Editar producto: ya no se escribe ahí; un botón «Ajustar stock» deja el historial (#10).
- Ajustes › «Borrar datos»: dice claro qué borra cada opción; en la web, «Eliminar mi cuenta» (#54).
- Roles: los permisos del Dueño se ven bloqueados; «Crear rol» explica por qué está apagado; el ícono de Roles en Equipo lleva texto (#51).
- Reportes › Metas: se quita «Enviar el cierre del día», que es de Ganancias (#58).
- En la web, «Bloquear la app» dice «Pide PIN», sin huella (#59).
- Vista previa de la tienda: «Todas», como en la app, y «Sin guardar» solo si hay cambios (#40).
- Proveedores usa todo el ancho, como Clientes (#37).
- Stocky no tapa montos en Caja ni la etiqueta «Hoy» del gráfico de Inicio (#18, #60).

## Decisiones
- **E1. Pantallas sin menú lateral.**
  - (a) *Recomendado.* Se abren dentro del contenido, con el menú a la izquierda, como el resto de la app. Es un cambio de navegación: se hace una vez y sirve para toda pantalla nueva.
  - (b) Siguen a pantalla completa, pero con el encabezado del diseño nuevo y la flecha para volver.
- **E2. Stock.**
  - (a) *Recomendado.* Lista: producto, cantidad, mínimo y botón «Ajustar», con lo agotado y lo bajo arriba.
  - (b) Igual que Productos, pero sin repetir las 4 tarjetas de arriba.
- **E3. Invitar en Equipo.**
  - (a) *Recomendado.* Solo el botón «Invitar», que abre una ventana con el enlace, el código y el QR.
  - (b) Solo la tarjeta del código y el QR.

## Cómo se trabaja
Pruebas automáticas de lo que cambia, imágenes de las pantallas en claro y oscuro, revisión de Codex de solo lectura y recorrido en la web publicada. Nada de commit, push, PR ni publicar sin permiso.
