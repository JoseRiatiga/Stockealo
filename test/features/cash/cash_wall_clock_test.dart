import 'package:flutter_test/flutter_test.dart';
import 'package:stockealo/core/services/supabase_service.dart';
import 'package:stockealo/features/cash/models/cash_session.dart';

/// 0.16.4: la caja abierta a las 5:04 p. m. salía «desde las 12:04 p. m.»
/// al volver de la nube en Colombia. La hora del reloj debe quedar igual.
void main() {
  test('la apertura vuelve de la nube con la misma hora del reloj', () {
    // Así la guarda la nube: la hora del equipo marcada como UTC
    final row = SupabaseService.cashSessionLocalRow({
      'id': 's1',
      'business_id': 'b1',
      'opened_by': 'Ana',
      'opened_at': '2026-11-16T17:04:00+00:00',
      'opening_amount': 100000,
      'closed_at': null,
      'updated_at': '2026-11-16T22:04:00+00:00',
      'summary': const {},
    });
    final session = CashSession.fromMap(row);
    expect(session.openedAt.hour, 17);
    expect(session.openedAt.minute, 4);
    expect(session.closedAt, isNull);
  });

  test('el movimiento de caja conserva la hora del reloj', () {
    final row = SupabaseService.cashMovementLocalRow({'id': 'm1', 'date': '2026-11-16T19:22:00Z'});
    expect(DateTime.parse(row['date'] as String).hour, 19);
    expect((row['date'] as String).endsWith('Z'), isFalse);
  });

  test('una hora local sin zona no cambia', () {
    expect(SupabaseService.wallClockIso('2026-11-16T07:30:00.000'), '2026-11-16T07:30:00.000');
    expect(SupabaseService.wallClockIso(null), isNull);
  });
}
