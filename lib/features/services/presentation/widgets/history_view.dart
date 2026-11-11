import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/design/app_card.dart';
import '../../../../core/design/content_width.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../business/models/business.dart';
import '../../data/services_repository.dart';
import '../../models/service_models.dart';
import '../../../../core/design/app_dialog.dart';

/// Servicios › Historial: búsqueda en vivo por placa o serial, nombre o teléfono.
/// Muestra las visitas, lo gastado, los servicios y quién atendió. Un trabajo ya
/// cobrado se puede reabrir anulando el cobro.
class HistoryView extends StatefulWidget {
  final Business business;
  final ServiceTemplate template;

  const HistoryView({super.key, required this.business, required this.template});

  @override
  State<HistoryView> createState() => _HistoryViewState();
}

class _HistoryViewState extends State<HistoryView> {
  final _repo = ServicesRepository.instance;
  final _query = TextEditingController();
  Timer? _debounce;
  List<WorkOrder> _orders = const [];
  Map<String, String> _staffNames = const {};
  bool _loading = true;

  ServiceTemplate get _t => widget.template;

  @override
  void initState() {
    super.initState();
    _repo.getStaff(widget.business.id, includeInactive: true).then((list) {
      if (mounted) setState(() => _staffNames = {for (final s in list) s.id: s.name});
    });
    _search('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () => _search(v));
  }

  Future<void> _search(String v) async {
    final found = await _repo.searchHistory(widget.business.id, v);
    if (mounted) {
      setState(() {
        _orders = found;
        _loading = false;
      });
    }
  }

  Future<void> _reopen(WorkOrder o) async {
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AppDialog(
title: '¿Anular el cobro de ${o.title}?',
content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Se anulan sus ventas (y el fiado, si lo hubo) y vuelve al tablero como listo para cobrar.'),
            TextField(
              controller: note,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Motivo (queda en la actividad)'),
            ),
          ],
        ),
actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Volver')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Anular cobro')),
        ],
),
    );
    final text = note.text;
    note.dispose();
    if (ok != true) return;
    try {
      await _repo.reopenPaid(o, note: text);
      if (mounted) AppToast.showSuccess(context, 'Cobro anulado. ${o.title} volvió al tablero.');
      await _search(_query.text);
    } catch (e) {
      if (mounted) AppToast.showError(context, '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final paid = _orders.where((o) => o.status == WorkOrder.delivered);
    final spent = paid.fold(0.0, (s, o) => s + o.total);
    final hint = [
      if (_t.identifierLabel != null) _t.identifierLabel!.toLowerCase(),
      'nombre',
      'teléfono',
    ].join(', ');

    return ContentWidth(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.xs, AppSpace.lg, AppSpace.xxl),
        children: [
          TextField(
            controller: _query,
            onChanged: _onChanged,
            decoration: InputDecoration(hintText: 'Buscar por $hint', prefixIcon: const Icon(Icons.search_outlined)),
          ),
          const SizedBox(height: AppSpace.md),
          if (_query.text.trim().isNotEmpty && _orders.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.sm),
              child: Text(
                '${_orders.length} ${_orders.length == 1 ? 'visita' : 'visitas'} · gastó ${CurrencyFormatter.format(spent)}',
                style: TextStyle(fontWeight: FontWeight.w600, color: c.ink),
              ),
            ),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (_orders.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpace.xxl),
              child: Text(
                _query.text.trim().isEmpty ? 'Aún no hay trabajos.' : 'No encontramos nada con esa búsqueda.',
                textAlign: TextAlign.center,
                style: TextStyle(color: c.inkMuted),
              ),
            ),
          for (final o in _orders) ...[
            AppCard(
              padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.md, AppSpace.sm, AppSpace.md),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          [
                            o.title,
                            if (o.vehicleKind != null) _t.vehicleLabel(o.vehicleKind),
                            if ((o.customerName ?? '').isNotEmpty && o.customerName != o.title) o.customerName!,
                          ].join(' · '),
                          style: TextStyle(fontWeight: FontWeight.w700, color: c.ink),
                        ),
                        Text(
                          '${o.createdAt.day}/${o.createdAt.month}/${o.createdAt.year} · ${o.statusLabelFor(_t)}',
                          style: TextStyle(fontSize: AppText.sizeCaption, color: c.inkMuted),
                        ),
                        const SizedBox(height: 2),
                        for (final l in o.lines)
                          Text(
                            '${l.name}${l.staffIds.isEmpty ? '' : ' · ${l.staffIds.map((id) => _staffNames[id] ?? 'Empleado').join(', ')}'}',
                            style: TextStyle(fontSize: AppText.sizeSmall, color: c.ink),
                          ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(CurrencyFormatter.format(o.isPaid ? o.total : o.subtotal),
                          style: TextStyle(fontWeight: FontWeight.w700, color: c.ink)),
                      if (o.isPaid && o.status == WorkOrder.delivered)
                        TextButton(onPressed: () => _reopen(o), child: const Text('Anular cobro')),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpace.sm),
          ],
        ],
      ),
    );
  }
}
