import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/design/app_card.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../home/navigation/app_pane.dart';
import '../../../products/data/product_repository.dart';
import '../../../products/models/product.dart';
import '../../../team/data/activity_repository.dart';
import '../../data/branch_repository.dart';
import '../../data/transfer_repository.dart';

/// Nuevo traslado (0.18.5, boceto aprobado el 25 nov): desde la sede elegida hacia
/// otra, con varios productos y cuántas unidades de cada uno. Al enviar, las unidades
/// salen de la sede de origen y quedan «En camino».
class NewTransferScreen extends StatefulWidget {
  final String businessId;

  /// null = la Principal
  final String? fromBranchId;

  /// Destino ya elegido (solo si [toSet]; null = la Principal)
  final String? toBranchId;
  final bool toSet;

  /// «Traer de Norte»: productos y cantidades ya puestos
  final List<({Product product, int quantity})> preset;

  const NewTransferScreen({
    super.key,
    required this.businessId,
    required this.fromBranchId,
    this.toBranchId,
    this.toSet = false,
    this.preset = const [],
  });

  /// true si se envió
  static Future<bool?> open(
    BuildContext context, {
    required String businessId,
    required String? fromBranchId,
    String? toBranchId,
    bool toSet = false,
    List<({Product product, int quantity})> preset = const [],
  }) =>
      AppPane.open<bool>(
        context,
        (_) => NewTransferScreen(
            businessId: businessId, fromBranchId: fromBranchId, toBranchId: toBranchId, toSet: toSet, preset: preset),
      );

  @override
  State<NewTransferScreen> createState() => _NewTransferScreenState();
}

/// Sentinela para «sin elegir» (null ya quiere decir la Principal)
const _none = '__none__';

class _NewTransferScreenState extends State<NewTransferScreen> {
  final _branches = BranchRepository.instance;
  final _search = TextEditingController();
  final _note = TextEditingController();
  List<Product> _products = const [];
  Map<String, Product> _atDest = const {};
  final _lines = <String, TransferDraftLine>{};
  String? _to = _none;

  /// Un id por pantalla: si se reintenta, la nube no envía dos veces
  final _transferId = const Uuid().v4();
  bool _loading = true;
  bool _sending = false;

  /// Sedes a las que se puede enviar: las abiertas y en uso, y la Principal
  List<(String?, String)> get _destinations => [
        if (widget.fromBranchId != null) (null, _branches.mainName),
        for (final b in _branches.openBranches)
          if (b.usable && b.id != widget.fromBranchId) (b.id, b.name),
      ];

  @override
  void initState() {
    super.initState();
    final dests = _destinations;
    if (widget.toSet && dests.any((d) => d.$1 == widget.toBranchId)) {
      _to = widget.toBranchId;
    } else if (dests.length == 1) {
      _to = dests.first.$1;
    }
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final repo = ProductRepository.instance;
    final products = await repo.productsAt(widget.businessId, widget.fromBranchId);
    if (!mounted) return;
    setState(() {
      _products = products;
      for (final p in widget.preset) {
        final here = products.where((x) => x.id == p.product.id).firstOrNull;
        if (here == null) continue;
        final line = TransferDraftLine(product: here, available: here.stock, quantity: p.quantity);
        _lines[line.key] = line;
      }
      _loading = false;
    });
    await _loadDest();
  }

  Future<void> _loadDest() async {
    if (_to == _none) return;
    final dest = await ProductRepository.instance.productsAt(widget.businessId, _to);
    if (mounted) setState(() => _atDest = {for (final p in dest) p.id: p});
  }

  int _destStock(Product p, String? variantId) {
    final d = _atDest[p.id];
    if (d == null) return 0;
    if (variantId == null) return d.stock;
    return d.variants.where((v) => v.id == variantId).firstOrNull?.stock ?? 0;
  }

  List<Product> get _matches {
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return const [];
    return _products
        .where((p) => p.name.toLowerCase().contains(q) || p.code.toLowerCase().contains(q))
        .take(8)
        .toList();
  }

  void _add(Product p, {String? variantId, String? variantLabel, required int available}) {
    final line = TransferDraftLine(product: p, variantId: variantId, variantLabel: variantLabel, available: available);
    setState(() {
      _lines.putIfAbsent(line.key, () => line);
      _search.clear();
    });
  }

  int get _units => _lines.values.fold(0, (s, l) => s + l.quantity);

  Future<void> _send() async {
    if (_to == _none) {
      AppToast.showWarning(context, 'Elige a qué sede lo envías.');
      return;
    }
    final to = _to;
    setState(() => _sending = true);
    try {
      final lines = _lines.values.toList();
      await TransferRepository.instance.send(
        id: _transferId,
        businessId: widget.businessId,
        fromBranchId: widget.fromBranchId,
        toBranchId: to,
        lines: lines,
        note: _note.text.trim(),
      );
      final names = lines.map((l) => '${l.quantity} ${l.label}').join(', ');
      ActivityRepository.instance.log(
        businessId: widget.businessId,
        action: ActivityAction.transferSend,
        summary: 'Envió $names de ${_branches.nameOf(widget.fromBranchId)} a ${_branches.nameOf(to)}',
      );
      if (!mounted) return;
      AppToast.showSuccess(context, 'Enviado: ${unitsText(_units)} ${_units == 1 ? 'va' : 'van'} en camino a ${_branches.nameOf(to)}.');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        AppToast.showError(context, TransferRepository.friendlyError(e));
        setState(() => _sending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final dests = _destinations;
    final from = _branches.nameOf(widget.fromBranchId);
    final over = _lines.values.where((l) => l.tooMany).toList();
    return Scaffold(
      backgroundColor: c.paper,
      appBar: AppBar(title: const Text('Nuevo traslado')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.all(AppSpace.lg),
                        children: [
                          AppCard(
                            child: Row(children: [
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text('DESDE', style: AppText.caption(context, color: c.inkMuted)),
                                  Text(from, style: AppText.bodyLarge(context, weight: FontWeight.w700)),
                                ]),
                              ),
                              Icon(Icons.arrow_forward, color: c.inkMuted),
                              const SizedBox(width: AppSpace.md),
                              Expanded(
                                child: DropdownButtonFormField<String?>(
                                  initialValue: _to,
                                  isExpanded: true,
                                  decoration: const InputDecoration(labelText: 'Hacia', isDense: true),
                                  items: [
                                    if (_to == _none) const DropdownMenuItem(value: _none, child: Text('Elige la sede')),
                                    for (final d in dests) DropdownMenuItem(value: d.$1, child: Text(d.$2)),
                                  ],
                                  onChanged: (v) {
                                    setState(() => _to = v);
                                    _loadDest();
                                  },
                                ),
                              ),
                            ]),
                          ),
                          if (dests.isEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: AppSpace.md),
                              child: Text('No hay otra sede en uso a la que enviar.', style: AppText.body(context, color: c.danger)),
                            ),
                          const SizedBox(height: AppSpace.lg),
                          TextField(
                            controller: _search,
                            decoration: const InputDecoration(
                              labelText: 'Productos',
                              hintText: 'Busca por nombre o código',
                              prefixIcon: Icon(Icons.search_outlined),
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                          for (final p in _matches) ..._matchTiles(p),
                          const SizedBox(height: AppSpace.md),
                          if (_lines.isNotEmpty)
                            AppCard(
                              child: Column(children: [for (final l in _lines.values) _lineRow(l)]),
                            ),
                          for (final l in over)
                            Padding(
                              padding: const EdgeInsets.only(top: AppSpace.sm),
                              child: Text('${l.label}: aquí hay ${l.available}, no se pueden enviar ${l.quantity}.',
                                  style: AppText.small(context, color: c.danger)),
                            ),
                          const SizedBox(height: AppSpace.md),
                          TextField(
                            controller: _note,
                            maxLength: 500,
                            decoration: const InputDecoration(labelText: 'Nota (opcional)'),
                          ),
                          Container(
                            padding: const EdgeInsets.all(AppSpace.md),
                            decoration: BoxDecoration(color: c.infoSoft, borderRadius: BorderRadius.circular(AppRadius.control)),
                            child: Text(
                              'Al enviar, las unidades salen de $from y quedan «En camino» hasta que las reciban. '
                              'Necesitas conexión.',
                              style: AppText.small(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                    _bottomBar(over.isNotEmpty),
                  ],
                ),
        ),
      ),
    );
  }

  List<Widget> _matchTiles(Product p) {
    final c = context.colors;
    if (p.hasVariants && p.variants.isNotEmpty) {
      return [
        for (final v in p.variants)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('${p.name} · ${v.label}'),
            subtitle: Text('Aquí hay ${v.stock}', style: AppText.small(context, color: c.inkMuted)),
            trailing: const Icon(Icons.add),
            enabled: v.stock > 0,
            onTap: () => _add(p, variantId: v.id, variantLabel: v.label, available: v.stock),
          ),
      ];
    }
    return [
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(p.name),
        subtitle: Text('Aquí hay ${p.stock}', style: AppText.small(context, color: c.inkMuted)),
        trailing: const Icon(Icons.add),
        enabled: p.stock > 0,
        onTap: () => _add(p, available: p.stock),
      ),
    ];
  }

  Widget _lineRow(TransferDraftLine l) {
    final c = context.colors;
    final destName = _to == _none ? null : _branches.nameOf(_to);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(l.label, style: AppText.body(context, weight: FontWeight.w600)),
            Text(
              [
                'Aquí hay ${l.available}',
                if (destName != null) '$destName tiene ${_destStock(l.product, l.variantId)}',
              ].join(' · '),
              style: AppText.small(context, color: l.tooMany ? c.danger : c.inkMuted),
            ),
          ]),
        ),
        IconButton(
          tooltip: 'Menos',
          onPressed: () => setState(() {
            if (l.quantity <= 1) {
              _lines.remove(l.key);
            } else {
              l.quantity--;
            }
          }),
          icon: Icon(l.quantity <= 1 ? Icons.delete_outline : Icons.remove),
        ),
        SizedBox(
          width: 36,
          child: Text('${l.quantity}', textAlign: TextAlign.center, style: AppText.bodyLarge(context, weight: FontWeight.w700)),
        ),
        IconButton(tooltip: 'Más', onPressed: () => setState(() => l.quantity++), icon: const Icon(Icons.add)),
      ]),
    );
  }

  Widget _bottomBar(bool blocked) {
    final c = context.colors;
    final n = _lines.length;
    final to = _to == _none ? null : _branches.nameOf(_to);
    return Container(
      decoration: BoxDecoration(color: c.surface, border: Border(top: BorderSide(color: c.line))),
      padding: EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.md, AppSpace.lg, AppSpace.md + MediaQuery.paddingOf(context).bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(child: Text('$n ${n == 1 ? 'producto' : 'productos'}', style: AppText.body(context, color: c.inkMuted))),
            Text(unitsText(_units), style: AppText.body(context, weight: FontWeight.w700)),
          ]),
          const SizedBox(height: AppSpace.sm),
          FilledButton(
            onPressed: _sending || blocked || n == 0 || to == null ? null : _send,
            child: Text(_sending ? 'Enviando…' : to == null ? 'Elige la sede' : 'Enviar a $to'),
          ),
        ],
      ),
    );
  }
}
