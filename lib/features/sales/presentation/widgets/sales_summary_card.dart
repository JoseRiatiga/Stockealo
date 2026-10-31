import 'package:flutter/material.dart';
import '../../../../core/design/app_card.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../models/sale.dart';

/// Resumen de las ventas de hoy: total, ganancia y desglose por método de pago.
class SalesSummaryCard extends StatelessWidget {
  /// Resultado de SalesRepository.getTodaySummary
  final Map<String, dynamic> summary;
  final List<Sale> sales;

  /// Mostrar la ganancia (solo dueño y admin)
  final bool showProfit;

  const SalesSummaryCard({super.key, required this.summary, required this.sales, required this.showProfit});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final double total = (summary['totalAmount'] as num?)?.toDouble() ?? 0;
    final double profit = (summary['netProfit'] as num?)?.toDouble() ?? 0;
    final int count = (summary['count'] as int?) ?? 0;
    final double efectivo = (summary['byEfectivo'] as num?)?.toDouble() ?? 0;
    final double transf = (summary['byTransferencia'] as num?)?.toDouble() ?? 0;
    final double fiado = (summary['byFiado'] as num?)?.toDouble() ?? 0;

    Widget method(String label, double value, Color color) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 12, color: c.inkMuted)),
              const SizedBox(height: 2),
              Text(
                CurrencyFormatter.format(value),
                style: AppText.amount(context, size: 14, weight: FontWeight.w600, color: value > 0 ? color : c.inkFaint),
              ),
            ],
          ),
        );

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Ventas de hoy', style: TextStyle(fontSize: 13, color: c.inkMuted)),
                    Text(CurrencyFormatter.format(total), style: AppText.amount(context, size: 28)),
                    Text(count == 1 ? '1 venta' : '$count ventas', style: TextStyle(fontSize: 12, color: c.inkMuted)),
                  ],
                ),
              ),
              if (showProfit)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('Ganancia', style: TextStyle(fontSize: 13, color: c.inkMuted)),
                    Text(
                      CurrencyFormatter.format(profit),
                      style: AppText.amount(context, size: 18, color: profit < 0 ? c.danger : c.success),
                    ),
                  ],
                ),
            ],
          ),
          Divider(height: AppSpace.xl, color: c.line),
          Row(
            children: [
              method('Efectivo', efectivo, c.ink),
              method('Transferencia', transf, c.ink),
              method('Fiado', fiado, c.warning),
            ],
          ),
        ],
      ),
    );
  }
}
