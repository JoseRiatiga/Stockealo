import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/design/color_swatch_dot.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../business/models/business.dart';
import '../../../auth/data/auth_repository.dart';
import '../../../suppliers/data/supplier_repository.dart';
import '../../../suppliers/data/supplier_whatsapp.dart';
import '../../../suppliers/models/supplier_order.dart';
import '../../../suppliers/models/supplier.dart';
import '../../../suppliers/presentation/widgets/supplier_picker.dart';
import '../../data/product_repository.dart';
import '../../models/product.dart';
import '../../models/product_variant.dart';
import 'product_image_view.dart';
import '../../../../core/design/app_dialog.dart';

/// Un producto del pedido: cantidad total o, si tiene tallas y colores, una por cada una
class RestockOrderItem {
  final Product product;
  int orderQty;
  final Map<String, int> variantQty;
  bool isSelected;

  RestockOrderItem({
    required this.product,
    this.orderQty = 0,
    Map<String, int>? variantQty,
    this.isSelected = true,
  }) : variantQty = variantQty ?? {};

  bool get withVariants => product.hasVariants && product.variants.isNotEmpty;

  int get totalQty => withVariants ? variantQty.values.fold(0, (s, q) => s + q) : orderQty;

  /// "M · Rojo: 2 / L · Azul: 1"
  String get variantSummary => [
        for (final v in product.variants)
          if ((variantQty[v.id] ?? 0) > 0) '${v.label.isEmpty ? 'Sin nombre' : v.label}: ${variantQty[v.id]}',
      ].join(' / ');

  /// Renglones para guardar el pedido (uno por talla y color)
  List<SupplierOrderItem> get orderItems => withVariants
      ? [
          for (final v in product.variants)
            if ((variantQty[v.id] ?? 0) > 0)
              SupplierOrderItem(
                productId: product.id,
                productName: product.name,
                variantId: v.id,
                variantName: v.label,
                quantity: variantQty[v.id]!,
              ),
        ]
      : [if (orderQty > 0) SupplierOrderItem(productId: product.id, productName: product.name, quantity: orderQty)];

  /// Sugerencia: reponer hasta el doble del mínimo. Con tallas y colores, ese
  /// objetivo se reparte entre las variantes y se pide lo que le falta a cada una.
  static RestockOrderItem suggested(Product p) {
    if (p.hasVariants && p.variants.isNotEmpty) {
      final target = ((p.minStock * 2) / p.variants.length).ceil().clamp(2, 9999);
      final qty = {for (final v in p.variants) v.id: (target - v.stock).clamp(0, 9999)};
      if (qty.values.every((q) => q == 0)) {
        for (final v in p.variants) {
          if (v.stock <= 0) qty[v.id] = 1;
        }
      }
      return RestockOrderItem(product: p, variantQty: qty);
    }
    final qty = p.minStock > 0 ? (p.minStock * 2 - p.stock).clamp(1, 9999) : (p.stock <= 0 ? 10 : 5);
    return RestockOrderItem(product: p, orderQty: qty);
  }

  /// Hace falta pedir: el producto está bajo o alguna talla/color se agotó
  static bool needsRestock(Product p) =>
      p.isLowStock || p.isOutOfStock || (p.hasVariants && p.variants.any((v) => v.stock <= 0));
}

/// Texto del pedido para WhatsApp, con tallas y colores por producto
String buildRestockOrderText({
  required String businessName,
  required List<RestockOrderItem> items,
  String? sender,
  Supplier? supplier,
  DateTime? now,
}) {
  final selected = items.where((i) => i.isSelected && i.totalQty > 0).toList();
  final date = DateFormat('dd/MM/yyyy hh:mm a').format(now ?? DateTime.now());
  var units = 0;
  var cost = 0.0;
  final b = StringBuffer()
    ..writeln('*PEDIDO - ${businessName.toUpperCase()}*')
    ..writeln('Fecha: $date');
  if (supplier != null) b.writeln('Para: ${supplier.contactName?.isNotEmpty == true ? '${supplier.contactName} (${supplier.name})' : supplier.name}');
  if ((sender ?? '').isNotEmpty) b.writeln('Pide: $sender');
  b
    ..writeln('────────────────')
    ..writeln('*PRODUCTOS:*');
  for (final i in selected) {
    final p = i.product;
    final code = p.code.isNotEmpty ? ' (Cód: ${p.code})' : '';
    if (i.withVariants) {
      b.writeln('• ${p.name}$code — ${i.variantSummary}');
    } else {
      b.writeln('• ${i.orderQty} × ${p.name}$code');
    }
    units += i.totalQty;
    if (p.purchasePrice > 0) cost += p.purchasePrice * i.totalQty;
  }
  b
    ..writeln('────────────────')
    ..writeln('Total: ${selected.length} ${selected.length == 1 ? 'producto' : 'productos'}, $units ${units == 1 ? 'unidad' : 'unidades'}');
  if (cost > 0) b.writeln('Costo estimado: ${CurrencyFormatter.format(cost)}');
  b
    ..writeln('')
    ..writeln('Por favor confirmar el pedido y la fecha de entrega. ¡Muchas gracias!');
  return b.toString();
}

class RestockOrderModal extends StatefulWidget {
  final Business business;
  final String? userName;
  final Supplier? supplier;

  const RestockOrderModal({super.key, required this.business, this.userName, this.supplier});

  static Future<void> show(
    BuildContext context, {
    required Business business,
    String? userName,
    Supplier? supplier,
  }) {
    return showModalBottomSheet(
      showDragHandle: false,
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => RestockOrderModal(business: business, userName: userName, supplier: supplier),
    );
  }

  @override
  State<RestockOrderModal> createState() => _RestockOrderModalState();
}

class _RestockOrderModalState extends State<RestockOrderModal> {
  final _productRepo = ProductRepository();
  final _searchController = TextEditingController();

  /// Sugeridos de todo el negocio; la lista visible se filtra por proveedor
  List<RestockOrderItem> _suggested = [];
  final List<RestockOrderItem> _manual = [];
  List<Product> _allProducts = [];
  bool _isLoading = true;
  String _searchFilter = '';
  late Supplier? _supplier = widget.supplier;

  /// Un solo pedido por ventana: si se reenvía, se actualiza el mismo
  final String _orderId = const Uuid().v4();
  bool _orderSaved = false;

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadProducts() async {
    setState(() => _isLoading = true);
    _allProducts = await _productRepo.searchProducts('', businessId: widget.business.id);
    final suggested = [
      for (final p in _allProducts)
        if (RestockOrderItem.needsRestock(p)) RestockOrderItem.suggested(p),
    ];
    if (mounted) {
      setState(() {
        _suggested = suggested;
        _isLoading = false;
      });
    }
  }

  /// Con proveedor elegido se ven sus productos (y los agregados a mano)
  List<RestockOrderItem> get _items => [
        ..._manual,
        for (final i in _suggested)
          if (_supplier == null || i.product.supplierId == _supplier!.id) i,
      ];

  Future<void> _pickSupplier() async {
    final s = await SupplierPicker.pick(context, businessId: widget.business.id);
    if (s != null && mounted) setState(() => _supplier = s);
  }

  void _showAddOtherProductSheet() {
    final c = context.colors;
    final inList = _items.map((i) => i.product.id).toSet();
    final available = _allProducts.where((p) => !inList.contains(p.id)).toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) {
        String query = '';
        return StatefulBuilder(
          builder: (context, setModalState) {
            final q = query.toLowerCase();
            final filtered =
                available.where((p) => p.name.toLowerCase().contains(q) || p.code.toLowerCase().contains(q)).toList();
            return SizedBox(
              height: MediaQuery.of(context).size.height * 0.7,
              child: Padding(
                padding: EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.lg, AppSpace.lg, MediaQuery.of(context).viewInsets.bottom),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Agregar producto', style: TextStyle(fontSize: AppText.sizeTitle, fontWeight: FontWeight.bold, color: c.ink)),
                    const SizedBox(height: AppSpace.md),
                    TextField(
                      autofocus: true,
                      decoration: const InputDecoration(hintText: 'Buscar por nombre o código', prefixIcon: Icon(Icons.search_outlined)),
                      onChanged: (val) => setModalState(() => query = val),
                    ),
                    const SizedBox(height: AppSpace.sm),
                    Expanded(
                      child: filtered.isEmpty
                          ? Center(child: Text('No se encontraron productos', style: TextStyle(color: c.inkMuted)))
                          : ListView.separated(
                              itemCount: filtered.length,
                              separatorBuilder: (_, __) => Divider(height: 1, color: c.line),
                              itemBuilder: (context, index) {
                                final p = filtered[index];
                                return ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: ProductImageView(
                                    imagePath: p.photoPath,
                                    width: 40,
                                    height: 40,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  title: Text(p.name, style: TextStyle(fontWeight: FontWeight.w600, color: c.ink)),
                                  subtitle: Text('Hay ${p.stock} · Cód: ${p.code}', style: TextStyle(color: c.inkMuted)),
                                  trailing: Icon(Icons.add_circle_outline_outlined, color: c.accent),
                                  onTap: () {
                                    final item = RestockOrderItem.suggested(p);
                                    setState(() => _manual.insert(0, item));
                                    Navigator.pop(ctx);
                                  },
                                );
                              },
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
  }

  Future<void> _editQuantity(RestockOrderItem item) async {
    final p = item.product;
    final controllers = item.withVariants
        ? {for (final v in p.variants) v.id: TextEditingController(text: '${item.variantQty[v.id] ?? 0}')}
        : {'': TextEditingController(text: '${item.orderQty}')};
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final c = ctx.colors;
        return AppDialog(
title: p.name,
content: SizedBox(
            width: 360,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.withVariants ? '¿Cuántas pides de cada talla y color?' : '¿Cuántas unidades pides?',
                    style: TextStyle(fontSize: AppText.sizeSmall, color: c.inkMuted),
                  ),
                  const SizedBox(height: AppSpace.md),
                  if (item.withVariants)
                    for (final v in p.variants)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpace.sm),
                        child: Row(
                          children: [
                            if (ColorSwatchDot.hasSwatch(v.colorHex)) ...[
                              ColorSwatchDot(hex: v.colorHex, hex2: v.colorHex2, size: 16),
                              const SizedBox(width: AppSpace.sm),
                            ],
                            Expanded(
                              child: Text('${v.label.isEmpty ? 'Sin nombre' : v.label}  ·  hay ${v.stock}',
                                  style: TextStyle(color: c.ink, fontSize: AppText.sizeSmall)),
                            ),
                            SizedBox(width: 80, child: _qtyField(controllers[v.id]!)),
                          ],
                        ),
                      )
                  else
                    _qtyField(controllers['']!, autofocus: true),
                ],
              ),
            ),
          ),
actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Aceptar')),
          ],
);
      },
    );
    if (ok == true) {
      setState(() {
        if (item.withVariants) {
          for (final e in controllers.entries) {
            item.variantQty[e.key] = int.tryParse(e.value.text.trim()) ?? 0;
          }
        } else {
          item.orderQty = int.tryParse(controllers['']!.text.trim()) ?? item.orderQty;
        }
      });
    }
    for (final c in controllers.values) {
      c.dispose();
    }
  }

  Widget _qtyField(TextEditingController controller, {bool autofocus = false}) => TextField(
        controller: controller,
        autofocus: autofocus,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        textAlign: TextAlign.center,
        decoration: const InputDecoration(isDense: true, suffixText: 'u.'),
      );

  String _buildOrderText() => buildRestockOrderText(
        businessName: widget.business.name,
        items: _items,
        sender: widget.userName,
        supplier: _supplier,
      );

  /// Queda guardado para compararlo con lo que llegue en la entrada de mercancía
  Future<void> _saveOrder() async {
    final items = [
      for (final i in _items)
        if (i.isSelected) ...i.orderItems,
    ];
    if (items.isEmpty) return;
    final first = !_orderSaved;
    _orderSaved = true;
    try {
      await SupplierRepository.instance.saveOrder(SupplierOrder(
        id: _orderId,
        businessId: widget.business.id,
        supplierId: _supplier?.id,
        supplierName: _supplier?.name,
        items: items,
        createdBy: AuthRepository.instance.currentUser?.email,
        createdAt: DateTime.now(),
      ));
      if (first && mounted) {
        AppToast.showInfo(context, 'Pedido guardado. Cuando llegue, regístralo en Entrada de mercancía para ver si faltó algo.');
      }
    } catch (e) {
      debugPrint('No se pudo guardar el pedido: $e');
    }
  }

  Future<void> _send() async {
    await _saveOrder();
    await SupplierWhatsApp.send(_supplier, _buildOrderText(), subject: 'Pedido - ${widget.business.name}');
  }

  void _copyOrderText() {
    Clipboard.setData(ClipboardData(text: _buildOrderText()));
    _saveOrder();
    AppToast.showSuccess(context, 'Pedido copiado.');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final items = _items;
    final selected = items.where((i) => i.isSelected && i.totalQty > 0).toList();
    final totalUnits = selected.fold(0, (s, i) => s + i.totalQty);
    final totalCost = selected.fold(0.0, (s, i) => s + i.product.purchasePrice * i.totalQty);
    final q = _searchFilter.toLowerCase();
    final filtered = items
        .where((i) => q.isEmpty || i.product.name.toLowerCase().contains(q) || i.product.code.toLowerCase().contains(q))
        .toList();
    final hasWhatsApp = SupplierWhatsApp.numberOf(_supplier) != null;

    return Container(
      height: MediaQuery.of(context).size.height * 0.92,
      decoration: BoxDecoration(
        color: c.paper,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(color: c.lineStrong, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: AppSpace.md),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: c.successSoft, borderRadius: BorderRadius.circular(AppRadius.control)),
                  child: Icon(Icons.local_shipping_outlined, color: c.success, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Pedido a proveedor', style: TextStyle(fontSize: AppText.sizeHeading, fontWeight: FontWeight.bold, color: c.ink)),
                      Text('Lo que se está acabando, por talla y color',
                          style: TextStyle(fontSize: AppText.sizeCaption, color: c.inkMuted)),
                    ],
                  ),
                ),
                IconButton(icon: const Icon(Icons.close_outlined), onPressed: () => Navigator.pop(context)),
              ],
            ),
          ),
          const SizedBox(height: AppSpace.md),
          // Proveedor
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Material(
              color: c.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.control),
                side: BorderSide(color: c.line),
              ),
              child: ListTile(
                dense: true,
                leading: Icon(Icons.storefront_outlined, color: c.inkMuted),
                title: Text(
                  _supplier == null ? 'Todos los proveedores' : _supplier!.name,
                  style: TextStyle(color: c.ink, fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  _supplier == null
                      ? 'Elige uno para ver solo sus productos y enviarle el pedido'
                      : (hasWhatsApp ? 'Se envía directo a su WhatsApp' : 'Sin WhatsApp: se comparte el pedido'),
                  style: TextStyle(color: c.inkMuted, fontSize: AppText.sizeCaption),
                ),
                trailing: _supplier == null
                    ? Text('Elegir', style: TextStyle(color: c.accent, fontWeight: FontWeight.w600))
                    : IconButton(
                        tooltip: 'Ver todos',
                        icon: const Icon(Icons.close_outlined, size: 18),
                        onPressed: () => setState(() => _supplier = null),
                      ),
                onTap: _pickSupplier,
              ),
            ),
          ),
          const SizedBox(height: AppSpace.md),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 42,
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Filtrar lista...',
                        prefixIcon: const Icon(Icons.search_outlined, size: 18),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear_outlined, size: 16),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _searchFilter = '');
                                },
                              )
                            : null,
                      ),
                      onChanged: (val) => setState(() => _searchFilter = val),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpace.sm),
                OutlinedButton.icon(
                  onPressed: _showAddOtherProductSheet,
                  icon: const Icon(Icons.add_outlined, size: 16),
                  label: const Text('Agregar'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${items.length} ${items.length == 1 ? 'producto' : 'productos'} para reponer',
                    style: TextStyle(fontSize: AppText.sizeCaption, fontWeight: FontWeight.w600, color: c.inkMuted),
                  ),
                ),
                TextButton(
                  onPressed: items.isEmpty
                      ? null
                      : () {
                          final all = items.every((i) => i.isSelected);
                          setState(() {
                            for (final i in items) {
                              i.isSelected = !all;
                            }
                          });
                        },
                  child: Text(items.isNotEmpty && items.every((i) => i.isSelected) ? 'Quitar todos' : 'Marcar todos'),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: c.line),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : items.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.check_circle_outline_outlined, size: 56, color: c.success),
                              const SizedBox(height: AppSpace.lg),
                              Text('Inventario en orden',
                                  style: TextStyle(fontSize: AppText.sizeTitle, fontWeight: FontWeight.bold, color: c.ink)),
                              const SizedBox(height: AppSpace.sm),
                              Text(
                                _supplier == null
                                    ? 'No hay productos agotados ni bajos de stock.'
                                    : 'No hay productos de ${_supplier!.name} por reponer.',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: AppText.sizeSmall, color: c.inkMuted),
                              ),
                              const SizedBox(height: 20),
                              FilledButton.tonalIcon(
                                onPressed: _showAddOtherProductSheet,
                                icon: const Icon(Icons.add_outlined),
                                label: const Text('Agregar productos'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: 10),
                        itemCount: filtered.length,
                        itemBuilder: (context, index) => _itemCard(filtered[index]),
                      ),
          ),
          Container(
            padding: EdgeInsets.fromLTRB(20, 14, 20, MediaQuery.of(context).padding.bottom + 16),
            decoration: BoxDecoration(color: c.surface, border: Border(top: BorderSide(color: c.line))),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${selected.length} ${selected.length == 1 ? 'producto' : 'productos'}',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: AppText.sizeSmall, color: c.ink)),
                          Text('$totalUnits unidades', style: TextStyle(fontSize: AppText.sizeCaption, color: c.inkMuted)),
                        ],
                      ),
                    ),
                    if (totalCost > 0)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('Costo estimado', style: TextStyle(fontSize: AppText.sizeCaption, color: c.inkMuted)),
                          Text(CurrencyFormatter.format(totalCost),
                              style: TextStyle(fontSize: AppText.sizeBodyLarge, fontWeight: FontWeight.bold, color: c.ink)),
                        ],
                      ),
                  ],
                ),
                const SizedBox(height: AppSpace.md),
                Row(
                  children: [
                    IconButton.filledTonal(
                      onPressed: selected.isEmpty ? null : _copyOrderText,
                      icon: const Icon(Icons.copy_outlined, size: 20),
                      tooltip: 'Copiar pedido',
                    ),
                    const SizedBox(width: AppSpace.sm),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: selected.isEmpty ? null : _send,
                        icon: Icon(hasWhatsApp ? Icons.send_outlined : Icons.share_outlined, size: 18),
                        label: Text(
                          hasWhatsApp ? 'Enviar a ${_supplier!.name}' : 'Compartir pedido',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _itemCard(RestockOrderItem item) {
    final c = context.colors;
    final p = item.product;
    final out = p.isOutOfStock;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: item.isSelected ? c.accent.withValues(alpha: 0.5) : c.line, width: item.isSelected ? 1.5 : 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Checkbox(
                  value: item.isSelected,
                  onChanged: (val) => setState(() => item.isSelected = val ?? false),
                ),
                ProductImageView(imagePath: p.photoPath, width: 42, height: 42, borderRadius: BorderRadius.circular(10)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.name, style: TextStyle(fontWeight: FontWeight.bold, fontSize: AppText.sizeBody, color: c.ink)),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: AppSpace.sm,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: out ? c.dangerSoft : c.warningSoft,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              out ? 'Agotado' : 'Hay ${p.stock} / mín. ${p.minStock}',
                              style: TextStyle(fontSize: AppText.sizeCaption, fontWeight: FontWeight.bold, color: out ? c.danger : c.warning),
                            ),
                          ),
                          if (p.purchasePrice > 0)
                            Text('Costo ${CurrencyFormatter.format(p.purchasePrice)}',
                                style: TextStyle(fontSize: AppText.sizeCaption, color: c.inkMuted)),
                        ],
                      ),
                    ],
                  ),
                ),
                if (!item.withVariants) ...[
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline_outlined, size: 22),
                    color: c.inkMuted,
                    onPressed: () {
                      if (item.orderQty > 1) setState(() => item.orderQty--);
                    },
                  ),
                  _qtyChip('${item.orderQty}', () => _editQuantity(item)),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline_outlined, size: 22),
                    color: c.accent,
                    onPressed: () => setState(() => item.orderQty++),
                  ),
                ] else
                  _qtyChip('${item.totalQty}', () => _editQuantity(item)),
              ],
            ),
            if (item.withVariants)
              Padding(
                padding: const EdgeInsets.only(left: 48, top: 6),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final v in p.variants)
                      if ((item.variantQty[v.id] ?? 0) > 0 || v.stock <= 0) _variantChip(v, item.variantQty[v.id] ?? 0, () => _editQuantity(item)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _qtyChip(String text, VoidCallback onTap) {
    final c = context.colors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: c.surfaceMuted, borderRadius: BorderRadius.circular(8)),
        child: Text(text, style: TextStyle(fontWeight: FontWeight.bold, fontSize: AppText.sizeBody, color: c.ink)),
      ),
    );
  }

  Widget _variantChip(ProductVariant v, int qty, VoidCallback onTap) {
    final c = context.colors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
        decoration: BoxDecoration(
          color: qty > 0 ? c.successSoft : c.surfaceMuted,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: c.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (ColorSwatchDot.hasSwatch(v.colorHex)) ...[
              ColorSwatchDot(hex: v.colorHex, hex2: v.colorHex2, size: 12),
              const SizedBox(width: 4),
            ],
            Text(
              '${v.label.isEmpty ? 'Sin nombre' : v.label}: $qty',
              style: TextStyle(fontSize: AppText.sizeCaption, color: c.ink, fontWeight: qty > 0 ? FontWeight.w600 : FontWeight.normal),
            ),
          ],
        ),
      ),
    );
  }
}
