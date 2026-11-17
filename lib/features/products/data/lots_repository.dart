import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/services/supabase_service.dart';
import '../../team/data/activity_repository.dart';
import '../models/product_lot.dart';
import '../../../core/utils/business_clock.dart';

/// Lotes con vencimiento (0.16.0, fase 2b, decisiones del 15 nov):
/// • Solo en productos con «Controla vencimiento por lote» y sin tallas ni colores.
/// • Los lotes se cuadran solos contra el stock del producto ([reconcile]): si el stock
///   bajó (ventas, mermas), se descuenta del lote que vence antes; si subió sin lote
///   (una venta anulada, el stock inicial) esas unidades quedan «sin fecha».
/// • Un lote vencido sale del stock vendible (no se vende ni sale en la tienda) y espera
///   el cambio con el proveedor o la baja.
class LotsRepository {
  static final LotsRepository instance = LotsRepository._();
  LotsRepository._();

  /// Cambia al moverse un lote: el aviso de Inicio y la ficha del producto se recargan
  final ValueNotifier<int> version = ValueNotifier<int>(0);

  Future<Database> get _db => AppDatabase.instance.database;

  static const soonDays = 30;

  Future<List<ProductLot>> lotsFor(String productId) async {
    final rows = await (await _db).query('product_lots', where: 'product_id = ?', whereArgs: [productId], orderBy: 'expires_on');
    return [for (final r in rows) ProductLot.fromMap(r)];
  }

  Future<List<ProductLot>> lotsOfBusiness(String businessId) async {
    final rows = await (await _db).query('product_lots', where: 'business_id = ?', whereArgs: [businessId], orderBy: 'expires_on');
    return [for (final r in rows) ProductLot.fromMap(r)];
  }

  Future<List<LotExchange>> exchanges(String businessId, {bool onlyPending = false}) async {
    final rows = await (await _db).query(
      'lot_exchanges',
      where: onlyPending ? 'business_id = ? AND status = ?' : 'business_id = ?',
      whereArgs: onlyPending ? [businessId, LotExchange.pending] : [businessId],
      orderBy: 'created_at DESC',
    );
    return [for (final r in rows) LotExchange.fromMap(r)];
  }

  /// Unidades del producto que no tienen lote («sin fecha»)
  Future<int> undated(String productId) async {
    final db = await _db;
    final p = await db.query('products', columns: ['stock'], where: 'id = ?', whereArgs: [productId], limit: 1);
    if (p.isEmpty) return 0;
    final lots = await db.rawQuery(
      "SELECT COALESCE(SUM(quantity), 0) AS q FROM product_lots WHERE product_id = ? AND status = 'ACTIVE'",
      [productId],
    );
    final left = (p.first['stock'] as num).toInt() - ((lots.first['q'] as num?)?.toInt() ?? 0);
    return left < 0 ? 0 : left;
  }

  /// Guarda en el celular. La subida a la nube va después de la transacción
  /// ([_upload]): la cola de la nube también escribe en la base y se trabarían.
  Future<void> _save(DatabaseExecutor db, ProductLot lot) =>
      db.insert('product_lots', lot.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);

  Future<void> _saveExchange(DatabaseExecutor db, LotExchange e) =>
      db.insert('lot_exchanges', e.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);

  void _upload({List<ProductLot> lots = const [], List<LotExchange> exchanges = const []}) {
    for (final l in lots) {
      SupabaseService.instance.upsertProductLotToCloud(l.toMap());
    }
    for (final e in exchanges) {
      SupabaseService.instance.upsertLotExchangeToCloud(e.toMap());
    }
  }

  /// Anota un lote. No cambia el stock: quien lo llama ya sumó las unidades (la entrada
  /// de mercancía o el ajuste), o son unidades que estaban «sin fecha».
  Future<ProductLot> addLot({
    required String businessId,
    required String productId,
    required int quantity,
    required DateTime expiresOn,
    String? code,
    double cost = 0,
    String source = 'ENTRADA',
    String? purchaseId,
    DateTime? now,
  }) async {
    final at = now ?? appNow();
    final lot = ProductLot(
      id: const Uuid().v4(),
      businessId: businessId,
      productId: productId,
      code: (code ?? '').trim().isEmpty ? null : code!.trim(),
      expiresOn: ProductLot.day(expiresOn),
      quantity: quantity,
      initialQuantity: quantity,
      cost: cost,
      source: source,
      purchaseId: purchaseId,
      createdAt: at,
      updatedAt: at,
    );
    await _save(await _db, lot);
    _upload(lots: [lot]);
    version.value++;
    return lot;
  }

  /// Cuadra los lotes con el stock y saca del stock vendible lo que ya venció.
  /// Se llama al abrir Inicio, Stock y la ficha del producto.
  Future<void> reconcile(String businessId, {DateTime? now}) async {
    final at = now ?? appNow();
    final db = await _db;
    final products = await db.query(
      'products',
      columns: ['id', 'name', 'stock'],
      where: 'business_id = ? AND tracks_expiry = 1 AND COALESCE(has_variants, 0) = 0 AND COALESCE(is_active, 1) = 1',
      whereArgs: [businessId],
    );
    var changed = false;
    for (final p in products) {
      final productId = p['id'] as String;
      var stock = (p['stock'] as num).toInt();
      final lots = [
        for (final r in await db.query('product_lots',
            where: "product_id = ? AND status = 'ACTIVE' AND quantity > 0", whereArgs: [productId], orderBy: 'expires_on, created_at'))
          ProductLot.fromMap(r),
      ];
      // 1. Lo que se vendió o se dio de baja sale del lote que vence antes
      var excess = lots.fold<int>(0, (s, l) => s + l.quantity) - (stock < 0 ? 0 : stock);
      for (var i = 0; i < lots.length && excess > 0; i++) {
        final take = excess < lots[i].quantity ? excess : lots[i].quantity;
        final left = lots[i].quantity - take;
        lots[i] = lots[i].copyWith(quantity: left, status: left == 0 ? ProductLot.used : null, updatedAt: at);
        await _save(db, lots[i]);
        _upload(lots: [lots[i]]);
        excess -= take;
        changed = true;
      }
      // 2. Lo vencido sale del stock vendible
      for (final lot in lots.where((l) => l.status == ProductLot.active && l.quantity > 0 && l.isExpiredOn(at))) {
        stock -= lot.quantity;
        await db.transaction((txn) async {
          await txn.rawUpdate('UPDATE products SET stock = MAX(0, stock - ?), updated_at = ? WHERE id = ?',
              [lot.quantity, at.toIso8601String(), productId]);
          await txn.insert('stock_movements', {
            'id': const Uuid().v4(),
            'business_id': businessId,
            'product_id': productId,
            'type': 'VENCIDO',
            'quantity': lot.quantity,
            'resulting_stock': stock < 0 ? 0 : stock,
            'reason': 'Lote ${lot.code ?? ''} vencido el ${ProductLot.dayText(lot.expiresOn)}'.replaceAll('  ', ' '),
            'date': at.toIso8601String(),
          });
          await _save(txn, lot.copyWith(status: ProductLot.expired, updatedAt: at));
        });
        _upload(lots: [lot.copyWith(status: ProductLot.expired, updatedAt: at)]);
        SupabaseService.instance.adjustProductStockInCloud(productId, -lot.quantity);
        changed = true;
      }
    }
    if (changed) version.value++;
  }

  /// Ponerle fecha a las unidades que no tenían lote
  Future<ProductLot> dateUndated(String businessId, String productId, {required int quantity, required DateTime expiresOn, String? code}) =>
      addLot(businessId: businessId, productId: productId, quantity: quantity, expiresOn: expiresOn, code: code, source: 'SIN_FECHA');

  /// «Devolver al proveedor para cambio»: el lote vencido queda en un cambio pendiente
  /// El lote como está guardado ahora (la pantalla puede tener uno viejo)
  Future<ProductLot?> _freshLot(String id) async {
    final rows = await (await _db).query('product_lots', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : ProductLot.fromMap(rows.first);
  }

  Future<LotExchange?> _freshExchange(String id) async {
    final rows = await (await _db).query('lot_exchanges', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : LotExchange.fromMap(rows.first);
  }

  Future<LotExchange> sendToExchange(ProductLot shown, {required String productName, String? supplierId, String? supplierName}) async {
    final lot = await _freshLot(shown.id);
    if (lot == null || lot.status != ProductLot.expired) throw StateError('Solo se devuelve un lote vencido.');
    final at = appNow();
    final db = await _db;
    final exchange = LotExchange(
      id: const Uuid().v4(),
      businessId: lot.businessId,
      productId: lot.productId,
      productName: productName,
      lotId: lot.id,
      supplierId: supplierId,
      supplierName: supplierName,
      quantity: lot.quantity,
      createdAt: at,
    );
    final returnedLot = lot.copyWith(status: ProductLot.returned, updatedAt: at);
    await db.transaction((txn) async {
      await _save(txn, returnedLot);
      await _saveExchange(txn, exchange);
    });
    _upload(lots: [returnedLot], exchanges: [exchange]);
    ActivityRepository.instance.log(
      businessId: lot.businessId,
      action: ActivityAction.stockAdjust,
      summary: 'Devolvió ${lot.quantity} × $productName vencidos${supplierName == null ? '' : ' a $supplierName'} para cambio',
      data: {'lot_id': lot.id, 'exchange_id': exchange.id},
    );
    version.value++;
    return exchange;
  }

  /// «Llegó el cambio»: entra un lote nuevo sin costo y vuelve al stock
  Future<ProductLot> receiveExchange(LotExchange shown, {required DateTime expiresOn, String? code, int? quantity}) async {
    final exchange = await _freshExchange(shown.id);
    if (exchange == null || !exchange.isPending) throw StateError('Ese cambio ya se cerró.');
    final qty = quantity ?? exchange.quantity;
    final at = appNow();
    final db = await _db;
    final lot = ProductLot(
      id: const Uuid().v4(),
      businessId: exchange.businessId,
      productId: exchange.productId,
      code: (code ?? '').trim().isEmpty ? null : code!.trim(),
      expiresOn: ProductLot.day(expiresOn),
      quantity: qty,
      initialQuantity: qty,
      source: 'CAMBIO',
      createdAt: at,
      updatedAt: at,
    );
    await db.transaction((txn) async {
      await txn.rawUpdate('UPDATE products SET stock = stock + ?, updated_at = ? WHERE id = ?', [qty, at.toIso8601String(), exchange.productId]);
      final p = await txn.query('products', columns: ['stock'], where: 'id = ?', whereArgs: [exchange.productId], limit: 1);
      await txn.insert('stock_movements', {
        'id': const Uuid().v4(),
        'business_id': exchange.businessId,
        'product_id': exchange.productId,
        'type': 'AJUSTE',
        'quantity': qty,
        'resulting_stock': p.isEmpty ? qty : p.first['stock'] as int,
        'reason': 'Cambio de lote vencido${exchange.supplierName == null ? '' : ' · ${exchange.supplierName}'}',
        'date': at.toIso8601String(),
      });
      await _save(txn, lot);
      await _saveExchange(txn, exchange.copyWith(status: LotExchange.received, newLotId: lot.id, closedAt: at));
    });
    _upload(lots: [lot], exchanges: [exchange.copyWith(status: LotExchange.received, newLotId: lot.id, closedAt: at)]);
    SupabaseService.instance.adjustProductStockInCloud(exchange.productId, qty);
    ActivityRepository.instance.log(
      businessId: exchange.businessId,
      action: ActivityAction.stockAdjust,
      summary: 'Llegó el cambio: $qty × ${exchange.productName}${exchange.supplierName == null ? '' : ' de ${exchange.supplierName}'}',
      data: {'exchange_id': exchange.id, 'lot_id': lot.id},
    );
    version.value++;
    return lot;
  }

  /// «Dar de baja»: el lote vencido (o el cambio que no llegó) queda como merma
  Future<void> writeOff(ProductLot shown, {required String productName, LotExchange? exchange}) async {
    final lot = await _freshLot(shown.id);
    if (lot == null || (lot.status != ProductLot.expired && lot.status != ProductLot.returned)) {
      throw StateError('Ese lote ya no se puede dar de baja.');
    }
    if (exchange != null && (await _freshExchange(exchange.id))?.isPending != true) throw StateError('Ese cambio ya se cerró.');
    final at = appNow();
    final db = await _db;
    await db.transaction((txn) async {
      final p = await txn.query('products', columns: ['stock'], where: 'id = ?', whereArgs: [lot.productId], limit: 1);
      // Las unidades ya habían salido del stock al vencerse: aquí solo se anota la pérdida
      await txn.insert('stock_movements', {
        'id': const Uuid().v4(),
        'business_id': lot.businessId,
        'product_id': lot.productId,
        'type': 'MERMA',
        'quantity': lot.quantity,
        'resulting_stock': p.isEmpty ? 0 : p.first['stock'] as int,
        'reason': 'Lote vencido dado de baja${lot.code == null ? '' : ' (${lot.code})'}',
        'date': at.toIso8601String(),
      });
      await _save(txn, lot.copyWith(status: ProductLot.writtenOff, updatedAt: at));
      if (exchange != null) await _saveExchange(txn, exchange.copyWith(status: LotExchange.writtenOff, closedAt: at));
    });
    _upload(
      lots: [lot.copyWith(status: ProductLot.writtenOff, updatedAt: at)],
      exchanges: [if (exchange != null) exchange.copyWith(status: LotExchange.writtenOff, closedAt: at)],
    );
    ActivityRepository.instance.log(
      businessId: lot.businessId,
      action: ActivityAction.shrinkage,
      summary: 'Dio de baja ${lot.quantity} × $productName vencidos',
      data: {'lot_id': lot.id},
    );
    version.value++;
  }

  /// Nombre y proveedor de los productos del negocio, para las listas de lotes
  Future<Map<String, ({String name, String? supplierId})>> productNames(String businessId) async {
    final rows = await (await _db).query('products', columns: ['id', 'name', 'supplier_id'], where: 'business_id = ?', whereArgs: [businessId]);
    return {for (final r in rows) r['id'] as String: (name: r['name'] as String? ?? 'Producto', supplierId: r['supplier_id'] as String?)};
  }

  /// Lo del aviso de Inicio y Stock
  Future<({List<ProductLot> expired, List<ProductLot> soon, List<LotExchange> pending})> alerts(String businessId, {DateTime? now}) async {
    final at = now ?? appNow();
    final lots = await lotsOfBusiness(businessId);
    return (
      expired: lots.where((l) => l.status == ProductLot.expired && l.quantity > 0).toList(),
      soon: lots.where((l) => l.status == ProductLot.active && l.quantity > 0 && l.expiresSoon(at, days: soonDays)).toList(),
      pending: await exchanges(businessId, onlyPending: true),
    );
  }
}
