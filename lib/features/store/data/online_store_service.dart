import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/coupons.dart';
import '../../../core/utils/business_clock.dart';

/// Dirección pública de las tiendas
const storeBaseUrl = 'https://stockealo.online/tienda';

/// Configuración de la tienda en línea de un negocio (Stockealo Pro)
class OnlineStoreConfig {
  final String slug;
  final bool enabled;

  /// WhatsApp que recibe los pedidos: internacional, solo dígitos
  final String whatsapp;
  final String? welcome;
  final bool showStock;

  /// Plantilla: [StoreTemplate.classic] o [StoreTemplate.fashion]
  final String template;

  /// Título grande de la portada (plantilla Moda): «Chaquetas y abrigos para el frío»
  final String? heroTitle;

  /// La portada muestra fotos de los productos (plantilla Moda)
  final bool heroPhotos;

  /// Foto de portada propia (0.15.0): su logo grande, un banner o una foto del local
  final String? heroImageUrl;

  /// Personalizar tienda (0.16.0): color, modo oscuro, destacados, horario y pago
  final StoreLook look;

  const OnlineStoreConfig({
    required this.slug,
    required this.enabled,
    required this.whatsapp,
    this.welcome,
    this.showStock = false,
    this.template = StoreTemplate.classic,
    this.heroTitle,
    this.heroPhotos = true,
    this.heroImageUrl,
    this.look = StoreLook.none,
  });

  factory OnlineStoreConfig.fromJson(Map<String, dynamic> j) => OnlineStoreConfig(
        slug: j['slug'] as String,
        enabled: j['enabled'] == true,
        whatsapp: j['whatsapp'] as String? ?? '',
        welcome: j['welcome'] as String?,
        showStock: j['show_stock'] == true,
        template: StoreTemplate.of(j['template'] as String?),
        heroTitle: j['hero_title'] as String?,
        heroPhotos: j['hero_photos'] != false,
        heroImageUrl: j['hero_image_url'] as String?,
        look: StoreLook.fromJson(j['look']),
      );

  String get url => '$storeBaseUrl/$slug';

  /// Link que abre la tienda con ese producto primero y resaltado (0.16.0, fase 3)
  String productUrl(String productId) => '$url?p=$productId';

  /// Dirección del QR del mostrador: con ?src=qr para contar esas visitas (fase 4)
  String get qrUrl => '$url?src=qr';
}

/// Estadísticas de la tienda (0.16.0, fase 4)
class StoreStatsDay {
  final DateTime day;
  final int visits;
  final int adds;
  final int orders;
  final double total;
  const StoreStatsDay({required this.day, this.visits = 0, this.adds = 0, this.orders = 0, this.total = 0});
}

class StoreStatsItem {
  final String productId;
  final String name;
  final double quantity;
  final double total;
  const StoreStatsItem({required this.productId, required this.name, this.quantity = 0, this.total = 0});
}

class StoreStats {
  final List<StoreStatsDay> days;
  final List<StoreStatsItem> topOrdered;

  /// Lo más agregado al carrito ([StoreStatsItem.quantity] = veces)
  final List<StoreStatsItem> topAdded;
  final int fromShared;
  final int fromQr;

  const StoreStats({this.days = const [], this.topOrdered = const [], this.topAdded = const [], this.fromShared = 0, this.fromQr = 0});

  int get visits => days.fold(0, (s, d) => s + d.visits);
  int get adds => days.fold(0, (s, d) => s + d.adds);
  int get orders => days.fold(0, (s, d) => s + d.orders);
  double get total => days.fold(0.0, (s, d) => s + d.total);

  /// Visitas que terminan en pedido, de 0 a 1 (null sin visitas)
  double? get conversion => visits == 0 ? null : orders / visits;

  /// Cuántos pedidos tuvo un producto (para «se agrega mucho y se pide poco»)
  double orderedOf(String productId) => topOrdered.where((i) => i.productId == productId).firstOrNull?.quantity ?? 0;

  /// La nube puede mandar los números como número o como texto
  static double _n(Object? v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;

  factory StoreStats.fromJson(Map<String, dynamic> j) => StoreStats(
        days: [
          for (final d in (j['days'] as List? ?? const []))
            StoreStatsDay(
              day: DateTime.tryParse('${(d as Map)['day']}') ?? appNow(),
              visits: _n(d['visits']).round(),
              adds: _n(d['adds']).round(),
              orders: _n(d['orders']).round(),
              total: _n(d['total']),
            ),
        ],
        topOrdered: [
          for (final t in (j['top_ordered'] as List? ?? const []))
            StoreStatsItem(
              productId: '${(t as Map)['product_id'] ?? ''}',
              name: '${t['name'] ?? 'Producto'}',
              quantity: _n(t['qty']),
              total: _n(t['total']),
            ),
        ],
        topAdded: [
          for (final t in (j['top_added'] as List? ?? const []))
            StoreStatsItem(productId: '${(t as Map)['product_id'] ?? ''}', name: '${t['name'] ?? 'Producto'}', quantity: _n(t['adds'])),
        ],
        fromShared: _n(j['shared']).round(),
        fromQr: _n(j['qr']).round(),
      );
}

/// Las plantillas de la tienda
abstract final class StoreTemplate {
  /// La de siempre, mejorada: clara, con el color del negocio arriba
  static const classic = 'clasica';

  /// Oscura, de portada grande, con filtros por talla, color y precio (ropa, calzado)
  static const fashion = 'moda';

  /// Lista compacta con botón + (tiendas de barrio, misceláneas, droguerías) (0.16.0)
  static const market = 'mercado';

  /// Cada categoría es una sección de la carta (comidas, panaderías, heladerías) (0.16.0)
  static const menu = 'menu';

  /// Fotos grandes y mucho espacio (joyería, cosméticos, artesanías) (0.16.0)
  static const boutique = 'boutique';

  static const all = [classic, fashion, market, menu, boutique];

  static String of(String? v) => all.contains(v) ? v! : classic;

  static String label(String v) => switch (v) {
        fashion => 'Moda',
        market => 'Mercado',
        menu => 'Menú',
        boutique => 'Boutique',
        _ => 'Clásica',
      };

  static String description(String v) => switch (v) {
        fashion => 'Oscura, con portada grande, filtros por talla, color y precio, y ofertas. Para ropa y calzado.',
        market => 'Lista compacta con botón +: se ven muchos productos. Para tiendas de barrio, misceláneas y droguerías.',
        menu => 'Cada categoría es una sección de la carta, con la descripción del plato. Para comidas, panaderías y heladerías.',
        boutique => 'Fotos grandes y mucho espacio; lo destacado va primero en grande. Para joyería, cosméticos y artesanías.',
        _ => 'Clara, con el color de tu negocio arriba. Para cualquier negocio.',
      };
}

/// Horario de la tienda (0.16.0): días (1 = lunes … 7 = domingo) y la hora de abrir
/// y de cerrar ("07:00", "20:00"). Fuera del horario se ve «Cerrado», pero los
/// pedidos se reciben con aviso (decisión del dueño, 15 nov).
class StoreSchedule {
  final Set<int> days;
  final String open;
  final String close;

  const StoreSchedule({required this.days, required this.open, required this.close});

  static const _dayNames = ['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'];
  static const dayShort = ['L', 'M', 'X', 'J', 'V', 'S', 'D'];

  static int? _minutes(String hhmm) {
    final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(hhmm.trim());
    if (m == null) return null;
    final h = int.parse(m.group(1)!), min = int.parse(m.group(2)!);
    return h > 23 || min > 59 ? null : h * 60 + min;
  }

  static StoreSchedule? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final days = <int>{
      for (final d in (raw['days'] as List? ?? const []))
        if (d is num && d >= 1 && d <= 7) d.toInt(),
    };
    final open = '${raw['open'] ?? ''}', close = '${raw['close'] ?? ''}';
    if (days.isEmpty || _minutes(open) == null || _minutes(close) == null) return null;
    return StoreSchedule(days: days, open: open, close: close);
  }

  Map<String, dynamic> toJson() => {'days': (days.toList()..sort()), 'open': open, 'close': close};

  /// Abierto a esta hora. Si cierra pasada la medianoche (18:00 a 02:00), la madrugada
  /// cuenta para el día anterior.
  bool isOpen(DateTime now) {
    final o = _minutes(open)!, c = _minutes(close)!;
    final t = now.hour * 60 + now.minute;
    if (o == c) return days.contains(now.weekday);
    if (o < c) return days.contains(now.weekday) && t >= o && t < c;
    final yesterday = now.weekday == 1 ? 7 : now.weekday - 1;
    return (days.contains(now.weekday) && t >= o) || (days.contains(yesterday) && t < c);
  }

  /// "7 a. m.", "8:30 p. m."
  static String hourText(String hhmm) {
    final m = _minutes(hhmm) ?? 0;
    final h = m ~/ 60, min = m % 60;
    final h12 = h % 12 == 0 ? 12 : h % 12;
    return '$h12${min == 0 ? '' : ':${min.toString().padLeft(2, '0')}'} ${h < 12 ? 'a. m.' : 'p. m.'}';
  }

  /// "Lun a sáb · 7 a. m. – 8 p. m."
  String get text {
    final sorted = days.toList()..sort();
    String cap(String s) => s[0].toUpperCase() + s.substring(1, 3);
    final consecutive = sorted.length > 1 && sorted.last - sorted.first == sorted.length - 1;
    final which = sorted.length == 7
        ? 'Todos los días'
        : consecutive
            ? '${cap(_dayNames[sorted.first - 1])} a ${_dayNames[sorted.last - 1].substring(0, 3)}'
            : sorted.map((d) => cap(_dayNames[d - 1])).join(', ');
    return '$which · ${hourText(open)} – ${hourText(close)}';
  }

  /// «Abierto · cierra 8 p. m.» o «Cerrado · abre el lunes 7 a. m.»
  String status(DateTime now) {
    if (isOpen(now)) return 'Abierto · cierra ${hourText(close)}';
    final o = _minutes(open)!;
    for (var i = 0; i < 8; i++) {
      final d = now.add(Duration(days: i));
      if (!days.contains(d.weekday)) continue;
      if (i == 0 && now.hour * 60 + now.minute >= o) continue;
      final when = i == 0 ? 'hoy' : i == 1 ? 'mañana' : 'el ${_dayNames[d.weekday - 1]}';
      return 'Cerrado · abre $when ${hourText(open)}';
    }
    return 'Cerrado';
  }
}

/// «Personalizar tienda» (0.16.0)
class StoreLook {
  /// Color propio de la tienda (#RRGGBB); null = el del negocio
  final String? accent;

  /// Modo oscuro en cualquier plantilla (Moda siempre es oscura)
  final bool dark;

  /// Hasta 6 productos que salen primero
  final List<String> featured;
  final StoreSchedule? schedule;

  /// Cómo pagarle al negocio («Nequi 300 123 4567 a nombre de Rosa»): sale al final del pedido
  final String? payment;

  /// Al entrar pregunta «¿Tienes 18 años o más?» (licoreras y vapers, fase 2a)
  final bool adult;

  /// Hashtags propios del negocio para Instagram (fase 3): «#VariedadesRosita»
  final List<String> hashtags;

  /// Íconos en los filtros de categoría (0.16.8, #28); apagado = solo el nombre
  final bool icons;

  const StoreLook({
    this.accent,
    this.dark = false,
    this.featured = const [],
    this.schedule,
    this.payment,
    this.adult = false,
    this.hashtags = const [],
    this.icons = true,
  });

  static const maxHashtags = 10;

  /// «#VariedadesRosita, domicilios» → ['#VariedadesRosita', '#domicilios']: cada palabra
  /// separada por coma o espacio queda como un hashtag limpio, sin repetir
  static List<String> parseHashtags(String raw) {
    final out = <String>[];
    for (final part in raw.split(RegExp(r'[\s,;]+'))) {
      final tag = cleanHashtag(part);
      if (tag != null && !out.any((t) => t.toLowerCase() == tag.toLowerCase())) out.add(tag);
      if (out.length >= maxHashtags) break;
    }
    return out;
  }

  /// '#Mi_Tienda' válido, o null
  static String? cleanHashtag(String raw) {
    final body = raw.trim().replaceFirst(RegExp(r'^#+'), '').replaceAll(RegExp(r'[^0-9A-Za-zÁÉÍÓÚÜÑáéíóúüñ_]'), '');
    if (body.isEmpty || body.length > 40) return null;
    return '#$body';
  }

  /// El nombre del negocio como hashtag: «Variedades Rosita» → «#VariedadesRosita»
  static String? nameHashtag(String businessName) => cleanHashtag(
        businessName.split(RegExp(r'\s+')).map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1)).join(),
      );

  static const none = StoreLook();
  static const maxFeatured = 6;

  static StoreLook fromJson(Object? raw) {
    if (raw is! Map) return none;
    final accent = '${raw['accent'] ?? ''}';
    final payment = '${raw['payment'] ?? ''}'.trim();
    return StoreLook(
      accent: RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(accent) ? accent.toUpperCase() : null,
      dark: raw['dark'] == true,
      featured: [
        for (final f in (raw['featured'] as List? ?? const []))
          if (f is String && f.isNotEmpty) f,
      ].take(maxFeatured).toList(),
      schedule: StoreSchedule.fromJson(raw['schedule']),
      payment: payment.isEmpty ? null : payment,
      adult: raw['adult'] == true,
      icons: raw['icons'] != false,
      hashtags: [
        for (final h in (raw['hashtags'] as List? ?? const []))
          if (h is String && cleanHashtag(h) != null) cleanHashtag(h)!,
      ].take(maxHashtags).toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        if (accent != null) 'accent': accent,
        'dark': dark,
        'featured': featured.take(maxFeatured).toList(),
        if (schedule != null) 'schedule': schedule!.toJson(),
        if (payment != null) 'payment': payment,
        'adult': adult,
        'icons': icons,
        if (hashtags.isNotEmpty) 'hashtags': hashtags.take(maxHashtags).toList(),
      };

  StoreLook copyWith({String? accent, bool clearAccent = false, bool? dark, List<String>? featured, StoreSchedule? schedule,
          bool clearSchedule = false, String? payment, bool clearPayment = false, bool? adult, List<String>? hashtags, bool? icons}) =>
      StoreLook(
        accent: clearAccent ? null : accent ?? this.accent,
        dark: dark ?? this.dark,
        featured: featured ?? this.featured,
        schedule: clearSchedule ? null : schedule ?? this.schedule,
        payment: clearPayment ? null : payment ?? this.payment,
        adult: adult ?? this.adult,
        hashtags: hashtags ?? this.hashtags,
        icons: icons ?? this.icons,
      );
}

/// Una talla, un color o los dos de un producto de la tienda
class StoreVariant {
  final String id;
  final String? size;
  final String? color;

  /// Muestra del color (#RRGGBB o 'multi')
  final String? hex;
  final double extra;
  final int? stock;

  /// Agotada: se ve tachada y no se puede elegir
  final bool soldOut;

  /// Quedan 3 o menos: «Quedan pocas, pide pronto»
  final bool few;

  /// Foto de este color (0.15.0); null = la del producto
  final String? imageUrl;

  /// Cómo se llaman las dos listas (0.16.0): «Talla» y «Color», o «Nicotina» y «Sabor»
  final String sizeName;
  final String optionName;

  const StoreVariant({
    required this.id,
    this.size,
    this.color,
    this.hex,
    this.extra = 0,
    this.stock,
    this.soldOut = false,
    this.few = false,
    this.imageUrl,
    this.sizeName = 'Talla',
    this.optionName = 'Color',
  });

  String get label => [if (size != null) size!, if (color != null) color!].join(' · ');

  static String? _clean(Object? v) {
    final t = (v as String? ?? '').trim();
    return t.isEmpty ? null : t;
  }

  factory StoreVariant.fromJson(Map<String, dynamic> j) => StoreVariant(
        id: j['id'] as String,
        size: _clean(j['size']),
        color: _clean(j['color']),
        hex: _clean(j['hex']),
        extra: (j['extra'] as num?)?.toDouble() ?? 0,
        stock: (j['stock'] as num?)?.toInt(),
        soldOut: j['sold_out'] == true,
        few: j['few'] == true,
        imageUrl: (j['image'] as String?)?.startsWith('https://') == true ? j['image'] as String : null,
        sizeName: _clean(j['size_name']) ?? 'Talla',
        optionName: _clean(j['option_name']) ?? 'Color',
      );
}

/// Promoción vigente de un producto en la tienda (0.13.4)
class StorePromo {
  final String name;
  final bool isPercent;
  final double percentOff;
  final int buyQty;
  final int payQty;
  final DateTime? endsAt;

  const StorePromo({
    required this.name,
    required this.isPercent,
    this.percentOff = 0,
    this.buyQty = 2,
    this.payQty = 1,
    this.endsAt,
  });

  /// En la cinta: «−20 %» o «2×1»
  String get badge => isPercent ? '−${percentOff.round()} %' : '$buyQty×$payQty';

  static StorePromo? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final j = Map<String, dynamic>.from(raw);
    return StorePromo(
      name: j['name'] as String? ?? 'Promoción',
      isPercent: j['kind'] == 'PERCENT',
      percentOff: (j['percent_off'] as num?)?.toDouble() ?? 0,
      buyQty: (j['buy_qty'] as num?)?.toInt() ?? 2,
      payQty: (j['pay_qty'] as num?)?.toInt() ?? 1,
      endsAt: DateTime.tryParse('${j['ends_at'] ?? ''}')?.toLocal(),
    );
  }
}

/// Un producto de la tienda pública
class StoreProduct {
  final String id;
  final String name;
  final String category;
  final double price;
  final String? imageUrl;

  /// Descripción del producto (la plantilla Menú la muestra debajo del nombre) (0.16.0)
  final String? description;

  /// Marca (0.16.0); la tienda filtra por marca cuando hay varias
  final String? brand;

  /// Unidades disponibles; null si el negocio no las muestra
  final int? stock;

  /// Precio de antes (se ve tachado con «Oferta»); null si no está en oferta
  final double? oldPrice;

  /// Tallas y colores (vacío si el producto no tiene); las agotadas vienen con [StoreVariant.soldOut]
  final List<StoreVariant> variants;

  /// Quedan 3 o menos (producto sin tallas ni colores)
  final bool few;

  /// Promoción vigente (con % el [price] ya viene rebajado y [oldPrice] es el de antes)
  final StorePromo? promo;

  const StoreProduct({
    required this.id,
    required this.name,
    required this.category,
    required this.price,
    this.imageUrl,
    this.description,
    this.brand,
    this.stock,
    this.oldPrice,
    this.variants = const [],
    this.few = false,
    this.promo,
  });

  /// Tallas y colores que todavía se pueden pedir
  List<StoreVariant> get available => variants.where((v) => !v.soldOut).toList();

  /// «Quedan pocas, pide pronto»: el producto o alguna de sus tallas
  bool get runningLow => variants.isEmpty ? few : available.any((v) => v.few);

  bool get onOffer => (oldPrice ?? 0) > price;

  /// Cómo se llaman sus listas: «Talla»/«Color» o «Nicotina»/«Sabor» (0.16.0)
  String get sizeName => variants.firstOrNull?.sizeName ?? 'Talla';
  String get optionName => variants.firstOrNull?.optionName ?? 'Color';
  List<String> get sizes => [for (final s in available.map((v) => v.size).whereType<String>().toSet()) s];
  List<String> get colorHexes => [for (final h in available.map((v) => v.hex).whereType<String>().toSet()) h];

  factory StoreProduct.fromJson(Map<String, dynamic> j) {
    final promo = StorePromo.fromJson(j['promo']);
    final base = (j['price'] as num?)?.toDouble() ?? 0;
    final before = (j['old_price'] as num?)?.toDouble();
    // Con % de descuento: se cobra rebajado y se tacha el precio normal
    final pct = promo != null && promo.isPercent && promo.percentOff > 0;
    final price = pct ? (base * (100 - promo.percentOff) / 100).roundToDouble() : base;
    return StoreProduct(
        id: j['id'] as String,
        name: j['name'] as String? ?? '',
        category: (j['category'] as String? ?? '').trim(),
        price: price,
        imageUrl: j['image_url'] as String?,
        description: (j['description'] as String?)?.trim().isEmpty == true ? null : (j['description'] as String?)?.trim(),
        brand: (j['brand'] as String?)?.trim().isEmpty == true ? null : (j['brand'] as String?)?.trim(),
        stock: (j['stock'] as num?)?.toInt(),
        oldPrice: pct ? ((before ?? 0) > base ? before : base) : before,
        few: j['few'] == true,
        promo: promo,
        variants: [
          for (final v in (j['variants'] as List? ?? const [])) StoreVariant.fromJson(Map<String, dynamic>.from(v as Map)),
        ],
      );
  }
}

/// Lo que ve el comprador en stockealo.online/tienda/<slug>
class PublicStore {
  final String slug;
  final String whatsapp;
  final String? welcome;
  final String businessName;
  final String? logoUrl;
  final String? color;
  final String currency;
  final List<StoreProduct> products;
  final String template;
  final String? heroTitle;

  /// La portada muestra fotos de los productos
  final bool heroPhotos;

  /// Foto de portada propia del negocio (0.15.0); null = la portada de siempre
  final String? heroImageUrl;

  /// Personalizar tienda (0.16.0)
  final StoreLook look;

  /// Ícono de cada categoría, por nombre en minúscula (0.16.8, #28)
  final Map<String, String> categoryIcons;

  const PublicStore({
    required this.slug,
    required this.whatsapp,
    required this.businessName,
    required this.currency,
    required this.products,
    this.welcome,
    this.logoUrl,
    this.color,
    this.template = StoreTemplate.classic,
    this.heroTitle,
    this.heroPhotos = true,
    this.heroImageUrl,
    this.look = StoreLook.none,
    this.categoryIcons = const {},
  });

  /// El ícono de una categoría de la tienda; null si no tiene o están apagados
  String? iconOf(String category) => look.icons ? categoryIcons[category.trim().toLowerCase()] : null;

  /// La misma tienda con otro diseño (la vista previa de «Personalizar»)
  PublicStore copyWith({String? template, String? heroTitle, bool? heroPhotos, String? heroImageUrl, StoreLook? look, String? welcome}) =>
      PublicStore(
        slug: slug,
        whatsapp: whatsapp,
        businessName: businessName,
        currency: currency,
        products: products,
        welcome: welcome ?? this.welcome,
        logoUrl: logoUrl,
        color: color,
        template: template ?? this.template,
        heroTitle: heroTitle ?? this.heroTitle,
        heroPhotos: heroPhotos ?? this.heroPhotos,
        heroImageUrl: heroImageUrl ?? this.heroImageUrl,
        look: look ?? this.look,
        categoryIcons: categoryIcons,
      );

  /// El color de la tienda: el propio o el del negocio
  String? get accentHex => look.accent ?? color;

  /// Los destacados primero (en el orden elegido) y después los demás
  List<StoreProduct> get ordered {
    if (look.featured.isEmpty) return products;
    final rank = {for (final (i, id) in look.featured.indexed) id: i};
    final first = products.where((p) => rank.containsKey(p.id)).toList()..sort((a, b) => rank[a.id]!.compareTo(rank[b.id]!));
    return [...first, ...products.where((p) => !rank.containsKey(p.id))];
  }

  bool isFeatured(StoreProduct p) => look.featured.contains(p.id);

  factory PublicStore.fromJson(Map<String, dynamic> j) {
    final b = Map<String, dynamic>.from(j['business'] as Map? ?? const {});
    return PublicStore(
      slug: j['slug'] as String,
      whatsapp: j['whatsapp'] as String? ?? '',
      welcome: j['welcome'] as String?,
      businessName: b['name'] as String? ?? 'Tienda',
      logoUrl: b['logo_url'] as String?,
      color: b['color'] as String?,
      currency: b['currency'] as String? ?? 'COP',
      template: StoreTemplate.of(j['template'] as String?),
      heroTitle: j['hero_title'] as String?,
      heroPhotos: j['hero_photos'] != false,
      heroImageUrl: (j['hero_image_url'] as String?)?.startsWith('https://') == true ? j['hero_image_url'] as String : null,
      look: StoreLook.fromJson(j['look']),
      categoryIcons: {
        for (final e in (j['category_icons'] as Map? ?? const {}).entries)
          if (e.value is String && (e.value as String).isNotEmpty) '${e.key}': e.value as String,
      },
      products: [
        for (final p in (j['products'] as List? ?? const [])) StoreProduct.fromJson(Map<String, dynamic>.from(p as Map)),
      ],
    );
  }

  /// Marcas, sin repetir, en orden alfabético (0.16.0)
  List<String> get brands => {for (final p in products) if (p.brand != null) p.brand!}.toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

  /// Categorías en el orden en que aparecen
  List<String> get categories => [
        for (final c in products.map((p) => p.category).where((c) => c.isNotEmpty).toSet()) c,
      ];
}

/// Un renglón del carrito (con la talla o el color elegido, si tiene)
class CartLine {
  final StoreProduct product;
  final int quantity;
  final StoreVariant? variant;

  const CartLine(this.product, this.quantity, [this.variant]);

  /// El producto y la variante, para no mezclar la talla S con la M
  String get key => keyOf(product, variant);
  static String keyOf(StoreProduct p, StoreVariant? v) => v == null ? p.id : '${p.id}:${v.id}';
  String get name => variant == null ? product.name : '${product.name} (${variant!.label})';
  double get unitPrice => product.price + (variant?.extra ?? 0);

  /// Con «lleva X, paga Y» se descuentan las unidades de regalo (0.13.4)
  double get subtotal {
    final promo = product.promo;
    if (promo == null || promo.isPercent || promo.buyQty <= promo.payQty) return unitPrice * quantity;
    final free = (quantity ~/ promo.buyQty) * (promo.buyQty - promo.payQty);
    return unitPrice * (quantity - free);
  }
  int? get stock => variant?.stock ?? product.stock;
}

class OnlineStoreException implements Exception {
  final String message;

  const OnlineStoreException(this.message);

  @override
  String toString() => message;
}

/// Tienda en línea: configuración (app) y lectura pública (web)
class OnlineStoreService {
  OnlineStoreService._();
  static final OnlineStoreService instance = OnlineStoreService._();

  SupabaseClient? get _client => SupabaseService.instance.client;

  Future<OnlineStoreConfig?> getMine(String businessId) async {
    final client = _client;
    if (client == null || client.auth.currentSession == null) {
      throw const OnlineStoreException('Necesitas iniciar sesión y tener internet.');
    }
    await SupabaseService.instance.ensureFreshSession();
    try {
      final data = await client.rpc('get_my_store', params: {'p_business_id': businessId});
      return data == null ? null : OnlineStoreConfig.fromJson(Map<String, dynamic>.from(data as Map));
    } on PostgrestException catch (e) {
      throw OnlineStoreException(errorMessage(e.message));
    }
  }

  Future<OnlineStoreConfig> save({
    required String businessId,
    required String slug,
    required bool enabled,
    required String whatsapp,
    String? welcome,
    bool showStock = false,
    String template = StoreTemplate.classic,
    String? heroTitle,
    bool heroPhotos = true,
    String? heroImageUrl,
  }) async {
    final client = _client;
    if (client == null || client.auth.currentSession == null) {
      throw const OnlineStoreException('Necesitas iniciar sesión y tener internet.');
    }
    final params = {
      'p_business_id': businessId,
      'p_slug': slug,
      'p_enabled': enabled,
      'p_whatsapp': whatsapp,
      'p_welcome': welcome,
      'p_show_stock': showStock,
    };
    // De la versión más nueva a la más vieja: si la nube no tiene una función (PGRST202),
    // se prueba la anterior y se guarda lo que se pueda
    final tries = [
      {...params, 'p_template': template, 'p_hero_title': heroTitle, 'p_hero_photos': heroPhotos, 'p_hero_image_url': heroImageUrl},
      {...params, 'p_template': template, 'p_hero_title': heroTitle, 'p_hero_photos': heroPhotos},
      {...params, 'p_template': template, 'p_hero_title': heroTitle},
      params,
    ];
    for (var i = 0; i < tries.length; i++) {
      try {
        final data = await client.rpc('save_my_store', params: tries[i]);
        return OnlineStoreConfig.fromJson(Map<String, dynamic>.from(data as Map));
      } on PostgrestException catch (e) {
        if (e.code == 'PGRST202' && i < tries.length - 1) continue;
        throw OnlineStoreException(errorMessage(e.message));
      }
    }
    throw const OnlineStoreException('No se pudo guardar la tienda.');
  }

  /// Guarda «Personalizar tienda» (0.16.0)
  Future<StoreLook> saveLook({required String businessId, required StoreLook look}) async {
    final client = _client;
    if (client == null || client.auth.currentSession == null) {
      throw const OnlineStoreException('Necesitas iniciar sesión y tener internet.');
    }
    try {
      final data = await client.rpc('save_my_store_look', params: {'p_business_id': businessId, 'p_look': look.toJson()});
      return StoreLook.fromJson(data);
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST202') throw const OnlineStoreException('Actualiza la nube para guardar el diseño de la tienda.');
      throw OnlineStoreException(errorMessage(e.message));
    }
  }

  /// Cuenta una visita, un producto agregado o de dónde llegó (fase 4). No guarda
  /// nada de quién visita y si falla no pasa nada.
  Future<void> track(String slug, String kind, {String? productId}) async {
    try {
      await _client?.rpc('track_store_event', params: {'p_slug': slug, 'p_kind': kind, 'p_product_id': productId});
    } catch (e) {
      debugPrint('No se pudo contar $kind: $e');
    }
  }

  /// Números de la tienda entre [from] y [to] (incluidos)
  Future<StoreStats> stats(String businessId, {required DateTime from, required DateTime to}) async {
    final client = _client;
    if (client == null || client.auth.currentSession == null) {
      throw const OnlineStoreException('Necesitas iniciar sesión y tener internet.');
    }
    String day(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    try {
      final data = await client.rpc('get_store_stats', params: {'p_business_id': businessId, 'p_from': day(from), 'p_to': day(to)});
      return StoreStats.fromJson(Map<String, dynamic>.from(data as Map));
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST202') throw const OnlineStoreException('Actualiza la nube para ver las estadísticas.');
      throw OnlineStoreException(errorMessage(e.message));
    }
  }

  /// Tienda pública; null si no existe o no está disponible
  Future<PublicStore?> getPublic(String slug) async {
    final client = _client;
    if (client == null) throw const OnlineStoreException('No se pudo conectar. Revisa tu internet.');
    try {
      final data = await client.rpc('get_public_store', params: {'p_slug': slug});
      return data == null ? null : PublicStore.fromJson(Map<String, dynamic>.from(data as Map));
    } on PostgrestException catch (e) {
      debugPrint('Tienda pública: ${e.message}');
      throw const OnlineStoreException('No se pudo cargar la tienda. Inténtalo de nuevo.');
    }
  }

  // ---------------------------------------------------------------------------

  /// Nombre para la dirección a partir del nombre del negocio: "Tienda Doña Ana" → "tienda-dona-ana"
  static String suggestSlug(String businessName) {
    const accents = {'á': 'a', 'é': 'e', 'í': 'i', 'ó': 'o', 'ú': 'u', 'ü': 'u', 'ñ': 'n'};
    var s = businessName.toLowerCase().split('').map((ch) => accents[ch] ?? ch).join();
    s = s.replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
    if (s.length > 40) s = s.substring(0, 40).replaceAll(RegExp(r'-+$'), '');
    return s.length < 3 ? 'mi-tienda' : s;
  }

  /// Mismas reglas que el servidor
  static bool isValidSlug(String slug) =>
      RegExp(r'^[a-z0-9][a-z0-9-]{1,38}[a-z0-9]$').hasMatch(slug) &&
      !const ['app', 'admin', 'tienda', 'api', 'www', 'stockealo', 'soporte', 'ayuda'].contains(slug);

  /// Mensaje de WhatsApp con el pedido
  /// Guarda el pedido en la nube con su código por negocio (T-0001). Devuelve el código,
  /// o null si no se pudo (sin conexión o la nube aún no tiene pedidos): el pedido sigue
  /// por WhatsApp como antes. (0.13.4)
  ///
  /// Con cupón (0.16.0) la nube lo revisa y descuenta; si el cupón no sirve devuelve el
  /// motivo en `error` y el pedido NO se guarda (para que el comprador lo corrija).
  Future<({String? code, String? error})> createOrder({
    required String slug,
    required String customerName,
    String? customerPhone,
    String? note,
    required List<CartLine> lines,
    String? coupon,
    String Function(num)? money,
  }) async {
    final client = _client;
    if (client == null) return (code: null, error: null);
    try {
      final data = await client.rpc('create_store_order', params: {
        'p_slug': slug,
        'p_customer_name': customerName.trim(),
        'p_customer_phone': customerPhone?.trim(),
        'p_note': note?.trim(),
        'p_lines': [
          for (final l in lines)
            {
              'product_id': l.product.id,
              'variant_id': l.variant?.id,
              'variant_name': l.variant?.label,
              'name': l.name,
              'quantity': l.quantity,
              'unit_price': l.unitPrice,
              'subtotal': l.subtotal,
            },
        ],
        'p_total': lines.fold<double>(0, (s, l) => s + l.subtotal),
        if (coupon != null && coupon.isNotEmpty) 'p_coupon': CouponText.normalize(coupon),
      });
      return (code: (data as Map)['code'] as String?, error: null);
    } on PostgrestException catch (e) {
      if (e.message.contains('coupon_')) return (code: null, error: CouponText.error(e.message, money: money));
      debugPrint('No se pudo guardar el pedido: $e');
      return (code: null, error: null);
    } catch (e) {
      debugPrint('No se pudo guardar el pedido: $e');
      return (code: null, error: null);
    }
  }

  // --- Cupones de la tienda (0.16.0) -------------------------------------------

  /// Revisa un cupón en el carrito sin gastarlo. Lanza el motivo si no sirve.
  Future<Coupon> checkCoupon({
    required String slug,
    required String code,
    required double total,
    String? phone,
    String Function(num)? money,
  }) async {
    final client = _client;
    if (client == null) throw const CouponException('Necesitas conexión a internet para usar el cupón.');
    try {
      final data = Map<String, dynamic>.from(await client.rpc('check_store_coupon', params: {
        'p_slug': slug,
        'p_code': CouponText.normalize(code),
        'p_total': total,
        'p_phone': (phone ?? '').trim().isEmpty ? null : phone!.trim(),
      }) as Map);
      return Coupon.fromRow(data);
    } on PostgrestException catch (e) {
      throw CouponException(CouponText.error(e.message, money: money));
    } catch (e) {
      debugPrint('Cupón: $e');
      throw CouponException(CouponText.error(''));
    }
  }

  /// Los cupones del negocio (dueño o administrador)
  Future<List<Coupon>> myCoupons(String businessId) async {
    final client = _client;
    if (client == null) throw const CouponException('Necesitas conexión a internet para ver los cupones.');
    final rows = await client.rpc('list_my_store_coupons', params: {'p_business_id': businessId});
    return [for (final r in rows as List) Coupon.fromRow(Map<String, dynamic>.from(r as Map))];
  }

  /// Crea o cambia un cupón. Lanza [CouponException] con el motivo.
  Future<void> saveCoupon(String businessId, Coupon coupon) async {
    final client = _client;
    if (client == null) throw const CouponException('Necesitas conexión a internet para guardar el cupón.');
    try {
      await client.rpc('save_my_store_coupon', params: {
        'p_business_id': businessId,
        'p_id': coupon.id,
        'p_code': CouponText.normalize(coupon.code),
        'p_percent': coupon.percent,
        'p_amount': coupon.amount,
        'p_min_total': coupon.minTotal,
        'p_max_uses': coupon.maxUses,
        'p_expires_at': coupon.expiresAt?.toUtc().toIso8601String(),
        'p_active': coupon.active,
      });
    } on PostgrestException catch (e) {
      if (e.message.contains('not_allowed')) throw CouponException(errorMessage(e.message));
      throw CouponException(CouponText.error(e.message));
    }
  }

  Future<void> deleteCoupon(String businessId, String id) async {
    final client = _client;
    if (client == null) throw const CouponException('Necesitas conexión a internet para borrar el cupón.');
    await client.rpc('delete_my_store_coupon', params: {'p_business_id': businessId, 'p_id': id});
  }

  static String orderMessage({
    required String businessName,
    required List<CartLine> lines,
    required String currency,
    String? customerName,
    String? note,

    /// Código del pedido (T-0001), para buscarlo en Ventas › Cotizaciones
    String? code,
    String? phone,

    /// Cupón aplicado y su descuento (0.16.0)
    String? couponCode,
    double discount = 0,
  }) {
    String money(num v) => CurrencyFormatter.formatIn(v, currency);
    final subtotal = lines.fold<double>(0, (s, l) => s + l.subtotal);
    final total = (subtotal - discount).clamp(0, subtotal);
    final name = customerName?.trim() ?? '';
    final extra = note?.trim() ?? '';
    final cel = phone?.trim() ?? '';
    return [
      code == null ? 'Hola $businessName, quiero hacer este pedido:' : 'Hola $businessName, quiero hacer el pedido $code:',
      '',
      for (final l in lines) '• ${l.quantity} × ${l.name} — ${money(l.subtotal)}',
      '',
      if (couponCode != null && discount > 0) ...['Subtotal: ${money(subtotal)}', 'Cupón $couponCode: −${money(discount)}'],
      'Total: ${money(total)}',
      if (name.isNotEmpty) 'A nombre de: $name',
      if (cel.isNotEmpty) 'Celular: $cel',
      if (extra.isNotEmpty) 'Nota: $extra',
      '',
      'Pedido hecho desde la tienda en línea (Stockealo).',
    ].join('\n');
  }

  @visibleForTesting
  static String errorMessage(String serverMessage) {
    if (serverMessage.contains('not_allowed') || serverMessage.contains('not_member')) {
      return 'Solo el dueño o un administrador del negocio pueden configurar la tienda.';
    }
    if (serverMessage.contains('slug_taken')) return 'Esa dirección ya la usa otra tienda. Prueba con otra.';
    if (serverMessage.contains('invalid_slug')) {
      return 'La dirección debe tener de 3 a 40 letras sin tildes, números o guiones.';
    }
    if (serverMessage.contains('invalid_whatsapp')) return 'Revisa el número de WhatsApp.';
    if (serverMessage.contains('welcome_too_long')) return 'El mensaje de bienvenida es muy largo (máximo 280).';
    if (serverMessage.contains('pro_required')) return 'Para publicar la tienda necesitas Stockealo Pro.';
    return 'No se pudo guardar. Inténtalo de nuevo.';
  }
}
