import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockealo/core/theme/app_theme.dart';
import 'package:stockealo/features/dashboard/presentation/widgets/dashboard_desktop_charts.dart';
import 'package:stockealo/features/dashboard/presentation/widgets/segmented_progress_card.dart';
import 'package:stockealo/features/dashboard/presentation/widgets/spline_area_chart.dart';

Map<String, dynamic> _summary(int categories) => {
      'periodTimelineSales': [
        for (final d in ['6-9h', '10-12h', '13-15h', '16-18h']) {'day': d, 'total': 1000},
      ],
      'categorySales': [
        for (var i = 0; i < categories; i++) {'name': 'Cat $i', 'percentage': 100 / categories},
      ],
    };

void main() {
  for (final dark in [false, true]) {
    for (final categories in [0, 1, 5]) {
      testWidgets('la tarjeta de categorías mide lo mismo que la gráfica ($categories categorías, '
          '${dark ? 'oscuro' : 'claro'})', (tester) async {
        tester.view.physicalSize = const Size(1400, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(MaterialApp(
          theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
          home: Scaffold(
            body: SingleChildScrollView(
              child: DashboardDesktopCharts(summary: _summary(categories), period: 'today'),
            ),
          ),
        ));
        expect(tester.takeException(), isNull);
        final chart = tester.getSize(find.byType(SplineAreaChart));
        final card = tester.getSize(find.byType(SegmentedProgressCard));
        expect(card.height, chart.height);
      });
    }
  }
}
