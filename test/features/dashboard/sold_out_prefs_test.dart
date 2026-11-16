import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stockealo/core/database/app_database.dart';
import 'package:stockealo/features/dashboard/data/sold_out_prefs.dart';

/// 0.16.0, fase 7: los interruptores del panel «Resolver» de un agotado
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory dbDir;
  const account = 'sold-out-test';
  final appDb = AppDatabase.instance;

  Future<void> deleteDbFile() async {
    for (final name in ['stockealo_v2.db', 'stockealo_$account.db']) {
      await databaseFactory.deleteDatabase(p.join(await getDatabasesPath(), name));
    }
  }

  setUpAll(() async {
    dbDir = await Directory.systemTemp.createTemp('stockealo_soldout_');
    await databaseFactory.setDatabasesPath(dbDir.path);
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

  test('ocultar en Vender se guarda por negocio y se puede quitar', () async {
    await SoldOutPrefs.setHidden('b1', 'p1', true);
    await SoldOutPrefs.setHidden('b1', 'p2', true);
    expect(await SoldOutPrefs.hidden('b1'), {'p1', 'p2'});
    expect(await SoldOutPrefs.hidden('b2'), isEmpty, reason: 'otro negocio no se ve afectado');
    await SoldOutPrefs.setHidden('b1', 'p1', false);
    expect(await SoldOutPrefs.hidden('b1'), {'p2'});
  });

  test('el recordatorio avisa solo cuando pasan los días', () async {
    final asked = DateTime(2026, 11, 10, 9);
    await SoldOutPrefs.setReminder('b1', 'p1', true, now: asked);
    final map = await SoldOutPrefs.reminders('b1');
    expect(map['p1'], asked);
    expect(SoldOutPrefs.overdueDays(map['p1'], now: asked.add(const Duration(days: 2))), isNull);
    expect(SoldOutPrefs.overdueDays(map['p1'], now: asked.add(const Duration(days: 4))), 4);
    expect(SoldOutPrefs.overdueDays(null), isNull);
    await SoldOutPrefs.setReminder('b1', 'p1', false);
    expect(await SoldOutPrefs.reminders('b1'), isEmpty);
  });
}
