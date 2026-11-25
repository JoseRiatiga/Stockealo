# Plan 0.18.4 · Registro sin código (PRIORIDAD, pedido el 24 nov)

Estado: **APROBADO el 24 nov** (A: no se pide verificar para pagar; B: el aviso vuelve a los 7 días; C: el dueño revisa el correo de Supabase).

## Por qué

El 24 nov un interesado en Pro se registró y no le llegó el código, así que no pudo entrar. Pedir el código antes de ver la app espanta a quien solo quiere probarla.

Pero en Stockealo el acceso a un negocio va por correo: invitaciones a empleados, dueño, administrador, cupones y pagos. Si cualquiera puede registrarse con cualquier correo sin probarlo, puede quedarse con la invitación de otra persona. Este plan quita el código del registro **sin abrir ese hueco**.

## La regla de seguridad (una sola)

**Una cuenta que no ha probado su correo nunca puede tener un correo al que le corresponda algo:** una invitación, un perfil viejo, un cupón o un plan. Eso se revisa en la nube en cuatro puntos, sin cambiar las 41 revisiones por correo que ya existen.

## Cómo queda para el cliente

1. **Registrarse:** correo, contraseña, nombre y teléfono, luego «Crear cuenta», y entra de una vez. Sin código.
2. **Aviso en Inicio y en Ajustes**, sin bloquear nada: «Verifica tu correo para proteger tu cuenta», con el botón «Verificar». El botón envía el código, se escribe y listo. Se puede cerrar el aviso; vuelve a salir a los 7 días.
3. **Si lo invitan a un negocio:** el dueño ve «Esa persona debe verificar su correo en Stockealo antes de entrar a tu negocio». El invitado ve el aviso en su app.
4. **Recuperar la contraseña:** igual que hoy, con código. Al cambiarla, la cuenta queda verificada.
5. **Entrar con Google:** queda verificada desde el inicio.

## Qué se hace

### En la nube (migración nueva, se ensaya con rollback y se aplica con permiso)

- **Tabla `unverified_accounts`** (cuenta, correo, fecha): aquí están solo las cuentas creadas sin código. Las cuentas de hoy quedan verificadas, salvo la de Mary, que se confirmó a mano y entra aquí.
- **Función nueva `register-account`**, sin sesión, con límite de 5 registros por hora desde la misma conexión. Crea la cuenta ya confirmada, la anota en `unverified_accounts` y la app inicia sesión.
  - Si ese correo tiene algo pendiente, no la crea sin código y pide el registro con código de siempre: una invitación sin cuenta, un perfil viejo sin cuenta (hoy hay 2), un plan, un cupón o un administrador.
  - Si el correo ya tiene una cuenta sin confirmar y que nunca entró (lo que dejan las apps viejas al pedir el código), se le pone la contraseña nueva y queda como sin verificar.
  - Con cabecera `x-stockealo-branches` en CORS y agregada a `tool/check_cors.sh`.
- **Invitaciones:** una regla en la tabla de miembros (un *trigger*: vale también para el panel y la nube, no solo para la app) no deja agregar ni cambiar un miembro a un correo que esté en `unverified_accounts`.
- **Verificar:** después de escribir el código, la nube revisa que la sesión venga de un código de verdad (no basta con que la app lo diga) y saca la cuenta de `unverified_accounts`.
  - Antes de programarlo, compruebo con una sesión real en el LAVADERO qué trae la sesión después del código. Si no es claro, el código se revisa dentro de una función de la nube.
- **Recuperar la contraseña:** la cuenta queda verificada solo cuando la contraseña nueva **ya se guardó**, y se cierran las otras sesiones. Así, si alguien registró el correo de otra persona, su contraseña deja de servir.
- **Cambio de correo:** sigue pidiendo confirmación (no se apaga «Confirm email» en Supabase). Si no, se podría cambiar el correo por uno invitado.

### En la app

- Pantalla de registro sin el paso del código. La app 0.18.3 y anteriores siguen con el código y siguen funcionando.
- Aviso «Verifica tu correo» en Inicio y Ajustes y la hoja para escribir el código, un solo lugar en `app_functions.dart`.
- Mensaje claro al invitar a alguien sin verificar.
- Pruebas automáticas de todo lo anterior y una prueba en la nube con rollback.

## Preguntas para el dueño

- **A. ¿Pedir el correo verificado para pagar Pro?**
  - Lo pidió así, pero mi opinión sincera es que **no**. Si el correo no llega, como le pasó a Mary, el cliente se quedaría trabado justo al pagar, que es el peor momento.
  - Quien paga es el dueño de ese negocio, así que no hay hueco de seguridad: el hueco está en las invitaciones, y esas sí quedan cerradas.
  - Propongo: pagar sin verificar, y que después del pago la app sugiera verificar.
- **B. ¿Cada cuánto vuelve el aviso si lo cierran?** Propongo 7 días.
- **C. Correo de Supabase:** la verificación sigue usando el mismo correo que no le llegó a Mary. Le pido mirar en el panel de Supabase, en Authentication › Emails y en Rate Limits, cuántos correos por hora permite. Yo no lo puedo ver desde aquí. Si es muy poco, el correo propio (SMTP) vuelve a ser necesario.

## Versión

Va como **0.18.4** (web + APK). La web como de escritorio pasa a la **0.18.5**. Revisión de Codex antes de publicar. Cada migración, commit, PR y publicación, con permiso.
