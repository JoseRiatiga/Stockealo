/// Comisiones y liquidaciones del módulo Servicios (0.12.0)
library;

/// Lo que gana una persona por un servicio cobrado (o una propina, o un ajuste)
class Commission {
  static const kindService = 'SERVICIO';
  static const kindTip = 'PROPINA';
  static const kindAdjustment = 'AJUSTE';

  final String id;
  final String businessId;
  final String staffId;
  final String? workOrderId;

  /// Venta de la que sale la comisión (null en propinas y ajustes sin venta)
  final String? saleId;
  final String kind;

  /// Nombre del servicio, "Propina" o el motivo del ajuste
  final String label;

  /// Parte de lo cobrado que le corresponde a esta persona (después del descuento)
  final double base;
  final double pct;
  final double amount;
  final DateTime date;

  /// Liquidación en la que se pagó (null = pendiente)
  final String? payoutId;
  final DateTime updatedAt;

  const Commission({
    required this.id,
    required this.businessId,
    required this.staffId,
    this.workOrderId,
    this.saleId,
    this.kind = kindService,
    required this.label,
    this.base = 0,
    this.pct = 0,
    required this.amount,
    required this.date,
    this.payoutId,
    required this.updatedAt,
  });

  bool get isPaid => payoutId != null;
  bool get isTip => kind == kindTip;

  Commission copyWith({String? payoutId, DateTime? updatedAt}) => Commission(
        id: id,
        businessId: businessId,
        staffId: staffId,
        workOrderId: workOrderId,
        saleId: saleId,
        kind: kind,
        label: label,
        base: base,
        pct: pct,
        amount: amount,
        date: date,
        payoutId: payoutId ?? this.payoutId,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'business_id': businessId,
        'staff_id': staffId,
        'work_order_id': workOrderId,
        'sale_id': saleId,
        'kind': kind,
        'label': label,
        'base': base,
        'pct': pct,
        'amount': amount,
        'date': date.toIso8601String(),
        'payout_id': payoutId,
        'updated_at': updatedAt.toIso8601String(),
      };

  factory Commission.fromMap(Map<String, dynamic> m) => Commission(
        id: m['id'] as String,
        businessId: m['business_id'] as String,
        staffId: m['staff_id'] as String,
        workOrderId: m['work_order_id'] as String?,
        saleId: m['sale_id'] as String?,
        kind: m['kind'] as String? ?? kindService,
        label: m['label'] as String? ?? '',
        base: (m['base'] as num?)?.toDouble() ?? 0,
        pct: (m['pct'] as num?)?.toDouble() ?? 0,
        amount: (m['amount'] as num?)?.toDouble() ?? 0,
        date: DateTime.tryParse('${m['date']}')?.toLocal() ?? DateTime.now(),
        payoutId: m['payout_id'] as String?,
        updatedAt: DateTime.tryParse('${m['updated_at']}') ?? DateTime.now(),
      );
}

/// Un pago a una persona: suma de sus comisiones y propinas pendientes
class StaffPayout {
  final String id;
  final String businessId;
  final String staffId;
  final DateTime fromDate;
  final DateTime toDate;
  final double commissions;
  final double tips;
  final DateTime paidAt;
  final String? paidBy;

  const StaffPayout({
    required this.id,
    required this.businessId,
    required this.staffId,
    required this.fromDate,
    required this.toDate,
    required this.commissions,
    required this.tips,
    required this.paidAt,
    this.paidBy,
  });

  double get total => commissions + tips;

  Map<String, dynamic> toMap() => {
        'id': id,
        'business_id': businessId,
        'staff_id': staffId,
        'from_date': fromDate.toIso8601String(),
        'to_date': toDate.toIso8601String(),
        'commissions': commissions,
        'tips': tips,
        'total': total,
        'paid_at': paidAt.toIso8601String(),
        'paid_by': paidBy,
      };

  factory StaffPayout.fromMap(Map<String, dynamic> m) => StaffPayout(
        id: m['id'] as String,
        businessId: m['business_id'] as String,
        staffId: m['staff_id'] as String,
        fromDate: DateTime.tryParse('${m['from_date']}')?.toLocal() ?? DateTime.now(),
        toDate: DateTime.tryParse('${m['to_date']}')?.toLocal() ?? DateTime.now(),
        commissions: (m['commissions'] as num?)?.toDouble() ?? 0,
        tips: (m['tips'] as num?)?.toDouble() ?? 0,
        paidAt: DateTime.tryParse('${m['paid_at']}')?.toLocal() ?? DateTime.now(),
        paidBy: m['paid_by'] as String?,
      );
}

/// Lo pendiente de una persona en un periodo
class StaffEarnings {
  final String staffId;
  final List<Commission> items;

  const StaffEarnings(this.staffId, this.items);

  double get commissions => items.where((c) => !c.isTip).fold(0.0, (s, c) => s + c.amount);
  double get tips => items.where((c) => c.isTip).fold(0.0, (s, c) => s + c.amount);
  double get total => commissions + tips;
  int get services => items.where((c) => c.kind == Commission.kindService).length;
}
