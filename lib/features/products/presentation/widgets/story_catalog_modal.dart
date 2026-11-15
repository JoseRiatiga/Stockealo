import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_tokens.dart';
import '../../../../core/utils/share_images.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../business/models/business.dart';
import '../../../business/presentation/business_identity.dart';
import '../../../reports/models/catalog_style.dart';
import '../../../store/data/online_store_service.dart';
import '../../data/product_templates.dart';
import '../../models/product.dart';
import 'product_image_view.dart';
import '../../../reports/data/catalog_pdf_service.dart';

/// Formatos de Instagram (0.16.0, fase 3)
enum PostFormat {
  story('Historia', 9 / 16, Icons.smartphone_outlined),
  square('Cuadrado', 1, Icons.crop_square_outlined),
  portrait('Vertical', 4 / 5, Icons.crop_portrait_outlined),
  carousel('Carrusel', 4 / 5, Icons.view_carousel_outlined);

  final String label;
  final double ratio;
  final IconData icon;
  const PostFormat(this.label, this.ratio, this.icon);

  /// En el carrusel va un producto por imagen, hasta 10
  static const carouselMax = 10;
}

/// Publicar en Instagram (0.16.0, fase 3; antes «Historias»): historia 9:16, cuadrado
/// 1:1, vertical 4:5 o carrusel de hasta 10 imágenes, con el mismo estilo del catálogo.
/// Cada imagen puede llevar el link de la tienda, su QR y la cinta de oferta; abajo sale
/// el texto listo para copiar (con los hashtags del negocio y los de su tipo).
/// «Compartir en Instagram» abre el menú de compartir del celular (decisión del 15 nov).
class StoryCatalogModal extends StatefulWidget {
  final Business business;
  final List<Product> products;
  final CatalogStyle style;

  /// La tienda publicada: su link, su QR y los hashtags propios del negocio
  final OnlineStoreConfig? store;

  const StoryCatalogModal({
    super.key,
    required this.business,
    required this.products,
    this.style = const CatalogStyle(),
    this.store,
  });

  static Future<void> show({
    required BuildContext context,
    required Business business,
    required List<Product> products,
    CatalogStyle style = const CatalogStyle(),
    OnlineStoreConfig? store,
  }) {
    return showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.85),
      builder: (_) => StoryCatalogModal(business: business, products: products, style: style, store: store),
    );
  }

  /// El texto para Instagram: los productos, el link y los hashtags (los del negocio
  /// primero, después los suyos y los de su tipo de negocio)
  static String caption({
    required Business business,
    required List<Product> products,
    String? storeUrl,
    List<String> ownHashtags = const [],
    String Function(Product p)? price,
  }) {
    final priceOf = price ?? (Product p) => CatalogPdfService.instance.priceOf(p);
    final lines = <String>[
      if (products.length == 1) ...[
        '${products.first.name} a ${priceOf(products.first)}',
        if ((products.first.description ?? '').trim().isNotEmpty) products.first.description!.trim(),
      ] else ...[
        'Lo nuevo en ${business.name}:',
        for (final p in products.take(6)) '• ${p.name} · ${priceOf(p)}',
        if (products.length > 6) '…y ${products.length - 6} más',
      ],
      '',
      storeUrl != null ? 'Pide aquí 👉 ${storeUrl.replaceFirst('https://', '')}' : 'Pídelo por mensaje directo',
    ];
    final suggested = ProductTemplate.suggestedFor(business.icon)?.hashtags ?? const ['#Domicilios'];
    final tags = <String>[];
    for (final t in [StoreLook.nameHashtag(business.name), ...ownHashtags, ...suggested]) {
      if (t != null && !tags.any((x) => x.toLowerCase() == t.toLowerCase())) tags.add(t);
    }
    return [...lines, '', tags.take(12).join(' ')].join('\n');
  }

  @override
  State<StoryCatalogModal> createState() => _StoryCatalogModalState();
}

class _StoryCatalogModalState extends State<StoryCatalogModal> {
  final _pageController = PageController();
  int _currentPageIndex = 0;
  bool _isExporting = false;
  late int _density = widget.style.itemsPerPage >= 4 ? 4 : widget.style.itemsPerPage;
  PostFormat _format = PostFormat.story;
  late bool _showLink = widget.store != null;
  late bool _showQr = widget.store != null;
  bool _showRibbon = true;

  // Claves para capturar cada imagen
  final Map<int, GlobalKey> _storyKeys = {};

  late final _StoryColors _colors = _StoryColors.of(widget.style, widget.business.color);

  String? get _storeUrl => widget.store?.url;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  int get _perImage => _format == PostFormat.carousel ? 1 : _density;

  List<List<Product>> get _storyPages {
    final products = _format == PostFormat.carousel ? widget.products.take(PostFormat.carouselMax).toList() : widget.products;
    return [
      for (var i = 0; i < products.length; i += _perImage) products.skip(i).take(_perImage).toList(),
    ];
  }

  List<Product> get _captionProducts => _format == PostFormat.carousel
      ? _storyPages.expand((p) => p).toList()
      : (_storyPages.isEmpty ? <Product>[] : _storyPages[_currentPageIndex.clamp(0, _storyPages.length - 1)]);

  String get _caption => StoryCatalogModal.caption(
        business: widget.business,
        products: _captionProducts,
        storeUrl: _showLink ? _storeUrl : null,
        ownHashtags: widget.store?.look.hashtags ?? const [],
      );

  void _reset(VoidCallback change) {
    setState(() {
      change();
      _currentPageIndex = 0;
      _storyKeys.clear();
    });
    if (_pageController.hasClients) _pageController.jumpToPage(0);
  }

  /// Compartir la imagen que se ve o, en el carrusel, todas (pasando por cada una
  /// para que se dibuje antes de tomarle la foto)
  Future<void> _share() async {
    setState(() => _isExporting = true);
    try {
      final pages = _storyPages;
      final keys = <GlobalKey>[];
      if (_format == PostFormat.carousel) {
        for (var i = 0; i < pages.length; i++) {
          _pageController.jumpToPage(i);
          await WidgetsBinding.instance.endOfFrame;
          await Future<void>.delayed(const Duration(milliseconds: 120));
          final k = _storyKeys[i];
          if (k != null) keys.add(k);
        }
      } else {
        final k = _storyKeys[_currentPageIndex];
        if (k != null) keys.add(k);
      }
      if (keys.isEmpty) throw StateError('No se pudo dibujar la imagen.');
      await shareImages(keys, baseName: '${_format.label}_${widget.business.name}', text: _caption);
    } catch (e) {
      if (mounted) AppToast.show(context, message: 'No se pudo preparar la imagen: $e', type: ToastType.error);
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _copyCaption() async {
    await Clipboard.setData(ClipboardData(text: _caption));
    if (mounted) AppToast.show(context, message: 'Texto copiado', type: ToastType.success);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final pages = _storyPages;

    Widget toggle(String label, bool value, ValueChanged<bool> onChanged) => Padding(
          padding: const EdgeInsets.only(right: AppSpace.xs + 2),
          child: FilterChip(
            label: Text(label),
            selected: value,
            visualDensity: VisualDensity.compact,
            onSelected: (v) => setState(() => onChanged(v)),
          ),
        );

    return Dialog(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: const RoundedRectangleBorder(),
      insetPadding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.lg),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.xs, AppSpace.sm),
              decoration:
                  BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(AppRadius.card), border: Border.all(color: c.line)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Instagram', style: TextStyle(fontSize: AppText.sizeBodyLarge, fontWeight: FontWeight.w700, color: c.ink)),
                            Text('${_currentPageIndex + 1} de ${pages.length}',
                                style: TextStyle(fontSize: AppText.sizeCaption, color: c.inkMuted)),
                          ],
                        ),
                      ),
                      if (_format != PostFormat.carousel)
                        SegmentedButton<int>(
                          showSelectedIcon: false,
                          style: const ButtonStyle(visualDensity: VisualDensity.compact),
                          segments: const [
                            ButtonSegment(value: 1, label: Text('1')),
                            ButtonSegment(value: 2, label: Text('2')),
                            ButtonSegment(value: 4, label: Text('4')),
                          ],
                          selected: {_density},
                          onSelectionChanged: (v) => _reset(() => _density = v.first),
                        ),
                      IconButton(
                        tooltip: 'Cerrar',
                        onPressed: () => Navigator.pop(context),
                        icon: Icon(Icons.close_outlined, color: c.inkMuted),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpace.xs),
                  Wrap(
                    runSpacing: AppSpace.xs,
                    children: [
                      for (final f in PostFormat.values)
                        Padding(
                          padding: const EdgeInsets.only(right: AppSpace.xs + 2),
                          child: ChoiceChip(
                            avatar: Icon(f.icon, size: 16),
                            label: Text(f.label),
                            selected: _format == f,
                            visualDensity: VisualDensity.compact,
                            onSelected: (_) => _reset(() => _format = f),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpace.xs),
                  Wrap(
                    runSpacing: AppSpace.xs,
                    children: [
                      if (_storeUrl != null) ...[
                        toggle('Link de la tienda', _showLink, (v) => _showLink = v),
                        toggle('QR', _showQr, (v) => _showQr = v),
                      ],
                      toggle('Cinta de oferta', _showRibbon, (v) => _showRibbon = v),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpace.sm),
            Expanded(
              child: Center(
                child: AspectRatio(
                  aspectRatio: _format.ratio,
                  child: PageView.builder(
                    key: ValueKey('$_format-$_density'),
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
            const SizedBox(height: AppSpace.sm),
            Container(
              padding: const EdgeInsets.all(AppSpace.sm),
              decoration:
                  BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(AppRadius.card), border: Border.all(color: c.line)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(_caption,
                      maxLines: 4, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: AppText.sizeCaption, color: c.inkMuted)),
                  const SizedBox(height: AppSpace.xs),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _copyCaption,
                          icon: const Icon(Icons.copy_outlined, size: 18),
                          label: const Text('Copiar texto'),
                        ),
                      ),
                      const SizedBox(width: AppSpace.sm),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _isExporting || pages.isEmpty ? null : _share,
                          icon: _isExporting
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.share_outlined, size: 18),
                          label: Text(
                            _isExporting
                                ? 'Preparando…'
                                : _format == PostFormat.carousel
                                    ? 'Compartir ${pages.length}'
                                    : 'Compartir en Instagram',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Historia 9:16: encabezado con el color del catálogo, productos y contacto
  Widget _buildStoryCard(List<Product> products) {
    final k = _colors;
    final style = widget.style;
    final title = style.title.trim().isNotEmpty ? style.title.trim() : 'Catálogo de productos';
    final contact =
        style.whatsapp.trim().isNotEmpty ? 'Pídelo por WhatsApp: ${style.whatsapp.trim()}' : 'Pregunta por tu producto favorito';
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
                          style: const TextStyle(fontSize: AppText.sizeBodyLarge, fontWeight: FontWeight.w700, color: Colors.white),
                        ),
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: AppText.sizeCaption, color: Colors.white),
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
                  // QR de la tienda (0.16.0): fondo blanco para que lo lea cualquier cámara
                  if (_showQr && _storeUrl != null) ...[
                    Container(
                      padding: const EdgeInsets.all(3),
                      color: Colors.white,
                      child: BarcodeWidget(barcode: Barcode.qrCode(), data: _storeUrl!, width: 44, height: 44, color: Colors.black),
                    ),
                    const SizedBox(width: AppSpace.sm),
                  ] else ...[
                    Icon(Icons.chat_outlined, size: 15, color: k.price),
                    const SizedBox(width: 6),
                  ],
                  Flexible(
                    child: Text(
                      _showLink && _storeUrl != null ? 'Pide en ${_storeUrl!.replaceFirst('https://', '')}' : contact,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: AppText.sizeCaption, fontWeight: FontWeight.w700, color: k.price),
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
                style: TextStyle(fontSize: AppText.sizeCaption, color: k.muted),
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
    final photo = _photo(p, iconSize);
    if (!_showRibbon || !CatalogPdfService.instance.hasPromo(p)) return photo;
    return Stack(
      fit: StackFit.expand,
      children: [
        photo,
        Positioned(
          top: 6,
          left: 6,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(color: _colors.accent, borderRadius: BorderRadius.circular(AppRadius.control)),
            child: const Text('OFERTA', style: TextStyle(fontSize: AppText.sizeCaption, fontWeight: FontWeight.w800, color: Colors.white)),
          ),
        ),
      ],
    );
  }

  Widget _photo(Product p, double iconSize) {
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
              CatalogPdfService.instance.priceOf(p),
              maxLines: 1,
              style: TextStyle(fontSize: size, fontWeight: FontWeight.w800, color: _colors.price),
            ),
          )
        else
          const Spacer(),
        if (style.showExactStock) Text('${p.stock} disp.', style: TextStyle(fontSize: size * 0.55, color: _colors.muted)),
      ],
    );
  }

  Widget _buildProductLayout(List<Product> products) {
    final k = _colors;
    final style = widget.style;

    if (_perImage == 1) {
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
              Text(meta, maxLines: 1, style: TextStyle(fontSize: AppText.sizeCaption, fontWeight: FontWeight.w600, color: k.muted)),
            Text(
              p.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: AppText.sizeTitle, fontWeight: FontWeight.w700, color: k.ink, height: 1.2),
            ),
            if (hasDescription) ...[
              const SizedBox(height: 4),
              Text(
                p.description!.trim(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: AppText.sizeCaption, color: k.muted),
              ),
            ],
            const SizedBox(height: AppSpace.sm),
            _priceRow(p, 22),
          ],
        ),
      );
    }

    if (_perImage == 2) {
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
                            // En el cuadrado las filas son bajas: sin el detalle y el nombre en una línea
                            if (_meta(p) != null && _format != PostFormat.square)
                              Text(_meta(p)!, maxLines: 1, style: TextStyle(fontSize: AppText.sizeCaption, color: k.muted)),
                            Flexible(
                              child: Text(
                                p.name,
                                maxLines: _format == PostFormat.square ? 1 : 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: AppText.sizeBody, fontWeight: FontWeight.w700, color: k.ink),
                              ),
                            ),
                            const SizedBox(height: 4),
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
                style: TextStyle(fontSize: AppText.sizeCaption, fontWeight: FontWeight.w700, color: k.ink),
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
