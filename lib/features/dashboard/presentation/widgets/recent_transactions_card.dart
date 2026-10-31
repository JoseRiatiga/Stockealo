import '../../../../core/theme/app_tokens.dart';
import 'package:flutter/material.dart';
import '../../../../core/utils/currency_formatter.dart';

class TransactionItem {
  final String id;
  final String title;
  final String subtitle;
  final double amount;
  final String paymentMethod;
  final DateTime date;

  const TransactionItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.amount,
    required this.paymentMethod,
    required this.date,
  });
}

class RecentTransactionsCard extends StatelessWidget {
  final List<TransactionItem> transactions;
  final VoidCallback onSeeAll;

  const RecentTransactionsCard({
    super.key,
    required this.transactions,
    required this.onSeeAll,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isDark ? const Color(0xFF262046) : context.colors.line,
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.2 : 0.03),
            blurRadius: 18,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Últimas ventas',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                      color: context.colors.inkMuted,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: onSeeAll,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Ver todas',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                          color: isDark ? const Color(0xFF34D399) : context.colors.accent,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.arrow_forward_rounded,
                        size: 14,
                        color: isDark ? const Color(0xFF34D399) : context.colors.accent,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          if (transactions.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  'No hay transacciones registradas en este periodo.',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: context.colors.inkFaint,
                  ),
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              itemCount: transactions.take(5).length,
              separatorBuilder: (_, __) => Divider(
                height: 16,
                color: context.colors.surfaceMuted,
              ),
              itemBuilder: (context, index) {
                final tx = transactions[index];
                final badgeData = _getPaymentBadge(tx.paymentMethod, isDark);

                return Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: badgeData.color.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(badgeData.icon, size: 18, color: badgeData.color),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tx.title,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: context.colors.ink,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            tx.subtitle,
                            style: TextStyle(
                              fontSize: 11,
                              color: context.colors.inkFaint,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          CurrencyFormatter.format(tx.amount),
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                            color: context.colors.ink,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: badgeData.color.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            badgeData.label,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: badgeData.color,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }

  _PaymentBadgeData _getPaymentBadge(String method, bool isDark) {
    final m = method.toLowerCase();
    if (m.contains('nequi') || m.contains('davi') || m.contains('transf')) {
      return const _PaymentBadgeData('Transferencia', Color(0xFF38BDF8), Icons.send_rounded);
    } else if (m.contains('fiad') || m.contains('credit') || m.contains('deuda')) {
      return const _PaymentBadgeData('Fiado', AppPalette.warning, Icons.assignment_late_outlined);
    } else if (m.contains('tarjet') || m.contains('card')) {
      return const _PaymentBadgeData('Tarjeta', Color(0xFFA855F7), Icons.credit_card_rounded);
    }
    return const _PaymentBadgeData('Efectivo', AppPalette.brand, Icons.payments_outlined);
  }
}

class _PaymentBadgeData {
  final String label;
  final Color color;
  final IconData icon;

  const _PaymentBadgeData(this.label, this.color, this.icon);
}
