import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/utils/currency_formatter.dart';
import '../../business/models/business.dart';
import '../../products/models/product.dart';

class CatalogPdfService {
  static final CatalogPdfService instance = CatalogPdfService._internal();
  CatalogPdfService._internal();

  /// Descarga o lee bytes de la imagen del producto
  Future<Uint8List?> _loadProductImage(String? photoPath) async {
    if (photoPath == null || photoPath.trim().isEmpty) return null;
    final path = photoPath.trim();

    try {
      // 1. URL Remota (Supabase Storage)
      if (path.startsWith('http://') || path.startsWith('https://')) {
        final res = await http.get(Uri.parse(path)).timeout(const Duration(seconds: 3));
        if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
          return res.bodyBytes;
        }
        return null;
      }

      // 2. Archivo Local en el teléfono
      final file = File(path);
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        if (bytes.isNotEmpty) return bytes;
      }
    } catch (e) {
      debugPrint('Error cargando imagen para catálogo: $e');
    }
    return null;
  }

  /// Genera el documento PDF del Catálogo Comercial de Productos
  Future<File> generateCatalogPdf({
    required Business business,
    required List<Product> products,
    String? contactPhone,
    bool showExactStock = false,
    String? categoryFilter,
    void Function(double progress, String status)? onProgress,
  }) async {
    // Filtrar productos por categoría si se seleccionó una en específico
    List<Product> targetProducts = products.where((p) => p.stock > 0).toList();
    if (categoryFilter != null && categoryFilter.trim().isNotEmpty && categoryFilter != 'Todas') {
      targetProducts = targetProducts.where((p) => p.category.toLowerCase() == categoryFilter.toLowerCase()).toList();
    }

    if (targetProducts.isEmpty) {
      throw Exception('No hay productos en stock para generar el catálogo.');
    }

    try {
      await initializeDateFormatting('es_CO', null);
    } catch (e) {
      debugPrint('No se pudo inicializar locale es_CO: $e');
    }

    onProgress?.call(0.1, 'Procesando imágenes de productos...');

    // 1. Cargar las imágenes de los productos de forma concurrente
    final Map<String, Uint8List?> imageMap = {};
    int loaded = 0;
    for (final prod in targetProducts) {
      if (prod.photoPath != null && prod.photoPath!.trim().isNotEmpty) {
        imageMap[prod.id] = await _loadProductImage(prod.photoPath);
      } else {
        imageMap[prod.id] = null;
      }
      loaded++;
      onProgress?.call(0.1 + (0.5 * (loaded / targetProducts.length)), 'Preparando ${prod.name}...');
    }

    onProgress?.call(0.65, 'Diseñando páginas del catálogo...');

    final pdf = pw.Document(
      title: 'Catálogo de Productos - ${business.name}',
      author: 'Stockealo',
    );

    // 2. Distribución en páginas: 6 productos por página (2 columnas x 3 filas)
    const int itemsPerPage = 6;
    final int totalPages = (targetProducts.length / itemsPerPage).ceil();

    for (int pIndex = 0; pIndex < totalPages; pIndex++) {
      final start = pIndex * itemsPerPage;
      final end = (start + itemsPerPage < targetProducts.length) ? start + itemsPerPage : targetProducts.length;
      final pageProducts = targetProducts.sublist(start, end);

      // Agrupar en filas de 2 productos
      final List<List<Product>> rows = [];
      for (int r = 0; r < pageProducts.length; r += 2) {
        if (r + 1 < pageProducts.length) {
          rows.add([pageProducts[r], pageProducts[r + 1]]);
        } else {
          rows.add([pageProducts[r]]);
        }
      }

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          build: (pw.Context context) {
            return pw.Column(
              children: [
                _buildHeader(
                  business: business,
                  contactPhone: contactPhone,
                  totalInStock: targetProducts.length,
                  categoryFilter: categoryFilter,
                ),
                pw.SizedBox(height: 8),
                ...rows.map((row) {
                  return pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 8),
                    child: pw.Row(
                      children: [
                        pw.Expanded(
                          child: _buildProductCard(
                            row[0],
                            imageMap[row[0].id],
                            showExactStock,
                            business.currency,
                          ),
                        ),
                        pw.SizedBox(width: 8),
                        if (row.length > 1)
                          pw.Expanded(
                            child: _buildProductCard(
                              row[1],
                              imageMap[row[1].id],
                              showExactStock,
                              business.currency,
                            ),
                          )
                        else
                          pw.Expanded(child: pw.Container()),
                      ],
                    ),
                  );
                }),
                pw.Spacer(),
                _buildFooter(pIndex + 1, totalPages, contactPhone),
              ],
            );
          },
        ),
      );
    }

    onProgress?.call(0.9, 'Guardando archivo PDF...');

    // 3. Guardar el archivo en la memoria temporal
    final bytes = await pdf.save();
    final tempDir = await getTemporaryDirectory();
    final cleanName = business.name.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
    final dateStr = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
    final file = File('${tempDir.path}/Catalogo_${cleanName}_$dateStr.pdf');
    await file.writeAsBytes(bytes, flush: true);

    onProgress?.call(1.0, '¡Catálogo listo!');
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
    final bytes = await pdfFile.readAsBytes();

    if (Platform.isAndroid) {
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

  /// Cabecera moderna estilo revista comercial
  pw.Widget _buildHeader({
    required Business business,
    required String? contactPhone,
    required int totalInStock,
    String? categoryFilter,
  }) {
    String dateFormatted;
    try {
      dateFormatted = DateFormat("d 'de' MMMM, yyyy", 'es_CO').format(DateTime.now());
    } catch (_) {
      final now = DateTime.now();
      const months = [
        'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
        'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'
      ];
      dateFormatted = '${now.day} de ${months[now.month - 1]}, ${now.year}';
    }

    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: pw.BoxDecoration(
        color: PdfColor.fromHex('#0F172A'),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                business.name.toUpperCase(),
                style: pw.TextStyle(
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.white,
                ),
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                categoryFilter != null && categoryFilter != 'Todas'
                    ? 'CATÁLOGO DE ${categoryFilter.toUpperCase()}'
                    : 'CATÁLOGO DE PRODUCTOS EN STOCK',
                style: pw.TextStyle(
                  fontSize: 8,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColor.fromHex('#34D399'),
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              if (contactPhone != null && contactPhone.trim().isNotEmpty) ...[
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: pw.BoxDecoration(
                    color: PdfColor.fromHex('#059669'),
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                  ),
                  child: pw.Text(
                    'Pedidos WhatsApp: $contactPhone',
                    style: pw.TextStyle(
                      fontSize: 8.5,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.white,
                    ),
                  ),
                ),
                pw.SizedBox(height: 3),
              ],
              pw.Text(
                '$totalInStock referencias disponibles • $dateFormatted',
                style: pw.TextStyle(fontSize: 7.5, color: PdfColor.fromHex('#94A3B8')),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Tarjeta de cada producto en el catálogo
  pw.Widget _buildProductCard(
    Product product,
    Uint8List? imageBytes,
    bool showExactStock,
    String currency,
  ) {
    return pw.Container(
      height: 200,
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
        border: pw.Border.all(color: PdfColor.fromHex('#E2E8F0'), width: 0.8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          // 1. Imagen del Producto o Placeholder con inicial
          pw.Container(
            height: 98,
            width: double.infinity,
            decoration: pw.BoxDecoration(
              color: PdfColor.fromHex('#F8FAFC'),
              borderRadius: const pw.BorderRadius.vertical(top: pw.Radius.circular(8)),
            ),
            child: imageBytes != null
                ? pw.ClipRRect(
                    horizontalRadius: 8,
                    verticalRadius: 8,
                    child: pw.Image(
                      pw.MemoryImage(imageBytes),
                      fit: pw.BoxFit.cover,
                    ),
                  )
                : pw.Center(
                    child: pw.Column(
                      mainAxisAlignment: pw.MainAxisAlignment.center,
                      children: [
                        pw.Container(
                          width: 38,
                          height: 38,
                          decoration: pw.BoxDecoration(
                            color: PdfColor.fromHex('#E2E8F0'),
                            shape: pw.BoxShape.circle,
                          ),
                          alignment: pw.Alignment.center,
                          child: pw.Text(
                            product.name.trim().isNotEmpty ? product.name.trim()[0].toUpperCase() : 'P',
                            style: pw.TextStyle(
                              fontSize: 18,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColor.fromHex('#64748B'),
                            ),
                          ),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          product.category,
                          style: pw.TextStyle(fontSize: 7, color: PdfColor.fromHex('#94A3B8')),
                        ),
                      ],
                    ),
                  ),
          ),

          // 2. Información del Producto
          pw.Padding(
            padding: const pw.EdgeInsets.all(8),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // Categoría y Badge de Disponibilidad
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: pw.BoxDecoration(
                        color: PdfColor.fromHex('#EFF6FF'),
                        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                      ),
                      child: pw.Text(
                        product.category.toUpperCase(),
                        style: pw.TextStyle(
                          fontSize: 6.5,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColor.fromHex('#2563EB'),
                        ),
                      ),
                    ),
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: pw.BoxDecoration(
                        color: PdfColor.fromHex('#ECFDF5'),
                        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                      ),
                      child: pw.Text(
                        showExactStock ? 'Stock: ${product.stock} und.' : 'Disponible',
                        style: pw.TextStyle(
                          fontSize: 6.5,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColor.fromHex('#059669'),
                        ),
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 4),

                // Nombre del producto
                pw.Text(
                  product.name,
                  maxLines: 2,
                  style: pw.TextStyle(
                    fontSize: 9.5,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColor.fromHex('#0F172A'),
                  ),
                ),
                pw.SizedBox(height: 4),

                // Precio de venta destacado y Código
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      CurrencyFormatter.format(product.salePrice),
                      style: pw.TextStyle(
                        fontSize: 13,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColor.fromHex('#059669'),
                      ),
                    ),
                    if (product.code.isNotEmpty)
                      pw.Text(
                        'Ref: ${product.code}',
                        style: pw.TextStyle(fontSize: 7, color: PdfColor.fromHex('#94A3B8')),
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

  /// Pie de página con numeración y contacto
  pw.Widget _buildFooter(int pageIndex, int totalPages, String? contactPhone) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(top: 6),
      decoration: pw.BoxDecoration(
        border: pw.Border(
          top: pw.BorderSide(color: PdfColor.fromHex('#E2E8F0'), width: 0.5),
        ),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            contactPhone != null && contactPhone.trim().isNotEmpty
                ? 'Para consultar disponibilidad o hacer un pedido: WhatsApp $contactPhone'
                : 'Precios sujetos a disponibilidad de inventario',
            style: pw.TextStyle(fontSize: 7.5, color: PdfColor.fromHex('#64748B')),
          ),
          pw.Text(
            'Página $pageIndex de $totalPages • Stockealo',
            style: pw.TextStyle(fontSize: 7.5, color: PdfColor.fromHex('#94A3B8')),
          ),
        ],
      ),
    );
  }
}
