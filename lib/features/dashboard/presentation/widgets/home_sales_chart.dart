import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_tokens.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../data/home_data.dart';

/// Gráfico «Ventas de los últimos 14 días» del Inicio: barras grises, la de hoy en
/// el color del negocio y la mejor en gris oscuro. Al pasar el puntero o tocar una
/// barra se ve el día, lo vendido y cuántas ventas.
class HomeSalesChart extends StatefulWidget {
  final List<HomeBar> bars;
  final HomeRange range;
  final ValueChanged<HomeRange> onRange;

  const HomeSalesChart({super.key, required this.bars, required this.range, required this.onRange});

  @override
  State<HomeSalesChart> createState() => _HomeSalesChartState();
}

class _HomeSalesChartState extends State<HomeSalesChart> {
  int? _hover;

  String get _title => switch (widget.range) {
        HomeRange.days14 => 'Ventas de los últimos 14 días',
        HomeRange.month => 'Ventas de este mes',
        HomeRange.year => 'Ventas de los últimos 12 meses',
      };

  String _label(HomeBar b) {
    if (widget.range == HomeRange.year) {
      return toBeginningOfSentenceCase(DateFormat('MMMM y', 'es_CO').format(b.start));
    }
    if (b.current) return 'Hoy';
    return toBeginningOfSentenceCase(DateFormat('EEEE d MMM', 'es_CO').format(b.start));
  }

  String _axis(HomeBar b) {
    if (b.current) return widget.range == HomeRange.year ? 'Este mes' : 'Hoy';
    return widget.range == HomeRange.year
        ? DateFormat('MMM', 'es_CO').format(b.start)
        : DateFormat('d MMM', 'es_CO').format(b.start);
  }

  @override
  void didUpdateWidget(covariant HomeSalesChart old) {
    super.didUpdateWidget(old);
    if (old.range != widget.range) _hover = null;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final bars = widget.bars;
    final max = bars.fold<double>(0, (m, b) => b.total > m ? b.total : m);
    final best = max <= 0 ? -1 : bars.indexWhere((b) => b.total == max && !b.current);
    final shown = _hover ?? (bars.isEmpty ? null : bars.length - 1);
    final total = bars.fold<double>(0, (s, b) => s + b.total);

    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: c.line),
      ),
      padding: const EdgeInsets.all(AppSpace.lg + 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpace.md,
            runSpacing: AppSpace.sm,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_title, style: AppText.title(context)),
                  Text('En total ${CurrencyFormatter.format(total)} · hoy en color', style: AppText.small(context)),
                ],
              ),
              _RangeSwitch(value: widget.range, onChanged: widget.onRange),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          // Detalle de la barra señalada (o de hoy)
          SizedBox(
            height: 40,
            child: shown == null
                ? null
                : Semantics(
                    liveRegion: true,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_label(bars[shown]), style: AppText.small(context, weight: FontWeight.w700, color: c.ink)),
                        Text(
                          '${CurrencyFormatter.format(bars[shown].total)} · ${bars[shown].count} ${bars[shown].count == 1 ? 'venta' : 'ventas'}',
                          style: AppText.small(context),
                        ),
                      ],
                    ),
                  ),
          ),
          const SizedBox(height: AppSpace.sm),
          SizedBox(
            height: 180,
            child: LayoutBuilder(
              builder: (context, box) {
                final gap = bars.length > 20 ? 3.0 : 8.0;
                return MouseRegion(
                  onExit: (_) => setState(() => _hover = null),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (var i = 0; i < bars.length; i++) ...[
                        if (i > 0) SizedBox(width: gap),
                        Expanded(
                          child: Semantics(
                            button: true,
                            label: '${_label(bars[i])}: ${CurrencyFormatter.format(bars[i].total)}',
                            excludeSemantics: true,
                            child: MouseRegion(
                              onEnter: (_) => setState(() => _hover = i),
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () => setState(() => _hover = i),
                                child: Align(
                                  alignment: Alignment.bottomCenter,
                                  child: AnimatedContainer(
                                    duration: AppMotion.of(context, AppMotion.normal),
                                    curve: AppMotion.curve,
                                    height: (max <= 0 ? 0.02 : (bars[i].total / max).clamp(0.02, 1.0)) * box.maxHeight,
                                    decoration: BoxDecoration(
                                      color: bars[i].current
                                          ? c.accent
                                          : (i == best ? c.inkFaint : (i == _hover ? c.lineStrong : c.line)),
                                      borderRadius: const BorderRadius.vertical(top: Radius.circular(6), bottom: Radius.circular(2)),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
          Divider(height: 1, color: c.line),
          const SizedBox(height: AppSpace.sm),
          if (bars.isNotEmpty)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_axis(bars.first), style: AppText.caption(context)),
                if (bars.length > 2) Text(_axis(bars[bars.length ~/ 2]), style: AppText.caption(context)),
                Text(_axis(bars.last), style: AppText.caption(context)),
              ],
            ),
        ],
      ),
    );
  }
}

/// «14 días · Mes · Año»
class _RangeSwitch extends StatelessWidget {
  final HomeRange value;
  final ValueChanged<HomeRange> onChanged;

  const _RangeSwitch({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    const labels = {HomeRange.days14: '14 días', HomeRange.month: 'Mes', HomeRange.year: 'Año'};
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: c.surfaceMuted, borderRadius: BorderRadius.circular(AppRadius.tile)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final e in labels.entries)
            Semantics(
              button: true,
              selected: e.key == value,
              child: Material(
                color: e.key == value ? c.surface : Colors.transparent,
                borderRadius: BorderRadius.circular(AppRadius.small),
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppRadius.small),
                  onTap: () => onChanged(e.key),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: 6),
                    child: Text(
                      e.value,
                      style: AppText.small(context,
                          weight: e.key == value ? FontWeight.w600 : FontWeight.w500, color: e.key == value ? c.ink : c.inkMuted),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
