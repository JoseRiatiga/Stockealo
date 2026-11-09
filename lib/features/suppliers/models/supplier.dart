/// Proveedor del negocio. Solo el nombre es obligatorio.
class Supplier {
  final String id;
  final String businessId;
  final String name;
  final String? contactName;
  final String? phone;
  final String? email;
  final String? taxId;

  /// Día en que suele pasar el vendedor (ej. 'Lunes')
  final String? visitDay;

  /// Días que tarda en entregar desde el pedido
  final int? deliveryDays;
  final double? minOrder;

  /// 'CONTADO' o 'CREDITO'
  final String paymentTerms;
  final int? creditDays;
  final String? notes;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Supplier({
    required this.id,
    required this.businessId,
    required this.name,
    this.contactName,
    this.phone,
    this.email,
    this.taxId,
    this.visitDay,
    this.deliveryDays,
    this.minOrder,
    this.paymentTerms = 'CONTADO',
    this.creditDays,
    this.notes,
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
  });

  static const weekDays = ['Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado', 'Domingo'];

  bool get isCredit => paymentTerms == 'CREDITO';

  /// Resumen corto para la lista: "Contado · Pasa los lunes · Entrega en 3 días"
  String get summary {
    final parts = <String>[
      isCredit ? 'Crédito${creditDays != null ? ' a $creditDays días' : ''}' : 'Contado',
      if ((visitDay ?? '').isNotEmpty) 'Pasa los ${visitDay!.toLowerCase()}',
      if (deliveryDays != null) 'Entrega en $deliveryDays ${deliveryDays == 1 ? 'día' : 'días'}',
    ];
    return parts.join(' · ');
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'business_id': businessId,
        'name': name,
        'contact_name': contactName,
        'phone': phone,
        'email': email,
        'tax_id': taxId,
        'visit_day': visitDay,
        'delivery_days': deliveryDays,
        'min_order': minOrder,
        'payment_terms': paymentTerms,
        'credit_days': creditDays,
        'notes': notes,
        'is_active': isActive ? 1 : 0,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  factory Supplier.fromMap(Map<String, dynamic> m) => Supplier(
        id: m['id'] as String,
        businessId: m['business_id'] as String,
        name: m['name'] as String,
        contactName: m['contact_name'] as String?,
        phone: m['phone'] as String?,
        email: m['email'] as String?,
        taxId: m['tax_id'] as String?,
        visitDay: m['visit_day'] as String?,
        deliveryDays: (m['delivery_days'] as num?)?.toInt(),
        minOrder: (m['min_order'] as num?)?.toDouble(),
        paymentTerms: (m['payment_terms'] as String?) ?? 'CONTADO',
        creditDays: (m['credit_days'] as num?)?.toInt(),
        notes: m['notes'] as String?,
        isActive: (m['is_active'] as int? ?? 1) == 1,
        createdAt: DateTime.tryParse(m['created_at'] as String? ?? '') ?? DateTime.now(),
        updatedAt: DateTime.tryParse(m['updated_at'] as String? ?? '') ?? DateTime.now(),
      );

  Supplier copyWith({
    String? name,
    String? contactName,
    String? phone,
    String? email,
    String? taxId,
    String? visitDay,
    int? deliveryDays,
    double? minOrder,
    String? paymentTerms,
    int? creditDays,
    String? notes,
    bool? isActive,
    DateTime? updatedAt,
  }) =>
      Supplier(
        id: id,
        businessId: businessId,
        name: name ?? this.name,
        contactName: contactName ?? this.contactName,
        phone: phone ?? this.phone,
        email: email ?? this.email,
        taxId: taxId ?? this.taxId,
        visitDay: visitDay ?? this.visitDay,
        deliveryDays: deliveryDays ?? this.deliveryDays,
        minOrder: minOrder ?? this.minOrder,
        paymentTerms: paymentTerms ?? this.paymentTerms,
        creditDays: creditDays ?? this.creditDays,
        notes: notes ?? this.notes,
        isActive: isActive ?? this.isActive,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}
