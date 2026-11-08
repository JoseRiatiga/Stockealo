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

  const OnlineStoreConfig({
    required this.slug,
    required this.enabled,
    required this.whatsapp,
    this.welcome,
    this.showStock = false,
  });

  factory OnlineStoreConfig.fromJson(Map<String, dynamic> j) => OnlineStoreConfig(
        slug: j['slug'] as String,
        enabled: j['enabled'] == true,
        whatsapp: j['whatsapp'] as String? ?? '',
        welcome: j['welcome'] as String?,
        showStock: j['show_stock'] == true,
      );

  String get url => '$storeBaseUrl/$slug';
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

  const StoreProduct({
    required this.id,
    required this.name,
    required this.category,
    required this.price,
    this.imageUrl,
    this.stock,
  });

  factory StoreProduct.fromJson(Map<String, dynamic> j) => StoreProduct(
        id: j['id'] as String,
        name: j['name'] as String? ?? '',
        category: (j['category'] as String? ?? '').trim(),
        price: (j['price'] as num?)?.toDouble() ?? 0,
        imageUrl: j['image_url'] as String?,
        stock: (j['stock'] as num?)?.toInt(),
      );
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

  const PublicStore({
    required this.slug,
    required this.whatsapp,
    required this.businessName,
    required this.currency,
    required this.products,
    this.welcome,
    this.logoUrl,
    this.color,
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

/// Un renglón del carrito
class CartLine {
  final StoreProduct product;
  final int quantity;

  const CartLine(this.product, this.quantity);

  double get subtotal => product.price * quantity;
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
  }) async {
    final client = _client;
    if (client == null || client.auth.currentSession == null) {
      throw const OnlineStoreException('Necesitas iniciar sesión y tener internet.');
    }
    try {
      final data = await client.rpc('save_my_store', params: {
        'p_business_id': businessId,
        'p_slug': slug,
        'p_enabled': enabled,
        'p_whatsapp': whatsapp,
        'p_welcome': welcome,
        'p_show_stock': showStock,
      });
      return OnlineStoreConfig.fromJson(Map<String, dynamic>.from(data as Map));
    } on PostgrestException catch (e) {
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
  static String orderMessage({
    required String businessName,
    required List<CartLine> lines,
    required String currency,
    String? customerName,
    String? note,
  }) {
    String money(num v) => CurrencyFormatter.formatIn(v, currency);
    final total = lines.fold<double>(0, (s, l) => s + l.subtotal);
    final name = customerName?.trim() ?? '';
    final extra = note?.trim() ?? '';
    return [
      'Hola $businessName, quiero hacer este pedido:',
      '',
      for (final l in lines) '• ${l.quantity} × ${l.product.name} — ${money(l.subtotal)}',
      '',
      'Total: ${money(total)}',
      if (name.isNotEmpty) 'A nombre de: $name',
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
