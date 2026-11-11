import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/design/color_swatch_dot.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../data/product_repository.dart';
import '../../models/product.dart';
import '../../models/product_variant.dart';
import '../widgets/barcode_modal.dart';
import '../widgets/product_image_view.dart';
import '../widgets/stock_status_badge.dart';
import 'product_form_screen.dart';
import '../../../auth/data/auth_repository.dart';
import '../../../sales/presentation/widgets/quick_sale_dialog.dart';
import '../../../team/data/team_repository.dart';
import '../../../suppliers/data/supplier_repository.dart';
import '../../../suppliers/models/purchase.dart';

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
    // La lista no trae las variantes: se cargan aquí para ver tallas y colores
    _refreshProduct();
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

  bool get _withVariants => _product.hasVariants && _product.variants.isNotEmpty;

  /// Último costo con cada proveedor, sacado de las entradas de mercancía
  List<SupplierCost> _supplierCosts = const [];

  Future<void> _refreshProduct() async {
    try {
      final updated = await _repository.getProductById(_product.id, _product.businessId);
      if (updated != null && mounted) setState(() => _product = updated);
      final costs = await SupplierRepository.instance.latestCosts(_product.businessId);
      if (mounted) setState(() => _supplierCosts = costs[_product.id] ?? const []);
    } catch (e) {
      debugPrint('No se pudo recargar el producto: $e');
    }
  }

  Future<void> _sell() async {
    final sold = await QuickSaleDialog.show(context, _product);
    if (sold == true) _refreshProduct();
  }

  Future<void> _showAdjustStockDialog() async {
    final c = context.colors;
    final variants = _product.variants;
    final totalController = TextEditingController(text: _product.stock.toString());
    final variantControllers = {
      for (final v in variants) v.id: TextEditingController(text: v.stock.toString()),
    };
    final reasonController = TextEditingController();

    int? parse(TextEditingController t) {
      final n = int.tryParse(t.text.trim());
      return n != null && n >= 0 ? n : null;
    }

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final valid = _withVariants
              ? variantControllers.values.every((t) => parse(t) != null)
              : parse(totalController) != null;
          final newTotal = _withVariants
              ? variantControllers.values.fold<int>(0, (s, t) => s + (parse(t) ?? 0))
              : (parse(totalController) ?? 0);
          return AlertDialog(
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(AppSpace.sm),
                  decoration: BoxDecoration(
                    color: c.successSoft,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.inventory_2_rounded, color: c.success, size: 20),
                ),
                const SizedBox(width: AppSpace.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Ajustar stock', style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.bold)),
                      Text(
                        _product.name,
                        style: TextStyle(fontSize: 12, color: c.inkMuted, fontWeight: FontWeight.normal),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 380,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _withVariants
                          ? 'Escribe cuántas unidades hay de cada talla y color. El total se calcula solo.'
                          : 'Indica la nueva cantidad física disponible y el motivo:',
                      style: TextStyle(fontSize: 12.5, color: c.inkMuted),
                    ),
                    const SizedBox(height: 14),
                    if (_withVariants) ...[
                      for (final v in variants)
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpace.sm),
                          child: Row(
                            children: [
                              if (ColorSwatchDot.hasSwatch(v.colorHex)) ...[
                                ColorSwatchDot(hex: v.colorHex, hex2: v.colorHex2, size: 18),
                                const SizedBox(width: AppSpace.sm),
                              ],
                              Expanded(
                                child: Text(
                                  v.label.isEmpty ? 'Sin nombre' : v.label,
                                  style: TextStyle(fontSize: 13.5, color: c.ink, fontWeight: FontWeight.w600),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              SizedBox(
                                width: 90,
                                child: TextField(
                                  controller: variantControllers[v.id],
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                  textAlign: TextAlign.center,
                                  onChanged: (_) => setLocal(() {}),
                                  decoration: const InputDecoration(
                                    isDense: true,
                                    suffixText: 'u.',
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      Container(
                        margin: const EdgeInsets.only(top: AppSpace.xs, bottom: AppSpace.md),
                        padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: 10),
                        decoration: BoxDecoration(
                          color: c.surfaceMuted,
                          borderRadius: BorderRadius.circular(AppRadius.control),
                        ),
                        child: Row(
                          children: [
                            Text('Nuevo total', style: TextStyle(color: c.inkMuted, fontSize: 13)),
                            const Spacer(),
                            Text(
                              '$newTotal unidades',
                              style: TextStyle(color: c.ink, fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                          ],
                        ),
                      ),
                    ] else ...[
                      TextField(
                        controller: totalController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        autofocus: true,
                        onChanged: (_) => setLocal(() {}),
                        decoration: const InputDecoration(
                          labelText: 'Nuevo stock total',
                          prefixIcon: Icon(Icons.pin_outlined),
                        ),
                      ),
                      const SizedBox(height: AppSpace.md),
                    ],
                    TextField(
                      controller: reasonController,
                      decoration: const InputDecoration(
                        labelText: 'Motivo del ajuste',
                        hintText: 'Ej. Conteo físico, merma, compra...',
                        prefixIcon: Icon(Icons.comment_outlined),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: valid ? () => Navigator.pop(ctx, true) : null,
                child: const Text('Guardar'),
              ),
            ],
          );
        },
      ),
    );

    if (result == true) {
      final reason = reasonController.text.trim().isEmpty ? 'Ajuste manual de stock' : reasonController.text.trim();
      if (_withVariants) {
        await _repository.adjustVariantStocks(
          _product,
          {for (final e in variantControllers.entries) e.key: parse(e.value) ?? 0},
          reason,
        );
      } else {
        await _repository.adjustStock(_product.id, _product.businessId, parse(totalController)!, reason);
      }
      await _refreshProduct();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Stock actualizado correctamente')),
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
            style: TextButton.styleFrom(foregroundColor: ctx.colors.danger),
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
    final c = context.colors;
    final isWide = MediaQuery.of(context).size.width >= 780;
    final hasDescription = _product.description != null && _product.description!.isNotEmpty;
    final showValuation = canViewCosts && _product.stock > 0;

    final rightColumn = <Widget>[
      _buildHeaderBlock(),
      const SizedBox(height: 14),
      _buildStockCard(),
      if (_withVariants) ...[
        const SizedBox(height: 14),
        _buildVariantsCard(),
      ],
      const SizedBox(height: 14),
      _buildPricingCard(),
      if (canViewCosts && _supplierCosts.isNotEmpty) ...[
        const SizedBox(height: 14),
        _buildSupplierCostsCard(),
      ],
      if (showValuation) ...[
        const SizedBox(height: 14),
        _buildValuationCard(),
      ],
    ];

    return Scaffold(
      backgroundColor: c.paper,
      appBar: AppBar(
        title: const Text('Detalle de producto'),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_2),
            tooltip: 'Código de barras / QR',
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
                if (updated == true) _refreshProduct();
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
              AppSpace.lg,
              AppSpace.lg,
              AppSpace.lg,
              MediaQuery.of(context).padding.bottom + 28,
            ),
            child: isWide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 340,
                        child: Column(
                          children: [
                            _buildPhotoCard(),
                            const SizedBox(height: 14),
                            _buildBarcodeCard(),
                            const SizedBox(height: 14),
                            _buildQuickActionsCard(),
                          ],
                        ),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ...rightColumn,
                            if (hasDescription) ...[
                              const SizedBox(height: 14),
                              _buildDescriptionCard(),
                            ],
                          ],
                        ),
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildPhotoCard(),
                      const SizedBox(height: 14),
                      ...rightColumn,
                      const SizedBox(height: 14),
                      _buildBarcodeCard(),
                      if (hasDescription) ...[
                        const SizedBox(height: 14),
                        _buildDescriptionCard(),
                      ],
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  /// Tarjeta base del diseño: superficie con borde fino
  Widget _card({required Widget child, EdgeInsets padding = const EdgeInsets.all(18), Color? color}) {
    final c = context.colors;
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? c.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: c.line),
      ),
      child: child,
    );
  }

  Widget _row(String label, String value, {Color? valueColor, bool bold = false}) {
    final c = context.colors;
    return Row(
      children: [
        Expanded(child: Text(label, style: TextStyle(fontSize: 12.5, color: c.inkMuted))),
        const SizedBox(width: AppSpace.sm),
        Text(
          value,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: bold ? FontWeight.bold : FontWeight.w600,
            color: valueColor ?? c.ink,
          ),
        ),
      ],
    );
  }

  Widget _buildPhotoCard() {
    return _card(
      padding: const EdgeInsets.all(AppSpace.sm),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.control),
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

  Widget _buildBarcodeCard() {
    final c = context.colors;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => BarcodeModal.show(context, _product),
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: _card(
          color: Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: AppSpace.md),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpace.sm),
                decoration: BoxDecoration(
                  color: c.surfaceMuted,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.qr_code_rounded, size: 22, color: c.accent),
              ),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Código / SKU', style: TextStyle(fontSize: 11, color: c.inkMuted)),
                    const SizedBox(height: 2),
                    Text(
                      _product.code,
                      style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: c.ink),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: 20, color: c.inkFaint),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickActionsCard() {
    return _card(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _sell,
              icon: const Icon(Icons.add_shopping_cart_rounded, size: 18),
              label: const Text('Registrar venta'),
            ),
          ),
          if (canEdit) ...[
            const SizedBox(height: AppSpace.sm),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _showAdjustStockDialog,
                icon: const Icon(Icons.tune_rounded, size: 17),
                label: const Text('Ajustar stock físico'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHeaderBlock() {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: c.surfaceMuted,
                borderRadius: BorderRadius.circular(AppRadius.pill),
                border: Border.all(color: c.line),
              ),
              child: Text(
                _product.category,
                style: TextStyle(color: c.inkMuted, fontWeight: FontWeight.w600, fontSize: 11.5),
              ),
            ),
            StockStatusBadge(product: _product),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          _product.name,
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: c.ink, height: 1.25),
        ),
      ],
    );
  }

  Widget _buildStockCard() {
    final c = context.colors;
    final variants = _product.variants;
    final outOfStock = variants.where((v) => v.stock <= 0).length;
    return _card(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Inventario disponible', style: TextStyle(fontSize: 12, color: c.inkMuted)),
                const SizedBox(height: 6),
                Text(
                  '${_product.stock} ${_product.stock == 1 ? 'unidad' : 'unidades'}',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: c.ink),
                ),
                const SizedBox(height: AppSpace.xs),
                Text(
                  _withVariants
                      ? 'Suma de ${variants.length} ${variants.length == 1 ? 'variante' : 'variantes'}'
                          '${outOfStock > 0 ? ' · $outOfStock agotada${outOfStock == 1 ? '' : 's'}' : ''}'
                      : 'Alerta mínima: ${_product.minStock} unid.',
                  style: TextStyle(fontSize: 11.5, color: c.inkMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpace.md),
          FilledButton.icon(
            onPressed: _sell,
            icon: const Icon(Icons.shopping_bag_outlined, size: 17),
            label: const Text('Vender'),
          ),
        ],
      ),
    );
  }

  /// Tallas y colores, agrupados por talla, con la cantidad de cada uno
  Widget _buildVariantsCard() {
    final c = context.colors;
    final groups = <String, List<ProductVariant>>{};
    for (final v in _product.variants) {
      groups.putIfAbsent(v.attributeValue.trim(), () => []).add(v);
    }
    final firstName = _product.variants.first.attributeName.trim();
    final plural = switch (firstName.toLowerCase()) {
      '' || 'talla' => 'Tallas',
      'presentación' => 'Presentaciones',
      _ => firstName,
    };
    final title = _product.variants.any((v) => v.hasSecondAttribute) ? '$plural y colores' : plural;

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: c.ink)),
              ),
              if (canEdit)
                TextButton.icon(
                  onPressed: _showAdjustStockDialog,
                  icon: const Icon(Icons.tune_rounded, size: 16),
                  label: const Text('Ajustar'),
                ),
            ],
          ),
          const SizedBox(height: AppSpace.sm),
          for (final entry in groups.entries) ...[
            if (entry.key.isNotEmpty && entry.value.any((v) => v.hasSecondAttribute))
              Padding(
                padding: const EdgeInsets.only(top: AppSpace.sm, bottom: 6),
                child: Text(
                  '${firstName.isEmpty ? 'Talla' : firstName} ${entry.key} · '
                  '${entry.value.fold<int>(0, (s, v) => s + v.stock)} u.',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.inkMuted),
                ),
              ),
            Wrap(
              spacing: AppSpace.sm,
              runSpacing: AppSpace.sm,
              children: [
                for (final v in entry.value) _variantChip(v, showFirst: !v.hasSecondAttribute || entry.key.isEmpty),
              ],
            ),
            const SizedBox(height: AppSpace.xs),
          ],
        ],
      ),
    );
  }

  Widget _variantChip(ProductVariant v, {required bool showFirst}) {
    final c = context.colors;
    final out = v.stock <= 0;
    final name = showFirst ? v.label : (v.attribute2Value ?? '').trim();
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
      decoration: BoxDecoration(
        color: out ? c.dangerSoft : c.surfaceMuted,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: out ? c.danger.withValues(alpha: 0.3) : c.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (ColorSwatchDot.hasSwatch(v.colorHex)) ...[
            ColorSwatchDot(hex: v.colorHex, hex2: v.colorHex2, size: 16),
            const SizedBox(width: 6),
          ],
          Text(
            name.isEmpty ? 'Sin nombre' : name,
            style: TextStyle(fontSize: 12.5, color: c.ink, fontWeight: FontWeight.w500),
          ),
          const SizedBox(width: AppSpace.sm),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: out ? c.danger : c.surface,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: Text(
              out ? 'Agotado' : '${v.stock}',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.bold,
                color: out ? Colors.white : c.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPricingCard() {
    final c = context.colors;
    return _card(
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Precio de venta', style: TextStyle(fontSize: 13, color: c.inkMuted)),
              ),
              Text(
                CurrencyFormatter.format(_product.salePrice),
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: c.ink),
              ),
            ],
          ),
          if (canViewCosts) ...[
            Divider(height: 24, color: c.line),
            _row('Costo de compra', CurrencyFormatter.format(_product.purchasePrice)),
            const SizedBox(height: 10),
            _row(
              'Ganancia por unidad',
              '${CurrencyFormatter.format(_product.profit)} (${_product.profitMarginLabel(decimals: 1)})',
              valueColor: _product.profit >= 0 ? c.success : c.danger,
              bold: true,
            ),
            if (_product.sellsBelowCost) ...[
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'Por debajo del costo: cada venta deja pérdida',
                  style: TextStyle(fontSize: 11.5, color: c.danger),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  /// Lo que cobra cada proveedor por este producto (última compra), el más barato arriba
  Widget _buildSupplierCostsCard() {
    final c = context.colors;
    const months = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Costo por proveedor', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: c.ink)),
          Text('Según tus últimas entradas de mercancía', style: TextStyle(fontSize: 12, color: c.inkMuted)),
          const SizedBox(height: AppSpace.md),
          for (final (i, s) in _supplierCosts.indexed)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.supplierName, style: TextStyle(color: c.ink, fontWeight: FontWeight.w600, fontSize: 13)),
                        Text(
                          '${s.date.day} ${months[s.date.month - 1]} ${s.date.year}'
                          '${s.change == null || s.change == 0 ? '' : (s.change! > 0 ? ' · subió ${CurrencyFormatter.format(s.change!)}' : ' · bajó ${CurrencyFormatter.format(-s.change!)}')}',
                          style: TextStyle(color: (s.change ?? 0) > 0 ? c.warning : c.inkMuted, fontSize: 11.5),
                        ),
                      ],
                    ),
                  ),
                  if (i == 0 && _supplierCosts.length > 1)
                    Container(
                      margin: const EdgeInsets.only(right: AppSpace.sm),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: c.successSoft, borderRadius: BorderRadius.circular(AppRadius.pill)),
                      child: Text('Más barato', style: TextStyle(color: c.success, fontSize: 11, fontWeight: FontWeight.w600)),
                    ),
                  Text(CurrencyFormatter.format(s.unitCost), style: TextStyle(color: c.ink, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildValuationCard() {
    final c = context.colors;
    final totalCost = _product.purchasePrice * _product.stock;
    final totalSale = _product.salePrice * _product.stock;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Valor del inventario',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: c.ink),
          ),
          const SizedBox(height: AppSpace.md),
          _row('Invertido en stock', CurrencyFormatter.format(totalCost)),
          const SizedBox(height: AppSpace.sm),
          _row('Venta total estimada', CurrencyFormatter.format(totalSale)),
          const SizedBox(height: AppSpace.sm),
          _row('Ganancia proyectada', CurrencyFormatter.format(totalSale - totalCost),
              valueColor: c.success, bold: true),
        ],
      ),
    );
  }

  Widget _buildDescriptionCard() {
    final c = context.colors;
    return _card(
      padding: const EdgeInsets.all(AppSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Descripción / notas',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: c.inkMuted),
          ),
          const SizedBox(height: 6),
          Text(_product.description!, style: TextStyle(color: c.ink, fontSize: 13, height: 1.4)),
        ],
      ),
    );
  }
}
