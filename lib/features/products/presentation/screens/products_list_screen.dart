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
import '../../../../core/services/supabase_service.dart';

class ProductsListScreen extends StatefulWidget {
  final String userId;
  final VoidCallback? onLogout;

  const ProductsListScreen({
    super.key,
    required this.userId,
    this.onLogout,
  });

  @override
  State<ProductsListScreen> createState() => _ProductsListScreenState();
}

class _ProductsListScreenState extends State<ProductsListScreen> {
  final _repository = ProductRepository();
  final _businessRepo = BusinessRepository.instance;
  final _searchController = TextEditingController();

  Business? _activeBusiness;
  List<Product> _products = [];
  List<Category> _categories = [];
  String _selectedCategory = 'Todos';
  String _sortOption = 'default';
  String _stockFilterOption = 'all';
  Map<String, dynamic> _stats = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _businessRepo.activeBusinessNotifier.addListener(_onBusinessChanged);
    _loadData();
    _syncSilently();
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
    _businessRepo.activeBusinessNotifier.removeListener(_onBusinessChanged);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
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

    // Criterio de ordenamiento
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
      case 'name_asc':
        filteredProducts.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        break;
      case 'name_desc':
        filteredProducts.sort((a, b) => b.name.toLowerCase().compareTo(a.name.toLowerCase()));
        break;
    }

    if (mounted) {
      setState(() {
        _products = filteredProducts;
        _categories = categories;
        _stats = stats;
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

  Future<void> _showQuickStockDialog(Product product) async {
    final controller = TextEditingController(text: product.stock.toString());
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Ajustar Stock: ${product.name}'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Nuevo Stock',
            prefixIcon: Icon(Icons.inventory_2_outlined),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              final val = int.tryParse(controller.text.trim());
              if (val != null && val >= 0) {
                Navigator.pop(ctx, true);
              }
            },
            child: const Text('Actualizar'),
          ),
        ],
      ),
    );

    if (result == true) {
      final newStock = int.parse(controller.text.trim());
      await _repository.adjustStock(
        product.id,
        product.businessId,
        newStock,
        'Ajuste rápido desde catálogo',
      );
      _loadData();
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    String tempSort = _sortOption;
    String tempStockFilter = _stockFilterOption;

    final applied = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalCtx, setModalState) {
            final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
            final textMain = isDark ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A);
            final textMuted = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
            final borderColor = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);

            Widget buildSortItem(String value, String label, IconData icon) {
              final isSelected = tempSort == value;
              return InkWell(
                onTap: () => setModalState(() => tempSort = value),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  margin: const EdgeInsets.only(bottom: 6),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? (const Color(0xFF059669).withOpacity(0.12))
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isSelected ? const Color(0xFF059669) : borderColor,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        icon,
                        size: 18,
                        color: isSelected ? const Color(0xFF059669) : textMuted,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          label,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                            color: isSelected ? const Color(0xFF059669) : textMain,
                          ),
                        ),
                      ),
                      if (isSelected)
                        const Icon(Icons.check_circle_rounded, size: 18, color: Color(0xFF059669)),
                    ],
                  ),
                ),
              );
            }

            Widget buildStockFilterChip(String value, String label, Color color) {
              final isSelected = tempStockFilter == value;
              return Expanded(
                child: InkWell(
                  onTap: () => setModalState(() => tempStockFilter = value),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isSelected ? color.withOpacity(0.15) : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSelected ? color : borderColor,
                        width: isSelected ? 1.5 : 1,
                      ),
                    ),
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                        color: isSelected ? color : textMuted,
                      ),
                    ),
                  ),
                ),
              );
            }

            return Container(
              padding: EdgeInsets.fromLTRB(
                20,
                16,
                20,
                MediaQuery.of(ctx).padding.bottom + 20,
              ),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF475569) : Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Filtros y Ordenamiento',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: textMain,
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            setModalState(() {
                              tempSort = 'default';
                              tempStockFilter = 'all';
                            });
                          },
                          child: const Text('Restablecer', style: TextStyle(fontSize: 12.5)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'ESTADO DEL STOCK',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: textMuted),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        buildStockFilterChip('all', 'Todos', const Color(0xFF059669)),
                        const SizedBox(width: 8),
                        buildStockFilterChip('low_stock', 'Bajo Stock', const Color(0xFFD97706)),
                        const SizedBox(width: 8),
                        buildStockFilterChip('out_of_stock', 'Agotados', const Color(0xFFDC2626)),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'ORDENAR POR',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: textMuted),
                    ),
                    const SizedBox(height: 8),
                    buildSortItem('default', 'Predeterminado (Más recientes)', Icons.schedule_rounded),
                    buildSortItem('stock_desc', 'Mayor stock disponible', Icons.inventory_2_rounded),
                    buildSortItem('stock_asc', 'Menor stock (Por agotarse)', Icons.production_quantity_limits_rounded),
                    buildSortItem('price_desc', 'Mayor precio de venta', Icons.arrow_upward_rounded),
                    buildSortItem('price_asc', 'Menor precio de venta', Icons.arrow_downward_rounded),
                    buildSortItem('margin_desc', 'Mayor margen de ganancia', Icons.trending_up_rounded),
                    buildSortItem('name_asc', 'Alfabético (A - Z)', Icons.sort_by_alpha_rounded),
                    buildSortItem('name_desc', 'Alfabético (Z - A)', Icons.sort_by_alpha_rounded),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF059669),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Aplicar Filtros', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (applied == true) {
      setState(() {
        _sortOption = tempSort;
        _stockFilterOption = tempStockFilter;
      });
      _loadData();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: InkWell(
          onTap: () async {
            final changed = await BusinessSelectorModal.show(
              context,
              userId: widget.userId,
              onLogout: widget.onLogout,
            );
            if (changed == true) {
              _loadData();
            }
          },
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.storefront, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    _activeBusiness?.name ?? 'Stockealo',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
                const Icon(Icons.arrow_drop_down, color: Colors.white),
              ],
            ),
          ),
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            tooltip: 'Más opciones',
            onSelected: (val) {
              if (val == 'catalog') {
                _openCatalogModal();
              } else if (val == 'excel') {
                _exportToExcel();
              } else if (val == 'categories') {
                _openManageCategories();
              } else if (val == 'restock') {
                _openRestockOrderModal();
              }
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 'catalog',
                child: Row(
                  children: [
                    Icon(Icons.picture_as_pdf_outlined, color: Color(0xFFDC2626), size: 20),
                    SizedBox(width: 8),
                    Text('Catálogo en PDF'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'restock',
                child: Row(
                  children: [
                    Icon(Icons.local_shipping_outlined, color: Color(0xFFD97706), size: 20),
                    SizedBox(width: 8),
                    Text('Pedido a proveedor'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'categories',
                child: Row(
                  children: [
                    Icon(Icons.tune, color: Color(0xFF2563EB), size: 20),
                    SizedBox(width: 8),
                    Text('Gestionar categorías'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'excel',
                child: Row(
                  children: [
                    Icon(Icons.table_chart_outlined, color: Color(0xFF059669), size: 20),
                    SizedBox(width: 8),
                    Text('Exportar a Excel (.xlsx)'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _handleRefresh,
        color: const Color(0xFF059669),
        child: CustomScrollView(
          slivers: [
            // Resumen de Métricas de Stock Superior
            SliverToBoxAdapter(
              child: _buildStatsHeader(),
            ),

            // Barra de búsqueda con lector de código y botón de filtros
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        onChanged: (_) => _loadData(),
                        decoration: InputDecoration(
                          hintText: 'Buscar por nombre o código...',
                          prefixIcon: const Icon(Icons.search, color: Color(0xFF64748B)),
                          suffixIcon: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_searchController.text.isNotEmpty)
                                IconButton(
                                  icon: const Icon(Icons.clear, size: 18),
                                  onPressed: () {
                                    _searchController.clear();
                                    _loadData();
                                  },
                                ),
                              IconButton(
                                icon: const Icon(Icons.qr_code_scanner, color: Color(0xFF059669)),
                                tooltip: 'Escanear para buscar',
                                onPressed: _scanToSearch,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: _openSortFilterModal,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: (_sortOption != 'default' || _stockFilterOption != 'all')
                              ? const Color(0xFF059669).withOpacity(0.15)
                              : (Theme.of(context).brightness == Brightness.dark
                                  ? const Color(0xFF1E293B)
                                  : Colors.white),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: (_sortOption != 'default' || _stockFilterOption != 'all')
                                ? const Color(0xFF059669)
                                : (Theme.of(context).brightness == Brightness.dark
                                    ? const Color(0xFF334155)
                                    : const Color(0xFFCBD5E1)),
                          ),
                        ),
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Icon(
                              Icons.tune_rounded,
                              size: 22,
                              color: (_sortOption != 'default' || _stockFilterOption != 'all')
                                  ? const Color(0xFF059669)
                                  : const Color(0xFF64748B),
                            ),
                            if (_sortOption != 'default' || _stockFilterOption != 'all')
                              Positioned(
                                top: -2,
                                right: -2,
                                child: Container(
                                  width: 8,
                                  height: 8,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF059669),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Filtro por categorías con botón de gestión
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: CategoryFilterBar(
                        categories: _categories,
                        selectedCategory: _selectedCategory,
                        onCategorySelected: (cat) {
                          setState(() {
                            _selectedCategory = cat;
                          });
                          _loadData();
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: IconButton(
                        icon: const Icon(Icons.tune, size: 20, color: Color(0xFF64748B)),
                        tooltip: 'Gestionar categorías',
                        onPressed: _openManageCategories,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Lista de productos
            if (_isLoading)
              const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_products.isEmpty)
              SliverFillRemaining(
                child: _buildEmptyState(),
              )
            else
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final product = _products[index];
                    return ProductCard(
                      product: product,
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ProductDetailScreen(product: product),
                          ),
                        );
                        _loadData();
                      },
                      onAdjustStock: () => _showQuickStockDialog(product),
                      onSale: () async {
                        final sold = await QuickSaleDialog.show(context, product);
                        if (sold == true) {
                          _loadData();
                        }
                      },
                    );
                  },
                  childCount: _products.length,
                ),
              ),

            SliverToBoxAdapter(
              child: SizedBox(height: MediaQuery.of(context).padding.bottom + 80), // Margen dinámico para Android safe area y el FAB
            ),
          ],
        ),
      ),
      floatingActionButton: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom),
        child: FloatingActionButton(
          onPressed: () async {
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
          },
          backgroundColor: const Color(0xFF059669),
          foregroundColor: Colors.white,
          elevation: 4,
          shape: const CircleBorder(),
          tooltip: 'Nuevo Producto',
          child: const Icon(Icons.add, size: 28),
        ),
      ),
    );
  }

  Widget _buildStatsHeader() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final total = _stats['totalProducts'] ?? 0;
    final outOfStock = _stats['outOfStock'] ?? 0;
    final lowStock = _stats['lowStock'] ?? 0;
    final totalValue = _stats['totalValue'] ?? 0.0;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildStatItem('Total Artículos', '$total', isDark ? const Color(0xFFF8FAFC) : const Color(0xFF1E293B)),
              _buildStatItem('Bajo Stock', '$lowStock', const Color(0xFFD97706)),
              _buildStatItem('Agotados', '$outOfStock', const Color(0xFFDC2626)),
            ],
          ),
          if (totalValue > 0) ...[
            Divider(height: 20, color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Valor comercial en inventario:',
                  style: TextStyle(fontSize: 12, color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
                ),
                Text(
                  CurrencyFormatter.format(totalValue),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF059669),
                  ),
                ),
              ],
            ),
          ],
          if (lowStock > 0 || outOfStock > 0) ...[
            const SizedBox(height: 12),
            InkWell(
              onTap: _openRestockOrderModal,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF78350F).withOpacity(0.5) : const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: isDark ? const Color(0xFFD97706) : const Color(0xFFFDE68A)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.local_shipping_outlined, size: 18, color: Color(0xFFD97706)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${lowStock + outOfStock} productos para reponer • Generar pedido',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isDark ? const Color(0xFFFDE68A) : const Color(0xFF92400E),
                        ),
                      ),
                    ),
                    Icon(Icons.arrow_forward_ios, size: 12, color: isDark ? const Color(0xFFFDE68A) : const Color(0xFF92400E)),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatItem(String title, String count, Color color) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      children: [
        Text(
          count,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          title,
          style: TextStyle(
            fontSize: 11,
            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF064E3B) : const Color(0xFFECFDF5),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.inventory_2_outlined,
                size: 56,
                color: Color(0xFF059669),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              _searchController.text.isNotEmpty
                  ? 'No se encontraron productos'
                  : 'Aún no tienes productos registrados',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isDark ? const Color(0xFFF8FAFC) : const Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _searchController.text.isNotEmpty
                  ? 'Intenta con otro término de búsqueda o limpia el filtro.'
                  : 'Toca el botón "+ Nuevo Producto" para comenzar a registrar tu catálogo y stock.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
