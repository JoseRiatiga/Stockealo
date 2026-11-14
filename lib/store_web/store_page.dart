import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/design/app_dialog.dart';
import '../core/design/color_swatch_dot.dart';
import '../core/design/status_pill.dart';
import '../core/services/maintenance_service.dart';
import '../core/services/supabase_service.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/app_tokens.dart';
import '../core/utils/currency_formatter.dart';
import '../core/widgets/maintenance_gate.dart';
import '../features/sales/presentation/widgets/sale_document.dart';
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

/// Lo que se está filtrando en la tienda
class StoreFilters {
  String query = '';
  String? category;
  String? size;
  String? colorHex;
  RangeValues? price;
  bool onlyOffers = false;

  bool get any => category != null || size != null || colorHex != null || price != null || onlyOffers;

  void clear() {
    category = size = colorHex = null;
    price = null;
    onlyOffers = false;
  }

  bool matches(StoreProduct p) {
    final q = query.trim().toLowerCase();
    if (q.isNotEmpty && !p.name.toLowerCase().contains(q) && !p.category.toLowerCase().contains(q)) return false;
    if (category != null && p.category != category) return false;
    if (size != null && !p.sizes.contains(size)) return false;
    if (colorHex != null && !p.colorHexes.contains(colorHex)) return false;
    if (onlyOffers && !p.onOffer) return false;
    final r = price;
    if (r != null && (p.price < r.start || p.price > r.end)) return false;
    return true;
  }
}

/// Página de la tienda: productos, carrito y pedido por WhatsApp. Tiene dos
/// plantillas (diseño aprobado, re-diseño 0.13.0): Clásica (clara, con el color
/// del negocio arriba) y Moda (oscura, portada grande y filtros a un lado).
class StorePage extends StatefulWidget {
  final String? slug;

  /// De dónde sale la tienda (por defecto, el servidor; las pruebas pasan la suya)
  final Future<PublicStore?> Function(String slug)? loader;

  /// Estado del mantenimiento (por defecto, el servidor; las pruebas pasan el suyo)
  final Future<MaintenanceState> Function()? maintenanceLoader;

  const StorePage({super.key, required this.slug, this.loader, this.maintenanceLoader});

  static Future<MaintenanceState> _serverMaintenance() async {
    try {
      final data = await SupabaseService.instance.client?.rpc('get_maintenance');
      return data is Map ? MaintenanceState.fromJson(Map<String, dynamic>.from(data)) : MaintenanceState.none;
    } catch (_) {
      return MaintenanceState.none; // si no se sabe, la tienda abre
    }
  }

  @override
  State<StorePage> createState() => _StorePageState();
}

class _StorePageState extends State<StorePage> {
  PublicStore? _store;
  MaintenanceState _maintenance = MaintenanceState.none;
  bool _loading = true;
  String? _error;

  /// Renglones del pedido por producto y talla o color
  final Map<String, CartLine> _cart = {};
  final _filters = StoreFilters();

  /// El contexto de la plantilla (con su tema): lo que se abre encima toma sus colores
  BuildContext? _themed;

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
      final maintenanceFuture = (widget.maintenanceLoader ?? StorePage._serverMaintenance)();
      final store = await (widget.loader ?? OnlineStoreService.instance.getPublic)(slug);
      final maintenance = await maintenanceFuture;
      if (mounted) {
        setState(() {
          _store = store;
          _maintenance = maintenance;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<CartLine> get _lines => _cart.values.toList();
  int _qtyOf(StoreProduct p) => _cart.values.where((l) => l.product.id == p.id).fold(0, (s, l) => s + l.quantity);

  void _setLine(CartLine line, int qty) {
    final max = line.stock ?? 999;
    setState(() {
      if (qty <= 0) {
        _cart.remove(line.key);
      } else {
        _cart[line.key] = CartLine(line.product, qty > max ? max : qty, line.variant);
      }
    });
  }

  /// Agregar uno; si tiene tallas o colores, primero se elige
  Future<void> _add(StoreProduct p) async {
    StoreVariant? variant;
    if (p.variants.isNotEmpty) {
      variant = await _pickVariant(p);
      if (variant == null) return;
    }
    final key = CartLine.keyOf(p, variant);
    final current = _cart[key]?.quantity ?? 0;
    _setLine(CartLine(p, current, variant), current + 1);
  }

  /// Elegir talla y color: a la derecha en el computador, desde abajo en el celular
  Future<StoreVariant?> _pickVariant(StoreProduct p) => AppSidePanel.show<StoreVariant>(
        context: _themed ?? context,
        title: p.name,
        subtitle: p.sizes.isNotEmpty && p.colorHexes.isNotEmpty ? 'Elige la talla y el color' : 'Elige una opción',
        builder: (_) => _VariantPicker(product: p, currency: _store?.currency ?? 'COP'),
      );

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final store = _store;
    if (store == null) {
      return _MessagePage(
        text: _error ??
            (widget.slug == null ? 'Abre el enlace de la tienda que te compartieron.' : 'Esta tienda no está disponible en este momento.'),
        onRetry: _error != null ? _load : null,
      );
    }
    final accent = AppPalette.fromHex(store.color) ?? AppPalette.brand;
    final fashion = store.template == StoreTemplate.fashion;
    final theme = AppTheme.build(fashion ? Brightness.dark : Brightness.light, accent: accent);
    if (_maintenance.storesClosed) {
      return Theme(data: AppTheme.build(Brightness.light, accent: accent), child: _MaintenancePage(store: store, maintenance: _maintenance));
    }
    final notice = _maintenance.affects('stores') && (_maintenance.notice || _maintenance.active);
    return Theme(
      data: theme,
      child: Builder(
        builder: (context) {
          _themed = context;
          final view = fashion ? _fashion(context, store) : _classic(context, store);
          return notice ? Column(children: [_MaintenanceNotice(maintenance: _maintenance), Expanded(child: view)]) : view;
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Plantilla Clásica
  // ---------------------------------------------------------------------------

  Widget _classic(BuildContext context, PublicStore store) {
    final c = context.colors;
    final visible = store.products.where(_filters.matches).toList();
    final width = MediaQuery.sizeOf(context).width;
    final side = width > 1100 ? (width - 1040) / 2 : AppSpace.lg;
    final hasMore = _hasExtraFilters(store);

    return Scaffold(
      backgroundColor: c.paper,
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _classicHeader(c, store, side)),
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(side, AppSpace.lg, side, 0),
              child: Row(
                children: [
                  Expanded(child: _searchField()),
                  if (hasMore) ...[
                    const SizedBox(width: AppSpace.sm),
                    _filtersButton(store),
                  ],
                ],
              ),
            ),
          ),
          if (store.categories.length > 1)
            SliverToBoxAdapter(
              child: SizedBox(
                height: 64,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: EdgeInsets.fromLTRB(side, AppSpace.md, side, 0),
                  children: [
                    _categoryChip(store, null),
                    for (final cat in store.categories) _categoryChip(store, cat),
                  ],
                ),
              ),
            ),
          ..._grid(context, store, visible, side, minWidth: 180, extent: 300, fashion: false),
          SliverToBoxAdapter(child: _footer(context, side, _lines.isEmpty)),
        ],
      ),
      bottomNavigationBar: _lines.isEmpty ? null : _cartBar(context, store),
    );
  }

  Widget _classicHeader(StockealoColors c, PublicStore store, double side) => Container(
        color: c.accent,
        padding: EdgeInsets.fromLTRB(side, AppSpace.xl, side, AppSpace.xl),
        child: Row(
          children: [
            _Logo(store: store, size: 56),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(store.businessName, style: AppText.page(context, color: c.onAccent)),
                  if (store.welcome?.isNotEmpty == true) ...[
                    const SizedBox(height: AppSpace.xs),
                    Text(store.welcome!, style: AppText.body(context, color: c.onAccent)),
                  ],
                ],
              ),
            ),
          ],
        ),
      );

  Widget _categoryChip(PublicStore store, String? cat) {
    final selected = _filters.category == cat;
    final thumb = cat == null ? null : store.products.where((p) => p.category == cat && p.imageUrl != null).firstOrNull?.imageUrl;
    return Padding(
      padding: const EdgeInsets.only(right: AppSpace.sm),
      child: ChoiceChip(
        avatar: thumb == null ? null : CircleAvatar(backgroundImage: NetworkImage(thumb)),
        showCheckmark: false,
        label: Text(cat ?? 'Todo'),
        selected: selected,
        onSelected: (_) => setState(() => _filters.category = cat),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Plantilla Moda
  // ---------------------------------------------------------------------------

  Widget _fashion(BuildContext context, PublicStore store) {
    final c = context.colors;
    final visible = store.products.where(_filters.matches).toList();
    final width = MediaQuery.sizeOf(context).width;
    final side = width > 1380 ? (width - 1320) / 2 : (width >= 700 ? AppSpace.xl : AppSpace.md + 2);
    final wide = width >= 980;
    final offers = store.products.any((p) => p.onOffer);

    final header = Padding(
      padding: EdgeInsets.fromLTRB(side, AppSpace.lg, side, AppSpace.lg),
      child: Column(
        children: [
          Row(
            children: [
              if (wide)
                Expanded(
                  child: Wrap(
                    spacing: AppSpace.lg,
                    children: [
                      if (offers) _navLink('OFERTAS', () => setState(() => _filters.onlyOffers = true), active: _filters.onlyOffers),
                    ],
                  ),
                ),
              Expanded(
                flex: wide ? 1 : 3,
                child: Text(
                  store.businessName.toUpperCase(),
                  textAlign: wide ? TextAlign.center : TextAlign.left,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.heading(context, weight: FontWeight.w800).copyWith(letterSpacing: wide ? 9 : 4),
                ),
              ),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (wide) SizedBox(width: 200, child: _searchField(pill: true)),
                    const SizedBox(width: AppSpace.sm),
                    _cartButton(context, store),
                  ],
                ),
              ),
            ],
          ),
          if (!wide) ...[
            const SizedBox(height: AppSpace.md),
            Row(children: [Expanded(child: _searchField(pill: true)), const SizedBox(width: AppSpace.sm), _filtersButton(store)]),
          ],
        ],
      ),
    );

    // Portada baja (0.13.3): título y fotos pequeñas; los productos quedan a la vista sin bajar
    final photos = wide && store.heroPhotos ? store.products.where((p) => p.imageUrl != null).take(3).toList() : const <StoreProduct>[];
    final hero = Padding(
      padding: EdgeInsets.symmetric(horizontal: side),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: wide ? AppSpace.xl : AppSpace.lg, vertical: AppSpace.lg),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: c.line),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_promoLine(store) != null)
                    SectionLabel(_promoLine(store)!.toUpperCase(), padding: const EdgeInsets.only(bottom: AppSpace.xs))
                  else if (offers)
                    const SectionLabel('HAY OFERTAS', padding: EdgeInsets.only(bottom: AppSpace.xs)),
                  Text(
                    (store.heroTitle ?? '').trim().isEmpty ? store.businessName : store.heroTitle!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.page(context, weight: FontWeight.w800).copyWith(height: 1.1),
                  ),
                  if (store.welcome?.isNotEmpty == true) ...[
                    const SizedBox(height: AppSpace.xs),
                    Text(store.welcome!, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.body(context, color: c.inkMuted)),
                  ],
                ],
              ),
            ),
            for (final photo in photos) ...[
              const SizedBox(width: AppSpace.md),
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.control),
                child: SizedBox(
                  width: 88,
                  height: 88,
                  child: Image.network(photo.imageUrl!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => ColoredBox(color: c.surfaceMuted)),
                ),
              ),
            ],
          ],
        ),
      ),
    );

    final title = _filters.onlyOffers ? 'Ofertas' : (_filters.category ?? 'Toda la tienda');
    final grid = [
      SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.fromLTRB(side + (wide ? 280 : 0), AppSpace.xl, side, AppSpace.md),
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.end,
            spacing: AppSpace.md,
            children: [
              Text(title, style: AppText.page(context, weight: FontWeight.w800)),
              Text('${visible.length} ${visible.length == 1 ? 'producto' : 'productos'}${_filters.size == null ? '' : ' · talla ${_filters.size}'}',
                  style: AppText.body(context, color: c.inkFaint)),
            ],
          ),
        ),
      ),
    ];

    return Scaffold(
      backgroundColor: c.paper,
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: header),
          SliverToBoxAdapter(child: Divider(height: 1, color: c.line)),
          const SliverToBoxAdapter(child: SizedBox(height: AppSpace.lg)),
          SliverToBoxAdapter(child: hero),
          ...grid,
          if (wide)
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: side),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 256, child: _FiltersPanel(store: store, filters: _filters, onChanged: () => setState(() {}))),
                    const SizedBox(width: AppSpace.xl - 4),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, box) => _staticGrid(context, store, visible, box.maxWidth, minWidth: 230, extent: 360),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            ..._grid(context, store, visible, side, minWidth: 160, extent: 320, fashion: true),
          SliverToBoxAdapter(child: _footer(context, side, _lines.isEmpty, fashion: true)),
        ],
      ),
      bottomNavigationBar: _lines.isEmpty || wide ? null : _cartBar(context, store),
    );
  }

  /// La franja de la promoción que termina primero: «Fin de mes · termina en 3 días»
  String? _promoLine(PublicStore store) {
    StorePromo? first;
    for (final p in store.products) {
      final promo = p.promo;
      if (promo?.endsAt == null) continue;
      if (first == null || promo!.endsAt!.isBefore(first.endsAt!)) first = promo;
    }
    if (first == null) return null;
    final left = first.endsAt!.difference(DateTime.now());
    final when = left.inHours < 24 ? 'termina hoy' : 'termina en ${left.inDays} ${left.inDays == 1 ? 'día' : 'días'}';
    return '${first.name} · $when';
  }

  Widget _navLink(String label, VoidCallback onTap, {bool active = false}) {
    final c = context.colors;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
        child: Text(label, style: AppText.small(context, weight: FontWeight.w600, color: active ? c.accent : c.ink).copyWith(letterSpacing: 1)),
      ),
    );
  }

  Widget _cartButton(BuildContext context, PublicStore store) {
    final c = context.colors;
    final n = _lines.fold<int>(0, (s, l) => s + l.quantity);
    return Badge(
      isLabelVisible: n > 0,
      backgroundColor: c.accent,
      label: Text('$n'),
      child: IconButton.outlined(
        tooltip: n == 0 ? 'Tu pedido' : 'Tu pedido: $n productos',
        onPressed: () => _openCart(context, store),
        icon: const Icon(Icons.shopping_bag_outlined),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Partes de las dos plantillas
  // ---------------------------------------------------------------------------

  bool _hasExtraFilters(PublicStore store) =>
      store.products.any((p) => p.variants.isNotEmpty || p.onOffer) || store.products.length > 8;

  Widget _searchField({bool pill = false}) => TextField(
        onChanged: (v) => setState(() => _filters.query = v),
        decoration: InputDecoration(
          hintText: 'Buscar',
          prefixIcon: const Icon(Icons.search_outlined),
          isDense: pill,
          border: pill ? const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(AppRadius.pill))) : null,
          enabledBorder: pill
              ? OutlineInputBorder(borderRadius: const BorderRadius.all(Radius.circular(AppRadius.pill)), borderSide: BorderSide(color: context.colors.line))
              : null,
        ),
      );

  Widget _filtersButton(PublicStore store) => Badge(
        isLabelVisible: _filters.any,
        smallSize: 8,
        backgroundColor: context.colors.accent,
        child: OutlinedButton.icon(
          onPressed: () => AppSheet.show<void>(
            context: context,
            title: 'Filtros',
            builder: (ctx) => StatefulBuilder(
              builder: (ctx, setSheet) => _FiltersPanel(
                store: store,
                filters: _filters,
                bare: true,
                onChanged: () {
                  setSheet(() {});
                  setState(() {});
                },
              ),
            ),
          ),
          icon: const Icon(Icons.tune_outlined, size: 18),
          label: const Text('Filtros'),
        ),
      );

  List<Widget> _grid(BuildContext context, PublicStore store, List<StoreProduct> visible, double side,
      {required double minWidth, required double extent, required bool fashion}) {
    final c = context.colors;
    if (visible.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.xxl),
            child: Column(
              children: [
                Text(
                  store.products.isEmpty ? 'Esta tienda todavía no tiene productos disponibles.' : 'No hay productos con esos filtros.',
                  textAlign: TextAlign.center,
                  style: AppText.body(context, color: c.inkMuted),
                ),
                if (_filters.any)
                  TextButton(onPressed: () => setState(_filters.clear), child: const Text('Quitar filtros')),
              ],
            ),
          ),
        ),
      ];
    }
    return [
      SliverPadding(
        padding: EdgeInsets.fromLTRB(side, AppSpace.md, side, AppSpace.md),
        sliver: SliverGrid(
          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: minWidth * 1.35,
            mainAxisExtent: extent,
            mainAxisSpacing: AppSpace.md,
            crossAxisSpacing: AppSpace.md,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, i) => _card(store, visible[i], fashion: fashion),
            childCount: visible.length,
          ),
        ),
      ),
    ];
  }

  /// La cuadrícula al lado de los filtros (Moda en pantalla ancha)
  Widget _staticGrid(BuildContext context, PublicStore store, List<StoreProduct> visible, double width,
      {required double minWidth, required double extent}) {
    if (visible.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(AppSpace.xxl),
        child: Column(
          children: [
            Text('No hay productos con esos filtros.', style: AppText.body(context, color: context.colors.inkMuted)),
            if (_filters.any) TextButton(onPressed: () => setState(_filters.clear), child: const Text('Quitar filtros')),
          ],
        ),
      );
    }
    final cols = math.max(1, ((width + AppSpace.md) / (minWidth + AppSpace.md)).floor());
    final w = (width - AppSpace.md * (cols - 1)) / cols;
    return Wrap(
      spacing: AppSpace.md,
      runSpacing: AppSpace.md,
      children: [for (final p in visible) SizedBox(width: w, height: extent, child: _card(store, p, fashion: true))],
    );
  }

  Widget _card(PublicStore store, StoreProduct p, {required bool fashion}) => _ProductCard(
        product: p,
        currency: store.currency,
        quantity: _qtyOf(p),
        fashion: fashion,
        onAdd: () => _add(p),
        onRemove: () {
          final line = _cart.values.where((l) => l.product.id == p.id).lastOrNull;
          if (line != null) _setLine(line, line.quantity - 1);
        },
      );

  Widget _footer(BuildContext context, double side, bool empty, {bool fashion = false}) {
    final c = context.colors;
    return Padding(
      padding: EdgeInsets.fromLTRB(side, AppSpace.xl, side, empty ? AppSpace.xl : 110),
      child: Column(
        children: [
          if (fashion) Divider(height: AppSpace.xl, color: c.line),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: AppSpace.lg,
            runSpacing: AppSpace.sm,
            children: [
              Text('Pedidos por WhatsApp · el negocio te confirma la entrega', style: AppText.small(context, color: c.inkFaint)),
              Text('Al pedir recibes tu tiquete «Por confirmar»', style: AppText.small(context, color: c.inkFaint)),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          Text('Tienda hecha con Stockealo', textAlign: TextAlign.center, style: AppText.caption(context, color: c.inkFaint)),
        ],
      ),
    );
  }

  Widget _cartBar(BuildContext context, PublicStore store) {
    final c = context.colors;
    final lines = _lines;
    final units = lines.fold<int>(0, (s, l) => s + l.quantity);
    final total = lines.fold<double>(0, (s, l) => s + l.subtotal);
    return Container(
      decoration: BoxDecoration(color: c.surface, border: Border(top: BorderSide(color: c.line))),
      padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.md, AppSpace.lg, AppSpace.md),
      child: SafeArea(
        top: false,
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              onPressed: () => _openCart(context, store),
              icon: const Icon(Icons.shopping_bag_outlined),
              label: Text('Ver pedido · $units · ${CurrencyFormatter.formatIn(total, store.currency)}', overflow: TextOverflow.ellipsis),
            ),
          ),
        ),
      ),
    );
  }

  /// El carrito como en las tiendas grandes: a la derecha en el computador y en
  /// página completa en el celular, con el total y «Hacer el pedido» fijos abajo
  /// [ctx] es el de la plantilla: así el carrito toma su tema (Moda es oscura)
  Future<void> _openCart(BuildContext ctx, PublicStore store) {
    final theme = Theme.of(ctx);
    Widget form({required bool pinned}) => _CartForm(
          store: store,
          lines: () => _lines,
          onChanged: _setLine,
          storeContext: context,
          pinnedFooter: pinned,
        );
    if (MediaQuery.sizeOf(ctx).width >= AppSidePanel.wideFrom) {
      return AppSidePanel.show<void>(context: ctx, title: 'Tu pedido', builder: (_) => form(pinned: false));
    }
    return Navigator.of(ctx).push<void>(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => Theme(
        data: theme,
        child: Builder(
          builder: (page) => Scaffold(
            backgroundColor: page.colors.paper,
            appBar: AppBar(title: const Text('Tu pedido')),
            body: SafeArea(child: form(pinned: true)),
          ),
        ),
      ),
    ));
  }
}

/// Logo del negocio, o su inicial
class _Logo extends StatelessWidget {
  final PublicStore store;
  final double size;

  const _Logo({required this.store, required this.size});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final initial = Text(
      store.businessName.trim().isEmpty ? 'T' : store.businessName.trim()[0].toUpperCase(),
      style: AppText.page(context, color: c.accent),
    );
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(AppRadius.control)),
      alignment: Alignment.center,
      child: store.logoUrl != null && store.logoUrl!.startsWith('https://')
          ? Image.network(store.logoUrl!, fit: BoxFit.cover, width: size, height: size, errorBuilder: (_, __, ___) => initial)
          : initial,
    );
  }
}

/// Filtros: categoría (con miniatura y cuántos hay), talla, color, precio y ofertas
class _FiltersPanel extends StatelessWidget {
  final PublicStore store;
  final StoreFilters filters;
  final VoidCallback onChanged;

  /// Sin la tarjeta (dentro de la hoja del celular)
  final bool bare;

  const _FiltersPanel({required this.store, required this.filters, required this.onChanged, this.bare = false});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final products = store.products;
    final sizes = <String>{for (final p in products) ...p.sizes}.toList();
    final colors = <String>{for (final p in products) ...p.colorHexes}.where((h) => h != 'multi').toList();
    final prices = products.map((p) => p.price).toList();
    final minP = prices.isEmpty ? 0.0 : prices.reduce(math.min);
    final maxP = prices.isEmpty ? 0.0 : prices.reduce(math.max);
    final offers = products.any((p) => p.onOffer);
    final range = filters.price ?? RangeValues(minP, maxP);
    String money(num v) => CurrencyFormatter.formatIn(v, store.currency);

    void set(VoidCallback f) {
      f();
      onChanged();
    }

    Widget label(String t) => SectionLabel(t, padding: const EdgeInsets.fromLTRB(0, AppSpace.lg, 0, AppSpace.sm));

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(child: Text('Filtros', style: AppText.title(context))),
            if (filters.any) TextButton(onPressed: () => set(filters.clear), child: const Text('Quitar filtros')),
          ],
        ),
        if (store.categories.length > 1) ...[
          label('CATEGORÍA'),
          for (final cat in <String?>[null, ...store.categories])
            () {
              final n = cat == null ? products.length : products.where((p) => p.category == cat).length;
              final thumb = cat == null ? null : products.where((p) => p.category == cat && p.imageUrl != null).firstOrNull?.imageUrl;
              final selected = filters.category == cat;
              return Material(
                color: selected ? c.surfaceMuted : Colors.transparent,
                borderRadius: BorderRadius.circular(AppRadius.control),
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppRadius.control),
                  onTap: () => set(() => filters.category = cat),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: 6),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(AppRadius.tile - 1),
                          child: SizedBox(
                            width: 28,
                            height: 28,
                            child: thumb == null
                                ? ColoredBox(color: c.lineStrong)
                                : Image.network(thumb, fit: BoxFit.cover, errorBuilder: (_, __, ___) => ColoredBox(color: c.lineStrong)),
                          ),
                        ),
                        const SizedBox(width: AppSpace.md - 2),
                        Expanded(
                          child: Text(cat ?? 'Todas',
                              style: AppText.body(context, weight: selected ? FontWeight.w700 : FontWeight.w500, color: selected ? c.ink : c.inkMuted)),
                        ),
                        Text('$n', style: AppText.caption(context)),
                      ],
                    ),
                  ),
                ),
              );
            }(),
        ],
        if (sizes.isNotEmpty) ...[
          label('TALLA'),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final s in sizes)
                ChoiceChip(
                  label: Text(s),
                  showCheckmark: false,
                  selected: filters.size == s,
                  onSelected: (on) => set(() => filters.size = on ? s : null),
                ),
            ],
          ),
        ],
        if (colors.isNotEmpty) ...[
          label('COLOR'),
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.sm,
            children: [
              for (final h in colors)
                Semantics(
                  button: true,
                  selected: filters.colorHex == h,
                  label: 'Color $h',
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => set(() => filters.colorHex = filters.colorHex == h ? null : h),
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: filters.colorHex == h ? c.accent : Colors.transparent, width: 2),
                      ),
                      child: ColorSwatchDot(hex: h, size: 26),
                    ),
                  ),
                ),
            ],
          ),
        ],
        if (maxP > minP) ...[
          label('PRECIO'),
          RangeSlider(
            values: RangeValues(range.start.clamp(minP, maxP), range.end.clamp(minP, maxP)),
            min: minP,
            max: maxP,
            onChanged: (v) => set(() => filters.price = (v.start <= minP && v.end >= maxP) ? null : v),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(money(range.start), style: AppText.small(context)),
              Text(money(range.end), style: AppText.small(context)),
            ],
          ),
        ],
        if (offers) ...[
          const SizedBox(height: AppSpace.sm),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: filters.onlyOffers,
            onChanged: (v) => set(() => filters.onlyOffers = v),
            title: Text('Solo ofertas', style: AppText.body(context, weight: FontWeight.w600)),
          ),
        ],
      ],
    );
    if (bare) return body;
    return Material(
      color: c.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sheet - 2), side: BorderSide(color: c.line)),
      child: Padding(padding: const EdgeInsets.all(AppSpace.lg + 2), child: body),
    );
  }
}

/// Tarjeta de producto: foto grande, oferta, precio (con el de antes tachado),
/// tallas y el botón de agregar
class _ProductCard extends StatelessWidget {
  final StoreProduct product;
  final String currency;
  final int quantity;
  final bool fashion;
  final VoidCallback onAdd;
  final VoidCallback onRemove;

  const _ProductCard({
    required this.product,
    required this.currency,
    required this.quantity,
    required this.fashion,
    required this.onAdd,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = product;
    final maxed = p.variants.isEmpty && p.stock != null && quantity >= p.stock!;
    final radius = BorderRadius.circular(fashion ? AppRadius.sheet - 2 : AppRadius.card);
    final sizes = p.sizes;
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: radius,
        border: Border.all(color: quantity > 0 ? c.accent : c.line, width: quantity > 0 ? 2 : 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(
                  color: c.surfaceMuted,
                  child: p.imageUrl != null
                      ? Image.network(p.imageUrl!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _placeholder(c))
                      : _placeholder(c),
                ),
                if (p.onOffer || p.promo != null)
                  Positioned(
                    top: AppSpace.md,
                    right: AppSpace.md,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm + 2, vertical: 4),
                      decoration: BoxDecoration(color: c.accent, borderRadius: BorderRadius.circular(AppRadius.pill)),
                      // Con promoción: «−20 %» o «2×1»
                      child: Text(p.promo?.badge ?? 'OFERTA',
                          style: AppText.caption(context, weight: FontWeight.w800, color: c.onAccent)),
                    ),
                  ),
                if (quantity > 0)
                  Positioned(
                    top: AppSpace.md,
                    left: AppSpace.md,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm + 2, vertical: 4),
                      decoration: BoxDecoration(color: c.ink, borderRadius: BorderRadius.circular(AppRadius.pill)),
                      child: Text('$quantity en tu pedido', style: AppText.caption(context, weight: FontWeight.w700, color: c.surface)),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpace.md + 2, AppSpace.md, AppSpace.md, AppSpace.md + 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.body(context, color: fashion ? c.inkMuted : c.ink)),
                      const SizedBox(height: 4),
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.end,
                        spacing: AppSpace.sm,
                        children: [
                          Text(CurrencyFormatter.formatIn(p.price, currency),
                              style: AppText.amount(context, size: AppText.sizeTitle + 2, weight: FontWeight.w800, color: p.onOffer ? c.accent : c.ink)),
                          if (p.onOffer)
                            Text(CurrencyFormatter.formatIn(p.oldPrice!, currency),
                                style: AppText.small(context, color: c.inkFaint).copyWith(decoration: TextDecoration.lineThrough)),
                        ],
                      ),
                      if (sizes.isNotEmpty)
                        Text(sizes.join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.caption(context))
                      else if (p.stock != null)
                        Text('${p.stock} disponibles', style: AppText.caption(context)),
                      if (p.runningLow)
                        Text('Quedan pocas, pide pronto',
                            style: AppText.caption(context, weight: FontWeight.w700, color: c.warning)),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpace.sm),
                if (quantity > 0 && p.variants.isEmpty)
                  IconButton.outlined(tooltip: 'Quitar uno', onPressed: onRemove, icon: const Icon(Icons.remove_outlined, size: 18)),
                const SizedBox(width: 4),
                SizedBox(
                  width: 44,
                  height: 44,
                  child: IconButton.filled(
                    tooltip: p.variants.isEmpty ? 'Agregar al pedido' : 'Elegir talla o color',
                    style: IconButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.control + 2))),
                    onPressed: maxed ? null : onAdd,
                    icon: const Icon(Icons.add_shopping_cart_outlined, size: 20),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _placeholder(StockealoColors c) => Center(child: Icon(Icons.checkroom_outlined, size: 36, color: c.inkFaint));
}

/// El pedido: cantidades, nombre, nota y enviar. Al enviar sale el tiquete «Por
/// confirmar» (el pedido todavía no es una venta) con «Enviar pedido por WhatsApp».
class _CartForm extends StatefulWidget {
  final PublicStore store;
  final List<CartLine> Function() lines;
  final void Function(CartLine, int) onChanged;
  final BuildContext storeContext;

  /// En el celular (página completa): el total y «Hacer el pedido» quedan fijos abajo
  final bool pinnedFooter;

  const _CartForm({
    required this.store,
    required this.lines,
    required this.onChanged,
    required this.storeContext,
    this.pinnedFooter = false,
  });

  @override
  State<_CartForm> createState() => _CartFormState();
}

class _CartFormState extends State<_CartForm> {
  final _name = TextEditingController();
  final _note = TextEditingController();

  /// Se intentó pedir sin nombre
  bool _nameMissing = false;

  @override
  void dispose() {
    _name.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _sendWhatsApp(List<CartLine> lines) async {
    final text = OnlineStoreService.orderMessage(
      businessName: widget.store.businessName,
      lines: lines,
      currency: widget.store.currency,
      customerName: _name.text,
      note: _note.text,
    );
    final uri = Uri.parse('https://wa.me/${widget.store.whatsapp}?text=${Uri.encodeComponent(text)}');
    await launchUrl(uri, mode: LaunchMode.externalApplication, webOnlyWindowName: '_blank');
  }

  /// El tiquete del pedido, con el sello POR CONFIRMAR
  Future<void> _showTicket(List<CartLine> lines) async {
    final total = lines.fold<double>(0, (s, l) => s + l.subtotal);
    final now = DateTime.now();
    final doc = SaleDocument(
      title: 'Pedido',
      number: 'P-${now.millisecondsSinceEpoch.toString().substring(6)}',
      date: now,
      lines: [for (final l in lines) SaleDocumentLine(quantity: l.quantity, name: l.name, unitPrice: l.unitPrice, total: l.subtotal)],
      total: total,
      customerName: _name.text.trim().isEmpty ? null : _name.text.trim(),
      notes: _note.text.trim().isEmpty ? null : _note.text.trim(),
      closing: 'El negocio te confirma el precio final y la entrega.',
      stamp: const TicketStamp('POR CONFIRMAR', tone: AppTone.info),
    );
    final text = OnlineStoreService.orderMessage(
      businessName: widget.store.businessName,
      lines: lines,
      currency: widget.store.currency,
      customerName: _name.text,
      note: _note.text,
    );
    Navigator.of(context).pop();
    final host = widget.storeContext;
    if (!host.mounted) return;
    await TicketViewer.show(
      host,
      business: null,
      businessName: widget.store.businessName,
      doc: doc,
      headline: 'Tu pedido',
      headlineTone: AppTone.info,
      subline: CurrencyFormatter.formatIn(total, widget.store.currency),
      text: text,
      primary: (label: 'Enviar pedido por WhatsApp', icon: Icons.chat_outlined, onTap: () => _sendWhatsApp(lines)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final lines = widget.lines();
    final total = lines.fold<double>(0, (s, l) => s + l.subtotal);
    String money(num v) => CurrencyFormatter.formatIn(v, widget.store.currency);
    final footer = <Widget>[
      Row(
        children: [
          Expanded(child: Text('Total', style: AppText.title(context))),
          Text(money(total), style: AppText.amount(context, size: AppText.sizeHeading)),
        ],
      ),
      const SizedBox(height: AppSpace.md),
      FilledButton.icon(
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
        onPressed: () {
          if (_name.text.trim().isEmpty) {
            setState(() => _nameMissing = true);
            return;
          }
          _showTicket(lines);
        },
        icon: const Icon(Icons.receipt_long_outlined),
        label: const Text('Hacer el pedido'),
      ),
      const SizedBox(height: AppSpace.sm),
      Text(
        'Te mostramos tu tiquete y lo envías por WhatsApp. La tienda te confirma el precio final y la entrega.',
        textAlign: TextAlign.center,
        style: AppText.caption(context),
      ),
    ];
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (lines.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpace.xl),
            child: Text('Tu pedido está vacío.', textAlign: TextAlign.center, style: AppText.body(context, color: c.inkMuted)),
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
                      Text(l.name, style: AppText.body(context, weight: FontWeight.w600)),
                      Text(money(l.subtotal), style: AppText.small(context)),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Quitar uno',
                  onPressed: () => setState(() => widget.onChanged(l, l.quantity - 1)),
                  icon: Icon(l.quantity == 1 ? Icons.delete_outline : Icons.remove_outlined, size: 20),
                ),
                Text('${l.quantity}', style: AppText.body(context, weight: FontWeight.w700)),
                IconButton(
                  tooltip: 'Agregar uno',
                  onPressed: l.stock == null || l.quantity < l.stock! ? () => setState(() => widget.onChanged(l, l.quantity + 1)) : null,
                  icon: const Icon(Icons.add_outlined, size: 20),
                ),
              ],
            ),
          ),
        if (lines.isNotEmpty) ...[
          Divider(height: AppSpace.xl, color: c.line),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            onChanged: (_) {
              if (_nameMissing) setState(() => _nameMissing = false);
            },
            decoration: InputDecoration(
              labelText: 'Tu nombre',
              errorText: _nameMissing ? 'Escribe tu nombre para que la tienda sepa quién pide' : null,
            ),
          ),
          const SizedBox(height: AppSpace.md),
          TextField(
            controller: _note,
            textCapitalization: TextCapitalization.sentences,
            maxLines: 2,
            minLines: 1,
            decoration: const InputDecoration(labelText: 'Nota (opcional)', hintText: 'Ej.: dirección de entrega, forma de pago'),
          ),
          if (!widget.pinnedFooter) ...[const SizedBox(height: AppSpace.lg), ...footer],
        ],
      ],
    );
    if (!widget.pinnedFooter) return body;
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.sm, AppSpace.lg, AppSpace.lg),
            child: body,
          ),
        ),
        if (lines.isNotEmpty)
          DecoratedBox(
            decoration: BoxDecoration(color: c.surface, border: Border(top: BorderSide(color: c.line))),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.md, AppSpace.lg, AppSpace.md),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: footer),
            ),
          ),
      ],
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
              Text(text, textAlign: TextAlign.center, style: AppText.title(context, weight: FontWeight.w500)),
              if (onRetry != null) ...[
                const SizedBox(height: AppSpace.lg),
                OutlinedButton(onPressed: onRetry, child: const Text('Reintentar')),
              ],
              const SizedBox(height: AppSpace.xl),
              Text('Tienda hecha con Stockealo', style: AppText.caption(context, color: c.inkFaint)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Franja de aviso: mantenimiento programado o en curso que no cierra la tienda
class _MaintenanceNotice extends StatelessWidget {
  final MaintenanceState maintenance;
  const _MaintenanceNotice({required this.maintenance});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final m = maintenance;
    final text = m.notice
        ? 'Mantenimiento programado ${MaintenanceGate.when(m.startsAt)}: la tienda puede no estar disponible '
            'hasta ${MaintenanceGate.when(m.endsAt)}.'
        : 'Estamos haciendo mantenimiento hasta ${MaintenanceGate.when(m.endsAt)}.';
    return Material(
      color: c.warningSoft,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.sm),
          child: Row(children: [
            Icon(Icons.construction_outlined, size: 18, color: c.warning),
            const SizedBox(width: AppSpace.sm),
            Expanded(child: Text(text, style: AppText.small(context, color: c.ink))),
          ]),
        ),
      ),
    );
  }
}

/// Tienda cerrada por mantenimiento: el cliente igual puede escribirle al negocio
class _MaintenancePage extends StatelessWidget {
  final PublicStore store;
  final MaintenanceState maintenance;
  const _MaintenancePage({required this.store, required this.maintenance});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final note = (maintenance.message ?? '').trim();
    final wa = store.whatsapp.replaceAll(RegExp(r'\D'), '');
    return Scaffold(
      backgroundColor: c.paper,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.construction_outlined, size: 48, color: c.accent),
                const SizedBox(height: AppSpace.md),
                Text(store.businessName, textAlign: TextAlign.center, style: AppText.heading(context)),
                const SizedBox(height: AppSpace.sm),
                Text(
                  'La tienda está en mantenimiento. Vuelve ${MaintenanceGate.when(maintenance.endsAt)}.',
                  textAlign: TextAlign.center,
                  style: AppText.bodyLarge(context, color: c.inkMuted),
                ),
                if (note.isNotEmpty) ...[
                  const SizedBox(height: AppSpace.md),
                  Text(note, textAlign: TextAlign.center, style: AppText.body(context)),
                ],
                if (wa.length >= 10) ...[
                  const SizedBox(height: AppSpace.xl),
                  FilledButton.icon(
                    onPressed: () => launchUrl(Uri.parse('https://wa.me/$wa'), webOnlyWindowName: '_blank'),
                    icon: const Icon(Icons.chat_outlined),
                    label: const Text('Escribir al negocio por WhatsApp'),
                  ),
                ],
                const SizedBox(height: AppSpace.xl),
                Text('Tienda hecha con Stockealo', style: AppText.caption(context, color: c.inkFaint)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Elegir talla y color como en las tiendas grandes: primero la talla y debajo los colores
/// que hay en esa talla. Lo agotado se ve tachado y no se puede elegir; si quedan pocas,
/// lo dice sin dar el número.
class _VariantPicker extends StatefulWidget {
  final StoreProduct product;
  final String currency;

  const _VariantPicker({required this.product, required this.currency});

  @override
  State<_VariantPicker> createState() => _VariantPickerState();
}

class _VariantPickerState extends State<_VariantPicker> {
  String? _size;
  StoreVariant? _chosen;

  List<StoreVariant> get _all => widget.product.variants;
  bool get _hasSizes => _all.any((v) => v.size != null);

  /// Tallas en el orden en que se crearon
  List<String> get _sizes => [for (final s in _all.map((v) => v.size).whereType<String>().toSet()) s];

  /// Las opciones de la talla elegida (o todas si no hay tallas)
  List<StoreVariant> get _options => _hasSizes ? _all.where((v) => v.size == _size).toList() : _all;

  bool _sizeSoldOut(String size) => _all.where((v) => v.size == size).every((v) => v.soldOut);
  bool _sizeFew(String size) => _all.any((v) => v.size == size && !v.soldOut && v.few);

  @override
  void initState() {
    super.initState();
    // Si solo hay una talla disponible, queda elegida
    final open = _sizes.where((s) => !_sizeSoldOut(s)).toList();
    if (_hasSizes && open.length == 1) _pickSize(open.single, rebuild: false);
    if (!_hasSizes) {
      final avail = _all.where((v) => !v.soldOut).toList();
      if (avail.length == 1) _chosen = avail.single;
    }
  }

  void _pickSize(String size, {bool rebuild = true}) {
    void apply() {
      _size = size;
      final avail = _all.where((v) => v.size == size && !v.soldOut).toList();
      // Sin colores (o uno solo): la talla ya es la opción
      _chosen = avail.length == 1 ? avail.single : null;
    }

    rebuild ? setState(apply) : apply();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final chosen = _chosen;
    final colors = _options.where((v) => v.color != null || v.hex != null).toList();
    final showColors = (!_hasSizes || _size != null) && colors.isNotEmpty;
    final price = widget.product.price + (chosen?.extra ?? 0);

    Widget label(String text) => Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.sm, top: AppSpace.md),
          child: Text(text, style: AppText.small(context, weight: FontWeight.w700, color: c.ink)),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_hasSizes) ...[
          label('Talla'),
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.sm,
            children: [
              for (final size in _sizes)
                _OptionChip(
                  label: size,
                  soldOut: _sizeSoldOut(size),
                  few: _sizeFew(size),
                  selected: _size == size,
                  onTap: () => _pickSize(size),
                ),
            ],
          ),
        ],
        if (showColors) ...[
          label(_hasSizes ? 'Color en talla $_size' : 'Color'),
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.sm,
            children: [
              for (final v in colors)
                _OptionChip(
                  label: v.color ?? 'Color',
                  hex: v.hex,
                  soldOut: v.soldOut,
                  few: v.few,
                  selected: _chosen?.id == v.id,
                  onTap: () => setState(() => _chosen = v),
                ),
            ],
          ),
        ] else if (!_hasSizes) ...[
          // Sin tallas ni colores con nombre: cada opción tal cual
          label('Opción'),
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.sm,
            children: [
              for (final v in _all)
                _OptionChip(
                  label: v.label.isEmpty ? 'Única' : v.label,
                  soldOut: v.soldOut,
                  few: v.few,
                  selected: _chosen?.id == v.id,
                  onTap: () => setState(() => _chosen = v),
                ),
            ],
          ),
        ],
        const SizedBox(height: AppSpace.lg),
        if ((chosen != null && chosen.few) || (chosen == null && _size != null && _sizeFew(_size!)))
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.sm),
            child: Text(chosen != null ? 'Quedan pocas, pide pronto' : 'Quedan pocas en talla $_size, pide pronto',
                style: AppText.small(context, weight: FontWeight.w700, color: c.warning)),
          ),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          onPressed: chosen == null ? null : () => Navigator.pop(context, chosen),
          child: Text(chosen == null
              ? (_hasSizes && _size == null ? 'Elige una talla' : 'Elige un color')
              : 'Agregar al pedido · ${CurrencyFormatter.formatIn(price, widget.currency)}'),
        ),
      ],
    );
  }
}

/// Una talla o un color: la elegida con el color del negocio, la agotada tachada
class _OptionChip extends StatelessWidget {
  final String label;
  final String? hex;
  final bool soldOut;
  final bool few;
  final bool selected;
  final VoidCallback onTap;

  const _OptionChip({
    required this.label,
    this.hex,
    this.soldOut = false,
    this.few = false,
    this.selected = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fg = soldOut ? c.inkFaint : (selected ? c.onAccent : c.ink);
    return Opacity(
      opacity: soldOut ? 0.55 : 1,
      child: Material(
        color: selected ? c.accent : (soldOut ? c.surfaceMuted : c.surface),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
          side: BorderSide(color: selected ? c.accent : c.line, width: selected ? 1.4 : 1),
        ),
        child: InkWell(
          onTap: soldOut ? null : onTap,
          borderRadius: BorderRadius.circular(AppRadius.control),
          // Todas del mismo alto: lo agotado solo se tacha; «quedan pocas» va debajo al elegir
          child: Tooltip(
            message: soldOut ? 'Agotada' : (few ? 'Quedan pocas' : ''),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 48, minHeight: 44),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (ColorSwatchDot.hasSwatch(hex)) ...[ColorSwatchDot(hex: hex, size: 16), const SizedBox(width: AppSpace.xs)],
                    Text(
                      label,
                      style: AppText.body(context, weight: FontWeight.w700, color: fg).copyWith(
                        decoration: soldOut ? TextDecoration.lineThrough : null,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
