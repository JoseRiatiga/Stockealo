/// Lote de un producto con vencimiento (0.16.0, fase 2b): cuántas unidades quedan y
/// cuándo vencen. Solo en productos sin tallas ni colores.
class ProductLot {
  static const active = 'ACTIVE';

  /// Ya venció: sus unidades salieron del stock vendible y esperan cambio o baja
  static const expired = 'EXPIRED';

  /// Se fue al proveedor para cambio (ver [LotExchange])
  static const returned = 'RETURNED';

  /// Dado de baja (merma)
  static const writtenOff = 'WRITTEN_OFF';

  /// Se vendió todo
  static const used = 'USED';

  final String id;
  final String businessId;
  final String productId;
  final String? code;
  final DateTime expiresOn;
  final int quantity;
  final int initialQuantity;
  final double cost;

  /// 'ENTRADA', 'AJUSTE', 'CAMBIO' o 'SIN_FECHA' (a las unidades que no tenían fecha)
  final String source;
  final String? purchaseId;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ProductLot({
    required this.id,
    required this.businessId,
    required this.productId,
    this.code,
    required this.expiresOn,
    required this.quantity,
    required this.initialQuantity,
    this.cost = 0,
    this.source = 'ENTRADA',
    this.purchaseId,
    this.status = active,
    required this.createdAt,
    required this.updatedAt,
  });

  static DateTime day(DateTime d) => DateTime(d.year, d.month, d.day);

  static String dayText(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Vence hoy o antes: se cuenta como vencido desde el día siguiente al de la fecha
  bool isExpiredOn(DateTime now) => day(now).isAfter(expiresOn);

  /// Días que faltan (0 = vence hoy, negativo = ya venció)
  int daysLeft(DateTime now) => expiresOn.difference(day(now)).inDays;

  /// Vence en los próximos [days] días y todavía no venció
  bool expiresSoon(DateTime now, {int days = 30}) => !isExpiredOn(now) && daysLeft(now) <= days;

  ProductLot copyWith({int? quantity, String? status, DateTime? updatedAt}) => ProductLot(
        id: id,
        businessId: businessId,
        productId: productId,
        code: code,
        expiresOn: expiresOn,
        quantity: quantity ?? this.quantity,
        initialQuantity: initialQuantity,
        cost: cost,
        source: source,
        purchaseId: purchaseId,
        status: status ?? this.status,
        createdAt: createdAt,
        updatedAt: updatedAt ?? DateTime.now(),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'business_id': businessId,
        'product_id': productId,
        'code': code,
        'expires_on': dayText(expiresOn),
        'quantity': quantity,
        'initial_quantity': initialQuantity,
        'cost': cost,
        'source': source,
        'purchase_id': purchaseId,
        'status': status,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  factory ProductLot.fromMap(Map<String, dynamic> m) {
    final exp = DateTime.tryParse('${m['expires_on']}') ?? DateTime.now();
    return ProductLot(
      id: m['id'] as String,
      businessId: m['business_id'] as String,
      productId: m['product_id'] as String,
      code: (m['code'] as String?)?.trim().isEmpty == true ? null : (m['code'] as String?)?.trim(),
      expiresOn: day(exp),
      quantity: (m['quantity'] as num?)?.toInt() ?? 0,
      initialQuantity: (m['initial_quantity'] as num?)?.toInt() ?? 0,
      cost: (m['cost'] as num?)?.toDouble() ?? 0,
      source: m['source'] as String? ?? 'ENTRADA',
      purchaseId: m['purchase_id'] as String?,
      status: m['status'] as String? ?? active,
      createdAt: DateTime.tryParse('${m['created_at']}') ?? DateTime.now(),
      updatedAt: DateTime.tryParse('${m['updated_at']}') ?? DateTime.now(),
    );
  }
}

/// Un lote vencido que se fue al proveedor para que lo cambie (0.16.0, fase 2b)
class LotExchange {
  static const pending = 'PENDING';
  static const received = 'RECEIVED';
  static const writtenOff = 'WRITTEN_OFF';

  final String id;
  final String businessId;
  final String productId;
  final String productName;
  final String lotId;
  final String? supplierId;
  final String? supplierName;
  final int quantity;
  final String status;
  final String? newLotId;
  final DateTime createdAt;
  final DateTime? closedAt;

  const LotExchange({
    required this.id,
    required this.businessId,
    required this.productId,
    required this.productName,
    required this.lotId,
    this.supplierId,
    this.supplierName,
    required this.quantity,
    this.status = pending,
    this.newLotId,
    required this.createdAt,
    this.closedAt,
  });

  bool get isPending => status == pending;

  LotExchange copyWith({String? status, String? newLotId, DateTime? closedAt}) => LotExchange(
        id: id,
        businessId: businessId,
        productId: productId,
        productName: productName,
        lotId: lotId,
        supplierId: supplierId,
        supplierName: supplierName,
        quantity: quantity,
        status: status ?? this.status,
        newLotId: newLotId ?? this.newLotId,
        createdAt: createdAt,
        closedAt: closedAt ?? this.closedAt,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'business_id': businessId,
        'product_id': productId,
        'product_name': productName,
        'lot_id': lotId,
        'supplier_id': supplierId,
        'supplier_name': supplierName,
        'quantity': quantity,
        'status': status,
        'new_lot_id': newLotId,
        'created_at': createdAt.toIso8601String(),
        'closed_at': closedAt?.toIso8601String(),
      };

  factory LotExchange.fromMap(Map<String, dynamic> m) => LotExchange(
        id: m['id'] as String,
        businessId: m['business_id'] as String,
        productId: m['product_id'] as String,
        productName: m['product_name'] as String? ?? '',
        lotId: m['lot_id'] as String,
        supplierId: m['supplier_id'] as String?,
        supplierName: m['supplier_name'] as String?,
        quantity: (m['quantity'] as num?)?.toInt() ?? 0,
        status: m['status'] as String? ?? pending,
        newLotId: m['new_lot_id'] as String?,
        createdAt: DateTime.tryParse('${m['created_at']}') ?? DateTime.now(),
        closedAt: DateTime.tryParse('${m['closed_at'] ?? ''}'),
      );
}
