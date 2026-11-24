# Plan de la 0.16.8 — Fase 4: mejoras

Fuente: Fase 4 de `docs/plan-0.16.4-0.16.5.md`. Cada número (#) es un hallazgo de `docs/revision-web-0.16.3.md`.
Estado: **APROBADO (18 nov): A1, C1 y E1 en la opción a.**

## Resumen

| Bloque | Qué trae | Nube (Supabase) |
|---|---|---|
| A | Íconos de categoría (#28) | **Sí:** columna `icon` en `categories` y la tienda pública la lee |
| B | Promociones y fechas (#24, #25, #21) | No |
| C | Plata: gastos en Reportes (#43) y fiado en pago mixto (#19) | No |
| D | Nombres actuales en listas y reportes (#26, decisión D1) | No |
| E | Detalles: puntos de mil (#20), Módulos que se tocan (#57), tienda sin WhatsApp (#39), Avisos en la web (#53) | No |
| F | Arranque más rápido (#42) | No |

Todo sale junto como **0.16.8**. Rama `fix/0.16.8` desde main.

---

## A. Íconos de categoría (#28)

Hoy la tienda pone en cada categoría la foto del primer producto, y «Todas» sale con un cuadro gris.

- Cada categoría tiene un ícono. Al crearla, se sugiere por el nombre (Bebidas → vaso, Aseo → spray, Calzado → zapato, Licores → copa…). Se puede cambiar a mano en Gestionar categorías, desde una cuadrícula de unos 40 íconos.
- Las categorías que ya existen reciben el ícono sugerido la primera vez; el dueño lo puede cambiar.
- «Todas» lleva su propio ícono.
- Se ve en los chips de la tienda, Vender y Productos.
- En Personalizar tienda, un interruptor «Mostrar íconos de categoría». Si se apaga, solo el nombre.
- **Migración (con tu permiso):** columna `icon` en `categories` (también en la base local) y la función de la tienda pública devuelve el ícono de cada categoría. Se ensaya antes de aplicarla y se comprueba que las tiendas publicadas sigan respondiendo.

**Decisión A1.** ¿Los íconos son (a) dibujos de línea como los del resto de la app, en el color del negocio, *recomendado*; o (b) emojis (🍺 👟 🧴), más alegres pero distintos al diseño?

## B. Promociones y fechas

- **#24:** en «Productos marcados», cada producto con su miniatura (o iniciales si no tiene foto), como en Vender.
- **#25:** «Cambiar fechas» abre una ventana emergente con el calendario de rango y atajos («Hoy», «Esta semana», «Este mes», «Fin de semana»). La misma ventana sirve en el filtro de fechas de Ventas. Es una sola función, en un solo lugar.
- **#21:** los ejemplos de Promociones según el tipo de negocio (un minimercado ve «2×1 en gaseosas», no «20 % en camisetas»).

## C. Plata

- **#43, gastos en Reportes:** la ganancia neta resta las salidas de caja de tipo «Gasto» del periodo. Se muestra la línea «Gastos de caja» entre la bruta y la neta. Retiros, pagos a proveedor y anulaciones no cuentan como gasto. Stocky y el cierre del día usan la misma cifra.
- **#19, fiado en pago mixto:** en Vender, el pago mixto suma «Fiado» como un medio más. Pide cliente, y esa parte queda en lo que debe.

**Decisión C1.** Fiado en pago mixto: (a) se permite y esa parte se suma a la deuda del cliente, *recomendado*; o (b) se deja para después, porque toca caja, devoluciones y anulaciones. Si es (a), lleva pruebas de anular y devolver esa venta.

## D. Nombres actuales (#26, D1 ya aprobada)

Ventas, Reportes, «Lo más vendido» y Stocky muestran el nombre actual del producto (se une por `product_id`). El recibo sigue con el nombre del día de la venta. Si el producto se borró, queda el nombre guardado.

## E. Detalles

- **#20:** los campos de valor muestran los puntos de mil mientras se escribe («999.999»), en Vender, abonos, caja, precios y promociones. Un solo formateador.
- **#57:** en Módulos, cada fila se puede tocar y lleva a esa función (Caja, Tienda en línea, Clientes y proveedores…).
- **#39:** hoy ya no deja guardar la tienda sin WhatsApp. Lo reviso en la web publicada; si una tienda vieja quedó encendida sin número, en Tienda en línea sale el aviso «Sin WhatsApp no te llegan los pedidos».
- **#53, Avisos en la web:** hoy «Avisos» solo aparece en el APK de Android, porque la web no manda notificaciones al celular.

**Decisión E1.** En la web: (a) mostrar «Avisos» con una nota «Los avisos llegan en la app del celular» y el enlace para instalarla, *recomendado*; o (b) avisos del navegador (pedidos y stock bajo con la pestaña abierta), que pide permiso al navegador y es más trabajo.

## F. Arranque más rápido (#42)

Al recargar la web se ven más de 8 s de «Elegir negocio» y bloques grises.

- Primero mido dónde se va el tiempo (base local, nube, roles, Pro).
- La app muestra enseguida el último negocio con los datos guardados en el equipo y actualiza lo de la nube por detrás.
- Lo que no hace falta para pintar Inicio (pedidos, autorizaciones, citas) se carga después.

## Cómo se trabaja

- Rama `fix/0.16.8` desde main. Nada de commit, push, PR ni migraciones sin tu permiso.
- Pruebas automáticas de lo que toque plata (gastos y fiado mixto), de los íconos y de los nombres.
- La prueba de vencimientos que falla a veces en GitHub (`lots_test`) se hace más estable.
- Revisión de Codex (solo lectura) antes de publicar; se comprueba cada hallazgo.
- Versión 0.16.8, novedades y notas del APK. Después se revisa en la web publicada.
