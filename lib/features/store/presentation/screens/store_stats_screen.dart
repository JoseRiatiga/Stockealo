import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/design/app_card.dart';
import '../../../../core/design/filter_tabs.dart';
import '../../../../core/design/stat_card.dart';
import '../../../../core/design/status_pill.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../business/models/business.dart';
import '../../data/online_store_service.dart';

/// Estadísticas de la tienda en línea (0.16.0, fase 4): visitas, pedidos, cuántas
/// visitas piden, lo más pedido, lo que se agrega al carrito y de dónde llegan.
class StoreStatsScreen extends StatefulWidget {
  final Business business;

  /// Para las pruebas: de dónde salen los números (por defecto, la nube)
  final Future<StoreStats> Function(DateTime from, DateTime to)? loader;
  final DateTime? now;

  const StoreStatsScreen({super.key, required this.business, this.loader, this.now});

  static Future<void> open(BuildContext context, Business business) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => StoreStatsScreen(business: business)));

  @override
  State<StoreStatsScreen> createState() => _StoreStatsScreenState();
}

class _StoreStatsScreenState extends State<StoreStatsScreen> {
  int _days = 7;
  StoreStats? _stats;
  StoreStats? _before;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<StoreStats> _fetch(DateTime from, DateTime to) =>
      (widget.loader ?? (f, t) => OnlineStoreService.instance.stats(widget.business.id, from: f, to: t))(from, to);

  Future<void> _load() async {
    setState(() {
      _stats = null;
      _error = null;
    });
    final now = widget.now ?? DateTime.now();
    final to = DateTime(now.year, now.month, now.day);
    final from = to.subtract(Duration(days: _days - 1));
    try {
      final current = await _fetch(from, to);
      final before = await _fetch(from.subtract(Duration(days: _days)), from.subtract(const Duration(days: 1)));
      if (mounted) {
        setState(() {
          _stats = current;
          _before = before;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  String _money(double v) => CurrencyFormatter.format(v.round());

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.paper,
      appBar: AppBar(title: const Text('Estadísticas de la tienda')),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpace.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error!, textAlign: TextAlign.center, style: AppText.body(context, color: c.inkMuted)),
                    const SizedBox(height: AppSpace.md),
                    OutlinedButton(onPressed: _load, child: const Text('Reintentar')),
                  ],
                ),
              ),
            )
          : _stats == null
              ? const Center(child: CircularProgressIndicator())
              : _body(context, _stats!),
    );
  }

  Widget _body(BuildContext context, StoreStats s) {
    final c = context.colors;
    final before = _before;
    final delta = before == null || before.visits == 0 ? null : (s.visits - before.visits) / before.visits;
    final conversion = s.conversion;
    final left = s.adds - s.orders;
    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.md, AppSpace.lg, AppSpace.xxl * 2),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(child: Text('Últimos $_days días', style: AppText.title(context))),
                    FilterTabs<int>(
                      options: const {7: '7 días', 30: '30 días'},
                      value: _days,
                      onChanged: (d) {
                        setState(() => _days = d);
                        _load();
                      },
                    ),
                  ],
                ),
                const SizedBox(height: AppSpace.md),
                LayoutBuilder(
                  builder: (context, box) {
                    final w = (box.maxWidth - AppSpace.sm) / 2;
                    Widget card(String title, String value, {String? detail, String? delta, AppTone tone = AppTone.neutral}) => SizedBox(
                          width: w,
                          child: StatCard(title: title, value: value, detail: detail, delta: delta, deltaTone: tone, compact: true),
                        );
                    return Wrap(
                      spacing: AppSpace.sm,
                      runSpacing: AppSpace.sm,
                      children: [
                        card(
                          'Visitas',
                          '${s.visits}',
                          delta: delta == null ? null : '${delta >= 0 ? '+' : ''}${(delta * 100).round()} % que antes',
                          tone: delta == null ? AppTone.neutral : (delta >= 0 ? AppTone.success : AppTone.warning),
                        ),
                        card('Pedidos', '${s.orders}', detail: _money(s.total)),
                        card(
                          'Visitas que piden',
                          conversion == null ? '—' : '${(conversion * 100).toStringAsFixed(1).replaceAll('.', ',')} %',
                          detail: '${s.orders} de ${s.visits}',
                        ),
                        card('Agregaron al carrito', '${s.adds}', detail: left > 0 ? '$left no terminaron' : null),
                      ],
                    );
                  },
                ),
                const SizedBox(height: AppSpace.md),
                AppCard(child: _DaysChart(days: s.days)),
                const SizedBox(height: AppSpace.md),
                _list(
                  context,
                  'Lo más pedido',
                  s.topOrdered.isEmpty
                      ? [Text('Todavía no hay pedidos en estos días.', style: AppText.body(context, color: c.inkMuted))]
                      : [
                          for (final i in s.topOrdered)
                            _row(context, i.name, '${i.quantity.round()} und. · ${_money(i.total)}'),
                        ],
                ),
                const SizedBox(height: AppSpace.md),
                _list(
                  context,
                  'Lo que más se agrega al carrito',
                  s.topAdded.isEmpty
                      ? [Text('Nadie ha agregado productos en estos días.', style: AppText.body(context, color: c.inkMuted))]
                      : [
                          for (final i in s.topAdded)
                            _row(context, i.name, '${i.quantity.round()} ${i.quantity == 1 ? 'vez' : 'veces'} · ${s.orderedOf(i.productId).round()} pedidos'),
                          const SizedBox(height: AppSpace.xs),
                          Text('Si se agrega mucho y se pide poco, revisa el precio o la foto.',
                              style: AppText.small(context, color: c.inkMuted)),
                        ],
                ),
                const SizedBox(height: AppSpace.md),
                _list(context, 'De dónde llegan', [
                  _row(context, 'Links de productos compartidos', '${s.fromShared} visitas'),
                  _row(context, 'QR del mostrador', '${s.fromQr} visitas'),
                  const SizedBox(height: AppSpace.xs),
                  Text('No guardamos datos de quién visita: solo se cuentan las visitas, una vez por visita.',
                      style: AppText.small(context, color: c.inkMuted)),
                ]),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _list(BuildContext context, String title, List<Widget> children) => AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: AppText.title(context)),
            const SizedBox(height: AppSpace.sm),
            ...children,
          ],
        ),
      );

  Widget _row(BuildContext context, String name, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpace.xs + 2),
        child: Row(
          children: [
            Expanded(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.body(context))),
            const SizedBox(width: AppSpace.sm),
            Text(value, style: AppText.small(context, color: context.colors.inkMuted)),
          ],
        ),
      );
}

/// Visitas por día (barras) y pedidos (puntos)
class _DaysChart extends StatelessWidget {
  final List<StoreStatsDay> days;
  const _DaysChart({required this.days});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final top = days.fold<int>(1, (m, d) => d.visits > m ? d.visits : m);
    final topOrders = days.fold<int>(1, (m, d) => d.orders > m ? d.orders : m);
    final many = days.length > 10;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 140,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final d in days)
                Expanded(
                  child: Tooltip(
                    message: '${DateFormat("d 'de' MMM", 'es_CO').format(d.day)}: ${d.visits} visitas, ${d.orders} pedidos',
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: many ? 1 : AppSpace.xs),
                      child: Stack(
                        alignment: Alignment.bottomCenter,
                        children: [
                          FractionallySizedBox(
                            heightFactor: d.visits == 0 ? 0.02 : d.visits / top,
                            child: Container(
                              decoration: BoxDecoration(
                                color: c.accent.withValues(alpha: 0.35),
                                borderRadius: BorderRadius.circular(AppRadius.small / 2),
                              ),
                            ),
                          ),
                          if (d.orders > 0)
                            Align(
                              alignment: Alignment(0, 1 - 1.6 * (d.orders / topOrders) * 0.6),
                              child: Container(
                                width: many ? 5 : 8,
                                height: many ? 5 : 8,
                                decoration: BoxDecoration(color: c.accent, shape: BoxShape.circle),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.xs),
        Row(
          children: [
            for (final (i, d) in days.indexed)
              Expanded(
                child: Text(
                  many ? (i % 5 == 0 ? '${d.day.day}' : '') : DateFormat('E', 'es_CO').format(d.day).substring(0, 1).toUpperCase(),
                  textAlign: TextAlign.center,
                  style: AppText.caption(context, color: c.inkFaint),
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpace.sm),
        const Wrap(
          spacing: AppSpace.md,
          children: [
            StatusPill('Barras: visitas', compact: true),
            StatusPill('Puntos: pedidos', tone: AppTone.accent, compact: true),
          ],
        ),
      ],
    );
  }
}
