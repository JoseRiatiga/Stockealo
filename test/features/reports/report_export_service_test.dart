import 'package:excel/excel.dart';
import 'package:flutter/material.dart' hide Border, BorderStyle;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stockealo/features/business/models/business.dart';
import 'package:stockealo/core/theme/app_theme.dart';
import 'package:stockealo/features/reports/data/report_export_service.dart';
import 'package:stockealo/features/reports/presentation/screens/reports_screen.dart';

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
