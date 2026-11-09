import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/services/supabase_service.dart';
import '../../auth/data/auth_repository.dart';
import '../../team/data/activity_repository.dart';
import '../models/service_models.dart';

/// Catálogo de servicios, empleados y tablero de órdenes. Todo se guarda primero
/// en el equipo y sube a la nube con la cola, como el resto de la app.
class ServicesRepository {
  ServicesRepository._();
  static final ServicesRepository instance = ServicesRepository._();

  /// Sin Stockealo Pro se pueden tener hasta estos empleados activos
  static const freeStaffLimit = 2;

  final AppDatabase _dbProvider = AppDatabase.instance;
  final _cloud = SupabaseService.instance;

  // ---------------------------------------------------------------------------
  // Catálogo de servicios
  // ---------------------------------------------------------------------------

  Future<List<ShopService>> getServices(String businessId, {bool includeInactive = false}) async {
    final db = await _dbProvider.database;
    final rows = await db.query(
      'services',
      where: includeInactive ? 'business_id = ?' : 'business_id = ? AND is_active = 1',
      whereArgs: [businessId],
      orderBy: 'is_active DESC, sort_order ASC, name COLLATE NOCASE ASC',
    );
    return rows.map(ShopService.fromMap).toList();
  }

  ShopService newService(String businessId, {String name = '', double price = 0, int? durationMin, double commissionPct = 0}) {
    final now = DateTime.now();
    return ShopService(
      id: const Uuid().v4(),
      businessId: businessId,
      name: name,
      price: price,
      durationMin: durationMin,
      commissionPct: commissionPct,
      createdAt: now,
      updatedAt: now,
    );
  }

  Future<void> saveService(ShopService service) async {
    final db = await _dbProvider.database;
    final row = service.copyWith(updatedAt: DateTime.now()).toMap();
    final updated = await db.update('services', row, where: 'id = ?', whereArgs: [service.id]);
    if (updated == 0) await db.insert('services', row);
    _cloud.upsertServiceToCloud(row);
  }

  /// Servicios de ejemplo del tipo de negocio, solo si el catálogo está vacío
  Future<int> seedExamples(String businessId, ServiceType type) async {
    if ((await getServices(businessId, includeInactive: true)).isNotEmpty) return 0;
    var order = 0;
    for (final (name, price, minutes, pct) in type.examples) {
      await saveService(newService(businessId, name: name, price: price, durationMin: minutes, commissionPct: pct)
          .copyWith(sortOrder: order++));
    }
    return type.examples.length;
  }

  // ---------------------------------------------------------------------------
  // Empleados
  // ---------------------------------------------------------------------------

  Future<List<StaffMember>> getStaff(String businessId, {bool includeInactive = false}) async {
    final db = await _dbProvider.database;
    final rows = await db.query(
      'staff',
      where: includeInactive ? 'business_id = ?' : 'business_id = ? AND is_active = 1',
      whereArgs: [businessId],
      orderBy: 'is_active DESC, name COLLATE NOCASE ASC',
    );
    return rows.map(StaffMember.fromMap).toList();
  }

  StaffMember newStaff(String businessId, String name) {
    final now = DateTime.now();
    return StaffMember(id: const Uuid().v4(), businessId: businessId, name: name.trim(), createdAt: now, updatedAt: now);
  }

  /// Sin Pro solo caben [freeStaffLimit] empleados activos
  Future<bool> canActivateStaff(String businessId, {required bool hasPro, String? exceptId}) async {
    if (hasPro) return true;
    final active = (await getStaff(businessId)).where((s) => s.id != exceptId).length;
    return active < freeStaffLimit;
  }

  Future<void> saveStaff(StaffMember staff) async {
    final db = await _dbProvider.database;
    final row = staff.copyWith(updatedAt: DateTime.now()).toMap();
    final updated = await db.update('staff', row, where: 'id = ?', whereArgs: [staff.id]);
    if (updated == 0) await db.insert('staff', row);
    _cloud.upsertStaffToCloud(row);
    ActivityRepository.instance.log(
      businessId: staff.businessId,
      action: ActivityAction.staffChange,
      summary: updated == 0
          ? 'Agregó al empleado ${staff.name}'
          : (staff.isActive ? 'Editó al empleado ${staff.name}' : 'Desactivó al empleado ${staff.name}'),
      data: {'staff_id': staff.id},
    );
  }

  // ---------------------------------------------------------------------------
  // Tablero de órdenes
  // ---------------------------------------------------------------------------

  /// Órdenes abiertas y las que se entregaron o cancelaron hoy
  Future<List<WorkOrder>> getBoard(String businessId, {DateTime? now}) async {
    final db = await _dbProvider.database;
    final today = now ?? DateTime.now();
    final start = DateTime(today.year, today.month, today.day).toIso8601String();
    final rows = await db.query(
      'work_orders',
      where: "business_id = ? AND (status NOT IN ('${WorkOrder.delivered}', '${WorkOrder.cancelled}') OR updated_at >= ?)",
      whereArgs: [businessId, start],
      orderBy: 'created_at ASC',
    );
    return rows.map(WorkOrder.fromMap).toList();
  }

  Future<WorkOrder?> getOrder(String id) async {
    final db = await _dbProvider.database;
    final rows = await db.query('work_orders', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : WorkOrder.fromMap(rows.first);
  }

  /// Historial de una placa, la visita más nueva primero
  Future<List<WorkOrder>> ordersByPlate(String businessId, String plate) async {
    final clean = WorkOrder.normalizePlate(plate);
    if (clean.isEmpty) return const [];
    final db = await _dbProvider.database;
    final rows = await db.query(
      'work_orders',
      where: 'business_id = ? AND plate = ?',
      whereArgs: [businessId, clean],
      orderBy: 'created_at DESC',
    );
    return rows.map(WorkOrder.fromMap).toList();
  }

  /// Placas que empiezan por [prefix] (para autocompletar), con su última visita
  Future<List<WorkOrder>> platesStartingWith(String businessId, String prefix) async {
    final clean = WorkOrder.normalizePlate(prefix);
    if (clean.length < 2) return const [];
    final db = await _dbProvider.database;
    final rows = await db.query(
      'work_orders',
      where: 'business_id = ? AND plate LIKE ?',
      whereArgs: [businessId, '$clean%'],
      orderBy: 'created_at DESC',
      limit: 40,
    );
    final seen = <String>{};
    return [
      for (final r in rows.map(WorkOrder.fromMap))
        if (seen.add(r.plate ?? '')) r,
    ].take(6).toList();
  }

  /// Número del día: la primera orden de hoy es la 1
  Future<String> _nextNumber(String businessId, DateTime now) async {
    final db = await _dbProvider.database;
    final start = DateTime(now.year, now.month, now.day).toIso8601String();
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS n FROM work_orders WHERE business_id = ? AND created_at >= ?',
      [businessId, start],
    );
    return '${((rows.first['n'] as num?)?.toInt() ?? 0) + 1}';
  }

  Future<WorkOrder> createOrder({
    required String businessId,
    required List<WorkOrderLine> lines,
    String? plate,
    String? vehicle,
    String? customerName,
    String? customerPhone,
    String? notes,
    DateTime? now,
  }) async {
    final at = now ?? DateTime.now();
    final cleanPlate = plate == null ? null : WorkOrder.normalizePlate(plate);
    final order = WorkOrder(
      id: const Uuid().v4(),
      businessId: businessId,
      number: await _nextNumber(businessId, at),
      plate: (cleanPlate ?? '').isEmpty ? null : cleanPlate,
      vehicle: _clean(vehicle),
      customerName: _clean(customerName),
      customerPhone: _clean(customerPhone),
      lines: lines,
      notes: _clean(notes),
      statusTimes: {WorkOrder.waiting: at},
      total: lines.fold(0.0, (s, l) => s + l.price),
      createdBy: AuthRepository.instance.currentUser?.email,
      createdAt: at,
      updatedAt: at,
    );
    await _store(order, insert: true);
    return order;
  }

  static String? _clean(String? v) => (v ?? '').trim().isEmpty ? null : v!.trim();

  Future<void> _store(WorkOrder order, {bool insert = false}) async {
    final db = await _dbProvider.database;
    final row = order.toMap();
    if (insert) {
      await db.insert('work_orders', row);
    } else {
      await db.update('work_orders', row, where: 'id = ?', whereArgs: [order.id]);
    }
    _cloud.upsertWorkOrderToCloud(row);
  }

  /// Guarda cambios de la orden (servicios, empleados, datos del cliente)
  Future<WorkOrder> updateOrder(WorkOrder order) async {
    final updated = order.copyWith(
      total: order.lines.fold<double>(0, (s, l) => s + l.price),
      updatedAt: DateTime.now(),
    );
    await _store(updated);
    return updated;
  }

  /// Pasa la orden a otra columna y anota la hora
  Future<WorkOrder> moveTo(WorkOrder order, String status, {DateTime? now}) async {
    final at = now ?? DateTime.now();
    final updated = order.copyWith(
      status: status,
      statusTimes: {...order.statusTimes, status: at},
      updatedAt: at,
    );
    await _store(updated);
    return updated;
  }

  /// Cancelar no cobra nada; una orden ya cobrada no se cancela (se anula la venta)
  Future<WorkOrder> cancel(WorkOrder order) async {
    if (order.isPaid) throw StateError('La orden ya se cobró: anula la venta en Ventas.');
    return moveTo(order, WorkOrder.cancelled);
  }

  /// Después de cobrar: guarda la venta, el descuento y la propina, y la entrega
  Future<WorkOrder> markPaid(
    WorkOrder order, {
    required List<String> saleIds,
    required String paymentMethod,
    required double total,
    double discount = 0,
    double tip = 0,
    DateTime? now,
  }) async {
    final at = now ?? DateTime.now();
    final updated = order.copyWith(
      saleIds: saleIds,
      paymentMethod: paymentMethod,
      total: total,
      discount: discount,
      tip: tip,
      status: WorkOrder.delivered,
      statusTimes: {...order.statusTimes, WorkOrder.delivered: at},
      updatedAt: at,
    );
    await _store(updated);
    return updated;
  }
}
