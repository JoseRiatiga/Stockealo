import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/design/app_card.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../products/presentation/widgets/product_image_view.dart';
import '../../models/sale.dart';
import 'digital_ticket_modal.dart';

/// Nombre legible del método de pago
String paymentMethodLabel(String method) => switch (method) {
      'EFECTIVO' => 'Efectivo',
      'TRANSFERENCIA' => 'Transferencia',
      'FIADO' => 'Fiado',
      _ => method,
    };

/// Venta en una fila compacta (foto, producto, hora y método, total). Al tocarla se
/// abre el detalle con cantidades, ganancia, comprobante y anular.
class SaleCard extends StatelessWidget {
  final Sale sale;

  /// Mostrar ganancia y costo (solo dueño y admin)
  final bool showProfit;

  /// Anular la venta; null oculta el botón (cajeros)
  final VoidCallback? onCancel;

  const SaleCard({super.key, required this.sale, required this.showProfit, this.onCancel});

  String get _title {
    final variant = sale.variantName;
    return variant == null || variant.isEmpty ? sale.productName : '${sale.productName} · $variant';
  }

  Future<void> _showDetail(BuildContext context) async {
    final c = context.colors;
    Widget row(String label, String value, {Color? color}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Expanded(child: Text(label, style: TextStyle(color: c.inkMuted, fontSize: 14))),
              Text(value, style: AppText.amount(context, size: 14, weight: FontWeight.w600, color: color)),
            ],
          ),
        );

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpace.xl, 0, AppSpace.xl, AppSpace.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  ProductImageView(
                    imagePath: sale.productPhotoPath,
                    width: 52,
                    height: 52,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  const SizedBox(width: AppSpace.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_title, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: c.ink)),
                        Text(
                          DateFormat("d 'de' MMMM, h:mm a", 'es_CO').format(sale.date),
                          style: TextStyle(fontSize: 13, color: c.inkMuted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpace.lg),
              row('Cantidad', '${sale.quantity}'),
              row('Precio unitario', CurrencyFormatter.format(sale.unitPrice)),
              row('Método de pago', paymentMethodLabel(sale.paymentMethod)),
              if (sale.customerName != null && sale.customerName!.trim().isNotEmpty) row('Cliente', sale.customerName!),
              if (sale.sellerName != null && sale.sellerName!.trim().isNotEmpty) row('Vendió', sale.sellerName!),
              if (showProfit)
                row('Ganancia', CurrencyFormatter.format(sale.netProfit), color: sale.netProfit < 0 ? c.danger : c.success),
              Divider(height: AppSpace.xl, color: c.line),
              Row(
                children: [
                  Expanded(child: Text('Total', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.ink))),
                  Text(CurrencyFormatter.format(sale.totalAmount), style: AppText.amount(ctx, size: 20)),
                ],
              ),
              const SizedBox(height: AppSpace.xl),
              FilledButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  DigitalTicketModal.show(context, sale: sale);
                },
                icon: const Icon(Icons.receipt_long_rounded),
                label: const Text('Ver comprobante'),
              ),
              if (onCancel != null) ...[
                const SizedBox(height: AppSpace.sm),
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: c.danger),
                  onPressed: () {
                    Navigator.pop(ctx);
                    onCancel!();
                  },
                  child: const Text('Anular venta'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isFiado = sale.paymentMethod == 'FIADO';
    final meta = [
      DateFormat('h:mm a', 'es_CO').format(sale.date),
      paymentMethodLabel(sale.paymentMethod),
      if (isFiado && sale.customerName != null && sale.customerName!.trim().isNotEmpty) sale.customerName!,
    ].join(' · ');

    return AppCard(
      padding: const EdgeInsets.all(AppSpace.md),
      onTap: () => _showDetail(context),
      child: Row(
        children: [
          ProductImageView(
            imagePath: sale.productPhotoPath,
            width: 44,
            height: 44,
            borderRadius: BorderRadius.circular(10),
          ),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sale.quantity > 1 ? '$_title  ×${sale.quantity}' : _title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.ink),
                ),
                const SizedBox(height: 2),
                Text(
                  meta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, color: isFiado ? c.warning : c.inkMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpace.sm),
          Text(CurrencyFormatter.format(sale.totalAmount), style: AppText.amount(context)),
        ],
      ),
    );
  }
}
