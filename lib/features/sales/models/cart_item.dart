import '../../products/models/product.dart';
import '../../products/models/product_variant.dart';
import 'promotion.dart';

class CartItem {
  final Product product;
  final ProductVariant? variant;
  int quantity;
  double customUnitPrice;
  double? discountPercent;

  /// La promoción que aplica a esta línea (la pone [SellCart] según las vigentes)
  Promotion? promotion;

  CartItem({
    required this.product,
    this.variant,
    this.quantity = 1,
    double? customUnitPrice,
    this.discountPercent,
  }) : customUnitPrice = customUnitPrice ?? (product.salePrice + (variant?.additionalPrice ?? 0.0));

  String get displayName => variant != null ? '${product.name} (${variant!.label})' : product.name;

  int get availableStock => variant != null ? variant!.stock : product.stock;

  double get unitPrice => customUnitPrice;
  double get unitCost => product.purchasePrice;

  double get originalSubtotal => quantity * (product.salePrice + (variant?.additionalPrice ?? 0.0));
  double get subtotal => quantity * unitPrice;
  double get totalCost => quantity * unitCost;
  double get netProfit => subtotal - totalCost;
  double get itemSavings => originalSubtotal - subtotal;

  /// Lo que descuenta la promoción en esta línea
  double get promoDiscount => promotion?.discountFor(unitPrice, quantity) ?? 0;

  /// Lo que se cobra por la línea con la promoción
  double get netSubtotal => (subtotal - promoDiscount).clamp(0, double.infinity).toDouble();
}
