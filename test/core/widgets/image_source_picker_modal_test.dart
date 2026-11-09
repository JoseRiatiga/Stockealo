import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:stockealo/core/theme/app_theme.dart';
import 'package:stockealo/core/widgets/image_source_picker_modal.dart';

void main() {
  for (final (width, brightness) in [
    (360.0, Brightness.light),
    (360.0, Brightness.dark),
    (1200.0, Brightness.light),
  ]) {
    testWidgets('ventana de imagen con el diseño nuevo a ${width.toInt()} px (${brightness.name})', (tester) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      ImageSource? chosen;
      var removed = false;
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.build(brightness),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => ImageSourcePickerModal.show(
                context,
                title: 'Logo del negocio',
                hasExistingImage: true,
                onSelected: (s) => chosen = s,
                onRemove: () => removed = true,
              ),
              child: const Text('abrir'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      expect(find.text('Logo del negocio'), findsOneWidget);
      expect(find.text('Quitar la imagen actual'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Elegir de la galería'));
      await tester.pumpAndSettle();
      expect(chosen, ImageSource.gallery);
      expect(find.text('Logo del negocio'), findsNothing, reason: 'se cierra al elegir');
      expect(removed, isFalse);
    });
  }
}
