import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../../core/design/app_dialog.dart';
import '../../../../core/design/status_pill.dart';
import '../../../../core/services/data_events.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../auth/data/auth_repository.dart';
import '../../../business/models/business.dart';
import '../../../cash/data/cash_register_repository.dart';
import '../../../cash/presentation/widgets/open_cash.dart';
import '../../../customers/data/customer_repository.dart';
import '../../../products/data/product_repository.dart';
import '../../../products/models/product.dart';
import '../../../products/models/product_variant.dart';
import '../../../products/presentation/widgets/product_image_view.dart';
import '../../data/sales_repository.dart';
import '../../data/sell_cart.dart';
import '../../models/payment_method.dart';
import '../../models/sale.dart';
import '../widgets/digital_ticket_modal.dart';
import '../widgets/variant_picker.dart';
import '../../../../core/codes/code_reader.dart';

/// Vender: el punto de venta. Buscar o escanear (también con lector USB: el código
/// entra solo al carrito), tocar productos, cobrar con F9 y seguir con la
/// siguiente venta sin cerrar ni abrir ventanas. Diseño aprobado el 11 nov 2026.
///
/// En el computador la cuenta va fija a la derecha; en el celular es una barra
/// abajo («3 productos · \$ 9.600 · Cobrar») que sube el detalle.
class SellScreen extends StatefulWidget {
  final Business business;
  final String role;

  const SellScreen({super.key, required this.business, required this.role});

  /// Desde este ancho la cuenta va al lado de los productos
  static const wideFrom = 900.0;

  /// Agrega un producto a la cuenta de Vender y lleva allá (desde el detalle de
  /// un producto o el buscador). Pregunta la talla o el color si hace falta.
  static Future<void> sell(BuildContext context, Product product, {ProductVariant? variant}) async {
    var v = variant;
    if (product.hasVariants && v == null) {
      v = await VariantPicker.pick(context, product);
      if (v == null) return;
    }
    final problem = SellCart.instance.add(product, v);
    if (context.mounted && problem != null) AppToast.showWarning(context, problem);
  }

  @override
  State<SellScreen> createState() => _SellScreenState();
}

/// Cómo se está pagando la cuenta (cambia sin tocar la cuenta)
class _Payment extends ChangeNotifier {
  String method = PaymentMethod.cash;

  /// Efectivo recibido (null = exacto)
  double? received;
  final Map<String, TextEditingController> mixed = {
    for (final m in PaymentMethod.forMixed) m: TextEditingController(),
  };

  void set(String m) {
    method = m;
    received = null;
    notifyListeners();
  }

  void receive(double? value) {
    received = value;
    notifyListeners();
  }

  Map<String, double> get split => {
        for (final e in mixed.entries)
          e.key: double.tryParse(e.value.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0,
      };

  double get mixedPaid => split.values.fold<double>(0, (a, b) => a + b);

  void reset() {
    method = PaymentMethod.cash;
    received = null;
    for (final c in mixed.values) {
      c.clear();
    }
    notifyListeners();
  }

  void changed() => notifyListeners();

  @override
  void dispose() {
    for (final c in mixed.values) {
      c.dispose();
    }
    super.dispose();
  }
}

/// La última venta, para el aviso «✓ Venta registrada» con «Enviar recibo»
class _LastSale {
  final List<Sale> sales;
  final double discount;
  final double total;
  final int units;
  final String method;
  final double change;
  final double? received;
  final double? debtAfter;

  const _LastSale(this.sales, this.discount, this.total, this.units, this.method, this.change, this.received, this.debtAfter);

  void showTicket(BuildContext context, {bool justSold = false}) => DigitalTicketModal.show(
        context,
        salesList: sales,
        discountAmount: discount,
        received: received,
        change: change,
        debtAfter: debtAfter,
        justSold: justSold,
      );
}

class _SellScreenState extends State<SellScreen> {
  final _cart = SellCart.instance;
  final _pay = _Payment();
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  final _customer = TextEditingController();

  List<Product> _products = const [];
  List<String> _customers = const [];
  String? _category;
  bool _loading = true;
  bool _saving = false;
  bool _cashClosed = false;
  _LastSale? _last;

  bool get _manager => widget.role == 'OWNER' || widget.role == 'ADMIN';
  String get _userName => AuthRepository.instance.currentUser?.displayName ?? '';

  @override
  void initState() {
    super.initState();
    // La cuenta es de un negocio: al cambiar de negocio no se arrastra
    final other = [..._cart.lines, for (final h in _cart.held) ...h.lines].any((l) => l.product.businessId != widget.business.id);
    if (other) _cart.reset();
    _customer.text = _cart.customer;
    _load();
    DataEvents.instance.salesVersion.addListener(_reloadStock);
    DataEvents.instance.cashVersion.addListener(_checkCash);
    _cart.addListener(_onCart);
  }

  @override
  void dispose() {
    DataEvents.instance.salesVersion.removeListener(_reloadStock);
    DataEvents.instance.cashVersion.removeListener(_checkCash);
    _cart.removeListener(_onCart);
    _pay.dispose();
    _search.dispose();
    _searchFocus.dispose();
    _customer.dispose();
    super.dispose();
  }

  void _onCart() {
    if (_customer.text != _cart.customer) _customer.text = _cart.customer;
    // Agregar algo nuevo cierra el aviso de la venta anterior
    if (_last != null && !_cart.isEmpty) setState(() => _last = null);
  }

  Future<void> _load() async {
    final products = await ProductRepository.instance.searchProducts('', businessId: widget.business.id);
    final customers = await CustomerRepository.instance.getCustomers(widget.business.id);
    final closed = await isCashClosedFor(widget.business);
    if (!mounted) return;
    setState(() {
      _products = products.where((p) => p.isActive).toList();
      _customers = [for (final c in customers) c.name];
      _cashClosed = closed;
      _loading = false;
    });
  }

  void _reloadStock() {
    if (mounted) _load();
  }

  Future<void> _checkCash() async {
    final closed = await isCashClosedFor(widget.business);
    if (mounted && closed != _cashClosed) setState(() => _cashClosed = closed);
  }

  // ---------------------------------------------------------------------------
  // Productos
  // ---------------------------------------------------------------------------

  List<String> get _categories {
    final set = <String>{for (final p in _products) if (p.category.trim().isNotEmpty) p.category.trim()};
    return set.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }

  List<Product> get _visible {
    final q = _search.text.trim().toLowerCase();
    return _products.where((p) {
      if (_category != null && p.category.trim() != _category) return false;
      if (q.isEmpty) return true;
      return p.name.toLowerCase().contains(q) || p.code.toLowerCase().contains(q);
    }).toList()
      // Lo que hay primero; lo agotado al final
      ..sort((a, b) {
        final out = (a.stock <= 0 ? 1 : 0) - (b.stock <= 0 ? 1 : 0);
        return out != 0 ? out : a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
  }

  Future<void> _add(Product p, [ProductVariant? v]) async {
    await SellScreen.sell(context, p, variant: v);
  }

  /// Enter en el buscador: el lector de código escribe el código y da Enter.
  /// Código exacto (o de una talla) → entra solo; si queda un solo resultado, ese.
  Future<void> _submitSearch(String text) async {
    final code = text.trim();
    if (code.isEmpty) return;
    final product = await ProductRepository.instance.getProductByCode(code, widget.business.id);
    if (!mounted) return;
    if (product != null) {
      final variant = product.variants.where((v) => v.skuOrBarcode == code).firstOrNull;
      await _add(product, variant);
      _search.clear();
      setState(() {});
      _searchFocus.requestFocus();
      return;
    }
    final visible = _visible;
    if (visible.length == 1) {
      await _add(visible.first);
      _search.clear();
      setState(() {});
      _searchFocus.requestFocus();
    } else if (visible.isEmpty) {
      AppToast.showWarning(context, 'No hay ningún producto con «$code»');
    }
  }

  Future<void> _scan() async {
    final code = await CodeReader.scan(context, title: 'Escanear para vender', caption: 'Vender');
    if (code != null && code.isNotEmpty) await _submitSearch(code);
  }

  // ---------------------------------------------------------------------------
  // Cobrar
  // ---------------------------------------------------------------------------

  Future<void> _charge({BuildContext? sheet}) async {
    if (_cart.isEmpty || _saving) return;
    final total = _cart.total;
    final method = _pay.method;
    final customer = _customer.text.trim();

    if (method == PaymentMethod.credit && customer.isEmpty) {
      AppToast.showWarning(context, 'Para fiar escribe a quién le fías.');
      return;
    }
    if (method == PaymentMethod.mixed && (_pay.mixedPaid - total).abs() > 0.5) {
      final diff = total - _pay.mixedPaid;
      AppToast.showWarning(
          context, diff > 0 ? 'Falta repartir ${CurrencyFormatter.format(diff)} del pago mixto.' : 'El pago mixto pasa el total por ${CurrencyFormatter.format(-diff)}.');
      return;
    }
    final received = _pay.received;
    if (method == PaymentMethod.cash && received != null && received < total) {
      AppToast.showWarning(context, 'Recibiste menos del total: faltan ${CurrencyFormatter.format(total - received)}.');
      return;
    }
    // Vender por debajo del costo: el cajero no puede; el dueño lo autoriza
    if (_cart.hasLoss) {
      if (!_manager) {
        AppToast.showError(context, 'Ese descuento deja pérdida. Solo el dueño o un administrador pueden autorizarlo.');
        return;
      }
      final ok = await AppDialog.confirm(
        context: context,
        title: 'Venta por debajo del costo',
        message: 'Con ese descuento pierdes ${CurrencyFormatter.format(_cart.loss)} frente a lo que te costó. ¿La autorizas?',
        confirmText: 'Sí, autorizar',
        destructive: true,
      );
      if (!ok || !mounted) return;
    }
    // Caja obligatoria si el negocio la usa
    if (!await CashGate.ensureOpen(context, business: widget.business, userName: _userName)) return;
    if (!mounted) return;

    setState(() => _saving = true);
    try {
      final units = _cart.units;
      final discount = _cart.discount;
      final sales = await SalesRepository.instance.recordMultiProductSale(
        businessId: widget.business.id,
        items: List.of(_cart.lines),
        paymentMethod: method,
        customerName: customer.isEmpty ? null : customer,
        discountAmount: discount,
        paymentSplit: method == PaymentMethod.mixed ? _pay.split : null,
      );
      final change = method == PaymentMethod.cash && received != null ? received - total : 0.0;
      // Fiado: lo que queda debiendo, para el tiquete
      double? debtAfter;
      if (method == PaymentMethod.credit) {
        final all = await CustomerRepository.instance.getCustomers(widget.business.id);
        debtAfter = all.where((c) => c.name.toLowerCase() == customer.toLowerCase()).firstOrNull?.debtBalance;
      }
      if (sheet != null && sheet.mounted) Navigator.pop(sheet);
      _cart.clear();
      _pay.reset();
      if (!mounted) return;
      setState(() {
        _saving = false;
        _cashClosed = false;
        _last = _LastSale(sales, discount, total, units, method, change, received, debtAfter);
      });
      // En el celular el tiquete «sale de la impresora» al cobrar; en el computador queda el aviso
      if (MediaQuery.sizeOf(context).width < SellScreen.wideFrom) {
        _last!.showTicket(context, justSold: true);
      } else {
        _searchFocus.requestFocus();
      }
    } on CashClosedException {
      if (mounted) setState(() => _saving = false);
      _checkCash();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppToast.showError(context, e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _quote() async {
    if (_cart.isEmpty) return;
    if (_cart.hasLoss && !_manager) {
      AppToast.showError(context, 'No se puede cotizar por debajo del costo.');
      return;
    }
    try {
      final q = await SalesRepository.instance.recordQuotation(
        businessId: widget.business.id,
        items: List.of(_cart.lines),
        customerName: _customer.text.trim().isEmpty ? null : _customer.text.trim(),
        discountAmount: _cart.discount,
      );
      _cart.clear();
      if (mounted) AppToast.showSuccess(context, 'Cotización ${q.quotationNumber} guardada en Ventas › Cotizaciones');
    } catch (e) {
      if (mounted) AppToast.showError(context, e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _clear() async {
    if (_cart.isEmpty) return;
    final ok = await AppDialog.confirm(
      context: context,
      title: 'Vaciar la cuenta',
      message: 'Se quitan los ${_cart.units} productos de esta venta.',
      confirmText: 'Vaciar',
      destructive: true,
    );
    if (ok) {
      _cart.clear();
      _pay.reset();
    }
  }

  Future<void> _editDiscount() async {
    final field = TextEditingController(text: _cart.discount > 0 ? _cart.discount.round().toString() : '');
    final value = await AppSheet.show<double>(
      context: context,
      title: 'Descuento a toda la venta',
      subtitle: 'Subtotal ${CurrencyFormatter.format(_cart.subtotal)}',
      builder: (ctx) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: field,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'Descuento', prefixText: '\$ '),
            onSubmitted: (t) => Navigator.pop(ctx, double.tryParse(t) ?? 0),
          ),
          const SizedBox(height: AppSpace.md),
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.sm,
            children: [
              for (final pct in [5, 10, 15, 20])
                ActionChip(label: Text('$pct %'), onPressed: () => Navigator.pop(ctx, (_cart.subtotal * pct / 100).roundToDouble())),
              if (_cart.maxSafeDiscount > 0)
                ActionChip(
                  label: Text('Máximo sin perder (${CurrencyFormatter.format(_cart.maxSafeDiscount)})'),
                  onPressed: () => Navigator.pop(ctx, _cart.maxSafeDiscount.floorToDouble()),
                ),
            ],
          ),
          const SizedBox(height: AppSpace.lg),
          Row(
            children: [
              Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(ctx, 0.0), child: const Text('Sin descuento'))),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.pop(ctx, double.tryParse(field.text) ?? 0),
                  child: const Text('Aplicar'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    field.dispose();
    if (value != null) _cart.setDiscount(value);
  }

  Future<void> _showHeld() async {
    await AppSheet.show<void>(
      context: context,
      title: 'Ventas en espera',
      subtitle: 'Toca una para seguir cobrándola. Lo que tengas en la cuenta pasa a espera.',
      builder: (ctx) => ListenableBuilder(
        listenable: _cart,
        builder: (ctx, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_cart.held.isEmpty) Text('No hay ventas en espera.', style: AppText.body(ctx, color: ctx.colors.inkMuted)),
            for (var i = 0; i < _cart.held.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.sm),
                child: ListTile(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.control), side: BorderSide(color: ctx.colors.line)),
                  title: Text(
                    _cart.held[i].customer.isEmpty ? 'Venta de las ${DateFormat('h:mm a', 'es_CO').format(_cart.held[i].at)}' : _cart.held[i].customer,
                    style: AppText.body(ctx, weight: FontWeight.w600),
                  ),
                  subtitle: Text('${_cart.held[i].units} productos', style: AppText.small(ctx)),
                  trailing: Text(CurrencyFormatter.format(_cart.held[i].total), style: AppText.body(ctx, weight: FontWeight.w700)),
                  onTap: () {
                    _cart.resume(i);
                    Navigator.pop(ctx);
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Pantalla
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f9): () => _charge(),
        const SingleActivator(LogicalKeyboardKey.f2): () => _searchFocus.requestFocus(),
        const SingleActivator(LogicalKeyboardKey.escape): _clear,
      },
      child: ColoredBox(
        color: c.paper,
        child: LayoutBuilder(
          builder: (context, box) {
            final wide = box.maxWidth >= SellScreen.wideFrom;
            if (wide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _productsPane(wide: true)),
                  Container(
                    width: math.min(400, box.maxWidth * 0.36),
                    decoration: BoxDecoration(color: c.surface, border: Border(left: BorderSide(color: c.line))),
                    child: _account(inSheet: false),
                  ),
                ],
              );
            }
            return Column(
              children: [
                Expanded(child: _productsPane(wide: false)),
                _bottomBar(),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _productsPane({required bool wide}) {
    final c = context.colors;
    final side = wide ? AppSpace.xl : AppSpace.md + 2;
    final products = _visible;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(side, wide ? AppSpace.lg : AppSpace.md, side, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_cashClosed) ...[_cashNotice(), const SizedBox(height: AppSpace.md)],
              if (_last != null && !wide) ...[_saleDone(), const SizedBox(height: AppSpace.md)],
              Row(
                children: [
                  Expanded(child: _searchField(wide)),
                  if (!wide) ...[
                    const SizedBox(width: AppSpace.sm),
                    SizedBox(
                      width: 48,
                      height: 48,
                      child: IconButton.filled(
                        tooltip: 'Escanear con la cámara',
                        style: IconButton.styleFrom(backgroundColor: c.ink, foregroundColor: c.surface),
                        onPressed: _scan,
                        icon: const Icon(Icons.qr_code_scanner_outlined),
                      ),
                    ),
                  ],
                  if (_cart.held.isNotEmpty) ...[
                    const SizedBox(width: AppSpace.sm),
                    OutlinedButton.icon(
                      onPressed: _showHeld,
                      icon: const Icon(Icons.pause_circle_outline, size: 18),
                      label: Text('En espera ${_cart.held.length}'),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: AppSpace.md),
              _categoryChips(),
              const SizedBox(height: AppSpace.md),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : products.isEmpty
                  ? _emptyProducts()
                  : wide
                      ? GridView.builder(
                          padding: EdgeInsets.fromLTRB(side, 0, side, AppSpace.xl),
                          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 200,
                            mainAxisExtent: 186,
                            crossAxisSpacing: AppSpace.md,
                            mainAxisSpacing: AppSpace.md,
                          ),
                          itemCount: products.length,
                          itemBuilder: (_, i) => _ProductTile(product: products[i], index: i, onTap: () => _add(products[i])),
                        )
                      : ListenableBuilder(
                          listenable: _cart,
                          builder: (context, _) => ListView.separated(
                            padding: EdgeInsets.fromLTRB(side, 0, side, AppSpace.lg),
                            itemCount: products.length,
                            separatorBuilder: (_, __) => const SizedBox(height: AppSpace.sm),
                            itemBuilder: (_, i) => _ProductRow(
                              product: products[i],
                              index: i,
                              inCart: _cart.lines.where((l) => l.product.id == products[i].id).fold<int>(0, (s, l) => s + l.quantity),
                              onTap: () => _add(products[i]),
                            ),
                          ),
                        ),
        ),
      ],
    );
  }

  Widget _searchField(bool wide) {
    final c = context.colors;
    return TextField(
      controller: _search,
      focusNode: _searchFocus,
      autofocus: wide,
      textInputAction: TextInputAction.done,
      onChanged: (_) => setState(() {}),
      onSubmitted: _submitSearch,
      style: AppText.bodyLarge(context),
      decoration: InputDecoration(
        hintText: wide ? 'Escanea el código o escribe el nombre del producto' : 'Buscar producto',
        prefixIcon: Icon(wide ? Icons.qr_code_scanner_outlined : Icons.search_outlined, color: c.inkMuted),
        suffixIcon: _search.text.isEmpty
            ? (wide ? Padding(
                padding: const EdgeInsets.only(right: AppSpace.md),
                child: Center(widthFactor: 1, child: Text('F2 · lector listo', style: AppText.caption(context))),
              ) : null)
            : IconButton(
                tooltip: 'Borrar',
                onPressed: () => setState(_search.clear),
                icon: const Icon(Icons.close_outlined, size: 18),
              ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.control + 2),
          borderSide: BorderSide(color: c.accent, width: 2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.control + 2),
          borderSide: BorderSide(color: c.accent, width: 2),
        ),
        contentPadding: EdgeInsets.symmetric(vertical: wide ? AppSpace.lg : AppSpace.md),
      ),
    );
  }

  Widget _categoryChips() {
    final cats = _categories;
    if (cats.length < 2) return const SizedBox.shrink();
    Widget chip(String label, String? value) {
      final selected = _category == value;
      return Padding(
        padding: const EdgeInsets.only(right: AppSpace.sm),
        child: ChoiceChip(
          label: Text(label),
          selected: selected,
          showCheckmark: false,
          onSelected: (_) => setState(() => _category = value),
        ),
      );
    }

    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [chip('Todas', null), for (final cat in cats) chip(cat, cat)],
      ),
    );
  }

  Widget _emptyProducts() {
    final c = context.colors;
    final searching = _search.text.trim().isNotEmpty || _category != null;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inventory_2_outlined, size: 40, color: c.inkFaint),
            const SizedBox(height: AppSpace.md),
            Text(searching ? 'No hay productos con «${_search.text.trim()}»' : 'Todavía no tienes productos',
                textAlign: TextAlign.center, style: AppText.title(context)),
            const SizedBox(height: AppSpace.xs),
            Text(
              searching ? 'Revisa cómo lo escribiste o cambia de categoría.' : 'Créalos en Productos para empezar a vender.',
              textAlign: TextAlign.center,
              style: AppText.body(context, color: c.inkMuted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cashNotice() {
    final t = ToneColors.of(context, AppTone.warning);
    return Container(
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(color: t.soft, borderRadius: BorderRadius.circular(AppRadius.control)),
      child: Row(
        children: [
          Icon(Icons.point_of_sale_outlined, color: t.strong),
          const SizedBox(width: AppSpace.md - 2),
          Expanded(
            child: Text('La caja está cerrada. Ábrela para poder cobrar.',
                style: AppText.body(context, weight: FontWeight.w600, color: context.colors.ink)),
          ),
          FilledButton(
            onPressed: () async {
              await CashGate.ensureOpen(context, business: widget.business, userName: _userName);
              _checkCash();
            },
            child: const Text('Abrir caja'),
          ),
        ],
      ),
    );
  }

  /// «✓ Venta registrada · 5 productos · \$ 9.600 · Efectivo» con «Enviar recibo»
  Widget _saleDone() {
    final last = _last!;
    final t = ToneColors.of(context, AppTone.success);
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.xs, AppSpace.sm),
        decoration: BoxDecoration(color: t.soft, borderRadius: BorderRadius.circular(AppRadius.control)),
        child: Row(
          children: [
            Icon(Icons.check_circle_outline, color: t.text),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Venta registrada · ${last.units} ${last.units == 1 ? 'producto' : 'productos'} · '
                    '${CurrencyFormatter.format(last.total)} · ${PaymentMethod.label(last.method)}',
                    style: AppText.small(context, weight: FontWeight.w600, color: t.text),
                  ),
                  if (last.change > 0)
                    Text('Vuelto: ${CurrencyFormatter.format(last.change)}', style: AppText.small(context, weight: FontWeight.w700, color: t.text)),
                ],
              ),
            ),
            TextButton(
              onPressed: () => last.showTicket(context),
              child: const Text('Ver recibo'),
            ),
          ],
        ),
      ),
    );
  }

  /// Celular: «3 productos · toca para ver», el total y Cobrar
  Widget _bottomBar() {
    final c = context.colors;
    return ListenableBuilder(
      listenable: _cart,
      builder: (context, _) {
        if (_cart.isEmpty) return const SizedBox.shrink();
        return Material(
          color: c.surface,
          child: Container(
            decoration: BoxDecoration(border: Border(top: BorderSide(color: c.line))),
            padding: EdgeInsets.fromLTRB(AppSpace.md + 2, AppSpace.sm + 2, AppSpace.md + 2, AppSpace.md + MediaQuery.paddingOf(context).bottom),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: _openAccountSheet,
                    borderRadius: BorderRadius.circular(AppRadius.control),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${_cart.units} ${_cart.units == 1 ? 'producto' : 'productos'} · toca para ver', style: AppText.caption(context)),
                        Text(CurrencyFormatter.format(_cart.total), style: AppText.heading(context)),
                      ],
                    ),
                  ),
                ),
                SizedBox(
                  height: 52,
                  child: FilledButton(onPressed: _openAccountSheet, child: const Text('Cobrar')),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openAccountSheet() => AppSheet.show<void>(
        context: context,
        title: 'Cuenta',
        builder: (ctx) => _account(inSheet: true, sheet: ctx),
      );

  // ---------------------------------------------------------------------------
  // La cuenta (al lado en el computador, en una hoja en el celular)
  // ---------------------------------------------------------------------------

  Widget _account({required bool inSheet, BuildContext? sheet}) {
    return ListenableBuilder(
      listenable: Listenable.merge([_cart, _pay]),
      builder: (context, _) {
        final c = context.colors;
        final lines = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_cart.isEmpty)
              Container(
                padding: const EdgeInsets.symmetric(vertical: AppSpace.xl, horizontal: AppSpace.lg),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.control + 2),
                  border: Border.all(color: c.lineStrong),
                ),
                child: Text('Toca un producto o escanéalo para agregarlo.',
                    textAlign: TextAlign.center, style: AppText.body(context, color: c.inkMuted)),
              ),
            for (var i = 0; i < _cart.lines.length; i++) _line(i),
          ],
        );
        final footer = _cart.isEmpty ? const SizedBox.shrink() : _checkout(sheet: sheet);

        if (inSheet) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [lines, const SizedBox(height: AppSpace.md), footer]);
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpace.lg + 2, AppSpace.lg, AppSpace.sm, AppSpace.sm),
              child: Row(
                children: [
                  Expanded(child: Text('Cuenta', style: AppText.heading(context))),
                  if (!_cart.isEmpty) TextButton(onPressed: _clear, child: const Text('Vaciar (Esc)')),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(AppSpace.lg + 2, 0, AppSpace.lg + 2, AppSpace.lg),
                children: [
                  if (_last != null) ...[_saleDone(), const SizedBox(height: AppSpace.md)],
                  lines,
                  const SizedBox(height: AppSpace.md),
                  footer,
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _line(int i) {
    final c = context.colors;
    final l = _cart.lines[i];
    void set(int q) {
      final problem = _cart.setQuantity(i, q);
      if (problem != null) AppToast.showWarning(context, problem);
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.sm + 2),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.line))),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.displayName, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.body(context, weight: FontWeight.w600)),
                Text('${CurrencyFormatter.format(l.unitPrice)} c/u', style: AppText.caption(context)),
              ],
            ),
          ),
          const SizedBox(width: AppSpace.sm),
          Container(
            decoration: BoxDecoration(border: Border.all(color: c.line), borderRadius: BorderRadius.circular(AppRadius.tile)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _qtyButton(l.quantity == 1 ? Icons.delete_outline : Icons.remove_outlined, l.quantity == 1 ? 'Quitar' : 'Quitar uno',
                    () => set(l.quantity - 1)),
                SizedBox(
                  width: 26,
                  child: Text('${l.quantity}', textAlign: TextAlign.center, style: AppText.body(context, weight: FontWeight.w700)),
                ),
                _qtyButton(Icons.add_outlined, 'Agregar uno', () => set(l.quantity + 1)),
              ],
            ),
          ),
          const SizedBox(width: AppSpace.sm),
          SizedBox(
            width: 84,
            child: Text(CurrencyFormatter.format(l.subtotal),
                textAlign: TextAlign.right, style: AppText.amount(context, size: AppText.sizeBody)),
          ),
        ],
      ),
    );
  }

  Widget _qtyButton(IconData icon, String tooltip, VoidCallback onTap) => SizedBox(
        width: 34,
        height: 34,
        child: IconButton(
          tooltip: tooltip,
          padding: EdgeInsets.zero,
          iconSize: 17,
          onPressed: onTap,
          icon: Icon(icon),
        ),
      );

  Widget _checkout({BuildContext? sheet}) {
    final c = context.colors;
    final total = _cart.total;
    final method = _pay.method;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _customerField(),
        const SizedBox(height: AppSpace.md),
        _totalRow('Subtotal', CurrencyFormatter.format(_cart.subtotal)),
        InkWell(
          onTap: _editDiscount,
          borderRadius: BorderRadius.circular(AppRadius.small),
          child: _totalRow(
            'Descuento a toda la venta',
            _cart.discount > 0 ? '− ${CurrencyFormatter.format(_cart.discount)}' : 'Agregar',
            link: _cart.discount <= 0,
            danger: _cart.hasLoss,
          ),
        ),
        if (_cart.hasLoss)
          Text('Con ese descuento pierdes ${CurrencyFormatter.format(_cart.loss)}.',
              style: AppText.caption(context, weight: FontWeight.w600, color: c.danger)),
        const SizedBox(height: AppSpace.sm),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(child: Text('Total', style: AppText.title(context))),
            Text(CurrencyFormatter.format(total), style: AppText.amount(context, size: AppText.sizeDisplay + 4, weight: FontWeight.w800)),
          ],
        ),
        const SizedBox(height: AppSpace.md),
        _methods(),
        if (method == PaymentMethod.cash) ...[const SizedBox(height: AppSpace.md), _cashBox(total)],
        if (method == PaymentMethod.mixed) ...[const SizedBox(height: AppSpace.md), _mixedBox(total)],
        if (method == PaymentMethod.credit && _customer.text.trim().isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: AppSpace.sm),
            child: Text('Para fiar, escribe arriba a quién.', style: AppText.small(context, color: c.warning)),
          ),
        const SizedBox(height: AppSpace.md),
        SizedBox(
          height: 56,
          child: FilledButton(
            onPressed: _saving ? null : () => _charge(sheet: sheet),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(_saving ? 'Cobrando…' : 'Cobrar ${CurrencyFormatter.format(total)}',
                    style: AppText.bodyLarge(context, weight: FontWeight.w700, color: c.onAccent)),
                if (sheet == null) ...[
                  const SizedBox(width: AppSpace.sm),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      border: Border.all(color: c.onAccent.withValues(alpha: 0.5)),
                      borderRadius: BorderRadius.circular(AppRadius.small - 2),
                    ),
                    child: Text('F9', style: AppText.caption(context, color: c.onAccent)),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpace.sm),
        Row(
          children: [
            Expanded(
              child: TextButton.icon(
                onPressed: () {
                  _cart.hold();
                  if (sheet != null) Navigator.pop(sheet);
                },
                icon: const Icon(Icons.pause_circle_outline, size: 18),
                label: const Text('Para después'),
              ),
            ),
            Expanded(
              child: TextButton.icon(
                onPressed: () {
                  if (sheet != null) Navigator.pop(sheet);
                  _quote();
                },
                icon: const Icon(Icons.request_quote_outlined, size: 18),
                label: const Text('Cotizar'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _totalRow(String label, String value, {bool link = false, bool danger = false}) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label, style: AppText.body(context, color: c.inkMuted))),
          Text(value,
              style: AppText.body(context,
                  weight: link ? FontWeight.w600 : FontWeight.w500, color: danger ? c.danger : (link ? c.accent : c.inkMuted))),
        ],
      ),
    );
  }

  Widget _customerField() {
    final credit = _pay.method == PaymentMethod.credit;
    return Autocomplete<String>(
      optionsBuilder: (v) {
        final q = v.text.trim().toLowerCase();
        if (q.isEmpty) return const Iterable<String>.empty();
        return _customers.where((n) => n.toLowerCase().contains(q)).take(5);
      },
      onSelected: _cart.setCustomer,
      fieldViewBuilder: (context, controller, focus, onSubmit) {
        if (controller.text != _customer.text) controller.text = _customer.text;
        return TextField(
          controller: controller,
          focusNode: focus,
          textCapitalization: TextCapitalization.words,
          onChanged: (t) {
            _customer.text = t;
            _cart.customer = t;
            _pay.changed();
          },
          decoration: InputDecoration(
            isDense: true,
            prefixIcon: const Icon(Icons.person_outline, size: 20),
            hintText: credit ? 'Cliente (obligatorio para fiar)' : 'Cliente (opcional)',
          ),
        );
      },
    );
  }

  Widget _methods() {
    return LayoutBuilder(builder: (context, box) {
      const cols = 3;
      const gap = AppSpace.sm - 2;
      final w = (box.maxWidth - gap * (cols - 1)) / cols;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final m in PaymentMethod.forSale)
            SizedBox(
              width: w,
              height: 42,
              child: _choice(PaymentMethod.label(m), _pay.method == m, () => _pay.set(m), icon: PaymentMethod.icon(m)),
            ),
        ],
      );
    });
  }

  /// Botón de elección: el elegido en tinta oscura (como los chips del diseño)
  Widget _choice(String label, bool selected, VoidCallback onTap, {IconData? icon}) {
    final c = context.colors;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? c.ink : c.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.tile),
          side: BorderSide(color: selected ? c.ink : c.line),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.tile),
          onTap: onTap,
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[Icon(icon, size: 16, color: selected ? c.surface : c.inkMuted), const SizedBox(width: 6)],
                Flexible(
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.small(context, weight: FontWeight.w600, color: selected ? c.surface : c.ink)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Efectivo: «Recibí» con atajos de billetes y el vuelto en grande
  Widget _cashBox(double total) {
    final c = context.colors;
    final bills = <double>{
      for (final step in [10000.0, 20000.0, 50000.0, 100000.0])
        if ((total / step).ceil() * step > total) (total / step).ceil() * step,
    }.toList()
      ..sort();
    final received = _pay.received;
    final change = received == null ? 0.0 : math.max(0.0, received - total);
    return Container(
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(color: c.paper, borderRadius: BorderRadius.circular(AppRadius.control)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Recibí', style: AppText.small(context)),
          const SizedBox(height: AppSpace.sm),
          Wrap(
            spacing: AppSpace.sm - 2,
            runSpacing: AppSpace.sm - 2,
            children: [
              SizedBox(height: 36, width: 86, child: _choice('Exacto', received == null, () => _pay.receive(null))),
              for (final b in bills.take(3))
                SizedBox(height: 36, width: 96, child: _choice(CurrencyFormatter.format(b), received == b, () => _pay.receive(b))),
              SizedBox(
                height: 36,
                width: 110,
                child: TextField(
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (t) => _pay.receive(t.isEmpty ? null : double.tryParse(t)),
                  style: AppText.small(context),
                  decoration: const InputDecoration(isDense: true, hintText: 'Otro valor', contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 9)),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(child: Text('Vuelto', style: AppText.body(context, weight: FontWeight.w600))),
              Text(
                received != null && received < total ? 'Faltan ${CurrencyFormatter.format(total - received)}' : CurrencyFormatter.format(change),
                style: AppText.amount(context,
                    size: AppText.sizeHeading + 2, color: received != null && received < total ? c.danger : c.success),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Mixto: cuánto entra por cada medio y cuánto falta repartir
  Widget _mixedBox(double total) {
    final c = context.colors;
    final left = total - _pay.mixedPaid;
    return Container(
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(color: c.paper, borderRadius: BorderRadius.circular(AppRadius.control)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final m in PaymentMethod.forMixed)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.sm),
              child: Row(
                children: [
                  Icon(PaymentMethod.icon(m), size: 18, color: c.inkMuted),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(child: Text(PaymentMethod.label(m), style: AppText.body(context))),
                  SizedBox(
                    width: 130,
                    child: TextField(
                      controller: _pay.mixed[m],
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      onChanged: (_) => _pay.changed(),
                      textAlign: TextAlign.right,
                      decoration: InputDecoration(
                        isDense: true,
                        prefixText: '\$ ',
                        hintText: '0',
                        suffixIcon: left > 0.5
                            ? IconButton(
                                tooltip: 'Poner aquí lo que falta',
                                iconSize: 16,
                                onPressed: () {
                                  final current = double.tryParse(_pay.mixed[m]!.text) ?? 0;
                                  _pay.mixed[m]!.text = (current + left).round().toString();
                                  _pay.changed();
                                },
                                icon: const Icon(Icons.add_outlined),
                              )
                            : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Text(
            left.abs() <= 0.5
                ? 'Repartido completo'
                : left > 0
                    ? 'Falta repartir ${CurrencyFormatter.format(left)}'
                    : 'Pasa el total por ${CurrencyFormatter.format(-left)}',
            textAlign: TextAlign.right,
            style: AppText.small(context, weight: FontWeight.w600, color: left.abs() <= 0.5 ? c.success : c.warning),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Productos
// -----------------------------------------------------------------------------

/// Etiqueta de stock: «62 u.», «Quedan 5» o «Sin stock»
StatusPill _stockPill(Product p) {
  if (p.stock <= 0) return const StatusPill('Sin stock', tone: AppTone.danger, compact: true);
  if (p.stock <= p.minStock) return StatusPill('Quedan ${p.stock}', tone: AppTone.warning, compact: true);
  return StatusPill('${p.stock} u.', tone: AppTone.neutral, compact: true);
}

/// Foto del producto, o sus iniciales sobre un color suave
class _ProductPicture extends StatelessWidget {
  final Product product;
  final int index;
  final double? width;
  final double height;

  const _ProductPicture({required this.product, required this.index, this.width, required this.height});

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppRadius.tile);
    if ((product.photoPath ?? '').isNotEmpty) {
      return ProductImageView(imagePath: product.photoPath, width: width, height: height, borderRadius: radius);
    }
    const tones = [AppTone.warning, AppTone.info, AppTone.accent, AppTone.success, AppTone.danger, AppTone.neutral];
    final t = ToneColors.of(context, tones[product.name.hashCode.abs() % tones.length]);
    final words = product.name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).take(2);
    return ExcludeSemantics(
      child: Container(
        width: width,
        height: height,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: t.soft, borderRadius: radius),
        child: Text(words.map((w) => w[0].toUpperCase()).join(), style: AppText.heading(context, color: context.colors.inkMuted)),
      ),
    );
  }
}

/// Computador: tarjeta de la cuadrícula
class _ProductTile extends StatelessWidget {
  final Product product;
  final int index;
  final VoidCallback onTap;

  const _ProductTile({required this.product, required this.index, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final out = product.stock <= 0;
    final radius = BorderRadius.circular(AppRadius.card - 2);
    return Opacity(
      opacity: out ? 0.55 : 1,
      child: Semantics(
        button: true,
        enabled: !out,
        label: '${product.name}, ${CurrencyFormatter.format(product.salePrice)}, ${out ? 'sin stock' : '${product.stock} disponibles'}',
        excludeSemantics: true,
        child: Material(
          color: c.surface,
          shape: RoundedRectangleBorder(borderRadius: radius, side: BorderSide(color: c.line)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: out ? null : onTap,
            child: Padding(
              padding: const EdgeInsets.all(AppSpace.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ProductPicture(product: product, index: index, width: double.infinity, height: 72),
                  const SizedBox(height: AppSpace.sm),
                  Expanded(
                    child: Text(product.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.body(context, weight: FontWeight.w600)),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: Text(CurrencyFormatter.format(product.salePrice),
                            maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.amount(context, size: AppText.sizeTitle, weight: FontWeight.w800)),
                      ),
                      _stockPill(product),
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

/// Celular: renglón grande, fácil de tocar; muestra cuántos van en la cuenta
class _ProductRow extends StatelessWidget {
  final Product product;
  final int index;
  final int inCart;
  final VoidCallback onTap;

  const _ProductRow({required this.product, required this.index, required this.inCart, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final out = product.stock <= 0;
    final radius = BorderRadius.circular(AppRadius.card - 2);
    return Opacity(
      opacity: out ? 0.55 : 1,
      child: Semantics(
        button: true,
        enabled: !out,
        label: '${product.name}, ${CurrencyFormatter.format(product.salePrice)}${inCart > 0 ? ', $inCart en la cuenta' : ''}',
        excludeSemantics: true,
        child: Material(
          color: c.surface,
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: BorderSide(color: inCart > 0 ? c.accent : c.line, width: inCart > 0 ? 2 : 1),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: out ? null : onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm + 2),
              child: Row(
                children: [
                  _ProductPicture(product: product, index: index, width: 48, height: 48),
                  const SizedBox(width: AppSpace.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(product.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.bodyLarge(context, weight: FontWeight.w600)),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Text(CurrencyFormatter.format(product.salePrice),
                                style: AppText.amount(context, size: AppText.sizeBodyLarge, weight: FontWeight.w800)),
                            const SizedBox(width: AppSpace.sm),
                            _stockPill(product),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (inCart > 0)
                    Container(
                      constraints: const BoxConstraints(minWidth: 30),
                      height: 30,
                      padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: c.accent, borderRadius: BorderRadius.circular(AppRadius.pill)),
                      child: Text('$inCart', style: AppText.body(context, weight: FontWeight.w800, color: c.onAccent)),
                    )
                  else if (!out)
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(border: Border.all(color: c.line), borderRadius: BorderRadius.circular(AppRadius.tile)),
                      child: Icon(Icons.add_outlined, color: c.inkMuted),
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
