import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/theme/app_tokens.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../business/models/business.dart';
import '../../../business/presentation/business_identity.dart';
import '../../../reports/models/catalog_style.dart';
import '../../models/product.dart';
import 'product_image_view.dart';

/// Historias verticales 9:16 para Estados de WhatsApp e Instagram, con el mismo
/// estilo del catálogo en PDF.
class StoryCatalogModal extends StatefulWidget {
  final Business business;
  final List<Product> products;
  final CatalogStyle style;

  const StoryCatalogModal({
    super.key,
    required this.business,
    required this.products,
    this.style = const CatalogStyle(),
  });

  static Future<void> show({
    required BuildContext context,
    required Business business,
    required List<Product> products,
    CatalogStyle style = const CatalogStyle(),
  }) {
    return showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.85),
      builder: (_) => StoryCatalogModal(business: business, products: products, style: style),
    );
  }

  @override
  State<StoryCatalogModal> createState() => _StoryCatalogModalState();
}

class _StoryCatalogModalState extends State<StoryCatalogModal> {
  final _pageController = PageController();
  int _currentPageIndex = 0;
  bool _isExporting = false;
  late int _density = widget.style.itemsPerPage >= 4 ? 4 : widget.style.itemsPerPage;

  // Claves para capturar cada historia como imagen
  final Map<int, GlobalKey> _storyKeys = {};

  late final _StoryColors _colors = _StoryColors.of(widget.style, widget.business.color);

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  List<List<Product>> get _storyPages => [
        for (var i = 0; i < widget.products.length; i += _density) widget.products.skip(i).take(_density).toList(),
      ];

  Future<void> _shareCurrentStory() async {
    final key = _storyKeys[_currentPageIndex];
    if (key == null) return;
    setState(() => _isExporting = true);

    try {
      final boundary = key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) throw Exception('No se pudo dibujar la historia');

      final ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) throw Exception('No se pudo crear la imagen');

      final tempDir = await getTemporaryDirectory();
      final cleanBiz = widget.business.name.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
      final file = File('${tempDir.path}/Historia_${cleanBiz}_${_currentPageIndex + 1}.png');
      await file.writeAsBytes(byteData.buffer.asUint8List(), flush: true);

      if (mounted) {
        setState(() => _isExporting = false);
        await Share.shareXFiles(
          [XFile(file.path, mimeType: 'image/png', name: 'Historia_${widget.business.name}.png')],
          text: 'Mira los productos de ${widget.business.name}',
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isExporting = false);
        AppToast.show(context, message: 'No se pudo exportar la historia: $e', type: ToastType.error);
      }
    }
  }

  void _setDensity(int density) {
    setState(() {
      _density = density;
      _currentPageIndex = 0;
      _storyKeys.clear();
    });
    _pageController.jumpToPage(0);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final pages = _storyPages;

    return Dialog(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: const RoundedRectangleBorder(),
      insetPadding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.xl),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.sm, AppSpace.xs, AppSpace.sm),
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
                    children: [
                      Text('Historias', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.ink)),
                      Text(
                        '${_currentPageIndex + 1} de ${pages.length}',
                        style: TextStyle(fontSize: 12, color: c.inkMuted),
                      ),
                    ],
                  ),
                ),
                SegmentedButton<int>(
                  showSelectedIcon: false,
                  style: const ButtonStyle(visualDensity: VisualDensity.compact),
                  segments: const [
                    ButtonSegment(value: 1, label: Text('1')),
                    ButtonSegment(value: 2, label: Text('2')),
                    ButtonSegment(value: 4, label: Text('4')),
                  ],
                  selected: {_density},
                  onSelectionChanged: (v) => _setDensity(v.first),
                ),
                IconButton(
                  tooltip: 'Cerrar',
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(Icons.close_rounded, color: c.inkMuted),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpace.md),
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: 9 / 16,
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: pages.length,
                  onPageChanged: (idx) => setState(() => _currentPageIndex = idx),
                  itemBuilder: (context, index) => RepaintBoundary(
                    key: _storyKeys.putIfAbsent(index, () => GlobalKey()),
                    child: _buildStoryCard(pages[index]),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpace.md),
          SizedBox(
            width: 320,
            child: FilledButton.icon(
              onPressed: _isExporting ? null : _shareCurrentStory,
              icon: _isExporting
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.share_rounded, size: 18),
              label: Text(_isExporting ? 'Preparando imagen…' : 'Compartir esta historia'),
            ),
          ),
        ],
      ),
    );
  }

  /// Historia 9:16: encabezado con el color del catálogo, productos y contacto
  Widget _buildStoryCard(List<Product> products) {
    final k = _colors;
    final style = widget.style;
    final title = style.title.trim().isNotEmpty ? style.title.trim() : 'Catálogo de productos';
    final contact = style.whatsapp.trim().isNotEmpty
        ? 'Pídelo por WhatsApp: ${style.whatsapp.trim()}'
        : 'Pregunta por tu producto favorito';
    final extra = [
      if (style.address.trim().isNotEmpty) style.address.trim(),
      if (style.hours.trim().isNotEmpty) style.hours.trim(),
      if (style.social.trim().isNotEmpty) style.social.trim(),
    ].join(' · ');

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.sheet),
      child: Container(
        color: k.page,
        padding: const EdgeInsets.all(AppSpace.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpace.md),
              decoration: BoxDecoration(color: k.accent, borderRadius: BorderRadius.circular(AppRadius.card)),
              child: Row(
                children: [
                  CatalogLogo(business: widget.business, color: k.accent, size: 38),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.business.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white),
                        ),
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpace.md),
            Expanded(child: _buildProductLayout(products)),
            const SizedBox(height: AppSpace.md),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm),
              decoration: BoxDecoration(color: k.accentSoft, borderRadius: BorderRadius.circular(AppRadius.control)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.chat_rounded, size: 15, color: k.price),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      contact,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: k.price),
                    ),
                  ),
                ],
              ),
            ),
            if (extra.isNotEmpty || style.showBranding) ...[
              const SizedBox(height: 6),
              Text(
                [if (extra.isNotEmpty) extra, if (style.showBranding) 'Hecho con Stockealo'].join(' · '),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 9.5, color: k.muted),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _box({required Widget child, EdgeInsets padding = const EdgeInsets.all(AppSpace.sm)}) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: _colors.card,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: _colors.line),
        ),
        child: child,
      );

  Widget _image(Product p, double iconSize) {
    final hasPhoto = p.photoPath != null && p.photoPath!.trim().isNotEmpty;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.control),
      child: hasPhoto
          ? ProductImageView(imagePath: p.photoPath, width: double.infinity, height: double.infinity, iconSize: iconSize)
          : Container(
              color: _colors.imageBg,
              alignment: Alignment.center,
              child: Icon(Icons.inventory_2_outlined, size: iconSize, color: _colors.muted),
            ),
    );
  }

  String? _meta(Product p) {
    final parts = [
      if (widget.style.showCategory && p.category.trim().isNotEmpty) p.category.trim(),
      if (widget.style.showCode && p.code.isNotEmpty) 'Ref. ${p.code}',
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  Widget _priceRow(Product p, double size) {
    final style = widget.style;
    return Row(
      children: [
        if (style.showPrice)
          Expanded(
            child: Text(
              CurrencyFormatter.format(p.salePrice),
              maxLines: 1,
              style: TextStyle(fontSize: size, fontWeight: FontWeight.w800, color: _colors.price),
            ),
          )
        else
          const Spacer(),
        if (style.showExactStock)
          Text('${p.stock} disp.', style: TextStyle(fontSize: size * 0.55, color: _colors.muted)),
      ],
    );
  }

  Widget _buildProductLayout(List<Product> products) {
    final k = _colors;
    final style = widget.style;

    if (_density == 1) {
      final p = products.first;
      final meta = _meta(p);
      final hasDescription = style.showDescription && (p.description?.trim().isNotEmpty ?? false);
      return _box(
        padding: const EdgeInsets.all(AppSpace.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _image(p, 56)),
            const SizedBox(height: AppSpace.md),
            if (meta != null)
              Text(meta, maxLines: 1, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: k.muted)),
            Text(
              p.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: k.ink, height: 1.2),
            ),
            if (hasDescription) ...[
              const SizedBox(height: 4),
              Text(
                p.description!.trim(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, color: k.muted),
              ),
            ],
            const SizedBox(height: AppSpace.sm),
            _priceRow(p, 22),
          ],
        ),
      );
    }

    if (_density == 2) {
      return Column(
        children: [
          for (final p in products)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.sm),
                child: _box(
                  child: Row(
                    children: [
                      SizedBox(width: 96, child: _image(p, 32)),
                      const SizedBox(width: AppSpace.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (_meta(p) != null)
                              Text(_meta(p)!, maxLines: 1, style: TextStyle(fontSize: 9.5, color: k.muted)),
                            Text(
                              p.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: k.ink),
                            ),
                            const SizedBox(height: 6),
                            _priceRow(p, 16),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          // Si la última historia queda con un solo producto, no se estira
          if (products.length < 2) const Spacer(),
        ],
      );
    }

    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      itemCount: products.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: AppSpace.sm,
        mainAxisSpacing: AppSpace.sm,
        childAspectRatio: 0.76,
      ),
      itemBuilder: (context, i) {
        final p = products[i];
        return _box(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _image(p, 24)),
              const SizedBox(height: 6),
              Text(
                p.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: k.ink),
              ),
              _priceRow(p, 13),
            ],
          ),
        );
      },
    );
  }
}

/// Colores de la historia: no siguen el tema de la app sino el estilo del catálogo
class _StoryColors {
  final Color accent;
  final Color accentSoft;
  final Color price;
  final Color page;
  final Color card;
  final Color imageBg;
  final Color ink;
  final Color muted;
  final Color line;

  const _StoryColors({
    required this.accent,
    required this.accentSoft,
    required this.price,
    required this.page,
    required this.card,
    required this.imageBg,
    required this.ink,
    required this.muted,
    required this.line,
  });

  factory _StoryColors.of(CatalogStyle style, String? businessColor) {
    final accent = AppPalette.fromHex(style.colorHex) ?? AppPalette.fromHex(businessColor) ?? AppPalette.brand;
    if (style.darkBackground) {
      return _StoryColors(
        accent: accent,
        accentSoft: Color.lerp(AppPalette.paperDark, accent, 0.3)!,
        price: Color.lerp(accent, Colors.white, 0.35)!,
        page: AppPalette.paperDark,
        card: AppPalette.surfaceDark,
        imageBg: AppPalette.surfaceMutedDark,
        ink: AppPalette.inkDark,
        muted: AppPalette.inkMutedDark,
        line: AppPalette.lineDark,
      );
    }
    return _StoryColors(
      accent: accent,
      accentSoft: Color.lerp(Colors.white, accent, 0.12)!,
      price: accent,
      page: AppPalette.paper,
      card: AppPalette.surface,
      imageBg: AppPalette.surfaceMuted,
      ink: AppPalette.ink,
      muted: AppPalette.inkMuted,
      line: AppPalette.line,
    );
  }
}

