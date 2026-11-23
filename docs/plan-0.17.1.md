# Plan de la 0.17.1 — planes, precios y cómo se venden

Estado: **APROBADO el 23 nov 2026.** Ya hecho antes en la rama `fix/0.17.0-pro` (sin commit): pantalla Pro con los tres planes (primera versión) y panel sin «Permanente».

La 0.17.1 sale con el APK (trae la 0.17.0 + esto). La web se publica al unir.

## Decisiones tomadas

- Pro Servicios: **$79.900 al mes**.
- **Nada permanente:** no se vende ni se regala. Desde el panel, máximo 1 año. Los 2 permanentes que había (Miselanea y Loliando) ya los pasó el dueño a 1 año, hasta el 23 nov 2027.
- **Sin prueba gratis** (con el Excel y el importador alguien podría abrir cuentas nuevas sin fin) y **sin cupón de lanzamiento**.
- **Sin plan semanal** (con Wompi se pierde cerca del 14 % y no fideliza). Si el dueño quiere dar una semana, va como código desde el panel.
- **Sin IVA por ahora:** el dueño no tiene RUT todavía; lo sacará antes de cobrar en serio y de pasar Wompi a modo real.

## Bloques

### A. Pantalla Pro
- Tres tarjetas:
  - Gratis;
  - Pro, con borde y la etiqueta «Recomendado»;
  - Pro Servicios, con «Para lavaderos, barberías, talleres y otros servicios».
- «Tu plan actual» en el plan que tiene el negocio. Catálogo «sin marca de agua». En el celular, una tarjeta debajo de otra.
- Selector **Mensual / Anual** con «Anual: 2 meses gratis». En Anual, el precio grande es lo que sale por mes y debajo va «$249.000 al año · ahorras $49.800».
- Los botones dicen **«Elegir»**.
- Nota final: «Precios en pesos colombianos (COP). Puedes cancelar cuando quieras».
- Con los precios apagados en el panel no se ven ni el selector ni los precios: queda «Escríbenos para activarlo».
- La ventana corta de Pro (al tocar algo de Pro) muestra los 5 primeros beneficios; el resto está en «Ver planes».

### B. Sin permanente
- Panel: Dar Pro / Pro Servicios y Códigos sin «Permanente»; lo más largo es 1 año (HECHO).
- Nube: migración `20261209000000_no_lifetime_grants.sql` (ensayada OK, falta aplicarla con permiso). Rechaza regalos sin fecha o de más de 366 días.

### C. Precios (en la nube, apagados)

| Plan | Mensual | Anual |
|---|---|---|
| Pro | $24.900 | $249.000 (se muestra «$20.750/mes») |
| Pro Servicios | $79.900 | $799.000 (se muestra «$66.580/mes») |

- Semanal, Pro Global y permanente: apagados para siempre.
- **HECHO en la nube el 23 nov, con permiso:**
  - Pro mensual $24.900 y anual $249.000 (antes $298.800, «2 meses gratis»).
  - Pro Servicios mensual $79.900 y anual $799.000 (nuevo; antes $958.800, «2 meses gratis»).
  - Se quitó la etiqueta falsa «Más elegido».
  - Se borraron `founder_slots` y `founder_until`.
  - `show_pricing` sigue apagado: la portada y la app no muestran precios. Comprobado: `public_landing` responde sin planes.
- Falta en código: quitar los campos «Cupos de la oferta Fundador» y «Oferta Fundador hasta» de Panel › Configuración de Pro.
- **Último paso (después de publicar):**
  1. El dueño hace una compra real de un mes en un negocio de prueba y se comprueba que Pro se activa solo y que el pago sale en el panel.
  2. Se revisa la portada con los precios.
  3. Se enciende «Mostrar precios y compra».

### D. Ver lo de Pro antes de pagar
- **Precio por mayor sin Pro:**
  - Se puede configurar y guardar en Editar producto («Guardado. Se activa con Pro · Ver planes»).
  - En Vender, al llegar a la cantidad, sale en gris «Con Pro: $1.800 c/u por mayor (ahorra $2.400)», y se cobra el precio normal.
  - Esa línea gris **solo la ve el dueño**, no los cajeros.
- **Catálogo PDF e imágenes para historias:**

| Quién | Plantilla | Vista previa | Al descargar o compartir |
|---|---|---|---|
| Sin Pro | Clásica (gratis) | Normal | Se descarga, con una marca pequeña «Hecho con Stockealo» en la **esquina inferior derecha** (reemplaza al pie de hoy) |
| Sin Pro | Plantillas y colores de Pro | Con la **marca suave en diagonal en el medio** (gris claro, sin recuadro, una vez por página; en historias, con un tono del color de fondo), para que una captura no sirva | Pide Pro, o deja bajar la versión Clásica gratis (como hoy) |
| Con Pro | Todas | Sin marca | Sin marca |

- No se bloquean las capturas de pantalla: la marca en diagonal las vuelve inútiles.
- La tienda en línea sigue igual: se arma y se ve en vista previa, y se publica con Pro. Se queda el pie discreto «Tienda creada con Stockealo», también con Pro.

### E. Mensajes del código (panel)
- El panel pregunta si es **compra** o **regalo** y copia el mensaje que corresponde.
- Un emoji al inicio de cada línea y la negrita de WhatsApp con asteriscos.
- Lo que trae el código cambia según el plan.
- La línea «Úsalo antes del…» solo sale si el código vence.

**Compra:**
```
¡Hola! 👋 Gracias por elegir *Stockealo Pro Servicios*.

🎟️ Tu código: *STK-U2EP-W87F*
⏳ Te da *1 mes* de Pro Servicios

✨ *Lo que se activa:*
• Tablero de trabajos y comisiones
• Agenda y reservas en línea
• Todo lo de Pro: tienda en línea, precio por mayor y más

📲 *Para activarlo:*
1. Abre Stockealo › Ajustes › Stockealo Pro
2. Baja a «¿Ya tienes un código?» y escríbelo

📅 Úsalo antes del 30/11/2026.
¿Dudas? Escríbeme por aquí y te ayudo 🙌
```

**Regalo:**
```
¡Hola! 🎁 Te regalo *1 semana de Stockealo Pro* para que lo pruebes en tu negocio.

🎟️ Tu código: *STK-4KMR-JGRS*

✨ *Con Pro tienes:*
• Tienda en línea con pedidos por WhatsApp
• Precio por mayor
• Cobro automático de fiados

📲 Actívalo en: Ajustes › Stockealo Pro › «¿Ya tienes un código?»

Si te sirve, me cuentas y te ayudo a dejarlo listo 🙌
```

Los códigos siguen empezando por **STK** (por Stockealo): se reconocen, no se confunden con los cupones de las tiendas y la app detecta si les falta una letra.

## Cómo quedó (23 nov, sin commit)

- **A–E hechos en código.** 693 pruebas pasan antes de la corrección; después se volvieron a correr las de Pro, el panel y Vender (95, todas pasan).
- **Pantalla Pro:**
  - quien ya tiene un plan ve «Tu plan actual» y, con precios a la vista, también «Renovar» (se suma a lo que le queda);
  - el plan se elige en la tarjeta y abajo queda el pago (se quitó la lista vieja de planes).
- **Catálogo:**
  - la Clásica gratis ya tenía «Hecho con Stockealo» abajo a la derecha, en el pie de página;
  - las historias de Instagram con diseño de Pro siguen pidiendo Pro antes de abrirse, así que ningún diseño de Pro sale sin Pro;
  - la marca en diagonal va en la vista previa del catálogo.
- **Codex: 2 hallazgos corregidos:**
  - un código permanente ya creado podía canjearse sin fin. Ahora la migración pasa los códigos sin días a 365 y el canje nunca da más de 366 días. Un pago de un plan sin periodo conocido da 365 días;
  - el selector «Anual» podía elegir el mensual si faltaba el anual. Ahora, sin ese periodo, la tarjeta queda sin precio y «Elegir» lleva a escribir por WhatsApp.
- **Migración** `20261209000000_no_lifetime_grants.sql` ampliada y **ensayada OK** con rollback (las 4 funciones quedan bien y no hay códigos sin días). **SIN APLICAR.**

## Cómo se trabaja

- Rama `fix/0.17.0-pro`, versión **0.17.1+59** con sus novedades.
- Migraciones ensayadas y aplicadas solo con permiso: la regla sin permanente y la carga de precios apagados.
- Pruebas de lo que toca plata y de la marca de agua. Codex antes de publicar.
- Commit, PR y publicación solo con permiso. Luego el APK v0.17.1 (trae la 0.17.0).
