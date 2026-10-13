import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class AppDatabase {
  static final AppDatabase instance = AppDatabase._init();
  static Database? _database;

  AppDatabase._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('stockealo_v2.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux)) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 2,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
      onOpen: (db) async {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS app_settings (
            key TEXT PRIMARY KEY,
            value TEXT
          )
        ''');
        try {
          await db.execute('ALTER TABLE businesses ADD COLUMN is_deleted INTEGER NOT NULL DEFAULT 0');
        } catch (_) {}
        try {
          await db.execute('ALTER TABLE businesses ADD COLUMN deleted_at TEXT');
        } catch (_) {}
        try {
          await db.execute('ALTER TABLE businesses ADD COLUMN description TEXT');
        } catch (_) {}
        try {
          await db.execute('ALTER TABLE business_members ADD COLUMN name TEXT');
        } catch (_) {}
        try {
          await db.execute('ALTER TABLE sales ADD COLUMN product_photo_path TEXT');
        } catch (_) {}
        try {
          await db.execute('ALTER TABLE sales ADD COLUMN seller_name TEXT');
        } catch (_) {}
      },
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
    );
  }

  Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
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
  }

  Future<void> _createDB(Database db, int version) async {
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
        FOREIGN KEY (business_id) REFERENCES businesses (id) ON DELETE CASCADE
      )
    ''');

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

  Future<void> close() async {
    final db = await instance.database;
    db.close();
  }
}
