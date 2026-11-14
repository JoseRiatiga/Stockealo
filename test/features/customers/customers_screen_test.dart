import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stockealo/core/database/app_database.dart';
import 'package:stockealo/core/services/supabase_service.dart';
import 'package:stockealo/core/theme/app_theme.dart';
import 'package:stockealo/features/auth/data/auth_repository.dart';
import 'package:stockealo/features/auth/models/app_user.dart';
import 'package:stockealo/features/business/models/business.dart';
import 'package:stockealo/features/customers/data/customer_repository.dart';
import 'package:stockealo/features/customers/presentation/screens/customers_screen.dart';

/// Re-diseño 0.13.4 (segunda pasada): Clientes y fiados con cifras en tarjetas,
/// buscador, pestañas y «Nuevo cliente» arriba (sin botón flotante).
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory dbDir;
  const account = 'customers-test';
  const businessId = 'biz-cli';
  final appDb = AppDatabase.instance;
  final now = DateTime(2026, 11, 14, 9);

  Future<void> deleteDbFile() async {
    for (final name in ['stockealo_v2.db', 'stockealo_$account.db']) {
      await databaseFactory.deleteDatabase(p.join(await getDatabasesPath(), name));
    }
  }

  setUpAll(() async {
    dbDir = await Directory.systemTemp.createTemp('stockealo_customers_');
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
    await db.insert('businesses', Business(id: businessId, userId: 'u1', name: 'Tienda Ana', createdAt: now).toMap());
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

  Future<void> save(WidgetTester tester, GlobalKey key, String name) async {
    final out = Platform.environment['PREVIEW_OUT'];
    if (out == null) return;
    await tester.runAsync(() async {
      final image = await (key.currentContext!.findRenderObject()! as RenderRepaintBoundary).toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      File('$out/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  }

  for (final size in const [Size(1200, 900), Size(390, 900)]) {
    testWidgets('Clientes y fiados a ${size.width.toInt()} px', (tester) async {
      await tester.runAsync(() async {
        final repo = CustomerRepository.instance;
        await repo.createCustomer(businessId: businessId, name: 'Carlos Gómez', phone: '3001112233', initialDebt: 45000);
        await repo.createCustomer(businessId: businessId, name: 'Lucía Pérez', phone: '3109998877');
      });
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final key = GlobalKey();
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: RepaintBoundary(key: key, child: const CustomersScreen(businessId: businessId, embedded: true)),
      ));
      // La lista se carga de la base: se deja correr y se dibuja
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(tester.takeException(), isNull);
      expect(find.text('Fiados por cobrar'), findsOneWidget);
      expect(find.text('Con deuda (1)'), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsNothing);
      expect(find.textContaining('Nuevo'), findsOneWidget);
      await save(tester, key, 'clientes_${size.width.toInt()}');

      await tester.tap(find.text('Con deuda (1)'));
      await tester.pump();
      expect(find.text('Carlos Gómez'), findsOneWidget);
      expect(find.text('Lucía Pérez'), findsNothing);
    });
  }
}
