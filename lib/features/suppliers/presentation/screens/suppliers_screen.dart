import 'package:flutter/material.dart';

import '../../../../core/design/app_card.dart';
import '../../../../core/design/content_width.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../business/models/business.dart';
import '../../../products/presentation/widgets/restock_order_modal.dart';
import '../../data/supplier_repository.dart';
import '../../data/supplier_whatsapp.dart';
import '../../models/purchase.dart';
import '../../models/supplier.dart';
import 'purchase_detail_screen.dart';
import 'purchase_entry_screen.dart';
import 'supplier_orders_screen.dart';
import 'supplier_form_screen.dart';

/// Clientes y proveedores › Proveedores: la lista, con acceso a las entradas de mercancía
class SuppliersScreen extends StatefulWidget {
  final Business business;
  final String? userName;

  /// Dentro del marco de la app (lugar «Clientes y proveedores»): sin barra propia;
  /// «Pedidos enviados» y «Entradas» pasan a una fila arriba de la lista
  final bool embedded;

  const SuppliersScreen({super.key, required this.business, this.userName, this.embedded = false});

  static Future<void> open(BuildContext context, {required Business business, String? userName}) =>
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => SuppliersScreen(business: business, userName: userName),
      ));

  @override
  State<SuppliersScreen> createState() => _SuppliersScreenState();
}

class _SuppliersScreenState extends State<SuppliersScreen> {
  final _repo = SupplierRepository.instance;
  List<Supplier> _suppliers = [];
  Map<String, int> _counts = {};
  List<Purchase> _payables = [];
  bool _loading = true;
  String _q = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final suppliers = await _repo.getSuppliers(widget.business.id);
    final counts = await _repo.productCounts(widget.business.id);
    final payables = await _repo.getPayables(widget.business.id);
    if (!mounted) return;
    setState(() {
      _suppliers = suppliers;
      _counts = counts;
      _payables = payables;
      _loading = false;
    });
  }

  Future<void> _new() async {
    final s = await SupplierFormScreen.open(context, businessId: widget.business.id);
    if (s != null) _load();
  }

  Future<void> _openDetail(Supplier s) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SupplierDetailScreen(business: widget.business, supplier: s, userName: widget.userName),
    ));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final q = _q.trim().toLowerCase();
    final list = _suppliers
        .where((s) => q.isEmpty || s.name.toLowerCase().contains(q) || (s.contactName ?? '').toLowerCase().contains(q))
        .toList();

    return Scaffold(
      backgroundColor: c.paper,
      appBar: widget.embedded ? null : AppBar(title: const Text('Proveedores'), actions: _actions(context)),
      // Dentro de Clientes y proveedores la acción va arriba (re-diseño 0.13.4, sin botón flotante)
      floatingActionButton: widget.embedded
          ? null
          : FloatingActionButton.extended(
              onPressed: _new,
              icon: const Icon(Icons.add_outlined),
              label: const Text('Nuevo proveedor'),
            ),
      body: ContentWidth(
        child: widget.embedded ? Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.lg, AppSpace.lg, 0),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: AppSpace.md,
              runSpacing: AppSpace.sm,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Proveedores', style: AppText.title(context)),
                    Text('A quién le compras, pedidos y entradas de mercancía', style: AppText.small(context)),
                  ],
                ),
                Wrap(
                  spacing: AppSpace.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    ..._actions(context),
                    FilledButton.icon(
                      onPressed: _new,
                      icon: const Icon(Icons.add_outlined, size: 18),
                      label: const Text('Nuevo proveedor'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(child: _content(list)),
        ]) : _content(list),
      ),
    );
  }

  List<Widget> _actions(BuildContext context) => [
        TextButton.icon(
          onPressed: () async {
            await SupplierOrdersScreen.open(context, business: widget.business);
            _load();
          },
          icon: const Icon(Icons.local_shipping_outlined, size: 18),
          label: const Text('Pedidos enviados'),
        ),
        TextButton.icon(
          onPressed: () => PurchasesScreen.open(context, business: widget.business),
          icon: const Icon(Icons.receipt_long_outlined, size: 18),
          label: const Text('Entradas'),
        ),
      ];

  Widget _content(List<Supplier> list) {
    final c = context.colors;
    return Builder(builder: (context) {
      return _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.lg, AppSpace.lg, 96),
                children: [
                  AppCard(
                    onTap: () async {
                      final saved = await PurchaseEntryScreen.open(context, business: widget.business);
                      if (saved == true) _load();
                    },
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: c.successSoft,
                            borderRadius: BorderRadius.circular(AppRadius.control),
                          ),
                          child: Icon(Icons.move_to_inbox_outlined, color: c.success),
                        ),
                        const SizedBox(width: AppSpace.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Registrar entrada de mercancía',
                                  style: TextStyle(color: c.ink, fontWeight: FontWeight.w600)),
                              Text('Lo que llegó suma al inventario, también por talla y color',
                                  style: TextStyle(color: c.inkMuted, fontSize: AppText.sizeCaption)),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right_outlined, color: c.inkFaint),
                      ],
                    ),
                  ),
                  if (_payables.isNotEmpty) ...[
                    const SizedBox(height: AppSpace.sm),
                    Builder(builder: (context) {
                      final owed = _payables.fold(0.0, (s, p) => s + p.balance);
                      final overdue = _payables.where((p) => p.isOverdue()).length;
                      return AppCard(
                        color: overdue > 0 ? c.dangerSoft : c.warningSoft,
                        onTap: () async {
                          await PayablesScreen.open(context, businessId: widget.business.id);
                          _load();
                        },
                        child: Row(
                          children: [
                            Icon(Icons.account_balance_wallet_outlined, color: overdue > 0 ? c.danger : c.warning),
                            const SizedBox(width: AppSpace.md),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Por pagar: ${CurrencyFormatter.format(owed)}',
                                      style: TextStyle(color: c.ink, fontWeight: FontWeight.w600)),
                                  Text(
                                    '${_payables.length} ${_payables.length == 1 ? 'entrada' : 'entradas'} a crédito'
                                    '${overdue > 0 ? ' · $overdue ${overdue == 1 ? 'vencida' : 'vencidas'}' : ''}',
                                    style: TextStyle(color: overdue > 0 ? c.danger : c.inkMuted, fontSize: AppText.sizeCaption),
                                  ),
                                ],
                              ),
                            ),
                            Icon(Icons.chevron_right_outlined, color: c.inkFaint),
                          ],
                        ),
                      );
                    }),
                  ],
                  const SizedBox(height: AppSpace.lg),
                  if (_suppliers.isNotEmpty) ...[
                    TextField(
                      onChanged: (v) => setState(() => _q = v),
                      decoration: const InputDecoration(hintText: 'Buscar proveedor', prefixIcon: Icon(Icons.search_outlined)),
                    ),
                    const SizedBox(height: AppSpace.md),
                  ],
                  if (_suppliers.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: AppSpace.xxl),
                      child: Column(
                        children: [
                          Icon(Icons.storefront_outlined, size: 48, color: c.inkFaint),
                          const SizedBox(height: AppSpace.md),
                          Text('Aún no tienes proveedores',
                              style: TextStyle(color: c.ink, fontWeight: FontWeight.w600, fontSize: AppText.sizeBodyLarge)),
                          const SizedBox(height: AppSpace.xs),
                          Text(
                            'Es opcional. Te sirve para enviarles pedidos por WhatsApp y llevar lo que te llega.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: c.inkMuted, fontSize: AppText.sizeSmall),
                          ),
                        ],
                      ),
                    ),
                  for (final s in list) ...[
                    AppCard(
                      onTap: () => _openDetail(s),
                      padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.md),
                      child: Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: c.surfaceMuted,
                            child: Text(s.name.characters.first.toUpperCase(),
                                style: TextStyle(color: c.ink, fontWeight: FontWeight.bold)),
                          ),
                          const SizedBox(width: AppSpace.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(s.name, style: TextStyle(color: c.ink, fontWeight: FontWeight.w600)),
                                Text(
                                  [
                                    '${_counts[s.id] ?? 0} ${(_counts[s.id] ?? 0) == 1 ? 'producto' : 'productos'}',
                                    s.summary,
                                  ].join(' · '),
                                  style: TextStyle(color: c.inkMuted, fontSize: AppText.sizeCaption),
                                ),
                              ],
                            ),
                          ),
                          if (SupplierWhatsApp.numberOf(s) != null)
                            IconButton(
                              tooltip: 'Escribir por WhatsApp',
                              icon: Icon(Icons.chat_outlined, color: c.success),
                              onPressed: () => SupplierWhatsApp.send(s, 'Hola ${s.contactName ?? s.name}, ', subject: s.name),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpace.sm),
                  ],
                ],
              );
    });
  }
}

/// Ficha del proveedor con sus acciones y las entradas que ha traído
class SupplierDetailScreen extends StatefulWidget {
  final Business business;
  final Supplier supplier;
  final String? userName;

  const SupplierDetailScreen({super.key, required this.business, required this.supplier, this.userName});

  @override
  State<SupplierDetailScreen> createState() => _SupplierDetailScreenState();
}

class _SupplierDetailScreenState extends State<SupplierDetailScreen> {
  late Supplier _s = widget.supplier;
  List<Purchase> _purchases = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = SupplierRepository.instance;
    final fresh = await repo.getSupplier(_s.id);
    final purchases = await repo.getPurchases(widget.business.id, supplierId: _s.id);
    if (!mounted) return;
    if (fresh == null) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      _s = fresh;
      _purchases = purchases;
    });
  }

  Future<void> _edit() async {
    await SupplierFormScreen.open(context, businessId: widget.business.id, supplier: _s);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final pending = _purchases.fold(0.0, (s, p) => s + p.balance);
    final info = <(IconData, String)>[
      if ((_s.contactName ?? '').isNotEmpty) (Icons.person_outline_outlined, _s.contactName!),
      if ((_s.phone ?? '').isNotEmpty) (Icons.phone_outlined, _s.phone!),
      if ((_s.taxId ?? '').isNotEmpty) (Icons.badge_outlined, 'NIT ${_s.taxId}'),
      if ((_s.email ?? '').isNotEmpty) (Icons.mail_outline_outlined, _s.email!),
      if (_s.minOrder != null) (Icons.shopping_basket_outlined, 'Pedido mínimo ${CurrencyFormatter.format(_s.minOrder!)}'),
      (Icons.payments_outlined, _s.summary),
      if ((_s.notes ?? '').isNotEmpty) (Icons.notes_outlined, _s.notes!),
    ];

    return Scaffold(
      backgroundColor: c.paper,
      appBar: AppBar(
        title: Text(_s.name),
        actions: [IconButton(icon: const Icon(Icons.edit_outlined), tooltip: 'Editar', onPressed: _edit)],
      ),
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.all(AppSpace.lg),
          children: [
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final (icon, text) in info)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(icon, size: 18, color: c.inkMuted),
                          const SizedBox(width: AppSpace.md),
                          Expanded(child: Text(text, style: TextStyle(color: c.ink, fontSize: AppText.sizeBody))),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpace.md),
            Wrap(
              spacing: AppSpace.sm,
              runSpacing: AppSpace.sm,
              children: [
                FilledButton.icon(
                  onPressed: () => RestockOrderModal.show(
                    context,
                    business: widget.business,
                    userName: widget.userName,
                    supplier: _s,
                  ),
                  icon: const Icon(Icons.local_shipping_outlined, size: 18),
                  label: const Text('Hacer pedido'),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    final saved = await PurchaseEntryScreen.open(context, business: widget.business, supplier: _s);
                    if (saved == true) _load();
                  },
                  icon: const Icon(Icons.move_to_inbox_outlined, size: 18),
                  label: const Text('Registrar entrada'),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    await SupplierOrdersScreen.open(context, business: widget.business, supplierId: _s.id);
                    _load();
                  },
                  icon: const Icon(Icons.local_shipping_outlined, size: 18),
                  label: const Text('Pedidos'),
                ),
                if (SupplierWhatsApp.numberOf(_s) != null)
                  OutlinedButton.icon(
                    onPressed: () => SupplierWhatsApp.send(_s, 'Hola ${_s.contactName ?? _s.name}, ', subject: _s.name),
                    icon: const Icon(Icons.chat_outlined, size: 18),
                    label: const Text('WhatsApp'),
                  ),
              ],
            ),
            if (pending > 0) ...[
              const SizedBox(height: AppSpace.md),
              AppCard(
                color: c.warningSoft,
                child: Text(
                  'Le debes ${CurrencyFormatter.format(pending)} en entradas a crédito.',
                  style: TextStyle(color: c.warning, fontWeight: FontWeight.w600),
                ),
              ),
            ],
            const SizedBox(height: AppSpace.xl),
            Text('Entradas de mercancía', style: TextStyle(color: c.ink, fontWeight: FontWeight.bold, fontSize: AppText.sizeBodyLarge)),
            const SizedBox(height: AppSpace.sm),
            if (_purchases.isEmpty)
              Text('Aún no hay entradas de este proveedor.', style: TextStyle(color: c.inkMuted, fontSize: AppText.sizeSmall))
            else
              for (final p in _purchases) ...[
                PurchaseTile(purchase: p, onChanged: _load),
                const SizedBox(height: AppSpace.sm),
              ],
          ],
        ),
      ),
    );
  }
}

/// Historial de todas las entradas de mercancía del negocio
class PurchasesScreen extends StatefulWidget {
  final Business business;
  const PurchasesScreen({super.key, required this.business});

  static Future<void> open(BuildContext context, {required Business business}) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => PurchasesScreen(business: business)));

  @override
  State<PurchasesScreen> createState() => _PurchasesScreenState();
}

class _PurchasesScreenState extends State<PurchasesScreen> {
  List<Purchase>? _purchases;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await SupplierRepository.instance.getPurchases(widget.business.id);
    if (mounted) setState(() => _purchases = list);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final list = _purchases;
    return Scaffold(
      backgroundColor: c.paper,
      appBar: AppBar(
        title: const Text('Entradas de mercancía'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final saved = await PurchaseEntryScreen.open(context, business: widget.business);
          if (saved == true) _load();
        },
        icon: const Icon(Icons.add_outlined),
        label: const Text('Nueva entrada'),
      ),
      body: ContentWidth(
        child: list == null
            ? const Center(child: CircularProgressIndicator())
            : list.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpace.xl),
                      child: Text(
                        'Aún no has registrado mercancía que llegó.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: c.inkMuted),
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.lg, AppSpace.lg, 96),
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const SizedBox(height: AppSpace.sm),
                    itemBuilder: (_, i) => PurchaseTile(purchase: list[i], showSupplier: true, onChanged: _load),
                  ),
      ),
    );
  }
}

/// Una entrada en una lista; al tocarla abre su ficha (abonos, foto)
class PurchaseTile extends StatelessWidget {
  final Purchase purchase;
  final bool showSupplier;
  final VoidCallback? onChanged;
  const PurchaseTile({super.key, required this.purchase, this.showSupplier = false, this.onChanged});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = purchase;
    final title = [
      purchaseDateLabel(p.date),
      if (showSupplier && (p.supplierName ?? '').isNotEmpty) p.supplierName!,
    ].join(' · ');
    final status = !p.isCredit
        ? null
        : (p.isPaid ? 'pagada' : (p.isOverdue() ? 'vencida' : 'falta ${CurrencyFormatter.format(p.balance)}'));
    return AppCard(
      onTap: () async {
        final changed = await PurchaseDetailScreen.open(context, p);
        if (changed == true) onChanged?.call();
      },
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.md),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(color: c.ink, fontWeight: FontWeight.w600)),
                Text(
                  [
                    '${p.units} unidades',
                    if ((p.invoiceNumber ?? '').isNotEmpty) 'factura ${p.invoiceNumber}',
                    if (p.photoPath != null) 'con foto',
                    if (status != null) 'a crédito, $status',
                  ].join(' · '),
                  style: TextStyle(color: p.isOverdue() ? c.danger : c.inkMuted, fontSize: AppText.sizeCaption),
                ),
              ],
            ),
          ),
          Text(CurrencyFormatter.format(p.total), style: TextStyle(color: c.ink, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
