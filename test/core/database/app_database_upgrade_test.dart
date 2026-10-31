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

  group('upgradeSchema v3 -> v4', () {
    Future<Set<String>> columnsOf(String table) async =>
        (await db.rawQuery('PRAGMA table_info($table)')).map((c) => c['name'] as String).toSet();

    setUp(() async {
      // Esquema de una base antigua, sin las columnas que antes agregaba onOpen
      await db.execute('CREATE TABLE businesses (id TEXT PRIMARY KEY, user_id TEXT, name TEXT, created_at TEXT)');
      await db.execute('CREATE TABLE business_members (id TEXT PRIMARY KEY, business_id TEXT, email TEXT)');
      await db.execute('CREATE TABLE products (id TEXT PRIMARY KEY, business_id TEXT, name TEXT)');
      await db.execute('CREATE TABLE sales (id TEXT PRIMARY KEY, business_id TEXT, total REAL)');
    });

    test('agrega las columnas y tablas que faltan', () async {
      await AppDatabase.upgradeSchema(db, 3, 4);

      expect(await columnsOf('businesses'), containsAll(['is_deleted', 'deleted_at', 'description']));
      expect(await columnsOf('business_members'), contains('name'));
      expect(await columnsOf('products'), contains('has_variants'));
      expect(
        await columnsOf('sales'),
        containsAll(['product_photo_path', 'seller_name', 'invoice_number', 'discount_amount', 'variant_id', 'variant_name']),
      );
      expect(await columnsOf('quotation_items'), containsAll(['variant_id', 'variant_name']));
      expect(await columnsOf('product_variants'), isNotEmpty);
      expect(await columnsOf('app_settings'), isNotEmpty);
    });

    test('se puede ejecutar dos veces sin fallar', () async {
      await AppDatabase.upgradeSchema(db, 3, 4);
      await expectLater(AppDatabase.upgradeSchema(db, 3, 4), completes);
    });
  });

  group('upgradeSchema v6 -> v7', () {
    setUp(() async {
      await db.execute(
        "CREATE TABLE businesses (id TEXT PRIMARY KEY, user_id TEXT, name TEXT, currency TEXT NOT NULL DEFAULT 'COP', created_at TEXT)",
      );
      await db.execute('CREATE TABLE cash_sessions (id TEXT PRIMARY KEY, business_id TEXT NOT NULL)');
      for (final (id, currency) in [('co', 'COP'), ('mx', 'MXN'), ('pe', 'PEN'), ('us', 'USD')]) {
        await db.insert('businesses', {'id': id, 'user_id': 'u1', 'name': id, 'currency': currency, 'created_at': '2026-10-01'});
      }
      await db.insert('cash_sessions', {'id': 's1', 'business_id': 'mx'});
    });

    Future<Map<String, Object?>> business(String id) async =>
        (await db.query('businesses', where: 'id = ?', whereArgs: [id])).single;

    test('deduce el país de la moneda que ya tenía cada negocio', () async {
      await AppDatabase.upgradeSchema(db, 6, 7);

      expect((await business('co'))['country'], 'CO');
      expect((await business('mx'))['country'], 'MX');
      expect((await business('pe'))['country'], 'PE');
      expect((await business('us'))['country'], 'US');
    });

    test('el arqueo queda activo solo en los negocios que ya lo usaron', () async {
      await AppDatabase.upgradeSchema(db, 6, 7);

      expect((await business('mx'))['cash_register_enabled'], 1);
      expect((await business('co'))['cash_register_enabled'], 0);
    });

    test('encola subir a la nube los negocios que conservan el arqueo', () async {
      await AppDatabase.upgradeSchema(db, 6, 7);

      final pending = await db.query('pending_sync');
      expect(pending, hasLength(1));
      expect(pending.single['operation'], 'upsert_business');
      expect(pending.single['payload'] as String, contains('"id":"mx"'));
    });

    test('se puede ejecutar dos veces sin fallar', () async {
      await AppDatabase.upgradeSchema(db, 6, 7);
      await expectLater(AppDatabase.upgradeSchema(db, 6, 7), completes);
    });
  });
}
