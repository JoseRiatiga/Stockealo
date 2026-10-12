import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../../../core/database/app_database.dart';
import '../../../core/utils/image_helper.dart';
import '../models/category.dart';
import '../models/product.dart';

class ProductRepository {
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

  /// Búsqueda predictiva aislada por empresa
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
    return maps.map((map) => Product.fromMap(map)).toList();
  }

  /// Obtener producto por ID dentro de la empresa
  Future<Product?> getProductById(String id, String businessId) async {
    final db = await _dbProvider.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'products',
      where: 'id = ? AND business_id = ? AND is_active = 1',
      whereArgs: [id, businessId],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return Product.fromMap(maps.first);
  }

  /// Buscar por código de barras / QR dentro de la empresa
  Future<Product?> getProductByCode(String code, String businessId) async {
    final db = await _dbProvider.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'products',
      where: 'code = ? AND business_id = ? AND is_active = 1',
      whereArgs: [code, businessId],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return Product.fromMap(maps.first);
  }

  /// Insertar nuevo producto asignado a su empresa
  Future<void> insertProduct(Product product) async {
    final db = await _dbProvider.database;
    await db.transaction((txn) async {
      await txn.insert(
        'products',
        product.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

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
  }

  /// Actualizar producto
  Future<void> updateProduct(Product product) async {
    final db = await _dbProvider.database;
    await db.update(
      'products',
      product.toMap(),
      where: 'id = ? AND business_id = ?',
      whereArgs: [product.id, product.businessId],
    );
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
    return category;
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
}
