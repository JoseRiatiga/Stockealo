import 'price_tier.dart';
import 'product_variant.dart';

class Product {
  final String id;
  final String businessId;
  final String code;
  final String name;
  final String? description;
  final String category;
  final double purchasePrice;
  final double salePrice;
  final int stock;
  final int minStock;
  final String? photoPath;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isSynced;
  final bool hasVariants;
  final List<ProductVariant> variants;

  /// Proveedor principal (opcional)
  final String? supplierId;

  /// Precio de antes, para mostrar la oferta en la tienda en línea (se ve tachado).
  /// Solo cuenta si es mayor al precio de venta.
  final double? comparePrice;

  /// Marca (0.16.0): «Elf Bar», «Tecnoquímicas». La tienda en línea filtra por marca.
  final String? brand;

  /// Controla vencimiento por lote (0.16.0, fase 2b): cada entrada pide su fecha y lo
  /// vencido no se vende. Solo en productos sin tallas ni colores.
  final bool tracksExpiry;

  /// Precio por cantidad (0.17.0, Pro): hasta 3 escalones, de menor a mayor cantidad
  final List<PriceTier> priceTiers;

  Product({
    required this.id,
    required this.businessId,
    required this.code,
    required this.name,
    this.description,
    required this.category,
    required this.purchasePrice,
    required this.salePrice,
    required this.stock,
    this.minStock = 5,
    this.photoPath,
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
    this.isSynced = false,
    this.hasVariants = false,
    this.variants = const [],
    this.supplierId,
    this.comparePrice,
    this.brand,
    this.tracksExpiry = false,
    this.priceTiers = const [],
  });

  /// Precio de una unidad al llevar [quantity] (sin tallas ni colores): el del escalón
  /// alcanzado o el normal
  double unitPriceFor(int quantity) => PriceTier.forQuantity(priceTiers, quantity)?.price ?? salePrice;

  /// Está en oferta: tiene un precio de antes mayor al de ahora
  bool get onOffer => (comparePrice ?? 0) > salePrice && salePrice > 0;

  /// Ganancia neta por unidad
  double get profit => salePrice - purchasePrice;

  /// Margen de ganancia porcentual
  double get profitMargin {
    if (salePrice <= 0) return 0.0;
    return ((salePrice - purchasePrice) / salePrice) * 100;
  }

  /// Se vende por debajo del costo de compra
  bool get sellsBelowCost => purchasePrice > 0 && salePrice < purchasePrice;

  /// Margen con su signo para mostrar: "+21%", "-26%" o "0%"
  String profitMarginLabel({int decimals = 0}) {
    final value = profitMargin.abs().toStringAsFixed(decimals);
    if (double.parse(value) == 0) return '0%';
    return '${profitMargin > 0 ? '+' : '-'}$value%';
  }

  /// Estados de stock
  bool get isOutOfStock => stock <= 0;
  bool get isLowStock => stock > 0 && stock <= minStock;
  bool get isStockHealthy => stock > minStock;

  Product copyWith({
    String? id,
    String? businessId,
    String? code,
    String? name,
    String? description,
    String? category,
    double? purchasePrice,
    double? salePrice,
    int? stock,
    int? minStock,
    String? photoPath,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isSynced,
    bool? hasVariants,
    List<ProductVariant>? variants,
    String? supplierId,
    bool clearSupplier = false,
    double? comparePrice,
    bool clearComparePrice = false,
    String? brand,
    bool clearBrand = false,
    bool? tracksExpiry,
    List<PriceTier>? priceTiers,
  }) {
    return Product(
      id: id ?? this.id,
      businessId: businessId ?? this.businessId,
      code: code ?? this.code,
      name: name ?? this.name,
      description: description ?? this.description,
      category: category ?? this.category,
      purchasePrice: purchasePrice ?? this.purchasePrice,
      salePrice: salePrice ?? this.salePrice,
      stock: stock ?? this.stock,
      minStock: minStock ?? this.minStock,
      photoPath: photoPath ?? this.photoPath,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isSynced: isSynced ?? this.isSynced,
      hasVariants: hasVariants ?? this.hasVariants,
      variants: variants ?? this.variants,
      supplierId: clearSupplier ? null : (supplierId ?? this.supplierId),
      comparePrice: clearComparePrice ? null : (comparePrice ?? this.comparePrice),
      brand: clearBrand ? null : (brand ?? this.brand),
      tracksExpiry: tracksExpiry ?? this.tracksExpiry,
      priceTiers: priceTiers ?? this.priceTiers,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'business_id': businessId,
      'code': code,
      'name': name,
      'description': description,
      'category': category,
      'purchase_price': purchasePrice,
      'sale_price': salePrice,
      'stock': stock,
      'min_stock': minStock,
      'photo_path': photoPath,
      'is_active': isActive ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'is_synced': isSynced ? 1 : 0,
      'has_variants': hasVariants ? 1 : 0,
      'supplier_id': supplierId,
      'compare_price': comparePrice,
      'brand': brand,
      'tracks_expiry': tracksExpiry ? 1 : 0,
      'price_tiers': PriceTier.encode(priceTiers),
    };
  }

  factory Product.fromMap(Map<String, dynamic> map, {List<ProductVariant> variants = const []}) {
    return Product(
      id: map['id'] as String,
      businessId: map['business_id'] as String? ?? 'default_business',
      code: map['code'] as String,
      name: map['name'] as String,
      description: map['description'] as String?,
      category: map['category'] as String,
      purchasePrice: (map['purchase_price'] as num).toDouble(),
      salePrice: (map['sale_price'] as num).toDouble(),
      stock: (map['stock'] as num).toInt(),
      minStock: (map['min_stock'] as num?)?.toInt() ?? 5,
      photoPath: map['photo_path'] as String?,
      isActive: (map['is_active'] as int?) == 1,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      isSynced: (map['is_synced'] as int?) == 1,
      hasVariants: (map['has_variants'] as int?) == 1,
      variants: variants,
      supplierId: map['supplier_id'] as String?,
      comparePrice: (map['compare_price'] as num?)?.toDouble(),
      brand: (map['brand'] as String?)?.trim().isEmpty == true ? null : (map['brand'] as String?)?.trim(),
      tracksExpiry: map['tracks_expiry'] == 1 || map['tracks_expiry'] == true,
      priceTiers: PriceTier.parse(map['price_tiers']),
    );
  }
}
