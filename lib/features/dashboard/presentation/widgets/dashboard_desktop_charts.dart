import 'package:flutter/material.dart';
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
      final colors = [
        const Color(0xFF06B6D4),
        const Color(0xFFEC4899),
        const Color(0xFF10B981),
        const Color(0xFFF59E0B),
        const Color(0xFF8B5CF6),
      ];
      final idx = categorySales.indexOf(cat) % colors.length;
      final pct = (cat['percentage'] as num?)?.toDouble() ?? 0.0;
      return SegmentedBarItem(
        label: cat['name'] as String,
        valueText: '${pct.toStringAsFixed(1)}%',
        percentage: pct / 100.0,
        color: colors[idx],
      );
    }).toList();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 6,
          child: SplineAreaChart(
            title: timelineTitle,
            subtitle: 'Curva continua de rendimiento operativo',
            data: splineData,
            height: 190,
            primaryColor: const Color(0xFF06B6D4),
            secondaryColor: const Color(0xFFEC4899),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          flex: 4,
          child: SegmentedProgressCard(
            title: 'PARTICIPACIÓN POR CATEGORÍA',
            subtitle: 'Distribución porcentual en el periodo',
            items: categoryItems.isNotEmpty
                ? categoryItems
                : [
                    const SegmentedBarItem(
                      label: 'General',
                      valueText: '100%',
                      percentage: 1.0,
                      color: Color(0xFF10B981),
                    )
                  ],
          ),
        ),
      ],
    );
  }
}
