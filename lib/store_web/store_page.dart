import 'dart:math' as math;
import '../features/products/presentation/category_icons.dart';
import 'dart:ui' show ImageFilter;

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
import '../features/store/data/booking_service.dart';
import 'booking_panel.dart';
import 'clean_url_stub.dart' if (dart.library.js_interop) 'clean_url_web.dart';
import '../core/utils/coupons.dart';

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

/// De dónde llegó la visita (?src=qr, fase 4)
String? sourceFromUri(Uri uri) {
  final s = uri.queryParameters['src']?.trim().toLowerCase();
  return s == null || s.isEmpty ? null : s;
}

/// Producto compartido (?p=<id>, 0.16.0): sale primero y resaltado
String? sharedProductFromUri(Uri uri) {
  final p = uri.queryParameters['p']?.trim();
  return p == null || p.isEmpty ? null : p;
}

/// Lo que se está filtrando en la tienda
class StoreFilters {
  String query = '';
  String? category;
  String? size;
  String? colorHex;

  /// Marca (0.16.0)
  String? brand;
  RangeValues? price;
  bool onlyOffers = false;

  bool get any => category != null || size != null || colorHex != null || brand != null || price != null || onlyOffers;

  void clear() {
    category = size = colorHex = brand = null;
    price = null;
    onlyOffers = false;
  }

  bool matches(StoreProduct p) {
    final q = query.trim().toLowerCase();
    if (q.isNotEmpty &&
        !p.name.toLowerCase().contains(q) &&
        !p.category.toLowerCase().contains(q) &&
        !(p.brand?.toLowerCase().contains(q) ?? false)) {
      return false;
    }
    if (category != null && p.category != category) return false;
    if (brand != null && p.brand != brand) return false;
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

  /// Producto que le compartieron al cliente (0.16.0): va primero con «Te compartieron este producto»
  final String? sharedProductId;

  /// De dónde llegó (?src=qr) (fase 4)
  final String? source;

  /// Cuenta visitas y productos agregados (fase 4). Por defecto, la nube cuando la tienda
  /// viene del servidor; las pruebas y la vista previa no cuentan.
  final void Function(String slug, String kind, String? productId)? tracker;

  const StorePage({
    super.key,
    required this.slug,
    this.loader,
    this.maintenanceLoader,
    this.sharedProductId,
    this.source,
    this.tracker,
  });

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

  /// Sede que mira quien compra (0.18.3); '' = Principal. Se recuerda en el navegador
  String _branchId = '';
  final _filters = StoreFilters();

  /// El contexto de la plantilla (con su tema): lo que se abre encima toma sus colores
  BuildContext? _themed;

  /// Reservas en línea (0.14.0); null si el negocio no las recibe
  PublicBooking? _booking;

  /// Aviso +18 (0.16.0): ya dijo que es mayor de edad en esta visita
  bool _adultOk = false;

  /// Cerró el aviso del producto compartido
  bool _sharedClosed = false;
  bool _adultNo = false;

  Future<void> _loadBooking(String slug) async {
    final now = DateTime.now();
    // Un día de margen a cada lado: el negocio puede estar en otra zona (0.16.9)
    final from = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 1));
    final booking = await BookingService.instance.get(slug, from: from, to: from.add(const Duration(days: 17)));
    if (mounted) setState(() => _booking = booking);
  }

  Future<void> _openBooking(PublicStore store) async {
    final booking = _booking;
    if (booking == null) return;
    await AppSidePanel.show<void>(
      context: _themed ?? context,
      title: 'Reservar una cita',
      subtitle: store.businessName,
      builder: (_) => BookingPanel(store: store, booking: booking),
    );
    _loadBooking(store.slug);
  }

  /// «Reservar cita» (solo si el negocio recibe reservas)
  Widget _bookButton(PublicStore store, {bool compact = false}) {
    if (_booking == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(right: AppSpace.sm),
      child: compact
          ? IconButton.filledTonal(
              tooltip: 'Reservar cita',
              onPressed: () => _openBooking(store),
              icon: const Icon(Icons.event_available_outlined),
            )
          : FilledButton.icon(
              onPressed: () => _openBooking(store),
              icon: const Icon(Icons.event_available_outlined, size: 18),
              label: const Text('Reservar cita'),
            ),
    );
  }

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
      if (store != null && widget.loader == null) _loadBooking(slug);
      if (store != null) _countVisit(store);
      if (mounted) {
        setState(() {
          // El producto compartido va primero, como un destacado más
          final shared = widget.sharedProductId;
          _store = store != null && shared != null && store.products.any((p) => p.id == shared)
              ? store.copyWith(look: store.look.copyWith(featured: [shared, ...store.look.featured.where((f) => f != shared)]))
              : store;
          _maintenance = maintenance;
          if (store != null && store.hasBranches) _branchId = store.branchOf(savedStoreBranch(slug)).id;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Estadísticas (fase 4): la visita una vez, de dónde llegó, y cada producto agregado
  /// una vez por visita
  final Set<String> _counted = {};

  void Function(String, String, String?)? get _track =>
      widget.tracker ?? (widget.loader == null ? (s, k, p) => OnlineStoreService.instance.track(s, k, productId: p) : null);

  void _countVisit(PublicStore store) {
    final track = _track;
    if (track == null || !firstTimeThisVisit('visit_${store.slug}')) return;
    track(store.slug, 'VISIT', null);
    if (widget.source == 'qr') track(store.slug, 'QR', null);
    if (widget.sharedProductId != null) track(store.slug, 'SHARED', widget.sharedProductId);
  }

  void _countAdd(StoreProduct p) {
    final store = _store;
    final track = _track;
    if (store == null || track == null || !_counted.add(p.id) || !firstTimeThisVisit('add_${store.slug}_${p.id}')) return;
    track(store.slug, 'ADD', p.id);
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

  /// Agregar uno. La talla y el color se eligen en la misma tarjeta (0.15.0); si el
  /// producto tiene otras opciones (sin talla ni color), se elige en el panel.
  Future<void> _add(StoreProduct p, [StoreVariant? chosen]) async {
    var variant = chosen;
    if (variant == null && p.variants.isNotEmpty) {
      variant = await _pickVariant(p);
      if (variant == null) return;
    }
    final key = CartLine.keyOf(p, variant);
    final current = _cart[key]?.quantity ?? 0;
    _setLine(CartLine(p, current, variant), current + 1);
    _countAdd(p);
  }

  /// Cambia la sede que se mira. El pedido es de una sede: si ya hay algo en el
  /// pedido, se pregunta antes de vaciarlo.
  Future<void> _chooseBranch(PublicStore store, String id) async {
    if (id == _branchId) return;
    if (_cart.isNotEmpty) {
      final ok = await AppDialog.confirm(
        context: _themed ?? context,
        title: '¿Cambiar a ${store.branchOf(id).name}?',
        message: 'Tu pedido es de ${store.branchOf(_branchId).name}. Al cambiar de sede se vacía.',
        confirmText: 'Cambiar',
      );
      if (!ok) return;
    }
    setState(() {
      _cart.clear();
      _branchId = id;
    });
    saveStoreBranch(store.slug, id);
  }

  /// «Estás viendo: Norte ▾», su dirección, su teléfono y «Cómo llegar» (0.18.3); si
  /// faltan productos aquí y hay en otra sede, lo dice con un botón para cambiar
  Widget _branchBar(BuildContext context, PublicStore store) {
    final c = context.colors;
    final branch = store.branchOf(_branchId);
    final away = store.elsewhere(_branchId);
    return Material(
      color: c.surface,
      child: Container(
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.line))),
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.sm),
        child: Wrap(
          spacing: AppSpace.md,
          runSpacing: AppSpace.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.place_outlined, size: 18, color: c.accent),
                const SizedBox(width: AppSpace.xs),
                Text('Estás viendo:', style: AppText.small(context, color: c.inkMuted)),
                const SizedBox(width: AppSpace.xs),
                DropdownButton<String>(
                  value: branch.id,
                  isDense: true,
                  underline: const SizedBox.shrink(),
                  style: AppText.small(context, weight: FontWeight.w700, color: c.ink),
                  items: [for (final b in store.branches) DropdownMenuItem(value: b.id, child: Text(b.name))],
                  onChanged: (id) => id == null ? null : _chooseBranch(store, id),
                ),
              ],
            ),
            if (branch.address != null)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(branch.address!, style: AppText.small(context, color: c.ink)),
                  TextButton(
                    onPressed: () => launchUrl(PublicStore.mapsUrl(branch.address!, businessName: store.businessName),
                        mode: LaunchMode.externalApplication, webOnlyWindowName: '_blank'),
                    child: const Text('Cómo llegar'),
                  ),
                ],
              ),
            if (branch.phone != null) Text('Tel. ${branch.phone}', style: AppText.small(context, color: c.inkMuted)),
            if (away.count > 0 && away.where != null)
              TextButton.icon(
                onPressed: () => _chooseBranch(store, away.where!.id),
                icon: const Icon(Icons.swap_horiz, size: 18),
                label: Text('${away.count} ${away.count == 1 ? 'producto' : 'productos'} más en ${away.where!.name}'),
              ),
          ],
        ),
      ),
    );
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
    final loaded = _store;
    if (loaded == null) {
      return _MessagePage(
        text: _error ??
            (widget.slug == null ? 'Abre el enlace de la tienda que te compartieron.' : 'Esta tienda no está disponible en este momento.'),
        onRetry: _error != null ? _load : null,
      );
    }
    // Con sedes (0.18.3) se ve lo que hay en la sede elegida, con su dirección
    final store = loaded.hasBranches ? loaded.inBranch(_branchId) : loaded;
    // Color propio de la tienda o el del negocio; Moda siempre es oscura y las demás
    // con «Modo oscuro» (0.16.0)
    final accent = AppPalette.fromHex(store.accentHex) ?? AppPalette.brand;
    final fashion = store.template == StoreTemplate.fashion;
    final theme = AppTheme.build(fashion || store.look.dark ? Brightness.dark : Brightness.light, accent: accent);
    if (_maintenance.storesClosed) {
      return Theme(data: AppTheme.build(Brightness.light, accent: accent), child: _MaintenancePage(store: store, maintenance: _maintenance));
    }
    final notice = _maintenance.affects('stores') && (_maintenance.notice || _maintenance.active);
    final shared = widget.sharedProductId == null ? null : store.products.where((p) => p.id == widget.sharedProductId).firstOrNull;
    final gated = store.look.adult && !_adultOk;
    final page = Theme(
      data: theme,
      child: Builder(
        builder: (context) {
          _themed = context;
          final view = switch (store.template) {
            StoreTemplate.fashion => _fashion(context, store),
            StoreTemplate.market => _market(context, store),
            StoreTemplate.menu => _menu(context, store),
            StoreTemplate.boutique => _boutique(context, store),
            _ => _classic(context, store),
          };
          final banner = shared == null || _sharedClosed
              ? null
              : MaterialBanner(
                  leading: const Icon(Icons.share_outlined),
                  content: Text('Te compartieron este producto: ${shared.name}. Va de primero.'),
                  actions: [TextButton(onPressed: () => setState(() => _sharedClosed = true), child: const Text('Entendido'))],
                );
          if (!notice && banner == null && !loaded.hasBranches) return view;
          return Column(children: [
            if (notice) _MaintenanceNotice(maintenance: _maintenance),
            if (loaded.hasBranches) _branchBar(context, loaded),
            if (banner != null) banner,
            Expanded(child: view),
          ]);
        },
      ),
    );
    if (!gated) return page;
    // La tienda se ve detrás, difuminada y oscurecida, y no se puede tocar hasta
    // responder (0.16.2). Única excepción a «sin difuminados» del rediseño.
    return Theme(
      data: theme,
      child: Builder(
        builder: (context) => Stack(
          fit: StackFit.expand,
          children: [
            // Sin toques, sin lector de pantalla y sin foco con el teclado (Tab)
            IgnorePointer(
              child: ExcludeFocus(
                child: ExcludeSemantics(
                  child: ImageFiltered(
                    key: const ValueKey('adult-gate-blur'),
                    imageFilter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                    child: page,
                  ),
                ),
              ),
            ),
            ColoredBox(color: Colors.black.withValues(alpha: 0.6)),
            _adultGate(context, store),
          ],
        ),
      ),
    );
  }

  /// «Esta tienda vende productos para mayores de 18 años» (0.16.0): tarjeta encima de
  /// la tienda difuminada (0.16.2)
  Widget _adultGate(BuildContext context, PublicStore store) {
    final c = context.colors;
    return Material(
      type: MaterialType.transparency,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpace.lg),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 420),
            padding: const EdgeInsets.all(AppSpace.xl),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(color: c.line),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _Logo(store: store, size: 56),
                const SizedBox(height: AppSpace.md),
                Text(store.businessName, textAlign: TextAlign.center, style: AppText.title(context)),
                const SizedBox(height: AppSpace.xl),
                Icon(Icons.warning_amber_outlined, size: 36, color: c.warning),
                const SizedBox(height: AppSpace.sm),
                Text('Esta tienda vende productos para mayores de 18 años',
                    textAlign: TextAlign.center, style: AppText.bodyLarge(context, weight: FontWeight.w700)),
                const SizedBox(height: AppSpace.xs),
                Text(
                  _adultNo ? 'Lo sentimos: solo pueden entrar mayores de edad.' : '¿Tienes 18 años o más?',
                  textAlign: TextAlign.center,
                  style: AppText.body(context, color: c.inkMuted),
                ),
                const SizedBox(height: AppSpace.lg),
                if (!_adultNo)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      OutlinedButton(onPressed: () => setState(() => _adultNo = true), child: const Text('No')),
                      const SizedBox(width: AppSpace.md),
                      FilledButton(onPressed: () => setState(() => _adultOk = true), child: const Text('Sí, entrar')),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Plantilla Clásica
  // ---------------------------------------------------------------------------

  Widget _classic(BuildContext context, PublicStore store) {
    final c = context.colors;
    final visible = store.ordered.where(_filters.matches).toList();
    final width = MediaQuery.sizeOf(context).width;
    final side = width > 1100 ? (width - 1040) / 2 : AppSpace.lg;
    final hasMore = _hasExtraFilters(store);

    return Scaffold(
      backgroundColor: c.paper,
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _classicHeader(c, store, side)),
          if (store.heroImageUrl != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(side, AppSpace.lg, side, 0),
                child: _coverImage(c, store, height: width > 700 ? 220 : 140),
              ),
            ),
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
          ..._grid(context, store, visible, side, minWidth: 180, extent: 300 + _optionsExtra(store), fashion: false),
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
                  if (store.look.schedule != null) ...[const SizedBox(height: AppSpace.sm), _openPill(store, onAccent: true)],
                ],
              ),
            ),
            // Reservas en línea (Pro Servicios)
            if (_booking != null)
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: c.onAccent, foregroundColor: c.accent),
                onPressed: () => _openBooking(store),
                icon: const Icon(Icons.event_available_outlined, size: 18),
                label: const Text('Reservar cita'),
              ),
          ],
        ),
      );

  /// Foto de portada propia del negocio, ancha y baja
  Widget _coverImage(StockealoColors c, PublicStore store, {required double height}) => ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: SizedBox(
          height: height,
          width: double.infinity,
          child: Image.network(
            store.heroImageUrl!,
            fit: BoxFit.cover,
            semanticLabel: 'Portada de ${store.businessName}',
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          ),
        ),
      );

  Widget _categoryChip(PublicStore store, String? cat) {
    final selected = _filters.category == cat;
    // Ícono de la categoría (0.16.8, #28): antes, la foto de un producto y «Todas» con
    // un cuadro gris. Si el negocio los apagó, solo el nombre
    final c = context.colors;
    final icon = !store.look.icons ? null : (cat == null ? CategoryIcon.all : CategoryIcon.of(store.iconOf(cat)));
    return Padding(
      padding: const EdgeInsets.only(right: AppSpace.sm),
      child: ChoiceChip(
        avatar: icon == null ? null : Icon(icon, size: 18, color: selected ? c.surface : c.accent),
        showCheckmark: false,
        label: Text(cat ?? 'Todas'),
        selected: selected,
        onSelected: (_) => setState(() => _filters.category = cat),
      ),
    );
  }


  /// «Abierto · cierra 8 p. m.» o «Cerrado · abre mañana 7 a. m.» (0.16.0); nada sin horario
  Widget _openPill(PublicStore store, {bool onAccent = false}) {
    final schedule = store.look.schedule;
    if (schedule == null) return const SizedBox.shrink();
    final now = DateTime.now();
    final open = schedule.isOpen(now);
    if (onAccent) {
      final c = context.colors;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(open ? Icons.schedule_outlined : Icons.do_not_disturb_on_outlined, size: 16, color: c.onAccent),
          const SizedBox(width: AppSpace.xs),
          Flexible(child: Text(schedule.status(now), style: AppText.small(context, color: c.onAccent, weight: FontWeight.w600))),
        ],
      );
    }
    return StatusPill(schedule.status(now), tone: open ? AppTone.success : AppTone.warning, dot: true);
  }

  /// Agregar o quitar uno desde una fila (Mercado y Menú)
  Widget _rowControls(PublicStore store, StoreProduct p) {
    final qty = _qtyOf(p);
    return _RowAdd(
      quantity: qty,
      onAdd: () => _add(p),
      onRemove: () {
        final line = _cart.values.where((l) => l.product.id == p.id).lastOrNull;
        if (line != null) _setLine(line, line.quantity - 1);
      },
    );
  }

  Widget _compactHeader(StockealoColors c, PublicStore store, double side, {bool soft = true}) => Container(
        color: soft ? c.accent.withValues(alpha: 0.12) : c.surface,
        padding: EdgeInsets.fromLTRB(side, AppSpace.md, side, AppSpace.md),
        child: Row(
          children: [
            _Logo(store: store, size: 40),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(store.businessName, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.title(context)),
                  if (store.look.schedule != null) ...[const SizedBox(height: AppSpace.xs), _openPill(store)],
                ],
              ),
            ),
            _bookButton(store, compact: true),
          ],
        ),
      );

  // ---------------------------------------------------------------------------
  // Plantilla Mercado (0.16.0): lista compacta con botón +
  // ---------------------------------------------------------------------------

  Widget _market(BuildContext context, PublicStore store) {
    final c = context.colors;
    final visible = store.ordered.where(_filters.matches).toList();
    final width = MediaQuery.sizeOf(context).width;
    final side = width > 900 ? (width - 820) / 2 : AppSpace.md;
    return Scaffold(
      backgroundColor: c.paper,
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _compactHeader(c, store, side)),
          if (store.welcome?.isNotEmpty == true)
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(side, AppSpace.md, side, 0),
                child: Text(store.welcome!, style: AppText.body(context, color: c.inkMuted)),
              ),
            ),
          SliverToBoxAdapter(
            child: Padding(padding: EdgeInsets.fromLTRB(side, AppSpace.md, side, 0), child: _searchField()),
          ),
          if (store.categories.length > 1)
            SliverToBoxAdapter(
              child: SizedBox(
                height: 56,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: EdgeInsets.fromLTRB(side, AppSpace.sm, side, 0),
                  children: [_categoryChip(store, null), for (final cat in store.categories) _categoryChip(store, cat)],
                ),
              ),
            ),
          if (store.brands.length > 1) SliverToBoxAdapter(child: _brandChips(store, side)),
          if (visible.isEmpty) ..._grid(context, store, visible, side, minWidth: 180, extent: 300, fashion: false),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(side, AppSpace.sm, side, 0),
            sliver: SliverList.separated(
              itemCount: visible.length,
              separatorBuilder: (_, __) => Divider(height: 1, color: c.line),
              itemBuilder: (context, i) {
                final p = visible[i];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
                  child: Row(
                    children: [
                      _RowThumb(url: p.imageUrl, size: 52),
                      const SizedBox(width: AppSpace.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(p.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.body(context, weight: FontWeight.w600)),
                            const SizedBox(height: 2),
                            _RowPrice(product: p, currency: store.currency, featured: store.isFeatured(p)),
                          ],
                        ),
                      ),
                      const SizedBox(width: AppSpace.sm),
                      _rowControls(store, p),
                    ],
                  ),
                );
              },
            ),
          ),
          SliverToBoxAdapter(child: _footer(context, side, _lines.isEmpty)),
        ],
      ),
      bottomNavigationBar: _lines.isEmpty ? null : _cartBar(context, store),
    );
  }

  // ---------------------------------------------------------------------------
  // Plantilla Menú (0.16.0): cada categoría es una sección de la carta
  // ---------------------------------------------------------------------------

  Widget _menu(BuildContext context, PublicStore store) {
    final c = context.colors;
    final visible = store.ordered.where(_filters.matches).toList();
    final width = MediaQuery.sizeOf(context).width;
    final side = width > 860 ? (width - 760) / 2 : AppSpace.lg;
    final featured = _filters.any ? const <StoreProduct>[] : visible.where(store.isFeatured).toList();
    final sections = <String, List<StoreProduct>>{};
    for (final p in visible) {
      if (featured.contains(p)) continue;
      sections.putIfAbsent(p.category.isEmpty ? 'Otros' : p.category, () => []).add(p);
    }
    Widget section(String title) => Padding(
          padding: EdgeInsets.fromLTRB(side, AppSpace.xl, side, AppSpace.xs),
          child: Container(
            padding: const EdgeInsets.only(bottom: AppSpace.xs + 2),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.lineStrong))),
            child: Text(title.toUpperCase(), style: AppText.caption(context, color: c.inkMuted).copyWith(letterSpacing: 1.6)),
          ),
        );
    Widget dish(StoreProduct p) => Padding(
          padding: EdgeInsets.fromLTRB(side, AppSpace.sm + 2, side, AppSpace.sm + 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.name, style: AppText.bodyLarge(context, weight: FontWeight.w600)),
                    if (p.description != null) ...[
                      const SizedBox(height: 2),
                      Text(p.description!, maxLines: 3, overflow: TextOverflow.ellipsis, style: AppText.small(context, color: c.inkMuted)),
                    ],
                    const SizedBox(height: AppSpace.xs),
                    _RowPrice(product: p, currency: store.currency, featured: false),
                    // Precio por cantidad (0.17.0)
                    if (p.priceTiers.isNotEmpty)
                      Text(p.tiersText((v) => CurrencyFormatter.formatIn(v, store.currency))!,
                          style: AppText.caption(context, weight: FontWeight.w700, color: c.success)),
                  ],
                ),
              ),
              if (p.imageUrl != null) ...[const SizedBox(width: AppSpace.md), _RowThumb(url: p.imageUrl, size: 72)],
              const SizedBox(width: AppSpace.sm),
              _rowControls(store, p),
            ],
          ),
        );
    return Scaffold(
      backgroundColor: c.paper,
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(side, AppSpace.xl, side, 0),
              child: Column(
                children: [
                  Row(children: [const Spacer(), _bookButton(store, compact: true)]),
                  _Logo(store: store, size: 64),
                  const SizedBox(height: AppSpace.md),
                  Text(store.businessName, textAlign: TextAlign.center, style: AppText.page(context)),
                  if (store.welcome?.isNotEmpty == true) ...[
                    const SizedBox(height: AppSpace.xs),
                    Text(store.welcome!, textAlign: TextAlign.center, style: AppText.body(context, color: c.inkMuted)),
                  ],
                  if (store.look.schedule != null) ...[const SizedBox(height: AppSpace.sm), _openPill(store)],
                  if (store.heroImageUrl != null) ...[
                    const SizedBox(height: AppSpace.lg),
                    _coverImage(c, store, height: width > 700 ? 220 : 150),
                  ],
                  const SizedBox(height: AppSpace.lg),
                  _searchField(pill: true),
                ],
              ),
            ),
          ),
          if (visible.isEmpty) ..._grid(context, store, visible, side, minWidth: 180, extent: 300, fashion: false),
          if (featured.isNotEmpty) ...[
            SliverToBoxAdapter(child: section('Recomendados')),
            SliverList.list(children: [for (final p in featured) dish(p)]),
          ],
          for (final e in sections.entries) ...[
            SliverToBoxAdapter(child: section(e.key)),
            SliverList.list(children: [for (final p in e.value) dish(p)]),
          ],
          SliverToBoxAdapter(child: _footer(context, side, _lines.isEmpty)),
        ],
      ),
      bottomNavigationBar: _lines.isEmpty ? null : _cartBar(context, store),
    );
  }

  // ---------------------------------------------------------------------------
  // Plantilla Boutique (0.16.0): fotos grandes y mucho espacio
  // ---------------------------------------------------------------------------

  Widget _boutique(BuildContext context, PublicStore store) {
    final c = context.colors;
    final visible = store.ordered.where(_filters.matches).toList();
    final width = MediaQuery.sizeOf(context).width;
    final side = width > 1200 ? (width - 1100) / 2 : (width >= 700 ? AppSpace.xxl : AppSpace.lg);
    final hero = !_filters.any ? visible.where((p) => store.isFeatured(p) && p.imageUrl != null).firstOrNull : null;
    final rest = hero == null ? visible : visible.where((p) => p != hero).toList();
    return Scaffold(
      backgroundColor: c.paper,
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(side, AppSpace.xl, side, AppSpace.md),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Spacer(),
                      _bookButton(store, compact: true),
                      _cartButton(context, store),
                    ],
                  ),
                  Text(
                    store.businessName.toUpperCase(),
                    textAlign: TextAlign.center,
                    style: AppText.heading(context, weight: FontWeight.w500).copyWith(letterSpacing: 6),
                  ),
                  if (store.welcome?.isNotEmpty == true) ...[
                    const SizedBox(height: AppSpace.sm),
                    Text(store.welcome!, textAlign: TextAlign.center, style: AppText.body(context, color: c.inkMuted)),
                  ],
                  if (store.look.schedule != null) ...[const SizedBox(height: AppSpace.sm), _openPill(store)],
                ],
              ),
            ),
          ),
          if (store.heroImageUrl != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(side, 0, side, AppSpace.lg),
                child: _coverImage(c, store, height: width > 700 ? 320 : 200),
              ),
            ),
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(side, 0, side, 0),
              child: Row(children: [Expanded(child: _searchField(pill: true)), if (_hasExtraFilters(store)) ...[const SizedBox(width: AppSpace.sm), _filtersButton(store)]]),
            ),
          ),
          if (hero != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(side, AppSpace.xl, side, 0),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: SizedBox(height: (width > 600 ? 600 : 470) + _optionsExtra(store), child: _card(store, hero, fashion: false)),
                  ),
                ),
              ),
            ),
          SliverToBoxAdapter(child: SizedBox(height: hero == null ? AppSpace.md : AppSpace.lg)),
          ..._grid(context, store, rest, side, minWidth: width > 600 ? 240 : 150, extent: (width > 600 ? 400 : 320) + _optionsExtra(store), fashion: false),
          SliverToBoxAdapter(child: _footer(context, side, _lines.isEmpty)),
        ],
      ),
      bottomNavigationBar: _lines.isEmpty ? null : _cartBar(context, store),
    );
  }

  // ---------------------------------------------------------------------------
  // Plantilla Moda
  // ---------------------------------------------------------------------------

  Widget _fashion(BuildContext context, PublicStore store) {
    final c = context.colors;
    final visible = store.ordered.where(_filters.matches).toList();
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
              // Espacio a la izquierda para que el nombre quede centrado. «Ofertas» se
              // filtra en el lateral («Solo ofertas»), no aquí arriba (0.16.2)
              if (wide) const Spacer(),
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
                    _bookButton(store, compact: !wide),
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
    final photos = wide && store.heroPhotos && store.heroImageUrl == null ? store.products.where((p) => p.imageUrl != null).take(3).toList() : const <StoreProduct>[];
    final hero = Padding(
      padding: EdgeInsets.symmetric(horizontal: side),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: wide ? AppSpace.xl : AppSpace.lg, vertical: AppSpace.lg),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: c.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Portada propia (0.15.0): ancha y baja, encima del título
            if (store.heroImageUrl != null) ...[
              _coverImage(c, store, height: wide ? 200 : 130),
              const SizedBox(height: AppSpace.md),
            ],
            Row(
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
                        builder: (context, box) => _staticGrid(context, store, visible, box.maxWidth, minWidth: 230, extent: 360 + _optionsExtra(store)),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            ..._grid(context, store, visible, side, minWidth: 160, extent: 320 + _optionsExtra(store), fashion: true),
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
      store.products.any((p) => p.variants.isNotEmpty || p.onOffer) || store.products.length > 8 || store.brands.length > 1;

  /// Marcas como chips (Mercado), si hay más de una (0.16.0)
  Widget _brandChips(PublicStore store, double side) => SizedBox(
        height: 52,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.fromLTRB(side, AppSpace.sm, side, 0),
          children: [
            for (final b in <String?>[null, ...store.brands])
              Padding(
                padding: const EdgeInsets.only(right: AppSpace.sm),
                child: ChoiceChip(
                  showCheckmark: false,
                  label: Text(b ?? 'Todas las marcas'),
                  selected: _filters.brand == b,
                  onSelected: (_) => setState(() => _filters.brand = b),
                ),
              ),
          ],
        ),
      );

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

  /// Alto extra de las tarjetas cuando alguna trae tallas o colores para elegir
  static double _optionsExtra(PublicStore store) => store.products.any(_ProductCard.hasOptions) ? 84 : 0;

  Widget _card(PublicStore store, StoreProduct p, {required bool fashion}) => _ProductCard(
        key: ValueKey('card-${p.id}'),
        product: p,
        currency: store.currency,
        quantity: _qtyOf(p),
        fashion: fashion,
        onAdd: (variant) => _add(p, variant),
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
              Text('Al pedir recibes tu comprobante «Por confirmar»', style: AppText.small(context, color: c.inkFaint)),
            ],
          ),
          // Dónde queda el local, con «Cómo llegar» (0.16.9)
          if (_store?.shownAddress != null) ...[
            const SizedBox(height: AppSpace.md),
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: AppSpace.xs,
              children: [
                Icon(Icons.place_outlined, size: 18, color: c.accent),
                Text(_store!.shownAddress!, style: AppText.small(context, color: c.ink)),
                TextButton(
                  onPressed: () => launchUrl(PublicStore.mapsUrl(_store!.shownAddress!, businessName: _store!.businessName),
                      mode: LaunchMode.externalApplication, webOnlyWindowName: '_blank'),
                  child: const Text('Cómo llegar'),
                ),
              ],
            ),
          ],
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
          branchId: store.hasBranches ? _branchId : null,
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
        if (store.brands.length > 1) ...[
          label('MARCA'),
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.sm,
            children: [
              for (final b in store.brands)
                ChoiceChip(
                  showCheckmark: false,
                  label: Text(b),
                  selected: filters.brand == b,
                  onSelected: (v) => set(() => filters.brand = v ? b : null),
                ),
            ],
          ),
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

/// Tarjeta de producto: foto grande, oferta, precio (con el de antes tachado) y el botón
/// de agregar. Desde la 0.15.0 la talla y el color se eligen aquí mismo: lo agotado se ve
/// tachado en diagonal y el carrito agrega directo, sin abrir nada.
class _ProductCard extends StatefulWidget {
  final StoreProduct product;
  final String currency;
  final int quantity;
  final bool fashion;

  /// Agregar: con la talla y el color elegidos en la tarjeta (null si no tiene)
  final ValueChanged<StoreVariant?> onAdd;
  final VoidCallback onRemove;

  const _ProductCard({
    super.key,
    required this.product,
    required this.currency,
    required this.quantity,
    required this.fashion,
    required this.onAdd,
    required this.onRemove,
  });

  /// Tiene tallas o colores para elegir en la tarjeta
  static bool hasOptions(StoreProduct p) =>
      p.variants.any((v) => v.size != null || v.color != null || ColorSwatchDot.hasSwatch(v.hex));

  @override
  State<_ProductCard> createState() => _ProductCardState();
}

class _ProductCardState extends State<_ProductCard> {
  String? _size;
  String? _color;

  /// Tocó agregar sin elegir: la línea de ayuda lo pide con otro color
  bool _nudge = false;

  List<StoreVariant> get _all => widget.product.variants;
  static String? _colorKey(StoreVariant v) => v.color ?? (ColorSwatchDot.hasSwatch(v.hex) ? v.hex : null);

  /// Tallas y colores en el orden en que se crearon, también los agotados
  List<String> get _sizes => [for (final x in _all.map((v) => v.size).whereType<String>().toSet()) x];
  List<StoreVariant> get _colors {
    final seen = <String>{};
    return [
      for (final v in _all)
        if (_colorKey(v) != null && seen.add(_colorKey(v)!)) v,
    ];
  }

  /// Foto del color elegido (o del único color de la talla); null = la del producto
  String? get _photo {
    if (_color == null) return null;
    return _all.where((v) => _colorKey(v) == _color && v.imageUrl != null).firstOrNull?.imageUrl;
  }

  bool _sizeOut(String size) => _all.where((v) => v.size == size).every((v) => v.soldOut);

  /// ¿Hay este color? En la talla elegida o, sin talla, en alguna
  bool _colorOpen(String key) =>
      _all.any((v) => _colorKey(v) == key && !v.soldOut && (_size == null || v.size == _size));

  /// La opción que quedó elegida; null si falta algo
  StoreVariant? get _chosen {
    final needSize = _sizes.isNotEmpty;
    final needColor = _colors.isNotEmpty;
    if ((needSize && _size == null) || (needColor && _color == null)) return null;
    return _all.where((v) => !v.soldOut && (!needSize || v.size == _size) && (!needColor || _colorKey(v) == _color)).firstOrNull;
  }

  @override
  void initState() {
    super.initState();
    _autoPick();
  }

  /// Si solo queda una talla o un color disponible, queda elegido solo
  void _autoPick() {
    if (_size == null) {
      final open = _sizes.where((x) => !_sizeOut(x)).toList();
      if (open.length == 1) _size = open.single;
    }
    if (_color == null) {
      final open = [for (final v in _colors) if (_colorOpen(_colorKey(v)!)) _colorKey(v)!];
      if (open.length == 1) _color = open.single;
    }
  }

  void _pickSize(String size) => setState(() {
        _nudge = false;
        _size = _size == size ? null : size;
        // El color elegido no existe en la talla nueva: se quita
        if (_color != null && _size != null && !_colorOpen(_color!)) _color = null;
        if (_size != null) _autoPick();
      });

  void _pickColor(String key) => setState(() {
        _nudge = false;
        _color = _color == key ? null : key;
        // Si ese color solo existe en una talla, queda elegida
        if (_color != null && _size == null) {
          final sizes = {for (final v in _all) if (_colorKey(v) == key && !v.soldOut && v.size != null) v.size!};
          if (sizes.length == 1) _size = sizes.single;
        }
      });

  void _add() {
    final p = widget.product;
    if (!_ProductCard.hasOptions(p)) return widget.onAdd(null);
    final chosen = _chosen;
    if (chosen == null) return setState(() => _nudge = true);
    widget.onAdd(chosen);
    setState(() {
      _size = null;
      _color = null;
      _autoPick();
    });
  }

  String get _hint {
    // Un color sin nombre (solo la muestra) no se escribe
    final p = widget.product;
    final sizeName = p.sizeName, option = p.optionName.toLowerCase();
    if (_chosen != null) return [if (_size != null) '$sizeName $_size', if (_chosen!.color != null) _chosen!.color!].join(' · ');
    final missSize = _sizes.isNotEmpty && _size == null;
    final missColor = _colors.isNotEmpty && _color == null;
    // «la talla», «la nicotina», «la presentación»; «el color», «el sabor»
    String art(String w) => const {'color', 'sabor', 'tamaño', 'aroma'}.contains(w.toLowerCase()) ? 'el' : 'la';
    final size = sizeName.toLowerCase();
    if (missSize && missColor) return _nudge ? 'Elige ${art(size)} $size y ${art(option)} $option' : 'Elige $size y $option';
    if (missSize) return 'Elige ${art(size)} $size';
    if (missColor) return _size == null ? 'Elige ${art(option)} $option' : '$sizeName $_size · elige ${art(option)} $option';
    return 'Esa combinación está agotada';
  }

  Widget _options(BuildContext context) {
    final c = context.colors;
    final chosen = _chosen;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_sizes.isNotEmpty)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final size in _sizes)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: _SizeChip(label: size, selected: _size == size, soldOut: _sizeOut(size), onTap: () => _pickSize(size)),
                  ),
              ],
            ),
          ),
        if (_colors.isNotEmpty) ...[
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final v in _colors)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: _ColorChoice(
                      name: v.color ?? 'Color',
                      hex: v.hex,
                      selected: _color == _colorKey(v),
                      soldOut: !_colorOpen(_colorKey(v)!),
                      onTap: () => _pickColor(_colorKey(v)!),
                    ),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 6),
        Text(
          chosen != null && chosen.few ? '$_hint · quedan pocas' : _hint,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppText.caption(
            context,
            weight: _nudge || chosen != null ? FontWeight.w700 : FontWeight.w400,
            color: _nudge ? c.warning : (chosen != null ? c.ink : c.inkFaint),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = widget.product;
    final quantity = widget.quantity;
    final fashion = widget.fashion;
    final currency = widget.currency;
    final maxed = p.variants.isEmpty && p.stock != null && quantity >= p.stock!;
    final radius = BorderRadius.circular(fashion ? AppRadius.sheet - 2 : AppRadius.card);
    final inline = _ProductCard.hasOptions(p);
    final sizes = inline ? const <String>[] : p.sizes;
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
                  // Con un color elegido se ve la foto de ese color (0.15.0)
                  child: (_photo ?? p.imageUrl) != null
                      ? Image.network(_photo ?? p.imageUrl!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _placeholder(c))
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
            padding: EdgeInsets.fromLTRB(AppSpace.md + 2, AppSpace.md, AppSpace.md, inline ? AppSpace.sm : AppSpace.md + 2),
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
                      // Precio por cantidad (0.17.0)
                      if (p.priceTiers.isNotEmpty)
                        Text(p.tiersText((v) => CurrencyFormatter.formatIn(v, currency))!,
                            maxLines: 2, overflow: TextOverflow.ellipsis,
                            style: AppText.caption(context, weight: FontWeight.w700, color: c.success)),
                      if (sizes.isNotEmpty)
                        Text(sizes.join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.caption(context))
                      else if (p.stock != null)
                        Text('${p.stock} disponibles', style: AppText.caption(context)),
                      if (p.runningLow && !inline)
                        Text('Quedan pocas, pide pronto',
                            style: AppText.caption(context, weight: FontWeight.w700, color: c.warning)),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpace.sm),
                if (quantity > 0 && p.variants.isEmpty)
                  IconButton.outlined(tooltip: 'Quitar uno', onPressed: widget.onRemove, icon: const Icon(Icons.remove_outlined, size: 18)),
                const SizedBox(width: 4),
                SizedBox(
                  width: 44,
                  height: 44,
                  child: IconButton.filled(
                    tooltip: inline && _chosen == null ? 'Elige talla o color' : 'Agregar al pedido',
                    style: IconButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.control + 2))),
                    onPressed: maxed ? null : _add,
                    icon: const Icon(Icons.add_shopping_cart_outlined, size: 20),
                  ),
                ),
              ],
            ),
          ),
          if (inline)
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpace.md + 2, 0, AppSpace.md, AppSpace.md + 2),
              child: _options(context),
            ),
        ],
      ),
    );
  }

  Widget _placeholder(StockealoColors c) => Center(child: NoPhotoIcon(size: 36, color: c.inkFaint));
}

/// Una talla en la tarjeta: la elegida llena y con borde grueso; la agotada tachada
class _SizeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final bool soldOut;
  final VoidCallback onTap;

  const _SizeChip({required this.label, required this.selected, required this.soldOut, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      selected: selected,
      label: soldOut ? 'Talla $label agotada' : 'Talla $label',
      child: Tooltip(
        message: soldOut ? 'Agotada' : '',
        child: InkWell(
          onTap: soldOut ? null : onTap,
          borderRadius: BorderRadius.circular(AppRadius.control),
          child: Container(
            constraints: const BoxConstraints(minWidth: 34, minHeight: 30),
            padding: const EdgeInsets.symmetric(horizontal: 9),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? c.ink : null,
              borderRadius: BorderRadius.circular(AppRadius.control),
              border: Border.all(color: selected ? c.ink : (soldOut ? c.line : c.lineStrong), width: selected ? 2 : 1),
            ),
            foregroundDecoration: soldOut ? _Crossed(c.inkMuted) : null,
            child: Text(
              label,
              style: AppText.caption(
                context,
                weight: selected ? FontWeight.w800 : FontWeight.w600,
                color: selected ? c.surface : (soldOut ? c.inkFaint : c.ink),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Un color en la tarjeta: el círculo del color (o su nombre si no tiene muestra); el
/// elegido con un aro; el que no hay en esa talla, tachado
class _ColorChoice extends StatelessWidget {
  final String name;
  final String? hex;
  final bool selected;
  final bool soldOut;
  final VoidCallback onTap;

  const _ColorChoice({required this.name, required this.hex, required this.selected, required this.soldOut, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final swatch = ColorSwatchDot.hasSwatch(hex);
    return Semantics(
      button: true,
      selected: selected,
      label: soldOut ? 'Color $name agotado' : 'Color $name',
      child: Tooltip(
        message: soldOut ? '$name · agotado en esta talla' : name,
        child: InkWell(
          onTap: soldOut ? null : onTap,
          customBorder: swatch ? const CircleBorder() : null,
          borderRadius: swatch ? null : BorderRadius.circular(AppRadius.control),
          child: Container(
            height: 30,
            width: swatch ? 30 : null,
            padding: swatch ? const EdgeInsets.all(3) : const EdgeInsets.symmetric(horizontal: 9),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: swatch ? BoxShape.circle : BoxShape.rectangle,
              borderRadius: swatch ? null : BorderRadius.circular(AppRadius.control),
              border: Border.all(color: selected ? c.ink : c.lineStrong, width: selected ? 2 : 1),
            ),
            foregroundDecoration: soldOut ? _Crossed(c.inkMuted) : null,
            child: swatch
                ? ColorSwatchDot(hex: hex, size: 20)
                : Text(name,
                    style: AppText.caption(context,
                        weight: selected ? FontWeight.w800 : FontWeight.w600, color: soldOut ? c.inkFaint : c.ink)),
          ),
        ),
      ),
    );
  }
}

/// Tachado en diagonal para lo agotado (de abajo a la izquierda hacia arriba a la derecha)
class _Crossed extends Decoration {
  final Color color;
  const _Crossed(this.color);

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) => _CrossedPainter(color);
}

class _CrossedPainter extends BoxPainter {
  final Color color;
  _CrossedPainter(this.color);

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    final size = configuration.size;
    if (size == null) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(offset + Offset(2, size.height - 2), offset + Offset(size.width - 2, 2), paint);
  }
}

/// El pedido en dos pasos (0.15.0): primero lo que se pide, con la foto, la talla y el
/// color de cada producto; después los datos del comprador. Al enviar sale el tiquete
/// «Por confirmar» (el pedido todavía no es una venta) con «Enviar pedido por WhatsApp».
class _CartForm extends StatefulWidget {
  final PublicStore store;
  final List<CartLine> Function() lines;
  final void Function(CartLine, int) onChanged;
  final BuildContext storeContext;

  /// En el celular (página completa): el total y «Hacer el pedido» quedan fijos abajo
  final bool pinnedFooter;

  /// Sede del pedido (0.18.3); null = el negocio no tiene sedes
  final String? branchId;

  const _CartForm({
    required this.store,
    this.branchId,
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
  final _phone = TextEditingController();

  /// Código del pedido guardado (T-0001)
  String? _code;
  bool _sending = false;

  /// 1 = el pedido; 2 = los datos del comprador
  int _step = 1;

  /// Cupón de la tienda (0.16.0): lo revisa la nube y lo vuelve a calcular al pedir
  final _couponField = TextEditingController();
  bool _showCoupon = false;
  bool _checkingCoupon = false;
  bool _phoneMissing = false;
  String? _couponError;
  Coupon? _coupon;

  String _money(num v) => CurrencyFormatter.formatIn(v, widget.store.currency);

  double _discount(double subtotal) => _coupon?.discountFor(subtotal) ?? 0;

  Future<void> _applyCoupon(double subtotal) async {
    final code = _couponField.text.trim();
    if (code.isEmpty) return;
    setState(() {
      _checkingCoupon = true;
      _couponError = null;
    });
    try {
      final coupon = await OnlineStoreService.instance.checkCoupon(
        slug: widget.store.slug,
        code: code,
        total: subtotal,
        phone: _phone.text,
        money: _money,
      );
      if (mounted) setState(() => _coupon = coupon);
    } on CouponException catch (e) {
      if (mounted) setState(() => _couponError = e.message);
    } finally {
      if (mounted) setState(() => _checkingCoupon = false);
    }
  }

  /// «¿Tienes un cupón?» → el campo → «BIENVENIDA10 · −$5.000»
  Widget _couponBox(StockealoColors c, double subtotal) {
    final coupon = _coupon;
    if (coupon != null) {
      final discount = _discount(subtotal);
      return Padding(
        padding: const EdgeInsets.only(top: AppSpace.md),
        child: Row(
          children: [
            Icon(Icons.local_offer_outlined, size: 18, color: discount > 0 ? c.success : c.warning),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Text(
                discount > 0
                    ? '${coupon.code} · −${_money(discount)}'
                    : '${coupon.code}: es para compras desde ${_money(coupon.minTotal)}',
                style: AppText.body(context, weight: FontWeight.w600, color: discount > 0 ? c.success : c.warning),
              ),
            ),
            TextButton(
              onPressed: () => setState(() {
                _coupon = null;
                _couponField.clear();
              }),
              child: const Text('Quitar'),
            ),
          ],
        ),
      );
    }
    if (!_showCoupon) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => setState(() => _showCoupon = true),
          icon: const Icon(Icons.local_offer_outlined, size: 18),
          label: const Text('¿Tienes un cupón?'),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: TextField(
              controller: _couponField,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(labelText: 'Cupón', isDense: true, errorText: _couponError, errorMaxLines: 3),
              onSubmitted: (_) => _applyCoupon(subtotal),
            ),
          ),
          const SizedBox(width: AppSpace.sm),
          OutlinedButton(
            onPressed: _checkingCoupon ? null : () => _applyCoupon(subtotal),
            child: Text(_checkingCoupon ? 'Revisando…' : 'Aplicar'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _couponField.dispose();
    _name.dispose();
    _note.dispose();
    _phone.dispose();
    super.dispose();
  }

  String _message(List<CartLine> lines) => OnlineStoreService.orderMessage(
        businessName: widget.store.businessName,
        lines: lines,
        currency: widget.store.currency,
        customerName: _name.text,
        note: _note.text,
        code: _code,
        phone: _phone.text,
        couponCode: _coupon?.code,
        discount: _discount(lines.fold<double>(0, (s, l) => s + l.subtotal)),
      );

  Future<void> _sendWhatsApp(List<CartLine> lines) async {
    final text = _message(lines);
    final uri = Uri.parse('https://wa.me/${widget.store.whatsapp}?text=${Uri.encodeComponent(text)}');
    await launchUrl(uri, mode: LaunchMode.externalApplication, webOnlyWindowName: '_blank');
  }

  /// El tiquete del pedido, con el sello POR CONFIRMAR
  Future<void> _showTicket(List<CartLine> lines) async {
    if (_sending) return;
    setState(() => _sending = true);
    // El pedido se guarda en la tienda con su código; sin conexión sigue por WhatsApp.
    // Si el cupón no sirve, se dice y el pedido espera a que lo corrija.
    if (_code == null) {
      final saved = await OnlineStoreService.instance.createOrder(
        slug: widget.store.slug,
        customerName: _name.text,
        customerPhone: _phone.text,
        note: _note.text,
        lines: lines,
        coupon: _coupon?.code,
        money: _money,
        branchId: widget.branchId,
      );
      if (!mounted) return;
      if (saved.error != null) {
        setState(() {
          _sending = false;
          _couponError = saved.error;
          _coupon = null;
          _showCoupon = true;
        });
        return;
      }
      _code = saved.code;
    }
    if (!mounted) return;
    setState(() => _sending = false);
    final subtotal = lines.fold<double>(0, (s, l) => s + l.subtotal);
    final discount = _discount(subtotal);
    final total = subtotal - discount;
    final now = DateTime.now();
    final doc = SaleDocument(
      title: 'Pedido',
      number: _code ?? 'P-${now.millisecondsSinceEpoch.toString().substring(6)}',
      date: now,
      lines: [for (final l in lines) SaleDocumentLine(quantity: l.quantity, name: l.name, unitPrice: l.unitPrice, total: l.subtotal)],
      total: total,
      discount: discount,
      customerName: _name.text.trim().isEmpty ? null : _name.text.trim(),
      notes: _note.text.trim().isEmpty ? null : _note.text.trim(),
      closing: 'El negocio te confirma el precio final y la entrega.',
      stamp: const TicketStamp('POR CONFIRMAR', tone: AppTone.info),
    );
    final text = _message(lines);
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
    // Si se vació el pedido estando en los datos, vuelve al primer paso
    if (lines.isEmpty) _step = 1;
    final subtotal = lines.fold<double>(0, (s, l) => s + l.subtotal);
    final total = subtotal - _discount(subtotal);
    final count = lines.fold<int>(0, (s, l) => s + l.quantity);
    String money(num v) => CurrencyFormatter.formatIn(v, widget.store.currency);
    final products = '$count ${count == 1 ? 'producto' : 'productos'}';

    Widget stepLabel(String text) => Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.sm),
          child: Text(text, style: AppText.caption(context)),
        );

    late final Widget body;
    late final List<Widget> footer;
    if (_step == 1) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          stepLabel('Paso 1 de 2 · revisa lo que pides'),
          if (lines.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpace.xl),
              child: Text('Tu pedido está vacío.', textAlign: TextAlign.center, style: AppText.body(context, color: c.inkMuted)),
            ),
          for (final l in lines)
            _CartItem(
              line: l,
              money: money,
              onMinus: () => setState(() => widget.onChanged(l, l.quantity - 1)),
              onPlus: l.stock == null || l.quantity < l.stock! ? () => setState(() => widget.onChanged(l, l.quantity + 1)) : null,
            ),
        ],
      );
      footer = [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text('Total', style: AppText.title(context)),
            const SizedBox(width: AppSpace.sm),
            Expanded(child: Text(products, style: AppText.caption(context))),
            Text(money(total), style: AppText.amount(context, size: AppText.sizeHeading)),
          ],
        ),
        const SizedBox(height: AppSpace.md),
        FilledButton.icon(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          onPressed: () => setState(() => _step = 2),
          icon: const Icon(Icons.arrow_forward_outlined),
          label: const Text('Continuar'),
        ),
        const SizedBox(height: AppSpace.xs),
        TextButton.icon(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back_outlined, size: 18),
          label: const Text('Seguir comprando'),
        ),
      ];
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Volver al pedido',
                onPressed: () => setState(() => _step = 1),
                icon: const Icon(Icons.arrow_back_outlined),
              ),
              Expanded(child: Text('Tus datos', style: AppText.title(context))),
            ],
          ),
          stepLabel('Paso 2 de 2 · para que la tienda te confirme'),
          // Fuera del horario se recibe igual, con aviso (0.16.0)
          if (widget.store.look.schedule case final s? when !s.isOpen(DateTime.now()))
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.md),
              child: _CartNotice(
                icon: Icons.schedule_outlined,
                tone: AppTone.warning,
                title: 'Estamos cerrados en este momento',
                text: 'Puedes hacer tu pedido igual: te atendemos al abrir. Horario: ${s.text}.',
              ),
            ),
          // Resumen: las fotos, cuántos productos, el total y «Editar»
          Container(
            padding: const EdgeInsets.all(AppSpace.sm + 2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(color: c.line),
            ),
            child: Row(
              children: [
                _ThumbStack(lines: lines),
                const SizedBox(width: AppSpace.sm),
                Expanded(child: Text(products, style: AppText.small(context))),
                Text(money(total), style: AppText.body(context, weight: FontWeight.w700)),
                TextButton(onPressed: () => setState(() => _step = 1), child: const Text('Editar')),
              ],
            ),
          ),
          const SizedBox(height: AppSpace.lg),
          TextField(
            controller: _name,
            autofocus: true,
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
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              labelText: _coupon != null ? 'Tu celular (lo pide el cupón)' : 'Tu celular (recomendado)',
              hintText: 'Para avisarte cuando esté listo',
              errorText: _phoneMissing ? CouponText.error('coupon_phone_required') : null,
            ),
            onChanged: (_) {
              if (_phoneMissing) setState(() => _phoneMissing = false);
            },
          ),
          const SizedBox(height: AppSpace.md),
          TextField(
            controller: _note,
            textCapitalization: TextCapitalization.sentences,
            maxLines: 2,
            minLines: 1,
            decoration: const InputDecoration(labelText: 'Nota (opcional)', hintText: 'Ej.: dirección de entrega, forma de pago'),
          ),
          // Cupón de la tienda (0.16.0)
          _couponBox(c, subtotal),
        ],
      );
      footer = [
        FilledButton.icon(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          onPressed: () {
            if (_name.text.trim().isEmpty) {
              setState(() => _nameMissing = true);
              return;
            }
            // Con cupón el celular es obligatorio: se usa una vez por cliente
            if (_coupon != null && _phone.text.replaceAll(RegExp(r'\D'), '').length < 7) {
              setState(() => _phoneMissing = true);
              return;
            }
            _showTicket(lines);
          },
          icon: const Icon(Icons.receipt_long_outlined),
          label: Text(_sending ? 'Guardando tu pedido…' : 'Hacer el pedido · ${money(total)}'),
        ),
        // Dónde recoger (0.16.9): la dirección del local
        if (widget.store.shownAddress != null) ...[
          const SizedBox(height: AppSpace.sm),
          _CartNotice(icon: Icons.place_outlined, tone: AppTone.info, title: 'Para recoger', text: widget.store.shownAddress!),
        ],
        // Cómo pagarle al negocio (0.16.0)
        if (widget.store.look.payment != null) ...[
          const SizedBox(height: AppSpace.sm),
          _CartNotice(icon: Icons.payments_outlined, tone: AppTone.info, title: 'Cómo pagar', text: widget.store.look.payment!),
        ],
        const SizedBox(height: AppSpace.sm),
        Text(
          'Te mostramos tu comprobante y lo envías por WhatsApp. La tienda te confirma el precio final y la entrega.',
          textAlign: TextAlign.center,
          style: AppText.caption(context),
        ),
      ];
    }

    if (!widget.pinnedFooter) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          body,
          if (lines.isNotEmpty) ...[const SizedBox(height: AppSpace.lg), ...footer],
        ],
      );
    }
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

/// Aviso dentro del carrito: «Estamos cerrados» o «Cómo pagar» (0.16.0)
class _CartNotice extends StatelessWidget {
  final IconData icon;
  final AppTone tone;
  final String title;
  final String text;
  const _CartNotice({required this.icon, required this.tone, required this.title, required this.text});

  @override
  Widget build(BuildContext context) {
    final t = ToneColors.of(context, tone);
    return Container(
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(color: t.soft, borderRadius: BorderRadius.circular(AppRadius.card)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: t.strong),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppText.body(context, weight: FontWeight.w700, color: t.text)),
                const SizedBox(height: 2),
                SelectableText(text, style: AppText.small(context, color: t.text)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Un producto del pedido: foto, nombre, talla y color, cantidad y precio
class _CartItem extends StatelessWidget {
  final CartLine line;
  final String Function(num) money;
  final VoidCallback onMinus;
  final VoidCallback? onPlus;

  const _CartItem({required this.line, required this.money, required this.onMinus, required this.onPlus});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l = line;
    final v = l.variant;
    final hasSwatch = ColorSwatchDot.hasSwatch(v?.hex);
    Widget tag(Widget child) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.control - 2),
            border: Border.all(color: c.lineStrong),
          ),
          child: child,
        );
    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.md),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.line))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CartThumb(product: l.product, imageUrl: l.variant?.imageUrl, size: 64),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.product.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.body(context, weight: FontWeight.w600)),
                if (v != null && (v.size != null || v.color != null || hasSwatch)) ...[
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      if (v.size != null) tag(Text('${v.sizeName} ${v.size}', style: AppText.caption(context, color: c.inkMuted))),
                      if (v.color != null || hasSwatch)
                        tag(Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (hasSwatch) ...[ColorSwatchDot(hex: v.hex, size: 10), const SizedBox(width: 4)],
                            Text(v.color ?? 'Color', style: AppText.caption(context, color: c.inkMuted)),
                          ],
                        )),
                    ],
                  ),
                ],
                const SizedBox(height: AppSpace.sm),
                Row(
                  children: [
                    _QtyButton(
                      tooltip: l.quantity == 1 ? 'Quitar del pedido' : 'Quitar uno',
                      icon: l.quantity == 1 ? Icons.delete_outline : Icons.remove_outlined,
                      onTap: onMinus,
                    ),
                    SizedBox(
                      width: 28,
                      child: Text('${l.quantity}', textAlign: TextAlign.center, style: AppText.body(context, weight: FontWeight.w700)),
                    ),
                    _QtyButton(tooltip: 'Agregar uno', icon: Icons.add_outlined, onTap: onPlus),
                    const Spacer(),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(money(l.subtotal), style: AppText.body(context, weight: FontWeight.w700)),
                        if (l.quantity > 1)
                          Text(l.wholesale ? 'Por mayor: ${money(l.unitPrice)} c/u' : '${money(l.unitPrice)} c/u',
                              style: AppText.caption(context, color: l.wholesale ? context.colors.success : null)),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Botón pequeño con borde para sumar o restar
class _QtyButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final VoidCallback? onTap;

  const _QtyButton({required this.tooltip, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.control),
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.control),
            border: Border.all(color: c.lineStrong),
          ),
          child: Icon(icon, size: 16, color: onTap == null ? c.inkFaint : c.ink),
        ),
      ),
    );
  }
}

/// La foto del producto en el pedido: la del color elegido o la principal (o un ícono)
class _CartThumb extends StatelessWidget {
  final StoreProduct product;
  final String? imageUrl;
  final double size;

  const _CartThumb({required this.product, this.imageUrl, required this.size});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final url = imageUrl ?? product.imageUrl;
    final icon = NoPhotoIcon(size: size * 0.45, color: c.inkFaint);
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.control + 2),
      child: SizedBox(
        width: size,
        height: size,
        child: ColoredBox(
          color: c.surfaceMuted,
          child: url != null
              ? Image.network(url, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Center(child: icon))
              : Center(child: icon),
        ),
      ),
    );
  }
}

/// Las fotos del pedido encimadas (hasta 3), para el resumen del paso 2
class _ThumbStack extends StatelessWidget {
  final List<CartLine> lines;

  const _ThumbStack({required this.lines});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final shown = lines.take(3).toList();
    const size = 36.0;
    const step = 26.0;
    return SizedBox(
      width: size + step * (shown.length - 1),
      height: size,
      child: Stack(
        children: [
          for (var i = 0; i < shown.length; i++)
            Positioned(
              left: step * i,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.control + 4),
                  border: Border.all(color: c.surface, width: 2),
                ),
                child: _CartThumb(product: shown[i].product, imageUrl: shown[i].variant?.imageUrl, size: size - 4),
              ),
            ),
        ],
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


/// Foto pequeña de una fila (Mercado y Menú)
class _RowThumb extends StatelessWidget {
  final String? url;
  final double size;
  const _RowThumb({required this.url, required this.size});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.tile),
      child: SizedBox(
        width: size,
        height: size,
        child: url == null
            ? ColoredBox(color: c.surfaceMuted, child: Icon(Icons.inventory_2_outlined, color: c.inkFaint, size: size * 0.4))
            : Image.network(url!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => ColoredBox(color: c.surfaceMuted)),
      ),
    );
  }
}

/// Precio de una fila, con el de antes tachado y «Destacado»
class _RowPrice extends StatelessWidget {
  final StoreProduct product;
  final String currency;
  final bool featured;
  const _RowPrice({required this.product, required this.currency, required this.featured});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = product;
    return Wrap(
      spacing: AppSpace.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('${p.variants.isNotEmpty && p.variants.any((v) => v.extra > 0) ? 'Desde ' : ''}${CurrencyFormatter.formatIn(p.price, currency)}',
            style: AppText.body(context, weight: FontWeight.w700, color: c.ink)),
        if (p.onOffer)
          Text(CurrencyFormatter.formatIn(p.oldPrice!, currency),
              style: AppText.small(context, color: c.inkFaint).copyWith(decoration: TextDecoration.lineThrough)),
        if (featured) const StatusPill('Destacado', tone: AppTone.accent, compact: true),
      ],
    );
  }
}

/// «+» o «− 2 +» al lado de cada producto (Mercado y Menú)
class _RowAdd extends StatelessWidget {
  final int quantity;
  final VoidCallback onAdd;
  final VoidCallback onRemove;
  const _RowAdd({required this.quantity, required this.onAdd, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (quantity == 0) {
      return IconButton.filled(
        tooltip: 'Agregar',
        onPressed: onAdd,
        style: IconButton.styleFrom(backgroundColor: c.accent, foregroundColor: c.onAccent),
        icon: const Icon(Icons.add),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton.outlined(tooltip: 'Quitar uno', onPressed: onRemove, icon: const Icon(Icons.remove, size: 18)),
        SizedBox(width: 28, child: Text('$quantity', textAlign: TextAlign.center, style: AppText.title(context))),
        IconButton.filled(
          tooltip: 'Agregar otro',
          onPressed: onAdd,
          style: IconButton.styleFrom(backgroundColor: c.accent, foregroundColor: c.onAccent),
          icon: const Icon(Icons.add, size: 18),
        ),
      ],
    );
  }
}

/// Dibujo de un producto sin foto en la tienda (0.16.3): una caja, que sirve para
/// cualquier negocio (antes era una percha, que solo le quedaba a la ropa)
class NoPhotoIcon extends StatelessWidget {
  final double size;
  final Color color;

  const NoPhotoIcon({super.key, required this.size, required this.color});

  static const icon = Icons.inventory_2_outlined;

  @override
  Widget build(BuildContext context) => Icon(icon, size: size, color: color);
}
