import '../../business/data/branch_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/services/supabase_service.dart';
import '../../sales/models/quotation.dart';
import '../../../core/utils/business_clock.dart';

/// Un pedido que acaba de llegar
typedef NewStoreOrder = ({String id, String code, String? name, double total});

/// Quién avisa de los pedidos (la campana y el celular). Lo conecta la navegación
/// de la app; así este repositorio no depende de las pantallas ni de los avisos.
abstract final class OrderAlerts {
  static void Function(NewStoreOrder order)? onNewOrder;
  static void Function(({String id, String code, String? name}) order)? onReminder;
}

/// Pedidos de la tienda en línea (0.13.4): el comprador los crea en la nube con su
/// código (T-0001) y aquí se bajan como cotizaciones «Tienda» para pasarlos a venta.
/// Vencen a los 7 días sin borrarse.
class StoreOrdersRepository {
  StoreOrdersRepository._();
  static final StoreOrdersRepository instance = StoreOrdersRepository._();

  static const validDays = 7;

  /// Pedidos sin ver: el número de Ventas y de Cotizaciones. Se pone en 0 al abrir Cotizaciones.
  final ValueNotifier<int> unseen = ValueNotifier(0);

  /// Si un pedido lleva este tiempo sin abrir, se recuerda una vez
  static const remindAfter = Duration(hours: 2);

  static String _seenKey(String businessId) => 'orders_seen_at_$businessId';
  static const _remindedKey = 'orders_reminded';

  /// Recalcula cuántos pedidos llegaron después de la última vez que se abrió Cotizaciones
  Future<int> refreshUnseen(String businessId) async {
    final db = await AppDatabase.instance.database;
    final seen = await AppDatabase.instance.getSetting(_seenKey(businessId)) ?? '';
    final now = appNow().toIso8601String();
    final n = Sqflite.firstIntValue(await db.rawQuery(
          "SELECT COUNT(*) FROM quotations WHERE business_id = ? AND source = ? AND status = 'PENDIENTE' "
          'AND created_at > ? AND (valid_until IS NULL OR valid_until > ?)',
          [businessId, Quotation.sourceStore, seen, now],
        )) ??
        0;
    unseen.value = n;
    return n;
  }

  /// Se abrió Cotizaciones: el número se quita (los pedidos siguen «Por confirmar»)
  Future<void> markAllSeen(String businessId) async {
    await AppDatabase.instance.setSetting(_seenKey(businessId), appNow().toIso8601String());
    unseen.value = 0;
  }

  /// Se abrió un pedido: se quita su marca «Nuevo»
  Future<void> markOpened(String quotationId) async {
    final db = await AppDatabase.instance.database;
    await db.update('quotations', {'opened_at': appNow().toIso8601String()},
        where: 'id = ? AND opened_at IS NULL', whereArgs: [quotationId]);
  }

  /// Pedidos que llevan más de [remindAfter] sin abrir y todavía no se recordaron.
  /// Se marcan como recordados (una sola vez cada uno).
  Future<List<({String id, String code, String? name})>> dueReminders(String businessId, {DateTime? now}) async {
    final db = await AppDatabase.instance.database;
    final at = now ?? appNow();
    final rows = await db.rawQuery(
      "SELECT id, quotation_number, customer_name FROM quotations WHERE business_id = ? AND source = ? AND status = 'PENDIENTE' "
      'AND opened_at IS NULL AND created_at <= ? AND (valid_until IS NULL OR valid_until > ?)',
      [businessId, Quotation.sourceStore, at.subtract(remindAfter).toIso8601String(), at.toIso8601String()],
    );
    final reminded = {...?(await AppDatabase.instance.getSetting(_remindedKey))?.split(',')};
    final due = [
      for (final r in rows)
        if (!reminded.contains(r['id']))
          (id: r['id'] as String, code: r['quotation_number'] as String, name: r['customer_name'] as String?),
    ];
    if (due.isNotEmpty) {
      reminded.addAll(due.map((d) => d.id));
      // Solo se guardan los últimos 200
      final keep = reminded.where((e) => e.isNotEmpty).toList();
      await AppDatabase.instance.setSetting(_remindedKey, keep.skip(keep.length > 200 ? keep.length - 200 : 0).join(','));
    }
    return due;
  }

  /// Trae los pedidos nuevos de la nube y avisa: cada pedido nuevo, y una vez los que
  /// llevan 2 horas sin abrir. Devuelve cuántos llegaron. Sin conexión no hace nada.
  Future<int> pull(String businessId) async {
    final arrived = await _download(businessId);
    for (final o in arrived) {
      OrderAlerts.onNewOrder?.call(o);
    }
    for (final r in await dueReminders(businessId)) {
      OrderAlerts.onReminder?.call(r);
    }
    await refreshUnseen(businessId);
    return arrived.length;
  }

  Future<List<NewStoreOrder>> _download(String businessId) async {
    final client = SupabaseService.instance.client;
    if (client == null || client.auth.currentSession == null) return const [];
    try {
      final rows = await client.from('store_orders').select().eq('business_id', businessId).eq('status', 'PENDIENTE');
      final db = await AppDatabase.instance.database;
      final added = <NewStoreOrder>[];
      for (final raw in rows) {
        final o = Map<String, dynamic>.from(raw as Map);
        final id = o['id'] as String;
        final exists = await db.query('quotations', columns: ['id'], where: 'id = ?', whereArgs: [id], limit: 1);
        if (exists.isNotEmpty) continue;
        final created = (DateTime.tryParse('${o['created_at']}') ?? appNow()).toLocal();
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
              // Cupón de la tienda (0.16.0): el descuento pasa a la venta al facturarlo
              'discount_amount': (o['discount'] as num?)?.toDouble() ?? 0.0,
              'notes': _notes(o),
              'status': 'PENDIENTE',
              'valid_until': created.add(const Duration(days: validDays)).toIso8601String(),
              'created_at': created.toIso8601String(),
              'source': Quotation.sourceStore,
              // Sede donde se pidió (0.18.3): el pedido sale en esa sede
              if ((o['branch_id'] as String?)?.isNotEmpty == true) 'branch_id': o['branch_id'],
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
        added.add((
          id: id,
          code: o['code'] as String,
          name: o['customer_name'] as String?,
          total: (o['total'] as num?)?.toDouble() ?? 0,
        ));
      }
      return added;
    } catch (e) {
      debugPrint('Pedidos de la tienda: $e');
      return const [];
    }
  }

  /// La nota del pedido y, si trae cupón, cuál fue
  static String? _notes(Map<String, dynamic> o) {
    final note = (o['note'] as String?)?.trim() ?? '';
    final coupon = o['coupon_code'] as String?;
    final branch = (o['branch_id'] as String?)?.isNotEmpty == true ? BranchRepository.instance.nameOf(o['branch_id'] as String) : null;
    final parts = [
      if (branch != null) 'Pedido en $branch',
      if (coupon != null && coupon.isNotEmpty) 'Cupón $coupon',
      if (note.isNotEmpty) note,
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  /// Cuántos pedidos de la tienda esperan confirmación (sin vencer)
  Future<int> pendingCount(String businessId) async {
    final db = await AppDatabase.instance.database;
    final now = appNow().toIso8601String();
    return Sqflite.firstIntValue(await db.rawQuery(
          "SELECT COUNT(*) FROM quotations WHERE business_id = ? AND source = ? AND status = 'PENDIENTE' "
          'AND (valid_until IS NULL OR valid_until > ?)',
          [businessId, Quotation.sourceStore, now],
        )) ??
        0;
  }
}
