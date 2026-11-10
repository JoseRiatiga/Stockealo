import '../services/maintenance_service.dart';

/// Textos del mantenimiento programado (0.12.0). Los usan la app (franja y ventana)
/// y el panel (vista previa), así los dos dicen exactamente lo mismo.
///
/// El panel programa en hora de Colombia (UTC−5, sin cambio de horario). Si el
/// equipo de la persona está en otra zona, también se le muestra su hora local.
class MaintenanceText {
  MaintenanceText._();

  static const colombiaOffset = Duration(hours: -5);

  static const _months = [
    'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
    'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
  ];

  /// Mensajes listos para el panel
  static const presets = <(String, String)>[
    ('Recomendación', 'Te recomendamos no agregar ni modificar productos, ventas ni clientes durante ese horario.'),
    ('Mejoras', 'Estamos actualizando y mejorando funciones de Stockealo.'),
    ('Velocidad', 'Estamos mejorando la velocidad de la app.'),
  ];

  /// La hora de Colombia de un instante, como DateTime con esos números (en UTC)
  static DateTime colombiaWall(DateTime instant) => instant.toUtc().add(colombiaOffset);

  /// Instante que corresponde a esa fecha y hora en Colombia
  static DateTime fromColombia(int year, int month, int day, int hour, int minute) =>
      DateTime.utc(year, month, day, hour, minute).subtract(colombiaOffset);

  static String _hour(DateTime d) {
    final h12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
    return '$h12:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? 'a. m.' : 'p. m.'}';
  }

  static String _day(DateTime d) => '${d.day} de ${_months[d.month - 1]}';

  static bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  /// "el 5 de diciembre de 11:00 p. m. a 2:00 a. m." con las horas ya convertidas
  static String _range(DateTime s, DateTime e, DateTime today) {
    final startDay = _sameDay(s, today) ? 'hoy' : 'el ${_day(s)}';
    // Si termina al día siguiente de madrugada basta con la hora; si no, se dice el día
    final nextMorning = e.difference(DateTime(s.year, s.month, s.day)).inHours < 36 && e.hour < 12 && !_sameDay(s, e);
    final end = _sameDay(s, e) || nextMorning ? _hour(e) : '${_hour(e)} del ${_day(e)}';
    return '$startDay de ${_hour(s)} a $end';
  }

  /// Horario en hora de Colombia y, si el equipo está en otra zona, también en su hora
  static String describe(DateTime starts, DateTime ends, {DateTime? now, Duration? deviceOffset}) {
    final n = now ?? DateTime.now();
    final co = _range(colombiaWall(starts), colombiaWall(ends), colombiaWall(n));
    final offset = deviceOffset ?? n.timeZoneOffset;
    if (offset == colombiaOffset) return '$co (hora Colombia)';
    DateTime local(DateTime d) => d.toUtc().add(offset);
    final mine = _range(local(starts), local(ends), local(n));
    return '$co (hora Colombia; en tu hora: $mine)';
  }

  /// "3 h" o "1 h 30 min"
  static String duration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    if (h == 0) return '$m min';
    return m == 0 ? '$h h' : '$h h $m min';
  }

  /// Franja de arriba de la app
  static String? banner(MaintenanceState s, {required bool isAdmin, DateTime? now, Duration? deviceOffset}) {
    if (!s.affects('app') || s.startsAt == null || s.endsAt == null) return null;
    final note = (s.message ?? '').trim();
    final extra = note.isEmpty ? '' : ' $note';
    final when = describe(s.startsAt!, s.endsAt!, now: now, deviceOffset: deviceOffset);
    if (s.notice) return 'Mantenimiento programado $when.$extra';
    if (!s.active) return null;
    if (isAdmin) return 'Mantenimiento en curso (nivel ${s.level}): eres administrador, puedes seguir usando la app.';
    if (s.level >= 2) {
      return 'Estamos haciendo cambios en Stockealo ($when). Puedes seguir vendiendo: '
          'todo se guarda en este equipo y se sube al terminar.$extra';
    }
    return 'Estamos haciendo cambios en Stockealo ($when).$extra';
  }

  /// Qué va a pasar según el nivel
  static String levelEffect(int level) => switch (level) {
        1 => 'La app seguirá funcionando normal.',
        2 => 'Podrás seguir vendiendo: lo que hagas se guarda en este equipo y se sube a la nube al terminar.',
        _ => 'La app no estará disponible durante ese horario. Tus datos están a salvo.',
      };

  /// Ventana que sale una vez por mantenimiento programado
  static ({String title, String body}) noticeDialog(MaintenanceState s, {DateTime? now, Duration? deviceOffset}) {
    final when = s.startsAt == null || s.endsAt == null ? '' : describe(s.startsAt!, s.endsAt!, now: now, deviceOffset: deviceOffset);
    final note = (s.message ?? '').trim();
    return (
      title: 'Mantenimiento programado',
      body: [
        'Haremos mantenimiento $when.',
        levelEffect(s.level),
        if (note.isNotEmpty) note,
      ].join('\n\n'),
    );
  }

  /// Clave para recordar que ya se vio la ventana de este mantenimiento
  static String seenKey(MaintenanceState s) =>
      '${s.startsAt?.toUtc().toIso8601String()}|${s.endsAt?.toUtc().toIso8601String()}|${s.level}';
}
