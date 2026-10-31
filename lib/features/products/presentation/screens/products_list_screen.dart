import '../../../../core/database/app_database.dart';
import '../../../../core/design/app_card.dart';
import '../../../../core/design/app_pagination.dart';
import '../../../../core/design/primary_action_button.dart';
import '../../../../core/design/quick_access_row.dart';
import '../../../../core/design/skeleton.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../business/presentation/business_identity.dart';
import '../widgets/quick_stock_dialog.dart';
import '../widgets/product_sort_filter_sheet.dart';
import '../../../business/presentation/active_business_scope.dart';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../data/product_repository.dart';
import '../../models/category.dart';
import '../../models/product.dart';
import '../widgets/category_filter_bar.dart';
import '../widgets/manage_categories_modal.dart';
import '../widgets/product_card.dart';
import 'barcode_scanner_screen.dart';
import 'product_detail_screen.dart';
import 'product_form_screen.dart';
import '../../../sales/presentation/widgets/quick_sale_dialog.dart';
import '../../../business/data/business_repository.dart';
import '../../../business/models/business.dart';
import '../../../business/presentation/widgets/business_selector_modal.dart';
import '../../../auth/data/auth_repository.dart';
import '../../../reports/data/excel_export_service.dart';
import '../widgets/restock_order_modal.dart';
import '../widgets/catalog_generator_modal.dart';
import '../../../team/data/team_repository.dart';
import '../../../../core/services/data_events.dart';
import '../../../../core/services/notification_service.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../core/widgets/stocky_empty_state.dart';

class ProductsListScreen extends StatefulWidget {
  final String userId;
  final String? userRole;
  final VoidCallback? onLogout;

  const ProductsListScreen({
    super.key,
    required this.userId,
    this.userRole,
    this.onLogout,
  });

  @override
  State<ProductsListScreen> createState() => _ProductsListScreenState();
}

class _ProductsListScreenState extends State<ProductsListScreen> with ActiveBusinessAware {
  @override
  void onActiveBusinessChanged() => _onBusinessChanged();

  final _repository = ProductRepository();
  final _businessRepo = BusinessRepository.instance;
  final _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  Business? _activeBusiness;
  List<Product> _products = [];
  List<Category> _categories = [];
  String _selectedCategory = 'Todos';
  String _sortOption = 'name_asc';
  String _stockFilterOption = 'all';
  Map<String, dynamic> _stats = {};
  bool _isLoading = true;
  String _effectiveRole = 'OWNER';

  bool get canEditProducts => _effectiveRole == 'OWNER' || _effectiveRole == 'ADMIN';
  bool get canViewCosts => _effectiveRole == 'OWNER' || _effectiveRole == 'ADMIN';

  int _currentPage = 1;
  static const int _pageSize = 12;

  /// Lista o cuadrícula; se recuerda en este dispositivo
  ProductLayout _layout = ProductLayout.list;
  static const _layoutKey = 'inventory_layout';

  List<Product> get _pagedProducts {
    if (_products.isEmpty) return [];
    final startIndex = (_currentPage - 1) * _pageSize;
    if (startIndex >= _products.length) {
      return _products.take(_pageSize).toList();
    }
    final endIndex = math.min(startIndex + _pageSize, _products.length);
    return _products.sublist(startIndex, endIndex);
  }

  @override
  void initState() {
    super.initState();
    AppDatabase.instance.getSetting(_layoutKey).then((value) {
      if (mounted && value == ProductLayout.grid.name) setState(() => _layout = ProductLayout.grid);
    });
    _loadData();
    _syncSilently();
    DataEvents.instance.salesVersion.addListener(_onSalesChanged);
    NotificationService.instance.remoteSalesVersion.addListener(_onSalesChanged);
  }

  /// Una venta (aquí, en otra pestaña o en otro teléfono) cambió el stock
  void _onSalesChanged() {
    if (mounted) _loadData(silent: true);
  }

  void _onBusinessChanged() {
    if (mounted) {
      _loadData();
      _syncSilently();
    }
  }

  Future<void> _syncSilently() async {
    try {
      if (await SupabaseService.instance.isCloudSyncEnabled()) {
        final currentUser = AuthRepository.instance.currentUser;
        await SupabaseService.instance.syncFromCloud(widget.userId, currentUser?.email);
        if (mounted) {
          _loadData();
        }
      }
    } catch (_) {}
  }

  Future<void> _handleRefresh() async {
    try {
      if (await SupabaseService.instance.isCloudSyncEnabled()) {
        final currentUser = AuthRepository.instance.currentUser;
        await SupabaseService.instance.syncFromCloud(widget.userId, currentUser?.email);
      }
    } catch (e) {
      debugPrint('Error sincronizando productos: $e');
    }
    await _loadData();
  }

  @override
  void dispose() {
    DataEvents.instance.salesVersion.removeListener(_onSalesChanged);
    NotificationService.instance.remoteSalesVersion.removeListener(_onSalesChanged);
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// [silent] recarga sin mostrar el indicador de carga, para no mover la lista
  Future<void> _loadData({bool silent = false}) async {
    if (!silent) setState(() => _isLoading = true);
    _activeBusiness = await _businessRepo.getActiveBusiness(widget.userId);

    if (_activeBusiness == null) {
      if (mounted) {
        setState(() {
          _products = [];
          _categories = [];
          _stats = {};
          _isLoading = false;
        });
      }
      return;
    }

    final businessId = _activeBusiness!.id;

    final categories = await _repository.getCategories(businessId);
    if (_selectedCategory != 'Todos' && !categories.any((c) => c.name == _selectedCategory)) {
      _selectedCategory = 'Todos';
    }

    final rawProducts = await _repository.searchProducts(
      _searchController.text.trim(),
      category: _selectedCategory,
      businessId: businessId,
    );
    final stats = await _repository.getInventoryStats(businessId);

    var filteredProducts = List<Product>.from(rawProducts);

    // Filtro por estado de stock
    if (_stockFilterOption == 'low_stock') {
      filteredProducts = filteredProducts.where((p) => p.isLowStock && !p.isOutOfStock).toList();
    } else if (_stockFilterOption == 'out_of_stock') {
      filteredProducts = filteredProducts.where((p) => p.isOutOfStock).toList();
    }

    // Criterio de ordenamiento (Predeterminado: A a la Z)
    switch (_sortOption) {
      case 'stock_desc':
        filteredProducts.sort((a, b) => b.stock.compareTo(a.stock));
        break;
      case 'stock_asc':
        filteredProducts.sort((a, b) => a.stock.compareTo(b.stock));
        break;
      case 'price_desc':
        filteredProducts.sort((a, b) => b.salePrice.compareTo(a.salePrice));
        break;
      case 'price_asc':
        filteredProducts.sort((a, b) => a.salePrice.compareTo(b.salePrice));
        break;
      case 'margin_desc':
        filteredProducts.sort((a, b) =>
            (b.salePrice - b.purchasePrice).compareTo(a.salePrice - a.purchasePrice));
        break;
      case 'name_desc':
        filteredProducts.sort((a, b) => b.name.toLowerCase().compareTo(a.name.toLowerCase()));
        break;
      case 'default':
      case 'name_asc':
      default:
        filteredProducts.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        break;
    }

    // Resolver rol efectivo del usuario para control de acceso
    String role = widget.userRole ?? 'OWNER';
    final user = AuthRepository.instance.currentUser;
    if (user != null) {
      role = await TeamRepository.instance.getUserRoleInBusiness(
        businessId: businessId,
        userId: user.id,
        userEmail: user.email,
      );
    }

    if (mounted) {
      setState(() {
        _products = filteredProducts;
        _categories = categories;
        _stats = stats;
        _effectiveRole = role;
        _isLoading = false;
      });
    }
  }

  Future<void> _scanToSearch() async {
    if (_activeBusiness == null) return;
    final code = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const BarcodeScannerScreen()),
    );
    if (code != null && code.isNotEmpty) {
      _searchController.text = code;
      _loadData();

      // Si hay coincidencia exacta de producto, abrir directamente el detalle
      final exactMatch = await _repository.getProductByCode(code, _activeBusiness!.id);
      if (exactMatch != null && mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ProductDetailScreen(product: exactMatch),
          ),
        );
        _loadData();
      }
    }
  }

  Future<void> _exportToExcel() async {
    if (_activeBusiness == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay una empresa activa seleccionada.'), backgroundColor: Colors.orange),
      );
      return;
    }

    final user = AuthRepository.instance.currentUser;
    final userEmail = user?.email ?? '';

    // Modal de progreso
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: Card(
          elevation: 6,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(16))),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: Color(0xFF059669)),
                SizedBox(height: 18),
                Text(
                  'Generando Excel (.xlsx)...',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                SizedBox(height: 6),
                Text(
                  'Inventario, Ventas y Clientes',
                  style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    bool dialogClosed = false;
    void closeDialog() {
      if (!dialogClosed && mounted) {
        dialogClosed = true;
        Navigator.pop(context);
      }
    }

    try {
      await ExcelExportService.instance.exportBusinessData(
        business: _activeBusiness!,
        userId: widget.userId,
        userEmail: userEmail,
        onGenerated: closeDialog,
      );
      closeDialog();
    } catch (e) {
      closeDialog();
      if (mounted) {
        final errorMsg = e.toString().replaceAll('Exception: ', '');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMsg),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  Future<void> _openManageCategories() async {
    if (_activeBusiness == null) return;
    final changed = await ManageCategoriesModal.show(context, _activeBusiness!.id);
    if (changed == true || mounted) {
      _loadData();
    }
  }

  void _openRestockOrderModal() {
    if (_activeBusiness == null) return;
    final user = AuthRepository.instance.currentUser;
    RestockOrderModal.show(
      context,
      business: _activeBusiness!,
      userName: user?.displayName,
    );
  }

  void _openCatalogModal() {
    if (_activeBusiness == null) return;
    CatalogGeneratorModal.show(
      context: context,
      business: _activeBusiness!,
    );
  }

  Future<void> _openSortFilterModal() async {
    final selection = await ProductSortFilterSheet.show(
      context,
      sort: _sortOption,
      stockFilter: _stockFilterOption,
    );
    if (selection != null) {
      setState(() {
        _sortOption = selection.sort;
        _stockFilterOption = selection.stockFilter;
      });
      _loadData();
    }
  }

  Future<void> _openNewProduct() async {
    if (_activeBusiness == null) return;
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => ProductFormScreen(businessId: _activeBusiness!.id)),
    );
    if (created == true) _loadData();
  }

  Future<void> _openProduct(Product product) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => ProductDetailScreen(product: product)));
    _loadData();
  }

  Future<void> _sellProduct(Product product) async {
    final sold = await QuickSaleDialog.show(context, product);
    if (sold == true) _loadData();
  }

  void _goToPage(int page) {
    setState(() => _currentPage = page);
    if (_scrollController.hasClients) {
      _scrollController.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
  }

  Future<void> _setLayout(ProductLayout layout) async {
    setState(() => _layout = layout);
    await AppDatabase.instance.setSetting(_layoutKey, layout.name);
  }

  bool get _hasActiveFilters => _sortOption != 'name_asc' || _stockFilterOption != 'all';

  ProductCard _card(Product product) => ProductCard(
        product: product,
        layout: _layout,
        showMargin: canViewCosts,
        canAdjustStock: canEditProducts,
        onTap: () => _openProduct(product),
        onAdjustStock: canEditProducts ? () => QuickStockDialog.show(context, product: product, onSaved: _loadData) : null,
        onSale: () => _sellProduct(product),
      );

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isDesktop = MediaQuery.of(context).size.width >= 850;
    return Scaffold(
      appBar: isDesktop
          ? null
          : AppBar(
              title: InkWell(
                onTap: () async {
                  final changed = await BusinessSelectorModal.show(
                    context,
                    userId: widget.userId,
                    onLogout: widget.onLogout,
                  );
                  if (changed == true) _loadData();
                },
                borderRadius: BorderRadius.circular(AppRadius.control),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xs),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_activeBusiness != null) ...[
                        BusinessAvatar(business: _activeBusiness!, size: 26),
                        const SizedBox(width: AppSpace.sm),
                      ],
                      Flexible(
                        child: Text(
                          _activeBusiness?.name ?? 'Stockealo',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
                        ),
                      ),
                      const Icon(Icons.expand_more_rounded),
                    ],
                  ),
                ),
              ),
            ),
      body: RefreshIndicator(
        onRefresh: _handleRefresh,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final double hPadding = math.max(AppSpace.lg, (constraints.maxWidth - 1200) / 2);
            final pagedList = _pagedProducts;
            final totalPages = (_products.length / _pageSize).ceil();
            final columns = _layout == ProductLayout.grid
                ? (constraints.maxWidth >= 1100 ? 4 : (constraints.maxWidth >= 700 ? 3 : 2))
                : (constraints.maxWidth >= 900 ? 2 : 1);

            return CustomScrollView(
              controller: _scrollController,
              slivers: [
                if (isDesktop && canEditProducts)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(hPadding, AppSpace.lg, hPadding, 0),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: PrimaryActionButton(label: 'Nuevo producto', onPressed: _openNewProduct),
                      ),
                    ),
                  ),

                // Resumen del inventario
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(hPadding, AppSpace.md, hPadding, 0),
                    child: _buildStatsHeader(),
                  ),
                ),

                // Accesos rápidos (antes en el menú ⋮)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(hPadding, AppSpace.md, hPadding, 0),
                    child: QuickAccessRow(
                      items: [
                        QuickAccessItem(
                          icon: Icons.menu_book_rounded,
                          label: 'Catálogo',
                          caption: 'PDF e historias',
                          onTap: _openCatalogModal,
                        ),
                        if (canEditProducts)
                          QuickAccessItem(
                            icon: Icons.local_shipping_outlined,
                            label: 'Pedido',
                            caption: 'A proveedor',
                            onTap: _openRestockOrderModal,
                          ),
                        QuickAccessItem(
                          icon: Icons.table_chart_outlined,
                          label: 'Excel',
                          caption: 'Exportar',
                          onTap: _exportToExcel,
                        ),
                      ],
                    ),
                  ),
                ),

                // Buscador a todo el ancho
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(hPadding, AppSpace.lg, hPadding, 0),
                    child: TextField(
                      controller: _searchController,
                      onChanged: (_) {
                        _currentPage = 1;
                        _loadData();
                      },
                      decoration: InputDecoration(
                        hintText: 'Buscar por nombre o código',
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_searchController.text.isNotEmpty)
                              IconButton(
                                icon: const Icon(Icons.close_rounded, size: 20),
                                tooltip: 'Borrar búsqueda',
                                onPressed: () {
                                  _searchController.clear();
                                  _currentPage = 1;
                                  _loadData();
                                },
                              ),
                            IconButton(
                              icon: const Icon(Icons.qr_code_scanner_rounded),
                              tooltip: 'Escanear código',
                              onPressed: _scanToSearch,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // Orden y filtros (un solo botón) + vista lista o cuadrícula
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(hPadding, AppSpace.sm, hPadding, 0),
                    child: Row(
                      children: [
                        OutlinedButton.icon(
                          onPressed: _openSortFilterModal,
                          icon: Icon(Icons.tune_rounded, size: 18, color: _hasActiveFilters ? c.accent : c.inkMuted),
                          label: Text(
                            _hasActiveFilters ? 'Orden: ${_getSortLabel(_sortOption)} · Filtros' : 'Orden: ${_getSortLabel(_sortOption)}',
                            style: TextStyle(fontSize: 13, color: _hasActiveFilters ? c.accent : c.ink),
                          ),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: 10),
                            side: BorderSide(color: _hasActiveFilters ? c.accent : c.line),
                          ),
                        ),
                        const Spacer(),
                        SegmentedButton<ProductLayout>(
                          showSelectedIcon: false,
                          style: SegmentedButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            selectedBackgroundColor: c.surfaceMuted,
                            side: BorderSide(color: c.line),
                          ),
                          segments: const [
                            ButtonSegment(value: ProductLayout.list, icon: Icon(Icons.view_list_rounded), tooltip: 'Ver en lista'),
                            ButtonSegment(value: ProductLayout.grid, icon: Icon(Icons.grid_view_rounded), tooltip: 'Ver en cuadrícula'),
                          ],
                          selected: {_layout},
                          onSelectionChanged: (s) => _setLayout(s.first),
                        ),
                      ],
                    ),
                  ),
                ),

                // Categorías, con "Editar" al final (antes había un segundo botón de filtros)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(hPadding, AppSpace.sm, hPadding, 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: CategoryFilterBar(
                            categories: _categories,
                            selectedCategory: _selectedCategory,
                            onCategorySelected: (cat) {
                              setState(() {
                                _selectedCategory = cat;
                                _currentPage = 1;
                              });
                              _loadData();
                            },
                          ),
                        ),
                        if (canEditProducts)
                          TextButton.icon(
                            onPressed: _openManageCategories,
                            icon: const Icon(Icons.edit_outlined, size: 18),
                            label: const Text('Editar'),
                          ),
                      ],
                    ),
                  ),
                ),

                // Encabezado de la lista con la paginación compacta
                if (!_isLoading && _products.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(hPadding + AppSpace.xs, AppSpace.md, hPadding, AppSpace.xs),
                      child: Row(
                        children: [
                          Text('Productos', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.ink)),
                          const SizedBox(width: AppSpace.sm),
                          Text('${_products.length}', style: AppText.amount(context, size: 14, weight: FontWeight.w500, color: c.inkMuted)),
                          const Spacer(),
                          AppPagination(currentPage: _currentPage, totalPages: totalPages, onPageChanged: _goToPage, compact: true),
                        ],
                      ),
                    ),
                  ),

                if (_isLoading)
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(hPadding, AppSpace.md, hPadding, 0),
                    sliver: SliverList.separated(
                      itemCount: 5,
                      separatorBuilder: (_, __) => const SizedBox(height: AppSpace.sm),
                      itemBuilder: (_, __) => const SkeletonListTile(),
                    ),
                  )
                else if (_products.isEmpty)
                  SliverFillRemaining(hasScrollBody: false, child: _buildEmptyState())
                else if (columns == 1)
                  SliverPadding(
                    padding: EdgeInsets.symmetric(horizontal: hPadding),
                    sliver: SliverList.separated(
                      itemCount: pagedList.length,
                      separatorBuilder: (_, __) => const SizedBox(height: AppSpace.sm),
                      itemBuilder: (_, i) => _card(pagedList[i]),
                    ),
                  )
                else
                  SliverPadding(
                    padding: EdgeInsets.symmetric(horizontal: hPadding),
                    sliver: SliverGrid(
                      gridDelegate: _layout == ProductLayout.grid
                          ? SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: columns,
                              crossAxisSpacing: AppSpace.sm,
                              mainAxisSpacing: AppSpace.sm,
                              childAspectRatio: 0.74,
                            )
                          : SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: columns,
                              crossAxisSpacing: AppSpace.sm,
                              mainAxisSpacing: AppSpace.sm,
                              mainAxisExtent: 88,
                            ),
                      delegate: SliverChildBuilderDelegate((_, i) => _card(pagedList[i]), childCount: pagedList.length),
                    ),
                  ),

                // Paginación completa abajo; espacio para el botón principal y Stocky
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(hPadding, AppSpace.md, hPadding, MediaQuery.of(context).padding.bottom + 150),
                    child: _isLoading
                        ? const SizedBox.shrink()
                        : AppPagination(currentPage: _currentPage, totalPages: totalPages, onPageChanged: _goToPage),
                  ),
                ),
              ],
            );
          },
        ),
      ),
      // El botón principal va a la izquierda: a la derecha está Stocky
      floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
      floatingActionButton: canEditProducts && !isDesktop
          ? Padding(
              // A la altura de la pastilla de Stocky en Inicio, justo encima de la barra
              padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom),
              child: PrimaryActionButton(label: 'Producto', onPressed: _openNewProduct),
            )
          : null,
    );
  }

  Widget _buildStatsHeader() {
    final c = context.colors;
    final total = _stats['totalProducts'] ?? 0;
    final outOfStock = _stats['outOfStock'] ?? 0;
    final lowStock = _stats['lowStock'] ?? 0;
    final totalValue = _stats['totalValue'] ?? 0.0;

    Widget stat(String label, String value, Color color) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value, style: AppText.amount(context, size: 22, color: color)),
              Text(label, style: TextStyle(fontSize: 12, color: c.inkMuted)),
            ],
          ),
        );

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              stat('Productos', '$total', c.ink),
              stat('Stock bajo', '$lowStock', lowStock > 0 ? c.warning : c.ink),
              stat('Agotados', '$outOfStock', outOfStock > 0 ? c.danger : c.ink),
            ],
          ),
          if (canViewCosts && totalValue > 0) ...[
            Divider(height: AppSpace.xl, color: c.line),
            Row(
              children: [
                Expanded(child: Text('Valor del inventario', style: TextStyle(fontSize: 13, color: c.inkMuted))),
                Text(CurrencyFormatter.format(totalValue), style: AppText.amount(context, size: 15)),
              ],
            ),
          ],
          if (lowStock > 0 || outOfStock > 0) ...[
            const SizedBox(height: AppSpace.md),
            Material(
              color: c.warningSoft,
              borderRadius: BorderRadius.circular(AppRadius.control),
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadius.control),
                onTap: _openRestockOrderModal,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: 10),
                  child: Row(
                    children: [
                      Icon(Icons.local_shipping_outlined, size: 18, color: c.warning),
                      const SizedBox(width: AppSpace.sm),
                      Expanded(
                        child: Text(
                          '${lowStock + outOfStock} por reponer · Generar pedido',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.warning),
                        ),
                      ),
                      Icon(Icons.chevron_right_rounded, size: 20, color: c.warning),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    final hasSearch = _searchController.text.isNotEmpty;
    final canCreate = widget.userRole != 'CASHIER';

    return StockyEmptyState(
      title: hasSearch ? 'No se encontraron productos' : 'Catálogo de Inventario Vacío',
      message: hasSearch
          ? 'Intenta con otro término de búsqueda o limpia los filtros activos.'
          : (canCreate
              ? 'Toca el botón "+ Nuevo Producto" para comenzar a registrar tu catálogo y stock.'
              : 'Aún no se han registrado productos en este negocio.'),
      actionLabel: hasSearch
          ? 'Limpiar Búsqueda'
          : (canCreate ? '+ Nuevo Producto' : null),
      onAction: hasSearch
          ? () {
              _searchController.clear();
              _currentPage = 1;
              _loadData();
            }
          : (canCreate
              ? () async {
                  if (_activeBusiness == null) return;
                  final created = await Navigator.push<bool>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ProductFormScreen(businessId: _activeBusiness!.id),
                    ),
                  );
                  if (created == true) {
                    _loadData();
                  }
                }
              : null),
    );
  }

  String _getSortLabel(String option) {
    switch (option) {
      case 'name_desc':
        return 'Z - A';
      case 'stock_desc':
        return 'Stock ↑';
      case 'stock_asc':
        return 'Stock ↓';
      case 'price_desc':
        return 'Precio ↑';
      case 'price_asc':
        return 'Precio ↓';
      case 'margin_desc':
        return 'Margen ↑';
      case 'name_asc':
      case 'default':
      default:
        return 'A - Z';
    }
  }
}
