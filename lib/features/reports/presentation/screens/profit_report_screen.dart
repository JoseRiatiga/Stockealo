import 'package:flutter/material.dart';

import '../../../../core/theme/app_tokens.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../business/models/business.dart';
import '../../../profile/presentation/widgets/settings_cards.dart';
import '../../data/profit_report_repository.dart';

/// Reporte de ganancias y pérdidas del negocio por periodo
class ProfitReportScreen extends StatefulWidget {
  final Business business;

  /// Fecha de referencia de los periodos (solo para pruebas); por defecto, ahora
  final DateTime? now;

  const ProfitReportScreen({super.key, required this.business, this.now});

  static Future<void> open(BuildContext context, Business business) {
    return Navigator.push(context, MaterialPageRoute(builder: (_) => ProfitReportScreen(business: business)));
  }

  @override
  State<ProfitReportScreen> createState() => _ProfitReportScreenState();
}

class _ProfitReportScreenState extends State<ProfitReportScreen> {
  ReportPeriod _period = ReportPeriod.month;
  late Future<ProfitReport> _report = _load();

  Future<ProfitReport> _load() => ProfitReportRepository.instance.build(widget.business.id, _period, now: widget.now);

  void _select(ReportPeriod period) {
    if (period == _period) return;
    setState(() {
      _period = period;
      _report = _load();
    });
  }

  String _money(num value) => CurrencyFormatter.formatIn(value, widget.business.currency);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.paper,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.md, AppSpace.lg, AppSpace.sm),
                  child: Row(
                    children: [
                      _BackButton(onTap: () => Navigator.pop(context)),
                      const SizedBox(width: AppSpace.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Ganancias y pérdidas',
                                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: c.ink)),
                            Text(widget.business.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 13, color: c.inkMuted)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  height: 48,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.xs),
                    itemCount: ReportPeriod.values.length,
                    separatorBuilder: (_, __) => const SizedBox(width: AppSpace.sm),
                    itemBuilder: (_, i) {
                      final period = ReportPeriod.values[i];
                      return ChoiceChip(
                        label: Text(period.label),
                        selected: period == _period,
                        onSelected: (_) => _select(period),
                      );
                    },
                  ),
                ),
                Expanded(
                  child: FutureBuilder<ProfitReport>(
                    future: _report,
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return const _Message(
                          icon: Icons.error_outline_rounded,
                          title: 'No se pudo armar el reporte',
                          body: 'Intenta de nuevo en un momento.',
                        );
                      }
                      final report = snapshot.data;
                      if (report == null) return const Center(child: CircularProgressIndicator());
                      if (report.isEmpty) {
                        return const _Message(
                          icon: Icons.insights_rounded,
                          title: 'Sin movimientos en este periodo',
                          body: 'Cuando registres ventas, aquí verás cuánto ganaste y en qué se fue el dinero.',
                        );
                      }
                      return _content(report);
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _content(ProfitReport r) {
    final c = context.colors;
    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.md, AppSpace.lg, AppSpace.xxl),
      children: [
        _hero(r),
        const SizedBox(height: AppSpace.xl),
        SettingsPanel(
          label: 'Cómo se calcula',
          child: Column(
            children: [
              _line('Ventas', _money(r.revenue), hint: '${r.salesCount} ${r.salesCount == 1 ? 'venta' : 'ventas'}'),
              _line('Costo de lo vendido', '− ${_money(r.cost)}'),
              _divider(),
              _line('Ganancia bruta', _money(r.grossProfit), strong: true),
              if (r.shrinkageLoss > 0) _line('Mermas', '− ${_money(r.shrinkageLoss)}', color: c.danger),
              _divider(),
              _line('Ganancia neta', _money(r.netProfit), strong: true, color: r.netProfit < 0 ? c.danger : c.success),
              if (r.discounts > 0)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpace.sm),
                  child: Text(
                    'Diste ${_money(r.discounts)} en descuentos (ya restados de las ventas).',
                    style: TextStyle(fontSize: 12.5, color: c.inkMuted),
                  ),
                ),
            ],
          ),
        ),
        SettingsPanel(
          label: 'Pérdidas',
          child: r.belowCostLoss == 0 && r.shrinkageLoss == 0
              ? Row(
                  children: [
                    Icon(Icons.check_circle_rounded, color: c.success, size: 20),
                    const SizedBox(width: AppSpace.sm),
                    Expanded(child: Text('Sin pérdidas en este periodo', style: TextStyle(color: c.ink))),
                  ],
                )
              : Column(
                  children: [
                    if (r.belowCostLoss > 0)
                      _line('Ventas por debajo del costo', _money(r.belowCostLoss),
                          hint: 'Revisa el precio de esos productos', color: c.danger),
                    if (r.shrinkageLoss > 0)
                      _line('Mermas (daños, vencidos, pérdidas)', _money(r.shrinkageLoss),
                          hint: '${r.shrinkageUnits} ${r.shrinkageUnits == 1 ? 'unidad' : 'unidades'} a costo actual',
                          color: c.danger),
                  ],
                ),
        ),
        if (r.byPaymentMethod.isNotEmpty)
          SettingsPanel(
            label: 'Cómo te pagaron',
            child: Column(
              children: [
                for (final entry in r.byPaymentMethod.entries) _methodBar(entry.key, entry.value, r.revenue),
                if (r.creditPending > 0 || r.debtCollected > 0) ...[
                  const SizedBox(height: AppSpace.xs),
                  _divider(),
                  if (r.creditPending > 0) _line('Fiado de este periodo sin cobrar', _money(r.creditPending), color: c.warning),
                  if (r.debtCollected > 0) _line('Abonos de fiados recibidos', _money(r.debtCollected), color: c.success),
                ],
              ],
            ),
          ),
        if (r.topProducts.isNotEmpty)
          SettingsPanel(
            label: 'Lo que más te dejó',
            child: Column(children: [for (final p in r.topProducts) _productRow(p)]),
          ),
        if (r.lowMarginProducts.isNotEmpty)
          SettingsPanel(
            label: 'Margen bajo (menos de 15%)',
            child: Column(children: [for (final p in r.lowMarginProducts) _productRow(p, warn: true)]),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
          child: Text(
            'No incluye gastos como arriendo, servicios o sueldos. Las mermas se calculan con el costo actual de cada producto.',
            style: TextStyle(fontSize: 12, height: 1.4, color: c.inkFaint),
          ),
        ),
      ],
    );
  }

  Widget _hero(ProfitReport r) {
    final c = context.colors;
    final change = r.change;
    final up = (change ?? 0) >= 0;
    return Container(
      padding: const EdgeInsets.all(AppSpace.xl),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Ganancia neta · ${_period.label.toLowerCase()}', style: TextStyle(fontSize: 13, color: c.inkMuted)),
          const SizedBox(height: AppSpace.xs),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              _money(r.netProfit),
              style: AppText.amount(context, size: 34, weight: FontWeight.w800, color: r.netProfit < 0 ? c.danger : c.ink),
            ),
          ),
          const SizedBox(height: AppSpace.sm),
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.xs,
            children: [
              _pill('Margen ${r.margin.toStringAsFixed(0)}%', c.surfaceMuted, c.inkMuted),
              if (change != null)
                _pill(
                  '${up ? '↑' : '↓'} ${change.abs().toStringAsFixed(0)}% vs ${_period.compareLabel}',
                  (up ? c.success : c.danger).withOpacity(0.12),
                  up ? c.success : c.danger,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _pill(String text, Color background, Color foreground) => Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm + 2, vertical: 4),
        decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(AppRadius.pill)),
        child: Text(text, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: foreground)),
      );

  Widget _divider() => Divider(height: AppSpace.lg, color: context.colors.line);

  Widget _line(String label, String amount, {String? hint, bool strong = false, Color? color}) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(fontSize: 14.5, fontWeight: strong ? FontWeight.w700 : FontWeight.w500, color: c.ink)),
                if (hint != null) Text(hint, style: TextStyle(fontSize: 12.5, color: c.inkMuted)),
              ],
            ),
          ),
          const SizedBox(width: AppSpace.md),
          Text(
            amount,
            style: AppText.amount(context, size: strong ? 16 : 14.5, weight: strong ? FontWeight.w800 : FontWeight.w600, color: color),
          ),
        ],
      ),
    );
  }

  static String _methodLabel(String method) => switch (method.toUpperCase()) {
        'EFECTIVO' => 'Efectivo',
        'TRANSFERENCIA' => 'Transferencia',
        'FIADO' => 'Fiado',
        'TARJETA' => 'Tarjeta',
        _ => method.isEmpty ? 'Otro' : method[0].toUpperCase() + method.substring(1).toLowerCase(),
      };

  Widget _methodBar(String method, double amount, double total) {
    final c = context.colors;
    final share = total > 0 ? (amount / total).clamp(0.0, 1.0) : 0.0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.xs + 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(_methodLabel(method), style: TextStyle(fontSize: 14.5, color: c.ink))),
              Text('${(share * 100).toStringAsFixed(0)}%  ', style: TextStyle(fontSize: 12.5, color: c.inkMuted)),
              Text(_money(amount), style: AppText.amount(context, size: 14.5)),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: LinearProgressIndicator(
              value: share,
              minHeight: 6,
              backgroundColor: c.surfaceMuted,
              valueColor: AlwaysStoppedAnimation(method.toUpperCase() == 'FIADO' ? c.warning : c.accent),
            ),
          ),
        ],
      ),
    );
  }

  Widget _productRow(ProductProfit p, {bool warn = false}) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.xs + 2),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: c.ink)),
                Text(
                  '${p.quantity} ${p.quantity == 1 ? 'unidad' : 'unidades'} · margen ${p.margin.toStringAsFixed(0)}%',
                  style: TextStyle(fontSize: 12.5, color: warn ? c.warning : c.inkMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpace.md),
          Text(_money(p.profit), style: AppText.amount(context, size: 14.5, color: p.profit < 0 ? c.danger : null)),
        ],
      ),
    );
  }
}

class _BackButton extends StatelessWidget {
  final VoidCallback onTap;

  const _BackButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Tooltip(
      message: 'Volver',
      child: Semantics(
        button: true,
        label: 'Volver',
        child: InkResponse(
          onTap: onTap,
          radius: 24,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: c.surface, shape: BoxShape.circle, border: Border.all(color: c.line)),
            child: Icon(Icons.arrow_back_rounded, color: c.ink, size: 22),
          ),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _Message({required this.icon, required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: c.inkFaint),
            const SizedBox(height: AppSpace.md),
            Text(title, textAlign: TextAlign.center, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: c.ink)),
            const SizedBox(height: AppSpace.xs),
            Text(body, textAlign: TextAlign.center, style: TextStyle(fontSize: 14, height: 1.4, color: c.inkMuted)),
          ],
        ),
      ),
    );
  }
}
