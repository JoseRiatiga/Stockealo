import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stockealo/core/database/app_database.dart';
import 'package:stockealo/features/business/models/business.dart';
import 'package:stockealo/features/cash/data/cash_register_repository.dart';
import 'package:stockealo/features/products/models/product.dart';
import 'package:stockealo/features/sales/data/sales_repository.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory dbDir;
  const businessId = 'biz-1';
  final appDb = AppDatabase.instance;
  final cash = CashRegisterRepository.instance;
  final sales = SalesRepository.instance;

  late Product product;

  setUpAll(() async {
    dbDir = await Directory.systemTemp.createTemp('stockealo_cash_');
    await databaseFactory.setDatabasesPath(dbDir.path);
  });

  setUp(() async {
    await appDb.useAccount(null);
    await appDb.close();
    for (final f in dbDir.listSync()) {
      f.deleteSync(recursive: true);
    }
    await appDb.useAccount('cash-test');
    final db = await appDb.database;
    await db.insert('users', {'id': 'u1', 'email': 'a@x.com', 'password': authManagedPassword, 'created_at': '2026-10-01'});
    await db.insert('businesses', Business(id: businessId, userId: 'u1', name: 'Tienda', createdAt: DateTime(2026, 10, 1)).toMap());
    final now = DateTime.now();
    product = Product(
      id: 'p1',
      businessId: businessId,
      code: 'P1',
      name: 'Producto',
      category: 'General',
      purchasePrice: 500,
      salePrice: 1000,
      stock: 100,
      createdAt: now,
      updatedAt: now,
    );
    await db.insert('products', product.toMap());
  });

  tearDownAll(() async {
    await appDb.useAccount(null);
    await appDb.close();
    if (await dbDir.exists()) await dbDir.delete(recursive: true);
  });

  test('solo cuenta el efectivo: ventas y abonos, no transferencias ni fiados', () async {
    final session = await cash.openSession(businessId: businessId, openingAmount: 50000, openedBy: 'Ana');
    await sales.recordSale(product: product, quantity: 3, paymentMethod: 'EFECTIVO');
    await sales.recordSale(product: product.copyWith(stock: 97), quantity: 2, paymentMethod: 'TRANSFERENCIA');
    await sales.recordSale(product: product.copyWith(stock: 95), quantity: 1, paymentMethod: 'FIADO', customerName: 'Luis');
    final db = await appDb.database;
    final customerId = (await db.query('customers')).single['id'] as String;
    await db.insert('customer_payments', {
      'id': 'pay-1',
      'business_id': businessId,
      'customer_id': customerId,
      'amount': 400,
      'payment_method': 'EFECTIVO',
      'date': DateTime.now().toIso8601String(),
    });

    final summary = await cash.summarize(session);

    expect(summary.cashSales, 3000);
    expect(summary.cashSalesCount, 1);
    expect(summary.cashPayments, 400);
    expect(summary.expected, 53400);
  });

  test('no deja sacar más que el efectivo de la caja (0.16.4)', () async {
    final session = await cash.openSession(businessId: businessId, openingAmount: 10000, openedBy: 'Ana');
    await sales.recordSale(product: product, quantity: 2, paymentMethod: 'EFECTIVO');

    expect(await cash.movementProblem(session: session, kind: 'SALIDA', amount: 12000), isNull);
    expect(await cash.movementProblem(session: session, kind: 'SALIDA', amount: 12001), contains('En la caja hay'));
    await expectLater(
      cash.addMovement(session: session, kind: 'SALIDA', reason: 'GASTO', amount: 999999),
      throwsA(isA<StateError>()),
    );
    // Una entrada grande sí se puede; con ceros de más, no
    expect(await cash.movementProblem(session: session, kind: 'ENTRADA', amount: 500000), isNull);
    expect(await cash.movementProblem(session: session, kind: 'ENTRADA', amount: 999999999999), isNotNull);

    await cash.addMovement(session: session, kind: 'SALIDA', reason: 'GASTO', amount: 12000);
    expect((await cash.summarize(session)).expected, 0);
    expect(await cash.movementProblem(session: session, kind: 'SALIDA', amount: 1), 'No hay efectivo en la caja para sacar.');
  });

  test('anular un movimiento lo cancela y no se puede anular dos veces (0.16.4)', () async {
    final session = await cash.openSession(businessId: businessId, openingAmount: 10000, openedBy: 'Ana');
    final gasto = await cash.addMovement(session: session, kind: 'SALIDA', reason: 'GASTO', amount: 3000, note: 'bolsas');
    expect((await cash.summarize(session)).expected, 7000);

    final anula = await cash.voidMovement(session: session, movement: gasto);
    expect(anula.kind, 'ENTRADA');
    expect(anula.voidsId, gasto.id);
    expect(anula.visibleNote, isNull);

    final summary = await cash.summarize(session);
    expect(summary.expected, 10000);
    // Los dos se cancelan: no aparecen como entrada ni como salida
    expect(summary.entries, 0);
    expect(summary.exits, 0);

    final moves = await cash.movements(session);
    expect(CashRegisterRepository.voidedIds(moves), {gasto.id, anula.id});
    await expectLater(cash.voidMovement(session: session, movement: gasto), throwsA(isA<StateError>()));
    await expectLater(cash.voidMovement(session: session, movement: anula), throwsA(isA<StateError>()));
  });

  test('anular una entrada con ceros de más sí se puede (0.16.4)', () async {
    final session = await cash.openSession(businessId: businessId, openingAmount: 0, openedBy: 'Ana');
    // Una entrada vieja, de antes del tope
    final db = await appDb.database;
    await db.insert('cash_movements', {
      'id': 'm-big',
      'business_id': businessId,
      'session_id': session.id,
      'kind': 'ENTRADA',
      'reason': 'OTRO',
      'amount': 999999999999.0,
      'date': DateTime.now().toIso8601String(),
    });
    final big = (await cash.movements(session)).single;
    await cash.voidMovement(session: session, movement: big);
    expect((await cash.summarize(session)).expected, 0);
  });

  test('no cuenta ventas de antes de abrir la caja', () async {
    await sales.recordSale(product: product, quantity: 5, paymentMethod: 'EFECTIVO');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    final session = await cash.openSession(businessId: businessId, openingAmount: 0, openedBy: 'Ana');

    expect((await cash.summarize(session)).cashSales, 0);
  });

  test('no permite abrir dos cajas a la vez', () async {
    await cash.openSession(businessId: businessId, openingAmount: 1000, openedBy: 'Ana');

    await expectLater(
      cash.openSession(businessId: businessId, openingAmount: 1000, openedBy: 'Ana'),
      throwsA(isA<Exception>()),
    );
  });

  test('al cerrar guarda lo esperado, lo contado y el faltante', () async {
    final session = await cash.openSession(businessId: businessId, openingAmount: 10000, openedBy: 'Ana');
    await sales.recordSale(product: product, quantity: 2, paymentMethod: 'EFECTIVO');

    final closed = await cash.closeSession(session: session, countedAmount: 11500, notes: '  billete roto  ');

    expect(closed.expectedAmount, 12000);
    expect(closed.difference, -500);
    expect(closed.notes, 'billete roto');
    expect(await cash.getOpenSession(businessId), isNull);
    expect((await cash.getClosedSessions(businessId)).single.id, session.id);
  });
}
