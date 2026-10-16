import 'package:flutter/material.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../business/data/business_repository.dart';
import '../../../customers/data/customer_repository.dart';
import '../../../customers/models/customer.dart';
import '../../../products/data/product_repository.dart';
import '../../../products/models/product.dart';
import '../../../products/presentation/widgets/product_image_view.dart';
import '../../data/sales_repository.dart';
import 'digital_ticket_modal.dart';

class QuickSaleDialog extends StatefulWidget {
  final Product? product;
  final bool isDialog;

  const QuickSaleDialog({
    super.key,
    this.product,
    this.isDialog = false,
  });

  static Future<bool?> show(BuildContext context, [Product? product]) {
    final isDesktop = MediaQuery.of(context).size.width >= 850;

    if (isDesktop) {
      return showDialog<bool>(
        context: context,
        barrierColor: Colors.black.withOpacity(0.65),
        builder: (_) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: QuickSaleDialog(product: product, isDialog: true),
            ),
          ),
        ),
      );
    }

    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => QuickSaleDialog(product: product, isDialog: false),
    );
  }

  @override
  State<QuickSaleDialog> createState() => _QuickSaleDialogState();
}

class _QuickSaleDialogState extends State<QuickSaleDialog> {
  final _salesRepo = SalesRepository();
  final _productRepo = ProductRepository();
  final _customerController = TextEditingController();
  final _searchProductController = TextEditingController();

  Product? _selectedProduct;
  List<Product> _availableProducts = [];
  bool _isSearchingProducts = false;

  int _quantity = 1;
  String _paymentMethod = 'EFECTIVO'; // 'EFECTIVO' | 'TRANSFERENCIA' | 'FIADO'
  bool _isLoading = false;
  List<Customer> _existingCustomers = [];

  @override
  void initState() {
    super.initState();
    _selectedProduct = widget.product;
    if (_selectedProduct != null) {
      _quantity = _selectedProduct!.stock > 0 ? 1 : 0;
      _loadCustomers(_selectedProduct!.businessId);
    } else {
      _loadInitialProducts();
    }
  }

  Future<void> _loadInitialProducts() async {
    final biz = BusinessRepository.instance.currentActiveBusiness;
    if (biz != null) {
      _loadCustomers(biz.id);
      try {
        final list = await _productRepo.searchProducts('', businessId: biz.id);
        if (mounted) {
          setState(() {
            _availableProducts = list.where((p) => p.stock > 0).toList();
          });
        }
      } catch (_) {}
    }
  }

  Future<void> _searchProducts(String query) async {
    final biz = BusinessRepository.instance.currentActiveBusiness;
    if (biz == null) return;

    if (query.trim().isEmpty) {
      _loadInitialProducts();
      return;
    }

    setState(() => _isSearchingProducts = true);
    try {
      final list = await _productRepo.searchProducts(query, businessId: biz.id);
      if (mounted) {
        setState(() {
          _availableProducts = list;
          _isSearchingProducts = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isSearchingProducts = false);
    }
  }

  Future<void> _loadCustomers(String businessId) async {
    try {
      final list = await CustomerRepository.instance.getCustomers(businessId);
      if (mounted) {
        setState(() => _existingCustomers = list);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _customerController.dispose();
    _searchProductController.dispose();
    super.dispose();
  }

  void _increment() {
    if (_selectedProduct != null && _quantity < _selectedProduct!.stock) {
      setState(() => _quantity++);
    }
  }

  void _decrement() {
    if (_quantity > 1) {
      setState(() => _quantity--);
    }
  }

  Future<void> _submitSale() async {
    final product = _selectedProduct;
    if (product == null) return;
    if (_quantity <= 0 || _quantity > product.stock) return;

    if (_paymentMethod == 'FIADO' && _customerController.text.trim().isEmpty) {
      AppToast.showWarning(
        context,
        'Por favor escribe o selecciona el nombre del cliente para el fiado.',
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final sale = await _salesRepo.recordSale(
        product: product,
        quantity: _quantity,
        paymentMethod: _paymentMethod,
        customerName: _paymentMethod == 'FIADO' ? _customerController.text.trim() : null,
      );

      if (mounted) {
        final remainingStock = product.stock - _quantity;
        final nav = Navigator.of(context);
        nav.pop(true);

        AppToast.showSuccess(
          context,
          'Se vendieron $_quantity unid. de "${product.name}". Stock restante: $remainingStock.',
          title: '¡Venta Registrada!',
        );

        DigitalTicketModal.show(context, sale: sale);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        AppToast.showError(context, 'Error al registrar la venta: $e');
      }
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

    final p = _selectedProduct;

    return Container(
      padding: EdgeInsets.fromLTRB(
        22,
        20,
        22,
        widget.isDialog ? 24 : MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).padding.bottom + 20,
      ),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: widget.isDialog
            ? BorderRadius.circular(24)
            : const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(color: borderColor, width: 1.2),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Barra superior / Cabecera
            if (!widget.isDialog)
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF332D5C) : Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: const Color(0xFF059669).withOpacity(0.18),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.flash_on_rounded, color: Color(0xFF10B981), size: 18),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Venta Rápida',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.3,
                        color: textMain,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(Icons.close_rounded, color: textMuted, size: 20),
                  splashRadius: 18,
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Si aún no hay producto seleccionado, mostrar buscador de productos
            if (p == null) ...[
              TextField(
                controller: _searchProductController,
                autofocus: true,
                onChanged: _searchProducts,
                decoration: const InputDecoration(
                  labelText: 'Buscar producto para vender',
                  hintText: 'Nombre, código o categoría...',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
              ),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 280),
                child: _isSearchingProducts
                    ? const Center(child: CircularProgressIndicator())
                    : _availableProducts.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.all(24),
                            child: Center(
                              child: Text(
                                'No se encontraron productos con stock.',
                                style: TextStyle(color: textMuted, fontSize: 13),
                              ),
                            ),
                          )
                        : ListView.separated(
                            shrinkWrap: true,
                            itemCount: _availableProducts.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 6),
                            itemBuilder: (context, idx) {
                              final prod = _availableProducts[idx];
                              return InkWell(
                                onTap: () {
                                  setState(() {
                                    _selectedProduct = prod;
                                    _quantity = prod.stock > 0 ? 1 : 0;
                                  });
                                  _loadCustomers(prod.businessId);
                                },
                                borderRadius: BorderRadius.circular(12),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: cardBg,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: borderColor),
                                  ),
                                  child: Row(
                                    children: [
                                      ProductImageView(
                                        imagePath: prod.photoPath,
                                        width: 38,
                                        height: 38,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              prod.name,
                                              style: TextStyle(
                                                fontSize: 13.5,
                                                fontWeight: FontWeight.bold,
                                                color: textMain,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            Text(
                                              'Stock: ${prod.stock} unid. • ${CurrencyFormatter.format(prod.salePrice)}',
                                              style: TextStyle(fontSize: 11.5, color: textMuted),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const Icon(Icons.add_circle_outline, size: 20, color: Color(0xFF10B981)),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
              ),
            ] else ...[
              // Producto Seleccionado
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: borderColor),
                ),
                child: Row(
                  children: [
                    ProductImageView(
                      imagePath: p.photoPath,
                      width: 52,
                      height: 52,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            p.name,
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.bold,
                              color: textMain,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${CurrencyFormatter.format(p.salePrice)} / unid. • Stock: ${p.stock}',
                            style: TextStyle(fontSize: 12, color: textMuted),
                          ),
                        ],
                      ),
                    ),
                    if (widget.product == null)
                      TextButton(
                        onPressed: () => setState(() => _selectedProduct = null),
                        child: const Text('Cambiar', style: TextStyle(fontSize: 12)),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // Selector de Cantidad
              Text(
                'Cantidad a vender:',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: textMain),
              ),
              const SizedBox(height: 8),

              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton.filledTonal(
                    onPressed: _decrement,
                    icon: const Icon(Icons.remove_rounded),
                    style: IconButton.styleFrom(
                      backgroundColor: cardBg,
                      foregroundColor: textMain,
                      side: BorderSide(color: borderColor),
                      padding: const EdgeInsets.all(12),
                    ),
                  ),
                  Container(
                    width: 80,
                    alignment: Alignment.center,
                    child: Text(
                      '$_quantity',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: textMain,
                      ),
                    ),
                  ),
                  IconButton.filledTonal(
                    onPressed: _increment,
                    icon: const Icon(Icons.add_rounded),
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFF059669).withOpacity(0.18),
                      foregroundColor: const Color(0xFF10B981),
                      side: BorderSide(color: const Color(0xFF059669).withOpacity(0.4)),
                      padding: const EdgeInsets.all(12),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Resumen Financiero
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF10B981).withOpacity(0.3)),
                  ),
                  child: Text(
                    'Total a Cobrar: ${CurrencyFormatter.format(p.salePrice * _quantity)}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF10B981),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Selector de Método de Pago
              Text(
                'Método de pago:',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: textMain),
              ),
              const SizedBox(height: 10),

              Row(
                children: [
                  _buildPaymentChip('EFECTIVO', Icons.payments_outlined, 'Efectivo', isDark, cardBg, borderColor),
                  const SizedBox(width: 8),
                  _buildPaymentChip('TRANSFERENCIA', Icons.account_balance_outlined, 'Transf.', isDark, cardBg, borderColor),
                  const SizedBox(width: 8),
                  _buildPaymentChip('FIADO', Icons.assignment_outlined, 'Fiado', isDark, cardBg, borderColor),
                ],
              ),

              // Nombre de Cliente si es Fiado
              if (_paymentMethod == 'FIADO') ...[
                const SizedBox(height: 14),
                TextField(
                  controller: _customerController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Nombre del Cliente para el Fiado *',
                    hintText: 'Ej. Juan Pérez...',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                ),
                if (_existingCustomers.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _existingCustomers.take(6).map((c) {
                        return Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ActionChip(
                            label: Text(c.name, style: const TextStyle(fontSize: 11)),
                            avatar: const Icon(Icons.person, size: 14),
                            onPressed: () {
                              _customerController.text = c.name;
                            },
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ],
              const SizedBox(height: 22),

              // Botón de Confirmación
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: _isLoading || p.stock <= 0 ? null : _submitSale,
                  icon: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : const Icon(Icons.check_circle_outline, size: 19),
                  label: Text(
                    _isLoading ? 'Guardando...' : 'Confirmar Venta (${CurrencyFormatter.format(p.salePrice * _quantity)})',
                    style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF059669),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentChip(
    String method,
    IconData icon,
    String label,
    bool isDark,
    Color cardBg,
    Color borderColor,
  ) {
    final isSelected = _paymentMethod == method;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _paymentMethod = method),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFF059669)
                : cardBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? const Color(0xFF10B981) : borderColor,
              width: isSelected ? 1.4 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 14,
                color: isSelected ? Colors.white : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  color: isSelected ? Colors.white : (isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
