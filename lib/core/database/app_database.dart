import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

/// Valor de la columna `users.password` cuando la contraseña la gestiona Supabase Auth.
const String authManagedPassword = 'SUPABASE_AUTH';

/// Archivo compartido de versiones anteriores. Pertenece a la primera cuenta que lo
/// reclama y es también el que se usa mientras no hay sesión.
const String _legacyDbFile = 'stockealo_v2.db';
/// Supabase Auth id de la cuenta dueña de [_legacyDbFile]
const String _ownerAuthIdKey = 'db_owner_auth_id';
/// Correo de quien tenía la sesión abierta al actualizar a v3, para que reclame su archivo
const String _ownerEmailKey = 'db_owner_email';

class AppDatabase {
  static const int _schemaVersion = 6;

  static final AppDatabase instance = AppDatabase._init();
  static Database? _database;
  static String _openFile = _legacyDbFile;

  AppDatabase._init();

  Future<Database> get database async {
    // Puede quedar cerrada por fuera (deleteDatabase, restaurar un respaldo): se reabre
    final db = _database;
    if (db != null && db.isOpen) return db;
    _database = await _initDB(_openFile);
    return _database!;
  }

  /// Aísla los datos locales por cuenta: cada una usa su propio archivo SQLite, así
  /// una cuenta no ve en el dispositivo los negocios de otra y nada se borra al salir.
  /// [authUserId] null vuelve al archivo compartido (sin sesión).
  Future<void> useAccount(String? authUserId, [String? email]) async {
    final file = authUserId == null ? _legacyDbFile : await _fileForAccount(authUserId, email);
    if (file == _openFile && _database?.isOpen == true) return;

    final previous = _database;
    _database = null;
    _openFile = file;
    await previous?.close();
  }

  Future<String> _fileForAccount(String authUserId, String? email) async {
    // openDatabase devuelve la misma instancia si el archivo compartido ya está abierto
    final legacy = await _initDB(_legacyDbFile);
    try {
      final owner = await _readSetting(legacy, _ownerAuthIdKey);
      if (owner != null) return owner == authUserId ? _legacyDbFile : _accountFile(authUserId);

      final ownerEmail = await _readSetting(legacy, _ownerEmailKey);
      final cleanEmail = email?.trim().toLowerCase();
      if (ownerEmail != null && ownerEmail != cleanEmail) return _accountFile(authUserId);

      await legacy.insert(
        'app_settings',
        {'key': _ownerAuthIdKey, 'value': authUserId},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      return _legacyDbFile;
    } finally {
      if (!identical(legacy, _database)) await legacy.close();
    }
  }

  static String _accountFile(String authUserId) => 'stockealo_$authUserId.db';

  /// Archivo SQLite de la cuenta en uso
  @visibleForTesting
  String get openFile => _openFile;

  static Future<String?> _readSetting(Database db, String key) async {
    final res = await db.query('app_settings', where: 'key = ?', whereArgs: [key], limit: 1);
    return res.isNotEmpty ? res.first['value'] as String? : null;
  }

  Future<Database> _initDB(String filePath) async {
    if (kIsWeb) {
      databaseFactory = databaseFactoryFfiWeb;
    } else if (defaultTargetPlatform == TargetPlatform.windows || defaultTargetPlatform == TargetPlatform.linux) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, filePath);

    return await openDatabase(
      path,
      version: _schemaVersion,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
    );
  }

  Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) =>
      upgradeSchema(db, oldVersion, newVersion);

  static const String _createPendingSync = '''
    CREATE TABLE IF NOT EXISTS pending_sync (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      operation TEXT NOT NULL,
      payload TEXT NOT NULL,
      attempts INTEGER NOT NULL DEFAULT 0,
      last_error TEXT,
      created_at TEXT NOT NULL
    )
  ''';

  static const String _createCashSessions = '''
    CREATE TABLE IF NOT EXISTS cash_sessions (
      id TEXT PRIMARY KEY,
      business_id TEXT NOT NULL,
      opened_by TEXT NOT NULL,
      opened_at TEXT NOT NULL,
      opening_amount REAL NOT NULL,
      closed_at TEXT,
      expected_amount REAL,
      counted_amount REAL,
      notes TEXT,
      FOREIGN KEY (business_id) REFERENCES businesses (id) ON DELETE CASCADE
    )
  ''';

  static const String _createAppSettings = '''
    CREATE TABLE IF NOT EXISTS app_settings (
      key TEXT PRIMARY KEY,
      value TEXT
    )
  ''';

  /// Agrega una columna solo si falta (SQLite no tiene ADD COLUMN IF NOT EXISTS)
  static Future<void> _addColumnIfMissing(Database db, String table, String column, String definition) async {
    final columns = await db.rawQuery('PRAGMA table_info($table)');
    // Tabla inexistente (base muy antigua o parcial): no hay nada que completar
    if (columns.isEmpty || columns.any((c) => c['name'] == column)) return;
    await db.execute('ALTER TABLE $table ADD COLUMN $column $definition');
  }

  @visibleForTesting
  static Future<void> upgradeSchema(Database db, int oldVersion, int newVersion) async {
    // Bases muy antiguas no tenían app_settings y algunos pasos la usan
    await db.execute(_createAppSettings);

    if (oldVersion < 2) {
      try {
        await db.execute('ALTER TABLE users ADD COLUMN name TEXT');
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE users ADD COLUMN phone TEXT');
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE users ADD COLUMN avatar_path TEXT');
      } catch (_) {}

      await db.execute('''
        CREATE TABLE IF NOT EXISTS business_members (
          id TEXT PRIMARY KEY,
          business_id TEXT NOT NULL,
          user_id TEXT,
          email TEXT NOT NULL,
          name TEXT,
          role TEXT NOT NULL DEFAULT 'CASHIER',
          status TEXT NOT NULL DEFAULT 'ACTIVE',
          created_at TEXT NOT NULL,
          FOREIGN KEY (business_id) REFERENCES businesses (id) ON DELETE CASCADE
        )
      ''');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_members_biz ON business_members(business_id)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_members_email ON business_members(email)');
    }
    if (oldVersion < 3) {
      // Las credenciales pasan a Supabase Auth: se eliminan los hashes guardados en el dispositivo.
      // La columna se conserva (NOT NULL) con un marcador para no reconstruir la tabla.
      await db.update('users', {'password': authManagedPassword});
      try {
        // Antes de olvidar la sesión, recordar de quién es este archivo (ver useAccount)
        final active = await db.rawQuery('''
          SELECT u.email FROM app_settings s JOIN users u ON u.id = s.value
          WHERE s.key = 'active_user_id'
        ''');
        final email = (active.isNotEmpty ? active.first['email'] as String? : null)?.trim().toLowerCase();
        if (email != null && email.isNotEmpty) {
          await db.insert(
            'app_settings',
            {'key': _ownerEmailKey, 'value': email},
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        await db.delete('app_settings', where: 'key = ?', whereArgs: ['active_user_id']);
      } catch (_) {}
    }
    if (oldVersion < 4 && newVersion >= 4) {
      // Columnas y tablas que antes se agregaban en cada apertura (onOpen) ocultando errores
      await _addColumnIfMissing(db, 'businesses', 'is_deleted', 'INTEGER NOT NULL DEFAULT 0');
      await _addColumnIfMissing(db, 'businesses', 'deleted_at', 'TEXT');
      await _addColumnIfMissing(db, 'businesses', 'description', 'TEXT');
      await _addColumnIfMissing(db, 'business_members', 'name', 'TEXT');
      await _addColumnIfMissing(db, 'products', 'has_variants', 'INTEGER DEFAULT 0');
      for (final column in ['product_photo_path', 'seller_name', 'invoice_number', 'variant_id', 'variant_name']) {
        await _addColumnIfMissing(db, 'sales', column, 'TEXT');
      }
      await _addColumnIfMissing(db, 'sales', 'discount_amount', 'REAL DEFAULT 0.0');

      await db.execute('''
        CREATE TABLE IF NOT EXISTS product_variants (
          id TEXT PRIMARY KEY,
          business_id TEXT NOT NULL,
          product_id TEXT NOT NULL,
          attribute_name TEXT NOT NULL DEFAULT 'Talla',
          attribute_value TEXT NOT NULL,
          sku_or_barcode TEXT,
          stock INTEGER NOT NULL DEFAULT 0,
          additional_price REAL DEFAULT 0.0,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          is_synced INTEGER DEFAULT 0,
          FOREIGN KEY (product_id) REFERENCES products (id) ON DELETE CASCADE
        )
      ''');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_variants_product ON product_variants(product_id)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_variants_barcode ON product_variants(sku_or_barcode)');

      await db.execute('''
        CREATE TABLE IF NOT EXISTS quotations (
          id TEXT PRIMARY KEY,
          business_id TEXT NOT NULL,
          quotation_number TEXT NOT NULL,
          customer_name TEXT,
          customer_phone TEXT,
          total_amount REAL NOT NULL,
          discount_amount REAL NOT NULL DEFAULT 0.0,
          notes TEXT,
          status TEXT NOT NULL DEFAULT 'PENDIENTE',
          valid_until TEXT,
          created_at TEXT NOT NULL,
          seller_name TEXT
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS quotation_items (
          id TEXT PRIMARY KEY,
          quotation_id TEXT NOT NULL,
          product_id TEXT NOT NULL,
          product_name TEXT NOT NULL,
          quantity INTEGER NOT NULL,
          unit_price REAL NOT NULL,
          subtotal REAL NOT NULL,
          variant_id TEXT,
          variant_name TEXT
        )
      ''');
      await _addColumnIfMissing(db, 'quotation_items', 'variant_id', 'TEXT');
      await _addColumnIfMissing(db, 'quotation_items', 'variant_name', 'TEXT');
    }
    if (oldVersion < 5 && newVersion >= 5) {
      // Cola de escrituras pendientes hacia la nube (ver SyncQueue)
      await db.execute(_createPendingSync);
    }
    if (oldVersion < 6 && newVersion >= 6) {
      // Arqueo de caja (turnos con base inicial y conteo al cierre)
      await db.execute(_createCashSessions);
    }
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute(_createAppSettings);
    await db.execute(_createPendingSync);
    await db.execute(_createCashSessions);

    // 1. Tabla de Usuarios (Cuentas)
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

    // 2. Tabla de Empresas / Negocios (vinculadas a usuario)
    await db.execute('''
      CREATE TABLE businesses (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        name TEXT NOT NULL,
        currency TEXT NOT NULL DEFAULT 'COP',
        description TEXT,
        created_at TEXT NOT NULL,
        is_synced INTEGER NOT NULL DEFAULT 0,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        deleted_at TEXT,
        FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
      )
    ''');

    // 2.1 Tabla de Miembros / Empleados por Empresa
    await db.execute('''
      CREATE TABLE business_members (
        id TEXT PRIMARY KEY,
        business_id TEXT NOT NULL,
        user_id TEXT,
        email TEXT NOT NULL,
        name TEXT,
        role TEXT NOT NULL DEFAULT 'CASHIER',
        status TEXT NOT NULL DEFAULT 'ACTIVE',
        created_at TEXT NOT NULL,
        FOREIGN KEY (business_id) REFERENCES businesses (id) ON DELETE CASCADE
      )
    ''');

    // 3. Tabla de Categorías (creadas exclusivamente por el usuario)
    await db.execute('''
      CREATE TABLE categories (
        id TEXT PRIMARY KEY,
        business_id TEXT NOT NULL,
        name TEXT NOT NULL,
        color_hex TEXT,
        FOREIGN KEY (business_id) REFERENCES businesses (id) ON DELETE CASCADE
      )
    ''');

    // 4. Tabla de Productos (aislados por empresa)
    await db.execute('''
      CREATE TABLE products (
        id TEXT PRIMARY KEY,
        business_id TEXT NOT NULL,
        code TEXT NOT NULL,
        name TEXT NOT NULL,
        description TEXT,
        category TEXT NOT NULL,
        purchase_price REAL NOT NULL DEFAULT 0.0,
        sale_price REAL NOT NULL DEFAULT 0.0,
        stock INTEGER NOT NULL DEFAULT 0,
        min_stock INTEGER NOT NULL DEFAULT 5,
        photo_path TEXT,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        is_synced INTEGER NOT NULL DEFAULT 0,
        has_variants INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (business_id) REFERENCES businesses (id) ON DELETE CASCADE
      )
    ''');

    // 4.1 Tabla de Variantes de Producto (Tallas / Colores / Presentaciones)
    await db.execute('''
      CREATE TABLE product_variants (
        id TEXT PRIMARY KEY,
        business_id TEXT NOT NULL,
        product_id TEXT NOT NULL,
        attribute_name TEXT NOT NULL DEFAULT 'Talla',
        attribute_value TEXT NOT NULL,
        sku_or_barcode TEXT,
        stock INTEGER NOT NULL DEFAULT 0,
        additional_price REAL DEFAULT 0.0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        is_synced INTEGER DEFAULT 0,
        FOREIGN KEY (product_id) REFERENCES products (id) ON DELETE CASCADE
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_variants_product ON product_variants(product_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_variants_barcode ON product_variants(sku_or_barcode)');

    // 5. Tabla de Clientes (aislados por empresa)
    await db.execute('''
      CREATE TABLE customers (
        id TEXT PRIMARY KEY,
        business_id TEXT NOT NULL,
        name TEXT NOT NULL,
        phone TEXT,
        address TEXT,
        debt_balance REAL NOT NULL DEFAULT 0.0,
        created_at TEXT NOT NULL,
        is_synced INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (business_id) REFERENCES businesses (id) ON DELETE CASCADE
      )
    ''');

    // 6. Tabla de Ventas (aisladas por empresa)
    await db.execute('''
      CREATE TABLE sales (
        id TEXT PRIMARY KEY,
        business_id TEXT NOT NULL,
        product_id TEXT,
        product_name TEXT NOT NULL,
        product_photo_path TEXT,
        quantity INTEGER NOT NULL DEFAULT 1,
        customer_id TEXT,
        customer_name TEXT,
        date TEXT NOT NULL,
        total REAL NOT NULL,
        total_cost REAL NOT NULL,
        net_profit REAL NOT NULL,
        payment_method TEXT NOT NULL, -- EFECTIVO | TRANSFERENCIA | FIADO
        payment_status TEXT NOT NULL DEFAULT 'PAGADO',
        seller_name TEXT,
        notes TEXT,
        invoice_number TEXT,
        discount_amount REAL DEFAULT 0.0,
        variant_id TEXT,
        variant_name TEXT,
        created_at TEXT NOT NULL,
        is_synced INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (business_id) REFERENCES businesses (id) ON DELETE CASCADE,
        FOREIGN KEY (product_id) REFERENCES products (id) ON DELETE SET NULL,
        FOREIGN KEY (customer_id) REFERENCES customers (id) ON DELETE SET NULL
      )
    ''');

    // 7. Detalle de Ventas
    await db.execute('''
      CREATE TABLE sale_items (
        id TEXT PRIMARY KEY,
        sale_id TEXT NOT NULL,
        product_id TEXT NOT NULL,
        quantity INTEGER NOT NULL,
        unit_price REAL NOT NULL,
        unit_cost REAL NOT NULL,
        subtotal REAL NOT NULL,
        FOREIGN KEY (sale_id) REFERENCES sales (id) ON DELETE CASCADE,
        FOREIGN KEY (product_id) REFERENCES products (id) ON DELETE RESTRICT
      )
    ''');

    // 8. Abonos de Deuda (aislados por empresa)
    await db.execute('''
      CREATE TABLE customer_payments (
        id TEXT PRIMARY KEY,
        business_id TEXT NOT NULL,
        customer_id TEXT NOT NULL,
        sale_id TEXT,
        amount REAL NOT NULL,
        payment_method TEXT NOT NULL,
        date TEXT NOT NULL,
        notes TEXT,
        FOREIGN KEY (business_id) REFERENCES businesses (id) ON DELETE CASCADE,
        FOREIGN KEY (customer_id) REFERENCES customers (id) ON DELETE CASCADE,
        FOREIGN KEY (sale_id) REFERENCES sales (id) ON DELETE SET NULL
      )
    ''');

    // 9. Kardex y Movimientos de Stock (aislados por empresa)
    await db.execute('''
      CREATE TABLE stock_movements (
        id TEXT PRIMARY KEY,
        business_id TEXT NOT NULL,
        product_id TEXT NOT NULL,
        type TEXT NOT NULL,
        quantity INTEGER NOT NULL,
        resulting_stock INTEGER NOT NULL,
        reason TEXT,
        date TEXT NOT NULL,
        FOREIGN KEY (business_id) REFERENCES businesses (id) ON DELETE CASCADE,
        FOREIGN KEY (product_id) REFERENCES products (id) ON DELETE CASCADE
      )
    ''');

    // 10. Tabla de Cotizaciones / Proformas (aisladas por empresa)
    await db.execute('''
      CREATE TABLE quotations (
        id TEXT PRIMARY KEY,
        business_id TEXT NOT NULL,
        quotation_number TEXT NOT NULL,
        customer_name TEXT,
        customer_phone TEXT,
        total_amount REAL NOT NULL,
        discount_amount REAL NOT NULL DEFAULT 0.0,
        notes TEXT,
        status TEXT NOT NULL DEFAULT 'PENDIENTE',
        valid_until TEXT,
        created_at TEXT NOT NULL,
        seller_name TEXT,
        FOREIGN KEY (business_id) REFERENCES businesses (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE quotation_items (
        id TEXT PRIMARY KEY,
        quotation_id TEXT NOT NULL,
        product_id TEXT NOT NULL,
        product_name TEXT NOT NULL,
        quantity INTEGER NOT NULL,
        unit_price REAL NOT NULL,
        subtotal REAL NOT NULL,
        variant_id TEXT,
        variant_name TEXT,
        FOREIGN KEY (quotation_id) REFERENCES quotations (id) ON DELETE CASCADE
      )
    ''');

    // Índices de alto rendimiento
    await db.execute('CREATE INDEX idx_businesses_user ON businesses(user_id)');
    await db.execute('CREATE INDEX idx_products_business ON products(business_id)');
    await db.execute('CREATE INDEX idx_products_code_business ON products(business_id, code)');
    await db.execute('CREATE INDEX idx_products_name_business ON products(business_id, name)');
    await db.execute('CREATE INDEX idx_sales_business ON sales(business_id)');
    await db.execute('CREATE INDEX idx_sales_date_business ON sales(business_id, date)');
    await db.execute('CREATE INDEX idx_customers_business ON customers(business_id)');
    await db.execute('CREATE INDEX idx_members_biz ON business_members(business_id)');
    await db.execute('CREATE INDEX idx_members_email ON business_members(email)');
    await db.execute('CREATE INDEX idx_quotations_biz ON quotations(business_id)');

    // NOTA: NO se inserta ninguna empresa ni categoría por defecto.
    // El usuario crea todo desde cero.
  }

  /// Lee un valor de configuración persistente
  Future<String?> getSetting(String key) async {
    final db = await database;
    final res = await db.query(
      'app_settings',
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (res.isNotEmpty) {
      return res.first['value'] as String?;
    }
    return null;
  }

  /// Guarda o elimina un valor de configuración persistente
  Future<void> setSetting(String key, String? value) async {
    final db = await database;
    if (value == null) {
      await db.delete('app_settings', where: 'key = ?', whereArgs: [key]);
    } else {
      await db.insert(
        'app_settings',
        {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  /// Copia consistente de la base de la cuenta en uso (sirve aunque esté abierta)
  Future<void> exportTo(String destinationPath) async {
    final file = File(destinationPath);
    if (await file.exists()) await file.delete();
    final db = await database;
    await db.execute('VACUUM INTO ?', [destinationPath]);
  }

  /// Reemplaza la base de la cuenta en uso por un respaldo. Valida antes que sea
  /// una base de Stockealo; los cambios pendientes de subir se descartan porque
  /// pertenecen a los datos que se reemplazan.
  Future<void> restoreFrom(String backupPath) async {
    await _validateBackup(backupPath);

    final target = p.join(await getDatabasesPath(), _openFile);
    await close();
    await File(backupPath).copy(target);
    final journal = File('$target-journal');
    if (await journal.exists()) await journal.delete();

    // Al reabrir se aplican las migraciones si el respaldo es de una versión anterior
    final db = await database;
    await db.delete('pending_sync');
    await db.delete('app_settings', where: 'key = ?', whereArgs: ['initial_upload_done']);
  }

  static Future<void> _validateBackup(String path) async {
    Database? backup;
    try {
      backup = await openDatabase(path, readOnly: true, singleInstance: false);
      final tables = (await backup.rawQuery("SELECT name FROM sqlite_master WHERE type = 'table'"))
          .map((r) => r['name'] as String)
          .toSet();
      if (!tables.containsAll(['businesses', 'products', 'sales'])) {
        throw Exception('El archivo no es un respaldo de Stockealo.');
      }
      if (await backup.getVersion() > _schemaVersion) {
        throw Exception('El respaldo es de una versión más nueva de la app. Actualiza Stockealo primero.');
      }
    } on DatabaseException {
      throw Exception('El archivo no es un respaldo de Stockealo.');
    } finally {
      await backup?.close();
    }
  }

  Future<void> close() async {
    final db = _database;
    _database = null;
    await db?.close();
  }
}
