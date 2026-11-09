import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stockealo/core/database/app_database.dart';
import 'package:stockealo/core/services/supabase_service.dart';
import 'package:stockealo/core/theme/app_theme.dart';
import 'package:stockealo/features/auth/data/auth_repository.dart';
import 'package:stockealo/features/auth/models/app_user.dart';
import 'package:stockealo/features/business/models/business.dart';
import 'package:stockealo/features/products/data/product_repository.dart';
import 'package:stockealo/features/products/models/product.dart';
import 'package:stockealo/features/products/models/product_variant.dart';
import 'package:stockealo/features/products/presentation/widgets/restock_order_modal.dart';
import 'package:stockealo/features/suppliers/data/supplier_repository.dart';
import 'package:stockealo/features/suppliers/models/purchase.dart';
import 'package:stockealo/features/suppliers/models/supplier.dart';
import 'package:stockealo/features/suppliers/models/supplier_order.dart';
import 'package:stockealo/features/suppliers/presentation/screens/supplier_orders_screen.dart';
import 'package:stockealo/core/services/phone_alerts_service.dart';
import 'package:stockealo/features/suppliers/presentation/screens/purchase_entry_screen.dart';
import 'package:stockealo/features/suppliers/presentation/screens/supplier_form_screen.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory dbDir;
  const account = 'suppliers-test';
  const businessId = 'biz-sup';
  final appDb = AppDatabase.instance;
  final repo = SupplierRepository.instance;
  final now = DateTime(2026, 11, 9);
  final business = Business(id: businessId, userId: 'u1', name: 'Loliando', createdAt: now);

  ProductVariant variant(String id, String talla, String color, int stock) => ProductVariant(
      id: id, businessId: businessId, productId: 'pij', attributeValue: talla, attribute2Name: 'Color',
      attribute2Value: color, stock: stock, createdAt: now, updatedAt: now);

  Product pijama() => Product(
        id: 'pij', businessId: businessId, code: 'P1', name: 'Pijama', category: 'Ropa',
        purchasePrice: 20000, salePrice: 50000, stock: 1, minStock: 4, hasVariants: true,
        variants: [variant('m-rojo', 'M', 'Rojo', 1), variant('l-azul', 'L', 'Azul', 0)],
        createdAt: now, updatedAt: now,
      );

  Product leggins() => Product(
        id: 'leg', businessId: businessId, code: 'L1', name: 'Leggins', category: 'Ropa',
        purchasePrice: 15000, salePrice: 30000, stock: 2, minStock: 3, createdAt: now, updatedAt: now,
      );

  Future<void> deleteDbFile() async {
    for (final name in ['stockealo_v2.db', 'stockealo_$account.db']) {
      await databaseFactory.deleteDatabase(p.join(await getDatabasesPath(), name));
    }
  }

  setUpAll(() async {
    dbDir = await Directory.systemTemp.createTemp('stockealo_suppliers_');
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

  test('la entrada suma por talla y color, actualiza el costo elegido y asigna el proveedor', () async {
    final products = ProductRepository.instance;
    await products.insertProduct(pijama());
    await products.insertProduct(leggins());
    final sol = repo.newSupplier(businessId, 'Distribuidora El Sol');
    await repo.saveSupplier(sol);

    await repo.registerPurchase(
      Purchase(
        id: 'e1',
        businessId: businessId,
        supplierId: sol.id,
        supplierName: sol.name,
        invoiceNumber: 'F-12',
        date: now,
        items: const [
          PurchaseItem(productId: 'pij', productName: 'Pijama', variantId: 'm-rojo', variantName: 'M · Rojo', quantity: 2, unitCost: 22000),
          PurchaseItem(productId: 'pij', productName: 'Pijama', variantId: 'l-azul', variantName: 'L · Azul', quantity: 3, unitCost: 22000),
          PurchaseItem(productId: 'leg', productName: 'Leggins', quantity: 4, unitCost: 16000),
        ],
        paymentTerms: 'CREDITO',
        isPaid: false,
        createdAt: now,
      ),
      newCosts: {'pij': 22000},
    );

    final p1 = (await products.getProductById('pij', businessId))!;
    expect(p1.stock, 6);
    expect({for (final v in p1.variants) v.id: v.stock}, {'m-rojo': 3, 'l-azul': 3});
    expect(p1.purchasePrice, 22000);
    expect(p1.supplierId, sol.id);

    final p2 = (await products.getProductById('leg', businessId))!;
    expect(p2.stock, 6);
    expect(p2.purchasePrice, 15000, reason: 'no se pidió cambiar el costo de los leggins');

    final saved = await repo.getPurchases(businessId, supplierId: sol.id);
    expect(saved.single.total, 22000 * 5 + 16000 * 4);
    expect(saved.single.units, 9);
    expect(saved.single.isCredit, isTrue);

    final db = await appDb.database;
    final moves = await db.query('stock_movements', where: "type = 'ENTRADA_COMPRA' AND reason LIKE 'Entrada%'");
    expect(moves.map((m) => m['quantity']).toSet(), {5, 4});
    expect(moves.first['reason'], contains('factura F-12'));
  });

  test('quitar un proveedor deja sus productos sin proveedor', () async {
    final sol = repo.newSupplier(businessId, 'El Sol');
    await repo.saveSupplier(sol);
    await ProductRepository.instance.insertProduct(leggins().copyWith(supplierId: sol.id));
    expect(await repo.productCounts(businessId), {sol.id: 1});

    await repo.deleteSupplier(sol);

    expect(await repo.getSuppliers(businessId), isEmpty);
    expect((await ProductRepository.instance.getProductById('leg', businessId))!.supplierId, isNull);
  });

  test('el pedido sugiere por talla y color y el mensaje las detalla', () {
    final item = RestockOrderItem.suggested(pijama());
    // Objetivo: el doble del mínimo (8) repartido entre 2 variantes = 4 de cada una
    expect(item.variantQty, {'m-rojo': 3, 'l-azul': 4});
    expect(RestockOrderItem.needsRestock(pijama()), isTrue);

    final supplier = Supplier(
      id: 's', businessId: businessId, name: 'El Sol', contactName: 'Carlos', createdAt: now, updatedAt: now,
    );
    final text = buildRestockOrderText(
      businessName: 'Loliando',
      items: [item, RestockOrderItem.suggested(leggins())],
      sender: 'Ana',
      supplier: supplier,
      now: now,
    );
    expect(text, contains('Para: Carlos (El Sol)'));
    expect(text, contains('• Pijama (Cód: P1) — M · Rojo: 3 / L · Azul: 4'));
    expect(text, contains('• 4 × Leggins (Cód: L1)'));
    expect(text, contains('Total: 2 productos, 11 unidades'));
  });

  test('abonos a una entrada a crédito hasta dejarla pagada', () async {
    await ProductRepository.instance.insertProduct(leggins());
    final purchase = Purchase(
      id: 'c1', businessId: businessId, supplierName: 'El Sol', date: now,
      items: const [PurchaseItem(productId: 'leg', productName: 'Leggins', quantity: 10, unitCost: 10000)],
      paymentTerms: 'CREDITO', dueDate: now.subtract(const Duration(days: 1)), isPaid: false, createdAt: now,
    );
    await repo.registerPurchase(purchase);
    expect((await repo.getPayables(businessId)).single.balance, 100000);
    expect(purchase.isOverdue(now), isTrue);

    final partial = await repo.addPayment(purchase, 40000, note: 'Nequi');
    expect(partial.isPaid, isFalse);
    expect(partial.balance, 60000);
    expect(partial.payments.single.note, 'Nequi');

    // Un abono mayor a lo que falta solo cubre el saldo
    final paid = await repo.addPayment(partial, 999999);
    expect(paid.isPaid, isTrue);
    expect(paid.payments.last.amount, 60000);
    expect(await repo.getPayables(businessId), isEmpty);
    expect((await repo.getPurchase('c1'))!.isPaid, isTrue);
  });

  testWidgets('la entrada retoma el borrador guardado', (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      await ProductRepository.instance.insertProduct(leggins());
      await appDb.setSetting(
        'purchase_draft_$businessId',
        jsonEncode({
          'saved_at': now.toIso8601String(),
          'invoice': 'F-99',
          'date': now.toIso8601String(),
          'credit': false,
          'lines': [
            {'product_id': 'leg', 'qty': 5, 'variants': {}, 'cost': 15000, 'update_cost': true},
          ],
        }),
      );
    });
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.build(Brightness.light),
      home: PurchaseEntryScreen(business: business),
    ));
    for (var i = 0; i < 20 && find.text('Leggins').evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    expect(find.textContaining('Retomaste el borrador'), findsOneWidget);
    expect(find.text('Leggins'), findsOneWidget);
    expect(find.text('F-99'), findsOneWidget);
    expect(find.text('5 unidades'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('el pedido guardado se compara con lo que llegó y deja los faltantes', () async {
    await ProductRepository.instance.insertProduct(pijama());
    await ProductRepository.instance.insertProduct(leggins());
    final order = SupplierOrder(
      id: 'o1', businessId: businessId, supplierName: 'El Sol', createdAt: now,
      items: const [
        SupplierOrderItem(productId: 'pij', productName: 'Pijama', variantId: 'm-rojo', variantName: 'M · Rojo', quantity: 3),
        SupplierOrderItem(productId: 'pij', productName: 'Pijama', variantId: 'l-azul', variantName: 'L · Azul', quantity: 2),
        SupplierOrderItem(productId: 'leg', productName: 'Leggins', quantity: 5),
      ],
    );
    await repo.saveOrder(order);
    expect((await repo.getOrders(businessId, pendingOnly: true)).single.id, 'o1');

    // Llegó todo menos 1 de M · Rojo y 2 leggins
    await repo.registerPurchase(Purchase(
      id: 'e-o1', businessId: businessId, orderId: 'o1', date: now, createdAt: now,
      items: const [
        PurchaseItem(productId: 'pij', productName: 'Pijama', variantId: 'm-rojo', quantity: 2, unitCost: 20000),
        PurchaseItem(productId: 'pij', productName: 'Pijama', variantId: 'l-azul', quantity: 2, unitCost: 20000),
        PurchaseItem(productId: 'leg', productName: 'Leggins', quantity: 3, unitCost: 15000),
      ],
    ));
    final partial = (await repo.getOrder('o1'))!;
    expect(partial.status, SupplierOrder.partial);
    expect(partial.missingUnits, 3);
    expect(partial.missingItems.map((i) => i.label), ['Pijama (M · Rojo)', 'Leggins']);

    final text = missingItemsText(businessName: 'Loliando', order: partial);
    expect(text, contains('• Pijama (M · Rojo): 1'));
    expect(text, contains('• Leggins: 2'));
    expect(text, contains('Total: 3 unidades.'));

    // Llega el resto: el pedido queda recibido y deja de estar pendiente
    final done = SupplierRepository.applyReceived(partial, const [
      PurchaseItem(productId: 'pij', productName: 'Pijama', variantId: 'm-rojo', quantity: 1, unitCost: 0),
      PurchaseItem(productId: 'leg', productName: 'Leggins', quantity: 2, unitCost: 0),
    ], now);
    expect(done.status, SupplierOrder.received);
    await repo.closeOrder(partial);
    expect(await repo.getOrders(businessId, pendingOnly: true), isEmpty);
  });

  test('día de visita: quién pasa hoy y cuándo avisar', () async {
    final lunes = repo.newSupplier(businessId, 'El Sol').copyWith(visitDay: 'Lunes');
    final miercoles = repo.newSupplier(businessId, 'La Luna').copyWith(visitDay: 'Miércoles');
    await repo.saveSupplier(lunes);
    await repo.saveSupplier(miercoles);

    // 9 de noviembre de 2026 es lunes
    expect((await repo.visitingOn(businessId, DateTime(2026, 11, 9))).map((s) => s.name), ['El Sol']);
    expect(PhoneAlertsService.nextVisit(DateTime(2026, 11, 9, 6), 1), DateTime(2026, 11, 9, 7));
    expect(PhoneAlertsService.nextVisit(DateTime(2026, 11, 9, 8), 1), DateTime(2026, 11, 16, 7));
    expect(PhoneAlertsService.nextVisit(DateTime(2026, 11, 9, 8), 3), DateTime(2026, 11, 11, 7));
    expect(PhoneAlertsService.nextVisit(DateTime(2026, 11, 14, 20), 1), DateTime(2026, 11, 16, 7));
  });

  testWidgets('la lista de pedidos muestra lo que faltó', (tester) async {
    tester.view.physicalSize = const Size(360, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(() => repo.saveOrder(SupplierOrder(
          id: 'o2', businessId: businessId, supplierName: 'El Sol', createdAt: now, status: SupplierOrder.partial,
          items: const [SupplierOrderItem(productId: 'leg', productName: 'Leggins', quantity: 5, received: 3)],
        )));
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.build(Brightness.light),
      home: SupplierOrdersScreen(business: business),
    ));
    for (var i = 0; i < 20 && find.text('Leggins').evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    expect(find.text('llegó 3 de 5'), findsOneWidget);
    expect(find.text('Pedir lo que faltó'), findsOneWidget);
    expect(find.text('Llegó lo que faltaba'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final width in [360.0, 1200.0]) {
    testWidgets('entrada de mercancía y ficha del proveedor se ven bien a ${width.toInt()} px', (tester) async {
      tester.view.physicalSize = Size(width, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.build(Brightness.light),
        home: PurchaseEntryScreen(business: business),
      ));
      // Deja terminar lo que la pantalla lee de la base al abrir (borrador, pedidos, costos)
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pump();
      expect(find.text('Entrada de mercancía'), findsOneWidget);
      expect(find.text('Sin proveedor'), findsOneWidget);
      await tester.tap(find.text('A crédito'));
      await tester.pump();
      expect(find.textContaining('Pagar a más tardar'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.build(Brightness.light),
        home: const SupplierFormScreen(businessId: businessId),
      ));
      expect(find.text('Nuevo proveedor'), findsOneWidget);
      await tester.tap(find.text('Más datos'));
      await tester.pumpAndSettle();
      expect(find.text('Forma de pago'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
