import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stockealo/core/database/app_database.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory dbDir;
  final appDb = AppDatabase.instance;

  setUpAll(() async {
    dbDir = await Directory.systemTemp.createTemp('stockealo_backup_');
    await databaseFactory.setDatabasesPath(dbDir.path);
  });

  setUp(() async {
    await appDb.useAccount(null);
    await appDb.close();
    for (final f in dbDir.listSync()) {
      f.deleteSync(recursive: true);
    }
    await appDb.useAccount('backup-test');
  });

  tearDownAll(() async {
    await appDb.useAccount(null);
    await appDb.close();
    if (await dbDir.exists()) await dbDir.delete(recursive: true);
  });

  Future<List<String>> settingKeys() async =>
      (await (await appDb.database).query('app_settings')).map((r) => r['key'] as String).toList();

  test('exportar y restaurar devuelve los datos del momento del respaldo', () async {
    await appDb.setSetting('marca', 'antes');
    final backup = p.join(dbDir.path, 'respaldo.db');
    await appDb.exportTo(backup);

    await appDb.setSetting('marca', 'después');
    await appDb.restoreFrom(backup);

    expect(await appDb.getSetting('marca'), 'antes');
  });

  test('al restaurar descarta los cambios pendientes y repite la subida inicial', () async {
    final db = await appDb.database;
    await db.insert('pending_sync', {'operation': 'upsert_sale', 'payload': '{}', 'created_at': '2026-10-30'});
    await appDb.setSetting('initial_upload_done', '1');
    final backup = p.join(dbDir.path, 'respaldo.db');
    await appDb.exportTo(backup);

    await appDb.restoreFrom(backup);

    expect(await (await appDb.database).query('pending_sync'), isEmpty);
    expect(await settingKeys(), isNot(contains('initial_upload_done')));
  });

  test('rechaza un archivo que no es un respaldo y deja los datos intactos', () async {
    await appDb.setSetting('marca', 'original');
    final notABackup = File(p.join(dbDir.path, 'foto.db'))..writeAsStringSync('no soy una base de datos');

    await expectLater(appDb.restoreFrom(notABackup.path), throwsA(isA<Exception>()));
    expect(await appDb.getSetting('marca'), 'original');
  });

  test('rechaza una base de SQLite que no es de Stockealo', () async {
    final other = p.join(dbDir.path, 'otra.db');
    final db = await databaseFactory.openDatabase(other);
    await db.execute('CREATE TABLE notas (id INTEGER)');
    await db.close();

    await expectLater(appDb.restoreFrom(other), throwsA(isA<Exception>()));
  });
}
