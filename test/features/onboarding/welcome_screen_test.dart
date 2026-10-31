import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockealo/core/theme/app_theme.dart';
import 'package:stockealo/features/onboarding/presentation/welcome_screen.dart';

Future<void> _pump(WidgetTester tester, VoidCallback onDone, {GlobalKey? key}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.build(Brightness.light),
    home: RepaintBoundary(key: key, child: WelcomeScreen(onDone: onDone)),
  ));
  await tester.pump(const Duration(milliseconds: 100));
}

/// Guarda la pantalla como imagen solo si se pasa PREVIEW_OUT (revisión visual)
Future<void> _snapshot(WidgetTester tester, GlobalKey key, String name) async {
  final out = Platform.environment['PREVIEW_OUT'];
  if (out == null) return;
  await tester.runAsync(() async {
    final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    File('$out/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final loader = FontLoader('Inter');
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      loader.addFont(rootBundle.load('assets/fonts/inter/Inter-$w.ttf'));
    }
    await loader.load();
  });

  testWidgets('se recorren los tres pasos y "Empezar" termina', (tester) async {
    var done = false;
    final key = GlobalKey();
    await _pump(tester, () => done = true, key: key);

    expect(find.text('Tu inventario, siempre al día'), findsOneWidget);
    expect(find.text('Saltar'), findsOneWidget);
    await _snapshot(tester, key, 'welcome_1');

    await tester.tap(find.text('Siguiente'));
    await tester.pumpAndSettle();
    expect(find.text('Vende y cobra en segundos'), findsOneWidget);
    await _snapshot(tester, key, 'welcome_2');

    await tester.tap(find.text('Siguiente'));
    // Stocky se anima sin parar: se avanza por cuadros en vez de esperar a que termine
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('Stocky te ayuda'), findsOneWidget);
    expect(find.text('Empezar'), findsOneWidget);
    await _snapshot(tester, key, 'welcome_3');

    await tester.tap(find.text('Empezar'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(done, isTrue);
  });

  testWidgets('"Saltar" termina desde el primer paso', (tester) async {
    var done = false;
    await _pump(tester, () => done = true);
    await tester.tap(find.text('Saltar'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(done, isTrue);
  });
}
