import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stockealo/core/database/app_database.dart';
import 'package:stockealo/core/services/supabase_service.dart';
import 'package:stockealo/features/auth/data/auth_repository.dart';
import 'package:stockealo/features/auth/models/app_user.dart';
import 'package:stockealo/features/business/models/business.dart';
import 'package:stockealo/features/cash/data/cash_register_repository.dart';
import 'package:stockealo/features/cash/models/cash_session.dart';
import 'package:stockealo/features/cash/presentation/widgets/cash_status_card.dart';

/// Arqueo de caja mejorado (0.12.0): movimientos, propinas, mercancía de contado,
/// cierre por forma de pago, nota obligatoria si no cuadra y comprobante
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory dbDir;
  const account = 'cash-test';
  const businessId = 'biz-cash';
  final appDb = AppDatabase.instance;
  final repo = CashRegisterRepository.instance;
  final opened = DateTime(2026, 11, 10, 8);
  final business = Business(id: businessId, userId: 'u1', name: 'Tienda Ana', cashRegisterEnabled: true, createdAt: opened);

  Future<void> deleteDbFile() async {
    for (final name in ['stockealo_v2.db', 'stockealo_$account.db']) {
      await databaseFactory.deleteDatabase(p.join(await getDatabasesPath(), name));
    }
  }

  setUpAll(() async {
    dbDir = await Directory.systemTemp.createTemp('stockealo_cash_');
    await databaseFactory.setDatabasesPath(dbDir.path);
  });

  setUp(() async {
    // El registro de actividad se guarda sin esperar: se deja terminar antes de cerrar la base
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await SupabaseService.instance.waitForPendingWrites();
    await appDb.useAccount(null);
    await appDb.close();
    await deleteDbFile();
    await appDb.useAccount(account);
    final db = await appDb.database;
    await db.insert('users', {'id': 'u1', 'email': 'ana@x.com', 'password': authManagedPassword, 'created_at': '2026-10-01'});
    await db.insert('businesses', business.toMap());
    AuthRepository.debugCurrentUser = AppUser(id: 'u1', email: 'ana@x.com', name: 'Ana', createdAt: opened);
  });

  tearDown(() => AuthRepository.debugCurrentUser = null);

  tearDownAll(() async {
    await SupabaseService.instance.waitForPendingWrites();
    await appDb.useAccount(null);
    await appDb.close();
    await deleteDbFile();
    if (await dbDir.exists()) await dbDir.delete(recursive: true);
  });

  Future<void> sale(String id, double total, String method, DateTime at) async {
    final db = await appDb.database;
    await db.insert('sales', {
      'id': id, 'business_id': businessId, 'product_name': 'Arroz', 'quantity': 1, 'date': at.toIso8601String(),
      'total': total, 'total_cost': 0, 'net_profit': total, 'payment_method': method,
      'created_at': at.toIso8601String(), 'is_synced': 0,
    });
  }

  test('lo esperado suma ventas y abonos en efectivo, propinas y entradas, y resta salidas y mercancía de contado', () async {
    final session = await repo.openSession(businessId: businessId, openingAmount: 50000, openedBy: 'Ana', now: opened);
    final at = opened.add(const Duration(hours: 1));
    await sale('s1', 30000, 'EFECTIVO', at);
    await sale('s2', 20000, 'TRANSFERENCIA', at);
    await sale('s3', 10000, 'FIADO', at);
    final db = await appDb.database;
    await db.insert('customers', {
      'id': 'c1', 'business_id': businessId, 'name': 'Carlos', 'debt_balance': 0, 'created_at': at.toIso8601String(),
    });
    await db.insert('customer_payments', {
      'id': 'a1', 'business_id': businessId, 'customer_id': 'c1', 'amount': 5000, 'payment_method': 'EFECTIVO',
      'date': at.toIso8601String(),
    });
    // Propina en efectivo de un lavado entregado en el turno
    await db.insert('work_orders', {
      'id': 'o1', 'business_id': businessId, 'number': '1', 'status': 'ENTREGADA', 'lines': '[]', 'tip': 3000,
      'payment_method': 'EFECTIVO', 'created_at': at.toIso8601String(), 'updated_at': at.toIso8601String(),
    });
    // Mercancía que llegó pagada de contado
    await db.insert('purchases', {
      'id': 'p1', 'business_id': businessId, 'date': at.toIso8601String(), 'items': '[]', 'total': 12000,
      'payment_terms': 'CONTADO', 'created_at': at.toIso8601String(),
    });
    await repo.addMovement(session: session, kind: CashMovement.exit, reason: 'GASTO', amount: 4000, note: 'almuerzo', now: at);
    await repo.addMovement(session: session, kind: CashMovement.exit, reason: 'PROPINA', amount: 1000, note: 'a Juan', now: at);
    await repo.addMovement(session: session, kind: CashMovement.entry, reason: 'BASE', amount: 10000, now: at);

    final s = await repo.summarize(session, until: opened.add(const Duration(hours: 2)));
    expect(s.cashSales, 30000);
    expect(s.cashPayments, 5000);
    expect(s.tipsIn, 3000);
    expect(s.tipsOut, 1000);
    expect(s.tipsToDeliver, 2000);
    expect(s.cashPurchases, 12000);
    expect(s.expected, 50000 + 30000 + 5000 + 3000 - 1000 + 10000 - 4000 - 12000);
    expect(s.byMethod['TRANSFERENCIA'], 20000);
    expect(s.byMethod['FIADO'], 10000);
    expect(s.byMethod['ABONO_EFECTIVO'], 5000);
  });

  test('si no cuadra, la nota es obligatoria; el cierre guarda el resumen y el conteo por billetes', () async {
    final session = await repo.openSession(businessId: businessId, openingAmount: 20000, openedBy: 'Ana', now: opened);
    await sale('s1', 30000, 'EFECTIVO', opened.add(const Duration(hours: 1)));
    final closeAt = opened.add(const Duration(hours: 3));

    await expectLater(repo.closeSession(session: session, countedAmount: 45000, now: closeAt), throwsStateError);
    final closed = await repo.closeSession(
      session: session,
      countedAmount: 45000,
      notes: 'Di mal un vuelto',
      denominations: {20000: 2, 5000: 1},
      now: closeAt,
    );
    expect(closed.difference, -5000);
    expect(closed.closedBy, 'ana@x.com');
    expect(closed.summary['denominations'], {'20000': 2, '5000': 1});
    expect(await repo.getOpenSession(businessId), isNull);

    final text = CashRegisterRepository.receipt(
      businessName: 'Tienda Ana',
      session: closed,
      summary: await repo.summarize(closed),
      servicesLines: const ['Servicios: 3 trabajos entregados'],
    );
    expect(text, contains('Cierre de caja · Tienda Ana'));
    expect(text, contains('Efectivo: \$30.000'));
    expect(text, contains('Faltan \$5.000'));
    expect(text, contains('Nota: Di mal un vuelto'));
    expect(text, contains('Servicios: 3 trabajos entregados'));
  });

  test('cuadra exacto sin nota y no se registran movimientos en una caja cerrada', () async {
    final session = await repo.openSession(businessId: businessId, openingAmount: 10000, openedBy: 'Ana', now: opened);
    final closed = await repo.closeSession(session: session, countedAmount: 10000, now: opened.add(const Duration(hours: 1)));
    expect(closed.difference, 0);
    await expectLater(
      repo.addMovement(session: closed, kind: CashMovement.exit, reason: 'GASTO', amount: 1000),
      throwsStateError,
    );
  });

  test('una caja abierta desde ayer se marca para cerrarla', () {
    final s = CashSession(id: 'x', businessId: businessId, openedBy: 'Ana', openedAt: opened, openingAmount: 0);
    expect(s.isStale(DateTime(2026, 11, 10, 20)), isFalse);
    expect(s.isStale(DateTime(2026, 11, 11, 7)), isTrue);
  });

  test('avisa al cobrar en efectivo con la caja cerrada, sin avisar por otros medios', () async {
    expect(await isCashClosedFor(business, 'EFECTIVO'), isTrue);
    expect(await isCashClosedFor(business, 'TRANSFERENCIA'), isFalse);
    expect(await isCashClosedFor(business.copyWith(cashRegisterEnabled: false), 'EFECTIVO'), isFalse);
    await repo.openSession(businessId: businessId, openingAmount: 0, openedBy: 'Ana');
    expect(await isCashClosedFor(business, 'EFECTIVO'), isFalse);
  });
}
