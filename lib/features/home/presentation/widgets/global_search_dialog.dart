import 'package:flutter/material.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../products/data/product_repository.dart';
import '../../../products/models/product.dart';
import '../../../products/presentation/screens/product_detail_screen.dart';
import '../../../products/presentation/screens/product_form_screen.dart';
import '../../../products/presentation/widgets/catalog_generator_modal.dart';
import '../../../products/presentation/widgets/product_image_view.dart';
import '../../../products/presentation/widgets/stock_status_badge.dart';
import '../../../sales/presentation/widgets/quick_sale_dialog.dart';
import '../../../business/data/business_repository.dart';

class GlobalSearchDialog extends StatefulWidget {
  final String? businessId;
  final Function(int tabIndex)? onNavigateToTab;

  const GlobalSearchDialog({
    super.key,
    this.businessId,
    this.onNavigateToTab,
  });

  static Future<void> show(
    BuildContext context, {
    String? businessId,
    Function(int tabIndex)? onNavigateToTab,
  }) {
    return showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.65),
      builder: (_) => GlobalSearchDialog(
        businessId: businessId,
        onNavigateToTab: onNavigateToTab,
      ),
    );
  }

  @override
  State<GlobalSearchDialog> createState() => _GlobalSearchDialogState();
}

class _GlobalSearchDialogState extends State<GlobalSearchDialog> {
  final _searchController = TextEditingController();
  final _repository = ProductRepository();
  List<Product> _results = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _onSearchChanged() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      if (mounted) setState(() => _results = []);
      return;
    }

    final bizId = widget.businessId ?? BusinessRepository.instance.currentActiveBusiness?.id;
    if (bizId == null) return;

    setState(() => _isLoading = true);

    try {
      final list = await _repository.searchProducts(
        query,
        businessId: bizId,
      );
      if (mounted) {
        setState(() {
          _results = list;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF131126) : Colors.white;
    final borderColor = isDark ? const Color(0xFF26214A) : const Color(0xFFE2E8F0);
    final cardBg = isDark ? const Color(0xFF18152F) : const Color(0xFFF8FAFC);
    final textMain = isDark ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A);
    final textMuted = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 600),
        child: Container(
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: borderColor, width: 1.2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.6 : 0.15),
                blurRadius: 36,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            children: [
              // Barra de Entrada del Buscador
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF8B5CF6).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.search_rounded, color: Color(0xFFA78BFA), size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        autofocus: true,
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: textMain),
                        decoration: InputDecoration(
                          hintText: 'Buscar por nombre, código o categoría...',
                          hintStyle: TextStyle(fontSize: 13.5, color: textMuted),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          filled: false,
                          contentPadding: EdgeInsets.zero,
                          suffixIcon: _searchController.text.isNotEmpty
                              ? IconButton(
                                  icon: Icon(Icons.close_rounded, size: 18, color: textMuted),
                                  onPressed: () => _searchController.clear(),
                                )
                              : null,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF231E44) : const Color(0xFFE2E8F0),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'ESC',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: textMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: borderColor),

              // Área de Contenido
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator(color: Color(0xFF8B5CF6)))
                    : _searchController.text.trim().isEmpty
                        ? _buildQuickShortcuts(isDark, cardBg, borderColor, textMain, textMuted)
                        : _results.isEmpty
                            ? _buildEmptyResults(textMuted)
                            : _buildResultsList(isDark, cardBg, borderColor, textMain, textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickShortcuts(
    bool isDark,
    Color cardBg,
    Color borderColor,
    Color textMain,
    Color textMuted,
  ) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Text(
            'ACCIONES RÁPIDAS',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
              color: textMuted,
            ),
          ),
        ),
        _buildShortcutTile(
          icon: Icons.inventory_2_rounded,
          iconColor: const Color(0xFF10B981),
          title: 'Ir a Catálogo de Inventario',
          subtitle: 'Consulta y gestiona todos tus productos',
          onTap: () {
            Navigator.pop(context);
            widget.onNavigateToTab?.call(1);
          },
          isDark: isDark,
          cardBg: cardBg,
          borderColor: borderColor,
          textMain: textMain,
        ),
        const SizedBox(height: 8),
        _buildShortcutTile(
          icon: Icons.point_of_sale_rounded,
          iconColor: const Color(0xFF38BDF8),
          title: 'Ir al Historial de Ventas',
          subtitle: 'Revisa las transacciones y pagos registrados',
          onTap: () {
            Navigator.pop(context);
            widget.onNavigateToTab?.call(2);
          },
          isDark: isDark,
          cardBg: cardBg,
          borderColor: borderColor,
          textMain: textMain,
        ),
        const SizedBox(height: 8),
        _buildShortcutTile(
          icon: Icons.add_circle_outline_rounded,
          iconColor: const Color(0xFF8B5CF6),
          title: 'Registrar Nuevo Producto',
          subtitle: 'Añade un nuevo artículo al catálogo',
          onTap: () async {
            final biz = BusinessRepository.instance.currentActiveBusiness;
            if (biz == null) return;
            Navigator.pop(context);
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ProductFormScreen(businessId: biz.id),
              ),
            );
          },
          isDark: isDark,
          cardBg: cardBg,
          borderColor: borderColor,
          textMain: textMain,
        ),
        const SizedBox(height: 8),
        _buildShortcutTile(
          icon: Icons.picture_as_pdf_rounded,
          iconColor: const Color(0xFFEF4444),
          title: 'Generar Catálogo en PDF',
          subtitle: 'Exporta tu catálogo comercial para clientes',
          onTap: () {
            final biz = BusinessRepository.instance.currentActiveBusiness;
            if (biz == null) return;
            Navigator.pop(context);
            CatalogGeneratorModal.show(context: context, business: biz);
          },
          isDark: isDark,
          cardBg: cardBg,
          borderColor: borderColor,
          textMain: textMain,
        ),
      ],
    );
  }

  Widget _buildShortcutTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    required bool isDark,
    required Color cardBg,
    required Color borderColor,
    required Color textMain,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: textMain),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Color(0xFF64748B), size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyResults(Color textMuted) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.search_off_rounded, size: 48, color: textMuted.withOpacity(0.5)),
          const SizedBox(height: 12),
          Text(
            'Sin resultados encontrados',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: textMuted),
          ),
          const SizedBox(height: 4),
          Text(
            'Intenta con otro término, código de barras o categoría',
            style: TextStyle(fontSize: 12, color: textMuted.withOpacity(0.8)),
          ),
        ],
      ),
    );
  }

  Widget _buildResultsList(
    bool isDark,
    Color cardBg,
    Color borderColor,
    Color textMain,
    Color textMuted,
  ) {
    return ListView.separated(
      padding: const EdgeInsets.all(14),
      itemCount: _results.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final product = _results[index];

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            children: [
              // Foto
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: ProductImageView(
                  imagePath: product.photoPath,
                  width: 48,
                  height: 48,
                  iconSize: 22,
                ),
              ),
              const SizedBox(width: 14),

              // Información
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.name,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: textMain,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Text(
                          'Cod: ${product.code}',
                          style: TextStyle(fontSize: 11, color: textMuted),
                        ),
                        const SizedBox(width: 8),
                        StockStatusBadge(product: product),
                      ],
                    ),
                  ],
                ),
              ),

              // Precio y Acciones
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    CurrencyFormatter.format(product.salePrice),
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF10B981),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Botón Ver
                      InkWell(
                        onTap: () async {
                          Navigator.pop(context);
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ProductDetailScreen(product: product),
                            ),
                          );
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF26214A) : const Color(0xFFE2E8F0),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.visibility_outlined, size: 14, color: textMuted),
                              const SizedBox(width: 4),
                              Text(
                                'Ver',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),

                      // Botón Vender
                      InkWell(
                        onTap: () async {
                          Navigator.pop(context);
                          await QuickSaleDialog.show(context, product);
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: const Color(0xFF059669),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.shopping_bag_outlined, size: 14, color: Colors.white),
                              SizedBox(width: 4),
                              Text(
                                'Vender',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
