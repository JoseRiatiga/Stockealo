import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/design/content_width.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../business/models/business.dart';
import '../../../auth/data/auth_repository.dart';
import '../../../cash/presentation/widgets/open_cash.dart';
import '../../../sales/data/sales_repository.dart';
import '../../data/services_repository.dart';
import '../../models/service_models.dart';
import '../../../sales/models/cart_item.dart';
import '../../../products/models/product.dart';
import '../../../products/data/product_repository.dart';
import '../../../../core/design/app_dialog.dart';
import '../../../customers/data/customer_repository.dart';
import '../../../sales/models/payment_method.dart';

/// Cobrar un trabajo listo: efectivo, Nequi, transferencia o fiado, con descuento y
/// propina. Cada servicio queda como una línea de venta; después se entrega.
/// 0.14.0: también se cobran productos o repuestos (pomada, shampoo, una llanta),
/// que salen del inventario y no dejan comisión.
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

  /// Productos o repuestos que se cobran con el servicio
  final List<CartItem> _products = [];

  /// Pago mixto: cuánto en cada medio (0.14.0)
  final _split = {for (final m in PaymentMethod.forMixed) m: TextEditingController()};

  /// Fiado con abono: lo que paga ahora (el resto queda debiendo)
  final _deposit = TextEditingController();

  Map<String, double> get _splitValues => {
        for (final e in _split.entries)
          if ((double.tryParse(e.value.text.trim()) ?? 0) > 0) e.key: double.parse(e.value.text.trim()),
      };

  double get _depositValue => double.tryParse(_deposit.text.trim()) ?? 0;

  double get _productsTotal => _products.fold(0.0, (t, l) => t + l.subtotal);

  Future<void> _addProduct() async {
    final picked = await ProductPickerSheet.show(context, businessId: widget.business.id);
    if (picked == null || !mounted) return;
    setState(() {
      final i = _products.indexWhere((l) => l.product.id == picked.product.id && l.variant?.id == picked.variant?.id);
      if (i >= 0) {
        if (_products[i].quantity < _products[i].availableStock) _products[i].quantity++;
      } else {
        _products.add(picked);
      }
    });
  }

  @override
  void dispose() {
    for (final c in [_discount, _tip, _customer, _deposit, ..._split.values]) {
      c.dispose();
    }
    super.dispose();
  }

  double get _sub => widget.order.subtotal;
  double get _disc => (double.tryParse(_discount.text.trim()) ?? 0).clamp(0, _sub).toDouble();
  double get _tipValue => double.tryParse(_tip.text.trim()) ?? 0;
  double get _total => _sub - _disc + _productsTotal;

  Future<void> _pay() async {
    if (_method == 'FIADO' && _customer.text.trim().isEmpty) {
      AppToast.showWarning(context, 'Para fiar escribe el nombre del cliente.');
      return;
    }
    // Mixto: los medios suman lo de los servicios (los productos van aparte, en efectivo)
    final servicesTotal = _sub - _disc;
    if (_method == PaymentMethod.mixed) {
      final sum = _splitValues.values.fold(0.0, (t, v) => t + v);
      if ((sum - servicesTotal).abs() > 1) {
        AppToast.showWarning(context,
            'Los medios suman ${CurrencyFormatter.format(sum)} y los servicios son ${CurrencyFormatter.format(servicesTotal)}.');
        return;
      }
    }
    if (_method == 'FIADO' && _depositValue >= servicesTotal && servicesTotal > 0) {
      AppToast.showWarning(context, 'El abono cubre todo: mejor cóbralo en efectivo o Nequi.');
      return;
    }
    // Caja obligatoria: si el negocio la usa y está cerrada, se abre aquí mismo
    final user = AuthRepository.instance.currentUser;
    if (!await CashGate.ensureOpen(context, business: widget.business, userName: user?.displayName ?? '')) return;
    if (!mounted) return;
    setState(() => _saving = true);
    try {
      final sales = await SalesRepository.instance.recordServiceSale(
        order: widget.order,
        paymentMethod: _method,
        customerName: _customer.text,
        discountAmount: _disc,
        staffNames: widget.staffNames,
        tipAmount: _tipValue,
        paymentSplit: _method == PaymentMethod.mixed ? _splitValues : null,
      );
      await ServicesRepository.instance.markPaid(
        widget.order,
        saleIds: [for (final s in sales) s.id],
        paymentMethod: _method,
        total: _sub - _disc,
        discount: _disc,
        tip: _tipValue,
      );
      // Fiado con abono: lo que paga ahora baja la deuda de una vez
      if (_method == 'FIADO' && _depositValue > 0) {
        final customer = await CustomerRepository.instance.findByName(widget.business.id, _customer.text.trim());
        if (customer != null) {
          await CustomerRepository.instance.recordPayment(
            customerId: customer.id,
            businessId: widget.business.id,
            amount: _depositValue,
            paymentMethod: 'EFECTIVO',
            notes: 'Abono al cobrar ${widget.order.title}',
          );
        }
      }
      // Los productos o repuestos: venta normal que descuenta el inventario
      if (_products.isNotEmpty) {
        await SalesRepository.instance.recordMultiProductSale(
          businessId: widget.business.id,
          items: _products,
          paymentMethod: _method == PaymentMethod.mixed ? PaymentMethod.cash : _method,
          customerName: _customer.text.trim().isEmpty ? null : _customer.text.trim(),
          notes: 'Con la orden ${widget.order.title}',
        );
      }
      if (!mounted) return;
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
            Text('Cobrar ${o.title}', style: TextStyle(fontSize: AppText.sizeHeading, fontWeight: FontWeight.w700, color: c.ink)),
            const SizedBox(height: AppSpace.md),
            for (final l in o.lines)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${l.name}${l.staffIds.isEmpty ? '' : ' · ${l.staffIds.map((id) => widget.staffNames[id] ?? 'Empleado').join(', ')}'}',
                        style: TextStyle(color: c.ink, fontSize: AppText.sizeBody),
                      ),
                    ),
                    Text(CurrencyFormatter.format(l.price), style: TextStyle(color: c.ink)),
                  ],
                ),
              ),
            // Productos o repuestos que se llevan con el servicio
            for (final l in _products)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Expanded(child: Text('${l.quantity} × ${l.displayName}', style: TextStyle(color: c.ink, fontSize: AppText.sizeBody))),
                    IconButton(
                      tooltip: 'Quitar uno',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => setState(() => l.quantity > 1 ? l.quantity-- : _products.remove(l)),
                      icon: const Icon(Icons.remove_circle_outline, size: 18),
                    ),
                    Text(CurrencyFormatter.format(l.subtotal), style: TextStyle(color: c.ink)),
                  ],
                ),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _addProduct,
                icon: const Icon(Icons.add_shopping_cart_outlined, size: 18),
                label: const Text('Agregar producto o repuesto'),
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
                for (final (code, label) in const [
                  ('EFECTIVO', 'Efectivo'),
                  ('NEQUI', 'Nequi'),
                  ('TRANSFERENCIA', 'Transferencia'),
                  ('MIXTO', 'Mixto'),
                  ('FIADO', 'Fiado'),
                ])
                  ChoiceChip(label: Text(label), selected: _method == code, onSelected: (_) => setState(() => _method = code)),
              ],
            ),
            if (_method == PaymentMethod.mixed) ...[
              const SizedBox(height: AppSpace.md),
              Text('¿Cuánto en cada medio? (los servicios: ${CurrencyFormatter.format(_sub - _disc)})',
                  style: TextStyle(fontSize: AppText.sizeSmall, color: c.inkMuted)),
              const SizedBox(height: AppSpace.xs),
              Wrap(
                spacing: AppSpace.sm,
                runSpacing: AppSpace.sm,
                children: [
                  for (final e in _split.entries)
                    SizedBox(
                      width: 150,
                      child: TextField(
                        controller: e.value,
                        keyboardType: TextInputType.number,
                        inputFormatters: digits,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(labelText: PaymentMethod.label(e.key), prefixText: '\$ ', isDense: true),
                      ),
                    ),
                ],
              ),
            ],
            if (_method == 'FIADO') ...[
              const SizedBox(height: AppSpace.md),
              TextField(
                controller: _customer,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Cliente que queda debiendo'),
              ),
              const SizedBox(height: AppSpace.sm),
              TextField(
                controller: _deposit,
                keyboardType: TextInputType.number,
                inputFormatters: digits,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Abona ahora (opcional)',
                  prefixText: '\$ ',
                  helperText: _depositValue > 0
                      ? 'Queda debiendo ${CurrencyFormatter.format((_sub - _disc - _depositValue).clamp(0, double.infinity))}'
                      : 'En efectivo; el resto queda fiado',
                ),
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

/// Elegir un producto del inventario (con talla o color si tiene) para cobrarlo
/// junto con el servicio. Devuelve una línea de 1 unidad.
class ProductPickerSheet extends StatefulWidget {
  final String businessId;

  const ProductPickerSheet({super.key, required this.businessId});

  static Future<CartItem?> show(BuildContext context, {required String businessId}) => AppSheet.show<CartItem>(
        context: context,
        title: 'Agregar producto o repuesto',
        subtitle: 'Sale del inventario al cobrar.',
        builder: (_) => ProductPickerSheet(businessId: businessId),
      );

  @override
  State<ProductPickerSheet> createState() => _ProductPickerSheetState();
}

class _ProductPickerSheetState extends State<ProductPickerSheet> {
  final _query = TextEditingController();
  List<Product> _found = const [];

  @override
  void initState() {
    super.initState();
    _search('');
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _search(String q) async {
    final list = await ProductRepository.instance.searchProducts(q, businessId: widget.businessId);
    if (mounted) setState(() => _found = list.where((p) => p.isActive && p.stock > 0).take(40).toList());
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _query,
          autofocus: true,
          onChanged: _search,
          decoration: const InputDecoration(hintText: 'Buscar producto', prefixIcon: Icon(Icons.search_outlined)),
        ),
        const SizedBox(height: AppSpace.sm),
        if (_found.isEmpty)
          Padding(
            padding: const EdgeInsets.all(AppSpace.lg),
            child: Text('No hay productos con existencias con ese nombre.', textAlign: TextAlign.center, style: TextStyle(color: c.inkMuted)),
          ),
        for (final p in _found)
          if (p.variants.isEmpty)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(p.name),
              subtitle: Text('Quedan ${p.stock}'),
              trailing: Text(CurrencyFormatter.format(p.salePrice)),
              onTap: () => Navigator.pop(context, CartItem(product: p)),
            )
          else
            for (final v in p.variants.where((v) => v.stock > 0))
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('${p.name} (${v.label})'),
                subtitle: Text('Quedan ${v.stock}'),
                trailing: Text(CurrencyFormatter.format(p.salePrice + v.additionalPrice)),
                onTap: () => Navigator.pop(context, CartItem(product: p, variant: v)),
              ),
      ],
    );
  }
}
