/// Metas de ventas (0.16.0, fase 0): semanal o mensual, del negocio o de una persona
/// del equipo (esta última con Pro). Se mide solo en ventas.
enum GoalPeriod {
  week('WEEK', 'Semana', 'Esta semana'),
  month('MONTH', 'Mes', 'Este mes');

  final String code;
  final String label;
  final String current;
  const GoalPeriod(this.code, this.label, this.current);

  static GoalPeriod of(String? code) => code == month.code ? month : week;

  /// Primer día del periodo que contiene [d]: la semana empieza el lunes
  DateTime startOf(DateTime d) {
    final day = DateTime(d.year, d.month, d.day);
    return this == week ? day.subtract(Duration(days: day.weekday - 1)) : DateTime(d.year, d.month);
  }

  /// Día siguiente al último del periodo que empieza en [start]
  DateTime endOf(DateTime start) => this == week ? start.add(const Duration(days: 7)) : DateTime(start.year, start.month + 1);

  /// El periodo anterior al que empieza en [start]
  DateTime previous(DateTime start) => this == week ? start.subtract(const Duration(days: 7)) : DateTime(start.year, start.month - 1);
}

class SalesGoal {
  final String id;
  final String businessId;
  final GoalPeriod period;

  /// null = meta de todo el negocio; si no, el user_id de la persona del equipo
  final String? memberUserId;
  final String? memberName;

  /// 0 = sin meta (se quitó)
  final double amount;

  /// Desde qué periodo vale: el primer día de la semana o del mes en que se puso
  final DateTime startsOn;
  final DateTime createdAt;
  final DateTime updatedAt;

  const SalesGoal({
    required this.id,
    required this.businessId,
    required this.period,
    this.memberUserId,
    this.memberName,
    required this.amount,
    required this.startsOn,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isBusiness => memberUserId == null;

  /// Un solo registro por negocio, periodo, persona y fecha de inicio: si se cambia la
  /// meta dentro del mismo mes, se reemplaza
  static String idFor(String businessId, GoalPeriod period, String? memberUserId, DateTime startsOn) =>
      '${businessId}_${period.code}_${memberUserId ?? 'negocio'}_${_day(startsOn)}';

  static String _day(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Map<String, dynamic> toMap() => {
        'id': id,
        'business_id': businessId,
        'period': period.code,
        'member_user_id': memberUserId,
        'member_name': memberName,
        'amount': amount,
        'starts_on': _day(startsOn),
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  factory SalesGoal.fromMap(Map<String, dynamic> m) {
    final start = DateTime.tryParse('${m['starts_on']}') ?? DateTime.now();
    return SalesGoal(
      id: m['id'] as String,
      businessId: m['business_id'] as String,
      period: GoalPeriod.of(m['period'] as String?),
      memberUserId: (m['member_user_id'] as String?)?.isEmpty == true ? null : m['member_user_id'] as String?,
      memberName: m['member_name'] as String?,
      amount: (m['amount'] as num?)?.toDouble() ?? 0,
      startsOn: DateTime(start.year, start.month, start.day),
      createdAt: DateTime.tryParse('${m['created_at']}') ?? DateTime.now(),
      updatedAt: DateTime.tryParse('${m['updated_at']}') ?? DateTime.now(),
    );
  }
}

/// Cómo va una meta en un periodo
class GoalProgress {
  final GoalPeriod period;
  final double goal;
  final double sold;
  final DateTime from;
  final DateTime to;
  final DateTime now;

  const GoalProgress({
    required this.period,
    required this.goal,
    required this.sold,
    required this.from,
    required this.to,
    required this.now,
  });

  double get ratio => goal <= 0 ? 0 : sold / goal;
  int get percent => (ratio * 100).floor();
  bool get reached => sold >= goal;
  double get missing => reached ? 0 : goal - sold;
  bool get isOver => !now.isBefore(to);

  int get totalDays => to.difference(from).inDays;

  /// Días que quedan contando hoy
  int get daysLeft {
    if (isOver) return 0;
    final today = DateTime(now.year, now.month, now.day);
    return to.difference(today).inDays.clamp(1, totalDays);
  }

  /// Cuánto hay que vender cada día que queda para llegar
  double get perDay => daysLeft == 0 ? 0 : missing / daysLeft;

  /// Lo que debería llevar vendido a esta altura para ir al ritmo (contando hoy entero)
  double get expectedByNow {
    if (isOver) return goal;
    final today = DateTime(now.year, now.month, now.day);
    final elapsed = today.difference(from).inDays + 1;
    return goal * elapsed / totalDays;
  }

  /// Va al ritmo (o ya llegó): verde; si no, amarillo
  bool get onPace => reached || sold >= expectedByNow * 0.95;
}
