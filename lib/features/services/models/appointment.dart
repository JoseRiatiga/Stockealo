import '../../../core/utils/business_clock.dart';
import 'dart:convert';

/// Una cita de la agenda (0.14.0): para barberías, peluquerías, spa y cualquier
/// negocio de servicios. Puede venir del local o de una reserva en línea.
/// Cuando el cliente llega, la cita pasa al tablero como orden de trabajo.
class Appointment {
  /// Reserva en línea que el negocio todavía no confirma
  static const pending = 'PENDIENTE';
  static const confirmed = 'CONFIRMADA';

  /// Llegó: ya es una orden en el tablero ([workOrderId])
  static const arrived = 'LLEGO';
  static const noShow = 'NO_VINO';
  static const cancelled = 'CANCELADA';

  static const sourceLocal = 'LOCAL';
  static const sourceOnline = 'TIENDA';

  final String id;
  final String businessId;
  final String customerName;
  final String? customerPhone;
  final List<String> serviceIds;

  /// Nombres de los servicios (para mostrar sin buscarlos)
  final String serviceNames;

  /// Quién la atiende; null = cualquiera
  final String? staffId;
  final DateTime startsAt;
  final int durationMin;
  final String status;
  final String source;
  final String? notes;
  final String? workOrderId;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Appointment({
    required this.id,
    required this.businessId,
    required this.customerName,
    this.customerPhone,
    this.serviceIds = const [],
    this.serviceNames = '',
    this.staffId,
    required this.startsAt,
    this.durationMin = 30,
    this.status = confirmed,
    this.source = sourceLocal,
    this.notes,
    this.workOrderId,
    required this.createdAt,
    required this.updatedAt,
  });

  DateTime get endsAt => startsAt.add(Duration(minutes: durationMin));

  /// Sigue en la agenda (no llegó, no se canceló, no faltó)
  bool get isOpen => status == pending || status == confirmed;

  /// Se cruza con otra cita del mismo empleado
  bool overlaps(Appointment other) =>
      other.id != id &&
      other.isOpen &&
      staffId != null &&
      other.staffId == staffId &&
      startsAt.isBefore(other.endsAt) &&
      other.startsAt.isBefore(endsAt);

  String get statusLabel => switch (status) {
        pending => 'Por confirmar',
        confirmed => 'Confirmada',
        arrived => 'Llegó',
        noShow => 'No vino',
        cancelled => 'Cancelada',
        _ => status,
      };

  Appointment copyWith({String? status, String? workOrderId, DateTime? startsAt, DateTime? updatedAt}) => Appointment(
        id: id,
        businessId: businessId,
        customerName: customerName,
        customerPhone: customerPhone,
        serviceIds: serviceIds,
        serviceNames: serviceNames,
        staffId: staffId,
        startsAt: startsAt ?? this.startsAt,
        durationMin: durationMin,
        status: status ?? this.status,
        source: source,
        notes: notes,
        workOrderId: workOrderId ?? this.workOrderId,
        createdAt: createdAt,
        updatedAt: updatedAt ?? DateTime.now(),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'business_id': businessId,
        'customer_name': customerName,
        'customer_phone': customerPhone,
        'service_ids': jsonEncode(serviceIds),
        'service_names': serviceNames,
        'staff_id': staffId,
        // La hora real de la cita, con la zona del negocio (0.16.9): no la del equipo
        'starts_at': BusinessClock.instantOf(startsAt).toIso8601String(),
        'duration_min': durationMin,
        'status': status,
        'source': source,
        'notes': notes,
        'work_order_id': workOrderId,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  factory Appointment.fromMap(Map<String, dynamic> m) {
    List<String> ids;
    try {
      final raw = m['service_ids'];
      ids = [for (final v in (raw is String ? jsonDecode(raw) : (raw ?? const [])) as List) '$v'];
    } catch (_) {
      ids = const [];
    }
    DateTime when(Object? v) => (DateTime.tryParse('${v ?? ''}') ?? DateTime.now()).toLocal();
    return Appointment(
      id: m['id'] as String,
      businessId: m['business_id'] as String,
      customerName: m['customer_name'] as String? ?? 'Cliente',
      customerPhone: m['customer_phone'] as String?,
      serviceIds: ids,
      serviceNames: m['service_names'] as String? ?? '',
      staffId: m['staff_id'] as String?,
      startsAt: BusinessClock.wallOf(DateTime.tryParse('${m['starts_at'] ?? ''}') ?? DateTime.now()),
      durationMin: (m['duration_min'] as num?)?.toInt() ?? 30,
      status: m['status'] as String? ?? confirmed,
      source: m['source'] as String? ?? sourceLocal,
      notes: m['notes'] as String?,
      workOrderId: m['work_order_id'] as String?,
      createdAt: when(m['created_at']),
      updatedAt: when(m['updated_at']),
    );
  }
}
