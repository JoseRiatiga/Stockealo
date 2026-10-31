import 'package:flutter/material.dart';
import '../../../../core/design/app_card.dart';
import '../../../../core/design/segmented_gauge.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/utils/currency_formatter.dart';

/// Cifras del panel: ventas, ganancia, inventario y fiados, cada una con un medidor
/// que la compara con una referencia (día normal, margen, stock sano, cobrado del mes).
/// En el celular el medidor va pequeño al lado del número; en pantallas anchas, grande
/// con el número adentro.
class DashboardMetricsGrid extends StatelessWidget {
  /// Resultado de DashboardRepository.getDashboardSummary
  final Map<String, dynamic> summary;

  /// 'today' | 'week' | 'month' | 'all'
  final String period;

  /// Mostrar la ganancia (solo dueño y admin)
  final bool showProfit;
  final VoidCallback onInventoryTap;

  /// Abre Clientes (fiados); null si no aplica
  final VoidCallback? onDebtsTap;

  const DashboardMetricsGrid({
    super.key,
    required this.summary,
    required this.period,
    required this.showProfit,
    required this.onInventoryTap,
    this.onDebtsTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final double periodTotal = summary['periodTotal'] ?? summary['todayTotal'] ?? 0.0;
    final double periodProfit = summary['periodProfit'] ?? summary['todayProfit'] ?? 0.0;
    final double profitMargin = summary['profitMargin'] ?? 0.0;
    final double averageTicket = summary['averageTicket'] ?? 0.0;
    final double totalDebt = summary['totalDebt'] ?? 0.0;
    final int periodCount = summary['periodCount'] ?? summary['todayCount'] ?? 0;
    final int totalProducts = summary['totalProducts'] ?? 0;
    final int lowStock = summary['lowStock'] ?? 0;
    final int outOfStock = summary['outOfStock'] ?? 0;
    final int alertTotal = lowStock + outOfStock;

    final periodName = switch (period) {
      'week' => '7 días',
      'month' => 'este mes',
      'all' => 'todo el tiempo',
      _ => 'hoy',
    };

    final double debtCollected = (summary['debtCollectedMonth'] as num?)?.toDouble() ?? 0.0;
    final double? salesReference = (summary['salesReference'] as num?)?.toDouble();
    final String? salesReferenceLabel = summary['salesReferenceLabel'] as String?;

    final salesShare = salesReference != null && salesReference > 0 ? periodTotal / salesReference : null;
    final salesCaption = periodCount == 1 ? '1 venta' : '$periodCount ventas';

    // El arco lleno es un margen de 50 % o más
    final profitColor = profitMargin >= 20 ? c.success : (profitMargin > 0 ? c.warning : c.danger);

    final collectBase = debtCollected + totalDebt;

    List<_Metric> metrics() => [
          _Metric(
            label: 'Ventas · $periodName',
            value: CurrencyFormatter.format(periodTotal),
            caption: salesShare == null ? salesCaption : '${(salesShare * 100).round()}% $salesReferenceLabel',
            semantics: salesCaption,
            icon: Icons.payments_outlined,
            progress: salesShare,
            gaugeColor: c.accent,
          ),
          _Metric(
            label: 'Ganancia · $periodName',
            value: showProfit ? CurrencyFormatter.format(periodProfit) : '••••',
            valueColor: !showProfit ? c.inkMuted : (periodProfit < 0 ? c.danger : c.success),
            caption: showProfit ? 'Margen ${profitMargin.toStringAsFixed(1)}%' : 'Solo dueño y administrador',
            icon: Icons.trending_up_rounded,
            // El cajero no ve la ganancia: tampoco el medidor que la delata
            progress: showProfit && periodTotal > 0 ? profitMargin / 50 : null,
            gaugeColor: profitColor,
          ),
          _Metric(
            label: 'Productos',
            value: '$totalProducts',
            caption: alertTotal > 0 ? '$alertTotal por reponer' : 'Stock al día',
            captionColor: alertTotal > 0 ? c.warning : null,
            icon: Icons.inventory_2_outlined,
            onTap: onInventoryTap,
            progress: totalProducts > 0 ? (totalProducts - alertTotal) / totalProducts : null,
            gaugeColor: alertTotal > 0 ? c.warning : c.success,
          ),
          _Metric(
            label: 'Fiados por cobrar',
            value: CurrencyFormatter.format(totalDebt),
            valueColor: totalDebt > 0 ? c.warning : null,
            caption: collectBase > 0
                ? 'Cobrado ${(debtCollected / collectBase * 100).round()}% este mes'
                : 'Ticket promedio ${CurrencyFormatter.format(averageTicket)}',
            icon: Icons.receipt_long_outlined,
            onTap: onDebtsTap,
            progress: collectBase > 0 ? debtCollected / collectBase : null,
            gaugeColor: totalDebt > 0 ? c.warning : c.success,
          ),
        ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        final columns = wide ? 4 : 2;
        return GridView.count(
          crossAxisCount: columns,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          // Sin esto la cuadrícula suma el alto de la barra de pestañas como relleno
          padding: EdgeInsets.zero,
          crossAxisSpacing: AppSpace.md,
          mainAxisSpacing: AppSpace.md,
          // Alto fijo que aguanta letra grande sin desbordarse
          childAspectRatio: wide ? 1.25 : 1.45,
          children: [for (final m in metrics()) _MetricCard(metric: m, large: wide)],
        );
      },
    );
  }
}

class _Metric {
  final String label;
  final String value;
  final String caption;
  final IconData icon;
  final Color? valueColor;
  final Color? captionColor;
  final VoidCallback? onTap;

  /// Avance del medidor (0 a 1); null si no hay con qué comparar y no se dibuja
  final double? progress;
  final Color gaugeColor;

  /// Lo que dice el lector de pantalla además de la tarjeta
  final String? semantics;

  const _Metric({
    required this.label,
    required this.value,
    required this.caption,
    required this.icon,
    required this.gaugeColor,
    this.valueColor,
    this.captionColor,
    this.onTap,
    this.progress,
    this.semantics,
  });
}

class _MetricCard extends StatelessWidget {
  final _Metric metric;

  /// Pantallas anchas: medidor grande con el número adentro
  final bool large;

  const _MetricCard({required this.metric, required this.large});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final m = metric;
    // En oscuro el verde de marca no se lee como texto pequeño: se aclara como en el medidor
    final dark = Theme.of(context).brightness == Brightness.dark;
    final captionTint = dark ? Color.lerp(m.gaugeColor, Colors.white, 0.3)! : m.gaugeColor;
    final header = Row(
      children: [
        Expanded(
          child: Text(m.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: c.inkMuted)),
        ),
        Icon(m.icon, size: 18, color: c.inkFaint),
      ],
    );
    final caption = Text(
      m.caption,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: large ? TextAlign.center : TextAlign.start,
      style: TextStyle(fontSize: 12, color: m.captionColor ?? (m.progress != null ? captionTint : c.inkMuted)),
    );

    Widget value(double size) => FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(m.value, style: AppText.amount(context, size: size, color: m.valueColor)),
        );

    final Widget body;
    if (large) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          Expanded(
            child: Center(
              child: m.progress == null
                  ? value(24)
                  : SegmentedGauge(
                      progress: m.progress!,
                      color: m.gaugeColor,
                      size: 118,
                      segments: 26,
                      child: SizedBox(width: 74, child: value(20)),
                    ),
            ),
          ),
          caption,
        ],
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header,
          const Spacer(),
          Row(
            children: [
              Expanded(child: Align(alignment: Alignment.centerLeft, child: value(22))),
              if (m.progress != null) ...[
                const SizedBox(width: AppSpace.xs),
                SegmentedGauge(progress: m.progress!, color: m.gaugeColor, size: 44, segments: 15),
              ],
            ],
          ),
          const SizedBox(height: 2),
          // A todo el ancho: al lado del medidor no cabía "70% de tu día normal"
          caption,
        ],
      );
    }

    return Semantics(
      label: m.semantics,
      child: AppCard(onTap: m.onTap, child: body),
    );
  }
}
