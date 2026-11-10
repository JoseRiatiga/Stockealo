import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/design/app_card.dart';
import '../../../../core/services/data_events.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../business/models/business.dart';
import '../../data/cash_register_repository.dart';
import '../../models/cash_session.dart';

/// Inicio: estado de la caja en una línea («Caja abierta desde 8:05 · $230.000 en
/// efectivo»). Es solo una cifra: al tocarla lleva a Ventas, donde vive la caja.
class CashStatusCard extends StatefulWidget {
  final Business business;
  final VoidCallback onTap;

  const CashStatusCard({super.key, required this.business, required this.onTap});

  @override
  State<CashStatusCard> createState() => _CashStatusCardState();
}

class _CashStatusCardState extends State<CashStatusCard> {
  CashSession? _open;
  CashSummary? _summary;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    DataEvents.instance.salesVersion.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    DataEvents.instance.salesVersion.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final repo = CashRegisterRepository.instance;
    final open = await repo.getOpenSession(widget.business.id);
    final summary = open == null ? null : await repo.summarize(open);
    if (!mounted) return;
    setState(() {
      _open = open;
      _summary = summary;
      _loaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();
    final c = context.colors;
    final open = _open;
    final stale = open?.isStale() ?? false;
    final text = open == null
        ? 'Caja cerrada · ábrela en Ventas antes de cobrar en efectivo'
        : stale
            ? 'La caja quedó abierta desde el ${DateFormat('d MMM', 'es_CO').format(open.openedAt)}: ciérrala en Ventas'
            : 'Caja abierta desde las ${DateFormat('h:mm a', 'es_CO').format(open.openedAt)} · '
                '${CurrencyFormatter.format(_summary?.expected ?? open.openingAmount)} en efectivo';
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.lg),
      child: AppCard(
        color: open == null || stale ? c.warningSoft : null,
        onTap: widget.onTap,
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.md),
        child: Row(
          children: [
            Icon(open == null ? Icons.lock_outline_rounded : Icons.point_of_sale_rounded,
                color: open == null || stale ? c.warning : c.success),
            const SizedBox(width: AppSpace.md),
            Expanded(child: Text(text, style: TextStyle(color: c.ink, fontWeight: FontWeight.w600))),
            Icon(Icons.chevron_right_rounded, color: c.inkFaint),
          ],
        ),
      ),
    );
  }
}

/// Aviso al cobrar en efectivo con la caja cerrada (la venta no se bloquea)
const kCashClosedWarning =
    'Venta registrada, pero la caja está cerrada: ábrela en Ventas › Caja para que el efectivo entre en el arqueo.';

/// ¿El negocio usa el arqueo, se cobró en efectivo y no hay caja abierta?
Future<bool> isCashClosedFor(Business? business, String paymentMethod) async {
  if (business == null || !business.cashRegisterEnabled || paymentMethod.toUpperCase() != 'EFECTIVO') return false;
  return await CashRegisterRepository.instance.getOpenSession(business.id) == null;
}
