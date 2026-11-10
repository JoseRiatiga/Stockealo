import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/services/supabase_service.dart';
import '../../auth/data/auth_repository.dart';
import '../../business/data/business_repository.dart';
import '../../sales/data/sales_repository.dart';
import '../../team/data/activity_repository.dart';
import '../models/service_models.dart';
import 'commissions_repository.dart';
import 'service_board.dart';

/// Catálogo de servicios, empleados y tablero de órdenes. Todo se guarda primero
/// en el equipo y sube a la nube con la cola, como el resto de la app.
class ServicesRepository {
  ServicesRepository._();
  static final ServicesRepository instance = ServicesRepository._();

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

  /// Servicios de ejemplo de la plantilla, solo si el catálogo está vacío
  Future<int> seedTemplate(String businessId, ServiceTemplate template) async {
    if ((await getServices(businessId, includeInactive: true)).isNotEmpty) return 0;
    var order = 0;
    for (final e in template.examples) {
      // Con precios por vehículo, el precio base es el más bajo (el de la moto)
      final base = e.prices.isEmpty ? e.price : e.prices.values.reduce((a, b) => a < b ? a : b);
      await saveService(newService(businessId, name: e.name, price: base, durationMin: e.minutes, commissionPct: e.commissionPct)
          .copyWith(sortOrder: order++, prices: e.prices));
    }
    return template.examples.length;
  }

  /// Primera vez en Servicios: el negocio elige su tipo y recibe la plantilla
  Future<int> setupTemplate(String businessId, ServiceTemplate template) async {
    await BusinessRepository.instance.updateBusiness(
      id: businessId,
      servicesEnabled: true,
      serviceType: template.code,
    );
    return seedTemplate(businessId, template);
  }

  /// Los lavaderos de la 0.11.0 tenían un solo precio por servicio: pasa a ser el de la moto
  Future<void> migrateLegacyLavadero(String businessId, String? serviceType) async {
    if (serviceType != 'LAVADERO_MOTOS') return;
    for (final s in await getServices(businessId, includeInactive: true)) {
      if (s.prices.isEmpty) await saveService(s.copyWith(prices: {'MOTO': s.price}));
    }
    await BusinessRepository.instance.updateBusiness(id: businessId, serviceType: ServiceTemplate.lavadero.code);
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
    String? vehicleKind,
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
      vehicleKind: _clean(vehicleKind),
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

  // ---------------------------------------------------------------------------
  // Servicios dentro de cada trabajo (0.12.0)
  // ---------------------------------------------------------------------------

  /// Guarda la orden con el estado que corresponde a sus servicios y anota la hora del cambio
  Future<WorkOrder> _saveDerived(WorkOrder order, DateTime at, {String? note}) async {
    final next = order.derivedStatus;
    final notes = note == null || note.trim().isEmpty
        ? order.notes
        : [if ((order.notes ?? '').trim().isNotEmpty) order.notes!.trim(), note.trim()].join('\n');
    final updated = order.copyWith(
      status: next,
      statusTimes: next == order.status ? order.statusTimes : {...order.statusTimes, next: at},
      notes: notes,
      updatedAt: at,
    );
    await _store(updated);
    return updated;
  }

  /// Empieza un servicio con uno o varios empleados. Revisa las reglas: cada uno
  /// vino hoy, está libre y hace ese servicio. Lanza [StateError] con el motivo.
  Future<WorkOrder> startLine(
    WorkOrder order,
    int index,
    List<String> staffIds, {
    required ServiceBoard board,
    DateTime? now,
  }) async {
    if (staffIds.isEmpty) throw StateError('Elige quién hace el servicio.');
    for (final id in staffIds) {
      final why = board.whyNotStart(order, index, id);
      if (why != null) throw StateError(why);
    }
    final at = now ?? DateTime.now();
    final lines = [...order.lines];
    lines[index] = lines[index].copyWith(staffIds: staffIds, status: WorkOrderLine.inProgress, startedAt: at);
    return _saveDerived(order.copyWith(lines: lines), at);
  }

  /// Termina un servicio: quien lo hacía queda libre en ese momento
  Future<WorkOrder> finishLine(WorkOrder order, int index, {DateTime? now}) async {
    final line = order.lines[index];
    if (!line.isInProgress) throw StateError('Ese servicio no está en proceso.');
    final at = now ?? DateTime.now();
    final lines = [...order.lines];
    lines[index] = line.copyWith(status: WorkOrderLine.done, finishedAt: at);
    return _saveDerived(order.copyWith(lines: lines), at);
  }

  /// Retrocede un servicio un paso (Terminado → En proceso → Pendiente) con una nota.
  /// No se puede si el trabajo ya se cobró: primero hay que anular el cobro.
  Future<WorkOrder> revertLine(
    WorkOrder order,
    int index, {
    required ServiceBoard board,
    String? note,
    DateTime? now,
  }) async {
    if (order.isPaid) throw StateError('Ya se cobró: primero anula el cobro.');
    final line = order.lines[index];
    final at = now ?? DateTime.now();
    final lines = [...order.lines];
    final String step;
    if (line.isDone) {
      // Vuelve a quien lo hacía, si sigue libre
      for (final id in line.staffIds) {
        final busy = board.activeLineOf(id);
        if (busy != null) {
          throw StateError('${board.staffOf(id)?.name ?? 'Quien lo hizo'} ya está en otro servicio. '
              'Termínalo primero o retrocede este servicio hasta Pendiente.');
        }
      }
      lines[index] = WorkOrderLine(
        serviceId: line.serviceId,
        name: line.name,
        price: line.price,
        commissionPct: line.commissionPct,
        staffIds: line.staffIds,
        status: WorkOrderLine.inProgress,
        startedAt: line.startedAt ?? at,
      );
      step = 'de Terminado a En proceso';
    } else if (line.isInProgress) {
      lines[index] = line.copyWith(staffIds: const [], status: WorkOrderLine.pending, clearTimes: true);
      step = 'de En proceso a Pendiente';
    } else {
      throw StateError('Ese servicio todavía no ha empezado.');
    }
    final clean = (note ?? '').trim();
    final updated = await _saveDerived(
      order.copyWith(lines: lines),
      at,
      note: 'Se retrocedió ${line.name} $step${clean.isEmpty ? '' : ': $clean'}',
    );
    ActivityRepository.instance.log(
      businessId: order.businessId,
      action: 'service_revert',
      summary: 'Retrocedió ${line.name} de ${order.title} $step${clean.isEmpty ? '' : ' ($clean)'}',
      data: {'work_order_id': order.id},
    );
    return updated;
  }

  /// Anula el cobro de un trabajo (sus ventas y el fiado) y lo deja otra vez listo
  Future<WorkOrder> reopenPaid(WorkOrder order, {String? note, DateTime? now}) async {
    if (!order.isPaid) return order;
    for (final id in order.saleIds) {
      final sale = await SalesRepository.instance.getSaleById(id);
      if (sale != null) await SalesRepository.instance.cancelSale(sale);
    }
    await CommissionsRepository.instance.onOrderReopened(order.id, now: now);
    final at = now ?? DateTime.now();
    final clean = (note ?? '').trim();
    final reopened = WorkOrder(
      id: order.id,
      businessId: order.businessId,
      number: order.number,
      plate: order.plate,
      vehicle: order.vehicle,
      vehicleKind: order.vehicleKind,
      customerName: order.customerName,
      customerPhone: order.customerPhone,
      status: WorkOrder.ready,
      lines: order.lines,
      notes: [
        if ((order.notes ?? '').trim().isNotEmpty) order.notes!.trim(),
        'Se anuló el cobro${clean.isEmpty ? '' : ': $clean'}',
      ].join('\n'),
      statusTimes: {...order.statusTimes, WorkOrder.ready: at},
      total: order.subtotal,
      createdBy: order.createdBy,
      createdAt: order.createdAt,
      updatedAt: at,
    );
    await _store(reopened);
    ActivityRepository.instance.log(
      businessId: order.businessId,
      action: 'service_revert',
      summary: 'Anuló el cobro de ${order.title}${clean.isEmpty ? '' : ' ($clean)'}',
      data: {'work_order_id': order.id},
    );
    return reopened;
  }

  // ---------------------------------------------------------------------------
  // Historial: búsqueda en vivo por placa o serial, nombre o teléfono
  // ---------------------------------------------------------------------------

  Future<List<WorkOrder>> searchHistory(String businessId, String query, {int limit = 60}) async {
    final db = await _dbProvider.database;
    final text = query.trim();
    if (text.isEmpty) {
      final rows = await db.query('work_orders',
          where: 'business_id = ?', whereArgs: [businessId], orderBy: 'created_at DESC', limit: limit);
      return rows.map(WorkOrder.fromMap).toList();
    }
    final plate = WorkOrder.normalizePlate(text);
    final digits = text.replaceAll(RegExp(r'[^0-9]'), '');
    final rows = await db.query(
      'work_orders',
      where: 'business_id = ? AND ('
          '${plate.isEmpty ? '0' : 'plate LIKE ?'} OR LOWER(customer_name) LIKE ? '
          'OR ${digits.length < 3 ? '0' : "REPLACE(REPLACE(customer_phone, ' ', ''), '+', '') LIKE ?"})',
      whereArgs: [
        businessId,
        if (plate.isNotEmpty) '%$plate%',
        '%${text.toLowerCase()}%',
        if (digits.length >= 3) '%$digits%',
      ],
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return rows.map(WorkOrder.fromMap).toList();
  }

  /// Último trabajo de una placa, nombre o teléfono, para completar los datos al recibir
  Future<WorkOrder?> lastVisit(String businessId, String query) async {
    final found = await searchHistory(businessId, query, limit: 1);
    return found.isEmpty ? null : found.first;
  }

  // ---------------------------------------------------------------------------
  // Asistencia del día
  // ---------------------------------------------------------------------------

  Future<List<StaffAttendance>> getAttendance(String businessId, {DateTime? day}) async {
    final db = await _dbProvider.database;
    final rows = await db.query('staff_attendance',
        where: 'business_id = ? AND day = ?', whereArgs: [businessId, StaffAttendance.dayOf(day ?? DateTime.now())]);
    return rows.map(StaffAttendance.fromMap).toList();
  }

  /// Asistencia de un empleado en un rango de días (para su perfil)
  Future<List<StaffAttendance>> attendanceOf(String staffId, {required DateTime from, required DateTime to}) async {
    final db = await _dbProvider.database;
    final rows = await db.query('staff_attendance',
        where: 'staff_id = ? AND day >= ? AND day <= ?',
        whereArgs: [staffId, StaffAttendance.dayOf(from), StaffAttendance.dayOf(to)],
        orderBy: 'day DESC');
    return rows.map(StaffAttendance.fromMap).toList();
  }

  Future<StaffAttendance> _saveAttendance(StaffAttendance a) async {
    final db = await _dbProvider.database;
    final row = a.toMap();
    await db.insert('staff_attendance', row, conflictAlgorithm: ConflictAlgorithm.replace);
    _cloud.upsertAttendanceToCloud(row);
    return a;
  }

  Future<StaffAttendance?> _todayOf(String businessId, String staffId, DateTime at) async {
    final db = await _dbProvider.database;
    final rows = await db.query('staff_attendance',
        where: 'business_id = ? AND staff_id = ? AND day = ?',
        whereArgs: [businessId, staffId, StaffAttendance.dayOf(at)],
        limit: 1);
    return rows.isEmpty ? null : StaffAttendance.fromMap(rows.first);
  }

  /// Marca que llegó (también corrige un «No vino» o una salida marcada por error)
  Future<StaffAttendance> markArrived(String businessId, String staffId, {DateTime? now}) async {
    final at = now ?? DateTime.now();
    final current = await _todayOf(businessId, staffId, at);
    return _saveAttendance(current == null
        ? StaffAttendance(
            id: const Uuid().v4(),
            businessId: businessId,
            staffId: staffId,
            day: StaffAttendance.dayOf(at),
            status: StaffAttendance.arrived,
            arrivedAt: at,
            updatedAt: at,
          )
        : current.copyWith(
            status: StaffAttendance.arrived,
            arrivedAt: current.arrivedAt ?? at,
            clearLeft: true,
            updatedAt: at,
          ));
  }

  /// Marca que no vino: no se le puede asignar trabajo hoy
  Future<StaffAttendance> markAbsent(String businessId, String staffId, {ServiceBoard? board, DateTime? now}) async {
    if (board?.activeLineOf(staffId) != null) {
      throw StateError('Está haciendo un servicio: termínalo o retrocédelo primero.');
    }
    final at = now ?? DateTime.now();
    final current = await _todayOf(businessId, staffId, at);
    return _saveAttendance(StaffAttendance(
      id: current?.id ?? const Uuid().v4(),
      businessId: businessId,
      staffId: staffId,
      day: StaffAttendance.dayOf(at),
      status: StaffAttendance.absent,
      updatedAt: at,
    ));
  }

  /// Marca la salida: deja de recibir trabajo
  Future<StaffAttendance> markLeft(String businessId, String staffId, {ServiceBoard? board, DateTime? now}) async {
    if (board?.activeLineOf(staffId) != null) {
      throw StateError('Está haciendo un servicio: termínalo antes de marcar la salida.');
    }
    final at = now ?? DateTime.now();
    final current = await _todayOf(businessId, staffId, at);
    if (current == null || current.status != StaffAttendance.arrived) {
      throw StateError('Primero marca su llegada.');
    }
    // Una pausa abierta se cierra con la salida
    final pauses = [for (final (start, end) in current.pauses) (start, end ?? at)];
    return _saveAttendance(current.copyWith(leftAt: at, pauses: pauses, updatedAt: at));
  }

  /// Empieza o termina una pausa
  Future<StaffAttendance> togglePause(String businessId, String staffId, {ServiceBoard? board, DateTime? now}) async {
    final at = now ?? DateTime.now();
    final current = await _todayOf(businessId, staffId, at);
    if (current == null || current.status != StaffAttendance.arrived || current.hasLeft) {
      throw StateError('Solo puede pausar quien llegó y no se ha ido.');
    }
    if (current.onPause) {
      final pauses = [...current.pauses];
      pauses[pauses.length - 1] = (pauses.last.$1, at);
      return _saveAttendance(current.copyWith(pauses: pauses, updatedAt: at));
    }
    if (board?.activeLineOf(staffId) != null) {
      throw StateError('Está haciendo un servicio: termínalo antes de la pausa.');
    }
    return _saveAttendance(current.copyWith(pauses: [...current.pauses, (at, null)], updatedAt: at));
  }

  /// Todo lo del tablero de hoy, listo para las reglas
  Future<ServiceBoard> loadBoard(String businessId, {DateTime? now}) async {
    final results = await Future.wait([
      getBoard(businessId, now: now),
      getStaff(businessId),
      getServices(businessId, includeInactive: true),
      getAttendance(businessId, day: now),
    ]);
    return ServiceBoard(
      orders: results[0] as List<WorkOrder>,
      staff: results[1] as List<StaffMember>,
      services: results[2] as List<ShopService>,
      attendance: results[3] as List<StaffAttendance>,
    );
  }
}
