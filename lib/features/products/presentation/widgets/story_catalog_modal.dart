import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../business/models/business.dart';
import '../../models/product.dart';
import 'product_image_view.dart';

/// Modal interactivo para previsualizar y exportar imágenes verticales 9:16
/// listas para subir a Estados de WhatsApp e Historias de Instagram.
class StoryCatalogModal extends StatefulWidget {
  final Business business;
  final List<Product> products;
  final String? contactPhone;
  final int itemsPerPage;

  const StoryCatalogModal({
    super.key,
    required this.business,
    required this.products,
    this.contactPhone,
    this.itemsPerPage = 1,
  });

  static Future<void> show({
    required BuildContext context,
    required Business business,
    required List<Product> products,
    String? contactPhone,
    int itemsPerPage = 1,
  }) {
    return showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.85),
      builder: (_) => StoryCatalogModal(
        business: business,
        products: products,
        contactPhone: contactPhone,
        itemsPerPage: itemsPerPage,
      ),
    );
  }

  @override
  State<StoryCatalogModal> createState() => _StoryCatalogModalState();
}

class _StoryCatalogModalState extends State<StoryCatalogModal> {
  late PageController _pageController;
  int _currentPageIndex = 0;
  bool _isExporting = false;
  late int _density;

  // Claves globales para capturar cada historia
  final Map<int, GlobalKey> _storyKeys = {};

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _density = (widget.itemsPerPage == 1 || widget.itemsPerPage == 2 || widget.itemsPerPage == 4)
        ? widget.itemsPerPage
        : 1;
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  List<List<Product>> get _storyPages {
    final List<List<Product>> pages = [];
    for (int i = 0; i < widget.products.length; i += _density) {
      final end = (i + _density < widget.products.length) ? i + _density : widget.products.length;
      pages.add(widget.products.sublist(i, end));
    }
    return pages;
  }

  Future<void> _shareCurrentStory() async {
    final key = _storyKeys[_currentPageIndex];
    if (key == null) return;

    setState(() => _isExporting = true);

    try {
      final boundary = key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) throw Exception('No se pudo renderizar la historia');

      final ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) throw Exception('Fallo al codificar PNG');

      final pngBytes = byteData.buffer.asUint8List();
      final tempDir = await getTemporaryDirectory();
      final cleanBiz = widget.business.name.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
      final file = File('${tempDir.path}/Historia_${cleanBiz}_${_currentPageIndex + 1}.png');
      await file.writeAsBytes(pngBytes, flush: true);

      if (mounted) {
        setState(() => _isExporting = false);
        await Share.shareXFiles(
          [
            XFile(
              file.path,
              mimeType: 'image/png',
              name: 'Historia_${widget.business.name}.png',
            ),
          ],
          text: '¡Mira los productos disponibles en ${widget.business.name}!',
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isExporting = false);
        AppToast.show(context, message: 'Error exportando historia: $e', type: ToastType.error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = _storyPages;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Column(
        children: [
          // Barra Superior: Controles de Densidad y Cerrar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF131126),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFF26214A)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: const Color(0xFF8B5CF6).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.auto_awesome_rounded, color: Color(0xFF8B5CF6), size: 18),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Historias para Redes',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFF8FAFC),
                          ),
                        ),
                        Text(
                          '${_currentPageIndex + 1} de ${pages.length} historias',
                          style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                        ),
                      ],
                    ),
                  ],
                ),
                // Selector rápido de densidad
                Row(
                  children: [
                    _buildDensityChip(1, '1'),
                    const SizedBox(width: 4),
                    _buildDensityChip(2, '2'),
                    const SizedBox(width: 4),
                    _buildDensityChip(4, '4'),
                    const SizedBox(width: 8),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded, color: Color(0xFF94A3B8), size: 20),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Área Central: Carrusel Vertical 9:16
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: 9 / 16,
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: pages.length,
                  onPageChanged: (idx) => setState(() => _currentPageIndex = idx),
                  itemBuilder: (context, index) {
                    final storyKey = _storyKeys.putIfAbsent(index, () => GlobalKey());
                    return RepaintBoundary(
                      key: storyKey,
                      child: _buildStoryCard(pages[index]),
                    );
                  },
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Barra Inferior: Botón Acción Subir / Compartir
          SizedBox(
            width: 320,
            child: ElevatedButton.icon(
              onPressed: _isExporting ? null : _shareCurrentStory,
              icon: _isExporting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.share_rounded, size: 18),
              label: Text(
                _isExporting ? 'Procesando imagen...' : 'Subir a Estados / Compartir PNG',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDensityChip(int density, String label) {
    final isSelected = _density == density;
    return InkWell(
      onTap: () {
        setState(() {
          _density = density;
          _currentPageIndex = 0;
          _storyKeys.clear();
        });
        _pageController.jumpToPage(0);
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF8B5CF6) : const Color(0xFF18152F),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? const Color(0xFF8B5CF6) : const Color(0xFF26214A),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: isSelected ? Colors.white : const Color(0xFF94A3B8),
          ),
        ),
      ),
    );
  }

  /// Construye la tarjeta vertical 9:16 con estética Obsidian Violet Bento
  Widget _buildStoryCard(List<Product> products) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0A0915),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF26214A), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF8B5CF6).withOpacity(0.18),
            blurRadius: 24,
            spreadRadius: 2,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Stack(
          children: [
            // Resplandor superior sutil
            Positioned(
              top: -60,
              left: 20,
              right: 20,
              child: Container(
                height: 180,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF8B5CF6).withOpacity(0.15),
                ),
              ),
            ),

            // Contenido estructurado de la Historia
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 1. Cabecera Comercial
                  Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: const Color(0xFF131126),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF8B5CF6).withOpacity(0.4)),
                        ),
                        child: Center(
                          child: Text(
                            widget.business.name.trim().isNotEmpty
                                ? widget.business.name.trim()[0].toUpperCase()
                                : 'S',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF8B5CF6),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    widget.business.name,
                                    style: const TextStyle(
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFFF8FAFC),
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Icon(Icons.verified_rounded, size: 14, color: Color(0xFF10B981)),
                              ],
                            ),
                            const Text(
                              'Catálogo Oficial en Tiempo Real',
                              style: TextStyle(fontSize: 10, color: Color(0xFF94A3B8)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // 2. Bloque Central de Productos
                  Expanded(
                    child: _buildProductLayout(products),
                  ),
                  const SizedBox(height: 14),

                  // 3. Pie de Historia: Call-to-Action WhatsApp
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFF10B981).withOpacity(0.35)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.chat_bubble_rounded, size: 15, color: Color(0xFF10B981)),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            widget.contactPhone != null && widget.contactPhone!.trim().isNotEmpty
                                ? 'Pídelo al WhatsApp: ${widget.contactPhone}'
                                : 'Pregunta por tu producto favorito',
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF10B981),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductLayout(List<Product> products) {
    if (_density == 1) {
      final p = products.first;
      return Container(
        decoration: BoxDecoration(
          color: const Color(0xFF131126),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFF26214A)),
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Imagen grande Hero
            Expanded(
              child: Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: ProductImageView(
                    imagePath: p.photoPath,
                    width: double.infinity,
                    height: double.infinity,
                    iconSize: 56,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF8B5CF6).withOpacity(0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                p.category.toUpperCase(),
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF8B5CF6),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              p.name,
              style: const TextStyle(
                fontSize: 16.5,
                fontWeight: FontWeight.bold,
                color: Color(0xFFF8FAFC),
                height: 1.2,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (p.description != null && p.description!.trim().isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                p.description!,
                style: const TextStyle(fontSize: 11.5, color: Color(0xFF94A3B8)),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  CurrencyFormatter.format(p.salePrice),
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF10B981),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF18152F),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFF26214A)),
                  ),
                  child: Text(
                    'Ref: ${p.code}',
                    style: const TextStyle(fontSize: 10, color: Color(0xFF64748B)),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    if (_density == 2) {
      return Column(
        children: products.map((p) {
          return Expanded(
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF131126),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF26214A)),
              ),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: ProductImageView(
                      imagePath: p.photoPath,
                      width: 90,
                      height: double.infinity,
                      iconSize: 32,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          p.category.toUpperCase(),
                          style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFF8B5CF6)),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          p.name,
                          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: Color(0xFFF8FAFC)),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          CurrencyFormatter.format(p.salePrice),
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF10B981)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      );
    }

    // Densidad 4: Grilla 2x2
    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      itemCount: products.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 0.76,
      ),
      itemBuilder: (context, i) {
        final p = products[i];
        return Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFF131126),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF26214A)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: ProductImageView(
                      imagePath: p.photoPath,
                      width: double.infinity,
                      height: double.infinity,
                      iconSize: 24,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                p.name,
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFF8FAFC)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                CurrencyFormatter.format(p.salePrice),
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Color(0xFF10B981)),
              ),
            ],
          ),
        );
      },
    );
  }
}
