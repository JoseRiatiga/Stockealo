import 'package:excel/excel.dart';
import 'package:flutter/material.dart' hide Border, BorderStyle;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stockealo/features/business/models/business.dart';
import 'package:stockealo/core/theme/app_theme.dart';
import 'package:stockealo/features/reports/data/report_export_service.dart';
import 'package:stockealo/features/reports/presentation/screens/reports_screen.dart';
import 'package:stockealo/features/suppliers/models/purchase.dart';
import 'package:stockealo/features/auth/data/auth_repository.dart';
import 'package:stockealo/features/auth/models/app_user.dart';
import 'package:stockealo/features/business/data/business_repository.dart';
import 'package:stockealo/features/business/presentation/active_business_scope.dart';

final _biz = Business(id: 'b1', userId: 'u1', name: 'Loliando', createdAt: DateTime(2026, 11, 1));

Future<Database> _db() async {
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
  await db.execute('''CREATE TABLE products (id TEXT PRIMARY KEY, business_id TEXT, code TEXT, name TEXT, category TEXT,
    purchase_price REAL, sale_price REAL, stock INTEGER, min_stock INTEGER, is_active INTEGER, has_variants INTEGER)''');
  await db.execute('''CREATE TABLE product_variants (id TEXT PRIMARY KEY, business_id TEXT, product_id TEXT,
    attribute_value TEXT, attribute2_value TEXT, sku_or_barcode TEXT, stock INTEGER, additional_price REAL)''');
  await db.execute('''CREATE TABLE sales (id TEXT PRIMARY KEY, business_id TEXT, product_name TEXT, variant_name TEXT,
    quantity INTEGER, total REAL, total_cost REAL, net_profit REAL, payment_method TEXT, customer_name TEXT,
    seller_name TEXT, invoice_number TEXT, date TEXT)''');
  await db.execute('''CREATE TABLE customers (id TEXT PRIMARY KEY, business_id TEXT, name TEXT, phone TEXT,
    address TEXT, debt_balance REAL, created_at TEXT)''');
  await db.execute('''CREATE TABLE stock_movements (id TEXT PRIMARY KEY, business_id TEXT, product_id TEXT, type TEXT,
    quantity INTEGER, resulting_stock INTEGER, reason TEXT, date TEXT)''');

  await db.insert('products', {
    'id': 'p1', 'business_id': 'b1', 'code': 'STK-1', 'name': 'Pijama', 'category': 'Ropa',
    'purchase_price': 20000, 'sale_price': 50000, 'stock': 3, 'min_stock': 1, 'is_active': 1, 'has_variants': 1,
  });
  await db.insert('products', {
    'id': 'p2', 'business_id': 'b1', 'code': 'STK-2', 'name': 'Leggins', 'category': 'Ropa',
    'purchase_price': 15000, 'sale_price': 30000, 'stock': 2, 'min_stock': 1, 'is_active': 1, 'has_variants': 0,
  });
  await db.insert('product_variants',
      {'id': 'v1', 'business_id': 'b1', 'product_id': 'p1', 'attribute_value': 'M', 'attribute2_value': 'Rojo', 'stock': 1});
  await db.insert('product_variants',
      {'id': 'v2', 'business_id': 'b1', 'product_id': 'p1', 'attribute_value': 'L', 'attribute2_value': 'Azul', 'stock': 2});
  // Una venta del 5 y otra del 20 de noviembre
  for (final (id, day, total) in const [('s1', 5, 50000.0), ('s2', 20, 30000.0)]) {
    await db.insert('sales', {
      'id': id, 'business_id': 'b1', 'product_name': id == 's1' ? 'Pijama' : 'Leggins',
      'variant_name': id == 's1' ? 'M · Rojo' : null, 'quantity': 1, 'total': total,
      'total_cost': total / 2, 'net_profit': total / 2, 'payment_method': 'EFECTIVO',
      'date': DateTime(2026, 11, day, 10).toIso8601String(),
    });
  }
  await db.insert('customers', {'id': 'c1', 'business_id': 'b1', 'name': 'Ana', 'debt_balance': 12000});
  await db.insert('stock_movements', {
    'id': 'm1', 'business_id': 'b1', 'product_id': 'p1', 'type': 'ENTRADA_COMPRA', 'quantity': 3,
    'resulting_stock': 3, 'reason': 'Inventario inicial', 'date': DateTime(2026, 11, 2).toIso8601String(),
  });
  return db;
}

List<List<String>> _rows(Sheet sheet) => [
      for (final r in sheet.rows) [for (final c in r) c?.value?.toString() ?? ''],
    ];

void main() {
  test('periodos: hoy, semana, mes y fechas elegidas', () {
    final now = DateTime(2026, 11, 8, 15); // domingo
    expect(ReportPeriod.today(now).contains(DateTime(2026, 11, 8, 23)), isTrue);
    expect(ReportPeriod.today(now).contains(DateTime(2026, 11, 9)), isFalse);
    expect(ReportPeriod.thisWeek(now).from, DateTime(2026, 11, 2)); // lunes
    expect(ReportPeriod.thisMonth(now).contains(DateTime(2026, 11, 30, 23)), isTrue);
    final r = ReportPeriod.range(DateTime(2026, 11, 1), DateTime(2026, 11, 10));
    expect(r.contains(DateTime(2026, 11, 10, 22)), isTrue);
    expect(r.fileTag, '2026-11-01_a_2026-11-10');
    expect(ReportPeriod.all.fileTag, '');
  });

  test('un solo Excel con una hoja por parte; el inventario trae tallas y colores', () async {
    final db = await _db();
    final files = await ReportExportService.instance.buildFiles(
      db: db,
      business: _biz,
      sections: ReportSection.values,
      period: ReportPeriod.range(DateTime(2026, 11, 1), DateTime(2026, 11, 10)),
      singleFile: true,
    );
    expect(files.length, 1);
    expect(files.single.name, startsWith('Reporte_completo_Loliando_2026-11-01_a_2026-11-10'));
    final excel = Excel.decodeBytes(files.single.bytes);
    expect(excel.tables.keys, containsAll(['Inventario', 'Ventas', 'Clientes y fiados', 'Movimientos', 'Ganancias']));

    final inv = _rows(excel.tables['Inventario']!);
    expect(inv.length, 1 + 3); // encabezado + 2 variantes del pijama + leggins
    expect(inv.map((r) => r[2]), containsAll(['M · Rojo', 'L · Azul']));

    // Solo la venta del 5 entra en el periodo; la del 20 no
    final sales = _rows(excel.tables['Ventas']!);
    expect(sales.where((r) => r.contains('Pijama')).length, 1);
    expect(sales.where((r) => r.contains('Leggins')), isEmpty);
    expect(sales.firstWhere((r) => r.contains('Pijama'))[3], 'M · Rojo');
    expect(sales.last.first, startsWith('TOTAL'));

    final profit = _rows(excel.tables['Ganancias']!);
    expect(profit[1][0], 'Pijama');
    await db.close();
  });

  test('un archivo por cada parte, con su propio nombre', () async {
    final db = await _db();
    final files = await ReportExportService.instance.buildFiles(
      db: db,
      business: _biz,
      sections: [ReportSection.inventory, ReportSection.sales],
      period: ReportPeriod.all,
      singleFile: false,
    );
    expect(files.length, 2);
    expect(files[0].name, startsWith('Inventario_Loliando_'));
    expect(files[1].name, startsWith('Ventas_Loliando_'));
    // "Todo" incluye las dos ventas
    final sales = _rows(Excel.decodeBytes(files[1].bytes).tables['Ventas']!);
    expect(sales.where((r) => r.contains('Leggins')).length, 1);
    await db.close();
  });

  test('compras del periodo y costo por proveedor', () async {
    final db = await _db();
    await db.execute('''CREATE TABLE purchases (id TEXT PRIMARY KEY, business_id TEXT, supplier_id TEXT, supplier_name TEXT,
      invoice_number TEXT, date TEXT, items TEXT, total REAL, payment_terms TEXT, due_date TEXT, is_paid INTEGER,
      payments TEXT, photo_path TEXT, order_id TEXT, notes TEXT, created_by TEXT, created_at TEXT)''');
    Purchase entry(String id, String supplier, int day, double cost, {bool credit = false}) => Purchase(
          id: id, businessId: 'b1', supplierId: supplier, supplierName: supplier == 's1' ? 'El Sol' : 'La Luna',
          invoiceNumber: 'F-$id', date: DateTime(2026, 11, day), createdAt: DateTime(2026, 11, day),
          paymentTerms: credit ? 'CREDITO' : 'CONTADO', isPaid: !credit, dueDate: credit ? DateTime(2026, 12, 1) : null,
          items: [
            PurchaseItem(productId: 'p1', productName: 'Pijama', variantId: 'v1', variantName: 'M · Rojo', quantity: 2, unitCost: cost),
            PurchaseItem(productId: 'p1', productName: 'Pijama', variantId: 'v2', variantName: 'L · Azul', quantity: 1, unitCost: cost),
          ],
        );
    await db.insert('purchases', entry('a', 's1', 2, 20000).toMap());
    await db.insert('purchases', entry('b', 's1', 6, 22000, credit: true).toMap());
    await db.insert('purchases', entry('c', 's2', 20, 19000).toMap());

    final files = await ReportExportService.instance.buildFiles(
      db: db,
      business: _biz,
      sections: [ReportSection.purchases, ReportSection.supplierCosts],
      period: ReportPeriod.range(DateTime(2026, 11, 1), DateTime(2026, 11, 10)),
      singleFile: true,
    );
    final excel = Excel.decodeBytes(files.single.bytes);

    final compras = _rows(excel.tables['Compras']!);
    // Encabezado + 2 entradas del periodo con 2 renglones cada una + vacía + total
    expect(compras.where((r) => r.contains('Pijama')).length, 4);
    expect(compras.any((r) => r.contains('F-c')), isFalse, reason: 'la del 20 está fuera del periodo');
    expect(compras.firstWhere((r) => r.contains('F-b'))[9], 'Por pagar');
    expect(compras.last.first, startsWith('TOTAL'));
    expect(double.parse(compras.last[10]), 66000);

    // Costos: todas las entradas (no usa periodo); La Luna es la más barata
    final costos = _rows(excel.tables['Costos por proveedor']!);
    expect(costos[1].sublist(0, 2), ['Pijama', 'La Luna']);
    expect(double.parse(costos[1][2]), 19000);
    expect(costos[1][6], 'Sí');
    expect(costos[2].sublist(0, 2), ['Pijama', 'El Sol']);
    expect(double.parse(costos[2][2]), 22000);
    expect(double.parse(costos[2][5]), 2000, reason: 'con El Sol subió de 20.000 a 22.000');
    await db.close();
  });

  for (final (role, sees) in const [('OWNER', true), ('ADMIN', true), ('CASHIER', false)]) {
    testWidgets('la pestaña Reportes con rol $role', (tester) async {
      tester.view.physicalSize = const Size(360, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      AuthRepository.debugCurrentUser = AppUser(id: 'u1', email: 'a@b.com', name: 'Ana', createdAt: DateTime(2026));
      addTearDown(() => AuthRepository.debugCurrentUser = null);
      final notifier = BusinessRepository.instance.activeBusinessNotifier;
      final previous = notifier.value;
      notifier.value = _biz;
      addTearDown(() => notifier.value = previous);

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.build(Brightness.light),
        builder: (context, child) => ActiveBusinessScope(child: child!),
        home: ReportsTab(userRole: role),
      ));
      expect(ReportsTab.allowed(role), sees);
      expect(find.text('1. ¿Qué incluir?'), sees ? findsOneWidget : findsNothing);
      expect(find.text('Solo el dueño o un administrador pueden descargar reportes.'), sees ? findsNothing : findsOneWidget);
      // Es una pestaña: no tiene botón de volver
      expect(find.byType(BackButton), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  for (final width in [360.0, 1200.0]) {
    testWidgets('la pantalla Reportes se ve bien a ${width.toInt()} px', (tester) async {
      tester.view.physicalSize = Size(width, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.build(Brightness.light),
        home: ReportsScreen(
          business: _biz,
          userId: 'u1',
          userEmail: 'a@b.com',
          initial: const {ReportSection.inventory},
        ),
      ));
      expect(find.text('Reportes'), findsOneWidget);
      // Solo inventario: no pide periodo y sale un solo archivo
      expect(find.text('2. Periodo'), findsNothing);
      expect(find.text('Con una sola parte sale un solo archivo.'), findsOneWidget);

      await tester.tap(find.text('Ventas'));
      await tester.pump();
      expect(find.text('2. Periodo'), findsOneWidget);
      expect(find.text('Un archivo con 2 hojas, una por cada parte.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
