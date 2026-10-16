import '../../products/models/product.dart';
import '../../products/models/product_variant.dart';

class CartItem {
  final Product product;
  final ProductVariant? variant;
  int quantity;
  double customUnitPrice;
  double? discountPercent;

  CartItem({
    required this.product,
    this.variant,
    this.quantity = 1,
    double? customUnitPrice,
    this.discountPercent,
  }) : customUnitPrice = customUnitPrice ?? (product.salePrice + (variant?.additionalPrice ?? 0.0));

  String get displayName => variant != null ? '${product.name} (${variant!.attributeValue})' : product.name;

  int get availableStock => variant != null ? variant!.stock : product.stock;

  double get unitPrice => customUnitPrice;
  double get unitCost => product.purchasePrice;

  double get originalSubtotal => quantity * (product.salePrice + (variant?.additionalPrice ?? 0.0));
  double get subtotal => quantity * unitPrice;
  double get totalCost => quantity * unitCost;
  double get netProfit => subtotal - totalCost;
  double get itemSavings => originalSubtotal - subtotal;
}
