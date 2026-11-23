import '../../../core/database/app_database.dart';
import '../../products/data/product_repository.dart';
import '../../products/models/product.dart';
import '../../products/models/product_variant.dart';

/// La primera venta de un negocio (0.17.0, bloque A). Una sola definición para
/// «Primeros pasos», el aviso del celular y las pruebas: cuenta una venta de verdad
/// (sin anular y que no sea una devolución). La venta de práctica no se guarda.
class FirstSale {
  FirstSale._();

  /// Ventas de verdad del negocio en este celular
  static Future<int> count(String businessId) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery('SELECT COUNT(*) AS n FROM sales_ok WHERE business_id = ? AND quantity > 0', [businessId]);
    return (rows.first['n'] as num?)?.toInt() ?? 0;
  }

  /// Productos activos del negocio
  static Future<int> products(String businessId) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery('SELECT COUNT(*) AS n FROM products WHERE business_id = ? AND COALESCE(is_active, 1) = 1', [businessId]);
    return (rows.first['n'] as num?)?.toInt() ?? 0;
  }

  /// Hay productos y todavía ninguna venta
  static Future<bool> pending(String businessId) async => await products(businessId) > 0 && await count(businessId) == 0;

  /// Un producto que se pueda vender ya (con stock): primero uno sin tallas ni colores;
  /// si solo hay con variantes, la primera variante con stock. Null si todo está en 0.
  static Future<(Product, ProductVariant?)?> pickProduct(String businessId) async {
    final repo = ProductRepository.instance;
    final all = await repo.getAllProducts(businessId);
    final simple = all.where((p) => !p.hasVariants && p.stock > 0).firstOrNull;
    if (simple != null) return (simple, null);
    for (final p in all.where((p) => p.hasVariants && p.stock > 0)) {
      final variants = await repo.getVariantsForProduct(p.id);
      final v = variants.where((v) => v.stock > 0).firstOrNull;
      if (v != null) return (p.copyWith(variants: variants), v);
    }
    return null;
  }
}
