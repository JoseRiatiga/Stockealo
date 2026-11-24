import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stockealo/core/database/app_database.dart';
import 'package:stockealo/core/services/supabase_service.dart';
import 'package:stockealo/features/auth/data/auth_repository.dart';
import 'package:stockealo/features/auth/models/app_user.dart';
import 'package:stockealo/features/business/data/branch_repository.dart';
import 'package:stockealo/features/business/models/business.dart';
import 'package:stockealo/features/business/models/ticket_info.dart';
import 'package:stockealo/features/business/presentation/widgets/branch_form_dialog.dart';
import 'package:stockealo/features/cash/data/cash_register_repository.dart';
import 'package:stockealo/features/products/data/product_repository.dart';
import 'package:stockealo/features/products/models/product.dart';
import 'package:stockealo/features/sales/data/sales_repository.dart';
import 'package:stockealo/features/sales/models/cart_item.dart';
import 'package:stockealo/features/sales/models/payment_method.dart';
import 'package:stockealo/features/suppliers/data/supplier_repository.dart';
import 'package:stockealo/features/suppliers/models/purchase.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory dbDir;
  const account = 'branches-test';
  const businessId = 'biz-sedes';
  const norte = 'sede-norte';
  final appDb = AppDatabase.instance;
  final now = DateTime(2026, 11, 24, 10);
  final business = Business(id: businessId, userId: 'u1', name: 'Lavadero El Sol', createdAt: now);

  Product shampoo() => Product(
        id: 'sha', businessId: businessId, code: 'S1', name: 'Shampoo', category: 'Insumos',
        purchasePrice: 5000, salePrice: 9000, stock: 10, minStock: 2, createdAt: now, updatedAt: now,
      );

  Future<void> deleteDbFile() async {
    for (final name in ['stockealo_v2.db', 'stockealo_$account.db']) {
      await databaseFactory.deleteDatabase(p.join(await getDatabasesPath(), name));
    }
  }

  Future<int> mainStock() async => (await (await appDb.database).query('products', where: 'id = ?', whereArgs: ['sha'])).first['stock'] as int;
  Future<int> norteStock() async => (await BranchRepository.stockIn(norte))['sha']?.stock ?? 0;

  setUpAll(() async {
    dbDir = await Directory.systemTemp.createTemp('stockealo_branches_');
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
    await db.insert('branches', {'id': norte, 'business_id': businessId, 'name': 'Norte', 'status': 'ACTIVE', 'usable': 1, 'created_at': now.toIso8601String()});
    AuthRepository.debugCurrentUser = AppUser(id: 'u1', email: 'ana@x.com', name: 'Ana', createdAt: now);
    await ProductRepository.instance.insertProduct(shampoo());
    await BranchRepository.instance.use(businessId, role: 'OWNER');
  });

  tearDown(() async {
    await BranchRepository.instance.choose(null);
    AuthRepository.debugCurrentUser = null;
  });

  tearDownAll(() async {
    await SupabaseService.instance.waitForPendingWrites();
    await appDb.useAccount(null);
    await appDb.close();
    await deleteDbFile();
    if (await dbDir.exists()) await dbDir.delete(recursive: true);
  });

  test('en una sede extra, vender, anular, devolver, recibir y ajustar no tocan la Principal (0.18.0)', () async {
    final repo = ProductRepository.instance;
    await BranchRepository.instance.choose(norte);
    expect(BranchRepository.active, norte);

    // Entrada de mercancía: 6 a Norte
    await SupplierRepository.instance.registerPurchase(Purchase(
      id: 'e1', businessId: businessId, supplierName: 'El Sol', date: now,
      items: const [PurchaseItem(productId: 'sha', productName: 'Shampoo', quantity: 6, unitCost: 5000)],
      createdAt: now,
    ));
    expect(await norteStock(), 6);
    expect(await mainStock(), 10);

    // La lista muestra el stock de Norte
    expect((await repo.getProductById('sha', businessId))!.stock, 6);

    // Venta de 2 en Norte
    final product = (await repo.getProductById('sha', businessId))!;
    final sales = await SalesRepository.instance.recordMultiProductSale(
      businessId: businessId,
      items: [CartItem(product: product, quantity: 2)],
      paymentMethod: PaymentMethod.cash,
    );
    expect(sales.single.branchId, norte);
    expect(await norteStock(), 4);
    expect(await mainStock(), 10);

    // Devolución de 1: vuelve a Norte
    await SalesRepository.instance.returnSale(sales.single, quantity: 1, restock: true);
    expect(await norteStock(), 5);

    // Anular la venta (con su devolución): Norte vuelve a 6
    await SalesRepository.instance.voidSale(sales.single, reason: 'prueba');
    expect(await norteStock(), 6);
    expect(await mainStock(), 10);

    // Ajuste en Norte
    await repo.adjustStock('sha', businessId, 3, 'Conteo');
    expect(await norteStock(), 3);
    expect(await mainStock(), 10);

    // De vuelta en la Principal todo sigue como antes
    await BranchRepository.instance.choose(null);
    expect((await repo.getProductById('sha', businessId))!.stock, 10);
  });

  test('en la Principal todo funciona como antes y no crea stock de sedes', () async {
    final product = (await ProductRepository.instance.getProductById('sha', businessId))!;
    final sales = await SalesRepository.instance.recordMultiProductSale(
      businessId: businessId,
      items: [CartItem(product: product, quantity: 3)],
      paymentMethod: PaymentMethod.cash,
    );
    expect(sales.single.branchId, isNull);
    expect(await mainStock(), 7);
    expect(await norteStock(), 0);
    final rows = await (await appDb.database).query('branch_stock');
    expect(rows, isEmpty);
  });

  test('los reportes y la caja miran la sede elegida; «Todas las sedes» las suma', () async {
    final db = await appDb.database;
    Future<double> total() async =>
        ((await db.rawQuery('SELECT COALESCE(SUM(total), 0) AS t FROM sales_here WHERE business_id = ?', [businessId])).first['t'] as num)
            .toDouble();
    final product = (await ProductRepository.instance.getProductById('sha', businessId))!;
    await SalesRepository.instance.recordMultiProductSale(
        businessId: businessId, items: [CartItem(product: product, quantity: 1)], paymentMethod: PaymentMethod.cash);
    await BranchRepository.instance.choose(norte);
    await BranchRepository.setStock(db, businessId: businessId, branchId: norte, productId: 'sha', stock: 5);
    final inNorte = (await ProductRepository.instance.getProductById('sha', businessId))!;
    await SalesRepository.instance.recordMultiProductSale(
        businessId: businessId, items: [CartItem(product: inNorte, quantity: 2)], paymentMethod: PaymentMethod.cash);
    expect(await total(), 18000);
    await BranchRepository.instance.choose(null);
    expect(await total(), 9000);
    BranchRepository.instance.setViewAll(true);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(await total(), 27000);
    BranchRepository.instance.setViewAll(false);
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });

  test('el recibo dice la sede solo si el negocio tiene sedes (0.18.1)', () async {
    final repo = BranchRepository.instance;
    // Norte está abierta: la Principal también se nombra
    expect(repo.ticketBranch(null)?.name, 'Principal');
    expect(repo.ticketBranch(norte)?.name, 'Norte');
    // Dirección y teléfono de la sede en lugar de los del negocio; el NIT se queda
    const info = TicketInfo(taxId: '900', address: 'Calle 1', phone: '300');
    final over = const TicketBranch('Norte', address: 'Carrera 9').over(info);
    expect(over.taxId, '900');
    expect(over.address, 'Carrera 9');
    expect(over.phone, '300');
  });

  test('Stock muestra lo que hay en las otras sedes (0.18.1)', () async {
    final db = await appDb.database;
    await BranchRepository.setStock(db, businessId: businessId, branchId: norte, productId: 'sha', stock: 4);
    // Desde la Principal se ve Norte
    expect(await BranchRepository.instance.stockElsewhere(businessId), {'sha': 'Norte 4'});
    // Desde Norte se ve la Principal
    await BranchRepository.instance.choose(norte);
    expect(await BranchRepository.instance.stockElsewhere(businessId), {'sha': 'Principal 10'});
  });

  test('con «Todas las sedes» no se abre caja (0.18.1)', () async {
    BranchRepository.instance.setViewAll(true);
    await expectLater(
      CashRegisterRepository.instance.openSession(businessId: businessId, openingAmount: 0, openedBy: 'Ana'),
      throwsA(isA<Exception>().having((e) => '$e', 'texto', contains('Elige una sede'))),
    );
    BranchRepository.instance.setViewAll(false);
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });

  test('el nombre de una sede no se repite sin importar mayúsculas ni espacios (0.18.1)', () {
    expect(BranchFormDialog.normalize('  Norte   Centro '), 'norte centro');
    expect(BranchFormDialog.normalize('NORTE'), BranchFormDialog.normalize('norte'));
  });
}
