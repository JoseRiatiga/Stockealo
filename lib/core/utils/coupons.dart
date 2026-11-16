/// Cupones (0.16.0, fase 7): los textos que comparten los cupones Pro y los de la tienda
abstract final class CouponText {
  /// Mayúsculas, sin espacios
  static String normalize(String code) => code.replaceAll(RegExp(r'\s'), '').toUpperCase();

  /// Lo que el negocio puede escribir como código de la tienda
  static bool validStoreCode(String code) => RegExp(r'^[A-Z0-9-]{3,24}$').hasMatch(normalize(code));

  /// «10 %» o «$5.000»
  static String discountLabel({num? percent, num? amount, required String Function(num) money}) =>
      percent != null ? '${_n(percent)} %' : money(amount ?? 0);

  /// El descuento de un cupón sobre un total (igual que la nube): 0 si no llega al mínimo
  static double discountFor({double? percent, double? amount, double minTotal = 0, required double total}) {
    if (total <= 0 || total < minTotal) return 0;
    if (percent != null) return (total * percent / 100).roundToDouble().clamp(0, total).toDouble();
    return (amount ?? 0).clamp(0, total).toDouble();
  }

  static String _n(num v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  /// Mensaje para cada motivo del servidor. [money] da formato a la compra mínima.
  static String error(String serverMessage, {String Function(num)? money}) {
    final m = serverMessage;
    if (m.contains('coupon_min_total')) {
      final v = num.tryParse(m.split('coupon_min_total:').last.split(RegExp(r'[^0-9.]')).first);
      return v == null || money == null ? 'Tu compra no llega al mínimo de este cupón.' : 'Este cupón es para compras desde ${money(v)}.';
    }
    if (m.contains('coupon_not_found')) return 'Ese cupón no existe o ya no está activo.';
    if (m.contains('coupon_expired')) return 'Este cupón venció.';
    if (m.contains('coupon_used_up')) return 'Este cupón ya se agotó.';
    if (m.contains('coupon_already_used')) return 'Ya usaste este cupón.';
    if (m.contains('coupon_wrong_plan')) return 'Este cupón no sirve para ese plan.';
    if (m.contains('coupon_first_purchase')) return 'Este cupón es solo para la primera compra.';
    if (m.contains('coupon_too_big')) return 'Este cupón no se puede usar con ese plan.';
    if (m.contains('coupon_phone_required')) return 'Para usar el cupón escribe tu teléfono.';
    if (m.contains('coupon_limit')) return 'Sin Pro puedes tener 1 cupón activo. Apaga el otro o activa Pro para tener varios.';
    if (m.contains('code_taken')) return 'Ya tienes un cupón con ese código.';
    if (m.contains('invalid_code')) return 'El código lleva de 3 a 24 letras, números o guiones.';
    return 'No se pudo revisar el cupón. Inténtalo de nuevo.';
  }
}

/// El motivo por el que un cupón no sirve, listo para mostrar
class CouponException implements Exception {
  final String message;
  const CouponException(this.message);
  @override
  String toString() => message;
}

/// Un cupón de descuento: los de Pro (panel) y los de la tienda (cada negocio)
class Coupon {
  /// Solo los de la tienda tienen id (los de Pro se identifican por el código)
  final String? id;
  final String code;
  final double? percent;
  final double? amount;
  final double minTotal;
  final int? maxUses;
  final int uses;
  final DateTime? expiresAt;
  final bool active;

  /// Solo Pro: en qué planes sirve, si es solo la primera compra y una nota
  final List<String> kinds;
  final bool firstPurchaseOnly;
  final String? note;

  const Coupon({
    this.id,
    required this.code,
    this.percent,
    this.amount,
    this.minTotal = 0,
    this.maxUses,
    this.uses = 0,
    this.expiresAt,
    this.active = true,
    this.kinds = const [],
    this.firstPurchaseOnly = false,
    this.note,
  });

  factory Coupon.fromRow(Map<String, dynamic> r) => Coupon(
        id: r['id'] as String?,
        code: r['code'] as String,
        percent: (r['percent'] as num?)?.toDouble(),
        amount: (r['amount'] as num?)?.toDouble(),
        minTotal: (r['min_total'] as num?)?.toDouble() ?? 0,
        maxUses: (r['max_uses'] as num?)?.toInt(),
        uses: (r['uses'] as num?)?.toInt() ?? 0,
        expiresAt: DateTime.tryParse('${r['expires_at']}')?.toLocal(),
        active: r['active'] as bool? ?? true,
        kinds: [for (final k in (r['kinds'] as List? ?? const [])) '$k'],
        firstPurchaseOnly: r['first_purchase_only'] as bool? ?? false,
        note: r['note'] as String?,
      );

  bool get expired => expiresAt != null && !expiresAt!.isAfter(DateTime.now());
  bool get usedUp => maxUses != null && uses >= maxUses!;

  /// Activo de verdad: encendido, sin vencer y sin agotar
  bool get usable => active && !expired && !usedUp;

  double discountFor(double total) =>
      CouponText.discountFor(percent: percent, amount: amount, minTotal: minTotal, total: total);

  /// Mensaje listo para compartir el cupón de la tienda
  String shareText({required String storeName, required String storeUrl, required String Function(num) money}) => [
        '¡Tienes ${discountLabel(money)} de descuento en $storeName!',
        'Usa el cupón $code al hacer tu pedido${minTotal > 0 ? ' (compras desde ${money(minTotal)})' : ''}.',
        storeUrl,
      ].join('\n');

  /// «10 %» o «$5.000»
  String discountLabel(String Function(num) money) => CouponText.discountLabel(percent: percent, amount: amount, money: money);

  /// «Usado 3 de 50 veces» / «Usado 3 veces»
  String get usesLabel => maxUses == null ? 'Usado $uses ${uses == 1 ? 'vez' : 'veces'}' : 'Usado $uses de $maxUses';

  /// Estado para la lista: «Activo», «Apagado», «Venció» o «Agotado»
  String get stateLabel => !active ? 'Apagado' : (expired ? 'Venció' : (usedUp ? 'Agotado' : 'Activo'));
}
