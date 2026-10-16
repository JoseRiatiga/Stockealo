class QuotationItem {
  final String id;
  final String quotationId;
  final String productId;
  final String productName;
  final int quantity;
  final double unitPrice;
  final double subtotal;
  final String? variantId;
  final String? variantName;

  QuotationItem({
    required this.id,
    required this.quotationId,
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.unitPrice,
    required this.subtotal,
    this.variantId,
    this.variantName,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'quotation_id': quotationId,
    'product_id': productId,
    'product_name': productName,
    'quantity': quantity,
    'unit_price': unitPrice,
    'subtotal': subtotal,
    'variant_id': variantId,
    'variant_name': variantName,
  };

  factory QuotationItem.fromMap(Map<String, dynamic> map) => QuotationItem(
    id: map['id'] as String,
    quotationId: map['quotation_id'] as String,
    productId: map['product_id'] as String,
    productName: map['product_name'] as String,
    quantity: (map['quantity'] as num).toInt(),
    unitPrice: (map['unit_price'] as num).toDouble(),
    subtotal: (map['subtotal'] as num).toDouble(),
    variantId: map['variant_id'] as String?,
    variantName: map['variant_name'] as String?,
  );
}

class Quotation {
  final String id;
  final String businessId;
  final String quotationNumber;
  final String? customerName;
  final String? customerPhone;
  final double totalAmount;
  final double discountAmount;
  final String? notes;
  final String status; // 'PENDIENTE' | 'FACTURADA' | 'VENCIDA'
  final DateTime? validUntil;
  final DateTime createdAt;
  final String? sellerName;
  final List<QuotationItem> items;

  Quotation({
    required this.id,
    required this.businessId,
    required this.quotationNumber,
    this.customerName,
    this.customerPhone,
    required this.totalAmount,
    this.discountAmount = 0.0,
    this.notes,
    this.status = 'PENDIENTE',
    this.validUntil,
    required this.createdAt,
    this.sellerName,
    this.items = const [],
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'business_id': businessId,
    'quotation_number': quotationNumber,
    'customer_name': customerName,
    'customer_phone': customerPhone,
    'total_amount': totalAmount,
    'discount_amount': discountAmount,
    'notes': notes,
    'status': status,
    'valid_until': validUntil?.toIso8601String(),
    'created_at': createdAt.toIso8601String(),
    'seller_name': sellerName,
  };

  factory Quotation.fromMap(Map<String, dynamic> map, [List<QuotationItem> items = const []]) => Quotation(
    id: map['id'] as String,
    businessId: map['business_id'] as String,
    quotationNumber: map['quotation_number'] as String,
    customerName: map['customer_name'] as String?,
    customerPhone: map['customer_phone'] as String?,
    totalAmount: (map['total_amount'] as num).toDouble(),
    discountAmount: (map['discount_amount'] as num?)?.toDouble() ?? 0.0,
    notes: map['notes'] as String?,
    status: map['status'] as String? ?? 'PENDIENTE',
    validUntil: map['valid_until'] != null ? DateTime.tryParse(map['valid_until'] as String) : null,
    createdAt: DateTime.parse(map['created_at'] as String),
    sellerName: map['seller_name'] as String?,
    items: items,
  );
}
