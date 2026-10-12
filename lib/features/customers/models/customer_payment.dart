class CustomerPayment {
  final String id;
  final String businessId;
  final String customerId;
  final String? saleId;
  final double amount;
  final String paymentMethod; // 'EFECTIVO' | 'TRANSFERENCIA'
  final DateTime date;
  final String? notes;

  const CustomerPayment({
    required this.id,
    required this.businessId,
    required this.customerId,
    this.saleId,
    required this.amount,
    required this.paymentMethod,
    required this.date,
    this.notes,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'business_id': businessId,
      'customer_id': customerId,
      'sale_id': saleId,
      'amount': amount,
      'payment_method': paymentMethod,
      'date': date.toIso8601String(),
      'notes': notes,
    };
  }

  factory CustomerPayment.fromMap(Map<String, dynamic> map) {
    return CustomerPayment(
      id: map['id'] as String,
      businessId: map['business_id'] as String,
      customerId: map['customer_id'] as String,
      saleId: map['sale_id'] as String?,
      amount: (map['amount'] as num?)?.toDouble() ?? 0.0,
      paymentMethod: map['payment_method'] as String? ?? 'EFECTIVO',
      date: map['date'] != null
          ? DateTime.tryParse(map['date'] as String) ?? DateTime.now()
          : DateTime.now(),
      notes: map['notes'] as String?,
    );
  }
}
