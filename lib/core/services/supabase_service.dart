import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../database/app_database.dart';
import 'sync_queue.dart';
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
    if (val == 'true') return true;

    // Auto-detección: si la base de datos ya contiene miembros de equipo (>1),
    // la sincronización en la nube se activa automáticamente para garantizar multi-dispositivo.
    try {
      final db = await AppDatabase.instance.database;
      final count = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM business_members'),
      ) ?? 0;
      if (count > 1) {
        await setCloudSyncEnabled(true);
        return true;
      }
    } catch (_) {}

    return false;
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

      // Solo se suben filas de negocios donde la cuenta es miembro, y según su rol:
      // con RLS, una sola fila no permitida haría fallar el lote completo.
      final myEmail = client!.auth.currentUser?.email?.toLowerCase();
      if (myEmail == null) {
        return const SyncResult(
          success: false,
          errorMessage: 'Inicia sesión para sincronizar con la nube.',
        );
      }
      final myRoles = <String, String>{};
      final myMemberships = await db.query(
        'business_members',
        columns: ['business_id', 'role'],
        where: 'LOWER(email) = ?',
        whereArgs: [myEmail],
      );
      for (final m in myMemberships) {
        myRoles[m['business_id'] as String] = ((m['role'] as String?) ?? 'CASHIER').toUpperCase();
      }
      final memberIds = myRoles.keys.toList();
      final managedIds = [
        for (final e in myRoles.entries)
          if (e.value == 'OWNER' || e.value == 'ADMIN') e.key,
      ];
      final ownedIds = [
        for (final e in myRoles.entries)
          if (e.value == 'OWNER') e.key,
      ];

      Future<List<Map<String, dynamic>>> rowsOf(
        String table,
        List<String> businessIds, {
        String idColumn = 'business_id',
        String? where,
      }) async {
        if (businessIds.isEmpty) return [];
        final marks = List.filled(businessIds.length, '?').join(', ');
        return db.query(
          table,
          where: '$idColumn IN ($marks)${where == null ? '' : ' AND $where'}',
          whereArgs: businessIds,
        );
      }

      // 0. Sincronizar el perfil de la cuenta en sesión (nunca credenciales ni perfiles ajenos)
      try {
        final sessionEmail = client!.auth.currentUser?.email?.toLowerCase();
        if (sessionEmail != null) {
          final localUsers = await db.query(
            'users',
            where: 'LOWER(email) = ?',
            whereArgs: [sessionEmail],
            limit: 1,
          );
          if (localUsers.isNotEmpty) {
            await upsertUserToCloud(localUsers.first);
          }
        }
      } catch (e) {
        debugPrint('Nota: error o tabla users no configurada en Supabase: $e');
      }

      // 1. Sincronizar Businesses
      final localBusinesses = await rowsOf('businesses', managedIds, idColumn: 'id', where: 'is_deleted = 0');
      if (localBusinesses.isNotEmpty) {
        final formattedBusinesses = localBusinesses.map((b) => {
          'id': b['id'],
          ..._businessCloudFields(b),
          'created_at': b['created_at'],
        }).toList();

        // Con RLS un negocio nuevo no puede crearse con upsert: primero se asegura
        // en el servidor que exista con su dueño (no hace nada si ya existe)
        for (final b in localBusinesses.where((b) => ownedIds.contains(b['id']))) {
          await _createBusinessWithOwner(client!, b);
        }
        await client!.from('businesses').upsert(
          formattedBusinesses,
          onConflict: 'id',
        );
      }

      // 1.1 Sincronizar Categories
      try {
        final localCategories = await rowsOf('categories', managedIds);
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
        final localMembers = await rowsOf('business_members', ownedIds);
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
      final inactiveProducts = await rowsOf('products', managedIds, where: 'is_active = 0');
      if (inactiveProducts.isNotEmpty) {
        final inactiveIds = inactiveProducts.map((p) => p['id'] as String).toList();
        await client!.from('products').delete().inFilter('id', inactiveIds);
      }

      // Luego sincronizar únicamente los productos activos (is_active = 1)
      final localProducts = await rowsOf('products', managedIds, where: 'is_active = 1');
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

        // Solo crea los que faltan: el stock de los existentes cambia por diferencia
        // (ventas) y pisarlo con el de este teléfono borraría ventas de otros
        await client!.from('products').upsert(
          formattedProducts,
          onConflict: 'id',
          ignoreDuplicates: true,
        );
      }

      // 3. Sincronizar Customers
      final localCustomers = await rowsOf('customers', memberIds);
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

        // Igual que los productos: la deuda de los existentes no se pisa
        await client!.from('customers').upsert(
          formattedCustomers,
          onConflict: 'id',
          ignoreDuplicates: true,
        );
      }

      // 4. Sincronizar Sales
      final localSales = await rowsOf('sales', memberIds);
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

      // Subir antes de bajar: la descarga reemplaza filas locales y borraría
      // cambios que todavía no llegaron a la nube (por ejemplo, ventas sin conexión)
      await _initialUploadOnce();
      final pending = await flushPendingSync();
      if (pending != 0) {
        return const SyncResult(
          success: false,
          errorMessage: 'Hay cambios sin enviar a la nube; se descargará cuando se envíen.',
        );
      }

      final db = await AppDatabase.instance.database;
      try {
        await db.execute('PRAGMA foreign_keys = OFF');
      } catch (_) {}

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

          final rawBizUserId = b['user_id']?.toString().trim();
          final targetUserId = (rawBizUserId != null && rawBizUserId.isNotEmpty)
              ? rawBizUserId
              : (existingUserId ?? (userId.trim().isNotEmpty ? userId.trim() : 'remote_owner'));

          // Asegurar que el usuario exista en la tabla local 'users' para preservar integridad referencial (FK)
          final userCheck = await db.query('users', where: 'id = ?', whereArgs: [targetUserId], limit: 1);
          if (userCheck.isEmpty) {
            await db.insert(
              'users',
              {
                'id': targetUserId,
                'email': targetUserId == userId
                    ? (userEmail ?? '$targetUserId@stockealo.local')
                    : '$targetUserId@stockealo.remote',
                'password': 'EXTERNAL_OR_REMOTE_USER',
                'name': targetUserId == userId ? 'Usuario' : 'Propietario Cloud',
                'created_at': DateTime.now().toIso8601String(),
              },
              conflictAlgorithm: ConflictAlgorithm.ignore,
            );
          }

          await db.insert(
            'businesses',
            {
              'id': b['id'],
              'user_id': targetUserId,
              'name': b['name'],
              'currency': b['currency'] ?? 'COP',
              'country': b['country'] ?? 'CO',
              'icon': b['icon'],
              'color': b['color'],
              'logo_url': b['logo_url'],
              'cash_register_enabled': b['cash_register_enabled'] == true ? 1 : 0,
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
          var memberName = (m['user_name'] ?? m['name']) as String?;

          // Si el nombre descargado está vacío o es solo el prefijo del correo, buscar el nombre real en users
          if (memberName == null || memberName.trim().isEmpty || memberName.trim().toLowerCase() == memberEmail.split('@').first.toLowerCase()) {
            final uRows = await db.query('users', columns: ['name'], where: 'LOWER(email) = ? OR id = ?', whereArgs: [memberEmail, resolvedUserId ?? ''], limit: 1);
            if (uRows.isNotEmpty && uRows.first['name'] != null && (uRows.first['name'] as String).trim().isNotEmpty) {
              memberName = (uRows.first['name'] as String).trim();
            }
          }
          if (memberName == null || memberName.trim().isEmpty) {
            memberName = memberEmail.split('@').first;
          }

          // Si el miembro es el usuario autenticado y su nombre en el perfil es real, sincronizarlo a Supabase
          if (userEmail != null && memberEmail == userEmail.trim().toLowerCase() && memberName != memberEmail.split('@').first) {
            try {
              await client!.rpc('link_my_memberships', params: {'p_name': memberName});
            } catch (e) {
              debugPrint('No se pudo vincular la membresía en Supabase: $e');
            }
          }
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
              final ownerUserCheck = await db.query('users', where: 'id = ?', whereArgs: [ownerIdToSet.trim()], limit: 1);
              if (ownerUserCheck.isEmpty) {
                await db.insert(
                  'users',
                  {
                    'id': ownerIdToSet.trim(),
                    'email': memberEmail.isNotEmpty ? memberEmail : '${ownerIdToSet.trim()}@stockealo.remote',
                    'password': 'EXTERNAL_OR_REMOTE_USER',
                    'name': memberName,
                    'created_at': DateTime.now().toIso8601String(),
                  },
                  conflictAlgorithm: ConflictAlgorithm.ignore,
                );
              }
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

          // Comprobar existencia de claves foráneas antes de insertar venta
          String? validProdId = prodId;
          if (validProdId != null) {
            final pExists = await db.query('products', columns: ['id'], where: 'id = ?', whereArgs: [validProdId], limit: 1);
            if (pExists.isEmpty) validProdId = null;
          }
          String? validCustId = custId;
          if (validCustId != null) {
            final cExists = await db.query('customers', columns: ['id'], where: 'id = ?', whereArgs: [validCustId], limit: 1);
            if (cExists.isEmpty) validCustId = null;
          }

          await db.insert(
            'sales',
            {
              'id': s['id'],
              'business_id': s['business_id'],
              'product_id': validProdId,
              'product_name': prodName,
              'quantity': qty,
              'customer_id': validCustId,
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
    } finally {
      try {
        final db = await AppDatabase.instance.database;
        await db.execute('PRAGMA foreign_keys = ON');
      } catch (_) {}
    }
  }

  // ---------------------------------------------------------------------------
  // Escrituras a la nube
  //
  // Cada método público guarda el cambio en la cola local (SyncQueue) y luego
  // intenta enviarla. Si no hay conexión el cambio queda pendiente y se reintenta
  // en la próxima escritura, al iniciar sesión o al volver a la app.
  // ---------------------------------------------------------------------------

  /// Una sola vez por cuenta: sube todo lo local. Cubre los datos creados antes de
  /// que existiera la cola; desde entonces solo se envían los cambios.
  Future<void> _initialUploadOnce() async {
    const key = 'initial_upload_done';
    try {
      if (!(await isCloudSyncEnabled())) return;
      if (await AppDatabase.instance.getSetting(key) != null) return;
      final result = await syncToCloud();
      if (result.success) await AppDatabase.instance.setSetting(key, '1');
    } catch (e) {
      debugPrint('Error en la subida inicial: $e');
    }
  }

  /// Escrituras en curso; varias pantallas las lanzan sin esperarlas
  final Set<Future<void>> _pendingWrites = {};

  /// Espera a que terminen las escrituras lanzadas sin esperar. Las pruebas lo usan
  /// antes de cerrar o borrar la base local, que esas escrituras todavía leen.
  @visibleForTesting
  Future<void> waitForPendingWrites() => Future.wait(_pendingWrites.toList());

  Future<void> _write(String operation, Map<String, dynamic> payload) {
    final write = _enqueueAndFlush(operation, payload);
    _pendingWrites.add(write);
    return write.whenComplete(() => _pendingWrites.remove(write));
  }

  Future<void> _enqueueAndFlush(String operation, Map<String, dynamic> payload) async {
    if (!(await isCloudSyncEnabled())) return;
    try {
      // Hora de la edición: la nube descarta ediciones más viejas que la guardada
      final stamped = {...payload, _editedAtKey: DateTime.now().toUtc().toIso8601String()};
      await SyncQueue.instance.enqueue(operation, stamped);
    } catch (e) {
      debugPrint('No se pudo encolar "$operation": $e');
      return;
    }
    await flushPendingSync();
  }

  /// Envía los cambios pendientes. Devuelve cuántos siguen sin enviarse (-1 si falló).
  Future<int> flushPendingSync() async {
    try {
      if (!(await isCloudSyncEnabled())) return 0;
      if (!_isInitialized) await initialize();
      // Sin sesión, RLS rechazaría todo: se espera al próximo inicio de sesión
      if (client?.auth.currentSession == null) return await SyncQueue.instance.pendingCount();
      return await SyncQueue.instance.flush(_send);
    } catch (e) {
      debugPrint('Error enviando cambios pendientes: $e');
      return -1;
    }
  }

  static const String _editedAtKey = '_edited_at';

  /// Actualiza una fila existente sin tocar [keepColumns] (valores que se ajustan
  /// por diferencia, como stock o deuda) y, si la fila no existe, la crea completa.
  /// Si la nube descartó la edición por ser más vieja, el insert no hace nada.
  Future<void> _updateOrInsert(
    SupabaseClient db,
    String table,
    Map<String, dynamic> row, {
    required List<String> keepColumns,
  }) async {
    final changes = Map<String, dynamic>.from(row)..removeWhere((k, _) => keepColumns.contains(k) || k == 'id');
    final updated = await db.from(table).update(changes).eq('id', row['id'] as String).select('id');
    if (updated.isNotEmpty) return;
    await db.from(table).upsert(row, onConflict: 'id', ignoreDuplicates: true);
  }

  Future<void> _send(String operation, Map<String, dynamic> p) async {
    final db = client;
    if (db == null) throw StateError('Supabase no está inicializado');
    final editedAt = p[_editedAtKey] as String?;
    switch (operation) {
      case 'upsert_product':
        await _sendProduct(db, p);
      case 'delete_product':
        await db.from('products').delete().eq('id', p['id'] as String);
      case 'update_stock':
        // Ajuste manual o importación: el usuario fija el valor exacto
        await db.from('products').update({'current_stock': p['stock']}).eq('id', p['id'] as String);
      case 'adjust_stock':
        await db.rpc('adjust_product_stock', params: {'p_product_id': p['id'], 'p_delta': p['delta']});
      case 'adjust_debt':
        await db.rpc('adjust_customer_debt', params: {'p_customer_id': p['id'], 'p_delta': p['delta']});
      case 'upsert_sale':
        await _sendSale(db, p);
      case 'delete_sale':
        await db.from('sales').delete().eq('id', p['id'] as String);
      case 'upsert_business':
        Future<List<dynamic>> update() => db
            .from('businesses')
            .update({..._businessCloudFields(p), if (editedAt != null) 'updated_at': editedAt})
            .eq('id', p['id'] as String)
            .select('id');
        if ((await update()).isEmpty) {
          // Es nuevo: se crea con su dueño y luego se completan país, ícono, color...
          await _createBusinessWithOwner(db, p);
          await update();
        }
      case 'update_business_deleted':
        await db.from('businesses').update({
          'is_deleted': p['is_deleted'],
          'deleted_at': p['deleted_at'],
        }).eq('id', p['id'] as String);
      case 'upsert_customer':
        // La deuda solo se fija al crear al cliente; luego cambia con adjust_debt
        await _updateOrInsert(db, 'customers', {
          'id': p['id'],
          'business_id': p['business_id'],
          'name': p['name'],
          'phone': p['phone'],
          'address': p['address'],
          'debt_balance': (p['debt_balance'] as num?)?.toDouble() ?? 0.0,
          'created_at': p['created_at'],
          if (editedAt != null) 'updated_at': editedAt,
        }, keepColumns: ['debt_balance', 'created_at']);
      case 'update_user':
        // La fila se crea al registrarse; aquí nunca se envían credenciales
        await db.from('users').update({
          'name': p['name'],
          'phone': p['phone'],
          'avatar_path': p['avatar_path'],
        }).eq('id', p['id'] as String);
      case 'upsert_category':
        await db.from('categories').upsert({
          'id': p['id'],
          'business_id': p['business_id'],
          'name': p['name'],
          'color_hex': p['color_hex'] ?? '0xFF059669',
          if (editedAt != null) 'updated_at': editedAt,
        }, onConflict: 'id');
      case 'delete_category':
        await db.from('categories').delete().eq('id', p['id'] as String);
      case 'upsert_member':
        final userEmail = (p['email'] ?? p['user_email'] ?? '').toString();
        final rawUserId = p['user_id'] as String?;
        final row = {
          'id': p['id'],
          'business_id': p['business_id'],
          'user_id': (rawUserId != null && rawUserId.trim().isNotEmpty) ? rawUserId.trim() : '',
          'user_email': userEmail,
          'user_name': (p['name'] ?? p['user_name'] ??
                  (userEmail.isNotEmpty ? userEmail.split('@').first : 'Colaborador'))
              .toString(),
          'role': p['role'] ?? 'CASHIER',
          'created_at': p['created_at'] ?? DateTime.now().toIso8601String(),
        };
        try {
          await db.from('business_members').upsert(row, onConflict: 'id');
        } on PostgrestException catch (e) {
          // El dueño de un negocio que aún no existe en la nube (creado sin conexión o
          // cuya creación se perdió): crearlo con su dueño en el servidor y reintentar
          final isOwnBusinessOwner = row['role'] == 'OWNER' &&
              userEmail.toLowerCase() == db.auth.currentUser?.email?.toLowerCase();
          if (e.code != '42501' || !isOwnBusinessOwner) rethrow;
          final local = await AppDatabase.instance.database;
          final business = await local.query('businesses', where: 'id = ?', whereArgs: [p['business_id']], limit: 1);
          if (business.isEmpty) rethrow;
          await _createBusinessWithOwner(db, business.first);
          await db.from('business_members').upsert(row, onConflict: 'id');
        }
      case 'delete_member':
        await db.from('business_members').delete().eq('id', p['id'] as String);
      case 'insert_activity':
        // Quién la hizo lo pone el servidor con la sesión (actor_email por defecto)
        try {
          await db.from('business_activity').upsert({
            'id': p['id'],
            'business_id': p['business_id'],
            'actor_name': p['actor_name'],
            'action': p['action'],
            'summary': p['summary'],
            'data': p['data'],
            'created_at': p['created_at'],
          }, onConflict: 'id', ignoreDuplicates: true);
        } on PostgrestException catch (e) {
          // Ya no es miembro o el negocio no existe: la anotación no se puede subir
          // y no debe frenar el resto de la cola
          if (e.code != '42501' && e.code != '23503') rethrow;
          debugPrint('Actividad descartada (${e.code}): ${p['action']}');
        }
      default:
        throw ArgumentError('Operación de sincronización desconocida: $operation');
    }
  }

  /// Campos del negocio que se guardan en la nube (fila local → columnas de Supabase)
  static Map<String, dynamic> _businessCloudFields(Map<String, dynamic> b) => {
        'name': b['name'],
        'type': (b['type'] ?? 'Comercio General').toString(),
        'currency': b['currency'] ?? 'COP',
        'country': b['country'] ?? 'CO',
        'icon': b['icon'],
        'color': b['color'],
        'logo_url': b['logo_url'],
        'cash_register_enabled': b['cash_register_enabled'] == 1 || b['cash_register_enabled'] == true,
        'is_deleted': (b['is_deleted'] as int?) ?? 0,
      };

  /// Crea el negocio y registra a esta cuenta como dueña en un solo paso del
  /// servidor. Usa el id de membresía que ya existe en el teléfono para que la
  /// membresía encolada después no quede duplicada.
  Future<void> _createBusinessWithOwner(SupabaseClient db, Map<String, dynamic> business) async {
    final email = db.auth.currentUser?.email?.toLowerCase();
    final local = await AppDatabase.instance.database;
    final owner = email == null
        ? <Map<String, dynamic>>[]
        : await local.query(
            'business_members',
            where: "business_id = ? AND LOWER(email) = ? AND role = 'OWNER'",
            whereArgs: [business['id'], email],
            limit: 1,
          );
    await db.rpc('create_business_with_owner', params: {
      'p_id': business['id'],
      'p_name': business['name'],
      'p_type': business['type'],
      'p_currency': business['currency'],
      'p_created_at': business['created_at'],
      'p_member_id': owner.isNotEmpty ? owner.first['id'] : null,
      'p_user_id': owner.isNotEmpty ? owner.first['user_id'] : null,
      'p_user_name': owner.isNotEmpty ? owner.first['name'] : null,
    });
  }

  Future<void> _sendProduct(SupabaseClient db, Map<String, dynamic> p) async {
    String? imageUrl = p['photo_path'] as String?;

    // Si tiene una imagen guardada en el dispositivo, subirla primero a Storage
    if (imageUrl != null && imageUrl.isNotEmpty && !imageUrl.startsWith('http')) {
      final uploadedUrl = await uploadProductImage(
        businessId: p['business_id'] as String,
        productId: p['id'] as String,
        localFilePath: imageUrl,
      );
      if (uploadedUrl != null) {
        imageUrl = uploadedUrl;
        final local = await AppDatabase.instance.database;
        await local.update(
          'products',
          {'photo_path': uploadedUrl},
          where: 'id = ?',
          whereArgs: [p['id']],
        );
      } else {
        // Una ruta local no sirve en otros dispositivos
        imageUrl = null;
      }
    }

    // El stock solo se fija al crear el producto; luego cambia con adjust_stock o update_stock
    final editedAt = p[_editedAtKey] as String?;
    await _updateOrInsert(db, 'products', {
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
      if (editedAt != null) 'updated_at': editedAt,
    }, keepColumns: ['current_stock', 'created_at']);
  }

  Future<void> _sendSale(SupabaseClient db, Map<String, dynamic> s) async {
    final total = (s['total_amount'] as num?)?.toDouble() ?? (s['total'] as num?)?.toDouble() ?? 0.0;
    final qty = (s['quantity'] as num?)?.toInt() ?? 1;
    final unitPrice = (s['unit_price'] as num?)?.toDouble() ?? (qty > 0 ? total / qty : 0.0);
    final totalCost = (s['total_cost'] as num?)?.toDouble() ?? 0.0;
    final unitCost = (s['unit_cost'] as num?)?.toDouble() ?? (qty > 0 ? totalCost / qty : 0.0);

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

    // upsert: si un reintento llega después de que la venta ya se guardó, no se duplica
    try {
      await db.from('sales').upsert(payload, onConflict: 'id');
    } catch (e) {
      if (e.toString().contains('product_name') ||
          e.toString().contains('customer_name') ||
          e.toString().contains('42703')) {
        payload.remove('product_name');
        payload.remove('customer_name');
        await db.from('sales').upsert(payload, onConflict: 'id');
      } else {
        rethrow;
      }
    }
  }

  /// Elimina un producto de Supabase
  Future<void> deleteProductFromCloud(String productId) => _write('delete_product', {'id': productId});

  /// Crea o actualiza un producto en Supabase (incluida su foto)
  Future<void> upsertProductToCloud(Map<String, dynamic> p) => _write('upsert_product', p);

  /// Registra una venta en Supabase
  Future<void> insertSaleToCloud(Map<String, dynamic> s) => _write('upsert_sale', s);

  /// Elimina una venta anulada de Supabase
  Future<void> deleteSaleFromCloud(String saleId) => _write('delete_sale', {'id': saleId});

  /// Fija el stock exacto de un producto (ajuste manual o importación)
  Future<void> updateProductStockInCloud(String productId, int newStock) =>
      _write('update_stock', {'id': productId, 'stock': newStock});

  /// Suma o resta stock (ventas y anulaciones): no se pisa con otros dispositivos
  Future<void> adjustProductStockInCloud(String productId, int delta) =>
      _write('adjust_stock', {'id': productId, 'delta': delta});

  /// Suma o resta deuda de un cliente (fiados, abonos y anulaciones)
  Future<void> adjustCustomerDebtInCloud(String customerId, double delta) =>
      _write('adjust_debt', {'id': customerId, 'delta': delta});

  /// Guarda o actualiza una empresa en Supabase
  Future<void> upsertBusinessToCloud(Map<String, dynamic> b) => _write('upsert_business', b);

  /// Actualiza el estado de eliminación (papelera) de una empresa en Supabase
  Future<void> updateBusinessDeletedStatus(String businessId, bool isDeleted) => _write('update_business_deleted', {
        'id': businessId,
        'is_deleted': isDeleted ? 1 : 0,
        'deleted_at': isDeleted ? DateTime.now().toIso8601String() : null,
      });

  /// Guarda o actualiza un cliente en Supabase
  Future<void> upsertCustomerToCloud(Map<String, dynamic> c) => _write('upsert_customer', c);

  /// Actualiza el perfil (nombre, teléfono, foto) de un usuario en Supabase.
  Future<void> upsertUserToCloud(Map<String, dynamic> u) => _write('update_user', {
        'id': u['id'],
        'name': u['name'],
        'phone': u['phone'],
        'avatar_path': u['avatar_path'],
      });

  /// Guarda o actualiza una categoría en Supabase
  Future<void> upsertCategoryToCloud(Map<String, dynamic> c) => _write('upsert_category', c);

  /// Elimina una categoría de Supabase
  Future<void> deleteCategoryFromCloud(String categoryId) => _write('delete_category', {'id': categoryId});

  /// Guarda o actualiza un miembro de equipo en Supabase
  Future<void> upsertBusinessMemberToCloud(Map<String, dynamic> m) => _write('upsert_member', m);

  /// Elimina un miembro de equipo de Supabase
  Future<void> deleteBusinessMemberFromCloud(String memberId) => _write('delete_member', {'id': memberId});

  /// Sube una anotación del registro de actividad (ver ActivityRepository)
  Future<void> insertActivityToCloud(Map<String, dynamic> row) => _write('insert_activity', row);

  /// Sube el logo del negocio a la carpeta del negocio (mismo bucket y permisos que las
  /// fotos de productos: lo ven los miembros y lo cambian dueño y admin)
  Future<String?> uploadBusinessLogo({required String businessId, required String localFilePath}) =>
      uploadProductImage(businessId: businessId, productId: 'logo', localFilePath: localFilePath);

  /// Sube la imagen del producto a Supabase Storage (bucket: product-images) y retorna la URL pública
  Future<String?> uploadProductImage({
    required String businessId,
    required String productId,
    required String localFilePath,
  }) async {
    try {
      if (!_isInitialized) await initialize();
      if (client == null) return null;

      if (kIsWeb) {
        return localFilePath.startsWith('http') ? localFilePath : null;
      }

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

  /// Elimina una empresa permanentemente de Supabase y todos sus datos relacionados
  Future<void> deleteBusinessPermanently(String businessId) async {
    try {
      if (!(await isCloudSyncEnabled())) return;
      if (!_isInitialized) await initialize();
      if (client == null) return;

      // 1. Fotos primero: al borrar el negocio se pierde el permiso sobre su carpeta
      try {
        final files = await client!.storage.from('product-images').list(path: businessId);
        if (files.isNotEmpty) {
          final filePaths = files.map((f) => '$businessId/${f.name}').toList();
          await client!.storage.from('product-images').remove(filePaths);
        }
      } catch (storageErr) {
        debugPrint('Nota al eliminar fotos de Storage en Supabase: $storageErr');
      }

      // 2. Borrar el negocio: ventas, clientes, productos, categorías y miembros caen
      //    en cascada. Con RLS un borrado sin permiso no da error, solo 0 filas.
      if (!await _deleteBusinessRow(businessId)) {
        debugPrint('No se pudo eliminar el negocio $businessId en Supabase (sin permiso o inexistente).');
        return;
      }
      debugPrint('Empresa $businessId destruida permanentemente de Supabase.');
    } catch (e) {
      debugPrint('Error al eliminar negocio permanentemente en Supabase: $e');
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

      // Cada negocio arrastra en cascada sus ventas, productos, clientes, categorías y miembros
      var allDeleted = true;
      for (final bizId in bizIds) {
        if (!await _deleteBusinessRow(bizId)) {
          debugPrint('No se pudo purgar el negocio $bizId en Supabase.');
          allDeleted = false;
        }
      }
      if (!allDeleted) return false;

      // Desactivar el flag de sincronización en la nube (volver a Modo Local Privado)
      await setCloudSyncEnabled(false);
      return true;
    } catch (e) {
      debugPrint('Error purgando datos de Supabase: $e');
      return false;
    }
  }

  /// Borra un negocio en la nube y confirma que se borró de verdad
  Future<bool> _deleteBusinessRow(String businessId) async {
    try {
      final deleted = await client!.from('businesses').delete().eq('id', businessId).select('id');
      return deleted.isNotEmpty;
    } catch (e) {
      debugPrint('Error eliminando el negocio $businessId en Supabase: $e');
      return false;
    }
  }

  /// Opción B: Eliminación Total y Definitiva de la Cuenta (Nube + Teléfono)
  ///
  /// La Edge Function `delete-account` borra en el servidor los negocios donde la
  /// cuenta es dueña única, sus membresías, su perfil y su usuario de Supabase Auth.
  /// Solo si eso funciona se limpia el teléfono, para no dejar una cuenta a medias.
  Future<void> deleteAccountCompletely() async {
    if (!_isInitialized) await initialize();
    if (client?.auth.currentSession == null) {
      throw Exception('Necesitas conexión a internet y una sesión activa para eliminar tu cuenta.');
    }

    try {
      final res = await client!.functions.invoke('delete-account');
      final data = res.data;
      if (data is! Map || data['deleted'] != true) throw Exception('respuesta inesperada: $data');
    } catch (e) {
      debugPrint('Error eliminando la cuenta en Supabase: $e');
      throw Exception('No se pudo eliminar la cuenta en la nube. Revisa tu conexión e inténtalo de nuevo.');
    }

    // Limpiar todas las tablas locales del archivo de esta cuenta
    final db = await AppDatabase.instance.database;
    for (final table in ['quotation_items', 'quotations', 'product_variants']) {
      try { await db.delete(table); } catch (_) {}
    }
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

    // Cerrar la sesión local (el usuario de Auth ya no existe en el servidor)
    try {
      await client?.auth.signOut();
    } catch (_) {}
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
