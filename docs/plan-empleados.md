# Plan: empleados en Servicios (PRIORIDAD ALTA, 11 nov 2026)

Pedido por el dueño después de presentar Stockealo a un lavadero interesado. Va **antes** que lo pendiente del re-diseño (`inventario-rediseno.md` §8). **Plan para aprobar: no se programa hasta que el dueño lo apruebe.**

## Lo que hay hoy (revisado en el código)

- **Personas que hacen los servicios** (`StaffMember`): nombre, celular, documento y % de comisión. No necesitan cuenta. Se agregan **solo en Ajustes › Equipo**.
- **Asistencia** (`StaffAttendance`): llegó, no vino, pausas y salida, por día. **No hay horarios.**
- **Tablero:** una persona está «Ocupada» si tiene **un** servicio en curso, y **no se le puede asignar otro** (`ServiceBoard.stateOf` → `busy`).
- **Comisiones:** se calculan **al cobrar cada trabajo**, sin cerrar la caja. La pestaña «Comisiones» muestra lo pendiente de cada uno con «Pagar» y «Enviar detalle por WhatsApp».
  - Lo que falla es que está en otra pestaña, lejos de la persona.
  - Además, **no cuenta los trabajos hechos que todavía no se cobran**: si alguien se va a las 11 y la moto que lavó se cobra a las 12, su comisión aparece después.

## Fase 1 · «Empleados» en lugar de Asistencia (0.13.1)

Una sola pestaña, **Empleados**, con una tarjeta por persona:

- estado ahora (disponible, ocupado con MXE800, en pausa, se fue) y horas de llegada y salida;
- **lo que lleva hoy:** servicios hechos y comisión **cobrada** y **por cobrar** (trabajos terminados que aún no se cobran);
- botones del día: Llegó · Pausa · **Se va**;
- **«Se va» muestra su liquidación al momento:** lo cobrado, lo pendiente de cobrar, «Pagar ahora» y «Enviar por WhatsApp». Sin cerrar la caja.
- **«Agregar empleado» ahí mismo:** la misma hoja de Ajustes › Equipo, movida a un solo lugar y usada desde los dos.
- La pestaña «Comisiones» queda para el historial de pagos (semana, mes). Se puede unir a Empleados si el dueño prefiere.
- **Arreglo de paso:** el tablero cortado a la izquierda.

No necesita cambios en la nube.

## Fase 2 · Varios servicios a la vez (0.13.1)

- **Ajuste del negocio:** «Un empleado puede hacer varios servicios a la vez» (apagado o encendido).
- **Encendido:** al tocar «Empezar» se puede elegir a alguien ocupado. El tablero muestra «Juan · 2 servicios (MXE800, ABC12D)».
- **Apagado:** como hoy, pero si **solo hay una persona disponible** se ofrece «Asignárselo igual».
- Las comisiones no cambian: cada servicio suma la suya.

No necesita cambios en la nube (es un ajuste del negocio que ya se sincroniza).

## Fase 3 · Horarios (0.14.0)

- **Horario del negocio (global):** por día de la semana, con hora de entrada y de salida, por ejemplo lunes a sábado de 8 a. m. a 6 p. m.
- **Horario por empleado (opcional, reemplaza al global):** por ejemplo Juan de 8 a. m. a 12 p. m., y Sebastián de 12 p. m. a 6 p. m.
- **Para qué se usa:**
  - **en Empleados:** «Juan entra a las 8», «Sebastián entra en 20 min», «Juan terminó su turno»;
  - **aviso** si a la hora de entrada no lo han marcado como llegado;
  - **el tablero sugiere** solo a quien está en su turno;
  - **horas trabajadas** del día y de la semana (llegada a salida, sin pausas), con «salió antes» o «se quedó más».
- **Necesita guardar los horarios** en la base del teléfono y en la nube: una migración pequeña, que se aplica con el permiso del dueño.

## Después (anotado)

- Cada servicio como tarjeta propia en el tablero (hoy la tarjeta es el vehículo).

## Decisiones del dueño (11 nov)

1. **Comisión:** se puede pagar solo cuando el servicio **ya está terminado**. Un servicio en curso no cuenta. Se interpreta así: terminado basta, aunque el cliente todavía no haya pagado; confirmar con el dueño si se necesita lo contrario.
2. **Varios servicios a la vez:** **máximo 2 por empleado**. Si hay pocos empleados y mucha cola, en el módulo Servicios hay un interruptor **«Habilitar múltiples servicios»** que quita ese límite.
3. **Horarios:** fuera del turno **solo se avisa** («fuera de turno»), no se bloquea.
4. **Comisiones:** **se quedan donde están** (pestaña Comisiones). El dueño no las había visto en la presentación.

**Ajustes al plan por estas decisiones:**
- **Fase 1:** «Empleados» reemplaza a Asistencia, con «Agregar empleado» ahí mismo y lo que lleva hoy cada uno, más «Ver en Comisiones». La liquidación al irse se hace en Comisiones, que ya existe. Comisiones suma lo de los servicios terminados aunque falte cobrarlos.
- **Fase 2:** límite de 2 servicios a la vez por empleado, más el interruptor «Habilitar múltiples servicios» para quitar el límite.
- **Fase 3:** horarios con aviso de «fuera de turno».

## Avance (11 nov)

**Hecho en la rama feat/0.13.1, sin commit:**
- **Fase 1:** la pestaña «Empleados» reemplaza a Asistencia (`employees_view.dart`). Tiene «Agregar empleado» ahí mismo con la hoja única `StaffEditor.show`, que también usa Ajustes › Equipo. Por persona muestra el estado, la llegada y la salida, los servicios en curso y lo que lleva hoy (servicios cobrados y comisión), con «Ver en Comisiones», y los botones Llegó, No vino, Pausa y Se va.
- **Fase 2:** hasta 2 servicios a la vez por empleado (`ServiceBoard.maxPerStaff`) y el interruptor «Habilitar múltiples servicios» en Empleados, que se guarda en este equipo (`services_multi_<negocio>`; falta subirlo a la nube).
- **Textos:** «Asistencia» pasa a «Empleados» en el tablero.
- **Tablero cortado a la izquierda:** en el código tiene su margen de 16 px. No se pudo reproducir; puede ser el recorte de la captura. Revisar con el dueño.
- 417 pruebas OK y análisis limpio.

**Fase 3 hecha (sin publicar):** horario del negocio (tarjeta en Empleados) y horario propio por empleado (en su hoja), con avisos «Debía llegar a las…», «Fuera de turno» y «Terminó su turno»; en el tablero el chip dice «fuera de turno». Base local v14. Migración `20261129200000_staff_schedules.sql` **aplicada en la nube** (11 nov). Pendiente opcional: subir a la nube el interruptor de «múltiples servicios» (hoy solo local).
