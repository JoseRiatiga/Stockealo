import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/utils/currency_formatter.dart';
import '../../business/models/business.dart';
import '../../products/models/product.dart';
import '../models/catalog_style.dart';

class CatalogPdfService {
  static final CatalogPdfService instance = CatalogPdfService._internal();
  CatalogPdfService._internal();

  /// Descarga o lee los bytes de una imagen (foto de producto o logo)
  Future<Uint8List?> loadImageBytes(String? photoPath) async {
    if (photoPath == null || photoPath.trim().isEmpty) return null;
    final path = photoPath.trim();

    try {
      // 1. URL Remota (Supabase Storage) o Blob URL en Web
      if (path.startsWith('http://') || path.startsWith('https://') || path.startsWith('blob:')) {
        final res = await http.get(Uri.parse(path)).timeout(const Duration(seconds: 3));
        if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
          return res.bodyBytes;
        }
        return null;
      }

      // 2. Archivo Local en el teléfono (solo fuera de web)
      if (!kIsWeb) {
        final file = File(path);
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          if (bytes.isNotEmpty) return bytes;
        }
      }
    } catch (e) {
      debugPrint('Error cargando imagen para catálogo: $e');
    }
    return null;
  }

  pw.ThemeData? _cachedTheme;

  /// Letra Inter (la misma de la app): la Helvetica del PDF no tiene tildes raras,
  /// símbolos ni emojis
  Future<pw.ThemeData> pdfTheme() async {
    if (_cachedTheme != null) return _cachedTheme!;
    try {
      final regular = await rootBundle.load('assets/fonts/inter/Inter-Regular.ttf');
      final bold = await rootBundle.load('assets/fonts/inter/Inter-Bold.ttf');
      return _cachedTheme = pw.ThemeData.withFont(base: pw.Font.ttf(regular), bold: pw.Font.ttf(bold));
    } catch (e) {
      debugPrint('No se pudo cargar la letra del catálogo: $e');
      return pw.ThemeData();
    }
  }

  /// Productos que entran al catálogo según el estilo y la categoría
  static List<Product> selectProducts(List<Product> products, CatalogStyle style, {String? categoryFilter}) {
    var targets = products.where((p) => p.stock > 0).toList();
    if (style.selectedProductIds.isNotEmpty) {
      targets = targets.where((p) => style.selectedProductIds.contains(p.id)).toList();
    } else if (categoryFilter != null && categoryFilter.trim().isNotEmpty && categoryFilter != 'Todas') {
      targets = targets.where((p) => p.category.toLowerCase() == categoryFilter.toLowerCase()).toList();
    }
    if (style.onlyWithPhoto) {
      targets = targets.where((p) => p.photoPath != null && p.photoPath!.trim().isNotEmpty).toList();
    }
    return targets;
  }

  /// Genera el catálogo en PDF con el estilo elegido
  Future<File> generateCatalogPdf({
    required Business business,
    required List<Product> products,
    CatalogStyle style = const CatalogStyle(),
    String? categoryFilter,
    void Function(double progress, String status)? onProgress,
  }) async {
    final targetProducts = selectProducts(products, style, categoryFilter: categoryFilter);
    if (targetProducts.isEmpty) {
      throw Exception('No hay productos con stock para este catálogo.');
    }

    try {
      await initializeDateFormatting('es_CO', null);
    } catch (e) {
      debugPrint('No se pudo inicializar locale es_CO: $e');
    }

    final colors = _CatalogColors.of(style, business.color);
    onProgress?.call(0.1, 'Preparando fotos…');

    final logo = await loadImageBytes(business.logoUrl);
    final Map<String, Uint8List?> imageMap = {};
    for (var i = 0; i < targetProducts.length; i++) {
      final prod = targetProducts[i];
      imageMap[prod.id] = await loadImageBytes(prod.photoPath);
      onProgress?.call(0.1 + 0.5 * ((i + 1) / targetProducts.length), 'Preparando ${prod.name}…');
    }

    onProgress?.call(0.65, 'Armando las páginas…');
    final pdf = pw.Document(
      title: 'Catálogo · ${business.name}',
      author: business.name,
      theme: await pdfTheme(),
    );

    // La lista de precios va en renglones; las demás, en tarjetas
    final isList = style.template == 'lista';
    final perPage = isList ? listRowsPerPage : style.itemsPerPage;
    final columns = isList ? 1 : (perPage >= 4 ? 2 : 1);
    final totalPages = (targetProducts.length / perPage).ceil();
    final title = style.title.trim().isNotEmpty
        ? style.title.trim()
        : (categoryFilter != null && categoryFilter != 'Todas' ? categoryFilter : 'Catálogo de productos');

    for (var page = 0; page < totalPages; page++) {
      final pageProducts = targetProducts.skip(page * perPage).take(perPage).toList();
      final rows = <List<Product>>[
        for (var r = 0; r < pageProducts.length; r += columns) pageProducts.skip(r).take(columns).toList(),
      ];

      pdf.addPage(
        pw.Page(
          pageTheme: pw.PageTheme(
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            buildBackground: (_) => pw.FullPage(ignoreMargins: true, child: pw.Container(color: colors.page)),
          ),
          build: (_) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              _buildHeader(business: business, title: title, logo: logo, colors: colors, compact: page > 0, style: style),
              pw.SizedBox(height: 12),
              if (isList) _buildPriceList(pageProducts, imageMap, style, colors),
              if (!isList)
              for (final row in rows)
                pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 10),
                  child: pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      for (var i = 0; i < columns; i++) ...[
                        if (i > 0) pw.SizedBox(width: 10),
                        pw.Expanded(
                          child: i < row.length
                              ? (style.template == 'vitrina'
                                  ? _buildShowcaseCard(row[i], imageMap[row[i].id], style, colors, perPage)
                                  : _buildProductCard(row[i], imageMap[row[i].id], style, colors, perPage))
                              : pw.SizedBox(),
                        ),
                      ],
                    ],
                  ),
                ),
              pw.Spacer(),
              _buildFooter(page + 1, totalPages, style, colors),
            ],
          ),
        ),
      );
    }

    onProgress?.call(0.9, 'Guardando el PDF…');
    final bytes = await pdf.save();
    final cleanName = business.name.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
    final dateStr = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());

    if (kIsWeb) {
      onProgress?.call(1.0, 'Catálogo listo');
      return File('Catalogo_${cleanName}_$dateStr.pdf');
    }

    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/Catalogo_${cleanName}_$dateStr.pdf');
    await file.writeAsBytes(bytes, flush: true);
    onProgress?.call(1.0, 'Catálogo listo');
    return file;
  }

  /// Guarda una copia del archivo PDF generado en la carpeta de Descargas del dispositivo
  Future<({File file, String pathLabel, bool isPublicDownload})> saveToDownloads({
    required File pdfFile,
    required String businessName,
  }) async {
    final cleanName = businessName.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
    final dateStr = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
    final fileName = 'Catalogo_${cleanName}_$dateStr.pdf';

    if (kIsWeb) {
      return (file: pdfFile, pathLabel: 'Descargas/$fileName', isPublicDownload: true);
    }

    final bytes = await pdfFile.readAsBytes();

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      // 1. Intentar carpeta estándar y visible para el usuario (/storage/emulated/0/Download)
      try {
        final publicDownloadDir = Directory('/storage/emulated/0/Download');
        if (await publicDownloadDir.exists()) {
          final targetFile = File('${publicDownloadDir.path}/$fileName');
          await targetFile.writeAsBytes(bytes, flush: true);
          return (file: targetFile, pathLabel: 'Descargas/$fileName', isPublicDownload: true);
        }
      } catch (e) {
        debugPrint('No se pudo guardar en /storage/emulated/0/Download: $e');
      }

      // 2. Intentar carpeta externa de descargas de la app
      try {
        final extDir = await getExternalStorageDirectory();
        if (extDir != null) {
          final downloadDir = Directory('${extDir.path}/Download');
          if (!await downloadDir.exists()) {
            await downloadDir.create(recursive: true);
          }
          final targetFile = File('${downloadDir.path}/$fileName');
          await targetFile.writeAsBytes(bytes, flush: true);
          return (file: targetFile, pathLabel: 'Almacenamiento/Download/$fileName', isPublicDownload: false);
        }
      } catch (e) {
        debugPrint('No se pudo guardar en getExternalStorageDirectory: $e');
      }
    }

    // 3. Fallback de sistema general
    try {
      final downloadsDir = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
      final targetFile = File('${downloadsDir.path}/$fileName');
      await targetFile.writeAsBytes(bytes, flush: true);
      return (file: targetFile, pathLabel: 'Descargas/$fileName', isPublicDownload: false);
    } catch (e) {
      return (file: pdfFile, pathLabel: pdfFile.path, isPublicDownload: false);
    }
  }

  /// Encabezado: franja con el color del catálogo, logo, nombre y título.
  /// En las páginas siguientes a la primera va más pequeño.
  pw.Widget _buildHeader({
    required Business business,
    required String title,
    required Uint8List? logo,
    required _CatalogColors colors,
    required bool compact,
    required CatalogStyle style,
  }) {
    final logoSize = compact ? 28.0 : 46.0;
    final logoBox = logo != null
        ? pw.ClipRRect(
            horizontalRadius: 10,
            verticalRadius: 10,
            child: pw.Image(pw.MemoryImage(logo), width: logoSize, height: logoSize, fit: pw.BoxFit.cover),
          )
        : pw.Container(
            width: logoSize,
            height: logoSize,
            alignment: pw.Alignment.center,
            decoration: const pw.BoxDecoration(
              color: PdfColors.white,
              borderRadius: pw.BorderRadius.all(pw.Radius.circular(10)),
            ),
            child: pw.Text(
              business.name.trim().isNotEmpty ? business.name.trim()[0].toUpperCase() : 'S',
              style: pw.TextStyle(fontSize: compact ? 14 : 22, fontWeight: pw.FontWeight.bold, color: colors.band),
            ),
          );

    return pw.Container(
      padding: pw.EdgeInsets.symmetric(horizontal: 16, vertical: compact ? 10 : 18),
      decoration: pw.BoxDecoration(
        color: colors.band,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(14)),
      ),
      child: pw.Row(
        children: [
          logoBox,
          pw.SizedBox(width: 12),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  business.name,
                  style: pw.TextStyle(fontSize: compact ? 13 : 20, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
                ),
                if (!compact && style.template == 'promo') ...[
                  pw.SizedBox(height: 6),
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: const pw.BoxDecoration(
                      color: PdfColors.white,
                      borderRadius: pw.BorderRadius.all(pw.Radius.circular(8)),
                    ),
                    child: pw.Text(
                      title.toUpperCase(),
                      style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: colors.band),
                    ),
                  ),
                ] else if (!compact) ...[
                  pw.SizedBox(height: 2),
                  pw.Text(title, style: const pw.TextStyle(fontSize: 11, color: PdfColors.white)),
                ],
              ],
            ),
          ),
          if (style.whatsapp.trim().isNotEmpty)
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text('Pedidos por WhatsApp', style: const pw.TextStyle(fontSize: 8, color: PdfColors.white)),
                pw.Text(
                  style.whatsapp.trim(),
                  style: pw.TextStyle(fontSize: compact ? 10 : 12, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
                ),
              ],
            ),
        ],
      ),
    );
  }

  /// Tarjeta de producto; el tamaño depende de cuántos van por página
  pw.Widget _buildProductCard(Product product, Uint8List? image, CatalogStyle style, _CatalogColors colors, int perPage) {
    final imageHeight = switch (perPage) { 1 => 320.0, 2 => 200.0, 4 => 140.0, _ => 96.0 };
    final nameSize = switch (perPage) { 1 => 20.0, 2 => 15.0, 4 => 11.5, _ => 10.0 };
    final priceSize = switch (perPage) { 1 => 24.0, 2 => 18.0, 4 => 14.0, _ => 12.0 };
    final hasDescription = style.showDescription && (product.description?.trim().isNotEmpty ?? false) && perPage <= 4;

    final stockText = style.showExactStock ? '${product.stock} disponibles' : null;
    final meta = [
      if (style.showCategory && product.category.trim().isNotEmpty) product.category,
      if (style.showCode && product.code.isNotEmpty) 'Ref. ${product.code}',
    ].join(' · ');

    return pw.Container(
      decoration: pw.BoxDecoration(
        color: colors.card,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(12)),
        border: pw.Border.all(color: colors.line, width: 0.8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Container(
            height: imageHeight,
            decoration: pw.BoxDecoration(
              color: colors.imageBg,
              borderRadius: const pw.BorderRadius.vertical(top: pw.Radius.circular(12)),
            ),
            child: pw.Stack(
              fit: pw.StackFit.expand,
              children: [
                _productImage(product, image, colors, imageHeight, perPage == 1 ? pw.BoxFit.contain : pw.BoxFit.cover),
                if (style.template == 'promo')
                  pw.Positioned(
                    top: 8,
                    left: 8,
                    child: pw.Container(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: pw.BoxDecoration(
                        color: colors.band,
                        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
                      ),
                      child: pw.Text(
                        'OFERTA',
                        style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          pw.Padding(
            padding: pw.EdgeInsets.all(perPage >= 4 ? 8 : 14),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                if (meta.isNotEmpty)
                  pw.Text(meta, maxLines: 1, style: pw.TextStyle(fontSize: perPage >= 4 ? 7 : 9, color: colors.muted)),
                pw.SizedBox(height: 2),
                pw.Text(
                  product.name,
                  maxLines: 2,
                  style: pw.TextStyle(fontSize: nameSize, fontWeight: pw.FontWeight.bold, color: colors.ink),
                ),
                if (hasDescription) ...[
                  pw.SizedBox(height: 4),
                  pw.Text(
                    product.description!.trim(),
                    maxLines: perPage == 1 ? 5 : 2,
                    style: pw.TextStyle(fontSize: perPage >= 4 ? 7.5 : 9.5, color: colors.muted),
                  ),
                ],
                pw.SizedBox(height: 6),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    if (style.showPrice)
                      pw.Text(
                        CurrencyFormatter.format(product.salePrice),
                        style: pw.TextStyle(fontSize: priceSize, fontWeight: pw.FontWeight.bold, color: colors.accent),
                      )
                    else
                      pw.SizedBox(),
                    if (stockText != null)
                      pw.Container(
                        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: pw.BoxDecoration(
                          color: colors.accentSoft,
                          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
                        ),
                        child: pw.Text(stockText, style: pw.TextStyle(fontSize: 7, color: colors.accent)),
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

  /// Renglones de la plantilla "Lista de precios"
  static const listRowsPerPage = 12;

  /// Foto del producto o su inicial cuando no tiene
  pw.Widget _productImage(Product product, Uint8List? image, _CatalogColors colors, double height, pw.BoxFit fit) {
    if (image != null) {
      return pw.ClipRRect(
        horizontalRadius: 12,
        verticalRadius: 12,
        child: pw.Image(pw.MemoryImage(image), fit: fit),
      );
    }
    return pw.Center(
      child: pw.Text(
        product.name.trim().isNotEmpty ? product.name.trim()[0].toUpperCase() : 'P',
        style: pw.TextStyle(fontSize: height / 4, fontWeight: pw.FontWeight.bold, color: colors.muted),
      ),
    );
  }

  /// Plantilla "Vitrina": la foto manda, el nombre y el precio van centrados
  pw.Widget _buildShowcaseCard(Product product, Uint8List? image, CatalogStyle style, _CatalogColors colors, int perPage) {
    final imageHeight = switch (perPage) { 1 => 420.0, 2 => 250.0, 4 => 180.0, _ => 120.0 };
    final nameSize = switch (perPage) { 1 => 22.0, 2 => 16.0, 4 => 12.0, _ => 10.0 };
    final priceSize = switch (perPage) { 1 => 22.0, 2 => 16.0, 4 => 12.0, _ => 10.5 };
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Container(
          height: imageHeight,
          decoration: pw.BoxDecoration(
            color: colors.imageBg,
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(16)),
          ),
          child: _productImage(product, image, colors, imageHeight, pw.BoxFit.cover),
        ),
        pw.SizedBox(height: 6),
        pw.Text(
          product.name,
          maxLines: 2,
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(fontSize: nameSize, fontWeight: pw.FontWeight.bold, color: colors.ink),
        ),
        if (style.showCategory && product.category.trim().isNotEmpty)
          pw.Text(
            product.category,
            maxLines: 1,
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(fontSize: perPage >= 4 ? 7 : 9, color: colors.muted),
          ),
        if (style.showPrice) ...[
          pw.SizedBox(height: 4),
          pw.Center(
            child: pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: pw.BoxDecoration(
                color: colors.band,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
              ),
              child: pw.Text(
                CurrencyFormatter.format(product.salePrice),
                style: pw.TextStyle(fontSize: priceSize, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
              ),
            ),
          ),
        ],
        if (style.showExactStock)
          pw.Text(
            '${product.stock} disponibles',
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(fontSize: 7, color: colors.muted),
          ),
      ],
    );
  }

  /// Plantilla "Lista de precios": un renglón por producto, con foto pequeña
  pw.Widget _buildPriceList(
      List<Product> products, Map<String, Uint8List?> images, CatalogStyle style, _CatalogColors colors) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        color: colors.card,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(12)),
        border: pw.Border.all(color: colors.line, width: 0.8),
      ),
      child: pw.Column(
        children: [
          for (var i = 0; i < products.length; i++)
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: i == 0
                  ? null
                  : pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: colors.line, width: 0.6))),
              child: pw.Row(
                children: [
                  pw.Container(
                    width: 34,
                    height: 34,
                    decoration: pw.BoxDecoration(
                      color: colors.imageBg,
                      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
                    ),
                    child: _productImage(products[i], images[products[i].id], colors, 34, pw.BoxFit.cover),
                  ),
                  pw.SizedBox(width: 10),
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          products[i].name,
                          maxLines: 1,
                          style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: colors.ink),
                        ),
                        if (listMeta(products[i], style).isNotEmpty)
                          pw.Text(listMeta(products[i], style),
                              maxLines: 1, style: pw.TextStyle(fontSize: 8, color: colors.muted)),
                      ],
                    ),
                  ),
                  if (style.showPrice)
                    pw.Text(
                      CurrencyFormatter.format(products[i].salePrice),
                      style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: colors.accent),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// Detalle bajo el nombre en la lista de precios
  static String listMeta(Product product, CatalogStyle style) => [
        if (style.showCategory && product.category.trim().isNotEmpty) product.category,
        if (style.showCode && product.code.isNotEmpty) 'Ref. ${product.code}',
        if (style.showExactStock) '${product.stock} disponibles',
      ].join(' · ');

  /// Pie: contacto del negocio, número de página y "Hecho con Stockealo"
  pw.Widget _buildFooter(int pageIndex, int totalPages, CatalogStyle style, _CatalogColors colors) {
    final contact = [
      if (style.whatsapp.trim().isNotEmpty) 'WhatsApp ${style.whatsapp.trim()}',
      if (style.address.trim().isNotEmpty) style.address.trim(),
      if (style.hours.trim().isNotEmpty) style.hours.trim(),
      if (style.social.trim().isNotEmpty) style.social.trim(),
    ].join('  ·  ');

    return pw.Container(
      padding: const pw.EdgeInsets.only(top: 8),
      decoration: pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: colors.line, width: 0.6))),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: pw.Text(
              contact.isNotEmpty ? contact : 'Precios sujetos a disponibilidad',
              style: pw.TextStyle(fontSize: 7.5, color: colors.muted),
            ),
          ),
          pw.SizedBox(width: 12),
          pw.Text(
            style.showBranding ? 'Página $pageIndex de $totalPages · Hecho con Stockealo' : 'Página $pageIndex de $totalPages',
            style: pw.TextStyle(fontSize: 7.5, color: colors.muted),
          ),
        ],
      ),
    );
  }
}

/// Colores del PDF según el estilo: el color del catálogo (o del negocio) y fondo
/// claro u oscuro
class _CatalogColors {
  /// Franja del encabezado: el color tal cual, con texto blanco encima
  final PdfColor band;

  /// Precios y detalles; en fondo oscuro se aclara para que se lea
  final PdfColor accent;
  final PdfColor accentSoft;
  final PdfColor page;
  final PdfColor card;
  final PdfColor imageBg;
  final PdfColor ink;
  final PdfColor muted;
  final PdfColor line;

  const _CatalogColors({
    required this.band,
    required this.accent,
    required this.accentSoft,
    required this.page,
    required this.card,
    required this.imageBg,
    required this.ink,
    required this.muted,
    required this.line,
  });

  factory _CatalogColors.of(CatalogStyle style, String? businessColor) {
    final hex = style.colorHex ?? businessColor ?? '#1E6B4E';
    final accent = PdfColor.fromHex(RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(hex) ? hex : '#1E6B4E');
    PdfColor mix(PdfColor a, PdfColor b, double t) =>
        PdfColor(a.red + (b.red - a.red) * t, a.green + (b.green - a.green) * t, a.blue + (b.blue - a.blue) * t);

    if (style.darkBackground) {
      final page = PdfColor.fromHex('#14130F');
      return _CatalogColors(
        band: accent,
        accent: mix(accent, PdfColors.white, 0.25),
        accentSoft: mix(page, accent, 0.3),
        page: page,
        card: PdfColor.fromHex('#1E1C18'),
        imageBg: PdfColor.fromHex('#272420'),
        ink: PdfColor.fromHex('#F2EEE5'),
        muted: PdfColor.fromHex('#B1AB9F'),
        line: PdfColor.fromHex('#2F2C26'),
      );
    }
    return _CatalogColors(
      band: accent,
      accent: accent,
      accentSoft: mix(PdfColors.white, accent, 0.12),
      page: PdfColor.fromHex('#F6F3EC'),
      card: PdfColors.white,
      imageBg: PdfColor.fromHex('#F1EDE4'),
      ink: PdfColor.fromHex('#1F1D18'),
      muted: PdfColor.fromHex('#6E6A60'),
      line: PdfColor.fromHex('#ECE7DC'),
    );
  }
}
