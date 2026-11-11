import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockealo/core/codes/barcode_check.dart';
import 'package:stockealo/core/codes/code_reader.dart';
import 'package:stockealo/core/theme/app_theme.dart';

/// Leer códigos (bloque 6): la cuenta del último número y el lector con «Usar 8».
/// Con PREVIEW_OUT=<carpeta> guarda imágenes.
void main() {
  group('último número', () {
    test('el ejemplo del diseño: la suma da 52, faltan 8 y termina en 8', () {
      final c = BarcodeCheck.of('7702004003508');
      expect(c.format, 'EAN-13');
      expect(c.sum, 52);
      expect(c.expected, 8);
      expect(c.valid, isTrue);
      expect(c.weights.take(4), [1, 3, 1, 3]);
      expect(c.explanation, contains('Cuadra'));
    });

    test('si no cuadra dice cuál debería ser y lo corrige', () {
      final c = BarcodeCheck.of('7702004003507');
      expect(c.valid, isFalse);
      expect(c.fixed, '7702004003508');
      expect(c.explanation, contains('debería ser 8'));
    });

    test('EAN-8 y UPC-A también se revisan', () {
      expect(BarcodeCheck.of('96385074').valid, isTrue);
      expect(BarcodeCheck.of('036000291452').valid, isTrue);
      expect(BarcodeCheck.of('036000291453').fixed, '036000291452');
    });

    test('los códigos propios se aceptan tal cual', () {
      final c = BarcodeCheck.of('STK-12345');
      expect(c.checked, isFalse);
      expect(c.valid, isTrue);
      expect(c.format, 'Código propio');
    });
  });

  Future<void> loadFonts() async {
    for (final family in ['Inter', 'monospace']) {
      final loader = FontLoader(family);
      for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
        loader.addFont(rootBundle.load('assets/fonts/inter/Inter-$w.ttf'));
      }
      await loader.load();
    }
  }

  for (final (size, label) in [(const Size(1100, 760), 'computador'), (const Size(390, 1300), 'celular')]) {
    testWidgets('el lector con un código que no cuadra ofrece «Usar 8» ($label)', (tester) async {
      await tester.runAsync(loadFonts);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      String? result;
      final key = GlobalKey();
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.build(Brightness.light),
        // Se captura todo, también la ventana que se abre encima
        builder: (context, child) => RepaintBoundary(key: key, child: child),
        home: (
          Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () async => result = await CodeReader.pick(
                    context,
                    caption: 'Nuevo producto',
                    initial: '7702004003507',
                    ownerOf: (code) async => code == '7702004003508' ? null : null,
                  ),
                  child: const Text('Abrir'),
                ),
              ),
            ),
          )
        ),
      ));
      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('No cuadra'), findsOneWidget);
      expect(find.text('Usar 8'), findsOneWidget);
      // Con el código mal no se puede usar
      final use = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Usar este código'));
      expect(use.onPressed, isNull);

      final out = Platform.environment['PREVIEW_OUT'];
      Future<void> save(String name) async {
        if (out == null) return;
        await tester.runAsync(() async {
          final image = await (key.currentContext!.findRenderObject()! as RenderRepaintBoundary).toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          File('$out/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
        });
      }

      await save('codigo_mal_$label');
      await tester.tap(find.text('Usar 8'));
      await tester.pumpAndSettle();
      expect(find.text('Válido'), findsOneWidget);
      expect(find.text('Ningún otro producto tiene este código.'), findsOneWidget);
      await save('codigo_bien_$label');
      await tester.tap(find.text('Usar este código'));
      await tester.pumpAndSettle();
      expect(result, '7702004003508');
    });
  }
}
