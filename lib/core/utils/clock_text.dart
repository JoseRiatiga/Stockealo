/// La hora como se escribe en toda la app (0.16.3): «5:04 p. m.», en 12 horas.
/// Antes la pastilla de la caja usaba el formato del navegador («17:04») y el resto
/// «5:04 p. m.». Da lo mismo que `DateFormat('h:mm a', 'es_CO')` (con el espacio
/// fino que no deja partir «p. m.»), sin depender de cargar el idioma.
String clockText(DateTime d) {
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  return '$h:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? 'a.\u202Fm.' : 'p.\u202Fm.'}';
}
