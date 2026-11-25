# Plan · Reordenar el panel de administración

Estado: **APROBADO el 25 nov** (plan). El dueño pidió no tocar código todavía; falta el boceto.

Sale de la conversación del 25 nov: el dueño no encontraba el interruptor de precios porque está en «Configuración», dentro del grupo «Sistema». Solo cambia el panel (`lib/admin/`). No cambia la app de los clientes ni su versión. El panel se publica con la web, igual que el re-diseño del 24 nov (PR #48).

## El menú nuevo

| Grupo | Secciones |
|---|---|
| Operación | Resumen · Usuarios · **Negocios (con su ficha)** · Tiendas |
| Ingresos | Suscripciones · Pagos · **Planes y precios (nueva)** · **Códigos y cupones** |
| Soporte | Sugerencias y fallos · Errores |
| Sistema | Equipo y registro · **Mantenimiento** · Configuración |

## Cambios

### 1. «Planes y precios», sección nueva en Ingresos
Todo lo que define qué se vende y a cuánto, en un solo lugar:
- **Arriba:** el interruptor «Mostrar precios y compra en la app», igual que hoy, con su explicación.
- **La lista de planes,** con «Editar»: precio, precio tachado, etiqueta y visible u oculto. Es la misma de hoy.
- **El «Aviso de precios»** que sale debajo de los planes en la app. Hoy está en «Pago y contacto».
- **Precios de las sedes extra:** mensual y anual, para Pro y para Pro Servicios, más el precio desde 3 sedes.
  - Hoy solo se cambian a mano en la nube (tabla `branch_slot_prices`); se podrán editar aquí.
  - Necesita una función pequeña en la nube, solo para el dueño del panel y con registro en «Equipo y registro». Se ensaya con rollback y se aplica con permiso.

**«Configuración» queda solo con «Pago y contacto»:** la llave de Wompi, el Nequi y el WhatsApp de ventas.

### 2. Ficha del negocio, en «Negocios»
- **Hoy:**
  - tocar un negocio abre la ficha del **dueño** (usuario);
  - «Dar Pro» y «Cupos de sede» están allí, negocio por negocio;
  - «Dar Pro» se repite en «Suscripciones».
  - Pro y sedes son del negocio, no de la persona.
- **Nuevo:** tocar un negocio abre **su ficha**:
  - nombre, dueño (que abre la ficha del usuario), país y fecha en que se creó;
  - **plan:** Gratis, Pro o Pro Servicios, hasta cuándo, y si después sigue otro (como en la app);
  - **sedes:** cuántas tiene abiertas, cuántos cupos y hasta cuándo;
  - **tienda en línea:** si está publicada, con su enlace;
  - **las acciones, en un solo lugar:** «Dar Pro» y «Cupos de sede».
- **En la ficha del usuario** quedan sus negocios en una lista; cada uno abre la ficha del negocio. Se quitan de ahí «Dar Pro» y «Cupos de sede».
- **En «Suscripciones»,** el botón «Dar Pro» pide el negocio y abre su ficha. Así hay un solo «Dar Pro».

### 3. La lista de «Negocios»
- La columna «Plan» distingue **Pro** de **Pro Servicios**; hoy los dos dicen «Pro».
- Columna nueva **«Sedes»**: «Principal + 2», o vacía si solo tiene la Principal.

### 4. «Códigos» pasa a «Códigos y cupones»
- Mismo contenido; el nombre dice que adentro están también los cupones de descuento.
- Sus dos pestañas quedan arriba, bien visibles: «Códigos canjeables» y «Cupones de descuento».

### 5. «Mantenimiento» pasa al grupo «Sistema»
- Con la copia de seguridad diaria, que ya está en esa página.
- Nada más cambia.

### 6. «Ingresos del mes» en «Resumen»
- Una tarjeta con lo cobrado este mes por Wompi (pagos aprobados), cuántos pagos fueron, y la comparación con el mes pasado.
- Solo lectura, con los datos que ya hay en «Pagos».

## Lo que no cambia
- Resumen con la salud de los negocios.
- Pagos con su filtro.
- Errores, Sugerencias y Equipo.
- El ingreso con el código de dos pasos.
- Los permisos: «Dar Pro», cupos y precios siguen siendo solo del dueño del panel.

## Cómo se hace
1. **Boceto** del menú nuevo, de «Planes y precios» y de la ficha del negocio, para aprobar antes de programar.
2. **En la nube:**
   - la función para guardar los precios de las sedes;
   - que la lista de negocios del panel traiga también el tipo de plan y las sedes de cada uno, si hoy no los trae.
   - Se ensaya con rollback y se aplica con permiso.
3. **El panel:**
   - las secciones movidas;
   - la ficha del negocio;
   - los textos.
   - Con pruebas: cada sección abre, y «Dar Pro» existe una sola vez.
4. **Revisión:** Codex, y la revisión en la web con el dueño, porque el panel pide su código de dos pasos.
5. **Commit, PR y publicar,** con permiso.

## Junto con esto (ya decidido para la próxima versión)
- **`pro-checkout` se niega a cobrar si «Mostrar precios y compra» está apagado.** Hoy la app no muestra el botón, pero la nube no lo bloquea.
