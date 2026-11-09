import 'dart:convert';

/// Un renglón del pedido: lo pedido y lo que ya llegó
class SupplierOrderItem {
  final String productId;
  final String productName;
  final String? variantId;
  final String? variantName;
  final int quantity;
  final int received;

  const SupplierOrderItem({
    required this.productId,
    required this.productName,
    this.variantId,
    this.variantName,
    required this.quantity,
    this.received = 0,
  });

  int get missing => (quantity - received).clamp(0, quantity);
  String get label => (variantName ?? '').isEmpty ? productName : '$productName ($variantName)';

  bool matches(String productId, String? variantId) => this.productId == productId && this.variantId == variantId;

  SupplierOrderItem copyWith({int? received}) => SupplierOrderItem(
        productId: productId,
        productName: productName,
        variantId: variantId,
        variantName: variantName,
        quantity: quantity,
        received: received ?? this.received,
      );

  Map<String, dynamic> toJson() => {
        'product_id': productId,
        'product_name': productName,
        if (variantId != null) 'variant_id': variantId,
        if (variantName != null) 'variant_name': variantName,
        'quantity': quantity,
        'received': received,
      };

  factory SupplierOrderItem.fromJson(Map<String, dynamic> j) => SupplierOrderItem(
        productId: j['product_id'] as String? ?? '',
        productName: j['product_name'] as String? ?? 'Producto',
        variantId: j['variant_id'] as String?,
        variantName: j['variant_name'] as String?,
        quantity: (j['quantity'] as num?)?.toInt() ?? 0,
        received: (j['received'] as num?)?.toInt() ?? 0,
      );
}

/// Pedido enviado a un proveedor. Al registrar la entrada se compara con lo que llegó.
class SupplierOrder {
  static const sent = 'ENVIADO';
  static const partial = 'PARCIAL';
  static const received = 'RECIBIDO';
  static const closed = 'CERRADO';

  final String id;
  final String businessId;
  final String? supplierId;
  final String? supplierName;
  final List<SupplierOrderItem> items;
  final String status;
  final String? createdBy;
  final DateTime createdAt;
  final DateTime? receivedAt;

  const SupplierOrder({
    required this.id,
    required this.businessId,
    this.supplierId,
    this.supplierName,
    required this.items,
    this.status = sent,
    this.createdBy,
    required this.createdAt,
    this.receivedAt,
  });

  bool get isPending => status == sent || status == partial;
  int get units => items.fold(0, (s, i) => s + i.quantity);
  int get receivedUnits => items.fold(0, (s, i) => s + i.received.clamp(0, i.quantity));
  int get missingUnits => items.fold(0, (s, i) => s + i.missing);
  List<SupplierOrderItem> get missingItems => [for (final i in items) if (i.missing > 0) i];

  String get statusLabel => switch (status) {
        sent => 'Por recibir',
        partial => 'Llegó incompleto',
        received => 'Recibido',
        closed => 'Cerrado',
        _ => status,
      };

  SupplierOrder copyWith({List<SupplierOrderItem>? items, String? status, DateTime? receivedAt}) => SupplierOrder(
        id: id,
        businessId: businessId,
        supplierId: supplierId,
        supplierName: supplierName,
        items: items ?? this.items,
        status: status ?? this.status,
        createdBy: createdBy,
        createdAt: createdAt,
        receivedAt: receivedAt ?? this.receivedAt,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'business_id': businessId,
        'supplier_id': supplierId,
        'supplier_name': supplierName,
        'items': jsonEncode([for (final i in items) i.toJson()]),
        'status': status,
        'created_by': createdBy,
        'created_at': createdAt.toIso8601String(),
        'received_at': receivedAt?.toIso8601String(),
      };

  factory SupplierOrder.fromMap(Map<String, dynamic> m) {
    List<SupplierOrderItem> items = const [];
    try {
      final raw = jsonDecode(m['items'] as String? ?? '[]') as List;
      items = [for (final r in raw) SupplierOrderItem.fromJson(Map<String, dynamic>.from(r as Map))];
    } catch (_) {}
    return SupplierOrder(
      id: m['id'] as String,
      businessId: m['business_id'] as String,
      supplierId: m['supplier_id'] as String?,
      supplierName: m['supplier_name'] as String?,
      items: items,
      status: m['status'] as String? ?? sent,
      createdBy: m['created_by'] as String?,
      createdAt: DateTime.tryParse(m['created_at'] as String? ?? '') ?? DateTime.now(),
      receivedAt: DateTime.tryParse(m['received_at'] as String? ?? ''),
    );
  }
}
