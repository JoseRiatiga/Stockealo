import 'package:flutter_test/flutter_test.dart';
import 'package:stockealo/core/services/maintenance_service.dart';
import 'package:stockealo/core/utils/maintenance_text.dart';

/// Mantenimiento programado (0.12.0): hora de Colombia, cruce de medianoche y textos
void main() {
  // 5 de diciembre, 11:00 p. m. a 2:00 a. m. del 6, hora Colombia
  final starts = MaintenanceText.fromColombia(2026, 12, 5, 23, 0);
  final ends = MaintenanceText.fromColombia(2026, 12, 6, 2, 0);
  final before = MaintenanceText.fromColombia(2026, 12, 1, 10, 0);
  const co = MaintenanceText.colombiaOffset;

  test('la hora de Colombia va y vuelve igual', () {
    expect(starts.isUtc, isTrue);
    expect(starts.toIso8601String(), '2026-12-06T04:00:00.000Z');
    final wall = MaintenanceText.colombiaWall(starts);
    expect([wall.day, wall.hour], [5, 23]);
  });

  test('el ejemplo del dueño: cruza la medianoche y dice hora Colombia', () {
    expect(
      MaintenanceText.describe(starts, ends, now: before, deviceOffset: co),
      'el 5 de diciembre de 11:00 p. m. a 2:00 a. m. (hora Colombia)',
    );
    expect(MaintenanceText.duration(ends.difference(starts)), '3 h');
    expect(MaintenanceText.duration(const Duration(minutes: 90)), '1 h 30 min');
  });

  test('desde otro país también se ve su hora local', () {
    final text = MaintenanceText.describe(starts, ends, now: before, deviceOffset: const Duration(hours: 1));
    expect(text, contains('(hora Colombia; en tu hora: el 6 de diciembre de 5:00 a. m. a 8:00 a. m.)'));
  });

  test('si es hoy dice «hoy»', () {
    final sameDay = MaintenanceText.fromColombia(2026, 12, 5, 9, 0);
    expect(MaintenanceText.describe(starts, ends, now: sameDay, deviceOffset: co), startsWith('hoy de 11:00 p. m.'));
  });

  test('la franja y la ventana repiten la recomendación y explican el nivel', () {
    final s = MaintenanceState(
      state: 'notice',
      level: 2,
      scopes: const {'app'},
      message: MaintenanceText.presets.first.$2,
      startsAt: starts,
      endsAt: ends,
    );
    final banner = MaintenanceText.banner(s, isAdmin: false, now: before, deviceOffset: co)!;
    expect(banner, startsWith('Mantenimiento programado el 5 de diciembre'));
    expect(banner, contains('no agregar ni modificar'));
    final dialog = MaintenanceText.noticeDialog(s, now: before, deviceOffset: co);
    expect(dialog.body, contains('Podrás seguir vendiendo'));
    expect(dialog.body, contains('no agregar ni modificar'));

    // En curso dice que se están haciendo cambios
    final active = MaintenanceState(state: 'active', level: 1, scopes: const {'app'}, startsAt: starts, endsAt: ends);
    expect(MaintenanceText.banner(active, isAdmin: false, now: before, deviceOffset: co), startsWith('Estamos haciendo cambios'));
    // Sin la app en mantenimiento no hay franja
    final storesOnly = MaintenanceState(state: 'notice', level: 2, scopes: const {'stores'}, startsAt: starts, endsAt: ends);
    expect(MaintenanceText.banner(storesOnly, isAdmin: false), isNull);
  });

  test('cada mantenimiento tiene su propia clave para la ventana de una sola vez', () {
    final a = MaintenanceState(state: 'notice', level: 2, scopes: const {'app'}, startsAt: starts, endsAt: ends);
    final b = MaintenanceState(state: 'notice', level: 2, scopes: const {'app'}, startsAt: starts, endsAt: ends.add(const Duration(hours: 1)));
    expect(MaintenanceText.seenKey(a), isNot(MaintenanceText.seenKey(b)));
  });
}
