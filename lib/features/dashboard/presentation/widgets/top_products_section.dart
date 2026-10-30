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
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
        ),
        child: const Center(
          child: Text(
            'Aún no hay ventas registradas para generar el Top de productos.',
            style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
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
                  color: isDark ? const Color(0xFFF8FAFC) : const Color(0xFF1E293B),
                ),
              ),
              Text(
                'Ventas & Ingresos',
                style: TextStyle(fontSize: 11, color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
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
                            color: isDark ? const Color(0xFFF8FAFC) : const Color(0xFF1E293B),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${item['qty']} un.',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF059669)),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '(${CurrencyFormatter.format(revenue)})',
                        style: TextStyle(fontSize: 11, color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: share.clamp(0.05, 1.0),
                      minHeight: 5,
                      backgroundColor: isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9),
                      valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF059669)),
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
        badgeColor = const Color(0xFFF59E0B);
        child = const Icon(Icons.emoji_events_rounded, size: 13, color: Colors.white);
        break;
      case 1: // 2do Lugar - Plata
        badgeColor = const Color(0xFF94A3B8);
        child = const Icon(Icons.military_tech_rounded, size: 14, color: Colors.white);
        break;
      case 2: // 3er Lugar - Bronce
        badgeColor = const Color(0xFFD97706);
        child = const Icon(Icons.military_tech_outlined, size: 14, color: Colors.white);
        break;
      default: // 4to y 5to
        badgeColor = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
        final textColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
        child = Text(
          '#${rank + 1}',
          style: TextStyle(
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
