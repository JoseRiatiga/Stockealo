# Plan 0.18.3 · Sedes y un solo pago (APROBADO el 24 nov, con A–E como se recomendó)

Fase 2 del plan del 24 nov (`docs/plan-proxima-sesion.md`). Lo decidido antes está en `docs/plan-sedes.md` (secciones 6 y 9). Aquí va cómo se haría y las preguntas que faltan.

## Cómo está hoy (revisado en el código y la nube)

- Los cupos de sede viven en `branch_slots` (cuántos, desde, hasta, origen). `branch_allowance` suma 2 si el plan es Pro Servicios y les agrega los cupos vigentes. Hoy los cupos **solo se dan desde el panel**: no se pueden comprar.
- El pago (`pro-checkout` y luego `pro_apply_payment` cuando llega el aviso de Wompi) compra **un plan**. Crea una suscripción que empieza cuando termina la vigente del mismo tipo.
- La tienda (`get_public_store`) no sabe nada de sedes: muestra el stock total del negocio.

## 1. Sedes en el menú lateral (aprobado)

```
┌──────────────────────────────┐
│ [🚗] LAVADERO              ⌃ │
│      Cambiar negocio         │
├──────────────────────────────┤
│  ● Principal    Caja abierta │  ← la sede en uso
│  ○ Norte        Caja cerrada │
│  ▦ Todas las sedes           │  ← dueño y administradores
│  ＋ Abrir una sede           │  ← solo el dueño
└──────────────────────────────┘
```
- Las sedes abiertas van debajo de la tarjeta del negocio. Un toque cambia de sede.
- El cajero ve solo su sede, sin poder cambiarla.
- Si hay muchas sedes, se muestran 4 y «Ver todas». Con el menú cerrado (solo íconos), se usa la hoja de hoy.
- «＋ Abrir una sede» abre el mismo formulario de Módulos › Sedes: no hay un segundo formulario. Sin cupo libre, lleva a la compra de cupos (punto 3).

## 2. La coronita (aprobada; falta decidir el texto)

- La corona dorada aparece junto al nombre de la cuenta, abajo del menú: «Jose Riatiga · Dueño · Pro Servicios».
- También aparece en cada negocio de «Tus negocios».
- La misma corona para los dos planes; la diferencia va escrita.

## 3. Un solo pago: plan + cupos de sede

En la pantalla Pro, debajo de cada plan:

```
Pro Servicios                        $79.900 /mes
Principal + 2 sedes incluidas
Sedes extra      [ − ]  1  [ + ]     $24.900 /mes
───────────────────────────────────────────────
Total                                $104.800 /mes
                           [ Pagar con Wompi ]
```

**Precios (aprobados el 23 nov):**

| | Al mes | Al año | Desde 3 extra, cada una al mes |
|---|---|---|---|
| Sede extra con Pro | $14.900 | $149.000 | $12.900 |
| Sede extra con Pro Servicios | $24.900 | $249.000 | $21.900 |

**Cómo se haría:**
- **Nube (migración):**
  - una tabla `branch_slot_prices` con esos precios, para cambiarlos desde la nube sin publicar la app;
  - una columna `branch_slots` en `pro_payments` (por defecto 0).
- **`pro-checkout`:** recibe cuántas sedes extra y calcula el total en el servidor. La app no puede cambiar el precio.
- **`pro_apply_payment`:** al aprobarse el pago, crea la suscripción **y** los cupos, con la misma fecha de vencimiento.

**Tres casos de compra:**
1. **Plan con sedes, todo junto:** plan + cupos, y todo vence el mismo día.
2. **Agregar sedes a mitad del periodo:** se pagan solo los días que faltan, redondeado a $100. Por ejemplo: con 15 de 30 días restantes, una sede de Pro Servicios cuesta $12.500.
3. **Renovar:** la compra trae ya marcadas las sedes que tiene hoy, para que no se le venzan sin darse cuenta.

## 4. Subir de Pro a Pro Servicios (aprobado)

- Se descuenta lo que le queda de Pro, por días: Pro × días restantes / días del periodo, redondeado a $100.
- **Además, el Pro viejo se corta ese día.** Si no, el cliente tendría el descuento **y además** esos días de Pro después de Pro Servicios: los cobraría dos veces a su favor.
- Este corte cambia una suscripción ya pagada. Por eso necesita su aprobación explícita (pregunta C).

## 5. Tienda por sede (aprobada el 23 nov: solo el stock)

```
┌─────────────────────────────────────────────┐
│ LAVADERO                                    │
│ Estás viendo: [ Norte ▾ ]                   │
│ Cra 10 # 20-30 · Lun a Sáb 8 a. m.–6 p. m.  │
│ Cómo llegar ›                               │
├─────────────────────────────────────────────┤
│ Shampoo        $9.000   Quedan 4 en Norte   │
│ Cera           $15.000  Agotado en Norte ·  │
│                         hay en Principal    │
└─────────────────────────────────────────────┘
```
- `get_public_store` trae las sedes abiertas (nombre, dirección, horario, teléfono) y el stock de cada producto en cada sede.
- Quien compra elige la sede, y la tienda la recuerda en ese navegador.
- «Cómo llegar» abre Google Maps con la dirección.
- Si la sede elegida no tiene el producto, la tienda dice en qué otra sede hay.
- Un negocio sin sedes ve su tienda igual que hoy.

## Preguntas para el dueño

- **A. El pedido de la tienda dice en qué sede se pidió.** El dueño ve «Pedido T-0012 · Norte» y sabe dónde prepararlo. Propongo **sí**: es una columna y no cambia lo que hace el cliente. La recogida con elección de sede sigue para después, como estaba.
- **B. Agregar sedes cuando faltan menos de 7 días del plan.** El plan aprobado dice «se suma el periodo siguiente». Pero el cupo debe vencer con el plan, y el plan no se está renovando. Propongo que en ese caso la app ofrezca **renovar el plan y agregar las sedes en un solo pago**.
- **C. Cortar el Pro viejo al subir a Pro Servicios con descuento** (punto 4). Propongo **sí**.
- **D. Texto junto a la corona:** «Dueño · Pro Servicios», o solo la corona con el nombre del plan al pasar el mouse. Propongo **el texto**: en el celular no hay mouse.

## Orden de trabajo y publicación

1. **Menú lateral y coronita:** solo app.
2. **Tienda por sede:** migración pequeña en `get_public_store` y la página de la tienda.
3. **Un solo pago:** migración de precios y columna, `pro-checkout`, `pro_apply_payment` y la pantalla Pro.
   - Es lo más delicado, porque toca plata real.
   - Cómo probarlo: ver la pregunta E.

- **E. Cómo probar el pago de plan + sedes.** La llave de pruebas de Wompi es una sola para toda la app. Si la pongo, mientras dure la prueba nadie puede pagar de verdad. Propongo: probar todo el cálculo con pruebas automáticas y, al final, que usted haga **una compra real pequeña**: 1 sede extra prorrateada en el LAVADERO. Si prefiere la llave de pruebas, la pongo un rato en un horario sin clientes y la vuelvo a quitar.

Cada migración y cada publicación con su permiso. Revisión de Codex antes de publicar, y la revisión a mano en la web con `tool/check_cors.sh`.
