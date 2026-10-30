import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../products/presentation/widgets/product_image_view.dart';
import '../../models/sale.dart';
import 'digital_ticket_modal.dart';

/// Tarjeta de una venta en el historial: método de pago, producto, cliente,
/// métricas y acciones (comprobante y, si se permite, anular).
class SaleCard extends StatelessWidget {
  final Sale sale;

  /// Mostrar la ganancia (solo dueño y admin)
  final bool showProfit;

  /// Anular la venta; null oculta el botón (cajeros)
  final VoidCallback? onCancel;

  const SaleCard({super.key, required this.sale, required this.showProfit, this.onCancel});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isToday = sale.date.year == DateTime.now().year &&
        sale.date.month == DateTime.now().month &&
        sale.date.day == DateTime.now().day;
    final timeStr = isToday
        ? 'Hoy, ${DateFormat('hh:mm a').format(sale.date)}'
        : DateFormat('dd/MM/yyyy • hh:mm a').format(sale.date);

    Color methodColor;
    String methodLabel;
    IconData methodIcon;

    switch (sale.paymentMethod) {
      case 'TRANSFERENCIA':
        methodColor = const Color(0xFF2563EB);
        methodLabel = 'Transferencia';
        methodIcon = Icons.account_balance_outlined;
        break;
      case 'FIADO':
        methodColor = const Color(0xFFD97706);
        methodLabel = 'Venta a Fiado';
        methodIcon = Icons.assignment_late_outlined;
        break;
      default:
        methodColor = const Color(0xFF059669);
        methodLabel = 'Efectivo';
        methodIcon = Icons.payments_outlined;
    }

    final unitPrice = sale.quantity > 0 ? sale.totalAmount / sale.quantity : sale.totalAmount;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      elevation: 0,
      color: isDark ? const Color(0xFF131127) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isDark ? const Color(0xFF26214A) : const Color(0xFFE2E8F0),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Cabecera: Fecha/Hora y Badge de Método de Pago
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.schedule_rounded,
                      size: 14,
                      color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      timeStr,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: methodColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: methodColor.withOpacity(0.25)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(methodIcon, size: 13, color: methodColor),
                      const SizedBox(width: 4),
                      Text(
                        methodLabel,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                          color: methodColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // 2. Bloque del Producto: Foto + Nombre Multilínea + Cliente si es fiado
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Foto del producto
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isDark ? const Color(0xFF26214A) : const Color(0xFFE2E8F0),
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(11),
                    child: ProductImageView(
                      imagePath: sale.productPhotoPath,
                      width: 56,
                      height: 56,
                      iconSize: 26,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Información textual completa del producto
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        sale.productName,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.bold,
                          color: isDark ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A),
                          height: 1.25,
                        ),
                        softWrap: true,
                      ),
                      if (sale.paymentMethod == 'FIADO' || (sale.customerName != null && sale.customerName!.trim().isNotEmpty)) ...[
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFFD97706).withOpacity(0.12),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFFD97706).withOpacity(0.3)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.person_rounded, size: 13, color: Color(0xFFD97706)),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  'Cliente: ${sale.customerName ?? "Sin registrar"}',
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFFD97706),
                                  ),
                                  softWrap: true,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // 3. Ficha de Métricas Comerciales (Bloque en grilla / celdas)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF18152F) : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark ? const Color(0xFF26214A) : const Color(0xFFE2E8F0),
                ),
              ),
              child: Row(
                children: [
                  _metricCell(
                    label: 'Cantidad',
                    value: 'x${sale.quantity} und.',
                    isDark: isDark,
                  ),
                  _metricDivider(isDark),
                  _metricCell(
                    label: 'Unitario',
                    value: CurrencyFormatter.format(unitPrice),
                    isDark: isDark,
                  ),
                  if (showProfit) ...[
                    _metricDivider(isDark),
                    _metricCell(
                      label: 'Ganancia',
                      value: '+${CurrencyFormatter.format(sale.netProfit)}',
                      isDark: isDark,
                      valueColor: const Color(0xFF059669),
                    ),
                  ],
                  _metricDivider(isDark),
                  _metricCell(
                    label: 'Total',
                    value: CurrencyFormatter.format(sale.totalAmount),
                    isDark: isDark,
                    isBold: true,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // 4. Barra Inferior de Acciones Directas
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => DigitalTicketModal.show(context, sale: sale),
                    icon: const Icon(Icons.receipt_long_rounded, size: 16),
                    label: const Text(
                      'Comprobante',
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF059669),
                      side: BorderSide(
                        color: isDark ? const Color(0xFF065F46) : const Color(0xFFA7F3D0),
                      ),
                      backgroundColor: isDark
                          ? const Color(0xFF064E3B).withOpacity(0.2)
                          : const Color(0xFFECFDF5),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                if (onCancel != null) ...[
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: onCancel,
                    icon: const Icon(Icons.undo_rounded, size: 15),
                    label: const Text(
                      'Anular',
                      style: TextStyle(fontSize: 12),
                    ),
                    style: TextButton.styleFrom(
                      foregroundColor: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  static Widget _metricCell({
    required String label,
    required String value,
    required bool isDark,
    Color? valueColor,
    bool isBold = false,
  }) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
                color: valueColor ??
                    (isDark ? const Color(0xFFF8FAFC) : const Color(0xFF1E293B)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _metricDivider(bool isDark) {
    return Container(
      height: 24,
      width: 1,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: isDark ? const Color(0xFF26214A) : const Color(0xFFE2E8F0),
    );
  }
}
