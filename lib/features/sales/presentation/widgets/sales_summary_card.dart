import 'package:flutter/material.dart';

import '../../../../core/theme/app_tokens.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../models/payment_method.dart';
import '../../models/sale.dart';

/// Resumen de las ventas de hoy: total, ganancia y lo que entró por cada forma de
/// pago (las anuladas no suman).
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
    final byMethod = (summary['byMethod'] as Map<String, double>?) ?? const {};
    // Siempre efectivo, transferencia y fiado; los demás solo si hubo
    const always = [PaymentMethod.cash, PaymentMethod.transfer, PaymentMethod.credit];
    final methods = [
      for (final m in PaymentMethod.forSale)
        if (m != PaymentMethod.mixed && (always.contains(m) || (byMethod[m] ?? 0) > 0)) m,
    ];

    return Container(
      padding: const EdgeInsets.all(AppSpace.lg + 2),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: c.line),
      ),
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
                    Text('Ventas de hoy', style: AppText.body(context, weight: FontWeight.w600, color: c.inkMuted)),
                    Text(CurrencyFormatter.format(total), style: AppText.display(context)),
                    Text(count == 1 ? '1 venta' : '$count ventas', style: AppText.small(context)),
                  ],
                ),
              ),
              if (showProfit)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('Ganancia', style: AppText.small(context)),
                    Text(
                      CurrencyFormatter.format(profit),
                      style: AppText.amount(context, size: AppText.sizeHeading, color: profit < 0 ? c.danger : c.success),
                    ),
                  ],
                ),
            ],
          ),
          Divider(height: AppSpace.xl, color: c.line),
          Wrap(
            spacing: AppSpace.xl,
            runSpacing: AppSpace.md,
            children: [
              for (final m in methods)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(PaymentMethod.label(m), style: AppText.caption(context)),
                    const SizedBox(height: 2),
                    Text(
                      CurrencyFormatter.format(byMethod[m] ?? 0),
                      style: AppText.amount(
                        context,
                        size: AppText.sizeBody,
                        weight: FontWeight.w600,
                        color: (byMethod[m] ?? 0) <= 0 ? c.inkFaint : (m == PaymentMethod.credit ? c.warning : c.ink),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}
