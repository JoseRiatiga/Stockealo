import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockealo/core/theme/app_theme.dart';
import 'package:stockealo/features/auth/presentation/widgets/forgot_password_dialog.dart';
import 'package:stockealo/features/auth/presentation/widgets/stockealo_splash_screen.dart';

Future<void> _pump(WidgetTester tester, Widget home, {GlobalKey? key, Brightness brightness = Brightness.light}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
  // El límite va por fuera de MaterialApp para que la imagen incluya los diálogos
  await tester.pumpWidget(RepaintBoundary(
    key: key,
    child: MaterialApp(theme: AppTheme.build(brightness), home: home),
  ));
  await _frames(tester);
}

/// Stocky se anima sin parar: se avanza por cuadros en vez de esperar a que termine
Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
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

  for (final brightness in Brightness.values) {
    testWidgets('pantalla de carga (${brightness.name})', (tester) async {
      final key = GlobalKey();
      await _pump(tester, const StockealoSplashScreen(statusMessage: 'Cargando tu negocio...'), key: key, brightness: brightness);
      expect(find.text('Cargando tu negocio...'), findsOneWidget);
      await _snapshot(tester, key, 'splash_${brightness.name}');
    });
  }

  testWidgets('recuperar contraseña: el primer paso valida el correo', (tester) async {
    final key = GlobalKey();
    await _pump(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => ForgotPasswordDialog.show(context, initialEmail: ''),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
      key: key,
    );
    await tester.tap(find.text('abrir'));
    await _frames(tester);
    expect(find.text('Recuperar contraseña'), findsOneWidget);

    await tester.tap(find.text('Enviar código de seguridad'));
    await _frames(tester);
    expect(find.text('Ingresa tu correo electrónico'), findsOneWidget);
    await _snapshot(tester, key, 'forgot_step1');
  });
}
