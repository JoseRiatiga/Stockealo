/// Una combinación vendible de un producto: hasta dos datos (ej. Talla M y Color
/// Rojo) con sus propias existencias. El color lleva además una muestra (#RRGGBB),
/// una segunda para prendas de dos tonos, o 'multi' para estampados.
class ProductVariant {
  final String id;
  final String businessId;
  final String productId;
  final String attributeName; // ej. 'Talla', 'Presentación'
  final String attributeValue; // ej. 'S', 'M', 'L'
  final String? attribute2Name; // ej. 'Color'
  final String? attribute2Value; // ej. 'Rojo', 'Blanco con rojo'
  final String? colorHex; // '#C62828' o 'multi'
  final String? colorHex2; // segundo tono, '#FFFFFF'
  final String? skuOrBarcode;
  final int stock;
  final double additionalPrice;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isSynced;

  static const multicolor = 'multi';

  ProductVariant({
    required this.id,
    required this.businessId,
    required this.productId,
    this.attributeName = 'Talla',
    required this.attributeValue,
    this.attribute2Name,
    this.attribute2Value,
    this.colorHex,
    this.colorHex2,
    this.skuOrBarcode,
    this.stock = 0,
    this.additionalPrice = 0.0,
    required this.createdAt,
    required this.updatedAt,
    this.isSynced = false,
  });

  bool get isOutOfStock => stock <= 0;

  bool get hasSecondAttribute => (attribute2Value ?? '').trim().isNotEmpty;

  /// Nombre para mostrar: "M", "M · Rojo" o solo "Rojo" si no hay primer dato
  String get label {
    final first = attributeValue.trim();
    final second = (attribute2Value ?? '').trim();
    if (second.isEmpty) return first;
    if (first.isEmpty) return second;
    return '$first · $second';
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'business_id': businessId,
      'product_id': productId,
      'attribute_name': attributeName,
      'attribute_value': attributeValue,
      'attribute2_name': attribute2Name,
      'attribute2_value': attribute2Value,
      'color_hex': colorHex,
      'color_hex2': colorHex2,
      'sku_or_barcode': skuOrBarcode,
      'stock': stock,
      'additional_price': additionalPrice,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'is_synced': isSynced ? 1 : 0,
    };
  }

  /// Fila para Supabase (sin columnas solo locales)
  static Map<String, dynamic> cloudRow(Map<String, dynamic> m) => {
        'id': m['id'],
        'business_id': m['business_id'],
        'product_id': m['product_id'],
        'attribute_name': m['attribute_name'] ?? 'Talla',
        'attribute_value': m['attribute_value'] ?? '',
        'attribute2_name': _blankToNull(m['attribute2_name']),
        'attribute2_value': _blankToNull(m['attribute2_value']),
        'color_hex': validHex(m['color_hex'] as String?, allowMulti: true),
        'color_hex2': validHex(m['color_hex2'] as String?),
        'sku_or_barcode': _blankToNull(m['sku_or_barcode']),
        'stock': (m['stock'] as num?)?.toInt() ?? 0,
        'additional_price': (m['additional_price'] as num?)?.toDouble() ?? 0.0,
        'created_at': m['created_at'],
        'updated_at': m['updated_at'],
      };

  /// '#RRGGBB' en mayúsculas, 'multi' si se permite, o null si no es válido
  static String? validHex(String? value, {bool allowMulti = false}) {
    final v = value?.trim();
    if (v == null || v.isEmpty) return null;
    if (allowMulti && v.toLowerCase() == multicolor) return multicolor;
    final hex = v.startsWith('#') ? v.substring(1) : v;
    if (!RegExp(r'^[0-9A-Fa-f]{6}$').hasMatch(hex)) return null;
    return '#${hex.toUpperCase()}';
  }

  static String? _blankToNull(Object? v) {
    final s = v?.toString().trim();
    return (s == null || s.isEmpty) ? null : s;
  }

  factory ProductVariant.fromMap(Map<String, dynamic> map) {
    return ProductVariant(
      id: map['id'] as String,
      businessId: map['business_id'] as String? ?? '',
      productId: map['product_id'] as String? ?? '',
      attributeName: map['attribute_name'] as String? ?? 'Talla',
      attributeValue: map['attribute_value'] as String? ?? '',
      attribute2Name: map['attribute2_name'] as String?,
      attribute2Value: map['attribute2_value'] as String?,
      colorHex: map['color_hex'] as String?,
      colorHex2: map['color_hex2'] as String?,
      skuOrBarcode: map['sku_or_barcode'] as String?,
      stock: (map['stock'] as num?)?.toInt() ?? 0,
      additionalPrice: (map['additional_price'] as num?)?.toDouble() ?? 0.0,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      isSynced: (map['is_synced'] as int?) == 1,
    );
  }

  ProductVariant copyWith({
    String? id,
    String? businessId,
    String? productId,
    String? attributeName,
    String? attributeValue,
    String? attribute2Name,
    String? attribute2Value,
    String? colorHex,
    String? colorHex2,
    bool clearColor = false,
    String? skuOrBarcode,
    int? stock,
    double? additionalPrice,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isSynced,
  }) {
    return ProductVariant(
      id: id ?? this.id,
      businessId: businessId ?? this.businessId,
      productId: productId ?? this.productId,
      attributeName: attributeName ?? this.attributeName,
      attributeValue: attributeValue ?? this.attributeValue,
      attribute2Name: attribute2Name ?? this.attribute2Name,
      attribute2Value: attribute2Value ?? this.attribute2Value,
      colorHex: clearColor ? null : (colorHex ?? this.colorHex),
      colorHex2: clearColor ? null : (colorHex2 ?? this.colorHex2),
      skuOrBarcode: skuOrBarcode ?? this.skuOrBarcode,
      stock: stock ?? this.stock,
      additionalPrice: additionalPrice ?? this.additionalPrice,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isSynced: isSynced ?? this.isSynced,
    );
  }

  /// Convierte lo escrito como "M (ROJO)" o "M - Rojo" en Talla M + Color Rojo.
  /// Devuelve null si el texto no tiene esa forma.
  static ({String first, String second})? splitLegacy(String value) {
    final v = value.trim();
    final paren = RegExp(r'^(.+?)\s*\((.+)\)$').firstMatch(v);
    final dash = RegExp(r'^(.+?)\s+[-–/]\s+(.+)$').firstMatch(v);
    final m = paren ?? dash;
    if (m == null) return null;
    final first = m[1]!.trim();
    final second = m[2]!.trim();
    if (first.isEmpty || second.isEmpty) return null;
    return (first: first, second: _capitalize(second));
  }

  static String _capitalize(String s) {
    final lower = s.toLowerCase();
    return lower[0].toUpperCase() + lower.substring(1);
  }
}
