import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockealo/core/theme/app_theme.dart';
import 'package:stockealo/features/products/presentation/screens/product_detail_screen.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stockealo/core/database/app_database.dart';
import 'package:stockealo/core/services/supabase_service.dart';
import 'package:stockealo/features/auth/data/auth_repository.dart';
import 'package:stockealo/features/auth/models/app_user.dart';
import 'package:stockealo/features/business/models/business.dart';
import 'package:stockealo/features/products/data/product_repository.dart';
import 'package:stockealo/features/products/models/product.dart';
import 'package:stockealo/features/products/models/product_variant.dart';
import 'package:stockealo/features/sales/data/sales_repository.dart';
import 'package:stockealo/features/team/data/activity_repository.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory dbDir;
  const account = 'activity-test';
  const businessId = 'biz-act';
  final appDb = AppDatabase.instance;
  final activity = ActivityRepository.instance;
  final now = DateTime(2026, 10, 30);

  Future<void> deleteDbFile() async {
    for (final name in ['stockealo_v2.db', 'stockealo_$account.db']) {
      await databaseFactory.deleteDatabase(p.join(await getDatabasesPath(), name));
    }
  }

  Future<Product> addProduct() async {
    final product = Product(
      id: 'arroz',
      businessId: businessId,
      code: 'A1',
      name: 'Arroz',
      category: 'General',
      purchasePrice: 2000,
      salePrice: 3000,
      stock: 10,
      createdAt: now,
      updatedAt: now,
    );
    await (await appDb.database).insert('products', product.toMap());
    return product;
  }

  setUpAll(() async {
    dbDir = await Directory.systemTemp.createTemp('stockealo_activity_');
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
    await db.insert('businesses', Business(id: businessId, userId: 'u1', name: 'Tienda', createdAt: now).toMap());
    AuthRepository.debugCurrentUser = AppUser(id: 'u1', email: 'Ana@X.com', name: 'Ana', createdAt: now);
  });

  tearDown(() => AuthRepository.debugCurrentUser = null);

  tearDownAll(() async {
    await SupabaseService.instance.waitForPendingWrites();
    await appDb.useAccount(null);
    await appDb.close();
    await deleteDbFile();
    if (await dbDir.exists()) await dbDir.delete(recursive: true);
  });

  test('una venta queda anotada con quién la hizo', () async {
    final product = await addProduct();
    await SalesRepository.instance.recordSale(product: product, quantity: 3, paymentMethod: 'EFECTIVO');

    final entries = await activity.list(businessId);
    expect(entries, hasLength(1));
    final e = entries.single;
    expect(e.action, ActivityAction.sale);
    expect(e.actor, 'Ana');
    expect(e.actorEmail, 'ana@x.com');
    expect(e.summary, startsWith('Vendió 3 × Arroz por'));
    expect(e.summary, contains('(efectivo)'));
  });

  test('cambio de precio y merma', () async {
    final product = await addProduct();
    await ProductRepository.instance.updateProduct(product.copyWith(salePrice: 3500));
    await ProductRepository.instance.adjustStock(product.id, businessId, 8, 'Se dañaron');

    final entries = await activity.list(businessId);
    final actions = entries.map((e) => e.action).toSet();
    expect(actions, containsAll([ActivityAction.priceChange, ActivityAction.shrinkage]));
    final price = entries.firstWhere((e) => e.action == ActivityAction.priceChange);
    expect(price.summary, contains('precio'));
    expect(price.summary, contains('→'));
    final shrink = entries.firstWhere((e) => e.action == ActivityAction.shrinkage);
    expect(shrink.summary, 'Dio de baja 2 × Arroz (queda 8) · Se dañaron');
  });

  test('ajuste por talla y color: el total es la suma de las variantes', () async {
    ProductVariant v(String id, String talla, String color, int stock) => ProductVariant(
          id: id, businessId: businessId, productId: 'blusa', attributeValue: talla,
          attribute2Name: 'Color', attribute2Value: color, stock: stock, createdAt: now, updatedAt: now);
    final product = Product(
      id: 'blusa', businessId: businessId, code: 'B1', name: 'Blusa', category: 'Ropa',
      purchasePrice: 20000, salePrice: 40000, stock: 4, hasVariants: true,
      variants: [v('v1', 'S', 'Rojo', 1), v('v2', 'M', 'Azul', 3)], createdAt: now, updatedAt: now,
    );
    await ProductRepository.instance.insertProduct(product);
    await ProductRepository.instance.adjustVariantStocks(product, {'v1': 5, 'v2': 2}, 'Conteo');

    final saved = await ProductRepository.instance.getProductById('blusa', businessId);
    expect(saved!.stock, 7);
    expect({for (final x in saved.variants) x.id: x.stock}, {'v1': 5, 'v2': 2});
    final entry = (await activity.list(businessId)).firstWhere((e) => e.action == ActivityAction.stockAdjust);
    expect(entry.summary, 'Ajustó Blusa: S · Rojo: 1 → 5, M · Azul: 3 → 2 (queda 7) · Conteo');
  });

  testWidgets('el detalle del producto muestra sus tallas y colores', (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    ProductVariant v(String id, String talla, String color, String hex, int stock) => ProductVariant(
        id: id, businessId: businessId, productId: 'pij', attributeValue: talla, attribute2Name: 'Color',
        attribute2Value: color, colorHex: hex, stock: stock, createdAt: now, updatedAt: now);
    final product = Product(
      id: 'pij', businessId: businessId, code: 'P1', name: 'Pijama', category: 'Ropa',
      purchasePrice: 20000, salePrice: 50000, stock: 3, hasVariants: true,
      variants: [v('a', 'M', 'Rojo', '#C62828', 3), v('b', 'L', 'Azul', '#1565C0', 0)],
      createdAt: now, updatedAt: now,
    );
    await tester.runAsync(() => ProductRepository.instance.insertProduct(product));
    // Se abre como desde la lista: sin variantes cargadas
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.build(Brightness.light),
      home: ProductDetailScreen(product: product.copyWith(variants: const [])),
    ));
    for (var i = 0; i < 20 && find.text('Tallas y colores').evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    expect(find.text('Tallas y colores'), findsOneWidget);
    expect(find.text('Rojo'), findsOneWidget);
    expect(find.text('Agotado'), findsOneWidget);
    expect(find.textContaining('Suma de 2 variantes'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('sin sesión no se anota nada', () async {
    AuthRepository.debugCurrentUser = null;
    await activity.log(businessId: businessId, action: ActivityAction.cashOpen, summary: 'Abrió la caja');
    expect(await activity.list(businessId), isEmpty);
  });

  test('textos largos se recortan al límite de la nube', () async {
    await activity.log(businessId: businessId, action: ActivityAction.productUpdate, summary: 'x' * 400);
    final e = (await activity.list(businessId)).single;
    expect(e.summary.length, 300);
  });
}
