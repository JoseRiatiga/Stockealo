import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:stockealo/core/theme/app_theme.dart';
import 'package:stockealo/features/products/presentation/widgets/lots_widgets.dart';
import 'package:stockealo/features/suppliers/models/purchase.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stockealo/core/database/app_database.dart';
import 'package:stockealo/core/services/supabase_service.dart';
import 'package:stockealo/features/business/models/business.dart';
import 'package:stockealo/features/products/data/lots_repository.dart';
import 'package:stockealo/features/products/models/product_lot.dart';

/// 0.16.0, fase 2b: lotes con vencimiento
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory dbDir;
  const account = 'lots-test';
  const businessId = 'biz-lots';
  final appDb = AppDatabase.instance;
  final lots = LotsRepository.instance;

  Future<void> deleteDbFile() async {
    for (final name in ['stockealo_v2.db', 'stockealo_$account.db']) {
      await databaseFactory.deleteDatabase(p.join(await getDatabasesPath(), name));
    }
  }

  Future<int> stockOf(String id) async =>
      ((await (await appDb.database).query('products', columns: ['stock'], where: 'id = ?', whereArgs: [id])).first['stock'] as num).toInt();

  Future<void> setStock(String id, int stock) async =>
      (await appDb.database).update('products', {'stock': stock}, where: 'id = ?', whereArgs: [id]);

  setUpAll(() async {
    await initializeDateFormatting('es_CO');
    dbDir = await Directory.systemTemp.createTemp('stockealo_lots_');
    await databaseFactory.setDatabasesPath(dbDir.path);
  });

  setUp(() async {
    await SupabaseService.instance.waitForPendingWrites();
    await appDb.useAccount(null);
    await appDb.close();
    await deleteDbFile();
    await appDb.useAccount(account);
    final db = await appDb.database;
    await db.insert('users', {'id': 'u1', 'email': 'rosa@x.com', 'password': authManagedPassword, 'created_at': '2026-10-01'});
    await db.insert('businesses', Business(id: businessId, userId: 'u1', name: 'Droguería Rosita', createdAt: DateTime(2026)).toMap());
    await db.insert('products', {
      'id': 'dolex', 'business_id': businessId, 'code': 'D1', 'name': 'Dolex', 'category': 'Medicamentos',
      'purchase_price': 1000, 'sale_price': 2000, 'stock': 54, 'min_stock': 5, 'tracks_expiry': 1,
      'created_at': '2026-10-01', 'updated_at': '2026-10-01',
    });
  });

  tearDownAll(() async {
    await SupabaseService.instance.waitForPendingWrites();
    await appDb.useAccount(null);
    await appDb.close();
    await deleteDbFile();
    if (await dbDir.exists()) await dbDir.delete(recursive: true);
  });

  test('fechas: vence el día que dice, se cuenta vencido desde el siguiente', () {
    final lot = ProductLot(
      id: 'x', businessId: businessId, productId: 'dolex', expiresOn: DateTime(2026, 12, 3), quantity: 1, initialQuantity: 1,
      createdAt: DateTime(2026), updatedAt: DateTime(2026),
    );
    expect(lot.isExpiredOn(DateTime(2026, 12, 3, 23)), isFalse);
    expect(lot.isExpiredOn(DateTime(2026, 12, 4)), isTrue);
    expect(lot.daysLeft(DateTime(2026, 11, 15, 10)), 18);
    expect(lot.expiresSoon(DateTime(2026, 11, 15)), isTrue);
    expect(lot.expiresSoon(DateTime(2026, 10, 1)), isFalse);
  });

  // Lo «sin fecha» se vende primero (no se sabe cuándo vence); después, el lote que vence antes
  test('al vender se descuenta primero el lote que vence antes; lo sin fecha va primero', () async {
    final now = DateTime(2026, 11, 15);
    await lots.addLot(businessId: businessId, productId: 'dolex', quantity: 40, expiresOn: DateTime(2027, 6, 10), code: 'A2391', now: now);
    await lots.addLot(businessId: businessId, productId: 'dolex', quantity: 10, expiresOn: DateTime(2026, 12, 3), code: 'A1876', now: now);
    expect(await lots.undated('dolex'), 4); // 54 en stock, 50 con lote
    await setStock('dolex', 42); // se vendieron 12
    await lots.reconcile(businessId, now: now);
    final after = await lots.lotsFor('dolex');
    final a1876 = after.firstWhere((l) => l.code == 'A1876');
    final a2391 = after.firstWhere((l) => l.code == 'A2391');
    expect(await lots.undated('dolex'), 0, reason: 'las 4 sin fecha se vendieron primero');
    expect(a1876.quantity, 2, reason: 'las otras 8 salen del que vence antes');
    expect(a2391.quantity, 40);
    await setStock('dolex', 30); // se venden 12 más: 2 del A1876 y 10 del A2391
    await lots.reconcile(businessId, now: now);
    final again = await lots.lotsFor('dolex');
    expect(again.firstWhere((l) => l.code == 'A1876').status, ProductLot.used);
    expect(again.firstWhere((l) => l.code == 'A2391').quantity, 30);
  });

  test('lo vencido sale del stock vendible; el cambio vuelve sin costo; la baja es merma', () async {
    final now = DateTime(2026, 11, 15);
    await setStock('dolex', 14);
    await lots.addLot(businessId: businessId, productId: 'dolex', quantity: 4, expiresOn: DateTime(2026, 11, 2), code: 'B1102', now: now);
    await lots.addLot(businessId: businessId, productId: 'dolex', quantity: 10, expiresOn: DateTime(2026, 12, 3), code: 'A1876', now: now);
    await lots.reconcile(businessId, now: now);
    expect(await stockOf('dolex'), 10, reason: 'las 4 vencidas ya no se venden');
    var alerts = await lots.alerts(businessId, now: now);
    expect(alerts.expired.single.code, 'B1102');
    expect(alerts.soon.single.code, 'A1876');
    // Reconciliar otra vez no vuelve a restar
    await lots.reconcile(businessId, now: now);
    expect(await stockOf('dolex'), 10);

    // Cambio con el proveedor
    final exchange = await lots.sendToExchange(alerts.expired.single, productName: 'Dolex', supplierName: 'Distribuidora X');
    alerts = await lots.alerts(businessId, now: now);
    expect(alerts.expired, isEmpty);
    expect(alerts.pending.single.quantity, 4);
    final fresh = await lots.receiveExchange(exchange, expiresOn: DateTime(2027, 8, 1), code: 'C9');
    expect(fresh.cost, 0);
    expect(fresh.source, 'CAMBIO');
    expect(await stockOf('dolex'), 14);
    expect((await lots.alerts(businessId, now: now)).pending, isEmpty);
    final closed = (await lots.exchanges(businessId)).single;
    await expectLater(lots.receiveExchange(closed, expiresOn: DateTime(2027)), throwsStateError, reason: 'no se recibe dos veces');
    await expectLater(lots.receiveExchange(exchange, expiresOn: DateTime(2027)), throwsStateError,
        reason: 'tampoco con el cambio viejo que tenía la pantalla');
    expect(await stockOf('dolex'), 14);

    // Otro lote que vence y se da de baja: queda como merma, sin tocar más el stock
    await lots.addLot(businessId: businessId, productId: 'dolex', quantity: 3, expiresOn: DateTime(2026, 11, 10), code: 'Z1', now: now);
    await setStock('dolex', 17);
    await lots.reconcile(businessId, now: now);
    expect(await stockOf('dolex'), 14);
    final z1 = (await lots.alerts(businessId, now: now)).expired.single;
    await lots.writeOff(z1, productName: 'Dolex');
    expect(await stockOf('dolex'), 14);
    final merma = await (await appDb.database).query('stock_movements', where: "type = 'MERMA' AND product_id = 'dolex'");
    expect(merma.single['quantity'], 3);
    expect((await lots.alerts(businessId, now: now)).expired, isEmpty);
  });

  test('un producto sin «Controla vencimiento» no se toca', () async {
    await (await appDb.database).update('products', {'tracks_expiry': 0}, where: 'id = ?', whereArgs: ['dolex']);
    await lots.addLot(businessId: businessId, productId: 'dolex', quantity: 4, expiresOn: DateTime(2026, 1, 1));
    await lots.reconcile(businessId, now: DateTime(2026, 11, 15));
    expect(await stockOf('dolex'), 54);
  });

  test('el renglón de la entrada guarda el lote y la fecha', () {
    final item = PurchaseItem(productId: 'dolex', productName: 'Dolex', quantity: 40, unitCost: 1000, lotCode: 'A2391', expiresOn: DateTime(2027, 6, 10));
    final back = PurchaseItem.fromJson(item.toJson());
    expect(back.lotCode, 'A2391');
    expect(back.expiresOn, DateTime(2027, 6, 10));
    expect(item.toJson()['expires_on'], '2027-06-10');
    expect(PurchaseItem.fromJson(const PurchaseItem(productId: 'x', productName: 'X', quantity: 1, unitCost: 1).toJson()).expiresOn, isNull);
  });

  testWidgets('el aviso de Inicio y la hoja de vencimientos', (tester) async {
    tester.view.physicalSize = const Size(360, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final now = DateTime.now();
    await tester.runAsync(() async {
      await setStock('dolex', 14);
      await lots.addLot(businessId: businessId, productId: 'dolex', quantity: 4, expiresOn: now.subtract(const Duration(days: 5)), code: 'B1102');
      await lots.addLot(businessId: businessId, productId: 'dolex', quantity: 10, expiresOn: now.add(const Duration(days: 12)), code: 'A1876');
    });
    final biz = Business(id: businessId, userId: 'u1', name: 'Droguería Rosita', createdAt: DateTime(2026));
    await tester.pumpWidget(MaterialApp(theme: AppTheme.lightTheme, home: Scaffold(body: ExpiryAlert(business: biz))));
    // Espera a que cargue (hasta 5 s): en GitHub la base va más lenta y fallaba a veces
    for (var i = 0; i < 100 && find.text('1 lote vence en los próximos 30 días').evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    expect(find.text('1 lote vence en los próximos 30 días'), findsOneWidget);
    expect(find.text('Y 1 ya venció'), findsOneWidget);
    expect(await tester.runAsync(() => stockOf('dolex')), 10, reason: 'lo vencido salió del stock');
    await tester.tap(find.text('Ver'));
    for (var i = 0; i < 100 && find.text('VENCEN PRONTO').evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(find.text('Vencimientos'), findsOneWidget);
    expect(find.text('VENCIDOS'), findsOneWidget);
    expect(find.text('VENCEN PRONTO'), findsOneWidget);
    expect(find.text('Vencido'), findsOneWidget);
    expect(find.text('En 12 días'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
