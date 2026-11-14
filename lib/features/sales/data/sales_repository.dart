import '../../services/data/commissions_repository.dart';
import '../../services/models/service_models.dart';
import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../../../core/database/app_database.dart';
import '../../../core/services/data_events.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../auth/data/auth_repository.dart';
import '../../team/data/activity_repository.dart';
import '../../products/models/product.dart';
import '../../cash/data/cash_register_repository.dart';
import '../models/sale.dart';
import '../models/cart_item.dart';
import '../models/quotation.dart';
import '../../sales/models/payment_method.dart';

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
          '(${PaymentMethod.label(paymentMethod).toLowerCase()}$who)',
      data: {'sale_id': saleId, 'total': total},
    );

    DataEvents.instance.salesChanged();
    return sale;
  }

  /// Registra una venta multi-producto (carrito) con descuento mayorista y factura unificada
  Future<List<Sale>> recordMultiProductSale({
    required String businessId,
    required List<CartItem> items,
    required String paymentMethod,
    String? customerName,
    double discountAmount = 0.0,
    double discountPercent = 0.0,
    String? notes,

    /// Solo con pago mixto: cuánto entró por cada medio (debe sumar el total)
    Map<String, double>? paymentSplit,
  }) async {
    if (items.isEmpty) {
      throw Exception('El carrito está vacío. Agrega al menos un producto.');
    }

    final db = await _dbProvider.database;
    await CashRegisterRepository.instance.requireOpen(businessId);

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

    // Con promoción: cada línea ya trae su descuento; el descuento a toda la venta se
    // reparte sobre lo que queda (0.13.4)
    final double totalSubtotal = items.fold(0.0, (sum, i) => sum + i.netSubtotal);
    final double finalDiscount = discountAmount > 0
        ? discountAmount
        : (discountPercent > 0 ? (totalSubtotal * (discountPercent / 100.0)) : 0.0);
    final double finalTotal = (totalSubtotal - finalDiscount).clamp(0.0, double.infinity);

    // Pago mixto: los medios tienen que sumar el total (sin fiado)
    final mixed = paymentMethod == PaymentMethod.mixed;
    if (mixed) {
      final split = paymentSplit ?? const {};
      final paid = split.values.fold<double>(0, (a, b) => a + b);
      if (split.keys.any((k) => !PaymentMethod.forMixed.contains(k))) {
        throw Exception('El pago mixto solo combina efectivo, Nequi, transferencia y tarjeta.');
      }
      if ((paid - finalTotal).abs() > 0.5) {
        throw Exception('Las partes del pago mixto suman ${CurrencyFormatter.format(paid)} y el total es ${CurrencyFormatter.format(finalTotal)}.');
      }
    }

    final now = DateTime.now();
    final invoiceNumber = '#INV-${now.millisecondsSinceEpoch.toString().substring(5)}';

    final currentUser = AuthRepository.instance.currentUser;
    final seller = (currentUser?.name != null && currentUser!.name!.trim().isNotEmpty)
        ? currentUser.name!
        : (currentUser?.email.split('@').first ?? 'Vendedor');

    final List<Sale> createdSales = [];
    final Map<String, int> stockDeltas = {};
    final Map<String, int> variantDeltas = {};
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
        final double itemProportion = totalSubtotal > 0 ? (item.netSubtotal / totalSubtotal) : (1.0 / items.length);
        final double itemDiscount = finalDiscount * itemProportion;
        final double itemTotal = (item.netSubtotal - itemDiscount).clamp(0.0, double.infinity);
        final promo = item.promoDiscount > 0 ? item.promotion : null;
        final double itemProfit = itemTotal - item.totalCost;
        // Cada línea guarda su parte de cada medio, para que la caja sepa cuánto fue en efectivo
        final String? itemSplit = mixed && finalTotal > 0
            ? PaymentMethod.encodeSplit({for (final e in paymentSplit!.entries) e.key: e.value * itemTotal / finalTotal})
            : null;

        // Descontar stock específico de la variante si aplica. Por diferencia: la
        // variante del carrito puede traer existencias de hace rato
        if (item.variant != null) {
          await txn.rawUpdate(
            'UPDATE product_variants SET stock = stock - ?, updated_at = ? WHERE id = ?',
            [item.quantity, now.toIso8601String(), item.variant!.id],
          );
          variantDeltas[item.variant!.id] = (variantDeltas[item.variant!.id] ?? 0) - item.quantity;
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
              ? 'Venta POS $invoiceNumber - ${item.variant!.label} ($paymentMethod)'
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
          'discount_amount': itemDiscount + (promo == null ? 0 : item.promoDiscount),
          'variant_id': item.variant?.id,
          'variant_name': item.variant?.label,
          'payment_split': itemSplit,
          'promotion_id': promo?.id,
          'promotion_name': promo?.name,
          'promotion_discount': promo == null ? 0.0 : item.promoDiscount,
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
          variantName: item.variant?.label,
          invoiceNumber: invoiceNumber,
          paymentSplit: itemSplit,
          promotionId: promo?.id,
          promotionName: promo?.name,
          promotionDiscount: promo == null ? 0 : item.promoDiscount,
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
    variantDeltas.forEach(SupabaseService.instance.adjustVariantStockInCloud);

    final units = items.fold<int>(0, (sum, i) => sum + i.quantity);
    final who = customerName?.trim().isNotEmpty == true ? ' a ${customerName!.trim()}' : '';
    final what = items.length == 1 ? '${items.first.quantity} × ${items.first.displayName}' : '$units productos';
    ActivityRepository.instance.log(
      businessId: businessId,
      action: ActivityAction.sale,
      summary: 'Vendió $what por ${CurrencyFormatter.format(finalTotal)} '
          '(${PaymentMethod.label(paymentMethod).toLowerCase()}$who)'
          '${finalDiscount > 0 ? ' con ${CurrencyFormatter.format(finalDiscount)} de descuento' : ''}',
      data: {'invoice': invoiceNumber, 'total': finalTotal, 'discount': finalDiscount},
    );

    DataEvents.instance.salesChanged();
    return createdSales;
  }

  /// Cobra los servicios de una orden del tablero. Cada servicio queda como una
  /// línea de venta sin producto (no toca el inventario), con la placa y quién lo
  /// hizo en la nota. El descuento se reparte en proporción al precio.
  /// La propina no es venta del negocio: se guarda en la orden para el empleado.
  Future<List<Sale>> recordServiceSale({
    required WorkOrder order,
    required String paymentMethod, // 'EFECTIVO' | 'TRANSFERENCIA' | 'FIADO'
    String? customerName,
    double discountAmount = 0,
    Map<String, String> staffNames = const {},

    /// Propina para quienes atendieron (se reparte en partes iguales)
    double tipAmount = 0,
    DateTime? now,
  }) async {
    final lines = order.lines;
    if (lines.isEmpty) throw Exception('La orden no tiene servicios para cobrar.');
    if (paymentMethod == 'FIADO' && (customerName ?? '').trim().isEmpty) {
      throw Exception('Para fiar escribe el nombre del cliente.');
    }
    final db = await _dbProvider.database;
    await CashRegisterRepository.instance.requireOpen(order.businessId);
    final businessId = order.businessId;
    final subtotal = lines.fold(0.0, (s, l) => s + l.price);
    final discount = discountAmount.clamp(0.0, subtotal).toDouble();
    final finalTotal = subtotal - discount;
    final at = now ?? DateTime.now();
    final invoiceNumber = '#INV-${at.millisecondsSinceEpoch.toString().substring(5)}';
    final currentUser = AuthRepository.instance.currentUser;
    final seller = (currentUser?.name ?? '').trim().isNotEmpty
        ? currentUser!.name!
        : (currentUser?.email.split('@').first ?? 'Vendedor');
    final cleanCustomer = (customerName ?? '').trim().isEmpty ? null : customerName!.trim();

    final created = <Sale>[];
    final charged = <ChargedLine>[];
    String? customerId;
    var customerIsNew = false;

    await db.transaction((txn) async {
      if (paymentMethod == 'FIADO' && cleanCustomer != null) {
        final existing = await txn.query(
          'customers',
          where: 'business_id = ? AND LOWER(name) = ?',
          whereArgs: [businessId, cleanCustomer.toLowerCase()],
          limit: 1,
        );
        if (existing.isNotEmpty) {
          customerId = existing.first['id'] as String;
          await txn.rawUpdate(
            'UPDATE customers SET debt_balance = debt_balance + ? WHERE id = ?',
            [finalTotal, customerId],
          );
        } else {
          customerId = const Uuid().v4();
          customerIsNew = true;
          await txn.insert('customers', {
            'id': customerId,
            'business_id': businessId,
            'name': cleanCustomer,
            'phone': order.customerPhone,
            'debt_balance': finalTotal,
            'created_at': at.toIso8601String(),
            'is_synced': 0,
          });
        }
      }

      for (final line in lines) {
        final share = subtotal > 0 ? line.price / subtotal : 1 / lines.length;
        final lineDiscount = discount * share;
        final lineTotal = (line.price - lineDiscount).clamp(0.0, double.infinity).toDouble();
        final who = [for (final id in line.staffIds) staffNames[id] ?? 'Empleado'].join(', ');
        final note = [
          if ((order.plate ?? '').isNotEmpty) 'Placa ${order.plate}',
          if (who.isNotEmpty) 'Atendió: $who',
        ].join(' · ');
        final saleId = const Uuid().v4();
        final staffJson = jsonEncode(line.staffIds);
        // La comisión de quienes lo hicieron es el costo del servicio
        final commission = CommissionsRepository.commissionOf(lineTotal, line.commissionPct, line.staffIds);
        charged.add((saleId: saleId, total: lineTotal, line: line));
        await txn.insert('sales', {
          'id': saleId,
          'business_id': businessId,
          'product_id': null,
          'product_name': line.name,
          'quantity': 1,
          'customer_id': customerId,
          'customer_name': cleanCustomer,
          'seller_name': seller,
          'date': at.toIso8601String(),
          'total': lineTotal,
          'total_cost': commission,
          'net_profit': lineTotal - commission,
          'payment_method': paymentMethod,
          'payment_status': paymentMethod == 'FIADO' ? 'PENDIENTE' : 'PAGADO',
          'notes': note.isEmpty ? null : note,
          'invoice_number': invoiceNumber,
          'discount_amount': lineDiscount,
          'service_id': line.serviceId,
          'work_order_id': order.id,
          'staff_ids': staffJson,
          'created_at': at.toIso8601String(),
          'is_synced': 0,
        });
        created.add(Sale(
          id: saleId,
          businessId: businessId,
          productId: '',
          productName: line.name,
          quantity: 1,
          unitPrice: lineTotal,
          unitCost: commission,
          totalAmount: lineTotal,
          netProfit: lineTotal - commission,
          paymentMethod: paymentMethod,
          customerName: cleanCustomer,
          sellerName: seller,
          date: at,
          serviceId: line.serviceId,
          workOrderId: order.id,
          staffIds: staffJson,
        ));
      }
    });

    await _syncCustomer(db, customerId, customerIsNew, finalTotal);
    for (final sale in created) {
      SupabaseService.instance.insertSaleToCloud({...sale.toMap(), 'notes': null});
    }
    await CommissionsRepository.instance.recordForOrder(order: order, charged: charged, tip: tipAmount, now: at);
    final what = lines.length == 1 ? lines.first.name : '${lines.length} servicios';
    ActivityRepository.instance.log(
      businessId: businessId,
      action: ActivityAction.serviceSale,
      summary: 'Cobró $what${(order.plate ?? '').isNotEmpty ? ' (${order.plate})' : ''} por '
          '${CurrencyFormatter.format(finalTotal)} (${PaymentMethod.label(paymentMethod).toLowerCase()})'
          '${discount > 0 ? ' con ${CurrencyFormatter.format(discount)} de descuento' : ''}',
      data: {'work_order_id': order.id, 'total': finalTotal},
    );
    DataEvents.instance.salesChanged();
    return created;
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
          variantName: item.variant?.label,
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

    return maps.map((map) => saleFromRow(map, businessId: businessId)).toList();
  }

  /// Una venta por su id (para anular el cobro de un servicio); null si no existe
  /// Todas las líneas de la misma venta (mismo número), en el orden en que se vendieron
  Future<List<Sale>> linesOf(Sale sale) async {
    if ((sale.invoiceNumber ?? '').isEmpty) return [sale];
    final db = await _dbProvider.database;
    final rows = await db.query('sales',
        where: 'business_id = ? AND invoice_number = ?', whereArgs: [sale.businessId, sale.invoiceNumber], orderBy: 'rowid');
    return rows.isEmpty ? [sale] : [for (final r in rows) saleFromRow(r)];
  }

  Future<Sale?> getSaleById(String id) async {
    final db = await _dbProvider.database;
    final rows = await db.query('sales', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : saleFromRow(rows.first);
  }

  /// Fila de la tabla sales -> Sale (la tabla guarda total y total_cost, no precios unitarios)
  static Sale saleFromRow(Map<String, dynamic> map, {String? businessId}) {
    final photoPath = map['resolved_photo'] as String? ?? map['product_photo_path'] as String?;
    return Sale(
      id: map['id'] as String,
      businessId: map['business_id'] as String? ?? businessId ?? 'default_business',
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
      // Sin la talla, anular la venta no le devolvía la unidad a la variante
      variantId: map['variant_id'] as String?,
      variantName: map['variant_name'] as String?,
      serviceId: map['service_id'] as String?,
      workOrderId: map['work_order_id'] as String?,
      staffIds: map['staff_ids'] as String?,
      invoiceNumber: map['invoice_number'] as String?,
      voidedAt: DateTime.tryParse('${map['voided_at'] ?? ''}'),
      voidReason: map['void_reason'] as String?,
      voidedBy: map['voided_by'] as String?,
      paymentSplit: map['payment_split'] as String?,
    );
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
    // Las anuladas se ven en el historial, pero no suman
    final sales = (await getSales(businessId: businessId))
        .where((s) => !s.isVoided && !s.date.isBefore(from) && s.date.isBefore(to))
        .toList();

    double totalAmount = 0.0;
    double netProfit = 0.0;
    int totalUnits = 0;
    final byMethod = <String, double>{};
    final invoices = <String>{};

    for (final s in sales) {
      totalAmount += s.totalAmount;
      netProfit += s.netProfit;
      totalUnits += s.quantity;
      invoices.add(s.invoiceNumber ?? s.id);
      for (final e in PaymentMethod.amounts(s.paymentMethod, s.totalAmount, s.paymentSplit).entries) {
        byMethod[e.key] = (byMethod[e.key] ?? 0) + e.value;
      }
    }

    return {
      'count': invoices.length,
      'totalAmount': totalAmount,
      'netProfit': netProfit,
      'totalUnits': totalUnits,
      'byMethod': byMethod,
      'byEfectivo': byMethod[PaymentMethod.cash] ?? 0.0,
      'byTransferencia': byMethod[PaymentMethod.transfer] ?? 0.0,
      'byFiado': byMethod[PaymentMethod.credit] ?? 0.0,
    };
  }

  /// Anula una venta SIN borrarla: queda en Ventas como «Anulada» (con el motivo y
  /// quién la anuló) y deja de contar en totales, caja, reportes y fiados.
  /// Anula todas las líneas de la misma venta (mismo número) y devuelve su stock.
  /// Si ya estaba anulada no hace nada.
  Future<void> voidSale(Sale sale, {String? reason}) async {
    final db = await _dbProvider.database;
    final user = AuthRepository.instance.currentUser;
    final by = (user?.name ?? '').trim().isNotEmpty ? user!.name!.trim() : (user?.email.split('@').first ?? 'Alguien');
    final cleanReason = (reason ?? '').trim().isEmpty ? null : reason!.trim();
    final now = DateTime.now().toIso8601String();

    final invoice = (sale.invoiceNumber ?? '').isEmpty ? null : sale.invoiceNumber;
    final rows = await db.query(
      'sales',
      where: invoice == null
          ? 'id = ? AND business_id = ? AND voided_at IS NULL'
          : 'invoice_number = ? AND business_id = ? AND voided_at IS NULL',
      whereArgs: [invoice ?? sale.id, sale.businessId],
    );
    if (rows.isEmpty) return;
    final lines = [for (final r in rows) saleFromRow(r)];

    final stock = <String, int>{};
    final variants = <String, int>{};
    final debts = <String, double>{};

    await db.transaction((txn) async {
      for (final line in lines) {
        if (line.productId.isNotEmpty) {
          await txn.rawUpdate(
            'UPDATE products SET stock = stock + ? WHERE id = ? AND business_id = ?',
            [line.quantity, line.productId, line.businessId],
          );
          final p = await txn.query('products', columns: ['stock'], where: 'id = ?', whereArgs: [line.productId], limit: 1);
          if (line.variantId != null) {
            await txn.rawUpdate(
              'UPDATE product_variants SET stock = stock + ?, updated_at = ? WHERE id = ?',
              [line.quantity, now, line.variantId],
            );
            variants[line.variantId!] = (variants[line.variantId!] ?? 0) + line.quantity;
          }
          if (p.isNotEmpty) {
            stock[line.productId] = (stock[line.productId] ?? 0) + line.quantity;
            await txn.insert('stock_movements', {
              'id': const Uuid().v4(),
              'business_id': line.businessId,
              'product_id': line.productId,
              'type': 'AJUSTE',
              'quantity': line.quantity,
              'resulting_stock': p.first['stock'] as int,
              'reason': 'Venta anulada${invoice == null ? '' : ' $invoice'}${cleanReason == null ? '' : ': $cleanReason'}',
              'date': now,
            });
          }
        }

        // Fiado: la deuda baja lo que se había fiado
        if (line.paymentMethod == PaymentMethod.credit && line.customerName != null) {
          final c = await txn.query(
            'customers',
            where: 'business_id = ? AND LOWER(name) = ?',
            whereArgs: [line.businessId, line.customerName!.toLowerCase()],
            limit: 1,
          );
          if (c.isNotEmpty) {
            final id = c.first['id'] as String;
            await txn.rawUpdate('UPDATE customers SET debt_balance = MAX(0, debt_balance - ?) WHERE id = ?', [line.totalAmount, id]);
            debts[id] = (debts[id] ?? 0) + line.totalAmount;
          }
        }

        await txn.update(
          'sales',
          {'voided_at': now, 'void_reason': cleanReason, 'voided_by': by, 'is_synced': 0},
          where: 'id = ?',
          whereArgs: [line.id],
        );
      }
    });

    DataEvents.instance.salesChanged();
    for (final line in lines) {
      // Un servicio anulado no deja comisión (si ya se pagó, queda un ajuste)
      if (line.serviceId != null) await CommissionsRepository.instance.onSaleCancelled(line.id);
    }
    final total = lines.fold<double>(0, (s, l) => s + l.totalAmount);
    final what = lines.length == 1 ? '${lines.first.quantity} × ${lines.first.productName}' : '${lines.length} productos';
    ActivityRepository.instance.log(
      businessId: sale.businessId,
      action: ActivityAction.saleCancel,
      summary: 'Anuló la venta de $what por ${CurrencyFormatter.format(total)}${cleanReason == null ? '' : ' ($cleanReason)'}',
      data: {'sale_id': sale.id, 'invoice': invoice, 'total': total},
    );

    // En la nube la venta queda marcada como anulada (no se borra)
    final cloud = SupabaseService.instance;
    final updated = await db.query('sales', where: 'id IN (${List.filled(lines.length, '?').join(',')})', whereArgs: [for (final l in lines) l.id]);
    for (final r in updated) {
      await cloud.insertSaleToCloud({...saleFromRow(r).toMap(), 'notes': r['notes'], 'customer_id': r['customer_id']});
    }
    for (final e in stock.entries) {
      await cloud.adjustProductStockInCloud(e.key, e.value);
    }
    for (final e in variants.entries) {
      await cloud.adjustVariantStockInCloud(e.key, e.value);
    }
    for (final e in debts.entries) {
      await cloud.adjustCustomerDebtInCloud(e.key, -e.value);
    }
  }
}
