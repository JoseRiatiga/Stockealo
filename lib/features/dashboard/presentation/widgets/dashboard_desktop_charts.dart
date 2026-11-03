import 'package:flutter/material.dart';
import '../../../../core/theme/app_tokens.dart';
import 'spline_area_chart.dart';
import 'segmented_progress_card.dart';

/// Gráficas del panel en pantallas anchas (tendencia de ventas y movimientos).
class DashboardDesktopCharts extends StatelessWidget {
  /// Resultado de DashboardRepository.getDashboardSummary
  final Map<String, dynamic> summary;

  /// 'today' | 'week' | 'month' | 'all'
  final String period;

  const DashboardDesktopCharts({super.key, required this.summary, required this.period});

  @override
  Widget build(BuildContext context) {
    final List<dynamic> timelineSales = summary['periodTimelineSales'] ?? summary['weeklySales'] ?? [];
    final List<dynamic> categorySales = summary['categorySales'] ?? [];

    String timelineTitle = 'Ventas de la Semana (7 días)';
    if (period == 'today') {
      timelineTitle = 'Ventas de Hoy por Horario';
    } else if (period == 'month') {
      timelineTitle = 'Ventas del Mes por Semanas';
    } else if (period == 'all') {
      timelineTitle = 'Ventas Históricas por Meses';
    }

    final splineData = timelineSales.map((item) {
      return {
        'label': item['day'] as String,
        'value': (item['total'] as num).toDouble(),
      };
    }).toList();

    final categoryItems = categorySales.take(5).map((cat) {
      final colors = chartSeries(context.colors);
      final idx = categorySales.indexOf(cat) % colors.length;
      final pct = (cat['percentage'] as num?)?.toDouble() ?? 0.0;
      return SegmentedBarItem(
        label: cat['name'] as String,
        valueText: '${pct.toStringAsFixed(1)}%',
        percentage: pct / 100.0,
        color: colors[idx],
      );
    }).toList();

    // Las dos tarjetas siempre con la misma altura, haya una categoría o cinco
    return IntrinsicHeight(
      child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 6,
          child: SplineAreaChart(
            title: timelineTitle,
            subtitle: 'Cómo se reparten tus ventas en el tiempo',
            data: splineData,
            height: 190,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          flex: 4,
          child: SegmentedProgressCard(
            title: 'Ventas por categoría',
            subtitle: 'Qué categorías venden más',
            items: categoryItems.isNotEmpty
                ? categoryItems
                : [
                    SegmentedBarItem(
                      label: 'General',
                      valueText: '100%',
                      percentage: 1.0,
                      color: context.colors.accent,
                    )
                  ],
          ),
        ),
      ],
      ),
    );
  }
}
