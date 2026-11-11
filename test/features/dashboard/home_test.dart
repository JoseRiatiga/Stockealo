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
import 'package:stockealo/features/business/data/business_repository.dart';
import 'package:stockealo/features/business/models/business.dart';
import 'package:stockealo/features/dashboard/data/home_data.dart';
import 'package:stockealo/features/dashboard/presentation/screens/dashboard_screen.dart';

/// Inicio del re-diseño: lo que calcula (cifras del día y «Necesita atención») y
/// cómo se ve en el computador y en el celular, en claro y en oscuro.
/// Con PREVIEW_OUT=<carpeta> guarda una imagen de cada uno.
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory dbDir;
  const account = 'home-test';
  const businessId = 'biz-home';
  final appDb = AppDatabase.instance;
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final business = Business(
    id: businessId,
    userId: 'u1',
    name: 'Variedades Rosita',
    color: '#1E6B4E',
    cashRegisterEnabled: true,
    createdAt: today.subtract(const Duration(days: 90)),
  );

  Future<void> deleteDbFile() async {
    for (final name in ['stockealo_v2.db', 'stockealo_$account.db']) {
      await databaseFactory.deleteDatabase(p.join(await getDatabasesPath(), name));
    }
  }

  var n = 0;
  Map<String, Object?> sale(String product, int qty, double total, DateTime at,
          {String invoice = '', String method = 'EFECTIVO', String? customer}) =>
      {
        'id': 's${n++}',
        'business_id': businessId,
        'product_id': product,
        'product_name': {'p-arroz': 'Arroz Diana 500 g', 'p-aceite': 'Aceite Premier 1 L', 'p-huevos': 'Huevos AA x30'}[product],
        'quantity': qty,
        'customer_id': customer,
        'date': at.toIso8601String(),
        'total': total,
        'total_cost': total * 0.7,
        'net_profit': total * 0.3,
        'payment_method': method,
        'invoice_number': invoice.isEmpty ? null : invoice,
        'created_at': at.toIso8601String(),
      };

  Future<void> seed() async {
    final db = await appDb.database;
    final created = today.subtract(const Duration(days: 60)).toIso8601String();
    Map<String, Object?> product(String id, String name, int stock, int min) => {
          'id': id,
          'business_id': businessId,
          'code': id,
          'name': name,
          'category': 'Despensa',
          'purchase_price': 3100,
          'sale_price': 4200,
          'stock': stock,
          'min_stock': min,
          'created_at': created,
          'updated_at': created,
        };
    await db.insert('products', product('p-arroz', 'Arroz Diana 500 g', 0, 10));
    await db.insert('products', product('p-aceite', 'Aceite Premier 1 L', 3, 10));
    await db.insert('products', product('p-huevos', 'Huevos AA x30', 40, 10));
    // Juan fió hace 40 días y no ha abonado; Marta abonó hace 5 días
    await db.insert('customers', {'id': 'c-juan', 'business_id': businessId, 'name': 'Juan Gómez', 'phone': '3001234567', 'debt_balance': 45000, 'created_at': created});
    await db.insert('customers', {'id': 'c-marta', 'business_id': businessId, 'name': 'Marta Ruiz', 'debt_balance': 20000, 'created_at': created});
    await db.insert('sales', sale('p-huevos', 1, 45000, today.subtract(const Duration(days: 40)), method: 'FIADO', customer: 'c-juan'));
    await db.insert('customer_payments', {
      'id': 'pay1', 'business_id': businessId, 'customer_id': 'c-marta', 'amount': 5000, 'payment_method': 'EFECTIVO',
      'date': today.subtract(const Duration(days: 5)).toIso8601String(),
    });
    // Hoy: dos ventas (una con dos productos); el mismo día de la semana pasada, una
    final morning = today.add(const Duration(hours: 9));
    await db.insert('sales', sale('p-arroz', 2, 8400, morning, invoice: '#A1'));
    await db.insert('sales', sale('p-huevos', 1, 18000, morning, invoice: '#A1'));
    await db.insert('sales', sale('p-arroz', 3, 12600, morning.add(const Duration(hours: 1)), invoice: '#A2'));
    await db.insert('sales', sale('p-aceite', 2, 20000, morning.subtract(const Duration(days: 7)), invoice: '#B1'));
    for (var d = 1; d < 6; d++) {
      await db.insert('sales', sale('p-arroz', 3, 12600, morning.subtract(Duration(days: d)), invoice: '#C$d'));
    }
    // Caja abierta hoy con base de 100.000
    await db.insert('cash_sessions', {
      'id': 'cash1', 'business_id': businessId, 'opened_by': 'Rosa', 'opened_at': today.add(const Duration(hours: 8)).toIso8601String(),
      'opening_amount': 100000,
    });
  }

  setUpAll(() async {
    await initializeDateFormatting('es_CO');
    dbDir = await Directory.systemTemp.createTemp('stockealo_home_');
    await databaseFactory.setDatabasesPath(dbDir.path);
  });

  setUp(() async {
    await SupabaseService.instance.waitForPendingWrites();
    await appDb.useAccount(null);
    await appDb.close();
    await deleteDbFile();
    await appDb.useAccount(account);
    final db = await appDb.database;
    await db.insert('users', {'id': 'u1', 'email': 'rosa@x.com', 'password': authManagedPassword, 'created_at': '2026-10-01'});
    await db.insert('businesses', business.toMap());
    await db.insert('business_members', {
      'id': 'm1', 'business_id': businessId, 'user_id': 'u1', 'email': 'rosa@x.com', 'role': 'OWNER', 'created_at': '2026-10-01',
    });
    AuthRepository.debugCurrentUser = AppUser(id: 'u1', email: 'rosa@x.com', name: 'Rosa Pérez', createdAt: today);
    BusinessRepository.instance.setActiveBusiness(null);
    await seed();
  });

  tearDown(() => AuthRepository.debugCurrentUser = null);

  tearDownAll(() async {
    await SupabaseService.instance.waitForPendingWrites();
    await appDb.useAccount(null);
    await appDb.close();
    await deleteDbFile();
    if (await dbDir.exists()) await dbDir.delete(recursive: true);
  });

  test('cifras del día: una venta es una factura, y se compara con el mismo día de la semana pasada', () async {
    final d = await HomeRepository.instance.load(businessId);
    expect(d.todayCount, 2, reason: '#A1 tiene dos productos y cuenta como una venta');
    expect(d.todayTotal, 39000);
    expect(d.lastWeekSameDay, 20000);
    expect(d.todayChange!.round(), 95);
    expect(d.todayByHour[1], 26400, reason: 'la venta de las 9 a. m. va en la segunda barra');
  });

  test('«Necesita atención»: agotados primero, después fiados vencidos y lo que está por acabarse', () async {
    final d = await HomeRepository.instance.load(businessId);
    expect(d.attention.map((a) => a.kind).toList(), [AttentionKind.outOfStock, AttentionKind.overdueDebt, AttentionKind.lowStock]);
    final arroz = d.attention.first;
    expect(arroz.name, 'Arroz Diana 500 g');
    expect(arroz.soldThisWeek, 20, reason: '5 hoy + 3 en cada uno de los 5 días anteriores');
    final juan = d.attention[1];
    expect(juan.name, 'Juan Gómez');
    expect(juan.neverPaid, isTrue);
    expect(juan.days, 40);
    expect(d.debtTotal, 65000);
    expect(d.debtCustomers, 2);
    expect(d.overdueCustomers, 1, reason: 'Marta abonó hace 5 días');
    expect(d.restockCount, 2);
    expect(d.outOfStockCount, 1);
  });

  test('el gráfico trae 14 días, los días del mes o 12 meses, con hoy marcado', () async {
    final days = await HomeRepository.instance.bars(businessId, HomeRange.days14);
    expect(days, hasLength(14));
    expect(days.last.current, isTrue);
    expect(days.last.total, 39000);
    expect(days.last.count, 2);
    final month = await HomeRepository.instance.bars(businessId, HomeRange.month);
    expect(month, hasLength(now.day));
    final year = await HomeRepository.instance.bars(businessId, HomeRange.year);
    expect(year, hasLength(12));
    expect(year.last.current, isTrue);
  });

  Future<void> loadInter() async {
    final loader = FontLoader('Inter');
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      loader.addFont(rootBundle.load('assets/fonts/inter/Inter-$w.ttf'));
    }
    await loader.load();
  }

  for (final (size, label) in [(const Size(1280, 1300), 'computador'), (const Size(390, 2300), 'celular')]) {
    for (final brightness in Brightness.values) {
      testWidgets('se ve el Inicio en el $label (${brightness.name})', (tester) async {
        await tester.runAsync(loadInter);
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final key = GlobalKey();
        await tester.runAsync(() async {
          await tester.pumpWidget(MaterialApp(
            theme: AppTheme.build(brightness),
            home: Scaffold(
              body: RepaintBoundary(key: key, child: DashboardScreen(userId: 'u1', onLogout: () {}, onNavigateToTab: (_) {})),
            ),
          ));
          await Future<void>.delayed(const Duration(milliseconds: 800));
        });
        await tester.pump(const Duration(milliseconds: 400));
        expect(tester.takeException(), isNull);

        expect(find.text('Hola, Rosa'), findsOneWidget);
        expect(find.text('Ventas de hoy'), findsOneWidget);
        expect(find.text('Necesita atención'), findsOneWidget);
        expect(find.text('Se acabó Arroz Diana 500 g'), findsOneWidget);
        expect(find.textContaining('Juan Gómez debe'), findsOneWidget);
        expect(find.text('Efectivo en caja'), findsOneWidget);
        expect(find.text('Lo más vendido'), findsOneWidget);

        final out = Platform.environment['PREVIEW_OUT'];
        if (out != null) {
          await tester.runAsync(() async {
            final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
            final image = await boundary.toImage();
            final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
            File('$out/inicio_${label}_${brightness.name}.png').writeAsBytesSync(bytes!.buffer.asUint8List());
          });
        }
        // Los servicios de fondo (nube, avisos) dejan temporizadores: se dejan terminar
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(minutes: 2));
      });
    }
  }
}
