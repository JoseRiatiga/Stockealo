import '../../../../core/theme/app_tokens.dart';
import '../../../pro/data/pro_service.dart';
import '../../data/app_functions.dart';
import '../../../business/presentation/active_business_scope.dart';
import 'package:flutter/material.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../products/data/product_repository.dart';
import '../../../products/models/product.dart';
import '../../../products/presentation/screens/product_detail_screen.dart';
import '../../../products/presentation/widgets/product_image_view.dart';
import '../../../products/presentation/widgets/stock_status_badge.dart';
import '../../../sales/presentation/widgets/quick_sale_dialog.dart';

class GlobalSearchDialog extends StatefulWidget {
  final String? businessId;
  final Function(int tabIndex)? onNavigateToTab;
  final String? userRole;

  const GlobalSearchDialog({
    super.key,
    this.businessId,
    this.onNavigateToTab,
    this.userRole,
  });

  static Future<void> show(
    BuildContext context, {
    String? businessId,
    Function(int tabIndex)? onNavigateToTab,
    String? userRole,
  }) {
    return showDialog(
      context: context,
      builder: (_) => GlobalSearchDialog(
        businessId: businessId,
        onNavigateToTab: onNavigateToTab,
        userRole: userRole,
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

    final bizId = widget.businessId ?? ActiveBusinessScope.read(context)?.id;
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
    final c = context.colors;
    return Dialog(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.xxl),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.sheet),
        side: BorderSide(color: c.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 600),
        child: Column(
          children: [
            // Campo de búsqueda
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.sm, AppSpace.sm, AppSpace.sm),
              child: Row(
                children: [
                  Icon(Icons.search_rounded, color: c.inkMuted, size: 22),
                  const SizedBox(width: AppSpace.md),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      autofocus: true,
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.ink),
                      decoration: InputDecoration(
                        hintText: 'Busca un producto o una función',
                        hintStyle: TextStyle(fontSize: 14, color: c.inkFaint),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        filled: false,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                  if (_searchController.text.isNotEmpty)
                    IconButton(
                      tooltip: 'Borrar',
                      icon: Icon(Icons.close_rounded, size: 18, color: c.inkMuted),
                      onPressed: () => _searchController.clear(),
                    ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cerrar'),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: c.line),

            // Contenido
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : Builder(builder: (context) {
                      // Funciones de la app: el buscador lleva a su único lugar (0.12.0)
                      final query = _searchController.text.trim();
                      final functions = findFunctions(
                        query,
                        role: widget.userRole ?? 'CASHIER',
                        services: ProService.instance.status.value.services,
                      );
                      if (query.isEmpty) return _buildAllFunctions(functions);
                      if (_results.isEmpty && functions.isEmpty) return _buildEmptyResults();
                      return ListView(
                        padding: const EdgeInsets.all(AppSpace.lg),
                        children: [
                          if (functions.isNotEmpty) ...[
                            _sectionLabel('Funciones'),
                            for (final f in functions.take(3)) ...[
                              _functionTile(f),
                              const SizedBox(height: AppSpace.sm),
                            ],
                          ],
                          if (_results.isNotEmpty) ...[
                            if (functions.isNotEmpty) const SizedBox(height: AppSpace.sm),
                            _sectionLabel('Productos'),
                            for (final p in _results) ...[
                              _productTile(p),
                              const SizedBox(height: AppSpace.sm),
                            ],
                          ],
                        ],
                      );
                    }),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(left: AppSpace.xs, bottom: AppSpace.sm),
        child: Text(text, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: context.colors.inkMuted)),
      );

  /// Sin escribir: todas las funciones de la app y dónde viven
  Widget _buildAllFunctions(List<AppFunction> functions) {
    return ListView(
      padding: const EdgeInsets.all(AppSpace.lg),
      children: [
        _sectionLabel('Dónde está cada cosa'),
        for (final f in functions) ...[
          _functionTile(f),
          const SizedBox(height: AppSpace.sm),
        ],
      ],
    );
  }

  Widget _functionTile(AppFunction f) {
    final c = context.colors;
    return Material(
      color: c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
        side: BorderSide(color: c.line),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.control),
        onTap: () {
          Navigator.pop(context);
          widget.onNavigateToTab?.call(f.tab);
        },
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.md),
          child: Row(
            children: [
              Icon(f.icon, color: c.accent, size: 22),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(f.title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.ink)),
                    const SizedBox(height: 2),
                    Text('Está en ${f.where}', style: TextStyle(fontSize: 12, color: c.inkMuted)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: c.inkFaint, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyResults() {
    final c = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off_rounded, size: 40, color: c.inkFaint),
            const SizedBox(height: AppSpace.md),
            Text('No encontramos nada', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.ink)),
            const SizedBox(height: AppSpace.xs),
            Text('Prueba con otra palabra, el código de barras o la categoría.',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: c.inkMuted)),
          ],
        ),
      ),
    );
  }

  Widget _productTile(Product product) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: c.line),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.control),
            child: ProductImageView(imagePath: product.photoPath, width: 48, height: 48, iconSize: 22),
          ),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(product.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.ink)),
                const SizedBox(height: 4),
                Wrap(
                  spacing: AppSpace.sm,
                  runSpacing: AppSpace.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(CurrencyFormatter.format(product.salePrice), style: AppText.amount(context, size: 14)),
                    StockStatusBadge(product: product),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpace.sm),
          OutlinedButton(
            onPressed: () => _openProduct(product),
            style: OutlinedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
            ),
            child: const Text('Ver'),
          ),
          const SizedBox(width: AppSpace.xs),
          FilledButton(
            onPressed: () => _sellProduct(product),
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
            ),
            child: const Text('Vender'),
          ),
        ],
      ),
    );
  }

  /// Se toma el navegador antes de cerrar el buscador: después de cerrarlo, su
  /// propio contexto ya no sirve para abrir otra pantalla.
  Future<void> _openProduct(Product product) async {
    final nav = Navigator.of(context);
    nav.pop();
    await nav.push(MaterialPageRoute(builder: (_) => ProductDetailScreen(product: product)));
  }

  Future<void> _sellProduct(Product product) async {
    final nav = Navigator.of(context);
    nav.pop();
    await QuickSaleDialog.show(nav.context, product);
  }
}
