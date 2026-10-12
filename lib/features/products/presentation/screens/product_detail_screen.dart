import 'dart:io';
import 'package:flutter/material.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../data/product_repository.dart';
import '../../models/product.dart';
import '../widgets/barcode_modal.dart';
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
        title: const Text('Ajustar Stock'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _product.name,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: stockController,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Nuevo Stock Total',
                prefixIcon: Icon(Icons.inventory_2_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                labelText: 'Motivo del ajuste',
                hintText: 'Ej. Conteo físico, Merma, Compra...',
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
    final hasPhoto = _product.photoPath != null &&
        _product.photoPath!.isNotEmpty &&
        File(_product.photoPath!).existsSync();

    final totalCostInventory = _product.purchasePrice * _product.stock;
    final totalSaleInventory = _product.salePrice * _product.stock;
    final totalPotentialProfit = totalSaleInventory - totalCostInventory;

    return Scaffold(
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
      body: ListView(
        children: [
          // Imagen Principal
          Container(
            height: 250,
            width: double.infinity,
            color: const Color(0xFFF1F5F9),
            child: hasPhoto
                ? Image.file(
                    File(_product.photoPath!),
                    fit: BoxFit.cover,
                  )
                : const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.inventory_2_outlined, size: 64, color: Color(0xFF94A3B8)),
                        SizedBox(height: 8),
                        Text(
                          'Sin foto asignada',
                          style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
          ),

          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Categoría y Código
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFECFDF5),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFFA7F3D0)),
                      ),
                      child: Text(
                        _product.category,
                        style: const TextStyle(
                          color: Color(0xFF059669),
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    InkWell(
                      onTap: () => BarcodeModal.show(context, _product),
                      child: Row(
                        children: [
                          const Icon(Icons.qr_code, size: 16, color: Color(0xFF64748B)),
                          const SizedBox(width: 4),
                          Text(
                            _product.code,
                            style: const TextStyle(
                              color: Color(0xFF64748B),
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Nombre
                Text(
                  _product.name,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 16),

                // Tarjeta de Stock
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Inventario Disponible',
                            style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Text(
                                '${_product.stock} unid.',
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF1E293B),
                                ),
                              ),
                              const SizedBox(width: 10),
                              StockStatusBadge(product: _product),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Alerta si baja de: ${_product.minStock} unid.',
                            style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                          ),
                        ],
                      ),
                      Column(
                        children: [
                          ElevatedButton.icon(
                            onPressed: () async {
                              final sold = await QuickSaleDialog.show(context, _product);
                              if (sold == true) {
                                _refreshProduct();
                              }
                            },
                            icon: const Icon(Icons.shopping_bag_outlined, size: 18),
                            label: const Text('Vender'),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              backgroundColor: const Color(0xFF059669),
                              foregroundColor: Colors.white,
                              elevation: 0,
                            ),
                          ),
                          if (canEdit) ...[
                            const SizedBox(height: 6),
                            OutlinedButton.icon(
                              onPressed: _showAdjustStockDialog,
                              icon: const Icon(Icons.tune, size: 16),
                              label: const Text('Ajustar'),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                foregroundColor: const Color(0xFF475569),
                                side: const BorderSide(color: Color(0xFFCBD5E1)),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Tarjeta de Precios y Rentabilidad
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Precio de Venta al Público', style: TextStyle(color: Color(0xFF64748B))),
                          Text(
                            CurrencyFormatter.format(_product.salePrice),
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF059669),
                            ),
                          ),
                        ],
                      ),
                      if (canViewCosts) ...[
                        const Divider(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Costo de Compra', style: TextStyle(color: Color(0xFF64748B))),
                            Text(
                              CurrencyFormatter.format(_product.purchasePrice),
                              style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF475569)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Ganancia por unidad', style: TextStyle(color: Color(0xFF64748B))),
                            Text(
                              '${CurrencyFormatter.format(_product.profit)} (+${_product.profitMargin.toStringAsFixed(1)}%)',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: _product.profit >= 0 ? const Color(0xFF059669) : Colors.red,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Valorización del lote actual (solo visible para dueños/admins)
                if (canViewCosts && _product.stock > 0)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Valorización de Existencias Actuales',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF334155)),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Capital invertido en stock:', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                            Text(CurrencyFormatter.format(totalCostInventory), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Venta total estimada:', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                            Text(CurrencyFormatter.format(totalSaleInventory), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Ganancia total proyectada:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF059669))),
                            Text(CurrencyFormatter.format(totalPotentialProfit), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF059669))),
                          ],
                        ),
                      ],
                    ),
                  ),

                if (_product.description != null && _product.description!.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'Descripción / Notas',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF334155)),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Text(
                      _product.description!,
                      style: const TextStyle(color: Color(0xFF475569), fontSize: 13),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
