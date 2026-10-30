import 'package:flutter/material.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../models/sale.dart';

/// Resumen de ventas del periodo: total, ganancia y desglose por método de pago.
class SalesSummaryCard extends StatelessWidget {
  /// Resultado de SalesRepository.getTodaySummary
  final Map<String, dynamic> summary;
  final List<Sale> sales;

  /// Mostrar la ganancia (solo dueño y admin)
  final bool showProfit;

  const SalesSummaryCard({super.key, required this.summary, required this.sales, required this.showProfit});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final total = summary['totalAmount'] ?? 0.0;
    final profit = summary['netProfit'] ?? 0.0;
    final efectivo = summary['byEfectivo'] ?? 0.0;
    final transf = summary['byTransferencia'] ?? 0.0;
    final fiado = summary['byFiado'] ?? 0.0;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF131127) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isDark ? const Color(0xFF26214A) : const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.2 : 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Total e ingresos de hoy
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Ventas de Hoy',
                    style: TextStyle(fontSize: 13, color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    CurrencyFormatter.format(total),
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: isDark ? const Color(0xFFF8FAFC) : const Color(0xFF1E293B),
                    ),
                  ),
                ],
              ),
              if (showProfit)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF064E3B) : const Color(0xFFECFDF5),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: isDark ? const Color(0xFF059669) : const Color(0xFFA7F3D0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'Ganancia Real',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: isDark ? const Color(0xFFA7F3D0) : const Color(0xFF065F46),
                        ),
                      ),
                      Text(
                        CurrencyFormatter.format(profit),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF059669),
                        ),
                      ),
                    ],
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF18152F) : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: isDark ? const Color(0xFF26214A) : const Color(0xFFCBD5E1)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'Ventas Hoy',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: isDark ? const Color(0xFFA78BFA) : const Color(0xFF7C3AED),
                        ),
                      ),
                      Text(
                        '${summary['salesCount'] ?? sales.where((s) {
                          final n = DateTime.now();
                          return s.date.year == n.year && s.date.month == n.month && s.date.day == n.day;
                        }).length} reg.',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: isDark ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          Divider(height: 24, color: isDark ? const Color(0xFF26214A) : const Color(0xFFE2E8F0)),

          // Desglose por Método de Pago
          Row(
            children: [
              _paymentPill(Icons.payments_outlined, 'Efectivo', CurrencyFormatter.format(efectivo), const Color(0xFF059669)),
              const SizedBox(width: 8),
              _paymentPill(Icons.account_balance_outlined, 'Transf.', CurrencyFormatter.format(transf), const Color(0xFF2563EB)),
              const SizedBox(width: 8),
              _paymentPill(Icons.assignment_outlined, 'Fiado', CurrencyFormatter.format(fiado), const Color(0xFFD97706)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _paymentPill(IconData icon, String title, String amount, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 11, color: color),
                const SizedBox(width: 3),
                Text(
                  title,
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              amount,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color),
            ),
          ],
        ),
      ),
    );
  }
}
