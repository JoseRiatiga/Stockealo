import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stockealo/core/database/app_database.dart';
import 'package:stockealo/core/services/supabase_service.dart';
import 'package:stockealo/features/auth/data/auth_repository.dart';
import 'package:stockealo/features/auth/models/app_user.dart';
import 'package:stockealo/features/business/models/business.dart';
import 'package:stockealo/features/products/data/product_repository.dart';
import 'package:stockealo/features/products/models/product.dart';
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
