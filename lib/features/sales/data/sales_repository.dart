import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../../../core/database/app_database.dart';
import '../../../core/services/data_events.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../auth/data/auth_repository.dart';
import '../../team/data/activity_repository.dart';
import '../../products/models/product.dart';
import '../models/sale.dart';
import '../models/cart_item.dart';
import '../models/quotation.dart';

class SalesRepository {
  static final SalesRepository instance = SalesRepository();
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

    String? customerId;
    var customerIsNew = false;

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
          customerIsNew = true;
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

    // Sincronizar cliente (deuda del fiado), venta y stock a Supabase.
    // El stock se envía como diferencia para no pisar ventas de otros dispositivos.
    await _syncCustomer(db, customerId, customerIsNew, total);
    SupabaseService.instance.insertSaleToCloud(sale.toMap());
    SupabaseService.instance.adjustProductStockInCloud(product.id, -quantity);

    final who = customerName?.trim().isNotEmpty == true ? ' a ${customerName!.trim()}' : '';
    ActivityRepository.instance.log(
      businessId: businessId,
      action: ActivityAction.sale,
      summary: 'Vendió $quantity × ${product.name} por ${CurrencyFormatter.format(total)} '
          '(${activityPaymentLabel(paymentMethod)}$who)',
      data: {'sale_id': saleId, 'total': total},
    );

    DataEvents.instance.salesChanged();
    return sale;
  }

  /// Registra una venta multi-producto (carrito) con descuento mayorista y factura unificada
  Future<List<Sale>> recordMultiProductSale({
    required String businessId,
    required List<CartItem> items,
    required String paymentMethod, // 'EFECTIVO' | 'TRANSFERENCIA' | 'FIADO'
    String? customerName,
    double discountAmount = 0.0,
    double discountPercent = 0.0,
    String? notes,
  }) async {
    if (items.isEmpty) {
      throw Exception('El carrito está vacío. Agrega al menos un producto.');
    }

    final db = await _dbProvider.database;

    // 1. Validar stock de todos los productos y variantes antes de iniciar
    for (final item in items) {
      final available = item.availableStock;
      if (available <= 0) {
        throw Exception('El producto "${item.displayName}" está agotado.');
      }
      if (item.quantity > available) {
        throw Exception('Stock insuficiente para "${item.displayName}". Quedan $available unidades.');
      }
      if (item.quantity <= 0) {
        throw Exception('La cantidad de "${item.displayName}" debe ser mayor a 0.');
      }
    }

    final double totalSubtotal = items.fold(0.0, (sum, i) => sum + i.subtotal);
    final double finalDiscount = discountAmount > 0
        ? discountAmount
        : (discountPercent > 0 ? (totalSubtotal * (discountPercent / 100.0)) : 0.0);
    final double finalTotal = (totalSubtotal - finalDiscount).clamp(0.0, double.infinity);

    final now = DateTime.now();
    final invoiceNumber = '#INV-${now.millisecondsSinceEpoch.toString().substring(5)}';

    final currentUser = AuthRepository.instance.currentUser;
    final seller = (currentUser?.name != null && currentUser!.name!.trim().isNotEmpty)
        ? currentUser.name!
        : (currentUser?.email.split('@').first ?? 'Vendedor');

    final List<Sale> createdSales = [];
    final Map<String, int> stockDeltas = {};
    String? customerId;
    var customerIsNew = false;

    await db.transaction((txn) async {
      // Registrar o actualizar deuda de fiado si corresponde
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
            {'debt_balance': currentDebt + finalTotal},
            where: 'id = ? AND business_id = ?',
            whereArgs: [customerId, businessId],
          );
        } else {
          customerId = const Uuid().v4();
          customerIsNew = true;
          await txn.insert('customers', {
            'id': customerId,
            'business_id': businessId,
            'name': cleanName,
            'debt_balance': finalTotal,
            'created_at': now.toIso8601String(),
            'is_synced': 0,
          });
        }
      }

      for (final item in items) {
        final product = item.product;
        final newStock = product.stock - item.quantity;
        final saleId = const Uuid().v4();

        // Proporción del descuento asignado a este ítem
        final double itemProportion = totalSubtotal > 0 ? (item.subtotal / totalSubtotal) : (1.0 / items.length);
        final double itemDiscount = finalDiscount * itemProportion;
        final double itemTotal = (item.subtotal - itemDiscount).clamp(0.0, double.infinity);
        final double itemProfit = itemTotal - item.totalCost;

        // Descontar stock específico de la variante si aplica
        if (item.variant != null) {
          final newVariantStock = item.variant!.stock - item.quantity;
          await txn.update(
            'product_variants',
            {
              'stock': newVariantStock,
              'updated_at': now.toIso8601String(),
            },
            where: 'id = ?',
            whereArgs: [item.variant!.id],
          );
        }

        // Descontar stock general en products
        await txn.update(
          'products',
          {
            'stock': newStock,
            'updated_at': now.toIso8601String(),
          },
          where: 'id = ? AND business_id = ?',
          whereArgs: [product.id, businessId],
        );

        // Movimiento en Kardex
        await txn.insert('stock_movements', {
          'id': const Uuid().v4(),
          'business_id': businessId,
          'product_id': product.id,
          'type': 'SALIDA_VENTA',
          'quantity': item.quantity,
          'resulting_stock': newStock,
          'reason': item.variant != null
              ? 'Venta POS $invoiceNumber - ${item.variant!.attributeValue} ($paymentMethod)'
              : 'Venta POS $invoiceNumber ($paymentMethod)',
          'date': now.toIso8601String(),
        });

        // Insertar en sales
        await txn.insert('sales', {
          'id': saleId,
          'business_id': businessId,
          'product_id': product.id,
          'product_name': item.displayName,
          'product_photo_path': product.photoPath,
          'quantity': item.quantity,
          'customer_id': customerId,
          'customer_name': customerName?.trim().isNotEmpty == true ? customerName!.trim() : null,
          'seller_name': seller,
          'date': now.toIso8601String(),
          'total': itemTotal,
          'total_cost': item.totalCost,
          'net_profit': itemProfit,
          'payment_method': paymentMethod,
          'payment_status': paymentMethod == 'FIADO' ? 'PENDIENTE' : 'PAGADO',
          'notes': notes,
          'invoice_number': invoiceNumber,
          'discount_amount': itemDiscount,
          'variant_id': item.variant?.id,
          'variant_name': item.variant?.attributeValue,
          'created_at': now.toIso8601String(),
          'is_synced': 0,
        });

        // Insertar en sale_items
        await txn.insert('sale_items', {
          'id': const Uuid().v4(),
          'sale_id': saleId,
          'product_id': product.id,
          'quantity': item.quantity,
          'unit_price': item.unitPrice,
          'unit_cost': item.unitCost,
          'subtotal': itemTotal,
        });

        final sale = Sale(
          id: saleId,
          businessId: businessId,
          productId: product.id,
          productName: item.displayName,
          productPhotoPath: product.photoPath,
          quantity: item.quantity,
          unitPrice: item.unitPrice,
          unitCost: item.unitCost,
          totalAmount: itemTotal,
          netProfit: itemProfit,
          paymentMethod: paymentMethod,
          customerName: customerName,
          sellerName: seller,
          date: now,
          variantId: item.variant?.id,
          variantName: item.variant?.attributeValue,
        );

        createdSales.add(sale);
        stockDeltas[product.id] = (stockDeltas[product.id] ?? 0) - item.quantity;
      }
    });

    // Sincronización a la nube fuera de la transacción: cliente, ventas y stock final
    await _syncCustomer(db, customerId, customerIsNew, finalTotal);
    for (final sale in createdSales) {
      SupabaseService.instance.insertSaleToCloud(sale.toMap());
    }
    stockDeltas.forEach(SupabaseService.instance.adjustProductStockInCloud);

    final units = items.fold<int>(0, (sum, i) => sum + i.quantity);
    final who = customerName?.trim().isNotEmpty == true ? ' a ${customerName!.trim()}' : '';
    final what = items.length == 1 ? '${items.first.quantity} × ${items.first.displayName}' : '$units productos';
    ActivityRepository.instance.log(
      businessId: businessId,
      action: ActivityAction.sale,
      summary: 'Vendió $what por ${CurrencyFormatter.format(finalTotal)} '
          '(${activityPaymentLabel(paymentMethod)}$who)'
          '${finalDiscount > 0 ? ' con ${CurrencyFormatter.format(finalDiscount)} de descuento' : ''}',
      data: {'invoice': invoiceNumber, 'total': finalTotal, 'discount': finalDiscount},
    );

    DataEvents.instance.salesChanged();
    return createdSales;
  }

  /// Lleva a la nube el fiado: un cliente nuevo se crea con su deuda; a uno
  /// existente se le suma la diferencia, para no pisar abonos de otros dispositivos.
  Future<void> _syncCustomer(Database db, String? customerId, bool isNew, double amount) async {
    if (customerId == null) return;
    if (!isNew) {
      await SupabaseService.instance.adjustCustomerDebtInCloud(customerId, amount);
      return;
    }
    final rows = await db.query('customers', where: 'id = ?', whereArgs: [customerId], limit: 1);
    if (rows.isNotEmpty) await SupabaseService.instance.upsertCustomerToCloud(rows.first);
  }

  /// Guarda una cotización formal (proforma) sin descontar inventario
  Future<Quotation> recordQuotation({
    required String businessId,
    required List<CartItem> items,
    String? customerName,
    String? customerPhone,
    double discountAmount = 0.0,
    int validDays = 7,
    String? notes,
  }) async {
    if (items.isEmpty) {
      throw Exception('Agrega al menos un producto para generar una cotización.');
    }

    final db = await _dbProvider.database;
    final now = DateTime.now();
    final quotationId = const Uuid().v4();
    final quotationNumber = 'COT-${now.millisecondsSinceEpoch.toString().substring(6)}';
    final validUntil = now.add(Duration(days: validDays));

    final totalSubtotal = items.fold(0.0, (sum, i) => sum + i.subtotal);
    final totalAmount = (totalSubtotal - discountAmount).clamp(0.0, double.infinity);

    final currentUser = AuthRepository.instance.currentUser;
    final seller = (currentUser?.name != null && currentUser!.name!.trim().isNotEmpty)
        ? currentUser.name!
        : (currentUser?.email.split('@').first ?? 'Vendedor');

    final List<QuotationItem> quotationItems = [];

    await db.transaction((txn) async {
      await txn.insert('quotations', {
        'id': quotationId,
        'business_id': businessId,
        'quotation_number': quotationNumber,
        'customer_name': customerName?.trim().isNotEmpty == true ? customerName!.trim() : null,
        'customer_phone': customerPhone?.trim().isNotEmpty == true ? customerPhone!.trim() : null,
        'total_amount': totalAmount,
        'discount_amount': discountAmount,
        'notes': notes,
        'status': 'PENDIENTE',
        'valid_until': validUntil.toIso8601String(),
        'created_at': now.toIso8601String(),
        'seller_name': seller,
      });

      for (final item in items) {
        final itemId = const Uuid().v4();
        final qItem = QuotationItem(
          id: itemId,
          quotationId: quotationId,
          productId: item.product.id,
          productName: item.displayName,
          quantity: item.quantity,
          unitPrice: item.unitPrice,
          subtotal: item.subtotal,
          variantId: item.variant?.id,
          variantName: item.variant?.attributeValue,
        );
        quotationItems.add(qItem);

        await txn.insert('quotation_items', qItem.toMap());
      }
    });

    return Quotation(
      id: quotationId,
      businessId: businessId,
      quotationNumber: quotationNumber,
      customerName: customerName,
      customerPhone: customerPhone,
      totalAmount: totalAmount,
      discountAmount: discountAmount,
      notes: notes,
      status: 'PENDIENTE',
      validUntil: validUntil,
      createdAt: now,
      sellerName: seller,
      items: quotationItems,
    );
  }

  /// Obtiene cotizaciones de la empresa
  Future<List<Quotation>> getQuotations({required String businessId}) async {
    final db = await _dbProvider.database;
    final rows = await db.query(
      'quotations',
      where: 'business_id = ?',
      whereArgs: [businessId],
      orderBy: 'created_at DESC',
    );

    // Todos los ítems de las cotizaciones del negocio en una sola consulta
    final itemRows = await db.rawQuery('''
      SELECT qi.* FROM quotation_items qi
      JOIN quotations q ON q.id = qi.quotation_id
      WHERE q.business_id = ?
    ''', [businessId]);
    final itemsByQuotation = <String, List<QuotationItem>>{};
    for (final m in itemRows) {
      itemsByQuotation.putIfAbsent(m['quotation_id'] as String, () => []).add(QuotationItem.fromMap(m));
    }

    return [
      for (final row in rows) Quotation.fromMap(row, itemsByQuotation[row['id'] as String] ?? []),
    ];
  }

  /// Elimina una cotización
  Future<void> deleteQuotation(String quotationId) async {
    final db = await _dbProvider.database;
    await db.delete('quotations', where: 'id = ?', whereArgs: [quotationId]);
  }

  /// Marca una cotización como FACTURADA
  Future<void> markQuotationAsBilled(String quotationId) async {
    final db = await _dbProvider.database;
    await db.update(
      'quotations',
      {'status': 'FACTURADA'},
      where: 'id = ?',
      whereArgs: [quotationId],
    );
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
  Future<Map<String, dynamic>> getTodaySummary(String businessId) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return getSalesSummary(businessId, from: today, to: today.add(const Duration(days: 1)));
  }

  /// Resumen de ventas entre [from] (incluido) y [to] (excluido), en hora local
  Future<Map<String, dynamic>> getSalesSummary(
    String businessId, {
    required DateTime from,
    required DateTime to,
  }) async {
    final sales = (await getSales(businessId: businessId))
        .where((s) => !s.date.isBefore(from) && s.date.isBefore(to))
        .toList();

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
    int? restoredStock;
    String? debtorId;
    await db.transaction((txn) async {
      // Reponer stock
      await txn.rawUpdate(
        'UPDATE products SET stock = stock + ? WHERE id = ? AND business_id = ?',
        [sale.quantity, sale.productId, sale.businessId],
      );
      final productRows = await txn.query(
        'products',
        columns: ['stock'],
        where: 'id = ? AND business_id = ?',
        whereArgs: [sale.productId, sale.businessId],
      );
      restoredStock = productRows.isNotEmpty ? productRows.first['stock'] as int : null;

      // Registrar reverso en kardex
      await txn.insert('stock_movements', {
        'id': const Uuid().v4(),
        'business_id': sale.businessId,
        'product_id': sale.productId,
        'type': 'AJUSTE',
        'quantity': sale.quantity,
        'resulting_stock': restoredStock ?? 0,
        'reason': 'Venta cancelada / reversada',
        'date': DateTime.now().toIso8601String(),
      });

      // Si fue fiado, reducir deuda
      if (sale.paymentMethod == 'FIADO' && sale.customerName != null) {
        await txn.rawUpdate(
          'UPDATE customers SET debt_balance = MAX(0, debt_balance - ?) WHERE business_id = ? AND LOWER(name) = ?',
          [sale.totalAmount, sale.businessId, sale.customerName!.toLowerCase()],
        );
        final customerRows = await txn.query(
          'customers',
          where: 'business_id = ? AND LOWER(name) = ?',
          whereArgs: [sale.businessId, sale.customerName!.toLowerCase()],
          limit: 1,
        );
        debtorId = customerRows.isNotEmpty ? customerRows.first['id'] as String : null;
      }

      // Eliminar registro de venta
      await txn.delete(
        'sales',
        where: 'id = ? AND business_id = ?',
        whereArgs: [sale.id, sale.businessId],
      );
    });

    DataEvents.instance.salesChanged();
    ActivityRepository.instance.log(
      businessId: sale.businessId,
      action: ActivityAction.saleCancel,
      summary: 'Anuló la venta de ${sale.quantity} × ${sale.productName} por ${CurrencyFormatter.format(sale.totalAmount)}',
      data: {'sale_id': sale.id, 'total': sale.totalAmount},
    );

    // Reflejar la anulación en la nube; si no, la venta reaparecería al descargar
    final cloud = SupabaseService.instance;
    await cloud.deleteSaleFromCloud(sale.id);
    if (restoredStock != null) await cloud.adjustProductStockInCloud(sale.productId, sale.quantity);
    if (debtorId != null) await cloud.adjustCustomerDebtInCloud(debtorId!, -sale.totalAmount);
  }
}
