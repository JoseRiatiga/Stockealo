/// Turno de caja: se abre con una base en efectivo y se cierra contando el dinero.
class CashSession {
  final String id;
  final String businessId;
  final String openedBy;
  final DateTime openedAt;
  final double openingAmount;
  final DateTime? closedAt;
  final double? expectedAmount;
  final double? countedAmount;
  final String? notes;

  const CashSession({
    required this.id,
    required this.businessId,
    required this.openedBy,
    required this.openedAt,
    required this.openingAmount,
    this.closedAt,
    this.expectedAmount,
    this.countedAmount,
    this.notes,
  });

  bool get isOpen => closedAt == null;

  /// Positivo: sobra dinero. Negativo: falta.
  double? get difference =>
      (countedAmount != null && expectedAmount != null) ? countedAmount! - expectedAmount! : null;

  Map<String, dynamic> toMap() => {
        'id': id,
        'business_id': businessId,
        'opened_by': openedBy,
        'opened_at': openedAt.toIso8601String(),
        'opening_amount': openingAmount,
        'closed_at': closedAt?.toIso8601String(),
        'expected_amount': expectedAmount,
        'counted_amount': countedAmount,
        'notes': notes,
      };

  factory CashSession.fromMap(Map<String, dynamic> map) => CashSession(
        id: map['id'] as String,
        businessId: map['business_id'] as String,
        openedBy: map['opened_by'] as String,
        openedAt: DateTime.parse(map['opened_at'] as String),
        openingAmount: (map['opening_amount'] as num).toDouble(),
        closedAt: map['closed_at'] != null ? DateTime.parse(map['closed_at'] as String) : null,
        expectedAmount: (map['expected_amount'] as num?)?.toDouble(),
        countedAmount: (map['counted_amount'] as num?)?.toDouble(),
        notes: map['notes'] as String?,
      );
}

/// Movimientos en efectivo de un turno y el dinero que debería haber en caja.
class CashSummary {
  final double openingAmount;
  final double cashSales;
  final int cashSalesCount;
  final double cashPayments;

  const CashSummary({
    required this.openingAmount,
    required this.cashSales,
    required this.cashSalesCount,
    required this.cashPayments,
  });

  double get expected => openingAmount + cashSales + cashPayments;
}
