import 'package:flutter/material.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../data/product_repository.dart';
import '../../models/product.dart';
import '../widgets/barcode_modal.dart';
import '../widgets/product_image_view.dart';
import '../widgets/stock_status_badge.dart';
import 'product_form_screen.dart';
import '../../../auth/data/auth_repository.dart';
import '../../../sales/presentation/widgets/quick_sale_dialog.dart';
import '../../../team/data/team_repository.dart';

class ProductDetailScreen extends StatefulWidget {
  final Product product;

  const ProductDetailScreen({super.key, required this.product});

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  final _repository = ProductRepository();
  final _authRepo = AuthRepository.instance;
  final _teamRepo = TeamRepository.instance;

  late Product _product;
  String _userRole = 'OWNER';

  @override
  void initState() {
    super.initState();
    _product = widget.product;
    _checkRole();
  }

  Future<void> _checkRole() async {
    final user = _authRepo.currentUser;
    if (user != null) {
      final role = await _teamRepo.getUserRoleInBusiness(
        businessId: _product.businessId,
        userId: user.id,
        userEmail: user.email,
      );
      if (mounted) setState(() => _userRole = role);
    }
  }

  bool get canEdit => _userRole == 'OWNER' || _userRole == 'ADMIN';
  bool get canViewCosts => _userRole == 'OWNER' || _userRole == 'ADMIN';

  Future<void> _refreshProduct() async {
    final updated = await _repository.getProductById(_product.id, _product.businessId);
    if (updated != null && mounted) {
      setState(() {
        _product = updated;
      });
    }
  }

  Future<void> _showAdjustStockDialog() async {
    final stockController = TextEditingController(text: _product.stock.toString());
    final reasonController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.inventory_2_rounded, color: Color(0xFF10B981), size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Ajustar Stock', style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.bold)),
                  Text(
                    _product.name,
                    style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8), fontWeight: FontWeight.normal),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Indica la nueva cantidad física disponible y el motivo:',
              style: TextStyle(fontSize: 12.5, color: Color(0xFF94A3B8)),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: stockController,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Nuevo Stock Total',
                prefixIcon: Icon(Icons.pin_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                labelText: 'Motivo del ajuste',
                hintText: 'Ej. Conteo físico, Merma, Compra...',
                prefixIcon: Icon(Icons.comment_outlined),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF059669),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            ),
            onPressed: () {
              final newStock = int.tryParse(stockController.text.trim());
              if (newStock != null && newStock >= 0) {
                Navigator.pop(ctx, true);
              }
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    if (result == true) {
      final newStock = int.parse(stockController.text.trim());
      final reason = reasonController.text.trim().isEmpty
          ? 'Ajuste manual de stock'
          : reasonController.text.trim();

      await _repository.adjustStock(_product.id, _product.businessId, newStock, reason);
      await _refreshProduct();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Stock actualizado correctamente'),
            backgroundColor: Color(0xFF059669),
          ),
        );
      }
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Eliminar producto?'),
        content: Text('¿Seguro que deseas eliminar "${_product.name}" del catálogo?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _repository.deleteProduct(_product.id, _product.businessId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Producto eliminado')),
        );
        Navigator.pop(context, true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isWide = MediaQuery.of(context).size.width >= 780;
    final totalCostInventory = _product.purchasePrice * _product.stock;
    final totalSaleInventory = _product.salePrice * _product.stock;
    final totalPotentialProfit = totalSaleInventory - totalCostInventory;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0A0915) : const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Detalle de Producto'),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_2),
            tooltip: 'Código de Barras / QR',
            onPressed: () => BarcodeModal.show(context, _product),
          ),
          if (canEdit)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Editar',
              onPressed: () async {
                final updated = await Navigator.push<bool>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ProductFormScreen(
                      productToEdit: _product,
                      businessId: _product.businessId,
                    ),
                  ),
                );
                if (updated == true) {
                  _refreshProduct();
                }
              },
            ),
          if (canEdit)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Eliminar',
              onPressed: _confirmDelete,
            ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1040),
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              20,
              16,
              20,
              MediaQuery.of(context).padding.bottom + 28,
            ),
            child: isWide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Columna Izquierda: Foto, QR y Acciones Rápidas
                      SizedBox(
                        width: 340,
                        child: Column(
                          children: [
                            _buildPhotoCard(isDark),
                            const SizedBox(height: 14),
                            _buildBarcodeCard(isDark),
                            const SizedBox(height: 14),
                            _buildQuickActionsCard(isDark),
                          ],
                        ),
                      ),
                      const SizedBox(width: 20),

                      // Columna Derecha: Título, Stock, Precios y Métricas Comerciales
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildHeaderBlock(isDark),
                            const SizedBox(height: 14),
                            _buildStockCard(isDark),
                            const SizedBox(height: 14),
                            _buildPricingCard(isDark),
                            if (canViewCosts && _product.stock > 0) ...[
                              const SizedBox(height: 14),
                              _buildValuationCard(
                                isDark: isDark,
                                totalCost: totalCostInventory,
                                totalSale: totalSaleInventory,
                                totalProfit: totalPotentialProfit,
                              ),
                            ],
                            if (_product.description != null && _product.description!.isNotEmpty) ...[
                              const SizedBox(height: 14),
                              _buildDescriptionCard(isDark),
                            ],
                          ],
                        ),
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildPhotoCard(isDark),
                      const SizedBox(height: 14),
                      _buildHeaderBlock(isDark),
                      const SizedBox(height: 14),
                      _buildStockCard(isDark),
                      const SizedBox(height: 14),
                      _buildPricingCard(isDark),
                      if (canViewCosts && _product.stock > 0) ...[
                        const SizedBox(height: 14),
                        _buildValuationCard(
                          isDark: isDark,
                          totalCost: totalCostInventory,
                          totalSale: totalSaleInventory,
                          totalProfit: totalPotentialProfit,
                        ),
                      ],
                      const SizedBox(height: 14),
                      _buildBarcodeCard(isDark),
                      if (_product.description != null && _product.description!.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        _buildDescriptionCard(isDark),
                      ],
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildPhotoCard(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF131126) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? const Color(0xFF26214A) : const Color(0xFFE2E8F0),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.25 : 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: ProductImageView(
          imagePath: _product.photoPath,
          width: double.infinity,
          height: 240,
          iconSize: 64,
          placeholderText: 'Sin foto asignada',
        ),
      ),
    );
  }

  Widget _buildBarcodeCard(bool isDark) {
    return InkWell(
      onTap: () => BarcodeModal.show(context, _product),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF131126) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? const Color(0xFF26214A) : const Color(0xFFE2E8F0),
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF8B5CF6).withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.qr_code_rounded, size: 22, color: Color(0xFF8B5CF6)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Código / SKU',
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _product.code,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.bold,
                      color: isDark ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A),
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, size: 20, color: Color(0xFF8B5CF6)),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActionsCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF131126) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF26214A) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () async {
                final sold = await QuickSaleDialog.show(context, _product);
                if (sold == true) {
                  _refreshProduct();
                }
              },
              icon: const Icon(Icons.add_shopping_cart_rounded, size: 18),
              label: const Text(
                'Registrar Venta',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF8B5CF6),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          if (canEdit) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _showAdjustStockDialog,
                icon: const Icon(Icons.tune_rounded, size: 17),
                label: const Text('Ajustar Stock Físico', style: TextStyle(fontSize: 13)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569),
                  side: BorderSide(
                    color: isDark ? const Color(0xFF26214A) : const Color(0xFFCBD5E1),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHeaderBlock(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF18152F) : const Color(0xFFF3E8FF),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isDark ? const Color(0xFF26214A) : const Color(0xFFE9D5FF),
                ),
              ),
              child: Text(
                _product.category,
                style: const TextStyle(
                  color: Color(0xFF8B5CF6),
                  fontWeight: FontWeight.bold,
                  fontSize: 11.5,
                ),
              ),
            ),
            const SizedBox(width: 8),
            StockStatusBadge(product: _product),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          _product.name,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: isDark ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A),
            height: 1.25,
          ),
        ),
      ],
    );
  }

  Widget _buildStockCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF131126) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? const Color(0xFF26214A) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Inventario Disponible',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${_product.stock} unidades',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: isDark ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Alerta mínima configurada: ${_product.minStock} unid.',
                style: TextStyle(
                  fontSize: 11.5,
                  color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                ),
              ),
            ],
          ),
          ElevatedButton.icon(
            onPressed: () async {
              final sold = await QuickSaleDialog.show(context, _product);
              if (sold == true) {
                _refreshProduct();
              }
            },
            icon: const Icon(Icons.shopping_bag_outlined, size: 17),
            label: const Text('Vender', style: TextStyle(fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPricingCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF131126) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? const Color(0xFF26214A) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Precio de Venta al Público (PVP)',
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                ),
              ),
              Text(
                CurrencyFormatter.format(_product.salePrice),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF10B981),
                ),
              ),
            ],
          ),
          if (canViewCosts) ...[
            Divider(height: 24, color: isDark ? const Color(0xFF26214A) : const Color(0xFFE2E8F0)),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Costo de Compra',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                  ),
                ),
                Text(
                  CurrencyFormatter.format(_product.purchasePrice),
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13.5,
                    color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Ganancia por Unidad',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                  ),
                ),
                Text(
                  '${CurrencyFormatter.format(_product.profit)} (${_product.profitMarginLabel(decimals: 1)})',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13.5,
                    color: _product.profit >= 0 ? const Color(0xFF10B981) : Colors.red,
                  ),
                ),
              ],
            ),
            if (_product.sellsBelowCost) ...[
              const SizedBox(height: 6),
              const Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'Por debajo del costo: cada venta deja pérdida',
                  style: TextStyle(fontSize: 11.5, color: Colors.red),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildValuationCard({
    required bool isDark,
    required double totalCost,
    required double totalSale,
    required double totalProfit,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF131126) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? const Color(0xFF26214A) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Valorización Comercial de Existencias',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13.5,
              color: isDark ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Capital Invertido en Stock:',
                style: TextStyle(fontSize: 12, color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
              ),
              Text(
                CurrencyFormatter.format(totalCost),
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 12.5,
                  color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Venta Total Estimada:',
                style: TextStyle(fontSize: 12, color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
              ),
              Text(
                CurrencyFormatter.format(totalSale),
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 12.5,
                  color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Ganancia Proyectada:',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF10B981)),
              ),
              Text(
                CurrencyFormatter.format(totalProfit),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13.5,
                  color: Color(0xFF10B981),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDescriptionCard(bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF131126) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF26214A) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Descripción / Notas',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _product.description!,
            style: TextStyle(
              color: isDark ? const Color(0xFFF8FAFC) : const Color(0xFF334155),
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
