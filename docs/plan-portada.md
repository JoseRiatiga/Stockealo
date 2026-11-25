# Plan · Portada nueva de stockealo.online

Estado: **APROBADO el 25 nov** (plan y boceto: https://claude.ai/artifact/9mFAhG72LaRaXgRa9MzkZ4). Sale de `docs/revision-portada-25nov.md`. No se toca código ni git hasta que el dueño apruebe el plan y el boceto.

No cambia la versión de la app: la portada es `web_site/index.html` y `web_site/site.css`, y se publica sola al unir a main, igual que hoy.

## Objetivo
Que quien llega entienda en 5 segundos qué es Stockealo, **vea la app**, sepa que lo esencial es gratis y cree su cuenta. Y que el negocio de servicios (lavadero, barbería) vea que también es para él, porque Pro Servicios es el plan más caro.

## Orden de la página
1. **Inicio**
   - Título: «Tu negocio en orden, desde el celular».
   - Debajo: «Inventario, ventas, caja y fiados para tiendas y negocios de servicios. Gratis en lo esencial».
   - Botones: «Crear cuenta gratis» (va a la app, en crear cuenta) y «Descargar para Android».
   - Debajo, en pequeño: «También en el navegador del computador o del iPhone · Cómo instalarla».
   - A la derecha, o debajo en el celular, **un celular con la app** en la pantalla de Inicio.
2. **Cómo empiezas, en 3 pasos:** crea tu negocio, carga tus productos (a mano, con el lector o desde Excel), vende y cuadra la caja.
3. **Lo que hace la app, con capturas.** Cuatro bloques que alternan imagen y texto:
   - Vender y caja;
   - Inventario y stock;
   - Fiados;
   - Tienda en línea.
4. **Para negocios de servicios:** el tablero (recibido, en proceso, listo), la agenda, los empleados con sus comisiones y las sedes, con una captura.
5. **Planes lado a lado: Gratis, Pro y Pro Servicios.**
   - Con todo lo que trae cada uno. Los textos son los mismos de la app, para no tener dos versiones distintas.
   - Precios en vivo desde el servidor, como hoy.
   - El nombre es «Pro», no «Pro Negocio».
6. **Tiendas de clientes:** solo tiendas con 8 o más productos. Si no hay al menos 3, la sección no se muestra (se arregla en la función `public_landing`).
   - Un negocio con varias sedes es **una sola tarjeta** (una tienda por negocio), con la etiqueta «3 sedes». Al entrar, el cliente elige la sede con el selector que ya tiene la tienda (0.18.3). `public_landing` devuelve también cuántas sedes abiertas tiene.
7. **Preguntas frecuentes,** 6 a 8, que se abren al tocar:
   - ¿Funciona sin internet?
   - ¿Mis datos son míos y puedo descargarlos?
   - ¿Cómo pago Pro?
   - ¿Puedo cancelar?
   - ¿Sirve para varios locales?
   - ¿Mis empleados pueden usarla?
   - ¿Hay versión para iPhone?
8. **Contacto y pie:** WhatsApp, correo, términos y privacidad.

Testimonios: la sección queda lista pero **oculta** hasta que haya al menos dos clientes que acepten.

## Cómo se ve
- **El mismo estilo de la app:** fondo gris claro, tarjetas blancas y el verde de Stockealo solo en lo importante. Siempre clara al abrir; oscura solo si la persona la cambia con el botón.
- **Más corta en el celular:** de unos 6.500 px a unos 4.500, porque las listas de tarjetas se cambian por bloques con imagen.
- **Capturas:** imágenes de verdad de la app, a 2x, en formato WebP y con carga diferida, para que la página siga rápida.
- **Sin las tarjetas vacías al bajar:** lo de abajo aparece sin esperar la animación.

## Decisiones que tomé por usted (cámbielas si quiere)
Las 4 preguntas de la revisión siguen sin respuesta; para poder bocetar tomé estas, y cualquiera se cambia:
- **Capturas:** de un **negocio de ejemplo con productos y fotos bonitas**, no del LAVADERO. El LAVADERO tiene datos de prueba como «Shampoo (prueba)». Lo armo en una cuenta de demostración, sin tocar clientes reales.
- **Testimonios:** sección oculta hasta que haya.
- **Correo:** se queda el Gmail por ahora. Recomiendo crear soporte@stockealo.online en Hostinger y reenviarlo al Gmail; cuando exista, se cambia en una línea.
- **«Gratis para siempre»:** pasa a «**Gratis en lo esencial**», que es cierto hoy y no amarra a futuro.

## Pasos (después de aprobar plan y boceto)
1. Cuenta y negocio de demostración, y sacar las capturas, en celular y en computador.
2. La página nueva en `web_site/`, con las mismas funciones de hoy: precios en vivo, WhatsApp del panel y tiendas.
3. Filtro de tiendas en `public_landing`: una migración pequeña, ensayada con rollback y aplicada con permiso.
4. Revisión en celular y computador, en claro y en oscuro; velocidad con Lighthouse.
5. Commit, PR y publicar, con permiso.

## Ideas extra (APROBADAS las 4 el 25 nov)
1. **«Tus datos son tuyos»:** un bloque corto de confianza: descárgalos en Excel cuando quieras, copia diaria en la nube, nadie más los ve.
2. **Botón de WhatsApp fijo** en el celular, abajo a la derecha, para preguntar sin buscar el contacto.
3. **Saber de dónde llegan las cuentas:** un contador propio, sin rastreadores ni cookies, de cuántas personas tocan «Crear cuenta» y desde qué página o enlace (Instagram, WhatsApp, Google).
4. **Sede extra con Pro ($14.900)** en la tarjeta de Pro, que hoy solo aparece en Pro Servicios.
5. **Botón de modo claro y oscuro** en la barra de arriba (pedido el 25 nov), con sol o luna como en la app.
   - **Por defecto siempre en modo claro** (decisión del dueño, 25 nov): ya no sigue el modo del equipo.
   - El botón pasa a modo oscuro y lo recuerda en ese navegador (localStorage), sin cookies. Al tocarlo otra vez, vuelve a claro.
