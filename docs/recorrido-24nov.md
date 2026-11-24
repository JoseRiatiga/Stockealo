# Recorrido de la app en la web (24 nov 2026)

Hecho en stockealo.online (0.18.1) a 1440×900, en oscuro y en claro, con la cuenta del dueño en el LAVADERO. Solo se miró: no se guardó nada.
Pantallas recorridas: Inicio, Vender, Caja, Productos, Stock, Ventas, Clientes y proveedores, Servicios, Ajustes, y el selector de negocios.
No se pudieron probar: abonar un fiado (el LAVADERO no tiene clientes) ni la tienda.

## Lo más grave (datos que no se ven)

1. **Al cerrar una sede, su historial desaparece de la app.** La venta de ayer de 2 Shampoo por $18.000 se hizo en «Norte (prueba)», que ahora está cerrada. No sale en Ventas, ni en «Lo más vendido», ni en «Cierres anteriores» de Caja (el cierre de $68.000 de ayer tampoco está). Como no queda ninguna sede abierta, tampoco se puede elegir «Todas las sedes». El plan de sedes decía que una sede cerrada «se ve y se descarga». Comprobado en la nube: la venta existe, con la sede Norte.
2. **Ventas no muestra la fecha de cada venta**, solo la hora («6:26 p. m.»). Con «Todas las fechas» no se sabe de qué día es cada una.

## Pasos de más o cosas confusas

3. **Productos y Stock son casi la misma pantalla.** Las dos tienen la lista de productos, el buscador, el orden, Todas/Insumos, la vista en lista o cuadrícula y «Editar». La diferencia (en Stock se ajusta; en Productos se edita el precio) no se ve. Propuesta: una sola pantalla «Productos» con el stock en cada fila («Ajustar» en la misma fila, ya aprobado) y, arriba, «Pedir al proveedor» y «Contar inventario». Se quita «Stock» del menú (nada duplicado).
4. **Servicios: para empezar el primer lavado del día hay que ir a otra pestaña.** El aviso dice «Marca quién vino hoy en Empleados: sin eso nadie puede empezar servicios», y arriba ya están «Jose · Sin marcar», «JUAN · Sin marcar» y «Sebastian · Sin marcar». Propuesta: tocar esa pastilla marca la llegada ahí mismo.
5. **Servicios tiene 7 pestañas** (Tablero, Agenda, Empleados, Historial, Comisiones, Catálogo y precios, Mensajes), y el botón «Recibir» queda abajo a la izquierda, lejos de todo en computador. Propuesta: «Recibir» arriba a la derecha, junto al título, y juntar Historial con Comisiones, y Catálogo con Mensajes (configuración).
6. **Productos tiene mucho encima de la lista:** 4 cifras, la barra «1 por reponer», 3 tarjetas (Catálogo, Promociones, Importar), el aviso de plantilla, el buscador y los filtros. La lista empieza a dos tercios de la pantalla. Propuesta: las 3 tarjetas en un menú «Más» junto a «Nuevo producto», y las cifras en una sola línea.
7. **Clientes repite el título tres veces:** «Clientes y proveedores» → pestaña «Clientes y fiados» → título «Clientes y fiados». Y con la lista vacía no hay botón para crear el primer cliente en el centro (solo arriba a la derecha).
8. **Caja: el botón «Igual que ayer» pone $117.000**, que es la base del 11 nov, no de ayer. Debe decir «Igual que la última vez». Y «Cierres anteriores» muestra el correo (byjosealbert@…) en vez del nombre.
9. **El botón «Nueva venta» de arriba sale también estando en Vender**, donde no hace nada nuevo. Ocultarlo en Vender.

## Diseño (oscuro y claro)

10. **Amarillo chillón en claro** (lo vio el dueño): las pastillas y los íconos de aviso («Quedan 5», «Bajo», «Caja cerrada», el aviso de Servicios) usan un amarillo muy brillante sobre blanco. En oscuro se ve bien. Bajar el tono del amarillo en el tema claro (más ámbar, menos limón), revisando el contraste del texto.
11. **«Necesita atención»** (ya anotado): hueco grande con un solo aviso y «Quedan 5» repetido.
12. **Iniciales raras en los productos sin foto:** «Shampoo (prueba)» sale como «S(». Las iniciales deben saltar los signos: «SP».
13. **Pantallas estiradas en computador:** las pestañas de Clientes ocupan todo el ancho; en Stock la fila del producto va de borde a borde, mientras en Productos la tarjeta ocupa la mitad. Va con las reglas de anchos de la fase 3.

## Bien resuelto (no tocar)

- **Vender:** 2 toques (producto y «Cobrar»), con atajos de teclado (F2, F9, Esc), billetes rápidos y vuelto. Es la pantalla mejor resuelta.
- **Abrir caja:** 1 toque, con montos rápidos.
- **Ajustes:** ordenado por grupos y fácil de leer.

## Nota sobre el color

El color de la app sale de Ajustes › Apariencia («Verde Stockealo»), no del color del negocio. No es un error.
