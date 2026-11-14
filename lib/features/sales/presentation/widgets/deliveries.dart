import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/design/app_dialog.dart';
import '../../../../core/design/status_pill.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../data/sales_repository.dart';
import '../../models/quotation.dart';
import '../../models/sale.dart';

/// Cómo se entrega un pedido al cobrarlo (0.13.4). Solo se pregunta en los pedidos
/// (cotizaciones), no en las ventas de mostrador.
class DeliveryChoice {
  /// null = ya se lo llevó; si no, [Sale.toDeliver]
  final String? status;
  final String? note;

  const DeliveryChoice(this.status, this.note);

  /// «¿Cómo se entrega?». null si se cancela.
  static Future<DeliveryChoice?> ask(BuildContext context) async {
    final address = TextEditingController();
    String option = 'now';
    final result = await AppDialog.show<DeliveryChoice>(
      context: context,
      icon: Icons.local_shipping_outlined,
      title: '¿Cómo se entrega?',
      subtitle: 'Si no se lo lleva ya, queda en Ventas › Por entregar hasta que lo marques entregado.',
      content: StatefulBuilder(
        builder: (ctx, set) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            RadioGroup<String>(
              groupValue: option,
              onChanged: (v) => set(() => option = v ?? option),
              child: Column(
                children: [
                  for (final o in const [
                    ('now', 'Ya se lo llevó', Icons.check_circle_outline),
                    ('pickup', 'Lo recoge después', Icons.storefront_outlined),
                    ('ship', 'Envío', Icons.local_shipping_outlined),
                  ])
                    RadioListTile<String>(
                      contentPadding: EdgeInsets.zero,
                      value: o.$1,
                      title: Text(o.$2),
                      secondary: Icon(o.$3),
                    ),
                ],
              ),
            ),
            if (option == 'ship')
              TextField(
                controller: address,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Dirección o indicaciones'),
              ),
          ],
        ),
      ),
      actions: [
        Builder(
          builder: (ctx) => TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
        ),
        Builder(
          builder: (ctx) => FilledButton(
            onPressed: () => Navigator.pop(
              ctx,
              switch (option) {
                'pickup' => const DeliveryChoice(Sale.toDeliver, 'Lo recoge después'),
                'ship' => DeliveryChoice(Sale.toDeliver,
                    address.text.trim().isEmpty ? 'Envío' : 'Envío: ${address.text.trim()}'),
                _ => const DeliveryChoice(null, null),
              },
            ),
            child: const Text('Cobrar'),
          ),
        ),
      ],
    );
    address.dispose();
    return result;
  }
}

/// De dónde vino un pedido en el local (al cotizar en Vender). null si se cancela.
Future<String?> askQuotationSource(BuildContext context) => AppDialog.show<String>(
      context: context,
      icon: Icons.receipt_long_outlined,
      title: '¿De dónde viene el pedido?',
      content: Builder(
        builder: (ctx) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              leading: const Icon(Icons.storefront_outlined),
              title: const Text('En el local'),
              subtitle: const Text('El cliente está aquí'),
              onTap: () => Navigator.pop(ctx, Quotation.sourceLocal),
            ),
            ListTile(
              leading: const Icon(Icons.chat_outlined),
              title: const Text('WhatsApp'),
              subtitle: const Text('Lo pidió por mensaje'),
              onTap: () => Navigator.pop(ctx, Quotation.sourceWhatsApp),
            ),
          ],
        ),
      ),
    );

/// Ventas › Por entregar: lo que se cobró y todavía no se ha entregado
class DeliveriesSheet extends StatefulWidget {
  final String businessId;

  const DeliveriesSheet({super.key, required this.businessId});

  static Future<void> show(BuildContext context, {required String businessId}) => AppSidePanel.show<void>(
        context: context,
        title: 'Por entregar',
        subtitle: 'Pedidos cobrados que el cliente recoge después o se envían.',
        builder: (_) => DeliveriesSheet(businessId: businessId),
      );

  @override
  State<DeliveriesSheet> createState() => _DeliveriesSheetState();
}

class _DeliveriesSheetState extends State<DeliveriesSheet> {
  List<List<Sale>>? _groups;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final groups = await SalesRepository.instance.pendingDeliveries(widget.businessId);
    if (mounted) setState(() => _groups = groups);
  }

  Future<void> _deliver(List<Sale> lines) async {
    await SalesRepository.instance.markDelivered(lines);
    if (!mounted) return;
    AppToast.showSuccess(context, 'Marcado como entregado.');
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final groups = _groups;
    if (groups == null) return const Padding(padding: EdgeInsets.all(AppSpace.xl), child: Center(child: CircularProgressIndicator()));
    if (groups.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpace.xl),
        child: Text('No hay nada por entregar.', textAlign: TextAlign.center, style: AppText.body(context, color: c.inkMuted)),
      );
    }
    final day = DateFormat("d MMM, h:mm a", 'es_CO');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final g in groups)
          Container(
            margin: const EdgeInsets.only(bottom: AppSpace.sm),
            padding: const EdgeInsets.all(AppSpace.md),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(color: c.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        g.first.customerName?.isNotEmpty == true ? g.first.customerName! : 'Sin nombre',
                        style: AppText.bodyLarge(context, weight: FontWeight.w700),
                      ),
                    ),
                    Text(CurrencyFormatter.format(g.fold<double>(0, (s, l) => s + l.totalAmount)),
                        style: AppText.amount(context, size: AppText.sizeBody)),
                  ],
                ),
                Text(
                  [
                    if ((g.first.invoiceNumber ?? '').isNotEmpty) g.first.invoiceNumber!,
                    day.format(g.first.date),
                    for (final l in g) '${l.quantity} × ${l.productName}',
                  ].join(' · '),
                  style: AppText.small(context),
                ),
                const SizedBox(height: AppSpace.xs),
                Row(
                  children: [
                    StatusPill(g.first.deliveryNote ?? 'Por entregar', tone: AppTone.warning, compact: true),
                    const Spacer(),
                    FilledButton.icon(
                      onPressed: () => _deliver(g),
                      icon: const Icon(Icons.check_outlined, size: 18),
                      label: const Text('Entregado'),
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }
}
