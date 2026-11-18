import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stockealo/core/database/app_database.dart';
import 'package:stockealo/core/services/supabase_service.dart';
import 'package:stockealo/core/theme/app_theme.dart';
import 'package:stockealo/features/business/models/business.dart';
import 'package:stockealo/features/products/models/product.dart';
import 'package:stockealo/features/reports/data/profit_report_repository.dart';
import 'package:stockealo/features/reports/presentation/screens/profit_report_screen.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory dbDir;
  const account = 'report-test';
  const businessId = 'biz-r';
  final appDb = AppDatabase.instance;
  final business = Business(id: businessId, userId: 'u1', name: 'Miscelánea Central', createdAt: DateTime(2026, 10, 1));
  final now = DateTime(2026, 10, 20, 12);

  Future<void> deleteDbFile() async {
    for (final name in ['stockealo_v2.db', 'stockealo_$account.db']) {
      await databaseFactory.deleteDatabase(p.join(await getDatabasesPath(), name));
    }
  }

  var saleCount = 0;
  Future<void> sale(String product, {required double total, required double cost, required DateTime date, int qty = 1, String method = 'EFECTIVO', double discount = 0, String? invoice}) async {
    saleCount++;
    await (await appDb.database).insert('sales', {
      'id': 's$saleCount',
      'business_id': businessId,
      'product_name': product,
      'quantity': qty,
      'date': date.toIso8601String(),
      'total': total,
      'total_cost': cost,
      'net_profit': total - cost,
      'payment_method': method,
      'payment_status': method == 'FIADO' ? 'PENDIENTE' : 'PAGADO',
      'discount_amount': discount,
      'invoice_number': invoice,
      'created_at': date.toIso8601String(),
    });
  }

  setUpAll(() async {
    dbDir = await Directory.systemTemp.createTemp('stockealo_report_');
    await databaseFactory.setDatabasesPath(dbDir.path);
    await SupabaseService.instance.waitForPendingWrites();
    await appDb.useAccount(null);
    await appDb.close();
    await deleteDbFile();
    await appDb.useAccount(account);
    final db = await appDb.database;
    await db.insert('users', {'id': 'u1', 'email': 'dueno@x.com', 'password': authManagedPassword, 'created_at': '2026-10-01'});
    await db.insert('businesses', business.toMap());
    await db.insert(
      'products',
      Product(
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
      ).toMap(),
    );

    // Este mes
    await sale('Arroz', total: 9000, cost: 6000, qty: 3, date: DateTime(2026, 10, 5));
    await sale('Aceite', total: 12000, cost: 8000, date: DateTime(2026, 10, 10), method: 'TRANSFERENCIA', discount: 500);
    await sale('Azúcar', total: 1000, cost: 1500, date: DateTime(2026, 10, 12), method: 'FIADO'); // bajo costo
    // Mes pasado
    await sale('Arroz', total: 6000, cost: 4000, qty: 2, date: DateTime(2026, 9, 15));
    // Agosto: 2 ventas de 3 productos cada una (6 líneas con el mismo comprobante)
    for (final invoice in ['F-1', 'F-2']) {
      for (final product in ['Arroz', 'Aceite', 'Azúcar']) {
        await sale(product, total: 1000, cost: 500, date: DateTime(2026, 8, 3), invoice: invoice);
      }
    }

    // Merma de 2 arroces este mes y un abono de fiado
    await db.insert('stock_movements', {
      'id': 'm1',
      'business_id': businessId,
      'product_id': 'arroz',
      'type': 'MERMA',
      'quantity': 2,
      'resulting_stock': 8,
      'date': DateTime(2026, 10, 15).toIso8601String(),
    });
    await db.insert('customers', {'id': 'c1', 'business_id': businessId, 'name': 'Ana', 'debt_balance': 0, 'created_at': now.toIso8601String()});
    await db.insert('customer_payments', {
      'id': 'p1',
      'business_id': businessId,
      'customer_id': 'c1',
      'amount': 4000,
      'payment_method': 'EFECTIVO',
      'date': DateTime(2026, 10, 18).toIso8601String(),
    });
  });

  tearDownAll(() async {
    await SupabaseService.instance.waitForPendingWrites();
    await appDb.useAccount(null);
    await appDb.close();
    await deleteDbFile();
    if (await dbDir.exists()) await dbDir.delete(recursive: true);
  });

  test('cuenta ventas, no líneas de producto', () async {
    final r = await ProfitReportRepository.instance.buildRange(
      businessId,
      DateTime(2026, 8, 1),
      DateTime(2026, 9, 1),
      prevFrom: DateTime(2026, 7, 1),
      prevTo: DateTime(2026, 8, 1),
    );
    expect(r.salesCount, 2);
    expect(r.revenue, 6000);
  });

  test('devolución, pago mixto y producto renombrado (0.16.4)', () async {
    final db = await appDb.database;
    final at = DateTime(2026, 6, 10, 17).toIso8601String();
    Future<void> row(String id, Map<String, Object?> extra) => db.insert('sales', {
          'id': id,
          'business_id': businessId,
          'quantity': 1,
          'date': at,
          'payment_status': 'PAGADO',
          'invoice_number': 'INV-J',
          'created_at': at,
          ...extra,
        });
    // Venta mixta de Arroz: 1.000 en efectivo y 2.000 por Nequi
    await row('j1', {
      'product_id': 'arroz', 'product_name': 'Arroz viejo', 'total': 3000, 'total_cost': 2000, 'net_profit': 1000,
      'payment_method': 'MIXTO', 'payment_split': '{"EFECTIVO":1000,"NEQUI":2000}',
    });
    // Otra venta del mismo producto, ya con el nombre nuevo
    await row('j2', {
      'product_id': 'arroz', 'product_name': 'Arroz', 'total': 3000, 'total_cost': 2000, 'net_profit': 1000,
      'payment_method': 'EFECTIVO', 'invoice_number': 'INV-K',
    });
    // Devolución de la primera, en efectivo
    await row('j3', {
      'product_id': 'arroz', 'product_name': 'Arroz viejo', 'quantity': -1, 'total': -3000, 'total_cost': -2000,
      'net_profit': -1000, 'payment_method': 'EFECTIVO', 'return_of': 'j1',
    });

    final r = await ProfitReportRepository.instance.buildRange(
      businessId,
      DateTime(2026, 6, 1),
      DateTime(2026, 7, 1),
      prevFrom: DateTime(2026, 5, 1),
      prevTo: DateTime(2026, 6, 1),
    );
    expect(r.belowCostLoss, 0, reason: 'la devolución no es una venta por debajo del costo');
    expect(r.byPaymentMethod.containsKey('MIXTO'), isFalse);
    expect(r.byPaymentMethod['EFECTIVO'], 1000);
    expect(r.byPaymentMethod['NEQUI'], 2000);
    expect(r.topProducts, hasLength(1), reason: 'el producto renombrado es una sola fila');
    expect(r.topProducts.single.name, 'Arroz');
    expect(r.topProducts.single.quantity, 1);
  });

  test('este mes: ventas, costos, mermas, pérdidas y comparación', () async {
    final r = await ProfitReportRepository.instance.build(businessId, ReportPeriod.month, now: now);

    expect(r.salesCount, 3);
    expect(r.revenue, 22000);
    expect(r.cost, 15500);
    expect(r.grossProfit, 6500);
    expect(r.discounts, 500);
    expect(r.belowCostLoss, 500);
    expect(r.shrinkageUnits, 2);
    expect(r.shrinkageLoss, 4000);
    expect(r.netProfit, 2500);
    expect(r.creditPending, 1000);
    expect(r.debtCollected, 4000);
    expect(r.byPaymentMethod, {'TRANSFERENCIA': 12000, 'EFECTIVO': 9000, 'FIADO': 1000});
    // Mes pasado: 2.000 de ganancia bruta → este mes 6.500 = +225 %
    expect(r.previousGrossProfit, 2000);
    expect(r.change, closeTo(225, 0.01));
    expect(r.topProducts.map((p) => p.name), ['Aceite', 'Arroz']);
    expect(r.lowMarginProducts.single.name, 'Azúcar');
  });

  test('mes pasado sin mermas y periodo vacío', () async {
    final last = await ProfitReportRepository.instance.build(businessId, ReportPeriod.lastMonth, now: now);
    expect(last.revenue, 6000);
    expect(last.shrinkageLoss, 0);

    final empty = await ProfitReportRepository.instance.build(businessId, ReportPeriod.today, now: DateTime(2026, 11, 3));
    expect(empty.isEmpty, isTrue);
    expect(empty.change, isNull);
  });

  // 0.16.8 (#43): la ganancia neta resta los gastos de caja que nadie anuló
  test('gastos de caja: restan de la neta; retiros y anulados no', () async {
    final db = await appDb.database;
    Future<void> move(String id, String kind, String reason, double amount, {String? note}) => db.insert('cash_movements', {
          'id': id,
          'business_id': businessId,
          'session_id': 's1',
          'kind': kind,
          'reason': reason,
          'amount': amount,
          'note': note,
          'date': DateTime(2026, 12, 5, 10).toIso8601String(),
        });
    await move('g1', 'SALIDA', 'GASTO', 3000);
    await move('g2', 'SALIDA', 'GASTO', 1000);
    await move('v2', 'ENTRADA', 'ANULA', 1000, note: 'anula:g2');
    await move('r1', 'SALIDA', 'RETIRO', 50000);
    final r = await ProfitReportRepository.instance.buildRange(
      businessId,
      DateTime(2026, 12, 1),
      DateTime(2027, 1, 1),
      prevFrom: DateTime(2026, 11, 1),
      prevTo: DateTime(2026, 12, 1),
    );
    expect(r.cashExpenses, 3000);
    expect(r.netProfit, -3000);
    expect(r.isEmpty, isFalse);
  });

  test('los rangos de cada periodo', () {
    final r = ReportPeriod.lastMonth.range(DateTime(2026, 1, 15));
    expect(r.from, DateTime(2025, 12));
    expect(r.to, DateTime(2026, 1));
    expect(r.prevFrom, DateTime(2025, 11));
    final w = ReportPeriod.week.range(DateTime(2026, 10, 20, 18));
    expect(w.from, DateTime(2026, 10, 14));
    expect(w.to, DateTime(2026, 10, 21));
  });

  testWidgets('la pantalla muestra el resultado del periodo', (tester) async {
    await tester.runAsync(() async {
      final loader = FontLoader('Inter');
      for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
        loader.addFont(rootBundle.load('assets/fonts/inter/Inter-$w.ttf'));
      }
      await loader.load();
    });
    tester.view.physicalSize = const Size(1080, 3600);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final key = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.build(Brightness.light),
      home: RepaintBoundary(key: key, child: ProfitReportScreen(business: business, now: now)),
    ));
    // Las consultas a la base corren fuera del reloj falso de la prueba
    for (var i = 0; i < 20 && find.text('CÓMO SE CALCULA').evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    expect(find.text('CÓMO SE CALCULA'), findsOneWidget);
    expect(find.text('Ganancia neta'), findsOneWidget);

    final out = Platform.environment['PREVIEW_OUT'];
    if (out != null) {
      await tester.runAsync(() async {
        final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        File('$out/profit_report.png').writeAsBytesSync(bytes!.buffer.asUint8List());
      });
    }
  });
}
