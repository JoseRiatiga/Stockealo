import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockealo/admin/admin_errors_page.dart';
import 'package:stockealo/core/services/error_reporter.dart';
import 'package:stockealo/core/theme/app_theme.dart';

/// 0.16.0, fase 5: errores al panel de administración
void main() {
  final reporter = ErrorReporter.instance;
  final sent = <Map<String, dynamic>>[];

  setUpAll(() async {
    final loader = FontLoader('Inter');
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      loader.addFont(rootBundle.load('assets/fonts/inter/Inter-$w.ttf'));
    }
    await loader.load();
  });

  setUp(() {
    sent.clear();
    reporter.resetForTest();
    reporter.sender = (r) async => sent.add(r);
  });

  tearDown(() => reporter.sender = null);

  test('tapa correos y teléfonos antes de enviar', () {
    expect(ErrorReporter.clean('No se encontró rosa.perez@gmail.com en 300 123 4567'), 'No se encontró <correo> en <número>');
    expect(ErrorReporter.clean('Faltan 3 unidades del pedido 12'), 'Faltan 3 unidades del pedido 12', reason: 'los números cortos sí quedan');
  });

  test('el mismo error va una sola vez por sesión y nunca más de 20', () async {
    final stack = StackTrace.fromString('#0 SalesRepository.sell (sales_repository.dart:40)\n#1 main');
    await reporter.report(StateError('No se pudo guardar la venta de ana@x.com'), stack, kind: 'flutter');
    await reporter.report(StateError('No se pudo guardar la venta de ana@x.com'), stack, kind: 'flutter');
    expect(sent.length, 1);
    expect(sent.single['p_message'], contains('<correo>'));
    expect(sent.single['p_message'], isNot(contains('ana@x.com')));
    expect(sent.single['p_version'], contains('+'));
    expect(sent.single['p_fingerprint'], isNotEmpty);
    for (var i = 0; i < 40; i++) {
      await reporter.report(StateError('Error distinto $i'), null);
    }
    expect(sent.length, ErrorReporter.maxPerSession);
  });

  test('un error que nadie atrapa (tarea sin esperar) llega al panel (0.16.3)', () async {
    // run() instala los avisos de Flutter: se dejan como estaban al terminar
    final flutterBefore = FlutterError.onError;
    final platformBefore = PlatformDispatcher.instance.onError;
    addTearDown(() {
      FlutterError.onError = flutterBefore;
      PlatformDispatcher.instance.onError = platformBefore;
    });
    reporter.run('app', () async {
      // Como la consulta de la 0.16.2 que se lanzaba sin esperar y fallaba en la web
      unawaited(Future<void>.error(StateError('no such column: "OWNER"')));
    });
    await pumpEventQueue();
    expect(sent, hasLength(1));
    expect(sent.single['p_kind'], 'async');
    expect(sent.single['p_app'], 'app');
    expect(sent.single['p_message'], contains('no such column'));
  });

  test('el mismo mensaje en otro lugar es otro error', () {
    final a = ErrorReporter.fingerprint('Boom', '#0 a.dart:1');
    expect(ErrorReporter.fingerprint('Boom', '#0 a.dart:1'), a);
    expect(ErrorReporter.fingerprint('Boom', '#0 b.dart:9'), isNot(a));
  });

  testWidgets('el panel muestra los errores agrupados y su detalle', (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final now = DateTime.now();
    Future<List<AppErrorGroup>> loader(int days) async => [
          AppErrorGroup(
            fingerprint: 'a1',
            message: 'No se pudo guardar la venta',
            count: 14,
            lastAt: now.subtract(const Duration(hours: 2)),
            versions: const ['0.16.0+48'],
            platforms: const ['android'],
            apps: const ['app'],
            stack: '#0 SalesRepository.sell',
          ),
          AppErrorGroup(fingerprint: 'b2', message: 'Foto del producto no carga', count: 3, lastAt: now.subtract(const Duration(days: 1))),
        ];
    await tester.pumpWidget(MaterialApp(theme: AppTheme.lightTheme, home: Scaffold(body: AdminErrorsPage(loader: loader))));
    await tester.pumpAndSettle();
    expect(find.text('14 veces'), findsOneWidget);
    expect(find.textContaining('hace 2 h'), findsOneWidget);
    expect(find.textContaining('ayer'), findsOneWidget);
    await tester.tap(find.text('No se pudo guardar la venta'));
    await tester.pumpAndSettle();
    expect(find.text('#0 SalesRepository.sell'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
