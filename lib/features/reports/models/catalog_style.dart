import 'dart:convert';

/// Cómo se ve un catálogo (PDF e historias). Se guarda por negocio para que la
/// próxima vez salga igual con un solo toque.
class CatalogStyle {
  /// Plantilla: por ahora solo 'clasica' (las demás serán de Stockealo Pro)
  final String template;

  /// Color principal "#RRGGBB"; null usa el color del negocio
  final String? colorHex;
  final bool darkBackground;

  /// Productos por página en el PDF: 1, 2, 4 o 6
  final int itemsPerPage;

  // Portada
  final String title;

  // Pie de página / contacto
  final String whatsapp;
  final String address;
  final String hours;
  final String social;

  // Qué mostrar de cada producto
  final bool showPrice;
  final bool showExactStock;
  final bool showCode;
  final bool showDescription;
  final bool showCategory;

  // Qué productos entran
  final bool onlyWithPhoto;

  /// Productos elegidos a mano; vacío = todos los de la categoría elegida
  final Set<String> selectedProductIds;

  /// Pie "Hecho con Stockealo" (en el plan gratis siempre va)
  final bool showBranding;

  const CatalogStyle({
    this.template = 'clasica',
    this.colorHex,
    this.darkBackground = false,
    this.itemsPerPage = 4,
    this.title = '',
    this.whatsapp = '',
    this.address = '',
    this.hours = '',
    this.social = '',
    this.showPrice = true,
    this.showExactStock = false,
    this.showCode = false,
    this.showDescription = true,
    this.showCategory = true,
    this.onlyWithPhoto = false,
    this.selectedProductIds = const {},
    this.showBranding = true,
  });

  CatalogStyle copyWith({
    String? template,
    String? colorHex,
    bool? darkBackground,
    int? itemsPerPage,
    String? title,
    String? whatsapp,
    String? address,
    String? hours,
    String? social,
    bool? showPrice,
    bool? showExactStock,
    bool? showCode,
    bool? showDescription,
    bool? showCategory,
    bool? onlyWithPhoto,
    Set<String>? selectedProductIds,
  }) {
    return CatalogStyle(
      template: template ?? this.template,
      colorHex: colorHex ?? this.colorHex,
      darkBackground: darkBackground ?? this.darkBackground,
      itemsPerPage: itemsPerPage ?? this.itemsPerPage,
      title: title ?? this.title,
      whatsapp: whatsapp ?? this.whatsapp,
      address: address ?? this.address,
      hours: hours ?? this.hours,
      social: social ?? this.social,
      showPrice: showPrice ?? this.showPrice,
      showExactStock: showExactStock ?? this.showExactStock,
      showCode: showCode ?? this.showCode,
      showDescription: showDescription ?? this.showDescription,
      showCategory: showCategory ?? this.showCategory,
      onlyWithPhoto: onlyWithPhoto ?? this.onlyWithPhoto,
      selectedProductIds: selectedProductIds ?? this.selectedProductIds,
      showBranding: showBranding,
    );
  }

  Map<String, dynamic> toJson() => {
        'template': template,
        'colorHex': colorHex,
        'darkBackground': darkBackground,
        'itemsPerPage': itemsPerPage,
        'title': title,
        'whatsapp': whatsapp,
        'address': address,
        'hours': hours,
        'social': social,
        'showPrice': showPrice,
        'showExactStock': showExactStock,
        'showCode': showCode,
        'showDescription': showDescription,
        'showCategory': showCategory,
        'onlyWithPhoto': onlyWithPhoto,
        'selectedProductIds': selectedProductIds.toList(),
      };

  factory CatalogStyle.fromJson(Map<String, dynamic> j) {
    final perPage = j['itemsPerPage'] as int? ?? 4;
    return CatalogStyle(
      template: j['template'] as String? ?? 'clasica',
      colorHex: j['colorHex'] as String?,
      darkBackground: j['darkBackground'] as bool? ?? false,
      itemsPerPage: const [1, 2, 4, 6].contains(perPage) ? perPage : 4,
      title: j['title'] as String? ?? '',
      whatsapp: j['whatsapp'] as String? ?? '',
      address: j['address'] as String? ?? '',
      hours: j['hours'] as String? ?? '',
      social: j['social'] as String? ?? '',
      showPrice: j['showPrice'] as bool? ?? true,
      showExactStock: j['showExactStock'] as bool? ?? false,
      showCode: j['showCode'] as bool? ?? false,
      showDescription: j['showDescription'] as bool? ?? true,
      showCategory: j['showCategory'] as bool? ?? true,
      onlyWithPhoto: j['onlyWithPhoto'] as bool? ?? false,
      selectedProductIds: {...(j['selectedProductIds'] as List? ?? const []).cast<String>()},
    );
  }

  String encode() => jsonEncode(toJson());

  /// Lee el estilo guardado; si falta o está dañado, el estilo por defecto
  static CatalogStyle decode(String? raw) {
    if (raw == null || raw.isEmpty) return const CatalogStyle();
    try {
      return CatalogStyle.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const CatalogStyle();
    }
  }

  /// Clave en app_settings
  static String settingsKey(String businessId) => 'catalog_style_$businessId';
}
