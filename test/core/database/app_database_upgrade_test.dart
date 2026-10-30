import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stockealo/core/database/app_database.dart';

void main() {
  sqfliteFfiInit();

  late Database db;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute('''
      CREATE TABLE users (
        id TEXT PRIMARY KEY,
        email TEXT UNIQUE NOT NULL,
        password TEXT NOT NULL,
        name TEXT,
        phone TEXT,
        avatar_path TEXT,
        created_at TEXT NOT NULL
      )
    ''');
  });

  tearDown(() => db.close());

  group('upgradeSchema v2 -> v3', () {
    test('reemplaza los hashes locales por el marcador de Supabase Auth', () async {
      await db.insert('users', {
        'id': 'u1',
        'email': 'a@b.com',
        'password': 'df578f828d33569bcd834ee8d13b27e02236a944cbf6502ed49dd7f2a2f14292',
        'created_at': '2026-10-01',
      });
      await db.insert('users', {
        'id': 'u2',
        'email': 'c@d.com',
        'password': 'texto-plano-antiguo',
        'created_at': '2026-10-01',
      });

      await AppDatabase.upgradeSchema(db, 2, 3);

      final rows = await db.query('users', columns: ['password']);
      expect(rows.map((r) => r['password']), everyElement(authManagedPassword));
    });

    test('borra la sesión local guardada para exigir login con Supabase', () async {
      await db.execute('CREATE TABLE app_settings (key TEXT PRIMARY KEY, value TEXT)');
      await db.insert('app_settings', {'key': 'active_user_id', 'value': 'u1'});
      await db.insert('app_settings', {'key': 'cloud_sync_enabled', 'value': 'true'});

      await AppDatabase.upgradeSchema(db, 2, 3);

      final keys = (await db.query('app_settings')).map((r) => r['key']);
      expect(keys, ['cloud_sync_enabled']);
    });

    test('recuerda el correo de la sesión como dueño del archivo', () async {
      await db.insert('users', {
        'id': 'u1',
        'email': 'Dueno@X.com',
        'password': 'hash',
        'created_at': '2026-10-01',
      });
      await db.execute('CREATE TABLE app_settings (key TEXT PRIMARY KEY, value TEXT)');
      await db.insert('app_settings', {'key': 'active_user_id', 'value': 'u1'});

      await AppDatabase.upgradeSchema(db, 2, 3);

      final rows = await db.query('app_settings', where: 'key = ?', whereArgs: ['db_owner_email']);
      expect(rows.single['value'], 'dueno@x.com');
    });

    test('no falla si app_settings todavía no existe', () async {
      await expectLater(AppDatabase.upgradeSchema(db, 2, 3), completes);
    });
  });
}
