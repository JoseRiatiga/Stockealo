import 'dart:convert';

/// Una promoción del negocio (0.13.4, para todos los planes): un nombre libre
/// («Fin de mes», «2×1 en camisetas»), unas fechas y a qué productos aplica.
/// Se apaga sola al terminar las fechas; los precios normales no se tocan.
class Promotion {
  /// % de descuento (por ejemplo 20 %)
  static const percent = 'PERCENT';

  /// Lleva X, paga Y (2×1, 3×2…)
  static const buyXPayY = 'BUY_X_PAY_Y';

  /// A todo el inventario, a una categoría o a productos marcados
  static const scopeAll = 'ALL';
  static const scopeCategory = 'CATEGORY';
  static const scopeProducts = 'PRODUCTS';

  final String id;
  final String businessId;
  final String name;
  final String kind;

  /// Con [percent]: cuánto se rebaja (1 a 90)
  final double percentOff;

  /// Con [buyXPayY]: lleva [buyQty], paga [payQty]
  final int buyQty;
  final int payQty;

  final String scope;
  final String? category;
  final List<String> productIds;
  final DateTime startsAt;
  final DateTime endsAt;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Promotion({
    required this.id,
    required this.businessId,
    required this.name,
    required this.kind,
    this.percentOff = 0,
    this.buyQty = 2,
    this.payQty = 1,
    this.scope = scopeAll,
    this.category,
    this.productIds = const [],
    required this.startsAt,
    required this.endsAt,
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isPercent => kind == percent;

  /// En la cinta: «−20 %» o «2×1»
  String get badge => isPercent ? '−${percentOff.round()} %' : '$buyQty×$payQty';

  /// Vale en ese momento (encendida y dentro de las fechas)
  bool isLiveAt(DateTime t) => isActive && !t.isBefore(startsAt) && t.isBefore(endsAt);

  /// Ya terminó
  bool isOverAt(DateTime t) => !t.isBefore(endsAt);

  bool appliesTo({required String productId, required String category}) => switch (scope) {
        scopeCategory => this.category != null && this.category!.trim().toLowerCase() == category.trim().toLowerCase(),
        scopeProducts => productIds.contains(productId),
        _ => true,
      };

  /// Cuánto se descuenta a [quantity] unidades de [unitPrice]
  double discountFor(double unitPrice, int quantity) {
    if (quantity <= 0 || unitPrice <= 0) return 0;
    if (isPercent) return (unitPrice * quantity * percentOff / 100).roundToDouble();
    if (buyQty <= payQty || buyQty <= 0) return 0;
    return (quantity ~/ buyQty) * (buyQty - payQty) * unitPrice;
  }

  /// Precio con la promoción (solo % de descuento; el 2×1 no cambia el precio unitario)
  double priceWith(double unitPrice) =>
      isPercent ? (unitPrice * (100 - percentOff) / 100).roundToDouble() : unitPrice;

  /// La que más rebaja de las que valen para ese producto
  static Promotion? best(Iterable<Promotion> all, {required String productId, required String category,
      required double unitPrice, required int quantity, required DateTime at}) {
    Promotion? best;
    var bestOff = 0.0;
    for (final p in all) {
      if (!p.isLiveAt(at) || !p.appliesTo(productId: productId, category: category)) continue;
      final off = p.discountFor(unitPrice, quantity);
      // Un 2×1 que todavía no se completa también se muestra (para que lleven otro)
      if (best == null || off > bestOff) {
        best = p;
        bestOff = off;
      }
    }
    return best;
  }

  /// Precio para los catálogos con la promoción que más rebaja: «$16.000 · −20 %» o
  /// «$8.000 · 2×1»; null si no hay ninguna vigente
  static String? catalogLabel(Iterable<Promotion> all,
      {required String productId, required String category, required double price, required String Function(double) money}) {
    final now = DateTime.now();
    final p = best(all, productId: productId, category: category, unitPrice: price, quantity: 10, at: now);
    if (p == null) return null;
    return '${money(p.priceWith(price))} · ${p.badge}';
  }

  Promotion copyWith({String? name, bool? isActive, DateTime? updatedAt}) => Promotion(
        id: id,
        businessId: businessId,
        name: name ?? this.name,
        kind: kind,
        percentOff: percentOff,
        buyQty: buyQty,
        payQty: payQty,
        scope: scope,
        category: category,
        productIds: productIds,
        startsAt: startsAt,
        endsAt: endsAt,
        isActive: isActive ?? this.isActive,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'business_id': businessId,
        'name': name,
        'kind': kind,
        'percent_off': percentOff,
        'buy_qty': buyQty,
        'pay_qty': payQty,
        'scope': scope,
        'category': category,
        'product_ids': jsonEncode(productIds),
        'starts_at': startsAt.toUtc().toIso8601String(),
        'ends_at': endsAt.toUtc().toIso8601String(),
        'is_active': isActive ? 1 : 0,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  factory Promotion.fromMap(Map<String, dynamic> m) {
    List<String> ids;
    try {
      final raw = m['product_ids'];
      ids = [for (final v in (raw is String ? jsonDecode(raw) : (raw ?? const [])) as List) '$v'];
    } catch (_) {
      ids = const [];
    }
    DateTime when(Object? v) => (DateTime.tryParse('${v ?? ''}') ?? DateTime.now()).toLocal();
    return Promotion(
      id: m['id'] as String,
      businessId: m['business_id'] as String,
      name: m['name'] as String? ?? 'Promoción',
      kind: m['kind'] as String? ?? percent,
      percentOff: (m['percent_off'] as num?)?.toDouble() ?? 0,
      buyQty: (m['buy_qty'] as num?)?.toInt() ?? 2,
      payQty: (m['pay_qty'] as num?)?.toInt() ?? 1,
      scope: m['scope'] as String? ?? scopeAll,
      category: m['category'] as String?,
      productIds: ids,
      startsAt: when(m['starts_at']),
      endsAt: when(m['ends_at']),
      isActive: m['is_active'] == 1 || m['is_active'] == true,
      createdAt: when(m['created_at']),
      updatedAt: when(m['updated_at']),
    );
  }
}
