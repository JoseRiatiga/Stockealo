import '../../../../core/theme/app_tokens.dart';
import 'package:flutter/material.dart';
import '../../../../core/utils/currency_formatter.dart';

/// Ranking de los productos más vendidos del periodo.
class TopProductsSection extends StatelessWidget {
  /// Resultado de DashboardRepository.getDashboardSummary
  final Map<String, dynamic> summary;

  const TopProductsSection({super.key, required this.summary});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final List<dynamic> topProducts = summary['topProducts'] ?? [];

    if (topProducts.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: context.colors.line),
        ),
        child: Center(
          child: Text(
            'Aún no hay ventas registradas para generar el Top de productos.',
            style: TextStyle(fontSize: 12, color: context.colors.inkMuted),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: context.colors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Top 5 Productos Más Vendidos',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: context.colors.ink,
                ),
              ),
              Text(
                'Ventas & Ingresos',
                style: TextStyle(fontSize: 11, color: context.colors.inkMuted),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...topProducts.asMap().entries.map((entry) {
            final idx = entry.key;
            final item = entry.value;
            final share = (item['share'] as num?)?.toDouble() ?? 0.0;
            final revenue = (item['revenue'] as num?)?.toDouble() ?? 0.0;

            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _rankingBadge(idx, isDark),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          item['name'] as String,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: context.colors.ink,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${item['qty']} un.',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: context.colors.accent),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '(${CurrencyFormatter.format(revenue)})',
                        style: TextStyle(fontSize: 11, color: context.colors.inkMuted),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: share.clamp(0.05, 1.0),
                      minHeight: 5,
                      backgroundColor: context.colors.surfaceMuted,
                      valueColor: AlwaysStoppedAnimation<Color>(context.colors.accent),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _rankingBadge(int rank, bool isDark) {
    Color badgeColor;
    Widget child;

    switch (rank) {
      case 0: // 1er Lugar - Oro
        badgeColor = AppPalette.warning;
        child = const Icon(Icons.emoji_events_rounded, size: 13, color: Colors.white);
        break;
      case 1: // 2do Lugar - Plata
        badgeColor = AppPalette.inkMuted;
        child = const Icon(Icons.military_tech_rounded, size: 14, color: Colors.white);
        break;
      case 2: // 3er Lugar - Bronce
        badgeColor = AppPalette.warning;
        child = const Icon(Icons.military_tech_outlined, size: 14, color: Colors.white);
        break;
      default: // 4to y 5to
        badgeColor = AppPalette.line;
        const textColor = AppPalette.inkMuted;
        child = Text(
          '#${rank + 1}',
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: textColor,
          ),
        );
    }

    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: badgeColor,
        shape: BoxShape.circle,
        boxShadow: rank < 3
            ? [
                BoxShadow(
                  color: badgeColor.withOpacity(0.35),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                )
              ]
            : null,
      ),
      alignment: Alignment.center,
      child: child,
    );
  }
}
