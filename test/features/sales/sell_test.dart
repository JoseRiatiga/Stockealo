import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stockealo/core/database/app_database.dart';
import 'package:stockealo/core/services/supabase_service.dart';
import 'package:stockealo/core/theme/app_theme.dart';
import 'package:stockealo/features/auth/data/auth_repository.dart';
import 'package:stockealo/features/auth/models/app_user.dart';
import 'package:stockealo/features/business/models/business.dart';
import 'package:stockealo/features/cash/data/cash_register_repository.dart';
import 'package:stockealo/features/dashboard/data/home_data.dart';
import 'package:stockealo/features/products/data/product_repository.dart';
import 'package:stockealo/features/sales/data/sales_repository.dart';
import 'package:stockealo/features/sales/data/sell_cart.dart';
import 'package:stockealo/features/sales/models/cart_item.dart';
import 'package:stockealo/features/sales/models/payment_method.dart';
import 'package:stockealo/features/sales/presentation/screens/sell_screen.dart';

/// Vender (bloque 4): pago mixto, caja obligatoria, anular sin borrar y cómo se
/// ve el punto de venta. Con PREVIEW_OUT=<carpeta> guarda imágenes.
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory dbDir;
  const account = 'sell-test';
  const businessId = 'biz-sell';
  final appDb = AppDatabase.instance;
  final sales = SalesRepository.instance;
  final cash = CashRegisterRepository.instance;
  final today = DateTime.now();
  var business = Business(id: businessId, userId: 'u1', name: 'Variedades Rosita', color: '#1E6B4E', createdAt: today);

  Future<void> deleteDbFile() async {
    for (final name in ['stockealo_v2.db', 'stockealo_$account.db']) {
      await databaseFactory.deleteDatabase(p.join(await getDatabasesPath(), name));
    }
  }

  Future<void> addProduct(String id, String name, {double price = 4200, double cost = 3000, int stock = 20, String category = 'Granos'}) async {
    final db = await appDb.database;
    final at = today.toIso8601String();
    await db.insert('products', {
      'id': id, 'business_id': businessId, 'code': 'C-$id', 'name': name, 'category': category,
      'purchase_price': cost, 'sale_price': price, 'stock': stock, 'min_stock': 5, 'created_at': at, 'updated_at': at,
    });
  }

  Future<void> setCash(bool enabled) async {
    final db = await appDb.database;
    business = business.copyWith(cashRegisterEnabled: enabled);
    await db.update('businesses', {'cash_register_enabled': enabled ? 1 : 0}, where: 'id = ?', whereArgs: [businessId]);
  }

  setUpAll(() async {
    await initializeDateFormatting('es_CO');
    dbDir = await Directory.systemTemp.createTemp('stockealo_sell_');
    await databaseFactory.setDatabasesPath(dbDir.path);
  });

  setUp(() async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await SupabaseService.instance.waitForPendingWrites();
    await appDb.useAccount(null);
    await appDb.close();
    await deleteDbFile();
    await appDb.useAccount(account);
    final db = await appDb.database;
    business = Business(id: businessId, userId: 'u1', name: 'Variedades Rosita', color: '#1E6B4E', createdAt: today);
    await db.insert('users', {'id': 'u1', 'email': 'rosa@x.com', 'password': authManagedPassword, 'created_at': '2026-10-01'});
    await db.insert('businesses', business.toMap());
    AuthRepository.debugCurrentUser = AppUser(id: 'u1', email: 'rosa@x.com', name: 'Rosa Pérez', createdAt: today);
    SellCart.instance.reset();
    await addProduct('arroz', 'Arroz Diana 500 g', stock: 0);
    await addProduct('huevos', 'Huevos AA x30', price: 18900, cost: 15000, stock: 14, category: 'Lácteos y huevos');
    await addProduct('aceite', 'Aceite Premier 1 L', price: 12900, cost: 10000, stock: 3);
    await addProduct('gaseosa', 'Gaseosa 1,5 L', price: 5600, cost: 4000, stock: 48, category: 'Bebidas');
  });

  tearDown(() => AuthRepository.debugCurrentUser = null);

  tearDownAll(() async {
    await SupabaseService.instance.waitForPendingWrites();
    await appDb.useAccount(null);
    await appDb.close();
    await deleteDbFile();
    if (await dbDir.exists()) await dbDir.delete(recursive: true);
  });

  Future<List<CartItem>> items(Map<String, int> qty) async => [
        for (final e in qty.entries)
          CartItem(product: (await ProductRepository.instance.getProductById(e.key, businessId))!, quantity: e.value),
      ];

  test('caja obligatoria: con la caja cerrada no se registra ninguna venta', () async {
    await setCash(true);
    await expectLater(
      sales.recordMultiProductSale(businessId: businessId, items: await items({'gaseosa': 1}), paymentMethod: PaymentMethod.nequi),
      throwsA(isA<CashClosedException>()),
    );
    await cash.openSession(businessId: businessId, openingAmount: 100000, openedBy: 'Rosa');
    final done = await sales.recordMultiProductSale(businessId: businessId, items: await items({'gaseosa': 1}), paymentMethod: PaymentMethod.nequi);
    expect(done.single.paymentMethod, 'NEQUI');
  });

  test('pago mixto: cada medio suma lo suyo y la caja solo cuenta el efectivo', () async {
    await setCash(true);
    final session = await cash.openSession(businessId: businessId, openingAmount: 100000, openedBy: 'Rosa');
    // 2 huevos (37.800) + 1 gaseosa (5.600) = 43.400: 20.000 en efectivo y 23.400 por Nequi
    final done = await sales.recordMultiProductSale(
      businessId: businessId,
      items: await items({'huevos': 2, 'gaseosa': 1}),
      paymentMethod: PaymentMethod.mixed,
      paymentSplit: {PaymentMethod.cash: 20000, PaymentMethod.nequi: 23400},
    );
    expect(done, hasLength(2));
    expect(done.map((s) => s.invoiceNumber).toSet(), hasLength(1), reason: 'las dos líneas son una sola venta');
    final summary = await cash.summarize(session);
    expect(summary.cashSales, closeTo(20000, 0.01));
    expect(summary.cashSalesCount, 1);
    expect(summary.byMethod[PaymentMethod.nequi], closeTo(23400, 0.01));
    expect(summary.expected, closeTo(120000, 0.01));

    // Si las partes no suman el total, no se registra
    await expectLater(
      sales.recordMultiProductSale(
        businessId: businessId,
        items: await items({'gaseosa': 1}),
        paymentMethod: PaymentMethod.mixed,
        paymentSplit: {PaymentMethod.cash: 1000},
      ),
      throwsA(isA<Exception>()),
    );
  });

  test('anular sin borrar: la venta queda en el historial y deja de contar en Inicio y en la caja', () async {
    await setCash(true);
    final session = await cash.openSession(businessId: businessId, openingAmount: 0, openedBy: 'Rosa');
    final done = await sales.recordMultiProductSale(businessId: businessId, items: await items({'huevos': 1, 'gaseosa': 2}), paymentMethod: PaymentMethod.cash);
    expect((await HomeRepository.instance.load(businessId)).todayCount, 1);

    await sales.voidSale(done.first, reason: 'Cobro repetido');

    final listed = await sales.getSales(businessId: businessId);
    expect(listed, hasLength(2), reason: 'las dos líneas siguen en el historial');
    expect(listed.every((s) => s.isVoided && s.voidReason == 'Cobro repetido'), isTrue);
    expect((await HomeRepository.instance.load(businessId)).todayTotal, 0);
    expect((await cash.summarize(session)).cashSales, 0);
    expect((await sales.getTodaySummary(businessId))['count'], 0);
    final huevos = await ProductRepository.instance.getProductById('huevos', businessId);
    expect(huevos!.stock, 14, reason: 'el stock volvió');
  });

  test('la cuenta de Vender: suma, no pasa del stock y guarda ventas para después', () async {
    final cart = SellCart.instance;
    final huevos = (await ProductRepository.instance.getProductById('huevos', businessId))!;
    final aceite = (await ProductRepository.instance.getProductById('aceite', businessId))!;
    final arroz = (await ProductRepository.instance.getProductById('arroz', businessId))!;
    expect(cart.add(arroz), contains('no tiene stock'));
    cart.add(huevos);
    cart.add(huevos);
    for (var i = 0; i < 3; i++) {
      cart.add(aceite);
    }
    expect(cart.add(aceite), 'Solo hay 3 de Aceite Premier 1 L');
    expect(cart.units, 5);
    expect(cart.total, 2 * 18900 + 3 * 12900);
    cart.setDiscount(10000); // la ganancia es 16.500
    expect(cart.hasLoss, isFalse);
    cart.setDiscount(20000);
    expect(cart.hasLoss, isTrue, reason: 'el descuento pasa la ganancia');
    cart.hold();
    expect(cart.isEmpty, isTrue);
    expect(cart.held.single.units, 5);
    cart.resume(0);
    expect(cart.units, 5);
    expect(cart.discount, 20000);
  });

  Future<void> loadInter() async {
    final loader = FontLoader('Inter');
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      loader.addFont(rootBundle.load('assets/fonts/inter/Inter-$w.ttf'));
    }
    await loader.load();
  }

  for (final (size, label) in [(const Size(1280, 860), 'computador'), (const Size(390, 844), 'celular')]) {
    for (final brightness in Brightness.values) {
      testWidgets('se ve Vender en el $label (${brightness.name})', (tester) async {
        await tester.runAsync(loadInter);
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.runAsync(() async {
          final huevos = (await ProductRepository.instance.getProductById('huevos', businessId))!;
          final gaseosa = (await ProductRepository.instance.getProductById('gaseosa', businessId))!;
          SellCart.instance
            ..add(huevos)
            ..add(gaseosa)
            ..add(gaseosa);
        });
        final key = GlobalKey();
        await tester.runAsync(() async {
          await tester.pumpWidget(MaterialApp(
            theme: AppTheme.build(brightness),
            home: Scaffold(body: RepaintBoundary(key: key, child: SellScreen(business: business, role: 'OWNER'))),
          ));
          await Future<void>.delayed(const Duration(milliseconds: 600));
        });
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull);
        expect(find.text('Huevos AA x30'), findsWidgets);
        expect(find.text('Sin stock'), findsOneWidget);
        if (label == 'computador') {
          expect(find.text('Cuenta'), findsOneWidget);
          expect(find.textContaining('Cobrar'), findsOneWidget);
          expect(find.text('Nequi'), findsOneWidget);
          expect(find.text('Vuelto'), findsOneWidget);
        } else {
          expect(find.textContaining('3 productos'), findsOneWidget);
        }
        final out = Platform.environment['PREVIEW_OUT'];
        if (out != null) {
          await tester.runAsync(() async {
            final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
            final image = await boundary.toImage();
            final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
            File('$out/vender_${label}_${brightness.name}.png').writeAsBytesSync(bytes!.buffer.asUint8List());
          });
        }
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(minutes: 2));
        SellCart.instance.reset();
      });
    }
  }
}
