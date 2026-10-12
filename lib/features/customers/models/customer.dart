class Customer {
  final String id;
  final String businessId;
  final String name;
  final String? phone;
  final String? address;
  final double debtBalance;
  final DateTime createdAt;
  final bool isSynced;

  const Customer({
    required this.id,
    required this.businessId,
    required this.name,
    this.phone,
    this.address,
    this.debtBalance = 0.0,
    required this.createdAt,
    this.isSynced = false,
  });

  bool get hasDebt => debtBalance > 0.01;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'business_id': businessId,
      'name': name,
      'phone': phone,
      'address': address,
      'debt_balance': debtBalance,
      'created_at': createdAt.toIso8601String(),
      'is_synced': isSynced ? 1 : 0,
    };
  }

  factory Customer.fromMap(Map<String, dynamic> map) {
    return Customer(
      id: map['id'] as String,
      businessId: map['business_id'] as String,
      name: map['name'] as String,
      phone: map['phone'] as String?,
      address: map['address'] as String?,
      debtBalance: (map['debt_balance'] as num?)?.toDouble() ?? 0.0,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'] as String) ?? DateTime.now()
          : DateTime.now(),
      isSynced: (map['is_synced'] as int?) == 1,
    );
  }

  Customer copyWith({
    String? name,
    String? phone,
    String? address,
    double? debtBalance,
  }) {
    return Customer(
      id: id,
      businessId: businessId,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      address: address ?? this.address,
      debtBalance: debtBalance ?? this.debtBalance,
      createdAt: createdAt,
      isSynced: isSynced,
    );
  }
}
