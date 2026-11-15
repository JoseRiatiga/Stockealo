import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stockealo/core/database/app_database.dart';
import 'package:stockealo/core/l10n/app_locale.dart';
import 'package:stockealo/core/services/supabase_service.dart';
import 'package:stockealo/core/services/sync_queue.dart';
import 'package:stockealo/core/design/status_pill.dart';
import 'package:stockealo/core/theme/app_theme.dart';
import 'package:stockealo/core/widgets/sync_pill.dart';
import 'package:stockealo/features/business/models/business.dart';
import 'package:stockealo/features/dashboard/presentation/widgets/first_steps_card.dart';
import 'package:stockealo/features/products/presentation/widgets/idle_products_alert.dart';

/// 0.16.0, fase 5: calidad y confianza
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory dbDir;
  const account = 'quality-test';
  const businessId = 'biz-q';
  final appDb = AppDatabase.instance;
  final now = DateTime(2026, 11, 15, 10);
  final business = Business(id: businessId, userId: 'u1', name: 'Variedades Rosita', createdAt: now.subtract(const Duration(days: 5)));

  Future<void> deleteDbFile() async {
    for (final name in ['stockealo_v2.db', 'stockealo_$account.db']) {
      await databaseFactory.deleteDatabase(p.join(await getDatabasesPath(), name));
    }
  }

  Future<void> product(String id, {int stock = 10, double cost = 1000, DateTime? created}) async {
    final at = (created ?? now.subtract(const Duration(days: 90))).toIso8601String();
    await (await appDb.database).insert('products', {
      'id': id, 'business_id': businessId, 'code': id, 'name': 'Producto $id', 'category': 'Granos',
      'purchase_price': cost, 'sale_price': cost * 2, 'stock': stock, 'min_stock': 1, 'created_at': at, 'updated_at': at,
    });
  }

  var n = 0;
  Future<void> sale(String productId, DateTime at) async {
    n++;
    await (await appDb.database).insert('sales', {
      'id': 's$n', 'business_id': businessId, 'product_id': productId, 'product_name': 'X', 'quantity': 1,
      'date': at.toIso8601String(), 'total': 2000, 'total_cost': 1000, 'net_profit': 1000,
      'payment_method': 'EFECTIVO', 'payment_status': 'PAGADO', 'created_at': at.toIso8601String(),
    });
  }

  setUpAll(() async {
    await initializeDateFormatting('es_CO');
    dbDir = await Directory.systemTemp.createTemp('stockealo_quality_');
    await databaseFactory.setDatabasesPath(dbDir.path);
    final loader = FontLoader('Inter');
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      loader.addFont(rootBundle.load('assets/fonts/inter/Inter-$w.ttf'));
    }
    await loader.load();
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
  });

  tearDownAll(() async {
    await SupabaseService.instance.waitForPendingWrites();
    await appDb.useAccount(null);
    await appDb.close();
    await deleteDbFile();
    if (await dbDir.exists()) await dbDir.delete(recursive: true);
  });

  testWidgets('el calendario del sistema sale en español', (tester) async {
    await tester.pumpWidget(MaterialApp(
      locale: AppLocale.locale,
      supportedLocales: AppLocale.supported,
      localizationsDelegates: AppLocale.delegates,
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => showDatePicker(context: context, initialDate: now, firstDate: DateTime(2020), lastDate: DateTime(2030)),
          child: const Text('abrir'),
        ),
      ),
    ));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    expect(find.text('Cancelar'), findsOneWidget);
    expect(find.text('Cancel'), findsNothing, reason: 'ya no sale en inglés');
    expect(find.textContaining('nov'), findsWidgets);
  });

  test('la nube en la barra: qué dice en cada caso', () {
    expect(SyncPill.describe(const SyncStatus()).label, 'Al día');
    expect(SyncPill.describe(const SyncStatus(pending: 3)).label, 'Subiendo 3');
    expect(SyncPill.describe(const SyncStatus(pending: 5, offline: true)).label, 'Sin conexión · 5 por subir');
    expect(SyncPill.describe(const SyncStatus(offline: true)).label, 'Sin conexión');
    final failed = SyncPill.describe(const SyncStatus(failed: 2));
    expect(failed.label, '2 no subieron');
    expect(failed.tone, AppTone.danger);
    expect(SyncPill.describe(const SyncStatus(failed: 1)).label, '1 no subió');
  });

  testWidgets('la pastilla de la nube cabe y no se ve con la nube apagada', (tester) async {
    await tester.pumpWidget(MaterialApp(theme: AppTheme.lightTheme, home: const Scaffold(body: Center(child: SyncPill(cloudEnabled: true)))));
    expect(find.text('Al día'), findsOneWidget);
    await tester.pumpWidget(MaterialApp(theme: AppTheme.lightTheme, home: const Scaffold(body: Center(child: SyncPill(cloudEnabled: false)))));
    expect(find.text('Al día'), findsNothing);
  });

  test('productos quietos: con stock, sin ventas en 30 días y no los nuevos', () async {
    await product('quieto', stock: 4, cost: 5000);
    await product('vende');
    await product('nuevo', created: now.subtract(const Duration(days: 3)));
    await product('agotado', stock: 0);
    await product('viejo-venta');
    await sale('vende', now.subtract(const Duration(days: 2)));
    await sale('viejo-venta', now.subtract(const Duration(days: 45)));
    final idle = await IdleProducts.find(businessId, now: now);
    expect(idle.map((p) => p.id).toSet(), {'quieto', 'viejo-venta'});
    expect(idle.first.id, 'quieto', reason: 'el de más plata quieta va primero');
    expect(idle.first.value, 20000);
    expect(idle.firstWhere((p) => p.id == 'viejo-venta').lastSale, isNotNull);
  });

  Future<void> pump(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(theme: AppTheme.lightTheme, home: Scaffold(body: SingleChildScrollView(child: child))));
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump();
    }
  }

  testWidgets('primeros pasos: muestra lo que falta y se puede esconder', (tester) async {
    await tester.runAsync(() => product('uno'));
    await pump(tester, FirstStepsCard(business: business, storePublished: false, now: now));
    expect(find.text('Primeros pasos · 1 de 5'), findsOneWidget);
    expect(find.text('Haz tu primera venta'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Ya sé usarla'));
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump();
    }
    expect(find.textContaining('Primeros pasos'), findsNothing);
    expect(await tester.runAsync(() => appDb.getSetting(FirstStepsCard.hiddenKey(businessId))), '1');
  });

  testWidgets('primeros pasos no sale en un negocio de hace más de 60 días', (tester) async {
    final old = Business(id: businessId, userId: 'u1', name: 'Viejo', createdAt: now.subtract(const Duration(days: 200)));
    await pump(tester, FirstStepsCard(business: old, storePublished: false, now: now));
    expect(find.textContaining('Primeros pasos'), findsNothing);
  });

  testWidgets('el aviso de productos quietos', (tester) async {
    await tester.runAsync(() => product('quieto', stock: 4, cost: 5000));
    await pump(tester, IdleProductsAlert(business: business, now: now));
    expect(find.text('1 producto sin ventas en 30 días'), findsOneWidget);
    expect(find.textContaining('quietos a costo'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
