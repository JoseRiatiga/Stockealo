import 'package:flutter/material.dart';

import '../../../../core/design/app_card.dart';
import '../../../../core/design/content_width.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../business/models/business.dart';
import '../../data/commissions_repository.dart';
import '../../data/services_repository.dart';
import '../../models/commission_models.dart';
import '../../models/service_models.dart';

/// Periodo para ver lo pendiente
enum CommissionPeriod {
  today('Hoy'),
  week('Esta semana'),
  month('Este mes'),
  all('Todo lo pendiente');

  final String label;
  const CommissionPeriod(this.label);

  /// Desde y hasta (sin incluir) para el periodo; null = sin límite
  (DateTime?, DateTime?) range(DateTime now) {
    final day = DateTime(now.year, now.month, now.day);
    return switch (this) {
      today => (day, day.add(const Duration(days: 1))),
      week => (day.subtract(Duration(days: day.weekday - 1)), day.add(const Duration(days: 1))),
      month => (DateTime(now.year, now.month), day.add(const Duration(days: 1))),
      all => (null, null),
    };
  }
}

/// Servicios › Comisiones y liquidaciones: lo pendiente de cada persona, pagar
/// (queda como pagado) y enviar el detalle por WhatsApp. Debajo, los pagos hechos.
class CommissionsView extends StatefulWidget {
  final Business business;

  const CommissionsView({super.key, required this.business});

  @override
  State<CommissionsView> createState() => _CommissionsViewState();
}

class _CommissionsViewState extends State<CommissionsView> {
  final _repo = CommissionsRepository.instance;
  CommissionPeriod _period = CommissionPeriod.all;
  List<StaffEarnings> _pending = const [];
  List<StaffPayout> _payouts = const [];
  Map<String, StaffMember> _staff = const {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final (from, to) = _period.range(DateTime.now());
    final results = await Future.wait([
      _repo.pending(widget.business.id, from: from, to: to),
      _repo.payouts(widget.business.id, limit: 20),
      ServicesRepository.instance.getStaff(widget.business.id, includeInactive: true),
    ]);
    if (!mounted) return;
    setState(() {
      _pending = (results[0] as List<StaffEarnings>)..sort((a, b) => b.total.compareTo(a.total));
      _payouts = results[1] as List<StaffPayout>;
      _staff = {for (final s in results[2] as List<StaffMember>) s.id: s};
      _loading = false;
    });
  }

  String _name(String id) => _staff[id]?.name ?? 'Persona eliminada';

  Future<void> _pay(StaffEarnings e) async {
    final name = _name(e.staffId);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('¿Pagar ${CurrencyFormatter.format(e.total)} a $name?'),
        content: Text(
          '${e.services} ${e.services == 1 ? 'servicio' : 'servicios'} · comisiones ${CurrencyFormatter.format(e.commissions)}'
          '${e.tips != 0 ? ' · propinas ${CurrencyFormatter.format(e.tips)}' : ''}.\n\n'
          'Queda como pagado y ya no aparece pendiente.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Marcar como pagado')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _repo.pay(widget.business.id, e, staffName: name);
      if (!mounted) return;
      final staff = _staff[e.staffId];
      if (staff != null) {
        final send = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Pago registrado'),
            content: Text('¿Le envías el detalle a $name por WhatsApp?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Enviar')),
            ],
          ),
        );
        if (send == true) {
          await CommissionsRepository.sendDetail(staff: staff, business: widget.business, earnings: e, paid: true);
        }
      }
    } on StateError catch (err) {
      if (mounted) AppToast.showWarning(context, err.message);
    }
    await _load();
  }

  Future<void> _detail(StaffEarnings e) async {
    final staff = _staff[e.staffId];
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) {
        final c = ctx.colors;
        return ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(AppSpace.lg, 0, AppSpace.lg, AppSpace.lg),
          children: [
            Text(_name(e.staffId), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c.ink)),
            Text('Pendiente: ${CurrencyFormatter.format(e.total)}', style: TextStyle(color: c.inkMuted)),
            const SizedBox(height: AppSpace.md),
            for (final item in e.items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${item.date.day}/${item.date.month} · ${item.label}'
                        '${item.kind == Commission.kindService ? ' (${item.pct.toStringAsFixed(item.pct % 1 == 0 ? 0 : 1)} % de ${CurrencyFormatter.format(item.base)})' : ''}',
                        style: TextStyle(fontSize: 13, color: c.ink),
                      ),
                    ),
                    Text(CurrencyFormatter.format(item.amount),
                        style: TextStyle(color: item.amount < 0 ? c.danger : c.ink, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            const SizedBox(height: AppSpace.lg),
            if (staff != null)
              OutlinedButton.icon(
                onPressed: () => CommissionsRepository.sendDetail(staff: staff, business: widget.business, earnings: e),
                icon: const Icon(Icons.chat_outlined, size: 18),
                label: const Text('Enviar detalle por WhatsApp'),
              ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (_loading) return const Center(child: CircularProgressIndicator());
    final total = _pending.fold(0.0, (s, e) => s + e.total);

    return RefreshIndicator(
      onRefresh: _load,
      child: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.xs, AppSpace.lg, AppSpace.xxl),
          children: [
            Text('Cada servicio cobrado suma la comisión de quien lo hizo. Paga al final del día, la semana o el mes.',
                style: TextStyle(fontSize: 13, color: c.inkMuted)),
            const SizedBox(height: AppSpace.md),
            Wrap(
              spacing: AppSpace.sm,
              runSpacing: AppSpace.sm,
              children: [
                for (final p in CommissionPeriod.values)
                  ChoiceChip(
                    label: Text(p.label),
                    selected: _period == p,
                    onSelected: (_) {
                      setState(() => _period = p);
                      _load();
                    },
                  ),
              ],
            ),
            const SizedBox(height: AppSpace.md),
            if (_pending.isEmpty)
              AppCard(child: Text('No hay nada pendiente por pagar en este periodo.', style: TextStyle(color: c.inkMuted)))
            else ...[
              Text('Pendiente: ${CurrencyFormatter.format(total)}',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.ink)),
              const SizedBox(height: AppSpace.sm),
              for (final e in _pending) ...[
                AppCard(
                  onTap: () => _detail(e),
                  padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.md, AppSpace.sm, AppSpace.md),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_name(e.staffId), style: TextStyle(fontWeight: FontWeight.w700, color: c.ink)),
                            Text(
                              '${e.services} ${e.services == 1 ? 'servicio' : 'servicios'} · comisiones ${CurrencyFormatter.format(e.commissions)}'
                              '${e.tips != 0 ? ' · propinas ${CurrencyFormatter.format(e.tips)}' : ''}',
                              style: TextStyle(fontSize: 12.5, color: c.inkMuted),
                            ),
                          ],
                        ),
                      ),
                      Text(CurrencyFormatter.format(e.total), style: TextStyle(fontWeight: FontWeight.w700, color: c.ink)),
                      const SizedBox(width: AppSpace.sm),
                      FilledButton(onPressed: e.total <= 0 ? null : () => _pay(e), child: const Text('Pagar')),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpace.sm),
              ],
            ],
            if (_payouts.isNotEmpty) ...[
              const SizedBox(height: AppSpace.lg),
              Text('Pagos hechos', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.ink)),
              const SizedBox(height: AppSpace.sm),
              for (final p in _payouts)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${p.paidAt.day}/${p.paidAt.month}/${p.paidAt.year} · ${_name(p.staffId)}',
                          style: TextStyle(color: c.ink),
                        ),
                      ),
                      Text(CurrencyFormatter.format(p.total), style: TextStyle(color: c.ink, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
