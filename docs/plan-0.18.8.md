# Plan 0.18.8: que un equipo no pise lo que cambió otro (28 nov)

Prioridad del dueño. Sale sola y corta: lo demás que estaba para la 0.18.8 pasa a la 0.18.9 (ver al final).

## Orden de prioridad

| # | Qué | Por qué va en ese lugar |
|---|-----|-------------------------|
| 1 | **Roles del equipo** que vuelven a como estaban | Un cajero puede recuperar permisos que ya le habían quitado. Es seguridad. |
| 2 | **Ventas** que vuelven a «pendiente» o cambian de medio de pago o de cliente | Descuadra entregas y la caja. Es plata. |
| 3 | **Datos del negocio** (nombre, tipo, ícono, color, logo, caja obligatoria, zona horaria, servicios) | Molesta y confunde; la zona horaria y la caja obligatoria cambian cómo funciona la app. |
| 4 | **Categorías** (nombre e ícono) | Solo se ve distinto. |
| 5 | **«Sincronizar ahora»** = mandar la cola y bajar | Cierra la puerta por donde entran los puntos 1 a 4. |
| 6 | **Copiar** que falla en el navegador (11 botones) | Pasó una vez; solo sale un error en el panel. |
| 7 | **Mapas del código** de la web en GitHub | No arregla nada hoy; sirve para rastrear el próximo error. |

Los puntos 1 a 5 son un solo arreglo (la subida completa) y se hacen juntos, en ese orden de revisión. El 6 y el 7 son aparte y cortos.

## Qué pasa hoy (puntos 1 a 5)

La app tiene dos formas de hablar con la nube.

1. **La de todos los días** (`syncFromCloud`): manda solo los cambios que tiene en cola y después **baja** lo de la nube, que reemplaza lo del equipo. Esta funciona bien: si algo cambia en otro equipo, aquí se ve al bajar.
2. **La subida completa** (`syncToCloud`): sube **todo** lo que el equipo tiene guardado. Para productos, tallas y clientes solo crea lo que falta (`ignoreDuplicates`). Pero para el equipo, las ventas, el negocio y las categorías **reemplaza** lo de la nube con la copia del equipo, aunque esté vieja.

**Cuándo corre la subida completa:**
- la primera vez que se usa la nube en un equipo;
- al encender la nube (Tienda en línea, Equipo, el recordatorio del Inicio);
- con el botón **«Sincronizar ahora»** de Perfil.

**Ejemplo real:** el dueño le cambia el rol a un cajero en el celular. Días después, en el computador, toca «Sincronizar ahora». El computador todavía tiene el rol viejo y lo vuelve a subir, así que el cajero recupera permisos que ya le habían quitado.

## Arreglo (puntos 1 a 5)

1. **La subida completa solo crea lo que falta**, como ya lo hace con los productos: `ignoreDuplicates` en equipo, ventas, negocios y categorías. Lo que ya está en la nube no se toca.
2. **Revisar que cada cambio vaya por la cola**, en el orden de la tabla: roles, entregas y anulaciones de ventas, datos del negocio, categorías. Si alguno solo llegaba a la nube por la subida completa, pasa a la cola, para no perder cambios.
3. **«Sincronizar ahora»** hace lo mismo que la sincronización de todos los días: manda la cola y baja lo de la nube. Si a la nube le falta algo, lo crea, pero no reemplaza nada.
4. **Prueba de candado:** la subida completa nunca reemplaza una fila que ya existe.
5. **Revisión de Codex (corregido):**
   - **Cambios hechos con la nube apagada** (en el celular viene apagada por defecto) no pasan por la cola. Al encender la nube, la **primera** subida completa manda la copia del equipo tal cual, como antes; las siguientes ya no pisan nada. La marca se borra solo si esa subida termina bien.
   - Solo se crean o suben los **negocios propios** que faltan en la nube. Uno ajeno que el equipo ya no puede ver no se puede crear desde ahí, y antes hacía fallar toda la subida.

## Punto 6: copiar que falla

«Clipboard.setData failed» (panel admin 0.18.1, 24 nov, una vez). El navegador a veces no deja copiar, por ejemplo si la pestaña no está al frente, y la app no lo esperaba.
- **Arreglo:** una sola función para copiar en `core`, que usan los 11 botones de la app y el panel. Si el navegador no deja, sale el aviso «No se pudo copiar. Selecciona el texto y cópialo a mano.» en vez del error.

## Punto 7: mapas del código

«Null check operator used on a null value» (app web 0.18.2, 24 nov, una vez). El rastro viene comprimido (`main.dart.js`) y esa versión ya no existe, así que no se puede saber en qué línea pasó.
- **Arreglo:** que la publicación de la web guarde los mapas del código de cada versión, solo en GitHub y no en la página pública. Así, el próximo error se puede traducir a la línea exacta.

## Lo que no cambia
- Las ventas, el stock y los productos funcionan igual: ya iban por la cola y por diferencia.
- No hay migración en la nube.

## Pruebas
- Un rol cambiado en un equipo y «Sincronizar ahora» en otro con la copia vieja: el rol nuevo se mantiene.
- Una venta entregada en un equipo no vuelve a «pendiente» por la subida de otro.
- Un negocio que solo existe en el equipo (sin nube): se crea completo al encender la nube.
- El nombre del negocio cambiado en un equipo llega al otro al bajar.
- Copiar cuando el navegador no deja: sale el aviso y no se registra un error.

## Anotado para después (pedido del dueño, 28 nov): estado de los errores en el panel

Hoy los errores de Panel › Errores no tienen estado: un error ya corregido sigue ahí y parece que todavía existe.
- Cada error (agrupado por su huella, `fingerprint`) tendrá un estado: **Nuevo**, **Pendiente de revisar**, **En proceso** o **Corregido** (con la versión en que se corrigió).
- Filtro por estado, y los corregidos se esconden por defecto.
- **Si un error «Corregido» vuelve a llegar** con una versión igual o más nueva, pasa solo a **«Volvió a pasar»**, para no creer que está arreglado cuando no lo está.
- Necesita una migración en la nube (tabla de estados por huella), con permiso aparte.
- Los dos errores del 24 nov (copiar y «Null check») se marcan «Corregido en 0.18.8» cuando exista el estado.

## Lo que pasa a la 0.18.9
- «Tienda en línea» ordenada en 5 secciones, con plantillas con dibujo, la dirección ahí mismo y un mapa de OpenStreetMap (boceto aprobado: https://claude.ai/artifact/5uXxEWtdVAdY9qpRtD3UzB).
- Botones de tallas según el tipo de negocio.
- Papelera de negocios en todos los equipos y purga en la nube.

Después: la web de escritorio (0.18.10) y fiados, precios y Servicios por sede (0.18.11).
