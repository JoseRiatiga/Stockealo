/// Datos extra de una orden (0.14.0) para taller, servicio técnico y lavandería.
/// Van juntos en una sola columna (`extra`, JSON) para no cambiar la tabla cada vez.
class OrderExtra {
  /// Presupuesto: el cliente tiene que aprobarlo antes de empezar
  static const quotePending = 'PENDIENTE';
  static const quoteApproved = 'APROBADO';
  static const quoteRejected = 'RECHAZADO';

  /// Estado propio del negocio («Esperando repuesto»); null = el normal
  final String? stage;

  /// Cuándo se le entrega al cliente
  final DateTime? dueAt;

  /// Presupuesto: null = no hace falta aprobarlo
  final String? quoteStatus;

  /// Quién lo aprobó o rechazó, cómo y cuándo («Aprobado por WhatsApp · Juan · 14/11 3:20 p. m.»)
  final String? quoteNote;

  /// Lo que el cliente dejó con el equipo o vehículo (cargador, estuche, llaves…)
  final String? accessories;

  /// Fotos al recibir (direcciones en la nube)
  final List<String> photos;

  /// Días de garantía del trabajo
  final int? warrantyDays;

  const OrderExtra({
    this.stage,
    this.dueAt,
    this.quoteStatus,
    this.quoteNote,
    this.accessories,
    this.photos = const [],
    this.warrantyDays,
  });

  static const none = OrderExtra();

  bool get isEmpty =>
      stage == null && dueAt == null && quoteStatus == null && (accessories ?? '').isEmpty && photos.isEmpty && warrantyDays == null;

  /// Todavía no se puede empezar: falta que el cliente apruebe el presupuesto
  bool get awaitingApproval => quoteStatus == quotePending;

  /// Ya pasó la fecha de entrega
  bool isLate(DateTime now) => dueAt != null && now.isAfter(dueAt!);

  /// Garantía hasta (desde la entrega)
  DateTime? warrantyUntil(DateTime deliveredAt) =>
      warrantyDays == null || warrantyDays! <= 0 ? null : deliveredAt.add(Duration(days: warrantyDays!));

  OrderExtra copyWith({
    String? stage,
    bool clearStage = false,
    DateTime? dueAt,
    String? quoteStatus,
    String? quoteNote,
    String? accessories,
    List<String>? photos,
    int? warrantyDays,
  }) =>
      OrderExtra(
        stage: clearStage ? null : (stage ?? this.stage),
        dueAt: dueAt ?? this.dueAt,
        quoteStatus: quoteStatus ?? this.quoteStatus,
        quoteNote: quoteNote ?? this.quoteNote,
        accessories: accessories ?? this.accessories,
        photos: photos ?? this.photos,
        warrantyDays: warrantyDays ?? this.warrantyDays,
      );

  Map<String, dynamic> toJson() => {
        if (stage != null) 'stage': stage,
        if (dueAt != null) 'due_at': dueAt!.toUtc().toIso8601String(),
        if (quoteStatus != null) 'quote_status': quoteStatus,
        if (quoteNote != null) 'quote_note': quoteNote,
        if ((accessories ?? '').isNotEmpty) 'accessories': accessories,
        if (photos.isNotEmpty) 'photos': photos,
        if (warrantyDays != null) 'warranty_days': warrantyDays,
      };

  factory OrderExtra.fromJson(Object? raw) {
    if (raw is! Map) return none;
    final j = Map<String, dynamic>.from(raw);
    return OrderExtra(
      stage: j['stage'] as String?,
      dueAt: DateTime.tryParse('${j['due_at'] ?? ''}')?.toLocal(),
      quoteStatus: j['quote_status'] as String?,
      quoteNote: j['quote_note'] as String?,
      accessories: j['accessories'] as String?,
      photos: [for (final p in (j['photos'] as List? ?? const [])) '$p'],
      warrantyDays: (j['warranty_days'] as num?)?.toInt(),
    );
  }
}
