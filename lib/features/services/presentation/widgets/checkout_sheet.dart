import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/design/content_width.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../business/models/business.dart';
import '../../../cash/presentation/widgets/cash_status_card.dart';
import '../../../sales/data/sales_repository.dart';
import '../../data/services_repository.dart';
import '../../models/service_models.dart';

/// Cobrar un trabajo listo: efectivo, transferencia o fiado, con descuento y
/// propina. Cada servicio queda como una línea de venta; después se entrega.
class CheckoutSheet extends StatefulWidget {
  final WorkOrder order;
  final Business business;
  final Map<String, String> staffNames;

  const CheckoutSheet({super.key, required this.order, required this.business, required this.staffNames});

  static Future<bool?> show(
    BuildContext context, {
    required WorkOrder order,
    required Business business,
    required Map<String, String> staffNames,
  }) =>
      showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (_) => CheckoutSheet(order: order, business: business, staffNames: staffNames),
      );

  @override
  State<CheckoutSheet> createState() => _CheckoutSheetState();
}

class _CheckoutSheetState extends State<CheckoutSheet> {
  final _discount = TextEditingController();
  final _tip = TextEditingController();
  late final _customer = TextEditingController(text: widget.order.customerName ?? '');
  String _method = 'EFECTIVO';
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_discount, _tip, _customer]) {
      c.dispose();
    }
    super.dispose();
  }

  double get _sub => widget.order.subtotal;
  double get _disc => (double.tryParse(_discount.text.trim()) ?? 0).clamp(0, _sub).toDouble();
  double get _tipValue => double.tryParse(_tip.text.trim()) ?? 0;
  double get _total => _sub - _disc;

  Future<void> _pay() async {
    if (_method == 'FIADO' && _customer.text.trim().isEmpty) {
      AppToast.showWarning(context, 'Para fiar escribe el nombre del cliente.');
      return;
    }
    setState(() => _saving = true);
    try {
      final sales = await SalesRepository.instance.recordServiceSale(
        order: widget.order,
        paymentMethod: _method,
        customerName: _customer.text,
        discountAmount: _disc,
        staffNames: widget.staffNames,
        tipAmount: _tipValue,
      );
      await ServicesRepository.instance.markPaid(
        widget.order,
        saleIds: [for (final s in sales) s.id],
        paymentMethod: _method,
        total: _total,
        discount: _disc,
        tip: _tipValue,
      );
      final cashClosed = await isCashClosedFor(widget.business, _method);
      if (!mounted) return;
      if (cashClosed) AppToast.showWarning(context, kCashClosedWarning);
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppToast.showError(context, e.toString().replaceFirst('Exception: ', ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final o = widget.order;
    final digits = [FilteringTextInputFormatter.digitsOnly];
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: ContentWidth(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(AppSpace.lg, 0, AppSpace.lg, AppSpace.lg),
          children: [
            Text('Cobrar ${o.title}', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c.ink)),
            const SizedBox(height: AppSpace.md),
            for (final l in o.lines)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${l.name}${l.staffIds.isEmpty ? '' : ' · ${l.staffIds.map((id) => widget.staffNames[id] ?? 'Empleado').join(', ')}'}',
                        style: TextStyle(color: c.ink, fontSize: 13.5),
                      ),
                    ),
                    Text(CurrencyFormatter.format(l.price), style: TextStyle(color: c.ink)),
                  ],
                ),
              ),
            Divider(color: c.line),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _discount,
                    keyboardType: TextInputType.number,
                    inputFormatters: digits,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(labelText: 'Descuento', prefixText: '\$ ', isDense: true),
                  ),
                ),
                const SizedBox(width: AppSpace.md),
                Expanded(
                  child: TextField(
                    controller: _tip,
                    keyboardType: TextInputType.number,
                    inputFormatters: digits,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Propina',
                      prefixText: '\$ ',
                      isDense: true,
                      helperText: 'Completa para quien atendió',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.md),
            Wrap(
              spacing: AppSpace.sm,
              children: [
                for (final (code, label) in const [('EFECTIVO', 'Efectivo'), ('TRANSFERENCIA', 'Transferencia'), ('FIADO', 'Fiado')])
                  ChoiceChip(label: Text(label), selected: _method == code, onSelected: (_) => setState(() => _method = code)),
              ],
            ),
            if (_method == 'FIADO') ...[
              const SizedBox(height: AppSpace.md),
              TextField(
                controller: _customer,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Cliente que queda debiendo'),
              ),
            ],
            const SizedBox(height: AppSpace.lg),
            FilledButton(
              onPressed: _saving ? null : _pay,
              child: Text(_saving
                  ? 'Cobrando...'
                  : 'Cobrar ${CurrencyFormatter.format(_total)}${_tipValue > 0 ? ' + ${CurrencyFormatter.format(_tipValue)} de propina' : ''}'),
            ),
          ],
        ),
      ),
    );
  }
}
