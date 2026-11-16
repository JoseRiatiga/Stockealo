import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stockealo/core/app_version.dart';
import 'package:stockealo/core/database/app_database.dart';
import 'package:stockealo/core/theme/app_theme.dart';
import 'package:stockealo/features/home/presentation/widgets/where_things_moved_sheet.dart';
import 'package:stockealo/features/home/presentation/widgets/whats_new_sheet.dart';

/// 0.16.0, fase 7: «Novedades» y «Lo nuevo»
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory dbDir;
  const account = 'whats-new-test';
  final appDb = AppDatabase.instance;

  Future<void> deleteDbFile() async {
    for (final name in ['stockealo_v2.db', 'stockealo_$account.db']) {
      await databaseFactory.deleteDatabase(p.join(await getDatabasesPath(), name));
    }
  }

  setUpAll(() async {
    dbDir = await Directory.systemTemp.createTemp('stockealo_whatsnew_');
    await databaseFactory.setDatabasesPath(dbDir.path);
    final loader = FontLoader('Inter');
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      loader.addFont(rootBundle.load('assets/fonts/inter/Inter-$w.ttf'));
    }
    await loader.load();
  });

  setUp(() async {
    await appDb.useAccount(null);
    await appDb.close();
    await deleteDbFile();
    await appDb.useAccount(account);
    await appDb.database;
  });

  tearDownAll(() async {
    await appDb.useAccount(null);
    await appDb.close();
    await deleteDbFile();
    if (await dbDir.exists()) await dbDir.delete(recursive: true);
  });

  test('la versión de esta app tiene sus novedades escritas', () {
    expect(WhatsNewSheet.entryFor(kAppVersion), isNotNull, reason: 'al publicar, agrega la versión a WhatsNewSheet.entries');
    final versions = WhatsNewSheet.entries.map((e) => e.version).toList();
    expect(versions.toSet().length, versions.length, reason: 'sin versiones repetidas');
  });

  Future<void> pumpHost(WidgetTester tester, String version) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(onPressed: () => WhatsNewSheet.showOnce(context, version: version), child: const Text('abrir')),
        ),
      ),
    ));
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('«Lo nuevo» sale una sola vez a quien ya usaba la app', (tester) async {
    await tester.runAsync(() => appDb.setSetting(WhereThingsMovedSheet.pendingKey, '1'));
    await pumpHost(tester, '0.16.0');
    await tester.tap(find.text('abrir'));
    await settle(tester);
    expect(find.text('Lo nuevo en Stockealo 0.16.0'), findsOneWidget);
    expect(find.textContaining('PIN o huella'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Entendido'));
    await settle(tester);
    await tester.tap(find.text('abrir'));
    await settle(tester);
    expect(find.text('Lo nuevo en Stockealo 0.16.0'), findsNothing, reason: 'ya la vio');
  });

  testWidgets('a quien recién se registra no le sale', (tester) async {
    await pumpHost(tester, '0.16.0');
    await tester.tap(find.text('abrir'));
    await settle(tester);
    expect(find.text('Lo nuevo en Stockealo 0.16.0'), findsNothing);
    expect(await tester.runAsync(() => appDb.getSetting(WhatsNewSheet.seenKey)), '0.16.0');
  });
}
