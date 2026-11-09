import 'dart:convert';

/// Tipo de negocio de servicios: cambia textos, ejemplos y si se pide la placa
enum ServiceType {
  lavaderoMotos('LAVADERO_MOTOS', 'Lavadero de motos', 'Moto', 'Lavando'),
  barberia('BARBERIA', 'Barbería / peluquería', 'Cliente', 'Atendiendo'),
  taller('TALLER', 'Taller', 'Vehículo', 'En reparación'),
  otro('OTRO', 'Otro', 'Orden', 'En proceso');

  final String code;
  final String label;

  /// Cómo se le dice a cada orden ("Moto", "Cliente"...)
  final String unit;

  /// Nombre del estado en proceso ("Lavando", "Atendiendo"...)
  final String inProgress;

  const ServiceType(this.code, this.label, this.unit, this.inProgress);

  /// Lavaderos y talleres trabajan por placa
  bool get usesPlate => this == lavaderoMotos || this == taller;

  static ServiceType of(String? code) =>
      ServiceType.values.firstWhere((t) => t.code == code, orElse: () => ServiceType.otro);

  /// Servicios de ejemplo al activar el módulo: (nombre, precio COP, minutos, % comisión)
  List<(String, double, int, double)> get examples => switch (this) {
        lavaderoMotos => const [
            ('Lavado sencillo', 10000, 20, 40),
            ('Lavado completo', 15000, 35, 40),
            ('Lavado y polichado', 25000, 50, 40),
            ('Desengrase de motor', 12000, 25, 40),
            ('Lavado de casco', 5000, 10, 40),
          ],
        barberia => const [
            ('Corte', 15000, 30, 50),
            ('Corte y barba', 22000, 45, 50),
            ('Barba', 10000, 20, 50),
          ],
        taller => const [
            ('Cambio de aceite', 15000, 30, 30),
            ('Revisión general', 30000, 60, 30),
          ],
        otro => const [],
      };
}

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
    required this.createdAt,
    required this.updatedAt,
  });

  ShopService copyWith({
    String? name,
    double? price,
    int? durationMin,
    double? commissionPct,
    bool? isActive,
    int? sortOrder,
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
        createdAt: DateTime.tryParse(m['created_at'] as String? ?? '') ?? DateTime.now(),
        updatedAt: DateTime.tryParse(m['updated_at'] as String? ?? '') ?? DateTime.now(),
      );
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
        createdAt: DateTime.tryParse(m['created_at'] as String? ?? '') ?? DateTime.now(),
        updatedAt: DateTime.tryParse(m['updated_at'] as String? ?? '') ?? DateTime.now(),
      );
}

/// Un servicio dentro de una orden, con quién lo hace
class WorkOrderLine {
  final String serviceId;
  final String name;
  final double price;
  final double commissionPct;
  final List<String> staffIds;

  const WorkOrderLine({
    required this.serviceId,
    required this.name,
    required this.price,
    this.commissionPct = 0,
    this.staffIds = const [],
  });

  WorkOrderLine copyWith({double? price, List<String>? staffIds}) => WorkOrderLine(
        serviceId: serviceId,
        name: name,
        price: price ?? this.price,
        commissionPct: commissionPct,
        staffIds: staffIds ?? this.staffIds,
      );

  Map<String, dynamic> toJson() => {
        'service_id': serviceId,
        'name': name,
        'price': price,
        'commission_pct': commissionPct,
        'staff_ids': staffIds,
      };

  factory WorkOrderLine.fromJson(Map<String, dynamic> j) => WorkOrderLine(
        serviceId: j['service_id'] as String? ?? '',
        name: j['name'] as String? ?? 'Servicio',
        price: (j['price'] as num?)?.toDouble() ?? 0,
        commissionPct: (j['commission_pct'] as num?)?.toDouble() ?? 0,
        staffIds: [for (final s in (j['staff_ids'] as List? ?? const [])) s as String],
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

  /// Desde cuándo está en el estado actual
  DateTime get since => statusTimes[status] ?? createdAt;

  /// Siguiente columna del tablero (null si ya se entregó o se canceló)
  String? get nextStatus {
    final i = flow.indexOf(status);
    return i < 0 || i >= flow.length - 1 ? null : flow[i + 1];
  }

  static String statusLabel(String status, ServiceType type) => switch (status) {
        waiting => 'En espera',
        inProgress => type.inProgress,
        ready => 'Lista',
        delivered => 'Entregada',
        cancelled => 'Cancelada',
        _ => status,
      };

  /// Placa limpia: mayúsculas, sin espacios ni guiones ("abc-12d" -> "ABC12D")
  static String normalizePlate(String raw) => raw.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

  /// Cómo se llama la orden en pantalla: placa, cliente o número
  String get title => (plate ?? '').isNotEmpty ? plate! : ((customerName ?? '').isNotEmpty ? customerName! : '#$number');

  WorkOrder copyWith({
    String? plate,
    String? vehicle,
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
    final times = Map<String, dynamic>.from(_json(m['status_times'], const {}) as Map);
    final sales = _json(m['sale_ids'], const []) as List;
    return WorkOrder(
      id: m['id'] as String,
      businessId: m['business_id'] as String,
      number: m['number'] as String? ?? '',
      plate: m['plate'] as String?,
      vehicle: m['vehicle'] as String?,
      customerName: m['customer_name'] as String?,
      customerPhone: m['customer_phone'] as String?,
      status: m['status'] as String? ?? waiting,
      lines: [for (final l in lines) WorkOrderLine.fromJson(Map<String, dynamic>.from(l as Map))],
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
