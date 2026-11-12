import 'dart:convert';

import 'service_template.dart';

export 'service_template.dart';

/// Un servicio del catálogo
class ShopService {
  final String id;
  final String businessId;
  final String name;
  final double price;
  final int? durationMin;

  /// % de comisión para quien lo hace (0-100)
  final double commissionPct;
  final bool isActive;
  final int sortOrder;

  /// Precio por tipo de vehículo (lavadero). Vacío = se usa [price] para todo.
  /// Un tipo que no aparece no se ofrece (por ejemplo, el lavado de casco en carro).
  final Map<String, double> prices;

  /// Empleados que pueden hacer este servicio. Vacío = cualquiera (servicios de la 0.11.0)
  final List<String> staffIds;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ShopService({
    required this.id,
    required this.businessId,
    required this.name,
    required this.price,
    this.durationMin,
    this.commissionPct = 0,
    this.isActive = true,
    this.sortOrder = 0,
    this.prices = const {},
    this.staffIds = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  /// Precio para un tipo de vehículo; null si el servicio no se ofrece para ese tipo
  double? priceFor(String? vehicleKind) {
    if (prices.isEmpty) return price;
    if (vehicleKind == null) return null;
    return prices[vehicleKind];
  }

  bool offeredFor(String? vehicleKind) => priceFor(vehicleKind) != null;

  /// ¿Este empleado puede hacerlo?
  bool doneBy(String staffId) => staffIds.isEmpty || staffIds.contains(staffId);

  ShopService copyWith({
    String? name,
    double? price,
    int? durationMin,
    double? commissionPct,
    bool? isActive,
    int? sortOrder,
    Map<String, double>? prices,
    List<String>? staffIds,
    DateTime? updatedAt,
  }) =>
      ShopService(
        id: id,
        businessId: businessId,
        name: name ?? this.name,
        price: price ?? this.price,
        durationMin: durationMin ?? this.durationMin,
        commissionPct: commissionPct ?? this.commissionPct,
        isActive: isActive ?? this.isActive,
        sortOrder: sortOrder ?? this.sortOrder,
        prices: prices ?? this.prices,
        staffIds: staffIds ?? this.staffIds,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'business_id': businessId,
        'name': name,
        'price': price,
        'duration_min': durationMin,
        'commission_pct': commissionPct,
        'is_active': isActive ? 1 : 0,
        'sort_order': sortOrder,
        'prices': jsonEncode(prices),
        'staff_ids': jsonEncode(staffIds),
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  factory ShopService.fromMap(Map<String, dynamic> m) => ShopService(
        id: m['id'] as String,
        businessId: m['business_id'] as String,
        name: m['name'] as String,
        price: (m['price'] as num?)?.toDouble() ?? 0,
        durationMin: (m['duration_min'] as num?)?.toInt(),
        commissionPct: (m['commission_pct'] as num?)?.toDouble() ?? 0,
        isActive: m['is_active'] == true || m['is_active'] == 1,
        sortOrder: (m['sort_order'] as num?)?.toInt() ?? 0,
        prices: {
          for (final e in Map<String, dynamic>.from(decodeJson(m['prices'], const {}) as Map).entries)
            if (e.value is num) e.key: (e.value as num).toDouble(),
        },
        staffIds: [for (final id in decodeJson(m['staff_ids'], const []) as List) id.toString()],
        createdAt: DateTime.tryParse(m['created_at'] as String? ?? '') ?? DateTime.now(),
        updatedAt: DateTime.tryParse(m['updated_at'] as String? ?? '') ?? DateTime.now(),
      );
}

/// JSON guardado como texto (en el equipo) o ya decodificado (de la nube)
dynamic decodeJson(Object? raw, Object fallback) {
  if (raw == null) return fallback;
  if (raw is String) {
    if (raw.trim().isEmpty) return fallback;
    try {
      return jsonDecode(raw);
    } catch (_) {
      return fallback;
    }
  }
  return raw;
}

/// Empleado: una persona que hace los servicios. No necesita cuenta en la app.
class StaffMember {
  final String id;
  final String businessId;
  final String name;
  final String? phone;
  final String? document;

  /// % propio que reemplaza el del servicio (null = se usa el del servicio)
  final double? commissionPct;
  final bool isActive;

  /// Cuenta del equipo vinculada (opcional, para que vea sus comisiones)
  final String? memberEmail;

  /// Horario propio (JSON de [WorkSchedule]); null = usa el del negocio
  final String? schedule;
  final DateTime createdAt;
  final DateTime updatedAt;

  const StaffMember({
    required this.id,
    required this.businessId,
    required this.name,
    this.phone,
    this.document,
    this.commissionPct,
    this.isActive = true,
    this.memberEmail,
    this.schedule,
    required this.createdAt,
    required this.updatedAt,
  });

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    return (parts.first[0] + (parts.length > 1 ? parts[1][0] : '')).toUpperCase();
  }

  StaffMember copyWith({
    String? name,
    String? phone,
    String? document,
    double? commissionPct,
    bool clearCommission = false,
    bool? isActive,
    DateTime? updatedAt,
    String? schedule,
    bool clearSchedule = false,
  }) =>
      StaffMember(
        id: id,
        businessId: businessId,
        name: name ?? this.name,
        phone: phone ?? this.phone,
        document: document ?? this.document,
        commissionPct: clearCommission ? null : (commissionPct ?? this.commissionPct),
        isActive: isActive ?? this.isActive,
        memberEmail: memberEmail,
        schedule: clearSchedule ? null : (schedule ?? this.schedule),
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'business_id': businessId,
        'name': name,
        'phone': phone,
        'document': document,
        'commission_pct': commissionPct,
        'is_active': isActive ? 1 : 0,
        'member_email': memberEmail,
        'schedule': schedule,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  factory StaffMember.fromMap(Map<String, dynamic> m) => StaffMember(
        id: m['id'] as String,
        businessId: m['business_id'] as String,
        name: m['name'] as String,
        phone: m['phone'] as String?,
        document: m['document'] as String?,
        commissionPct: (m['commission_pct'] as num?)?.toDouble(),
        isActive: m['is_active'] == true || m['is_active'] == 1,
        memberEmail: m['member_email'] as String?,
        schedule: m['schedule'] as String?,
        createdAt: DateTime.tryParse(m['created_at'] as String? ?? '') ?? DateTime.now(),
        updatedAt: DateTime.tryParse(m['updated_at'] as String? ?? '') ?? DateTime.now(),
      );
}

/// Un servicio dentro de una orden, con quién lo hace y en qué va.
/// Cada servicio avanza por separado: Pendiente → En proceso → Terminado.
class WorkOrderLine {
  static const pending = 'PENDIENTE';
  static const inProgress = 'PROCESO';
  static const done = 'TERMINADO';

  final String serviceId;
  final String name;
  final double price;
  final double commissionPct;
  final List<String> staffIds;
  final String status;
  final DateTime? startedAt;
  final DateTime? finishedAt;

  const WorkOrderLine({
    required this.serviceId,
    required this.name,
    required this.price,
    this.commissionPct = 0,
    this.staffIds = const [],
    this.status = pending,
    this.startedAt,
    this.finishedAt,
  });

  bool get isPending => status == pending;
  bool get isInProgress => status == inProgress;
  bool get isDone => status == done;

  WorkOrderLine copyWith({
    double? price,
    List<String>? staffIds,
    String? status,
    DateTime? startedAt,
    DateTime? finishedAt,
    bool clearTimes = false,
  }) =>
      WorkOrderLine(
        serviceId: serviceId,
        name: name,
        price: price ?? this.price,
        commissionPct: commissionPct,
        staffIds: staffIds ?? this.staffIds,
        status: status ?? this.status,
        startedAt: clearTimes ? null : (startedAt ?? this.startedAt),
        finishedAt: clearTimes ? null : (finishedAt ?? this.finishedAt),
      );

  Map<String, dynamic> toJson() => {
        'service_id': serviceId,
        'name': name,
        'price': price,
        'commission_pct': commissionPct,
        'staff_ids': staffIds,
        'status': status,
        if (startedAt != null) 'started_at': startedAt!.toIso8601String(),
        if (finishedAt != null) 'finished_at': finishedAt!.toIso8601String(),
      };

  /// [orderStatus] completa el estado de las líneas de la 0.11.0, que no lo guardaban
  factory WorkOrderLine.fromJson(Map<String, dynamic> j, {String? orderStatus}) => WorkOrderLine(
        serviceId: j['service_id'] as String? ?? '',
        name: j['name'] as String? ?? 'Servicio',
        price: (j['price'] as num?)?.toDouble() ?? 0,
        commissionPct: (j['commission_pct'] as num?)?.toDouble() ?? 0,
        staffIds: [for (final s in (j['staff_ids'] as List? ?? const [])) s as String],
        status: j['status'] as String? ??
            switch (orderStatus) {
              WorkOrder.ready || WorkOrder.delivered => done,
              WorkOrder.inProgress => inProgress,
              _ => pending,
            },
        startedAt: DateTime.tryParse('${j['started_at']}'),
        finishedAt: DateTime.tryParse('${j['finished_at']}'),
      );
}

/// Orden del tablero: una moto en el lavadero, un cliente en la barbería...
class WorkOrder {
  static const waiting = 'ESPERA';
  static const inProgress = 'PROCESO';
  static const ready = 'LISTA';
  static const delivered = 'ENTREGADA';
  static const cancelled = 'CANCELADA';

  /// Columnas del tablero, en orden
  static const flow = [waiting, inProgress, ready, delivered];

  final String id;
  final String businessId;

  /// Número corto para llamar la orden ("A3F2")
  final String number;
  final String? plate;
  final String? vehicle;

  /// Tipo de vehículo del lavadero (MOTO, CARRO, CAMIONETA); define los precios
  final String? vehicleKind;
  final String? customerName;
  final String? customerPhone;
  final String status;
  final List<WorkOrderLine> lines;
  final String? notes;

  /// Hora en que entró a cada estado
  final Map<String, DateTime> statusTimes;
  final double total;
  final double discount;
  final double tip;
  final String? paymentMethod;
  final List<String> saleIds;
  final String? createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  const WorkOrder({
    required this.id,
    required this.businessId,
    required this.number,
    this.plate,
    this.vehicle,
    this.vehicleKind,
    this.customerName,
    this.customerPhone,
    this.status = waiting,
    required this.lines,
    this.notes,
    this.statusTimes = const {},
    this.total = 0,
    this.discount = 0,
    this.tip = 0,
    this.paymentMethod,
    this.saleIds = const [],
    this.createdBy,
    required this.createdAt,
    required this.updatedAt,
  });

  double get subtotal => lines.fold(0.0, (s, l) => s + l.price);
  bool get isPaid => saleIds.isNotEmpty;
  bool get isOpen => status != delivered && status != cancelled;

  /// Todos los empleados que trabajan en la orden
  Set<String> get staffIds => {for (final l in lines) ...l.staffIds};

  /// Todos sus servicios están terminados
  bool get allDone => lines.isNotEmpty && lines.every((l) => l.isDone);

  /// Algunos servicios terminados y otros esperando, sin ninguno en proceso
  bool get isPartial =>
      status == waiting && lines.any((l) => l.isDone) && lines.any((l) => l.isPending) && !lines.any((l) => l.isInProgress);

  /// Estado que corresponde según sus servicios (las órdenes entregadas o canceladas no cambian)
  String get derivedStatus {
    if (status == delivered || status == cancelled) return status;
    if (lines.any((l) => l.isInProgress)) return inProgress;
    if (allDone) return ready;
    return waiting;
  }

  /// Desde cuándo está en el estado actual
  DateTime get since => statusTimes[status] ?? createdAt;

  /// Siguiente columna del tablero (null si ya se entregó o se canceló)
  String? get nextStatus {
    final i = flow.indexOf(status);
    return i < 0 || i >= flow.length - 1 ? null : flow[i + 1];
  }

  /// Nombre del estado con las palabras de la plantilla del negocio
  String statusLabelFor(ServiceTemplate t) => switch (status) {
        waiting => isPartial ? t.partialLabel : t.waitingLabel,
        inProgress => t.inProgress,
        ready => t.readyLabel,
        delivered => t.deliveredLabel,
        cancelled => t.feminine ? 'Cancelada' : 'Cancelado',
        _ => status,
      };

  /// Placa limpia: mayúsculas, sin espacios ni guiones ("abc-12d" -> "ABC12D")
  static String normalizePlate(String raw) => raw.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

  /// Cómo se llama la orden en pantalla: placa, cliente o número
  String get title => (plate ?? '').isNotEmpty ? plate! : ((customerName ?? '').isNotEmpty ? customerName! : '#$number');

  WorkOrder copyWith({
    String? plate,
    String? vehicle,
    String? vehicleKind,
    String? customerName,
    String? customerPhone,
    String? status,
    List<WorkOrderLine>? lines,
    String? notes,
    Map<String, DateTime>? statusTimes,
    double? total,
    double? discount,
    double? tip,
    String? paymentMethod,
    List<String>? saleIds,
    DateTime? updatedAt,
  }) =>
      WorkOrder(
        id: id,
        businessId: businessId,
        number: number,
        plate: plate ?? this.plate,
        vehicle: vehicle ?? this.vehicle,
        vehicleKind: vehicleKind ?? this.vehicleKind,
        customerName: customerName ?? this.customerName,
        customerPhone: customerPhone ?? this.customerPhone,
        status: status ?? this.status,
        lines: lines ?? this.lines,
        notes: notes ?? this.notes,
        statusTimes: statusTimes ?? this.statusTimes,
        total: total ?? this.total,
        discount: discount ?? this.discount,
        tip: tip ?? this.tip,
        paymentMethod: paymentMethod ?? this.paymentMethod,
        saleIds: saleIds ?? this.saleIds,
        createdBy: createdBy,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'business_id': businessId,
        'number': number,
        'plate': plate,
        'vehicle': vehicle,
        'vehicle_kind': vehicleKind,
        'customer_name': customerName,
        'customer_phone': customerPhone,
        'status': status,
        'lines': jsonEncode([for (final l in lines) l.toJson()]),
        'notes': notes,
        'status_times': jsonEncode({for (final e in statusTimes.entries) e.key: e.value.toIso8601String()}),
        'total': total,
        'discount': discount,
        'tip': tip,
        'payment_method': paymentMethod,
        'sale_ids': jsonEncode(saleIds),
        'created_by': createdBy,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  static dynamic _json(Object? raw, Object fallback) {
    if (raw == null) return fallback;
    if (raw is String) {
      try {
        return jsonDecode(raw);
      } catch (_) {
        return fallback;
      }
    }
    return raw;
  }

  factory WorkOrder.fromMap(Map<String, dynamic> m) {
    final lines = _json(m['lines'], const []) as List;
    final status = m['status'] as String? ?? waiting;
    final times = Map<String, dynamic>.from(_json(m['status_times'], const {}) as Map);
    final sales = _json(m['sale_ids'], const []) as List;
    return WorkOrder(
      id: m['id'] as String,
      businessId: m['business_id'] as String,
      number: m['number'] as String? ?? '',
      plate: m['plate'] as String?,
      vehicle: m['vehicle'] as String?,
      vehicleKind: m['vehicle_kind'] as String?,
      customerName: m['customer_name'] as String?,
      customerPhone: m['customer_phone'] as String?,
      status: status,
      lines: [for (final l in lines) WorkOrderLine.fromJson(Map<String, dynamic>.from(l as Map), orderStatus: status)],
      notes: m['notes'] as String?,
      statusTimes: {
        for (final e in times.entries)
          if (DateTime.tryParse(e.value.toString()) != null) e.key: DateTime.parse(e.value.toString()),
      },
      total: (m['total'] as num?)?.toDouble() ?? 0,
      discount: (m['discount'] as num?)?.toDouble() ?? 0,
      tip: (m['tip'] as num?)?.toDouble() ?? 0,
      paymentMethod: m['payment_method'] as String?,
      saleIds: [for (final s in sales) s.toString()],
      createdBy: m['created_by'] as String?,
      createdAt: DateTime.tryParse(m['created_at'] as String? ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(m['updated_at'] as String? ?? '') ?? DateTime.now(),
    );
  }
}


/// Asistencia de un empleado en un día: llegó o no vino, salida y pausas
class StaffAttendance {
  static const arrived = 'LLEGO';
  static const absent = 'NO_VINO';

  final String id;
  final String businessId;
  final String staffId;

  /// Día en formato AAAA-MM-DD (hora del equipo)
  final String day;
  final String status;
  final DateTime? arrivedAt;
  final DateTime? leftAt;

  /// Pausas del día; la última sin fin es una pausa en curso
  final List<(DateTime, DateTime?)> pauses;
  final DateTime updatedAt;

  const StaffAttendance({
    required this.id,
    required this.businessId,
    required this.staffId,
    required this.day,
    required this.status,
    this.arrivedAt,
    this.leftAt,
    this.pauses = const [],
    required this.updatedAt,
  });

  static String dayOf(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  bool get isAbsent => status == absent;
  bool get hasLeft => leftAt != null;
  bool get onPause => pauses.isNotEmpty && pauses.last.$2 == null;

  /// Puede recibir trabajo: llegó, no ha salido y no está en pausa
  bool get canWork => status == arrived && !hasLeft && !onPause;

  StaffAttendance copyWith({
    String? status,
    DateTime? arrivedAt,
    DateTime? leftAt,
    bool clearLeft = false,
    List<(DateTime, DateTime?)>? pauses,
    DateTime? updatedAt,
  }) =>
      StaffAttendance(
        id: id,
        businessId: businessId,
        staffId: staffId,
        day: day,
        status: status ?? this.status,
        arrivedAt: arrivedAt ?? this.arrivedAt,
        leftAt: clearLeft ? null : (leftAt ?? this.leftAt),
        pauses: pauses ?? this.pauses,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'business_id': businessId,
        'staff_id': staffId,
        'day': day,
        'status': status,
        'arrived_at': arrivedAt?.toIso8601String(),
        'left_at': leftAt?.toIso8601String(),
        'pauses': jsonEncode([
          for (final (start, end) in pauses)
            {'start': start.toIso8601String(), if (end != null) 'end': end.toIso8601String()}
        ]),
        'updated_at': updatedAt.toIso8601String(),
      };

  factory StaffAttendance.fromMap(Map<String, dynamic> m) => StaffAttendance(
        id: m['id'] as String,
        businessId: m['business_id'] as String,
        staffId: m['staff_id'] as String,
        day: m['day'] as String,
        status: m['status'] as String? ?? arrived,
        arrivedAt: DateTime.tryParse('${m['arrived_at']}'),
        leftAt: DateTime.tryParse('${m['left_at']}'),
        pauses: [
          for (final p in decodeJson(m['pauses'], const []) as List)
            if (p is Map && DateTime.tryParse('${p['start']}') != null)
              (DateTime.parse('${p['start']}'), DateTime.tryParse('${p['end']}')),
        ],
        updatedAt: DateTime.tryParse('${m['updated_at']}') ?? DateTime.now(),
      );
}
