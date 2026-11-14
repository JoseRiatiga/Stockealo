import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/services/supabase_service.dart';
import '../../sales/models/quotation.dart';

/// Pedidos de la tienda en línea (0.13.4): el comprador los crea en la nube con su
/// código (T-0001) y aquí se bajan como cotizaciones «Tienda» para pasarlos a venta.
/// Vencen a los 7 días sin borrarse.
class StoreOrdersRepository {
  StoreOrdersRepository._();
  static final StoreOrdersRepository instance = StoreOrdersRepository._();

  static const validDays = 7;

  /// Trae los pedidos nuevos de la nube. Devuelve cuántos llegaron. Sin conexión no hace nada.
  Future<int> pull(String businessId) async {
    final client = SupabaseService.instance.client;
    if (client == null || client.auth.currentSession == null) return 0;
    try {
      final rows = await client.from('store_orders').select().eq('business_id', businessId).eq('status', 'PENDIENTE');
      final db = await AppDatabase.instance.database;
      var added = 0;
      for (final raw in rows) {
        final o = Map<String, dynamic>.from(raw as Map);
        final id = o['id'] as String;
        final exists = await db.query('quotations', columns: ['id'], where: 'id = ?', whereArgs: [id], limit: 1);
        if (exists.isNotEmpty) continue;
        final created = (DateTime.tryParse('${o['created_at']}') ?? DateTime.now()).toLocal();
        await db.transaction((txn) async {
          await txn.insert(
            'quotations',
            {
              'id': id,
              'business_id': businessId,
              'quotation_number': o['code'] as String,
              'customer_name': o['customer_name'],
              'customer_phone': o['customer_phone'],
              'total_amount': (o['total'] as num?)?.toDouble() ?? 0,
              'discount_amount': 0.0,
              'notes': o['note'],
              'status': 'PENDIENTE',
              'valid_until': created.add(const Duration(days: validDays)).toIso8601String(),
              'created_at': created.toIso8601String(),
              'source': Quotation.sourceStore,
            },
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
          for (final l in (o['lines'] as List? ?? const [])) {
            final line = Map<String, dynamic>.from(l as Map);
            final qty = (line['quantity'] as num?)?.toInt() ?? 1;
            final price = (line['unit_price'] as num?)?.toDouble() ?? 0;
            await txn.insert('quotation_items', {
              'id': const Uuid().v4(),
              'quotation_id': id,
              'product_id': line['product_id'] ?? '',
              'product_name': line['name'] ?? 'Producto',
              'quantity': qty,
              'unit_price': price,
              'subtotal': (line['subtotal'] as num?)?.toDouble() ?? price * qty,
              'variant_id': line['variant_id'],
              'variant_name': line['variant_name'],
            });
          }
        });
        added++;
      }
      return added;
    } catch (e) {
      debugPrint('Pedidos de la tienda: $e');
      return 0;
    }
  }

  /// Cuántos pedidos de la tienda esperan confirmación (sin vencer)
  Future<int> pendingCount(String businessId) async {
    final db = await AppDatabase.instance.database;
    final now = DateTime.now().toIso8601String();
    return Sqflite.firstIntValue(await db.rawQuery(
          "SELECT COUNT(*) FROM quotations WHERE business_id = ? AND source = ? AND status = 'PENDIENTE' "
          'AND (valid_until IS NULL OR valid_until > ?)',
          [businessId, Quotation.sourceStore, now],
        )) ??
        0;
  }
}
