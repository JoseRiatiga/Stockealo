import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockealo/core/design/content_width.dart';

/// 0.16.6 (hallazgo 61): en el computador la rueda del mouse hace scroll también
/// con el puntero en los costados, no solo sobre la columna del centro.
void main() {
  testWidgets('ContentListView hace scroll con el puntero en el costado', (tester) async {
    tester.view.physicalSize = const Size(1400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ContentListView(
          controller: controller,
          padding: const EdgeInsets.all(16),
          children: [for (var i = 0; i < 60; i++) SizedBox(height: 60, child: Text('Fila $i'))],
        ),
      ),
    ));

    // El contenido sigue centrado en 720 px
    final row = tester.getRect(find.text('Fila 0'));
    expect(row.left, closeTo((1400 - ContentWidth.max) / 2 + 16, 1));

    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(pointer.hover(const Offset(20, 400)));
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 300)));
    await tester.pumpAndSettle();
    expect(controller.offset, greaterThan(0), reason: 'la rueda en el costado mueve la lista');
  });
}
