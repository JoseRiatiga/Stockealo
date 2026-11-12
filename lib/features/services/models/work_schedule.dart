import 'dart:convert';

/// Un turno: de [start] a [end], en minutos desde la medianoche (8:00 a. m. = 480)
class ShiftTime {
  final int start;
  final int end;

  const ShiftTime(this.start, this.end);

  bool contains(int minute) => minute >= start && minute < end;

  static String clock(int minutes) {
    final h24 = minutes ~/ 60, m = minutes % 60;
    final h = h24 % 12 == 0 ? 12 : h24 % 12;
    return '$h:${m.toString().padLeft(2, '0')} ${h24 < 12 ? 'a. m.' : 'p. m.'}';
  }

  String get label => '${clock(start)} – ${clock(end)}';

  @override
  bool operator ==(Object other) => other is ShiftTime && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);
}

/// Cómo está un empleado frente a su turno en un momento
enum ShiftState {
  /// No tiene horario (ni propio ni del negocio)
  none,

  /// Hoy no le toca
  dayOff,

  /// Todavía no empieza su turno
  before,

  /// Está en su turno
  during,

  /// Ya terminó su turno
  after,
}

/// Horario de trabajo (0.13.1): qué días y de qué hora a qué hora. Puede ser el del
/// negocio (para todos) o el propio de un empleado, que reemplaza al del negocio.
/// Fuera del turno solo se avisa; no se bloquea (decisión del dueño, 11 nov 2026).
class WorkSchedule {
  /// Por día de la semana: 1 = lunes … 7 = domingo. Un día que no está = no trabaja.
  final Map<int, ShiftTime> days;

  const WorkSchedule(this.days);

  static const dayNames = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];

  /// De lunes a sábado, de 8:00 a. m. a 6:00 p. m. (para empezar a editar)
  static const typical = WorkSchedule({
    1: ShiftTime(480, 1080), 2: ShiftTime(480, 1080), 3: ShiftTime(480, 1080),
    4: ShiftTime(480, 1080), 5: ShiftTime(480, 1080), 6: ShiftTime(480, 1080),
  });

  bool get isEmpty => days.isEmpty;

  ShiftTime? on(DateTime d) => days[d.weekday];

  ShiftState stateAt(DateTime t) {
    if (days.isEmpty) return ShiftState.none;
    final shift = on(t);
    if (shift == null) return ShiftState.dayOff;
    final m = t.hour * 60 + t.minute;
    if (m < shift.start) return ShiftState.before;
    if (m >= shift.end) return ShiftState.after;
    return ShiftState.during;
  }

  /// En palabras: «Lun a sáb · 8:00 a. m. – 6:00 p. m.», o día por día si cambian
  String describe() {
    if (days.isEmpty) return 'Sin horario';
    final keys = days.keys.toList()..sort();
    final same = days.values.toSet().length == 1;
    final consecutive = keys.last - keys.first + 1 == keys.length;
    if (same) {
      final when = keys.length == 1
          ? dayNames[keys.first - 1]
          : consecutive
              ? '${dayNames[keys.first - 1]} a ${dayNames[keys.last - 1].toLowerCase()}'
              : keys.map((d) => dayNames[d - 1]).join(', ');
      return '$when · ${days[keys.first]!.label}';
    }
    return keys.map((d) => '${dayNames[d - 1]} ${days[d]!.label}').join(' · ');
  }

  String encode() => jsonEncode({for (final e in days.entries) '${e.key}': [e.value.start, e.value.end]});

  static WorkSchedule? decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final days = <int, ShiftTime>{};
      for (final e in map.entries) {
        final v = e.value as List;
        days[int.parse(e.key)] = ShiftTime((v[0] as num).toInt(), (v[1] as num).toInt());
      }
      return WorkSchedule(days);
    } catch (_) {
      return null;
    }
  }
}
