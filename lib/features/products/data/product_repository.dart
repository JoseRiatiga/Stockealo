import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../../../core/database/app_database.dart';
import '../../../core/utils/image_helper.dart';
import '../../../core/services/supabase_service.dart';
import '../models/category.dart';
import '../models/product.dart';
import '../models/product_variant.dart';

class ProductRepository {
  static final ProductRepository instance = ProductRepository();
  final AppDatabase _dbProvider = AppDatabase.instance;

  /// Obtiene todos los productos activos de la empresa especificada
  Future<List<Product>> getAllProducts(String businessId) async {
    final db = await _dbProvider.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'products',
      where: 'business_id = ? AND is_active = 1',
      whereArgs: [businessId],
      orderBy: 'name ASC',
    );
    return maps.map((map) => Product.fromMap(map)).toList();
  }

  /// Búsqueda predictiva aislada por empresa (con soporte de variantes)
  Future<List<Product>> searchProducts(
    String query, {
    String? category,
    required String businessId,
  }) async {
    final db = await _dbProvider.database;
    String whereClause = 'business_id = ? AND is_active = 1';
    List<dynamic> whereArgs = [businessId];

    if (query.isNotEmpty) {
      whereClause += ' AND (name LIKE ? OR code LIKE ?)';
      whereArgs.addAll(['%$query%', '%$query%']);
    }

    if (category != null && category.isNotEmpty && category != 'Todos') {
      whereClause += ' AND category = ?';
      whereArgs.add(category);
    }

    final List<Map<String, dynamic>> maps = await db.query(
      'products',
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: 'name ASC',
    );

    final List<Product> result = [];
    for (final map in maps) {
      final p = Product.fromMap(map);
      if (p.hasVariants) {
        final variants = await getVariantsForProduct(p.id);
        result.add(p.copyWith(variants: variants));
      } else {
        result.add(p);
      }
    }
    return result;
  }

  /// Obtener variantes asociadas a un producto
  Future<List<ProductVariant>> getVariantsForProduct(String productId) async {
    final db = await _dbProvider.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'product_variants',
      where: 'product_id = ?',
      whereArgs: [productId],
      orderBy: 'created_at ASC',
    );
    return maps.map((m) => ProductVariant.fromMap(m)).toList();
  }

  /// Guardar o reemplazar lista de variantes de un producto
  Future<void> saveVariants(String productId, String businessId, List<ProductVariant> variants) async {
    final db = await _dbProvider.database;
    await db.transaction((txn) async {
      await txn.delete('product_variants', where: 'product_id = ?', whereArgs: [productId]);
      for (final v in variants) {
        await txn.insert('product_variants', v.toMap());
      }
    });
  }

  /// Obtener producto por ID dentro de la empresa (con variantes cargadas si existen)
  Future<Product?> getProductById(String id, String businessId) async {
    final db = await _dbProvider.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'products',
      where: 'id = ? AND business_id = ? AND is_active = 1',
      whereArgs: [id, businessId],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    final product = Product.fromMap(maps.first);
    if (product.hasVariants) {
      final variants = await getVariantsForProduct(product.id);
      return product.copyWith(variants: variants);
    }
    return product;
  }

  /// Buscar por código de barras / QR dentro de la empresa (busca en producto y en códigos de variante)
  Future<Product?> getProductByCode(String code, String businessId) async {
    final db = await _dbProvider.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'products',
      where: 'code = ? AND business_id = ? AND is_active = 1',
      whereArgs: [code, businessId],
      limit: 1,
    );
    if (maps.isNotEmpty) {
      final product = Product.fromMap(maps.first);
      if (product.hasVariants) {
        final variants = await getVariantsForProduct(product.id);
        return product.copyWith(variants: variants);
      }
      return product;
    }

    // Si no coincide con código de producto, buscar en códigos de variantes
    final List<Map<String, dynamic>> variantMaps = await db.query(
      'product_variants',
      where: 'sku_or_barcode = ? AND business_id = ?',
      whereArgs: [code, businessId],
      limit: 1,
    );
    if (variantMaps.isNotEmpty) {
      final parentId = variantMaps.first['product_id'] as String;
      return getProductById(parentId, businessId);
    }

    return null;
  }

  /// Insertar nuevo producto asignado a su empresa (con sus variantes si aplica)
  Future<void> insertProduct(Product product) async {
    final db = await _dbProvider.database;
    await db.transaction((txn) async {
      await txn.insert(
        'products',
        product.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      if (product.hasVariants && product.variants.isNotEmpty) {
        for (final v in product.variants) {
          await txn.insert('product_variants', v.toMap());
        }
      }

      // Registrar movimiento inicial de stock en la empresa
      if (product.stock > 0) {
        await txn.insert('stock_movements', {
          'id': const Uuid().v4(),
          'business_id': product.businessId,
          'product_id': product.id,
          'type': 'ENTRADA_COMPRA',
          'quantity': product.stock,
          'resulting_stock': product.stock,
          'reason': 'Inventario inicial de creación',
          'date': DateTime.now().toIso8601String(),
        });
      }
    });

    // Sincronizar en tiempo real a Supabase
    SupabaseService.instance.upsertProductToCloud(product.toMap());
  }

  /// Actualizar producto (y sincronizar variantes)
  Future<void> updateProduct(Product product) async {
    final db = await _dbProvider.database;
    await db.transaction((txn) async {
      await txn.update(
        'products',
        product.toMap(),
        where: 'id = ? AND business_id = ?',
        whereArgs: [product.id, product.businessId],
      );

      if (product.hasVariants) {
        await txn.delete('product_variants', where: 'product_id = ?', whereArgs: [product.id]);
        for (final v in product.variants) {
          await txn.insert('product_variants', v.toMap());
        }
      }
    });

    // Sincronizar actualización en tiempo real a Supabase
    SupabaseService.instance.upsertProductToCloud(product.toMap());
  }

  /// Eliminar producto
  Future<void> deleteProduct(String id, String businessId) async {
    final db = await _dbProvider.database;
    final product = await getProductById(id, businessId);
    if (product != null) {
      if (product.photoPath != null) {
        await ImageHelper.deleteImage(product.photoPath);
      }
      await db.update(
        'products',
        {
          'is_active': 0,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ? AND business_id = ?',
        whereArgs: [id, businessId],
      );

      // Eliminar también de Supabase en tiempo real
      await SupabaseService.instance.deleteProductFromCloud(id);
    }
  }

  /// Ajustar stock directamente con auditoría
  Future<void> adjustStock(String productId, String businessId, int newStock, String reason) async {
    final db = await _dbProvider.database;
    final product = await getProductById(productId, businessId);
    if (product == null) return;

    final diff = newStock - product.stock;
    final type = diff >= 0 ? 'AJUSTE' : 'MERMA';

    await db.transaction((txn) async {
      await txn.update(
        'products',
        {
          'stock': newStock,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ? AND business_id = ?',
        whereArgs: [productId, businessId],
      );

      await txn.insert('stock_movements', {
        'id': const Uuid().v4(),
        'business_id': businessId,
        'product_id': productId,
        'type': type,
        'quantity': diff.abs(),
        'resulting_stock': newStock,
        'reason': reason,
        'date': DateTime.now().toIso8601String(),
      });
    });

    // Actualizar stock en Supabase en tiempo real
    SupabaseService.instance.updateProductStockInCloud(productId, newStock);
  }

  /// Obtener categorías de la empresa
  Future<List<Category>> getCategories(String businessId) async {
    final db = await _dbProvider.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'categories',
      where: 'business_id = ?',
      whereArgs: [businessId],
      orderBy: 'name ASC',
    );
    return maps.map((map) => Category.fromMap(map)).toList();
  }

  /// Crear categoría al vuelo para la empresa
  Future<Category> addCategory(String name, String businessId) async {
    final db = await _dbProvider.database;
    final category = Category(
      id: const Uuid().v4(),
      businessId: businessId,
      name: name.trim(),
      colorHex: '0xFF059669',
    );
    await db.insert(
      'categories',
      category.toMap(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );

    // Sincronizar en tiempo real a Supabase
    SupabaseService.instance.upsertCategoryToCloud(category.toMap());

    return category;
  }

  /// Actualizar / renombrar categoría existente (actualiza también los productos asociados)
  Future<void> updateCategory({
    required String id,
    required String businessId,
    required String oldName,
    required String newName,
  }) async {
    final db = await _dbProvider.database;
    final cleanNewName = newName.trim();

    await db.transaction((txn) async {
      // 1. Actualizar la tabla categories
      await txn.update(
        'categories',
        {'name': cleanNewName},
        where: 'id = ? AND business_id = ?',
        whereArgs: [id, businessId],
      );

      // 2. Actualizar todos los productos que tenían la categoría anterior
      await txn.update(
        'products',
        {'category': cleanNewName},
        where: 'business_id = ? AND category = ?',
        whereArgs: [businessId, oldName],
      );
    });

    // 3. Sincronizar a Supabase
    SupabaseService.instance.upsertCategoryToCloud({
      'id': id,
      'business_id': businessId,
      'name': cleanNewName,
      'color_hex': '0xFF059669',
    });
    try {
      await SupabaseService.instance.client
          ?.from('products')
          .update({'category': cleanNewName})
          .eq('business_id', businessId)
          .eq('category', oldName);
    } catch (_) {}
  }

  /// Eliminar categoría y reasignar productos a 'General'
  Future<void> deleteCategory({
    required String id,
    required String businessId,
    required String categoryName,
  }) async {
    final db = await _dbProvider.database;

    await db.transaction((txn) async {
      // 1. Eliminar de la tabla categories
      await txn.delete(
        'categories',
        where: 'id = ? AND business_id = ?',
        whereArgs: [id, businessId],
      );

      // 2. Reasignar productos de esta categoría a 'General'
      await txn.update(
        'products',
        {'category': 'General'},
        where: 'business_id = ? AND category = ?',
        whereArgs: [businessId, categoryName],
      );
    });

    // 3. Eliminar de Supabase
    await SupabaseService.instance.deleteCategoryFromCloud(id);
    try {
      await SupabaseService.instance.client
          ?.from('products')
          .update({'category': 'General'})
          .eq('business_id', businessId)
          .eq('category', categoryName);
    } catch (_) {}
  }

  /// Contar cuántos productos pertenecen a una categoría
  Future<int> countProductsInCategory(String categoryName, String businessId) async {
    final db = await _dbProvider.database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM products WHERE business_id = ? AND category = ? AND is_active = 1',
      [businessId, categoryName],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Resumen estadístico del inventario de la empresa
  Future<Map<String, dynamic>> getInventoryStats(String businessId) async {
    final products = await getAllProducts(businessId);
    int totalCount = products.length;
    int outOfStock = 0;
    int lowStock = 0;
    double totalInventoryCost = 0.0;
    double totalInventorySaleValue = 0.0;

    for (final p in products) {
      if (p.isOutOfStock) {
        outOfStock++;
      } else if (p.isLowStock) {
        lowStock++;
      }
      totalInventoryCost += (p.purchasePrice * p.stock);
      totalInventorySaleValue += (p.salePrice * p.stock);
    }

    return {
      'totalProducts': totalCount,
      'outOfStock': outOfStock,
      'lowStock': lowStock,
      'healthyStock': totalCount - outOfStock - lowStock,
      'totalCost': totalInventoryCost,
      'totalValue': totalInventorySaleValue,
      'estimatedProfit': totalInventorySaleValue - totalInventoryCost,
    };
  }

  /// Obtiene los productos con stock bajo o agotado para reposición
  Future<List<Product>> getRestockProducts(String businessId) async {
    final products = await getAllProducts(businessId);
    return products.where((p) => p.isLowStock || p.isOutOfStock).toList();
  }
}
