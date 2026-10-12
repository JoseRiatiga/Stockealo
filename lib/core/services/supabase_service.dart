import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../database/app_database.dart';

class SyncResult {
  final bool success;
  final int businessesCount;
  final int productsCount;
  final int customersCount;
  final int salesCount;
  final String? errorMessage;

  const SyncResult({
    required this.success,
    this.businessesCount = 0,
    this.productsCount = 0,
    this.customersCount = 0,
    this.salesCount = 0,
    this.errorMessage,
  });
}

class SupabaseService {
  SupabaseService._();
  static final SupabaseService instance = SupabaseService._();

  static const String supabaseUrl = 'https://evdwwmkafwjyfawsufjb.supabase.co';
  static const String supabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImV2ZHd3bWthZndqeWZhd3N1ZmpiIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTE3OTE0MTYsImV4cCI6MjEwNzM2NzQxNn0.frOJQKnpqXI-ssLtcRxtVgvrDPYeMVZ4grExaQwmeZQ';

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  SupabaseClient? get client {
    if (!_isInitialized) return null;
    return Supabase.instance.client;
  }

  Future<bool> initialize() async {
    try {
      // ignore: deprecated_member_use
      await Supabase.initialize(
        url: supabaseUrl,
        // ignore: deprecated_member_use
        anonKey: supabaseAnonKey,
      );
      _isInitialized = true;
      debugPrint('Supabase inicializado correctamente.');
      return true;
    } catch (e) {
      debugPrint('Error al inicializar Supabase: $e');
      _isInitialized = false;
      return false;
    }
  }

  /// Verifica la conexión con el servidor de Supabase
  Future<Map<String, dynamic>> testConnection() async {
    try {
      if (!_isInitialized) {
        final ok = await initialize();
        if (!ok) {
          return {
            'success': false,
            'message': 'No se pudo inicializar el cliente de Supabase.',
          };
        }
      }

      // Consulta de prueba a la tabla businesses
      final response = await client!.from('businesses').select().limit(1);
      return {
        'success': true,
        'message': '¡Conexión establecida con éxito! Supabase está en línea y las tablas responden.',
        'data': response,
      };
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST205' || e.message.contains('schema cache')) {
        return {
          'success': false,
          'needsTables': true,
          'message':
              'Conexión exitosa al servidor, pero las tablas aún no están creadas en Supabase. Debes ejecutar el script SQL en el SQL Editor de Supabase.',
        };
      }
      return {
        'success': false,
        'message': 'Error de Supabase: ${e.message}',
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Error al conectar con Supabase: $e',
      };
    }
  }

  /// Sincroniza todos los datos locales de SQLite hacia Supabase
  Future<SyncResult> syncToCloud() async {
    try {
      if (!_isInitialized) {
        final ok = await initialize();
        if (!ok) {
          return const SyncResult(
            success: false,
            errorMessage: 'Supabase no está inicializado.',
          );
        }
      }

      final db = await AppDatabase.instance.database;

      // 1. Sincronizar Businesses
      final localBusinesses = await db.query(
        'businesses',
        where: 'is_deleted = 0',
      );
      if (localBusinesses.isNotEmpty) {
        final formattedBusinesses = localBusinesses.map((b) => {
          'id': b['id'],
          'name': b['name'],
          'type': (b['type'] ?? 'Comercio General').toString(),
          'currency': b['currency'] ?? 'COP',
          'is_deleted': (b['is_deleted'] as int?) ?? 0,
          'created_at': b['created_at'],
        }).toList();

        await client!.from('businesses').upsert(
          formattedBusinesses,
          onConflict: 'id',
        );
      }

      // 2. Sincronizar Products
      // Primero eliminar de Supabase los productos que fueron eliminados localmente (is_active = 0)
      final inactiveProducts = await db.query('products', where: 'is_active = 0');
      if (inactiveProducts.isNotEmpty) {
        final inactiveIds = inactiveProducts.map((p) => p['id'] as String).toList();
        await client!.from('products').delete().inFilter('id', inactiveIds);
      }

      // Luego sincronizar únicamente los productos activos (is_active = 1)
      final localProducts = await db.query('products', where: 'is_active = 1');
      if (localProducts.isNotEmpty) {
        final formattedProducts = localProducts.map((p) => {
          'id': p['id'],
          'business_id': p['business_id'],
          'name': p['name'],
          'sku': p['code'] ?? '',
          'category': p['category'] ?? 'General',
          'cost_price': (p['purchase_price'] as num?)?.toDouble() ?? 0.0,
          'sale_price': (p['sale_price'] as num?)?.toDouble() ?? 0.0,
          'current_stock': (p['stock'] as num?)?.toInt() ?? 0,
          'min_stock_alert': (p['min_stock'] as num?)?.toInt() ?? 5,
          'image_url': p['photo_path'],
          'created_at': p['created_at'],
        }).toList();

        await client!.from('products').upsert(
          formattedProducts,
          onConflict: 'id',
        );
      }

      // 3. Sincronizar Customers
      final localCustomers = await db.query('customers');
      if (localCustomers.isNotEmpty) {
        final formattedCustomers = localCustomers.map((c) => {
          'id': c['id'],
          'business_id': c['business_id'],
          'name': c['name'],
          'phone': c['phone'],
          'address': c['address'],
          'debt_balance': (c['debt_balance'] as num?)?.toDouble() ?? 0.0,
          'created_at': c['created_at'],
        }).toList();

        await client!.from('customers').upsert(
          formattedCustomers,
          onConflict: 'id',
        );
      }

      // 4. Sincronizar Sales
      final localSales = await db.query('sales');
      if (localSales.isNotEmpty) {
        final formattedSales = localSales.map((s) => {
          'id': s['id'],
          'business_id': s['business_id'],
          'product_id': s['product_id'],
          'quantity': (s['quantity'] as num?)?.toInt() ?? 1,
          'unit_price': (s['unit_price'] as num?)?.toDouble() ?? 0.0,
          'unit_cost': (s['unit_cost'] as num?)?.toDouble() ?? 0.0,
          'total_amount': (s['total_amount'] as num?)?.toDouble() ?? 0.0,
          'payment_method': s['payment_method'] ?? 'Efectivo',
          'customer_id': null,
          'sale_date': s['date'] ?? DateTime.now().toIso8601String(),
        }).toList();

        await client!.from('sales').upsert(
          formattedSales,
          onConflict: 'id',
        );
      }

      return SyncResult(
        success: true,
        businessesCount: localBusinesses.length,
        productsCount: localProducts.length,
        customersCount: localCustomers.length,
        salesCount: localSales.length,
      );
    } on PostgrestException catch (e) {
      return SyncResult(
        success: false,
        errorMessage: 'Error en Supabase: ${e.message}',
      );
    } catch (e) {
      return SyncResult(
        success: false,
        errorMessage: 'Error al sincronizar: $e',
      );
    }
  }

  /// Elimina un producto de Supabase inmediatamente
  Future<void> deleteProductFromCloud(String productId) async {
    try {
      if (!_isInitialized) await initialize();
      await client?.from('products').delete().eq('id', productId);
      debugPrint('Producto \$productId eliminado de Supabase con éxito.');
    } catch (e) {
      debugPrint('Error al eliminar producto en Supabase: \$e');
    }
  }

  /// Crea o actualiza un producto en Supabase inmediatamente
  Future<void> upsertProductToCloud(Map<String, dynamic> p) async {
    try {
      if (!_isInitialized) await initialize();
      await client?.from('products').upsert({
        'id': p['id'],
        'business_id': p['business_id'],
        'name': p['name'],
        'sku': p['code'] ?? '',
        'category': p['category'] ?? 'General',
        'cost_price': (p['purchase_price'] as num?)?.toDouble() ?? 0.0,
        'sale_price': (p['sale_price'] as num?)?.toDouble() ?? 0.0,
        'current_stock': (p['stock'] as num?)?.toInt() ?? 0,
        'min_stock_alert': (p['min_stock'] as num?)?.toInt() ?? 5,
        'image_url': p['photo_path'],
        'created_at': p['created_at'],
      }, onConflict: 'id');
    } catch (e) {
      debugPrint('Error al guardar producto en Supabase: \$e');
    }
  }

  /// Registra una venta en Supabase inmediatamente
  Future<void> insertSaleToCloud(Map<String, dynamic> s) async {
    try {
      if (!_isInitialized) await initialize();
      await client?.from('sales').insert({
        'id': s['id'],
        'business_id': s['business_id'],
        'product_id': s['product_id'],
        'quantity': (s['quantity'] as num?)?.toInt() ?? 1,
        'unit_price': (s['unit_price'] as num?)?.toDouble() ?? 0.0,
        'unit_cost': (s['unit_cost'] as num?)?.toDouble() ?? 0.0,
        'total_amount': (s['total_amount'] as num?)?.toDouble() ?? 0.0,
        'payment_method': s['payment_method'] ?? 'Efectivo',
        'customer_id': null,
        'sale_date': s['date'] ?? DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('Error al insertar venta en Supabase: \$e');
    }
  }

  /// Script SQL listo para crear las tablas
  static const String sqlSetupScript = '''
-- 1. Tabla de Empresas
CREATE TABLE IF NOT EXISTS businesses (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    type TEXT NOT NULL,
    currency TEXT NOT NULL DEFAULT 'COP',
    is_deleted INTEGER NOT NULL DEFAULT 0,
    deleted_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 2. Tabla de Miembros del Negocio / Equipo
CREATE TABLE IF NOT EXISTS business_members (
    id TEXT PRIMARY KEY,
    business_id TEXT REFERENCES businesses(id) ON DELETE CASCADE,
    user_id TEXT NOT NULL,
    user_email TEXT NOT NULL,
    user_name TEXT NOT NULL,
    role TEXT NOT NULL DEFAULT 'CASHIER',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 3. Tabla de Productos
CREATE TABLE IF NOT EXISTS products (
    id TEXT PRIMARY KEY,
    business_id TEXT REFERENCES businesses(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    sku TEXT NOT NULL,
    category TEXT NOT NULL DEFAULT 'General',
    cost_price NUMERIC(12, 2) NOT NULL DEFAULT 0,
    sale_price NUMERIC(12, 2) NOT NULL,
    current_stock INTEGER NOT NULL DEFAULT 0,
    min_stock_alert INTEGER NOT NULL DEFAULT 5,
    image_url TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 4. Tabla de Clientes y Fiados
CREATE TABLE IF NOT EXISTS customers (
    id TEXT PRIMARY KEY,
    business_id TEXT REFERENCES businesses(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    phone TEXT,
    address TEXT,
    debt_balance NUMERIC(12, 2) NOT NULL DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 5. Tabla de Ventas
CREATE TABLE IF NOT EXISTS sales (
    id TEXT PRIMARY KEY,
    business_id TEXT REFERENCES businesses(id) ON DELETE CASCADE,
    product_id TEXT REFERENCES products(id) ON DELETE SET NULL,
    quantity INTEGER NOT NULL,
    unit_price NUMERIC(12, 2) NOT NULL,
    unit_cost NUMERIC(12, 2) NOT NULL DEFAULT 0,
    total_amount NUMERIC(12, 2) NOT NULL,
    payment_method TEXT NOT NULL DEFAULT 'Efectivo',
    customer_id TEXT REFERENCES customers(id) ON DELETE SET NULL,
    sale_date TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Desactivar RLS temporalmente para acceso directo de prueba
ALTER TABLE businesses DISABLE ROW LEVEL SECURITY;
ALTER TABLE business_members DISABLE ROW LEVEL SECURITY;
ALTER TABLE products DISABLE ROW LEVEL SECURITY;
ALTER TABLE customers DISABLE ROW LEVEL SECURITY;
ALTER TABLE sales DISABLE ROW LEVEL SECURITY;
''';
}
