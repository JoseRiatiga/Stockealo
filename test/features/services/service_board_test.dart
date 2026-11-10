import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stockealo/core/database/app_database.dart';
import 'package:stockealo/core/services/supabase_service.dart';
import 'package:stockealo/features/auth/data/auth_repository.dart';
import 'package:stockealo/features/auth/models/app_user.dart';
import 'package:stockealo/features/business/models/business.dart';
import 'package:stockealo/features/sales/data/sales_repository.dart';
import 'package:stockealo/features/services/data/service_board.dart';
import 'package:stockealo/features/services/data/services_repository.dart';
import 'package:stockealo/features/services/models/service_models.dart';

/// Reglas del módulo Servicios de la 0.12.0: plantillas, precio por vehículo,
/// asistencia, un servicio activo por empleado, cola, retroceder y anular cobro
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory dbDir;
  const account = 'service-board-test';
  const businessId = 'biz-board';
  final appDb = AppDatabase.instance;
  final repo = ServicesRepository.instance;
  final now = DateTime(2026, 11, 10, 9);
  final business = Business(
    id: businessId,
    userId: 'u1',
    name: 'Lavadero Brillo',
    servicesEnabled: true,
    serviceType: ServiceTemplate.lavadero.code,
    createdAt: now,
  );

  Future<void> deleteDbFile() async {
    for (final name in ['stockealo_v2.db', 'stockealo_$account.db']) {
      await databaseFactory.deleteDatabase(p.join(await getDatabasesPath(), name));
    }
  }

  setUpAll(() async {
    dbDir = await Directory.systemTemp.createTemp('stockealo_board_');
    await databaseFactory.setDatabasesPath(dbDir.path);
  });

  setUp(() async {
    await SupabaseService.instance.waitForPendingWrites();
    await appDb.useAccount(null);
    await appDb.close();
    await deleteDbFile();
    await appDb.useAccount(account);
    final db = await appDb.database;
    await db.insert('users', {'id': 'u1', 'email': 'ana@x.com', 'password': authManagedPassword, 'created_at': '2026-10-01'});
    await db.insert('businesses', business.toMap());
    AuthRepository.debugCurrentUser = AppUser(id: 'u1', email: 'ana@x.com', name: 'Ana', createdAt: now);
  });

  tearDown(() => AuthRepository.debugCurrentUser = null);

  tearDownAll(() async {
    await SupabaseService.instance.waitForPendingWrites();
    await appDb.useAccount(null);
    await appDb.close();
    await deleteDbFile();
    if (await dbDir.exists()) await dbDir.delete(recursive: true);
  });

  /// Lavado (lo hacen Juan y Pedro) y Polichado (solo Juan); Juan y Pedro llegaron
  Future<(StaffMember, StaffMember, ShopService, ShopService)> setUpTeam() async {
    final juan = repo.newStaff(businessId, 'Juan');
    final pedro = repo.newStaff(businessId, 'Pedro');
    await repo.saveStaff(juan);
    await repo.saveStaff(pedro);
    final lavado = repo.newService(businessId, name: 'Lavado', price: 10000)
        .copyWith(prices: {'MOTO': 10000, 'CARRO': 20000}, staffIds: [juan.id, pedro.id]);
    final polichado = repo.newService(businessId, name: 'Polichado', price: 25000)
        .copyWith(prices: {'MOTO': 25000}, staffIds: [juan.id]);
    await repo.saveService(lavado);
    await repo.saveService(polichado);
    await repo.markArrived(businessId, juan.id, now: now);
    await repo.markArrived(businessId, pedro.id, now: now);
    return (juan, pedro, lavado, polichado);
  }

  WorkOrderLine lineOf(ShopService s, String kind) =>
      WorkOrderLine(serviceId: s.id, name: s.name, price: s.priceFor(kind)!, commissionPct: s.commissionPct);

  group('plantillas', () {
    test('cada tipo de negocio trae sus palabras y ninguno fuera del lavadero o taller habla de placa', () {
      expect(ServiceTemplate.lavadero.unit, 'Vehículo');
      expect(ServiceTemplate.lavadero.identifierLabel, 'Placa');
      expect(ServiceTemplate.lavadero.inProgress, 'Lavando');
      expect(ServiceTemplate.barberia.unit, 'Cliente');
      expect(ServiceTemplate.barberia.identifierLabel, isNull);
      expect(ServiceTemplate.tecnico.identifierLabel, 'Serial');
      for (final t in ServiceTemplate.all) {
        final words = '${t.unit} ${t.inProgress} ${t.readyLabel}'.toLowerCase();
        if (t != ServiceTemplate.lavadero) expect(words, isNot(contains('lavando')), reason: t.label);
        expect(words, isNot(contains('moto')), reason: t.label);
      }
    });

    test('los códigos de la 0.11.0 siguen funcionando', () {
      expect(ServiceTemplate.of('LAVADERO_MOTOS'), ServiceTemplate.lavadero);
      expect(ServiceTemplate.of('BARBERIA'), ServiceTemplate.barberia);
      expect(ServiceTemplate.of('cualquier cosa'), ServiceTemplate.otro);
    });

    test('el lavadero se configura con precios por vehículo y el casco solo es para motos', () async {
      final seeded = await repo.setupTemplate(businessId, ServiceTemplate.lavadero);
      expect(seeded, ServiceTemplate.lavadero.examples.length);
      final services = await repo.getServices(businessId);
      final casco = services.firstWhere((s) => s.name == 'Lavado de casco');
      final completo = services.firstWhere((s) => s.name == 'Lavado completo');
      expect(completo.priceFor('MOTO'), 15000);
      expect(completo.priceFor('CARRO'), 30000);
      expect(casco.offeredFor('MOTO'), isTrue);
      expect(casco.offeredFor('CARRO'), isFalse);
      // Una segunda vez no repite los servicios
      expect(await repo.setupTemplate(businessId, ServiceTemplate.lavadero), 0);
    });

    test('un lavadero de la 0.11.0 conserva sus precios como precio de moto', () async {
      await repo.saveService(repo.newService(businessId, name: 'Lavado viejo', price: 12000));
      await repo.migrateLegacyLavadero(businessId, 'LAVADERO_MOTOS');
      final s = (await repo.getServices(businessId)).single;
      expect(s.priceFor('MOTO'), 12000);
      expect(s.offeredFor('CARRO'), isFalse);
    });

    test('un servicio sin precios por vehículo cobra lo mismo para todos', () {
      final s = repo.newService(businessId, name: 'Corte', price: 15000);
      expect(s.priceFor(null), 15000);
      expect(s.priceFor('CARRO'), 15000);
    });
  });

  group('reglas del tablero', () {
    test('nadie empieza sin haber llegado, sin estar libre o sin hacer ese servicio', () async {
      final (juan, pedro, lavado, polichado) = await setUpTeam();
      final ana = repo.newStaff(businessId, 'Ana');
      await repo.saveStaff(ana);
      // Ana también lava
      await repo.saveService(lavado.copyWith(staffIds: [juan.id, pedro.id, ana.id]));
      final o1 = await repo.createOrder(
          businessId: businessId, plate: 'ABC12D', vehicleKind: 'MOTO', lines: [lineOf(lavado, 'MOTO'), lineOf(polichado, 'MOTO')], now: now);
      var board = await repo.loadBoard(businessId, now: now);

      // Ana no ha marcado llegada; Pedro no hace polichado
      expect(board.whyNotStart(o1, 0, ana.id), contains('marca la llegada'));
      expect(board.whyNotStart(o1, 1, pedro.id), contains('no hace Polichado'));
      expect(board.eligibleFor(o1, 1).map((s) => s.name), ['Juan']);

      final started = await repo.startLine(o1, 0, [juan.id], board: board, now: now);
      expect(started.status, WorkOrder.inProgress);
      board = await repo.loadBoard(businessId, now: now);
      expect(board.stateOf(juan.id), StaffState.busy);

      // Un solo servicio activo por empleado
      expect(board.whyNotStart(started, 1, juan.id), contains('ya está haciendo otro servicio'));
      expect(() => repo.startLine(started, 1, [juan.id], board: board, now: now), throwsStateError);

      // Ana no vino: no recibe trabajo
      await repo.markAbsent(businessId, ana.id, now: now);
      board = await repo.loadBoard(businessId, now: now);
      expect(board.stateOf(ana.id), StaffState.absent);
      expect(board.whyNotStart(started, 0, ana.id), isNotNull);
    });

    test('cola por orden de llegada y sugerencia cuando alguien se libera', () async {
      final (juan, pedro, lavado, polichado) = await setUpTeam();
      final first = await repo.createOrder(
          businessId: businessId, plate: 'AAA11A', vehicleKind: 'MOTO', lines: [lineOf(lavado, 'MOTO'), lineOf(polichado, 'MOTO')], now: now);
      final second = await repo.createOrder(
          businessId: businessId, plate: 'BBB22B', vehicleKind: 'CARRO', lines: [lineOf(lavado, 'CARRO')],
          now: now.add(const Duration(minutes: 5)));
      var board = await repo.loadBoard(businessId, now: now);
      expect(board.queue.length, 3);
      expect(board.turnOf(first), 1);
      expect(board.turnOf(second), 2);

      var o = await repo.startLine(first, 0, [juan.id], board: board, now: now);
      board = await repo.loadBoard(businessId, now: now);
      // Pedro está libre: lo siguiente que puede hacer es el lavado del segundo (no hace polichado)
      final forPedro = board.suggestionFor(pedro.id)!;
      expect(forPedro.order.id, second.id);

      // Juan termina: queda libre en ese momento y se le sugiere el polichado del primero
      o = await repo.finishLine(o, 0, now: now.add(const Duration(minutes: 20)));
      expect(o.isPartial, isTrue);
      expect(o.statusLabelFor(ServiceTemplate.lavadero), 'A medias');
      board = await repo.loadBoard(businessId, now: now);
      expect(board.stateOf(juan.id), StaffState.available);
      final forJuan = board.suggestionFor(juan.id)!;
      expect(forJuan.order.id, first.id);
      expect(forJuan.index, 1);

      o = await repo.startLine(o, 1, [juan.id], board: board, now: now);
      o = await repo.finishLine(o, 1, now: now);
      expect(o.status, WorkOrder.ready);
      expect(o.statusLabelFor(ServiceTemplate.lavadero), 'Listo');
    });

    test('pausa y salida: no recibe trabajo, y no se puede pausar con un servicio en curso', () async {
      final (juan, pedro, lavado, _) = await setUpTeam();
      final o = await repo.createOrder(
          businessId: businessId, vehicleKind: 'MOTO', lines: [lineOf(lavado, 'MOTO')], now: now);
      await repo.togglePause(businessId, pedro.id, now: now);
      var board = await repo.loadBoard(businessId, now: now);
      expect(board.stateOf(pedro.id), StaffState.paused);
      expect(board.whyNotStart(o, 0, pedro.id), contains('pausa'));

      await repo.startLine(o, 0, [juan.id], board: board, now: now);
      board = await repo.loadBoard(businessId, now: now);
      expect(() => repo.togglePause(businessId, juan.id, board: board, now: now), throwsStateError);
      expect(() => repo.markLeft(businessId, juan.id, board: board, now: now), throwsStateError);

      await repo.togglePause(businessId, pedro.id, now: now);
      await repo.markLeft(businessId, pedro.id, now: now);
      board = await repo.loadBoard(businessId, now: now);
      expect(board.stateOf(pedro.id), StaffState.left);
      expect(board.queueBlocked, isFalse);
    });
  });

  group('retroceder y anular el cobro', () {
    test('retrocede un paso a la vez y deja nota y registro', () async {
      final (juan, _, lavado, _) = await setUpTeam();
      var o = await repo.createOrder(businessId: businessId, vehicleKind: 'MOTO', lines: [lineOf(lavado, 'MOTO')], now: now);
      var board = await repo.loadBoard(businessId, now: now);
      o = await repo.startLine(o, 0, [juan.id], board: board, now: now);
      o = await repo.finishLine(o, 0, now: now);
      expect(o.status, WorkOrder.ready);

      board = await repo.loadBoard(businessId, now: now);
      o = await repo.revertLine(o, 0, board: board, note: 'Quedó sucio el rin', now: now);
      expect(o.status, WorkOrder.inProgress);
      expect(o.lines.single.staffIds, [juan.id]);
      expect(o.notes, contains('Quedó sucio el rin'));

      board = await repo.loadBoard(businessId, now: now);
      o = await repo.revertLine(o, 0, board: board, now: now);
      expect(o.status, WorkOrder.waiting);
      expect(o.lines.single.staffIds, isEmpty);
      board = await repo.loadBoard(businessId, now: now);
      expect(board.stateOf(juan.id), StaffState.available);
    });

    test('un trabajo cobrado no se retrocede: se anula el cobro y vuelve a Listo', () async {
      final (juan, _, lavado, _) = await setUpTeam();
      var o = await repo.createOrder(businessId: businessId, vehicleKind: 'CARRO', lines: [lineOf(lavado, 'CARRO')], now: now);
      var board = await repo.loadBoard(businessId, now: now);
      o = await repo.startLine(o, 0, [juan.id], board: board, now: now);
      o = await repo.finishLine(o, 0, now: now);
      final sales = await SalesRepository.instance.recordServiceSale(order: o, paymentMethod: 'EFECTIVO', now: now);
      o = await repo.markPaid(o, saleIds: [for (final s in sales) s.id], paymentMethod: 'EFECTIVO', total: 20000, now: now);
      expect(o.status, WorkOrder.delivered);

      board = await repo.loadBoard(businessId, now: now);
      expect(() => repo.revertLine(o, 0, board: board, now: now), throwsStateError);

      o = await repo.reopenPaid(o, note: 'Cobré mal', now: now);
      expect(o.status, WorkOrder.ready);
      expect(o.isPaid, isFalse);
      expect(o.notes, contains('Se anuló el cobro'));
      final db = await appDb.database;
      expect(await db.query('sales', where: 'id = ?', whereArgs: [sales.single.id]), isEmpty);
    });
  });

  test('historial en vivo por placa, nombre o teléfono', () async {
    final (_, _, lavado, _) = await setUpTeam();
    await repo.createOrder(
        businessId: businessId, plate: 'xyz-98k', customerName: 'Carlos Gómez', customerPhone: '+57 300 111 2233',
        vehicleKind: 'MOTO', lines: [lineOf(lavado, 'MOTO')], now: now);
    expect((await repo.searchHistory(businessId, 'xyz')).single.plate, 'XYZ98K');
    expect((await repo.searchHistory(businessId, 'carl')).length, 1);
    expect((await repo.searchHistory(businessId, '3001112')).length, 1);
    expect(await repo.searchHistory(businessId, 'nadie'), isEmpty);
    expect((await repo.lastVisit(businessId, 'XYZ98K'))?.customerName, 'Carlos Gómez');
  });
}
