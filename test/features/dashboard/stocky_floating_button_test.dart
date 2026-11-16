import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockealo/core/theme/app_theme.dart';
import 'package:stockealo/features/dashboard/presentation/widgets/stocky_floating_button.dart';

void main() {
  Future<void> pump(WidgetTester tester, {required bool compact}) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(
        body: Align(alignment: Alignment.bottomRight, child: StockyFloatingButton(compact: compact)),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 600));
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 5));
  }

  testWidgets('en el celular es solo el círculo de Stocky, sin texto (0.16.3)', (tester) async {
    await pump(tester, compact: true);
    expect(find.text('Pregúntale a Stocky'), findsNothing);
    expect(find.bySemanticsLabel('Pregúntale a Stocky'), findsOneWidget);
    expect(tester.getSize(find.byType(StockyFloatingButton)).width, lessThan(60));
    await unmount(tester);
  });

  testWidgets('en computador sigue la pastilla con el texto', (tester) async {
    await pump(tester, compact: false);
    expect(find.text('Pregúntale a Stocky'), findsOneWidget);
    await unmount(tester);
  });
}
