import 'package:flutter/material.dart';
import '../../../../core/utils/clock_text.dart';
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

  /// Devolver unidades de esta venta (0.15.0); null = el rol no puede devolver
  final VoidCallback? onReturn;

  /// Todavía no sube a la nube (se hizo sin conexión): «Pendiente de subir»
  final bool pendingUpload;

  const SaleCard({super.key, required this.sale, required this.showProfit, this.onCancel, this.onReturn, this.pendingUpload = false});

  String get _title {
    final variant = sale.variantName;
    final name = variant == null || variant.isEmpty ? sale.listName : '${sale.listName} · $variant';
    // Una devolución se nombra como tal (0.16.4): antes parecía otra venta en negativo
    return sale.isReturn ? 'Devolución · $name' : name;
  }

  Future<void> showDetail(BuildContext context) async {
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
          if (onReturn != null && !sale.isVoided && !sale.isReturn && !sale.isService) ...[
            const SizedBox(height: AppSpace.sm),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                onReturn!();
              },
              icon: const Icon(Icons.assignment_return_outlined),
              label: const Text('Devolver'),
            ),
          ],
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
    final isFiado = PaymentMethod.creditPart(sale.paymentMethod, sale.totalAmount, sale.paymentSplit) != 0;
    final voided = sale.isVoided;
    final meta = [
      clockText(sale.date),
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
          onTap: () => showDetail(context),
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
                          sale.quantity.abs() > 1 ? '$_title  ×${sale.quantity.abs()}' : _title,
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
                      if (sale.isReturn && !voided) ...[
                        const SizedBox(height: 2),
                        const StatusPill('Devolución', tone: AppTone.info, compact: true),
                      ],
                      if (sale.pendingDelivery) ...[
                        const SizedBox(height: 2),
                        const StatusPill('Por entregar', tone: AppTone.warning, compact: true),
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

/// Una venta con varios productos en una sola tarjeta (0.16.4): «Arroz y 3 más».
/// Antes cada producto salía como una venta aparte y la lista decía «9 ventas»
/// cuando eran 4. Al tocarla se ven sus productos; cada uno abre su detalle
/// (devolver, ganancia) y abajo están el comprobante y anular.
class SaleGroupCard extends StatelessWidget {
  /// Las líneas de un mismo comprobante, la primera es la más reciente
  final List<Sale> lines;
  final bool showProfit;

  /// Arma la tarjeta de una línea para abrir su detalle (devolver, anular)
  final SaleCard Function(Sale line) lineCard;

  /// Anular toda la venta; null oculta el botón
  final VoidCallback? onCancel;
  final bool pendingUpload;

  const SaleGroupCard({
    super.key,
    required this.lines,
    required this.showProfit,
    required this.lineCard,
    this.onCancel,
    this.pendingUpload = false,
  });

  Sale get _first => lines.first;
  bool get _voided => lines.every((l) => l.isVoided);
  double get _total => lines.where((l) => !l.isVoided || _voided).fold(0.0, (s, l) => s + l.totalAmount);
  int get _units => lines.fold(0, (s, l) => s + l.quantity);
  String get _title => '${_first.listName} y ${lines.length - 1} más';

  String _meta() {
    final customer = lines.map((l) => l.customerName ?? '').firstWhere((n) => n.trim().isNotEmpty, orElse: () => '');
    return [
      clockText(_first.date),
      PaymentMethod.label(_first.paymentMethod),
      if (PaymentMethod.creditPart(_first.paymentMethod, _first.totalAmount, _first.paymentSplit) != 0 && customer.isNotEmpty) customer,
    ].join(' · ');
  }

  Future<void> _showDetail(BuildContext context) async {
    final c = context.colors;
    await AppSheet.show<void>(
      context: context,
      title: '${lines.length} productos · $_units unidades',
      subtitle: '${DateFormat("d 'de' MMMM, h:mm a", 'es_CO').format(_first.date)}'
          '${(_first.invoiceNumber ?? '').isEmpty ? '' : ' · ${_first.invoiceNumber}'}',
      builder: (ctx) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_voided) ...[
            AnulledNotice(sale: _first),
            const SizedBox(height: AppSpace.md),
          ],
          Text('Toca un producto para ver su detalle o devolverlo.', style: AppText.caption(ctx)),
          const SizedBox(height: AppSpace.sm),
          for (final l in lines)
            InkWell(
              borderRadius: BorderRadius.circular(AppRadius.control),
              onTap: () {
                Navigator.pop(ctx);
                lineCard(l).showDetail(context);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${l.listName}${(l.variantName ?? '').isEmpty ? '' : ' · ${l.variantName}'}'
                        '${l.quantity > 1 ? '  ×${l.quantity}' : ''}',
                        style: AppText.body(ctx, color: l.isVoided ? c.inkMuted : null),
                      ),
                    ),
                    Text(CurrencyFormatter.format(l.totalAmount), style: AppText.amount(ctx, size: AppText.sizeBody, weight: FontWeight.w600)),
                    const SizedBox(width: AppSpace.xs),
                    Icon(Icons.chevron_right_outlined, size: 18, color: c.inkFaint),
                  ],
                ),
              ),
            ),
          Divider(height: AppSpace.xl, color: c.line),
          Row(
            children: [
              Expanded(child: Text('Total', style: AppText.title(ctx))),
              Text(
                CurrencyFormatter.format(_total),
                style: AppText.amount(ctx, size: AppText.sizeHeading).copyWith(decoration: _voided ? TextDecoration.lineThrough : null),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.xl),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              DigitalTicketModal.show(context, salesList: lines);
            },
            icon: const Icon(Icons.receipt_long_outlined),
            label: const Text('Ver comprobante'),
          ),
          if (onCancel != null && !_voided) ...[
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
    final voided = _voided;
    final isFiado = PaymentMethod.creditPart(_first.paymentMethod, _first.totalAmount, _first.paymentSplit) != 0;
    final meta = _meta();
    final radius = BorderRadius.circular(AppRadius.control + 2);
    return Semantics(
      button: true,
      label: '$_title, ${CurrencyFormatter.format(_total)}, $meta${voided ? ', anulada' : ''}',
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
                    imagePath: _first.productPhotoPath,
                    width: 44,
                    height: 44,
                    borderRadius: BorderRadius.circular(AppRadius.tile),
                  ),
                  const SizedBox(width: AppSpace.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.bodyLarge(context, weight: FontWeight.w600)),
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
                        CurrencyFormatter.format(_total),
                        style: AppText.amount(context).copyWith(decoration: voided ? TextDecoration.lineThrough : null),
                      ),
                      if (voided) ...[
                        const SizedBox(height: 2),
                        const StatusPill('Anulada', tone: AppTone.danger, compact: true),
                      ],
                      if (lines.any((l) => l.pendingDelivery)) ...[
                        const SizedBox(height: 2),
                        const StatusPill('Por entregar', tone: AppTone.warning, compact: true),
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
