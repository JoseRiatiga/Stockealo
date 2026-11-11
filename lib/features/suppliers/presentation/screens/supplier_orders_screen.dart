import 'package:flutter/material.dart';

import '../../../../core/design/app_card.dart';
import '../../../../core/design/content_width.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../business/models/business.dart';
import '../../data/supplier_repository.dart';
import '../../data/supplier_whatsapp.dart';
import '../../models/supplier_order.dart';
import 'purchase_detail_screen.dart';
import 'purchase_entry_screen.dart';
import '../../../../core/design/app_dialog.dart';

/// Mensaje para pedir de nuevo lo que no llegó
String missingItemsText({required String businessName, required SupplierOrder order}) {
  final b = StringBuffer()
    ..writeln('*PEDIDO PENDIENTE - ${businessName.toUpperCase()}*')
    ..writeln('Del pedido del ${purchaseDateLabel(order.createdAt)} no nos llegó:');
  for (final i in order.missingItems) {
    b.writeln('• ${i.label}: ${i.missing}');
  }
  b
    ..writeln('')
    ..writeln('Total: ${order.missingUnits} ${order.missingUnits == 1 ? 'unidad' : 'unidades'}.')
    ..writeln('¿Nos confirmas cuándo lo puedes enviar? ¡Gracias!');
  return b.toString();
}

/// Pedidos enviados a proveedores: lo pedido, lo que llegó y lo que falta
class SupplierOrdersScreen extends StatefulWidget {
  final Business business;
  final String? supplierId;
  const SupplierOrdersScreen({super.key, required this.business, this.supplierId});

  static Future<void> open(BuildContext context, {required Business business, String? supplierId}) =>
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => SupplierOrdersScreen(business: business, supplierId: supplierId),
      ));

  @override
  State<SupplierOrdersScreen> createState() => _SupplierOrdersScreenState();
}

class _SupplierOrdersScreenState extends State<SupplierOrdersScreen> {
  final _repo = SupplierRepository.instance;
  List<SupplierOrder>? _orders;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await _repo.getOrders(widget.business.id, supplierId: widget.supplierId);
    if (mounted) setState(() => _orders = list);
  }

  Future<void> _receive(SupplierOrder o) async {
    final saved = await PurchaseEntryScreen.open(context, business: widget.business, order: o);
    if (saved == true) _load();
  }

  Future<void> _askMissing(SupplierOrder o) async {
    final supplier = o.supplierId == null ? null : await _repo.getSupplier(o.supplierId!);
    await SupplierWhatsApp.send(
      supplier,
      missingItemsText(businessName: widget.business.name, order: o),
      subject: 'Pedido pendiente',
    );
  }

  Future<void> _close(SupplierOrder o) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AppDialog(
title: '¿Cerrar el pedido?',
content: Text(
          o.missingUnits > 0
              ? 'Ya no esperas las ${o.missingUnits} unidades que faltan. El pedido deja de aparecer como pendiente.'
              : 'El pedido deja de aparecer como pendiente.',
        ),
actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Cerrar pedido')),
        ],
),
    );
    if (ok != true) return;
    await _repo.closeOrder(o);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final list = _orders;
    return Scaffold(
      backgroundColor: c.paper,
      appBar: AppBar(title: const Text('Pedidos a proveedores')),
      body: ContentWidth(
        child: list == null
            ? const Center(child: CircularProgressIndicator())
            : list.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpace.xl),
                      child: Text(
                        'Aún no has enviado pedidos. Se guardan solos al enviarlos desde "Pedido a proveedor".',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: c.inkMuted),
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(AppSpace.lg),
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const SizedBox(height: AppSpace.md),
                    itemBuilder: (_, i) => _orderCard(list[i]),
                  ),
      ),
    );
  }

  Widget _orderCard(SupplierOrder o) {
    final c = context.colors;
    final (bg, fg) = switch (o.status) {
      SupplierOrder.received => (c.successSoft, c.success),
      SupplierOrder.partial => (c.warningSoft, c.warning),
      SupplierOrder.closed => (c.surfaceMuted, c.inkMuted),
      _ => (c.infoSoft, c.info),
    };
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${o.supplierName ?? 'Sin proveedor'} · ${purchaseDateLabel(o.createdAt)}',
                  style: TextStyle(color: c.ink, fontWeight: FontWeight.w600),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(AppRadius.pill)),
                child: Text(o.statusLabel, style: TextStyle(color: fg, fontSize: AppText.sizeCaption, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.sm),
          for (final i in o.items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Expanded(child: Text(i.label, style: TextStyle(color: c.ink, fontSize: AppText.sizeSmall))),
                  Text(
                    o.status == SupplierOrder.sent ? 'pedido ${i.quantity}' : 'llegó ${i.received} de ${i.quantity}',
                    style: TextStyle(
                      color: o.status != SupplierOrder.sent && i.missing > 0 ? c.danger : c.inkMuted,
                      fontSize: AppText.sizeSmall,
                      fontWeight: i.missing > 0 && o.status != SupplierOrder.sent ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
          if (o.isPending) ...[
            const SizedBox(height: AppSpace.md),
            Wrap(
              spacing: AppSpace.sm,
              runSpacing: AppSpace.sm,
              children: [
                FilledButton.icon(
                  onPressed: () => _receive(o),
                  icon: const Icon(Icons.move_to_inbox_outlined, size: 18),
                  label: Text(o.status == SupplierOrder.partial ? 'Llegó lo que faltaba' : 'Registrar lo que llegó'),
                ),
                if (o.status == SupplierOrder.partial)
                  OutlinedButton.icon(
                    onPressed: () => _askMissing(o),
                    icon: const Icon(Icons.send_outlined, size: 16),
                    label: const Text('Pedir lo que faltó'),
                  ),
                TextButton(onPressed: () => _close(o), child: const Text('Cerrar pedido')),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
