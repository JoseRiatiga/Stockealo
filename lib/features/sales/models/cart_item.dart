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

  /// Descuento solo de esta línea, en dinero (0.15.0). El precio unitario no cambia: así
  /// la venta guarda cuánto se descontó y la nube aplica el límite de descuento del rol.
  double lineDiscount = 0;

  /// El precio lo pone Vender (normal o por mayor, 0.17.0). Un precio cotizado o
  /// guardado a mano no se toca.
  final bool autoPrice;

  /// Se está cobrando con precio por mayor (lo pone [SellCart])
  bool wholesale = false;

  /// Sin Pro (0.17.1): el precio por mayor que tendría esta línea con Pro, para mostrarlo
  /// en gris; no se cobra. Null si no llega a ningún escalón.
  double? wholesalePreview;

  CartItem({
    required this.product,
    this.variant,
    this.quantity = 1,
    double? customUnitPrice,
    this.discountPercent,
    bool? autoPrice,
  })  : autoPrice = autoPrice ?? customUnitPrice == null,
        customUnitPrice = customUnitPrice ?? (product.salePrice + (variant?.additionalPrice ?? 0.0));

  /// Precio normal de una unidad (con lo que suma la talla o el color)
  double get basePrice => product.salePrice + (variant?.additionalPrice ?? 0.0);

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

  /// Lo que se cobra por la línea con la promoción y su descuento
  double get netSubtotal => (subtotal - promoDiscount - lineDiscount).clamp(0, double.infinity).toDouble();
}
