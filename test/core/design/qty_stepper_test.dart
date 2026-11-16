import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockealo/core/design/qty_stepper.dart';
import 'package:stockealo/core/design/status_pill.dart';
import 'package:stockealo/core/theme/app_theme.dart';
import 'package:stockealo/core/theme/app_tokens.dart';

void main() {
  Widget host(Widget child) => MaterialApp(theme: AppTheme.lightTheme, home: Scaffold(body: Center(child: child)));

  testWidgets('el contador suma, resta y apaga el «−» en cero (0.16.3)', (tester) async {
    var n = 0;
    await tester.pumpWidget(StatefulBuilder(
      builder: (context, set) => host(QtyStepper(
        value: n,
        onRemove: n == 0 ? null : () => set(() => n--),
        onAdd: () => set(() => n++),
      )),
    ));
    expect(tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.remove_outlined)).onPressed, isNull);
    await tester.tap(find.byTooltip('Agregar uno'));
    await tester.pump();
    expect(find.text('1'), findsOneWidget);
    await tester.tap(find.byTooltip('Quitar uno'));
    await tester.pump();
    expect(find.text('0'), findsOneWidget);
  });

  testWidgets('con removeDeletes el «−» es la caneca', (tester) async {
    await tester.pumpWidget(host(QtyStepper(value: 1, removeDeletes: true, onRemove: () {}, onAdd: () {})));
    expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    expect(find.byTooltip('Quitar'), findsOneWidget);
  });

  testWidgets('«Quedan 3»: pastilla gris con el puntito de aviso', (tester) async {
    await tester.pumpWidget(host(const StatusPill('Quedan 3', dotTone: AppTone.warning, compact: true)));
    final context = tester.element(find.text('Quedan 3'));
    final boxes = tester.widgetList<Container>(find.descendant(of: find.byType(StatusPill), matching: find.byType(Container)));
    final colors = boxes.map((b) => (b.decoration as BoxDecoration?)?.color).toList();
    expect(colors, contains(context.colors.surfaceMuted));
    expect(colors, contains(context.colors.warning));
  });
}
