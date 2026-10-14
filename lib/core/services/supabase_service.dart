import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../database/app_database.dart';
import 'package:sqflite/sqflite.dart';

class SyncResult {
  final bool success;
  final int businessesCount;
  final int productsCount;
  final int customersCount;
  final int salesCount;
  final int membersCount;
  final String? errorMessage;

  const SyncResult({
    required this.success,
    this.businessesCount = 0,
    this.productsCount = 0,
    this.customersCount = 0,
    this.salesCount = 0,
    this.membersCount = 0,
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

  /// Comprueba si el usuario tiene activada la sincronización en la nube (False por defecto = Local-First)
  Future<bool> isCloudSyncEnabled() async {
    final val = await AppDatabase.instance.getSetting('cloud_sync_enabled');
    return val == 'true';
  }

  /// Activa o desactiva la sincronización en la nube
  Future<void> setCloudSyncEnabled(bool enabled) async {
    await AppDatabase.instance.setSetting('cloud_sync_enabled', enabled ? 'true' : 'false');
  }

  /// Sincroniza todos los datos locales de SQLite hacia Supabase
  Future<SyncResult> syncToCloud() async {
    try {
      // 1. Verificar si el usuario tiene activada la sincronización en la nube
      if (!(await isCloudSyncEnabled())) {
        return const SyncResult(
          success: true,
          errorMessage: 'Modo Local Privado activo. Sincronización en la nube desactivada.',
        );
      }

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

      // 0. Sincronizar Usuarios (Cuentas)
      try {
        final localUsers = await db.query('users');
        if (localUsers.isNotEmpty) {
          final formattedUsers = localUsers.map((u) => {
            'id': u['id'],
            'email': u['email'],
            'password': u['password'],
            'name': u['name'],
            'phone': u['phone'],
            'avatar_path': u['avatar_path'],
            'created_at': u['created_at'],
          }).toList();

          await client!.from('users').upsert(
            formattedUsers,
            onConflict: 'id',
          );
        }
      } catch (e) {
        debugPrint('Nota: error o tabla users no configurada en Supabase: $e');
      }

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

      // 1.1 Sincronizar Categories
      try {
        final localCategories = await db.query('categories');
        if (localCategories.isNotEmpty) {
          final formattedCategories = localCategories.map((c) => {
            'id': c['id'],
            'business_id': c['business_id'],
            'name': c['name'],
            'color_hex': c['color_hex'] ?? '0xFF059669',
          }).toList();

          await client!.from('categories').upsert(
            formattedCategories,
            onConflict: 'id',
          );
        }
      } catch (e) {
        debugPrint('Nota: error o tabla categories no configurada en Supabase: $e');
      }

      // 1.2 Sincronizar Miembros de Equipos (business_members)
      int localMembersCount = 0;
      try {
        final localMembers = await db.query('business_members');
        if (localMembers.isNotEmpty) {
          final formattedMembers = localMembers.map((m) {
            final email = (m['email'] ?? '').toString();
            final rawUserId = m['user_id'] as String?;
            final memberName = (m['name'] as String?)?.trim();
            return {
              'id': m['id'],
              'business_id': m['business_id'],
              'user_id': (rawUserId != null && rawUserId.trim().isNotEmpty) ? rawUserId.trim() : '',
              'user_email': email,
              'user_name': (memberName != null && memberName.isNotEmpty)
                  ? memberName
                  : (email.isNotEmpty ? email.split('@').first : 'Colaborador'),
              'role': m['role'] ?? 'CASHIER',
              'created_at': m['created_at'] ?? DateTime.now().toIso8601String(),
            };
          }).toList();

          await client!.from('business_members').upsert(
            formattedMembers,
            onConflict: 'id',
          );
          localMembersCount = formattedMembers.length;
        }
      } catch (e) {
        debugPrint('Nota: error o tabla business_members no configurada en Supabase: $e');
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
        final List<Map<String, dynamic>> formattedProducts = [];
        for (final p in localProducts) {
          String? imageUrl = p['photo_path'] as String?;
          if (imageUrl != null && imageUrl.isNotEmpty && !imageUrl.startsWith('http')) {
            final uploadedUrl = await uploadProductImage(
              businessId: p['business_id'] as String,
              productId: p['id'] as String,
              localFilePath: imageUrl,
            );
            if (uploadedUrl != null) {
              imageUrl = uploadedUrl;
              await db.update(
                'products',
                {'photo_path': uploadedUrl},
                where: 'id = ?',
                whereArgs: [p['id']],
              );
            }
          }

          formattedProducts.add({
            'id': p['id'],
            'business_id': p['business_id'],
            'name': p['name'],
            'sku': p['code'] ?? '',
            'category': p['category'] ?? 'General',
            'cost_price': (p['purchase_price'] as num?)?.toDouble() ?? 0.0,
            'sale_price': (p['sale_price'] as num?)?.toDouble() ?? 0.0,
            'current_stock': (p['stock'] as num?)?.toInt() ?? 0,
            'min_stock_alert': (p['min_stock'] as num?)?.toInt() ?? 5,
            'image_url': imageUrl,
            'created_at': p['created_at'],
          });
        }

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
        final formattedSales = localSales.map((s) {
          final qty = (s['quantity'] as num?)?.toInt() ?? 1;
          final totalAmount = (s['total'] as num?)?.toDouble() ?? (s['total_amount'] as num?)?.toDouble() ?? 0.0;
          final totalCost = (s['total_cost'] as num?)?.toDouble() ?? 0.0;
          final unitPrice = qty > 0 ? (totalAmount / qty) : 0.0;
          final unitCost = qty > 0 ? (totalCost / qty) : 0.0;

          return {
            'id': s['id'],
            'business_id': s['business_id'],
            'product_id': s['product_id'],
            'product_name': s['product_name'],
            'quantity': qty,
            'unit_price': unitPrice,
            'unit_cost': unitCost,
            'total_amount': totalAmount,
            'payment_method': s['payment_method'] ?? 'Efectivo',
            'customer_id': s['customer_id'],
            'customer_name': s['customer_name'],
            'sale_date': s['date'] ?? s['created_at'] ?? DateTime.now().toIso8601String(),
          };
        }).toList();

        try {
          await client!.from('sales').upsert(
            formattedSales,
            onConflict: 'id',
          );
        } catch (e) {
          if (e.toString().contains('product_name') ||
              e.toString().contains('customer_name') ||
              e.toString().contains('42703')) {
            final fallbackSales = formattedSales.map((m) {
              final copy = Map<String, dynamic>.from(m);
              copy.remove('product_name');
              copy.remove('customer_name');
              return copy;
            }).toList();
            await client!.from('sales').upsert(
              fallbackSales,
              onConflict: 'id',
            );
          } else {
            rethrow;
          }
        }
      }

      return SyncResult(
        success: true,
        businessesCount: localBusinesses.length,
        productsCount: localProducts.length,
        customersCount: localCustomers.length,
        salesCount: localSales.length,
        membersCount: localMembersCount,
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

  /// Descarga todos los datos desde Supabase hacia la base de datos local SQLite
  Future<SyncResult> syncFromCloud(String userId, [String? userEmail]) async {
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
      int businessesCount = 0;
      int productsCount = 0;
      int customersCount = 0;
      int salesCount = 0;

      // 1. Descargar Empresas
      try {
        final List<dynamic> cloudBusinesses = await client!
            .from('businesses')
            .select()
            .eq('is_deleted', 0);

        for (final b in cloudBusinesses) {
          final existing = await db.query('businesses', where: 'id = ?', whereArgs: [b['id']], limit: 1);
          final existingUserId = existing.isNotEmpty ? existing.first['user_id'] as String? : null;

          await db.insert(
            'businesses',
            {
              'id': b['id'],
              'user_id': b['user_id'] ?? existingUserId ?? 'remote_owner',
              'name': b['name'],
              'currency': b['currency'] ?? 'COP',
              'is_deleted': (b['is_deleted'] as int?) ?? 0,
              'deleted_at': b['deleted_at'],
              'created_at': b['created_at'] ?? DateTime.now().toIso8601String(),
              'is_synced': 1,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          businessesCount++;
        }
      } catch (e) {
        debugPrint('Error descargando empresas de Supabase: $e');
      }

      // 1.1 Descargar Categorías
      try {
        final List<dynamic> cloudCategories = await client!.from('categories').select();
        for (final c in cloudCategories) {
          await db.insert(
            'categories',
            {
              'id': c['id'],
              'business_id': c['business_id'],
              'name': c['name'],
              'color_hex': c['color_hex'] ?? '0xFF059669',
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      } catch (e) {
        debugPrint('Error descargando categorías de Supabase: $e');
      }

      // 1.2 Descargar Miembros de equipo
      int membersCount = 0;
      try {
        final List<dynamic> cloudMembers = await client!.from('business_members').select();
        for (final m in cloudMembers) {
          final rawUserId = m['user_id'] as String?;
          final memberEmail = (m['user_email'] ?? m['email'] ?? '').toString().trim().toLowerCase();
          String? resolvedUserId = (rawUserId != null && rawUserId.trim().isNotEmpty) ? rawUserId.trim() : null;
          if (resolvedUserId == null && userEmail != null && memberEmail == userEmail.trim().toLowerCase()) {
            resolvedUserId = userId;
          }
          final memberRole = (m['role'] ?? 'CASHIER').toString().toUpperCase();
          final memberName = m['user_name'] ?? m['name'] ?? memberEmail.split('@').first;
          await db.insert(
            'business_members',
            {
              'id': m['id'],
              'business_id': m['business_id'],
              'user_id': resolvedUserId,
              'email': memberEmail,
              'name': memberName,
              'role': memberRole,
              'status': 'ACTIVE',
              'created_at': m['created_at'] ?? DateTime.now().toIso8601String(),
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );

          // Si el miembro descargado es OWNER, asegurar que el negocio local reconozca a este dueño auténtico
          if (memberRole == 'OWNER') {
            final ownerIdToSet = resolvedUserId ?? rawUserId;
            if (ownerIdToSet != null && ownerIdToSet.trim().isNotEmpty) {
              await db.update(
                'businesses',
                {'user_id': ownerIdToSet.trim()},
                where: 'id = ?',
                whereArgs: [m['business_id']],
              );
            }
          }
          membersCount++;
        }
      } catch (e) {
        debugPrint('Error descargando miembros de Supabase: $e');
      }

      // 2. Descargar Productos
      try {
        final List<dynamic> cloudProducts = await client!.from('products').select();
        for (final p in cloudProducts) {
          await db.insert(
            'products',
            {
              'id': p['id'],
              'business_id': p['business_id'],
              'code': p['sku'] ?? '',
              'name': p['name'],
              'description': p['description'],
              'category': p['category'] ?? 'General',
              'purchase_price': (p['cost_price'] as num?)?.toDouble() ?? 0.0,
              'sale_price': (p['sale_price'] as num?)?.toDouble() ?? 0.0,
              'stock': (p['current_stock'] as num?)?.toInt() ?? 0,
              'min_stock': (p['min_stock_alert'] as num?)?.toInt() ?? 5,
              'photo_path': p['image_url'],
              'is_active': 1,
              'created_at': p['created_at'] ?? DateTime.now().toIso8601String(),
              'updated_at': p['created_at'] ?? DateTime.now().toIso8601String(),
              'is_synced': 1,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          productsCount++;
        }
      } catch (e) {
        debugPrint('Error descargando productos de Supabase: $e');
      }

      // 3. Descargar Clientes
      try {
        final List<dynamic> cloudCustomers = await client!.from('customers').select();
        for (final c in cloudCustomers) {
          await db.insert(
            'customers',
            {
              'id': c['id'],
              'business_id': c['business_id'],
              'name': c['name'],
              'phone': c['phone'],
              'address': c['address'],
              'debt_balance': (c['debt_balance'] as num?)?.toDouble() ?? 0.0,
              'created_at': c['created_at'] ?? DateTime.now().toIso8601String(),
              'is_synced': 1,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          customersCount++;
        }
      } catch (e) {
        debugPrint('Error descargando clientes de Supabase: $e');
      }

      // 4. Descargar Ventas
      try {
        final List<dynamic> cloudSales = await client!.from('sales').select();
        for (final s in cloudSales) {
          final qty = (s['quantity'] as num?)?.toInt() ?? 1;
          final unitCost = (s['unit_cost'] as num?)?.toDouble() ?? 0.0;
          final unitPrice = (s['unit_price'] as num?)?.toDouble() ?? 0.0;
          var totalAmount = (s['total_amount'] as num?)?.toDouble() ?? (s['total'] as num?)?.toDouble() ?? 0.0;
          if (totalAmount <= 0.0 && unitPrice > 0.0) {
            totalAmount = unitPrice * qty;
          }

          // Resolver nombre del producto y precios de respaldo desde SQLite si faltan
          String prodName = (s['product_name'] as String?)?.trim() ?? '';
          final prodId = s['product_id'] as String?;
          var calcTotalCost = unitCost * qty;

          if (prodId != null) {
            final prodRows = await db.query(
              'products',
              columns: ['name', 'sale_price', 'purchase_price'],
              where: 'id = ?',
              whereArgs: [prodId],
              limit: 1,
            );
            if (prodRows.isNotEmpty) {
              if (prodName.isEmpty || prodName.toLowerCase() == 'producto') {
                final foundName = prodRows.first['name'] as String?;
                if (foundName != null && foundName.trim().isNotEmpty) {
                  prodName = foundName.trim();
                }
              }
              if (totalAmount <= 0.0) {
                final fallbackSalePrice = (prodRows.first['sale_price'] as num?)?.toDouble() ?? 0.0;
                totalAmount = fallbackSalePrice * qty;
              }
              if (calcTotalCost <= 0.0) {
                final fallbackCostPrice = (prodRows.first['purchase_price'] as num?)?.toDouble() ?? 0.0;
                calcTotalCost = fallbackCostPrice * qty;
              }
            }
          }
          if (prodName.isEmpty) prodName = 'Producto';

          // Resolver nombre del cliente si está referenciado
          String? custName = (s['customer_name'] as String?)?.trim();
          final custId = s['customer_id'] as String?;
          if ((custName == null || custName.isEmpty) && custId != null) {
            final custRows = await db.query('customers', columns: ['name'], where: 'id = ?', whereArgs: [custId], limit: 1);
            if (custRows.isNotEmpty) {
              custName = custRows.first['name'] as String?;
            }
          }

          await db.insert(
            'sales',
            {
              'id': s['id'],
              'business_id': s['business_id'],
              'product_id': prodId,
              'product_name': prodName,
              'quantity': qty,
              'customer_id': custId,
              'customer_name': custName,
              'date': s['sale_date'] ?? DateTime.now().toIso8601String(),
              'total': totalAmount,
              'total_cost': calcTotalCost,
              'net_profit': totalAmount - calcTotalCost,
              'payment_method': s['payment_method'] ?? 'Efectivo',
              'payment_status': 'PAGADO',
              'notes': s['notes'],
              'created_at': s['sale_date'] ?? DateTime.now().toIso8601String(),
              'is_synced': 1,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          salesCount++;
        }
      } catch (e) {
        debugPrint('Error descargando ventas de Supabase: $e');
      }

      return SyncResult(
        success: true,
        businessesCount: businessesCount,
        productsCount: productsCount,
        customersCount: customersCount,
        salesCount: salesCount,
        membersCount: membersCount,
      );
    } catch (e) {
      return SyncResult(
        success: false,
        errorMessage: 'Error al descargar datos: $e',
      );
    }
  }

  /// Elimina un producto de Supabase inmediatamente
  Future<void> deleteProductFromCloud(String productId) async {
    try {
      if (!(await isCloudSyncEnabled())) return;
      if (!_isInitialized) await initialize();
      await client?.from('products').delete().eq('id', productId);
      debugPrint('Producto $productId eliminado de Supabase con éxito.');
    } catch (e) {
      debugPrint('Error al eliminar producto en Supabase: $e');
    }
  }

  /// Sube la imagen del producto a Supabase Storage (bucket: product-images) y retorna la URL pública
  Future<String?> uploadProductImage({
    required String businessId,
    required String productId,
    required String localFilePath,
  }) async {
    try {
      if (!_isInitialized) await initialize();
      if (client == null) return null;

      final file = File(localFilePath);
      if (!await file.exists()) return null;

      final extension = localFilePath.toLowerCase().endsWith('.png') ? 'png' : 'jpg';
      final storagePath = '$businessId/$productId.$extension';

      await client!.storage.from('product-images').upload(
        storagePath,
        file,
        fileOptions: FileOptions(
          upsert: true,
          contentType: extension == 'png' ? 'image/png' : 'image/jpeg',
        ),
      );

      final publicUrl = client!.storage.from('product-images').getPublicUrl(storagePath);
      final urlWithTimestamp = '$publicUrl?t=${DateTime.now().millisecondsSinceEpoch}';
      return urlWithTimestamp;
    } catch (e) {
      debugPrint('Error al subir imagen a Supabase Storage: $e');
      return null;
    }
  }

  /// Crea o actualiza un producto en Supabase inmediatamente
  Future<void> upsertProductToCloud(Map<String, dynamic> p) async {
    try {
      if (!(await isCloudSyncEnabled())) return;
      if (!_isInitialized) await initialize();

      String? imageUrl = p['photo_path'] as String?;

      // Si tiene una imagen local almacenada en el dispositivo, subirla a Supabase Storage
      if (imageUrl != null && imageUrl.isNotEmpty && !imageUrl.startsWith('http')) {
        final uploadedUrl = await uploadProductImage(
          businessId: p['business_id'] as String,
          productId: p['id'] as String,
          localFilePath: imageUrl,
        );
        if (uploadedUrl != null) {
          imageUrl = uploadedUrl;
          final db = await AppDatabase.instance.database;
          await db.update(
            'products',
            {'photo_path': uploadedUrl},
            where: 'id = ?',
            whereArgs: [p['id']],
          );
        }
      }

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
        'image_url': imageUrl,
        'created_at': p['created_at'],
      }, onConflict: 'id');
    } catch (e) {
      debugPrint('Error al guardar producto en Supabase: $e');
    }
  }

  /// Registra una venta en Supabase inmediatamente
  Future<void> insertSaleToCloud(Map<String, dynamic> s) async {
    try {
      if (!(await isCloudSyncEnabled())) return;
      if (!_isInitialized) await initialize();

      final total = (s['total_amount'] as num?)?.toDouble() ??
          (s['total'] as num?)?.toDouble() ??
          0.0;
      final qty = (s['quantity'] as num?)?.toInt() ?? 1;
      final unitPrice = (s['unit_price'] as num?)?.toDouble() ??
          (qty > 0 ? total / qty : 0.0);
      final totalCost = (s['total_cost'] as num?)?.toDouble() ?? 0.0;
      final unitCost = (s['unit_cost'] as num?)?.toDouble() ??
          (qty > 0 ? totalCost / qty : 0.0);

      final payload = {
        'id': s['id'],
        'business_id': s['business_id'],
        'product_id': s['product_id'],
        'product_name': s['product_name'],
        'quantity': qty,
        'unit_price': unitPrice,
        'unit_cost': unitCost,
        'total_amount': total,
        'payment_method': s['payment_method'] ?? 'Efectivo',
        'customer_id': s['customer_id'],
        'customer_name': s['customer_name'],
        'sale_date': s['date'] ?? s['created_at'] ?? DateTime.now().toIso8601String(),
      };

      try {
        await client?.from('sales').insert(payload);
      } catch (e) {
        if (e.toString().contains('product_name') ||
            e.toString().contains('customer_name') ||
            e.toString().contains('42703')) {
          payload.remove('product_name');
          payload.remove('customer_name');
          await client?.from('sales').insert(payload);
        } else {
          rethrow;
        }
      }
    } catch (e) {
      debugPrint('Error al insertar venta en Supabase: $e');
    }
  }

  /// Actualiza el stock de un producto en Supabase en tiempo real
  Future<void> updateProductStockInCloud(String productId, int newStock) async {
    try {
      if (!(await isCloudSyncEnabled())) return;
      if (!_isInitialized) await initialize();
      await client?.from('products').update({'current_stock': newStock}).eq('id', productId);
    } catch (e) {
      debugPrint('Error al actualizar stock en Supabase: $e');
    }
  }

  /// Guarda o actualiza una empresa en Supabase en tiempo real
  Future<void> upsertBusinessToCloud(Map<String, dynamic> b) async {
    try {
      if (!(await isCloudSyncEnabled())) return;
      if (!_isInitialized) await initialize();
      await client?.from('businesses').upsert({
        'id': b['id'],
        'name': b['name'],
        'type': (b['type'] ?? 'Comercio General').toString(),
        'currency': b['currency'] ?? 'COP',
        'is_deleted': (b['is_deleted'] as int?) ?? 0,
        'created_at': b['created_at'],
      }, onConflict: 'id');
    } catch (e) {
      debugPrint('Error al guardar empresa en Supabase: $e');
    }
  }

  /// Actualiza el estado de eliminación de una empresa en Supabase
  Future<void> updateBusinessDeletedStatus(String businessId, bool isDeleted) async {
    try {
      if (!(await isCloudSyncEnabled())) return;
      if (!_isInitialized) await initialize();
      await client?.from('businesses').update({
        'is_deleted': isDeleted ? 1 : 0,
        'deleted_at': isDeleted ? DateTime.now().toIso8601String() : null,
      }).eq('id', businessId);
    } catch (e) {
      debugPrint('Error al actualizar estado de empresa en Supabase: $e');
    }
  }

  /// Elimina una empresa permanentemente de Supabase y todos sus datos relacionados
  Future<void> deleteBusinessPermanently(String businessId) async {
    try {
      if (!(await isCloudSyncEnabled())) return;
      if (!_isInitialized) await initialize();
      if (client == null) return;

      // 1. Eliminar datos hijos en la nube
      try {
        await client!.from('sales').delete().eq('business_id', businessId);
      } catch (_) {}
      try {
        await client!.from('customers').delete().eq('business_id', businessId);
      } catch (_) {}
      try {
        await client!.from('products').delete().eq('business_id', businessId);
      } catch (_) {}
      try {
        await client!.from('categories').delete().eq('business_id', businessId);
      } catch (_) {}
      try {
        await client!.from('business_members').delete().eq('business_id', businessId);
      } catch (_) {}

      // 2. Eliminar la empresa
      await client!.from('businesses').delete().eq('id', businessId);

      // 3. Eliminar fotos del Storage correspondientes a este negocio
      try {
        final files = await client!.storage.from('product-images').list(path: businessId);
        if (files.isNotEmpty) {
          final filePaths = files.map((f) => '$businessId/${f.name}').toList();
          await client!.storage.from('product-images').remove(filePaths);
        }
      } catch (storageErr) {
        debugPrint('Nota al eliminar fotos de Storage en Supabase: $storageErr');
      }
      debugPrint('Empresa $businessId destruida permanentemente de Supabase.');
    } catch (e) {
      debugPrint('Error al eliminar negocio permanentemente en Supabase: $e');
    }
  }

  /// Guarda o actualiza un cliente en Supabase en tiempo real
  Future<void> upsertCustomerToCloud(Map<String, dynamic> c) async {
    try {
      if (!(await isCloudSyncEnabled())) return;
      if (!_isInitialized) await initialize();
      await client?.from('customers').upsert({
        'id': c['id'],
        'business_id': c['business_id'],
        'name': c['name'],
        'phone': c['phone'],
        'address': c['address'],
        'debt_balance': (c['debt_balance'] as num?)?.toDouble() ?? 0.0,
        'created_at': c['created_at'],
      }, onConflict: 'id');
    } catch (e) {
      debugPrint('Error al guardar cliente en Supabase: $e');
    }
  }

  /// Guarda o actualiza un usuario/cuenta en Supabase en tiempo real
  Future<void> upsertUserToCloud(Map<String, dynamic> u) async {
    try {
      if (!(await isCloudSyncEnabled())) return;
      if (!_isInitialized) await initialize();
      await client?.from('users').upsert({
        'id': u['id'],
        'email': u['email'],
        'password': u['password'],
        'name': u['name'],
        'phone': u['phone'],
        'avatar_path': u['avatar_path'],
        'created_at': u['created_at'],
      }, onConflict: 'id');
      debugPrint('Usuario ${u["email"]} sincronizado en Supabase.');
    } catch (e) {
      debugPrint('Error al guardar usuario en Supabase: $e');
    }
  }

  /// Guarda o actualiza una categoría en Supabase en tiempo real
  Future<void> upsertCategoryToCloud(Map<String, dynamic> c) async {
    try {
      if (!(await isCloudSyncEnabled())) return;
      if (!_isInitialized) await initialize();
      await client?.from('categories').upsert({
        'id': c['id'],
        'business_id': c['business_id'],
        'name': c['name'],
        'color_hex': c['color_hex'] ?? '0xFF059669',
      }, onConflict: 'id');
    } catch (e) {
      debugPrint('Error al guardar categoría en Supabase: $e');
    }
  }

  /// Elimina una categoría de Supabase en tiempo real
  Future<void> deleteCategoryFromCloud(String categoryId) async {
    try {
      if (!(await isCloudSyncEnabled())) return;
      if (!_isInitialized) await initialize();
      await client?.from('categories').delete().eq('id', categoryId);
    } catch (e) {
      debugPrint('Error al eliminar categoría en Supabase: $e');
    }
  }

  /// Guarda o actualiza un miembro de equipo en Supabase en tiempo real
  Future<void> upsertBusinessMemberToCloud(Map<String, dynamic> m) async {
    try {
      if (!(await isCloudSyncEnabled())) return;
      if (!_isInitialized) await initialize();
      final userEmail = (m['email'] ?? m['user_email'] ?? '').toString();
      final userName = (m['name'] ?? m['user_name'] ?? (userEmail.isNotEmpty ? userEmail.split('@').first : 'Colaborador')).toString();
      final rawUserId = m['user_id'] as String?;
      await client?.from('business_members').upsert({
        'id': m['id'],
        'business_id': m['business_id'],
        'user_id': (rawUserId != null && rawUserId.trim().isNotEmpty) ? rawUserId.trim() : '',
        'user_email': userEmail,
        'user_name': userName,
        'role': m['role'] ?? 'CASHIER',
        'created_at': m['created_at'] ?? DateTime.now().toIso8601String(),
      }, onConflict: 'id');
      debugPrint('Miembro $userEmail sincronizado en Supabase.');
    } catch (e) {
      debugPrint('Error al guardar miembro en Supabase: $e');
    }
  }

  /// Elimina un miembro de equipo de Supabase en tiempo real
  Future<void> deleteBusinessMemberFromCloud(String memberId) async {
    try {
      if (!(await isCloudSyncEnabled())) return;
      if (!_isInitialized) await initialize();
      await client?.from('business_members').delete().eq('id', memberId);
      debugPrint('Miembro $memberId eliminado de Supabase.');
    } catch (e) {
      debugPrint('Error al eliminar miembro en Supabase: $e');
    }
  }

  /// Opción A: Purgar únicamente los datos en la Nube (mantiene la base local SQLite intacta)
  Future<bool> purgeCloudDataForUser(String userId, [String? userEmail]) async {
    try {
      if (!_isInitialized) await initialize();
      if (client == null) return false;

      final db = await AppDatabase.instance.database;
      final localBusinesses = await db.query('businesses', where: 'user_id = ?', whereArgs: [userId]);
      final bizIds = localBusinesses.map((b) => b['id'] as String).toList();

      for (final bizId in bizIds) {
        try { await client!.from('sales').delete().eq('business_id', bizId); } catch (_) {}
        try { await client!.from('products').delete().eq('business_id', bizId); } catch (_) {}
        try { await client!.from('customers').delete().eq('business_id', bizId); } catch (_) {}
        try { await client!.from('categories').delete().eq('business_id', bizId); } catch (_) {}
        try { await client!.from('business_members').delete().eq('business_id', bizId); } catch (_) {}
        try { await client!.from('businesses').delete().eq('id', bizId); } catch (_) {}
      }

      // Desactivar el flag de sincronización en la nube (volver a Modo Local Privado)
      await setCloudSyncEnabled(false);
      return true;
    } catch (e) {
      debugPrint('Error purgando datos de Supabase: $e');
      return false;
    }
  }

  /// Opción B: Eliminación Total y Definitiva de la Cuenta (Nube + Teléfono)
  Future<void> deleteAccountCompletely({
    required String userId,
    String? userEmail,
  }) async {
    // 1. Purgar datos de negocio en la nube primero
    await purgeCloudDataForUser(userId, userEmail);

    // 2. Eliminar el registro de usuario / cuenta en la nube
    try { await client?.from('users').delete().eq('id', userId); } catch (_) {}
    if (userEmail != null && userEmail.isNotEmpty) {
      try { await client?.from('users').delete().eq('email', userEmail.toLowerCase().trim()); } catch (_) {}
    }

    // 3. Limpiar todas las tablas locales en SQLite
    final db = await AppDatabase.instance.database;
    await db.delete('stock_movements');
    await db.delete('customer_payments');
    await db.delete('sale_items');
    await db.delete('sales');
    await db.delete('products');
    await db.delete('customers');
    await db.delete('categories');
    await db.delete('business_members');
    await db.delete('businesses');
    await db.delete('users');
    await db.delete('app_settings');
  }

  /// Script SQL listo para crear las tablas
  static const String sqlSetupScript = '''
-- 0. Tabla de Usuarios / Cuentas
CREATE TABLE IF NOT EXISTS users (
    id TEXT PRIMARY KEY,
    email TEXT UNIQUE NOT NULL,
    password TEXT NOT NULL,
    name TEXT,
    phone TEXT,
    avatar_path TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 1. Tabla de Empresas
CREATE TABLE IF NOT EXISTS businesses (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    type TEXT NOT NULL DEFAULT 'Comercio General',
    currency TEXT NOT NULL DEFAULT 'COP',
    is_deleted INTEGER NOT NULL DEFAULT 0,
    deleted_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 1.1 Tabla de Categorías
CREATE TABLE IF NOT EXISTS categories (
    id TEXT PRIMARY KEY,
    business_id TEXT REFERENCES businesses(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    color_hex TEXT DEFAULT '0xFF059669',
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
    product_name TEXT,
    quantity INTEGER NOT NULL,
    unit_price NUMERIC(12, 2) NOT NULL,
    unit_cost NUMERIC(12, 2) NOT NULL DEFAULT 0,
    total_amount NUMERIC(12, 2) NOT NULL,
    payment_method TEXT NOT NULL DEFAULT 'Efectivo',
    customer_id TEXT REFERENCES customers(id) ON DELETE SET NULL,
    customer_name TEXT,
    sale_date TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Asegurar columnas nuevas en caso de que la tabla ya existiera previamente
ALTER TABLE sales ADD COLUMN IF NOT EXISTS product_name TEXT;
ALTER TABLE sales ADD COLUMN IF NOT EXISTS customer_name TEXT;

-- Desactivar RLS temporalmente para acceso directo de prueba
ALTER TABLE users DISABLE ROW LEVEL SECURITY;
ALTER TABLE businesses DISABLE ROW LEVEL SECURITY;
ALTER TABLE categories DISABLE ROW LEVEL SECURITY;
ALTER TABLE business_members DISABLE ROW LEVEL SECURITY;
ALTER TABLE products DISABLE ROW LEVEL SECURITY;
ALTER TABLE customers DISABLE ROW LEVEL SECURITY;
ALTER TABLE sales DISABLE ROW LEVEL SECURITY;
''';
}
