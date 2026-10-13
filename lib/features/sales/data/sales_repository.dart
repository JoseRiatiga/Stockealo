import 'package:uuid/uuid.dart';
import '../../../core/database/app_database.dart';
import '../../../core/services/supabase_service.dart';
import '../../auth/data/auth_repository.dart';
import '../../products/models/product.dart';
import '../models/sale.dart';

class SalesRepository {
  final AppDatabase _dbProvider = AppDatabase.instance;

  /// Registra una venta aislada por empresa y descuenta stock
  Future<Sale> recordSale({
    required Product product,
    required int quantity,
    required String paymentMethod, // 'EFECTIVO' | 'TRANSFERENCIA' | 'FIADO'
    String? customerName,
    String? notes,
  }) async {
    final db = await _dbProvider.database;

    // 1. Validación estricta de stock
    if (product.stock <= 0) {
      throw Exception('El producto "${product.name}" está agotado.');
    }
    if (quantity > product.stock) {
      throw Exception('Stock insuficiente. Solo quedan ${product.stock} unidades.');
    }
    if (quantity <= 0) {
      throw Exception('La cantidad debe ser mayor a 0.');
    }

    final total = product.salePrice * quantity;
    final totalCost = product.purchasePrice * quantity;
    final netProfit = total - totalCost;
    final newStock = product.stock - quantity;
    final now = DateTime.now();
    final saleId = const Uuid().v4();
    final businessId = product.businessId;

    final currentUser = AuthRepository.instance.currentUser;
    final seller = (currentUser?.name != null && currentUser!.name!.trim().isNotEmpty)
        ? currentUser.name!
        : (currentUser?.email.split('@').first ?? 'Vendedor');

    await db.transaction((txn) async {
      // 2. Descontar stock del producto dentro de la empresa
      await txn.update(
        'products',
        {
          'stock': newStock,
          'updated_at': now.toIso8601String(),
        },
        where: 'id = ? AND business_id = ?',
        whereArgs: [product.id, businessId],
      );

      // 3. Registrar salida en Kardex (stock_movements)
      await txn.insert('stock_movements', {
        'id': const Uuid().v4(),
        'business_id': businessId,
        'product_id': product.id,
        'type': 'SALIDA_VENTA',
        'quantity': quantity,
        'resulting_stock': newStock,
        'reason': 'Venta rápida ($paymentMethod)',
        'date': now.toIso8601String(),
      });

      String? customerId;
      // 4. Si es FIADO, registrar o actualizar deuda del cliente para esta empresa
      if (paymentMethod == 'FIADO' && customerName != null && customerName.trim().isNotEmpty) {
        final cleanName = customerName.trim();
        final List<Map<String, dynamic>> existingCustomer = await txn.query(
          'customers',
          where: 'business_id = ? AND LOWER(name) = ?',
          whereArgs: [businessId, cleanName.toLowerCase()],
          limit: 1,
        );

        if (existingCustomer.isNotEmpty) {
          customerId = existingCustomer.first['id'] as String;
          final currentDebt = (existingCustomer.first['debt_balance'] as num).toDouble();
          await txn.update(
            'customers',
            {
              'debt_balance': currentDebt + total,
            },
            where: 'id = ? AND business_id = ?',
            whereArgs: [customerId, businessId],
          );
        } else {
          customerId = const Uuid().v4();
          await txn.insert('customers', {
            'id': customerId,
            'business_id': businessId,
            'name': cleanName,
            'debt_balance': total,
            'created_at': now.toIso8601String(),
            'is_synced': 0,
          });
        }
      }

      // 5. Registrar la Venta en la empresa
      await txn.insert('sales', {
        'id': saleId,
        'business_id': businessId,
        'product_id': product.id,
        'product_name': product.name,
        'product_photo_path': product.photoPath,
        'quantity': quantity,
        'customer_id': customerId,
        'customer_name': customerName?.trim().isNotEmpty == true ? customerName!.trim() : null,
        'seller_name': seller,
        'date': now.toIso8601String(),
        'total': total,
        'total_cost': totalCost,
        'net_profit': netProfit,
        'payment_method': paymentMethod,
        'payment_status': paymentMethod == 'FIADO' ? 'PENDIENTE' : 'PAGADO',
        'notes': notes,
        'created_at': now.toIso8601String(),
        'is_synced': 0,
      });
    });

    final sale = Sale(
      id: saleId,
      businessId: businessId,
      productId: product.id,
      productName: product.name,
      productPhotoPath: product.photoPath,
      quantity: quantity,
      unitPrice: product.salePrice,
      unitCost: product.purchasePrice,
      totalAmount: total,
      netProfit: netProfit,
      paymentMethod: paymentMethod,
      customerName: customerName,
      sellerName: seller,
      date: now,
    );

    // Sincronizar venta y stock actualizado en tiempo real a Supabase
    SupabaseService.instance.insertSaleToCloud(sale.toMap());
    SupabaseService.instance.updateProductStockInCloud(product.id, newStock);

    return sale;
  }

  /// Obtener ventas filtradas exclusivamente por la empresa con resolución de foto de producto
  Future<List<Sale>> getSales({
    required String businessId,
    String? dateFilter,
  }) async {
    final db = await _dbProvider.database;
    String sql = '''
      SELECT s.*, COALESCE(s.product_photo_path, p.photo_path) AS resolved_photo
      FROM sales s
      LEFT JOIN products p ON s.product_id = p.id
      WHERE s.business_id = ?
    ''';
    final List<dynamic> args = [businessId];

    if (dateFilter != null && dateFilter.isNotEmpty) {
      sql += ' AND s.date LIKE ?';
      args.add('$dateFilter%');
    }
    sql += ' ORDER BY s.date DESC';

    final List<Map<String, dynamic>> maps = await db.rawQuery(sql, args);

    return maps.map((map) {
      final photoPath = map['resolved_photo'] as String? ?? map['product_photo_path'] as String?;
      return Sale(
        id: map['id'] as String,
        businessId: map['business_id'] as String? ?? businessId,
        productId: map['product_id'] as String? ?? '',
        productName: map['product_name'] as String,
        productPhotoPath: photoPath,
        quantity: (map['quantity'] as num).toInt(),
        unitPrice: (map['quantity'] as num).toInt() > 0
            ? ((map['total'] as num).toDouble()) / ((map['quantity'] as num).toInt())
            : 0.0,
        unitCost: (map['quantity'] as num).toInt() > 0
            ? ((map['total_cost'] as num).toDouble()) / ((map['quantity'] as num).toInt())
            : 0.0,
        totalAmount: (map['total'] as num).toDouble(),
        netProfit: (map['net_profit'] as num).toDouble(),
        paymentMethod: map['payment_method'] as String,
        customerName: map['customer_name'] as String?,
        sellerName: map['seller_name'] as String?,
        date: DateTime.parse(map['date'] as String),
        isSynced: (map['is_synced'] as int?) == 1,
      );
    }).toList();
  }

  /// Obtiene el resumen de ventas del día actual de la empresa
  Future<Map<String, dynamic>> getTodaySummary(String businessId) async {
    final todayStr = DateTime.now().toIso8601String().substring(0, 10);
    final sales = await getSales(businessId: businessId, dateFilter: todayStr);

    double totalAmount = 0.0;
    double netProfit = 0.0;
    int totalUnits = 0;
    double byEfectivo = 0.0;
    double byTransferencia = 0.0;
    double byFiado = 0.0;

    for (final s in sales) {
      totalAmount += s.totalAmount;
      netProfit += s.netProfit;
      totalUnits += s.quantity;

      switch (s.paymentMethod) {
        case 'EFECTIVO':
          byEfectivo += s.totalAmount;
          break;
        case 'TRANSFERENCIA':
          byTransferencia += s.totalAmount;
          break;
        case 'FIADO':
          byFiado += s.totalAmount;
          break;
      }
    }

    return {
      'count': sales.length,
      'totalAmount': totalAmount,
      'netProfit': netProfit,
      'totalUnits': totalUnits,
      'byEfectivo': byEfectivo,
      'byTransferencia': byTransferencia,
      'byFiado': byFiado,
    };
  }

  /// Cancelar / Revertir una venta por error en la empresa correspondiente
  Future<void> cancelSale(Sale sale) async {
    final db = await _dbProvider.database;
    await db.transaction((txn) async {
      // Reponer stock
      await txn.rawUpdate(
        'UPDATE products SET stock = stock + ? WHERE id = ? AND business_id = ?',
        [sale.quantity, sale.productId, sale.businessId],
      );

      // Registrar reverso en kardex
      await txn.insert('stock_movements', {
        'id': const Uuid().v4(),
        'business_id': sale.businessId,
        'product_id': sale.productId,
        'type': 'AJUSTE',
        'quantity': sale.quantity,
        'resulting_stock': 0,
        'reason': 'Venta cancelada / reversada',
        'date': DateTime.now().toIso8601String(),
      });

      // Si fue fiado, reducir deuda
      if (sale.paymentMethod == 'FIADO' && sale.customerName != null) {
        await txn.rawUpdate(
          'UPDATE customers SET debt_balance = MAX(0, debt_balance - ?) WHERE business_id = ? AND LOWER(name) = ?',
          [sale.totalAmount, sale.businessId, sale.customerName!.toLowerCase()],
        );
      }

      // Eliminar registro de venta
      await txn.delete(
        'sales',
        where: 'id = ? AND business_id = ?',
        whereArgs: [sale.id, sale.businessId],
      );
    });
  }
}
