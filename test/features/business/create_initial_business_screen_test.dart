import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockealo/core/theme/app_theme.dart';
import 'package:stockealo/features/business/presentation/screens/create_initial_business_screen.dart';

Future<void> _pump(WidgetTester tester, {GlobalKey? key, Brightness brightness = Brightness.light, VoidCallback? onLogout}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.build(brightness),
    home: RepaintBoundary(
      key: key,
      child: CreateInitialBusinessScreen(
        userId: 'u1',
        userEmail: 'ana@ejemplo.com',
        userName: 'Ana María López',
        onBusinessCreated: () {},
        onLogout: onLogout,
      ),
    ),
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

  testWidgets('saluda por el nombre y la vista previa sigue al nombre escrito', (tester) async {
    final key = GlobalKey();
    await _pump(tester, key: key);

    expect(find.text('Hola, Ana'), findsOneWidget);
    expect(find.text('Crea tu negocio'), findsOneWidget);
    expect(find.text('Tu negocio'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'Miscelánea Central');
    await tester.pump();
    expect(find.text('Miscelánea Central'), findsWidgets);
    await _snapshot(tester, key, 'initial_create');
  });

  testWidgets('sin nombre no crea y muestra el aviso', (tester) async {
    await _pump(tester);
    await tester.ensureVisible(find.text('Crear y empezar'));
    await tester.tap(find.text('Crear y empezar'));
    await tester.pump();
    expect(find.text('Escribe el nombre de tu negocio'), findsOneWidget);
  });

  testWidgets('"Me invitaron" muestra la opción de unirse', (tester) async {
    final key = GlobalKey();
    var loggedOut = false;
    await _pump(tester, key: key, onLogout: () => loggedOut = true);

    await tester.tap(find.text('Me invitaron'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Únete a un equipo'), findsOneWidget);
    expect(find.text('Abrir la cámara'), findsOneWidget);
    expect(find.text('Unirme al equipo'), findsOneWidget);
    await _snapshot(tester, key, 'initial_join');

    await tester.tap(find.text('Cerrar sesión'));
    expect(loggedOut, isTrue);
  });

  testWidgets('modo oscuro se dibuja', (tester) async {
    final key = GlobalKey();
    await _pump(tester, key: key, brightness: Brightness.dark);
    await _snapshot(tester, key, 'initial_create_dark');
  });
}
