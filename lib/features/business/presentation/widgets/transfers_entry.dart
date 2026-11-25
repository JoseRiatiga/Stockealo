import 'package:flutter/material.dart';

import '../../../../core/design/app_card.dart';
import '../../../../core/services/data_events.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../products/data/product_repository.dart';
import '../../../products/models/product.dart';
import '../../data/branch_repository.dart';
import '../../data/transfer_repository.dart';
import '../../models/business.dart';
import '../screens/new_transfer_screen.dart';
import '../screens/transfers_screen.dart';

/// En Stock (0.18.5): el botón «Traslados», el aviso «Te llegan» y la sugerencia
/// «Norte tiene 3 productos que aquí faltan · Traer de Norte» (dueño y
/// administradores). Solo si el negocio tiene sedes abiertas.
class TransfersEntry extends StatefulWidget {
  final Business business;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onChanged;

  const TransfersEntry({super.key, required this.business, this.padding = EdgeInsets.zero, this.onChanged});

  @override
  State<TransfersEntry> createState() => _TransfersEntryState();
}

class _TransfersEntryState extends State<TransfersEntry> {
  final _branches = BranchRepository.instance;
  ({String? fromBranchId, List<({Product product, int quantity})> items})? _suggestion;

  @override
  void initState() {
    super.initState();
    _branches.addListener(_refresh);
    DataEvents.instance.productsVersion.addListener(_suggest);
    _refresh();
  }

  @override
  void dispose() {
    _branches.removeListener(_refresh);
    DataEvents.instance.productsVersion.removeListener(_suggest);
    super.dispose();
  }

  void _refresh() {
    if (!mounted) return;
    setState(() {});
    _suggest();
  }

  /// Lo que otra sede tiene de sobra y aquí falta (solo dueño y administradores)
  Future<void> _suggest() async {
    if (!TransfersScreen.isManager || _branches.openBranches.isEmpty || _branches.viewAll.value) {
      if (mounted && _suggestion != null) setState(() => _suggestion = null);
      return;
    }
    final here = BranchRepository.active;
    final repo = ProductRepository.instance;
    final mine = await repo.productsAt(widget.business.id, here);
    final others = <String?, List<Product>>{
      if (here != null) null: await repo.productsAt(widget.business.id, null),
      for (final b in _branches.openBranches)
        if (b.id != here && b.usable) b.id: await repo.productsAt(widget.business.id, b.id),
    };
    final found = TransferRepository.suggestions(here: mine, others: others);
    if (mounted) setState(() => _suggestion = found.firstOrNull);
  }

  Future<void> _open() async {
    await TransfersScreen.open(context, widget.business);
    await TransferRepository.instance.refreshIncoming(widget.business.id);
    widget.onChanged?.call();
  }

  Future<void> _bring() async {
    final s = _suggestion;
    if (s == null) return;
    final sent = await NewTransferScreen.open(
      context,
      businessId: widget.business.id,
      fromBranchId: s.fromBranchId,
      toBranchId: BranchRepository.active,
      toSet: true,
      preset: s.items,
    );
    if (sent == true) {
      widget.onChanged?.call();
      _suggest();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_branches.openBranches.isEmpty) return const SizedBox.shrink();
    final c = context.colors;
    final s = _suggestion;
    return Padding(
      padding: widget.padding,
      child: ValueListenableBuilder<int>(
        valueListenable: TransferRepository.instance.incoming,
        builder: (context, incoming, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (incoming > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.sm),
                child: AppCard(
                  onTap: _open,
                  child: Row(children: [
                    Icon(Icons.move_to_inbox_outlined, color: c.warning),
                    const SizedBox(width: AppSpace.md),
                    Expanded(
                      child: Text(
                        incoming == 1 ? 'Te llega 1 traslado' : 'Te llegan $incoming traslados',
                        style: AppText.body(context, weight: FontWeight.w700),
                      ),
                    ),
                    FilledButton(onPressed: _open, child: const Text('Recibir')),
                  ]),
                ),
              ),
            if (s != null)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.sm),
                child: AppCard(
                  child: Row(children: [
                    Icon(Icons.swap_horiz_outlined, color: c.info),
                    const SizedBox(width: AppSpace.md),
                    Expanded(
                      child: Text(
                        '${_branches.nameOf(s.fromBranchId)} tiene ${s.items.length == 1 ? '1 producto que aquí falta' : '${s.items.length} productos que aquí faltan'}: '
                        '${s.items.take(2).map((i) => i.product.name).join(', ')}${s.items.length > 2 ? '…' : ''}',
                        style: AppText.small(context),
                      ),
                    ),
                    const SizedBox(width: AppSpace.sm),
                    OutlinedButton(onPressed: _bring, child: Text('Traer de ${_branches.nameOf(s.fromBranchId)}')),
                  ]),
                ),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _open,
                icon: const Icon(Icons.swap_horiz_outlined, size: 18),
                label: const Text('Traslados'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
