import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/services/phone_alerts_service.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../team/data/activity_repository.dart';
import '../models/purchase.dart';
import '../models/supplier.dart';
import '../models/supplier_order.dart';

/// Proveedores y entradas de mercancía. Todo se guarda primero en el equipo y
/// luego se sube a la nube con la cola, como el resto de la app.
class SupplierRepository {
  SupplierRepository._();
  static final SupplierRepository instance = SupplierRepository._();

  final AppDatabase _dbProvider = AppDatabase.instance;

  // ---------------------------------------------------------------------------
  // Proveedores
  // ---------------------------------------------------------------------------

  Future<List<Supplier>> getSuppliers(String businessId) async {
    final db = await _dbProvider.database;
    final rows = await db.query(
      'suppliers',
      where: 'business_id = ? AND is_active = 1',
      whereArgs: [businessId],
      orderBy: 'name COLLATE NOCASE ASC',
    );
    return rows.map(Supplier.fromMap).toList();
  }

  /// Proveedores que pasan el día de [date] (según su "día en que pasa")
  Future<List<Supplier>> visitingOn(String businessId, DateTime date) async {
    final day = Supplier.weekDays[date.weekday - 1];
    final all = await getSuppliers(businessId);
    return [for (final s in all) if (s.visitDay == day) s];
  }

  Future<Supplier?> getSupplier(String id) async {
    final db = await _dbProvider.database;
    final rows = await db.query('suppliers', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : Supplier.fromMap(rows.first);
  }

  /// Crea un proveedor nuevo solo con lo que se sabe (el nombre basta)
  Supplier newSupplier(String businessId, String name) {
    final now = DateTime.now();
    return Supplier(
      id: const Uuid().v4(),
      businessId: businessId,
      name: name.trim(),
      createdAt: now,
      updatedAt: now,
    );
  }

  Future<void> saveSupplier(Supplier supplier) async {
    final db = await _dbProvider.database;
    final existed = (await db.query('suppliers', columns: ['id'], where: 'id = ?', whereArgs: [supplier.id])).isNotEmpty;
    final row = supplier.copyWith(updatedAt: DateTime.now()).toMap();
    if (existed) {
      await db.update('suppliers', row, where: 'id = ?', whereArgs: [supplier.id]);
    } else {
      await db.insert('suppliers', row);
    }
    SupabaseService.instance.upsertSupplierToCloud(row);
    PhoneAlertsService.instance.refreshVisitReminders();
    ActivityRepository.instance.log(
      businessId: supplier.businessId,
      action: ActivityAction.supplierChange,
      summary: existed ? 'Editó el proveedor ${supplier.name}' : 'Agregó el proveedor ${supplier.name}',
      data: {'supplier_id': supplier.id},
    );
  }

  /// Quita el proveedor; sus productos quedan sin proveedor y sus entradas se conservan
  Future<void> deleteSupplier(Supplier supplier) async {
    final db = await _dbProvider.database;
    await db.transaction((txn) async {
      await txn.delete('suppliers', where: 'id = ?', whereArgs: [supplier.id]);
      await txn.update('products', {'supplier_id': null}, where: 'supplier_id = ?', whereArgs: [supplier.id]);
    });
    SupabaseService.instance.deleteSupplierFromCloud(supplier.id);
    PhoneAlertsService.instance.refreshVisitReminders();
    ActivityRepository.instance.log(
      businessId: supplier.businessId,
      action: ActivityAction.supplierChange,
      summary: 'Quitó el proveedor ${supplier.name}',
      data: {'supplier_id': supplier.id},
    );
  }

  /// Cuántos productos tiene cada proveedor como principal
  Future<Map<String, int>> productCounts(String businessId) async {
    final db = await _dbProvider.database;
    final rows = await db.rawQuery(
      'SELECT supplier_id, COUNT(*) AS n FROM products '
      'WHERE business_id = ? AND is_active = 1 AND supplier_id IS NOT NULL GROUP BY supplier_id',
      [businessId],
    );
    return {for (final r in rows) r['supplier_id'] as String: (r['n'] as num).toInt()};
  }

  // ---------------------------------------------------------------------------
  // Entradas de mercancía
  // ---------------------------------------------------------------------------

  Future<List<Purchase>> getPurchases(String businessId, {String? supplierId}) async {
    final db = await _dbProvider.database;
    final rows = await db.query(
      'purchases',
      where: supplierId == null ? 'business_id = ?' : 'business_id = ? AND supplier_id = ?',
      whereArgs: supplierId == null ? [businessId] : [businessId, supplierId],
      orderBy: 'date DESC',
    );
    return rows.map(Purchase.fromMap).toList();
  }

  // ---------------------------------------------------------------------------
  // Pedidos a proveedores
  // ---------------------------------------------------------------------------

  /// Guarda el pedido enviado (o lo actualiza si se vuelve a enviar)
  Future<void> saveOrder(SupplierOrder order) async {
    final db = await _dbProvider.database;
    final row = order.toMap();
    await db.insert('supplier_orders', row, conflictAlgorithm: ConflictAlgorithm.replace);
    SupabaseService.instance.upsertSupplierOrderToCloud(row);
  }

  Future<SupplierOrder?> getOrder(String id) async {
    final db = await _dbProvider.database;
    final rows = await db.query('supplier_orders', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : SupplierOrder.fromMap(rows.first);
  }

  /// Pedidos del negocio, el más nuevo arriba. [pendingOnly]: los que faltan por llegar.
  Future<List<SupplierOrder>> getOrders(String businessId, {String? supplierId, bool pendingOnly = false}) async {
    final db = await _dbProvider.database;
    final where = <String>['business_id = ?'];
    final args = <Object?>[businessId];
    if (supplierId != null) {
      where.add('supplier_id = ?');
      args.add(supplierId);
    }
    if (pendingOnly) where.add("status IN ('${SupplierOrder.sent}', '${SupplierOrder.partial}')");
    final rows = await db.query('supplier_orders', where: where.join(' AND '), whereArgs: args, orderBy: 'created_at DESC');
    return rows.map(SupplierOrder.fromMap).toList();
  }

  /// Ya no se espera nada más de este pedido (lo que faltó no llegará)
  Future<SupplierOrder> closeOrder(SupplierOrder order) async {
    final closed = order.copyWith(status: SupplierOrder.closed);
    await saveOrder(closed);
    return closed;
  }

  /// Suma lo que llegó en una entrada a lo recibido del pedido y deja su estado
  @visibleForTesting
  static SupplierOrder applyReceived(SupplierOrder order, List<PurchaseItem> arrived, DateTime now) {
    final items = [
      for (final i in order.items)
        i.copyWith(
          received: i.received +
              arrived.where((a) => i.matches(a.productId, a.variantId)).fold(0, (s, a) => s + a.quantity),
        ),
    ];
    final complete = items.every((i) => i.missing == 0);
    return order.copyWith(
      items: items,
      status: complete ? SupplierOrder.received : SupplierOrder.partial,
      receivedAt: now,
    );
  }

  /// Último costo de cada producto con cada proveedor
  Future<Map<String, List<SupplierCost>>> latestCosts(String businessId) async =>
      SupplierCost.latestByProduct(await getPurchases(businessId));

  /// Cuentas por pagar: entradas a crédito sin pagar, la que vence primero arriba
  Future<List<Purchase>> getPayables(String businessId) async {
    final db = await _dbProvider.database;
    final rows = await db.query(
      'purchases',
      where: "business_id = ? AND payment_terms = 'CREDITO' AND is_paid = 0",
      whereArgs: [businessId],
      orderBy: 'COALESCE(due_date, date) ASC',
    );
    return rows.map(Purchase.fromMap).toList();
  }

  Future<Purchase?> getPurchase(String id) async {
    final db = await _dbProvider.database;
    final rows = await db.query('purchases', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : Purchase.fromMap(rows.first);
  }

  Future<Purchase> _updatePurchase(Purchase purchase) async {
    final db = await _dbProvider.database;
    final row = purchase.toMap();
    await db.update('purchases', row, where: 'id = ?', whereArgs: [purchase.id]);
    SupabaseService.instance.upsertPurchaseToCloud(row);
    return purchase;
  }

  /// Abono a una entrada a crédito. Si cubre lo que falta, queda pagada.
  Future<Purchase> addPayment(Purchase purchase, double amount, {String? note, DateTime? date}) async {
    final fresh = await getPurchase(purchase.id) ?? purchase;
    final pay = amount.clamp(0, fresh.balance).toDouble();
    if (pay <= 0) return fresh;
    final payments = [...fresh.payments, PurchasePayment(amount: pay, date: date ?? DateTime.now(), note: note)];
    final paidNow = payments.fold(0.0, (s, p) => s + p.amount) >= fresh.total - 0.5;
    final updated = await _updatePurchase(fresh.copyWith(payments: payments, isPaid: paidNow));
    final who = (fresh.supplierName ?? '').isEmpty ? '' : ' a ${fresh.supplierName}';
    ActivityRepository.instance.log(
      businessId: fresh.businessId,
      action: ActivityAction.supplierPayment,
      summary: paidNow
          ? 'Pagó$who la entrada de ${CurrencyFormatter.format(fresh.total)} (último abono ${CurrencyFormatter.format(pay)})'
          : 'Abonó ${CurrencyFormatter.format(pay)}$who (falta ${CurrencyFormatter.format(updated.balance)})',
      data: {'purchase_id': fresh.id},
    );
    return updated;
  }

  /// Marca pagado todo lo que faltaba
  Future<Purchase> markPaid(Purchase purchase) async {
    final fresh = await getPurchase(purchase.id) ?? purchase;
    if (fresh.isPaid) return fresh;
    return addPayment(fresh, fresh.balance, note: 'Pago total');
  }

  /// Guarda la ruta de la foto de la factura
  Future<Purchase> setPhoto(Purchase purchase, String photoPath) async {
    final fresh = await getPurchase(purchase.id) ?? purchase;
    return _updatePurchase(fresh.copyWith(photoPath: photoPath));
  }

  /// Guarda la entrada y suma lo que llegó al inventario (producto y talla/color).
  /// [newCosts] trae el costo nuevo de los productos a los que el usuario le
  /// aceptó actualizarlo.
  Future<void> registerPurchase(Purchase purchase, {Map<String, double> newCosts = const {}}) async {
    final db = await _dbProvider.database;
    final now = DateTime.now().toIso8601String();
    final byProduct = <String, int>{};
    for (final item in purchase.items) {
      if (item.quantity <= 0) continue;
      byProduct[item.productId] = (byProduct[item.productId] ?? 0) + item.quantity;
    }
    final costChanged = <String, Map<String, Object?>>{};

    await db.transaction((txn) async {
      await txn.insert('purchases', purchase.toMap());
      for (final item in purchase.items) {
        if (item.quantity <= 0 || item.variantId == null) continue;
        await txn.rawUpdate(
          'UPDATE product_variants SET stock = stock + ?, updated_at = ? WHERE id = ? AND product_id = ?',
          [item.quantity, now, item.variantId, item.productId],
        );
      }
      for (final entry in byProduct.entries) {
        final rows = await txn.query('products', columns: ['stock', 'supplier_id'], where: 'id = ?', whereArgs: [entry.key]);
        if (rows.isEmpty) continue;
        final newStock = (rows.first['stock'] as num).toInt() + entry.value;
        // El proveedor de la entrada queda como principal si el producto no tenía
        final takesSupplier = purchase.supplierId != null && rows.first['supplier_id'] == null;
        await txn.update(
          'products',
          {
            'stock': newStock,
            'updated_at': now,
            if (newCosts.containsKey(entry.key)) 'purchase_price': newCosts[entry.key],
            if (takesSupplier) 'supplier_id': purchase.supplierId,
          },
          where: 'id = ?',
          whereArgs: [entry.key],
        );
        if (newCosts.containsKey(entry.key) || takesSupplier) {
          final changed = await txn.query('products', where: 'id = ?', whereArgs: [entry.key]);
          if (changed.isNotEmpty) costChanged[entry.key] = changed.first;
        }
        await txn.insert('stock_movements', {
          'id': const Uuid().v4(),
          'business_id': purchase.businessId,
          'product_id': entry.key,
          'type': 'ENTRADA_COMPRA',
          'quantity': entry.value,
          'resulting_stock': newStock,
          'reason': [
            'Entrada de mercancía',
            if ((purchase.supplierName ?? '').isNotEmpty) purchase.supplierName,
            if ((purchase.invoiceNumber ?? '').isNotEmpty) 'factura ${purchase.invoiceNumber}',
          ].join(' · '),
          'date': purchase.date.toIso8601String(),
        });
      }
    });

    // Nube: la entrada, las existencias por diferencia (no pisan ventas de otros
    // equipos) y los productos con costo o proveedor nuevo
    final cloud = SupabaseService.instance;
    cloud.upsertPurchaseToCloud(purchase.toMap());
    for (final item in purchase.items) {
      if (item.quantity > 0 && item.variantId != null) {
        cloud.adjustVariantStockInCloud(item.variantId!, item.quantity);
      }
    }
    for (final entry in byProduct.entries) {
      cloud.adjustProductStockInCloud(entry.key, entry.value);
      final row = costChanged[entry.key];
      if (row != null) cloud.upsertProductToCloud(row);
    }

    // Si la entrada recibe un pedido, se anota lo que llegó contra lo pedido
    final orderId = purchase.orderId;
    if (orderId != null) {
      final order = await getOrder(orderId);
      if (order != null) await saveOrder(applyReceived(order, purchase.items, DateTime.now()));
    }

    final who = (purchase.supplierName ?? '').isEmpty ? '' : ' de ${purchase.supplierName}';
    ActivityRepository.instance.log(
      businessId: purchase.businessId,
      action: ActivityAction.purchase,
      summary: 'Recibió ${purchase.units} unidades$who por ${CurrencyFormatter.format(purchase.total)}'
          '${purchase.isCredit ? ' (a crédito)' : ''}',
      data: {'purchase_id': purchase.id},
    );
  }
}
