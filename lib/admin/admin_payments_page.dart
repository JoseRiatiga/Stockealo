import 'package:flutter/material.dart';

import '../core/theme/app_tokens.dart';
import '../core/utils/currency_formatter.dart';
import '../features/pro/data/pro_admin_service.dart';
import 'admin_user_detail.dart';
import 'admin_widgets.dart';

/// Pagos en línea con Wompi: quién pagó, qué plan, cuánto y cómo quedó
class AdminPaymentsPage extends StatefulWidget {
  const AdminPaymentsPage({super.key});

  @override
  State<AdminPaymentsPage> createState() => _AdminPaymentsPageState();
}

class _AdminPaymentsPageState extends State<AdminPaymentsPage> {
  List<AdminPayment> _payments = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final payments = await ProAdminService.instance.listPayments();
      if (mounted) setState(() => _payments = payments);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final approved = _payments.where((p) => p.status == 'APPROVED');
    final total = approved.fold<double>(0, (s, p) => s + p.amount);
    final state = AdminLoadState(
      loading: _loading,
      error: _error,
      empty: _payments.isEmpty,
      emptyText: 'Todavía no hay pagos en línea',
      emptyDetail: 'Aquí aparecen los pagos con Wompi. Los pagos por Nequi con comprobante se ven en Códigos.',
      emptyIcon: Icons.payments_outlined,
      onRetry: _load,
    );
    return AdminPage(
      title: 'Pagos',
      subtitle: _loading
          ? null
          : '${approved.length} aprobados · ${CurrencyFormatter.formatIn(total, 'COP')} en total (antes de la comisión de Wompi)',
      onRefresh: _load,
      children: [
        if (state.blocking)
          state
        else
          for (final p in _payments) _row(c, p),
      ],
    );
  }

  /// Un pago: monto, estado, plan y negocio; tocarlo abre la ficha de quien pagó
  Widget _row(StockealoColors c, AdminPayment p) {
    final state = adminPaymentState(p.status, p.createdAt);
    return AdminCard(
      padding: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.card),
        onTap: p.userEmail.isEmpty ? null : () => AdminUserDetailDialog.show(context, p.userEmail),
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.lg),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: AppSpace.sm,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(CurrencyFormatter.formatIn(p.amount, p.currency), style: AppText.amount(context, size: 16, color: c.ink)),
                        AdminBadge(state.label, tone: state.tone),
                      ],
                    ),
                    Text(
                      [p.planLabel, p.businessName ?? 'negocio eliminado', if (p.paymentMethod != null) p.methodLabel].join(' · '),
                      overflow: TextOverflow.ellipsis,
                      style: AppText.small(context, color: c.inkMuted),
                    ),
                    Text('${p.userEmail} · ${adminWhen(p.createdAt)} · ${p.reference}',
                        overflow: TextOverflow.ellipsis, style: AppText.caption(context, color: c.inkFaint)),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Copiar referencia',
                onPressed: () => adminCopy(context, p.reference, 'Referencia'),
                icon: Icon(Icons.copy_outlined, size: 18, color: c.inkMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
