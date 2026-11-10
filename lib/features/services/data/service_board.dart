import '../models/service_models.dart';

/// Estado de un empleado en el día
enum StaffState {
  /// Aún no se marcó si vino
  notMarked,

  /// Marcado como «No vino»
  absent,

  /// Vino y está libre
  available,

  /// Está haciendo un servicio
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
///   • Un empleado tiene un solo servicio activo a la vez.
///   • Si no hay nadie libre, el servicio queda en cola por orden de llegada.
///   • Cuando alguien se libera, se le sugiere el primer servicio de la cola que
///     puede hacer (el cajero confirma).
class ServiceBoard {
  final List<WorkOrder> orders;
  final List<StaffMember> staff;
  final List<ShopService> services;

  /// Asistencia de hoy por empleado
  final Map<String, StaffAttendance> attendance;

  ServiceBoard({
    required this.orders,
    required this.staff,
    required this.services,
    required List<StaffAttendance> attendance,
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

  /// Servicio que el empleado está haciendo ahora (si hay)
  LineRef? activeLineOf(String staffId) {
    for (final o in orders) {
      if (!o.isOpen) continue;
      for (var i = 0; i < o.lines.length; i++) {
        final l = o.lines[i];
        if (l.isInProgress && l.staffIds.contains(staffId)) return (order: o, index: i);
      }
    }
    return null;
  }

  StaffState stateOf(String staffId) {
    final a = attendance[staffId];
    if (a == null) return StaffState.notMarked;
    if (a.isAbsent) return StaffState.absent;
    if (a.hasLeft) return StaffState.left;
    if (activeLineOf(staffId) != null) return StaffState.busy;
    if (a.onPause) return StaffState.paused;
    return StaffState.available;
  }

  /// Vino, no se ha ido, no está en pausa y no tiene otro servicio activo
  bool isFree(String staffId) => stateOf(staffId) == StaffState.available;

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
      StaffState.notMarked => 'Primero marca la llegada de $name en Asistencia.',
      StaffState.absent => '$name no vino hoy.',
      StaffState.left => '$name ya se fue.',
      StaffState.paused => '$name está en pausa.',
      StaffState.busy => '$name ya está haciendo otro servicio.',
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
