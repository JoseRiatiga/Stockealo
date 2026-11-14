import 'package:flutter_test/flutter_test.dart';
import 'package:stockealo/features/store/data/booking_service.dart';

/// Reservas en línea (0.14.0): horas libres según el horario y lo ocupado
void main() {
  // Martes 1 de diciembre de 2026, a las 7:00 a. m.
  final now = DateTime(2026, 12, 1, 7);
  final day = DateTime(2026, 12, 1);

  PublicBooking booking({List<Map<String, dynamic>> busy = const []}) => PublicBooking.fromJson({
        'schedule': '{"2":[540,720]}', // martes de 9:00 a 12:00
        'services': [
          {'id': 's1', 'name': 'Corte', 'price': 20000, 'duration_min': 30},
        ],
        'staff': [
          {'id': 'juan', 'name': 'Juan'},
          {'id': 'pedro', 'name': 'Pedro'},
        ],
        'busy': busy,
      });

  String hhmm(DateTime d) => '${d.hour}:${d.minute.toString().padLeft(2, '0')}';

  test('dentro del horario, cada 30 minutos, sin pasarse del cierre', () {
    final slots = booking().freeSlots(day, 60, now: now);
    expect(slots.map(hhmm), ['9:00', '9:30', '10:00', '10:30', '11:00']);
  });

  test('un día que no trabaja no tiene horas', () {
    expect(booking().freeSlots(DateTime(2026, 12, 2), 30, now: now), isEmpty);
  });

  test('lo ocupado de un empleado: con él no hay hora, con cualquiera sí', () {
    final b = booking(busy: [
      {'staff_id': 'juan', 'starts_at': DateTime(2026, 12, 1, 9).toUtc().toIso8601String(), 'ends_at': DateTime(2026, 12, 1, 10).toUtc().toIso8601String()},
    ]);
    expect(b.freeSlots(day, 30, staffId: 'juan', now: now).map(hhmm), isNot(contains('9:00')));
    expect(b.freeSlots(day, 30, staffId: 'juan', now: now).map(hhmm), contains('10:00'));
    expect(b.freeSlots(day, 30, now: now).map(hhmm), contains('9:00'), reason: 'Pedro está libre');
  });

  test('no ofrece horas que ya pasaron (ni las de la próxima media hora)', () {
    final slots = booking().freeSlots(day, 30, now: DateTime(2026, 12, 1, 10, 10));
    expect(slots.map(hhmm).first, '11:00');
  });
}
