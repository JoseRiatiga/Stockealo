# Revisión de la portada · stockealo.online (25 nov)

Revisada en computador (800 px) y en celular (375 px). El código está en `web_site/index.html` y `web_site/site.css`. La última vez que se tocó a fondo fue en la 0.13.2; la app ya va en la 0.18.6.

## Lo que funciona bien
- **Un mensaje claro arriba:** «Tu negocio en orden, desde el celular», con dos botones: Descargar para Android y Usar en el navegador.
- **Precios en vivo** desde el servidor (Pro $24.900/mes, $249.000/año) y el pago con Wompi explicado.
- **Títulos para buscadores y redes:** descripción para Google y vista previa al compartir, ya puestos.
- **En el celular no se sale de la pantalla** (no hay que mover de lado).
- **Enlaces legales, WhatsApp y «Cómo instalarla»** funcionan.

## Lo que falla o quedó viejo

### 1. No se ve la app
- La única imagen de toda la página es el ícono (la caja verde). No hay ni una captura de Vender, Inventario, Caja ni de la tienda en línea.
- Quien llega no sabe cómo se ve ni si es fácil. Es lo primero que se mira antes de descargar.

### 2. Colores
- **Corrección:** la portada no es siempre oscura. Sigue el modo del equipo (`prefers-color-scheme`): en modo claro usa los mismos colores de la app. La revisé en un navegador en modo oscuro.
- Lo que sí pasa: con el modo oscuro del equipo, la portada sale oscura aunque la app no esté en oscuro. Es un detalle menor, pero se ven distintas.

### 3. Se quedó en la 0.13
Faltan cosas que ya existen y que venden:
- **Pro Servicios:** al tocar la pestaña solo sale una frase. No dice qué trae: tablero, agenda, empleados, comisiones, 2 sedes incluidas.
- **Sedes y traslados (0.18):** no aparecen en ninguna parte.
- **Lo que trae Pro:** la portada muestra 4 cosas; la app tiene 8. Faltan roles y límites del equipo, precio por mayor, metas por persona y cupones de la tienda.
- **Nombres distintos:** la portada dice «Pro Negocio» y la app dice «Pro». Conviene un solo nombre.
- **Solo tiendas:** el texto de arriba habla de «tiendas, misceláneas y emprendimientos». Ya hay lavaderos y negocios de servicios, que es justo el plan más caro.

### 4. La sección «Negocios que ya venden en línea» resta
- Hoy muestra dos tiendas: «Miselanea» (13 productos) y «Yeddgd» (2 productos).
- «Yeddgd» parece una prueba. Una tienda con 2 productos y nombre sin sentido da la impresión contraria a la que se busca.
- Propuesta: mostrar solo tiendas con un mínimo de productos (por ejemplo, 8 o más) y foto, o que el dueño las elija desde el panel. Si no hay suficientes, no mostrar la sección.

### 5. Muy larga en el celular y sin un camino claro
- En el celular mide unos 6.500 px, casi 8 pantallas.
- Las 8 tarjetas de lo gratis y las 4 de Pro son parecidas y se leen como una lista.
- No hay una sección de «cómo empiezo» (3 pasos) ni preguntas frecuentes: ¿funciona sin internet?, ¿mis datos son míos?, ¿cómo pago?, ¿puedo cancelar?
- Al bajar rápido, las tarjetas aparecen vacías un momento, hasta que «entran» con la animación.

### 6. Confianza
- **Sin testimonios.** No hay ni un comentario de un cliente real. Ya hay clientes; con su permiso, una frase y el nombre del negocio ayudan mucho.
- **El correo de contacto es el personal** (byjosealbert@gmail.com). Para un producto que cobra se ve mejor un correo del dominio, como soporte@stockealo.online. Se puede reenviar al Gmail.
- **«Gratis para siempre en lo esencial»:** es una promesa fuerte. Si algún día cambia lo que es gratis, queda escrita. Sugiero «Gratis en lo esencial» sin el «para siempre», o dejarlo si de verdad es una decisión firme.

### 7. Detalles
- El botón de arriba dice «Entrar» y lleva a la app; para quien no tiene cuenta convendría «Crear cuenta gratis» al lado.
- En el computador, el lado derecho del inicio es solo el ícono grande: espacio desperdiciado, donde iría una captura del celular con la app.
- La página no dice que también hay versión para iPhone desde el navegador; «Cómo instalarla» sí lo explica, pero está escondido en letra pequeña.

## Mi opinión
**Sí necesita un re-diseño completo,** no solo retoques. El texto principal sirve, pero la página:
- no muestra la app;
- no cuenta lo que hoy se vende (Pro Servicios, sedes);
- muestra una tienda de prueba como ejemplo.

Para un cliente como Mary, que llega a pagar Pro, es lo primero que ve.

### Propuesta de orden de la página nueva (para bocetar, sin aprobar)
1. **Inicio:**
   - el mensaje de hoy, ajustado a tiendas y negocios de servicios;
   - una captura grande del celular con la app;
   - «Crear cuenta gratis» y «Descargar para Android».
2. **Tres pasos:** crea tu negocio, carga tus productos, vende.
3. **Lo que hace la app, con capturas:** Vender y caja, Inventario y stock, Fiados, Tienda en línea.
4. **Para negocios de servicios:** el tablero, la agenda y los empleados, con su captura.
5. **Planes:** Gratis, Pro y Pro Servicios lado a lado, con todo lo que trae cada uno (los mismos textos que la app, para no repetir dos versiones).
6. **Tiendas de clientes:** solo si hay suficientes reales.
7. **Testimonios,** cuando haya.
8. **Preguntas frecuentes.**
9. **Contacto y pie.**

El estilo sigue siendo el de la app (claro, con el verde de Stockealo, y oscuro si el equipo está en modo oscuro).

## Lo que necesito saber antes de bocetar
- **Capturas:** ¿las saco yo del LAVADERO, o prefiere un negocio de ejemplo con productos bonitos, por ejemplo una tienda con fotos?
- **Testimonios:** ¿hay algún cliente que acepte poner una frase?
- **Correo:** ¿crea soporte@stockealo.online en Hostinger, o seguimos con el Gmail?
- **«Gratis para siempre»:** ¿se queda o lo suavizamos?
