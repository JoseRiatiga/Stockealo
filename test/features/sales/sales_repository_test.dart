import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stockealo/core/database/app_database.dart';
import 'package:stockealo/core/services/supabase_service.dart';
import 'package:stockealo/features/business/models/business.dart';
import 'package:stockealo/features/products/models/product.dart';
import 'package:stockealo/features/sales/data/sales_repository.dart';
import 'package:stockealo/features/sales/models/cart_item.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  // Carpeta propia por archivo de pruebas: flutter test ejecuta los archivos en paralelo
  late Directory dbDir;
  setUpAll(() async {
    dbDir = await Directory.systemTemp.createTemp('stockealo_sales_');
    await databaseFactory.setDatabasesPath(dbDir.path);
  });
  tearDownAll(() async {
    if (await dbDir.exists()) await dbDir.delete(recursive: true);
  });

  const account = 'sales-test';
  const businessId = 'biz-1';
  final appDb = AppDatabase.instance;
  final repo = SalesRepository.instance;

  // La primera cuenta se queda con el archivo compartido; se borran ambos por si acaso
  Future<void> deleteDbFile() async {
    for (final name in ['stockealo_v2.db', 'stockealo_$account.db']) {
      await databaseFactory.deleteDatabase(p.join(await getDatabasesPath(), name));
    }
  }

  Future<Product> addProduct(String id, {double cost = 600, double price = 1000, int stock = 10}) async {
    final now = DateTime(2026, 10, 30);
    final product = Product(
      id: id,
      businessId: businessId,
      code: 'SKU-$id',
      name: 'Producto $id',
      category: 'General',
      purchasePrice: cost,
      salePrice: price,
      stock: stock,
      createdAt: now,
      updatedAt: now,
    );
    await (await appDb.database).insert('products', product.toMap());
    return product;
  }

  Future<int> stockOf(String productId) async {
    final rows = await (await appDb.database).query('products', where: 'id = ?', whereArgs: [productId]);
    return rows.single['stock'] as int;
  }

  Future<double> debtOf(String name) async {
    final rows = await (await appDb.database).query('customers', where: 'name = ?', whereArgs: [name]);
    return (rows.single['debt_balance'] as num).toDouble();
  }

  setUp(() async {
    // Cada prueba usa un archivo propio y vacío; no toca la base de ninguna cuenta real.
    // Antes se espera a las escrituras a la nube de la prueba anterior, que aún leen la base
    await SupabaseService.instance.waitForPendingWrites();
    await appDb.useAccount(null);
    await appDb.close();
    await deleteDbFile();
    await appDb.useAccount(account);
    final db = await appDb.database;
    await db.insert('users', {
      'id': 'u1',
      'email': 'dueno@x.com',
      'password': authManagedPassword,
      'created_at': '2026-10-01',
    });
    await db.insert(
      'businesses',
      Business(id: businessId, userId: 'u1', name: 'Tienda', createdAt: DateTime(2026, 10, 1)).toMap(),
    );
  });

  tearDownAll(() async {
    await SupabaseService.instance.waitForPendingWrites();
    await appDb.useAccount(null);
    await appDb.close();
    await deleteDbFile();
  });

  group('recordSale', () {
    test('descuenta stock, registra el movimiento y calcula total y ganancia', () async {
      final product = await addProduct('p1');

      final sale = await repo.recordSale(product: product, quantity: 3, paymentMethod: 'EFECTIVO');

      expect(sale.totalAmount, 3000);
      expect(sale.netProfit, 1200);
      expect(await stockOf('p1'), 7);
      final db = await appDb.database;
      final movement = (await db.query('stock_movements')).single;
      expect(movement['type'], 'SALIDA_VENTA');
      expect(movement['resulting_stock'], 7);
      expect((await db.query('sales')).single['payment_status'], 'PAGADO');
    });

    test('rechaza vender más de lo que hay y no cambia nada', () async {
      final product = await addProduct('p1', stock: 2);

      await expectLater(
        repo.recordSale(product: product, quantity: 3, paymentMethod: 'EFECTIVO'),
        throwsA(isA<Exception>()),
      );
      expect(await stockOf('p1'), 2);
      expect(await (await appDb.database).query('sales'), isEmpty);
    });

    test('rechaza un producto agotado', () async {
      final product = await addProduct('p1', stock: 0);

      await expectLater(
        repo.recordSale(product: product, quantity: 1, paymentMethod: 'EFECTIVO'),
        throwsA(isA<Exception>()),
      );
    });

    test('el fiado crea al cliente y acumula su deuda sin importar mayúsculas', () async {
      final product = await addProduct('p1');

      await repo.recordSale(product: product, quantity: 1, paymentMethod: 'FIADO', customerName: 'Ana');
      await repo.recordSale(
        product: product.copyWith(stock: 9),
        quantity: 2,
        paymentMethod: 'FIADO',
        customerName: ' ANA ',
      );

      expect(await debtOf('Ana'), 3000);
      expect(await (await appDb.database).query('customers'), hasLength(1));
      final statuses = (await (await appDb.database).query('sales')).map((s) => s['payment_status']);
      expect(statuses, everyElement('PENDIENTE'));
    });
  });

  group('voidSale', () {
    test('anular repone el stock y descuenta la deuda, y la venta queda en el historial como anulada', () async {
      final product = await addProduct('p1');
      final sale = await repo.recordSale(product: product, quantity: 3, paymentMethod: 'FIADO', customerName: 'Ana');

      await repo.voidSale(sale, reason: 'Se equivocó de producto');

      expect(await stockOf('p1'), 10);
      expect(await debtOf('Ana'), 0);
      final db = await appDb.database;
      final row = (await db.query('sales')).single;
      expect(row['voided_at'], isNotNull);
      expect(row['void_reason'], 'Se equivocó de producto');
      expect(await db.query('sales_ok'), isEmpty, reason: 'una venta anulada no cuenta en los totales');
      // Anular dos veces no repone dos veces
      await repo.voidSale(sale);
      expect(await stockOf('p1'), 10);
      final reversal = (await db.query('stock_movements', where: "type = 'AJUSTE'")).single;
      expect(reversal['resulting_stock'], 10);
    });

    // Hallazgo 63 (0.16.6): anular una venta fiada que ya tuvo una devolución «llegó dañado»
    test('anular después de una devolución sin reponer: stock, deuda y un solo movimiento claro', () async {
      final a = await addProduct('a', price: 1000, stock: 10);
      final sold = await repo.recordMultiProductSale(
        businessId: businessId,
        items: [CartItem(product: a, quantity: 3)],
        paymentMethod: 'FIADO',
        customerName: 'Ana',
      );
      expect(await stockOf('a'), 7);
      expect(await debtOf('Ana'), 3000);

      // Una unidad llegó dañada: se le devuelve la plata, pero no vuelve al inventario
      await repo.returnSale(sold.single, quantity: 1, restock: false, reason: 'Llegó dañado');
      expect(await stockOf('a'), 7);
      expect(await debtOf('Ana'), 2000);

      await repo.voidSale(sold.single, reason: 'Se arrepintió');

      // Vuelven las 2 que tenía el cliente; la dañada no regresa
      expect(await stockOf('a'), 9);
      expect(await debtOf('Ana'), 0, reason: 'no queda debiendo lo que ya se le descontó');
      final db = await appDb.database;
      final moves = await db.query('stock_movements', where: "reason LIKE 'Venta anulada%'");
      expect(moves, hasLength(1), reason: 'un solo movimiento, no +3 y −1');
      expect(moves.single['quantity'], 2);
      expect(moves.single['resulting_stock'], 9);
      expect(moves.single['reason'] as String, contains('vuelven 2'));
    });

    test('anular una venta sin comprobante que ya tuvo devolución: también se anula la devolución', () async {
      final product = await addProduct('p2', stock: 10);
      final sale = await repo.recordSale(product: product, quantity: 3, paymentMethod: 'FIADO', customerName: 'Eva');
      await repo.returnSale(sale, quantity: 1, restock: true);
      expect(await stockOf('p2'), 8);
      expect(await debtOf('Eva'), 2000);

      await repo.voidSale(sale);

      expect(await stockOf('p2'), 10, reason: 'vuelven las 2 que faltaban, no las 3');
      expect(await debtOf('Eva'), 0);
      final db = await appDb.database;
      final active = await db.query('sales', where: 'voided_at IS NULL');
      expect(active, isEmpty, reason: 'la devolución queda anulada con su venta');
    });

    test('una devolución sola no se anula (no se sabe si volvió al inventario)', () async {
      final product = await addProduct('p3', stock: 5);
      final sale = await repo.recordSale(product: product, quantity: 1, paymentMethod: 'EFECTIVO');
      final dev = await repo.returnSale(sale, quantity: 1, restock: false, reason: 'Dañado');
      await expectLater(repo.voidSale(dev), throwsStateError);
      expect(await stockOf('p3'), 4, reason: 'el stock no cambia');
    });
  });

  group('recordMultiProductSale', () {
    test('reparte un descuento fijo en proporción al subtotal de cada producto', () async {
      final a = await addProduct('a', price: 1000);
      final b = await addProduct('b', price: 2000);

      final sales = await repo.recordMultiProductSale(
        businessId: businessId,
        items: [CartItem(product: a, quantity: 2), CartItem(product: b, quantity: 1)],
        paymentMethod: 'EFECTIVO',
        discountAmount: 400,
      );

      // Subtotales 2000 y 2000: el descuento de 400 se reparte 200 y 200
      expect(sales.map((s) => s.totalAmount), [1800, 1800]);
      expect(await stockOf('a'), 8);
      expect(await stockOf('b'), 9);
      final invoices = (await (await appDb.database).query('sales')).map((s) => s['invoice_number']).toSet();
      expect(invoices, hasLength(1));
    });

    test('aplica el descuento porcentual sobre el total del carrito', () async {
      final a = await addProduct('a', price: 1000);

      final sales = await repo.recordMultiProductSale(
        businessId: businessId,
        items: [CartItem(product: a, quantity: 5)],
        paymentMethod: 'EFECTIVO',
        discountPercent: 10,
      );

      expect(sales.single.totalAmount, 4500);
    });

    test('el fiado del carrito suma a la deuda el total ya descontado', () async {
      final a = await addProduct('a', price: 1000);

      await repo.recordMultiProductSale(
        businessId: businessId,
        items: [CartItem(product: a, quantity: 2)],
        paymentMethod: 'FIADO',
        customerName: 'Luis',
        discountAmount: 500,
      );

      expect(await debtOf('Luis'), 1500);
    });

    test('si un producto no alcanza, no se registra ninguna venta del carrito', () async {
      final a = await addProduct('a', stock: 10);
      final b = await addProduct('b', stock: 1);

      await expectLater(
        repo.recordMultiProductSale(
          businessId: businessId,
          items: [CartItem(product: a, quantity: 2), CartItem(product: b, quantity: 5)],
          paymentMethod: 'EFECTIVO',
        ),
        throwsA(isA<Exception>()),
      );
      expect(await stockOf('a'), 10);
      expect(await (await appDb.database).query('sales'), isEmpty);
    });
  });
}
