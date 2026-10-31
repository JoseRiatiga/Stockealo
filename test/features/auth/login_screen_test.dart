import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockealo/core/design/primary_action_button.dart';
import 'package:stockealo/core/theme/app_theme.dart';
import 'package:stockealo/features/auth/presentation/screens/login_screen.dart';

Future<void> _pump(WidgetTester tester, {GlobalKey? key, Brightness brightness = Brightness.light}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.build(brightness),
    home: RepaintBoundary(key: key, child: LoginScreen(onLoginSuccess: () {})),
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

  testWidgets('inicio de sesión: valida los campos vacíos', (tester) async {
    final key = GlobalKey();
    await _pump(tester, key: key);
    expect(find.text('Hola de nuevo'), findsOneWidget);
    expect(find.text('¿Olvidaste tu contraseña?'), findsOneWidget);
    await _snapshot(tester, key, 'login');

    await tester.tap(find.text('Ingresar'));
    await _frames(tester);
    expect(find.text('Ingresa tu correo'), findsOneWidget);
    expect(find.text('Ingresa tu contraseña'), findsOneWidget);
  });

  testWidgets('crear cuenta: pide aceptar los términos', (tester) async {
    final key = GlobalKey();
    await _pump(tester, key: key);
    await tester.tap(find.text('Crear cuenta'));
    await _frames(tester);
    expect(find.text('Crea tu cuenta'), findsOneWidget);
    expect(find.text('Repite la contraseña'), findsOneWidget);
    await _snapshot(tester, key, 'register');

    await tester.enterText(find.widgetWithText(TextFormField, 'Tu nombre'), 'Ana');
    await tester.enterText(find.widgetWithText(TextFormField, 'Correo'), 'ana@ejemplo.com');
    await tester.enterText(find.widgetWithText(TextFormField, 'Contraseña'), 'secreta1');
    await tester.enterText(find.widgetWithText(TextFormField, 'Repite la contraseña'), 'secreta1');
    final button = find.byType(PrimaryActionButton);
    await tester.ensureVisible(button);
    await tester.tap(button);
    await _frames(tester);
    expect(find.textContaining('acepta los términos'), findsOneWidget);
    await _snapshot(tester, key, 'register_error');
  });

  testWidgets('modo oscuro se dibuja', (tester) async {
    final key = GlobalKey();
    await _pump(tester, key: key, brightness: Brightness.dark);
    await _snapshot(tester, key, 'login_dark');
  });
}
