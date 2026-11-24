# Plan de la 0.16.9 — arreglos sueltos

Estado: **APROBADO (22 nov), 1b en la opción a.**

## 1. Citas y reservas con la hora del negocio

**Qué pasa hoy:** las citas se guardan con la hora real (UTC), y eso está bien para citas. El problema es que, al convertirla, la app usa la zona del equipo y no la del negocio:

- un cliente que reserva desde otro país (por ejemplo, desde España para una barbería de Bogotá) ve las horas libres con la hora de su celular, y la cita queda corrida 6 o 7 horas;
- si el computador del negocio tiene otra zona (mal configurado, o el dueño de viaje), la agenda se ve corrida.

**Arreglo:**
- La app y la página de reservas convierten con la zona del negocio (la misma de la 0.16.6). Las horas libres siempre se muestran con la hora del negocio, y la página lo dice: «Horas de Bogotá».
- **Migración pequeña (con tu permiso):** `get_public_booking` también devuelve la zona del negocio.
- Las citas que ya existen no se tocan: ya están guardadas con la hora real.

## 1b. La dirección del negocio en las reservas y la tienda (idea del dueño, 22 nov)

**Qué pasa hoy:** la dirección ya se guarda en un solo lugar, Ajustes › Tu negocio › Datos del recibo, y sale en los recibos. Pero quien reserva una cita o compra para recoger no la ve en ninguna parte.

**Propuesta:**
- **Reservar cita:** al elegir la hora y en la confirmación, «Te esperamos en Cra. 7 # 12-34, Centro» con el botón «Cómo llegar», que abre Google Maps con esa dirección (sin costo, sin clave).
- **Tienda en línea:** la dirección debajo del nombre del negocio y en «¿Cómo se entrega?» → «Recoger en el local».
- **Mensaje de WhatsApp de la cita:** lleva la dirección.
- **No se duplica:** se usa la misma dirección de «Datos del recibo». Si está vacía, no sale nada, y en Tienda en línea aparece la nota «Agrega la dirección de tu local» con el enlace.
- **Migración:** la misma de la sección 1; `get_public_store` y `get_public_booking` también devuelven la dirección.

**Decisión 1b.** La dirección en la web: (a) se muestra si el negocio la escribió, con un interruptor «Mostrar la dirección» en Personalizar tienda, encendido por defecto, *recomendado* (ya sale en cada recibo); o (b) apagada hasta que el negocio la encienda.

## 2. «Esperando a Google…» bloqueado

**Qué pasa hoy:** en el APK, si abres Google y lo cierras sin elegir cuenta, el botón queda bloqueado 2 minutos. En la web no pasa, porque la página entera se va a Google.

**Arreglo:**
- Al volver a la app sin haber entrado, el botón se libera solo en 2 segundos.
- Mientras espera, sale «Cancelar» debajo.

## 3. Precios de Editar producto con puntos de mil

**Qué pasa hoy:** precio de compra, de venta y «antes» se escriben sin puntos («999999»), porque esos campos aceptan decimales.

**Arreglo:** depende de la moneda del negocio.
- **Monedas sin centavos** (peso colombiano, chileno, guaraní…): puntos de mil mientras se escribe, como en el resto de la app (`MoneyInput`).
- **Monedas con centavos** (dólar, euro, peso mexicano…): se quedan como hoy, con decimales. Si no, «2.50» se leería como 250.

## Cómo se trabaja

- Rama `fix/0.16.9` desde main. Pruebas de la conversión de horas (Bogotá, Madrid, Nueva York con horario de verano) y de los precios por moneda.
- Revisión de Codex antes de publicar. Versión 0.16.9 y novedades.
- Sale junto con el APK: así el APK trae la 0.16.8 y estos arreglos en una sola actualización.
