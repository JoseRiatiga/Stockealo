import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:stockealo/admin/admin_backup_card.dart';
import 'package:stockealo/core/theme/app_theme.dart';

/// 0.16.0, fase 5: la copia diaria en el panel
void main() {
  setUpAll(() async {
    await initializeDateFormatting('es_CO');
    final loader = FontLoader('Inter');
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      loader.addFont(rootBundle.load('assets/fonts/inter/Inter-$w.ttf'));
    }
    await loader.load();
  });

  test('lee lo que manda la nube, también números como texto', () {
    final r = BackupRun.fromJson({
      'day': '2026-11-16', 'started_at': '2026-11-16T08:00:00Z', 'ok': true, 'by': 'cron',
      'tables': 42, 'rows': '1520', 'bytes': 2 * 1024 * 1024, 'error': null,
    });
    expect(r.ok, isTrue);
    expect(r.rows, 1520);
    expect(r.size, '2.0 MB');
    expect(BackupRun(day: _d, startedAt: _d, ok: true, bytes: 3000).size, '3 KB');
  });

  Future<void> pump(WidgetTester tester, List<BackupRun> runs, DateTime now) async {
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(body: SingleChildScrollView(child: AdminBackupCard(key: UniqueKey(), loader: () async => runs, now: now))),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('completa, incompleta, atrasada y sin copias', (tester) async {
    final now = DateTime(2026, 11, 16, 10);
    final ok = BackupRun(day: now, startedAt: now.subtract(const Duration(hours: 7)), ok: true, tables: 42, rows: 1520, bytes: 90000);
    await pump(tester, [ok], now);
    expect(find.text('Completa'), findsOneWidget);
    expect(find.textContaining('42 tablas · 1520 filas'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await pump(tester, [BackupRun(day: now, startedAt: now.subtract(const Duration(hours: 7)), ok: false, error: 'sales: guardó 9 de 10 filas')], now);
    expect(find.text('Incompleta'), findsOneWidget);
    expect(find.text('sales: guardó 9 de 10 filas'), findsOneWidget);

    await pump(tester, [BackupRun(day: now, startedAt: now.subtract(const Duration(days: 3)), ok: true)], now);
    expect(find.text('Atrasada'), findsOneWidget, reason: 'más de un día y medio sin copia');

    await pump(tester, const [], now);
    expect(find.textContaining('Todavía no hay copias'), findsOneWidget);
    expect(find.text('Hacer copia ahora'), findsOneWidget);
  });
}

final _d = DateTime(2026, 11, 16);
