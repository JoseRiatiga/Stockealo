import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stockealo/core/database/app_database.dart';
import 'package:stockealo/core/services/supabase_service.dart';
import 'package:stockealo/features/backup/data/auto_backup_service.dart';
import 'package:stockealo/features/business/models/business.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory dbDir;
  late Directory docsDir;
  const account = 'auto-backup-test';
  final appDb = AppDatabase.instance;
  final auto = AutoBackupService.instance;

  Future<void> deleteDbFile() async {
    for (final name in ['stockealo_v2.db', 'stockealo_$account.db']) {
      await databaseFactory.deleteDatabase(p.join(await getDatabasesPath(), name));
    }
  }

  Future<int> businessCount() async =>
      (await (await appDb.database).rawQuery('SELECT COUNT(*) AS n FROM businesses')).first['n'] as int;

  Future<void> addBusiness(String id) async => (await appDb.database)
      .insert('businesses', Business(id: id, userId: 'u1', name: 'Negocio $id', createdAt: DateTime(2026, 10, 1)).toMap());

  setUpAll(() async {
    dbDir = await Directory.systemTemp.createTemp('stockealo_autobk_db_');
    docsDir = await Directory.systemTemp.createTemp('stockealo_autobk_docs_');
    await databaseFactory.setDatabasesPath(dbDir.path);
    AutoBackupService.baseDirectory = () async => docsDir;
  });

  setUp(() async {
    await SupabaseService.instance.waitForPendingWrites();
    await appDb.useAccount(null);
    await appDb.close();
    await deleteDbFile();
    final folder = Directory(p.join(docsDir.path, 'respaldos'));
    if (await folder.exists()) await folder.delete(recursive: true);
    await appDb.useAccount(account);
    await (await appDb.database)
        .insert('users', {'id': 'u1', 'email': 'dueno@x.com', 'password': authManagedPassword, 'created_at': '2026-10-01'});
  });

  tearDownAll(() async {
    await SupabaseService.instance.waitForPendingWrites();
    await appDb.useAccount(null);
    await appDb.close();
    await deleteDbFile();
    for (final d in [dbDir, docsDir]) {
      if (await d.exists()) await d.delete(recursive: true);
    }
  });

  test('hace una copia al día, no más', () async {
    final day = DateTime(2026, 10, 30, 8);
    expect(await auto.runIfDue(now: day), isTrue);
    expect(await auto.runIfDue(now: day.add(const Duration(hours: 5))), isFalse);
    expect(await auto.runIfDue(now: day.add(const Duration(hours: 21))), isTrue);

    final copies = await auto.list();
    expect(copies, hasLength(2));
    expect(copies.first.date, day.add(const Duration(hours: 21)));
    expect(await auto.lastBackup(), day.add(const Duration(hours: 21)));
  });

  test('guarda solo las últimas 7', () async {
    for (var i = 0; i < 9; i++) {
      await auto.backupNow(now: DateTime(2026, 10, 1 + i, 9));
    }
    final copies = await auto.list();
    expect(copies, hasLength(AutoBackupService.keep));
    expect(copies.first.date, DateTime(2026, 10, 9, 9));
    expect(copies.last.date, DateTime(2026, 10, 3, 9));
  });

  test('apagada no copia', () async {
    await auto.setEnabled(false);
    expect(await auto.runIfDue(now: DateTime(2026, 10, 30)), isFalse);
    expect(await auto.list(), isEmpty);
    await auto.setEnabled(true);
  });

  test('volver a una copia deshace lo que vino después', () async {
    await addBusiness('a');
    await auto.backupNow(now: DateTime(2026, 10, 30, 8));
    await addBusiness('b');
    expect(await businessCount(), 2);

    await auto.restore((await auto.list()).first);
    expect(await businessCount(), 1);
  });

  test('cada cuenta tiene su propia carpeta', () async {
    await auto.backupNow(now: DateTime(2026, 10, 30, 8));
    final copy = (await auto.list()).single;
    expect(p.basename(p.dirname(copy.path)), p.basenameWithoutExtension(appDb.openFile));
  });
}
