class ProductVariant {
  final String id;
  final String businessId;
  final String productId;
  final String attributeName; // ej. 'Talla', 'Color', 'Presentación'
  final String attributeValue; // ej. 'S', 'M', 'L', 'Rojo', 'Azul'
  final String? skuOrBarcode;
  final int stock;
  final double additionalPrice;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isSynced;

  ProductVariant({
    required this.id,
    required this.businessId,
    required this.productId,
    this.attributeName = 'Talla',
    required this.attributeValue,
    this.skuOrBarcode,
    this.stock = 0,
    this.additionalPrice = 0.0,
    required this.createdAt,
    required this.updatedAt,
    this.isSynced = false,
  });

  bool get isOutOfStock => stock <= 0;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'business_id': businessId,
      'product_id': productId,
      'attribute_name': attributeName,
      'attribute_value': attributeValue,
      'sku_or_barcode': skuOrBarcode,
      'stock': stock,
      'additional_price': additionalPrice,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'is_synced': isSynced ? 1 : 0,
    };
  }

  factory ProductVariant.fromMap(Map<String, dynamic> map) {
    return ProductVariant(
      id: map['id'] as String,
      businessId: map['business_id'] as String? ?? '',
      productId: map['product_id'] as String? ?? '',
      attributeName: map['attribute_name'] as String? ?? 'Talla',
      attributeValue: map['attribute_value'] as String? ?? '',
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
      skuOrBarcode: skuOrBarcode ?? this.skuOrBarcode,
      stock: stock ?? this.stock,
      additionalPrice: additionalPrice ?? this.additionalPrice,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isSynced: isSynced ?? this.isSynced,
    );
  }
}
