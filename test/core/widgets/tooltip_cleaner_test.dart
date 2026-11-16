import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockealo/core/theme/app_theme.dart';
import 'package:stockealo/core/widgets/tooltip_cleaner.dart';

void main() {
  testWidgets('la ayuda del mouse se cierra al abrir una ventana (0.16.3)', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      navigatorObservers: [TooltipCleaner()],
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: IconButton(
              tooltip: 'Abrir avisos',
              icon: const Icon(Icons.notifications_outlined),
              onPressed: () => showDialog<void>(context: context, builder: (_) => const Dialog(child: Text('Avisos'))),
            ),
          ),
        ),
      ),
    ));
    // El mouse se posa encima y sale la ayuda
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.byType(IconButton)));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(find.text('Abrir avisos'), findsOneWidget);

    // Se abre la ventana con el mouse todavía encima: la ayuda se va
    await tester.tap(find.byType(IconButton));
    await tester.pumpAndSettle();
    expect(find.text('Avisos'), findsOneWidget);
    expect(find.text('Abrir avisos'), findsNothing);
  });
}
