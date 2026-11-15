import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockealo/core/theme/app_theme.dart';
import 'package:stockealo/features/pro/presentation/widgets/plan_finder.dart';

/// 0.15.0, punto 9: elegir el plan por lo que se necesita
void main() {
  test('sugiere Pro o Pro Servicios según lo que se marca', () {
    expect(ProNeed.suggest({}), isNull);
    expect(ProNeed.suggest({ProNeed.store, ProNeed.debts}), 'business');
    expect(ProNeed.suggest({ProNeed.store, ProNeed.services}), 'services', reason: 'Pro Servicios trae todo lo de Pro');
    expect(ProNeed.suggest({ProNeed.branches}), 'services');
  });

  for (final width in [360.0, 1200.0]) {
    testWidgets('marca, ve la sugerencia y elige a ${width.toInt()} px', (tester) async {
      tester.view.physicalSize = Size(width, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      String? chosen;
      Set<ProNeed>? withNeeds;
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.build(Brightness.light),
        home: Scaffold(
          body: SingleChildScrollView(
            child: PlanFinder(
              pricingVisible: false,
              onChoose: (kind, needs) {
                chosen = kind;
                withNeeds = needs;
              },
            ),
          ),
        ),
      ));
      expect(find.text('Marca lo que necesitas y te decimos qué plan te sirve.'), findsOneWidget);
      await tester.tap(find.text(ProNeed.store.label));
      await tester.pump();
      expect(find.text('Pro'), findsOneWidget);
      await tester.tap(find.text(ProNeed.services.label));
      await tester.pump();
      expect(find.text('Pro Servicios'), findsOneWidget);
      await tester.tap(find.text('Preguntar por Pro Servicios'));
      expect(chosen, 'services');
      expect(withNeeds, {ProNeed.store, ProNeed.services});
      expect(tester.takeException(), isNull);
    });
  }
}
