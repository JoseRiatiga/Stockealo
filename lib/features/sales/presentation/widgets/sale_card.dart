import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/design/app_dialog.dart';
import '../../../../core/design/status_pill.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../products/presentation/widgets/product_image_view.dart';
import '../../models/payment_method.dart';
import '../../models/sale.dart';
import 'digital_ticket_modal.dart';
import '../../data/sales_repository.dart';

/// Venta en una fila compacta (foto, producto, hora y forma de pago, total). Al
/// tocarla se abre el detalle con cantidades, ganancia, comprobante y anular.
/// Una venta anulada se ve tachada, con la pastilla «Anulada» y su motivo.
class SaleCard extends StatelessWidget {
  final Sale sale;

  /// Mostrar ganancia y costo (solo dueño y admin)
  final bool showProfit;

  /// Anular la venta; null oculta el botón (cajeros, o ya anulada)
  final VoidCallback? onCancel;

  /// Todavía no sube a la nube (se hizo sin conexión): «Pendiente de subir»
  final bool pendingUpload;

  const SaleCard({super.key, required this.sale, required this.showProfit, this.onCancel, this.pendingUpload = false});

  String get _title {
    final variant = sale.variantName;
    return variant == null || variant.isEmpty ? sale.productName : '${sale.productName} · $variant';
  }

  Future<void> _showDetail(BuildContext context) async {
    final c = context.colors;
    final split = PaymentMethod.decodeSplit(sale.paymentSplit);
    Widget row(String label, String value, {Color? color}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            children: [
              Expanded(child: Text(label, style: AppText.body(context, color: c.inkMuted))),
              Text(value, style: AppText.amount(context, size: AppText.sizeBody, weight: FontWeight.w600, color: color)),
            ],
          ),
        );

    await AppSheet.show<void>(
      context: context,
      title: _title,
      subtitle: DateFormat("d 'de' MMMM, h:mm a", 'es_CO').format(sale.date),
      builder: (ctx) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (sale.isVoided) ...[
            AnulledNotice(sale: sale),
            const SizedBox(height: AppSpace.md),
          ],
          row('Cantidad', '${sale.quantity}'),
          row('Precio unitario', CurrencyFormatter.format(sale.unitPrice)),
          row('Forma de pago', PaymentMethod.label(sale.paymentMethod)),
          for (final e in split.entries) row('   ${PaymentMethod.label(e.key)}', CurrencyFormatter.format(e.value)),
          if (sale.customerName != null && sale.customerName!.trim().isNotEmpty) row('Cliente', sale.customerName!),
          if (sale.sellerName != null && sale.sellerName!.trim().isNotEmpty) row('Vendió', sale.sellerName!),
          if ((sale.invoiceNumber ?? '').isNotEmpty) row('Venta', sale.invoiceNumber!),
          if (showProfit && !sale.isVoided)
            row('Ganancia', CurrencyFormatter.format(sale.netProfit), color: sale.netProfit < 0 ? c.danger : c.success),
          Divider(height: AppSpace.xl, color: c.line),
          Row(
            children: [
              Expanded(child: Text('Total', style: AppText.title(ctx))),
              Text(
                CurrencyFormatter.format(sale.totalAmount),
                style: AppText.amount(ctx, size: AppText.sizeHeading).copyWith(
                  decoration: sale.isVoided ? TextDecoration.lineThrough : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.xl),
          FilledButton.icon(
            onPressed: () async {
              Navigator.pop(ctx);
              final lines = await SalesRepository.instance.linesOf(sale);
              if (context.mounted) DigitalTicketModal.show(context, salesList: lines);
            },
            icon: const Icon(Icons.receipt_long_outlined),
            label: const Text('Ver comprobante'),
          ),
          if (onCancel != null && !sale.isVoided) ...[
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isFiado = sale.paymentMethod == PaymentMethod.credit;
    final voided = sale.isVoided;
    final meta = [
      DateFormat('h:mm a', 'es_CO').format(sale.date),
      PaymentMethod.label(sale.paymentMethod),
      if (isFiado && sale.customerName != null && sale.customerName!.trim().isNotEmpty) sale.customerName!,
    ].join(' · ');
    final radius = BorderRadius.circular(AppRadius.control + 2);

    return Semantics(
      button: true,
      label: '$_title, ${CurrencyFormatter.format(sale.totalAmount)}, $meta${voided ? ', anulada' : ''}',
      excludeSemantics: true,
      child: Material(
        color: c.surface,
        shape: RoundedRectangleBorder(borderRadius: radius, side: BorderSide(color: c.line)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _showDetail(context),
          child: Opacity(
            opacity: voided ? 0.6 : 1,
            child: Padding(
              padding: const EdgeInsets.all(AppSpace.md),
              child: Row(
                children: [
                  ProductImageView(
                    imagePath: sale.productPhotoPath,
                    width: 44,
                    height: 44,
                    borderRadius: BorderRadius.circular(AppRadius.tile),
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
                          style: AppText.bodyLarge(context, weight: FontWeight.w600),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          meta,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.small(context, color: isFiado && !voided ? c.warning : c.inkMuted),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpace.sm),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        CurrencyFormatter.format(sale.totalAmount),
                        style: AppText.amount(context).copyWith(decoration: voided ? TextDecoration.lineThrough : null),
                      ),
                      if (voided) ...[
                        const SizedBox(height: 2),
                        const StatusPill('Anulada', tone: AppTone.danger, compact: true),
                      ],
                      if (pendingUpload) ...[
                        const SizedBox(height: 2),
                        const StatusPill('Pendiente de subir', tone: AppTone.warning, compact: true),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// «Anulada el 11 nov por Carlos: se equivocó de producto»
class AnulledNotice extends StatelessWidget {
  final Sale sale;

  const AnulledNotice({super.key, required this.sale});

  @override
  Widget build(BuildContext context) {
    final t = ToneColors.of(context, AppTone.danger);
    final when = DateFormat("d MMM, h:mm a", 'es_CO').format(sale.voidedAt!);
    return Container(
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(color: t.soft, borderRadius: BorderRadius.circular(AppRadius.control)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.block_outlined, size: 18, color: t.strong),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Text(
              'Anulada el $when${sale.voidedBy == null ? '' : ' por ${sale.voidedBy}'}'
              '${(sale.voidReason ?? '').isEmpty ? '' : ': ${sale.voidReason}'}. '
              'No cuenta en los totales, la caja ni los reportes.',
              style: AppText.small(context, color: t.text),
            ),
          ),
        ],
      ),
    );
  }
}
