# Plan para la próxima sesión (guardado el 24 nov 2026)

## Dónde quedamos

- **Publicado:** 0.18.1 (web y APK v0.18.1 «Latest»): Sedes y los 12 arreglos de su prueba. Panel de administración re-diseñado (PR #48), sin cambiar la versión de la app.
- **Precios ENCENDIDOS** («Mostrar precios y compra» = on, con la llave de producción de Wompi). Los usuarios son conocidos del dueño con Pro regalado.
- **LAVADERO = entorno de pruebas.** Ahí se prueba todo lo que cambia datos. Hoy tiene Pro Servicios hasta el 11 dic y 4 cupos de sede (uno de prueba), 3 sedes de prueba cerradas y el producto «Shampoo (prueba)».
- Rama local: `fix/panel-menores` (sale de `fix/cors-sedes`, PR #50).
- Las versiones de sedes se corren un número: lo que era 0.18.2 (tienda por sede) ahora es 0.18.3.

## Hecho el 24 nov

- **Pago real con Wompi probado:** Nequi, $24.900, APPROVED, aviso recibido, Pro del LAVADERO hasta el 10 ene 2027 (después de su Pro Servicios del 11 dic).
- **Arreglado en la nube:** el pago, Stocky, la foto de producto, recuperar contraseña, borrar cuenta y legacy-login fallaban en la web desde la 0.18.0 por CORS (cabecera `x-stockealo-branches`). PR #50 (falta unirlo a main).

## Fases (orden aprobado el 24 nov: primero plata y datos, después sedes, después la web)

### Fase 1 · 0.18.2 · Plata y datos (ya empezada en la rama `fix/panel-menores`)

Hecho sin commit (24 nov, rama `fix/panel-menores`): los puntos 1 a 7, 9 y 10 de la lista, y en el panel: «Última entrada» en una línea, confirmar al borrar nota y el filtro de Pagos. Del 6 queda igual la fila «Todo está guardado en la nube» (es cierto: la cola está al día). El 8 tiene el chequeo automático `bash tool/check_cors.sh`; la revisión a mano se hace antes de publicar.

Lista:
1. **«Sincronizar ahora»** falla con «null value in column services_enabled»: la subida completa manda los negocios en un solo paquete con datos distintos y a los que no tienen servicios les llegan vacíos. Subir en grupos con los mismos datos (como las categorías). Igual con las ventas (`promotion_discount`, `supabase_service.dart:458`).
2. **No dejar comprar Pro con Pro Servicios vigente:** tarjeta «Incluido en tu plan» sin botón (`pro_screen.dart`) y bloqueo en `pro-checkout`.
3. **Plan y fecha con Pro y Pro Servicios a la vez:** leer `services_ends_at` (`pro_service.dart:215`). Ajustes: «Stockealo Pro Servicios · activo» y «Pro Servicios hasta el 11/12/2026 · después Pro hasta el 10/1/2027» (`profile_screen.dart:915`). El aviso de Inicio de vencimiento usa la fecha de Pro Servicios (`dashboard_screen.dart:785`). Revisar la pantalla de Pro.
4. **Papelera con Pro pagado:** avisar «Este negocio tiene Pro Servicios hasta el 11 dic; si lo borras, pierdes ese tiempo». Dejar un solo «Mover a la papelera» (hoy hay dos con confirmaciones distintas; queda el que pide escribir el nombre).
5. **Errores al panel:** los fallos que la app atrapa (pago que no inicia, sincronización que falla) también van a Panel › Errores.
6. **Errores al cliente en español claro**, sin «Error en Supabase: null value…» (`supabase_service.dart:501`); que «Todo está guardado en la nube» no salga si falló.
7. «Metió $50.000 **a** la caja» (`cash_register_repository.dart:167`).
8. **Revisión antes de publicar** (desde esta versión, cada vez): en la web, con el LAVADERO y otro negocio: Sincronizar ahora, iniciar un pago sin pagar, una pregunta a Stocky, una foto de producto. Y un chequeo automático de que todas las funciones de la nube responden desde la web (CORS).
9. **El historial de una sede cerrada desaparece** (recorrido 24 nov, `docs/recorrido-24nov.md` punto 1): la venta de $18.000 y el cierre de caja de «Norte (prueba)» no salen en Ventas, «Lo más vendido» ni «Cierres anteriores», y sin sedes abiertas no se puede elegir «Todas las sedes». Lo cerrado debe seguir viéndose.
10. **Ventas sin fecha:** cada venta muestra solo la hora; agrupar por día o mostrar la fecha.

Se publica: web + APK 0.18.2 + `pro-checkout`.

### Fase 2 · 0.18.3 · Sedes y un solo pago (ver `docs/plan-sedes.md`)

Antes de programar: plan para aprobar y bocetos.
- **Sedes en el menú lateral, debajo del negocio:** sedes abiertas (Principal primero), la activa marcada y el estado de su caja; un toque cambia de sede; «Todas las sedes (reportes)» solo dueño y administradores; el cajero ve solo su sede; «＋ Abrir una sede» solo el dueño (sin sedes es la única línea; sin Pro lleva a Pro); con muchas, 4 y «Ver todas»; con el menú cerrado, la hoja de hoy; cerradas e inactivas solo en Ajustes › Módulos › Sedes.
- **Coronita junto al nombre de la cuenta** y en cada negocio de «Tus negocios», con Pro o Pro Servicios. Propuesta por aprobar: la misma corona dorada para los dos y la diferencia en texto («Dueño · Pro Servicios»), no por color.
- **Tienda por sede:** selector de sede (stock, dirección, horario, «Cómo llegar»; recuerda la elegida).
- **Un solo pago con Wompi por el plan y los cupos de sede:** prorrateo por días; con menos de 7 días se suma el periodo siguiente.
- **Subir de Pro a Pro Servicios:** se descuentan los días de Pro que quedan (ej. 15 de 30 días = ~$12.450 menos), con el mismo cálculo.

### Fase 3 · 0.18.4 · La web como de escritorio

Reglas para toda la app: anchos máximos, ventanas centradas en vez de hojas desde abajo, editar en el mismo lugar cuando es un solo dato. Lo nuevo ya nace así.
- **Avisos (toasts):** ancho máximo ~420 px y centrados en computador; en el celular, a lo ancho (`app_toast.dart:51`). Hoy tapan el botón «Cobrar».
- **«Tu negocio» en una sola página** (APROBADO): Identidad · Recibo con vista previa al lado · Detalles · Papelera; un solo «Guardar»; «Editar negocio» de «Tus negocios» abre esta página.
- **Ajustar stock en la misma fila** (por aprobar): − y +, «5 → 7 (+2)» antes de guardar, Enter/✓ y Esc/✗, dice la sede; se quita la ventana actual.
- **«Tus negocios»:** el menú ⋮ se abre pegado al botón y dentro de la ventana (`business_selector_modal.dart:467`).
- **Actividad del equipo:** ancho máximo; la sede en ventas y caja; íconos de caja sin rojo de error; tocar una línea abre la venta o el cierre; filtro por sede y por persona.

- **Inicio › «Necesita atención»** (visto 24 nov, por aprobar): con un solo aviso queda un hueco blanco grande (la tarjeta se estira al alto de la de al lado); «Quedan 5» se repite en el título y en la pastilla; «Mínimo 5» con 5 en stock no dice qué hacer. Propuesta: la tarjeta mide lo que tiene; título «Shampoo (prueba)», detalle «Quedan 5 · mínimo 5 · pide más» y la pastilla «Bajo»; con pocos avisos, un acceso a «Pedir al proveedor».
- **Recorrido de las 15 tareas más comunes** (propuesto 24 nov): contar toques, marcar pasos de más y cosas escondidas, informe con capturas para aprobar una por una. Primer paso de esta fase.

- **Recorrido del 24 nov** (`docs/recorrido-24nov.md`, puntos 3 a 13, por aprobar uno por uno): Productos y Stock en una sola pantalla; marcar la llegada en Servicios tocando la pastilla; «Recibir» arriba y menos pestañas en Servicios; menos cosas encima de la lista de Productos; títulos repetidos en Clientes; «Igual que la última vez» y nombres en vez de correos en Caja; sin «Nueva venta» dentro de Vender; **amarillo más suave en modo claro**; iniciales «SP» en vez de «S(»; anchos en computador. Revisar cada cambio en claro y en oscuro.

### Después

- 0.18.5: traslados entre sedes y encargado de turno.
- 0.18.6: fiados, precios y Servicios por sede; el recibo con la dirección y el teléfono de la sede (APROBADO).
- Panel: Negocios que distinga Pro de Pro Servicios y muestre sedes, e «Ingresos del mes» en Resumen; el registro de acciones con más de 50 negocios, por ids.
- Pruebas del dueño en el celular con el APK (aviso de primera venta, Contar con la cámara, vender sin conexión): con el APK 0.18.2.
- **Sacar el RUT: ya hay precios encendidos y entró el primer pago real. No dejarlo para después.**

## Recordatorios de trabajo

- Todo en español; planear y aprobar antes de programar; pedir permiso para commit, PR, migraciones y publicar.
- Revisión de Codex antes de publicar, comprobando cada hallazgo.
- Una sola carpeta (Desktop/Stockealo), una rama por versión.
