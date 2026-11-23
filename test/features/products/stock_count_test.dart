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
import 'package:stockealo/features/products/data/stock_count.dart';
import 'package:stockealo/features/products/models/product.dart';
import 'package:stockealo/features/products/models/product_variant.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory dbDir;
  const account = 'count-test';
  const businessId = 'biz-count';
  final appDb = AppDatabase.instance;
  final now = DateTime(2026, 11, 22);
  final business = Business(id: businessId, userId: 'u1', name: 'La Esquina', createdAt: now);

  Product arroz({int stock = 10}) => Product(
        id: 'arroz', businessId: businessId, code: 'A1', name: 'Arroz', category: 'Granos',
        purchasePrice: 3000, salePrice: 4500, stock: stock, minStock: 2, createdAt: now, updatedAt: now,
      );

  ProductVariant variant(String id, String talla, int stock) => ProductVariant(
      id: id, businessId: businessId, productId: 'cam', attributeValue: talla, stock: stock, createdAt: now, updatedAt: now);

  Product camisa() => Product(
        id: 'cam', businessId: businessId, code: 'C1', name: 'Camisa', category: 'Ropa',
        purchasePrice: 20000, salePrice: 40000, stock: 5, minStock: 1, hasVariants: true,
        variants: [variant('s', 'S', 2), variant('m', 'M', 3)],
        createdAt: now, updatedAt: now,
      );

  Future<void> deleteDbFile() async {
    for (final name in ['stockealo_v2.db', 'stockealo_$account.db']) {
      await databaseFactory.deleteDatabase(p.join(await getDatabasesPath(), name));
    }
  }

  setUpAll(() async {
    dbDir = await Directory.systemTemp.createTemp('stockealo_count_');
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

  test('vacío no es cero y el resumen da lo que sobró y faltó a costo (0.17.0)', () {
    final count = StockCount(businessId: businessId, startedAt: now);
    final a = arroz();
    count.set(a, 7);
    expect(count.lines['arroz']!.diff, -3);
    count.set(a, null);
    expect(count.lines, isEmpty);
    count.set(a, 12);
    final c = camisa();
    count.set(c, 2, variantId: 's');
    count.set(c, 1, variantId: 'm');
    final s = count.summary({'arroz': a, 'cam': c});
    expect(s.surplusUnits, 2);
    expect(s.surplusValue, 6000);
    expect(s.missingUnits, 2);
    expect(s.missingValue, 40000);
    expect(s.withDifference, 2);
    expect(count.reason, 'Conteo del 22/11/2026');
  });

  test('el borrador se guarda y vuelve; al aplicar respeta lo vendido mientras tanto', () async {
    final repo = ProductRepository.instance;
    await repo.insertProduct(arroz());
    await repo.insertProduct(camisa());

    final count = StockCount(businessId: businessId, startedAt: now);
    count.set(arroz(), 8); // faltan 2
    count.set(camisa(), 4, variantId: 'm'); // sobra 1 de la M
    count.addOne(arroz()); // con el lector: 9
    await count.save();

    final back = (await StockCount.load(businessId))!;
    expect(back.countedOf('arroz'), 9);
    expect(back.countedOf('cam', 'm'), 4);

    // Mientras se contaba se vendió 1 arroz: quedaban 9 en la app
    await repo.adjustStock('arroz', businessId, 9, 'Venta');
    expect(await back.apply(), 2);

    expect((await repo.getProductById('arroz', businessId))!.stock, 8);
    final variants = await repo.getVariantsForProduct('cam');
    expect(variants.firstWhere((v) => v.id == 'm').stock, 4);
    expect(variants.firstWhere((v) => v.id == 's').stock, 2);
    expect((await repo.getProductById('cam', businessId))!.stock, 6);

    final db = await appDb.database;
    final moves = await db.query('stock_movements', where: 'reason LIKE ?', whereArgs: ['Conteo del 22/11/2026%']);
    expect(moves, hasLength(2));
    expect(await StockCount.load(businessId), isNull);
    expect(back.lines, isEmpty);
  });

  test('una venta de otro celular antes de contar no se descuenta dos veces', () async {
    final repo = ProductRepository.instance;
    await repo.insertProduct(arroz());
    final count = StockCount(businessId: businessId, startedAt: now);
    // La app decía 10; otro celular vendió 3 y la pantalla se puso al día antes de contar
    await repo.adjustStock('arroz', businessId, 7, 'Venta');
    final fresh = (await repo.getProductById('arroz', businessId))!;
    count.set(fresh, 7);
    expect(count.lines['arroz']!.diff, 0);
    expect(await count.apply(), 0);
    expect((await repo.getProductById('arroz', businessId))!.stock, 7);
  });
}
