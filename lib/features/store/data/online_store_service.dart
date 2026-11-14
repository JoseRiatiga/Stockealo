import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';
import '../../../core/utils/currency_formatter.dart';

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

  const OnlineStoreConfig({
    required this.slug,
    required this.enabled,
    required this.whatsapp,
    this.welcome,
    this.showStock = false,
    this.template = StoreTemplate.classic,
    this.heroTitle,
    this.heroPhotos = true,
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
      );

  String get url => '$storeBaseUrl/$slug';
}

/// Las plantillas de la tienda
abstract final class StoreTemplate {
  /// La de siempre, mejorada: clara, con el color del negocio arriba
  static const classic = 'clasica';

  /// Oscura, de portada grande, con filtros por talla, color y precio (ropa, calzado)
  static const fashion = 'moda';

  static String of(String? v) => v == fashion ? fashion : classic;
  static String label(String v) => v == fashion ? 'Moda' : 'Clásica';
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

  const StoreVariant({
    required this.id,
    this.size,
    this.color,
    this.hex,
    this.extra = 0,
    this.stock,
    this.soldOut = false,
    this.few = false,
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
  });

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
      products: [
        for (final p in (j['products'] as List? ?? const [])) StoreProduct.fromJson(Map<String, dynamic>.from(p as Map)),
      ],
    );
  }

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
  Future<String?> createOrder({
    required String slug,
    required String customerName,
    String? customerPhone,
    String? note,
    required List<CartLine> lines,
  }) async {
    final client = _client;
    if (client == null) return null;
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
      });
      return (data as Map)['code'] as String?;
    } catch (e) {
      debugPrint('No se pudo guardar el pedido: $e');
      return null;
    }
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
  }) {
    String money(num v) => CurrencyFormatter.formatIn(v, currency);
    final total = lines.fold<double>(0, (s, l) => s + l.subtotal);
    final name = customerName?.trim() ?? '';
    final extra = note?.trim() ?? '';
    final cel = phone?.trim() ?? '';
    return [
      code == null ? 'Hola $businessName, quiero hacer este pedido:' : 'Hola $businessName, quiero hacer el pedido $code:',
      '',
      for (final l in lines) '• ${l.quantity} × ${l.name} — ${money(l.subtotal)}',
      '',
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
