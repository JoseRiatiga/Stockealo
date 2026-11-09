import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/utils/image_helper.dart';
import '../../../../core/widgets/image_source_picker_modal.dart';
import '../../../products/data/product_image_service.dart';
import '../../../products/presentation/screens/product_form_screen.dart';
import '../../data/invoice_photo_service.dart';

import '../../../../core/design/color_swatch_dot.dart';
import '../../../../core/design/content_width.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../auth/data/auth_repository.dart';
import '../../../business/models/business.dart';
import '../../../products/data/product_repository.dart';
import '../../../products/models/product.dart';
import '../../../products/presentation/screens/barcode_scanner_screen.dart';
import '../../../products/presentation/widgets/product_image_view.dart';
import '../../data/supplier_repository.dart';
import '../../models/purchase.dart';
import '../../models/supplier.dart';
import '../../models/supplier_order.dart';
import '../widgets/supplier_picker.dart';

/// Un producto en la entrada, con su cantidad (o una por talla y color) y su costo
class _Line {
  final Product product;
  final TextEditingController qty;
  final Map<String, TextEditingController> variantQty;
  final TextEditingController cost;
  bool updateCost = true;

  _Line(this.product,
      {int initialQty = 0, String? variantId, Map<String, int> initialVariantQty = const {}, double? cost})
      : qty = TextEditingController(text: initialQty > 0 && !product.hasVariants ? '$initialQty' : ''),
        variantQty = {
          for (final v in product.variants)
            v.id: TextEditingController(
              text: (initialVariantQty[v.id] ?? 0) > 0
                  ? '${initialVariantQty[v.id]}'
                  : (v.id == variantId && initialQty > 0 ? '$initialQty' : ''),
            ),
        },
        cost = TextEditingController(
          text: (cost ?? product.purchasePrice) > 0 ? (cost ?? product.purchasePrice).toStringAsFixed(0) : '',
        );

  Map<String, dynamic> toDraft() => {
        'product_id': product.id,
        'qty': _n(qty),
        'variants': {
          for (final e in variantQty.entries)
            if (_n(e.value) > 0) e.key: _n(e.value)
        },
        'cost': unitCost,
        'update_cost': updateCost,
      };

  bool get withVariants => product.hasVariants && product.variants.isNotEmpty;

  static int _n(TextEditingController c) => int.tryParse(c.text.trim()) ?? 0;

  int get units => withVariants ? variantQty.values.fold(0, (s, c) => s + _n(c)) : _n(qty);
  double get unitCost => double.tryParse(cost.text.trim()) ?? 0;
  bool get costChanged => unitCost > 0 && unitCost != product.purchasePrice;

  List<PurchaseItem> get items => withVariants
      ? [
          for (final v in product.variants)
            if (_n(variantQty[v.id]!) > 0)
              PurchaseItem(
                productId: product.id,
                productName: product.name,
                variantId: v.id,
                variantName: v.label,
                quantity: _n(variantQty[v.id]!),
                unitCost: unitCost,
              ),
        ]
      : [
          if (_n(qty) > 0)
            PurchaseItem(productId: product.id, productName: product.name, quantity: _n(qty), unitCost: unitCost),
        ];

  void addOne(String? variantId) {
    final c = variantId != null && variantQty.containsKey(variantId) ? variantQty[variantId]! : qty;
    c.text = '${_n(c) + 1}';
  }

  void dispose() {
    qty.dispose();
    cost.dispose();
    for (final c in variantQty.values) {
      c.dispose();
    }
  }
}

/// Entrada de mercancía: lo que llegó del proveedor suma al inventario (también
/// por talla y color) y queda registrado con su factura y forma de pago.
class PurchaseEntryScreen extends StatefulWidget {
  final Business business;
  final Supplier? supplier;

  /// Pedido que se está recibiendo (desde la lista de pedidos)
  final SupplierOrder? order;

  const PurchaseEntryScreen({super.key, required this.business, this.supplier, this.order});

  /// true si se registró la entrada
  static Future<bool?> open(BuildContext context,
          {required Business business, Supplier? supplier, SupplierOrder? order}) =>
      Navigator.of(context).push<bool>(MaterialPageRoute(
        builder: (_) => PurchaseEntryScreen(business: business, supplier: supplier, order: order),
      ));

  @override
  State<PurchaseEntryScreen> createState() => _PurchaseEntryScreenState();
}

class _PurchaseEntryScreenState extends State<PurchaseEntryScreen> {
  final _products = ProductRepository();
  final _invoice = TextEditingController();
  final _notes = TextEditingController();
  final List<_Line> _lines = [];

  late Supplier? _supplier = widget.supplier;
  DateTime _date = DateTime.now();
  late bool _credit = widget.supplier?.isCredit ?? false;
  DateTime? _dueDate;
  bool _saving = false;

  /// Ya se decidió salir (borrador o descartar): deja cerrar la pantalla
  bool _leaving = false;

  /// Id fijo desde que se abre: la foto de la factura se guarda con él
  final String _purchaseId = const Uuid().v4();
  ({Uint8List bytes, String? mimeType})? _photo;
  DateTime? _draftFrom;

  /// Pedido que llega con esta entrada y los que están por recibir
  SupplierOrder? _order;
  List<SupplierOrder> _pendingOrders = [];

  /// Último costo de cada producto con cada proveedor
  Map<String, List<SupplierCost>> _costs = const {};

  Future<void> _loadCosts() async {
    final costs = await SupplierRepository.instance.latestCosts(widget.business.id);
    if (mounted) setState(() => _costs = costs);
  }

  /// "Con El Sol: $22.000 · Más barato con La Luna: $20.000"
  String? _costHint(Product p) {
    final list = _costs[p.id];
    if (list == null || list.isEmpty) return null;
    final mine = _supplier == null
        ? null
        : list.where((s) => s.supplierId == _supplier!.id).firstOrNull;
    final cheapest = list.first;
    final parts = <String>[
      if (mine != null) 'Última vez con ${mine.supplierName}: ${CurrencyFormatter.format(mine.unitCost)}',
      if (cheapest.supplierId != _supplier?.id && (mine == null || cheapest.unitCost < mine.unitCost))
        'Más barato con ${cheapest.supplierName}: ${CurrencyFormatter.format(cheapest.unitCost)}',
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  String get _draftKey => 'purchase_draft_${widget.business.id}';

  @override
  void initState() {
    super.initState();
    _syncDueDate();
    _loadCosts();
    final order = widget.order;
    if (order != null) {
      _useOrder(order);
    } else {
      _restoreDraft().then((_) => _loadPendingOrders());
    }
  }

  // ---------------------------------------------------------------------------
  // Recibir un pedido: se precargan las cantidades pedidas que faltan por llegar
  // ---------------------------------------------------------------------------

  Future<void> _loadPendingOrders() async {
    final list = await SupplierRepository.instance.getOrders(widget.business.id, pendingOnly: true);
    if (mounted) setState(() => _pendingOrders = list);
  }

  Future<void> _chooseOrder() async {
    final list =
        _supplier == null ? _pendingOrders : _pendingOrders.where((o) => o.supplierId == _supplier!.id).toList();
    final picked = await showModalBottomSheet<SupplierOrder>(
      context: context,
      useSafeArea: true,
      builder: (ctx) {
        final c = ctx.colors;
        return ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(AppSpace.lg),
          children: [
            Text('¿Qué pedido llegó?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: c.ink)),
            const SizedBox(height: AppSpace.sm),
            for (final o in list.isEmpty ? _pendingOrders : list)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.local_shipping_outlined, color: c.inkMuted),
                title: Text(
                  '${o.supplierName ?? 'Sin proveedor'} · ${_dateLabel(o.createdAt)}',
                  style: TextStyle(color: c.ink, fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  '${o.statusLabel} · faltan ${o.missingUnits} de ${o.units} unidades',
                  style: TextStyle(color: c.inkMuted, fontSize: 12),
                ),
                onTap: () => Navigator.pop(ctx, o),
              ),
          ],
        );
      },
    );
    if (picked != null) await _useOrder(picked);
  }

  Future<void> _useOrder(SupplierOrder order) async {
    final byProduct = <String, List<SupplierOrderItem>>{};
    for (final i in order.missingItems) {
      byProduct.putIfAbsent(i.productId, () => []).add(i);
    }
    final lines = <_Line>[];
    for (final entry in byProduct.entries) {
      final product = await _products.getProductById(entry.key, widget.business.id);
      if (product == null) continue;
      lines.add(_Line(
        product,
        initialQty: entry.value.where((i) => i.variantId == null).fold(0, (s, i) => s + i.missing),
        initialVariantQty: {
          for (final i in entry.value)
            if (i.variantId != null) i.variantId!: i.missing,
        },
      ));
    }
    final supplier = order.supplierId == null ? null : await SupplierRepository.instance.getSupplier(order.supplierId!);
    if (!mounted) return;
    setState(() {
      for (final l in _lines) {
        l.dispose();
      }
      _lines
        ..clear()
        ..addAll(lines);
      _order = order;
      if (supplier != null) {
        _supplier = supplier;
        _credit = supplier.isCredit;
        _syncDueDate();
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Borrador: si sales sin guardar, la entrada queda guardada en este equipo
  // ---------------------------------------------------------------------------

  Future<void> _saveDraft() async {
    final draft = {
      'saved_at': DateTime.now().toIso8601String(),
      'supplier_id': _supplier?.id,
      'invoice': _invoice.text.trim(),
      'date': _date.toIso8601String(),
      'credit': _credit,
      'due': _dueDate?.toIso8601String(),
      'notes': _notes.text.trim(),
      'lines': [for (final l in _lines) l.toDraft()],
      'order_id': _order?.id,
    };
    await AppDatabase.instance.setSetting(_draftKey, jsonEncode(draft));
  }

  Future<void> _clearDraft() => AppDatabase.instance.setSetting(_draftKey, null);

  Future<void> _restoreDraft() async {
    try {
      final raw = await AppDatabase.instance.getSetting(_draftKey);
      if (raw == null) return;
      final d = jsonDecode(raw) as Map<String, dynamic>;
      final lines = <_Line>[];
      for (final l in (d['lines'] as List? ?? const [])) {
        final m = Map<String, dynamic>.from(l as Map);
        final product = await _products.getProductById(m['product_id'] as String, widget.business.id);
        if (product == null) continue;
        final line = _Line(
          product,
          initialQty: (m['qty'] as num?)?.toInt() ?? 0,
          initialVariantQty: {
            for (final e in Map<String, dynamic>.from(m['variants'] as Map? ?? const {}).entries)
              e.key: (e.value as num).toInt(),
          },
          cost: (m['cost'] as num?)?.toDouble(),
        )..updateCost = m['update_cost'] as bool? ?? true;
        lines.add(line);
      }
      final orderId = d['order_id'] as String?;
      final order = orderId == null ? null : await SupplierRepository.instance.getOrder(orderId);
      final supplierId = d['supplier_id'] as String?;
      final supplier =
          widget.supplier ?? (supplierId == null ? null : await SupplierRepository.instance.getSupplier(supplierId));
      if (!mounted) return;
      setState(() {
        _lines.addAll(lines);
        _supplier = supplier;
        _invoice.text = d['invoice'] as String? ?? '';
        _notes.text = d['notes'] as String? ?? '';
        _date = DateTime.tryParse(d['date'] as String? ?? '') ?? _date;
        _credit = d['credit'] as bool? ?? _credit;
        _dueDate = DateTime.tryParse(d['due'] as String? ?? '') ?? _dueDate;
        _draftFrom = DateTime.tryParse(d['saved_at'] as String? ?? '');
        _order = order;
      });
    } catch (e) {
      debugPrint('No se pudo leer el borrador de la entrada: $e');
    }
  }

  Future<void> _discardDraft() async {
    await _clearDraft();
    if (!mounted) return;
    setState(() {
      for (final l in _lines) {
        l.dispose();
      }
      _lines.clear();
      _invoice.clear();
      _notes.clear();
      _draftFrom = null;
    });
  }

  /// Al salir con productos escritos: guardar borrador, descartar o seguir
  Future<void> _confirmLeave() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Salir sin guardar la entrada?'),
        content: const Text('Puedes dejarla como borrador y terminarla después en este equipo.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, 'discard'), child: const Text('Descartar')),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Seguir aquí')),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'draft'), child: const Text('Guardar borrador')),
        ],
      ),
    );
    if (choice == null || !mounted) return;
    if (choice == 'draft') {
      await _saveDraft();
      if (mounted) AppToast.showInfo(context, 'Borrador guardado. Lo verás al abrir otra entrada.');
    } else {
      await _clearDraft();
    }
    if (!mounted) return;
    setState(() => _leaving = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.pop(context, false);
    });
  }

  // ---------------------------------------------------------------------------
  // Foto de la factura
  // ---------------------------------------------------------------------------

  void _pickPhoto() {
    ImageSourcePickerModal.show(
      context,
      title: 'Foto de la factura',
      subtitle: 'Queda guardada en privado: solo la ve el equipo del negocio',
      hasExistingImage: _photo != null,
      onSelected: (source) async {
        final picked = await ImageHelper.pickBytes(source);
        if (picked != null && mounted) setState(() => _photo = picked);
      },
      onRemove: () => setState(() => _photo = null),
    );
  }

  // ---------------------------------------------------------------------------
  // Producto nuevo (no estaba en el inventario)
  // ---------------------------------------------------------------------------

  Future<void> _createProduct() async {
    Product? created;
    await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => ProductFormScreen(
        businessId: widget.business.id,
        initialSupplierId: _supplier?.id,
        onCreatedForPurchase: (p) => created = p,
      ),
    ));
    final p = created;
    if (p == null || !mounted) return;
    // Se guardó en 0: lo escrito en el formulario es lo que llegó
    final saved = await _products.getProductById(p.id, p.businessId) ?? p;
    if (!mounted) return;
    setState(() {
      _lines.insert(
        0,
        _Line(
          saved,
          initialQty: p.hasVariants ? 0 : p.stock,
          initialVariantQty: {for (final v in p.variants) v.id: v.stock},
          cost: p.purchasePrice,
        )..updateCost = false,
      );
    });
  }

  @override
  void dispose() {
    _invoice.dispose();
    _notes.dispose();
    for (final l in _lines) {
      l.dispose();
    }
    super.dispose();
  }

  void _syncDueDate() {
    _dueDate = _credit ? _date.add(Duration(days: _supplier?.creditDays ?? 30)) : null;
  }

  double get _total => _lines.fold(0.0, (s, l) => s + l.unitCost * l.units);
  int get _units => _lines.fold(0, (s, l) => s + l.units);

  Future<void> _pickSupplier() async {
    final s = await SupplierPicker.pick(context, businessId: widget.business.id);
    if (s == null || !mounted) return;
    setState(() {
      _supplier = s;
      _credit = s.isCredit;
      _syncDueDate();
    });
  }

  Future<void> _addProduct(Product product, {String? variantId, int qty = 0}) async {
    // La lista no trae tallas y colores: se carga el producto completo
    final full = await _products.getProductById(product.id, product.businessId) ?? product;
    if (!mounted) return;
    setState(() {
      final existing = _lines.where((l) => l.product.id == full.id).firstOrNull;
      if (existing != null) {
        if (qty > 0) existing.addOne(variantId);
      } else {
        _lines.insert(0, _Line(full, initialQty: qty, variantId: variantId));
      }
    });
  }

  Future<void> _search() async {
    final all = await _products.getAllProducts(widget.business.id);
    if (!mounted) return;
    final picked = await showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _ProductSearchSheet(products: all, supplierId: _supplier?.id),
    );
    if (picked is Product) await _addProduct(picked);
    if (picked == _ProductSearchSheet.createNew) await _createProduct();
  }

  Future<void> _scan() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const BarcodeScannerScreen()),
    );
    if (code == null || code.isEmpty || !mounted) return;
    final product = await _products.getProductByCode(code, widget.business.id);
    if (!mounted) return;
    if (product == null) {
      AppToast.showWarning(context, 'No hay ningún producto con el código $code.');
      return;
    }
    final variant = product.variants.where((v) => v.skuOrBarcode == code).firstOrNull;
    await _addProduct(product, variantId: variant?.id, qty: product.hasVariants && variant == null ? 0 : 1);
  }

  Future<void> _pickDate({required bool due}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: due ? (_dueDate ?? now) : _date,
      firstDate: DateTime(now.year - 2),
      lastDate: due ? DateTime(now.year + 2) : now,
    );
    if (picked == null) return;
    setState(() {
      if (due) {
        _dueDate = picked;
      } else {
        _date = DateTime(picked.year, picked.month, picked.day, now.hour, now.minute);
        _syncDueDate();
      }
    });
  }

  Future<void> _save() async {
    final items = [for (final l in _lines) ...l.items];
    if (items.isEmpty) {
      AppToast.showWarning(context, 'Escribe cuántas unidades llegaron.');
      return;
    }
    setState(() => _saving = true);
    final purchase = Purchase(
      id: _purchaseId,
      orderId: _order?.id,
      businessId: widget.business.id,
      supplierId: _supplier?.id,
      supplierName: _supplier?.name,
      invoiceNumber: _invoice.text.trim().isEmpty ? null : _invoice.text.trim(),
      date: _date,
      items: items,
      paymentTerms: _credit ? 'CREDITO' : 'CONTADO',
      dueDate: _credit ? _dueDate : null,
      isPaid: !_credit,
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      createdBy: AuthRepository.instance.currentUser?.email,
      createdAt: DateTime.now(),
    );
    final newCosts = {
      for (final l in _lines)
        if (l.units > 0 && l.costChanged && l.updateCost) l.product.id: l.unitCost,
    };
    try {
      final repo = SupplierRepository.instance;
      await repo.registerPurchase(purchase, newCosts: newCosts);
      await _clearDraft();
      var photoFailed = false;
      final photo = _photo;
      if (photo != null) {
        try {
          final path = await InvoicePhotoService.instance.upload(
            businessId: widget.business.id,
            purchaseId: purchase.id,
            bytes: photo.bytes,
            mimeType: photo.mimeType,
          );
          await repo.setPhoto(purchase, path);
        } on ProductImageException catch (e) {
          debugPrint('Foto de factura: ${e.message}');
          photoFailed = true;
        }
      }
      if (!mounted) return;
      final orderNow = _order == null ? null : await repo.getOrder(_order!.id);
      if (!mounted) return;
      if (orderNow != null && orderNow.missingUnits > 0) {
        AppToast.showWarning(
          context,
          'Entrada guardada. Del pedido faltaron ${orderNow.missingUnits} unidades: '
          'puedes pedirlas de nuevo desde Proveedores › Pedidos.',
        );
      } else if (photoFailed) {
        AppToast.showWarning(
          context,
          'Entrada guardada, pero la foto de la factura no se pudo subir. Puedes agregarla desde la entrada.',
        );
      } else {
        AppToast.showSuccess(context, 'Entrada guardada: ${purchase.units} unidades sumadas al inventario.');
      }
      Navigator.pop(context, true);
    } catch (e) {
      debugPrint('No se pudo guardar la entrada: $e');
      if (!mounted) return;
      setState(() => _saving = false);
      AppToast.showError(context, 'No se pudo guardar la entrada. Inténtalo de nuevo.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return PopScope(
      canPop: _lines.isEmpty || _saving || _leaving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: Scaffold(
        backgroundColor: c.paper,
        appBar: AppBar(title: const Text('Entrada de mercancía')),
        bottomNavigationBar: SafeArea(
          child: Container(
            padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.md, AppSpace.lg, AppSpace.md),
            decoration: BoxDecoration(color: c.surface, border: Border(top: BorderSide(color: c.line))),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('$_units ${_units == 1 ? 'unidad' : 'unidades'}',
                          style: TextStyle(color: c.inkMuted, fontSize: 12)),
                      Text(
                        CurrencyFormatter.format(_total),
                        style: TextStyle(color: c.ink, fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                FilledButton.icon(
                  onPressed: _saving || _units == 0 ? null : _save,
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: Text(_saving ? 'Guardando...' : 'Guardar entrada'),
                ),
              ],
            ),
          ),
        ),
        body: ContentWidth(
          child: ListView(
            padding: const EdgeInsets.all(AppSpace.lg),
            children: [
              if (_draftFrom != null) ...[
                Container(
                  padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.sm, AppSpace.sm, AppSpace.sm),
                  decoration: BoxDecoration(
                    color: c.infoSoft,
                    borderRadius: BorderRadius.circular(AppRadius.control),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Retomaste el borrador del ${_dateLabel(_draftFrom!)}.',
                          style: TextStyle(color: c.info, fontSize: 13),
                        ),
                      ),
                      TextButton(onPressed: _discardDraft, child: const Text('Descartar')),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpace.md),
              ],
              _section(
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.storefront_outlined, color: c.inkMuted),
                    title: Text(
                      _supplier?.name ?? 'Sin proveedor',
                      style: TextStyle(color: c.ink, fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      _supplier == null ? 'Opcional: toca para elegirlo' : _supplier!.summary,
                      style: TextStyle(color: c.inkMuted, fontSize: 12),
                    ),
                    trailing: _supplier == null
                        ? Text('Elegir', style: TextStyle(color: c.accent, fontWeight: FontWeight.w600))
                        : IconButton(
                            tooltip: 'Quitar proveedor',
                            icon: const Icon(Icons.close_rounded, size: 18),
                            onPressed: () => setState(() => _supplier = null),
                          ),
                    onTap: _pickSupplier,
                  ),
                  Divider(color: c.line, height: 1),
                  const SizedBox(height: AppSpace.md),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _invoice,
                          decoration: const InputDecoration(labelText: 'N.º de factura (opcional)', isDense: true),
                        ),
                      ),
                      const SizedBox(width: AppSpace.md),
                      OutlinedButton.icon(
                        onPressed: () => _pickDate(due: false),
                        icon: const Icon(Icons.event_outlined, size: 16),
                        label: Text(_dateLabel(_date)),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpace.md),
                  SegmentedButton<bool>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: false, label: Text('De contado')),
                      ButtonSegment(value: true, label: Text('A crédito')),
                    ],
                    selected: {_credit},
                    onSelectionChanged: (v) => setState(() {
                      _credit = v.first;
                      _syncDueDate();
                    }),
                  ),
                  if (_credit) ...[
                    const SizedBox(height: AppSpace.sm),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      leading: Icon(Icons.schedule_rounded, size: 18, color: context.colors.inkMuted),
                      title: Text(
                        'Pagar a más tardar el ${_dateLabel(_dueDate ?? DateTime.now())}',
                        style: TextStyle(color: context.colors.ink),
                      ),
                      trailing:
                          Text('Cambiar', style: TextStyle(color: context.colors.accent, fontWeight: FontWeight.w600)),
                      onTap: () => _pickDate(due: true),
                    ),
                  ],
                  const SizedBox(height: AppSpace.sm),
                  _photo == null
                      ? OutlinedButton.icon(
                          onPressed: _pickPhoto,
                          icon: const Icon(Icons.photo_camera_outlined, size: 18),
                          label: const Text('Foto de la factura (opcional)'),
                        )
                      : Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.memory(_photo!.bytes, width: 56, height: 56, fit: BoxFit.cover),
                            ),
                            const SizedBox(width: AppSpace.md),
                            Expanded(
                              child: Text('Foto de la factura lista', style: TextStyle(color: c.ink, fontSize: 13)),
                            ),
                            TextButton(onPressed: _pickPhoto, child: const Text('Cambiar')),
                          ],
                        ),
                ],
              ),
              if (_order != null) ...[
                const SizedBox(height: AppSpace.md),
                Container(
                  padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.sm, AppSpace.sm, AppSpace.sm),
                  decoration:
                      BoxDecoration(color: c.successSoft, borderRadius: BorderRadius.circular(AppRadius.control)),
                  child: Row(
                    children: [
                      Icon(Icons.local_shipping_outlined, color: c.success, size: 20),
                      const SizedBox(width: AppSpace.sm),
                      Expanded(
                        child: Text(
                          'Recibiendo el pedido del ${_dateLabel(_order!.createdAt)}. '
                          'Corrige las cantidades si algo no llegó.',
                          style: TextStyle(color: c.ink, fontSize: 12.5),
                        ),
                      ),
                      TextButton(onPressed: () => setState(() => _order = null), child: const Text('Quitar')),
                    ],
                  ),
                ),
              ] else if (_pendingOrders.isNotEmpty) ...[
                const SizedBox(height: AppSpace.md),
                OutlinedButton.icon(
                  onPressed: _chooseOrder,
                  icon: const Icon(Icons.local_shipping_outlined, size: 18),
                  label: Text(
                    _pendingOrders.length == 1
                        ? 'Recibir el pedido que está en camino'
                        : 'Recibir un pedido (${_pendingOrders.length} en camino)',
                  ),
                ),
              ],
              const SizedBox(height: AppSpace.lg),
              Row(
                children: [
                  Expanded(
                    child:
                        Text('Lo que llegó', style: TextStyle(color: c.ink, fontWeight: FontWeight.bold, fontSize: 15)),
                  ),
                  IconButton(
                      tooltip: 'Escanear código', onPressed: _scan, icon: const Icon(Icons.qr_code_scanner_rounded)),
                  const SizedBox(width: AppSpace.xs),
                  FilledButton.tonalIcon(
                    onPressed: _search,
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Agregar'),
                  ),
                ],
              ),
              const SizedBox(height: AppSpace.sm),
              if (_lines.isEmpty)
                _section(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: AppSpace.lg),
                      child: Text(
                        'Agrega los productos que llegaron. Si tienen tallas y colores, escribe cuántos llegaron de cada uno.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: c.inkMuted, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              for (final l in _lines) ...[
                _lineCard(l),
                const SizedBox(height: AppSpace.md),
              ],
              const SizedBox(height: AppSpace.sm),
              TextField(
                controller: _notes,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Notas (opcional)', alignLabelWithHint: true),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _dateLabel(DateTime d) {
    const months = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  Widget _section({required List<Widget> children}) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.sm, AppSpace.lg, AppSpace.lg),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: c.line),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
    );
  }

  Widget _qtyField(TextEditingController controller) => SizedBox(
        width: 84,
        child: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          textAlign: TextAlign.center,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(isDense: true, hintText: '0', suffixText: 'u.'),
        ),
      );

  Widget _lineCard(_Line l) {
    final c = context.colors;
    final p = l.product;
    return Container(
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              ProductImageView(
                imagePath: p.photoPath,
                width: 40,
                height: 40,
                borderRadius: BorderRadius.circular(8),
              ),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.name, style: TextStyle(color: c.ink, fontWeight: FontWeight.w600)),
                    Text('Hay ${p.stock} · Cód: ${p.code}', style: TextStyle(color: c.inkMuted, fontSize: 12)),
                  ],
                ),
              ),
              if (!l.withVariants) _qtyField(l.qty),
              IconButton(
                tooltip: 'Quitar',
                icon: Icon(Icons.close_rounded, size: 18, color: c.inkFaint),
                onPressed: () => setState(() {
                  _lines.remove(l);
                  l.dispose();
                }),
              ),
            ],
          ),
          if (l.withVariants) ...[
            const SizedBox(height: AppSpace.sm),
            for (final v in p.variants)
              Padding(
                padding: const EdgeInsets.only(bottom: 6, left: 52),
                child: Row(
                  children: [
                    if (ColorSwatchDot.hasSwatch(v.colorHex)) ...[
                      ColorSwatchDot(hex: v.colorHex, hex2: v.colorHex2, size: 16),
                      const SizedBox(width: AppSpace.sm),
                    ],
                    Expanded(
                      child: Text(
                        '${v.label.isEmpty ? 'Sin nombre' : v.label}  ·  hay ${v.stock}',
                        style: TextStyle(color: c.ink, fontSize: 13),
                      ),
                    ),
                    _qtyField(l.variantQty[v.id]!),
                    const SizedBox(width: 40),
                  ],
                ),
              ),
          ],
          const SizedBox(height: AppSpace.sm),
          Row(
            children: [
              const SizedBox(width: 52),
              SizedBox(
                width: 150,
                child: TextField(
                  controller: l.cost,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(isDense: true, labelText: 'Costo por unidad', prefixText: '\$ '),
                ),
              ),
              const Spacer(),
              Text(
                CurrencyFormatter.format(l.unitCost * l.units),
                style: TextStyle(color: c.ink, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          if (_costHint(l.product) case final hint?)
            Padding(
              padding: const EdgeInsets.only(left: 52, top: AppSpace.xs),
              child: Text(hint, style: TextStyle(color: c.inkMuted, fontSize: 11.5)),
            ),
          if (l.costChanged)
            Padding(
              padding: const EdgeInsets.only(left: 40, top: AppSpace.xs),
              child: CheckboxListTile(
                value: l.updateCost,
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                onChanged: (v) => setState(() => l.updateCost = v ?? true),
                title: Text(
                  p.purchasePrice > 0
                      ? 'El costo cambió (antes ${CurrencyFormatter.format(p.purchasePrice)}). Actualizarlo en el producto'
                      : 'Guardar este costo en el producto',
                  style: TextStyle(color: c.warning, fontSize: 12.5),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Buscador de productos para la entrada. Si hay proveedor, sus productos salen primero.
class _ProductSearchSheet extends StatefulWidget {
  /// Lo que devuelve la hoja cuando se pide crear un producto que no existe
  static const createNew = 'create_new';

  final List<Product> products;
  final String? supplierId;
  const _ProductSearchSheet({required this.products, this.supplierId});

  @override
  State<_ProductSearchSheet> createState() => _ProductSearchSheetState();
}

class _ProductSearchSheetState extends State<_ProductSearchSheet> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final q = _q.trim().toLowerCase();
    final list = widget.products
        .where((p) => q.isEmpty || p.name.toLowerCase().contains(q) || p.code.toLowerCase().contains(q))
        .toList()
      ..sort((a, b) {
        final sa = a.supplierId != null && a.supplierId == widget.supplierId ? 0 : 1;
        final sb = b.supplierId != null && b.supplierId == widget.supplierId ? 0 : 1;
        return sa != sb ? sa - sb : a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.75,
      child: Padding(
        padding: EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.lg, AppSpace.lg, MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Agregar producto', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: c.ink)),
            const SizedBox(height: AppSpace.md),
            TextField(
              autofocus: true,
              onChanged: (v) => setState(() => _q = v),
              decoration: const InputDecoration(hintText: 'Buscar por nombre o código', prefixIcon: Icon(Icons.search)),
            ),
            const SizedBox(height: AppSpace.sm),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(backgroundColor: c.successSoft, child: Icon(Icons.add_rounded, color: c.success)),
              title: Text('Crear producto nuevo', style: TextStyle(color: c.ink, fontWeight: FontWeight.w600)),
              subtitle: Text('Si llegó algo que aún no tienes en el inventario',
                  style: TextStyle(color: c.inkMuted, fontSize: 12)),
              onTap: () => Navigator.pop(context, _ProductSearchSheet.createNew),
            ),
            Divider(color: c.line, height: 1),
            Expanded(
              child: list.isEmpty
                  ? Center(child: Text('No se encontraron productos', style: TextStyle(color: c.inkMuted)))
                  : ListView.separated(
                      itemCount: list.length,
                      separatorBuilder: (_, __) => Divider(color: c.line, height: 1),
                      itemBuilder: (_, i) {
                        final p = list[i];
                        final fromSupplier = p.supplierId != null && p.supplierId == widget.supplierId;
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: ProductImageView(
                            imagePath: p.photoPath,
                            width: 40,
                            height: 40,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          title: Text(p.name, style: TextStyle(color: c.ink, fontWeight: FontWeight.w600)),
                          subtitle: Text(
                            'Hay ${p.stock}${p.hasVariants ? ' · con tallas y colores' : ''}${fromSupplier ? ' · de este proveedor' : ''}',
                            style: TextStyle(color: c.inkMuted, fontSize: 12),
                          ),
                          trailing: Icon(Icons.add_circle_outline, color: c.accent),
                          onTap: () => Navigator.pop(context, p),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
