import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/services/supabase_service.dart';
import '../models/appointment.dart';
import '../models/service_models.dart';
import 'services_repository.dart';
import '../../../core/utils/business_clock.dart';

/// La agenda de citas (0.14.0). Se guarda en el equipo y se sube a la nube
/// (tabla `appointments`). Cuando el cliente llega, la cita pasa al tablero.
class AppointmentsRepository {
  AppointmentsRepository._();
  static final AppointmentsRepository instance = AppointmentsRepository._();

  final _db = AppDatabase.instance;

  /// Quién avisa de una reserva nueva (la conecta la navegación de la app)
  static void Function(Appointment booking)? onNewBooking;

  /// Baja las reservas en línea nuevas y avisa de cada una. Sin conexión no hace nada.
  Future<int> pullOnline(String businessId) async {
    final client = SupabaseService.instance.client;
    if (client == null || client.auth.currentSession == null) return 0;
    try {
      final rows = await client
          .from('appointments')
          .select()
          .eq('business_id', businessId)
          .eq('source', Appointment.sourceOnline)
          .eq('status', Appointment.pending);
      final db = await _db.database;
      var added = 0;
      for (final raw in rows) {
        final a = Appointment.fromMap(Map<String, dynamic>.from(raw as Map));
        final exists = await db.query('appointments', columns: ['id'], where: 'id = ?', whereArgs: [a.id], limit: 1);
        if (exists.isNotEmpty) continue;
        await db.insert('appointments', a.toMap(), conflictAlgorithm: ConflictAlgorithm.ignore);
        onNewBooking?.call(a);
        added++;
      }
      return added;
    } catch (_) {
      return 0;
    }
  }

  Appointment newAppointment(String businessId, {required DateTime startsAt}) {
    final now = appNow();
    return Appointment(
      id: const Uuid().v4(),
      businessId: businessId,
      customerName: '',
      startsAt: startsAt,
      createdAt: now,
      updatedAt: now,
    );
  }

  /// Las citas de un día, por hora
  Future<List<Appointment>> forDay(String businessId, DateTime day) async {
    final db = await _db.database;
    final from = DateTime(day.year, day.month, day.day);
    final to = from.add(const Duration(days: 1));
    final rows = await db.query(
      'appointments',
      where: 'business_id = ? AND starts_at >= ? AND starts_at < ?',
      // El día del negocio, en hora real (0.16.9)
      whereArgs: [businessId, BusinessClock.instantOf(from).toIso8601String(), BusinessClock.instantOf(to).toIso8601String()],
      orderBy: 'starts_at ASC',
    );
    return [for (final r in rows) Appointment.fromMap(r)];
  }

  /// Reservas en línea que esperan que el negocio las confirme
  Future<int> pendingCount(String businessId) async {
    final db = await _db.database;
    return Sqflite.firstIntValue(await db.rawQuery(
          'SELECT COUNT(*) FROM appointments WHERE business_id = ? AND status = ? AND starts_at >= ?',
          [businessId, Appointment.pending, DateTime.now().toUtc().toIso8601String()],
        )) ??
        0;
  }

  /// Otra cita del mismo empleado que se cruza (para avisar antes de guardar)
  Future<Appointment?> conflictWith(Appointment a) async {
    for (final other in await forDay(a.businessId, a.startsAt)) {
      if (a.overlaps(other)) return other;
    }
    return null;
  }

  Future<void> save(Appointment a) async {
    final db = await _db.database;
    final row = a.copyWith(updatedAt: appNow()).toMap();
    await db.insert('appointments', row, conflictAlgorithm: ConflictAlgorithm.replace);
    await SupabaseService.instance.upsertAppointmentToCloud(row);
  }

  Future<Appointment> setStatus(Appointment a, String status) async {
    final updated = a.copyWith(status: status);
    await save(updated);
    return updated;
  }

  /// Llegó el cliente: la cita se vuelve una orden en el tablero, con sus servicios
  Future<WorkOrder> arrive(Appointment a, {DateTime? now}) async {
    final services = ServicesRepository.instance;
    final all = await services.getServices(a.businessId);
    final lines = [
      for (final id in a.serviceIds)
        for (final s in all.where((s) => s.id == id))
          WorkOrderLine(serviceId: s.id, name: s.name, price: s.priceFor(null) ?? s.price, commissionPct: s.commissionPct),
    ];
    if (lines.isEmpty) throw StateError('La cita no tiene servicios del catálogo. Agrégalos antes de pasarla al tablero.');
    final order = await services.createOrder(
      businessId: a.businessId,
      lines: lines,
      customerName: a.customerName,
      customerPhone: a.customerPhone,
      notes: 'Cita de las ${a.startsAt.hour}:${a.startsAt.minute.toString().padLeft(2, '0')}'
          '${(a.notes ?? '').isEmpty ? '' : ' · ${a.notes}'}',
      now: now,
    );
    await save(a.copyWith(status: Appointment.arrived, workOrderId: order.id));
    return order;
  }

  Future<void> delete(Appointment a) async {
    final db = await _db.database;
    await db.delete('appointments', where: 'id = ?', whereArgs: [a.id]);
    await SupabaseService.instance.deleteAppointmentFromCloud(a.id);
  }
}
