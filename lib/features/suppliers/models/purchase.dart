import 'dart:convert';

/// Un renglón de la entrada: producto (y talla/color si tiene), cantidad y costo
class PurchaseItem {
  final String productId;
  final String productName;
  final String? variantId;
  final String? variantName;
  final int quantity;
  final double unitCost;

  const PurchaseItem({
    required this.productId,
    required this.productName,
    this.variantId,
    this.variantName,
    required this.quantity,
    required this.unitCost,
  });

  double get subtotal => unitCost * quantity;

  String get label => (variantName ?? '').isEmpty ? productName : '$productName ($variantName)';

  Map<String, dynamic> toJson() => {
        'product_id': productId,
        'product_name': productName,
        if (variantId != null) 'variant_id': variantId,
        if (variantName != null) 'variant_name': variantName,
        'quantity': quantity,
        'unit_cost': unitCost,
      };

  factory PurchaseItem.fromJson(Map<String, dynamic> j) => PurchaseItem(
        productId: j['product_id'] as String? ?? '',
        productName: j['product_name'] as String? ?? 'Producto',
        variantId: j['variant_id'] as String?,
        variantName: j['variant_name'] as String?,
        quantity: (j['quantity'] as num?)?.toInt() ?? 0,
        unitCost: (j['unit_cost'] as num?)?.toDouble() ?? 0,
      );
}

/// Un abono a una entrada a crédito
class PurchasePayment {
  final double amount;
  final DateTime date;
  final String? note;

  const PurchasePayment({required this.amount, required this.date, this.note});

  Map<String, dynamic> toJson() => {
        'amount': amount,
        'date': date.toIso8601String(),
        if ((note ?? '').isNotEmpty) 'note': note,
      };

  factory PurchasePayment.fromJson(Map<String, dynamic> j) => PurchasePayment(
        amount: (j['amount'] as num?)?.toDouble() ?? 0,
        date: DateTime.tryParse(j['date'] as String? ?? '') ?? DateTime.now(),
        note: j['note'] as String?,
      );
}

/// Entrada de mercancía: lo que llegó del proveedor
class Purchase {
  final String id;
  final String businessId;
  final String? supplierId;
  final String? supplierName;
  final String? invoiceNumber;
  final DateTime date;
  final List<PurchaseItem> items;

  /// 'CONTADO' o 'CREDITO'
  final String paymentTerms;
  final DateTime? dueDate;
  final bool isPaid;
  final List<PurchasePayment> payments;

  /// Foto de la factura en el depósito privado (ruta "negocio/archivo"), no una URL
  final String? photoPath;

  /// Pedido al proveedor que se recibió con esta entrada
  final String? orderId;
  final String? notes;
  final String? createdBy;
  final DateTime createdAt;

  const Purchase({
    required this.id,
    required this.businessId,
    this.supplierId,
    this.supplierName,
    this.invoiceNumber,
    required this.date,
    required this.items,
    this.paymentTerms = 'CONTADO',
    this.dueDate,
    this.isPaid = true,
    this.payments = const [],
    this.photoPath,
    this.orderId,
    this.notes,
    this.createdBy,
    required this.createdAt,
  });

  double get total => items.fold(0.0, (s, i) => s + i.subtotal);
  int get units => items.fold(0, (s, i) => s + i.quantity);
  bool get isCredit => paymentTerms == 'CREDITO';

  /// Lo abonado; una entrada de contado o marcada como pagada cuenta completa
  double get paidAmount => isPaid ? total : payments.fold(0.0, (s, p) => s + p.amount);

  /// Lo que falta pagar
  double get balance => isPaid ? 0 : (total - paidAmount).clamp(0, double.infinity).toDouble();

  bool isOverdue([DateTime? now]) {
    final due = dueDate;
    if (isPaid || due == null) return false;
    final today = now ?? DateTime.now();
    return DateTime(due.year, due.month, due.day).isBefore(DateTime(today.year, today.month, today.day));
  }

  Purchase copyWith({bool? isPaid, List<PurchasePayment>? payments, String? photoPath}) => Purchase(
        id: id,
        businessId: businessId,
        supplierId: supplierId,
        supplierName: supplierName,
        invoiceNumber: invoiceNumber,
        date: date,
        items: items,
        paymentTerms: paymentTerms,
        dueDate: dueDate,
        isPaid: isPaid ?? this.isPaid,
        payments: payments ?? this.payments,
        photoPath: photoPath ?? this.photoPath,
        orderId: orderId,
        notes: notes,
        createdBy: createdBy,
        createdAt: createdAt,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'business_id': businessId,
        'supplier_id': supplierId,
        'supplier_name': supplierName,
        'invoice_number': invoiceNumber,
        'date': date.toIso8601String(),
        'items': jsonEncode([for (final i in items) i.toJson()]),
        'total': total,
        'payment_terms': paymentTerms,
        'due_date': dueDate?.toIso8601String(),
        'is_paid': isPaid ? 1 : 0,
        'payments': jsonEncode([for (final p in payments) p.toJson()]),
        'photo_path': photoPath,
        'order_id': orderId,
        'notes': notes,
        'created_by': createdBy,
        'created_at': createdAt.toIso8601String(),
      };

  factory Purchase.fromMap(Map<String, dynamic> m) {
    List<PurchaseItem> items = const [];
    try {
      final raw = jsonDecode(m['items'] as String? ?? '[]') as List;
      items = [for (final r in raw) PurchaseItem.fromJson(Map<String, dynamic>.from(r as Map))];
    } catch (_) {}
    List<PurchasePayment> payments = const [];
    try {
      final raw = jsonDecode(m['payments'] as String? ?? '[]') as List;
      payments = [for (final r in raw) PurchasePayment.fromJson(Map<String, dynamic>.from(r as Map))];
    } catch (_) {}
    return Purchase(
      id: m['id'] as String,
      businessId: m['business_id'] as String,
      supplierId: m['supplier_id'] as String?,
      supplierName: m['supplier_name'] as String?,
      invoiceNumber: m['invoice_number'] as String?,
      date: DateTime.tryParse(m['date'] as String? ?? '') ?? DateTime.now(),
      items: items,
      paymentTerms: (m['payment_terms'] as String?) ?? 'CONTADO',
      dueDate: DateTime.tryParse(m['due_date'] as String? ?? ''),
      isPaid: (m['is_paid'] as int? ?? 1) == 1,
      payments: payments,
      photoPath: m['photo_path'] as String?,
      orderId: m['order_id'] as String?,
      notes: m['notes'] as String?,
      createdBy: m['created_by'] as String?,
      createdAt: DateTime.tryParse(m['created_at'] as String? ?? '') ?? DateTime.now(),
    );
  }
}

/// Último costo de un producto con un proveedor (sale de las entradas de mercancía)
class SupplierCost {
  final String? supplierId;
  final String supplierName;
  final double unitCost;
  final DateTime date;

  /// Costo de la entrada anterior con ese mismo proveedor (para ver si subió)
  final double? previousCost;

  const SupplierCost({
    this.supplierId,
    required this.supplierName,
    required this.unitCost,
    required this.date,
    this.previousCost,
  });

  /// Cuánto cambió frente a la compra anterior (+ subió, - bajó); null si no hay anterior
  double? get change => previousCost == null || previousCost == 0 ? null : unitCost - previousCost!;

  /// Por producto, el último costo con cada proveedor, del más barato al más caro.
  /// Las entradas sin proveedor no cuentan: no hay con quién comparar.
  static Map<String, List<SupplierCost>> latestByProduct(List<Purchase> purchases) {
    final sorted = [...purchases]..sort((a, b) => a.date.compareTo(b.date));
    final last = <String, Map<String, SupplierCost>>{};
    for (final p in sorted) {
      final key = p.supplierId ?? p.supplierName;
      if (key == null || key.isEmpty) continue;
      // Un producto con tallas trae un renglón por talla: se toma un costo por entrada
      final costs = <String, double>{};
      for (final i in p.items) {
        if (i.unitCost > 0 && i.quantity > 0) costs[i.productId] = i.unitCost;
      }
      for (final e in costs.entries) {
        final bySupplier = last.putIfAbsent(e.key, () => {});
        final before = bySupplier[key];
        bySupplier[key] = SupplierCost(
          supplierId: p.supplierId,
          supplierName: p.supplierName ?? 'Proveedor',
          unitCost: e.value,
          date: p.date,
          previousCost: before?.unitCost,
        );
      }
    }
    return {
      for (final e in last.entries)
        e.key: e.value.values.toList()..sort((a, b) => a.unitCost.compareTo(b.unitCost)),
    };
  }
}
