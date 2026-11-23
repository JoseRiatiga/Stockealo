import 'dart:math' as math;

import '../../../core/database/app_database.dart';
import '../../../core/utils/business_clock.dart';
import '../models/supplier.dart';

/// Lo que se sugiere pedir de un producto (o de una talla/color) y por qué
class RestockAdvice {
  final int quantity;

  /// «Vendes 4 por semana; te alcanza para 3 días». Null si no hay ventas recientes.
  final String? why;

  const RestockAdvice(this.quantity, {this.why});
}

/// Pedido sugerido al proveedor (0.17.0, bloque D): según lo que se vendió en los
/// últimos 30 días y los días hasta la próxima visita del proveedor. Sin ventas
/// recientes se queda la regla de antes (reponer hasta el doble del mínimo).
class RestockPlanner {
  RestockPlanner._();

  /// Días de ventas que se miran
  static const days = 30;

  /// Sin día de visita, el pedido alcanza para dos semanas
  static const defaultHorizon = 14;

  /// Clave de las ventas de un producto o de una talla/color
  static String key(String productId, [String? variantId]) => variantId == null ? productId : '$productId|$variantId';

  /// Unidades vendidas en los últimos 30 días, ya sin anuladas y restando devoluciones
  /// (las devoluciones se guardan con cantidad negativa). Por producto y por variante.
  static Future<Map<String, int>> soldLastDays(String businessId, {DateTime? now}) async {
    final since = (now ?? appNow()).subtract(const Duration(days: days)).toIso8601String();
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery(
      'SELECT product_id, variant_id, SUM(quantity) AS sold FROM sales_ok '
      'WHERE business_id = ? AND product_id IS NOT NULL AND date >= ? GROUP BY product_id, variant_id',
      [businessId, since],
    );
    final out = <String, int>{};
    for (final r in rows) {
      final sold = (r['sold'] as num?)?.toInt() ?? 0;
      final product = r['product_id'] as String;
      final variant = r['variant_id'] as String?;
      out[key(product)] = (out[key(product)] ?? 0) + sold;
      if (variant != null) out[key(product, variant)] = (out[key(product, variant)] ?? 0) + sold;
    }
    out.removeWhere((_, v) => v <= 0);
    return out;
  }

  /// Unidades por día: lo vendido entre 30 días o, si el producto es más nuevo, entre
  /// los días que lleva (mínimo 1)
  static double perDay(int sold, {required DateTime createdAt, required DateTime now}) {
    if (sold <= 0) return 0;
    final age = now.difference(createdAt).inDays.clamp(1, days);
    return sold / age;
  }

  /// Días que tiene que alcanzar el pedido: hasta la próxima visita y una semana más
  /// (hasta la visita siguiente). Sin día de visita, dos semanas.
  static int horizon(Supplier? supplier, DateTime now) {
    final day = Supplier.weekDays.indexOf(supplier?.visitDay ?? '');
    if (day < 0) return defaultHorizon;
    final untilVisit = (day + 1 - now.weekday) % 7;
    return untilVisit + 7;
  }

  /// Cuánto pedir para que alcance [horizonDays]. Sin ventas recientes: la regla de
  /// antes ([fallback]). Con ventas: lo que se venderá en ese tiempo (y por lo menos una
  /// unidad más que el mínimo), menos lo que hay.
  static RestockAdvice advise({
    required int stock,
    required int minStock,
    required double perDay,
    required int horizonDays,
    required int fallback,
  }) {
    if (perDay <= 0) return RestockAdvice(fallback);
    // Nunca queda justo en el mínimo (seguiría saliendo «por reponer»)
    final target = math.max((perDay * horizonDays).ceil(), minStock > 0 ? minStock + 1 : 0);
    final int qty = math.max(0, target - math.max(0, stock));
    return RestockAdvice(qty, why: why(perDay, stock));
  }

  /// Hace falta pedir aunque no esté en el mínimo: no alcanza hasta la próxima visita
  static bool runsOut({required int stock, required double perDay, required int horizonDays}) =>
      perDay > 0 && stock < perDay * horizonDays;

  /// «Vendes 4 por semana; te alcanza para 3 días»
  static String why(double perDay, int stock) {
    final week = perDay * 7;
    final pace = week >= 1 ? 'Vendes ${week.round()} por semana' : 'Vendes ${(perDay * 30).round()} al mes';
    if (stock <= 0) return '$pace; está agotado';
    final left = (stock / perDay).floor();
    if (left > 60) return pace;
    return '$pace; te alcanza para ${left <= 1 ? (left == 1 ? '1 día' : 'menos de un día') : '$left días'}';
  }
}
