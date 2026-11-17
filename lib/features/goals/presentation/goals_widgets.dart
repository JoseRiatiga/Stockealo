import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../core/design/app_card.dart';
import '../../../core/design/app_dialog.dart';
import '../../../core/design/filter_tabs.dart';
import '../../../core/design/pro_crown.dart';
import '../../../core/design/status_pill.dart';
import '../../../core/permissions/permissions.dart';
import '../../../core/services/data_events.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/widgets/app_toast.dart';
import '../../auth/data/auth_repository.dart';
import '../../business/models/business.dart';
import '../../pro/data/pro_service.dart';
import '../../pro/presentation/screens/pro_screen.dart';
import '../../team/data/team_repository.dart';
import '../../team/models/business_member.dart';
import '../data/goals_repository.dart';
import '../models/sales_goal.dart';

/// Metas de ventas (0.16.0, fase 0): tarjeta de Inicio, hoja para ponerlas y la vista
/// de Reportes › Metas con la gráfica, el equipo (Pro) y el historial (Pro).

bool get _isPro => ProService.instance.status.value.active;

String _money(double v) => CurrencyFormatter.format(v.round());

/// Barra de avance con el porcentaje, lo que falta y cuánto vender por día
class GoalBar extends StatelessWidget {
  final String title;
  final GoalProgress progress;
  const GoalBar({super.key, required this.title, required this.progress});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = progress;
    final color = p.onPace ? c.success : c.warning;
    // La barra es un semáforo (verde al día, ámbar atrás) y se ve igual en los dos
    // modos: usa el relleno de aviso, no el ámbar oscuro de texto (0.16.6)
    final bar = p.onPace ? c.success : c.warningFill;
    final detail = p.reached
        ? '¡Meta cumplida! ${_money(p.sold)} de ${_money(p.goal)}'
        : p.isOver
            ? '${_money(p.sold)} de ${_money(p.goal)}'
            : '${_money(p.sold)} de ${_money(p.goal)} · faltan ${_money(p.missing)}'
                '${p.daysLeft > 1 ? ' · ${_money(p.perDay)} por día' : ' · hoy es el último día'}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(title, style: AppText.body(context, weight: FontWeight.w600))),
            Text('${p.percent} %', style: AppText.body(context, weight: FontWeight.w700, color: color)),
          ],
        ),
        const SizedBox(height: AppSpace.xs + 2),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          child: LinearProgressIndicator(
            value: p.ratio.clamp(0, 1).toDouble(),
            minHeight: 10,
            color: bar,
            backgroundColor: c.surfaceMuted,
          ),
        ),
        const SizedBox(height: AppSpace.xs + 2),
        Text(
          !p.onPace && !p.isOver ? '$detail · vas un poco atrás' : detail,
          style: AppText.small(context, color: c.inkMuted),
        ),
      ],
    );
  }
}

/// Lo vendido acumulado día a día (línea del color del negocio) frente al ritmo para
/// llegar a la meta (línea punteada)
class GoalChart extends StatelessWidget {
  final GoalProgress progress;
  final List<double> daily;
  const GoalChart({super.key, required this.progress, required this.daily});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final today = DateTime(progress.now.year, progress.now.month, progress.now.day);
    final shownDays = progress.isOver ? daily.length : (today.difference(progress.from).inDays + 1).clamp(1, daily.length);
    final cumulative = <double>[];
    var sum = 0.0;
    for (var i = 0; i < shownDays; i++) {
      sum += daily[i];
      cumulative.add(sum);
    }
    final fmt = DateFormat('d MMM', 'es_CO');
    final last = progress.to.subtract(const Duration(days: 1));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 160,
          child: CustomPaint(
            painter: _GoalPainter(
              goal: progress.goal,
              days: daily.length,
              cumulative: cumulative,
              line: c.accent,
              pace: c.inkFaint,
              grid: c.line,
            ),
          ),
        ),
        const SizedBox(height: AppSpace.xs),
        Row(
          children: [
            Text(fmt.format(progress.from), style: AppText.caption(context, color: c.inkFaint)),
            const Spacer(),
            Text(fmt.format(last), style: AppText.caption(context, color: c.inkFaint)),
          ],
        ),
        const SizedBox(height: AppSpace.sm),
        Wrap(
          spacing: AppSpace.md,
          runSpacing: AppSpace.xs,
          children: [
            _Legend(color: c.accent, label: 'Lo vendido'),
            _Legend(color: c.inkFaint, label: 'Ritmo para llegar a ${_money(progress.goal)}', dashed: true),
          ],
        ),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  final Color color;
  final String label;
  final bool dashed;
  const _Legend({required this.color, required this.label, this.dashed = false});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 16,
          height: 3,
          decoration: BoxDecoration(color: dashed ? null : color, border: dashed ? Border.all(color: color, width: 1) : null),
        ),
        const SizedBox(width: AppSpace.xs + 2),
        Flexible(child: Text(label, style: AppText.caption(context, color: context.colors.inkMuted))),
      ],
    );
  }
}

class _GoalPainter extends CustomPainter {
  final double goal;
  final int days;
  final List<double> cumulative;
  final Color line;
  final Color pace;
  final Color grid;

  _GoalPainter({required this.goal, required this.days, required this.cumulative, required this.line, required this.pace, required this.grid});

  @override
  void paint(Canvas canvas, Size size) {
    if (days <= 0) return;
    final top = [goal, ...cumulative].fold<double>(0, (m, v) => v > m ? v : m) * 1.08;
    if (top <= 0) return;
    double x(num i) => size.width * i / days;
    double y(double v) => size.height - size.height * (v < 0 ? 0 : v) / top;

    canvas.drawLine(Offset(0, size.height), Offset(size.width, size.height), Paint()..color = grid..strokeWidth = 1);
    // La meta: línea fina arriba
    canvas.drawLine(Offset(0, y(goal)), Offset(size.width, y(goal)), Paint()..color = grid..strokeWidth = 1);

    // El ritmo: de 0 a la meta, punteado
    final pacePaint = Paint()
      ..color = pace
      ..strokeWidth = 1.5;
    const dash = 6.0, gap = 5.0;
    final start = Offset(0, size.height), end = Offset(size.width, y(goal));
    final length = (end - start).distance;
    final dir = (end - start) / length;
    for (var d = 0.0; d < length; d += dash + gap) {
      canvas.drawLine(start + dir * d, start + dir * (d + dash > length ? length : d + dash), pacePaint);
    }

    if (cumulative.isEmpty) return;
    final path = Path()..moveTo(0, size.height);
    for (var i = 0; i < cumulative.length; i++) {
      path.lineTo(x(i + 1), y(cumulative[i]));
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = line
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawCircle(Offset(x(cumulative.length), y(cumulative.last)), 4.5, Paint()..color = line);
  }

  @override
  bool shouldRepaint(covariant _GoalPainter old) =>
      old.goal != goal || old.days != days || old.cumulative.length != cumulative.length || old.line != line ||
      (cumulative.isNotEmpty && old.cumulative.last != cumulative.last);
}

/// Hoja «Meta de ventas»: semanal y/o mensual, para todo el negocio o (Pro) para una
/// persona del equipo. Solo el dueño la abre.
class GoalSheet {
  static Future<bool> show(BuildContext context, {required Business business, String? memberUserId}) async {
    final members = (await TeamRepository.instance.getMembers(business.id)).where((m) => m.userId != null).toList();
    final goals = await GoalsRepository.instance.list(business.id);
    if (!context.mounted) return false;
    final pro = _isPro;
    String? who = memberUserId;
    final week = TextEditingController();
    final month = TextEditingController();
    String? error;

    void fill() {
      final now = DateTime.now();
      final w = GoalsRepository.goalFor(goals, GoalPeriod.week, GoalPeriod.week.startOf(now), member: who);
      final m = GoalsRepository.goalFor(goals, GoalPeriod.month, GoalPeriod.month.startOf(now), member: who);
      week.text = w == null ? '' : '${w.amount.round()}';
      month.text = m == null ? '' : '${m.amount.round()}';
    }

    fill();
    final ok = await AppSheet.show<bool>(
      context: context,
      title: 'Meta de ventas',
      subtitle: 'Deja vacía la que no quieras. Cuenta desde esta semana o este mes.',
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (members.isNotEmpty) ...[
              Row(
                children: [
                  Text('¿Para quién?', style: AppText.body(ctx, weight: FontWeight.w600)),
                  const SizedBox(width: AppSpace.sm),
                  if (!pro) const ProCrown(),
                ],
              ),
              const SizedBox(height: AppSpace.sm),
              FilterTabs<String>(
                wrap: true,
                options: {
                  '': 'Todo el negocio',
                  for (final m in members) m.userId!: m.displayName,
                },
                value: who ?? '',
                onChanged: (v) {
                  if (v.isNotEmpty && !pro) {
                    Navigator.pop(ctx, false);
                    ProScreen.open(context, business);
                    return;
                  }
                  setLocal(() {
                    who = v.isEmpty ? null : v;
                    error = null;
                    fill();
                  });
                },
              ),
              const SizedBox(height: AppSpace.md),
            ],
            TextField(
              controller: week,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: 'Meta semanal', hintText: 'Ej.: 2000000', prefixText: '\$ '),
            ),
            const SizedBox(height: AppSpace.md),
            TextField(
              controller: month,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(labelText: 'Meta mensual', hintText: 'Ej.: 8000000', prefixText: '\$ ', errorText: error),
            ),
            const SizedBox(height: AppSpace.lg),
            FilledButton(
              onPressed: () {
                final w = double.tryParse(week.text) ?? 0, m = double.tryParse(month.text) ?? 0;
                if (w > 0 && m > 0 && m < w) {
                  setLocal(() => error = 'La meta del mes no puede ser menor que la de la semana.');
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
    final w = double.tryParse(week.text) ?? 0, m = double.tryParse(month.text) ?? 0;
    week.dispose();
    month.dispose();
    if (ok != true) return false;
    final now = DateTime.now();
    final name = who == null ? null : members.firstWhere((x) => x.userId == who).displayName;
    for (final (period, amount) in [(GoalPeriod.week, w), (GoalPeriod.month, m)]) {
      final current = GoalsRepository.goalFor(goals, period, period.startOf(now), member: who);
      if ((current?.amount ?? 0) == amount) continue;
      await GoalsRepository.instance.setGoal(
        businessId: business.id,
        period: period,
        amount: amount,
        memberUserId: who,
        memberName: name,
        now: now,
      );
    }
    if (context.mounted) AppToast.showSuccess(context, 'Meta guardada.');
    return true;
  }
}

/// Tarjeta «Metas» de Inicio. El dueño y quien ve reportes ven la del negocio; cada
/// persona con meta propia (Pro) ve la suya. Sin metas, el dueño ve la invitación.
class GoalsCard extends StatefulWidget {
  final Business business;
  final String role;
  const GoalsCard({super.key, required this.business, required this.role});

  @override
  State<GoalsCard> createState() => _GoalsCardState();
}

class _GoalsCardState extends State<GoalsCard> {
  List<(String, GoalProgress)> _bars = const [];
  bool _loaded = false;

  bool get _owner => widget.role == Permissions.owner;
  bool get _seesBusiness => Permissions.can(widget.role, Perm.reportsSales);

  @override
  void initState() {
    super.initState();
    GoalsRepository.instance.version.addListener(_load);
    DataEvents.instance.salesVersion.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    GoalsRepository.instance.version.removeListener(_load);
    DataEvents.instance.salesVersion.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    // Inicio no se cae si la base se cerró mientras cargaba (cerrar sesión, cambiar de cuenta)
    try {
      await _loadNow();
    } catch (e) {
      debugPrint('Inicio: no se pudo cargar: $e');
    }
  }

  Future<void> _loadNow() async {
    final repo = GoalsRepository.instance;
    final biz = widget.business.id;
    final goals = await repo.list(biz);
    final bars = <(String, GoalProgress)>[];
    if (_seesBusiness) {
      for (final p in GoalPeriod.values) {
        final g = await repo.businessProgress(biz, p, goals: goals);
        if (g != null) bars.add((p.current, g));
      }
    }
    // Mi meta personal (Pro): lo vendido por mí lo da la nube
    final me = AuthRepository.instance.currentUser?.id;
    if (me != null && _isPro) {
      final now = DateTime.now();
      for (final p in GoalPeriod.values) {
        final from = p.startOf(now);
        final mine = GoalsRepository.goalFor(goals, p, from, member: me);
        if (mine == null) continue;
        final sold = await repo.memberSales(biz, from, p.endOf(from));
        if (sold == null) continue;
        bars.add((
          'Mi meta · ${p.current.toLowerCase()}',
          GoalProgress(period: p, goal: mine.amount, sold: sold[me] ?? 0, from: from, to: p.endOf(from), now: now),
        ));
      }
    }
    if (mounted) {
      setState(() {
        _bars = bars;
        _loaded = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();
    final c = context.colors;
    if (_bars.isEmpty) {
      if (!_owner) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: AppSpace.md),
        child: AppCard(
          onTap: () => GoalSheet.show(context, business: widget.business),
          child: Row(
            children: [
              Icon(Icons.flag_outlined, color: c.accent),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Ponle una meta a tus ventas', style: AppText.body(context, weight: FontWeight.w600)),
                    Text('Semanal o mensual, y ves cada día cómo vas.', style: AppText.small(context, color: c.inkMuted)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.md),
      child: AppCard(
        onTap: _seesBusiness ? () => GoalsView.open(context, business: widget.business, role: widget.role) : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.flag_outlined, color: c.accent, size: 20),
                const SizedBox(width: AppSpace.sm),
                Expanded(child: Text('Metas', style: AppText.title(context))),
                if (_seesBusiness) Text('Ver más', style: AppText.small(context, color: c.accent, weight: FontWeight.w600)),
              ],
            ),
            for (final (title, p) in _bars) ...[
              const SizedBox(height: AppSpace.md),
              GoalBar(title: title, progress: p),
            ],
          ],
        ),
      ),
    );
  }
}

/// Reportes › Metas: la gráfica de la semana o del mes, las metas del equipo (Pro) y el
/// historial (Pro)
class GoalsView extends StatefulWidget {
  final Business business;
  final String role;
  final bool embedded;
  const GoalsView({super.key, required this.business, required this.role, this.embedded = false});

  static Future<void> open(BuildContext context, {required Business business, required String role}) => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => Scaffold(
            appBar: AppBar(title: const Text('Metas de ventas')),
            body: GoalsView(business: business, role: role),
          ),
        ),
      );

  @override
  State<GoalsView> createState() => _GoalsViewState();
}

class _GoalsViewState extends State<GoalsView> {
  GoalPeriod _period = GoalPeriod.month;
  GoalProgress? _progress;
  List<double> _daily = const [];
  List<GoalProgress> _history = const [];
  List<(BusinessMember, SalesGoal, double?)> _team = const [];
  bool _loading = true;

  bool get _owner => widget.role == Permissions.owner;

  @override
  void initState() {
    super.initState();
    GoalsRepository.instance.version.addListener(_load);
    DataEvents.instance.salesVersion.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    GoalsRepository.instance.version.removeListener(_load);
    DataEvents.instance.salesVersion.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    // Inicio no se cae si la base se cerró mientras cargaba (cerrar sesión, cambiar de cuenta)
    try {
      await _loadNow();
    } catch (e) {
      debugPrint('Inicio: no se pudo cargar: $e');
    }
  }

  Future<void> _loadNow() async {
    final repo = GoalsRepository.instance;
    final biz = widget.business.id;
    final now = DateTime.now();
    final from = _period.startOf(now), to = _period.endOf(from);
    final goals = await repo.list(biz);
    final progress = await repo.businessProgress(biz, _period, goals: goals, now: now);
    final daily = await repo.dailySales(biz, from, to);
    final pro = _isPro;
    final history = pro ? await repo.businessHistory(biz, _period, now: now) : <GoalProgress>[];
    final team = <(BusinessMember, SalesGoal, double?)>[];
    if (pro) {
      final members = await TeamRepository.instance.getMembers(biz);
      final withGoal = [
        for (final m in members)
          if (m.userId != null)
            if (GoalsRepository.goalFor(goals, _period, from, member: m.userId) case final g?) (m, g),
      ];
      if (withGoal.isNotEmpty) {
        final sold = await repo.memberSales(biz, from, to);
        for (final (m, g) in withGoal) {
          team.add((m, g, sold == null ? null : sold[m.userId] ?? 0));
        }
      }
    }
    if (!mounted) return;
    setState(() {
      _progress = progress;
      _daily = daily;
      _history = history;
      _team = team;
      _loading = false;
    });
  }

  String _periodName(DateTime from) => _period == GoalPeriod.month
      ? toBeginningOfSentenceCase(DateFormat('MMMM y', 'es_CO').format(from))
      : 'Semana del ${DateFormat("d 'de' MMM", 'es_CO').format(from)}';

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (_loading) return const Center(child: CircularProgressIndicator());
    final now = DateTime.now();
    final from = _period.startOf(now);
    final pro = _isPro;
    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.md, AppSpace.lg, AppSpace.xxl * 3),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    FilterTabs<GoalPeriod>(
                      options: {for (final p in GoalPeriod.values) p: p.label},
                      value: _period,
                      onChanged: (p) {
                        setState(() {
                          _period = p;
                          _loading = true;
                        });
                        _load();
                      },
                    ),
                    const Spacer(),
                    if (_owner)
                      TextButton.icon(
                        onPressed: () => GoalSheet.show(context, business: widget.business),
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        label: Text(_progress == null ? 'Poner meta' : 'Cambiar'),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpace.md),
                AppCard(
                  child: _progress == null
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_periodName(from), style: AppText.title(context)),
                            const SizedBox(height: AppSpace.sm),
                            Text(
                              _owner
                                  ? 'Todavía no tienes meta ${_period == GoalPeriod.week ? 'semanal' : 'mensual'}. Ponla y aquí verás cada día cómo vas.'
                                  : 'El dueño todavía no puso una meta ${_period == GoalPeriod.week ? 'semanal' : 'mensual'}.',
                              style: AppText.body(context, color: c.inkMuted),
                            ),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            GoalBar(title: _periodName(from), progress: _progress!),
                            const SizedBox(height: AppSpace.lg),
                            GoalChart(progress: _progress!, daily: _daily),
                          ],
                        ),
                ),
                const SizedBox(height: AppSpace.lg),
                _section(context, 'Metas del equipo'),
                const SizedBox(height: AppSpace.sm),
                AppCard(
                  child: !pro
                      ? _proInvite(context, 'Ponle una meta a cada persona del equipo y mira cómo va cada una.')
                      : _team.isEmpty
                          ? Text(
                              _owner
                                  ? 'Nadie del equipo tiene meta propia. En «Cambiar», elige a la persona.'
                                  : 'Nadie del equipo tiene meta propia.',
                              style: AppText.body(context, color: c.inkMuted),
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                for (final (i, (m, g, sold)) in _team.indexed) ...[
                                  if (i > 0) const SizedBox(height: AppSpace.md),
                                  sold == null
                                      ? Text('${m.displayName}: ${_money(g.amount)} · se ve con internet',
                                          style: AppText.body(context, color: c.inkMuted))
                                      : GoalBar(
                                          title: m.displayName,
                                          progress: GoalProgress(
                                              period: _period, goal: g.amount, sold: sold, from: from, to: _period.endOf(from), now: now),
                                        ),
                                ],
                                const SizedBox(height: AppSpace.md),
                                Text('Cada persona ve solo su meta.', style: AppText.small(context, color: c.inkFaint)),
                              ],
                            ),
                ),
                const SizedBox(height: AppSpace.lg),
                _section(context, 'Historial'),
                const SizedBox(height: AppSpace.sm),
                AppCard(
                  child: !pro
                      ? _proInvite(context, 'Mira si cumpliste la meta de las semanas y los meses anteriores.')
                      : _history.isEmpty
                          ? Text('Aquí aparecerán las metas que ya pasaron.', style: AppText.body(context, color: c.inkMuted))
                          : Column(
                              children: [
                                for (final h in _history)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(vertical: AppSpace.xs + 2),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(_periodName(h.from), style: AppText.body(context, weight: FontWeight.w600)),
                                              Text('${_money(h.sold)} de ${_money(h.goal)}',
                                                  style: AppText.small(context, color: c.inkMuted)),
                                            ],
                                          ),
                                        ),
                                        StatusPill(
                                          h.reached ? 'Cumplida' : '${h.percent} %',
                                          tone: h.reached ? AppTone.success : AppTone.warning,
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _section(BuildContext context, String title) => Row(
        children: [
          Text(title, style: AppText.title(context)),
          const SizedBox(width: AppSpace.sm),
          const ProCrown(),
        ],
      );

  Widget _proInvite(BuildContext context, String text) => Row(
        children: [
          Expanded(child: Text(text, style: AppText.body(context, color: context.colors.inkMuted))),
          const SizedBox(width: AppSpace.md),
          OutlinedButton(onPressed: () => ProScreen.open(context, widget.business), child: const Text('Ver Pro')),
        ],
      );
}
