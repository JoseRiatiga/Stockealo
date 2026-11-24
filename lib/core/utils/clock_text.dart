/// La hora como se escribe en toda la app (0.16.3): «5:04 p. m.», en 12 horas.
/// Antes la pastilla de la caja usaba el formato del navegador («17:04») y el resto
/// «5:04 p. m.». Da lo mismo que `DateFormat('h:mm a', 'es_CO')` (con el espacio
/// fino que no deja partir «p. m.»), sin depender de cargar el idioma.
String clockText(DateTime d) {
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  return '$h:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? 'a.\u202Fm.' : 'p.\u202Fm.'}';
}

/// Cuándo fue una venta (24 nov): «hoy 5:04 p. m.», «ayer 5:04 p. m.» o
/// «11 nov · 5:04 p. m.». Con «Todas las fechas», solo la hora no decía de qué día era.
String whenText(DateTime d, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final day = DateTime(d.year, d.month, d.day);
  final today = DateTime(n.year, n.month, n.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'hoy ${clockText(d)}';
  if (diff == 1) return 'ayer ${clockText(d)}';
  const months = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
  final year = d.year == n.year ? '' : ' ${d.year}';
  return '${d.day} ${months[d.month - 1]}$year · ${clockText(d)}';
}
