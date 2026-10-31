import '../../../../core/theme/app_tokens.dart';
import '../../../business/presentation/active_business_scope.dart';
import 'package:flutter/material.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../customers/data/customer_repository.dart';
import '../../../customers/models/customer.dart';
import '../../../products/data/product_repository.dart';
import '../../../products/models/product.dart';
import '../../../products/presentation/screens/barcode_scanner_screen.dart';
import '../../../products/presentation/widgets/product_image_view.dart';
import '../../data/sales_repository.dart';
import '../../models/cart_item.dart';
import '../../models/sale.dart';
import '../../../products/models/product_variant.dart';
import '../../../auth/data/auth_repository.dart';
import '../../../team/data/team_repository.dart';
import 'digital_ticket_modal.dart';
import 'quotations_list_modal.dart';

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
            constraints: const BoxConstraints(maxWidth: 580),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: QuickSaleDialog(product: product, isDialog: true),
            ),
          ),
        ),
      );
    }

    return showModalBottomSheet<bool>(
      showDragHandle: false,
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
  final _discountController = TextEditingController();

  final List<CartItem> _cartItems = [];
  List<Product> _availableProducts = [];
  bool _isSearchingProducts = false;
  bool _showProductPicker = false;

  // Descuentos mayoristas / por volumen
  bool _showDiscountBar = false;
  double _discountPercent = 0.0;
  double _discountFixedAmount = 0.0;
  bool _isDiscountPercentMode = true;

  String _paymentMethod = 'EFECTIVO'; // 'EFECTIVO' | 'TRANSFERENCIA' | 'FIADO'
  bool _isLoading = false;
  List<Customer> _existingCustomers = [];

  String _userRole = 'OWNER';
  bool get _isCashier => _userRole == 'CASHIER';

  @override
  void initState() {
    super.initState();
    _loadUserRole();
    if (widget.product != null) {
      if (widget.product!.hasVariants) {
        _showProductPicker = true;
        _loadInitialProducts();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _showVariantSelector(widget.product!);
        });
      } else {
        _cartItems.add(CartItem(
          product: widget.product!,
          quantity: widget.product!.stock > 0 ? 1 : 0,
        ));
      }
      _loadCustomers(widget.product!.businessId);
    } else {
      _showProductPicker = true;
      _loadInitialProducts();
    }
  }

  Future<void> _loadUserRole() async {
    final biz = ActiveBusinessScope.read(context);
    final user = AuthRepository.instance.currentUser;
    if (biz != null && user != null) {
      final role = await TeamRepository.instance.getUserRoleInBusiness(
        businessId: biz.id,
        userId: user.id,
        userEmail: user.email,
      );
      if (mounted) setState(() => _userRole = role);
    }
  }

  Future<void> _loadInitialProducts() async {
    final biz = ActiveBusinessScope.read(context);
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
    final biz = ActiveBusinessScope.read(context);
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
    _discountController.dispose();
    super.dispose();
  }

  void _addProductToCart(Product p, [ProductVariant? variant]) {
    if (p.hasVariants && variant == null) {
      _showVariantSelector(p);
      return;
    }

    final existingIndex = _cartItems.indexWhere(
      (i) => i.product.id == p.id && i.variant?.id == variant?.id,
    );
    final maxStock = variant != null ? variant.stock : p.stock;

    setState(() {
      if (existingIndex >= 0) {
        if (_cartItems[existingIndex].quantity < maxStock) {
          _cartItems[existingIndex].quantity++;
        }
      } else {
        _cartItems.add(CartItem(
          product: p,
          variant: variant,
          quantity: maxStock > 0 ? 1 : 0,
        ));
      }
      _showProductPicker = false;
      _searchProductController.clear();
    });
  }

  Future<void> _showVariantSelector(Product p) async {
    List<ProductVariant> variants = p.variants;
    if (variants.isEmpty) {
      final biz = ActiveBusinessScope.read(context);
      if (biz != null) {
        variants = await _productRepo.getVariantsForProduct(p.id);
      }
    }

    if (variants.isEmpty) {
      _addProductToCart(p, null);
      return;
    }

    if (!mounted) return;

    showModalBottomSheet(
      showDragHandle: false,
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        final sheetBg = context.colors.surface;
        final titleColor = context.colors.ink;

        return Container(
          decoration: BoxDecoration(
            color: sheetBg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: EdgeInsets.fromLTRB(
            20,
            16,
            20,
            MediaQuery.of(ctx).padding.bottom + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: context.colors.inkMuted.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  ProductImageView(
                    imagePath: p.photoPath,
                    width: 44,
                    height: 44,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p.name,
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: titleColor),
                        ),
                        Text(
                          'Selecciona la ${variants.first.attributeName.toLowerCase()} para agregar:',
                          style: TextStyle(fontSize: 12, color: context.colors.inkMuted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: variants.map((v) {
                  final isAvailable = v.stock > 0;
                  return InkWell(
                    onTap: isAvailable
                        ? () {
                            Navigator.pop(ctx);
                            _addProductToCart(p, v);
                          }
                        : null,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: isAvailable
                            ? (context.colors.surfaceMuted)
                            : (context.colors.surfaceMuted),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isAvailable
                              ? context.colors.accent.withOpacity(0.4)
                              : context.colors.inkMuted.withOpacity(0.3),
                          width: 1.2,
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            v.attributeValue,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: isAvailable
                                  ? (context.colors.ink)
                                  : context.colors.inkMuted,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            isAvailable ? '${v.stock} disp.' : 'Agotada',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isAvailable ? context.colors.accent : context.colors.danger,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }

  Future<void> _scanBarcodeToAdd() async {
    final biz = ActiveBusinessScope.read(context);
    if (biz == null) return;

    final code = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const BarcodeScannerScreen()),
    );

    if (code != null && code.isNotEmpty) {
      final product = await _productRepo.getProductByCode(code, biz.id);
      if (product != null) {
        ProductVariant? matchedVariant;
        if (product.hasVariants) {
          for (final v in product.variants) {
            if (v.skuOrBarcode == code) {
              matchedVariant = v;
              break;
            }
          }
        }
        _addProductToCart(product, matchedVariant);
        if (mounted) {
          AppToast.show(
            context,
            message: 'Agregado: ${matchedVariant != null ? "${product.name} (${matchedVariant.attributeValue})" : product.name}',
            type: ToastType.success,
          );
        }
      } else if (mounted) {
        AppToast.show(
          context,
          message: 'No se encontró producto con el código "$code"',
          type: ToastType.warning,
        );
      }
    }
  }

  void _incrementItem(int idx) {
    final item = _cartItems[idx];
    if (item.quantity < item.availableStock) {
      setState(() => item.quantity++);
    }
  }

  void _decrementItem(int idx) {
    final item = _cartItems[idx];
    if (item.quantity > 1) {
      setState(() => item.quantity--);
    } else {
      _removeItem(idx);
    }
  }

  void _removeItem(int idx) {
    setState(() {
      _cartItems.removeAt(idx);
      if (_cartItems.isEmpty) {
        _showProductPicker = true;
        _loadInitialProducts();
      }
    });
  }

  double get _subtotalAmount => _cartItems.fold(0.0, (sum, i) => sum + i.subtotal);

  double get _totalCostAmount => _cartItems.fold(0.0, (sum, i) => sum + (i.product.purchasePrice * i.quantity));

  double get _maxSafeDiscount => (_subtotalAmount - _totalCostAmount).clamp(0.0, double.infinity);

  double get _maxSafePercent => _subtotalAmount > 0 ? ((_maxSafeDiscount / _subtotalAmount) * 100).clamp(0.0, 100.0) : 0.0;

  double get _calculatedDiscount {
    if (_isDiscountPercentMode) {
      return _subtotalAmount * (_discountPercent / 100.0);
    } else {
      return _discountFixedAmount;
    }
  }

  double get _totalToPay => (_subtotalAmount - _calculatedDiscount).clamp(0.0, double.infinity);

  bool get _hasLoss => _totalCostAmount > 0 && (_subtotalAmount - _calculatedDiscount) < _totalCostAmount;

  double get _lossAmount => _hasLoss ? _totalCostAmount - (_subtotalAmount - _calculatedDiscount) : 0.0;

  void _applyQuickPercent(double percent) {
    setState(() {
      _isDiscountPercentMode = true;
      _discountPercent = percent;
      _discountFixedAmount = 0.0;
      _discountController.text = percent > 0 ? percent.toStringAsFixed(0) : '';
    });
  }

  void _applyMaxSafeDiscount() {
    setState(() {
      _isDiscountPercentMode = false;
      _discountPercent = 0.0;
      _discountFixedAmount = _maxSafeDiscount;
      _discountController.text = _maxSafeDiscount.toStringAsFixed(0);
    });
  }

  Future<void> _submitSale() async {
    if (_cartItems.isEmpty) return;
    for (final item in _cartItems) {
      if (item.quantity <= 0 || item.quantity > item.availableStock) {
        AppToast.show(
          context,
          message: 'Revisa las cantidades de "${item.displayName}".',
          type: ToastType.warning,
        );
        return;
      }
    }

    if (_paymentMethod == 'FIADO' && _customerController.text.trim().isEmpty) {
      AppToast.show(
        context,
        message: 'Escribe o elige el cliente del fiado.',
        type: ToastType.warning,
      );
      return;
    }

    final biz = ActiveBusinessScope.read(context);
    if (biz == null) return;

    // Blindaje Anti-Pérdidas: Protección de rentabilidad
    if (_hasLoss) {
      if (_isCashier) {
        AppToast.show(
          context,
          message: 'Ese descuento deja pérdida. Solo el dueño o un administrador pueden autorizarlo.',
          type: ToastType.error,
        );
        return;
      }

      final confirmLoss = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: context.colors.danger),
              const SizedBox(width: 8),
              const Text('Venta bajo el costo'),
            ],
          ),
          content: Text(
            'El descuento aplicado de ${CurrencyFormatter.formatCOP(_calculatedDiscount)} supera la ganancia estimada. Registrarás una pérdida de ${CurrencyFormatter.formatCOP(_lossAmount)} respecto al costo de compra.\n\n¿Estás seguro de que deseas autorizar esta venta?',
            style: const TextStyle(fontSize: 13.5),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Corregir'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: context.colors.danger),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Sí, autorizar', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );

      if (confirmLoss != true) return;
    }

    setState(() => _isLoading = true);

    try {
      final List<Sale> sales = await _salesRepo.recordMultiProductSale(
        businessId: biz.id,
        items: _cartItems,
        paymentMethod: _paymentMethod,
        customerName: _customerController.text.trim().isNotEmpty ? _customerController.text.trim() : null,
        discountAmount: _calculatedDiscount,
      );

      if (mounted) {
        final nav = Navigator.of(context);
        nav.pop(true);

        AppToast.show(
          context,
          message: 'Venta registrada',
          type: ToastType.success,
        );

        DigitalTicketModal.show(
          context,
          salesList: sales,
          discountAmount: _calculatedDiscount,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        AppToast.show(context, message: 'Error al registrar: $e', type: ToastType.error);
      }
    }
  }

  Future<void> _saveAsQuotation() async {
    if (_cartItems.isEmpty) return;

    final biz = ActiveBusinessScope.read(context);
    if (biz == null) return;

    if (_hasLoss && _isCashier) {
      AppToast.show(
        context,
        message: 'No se puede cotizar por debajo del costo.',
        type: ToastType.error,
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final q = await _salesRepo.recordQuotation(
        businessId: biz.id,
        items: _cartItems,
        customerName: _customerController.text.trim().isNotEmpty ? _customerController.text.trim() : null,
        discountAmount: _calculatedDiscount,
      );

      if (mounted) {
        final nav = Navigator.of(context);
        nav.pop(false);

        AppToast.show(
          context,
          message: 'Cotización ${q.quotationNumber} guardada',
          type: ToastType.success,
        );

        QuotationsListModal.show(context, businessId: biz.id);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        AppToast.show(context, message: 'Error al cotizar: $e', type: ToastType.error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = context.colors.surface;
    final borderColor = context.colors.line;
    final cardBg = context.colors.surfaceMuted;
    final textMain = context.colors.ink;
    final textMuted = context.colors.inkMuted;

    final totalItemsCount = _cartItems.fold(0, (sum, i) => sum + i.quantity);

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.90,
      ),
      padding: EdgeInsets.fromLTRB(
        22,
        18,
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
            // Barra superior
            if (!widget.isDialog)
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: context.colors.lineStrong,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

            // Cabecera Principal POS
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: context.colors.accent.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.point_of_sale_rounded, color: context.colors.accent, size: 18),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _cartItems.length > 1 ? 'Carrito' : 'Nueva venta',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            letterSpacing: -0.3,
                            color: textMain,
                          ),
                        ),
                        Text(
                          _cartItems.isEmpty
                              ? 'Selecciona productos para comenzar'
                              : '$totalItemsCount unid. (${_cartItems.length} productos en cuenta)',
                          style: TextStyle(fontSize: 11, color: textMuted),
                        ),
                      ],
                    ),
                  ],
                ),
                Row(
                  children: [
                    IconButton(
                      icon: Icon(Icons.qr_code_scanner, color: context.colors.accent, size: 22),
                      tooltip: 'Escanear producto con cámara',
                      onPressed: _scanBarcodeToAdd,
                    ),
                    IconButton(
                      icon: Icon(Icons.close, color: textMuted),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Selector / Buscador de Productos si está desplegado
            if (_showProductPicker) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: borderColor),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Agregar producto',
                          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: textMain),
                        ),
                        if (_cartItems.isNotEmpty)
                          TextButton(
                            onPressed: () => setState(() => _showProductPicker = false),
                            child: const Text('Cerrar buscador', style: TextStyle(fontSize: 11)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _searchProductController,
                      autofocus: _cartItems.isEmpty,
                      onChanged: _searchProducts,
                      decoration: InputDecoration(
                        hintText: 'Nombre o código',
                        prefixIcon: const Icon(Icons.search, size: 18),
                        suffixIcon: _searchProductController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 16),
                                onPressed: () {
                                  _searchProductController.clear();
                                  _loadInitialProducts();
                                },
                              )
                            : null,
                      ),
                    ),
                    const SizedBox(height: 8),

                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 180),
                      child: _isSearchingProducts
                          ? const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator(strokeWidth: 2)))
                          : _availableProducts.isEmpty
                              ? Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Text('No hay productos disponibles', style: TextStyle(fontSize: 12, color: textMuted)),
                                  ),
                                )
                              : ListView.separated(
                                  shrinkWrap: true,
                                  itemCount: _availableProducts.length,
                                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                                  itemBuilder: (context, idx) {
                                    final prod = _availableProducts[idx];
                                    return InkWell(
                                      onTap: () => _addProductToCart(prod),
                                      borderRadius: BorderRadius.circular(10),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: bgColor,
                                          borderRadius: BorderRadius.circular(10),
                                          border: Border.all(color: borderColor),
                                        ),
                                        child: Row(
                                          children: [
                                            ProductImageView(imagePath: prod.photoPath, width: 32, height: 32, borderRadius: BorderRadius.circular(6)),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(prod.name, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: textMain), maxLines: 1),
                                                  Text('Stock: ${prod.stock} • ${CurrencyFormatter.formatCOP(prod.salePrice)}', style: TextStyle(fontSize: 11, color: textMuted)),
                                                ],
                                              ),
                                            ),
                                            Icon(Icons.add_circle, color: context.colors.accent, size: 18),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],

            // Lista de Ítems en el Carrito
            if (_cartItems.isNotEmpty) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'PRODUCTOS EN LA CUENTA (${_cartItems.length})',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.5, color: textMuted),
                  ),
                  if (!_showProductPicker)
                    InkWell(
                      onTap: () => setState(() => _showProductPicker = true),
                      child: Row(
                        children: [
                          Icon(Icons.add, size: 15, color: context.colors.accent),
                          const SizedBox(width: 4),
                          Text(
                            'Agregar producto',
                            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: context.colors.accent),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),

              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _cartItems.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, idx) {
                  final item = _cartItems[idx];
                  final p = item.product;

                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: borderColor),
                    ),
                    child: Row(
                      children: [
                        ProductImageView(imagePath: p.photoPath, width: 40, height: 40, borderRadius: BorderRadius.circular(8)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.displayName,
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: textMain),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                '${CurrencyFormatter.formatCOP(item.unitPrice)} c/u • Stock: ${item.availableStock}',
                                style: TextStyle(fontSize: 11, color: textMuted),
                              ),
                            ],
                          ),
                        ),

                        // Controles de Cantidad
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.remove_circle_outline, size: 18),
                              onPressed: () => _decrementItem(idx),
                              color: textMuted,
                            ),
                            Container(
                              constraints: const BoxConstraints(minWidth: 26),
                              alignment: Alignment.center,
                              child: Text(
                                '${item.quantity}',
                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: textMain),
                              ),
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.add_circle, size: 18),
                              onPressed: () => _incrementItem(idx),
                              color: context.colors.accent,
                            ),
                          ],
                        ),

                        // Subtotal de la fila
                        SizedBox(
                          width: 70,
                          child: Text(
                            CurrencyFormatter.formatCOP(item.subtotal),
                            textAlign: TextAlign.right,
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: textMain),
                          ),
                        ),

                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: Icon(Icons.delete_outline, size: 16, color: context.colors.danger),
                          onPressed: () => _removeItem(idx),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),

              // Botón Descuento Mayorista / Por Volumen
              InkWell(
                onTap: () => setState(() => _showDiscountBar = !_showDiscountBar),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: _calculatedDiscount > 0
                        ? context.colors.accent.withOpacity(0.12)
                        : (isDark ? const Color(0xFF1E1B4B).withOpacity(0.4) : context.colors.surfaceMuted),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _calculatedDiscount > 0
                          ? context.colors.accent.withOpacity(0.4)
                          : borderColor,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.local_offer_outlined,
                            size: 16,
                            color: _calculatedDiscount > 0 ? context.colors.accent : context.colors.accent,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _calculatedDiscount > 0
                                ? 'Descuento Aplicado: -${CurrencyFormatter.formatCOP(_calculatedDiscount)}'
                                : '¿Aplicar un descuento?',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _calculatedDiscount > 0 ? context.colors.accent : textMain,
                            ),
                          ),
                        ],
                      ),
                      Icon(
                        _showDiscountBar ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                        size: 18,
                        color: textMuted,
                      ),
                    ],
                  ),
                ),
              ),

              // Panel Desplegable de Descuento
              if (_showDiscountBar) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: borderColor),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Descuento rápido',
                        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: textMuted),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          _buildDiscountChip('0%', 0),
                          _buildDiscountChip('5%', 5),
                          _buildDiscountChip('10%', 10),
                          _buildDiscountChip('15%', 15),
                          _buildDiscountChip('20%', 20),
                          if (_maxSafeDiscount > 0 && _maxSafePercent < 100)
                            ActionChip(
                              avatar: Icon(Icons.shield_outlined, size: 14, color: context.colors.accent),
                              label: Text(
                                '💡 Máx. sin pérdida (-${_maxSafePercent.toStringAsFixed(0)}%)',
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: context.colors.accent),
                              ),
                              backgroundColor: context.colors.accent.withOpacity(0.12),
                              side: BorderSide(color: context.colors.accent, width: 0.8),
                              onPressed: _applyMaxSafeDiscount,
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _discountController,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                labelText: _isDiscountPercentMode ? 'Porcentaje (%)' : 'Monto Fijo (\$)',
                                isDense: true,
                                suffixIcon: _discountController.text.isNotEmpty
                                    ? IconButton(
                                        icon: const Icon(Icons.clear, size: 14),
                                        onPressed: () {
                                          _discountController.clear();
                                          _applyQuickPercent(0);
                                        },
                                      )
                                    : null,
                              ),
                              onChanged: (val) {
                                final parsed = double.tryParse(val) ?? 0.0;
                                setState(() {
                                  if (_isDiscountPercentMode) {
                                    _discountPercent = parsed.clamp(0.0, 100.0);
                                  } else {
                                    _discountFixedAmount = parsed.clamp(0.0, _subtotalAmount);
                                  }
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          ActionChip(
                            label: Text(_isDiscountPercentMode ? 'Usar \$ Monto' : 'Usar % Porcentaje', style: const TextStyle(fontSize: 11)),
                            onPressed: () {
                              setState(() {
                                _isDiscountPercentMode = !_isDiscountPercentMode;
                                _discountController.clear();
                                _discountPercent = 0.0;
                                _discountFixedAmount = 0.0;
                              });
                            },
                          ),
                        ],
                      ),

                      // Feedback de Rentabilidad / Alerta de Pérdidas
                      if (_hasLoss) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: context.colors.danger.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: context.colors.danger.withOpacity(0.4)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.warning_amber_rounded, size: 18, color: context.colors.danger),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _isCashier
                                      ? 'Ese descuento deja pérdida: supera el margen del producto.'
                                      : '⚠️ ¡Venta a pérdida! Este descuento excede el costo de compra en ${CurrencyFormatter.formatCOP(_lossAmount)}.',
                                  style: TextStyle(fontSize: 11.5, color: context.colors.danger, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ] else if (_calculatedDiscount > 0) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: context.colors.accent.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: context.colors.accent.withOpacity(0.3)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.verified_outlined, size: 15, color: context.colors.accent),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  _isCashier
                                      ? 'Descuento dentro del margen.'
                                      : '🛡️ Margen seguro: Tu ganancia neta estimada será de ${CurrencyFormatter.formatCOP(_subtotalAmount - _calculatedDiscount - _totalCostAmount)}.',
                                  style: TextStyle(fontSize: 11, color: context.colors.accent, fontWeight: FontWeight.w500),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 14),

              // Resumen Financiero en Vivo
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E1B4B).withOpacity(0.3) : context.colors.successSoft,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: context.colors.accent.withOpacity(0.3)),
                ),
                child: Column(
                  children: [
                    if (_calculatedDiscount > 0) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Subtotal', style: TextStyle(fontSize: 12, color: textMuted)),
                          Text(CurrencyFormatter.formatCOP(_subtotalAmount), style: TextStyle(fontSize: 12, color: textMain)),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Descuento', style: TextStyle(fontSize: 12, color: context.colors.accent)),
                          Text('-${CurrencyFormatter.formatCOP(_calculatedDiscount)}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: context.colors.accent)),
                        ],
                      ),
                      const Divider(height: 12),
                    ],
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Total', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: textMain)),
                        Text(
                          CurrencyFormatter.formatCOP(_totalToPay),
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: context.colors.accent),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Método de Pago
              Text('Método de pago', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: textMain)),
              const SizedBox(height: 8),

              Row(
                children: [
                  _buildPaymentChip('EFECTIVO', Icons.payments_outlined, 'Efectivo', isDark, cardBg, borderColor),
                  const SizedBox(width: 8),
                  _buildPaymentChip('TRANSFERENCIA', Icons.account_balance_outlined, 'Transferencia', isDark, cardBg, borderColor),
                  const SizedBox(width: 8),
                  _buildPaymentChip('FIADO', Icons.assignment_outlined, 'Fiado', isDark, cardBg, borderColor),
                ],
              ),

              // Nombre de Cliente
              const SizedBox(height: 12),
              TextField(
                controller: _customerController,
                decoration: InputDecoration(
                  labelText: _paymentMethod == 'FIADO' ? 'Cliente del fiado' : 'Cliente (opcional)',
                  hintText: 'Juan Pérez',
                  prefixIcon: const Icon(Icons.person_outline, size: 18),
                  isDense: true,
                ),
              ),
              if (_existingCustomers.isNotEmpty) ...[
                const SizedBox(height: 6),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _existingCustomers.take(5).map((c) {
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ActionChip(
                          label: Text(c.name, style: const TextStyle(fontSize: 10.5)),
                          avatar: const Icon(Icons.person, size: 12),
                          onPressed: () => _customerController.text = c.name,
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
              const SizedBox(height: 20),

              // Botones de Acción: Cotizar vs Cobrar
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: context.colors.accent,
                        side: BorderSide(color: context.colors.accent, width: 1.2),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: _isLoading ? null : _saveAsQuotation,
                      icon: const Icon(Icons.description_outlined, size: 17),
                      label: const Text('Cotizar', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 3,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: context.colors.accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 1,
                      ),
                      onPressed: _isLoading ? null : _submitSale,
                      icon: _isLoading
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Icon(Icons.check_circle_outline, size: 18),
                      label: Text(
                        _isLoading ? 'Guardando…' : 'Cobrar ${CurrencyFormatter.formatCOP(_totalToPay)}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDiscountChip(String label, double percent) {
    final isSelected = _isDiscountPercentMode && _discountPercent == percent;
    return ChoiceChip(
      label: Text(label, style: TextStyle(fontSize: 11, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
      selected: isSelected,
      selectedColor: context.colors.accent.withOpacity(0.2),
      onSelected: (_) => _applyQuickPercent(percent),
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
          padding: const EdgeInsets.symmetric(vertical: 9),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected ? context.colors.accent : cardBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? context.colors.accent : borderColor,
              width: isSelected ? 1.4 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 13,
                color: isSelected ? Colors.white : (context.colors.inkMuted),
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  color: isSelected ? Colors.white : (context.colors.ink),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
