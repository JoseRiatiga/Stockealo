import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// La hora del negocio (0.16.6, hallazgo 62, «camino simple»).
///
/// Stockealo guarda en el equipo y en la nube la hora del reloj del negocio, sin zona
/// («17:04»). Si el equipo tiene otra zona (un computador mal configurado, el dueño
/// de viaje), [now] da igual la hora del negocio: así las ventas, la caja y «hoy»
/// quedan con la hora de allá. Cuando las dos zonas coinciden es lo mismo que
/// `DateTime.now()`.
///
/// La zona sale del negocio activo ([Business.zone]): la del país, o la elegida en
/// EE. UU. y México. Nunca se convierte con `toUtc()` una hora del reloj: eso usa la
/// zona del equipo.
class BusinessClock {
  BusinessClock._();

  static tz.Location? _location;
  static bool _loaded = false;

  /// Zona del negocio activo; null = la del equipo
  static String? get zone => _location?.name;

  /// Usa la zona del negocio activo (null o desconocida = la del equipo)
  static void use(String? zone) {
    // Para pruebas: --dart-define=FORCE_BUSINESS_ZONE=Pacific/Kiritimati obliga una zona
    // lejana y deja ver dónde se mezclan la hora del equipo y la del negocio
    const forced = String.fromEnvironment('FORCE_BUSINESS_ZONE');
    final z = forced.isNotEmpty && zone != null ? forced : zone;
    _location = z == null ? null : locationOf(z);
  }

  /// La zona por su nombre IANA («America/Bogota»); null si no existe
  static tz.Location? locationOf(String zone) {
    try {
      if (!_loaded) {
        tz_data.initializeTimeZones();
        _loaded = true;
      }
      return tz.getLocation(zone);
    } catch (_) {
      return null;
    }
  }

  /// Ahora, con la hora del reloj del negocio
  static DateTime now() {
    final device = DateTime.now();
    final location = _location;
    if (location == null) return device;
    return wallAt(device, location, device: device);
  }

  /// La hora del reloj en [location] para un instante dado
  static DateTime wallAt(DateTime instant, tz.Location location, {DateTime? device}) {
    final t = tz.TZDateTime.from(instant, location);
    // Misma zona que el equipo: la hora tal cual (sin pasar por la tabla de zonas)
    if (device != null && t.timeZoneOffset == device.timeZoneOffset) return device;
    return DateTime(t.year, t.month, t.day, t.hour, t.minute, t.second, t.millisecond, t.microsecond);
  }

  /// Una hora del reloj del negocio como la guarda la nube: los mismos números
  /// escritos como UTC («17:04+00» = las 5:04 p. m. en el negocio). Para enviar
  /// rangos de fechas a la nube.
  static String cloudIso(DateTime wall) => DateTime.utc(
        wall.year,
        wall.month,
        wall.day,
        wall.hour,
        wall.minute,
        wall.second,
        wall.millisecond,
        wall.microsecond,
      ).toIso8601String();
}

/// «Ahora» en el negocio activo: para la hora de lo que se registra y para «hoy»
DateTime appNow() => BusinessClock.now();
