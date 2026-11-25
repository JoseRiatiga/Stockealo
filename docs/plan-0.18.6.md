# Plan 0.18.6 · Arreglos cortos (antes de que Mary empiece con Pro)

Estado: **APROBADO el 25 nov**.

Salen de la prueba en pantalla de los traslados y de la revisión de Pro para Mary (25 nov). Son cuatro cosas pequeñas, sin migración en la nube.

Las versiones se corren otra vez:
- **0.18.6:** estos arreglos.
- **0.18.7:** la web como de escritorio.
- **0.18.8:** fiados, precios y Servicios por sede.

## 1. Avisos (toasts) que no tapen la pantalla en computador
- **Hoy:** en la web, el aviso de abajo («Venta registrada», «Enviado…») ocupa todo el ancho y tapa el botón «Cobrar».
- **Cambio:**
  - en pantallas anchas (computador o tableta acostada), el aviso mide como máximo unos **420 px** y va **centrado abajo**;
  - en el celular queda igual, a lo ancho.
  - Un solo lugar: `lib/core/widgets/app_toast.dart`, que usan todos los avisos de la app.

## 2. «1 unidades» → «1 unidad»
- **Hoy:** tres textos de los traslados dicen «1 unidades»:
  - el aviso al enviar;
  - el aviso al recibir;
  - el botón «Recibir 1 unidades».
- **Cambio:** singular y plural correctos («1 unidad», «3 unidades»), también en el mensaje de cancelar y en la Actividad.

## 3. Caja › Cierres anteriores: el nombre, no el correo
- **Hoy:** un cierre viejo dice «Esperado $117.000 · Contado $117.000 · byjosealbert@gmail.com».
  - Las versiones anteriores guardaban el correo de quien cerró.
  - Desde hace varias versiones se guarda el nombre: el comprobante de hoy ya decía «Atendió Jose Riatiga».
- **Cambio:** si lo guardado es un correo, la app muestra el **nombre de esa persona en el equipo**. Si ya no está en el equipo, muestra la parte del correo antes de la @.
  - No se cambian los datos guardados; solo cómo se muestran.
  - Así no se ven correos de otras personas en pantalla.

## 4. Sesión vencida: avisar y volver a entrar
- **Hoy:** cuando la sesión con la nube vence, la app sigue mostrando el negocio como si nada.
  - Todo lo que va a la nube falla con un mensaje que confunde, como «Para reabrir una sede necesitas conexión».
  - Lo que se vende queda guardado en el celular, pero no sube hasta volver a entrar.
  - Lo vimos el 25 nov en el LAVADERO.
- **Cambio:**
  - la app escucha cuando Supabase cierra la sesión por su cuenta (no porque la persona tocó «Salir»);
  - al pasar, muestra «**Tu sesión se cerró. Vuelve a entrar para guardar tus cambios en la nube.**» con el botón «Entrar»;
  - lo guardado en el celular no se borra: al volver a entrar con la misma cuenta, sube lo que estaba pendiente;
  - lo mismo al volver a abrir la app si la sesión ya venció.
- **Lo que no cambia:** sin internet la app sigue funcionando igual. Solo se avisa cuando la sesión de verdad se cerró, no cuando falta conexión.

## Qué se hace
- Los 4 cambios en la app, con pruebas automáticas:
  - el ancho de los avisos;
  - los textos en singular y plural;
  - el nombre en lugar del correo;
  - el aviso de sesión cerrada.
- Revisión en la web con el LAVADERO, y revisión de Codex antes de publicar.
- Versión **0.18.6** (web + APK). Commit, PR y publicación, con permiso.

## Sin preguntas
No hay decisiones abiertas. Si quiere otro texto para el aviso de sesión cerrada, dígamelo.
