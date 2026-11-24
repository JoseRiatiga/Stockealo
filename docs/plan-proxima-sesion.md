# Plan para la próxima sesión (guardado el 24 nov 2026)

## Dónde quedamos

- **Publicado:** 0.18.1 (web y APK v0.18.1 «Latest»): Sedes y los 12 arreglos de su prueba. Panel de administración re-diseñado (PR #48), sin cambiar la versión de la app.
- **Precios ENCENDIDOS** («Mostrar precios y compra» = on, con la llave de producción de Wompi). Los usuarios son conocidos del dueño con Pro regalado.
- **LAVADERO = entorno de pruebas.** Ahí se prueba todo lo que cambia datos. Hoy tiene Pro Servicios hasta el 11 dic y 4 cupos de sede (uno de prueba), 3 sedes de prueba cerradas y el producto «Shampoo (prueba)».
- Rama local: `main` al día. Nada sin commit en el código; este archivo queda sin commit.

## En orden

1. **PRIMERO: compra real de prueba con Wompi** (lo hace el dueño; yo verifico).
   - Comprar 1 mes de Pro ($24.900) para el LAVADERO desde su cuenta, con Nequi o tarjeta. Comisión de Wompi aproximada: $1.500.
   - Verificar en la nube: el pago queda APPROVED, llega el aviso de Wompi y la suscripción queda activa con la fecha correcta.
   - Si falla: apagar «Mostrar precios y compra» en Panel › Configuración y arreglarlo.
2. **Pruebas del dueño en el celular con el APK v0.18.1:**
   - el aviso de primera venta a los 2 días;
   - Contar inventario con la cámara (cada lectura suma 1);
   - vender sin conexión con Pro.
3. **Arreglos menores del panel** (una sola publicación):
   - en la ficha, la etiqueta «Última entrada» se parte en dos líneas: más ancho para la etiqueta;
   - borrar una nota interna no pide confirmación;
   - filtro en Pagos: «Ocultar sin terminar y de prueba».
4. **0.18.2: tienda por sede y un solo pago por plan y cupos** (ver `docs/plan-sedes.md`):
   - la tienda con selector de sede (stock, dirección, horario, «Cómo llegar»; recuerda la elegida);
   - un solo pago con Wompi por el plan y los cupos de sede (prorrateo por días; con menos de 7 días se suma el periodo siguiente).
   - Antes de programar: plan para aprobar y bocetos.
5. **Después:**
   - 0.18.3: traslados entre sedes y encargado de turno;
   - 0.18.4: fiados, precios y Servicios por sede;
   - panel: Negocios que distinga Pro de Pro Servicios y muestre sedes (migración pequeña de solo lectura), e «Ingresos del mes» en Resumen;
   - el registro de acciones busca nombres en máximo 50 negocios: con más negocios, consulta por ids;
   - sacar el RUT antes de cobrar en serio.

## Recordatorios de trabajo

- Todo en español; planear y aprobar antes de programar; pedir permiso para commit, PR, migraciones y publicar.
- Revisión de Codex antes de publicar, comprobando cada hallazgo.
- Una sola carpeta (Desktop/Stockealo), una rama por versión.
