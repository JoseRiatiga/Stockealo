import '../../../../core/theme/app_tokens.dart';
import '../../../pro/data/pro_service.dart';
import '../../data/app_functions.dart';
import '../../../business/presentation/active_business_scope.dart';
import 'package:flutter/material.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../customers/data/customer_repository.dart';
import '../../../customers/models/customer.dart';
import '../../../customers/presentation/screens/customers_screen.dart';
import '../../../products/data/product_repository.dart';
import '../../../products/models/product.dart';
import '../../../products/presentation/screens/product_detail_screen.dart';
import '../../../products/presentation/widgets/product_image_view.dart';
import '../../../products/presentation/widgets/stock_status_badge.dart';
import '../../../sales/presentation/screens/sell_screen.dart';
import '../../navigation/app_places.dart';

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
  List<Customer> _customers = [];
  bool _isLoading = false;

  /// Cada letra que se escribe lanza una búsqueda: solo vale la última
  int _query = 0;

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
    final run = ++_query;
    if (query.isEmpty) {
      if (mounted) {
        setState(() {
          _results = [];
          _customers = [];
        });
      }
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
      // Clientes por nombre o teléfono (0.16.6, hallazgo 45)
      final customers = matchCustomers(await CustomerRepository.instance.getCustomers(bizId), query);
      if (mounted && run == _query) {
        setState(() {
          _results = list;
          _customers = customers;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted && run == _query) setState(() => _isLoading = false);
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
                  Icon(Icons.search_outlined, color: c.inkMuted, size: 22),
                  const SizedBox(width: AppSpace.md),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      autofocus: true,
                      style: TextStyle(fontSize: AppText.sizeBodyLarge, fontWeight: FontWeight.w600, color: c.ink),
                      decoration: InputDecoration(
                        hintText: 'Busca un producto, un cliente o una función',
                        hintStyle: TextStyle(fontSize: AppText.sizeBody, color: c.inkFaint),
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
                      icon: Icon(Icons.close_outlined, size: 18, color: c.inkMuted),
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
                      if (_results.isEmpty && _customers.isEmpty && functions.isEmpty) return _buildEmptyResults();
                      return ListView(
                        padding: const EdgeInsets.all(AppSpace.lg),
                        children: [
                          if (functions.isNotEmpty) ...[
                            _sectionLabel('Funciones'),
                            for (final f in functions.take(5)) ...[
                              _functionTile(f),
                              const SizedBox(height: AppSpace.sm),
                            ],
                          ],
                          if (_customers.isNotEmpty) ...[
                            if (functions.isNotEmpty) const SizedBox(height: AppSpace.sm),
                            _sectionLabel('Clientes'),
                            for (final cu in _customers.take(5)) ...[
                              _customerTile(cu),
                              const SizedBox(height: AppSpace.sm),
                            ],
                          ],
                          if (_results.isNotEmpty) ...[
                            if (functions.isNotEmpty || _customers.isNotEmpty) const SizedBox(height: AppSpace.sm),
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
        child: Text(text, style: TextStyle(fontSize: AppText.sizeSmall, fontWeight: FontWeight.w700, color: context.colors.inkMuted)),
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
                    Text(f.title, style: TextStyle(fontSize: AppText.sizeBody, fontWeight: FontWeight.w600, color: c.ink)),
                    const SizedBox(height: 2),
                    Text('Está en ${f.where}', style: TextStyle(fontSize: AppText.sizeCaption, color: c.inkMuted)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_outlined, color: c.inkFaint, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  /// Un cliente: lleva a Clientes con la lista filtrada por él
  Widget _customerTile(Customer cu) {
    final c = context.colors;
    final detail = [
      if ((cu.phone ?? '').trim().isNotEmpty) cu.phone!.trim(),
      cu.hasDebt ? 'Debe ${CurrencyFormatter.format(cu.debtBalance)}' : 'Al día',
    ].join(' · ');
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
          CustomersScreen.focus.value = cu.name;
          widget.onNavigateToTab?.call(AppPlace.personas);
        },
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.md),
          child: Row(
            children: [
              Icon(Icons.person_outline, color: c.accent, size: 22),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(cu.name, style: TextStyle(fontSize: AppText.sizeBody, fontWeight: FontWeight.w600, color: c.ink)),
                    const SizedBox(height: 2),
                    Text(detail, style: TextStyle(fontSize: AppText.sizeCaption, color: cu.hasDebt ? c.warning : c.inkMuted)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_outlined, color: c.inkFaint, size: 20),
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
            Icon(Icons.search_off_outlined, size: 40, color: c.inkFaint),
            const SizedBox(height: AppSpace.md),
            Text('No encontramos nada', style: TextStyle(fontSize: AppText.sizeBodyLarge, fontWeight: FontWeight.w700, color: c.ink)),
            const SizedBox(height: AppSpace.xs),
            Text('Prueba con otra palabra, el código de barras o la categoría.',
                textAlign: TextAlign.center, style: TextStyle(fontSize: AppText.sizeSmall, color: c.inkMuted)),
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
                    style: TextStyle(fontSize: AppText.sizeBody, fontWeight: FontWeight.w600, color: c.ink)),
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
    await SellScreen.sell(nav.context, product);
    AppPlace.go(AppPlace.vender);
  }
}

/// Clientes cuyo nombre o teléfono tiene lo escrito, sin importar tildes ni mayúsculas
List<Customer> matchCustomers(List<Customer> all, String query) {
  final q = foldText(query.trim());
  if (q.isEmpty) return const [];
  final digits = q.replaceAll(RegExp(r'[^0-9]'), '');
  return [
    for (final c in all)
      if (foldText(c.name).contains(q) || (digits.length >= 3 && (c.phone ?? '').replaceAll(RegExp(r'[^0-9]'), '').contains(digits))) c,
  ];
}
