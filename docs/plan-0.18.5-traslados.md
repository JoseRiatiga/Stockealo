# Plan 0.18.5 · Traslados entre sedes y encargado de turno

Estado: **APROBADO el 25 nov** con las recomendaciones: A faltante = pérdida registrada; B envían dueño y administradores desde cualquier sede y quien tenga «Ajustar stock» desde la suya; C el encargado no recibe proveedores (después); D solicitudes de traslado después.

El dueño eligió los traslados antes que la web de escritorio. Las versiones se corren:
- **0.18.5:** traslados y encargado de turno (este plan).
- **0.18.6:** la web como de escritorio.
- **0.18.7:** fiados, precios y Servicios por sede, y el recibo con los datos de la sede.

Se basa en lo aprobado en `docs/plan-sedes.md` (sección 4, «Traslados» y «Encargado de turno»).

## Cómo queda para el cliente

### Enviar mercancía a otra sede
1. En **Stock › Traslados › Nuevo traslado**, o desde el producto con «Enviar a otra sede».
2. Elige la sede de destino, los productos (con talla o color) y cuántas unidades. Un traslado puede llevar varios productos, como un pedido.
3. Al tocar **«Enviar»**, las unidades **salen del stock de la sede de origen** y quedan **«En camino»**. No se pueden vender en ninguna de las dos sedes.
4. La sede de destino ve el aviso en la campana y en Stock: «Te llegan 3 productos desde Principal».

### Recibir
- Quien recibe abre el traslado, cuenta y escribe lo que llegó de cada producto. Por defecto viene lo enviado.
- **Si llegó todo:** «Recibir». Las unidades entran al stock de la sede de destino.
- **Si llegó menos:** escribe cuánto llegó y una nota. La diferencia queda registrada como **faltante** con el nombre de quién envió y quién recibió.

### Quién recibe
- El **dueño y los administradores**, en cualquier sede.
- El **encargado de turno** de esa sede, mientras su turno esté vigente.
- **Un cajero sin encargado:** puede **recibir provisionalmente**. Las unidades entran al stock y se pueden vender, para que la mercancía no se quede parada. El traslado queda **«Recibido, por verificar»** hasta que un administrador lo revise y lo confirme.

### Cancelar
Mientras esté «En camino», quien lo envió (o el dueño o un administrador) puede cancelarlo. Las unidades vuelven a la sede de origen.

### Lo que se ve
- **Stock › Traslados:** tres grupos: «Te llegan», «Enviados» e «Historial». El dueño y los administradores ven los de todas las sedes.
- **En el producto:** «3 en camino a Norte».
- **Actividad:** «Envió 5 Shampoo a Norte», «Recibió 4 de 5 Shampoo desde Principal (faltó 1)» y «Canceló el traslado». Lo que hace el encargado lleva «como encargado».
- **El cajero y el encargado no ven costos** en los traslados.

### Sugerencia de traslado
En **Stock › Por reponer** y en **Pedido al proveedor**: si a esta sede le falta un producto y otra sede tiene más de su mínimo, aparece «Norte tiene 12». El dueño o un administrador lo trae con **«Traer de Norte»**, que arma el traslado con lo que falta. El cajero solo ve la sugerencia.

### Encargado de turno
- **Quién lo nombra:** el dueño o un administrador, en **Ajustes › Equipo**, toca a un cajero y elige **«Dejar a cargo de la sede»**.
- **Cuánto dura:** «hasta hoy a las 6:00 p. m.» (eligiendo la hora), «hasta mañana a esta hora» o «hasta que lo quite». Hay un encargado por sede a la vez.
- **Se termina solo** al cumplirse la hora. En Equipo se ve «Encargado de Norte hasta las 6:00 p. m.» y se puede quitar antes.
- **Mientras tanto, solo en su sede, puede:**
  - confirmar los traslados que llegan, y verificar los recibidos provisionalmente;
  - cerrar la caja de otra persona.
- **No puede:** ver costos o ganancias, ni cambiar precios. Sigue siendo cajero.
- El encargado ve en Inicio «Estás a cargo de Norte hasta las 6:00 p. m.».

## Qué se hace

### En la nube (migración nueva, se ensaya con rollback en el LAVADERO y se aplica con permiso)
- **Tablas `stock_transfers`** (origen, destino, estado, quién envió y recibió, nota, fechas) **y `stock_transfer_lines`** (producto, variante, enviado, recibido). `branch_id` vacío = la Principal, como en el resto.
- **Cuatro funciones** que mueven el stock de una vez, en la nube (enviar, recibir, verificar y cancelar). Cada una revisa:
  - quién puede hacerlo;
  - que haya unidades suficientes en la sede de origen;
  - que el traslado esté en el estado correcto: no se recibe dos veces ni se cancela uno ya recibido.
- **Lotes con vencimiento:** al enviar, salen primero los lotes que vencen antes. Al recibir, se crean en el destino con la misma fecha y el mismo código. Se agrega el origen «TRASLADO» a los lotes.
- **Encargado de turno:** columna `lead_until` en los miembros del equipo. La nube revisa la hora, no la app: se acaba solo aunque el celular tenga la hora mal.
- **Necesita conexión para enviar, recibir y cancelar.** Mover stock entre dos sedes desde dos celulares sin conexión descuadra las cuentas. Sin internet, la app dice «Para enviar o recibir un traslado necesitas conexión».
- **Las apps viejas** no ven traslados. Como la nube mueve el stock sumando y restando unidades, lo que muestran sigue cuadrado.
- **Copia diaria, «Descargar todos mis datos» y el borrado de cuenta** incluyen los traslados.

### En la app
- **Pantallas nuevas en Stock:**
  - Traslados, con «Te llegan», «Enviados» e «Historial»;
  - Nuevo traslado;
  - Recibir.
  Van en `app_functions.dart` («Traslados»).
- **El producto:** «Enviar a otra sede» y la línea «En camino».
- **Por reponer y Pedido al proveedor:** la sugerencia «Norte tiene 12» con «Traer de Norte».
- **Equipo:** «Dejar a cargo de la sede» y quitar el encargado; el aviso en Inicio para el encargado.
- **Campana de avisos:** traslados que llegan y recibidos por verificar.
- **Pruebas automáticas** y **revisión de Codex** antes de publicar.
- **Bocetos de las 3 pantallas nuevas** para aprobar antes de programarlas.

## Preguntas para el dueño
- **A. El faltante:** ¿queda registrado como pérdida (lo que no llegó no vuelve a ninguna sede) o vuelve al stock de origen?
  - Propongo **pérdida registrada**: si no llegó, no está en ningún lado, y el informe dice quién envió y quién recibió. Si después aparece, se ajusta a mano.
- **B. ¿Quién envía?** Propongo:
  - el dueño y los administradores, desde cualquier sede;
  - quien tenga el permiso «Ajustar stock», solo desde su propia sede.
  - El encargado de turno no envía: solo recibe.
- **C. ¿El encargado recibe mercancía de proveedores?**
  - Estaba en el plan, pero la entrada de proveedor pide el costo y el encargado no ve costos.
  - Propongo **dejarlo para después**: en esta versión el encargado recibe traslados y cierra cajas.
- **D. ¿La sede que necesita puede «pedir» un traslado** (una solicitud que la otra sede acepta y envía)?
  - Propongo **después**. Por ahora, el dueño y los administradores lo arman con «Traer de Norte».

## Verificación
- **Pruebas con rollback en la nube:**
  - enviar baja el origen;
  - recibir sube el destino;
  - el faltante queda registrado;
  - cancelar devuelve las unidades;
  - no se recibe dos veces ni se cancela algo ya recibido;
  - un cajero no recibe de forma definitiva sin ser encargado;
  - el encargado vencido ya no puede;
  - los lotes pasan con su fecha;
  - con stock insuficiente, no se envía.
- **Prueba real en el LAVADERO:** reabrir una sede de prueba, trasladar el «Shampoo (prueba)» de ida y vuelta, y cerrarla otra vez.
- **Antes de publicar:** revisión en la web y CORS (`bash tool/check_cors.sh`).

## Versión
Va como **0.18.5** (web + APK). Cada migración, commit, PR y publicación se hace con permiso.
