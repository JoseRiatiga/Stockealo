import 'dart:convert';

/// Precio por cantidad (0.17.0, bloque B, Pro): «desde 12 unidades: $1.800».
/// Un producto tiene hasta [max] escalones; vale el de la cantidad más alta alcanzada.
class PriceTier {
  final int minQty;
  final double price;

  const PriceTier(this.minQty, this.price);

  static const max = 3;

  Map<String, dynamic> toJson() => {'min': minQty, 'price': price};

  @override
  bool operator ==(Object other) => other is PriceTier && other.minQty == minQty && other.price == price;

  @override
  int get hashCode => Object.hash(minQty, price);

  /// Escalones válidos: desde 2 unidades, precio mayor que 0 y menor que el normal,
  /// sin cantidades repetidas, ordenados y como mucho [max]
  static List<PriceTier> clean(Iterable<PriceTier> tiers, {double? basePrice}) {
    final byQty = <int, PriceTier>{};
    for (final t in tiers) {
      if (t.minQty < 2 || t.price <= 0) continue;
      if (basePrice != null && basePrice > 0 && t.price >= basePrice) continue;
      byQty[t.minQty] = t;
    }
    final list = byQty.values.toList()..sort((a, b) => a.minQty.compareTo(b.minQty));
    // Comprar más nunca sale más caro por unidad
    final out = <PriceTier>[];
    for (final t in list) {
      if (out.isNotEmpty && t.price >= out.last.price) continue;
      out.add(t);
    }
    return out.take(max).toList();
  }

  /// Lee el JSON guardado (texto en el celular, lista en la nube). Lo dañado se ignora.
  static List<PriceTier> parse(Object? raw) {
    try {
      final data = raw is String ? (raw.trim().isEmpty ? null : jsonDecode(raw)) : raw;
      if (data is! List) return const [];
      return clean([
        for (final e in data)
          if (e is Map && e['min'] is num && e['price'] is num) PriceTier((e['min'] as num).toInt(), (e['price'] as num).toDouble()),
      ]);
    } catch (_) {
      return const [];
    }
  }

  /// Texto para guardar en el celular; null si no hay escalones
  static String? encode(List<PriceTier> tiers) => tiers.isEmpty ? null : jsonEncode([for (final t in tiers) t.toJson()]);

  /// El escalón que aplica a [quantity], o null
  static PriceTier? forQuantity(List<PriceTier> tiers, int quantity) {
    PriceTier? best;
    for (final t in tiers) {
      if (quantity >= t.minQty) best = t;
    }
    return best;
  }
}
