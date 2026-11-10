import 'dart:convert';

/// Turno de caja: se abre con una base en efectivo y se cierra contando el dinero.
class CashSession {
  final String id;
  final String businessId;
  final String openedBy;
  final DateTime openedAt;
  final double openingAmount;
  final DateTime? closedAt;
  final String? closedBy;
  final double? expectedAmount;
  final double? countedAmount;
  final String? notes;

  /// Resumen guardado al cerrar: por forma de pago, conteo por billetes, propinas…
  final Map<String, dynamic> summary;
  final DateTime? updatedAt;

  const CashSession({
    required this.id,
    required this.businessId,
    required this.openedBy,
    required this.openedAt,
    required this.openingAmount,
    this.closedAt,
    this.closedBy,
    this.expectedAmount,
    this.countedAmount,
    this.notes,
    this.summary = const {},
    this.updatedAt,
  });

  bool get isOpen => closedAt == null;

  /// Positivo: sobra dinero. Negativo: falta.
  double? get difference =>
      (countedAmount != null && expectedAmount != null) ? countedAmount! - expectedAmount! : null;

  /// La caja quedó abierta desde un día anterior
  bool isStale([DateTime? now]) {
    final n = now ?? DateTime.now();
    return isOpen && DateTime(openedAt.year, openedAt.month, openedAt.day).isBefore(DateTime(n.year, n.month, n.day));
  }

  CashSession copyWith({
    DateTime? closedAt,
    String? closedBy,
    double? expectedAmount,
    double? countedAmount,
    String? notes,
    Map<String, dynamic>? summary,
    DateTime? updatedAt,
  }) =>
      CashSession(
        id: id,
        businessId: businessId,
        openedBy: openedBy,
        openedAt: openedAt,
        openingAmount: openingAmount,
        closedAt: closedAt ?? this.closedAt,
        closedBy: closedBy ?? this.closedBy,
        expectedAmount: expectedAmount ?? this.expectedAmount,
        countedAmount: countedAmount ?? this.countedAmount,
        notes: notes ?? this.notes,
        summary: summary ?? this.summary,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'business_id': businessId,
        'opened_by': openedBy,
        'opened_at': openedAt.toIso8601String(),
        'opening_amount': openingAmount,
        'closed_at': closedAt?.toIso8601String(),
        'closed_by': closedBy,
        'expected_amount': expectedAmount,
        'counted_amount': countedAmount,
        'notes': notes,
        'summary': jsonEncode(summary),
        'updated_at': (updatedAt ?? closedAt ?? openedAt).toIso8601String(),
      };

  factory CashSession.fromMap(Map<String, dynamic> map) {
    final raw = map['summary'];
    Map<String, dynamic> summary = const {};
    if (raw is Map) {
      summary = Map<String, dynamic>.from(raw);
    } else if (raw is String && raw.trim().isNotEmpty) {
      try {
        summary = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      } catch (_) {}
    }
    return CashSession(
      id: map['id'] as String,
      businessId: map['business_id'] as String,
      openedBy: map['opened_by'] as String,
      openedAt: DateTime.parse(map['opened_at'] as String).toLocal(),
      openingAmount: (map['opening_amount'] as num).toDouble(),
      closedAt: map['closed_at'] != null ? DateTime.parse(map['closed_at'] as String).toLocal() : null,
      closedBy: map['closed_by'] as String?,
      expectedAmount: (map['expected_amount'] as num?)?.toDouble(),
      countedAmount: (map['counted_amount'] as num?)?.toDouble(),
      notes: map['notes'] as String?,
      summary: summary,
      updatedAt: DateTime.tryParse('${map['updated_at']}')?.toLocal(),
    );
  }
}

/// Entrada o salida de efectivo hecha a mano durante el turno
class CashMovement {
  static const entry = 'ENTRADA';
  static const exit = 'SALIDA';

  /// Motivos de salida y entrada
  static const reasons = <String, String>{
    'GASTO': 'Gasto',
    'RETIRO': 'Retiro',
    'PROVEEDOR': 'Pago a proveedor',
    'PROPINA': 'Propina entregada',
    'BASE': 'Más base',
    'OTRO': 'Otro',
  };

  static const exitReasons = ['GASTO', 'RETIRO', 'PROVEEDOR', 'PROPINA', 'OTRO'];
  static const entryReasons = ['BASE', 'OTRO'];

  final String id;
  final String businessId;
  final String sessionId;
  final String kind;
  final String reason;
  final double amount;
  final String? note;
  final String? createdBy;
  final DateTime date;

  const CashMovement({
    required this.id,
    required this.businessId,
    required this.sessionId,
    required this.kind,
    required this.reason,
    required this.amount,
    this.note,
    this.createdBy,
    required this.date,
  });

  bool get isExit => kind == exit;
  String get reasonLabel => reasons[reason] ?? reason;

  /// Positivo si entra, negativo si sale
  double get signed => isExit ? -amount : amount;

  Map<String, dynamic> toMap() => {
        'id': id,
        'business_id': businessId,
        'session_id': sessionId,
        'kind': kind,
        'reason': reason,
        'amount': amount,
        'note': note,
        'created_by': createdBy,
        'date': date.toIso8601String(),
      };

  factory CashMovement.fromMap(Map<String, dynamic> m) => CashMovement(
        id: m['id'] as String,
        businessId: m['business_id'] as String,
        sessionId: m['session_id'] as String,
        kind: m['kind'] as String? ?? exit,
        reason: m['reason'] as String? ?? 'OTRO',
        amount: (m['amount'] as num?)?.toDouble() ?? 0,
        note: m['note'] as String?,
        createdBy: m['created_by'] as String?,
        date: DateTime.tryParse('${m['date']}')?.toLocal() ?? DateTime.now(),
      );
}

/// Lo que pasó en el turno y el efectivo que debería haber en caja
class CashSummary {
  final double openingAmount;
  final double cashSales;
  final int cashSalesCount;
  final double cashPayments;

  /// Propinas cobradas en efectivo (son de quienes atendieron)
  final double tipsIn;

  /// Propinas ya entregadas (salidas con motivo «Propina entregada»)
  final double tipsOut;

  /// Entradas y salidas a mano (sin contar las propinas entregadas)
  final double entries;
  final double exits;

  /// Mercancía pagada de contado en el turno
  final double cashPurchases;

  /// Ventas y abonos por forma de pago (EFECTIVO, TRANSFERENCIA, FIADO…)
  final Map<String, double> byMethod;

  const CashSummary({
    required this.openingAmount,
    required this.cashSales,
    required this.cashSalesCount,
    required this.cashPayments,
    this.tipsIn = 0,
    this.tipsOut = 0,
    this.entries = 0,
    this.exits = 0,
    this.cashPurchases = 0,
    this.byMethod = const {},
  });

  double get tipsToDeliver => tipsIn - tipsOut;

  double get expected =>
      openingAmount + cashSales + cashPayments + tipsIn - tipsOut + entries - exits - cashPurchases;

  Map<String, dynamic> toJson() => {
        'opening': openingAmount,
        'cash_sales': cashSales,
        'cash_sales_count': cashSalesCount,
        'cash_payments': cashPayments,
        'tips_in': tipsIn,
        'tips_out': tipsOut,
        'entries': entries,
        'exits': exits,
        'cash_purchases': cashPurchases,
        'by_method': byMethod,
        'expected': expected,
      };
}

/// Billetes y monedas para contar la caja (pesos colombianos)
const kCopDenominations = <int>[100000, 50000, 20000, 10000, 5000, 2000, 1000, 500, 200, 100, 50];
