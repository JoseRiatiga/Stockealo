import 'package:flutter/material.dart';
import '../../../../core/utils/currency_formatter.dart';
import 'radial_gauge_card.dart';
import 'segmented_progress_card.dart';

/// Tarjetas de métricas del panel: ventas, ganancia, inventario y cartera.
class DashboardMetricsGrid extends StatelessWidget {
  /// Resultado de DashboardRepository.getDashboardSummary
  final Map<String, dynamic> summary;

  /// 'today' | 'week' | 'month' | 'all'
  final String period;

  /// Mostrar la ganancia (solo dueño y admin)
  final bool showProfit;
  final VoidCallback onInventoryTap;

  const DashboardMetricsGrid({
    super.key,
    required this.summary,
    required this.period,
    required this.showProfit,
    required this.onInventoryTap,
  });

  @override
  Widget build(BuildContext context) {
    final double periodTotal = summary['periodTotal'] ?? summary['todayTotal'] ?? 0.0;
    final double periodProfit = summary['periodProfit'] ?? summary['todayProfit'] ?? 0.0;
    final double profitMargin = summary['profitMargin'] ?? 0.0;
    final double averageTicket = summary['averageTicket'] ?? 0.0;
    final double totalDebt = summary['totalDebt'] ?? 0.0;
    final int periodCount = summary['periodCount'] ?? summary['todayCount'] ?? 0;

    String salesTitle = 'Ventas de Hoy';
    String profitTitle = 'Ganancia de Hoy';
    if (period == 'week') {
      salesTitle = 'Ventas (7 Días)';
      profitTitle = 'Ganancia (7 Días)';
    } else if (period == 'month') {
      salesTitle = 'Ventas del Mes';
      profitTitle = 'Ganancia del Mes';
    } else if (period == 'all') {
      salesTitle = 'Ventas Totales';
      profitTitle = 'Ganancia Total';
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth >= 900;
    final int totalProducts = summary['totalProducts'] ?? 0;
    final int lowStock = summary['lowStock'] ?? 0;
    final int outOfStock = summary['outOfStock'] ?? 0;
    final int alertTotal = lowStock + outOfStock;
    final double? trendPercent = summary['trendPercent'] as double?;

    // Progreso dinámico para medidores radiales
    final salesProgress = trendPercent != null
        ? ((50 + trendPercent / 2) / 100).clamp(0.12, 1.0)
        : (periodTotal > 0 ? 0.75 : 0.08);

    final profitProgress = showProfit
        ? (profitMargin / 100.0).clamp(0.08, 1.0)
        : 0.5;

    final stockHealthProgress = totalProducts > 0
        ? ((totalProducts - alertTotal) / totalProducts).clamp(0.05, 1.0)
        : 1.0;

    final cardVentas = RadialGaugeCard(
      title: salesTitle,
      value: CurrencyFormatter.format(periodTotal),
      subtitle: '$periodCount ${periodCount == 1 ? "venta" : "ventas"} en periodo',
      progress: salesProgress,
      gradientColors: const [Color(0xFF06B6D4), Color(0xFF10B981)],
      icon: Icons.payments_rounded,
    );

    final cardGanancia = RadialGaugeCard(
      title: profitTitle,
      value: showProfit ? CurrencyFormatter.format(periodProfit) : '••••••',
      subtitle: showProfit
          ? (periodTotal > 0 ? 'Margen neto: ${profitMargin.toStringAsFixed(1)}%' : 'Margen neto estimado')
          : 'Restringido para cajeros',
      progress: profitProgress,
      gradientColors: const [Color(0xFFEC4899), Color(0xFF8B5CF6)],
      icon: Icons.trending_up_rounded,
    );

    final cardStock = RadialGaugeCard(
      title: 'Inventario Activo',
      value: '$totalProducts Prod.',
      subtitle: alertTotal > 0 ? '$alertTotal con stock crítico' : 'Existencias 100% al día',
      progress: stockHealthProgress,
      gradientColors: alertTotal > 0
          ? const [Color(0xFFF59E0B), Color(0xFFEF4444)]
          : const [Color(0xFF84CC16), Color(0xFF10B981)],
      icon: Icons.inventory_2_rounded,
      onTap: onInventoryTap,
    );

    final cardCartera = SegmentedProgressCard(
      title: 'CARTERA Y TICKET',
      subtitle: 'Comportamiento comercial',
      items: [
        SegmentedBarItem(
          label: 'Ticket Promedio',
          valueText: CurrencyFormatter.format(averageTicket),
          percentage: averageTicket > 0 ? (averageTicket / (periodTotal > 0 ? periodTotal : 100000)).clamp(0.2, 0.95) : 0.1,
          color: const Color(0xFF06B6D4),
        ),
        SegmentedBarItem(
          label: 'Por Cobrar (Fiados)',
          valueText: CurrencyFormatter.format(totalDebt),
          percentage: totalDebt > 0 ? 0.65 : 0.05,
          color: const Color(0xFFF59E0B),
        ),
      ],
    );

    if (isDesktop) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: cardVentas),
          const SizedBox(width: 14),
          Expanded(child: cardGanancia),
          const SizedBox(width: 14),
          Expanded(child: cardStock),
          const SizedBox(width: 14),
          Expanded(child: cardCartera),
        ],
      );
    }

    return Column(
      children: [
        Row(
          children: [
            Expanded(child: cardVentas),
            const SizedBox(width: 12),
            Expanded(child: cardGanancia),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: cardStock),
            const SizedBox(width: 12),
            Expanded(child: cardCartera),
          ],
        ),
      ],
    );
  }
}
