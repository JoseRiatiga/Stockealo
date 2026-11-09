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

  group('upgradeSchema v8 -> v9', () {
    setUp(() async {
      await db.execute('CREATE TABLE products (id TEXT PRIMARY KEY, has_variants INTEGER DEFAULT 0)');
      await db.execute('''
        CREATE TABLE product_variants (
          id TEXT PRIMARY KEY, business_id TEXT, product_id TEXT,
          attribute_name TEXT, attribute_value TEXT, stock INTEGER
        )
      ''');
    });

    test('agrega talla y color y vuelve a mostrar las variantes perdidas', () async {
      // La descarga de la nube había dejado este producto sin la marca de variantes
      await db.insert('products', {'id': 'p1', 'has_variants': 0});
      await db.insert('products', {'id': 'p2', 'has_variants': 0});
      await db.insert('product_variants', {'id': 'v1', 'product_id': 'p1', 'attribute_value': 'M (ROJO)', 'stock': 1});

      await AppDatabase.upgradeSchema(db, 8, 9);

      final columns = (await db.rawQuery('PRAGMA table_info(product_variants)')).map((c) => c['name']).toSet();
      expect(columns, containsAll(['attribute2_name', 'attribute2_value', 'color_hex', 'color_hex2']));
      final flags = {
        for (final r in await db.query('products')) r['id']: r['has_variants'],
      };
      expect(flags, {'p1': 1, 'p2': 0});
    });

    test('se puede ejecutar dos veces sin fallar', () async {
      await AppDatabase.upgradeSchema(db, 8, 9);
      await expectLater(AppDatabase.upgradeSchema(db, 8, 9), completes);
    });
  });

  group('upgradeSchema v9 -> v10', () {
    test('agrega proveedores, entradas y el proveedor del producto sin tocar lo demás', () async {
      await db.execute('CREATE TABLE products (id TEXT PRIMARY KEY, name TEXT)');
      await db.insert('products', {'id': 'p1', 'name': 'Arroz'});

      await AppDatabase.upgradeSchema(db, 9, 10);
      await expectLater(AppDatabase.upgradeSchema(db, 9, 10), completes);

      final columns = (await db.rawQuery('PRAGMA table_info(products)')).map((c) => c['name']).toSet();
      expect(columns, contains('supplier_id'));
      expect((await db.query('products')).single['name'], 'Arroz');
      expect(await db.query('suppliers'), isEmpty);
      expect(await db.query('purchases'), isEmpty);
    });
  });

  group('upgradeSchema v10 -> v11', () {
    test('agrega servicios, empleados, tablero y columnas de servicio en ventas', () async {
      await db.execute("CREATE TABLE businesses (id TEXT PRIMARY KEY, name TEXT)");
      await db.execute('CREATE TABLE sales (id TEXT PRIMARY KEY, product_id TEXT, total REAL)');
      await db.insert('businesses', {'id': 'b1', 'name': 'Lavadero'});
      await db.insert('sales', {'id': 's1', 'product_id': 'p1', 'total': 1000});

      await AppDatabase.upgradeSchema(db, 10, 11);
      await expectLater(AppDatabase.upgradeSchema(db, 10, 11), completes);

      Future<Set<Object?>> cols(String t) async => (await db.rawQuery('PRAGMA table_info($t)')).map((c) => c['name']).toSet();
      expect(await cols('businesses'), containsAll(['services_enabled', 'service_type']));
      expect(await cols('sales'), containsAll(['service_id', 'work_order_id', 'staff_ids']));
      expect((await db.query('businesses')).single['services_enabled'], 0);
      expect((await db.query('sales')).single['total'], 1000);
      expect(await db.query('work_orders'), isEmpty);
    });
  });
}
