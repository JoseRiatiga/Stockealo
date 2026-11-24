# Plan de la 0.18.1 — arreglos de la prueba de Sedes

Sale de la prueba en la web publicada (24 nov, LAVADERO; ver `docs/plan-sedes.md` §10). Es una versión corta: no trae funciones nuevas grandes, solo deja Sedes y algunas pantallas como deben verse. Después de esta sale el APK.

## Sedes

1. **Formulario «Nueva sede» con el diseño nuevo.** Hoy son tres campos sueltos y «Guardar» se puede tocar con el nombre vacío. Queda como las ventanas nuevas (por ejemplo «Nueva categoría»):
   - una línea que explica qué es una sede;
   - campos con ícono: nombre, dirección y teléfono con bandera del país (el mismo campo de teléfono del negocio);
   - «Guardar» se activa solo con nombre;
   - avisa si ya hay una sede con ese nombre.
   Antes de programarlo te muestro un boceto para aprobar.
2. **«Principal (Principal)».** En el selector sale el nombre y la etiqueta repetidos. Queda «Principal» y, si le cambias el nombre (por ejemplo «Centro»), sale «Centro · Principal».
3. **«Todas las sedes» en Vender y Caja.** Hoy dice «La caja está cerrada. Ábrela para poder cobrar» y ofrece «Abrir caja», que abriría la de la Principal. Queda un aviso único: «Estás viendo todas las sedes. Para vender o abrir caja, elige una sede», con un botón que abre el selector. Cobrar ya estaba bloqueado.
4. **Aviso «Venta registrada» al cambiar de sede.** Se borra al cambiar de sede, para no ver en la Principal la venta que se hizo en Norte.
5. **La sede en el recibo y en el cierre de caja.** Solo cuando el negocio tiene sedes abiertas: «LAVADERO · Norte», con la dirección y el teléfono de esa sede si los tiene. Sin sedes, el recibo queda igual que hoy.
6. **Stock de las otras sedes en la lista.** Debajo de cada producto, en letra pequeña: «Norte 14 · Sur 6». Solo para dueño y administradores, y solo si hay otras sedes con unidades. (Venía pendiente del boceto de sedes.)

## Otras cosas vistas en la prueba

7. **«Valor del inventario» mal calculado.** Dice «A precio de costo» pero suma el precio de venta (pasa desde la primera versión). Queda con el costo, que es lo que dice.
8. **Cierre de caja: «ATENDIÓ» muestra el correo.** Queda el nombre de quien cierra, como al abrir.
9. **Contar inventario:**
   - el campo dice «Conta…» cortado: queda «Contaste» completo o el campo más ancho;
   - «se ajustaron 1 productos»: queda «1 producto» / «3 productos».
10. **Tienda en línea que nunca se guardó.** La pantalla muestra «Tienda encendida» aunque no existe. Queda apagada hasta que el dueño la guarde, con el botón «Publicar mi tienda».

## Panel

11. **«Cupos de sede»:** la ventana dice cuántos cupos tiene ya el negocio y hasta cuándo, y no ofrece un plazo que pase del fin de su plan (en ese caso dice «hasta el fin de su plan, 11 dic»).
12. **La tarjeta del negocio dice «Pro Servicios»** cuando es ese plan, no solo «Pro».

## Cómo se trabaja

- Rama `fix/0.18.1` desde main. Sin migraciones: todo es de la app y del panel.
- Primero el boceto del punto 1; el resto no cambia la forma de las pantallas.
- Pruebas: las que hay más una por cada arreglo (recibo con y sin sedes, aviso de Todas las sedes, valor del inventario, textos del conteo).
- Revisión de Codex antes de publicar y comprobar sus hallazgos.
- Publicar la web y después el **APK v0.18.1** (trae la 0.18.0). Propongo no sacar un APK de la 0.18.0 sola, porque llevaría estos errores al celular.
- En el celular, con el APK, quedan por probar: el aviso de primera venta, contar con la cámara y vender sin conexión.

## Lo que se corre de número

Antes la 0.18.1 era «tienda con selector de sede y un solo pago Wompi». Con este cambio:
- **0.18.2:** tienda por sede y pago único de plan + cupos.
- **0.18.3:** traslados entre sedes y encargado de turno.
- **0.18.4:** fiados, precios y Servicios por sede.

## Después de la 0.18.1 (aprobado 24 nov)

Re-diseño del panel de administración como versión aparte: primero recorrer todas sus pantallas con capturas, listar lo que está viejo (ficha del usuario, historial de Pro, ventanas de opciones) y mostrar un boceto para aprobar.

## Cómo quedó (24 nov, rama fix/0.18.1, sin commit)

Los 12 puntos hechos. Formulario de sede según el boceto aprobado (`branch_form_dialog.dart`, también para editar y renombrar la Principal). Recibo y cierre con «SEDE NORTE» y la dirección/teléfono de la sede. «Todas las sedes»: aviso con «Elegir sede» en Vender y Caja, y `openSession` lo rechaza también por código. Stock: «Principal 10 · Norte 4» solo para dueño y administradores. Panel: la ventana de cupos dice cuántos tiene y hasta cuándo, y no da más días de los que le quedan al plan; la tarjeta dice «Pro Servicios».

**Diferencia con el plan:** sí hay una migración, pequeña y de solo lectura: `20261211000000_admin_branch_slots.sql` (el panel no podía leer los cupos de negocios donde el dueño no es miembro). ENSAYADA con rollback y SIN APLICAR. Sin ella el panel sigue funcionando y solo dice «No se pudo leer cuántos cupos tiene».

Pruebas: 701 (4 nuevas en `branches_test.dart`; `cash_register_test` ahora espera el nombre al cerrar). Codex: 1 hallazgo (el carrito al cambiar de sede) comprobado como falso: `main_navigation_screen._onBranchChanged` ya vacía el carrito.
