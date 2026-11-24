# Re-diseño del panel de administración (propuesta, 24 nov)

Recorrido a 1280 px de todas las pantallas del panel. Lo que ya está con el diseño nuevo se queda: menú lateral, Resumen, Usuarios, Suscripciones, Códigos, Mantenimiento y Configuración.

## Lo que cambia

1. **Ficha del usuario** (lo más viejo):
   - cabecera con iniciales, nombre, «cliente desde» y última entrada;
   - acciones (WhatsApp, correo, contactado) como botones, y lo poco usado en el menú «…»;
   - datos en filas con ícono;
   - negocios como tarjetas: plan, vencimiento, sedes «0 de 3», tienda, con «Dar Pro» y «Cupos de sede»;
   - historial de Pro con un punto de color por estado (activo, terminado, pago sin terminar) y nombres legibles: «Pro mensual», no «business_month_cop»;
   - notas internas al final.
2. **Registro de acciones:** agrupado por día, con ícono por tipo y **a quién** se le hizo («Dio Pro 1 año a Miselanea»). Hoy dice «Dio Pro (365 días) a un negocio» sin decir cuál. Incluye las acciones nuevas (cupos de sede).
3. **Negocios:** en computador, una tabla (negocio, dueño, plan, vence, tienda, sedes); tocar un negocio abre la ficha de su dueño. Hoy es una lista sin acción.
4. **Pantallas vacías** (Errores, Sugerencias, listas sin resultados) con ícono y una línea que explica qué aparecerá ahí.
5. **Ventanas** de «Dar Pro» y «Cupos de sede» con el diseño de ventanas de la app (hoy son listas simples).
6. **Pagos que nunca terminaron:** después de 24 horas dicen «Sin terminar», no «Pendiente» para siempre.

## Errores encontrados en el recorrido

7. **Embudo de activación:** las barras se calculan sobre las cuentas (4) y no sobre la base de cada paso, así que salen llenas aunque digan 50 %. Además mezcla cuentas con negocios. Las barras quedan proporcionales y cada paso dice sobre qué se cuenta.

## Cómo se trabaja

- Solo app y panel; la ficha usa los datos que ya trae la nube. El registro con nombres puede necesitar que la nube guarde el nombre del negocio en cada acción (se ve al programarlo; si hace falta, migración pequeña con permiso).
- Versión propia del panel (no cambia la app de los clientes); con pruebas a 360 y 1280 px, Codex antes de publicar.

## Cómo quedó (24 nov, rama feat/panel-rediseno, sin commit)

Hecho: ficha nueva (cabecera, datos con ícono, negocios con plan/vence/sedes/tienda, historial con puntos y nombres legibles), «Dar Pro» y «Cupos de sede» solo en negocios de los que la cuenta es dueña (antes «Cupos» salía también como cajero), ventanas de elegir con el diseño de la app, registro por día con ícono y nombre del negocio (y textos para cupos de sede y mensajes de soporte, que salían en código), Negocios en columnas que abren la ficha del dueño, Pagos «Sin terminar» después de 24 h y tocar un pago abre la ficha, embudo con barras proporcionales, pantallas vacías con ícono y explicación, terminar suscripción con botón rojo, horas en 12 h. Sin migraciones.

Pruebas: 714 (nuevas: textos, pagos, fechas, pantalla vacía y ficha/registro/Pagos/Negocios a 1280 y 390 px sin desbordes; se encontró y arregló un desborde de Pagos en el celular). Codex: gancho de pruebas bloqueado fuera de desarrollo (corregido). Anotado: el registro busca los nombres en una lista de máximo 50 negocios; con más, los viejos dirían «a un negocio» (con más de 50 negocios, consulta por ids).

**Sin estirar (24 nov, pedido del dueño):** cada pantalla tiene su ancho máximo en el computador: listas 880 px, formularios 720 px (Códigos, Configuración, Mantenimiento) y pantallas con columnas 1240 px (Resumen, Negocios). Resumen: las 5 tarjetas en una fila y Salud al lado de Uso de la app desde 1100 px.

**Prueba de acciones en el panel publicado (24 nov, con la sesión del dueño, LAVADERO como entorno de pruebas):** funcionan Dar Pro, Cupos de sede, crear/mensaje/desactivar código, notas, contactado, buscador (botón de arriba), programar mantenimiento, mensaje de soporte de la app al panel con respuesta, y terminar suscripción. Todo quedó en el registro. Se corrigió en la rama:
- Dar Pro siempre daba Pro normal: a un negocio con Pro Servicios le creaba un Pro aparte que no sumaba nada. Ahora se elige el plan y dice que corre aparte desde hoy.
- Cupos de sede vencían unas horas antes que el plan (días redondeados hacia abajo).
- Ctrl K no hacía nada después de tocar una zona sin foco: ahora funciona en cualquier parte.
- El buscador mostraba un código desactivado como «0/1 usos».
- Un mantenimiento programado con «Avisar al empezar» no salía en el panel ni se podía cancelar (se canceló a mano en la nube, con su registro). Ahora sale «Programado: todavía no se avisa» con «Cancelar».
- «1 suscripciones vencen…».
Pendiente menor: borrar una nota no pide confirmación.
