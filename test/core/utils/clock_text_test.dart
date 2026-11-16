import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:stockealo/core/utils/clock_text.dart';

void main() {
  test('la hora va en 12 horas en toda la app: 17:04 es «5:04 p. m.» (0.16.3)', () async {
    expect(clockText(DateTime(2026, 11, 16, 17, 4)), '5:04 p. m.');
    expect(clockText(DateTime(2026, 11, 16, 0, 5)), '12:05 a. m.');
    expect(clockText(DateTime(2026, 11, 16, 12, 0)), '12:00 p. m.');
    // Igual que los recibos y demás pantallas que usan el formato de Colombia
    await initializeDateFormatting('es_CO');
    for (final h in [0, 9, 12, 17, 23]) {
      final d = DateTime(2026, 11, 16, h, 7);
      expect(clockText(d), DateFormat('h:mm a', 'es_CO').format(d));
    }
  });
}
