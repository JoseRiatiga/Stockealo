# Permisos que se cumplen también en la nube (0.15.0, punto 7)

> **Estado:** PLAN, falta que el dueño elija la opción. No se toca código ni Supabase hasta aprobarlo.
> Origen: la revisión de Codex del 14 nov 2026. Hoy los permisos y límites se cumplen solo dentro de la app.

## 1. Cómo está hoy

La nube solo distingue 3 roles (Dueño, Administrador, Cajero) y en varias tablas deja escribir a **cualquiera del equipo**:

| Tabla | Hoy deja escribir a | Riesgo |
|---|---|---|
| Ventas (crear y cambiar) | Todo el equipo | Venta con descuento, fiado o pérdida sin autorización; anular sin permiso |
| Movimientos de caja (crear) | Todo el equipo | Salida de dinero por encima del límite |
| Turnos de caja (abrir y cerrar) | Todo el equipo | Cerrar la caja de otro |
| Clientes (crear y cambiar) | Todo el equipo | Cambiar la deuda de un cliente |
| Productos (cambiar) | Todo el equipo | Cambiar precios o costos |
| Productos (leer) | Todo el equipo | El costo viaja en la misma fila: quien no tiene «Ver costos» lo puede leer |

Esto ya era así antes de la 0.15.0, pero ahora que hay roles propios y límites conviene cerrarlo antes de publicar.

**Lo delicado:** la app guarda primero en el celular y sube después, también sin internet. Si la nube rechaza un cambio, ese cambio queda «pendiente con error» en el celular (con «Reintentar») y no se pierde. Como la app ya bloquea lo que el rol no permite, la nube solo rechazaría algo si alguien se salta la app o si le cambiaron el rol mientras estaba sin internet.

## 2. Opciones

### A. Permisos y límites en la nube (recomendada)

1. **Una función en la nube, `has_permission(negocio, permiso)`**, que sabe lo mismo que la app: el rol de la persona, su rol propio y los ajustes del Administrador y del Cajero. Una prueba compara la lista de la app con la de la nube para que nunca se desfasen.
2. **Reglas por tabla:**
   - Ventas: crear necesita «Vender»; con descuento, «Dar descuento»; fiada, «Fiar»; anular, «Anular venta».
   - Caja: abrir y cerrar la propia, «Abrir y cerrar mi caja»; la de otro, «Cerrar la caja de otros»; entradas y salidas, «Entradas y salidas de dinero».
   - Clientes: crear y editar, «Crear y editar clientes»; abonos, «Cobrar fiados».
   - Productos: cambiar precio o datos, «Crear y editar productos». El stock sigue bajando con cada venta.
3. **Límites:** si una venta, un fiado, una anulación o una salida pasa el límite del rol, la nube exige que lleve el número de una **autorización ya usada** por esa persona, en ese negocio y en la última hora. Cada autorización sirve para un solo cambio.

### B. Solo permisos (sin límites en la nube)

Los puntos 1 y 2 de la opción A. Los límites con números se siguen cumpliendo solo en la app. Es menos trabajo y cierra lo más grave (hacer lo que el rol no permite), pero un cajero con conocimientos podría pasarse de su límite.

### C. Todo por funciones del servidor

Cada venta, abono o movimiento pasaría por una función del servidor en lugar de escribir en la tabla. Es lo más estricto, pero obliga a rehacer la sincronización y lo que funciona sin internet. **No se recomienda.**

## 3. «Ver costos» (aparte, en cualquier opción)

Para que quien no tiene «Ver costos» de verdad no pueda leerlo, el costo tiene que salir de la fila del producto: la app lo pediría por una función que solo se lo entrega a quien tiene el permiso. Toca la descarga de productos, el Excel y los reportes. **Propuesta:** hacerlo después de la opción elegida, en la misma 0.15.0.

## 4. Orden de trabajo (opción A)

1. `has_permission` y la prueba que compara la app con la nube.
2. Reglas de ventas, caja, clientes y productos.
3. Límites con la autorización vinculada (la app manda el número de la autorización con la venta o el movimiento).
4. Pruebas en la nube con un usuario Cajero de prueba, revisión con Codex y migración con permiso.
5. «Ver costos».
