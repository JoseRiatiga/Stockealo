class Sale {
  final String id;
  final String businessId;
  final String productId;
  final String productName;
  final String? productPhotoPath;
  final int quantity;
  final double unitPrice;
  final double unitCost;
  final double totalAmount;
  final double netProfit;
  /// Código de [PaymentMethod] (EFECTIVO, NEQUI, TRANSFERENCIA, TARJETA, FIADO o MIXTO)
  final String paymentMethod;
  final String? customerName;
  final String? sellerName;
  final DateTime date;
  final bool isSynced;
  final String? variantId;
  final String? variantName;

  /// Línea de servicio (lavado, corte...): no tiene producto (productId vacío)
  final String? serviceId;
  final String? workOrderId;

  /// Empleados que hicieron el servicio (lista JSON de ids)
  final String? staffIds;

  /// Número de la venta (todas las líneas de una misma venta lo comparten)
  final String? invoiceNumber;

  /// Anulada: sigue en el historial, pero no cuenta en totales, caja ni reportes
  final DateTime? voidedAt;
  final String? voidReason;
  final String? voidedBy;

  /// Pago mixto: cuánto entró por cada medio en esta línea (JSON)
  final String? paymentSplit;

  /// Promoción que se aplicó a la línea (0.13.4) y cuánto descontó
  final String? promotionId;
  final String? promotionName;
  final double promotionDiscount;

  bool get isService => serviceId != null || productId.isEmpty;
  bool get isVoided => voidedAt != null;

  Sale({
    required this.id,
    this.businessId = 'default_business',
    required this.productId,
    required this.productName,
    this.productPhotoPath,
    required this.quantity,
    required this.unitPrice,
    required this.unitCost,
    required this.totalAmount,
    required this.netProfit,
    required this.paymentMethod,
    this.customerName,
    this.sellerName,
    required this.date,
    this.isSynced = false,
    this.variantId,
    this.variantName,
    this.serviceId,
    this.workOrderId,
    this.staffIds,
    this.invoiceNumber,
    this.voidedAt,
    this.voidReason,
    this.voidedBy,
    this.paymentSplit,
    this.promotionId,
    this.promotionName,
    this.promotionDiscount = 0,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'business_id': businessId,
      'product_id': productId.isEmpty ? null : productId,
      'product_name': productName,
      'product_photo_path': productPhotoPath,
      'quantity': quantity,
      'unit_price': unitPrice,
      'unit_cost': unitCost,
      'total_amount': totalAmount,
      'net_profit': netProfit,
      'payment_method': paymentMethod,
      'customer_name': customerName,
      'seller_name': sellerName,
      'date': date.toIso8601String(),
      'is_synced': isSynced ? 1 : 0,
      'variant_id': variantId,
      'variant_name': variantName,
      'service_id': serviceId,
      'work_order_id': workOrderId,
      'staff_ids': staffIds,
      'invoice_number': invoiceNumber,
      'voided_at': voidedAt?.toIso8601String(),
      'void_reason': voidReason,
      'voided_by': voidedBy,
      'payment_split': paymentSplit,
      'promotion_id': promotionId,
      'promotion_name': promotionName,
      'promotion_discount': promotionDiscount,
    };
  }

  factory Sale.fromMap(Map<String, dynamic> map) {
    return Sale(
      id: map['id'] as String,
      businessId: map['business_id'] as String? ?? 'default_business',
      productId: map['product_id'] as String? ?? '',
      productName: map['product_name'] as String,
      productPhotoPath: map['product_photo_path'] as String?,
      quantity: (map['quantity'] as num).toInt(),
      unitPrice: (map['unit_price'] as num).toDouble(),
      unitCost: (map['unit_cost'] as num).toDouble(),
      totalAmount: (map['total_amount'] as num).toDouble(),
      netProfit: (map['net_profit'] as num).toDouble(),
      paymentMethod: map['payment_method'] as String,
      customerName: map['customer_name'] as String?,
      sellerName: map['seller_name'] as String?,
      date: DateTime.parse(map['date'] as String),
      isSynced: (map['is_synced'] as int?) == 1,
      variantId: map['variant_id'] as String?,
      variantName: map['variant_name'] as String?,
      serviceId: map['service_id'] as String?,
      workOrderId: map['work_order_id'] as String?,
      staffIds: map['staff_ids'] as String?,
      invoiceNumber: map['invoice_number'] as String?,
      voidedAt: DateTime.tryParse('${map['voided_at'] ?? ''}'),
      voidReason: map['void_reason'] as String?,
      voidedBy: map['voided_by'] as String?,
      paymentSplit: map['payment_split'] as String?,
      promotionId: map['promotion_id'] as String?,
      promotionName: map['promotion_name'] as String?,
      promotionDiscount: (map['promotion_discount'] as num?)?.toDouble() ?? 0,
    );
  }
}
