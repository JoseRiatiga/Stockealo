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
  Future<void> sale(String product, {required double total, required double cost, required DateTime date, int qty = 1, String method = 'EFECTIVO', double discount = 0}) async {
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
