import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/theme/app_theme.dart';
import '../core/theme/app_tokens.dart';
import '../core/utils/currency_formatter.dart';
import '../features/store/data/online_store_service.dart';

/// Nombre de la tienda en la dirección: /tienda/<slug> o /tienda/?t=<slug>
/// (el 404 del sitio convierte la primera en la segunda)
String? slugFromUri(Uri uri) {
  final fromQuery = uri.queryParameters['t']?.trim().toLowerCase();
  if (fromQuery != null && fromQuery.isNotEmpty) return fromQuery;
  final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  final i = segments.indexOf('tienda');
  if (i >= 0 && i + 1 < segments.length) return segments[i + 1].toLowerCase();
  return null;
}

/// Página de la tienda: productos, carrito y pedido por WhatsApp
class StorePage extends StatefulWidget {
  final String? slug;

  /// De dónde sale la tienda (por defecto, el servidor; las pruebas pasan la suya)
  final Future<PublicStore?> Function(String slug)? loader;

  const StorePage({super.key, required this.slug, this.loader});

  @override
  State<StorePage> createState() => _StorePageState();
}

class _StorePageState extends State<StorePage> {
  PublicStore? _store;
  bool _loading = true;
  String? _error;

  /// Cantidad por id de producto
  final Map<String, int> _cart = {};
  String _query = '';
  String? _category;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final slug = widget.slug;
    if (slug == null) {
      setState(() => _loading = false);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final store = await (widget.loader ?? OnlineStoreService.instance.getPublic)(slug);
      if (mounted) setState(() => _store = store);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<CartLine> get _lines => [
        for (final p in _store?.products ?? const <StoreProduct>[])
          if ((_cart[p.id] ?? 0) > 0) CartLine(p, _cart[p.id]!),
      ];

  void _setQty(StoreProduct p, int qty) {
    final max = p.stock ?? 999;
    setState(() {
      if (qty <= 0) {
        _cart.remove(p.id);
      } else {
        _cart[p.id] = qty > max ? max : qty;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final store = _store;
    if (store == null) {
      return _MessagePage(
        text: _error ??
            (widget.slug == null
                ? 'Abre el enlace de la tienda que te compartieron.'
                : 'Esta tienda no está disponible en este momento.'),
        onRetry: _error != null ? _load : null,
      );
    }
    final accent = AppPalette.fromHex(store.color) ?? AppPalette.brand;
    return Theme(
      data: AppTheme.build(Brightness.light, accent: accent),
      child: Builder(builder: (context) => _storeView(context, store)),
    );
  }

  Widget _storeView(BuildContext context, PublicStore store) {
    final c = context.colors;
    final q = _query.toLowerCase();
    final visible = store.products
        .where((p) => (_category == null || p.category == _category) && (q.isEmpty || p.name.toLowerCase().contains(q)))
        .toList();
    final lines = _lines;
    final width = MediaQuery.of(context).size.width;
    final side = width > 1000 ? (width - 960) / 2 : AppSpace.lg;
    final columns = width >= 900 ? 4 : (width >= 600 ? 3 : 2);

    return Scaffold(
      backgroundColor: c.paper,
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _header(c, store, side)),
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(side, AppSpace.md, side, 0),
              child: TextField(
                onChanged: (v) => setState(() => _query = v.trim()),
                decoration: const InputDecoration(hintText: 'Buscar productos', prefixIcon: Icon(Icons.search_rounded)),
              ),
            ),
          ),
          if (store.categories.length > 1)
            SliverToBoxAdapter(
              child: SizedBox(
                height: 56,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: EdgeInsets.fromLTRB(side, AppSpace.sm, side, 0),
                  children: [
                    _chip('Todo', _category == null, () => setState(() => _category = null)),
                    for (final cat in store.categories)
                      _chip(cat, _category == cat, () => setState(() => _category = cat)),
                  ],
                ),
              ),
            ),
          if (visible.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(AppSpace.xxl),
                child: Text(
                  store.products.isEmpty ? 'Esta tienda todavía no tiene productos disponibles.' : 'No hay productos con ese nombre.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: c.inkMuted),
                ),
              ),
            )
          else
            SliverPadding(
              padding: EdgeInsets.fromLTRB(side, AppSpace.md, side, AppSpace.md),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisSpacing: AppSpace.md,
                  crossAxisSpacing: AppSpace.md,
                  childAspectRatio: 0.62,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, i) => _ProductCard(
                    product: visible[i],
                    currency: store.currency,
                    quantity: _cart[visible[i].id] ?? 0,
                    onChanged: (qty) => _setQty(visible[i], qty),
                  ),
                  childCount: visible.length,
                ),
              ),
            ),
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(side, AppSpace.lg, side, lines.isEmpty ? AppSpace.xl : 110),
              child: Text('Tienda hecha con Stockealo',
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: c.inkFaint)),
            ),
          ),
        ],
      ),
      bottomSheet: lines.isEmpty ? null : _cartBar(c, store, lines, side),
    );
  }

  Widget _header(StockealoColors c, PublicStore store, double side) {
    return Container(
      color: c.accent,
      padding: EdgeInsets.fromLTRB(side, AppSpace.xl, side, AppSpace.xl),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(AppRadius.control)),
            alignment: Alignment.center,
            child: store.logoUrl != null && store.logoUrl!.startsWith('https://')
                ? Image.network(store.logoUrl!, fit: BoxFit.cover, width: 56, height: 56,
                    errorBuilder: (_, __, ___) => _initial(c, store))
                : _initial(c, store),
          ),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(store.businessName,
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: c.onAccent)),
                if (store.welcome?.isNotEmpty == true) ...[
                  const SizedBox(height: AppSpace.xs),
                  Text(store.welcome!, style: TextStyle(fontSize: 14, color: c.onAccent)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _initial(StockealoColors c, PublicStore store) => Text(
        store.businessName.trim().isEmpty ? 'T' : store.businessName.trim()[0].toUpperCase(),
        style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: c.accent),
      );

  Widget _chip(String label, bool selected, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(right: AppSpace.sm),
        child: ChoiceChip(label: Text(label), selected: selected, onSelected: (_) => onTap()),
      );

  Widget _cartBar(StockealoColors c, PublicStore store, List<CartLine> lines, double side) {
    final units = lines.fold<int>(0, (s, l) => s + l.quantity);
    final total = lines.fold<double>(0, (s, l) => s + l.subtotal);
    return Container(
      decoration: BoxDecoration(color: c.surface, border: Border(top: BorderSide(color: c.line))),
      padding: EdgeInsets.fromLTRB(side, AppSpace.md, side, AppSpace.md),
      child: SafeArea(
        top: false,
        child: FilledButton.icon(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          onPressed: () => _openCart(store),
          icon: const Icon(Icons.shopping_bag_outlined),
          label: Text('Ver pedido · $units · ${CurrencyFormatter.formatIn(total, store.currency)}'),
        ),
      ),
    );
  }

  Future<void> _openCart(PublicStore store) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      backgroundColor: Colors.transparent,
      builder: (_) => Theme(
        data: Theme.of(context),
        child: _CartSheet(
          store: store,
          lines: () => _lines,
          onChanged: _setQty,
        ),
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  final StoreProduct product;
  final String currency;
  final int quantity;
  final ValueChanged<int> onChanged;

  const _ProductCard({required this.product, required this.currency, required this.quantity, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final maxed = product.stock != null && quantity >= product.stock!;
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: quantity > 0 ? c.accent : c.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Container(
              color: c.surfaceMuted,
              child: product.imageUrl != null
                  ? Image.network(product.imageUrl!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _placeholder(c))
                  : _placeholder(c),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md, AppSpace.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(product.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: FontWeight.w600, color: c.ink)),
                const SizedBox(height: 2),
                Text(CurrencyFormatter.formatIn(product.price, currency),
                    style: AppText.amount(context, size: 16, color: c.accent)),
                if (product.stock != null)
                  Text('${product.stock} disponibles', style: TextStyle(fontSize: 12, color: c.inkMuted)),
                const SizedBox(height: AppSpace.sm),
                if (quantity == 0)
                  OutlinedButton.icon(
                    onPressed: () => onChanged(1),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Agregar'),
                  )
                else
                  _Stepper(quantity: quantity, canAdd: !maxed, onChanged: onChanged),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _placeholder(StockealoColors c) => Center(child: Icon(Icons.inventory_2_outlined, size: 32, color: c.inkFaint));
}

class _Stepper extends StatelessWidget {
  final int quantity;
  final bool canAdd;
  final ValueChanged<int> onChanged;

  const _Stepper({required this.quantity, required this.canAdd, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(color: c.surfaceMuted, borderRadius: BorderRadius.circular(AppRadius.pill)),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Quitar uno',
            onPressed: () => onChanged(quantity - 1),
            icon: Icon(quantity == 1 ? Icons.delete_outline_rounded : Icons.remove_rounded, size: 20),
          ),
          Expanded(
            child: Text('$quantity',
                textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w700, color: c.ink)),
          ),
          IconButton(
            tooltip: 'Agregar uno',
            onPressed: canAdd ? () => onChanged(quantity + 1) : null,
            icon: const Icon(Icons.add_rounded, size: 20),
          ),
        ],
      ),
    );
  }
}

/// Resumen del pedido: cantidades, nombre, nota y botón de WhatsApp
class _CartSheet extends StatefulWidget {
  final PublicStore store;
  final List<CartLine> Function() lines;
  final void Function(StoreProduct, int) onChanged;

  const _CartSheet({required this.store, required this.lines, required this.onChanged});

  @override
  State<_CartSheet> createState() => _CartSheetState();
}

class _CartSheetState extends State<_CartSheet> {
  final _nameController = TextEditingController();
  final _noteController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _send(List<CartLine> lines) async {
    final text = OnlineStoreService.orderMessage(
      businessName: widget.store.businessName,
      lines: lines,
      currency: widget.store.currency,
      customerName: _nameController.text,
      note: _noteController.text,
    );
    final uri = Uri.parse('https://wa.me/${widget.store.whatsapp}?text=${Uri.encodeComponent(text)}');
    await launchUrl(uri, mode: LaunchMode.externalApplication, webOnlyWindowName: '_blank');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final lines = widget.lines();
    final total = lines.fold<double>(0, (s, l) => s + l.subtotal);
    String money(num v) => CurrencyFormatter.formatIn(v, widget.store.currency);
    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 560, maxHeight: MediaQuery.of(context).size.height * 0.9),
        child: Container(
          decoration: BoxDecoration(
            color: c.paper,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
          ),
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: SafeArea(
            top: false,
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(AppSpace.lg),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text('Tu pedido', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: c.ink)),
                    ),
                    IconButton(
                      tooltip: 'Cerrar',
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(Icons.close_rounded, color: c.inkMuted),
                    ),
                  ],
                ),
                if (lines.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppSpace.xl),
                    child: Text('Tu pedido está vacío.', textAlign: TextAlign.center, style: TextStyle(color: c.inkMuted)),
                  ),
                for (final l in lines)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(l.product.name, style: TextStyle(fontWeight: FontWeight.w600, color: c.ink)),
                              Text(money(l.subtotal), style: TextStyle(fontSize: 13, color: c.inkMuted)),
                            ],
                          ),
                        ),
                        SizedBox(
                          width: 140,
                          child: _Stepper(
                            quantity: l.quantity,
                            canAdd: l.product.stock == null || l.quantity < l.product.stock!,
                            onChanged: (q) => setState(() => widget.onChanged(l.product, q)),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (lines.isNotEmpty) ...[
                  Divider(height: AppSpace.xl, color: c.line),
                  Row(
                    children: [
                      Expanded(child: Text('Total', style: TextStyle(fontSize: 16, color: c.ink))),
                      Text(money(total), style: AppText.amount(context, size: 20, color: c.ink)),
                    ],
                  ),
                  const SizedBox(height: AppSpace.lg),
                  TextField(
                    controller: _nameController,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Tu nombre (opcional)'),
                  ),
                  const SizedBox(height: AppSpace.md),
                  TextField(
                    controller: _noteController,
                    textCapitalization: TextCapitalization.sentences,
                    maxLines: 2,
                    minLines: 1,
                    decoration: const InputDecoration(
                      labelText: 'Nota (opcional)',
                      hintText: 'Ej.: dirección de entrega, forma de pago',
                    ),
                  ),
                  const SizedBox(height: AppSpace.lg),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                    onPressed: () => _send(lines),
                    icon: const Icon(Icons.chat_rounded),
                    label: const Text('Enviar pedido por WhatsApp'),
                  ),
                  const SizedBox(height: AppSpace.sm),
                  Text(
                    'Se abre WhatsApp con tu pedido escrito. La tienda te confirma el precio final y la entrega.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: c.inkMuted),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Tienda no encontrada, apagada o sin conexión
class _MessagePage extends StatelessWidget {
  final String text;
  final VoidCallback? onRetry;

  const _MessagePage({required this.text, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.paper,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.storefront_outlined, size: 48, color: c.inkFaint),
              const SizedBox(height: AppSpace.md),
              Text(text, textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: c.ink)),
              if (onRetry != null) ...[
                const SizedBox(height: AppSpace.lg),
                OutlinedButton(onPressed: onRetry, child: const Text('Reintentar')),
              ],
              const SizedBox(height: AppSpace.xl),
              Text('Tienda hecha con Stockealo', style: TextStyle(fontSize: 12, color: c.inkFaint)),
            ],
          ),
        ),
      ),
    );
  }
}
