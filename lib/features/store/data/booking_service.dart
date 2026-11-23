import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';
import '../../services/models/work_schedule.dart';
import '../../../core/utils/business_clock.dart';

/// Un servicio que se puede reservar en línea
class BookableService {
  final String id;
  final String name;
  final double price;
  final int durationMin;

  const BookableService({required this.id, required this.name, required this.price, required this.durationMin});
}

/// Lo que ve el cliente para reservar (0.14.0): servicios, empleados, horario y lo ocupado
class PublicBooking {
  final List<BookableService> services;
  final List<({String id, String name})> staff;
  final WorkSchedule? schedule;
  final List<({String? staffId, DateTime start, DateTime end})> busy;

  /// Zona del negocio (0.16.9): las horas se muestran con la hora del negocio, no
  /// con la del celular de quien reserva. null = la del equipo (nube sin actualizar)
  final String? zone;

  const PublicBooking({required this.services, required this.staff, this.schedule, this.busy = const [], this.zone});

  /// Ahora, con la hora del negocio
  DateTime get now => BusinessClock.wallOf(DateTime.now(), zone: zone);

  /// Una hora del negocio → la hora real, para guardar la cita
  DateTime instantOf(DateTime wall) => BusinessClock.instantOf(wall, zone: zone);

  factory PublicBooking.fromJson(Map<String, dynamic> j) {
    final zone = j['time_zone'] as String?;
    return PublicBooking(
        zone: zone,
        services: [
          for (final s in (j['services'] as List? ?? const []))
            BookableService(
              id: s['id'] as String,
              name: s['name'] as String? ?? '',
              price: (s['price'] as num?)?.toDouble() ?? 0,
              durationMin: (s['duration_min'] as num?)?.toInt() ?? 30,
            ),
        ],
        staff: [for (final s in (j['staff'] as List? ?? const [])) (id: s['id'] as String, name: s['name'] as String? ?? '')],
        schedule: WorkSchedule.decode(j['schedule'] as String?),
        busy: [
          for (final b in (j['busy'] as List? ?? const []))
            (
              staffId: b['staff_id'] as String?,
              start: BusinessClock.wallOf(DateTime.parse(b['starts_at'] as String), zone: zone),
              end: BusinessClock.wallOf(DateTime.parse(b['ends_at'] as String), zone: zone),
            ),
        ],
      );
  }

  /// Horas libres de un día, cada [step] minutos, para [minutes] de servicio con
  /// [staffId] (null = con cualquiera: libre si alguien está libre). Sin horario del
  /// negocio se usa de 8:00 a. m. a 6:00 p. m.
  List<DateTime> freeSlots(DateTime day, int minutes, {String? staffId, DateTime? now, int step = 30}) {
    final at = now ?? this.now;
    final shift = schedule == null || schedule!.isEmpty ? const ShiftTime(480, 1080) : schedule!.on(day);
    if (shift == null) return const [];
    final people = staffId != null ? [staffId] : (staff.isEmpty ? <String?>[null] : [for (final s in staff) s.id]);
    final slots = <DateTime>[];
    for (var m = shift.start; m + minutes <= shift.end; m += step) {
      final start = DateTime(day.year, day.month, day.day, m ~/ 60, m % 60);
      if (!start.isAfter(at.add(const Duration(minutes: 30)))) continue;
      final end = start.add(Duration(minutes: minutes));
      bool freeFor(String? who) => !busy.any((b) =>
          (who == null || b.staffId == null || b.staffId == who) && b.start.isBefore(end) && start.isBefore(b.end));
      if (people.any(freeFor)) slots.add(start);
    }
    return slots;
  }
}

class BookingException implements Exception {
  final String message;
  const BookingException(this.message);
  @override
  String toString() => message;
}

/// Reservas en línea desde la tienda (Pro Servicios)
class BookingService {
  BookingService._();
  static final BookingService instance = BookingService._();

  SupabaseClient? get _client => SupabaseService.instance.client;

  /// null si el negocio no recibe reservas (sin Pro Servicios o tienda apagada)
  Future<PublicBooking?> get(String slug, {required DateTime from, required DateTime to}) async {
    final client = _client;
    if (client == null) return null;
    try {
      final data = await client.rpc('get_public_booking', params: {
        'p_slug': slug,
        'p_from': from.toUtc().toIso8601String(),
        'p_to': to.toUtc().toIso8601String(),
      });
      return data == null ? null : PublicBooking.fromJson(Map<String, dynamic>.from(data as Map));
    } catch (e) {
      debugPrint('Reservas: $e');
      return null;
    }
  }

  Future<void> create({
    required String slug,
    required String name,
    required String phone,
    required List<String> serviceIds,
    String? staffId,
    required DateTime startsAt,
    String? note,
  }) async {
    final client = _client;
    if (client == null) throw const BookingException('No hay conexión. Inténtalo de nuevo.');
    try {
      await client.rpc('create_booking', params: {
        'p_slug': slug,
        'p_customer_name': name.trim(),
        'p_customer_phone': phone.trim(),
        'p_service_ids': serviceIds,
        'p_staff_id': staffId,
        'p_starts_at': startsAt.toUtc().toIso8601String(),
        'p_note': note?.trim(),
      });
    } on PostgrestException catch (e) {
      final m = e.message;
      throw BookingException(switch (m) {
        _ when m.contains('slot_taken') => 'Esa hora se acaba de ocupar. Elige otra.',
        _ when m.contains('past_time') => 'Esa hora ya pasó. Elige otra.',
        _ when m.contains('phone_required') => 'Escribe tu celular para confirmarte la cita.',
        _ when m.contains('name_required') => 'Escribe tu nombre.',
        _ => 'No se pudo pedir la cita. Inténtalo de nuevo.',
      });
    }
  }
}
