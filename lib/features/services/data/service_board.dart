import '../models/service_models.dart';
import '../models/work_schedule.dart';

/// Estado de un empleado en el día
enum StaffState {
  /// Aún no se marcó si vino
  notMarked,

  /// Marcado como «No vino»
  absent,

  /// Vino y está libre
  available,

  /// Tiene todos los servicios que puede hacer a la vez
  busy,

  /// En pausa (almuerzo, permiso)
  paused,

  /// Ya se fue
  left;

  String get label => switch (this) {
        notMarked => 'Sin marcar',
        absent => 'No vino',
        available => 'Disponible',
        busy => 'Ocupado',
        paused => 'En pausa',
        left => 'Salió',
      };
}

/// Un servicio de un trabajo: la orden y la posición del servicio en ella
typedef LineRef = ({WorkOrder order, int index});

/// Reglas del tablero de Servicios (0.12.0), sin pantallas ni base de datos:
///
///   • Ningún servicio empieza sin un empleado que haya venido hoy, esté libre y
///     esté habilitado para ese servicio.
///   • Un empleado hace hasta [ServiceBoard.defaultMax] servicios a la vez (0.13.1);
///     con «Habilitar múltiples servicios» no hay límite.
///   • Si no hay nadie libre, el servicio queda en cola por orden de llegada.
///   • Cuando alguien se libera, se le sugiere el primer servicio de la cola que
///     puede hacer (el cajero confirma).
class ServiceBoard {
  final List<WorkOrder> orders;
  final List<StaffMember> staff;
  final List<ShopService> services;

  /// Asistencia de hoy por empleado
  final Map<String, StaffAttendance> attendance;

  /// Servicios a la vez por empleado; null = sin límite («Habilitar múltiples servicios»)
  final int? maxPerStaff;

  /// Horario del negocio (para quien no tiene uno propio)
  final WorkSchedule? globalSchedule;

  /// Límite normal (decisión del dueño, 11 nov 2026)
  static const defaultMax = 2;

  ServiceBoard({
    required this.orders,
    required this.staff,
    required this.services,
    required List<StaffAttendance> attendance,
    this.maxPerStaff = defaultMax,
    this.globalSchedule,
  }) : attendance = {for (final a in attendance) a.staffId: a};

  ShopService? serviceOf(String serviceId) {
    for (final s in services) {
      if (s.id == serviceId) return s;
    }
    return null;
  }

  StaffMember? staffOf(String staffId) {
    for (final s in staff) {
      if (s.id == staffId) return s;
    }
    return null;
  }

  /// Servicios que el empleado está haciendo ahora
  List<LineRef> activeLinesOf(String staffId) => [
        for (final o in orders)
          if (o.isOpen)
            for (var i = 0; i < o.lines.length; i++)
              if (o.lines[i].isInProgress && o.lines[i].staffIds.contains(staffId)) (order: o, index: i),
      ];

  /// El primer servicio que el empleado está haciendo ahora (si hay)
  LineRef? activeLineOf(String staffId) => activeLinesOf(staffId).firstOrNull;

  /// Puede tomar otro servicio sin pasar su límite
  bool hasRoom(String staffId) => maxPerStaff == null || activeLinesOf(staffId).length < maxPerStaff!;

  StaffState stateOf(String staffId) {
    final a = attendance[staffId];
    if (a == null) return StaffState.notMarked;
    if (a.isAbsent) return StaffState.absent;
    if (a.hasLeft) return StaffState.left;
    if (!hasRoom(staffId)) return StaffState.busy;
    if (a.onPause) return StaffState.paused;
    return StaffState.available;
  }

  /// Vino, no se ha ido, no está en pausa y le cabe otro servicio
  bool isFree(String staffId) => stateOf(staffId) == StaffState.available;

  /// Horario de un empleado: el propio o, si no tiene, el del negocio
  WorkSchedule? scheduleOf(String staffId) => WorkSchedule.decode(staffOf(staffId)?.schedule) ?? globalSchedule;

  /// Está trabajando (llegó y no se ha ido) por fuera de su turno: solo se avisa
  bool outOfShift(String staffId, DateTime now) {
    final schedule = scheduleOf(staffId);
    if (schedule == null || schedule.isEmpty) return false;
    final a = attendance[staffId];
    if (a == null || a.isAbsent || a.hasLeft) return false;
    final state = schedule.stateAt(now);
    return state == ShiftState.dayOff || state == ShiftState.before || state == ShiftState.after;
  }

  /// Aviso del turno (solo avisa, no bloquea): fuera de turno o tarde. null = nada que decir
  String? shiftWarning(String staffId, DateTime now) {
    final schedule = scheduleOf(staffId);
    if (schedule == null || schedule.isEmpty) return null;
    final shift = schedule.on(now);
    final m = now.hour * 60 + now.minute;
    if (outOfShift(staffId, now)) {
      if (shift == null) return 'Hoy no le toca: está fuera de turno';
      if (m < shift.start) return 'Fuera de turno: entra a las ${ShiftTime.clock(shift.start)}';
      return 'Terminó su turno a las ${ShiftTime.clock(shift.end)}';
    }
    // 15 minutos de margen antes de avisar que no ha llegado
    if (stateOf(staffId) == StaffState.notMarked && shift != null && m >= shift.start + 15 && m < shift.end) {
      return 'Debía llegar a las ${ShiftTime.clock(shift.start)}';
    }
    return null;
  }

  /// Está habilitado para hacer ese servicio
  bool canDo(String staffId, String serviceId) {
    final service = serviceOf(serviceId);
    // Un servicio que ya no está en el catálogo lo puede hacer cualquiera
    return service == null || service.doneBy(staffId);
  }

  /// Quiénes pueden empezar este servicio ahora
  List<StaffMember> eligibleFor(WorkOrder order, int index) {
    final line = order.lines[index];
    return [
      for (final s in staff)
        if (s.isActive && isFree(s.id) && canDo(s.id, line.serviceId)) s,
    ];
  }

  /// Por qué no se puede empezar un servicio con ese empleado; null si sí se puede
  String? whyNotStart(WorkOrder order, int index, String staffId) {
    final line = order.lines[index];
    if (!line.isPending) return 'Ese servicio ya empezó.';
    final person = staffOf(staffId);
    final name = person?.name ?? 'Esa persona';
    if (person == null || !person.isActive) return '$name ya no está en el equipo.';
    if (!canDo(staffId, line.serviceId)) return '$name no hace ${line.name}.';
    return switch (stateOf(staffId)) {
      StaffState.notMarked => 'Primero marca la llegada de $name en Empleados.',
      StaffState.absent => '$name no vino hoy.',
      StaffState.left => '$name ya se fue.',
      StaffState.paused => '$name está en pausa.',
      StaffState.busy => maxPerStaff == null
          ? '$name ya está haciendo otro servicio.'
          : '$name ya tiene $maxPerStaff servicios a la vez. Si hay mucha cola, activa «Habilitar múltiples servicios» en Empleados.',
      StaffState.available => null,
    };
  }

  /// Servicios pendientes de todos los trabajos abiertos, por orden de llegada
  List<LineRef> get queue {
    final open = orders.where((o) => o.isOpen && o.status != WorkOrder.ready).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return [
      for (final o in open)
        for (var i = 0; i < o.lines.length; i++)
          if (o.lines[i].isPending) (order: o, index: i),
    ];
  }

  /// Puesto en la cola de un trabajo (1 = el siguiente); null si no tiene pendientes
  int? turnOf(WorkOrder order) {
    final ids = <String>[];
    for (final ref in queue) {
      if (!ids.contains(ref.order.id)) ids.add(ref.order.id);
    }
    final i = ids.indexOf(order.id);
    return i < 0 ? null : i + 1;
  }

  /// Lo primero de la cola que este empleado puede hacer ahora
  LineRef? suggestionFor(String staffId) {
    if (!isFree(staffId)) return null;
    for (final ref in queue) {
      if (canDo(staffId, ref.order.lines[ref.index].serviceId)) return ref;
    }
    return null;
  }

  /// Duración estimada de un servicio (la del catálogo; 20 min si no tiene)
  int durationOf(WorkOrderLine line) => serviceOf(line.serviceId)?.durationMin ?? 20;

  /// Minutos que le faltan a un servicio en proceso (0 si ya pasó su duración)
  int remainingOf(WorkOrderLine line, DateTime now) {
    if (!line.isInProgress || line.startedAt == null) return durationOf(line);
    final left = durationOf(line) - now.difference(line.startedAt!).inMinutes;
    return left < 0 ? 0 : left;
  }

  /// Servicio en proceso que ya pasó su duración estimada: minutos de más, o null
  int? delayOf(WorkOrderLine line, DateTime now) {
    if (!line.isInProgress || line.startedAt == null) return null;
    final over = now.difference(line.startedAt!).inMinutes - durationOf(line);
    return over > 0 ? over : null;
  }

  /// Espera aproximada en minutos hasta que empiece el primer servicio pendiente
  /// de un trabajo: lo que falta de lo que está en proceso más lo que hay antes en
  /// la cola, repartido entre quienes pueden trabajar. null si no hay nadie hoy.
  int? estimatedWait(WorkOrder order, {DateTime? now}) {
    final at = now ?? DateTime.now();
    final workers = staff.where((s) => s.isActive && (attendance[s.id]?.canWork ?? false)).length;
    if (workers == 0) return null;
    final refs = queue;
    final first = refs.indexWhere((r) => r.order.id == order.id);
    if (first < 0) return null;
    var minutes = 0;
    for (final o in orders) {
      if (!o.isOpen) continue;
      for (final l in o.lines) {
        if (l.isInProgress) minutes += remainingOf(l, at);
      }
    }
    for (final r in refs.take(first)) {
      minutes += durationOf(r.order.lines[r.index]);
    }
    return (minutes / workers).ceil();
  }

  /// Hay servicios esperando y nadie libre que pueda hacerlos
  bool get queueBlocked =>
      queue.isNotEmpty && !queue.any((ref) => eligibleFor(ref.order, ref.index).isNotEmpty);
}
