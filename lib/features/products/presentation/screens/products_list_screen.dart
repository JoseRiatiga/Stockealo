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
import '../../../sales/presentation/screens/sales_history_screen.dart';
import '../../../sales/presentation/widgets/quick_sale_dialog.dart';
import '../../../business/data/business_repository.dart';
import '../../../business/models/business.dart';
import '../../../business/presentation/widgets/business_selector_modal.dart';
import '../../../auth/data/auth_repository.dart';
import '../../../reports/data/excel_export_service.dart';

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
  Map<String, dynamic> _stats = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
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

    final products = await _repository.searchProducts(
      _searchController.text.trim(),
      category: _selectedCategory,
      businessId: businessId,
    );
    final stats = await _repository.getInventoryStats(businessId);

    if (mounted) {
      setState(() {
        _products = products;
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

  Future<void> _scanToSell() async {
    if (_activeBusiness == null) return;
    final code = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const BarcodeScannerScreen()),
    );
    if (code != null && code.isNotEmpty) {
      final product = await _repository.getProductByCode(code, _activeBusiness!.id);
      if (product != null && mounted) {
        final sold = await QuickSaleDialog.show(context, product);
        if (sold == true) {
          _loadData();
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No se encontró ningún producto con el código "$code" en ${_activeBusiness?.name}'),
            backgroundColor: Colors.orange,
          ),
        );
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
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            tooltip: 'Escanear para Vender',
            onPressed: _scanToSell,
          ),
          IconButton(
            icon: const Icon(Icons.receipt_long_outlined),
            tooltip: 'Historial de Ventas',
            onPressed: () async {
              if (_activeBusiness != null) {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SalesHistoryScreen(businessId: _activeBusiness!.id),
                  ),
                );
                _loadData();
              }
            },
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            tooltip: 'Más opciones',
            onSelected: (val) {
              if (val == 'excel') {
                _exportToExcel();
              } else if (val == 'categories') {
                _openManageCategories();
              }
            },
            itemBuilder: (ctx) => [
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
        onRefresh: _loadData,
        color: const Color(0xFF059669),
        child: CustomScrollView(
          slivers: [
            // Resumen de Métricas de Stock Superior
            SliverToBoxAdapter(
              child: _buildStatsHeader(),
            ),

            // Barra de búsqueda con lector de código
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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

            const SliverToBoxAdapter(
              child: SizedBox(height: 80), // Margen para el FAB
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
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
        icon: const Icon(Icons.add),
        label: const Text('Nuevo Producto', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildStatsHeader() {
    final total = _stats['totalProducts'] ?? 0;
    final outOfStock = _stats['outOfStock'] ?? 0;
    final lowStock = _stats['lowStock'] ?? 0;
    final totalValue = _stats['totalValue'] ?? 0.0;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
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
              _buildStatItem('Total Artículos', '$total', const Color(0xFF1E293B)),
              _buildStatItem('Bajo Stock', '$lowStock', const Color(0xFFD97706)),
              _buildStatItem('Agotados', '$outOfStock', const Color(0xFFDC2626)),
            ],
          ),
          if (totalValue > 0) ...[
            const Divider(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Valor comercial en inventario:',
                  style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
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
        ],
      ),
    );
  }

  Widget _buildStatItem(String title, String count, Color color) {
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
          style: const TextStyle(
            fontSize: 11,
            color: Color(0xFF64748B),
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: const BoxDecoration(
                color: Color(0xFFECFDF5),
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
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _searchController.text.isNotEmpty
                  ? 'Intenta con otro término de búsqueda o limpia el filtro.'
                  : 'Toca el botón "+ Nuevo Producto" para comenzar a registrar tu catálogo y stock.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF64748B),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
