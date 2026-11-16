import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/design/skeleton.dart';
import '../../../../core/design/stat_card.dart';
import '../../../../core/design/status_pill.dart';
import '../../../../core/services/data_events.dart';
import '../../../../core/services/notification_service.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../auth/data/auth_repository.dart';
import '../../../business/data/business_repository.dart';
import '../../../business/models/business.dart';
import '../../../business/presentation/active_business_scope.dart';
import '../../../cash/data/cash_register_repository.dart';
import '../../../cash/models/cash_session.dart';
import '../../../home/navigation/app_places.dart';
import '../../../services/data/services_repository.dart';
import '../../../services/models/service_models.dart';
import '../../../team/data/activity_repository.dart';
import '../../../team/data/team_repository.dart';
import '../../data/home_data.dart';
import '../widgets/attention_panel.dart';
import '../widgets/cloud_sync_reminder.dart';
import '../widgets/home_sales_chart.dart';
import '../widgets/quick_actions_section.dart';
import '../../../../core/permissions/permissions.dart';
import '../../../pro/presentation/screens/pro_screen.dart';
import '../../../pro/data/pro_service.dart';
import '../../../goals/presentation/goals_widgets.dart';
import '../../../products/presentation/widgets/lots_widgets.dart';
import '../widgets/first_steps_card.dart';
import '../../../products/presentation/widgets/idle_products_alert.dart';
import '../../../team/presentation/screens/activity_screen.dart';
import '../../../team/data/activity_line.dart';

/// Inicio: cómo va el día de un vistazo y lo que necesita atención, con su
/// solución a un toque. Diseño aprobado el 11 nov 2026 (re-diseño 0.13.0).
class DashboardScreen extends StatefulWidget {
  final String userId;
  final VoidCallback onLogout;

  /// Lleva a otro lugar del menú (número de [AppPlace])
  final ValueChanged<int>? onNavigateToTab;

  const DashboardScreen({super.key, required this.userId, required this.onLogout, this.onNavigateToTab});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> with ActiveBusinessAware {
  /// Avisos que se ven en Inicio; el resto, en Stock y en Clientes
  static const _attentionShown = 5;

  final _auth = AuthRepository.instance;

  Business? _business;
  String _role = 'OWNER';
  HomeData _data = const HomeData();
  HomeRange _range = HomeRange.days14;
  bool _loading = true;

  // Partes que solo se ven si el negocio las usa
  CashSession? _cash;
  CashSummary? _cashSummary;
  List<WorkOrder>? _board;
  List<ActivityEntry>? _activity;

  bool _can(Perm p) => Permissions.can(_role, p);

  @override
  void onActiveBusinessChanged() {
    if (!mounted) return;
    _load();
    _syncSilently();
  }

  @override
  void initState() {
    super.initState();
    _load();
    NotificationService.instance.remoteSalesVersion.addListener(_reload);
    DataEvents.instance.salesVersion.addListener(_reload);
    DataEvents.instance.cashVersion.addListener(_reload);
    _syncSilently();
  }

  @override
  void dispose() {
    NotificationService.instance.remoteSalesVersion.removeListener(_reload);
    DataEvents.instance.salesVersion.removeListener(_reload);
    DataEvents.instance.cashVersion.removeListener(_reload);
    super.dispose();
  }

  void _reload() {
    if (mounted) _load(quiet: true);
  }

  Future<void> _syncSilently() async {
    try {
      final user = _auth.currentUser;
      if (user != null && await SupabaseService.instance.isCloudSyncEnabled()) {
        await SupabaseService.instance.syncFromCloud(widget.userId, user.email);
        if (mounted) _load(quiet: true);
      }
    } catch (_) {}
  }

  Future<void> _refresh() async {
    try {
      final user = _auth.currentUser;
      if (user != null && await SupabaseService.instance.isCloudSyncEnabled()) {
        await SupabaseService.instance.syncFromCloud(widget.userId, user.email);
      }
    } catch (e) {
      debugPrint('Error sincronizando Inicio: $e');
    }
    await _load(quiet: true);
  }

  Future<void> _load({bool quiet = false}) async {
    if (!quiet) setState(() => _loading = true);
    final user = _auth.currentUser;
    final biz = await BusinessRepository.instance.getActiveBusiness(widget.userId, user?.email);
    if (biz == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final role = user == null
        ? 'OWNER'
        : await TeamRepository.instance.getUserRoleInBusiness(businessId: biz.id, userId: user.id, userEmail: user.email);
    final data = await HomeRepository.instance.load(biz.id, range: _range);

    CashSession? cash;
    CashSummary? cashSummary;
    if (biz.cashRegisterEnabled) {
      try {
        cash = await CashRegisterRepository.instance.getOpenSession(biz.id);
        if (cash != null) cashSummary = await CashRegisterRepository.instance.summarize(cash);
      } catch (_) {}
    }
    List<WorkOrder>? board;
    if (biz.servicesEnabled) {
      try {
        board = await ServicesRepository.instance.getBoard(biz.id);
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _business = biz;
      _role = role;
      _data = data;
      _cash = cash;
      _cashSummary = cashSummary;
      _board = board;
      _loading = false;
    });
    // La actividad puede venir de la nube: llega después, sin frenar el resto
    if (Permissions.can(role, Perm.activity)) {
      try {
        final activity = await ActivityRepository.instance.list(biz.id, limit: 4);
        if (mounted && _business?.id == biz.id) setState(() => _activity = activity);
      } catch (_) {}
    }
  }

  Future<void> _changeRange(HomeRange range) async {
    final biz = _business;
    if (biz == null || range == _range) return;
    setState(() => _range = range);
    final bars = await HomeRepository.instance.bars(biz.id, range);
    if (!mounted || _range != range) return;
    setState(() => _data = HomeData(
          todayTotal: _data.todayTotal,
          todayCount: _data.todayCount,
          lastWeekSameDay: _data.lastWeekSameDay,
          todayByHour: _data.todayByHour,
          monthProfit: _data.monthProfit,
          prevMonthProfit: _data.prevMonthProfit,
          debtTotal: _data.debtTotal,
          debtCustomers: _data.debtCustomers,
          overdueCustomers: _data.overdueCustomers,
          restockCount: _data.restockCount,
          outOfStockCount: _data.outOfStockCount,
          bars: bars,
          topWeek: _data.topWeek,
          attention: _data.attention,
        ));
  }

  void _go(int place) => widget.onNavigateToTab?.call(place);

  String get _firstName {
    final name = (_auth.currentUser?.displayName ?? '').trim();
    return name.isEmpty ? '' : name.split(RegExp(r'\s+')).first;
  }

  void _resolve(AttentionItem item) {
    final biz = _business;
    if (biz == null) return;
    AttentionPanel.show(context, item: item, business: biz, userName: _auth.currentUser?.displayName ?? '', onNavigate: _go);
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: context.colors.paper,
      child: RefreshIndicator(
        onRefresh: _refresh,
        child: LayoutBuilder(
          builder: (context, box) {
            final wide = box.maxWidth >= 900;
            final side = wide ? AppSpace.xl + 4 : AppSpace.md + 2;
            final pad = EdgeInsets.fromLTRB(
              math.max(side, (box.maxWidth - 1320) / 2),
              wide ? AppSpace.xl - 2 : AppSpace.lg,
              math.max(side, (box.maxWidth - 1320) / 2),
              MediaQuery.paddingOf(context).bottom + 120,
            );
            if (_loading) return _skeleton(pad);
            final gap = wide ? AppSpace.lg : AppSpace.md + 2;
            return ListView(
              padding: pad,
              children: [
                _greeting(wide),
                SizedBox(height: gap),
                // Accesos rápidos arriba, en una fila (0.16.1): antes quedaban al final
                if (_business != null) ...[
                  QuickActionsSection(
                    key: ValueKey('quick-${_business!.id}-$_role'),
                    business: _business!,
                    role: _role,
                    userName: _auth.currentUser?.displayName ?? '',
                    onNavigateToTab: _go,
                    onReturn: () => _load(quiet: true),
                  ),
                  SizedBox(height: gap),
                ],
                CloudSyncReminder(key: ValueKey('cloud-${_business?.id}-$_role'), canManage: _can(Perm.cloud)),
                if (_role == Permissions.owner && _business != null) _ProExpiry(business: _business!),
                // Primeros pasos y productos quietos (0.16.0, fase 5)
                if (_business != null && _role == Permissions.owner)
                  FirstStepsCard(key: ValueKey('first-${_business!.id}'), business: _business!),
                if (_business != null && _can(Perm.productsEdit))
                  IdleProductsAlert(key: ValueKey('idle-${_business!.id}'), business: _business!),
                // Vencimientos (0.16.0, fase 2b)
                if (_business != null && _can(Perm.stockAdjust))
                  ExpiryAlert(key: ValueKey('expiry-${_business!.id}'), business: _business!),
                // Metas de ventas (0.16.0)
                if (_business != null) GoalsCard(key: ValueKey('goals-${_business!.id}-$_role'), business: _business!, role: _role),
                _figures(wide, box.maxWidth - pad.horizontal),
                SizedBox(height: gap),
                _grid(
                  minWidth: 420,
                  width: box.maxWidth - pad.horizontal,
                  gap: gap,
                  // En el celular va primero lo que necesita atención
                  children: [
                    if (!wide) _attentionCard(),
                    HomeSalesChart(bars: _data.bars, range: _range, onRange: _changeRange),
                    if (wide) _attentionCard(),
                  ],
                ),
                SizedBox(height: gap),
                _grid(
                  minWidth: 300,
                  width: box.maxWidth - pad.horizontal,
                  gap: gap,
                  children: [
                    _topCard(),
                    if (_can(Perm.activity)) _activityCard(),
                    if (_board != null) _servicesCard(),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _skeleton(EdgeInsets pad) => ListView(
        padding: pad,
        children: const [
          SkeletonBox(width: 200, height: 26),
          SizedBox(height: AppSpace.sm),
          SkeletonBox(width: 320, height: 14),
          SizedBox(height: AppSpace.xl),
          SkeletonBox(height: 140, radius: AppRadius.card),
          SizedBox(height: AppSpace.lg),
          SkeletonBox(height: 280, radius: AppRadius.card),
        ],
      );

  /// Reparte tarjetas en columnas del mismo ancho (como «auto-fit» en la web)
  Widget _grid({required double minWidth, required double width, required double gap, required List<Widget> children}) {
    final cols = math.max(1, math.min(children.length, ((width + gap) / (minWidth + gap)).floor()));
    if (cols == 1) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[if (i > 0) SizedBox(height: gap), children[i]],
        ],
      );
    }
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i += cols) {
      final slice = children.sublist(i, math.min(i + cols, children.length));
      rows.add(IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var j = 0; j < cols; j++) ...[
              if (j > 0) SizedBox(width: gap),
              Expanded(child: j < slice.length ? slice[j] : const SizedBox()),
            ],
          ],
        ),
      ));
    }
    return Column(children: [for (var i = 0; i < rows.length; i++) ...[if (i > 0) SizedBox(height: gap), rows[i]]]);
  }

  Widget _greeting(bool wide) {
    final date = toBeginningOfSentenceCase(DateFormat("EEEE d 'de' MMMM", 'es_CO').format(DateTime.now()));
    final n = _data.attention.length;
    final parts = [
      date,
      if (_data.todayCount > 0) '${_data.todayCount} ${_data.todayCount == 1 ? 'venta' : 'ventas'} hasta ahora',
      if (n > 0) '$n ${n == 1 ? 'cosa necesita' : 'cosas necesitan'} atención' else 'Todo en orden',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_firstName.isEmpty ? 'Hola' : 'Hola, $_firstName',
            style: wide ? AppText.page(context) : AppText.heading(context).copyWith(fontSize: AppText.sizePage - 4)),
        const SizedBox(height: AppSpace.xs),
        Text(parts.join(' · '), style: AppText.body(context, color: context.colors.inkMuted)),
      ],
    );
  }

  /// Las cifras del día: ventas de hoy (en el color del negocio), ganancia, fiados
  /// y efectivo en caja (o lo que hay que reponer, si el negocio no usa caja)
  Widget _figures(bool wide, double width) {
    final d = _data;
    final today = d.todayChange;
    final weekday = DateFormat('EEEE', 'es_CO').format(DateTime.now());
    final sales = StatCard(
      filled: true,
      title: 'Ventas de hoy',
      trailing: '${d.todayCount} ${d.todayCount == 1 ? 'venta' : 'ventas'}',
      value: CurrencyFormatter.format(d.todayTotal),
      delta: today == null
          ? 'Aún sin comparación con el $weekday pasado'
          : '${today >= 0 ? '↑' : '↓'} ${today.abs().toStringAsFixed(0)} % frente al $weekday pasado',
      chart: wide
          ? MiniBars(
              values: d.todayByHour,
              highlight: 3,
              color: context.colors.onAccent,
              dimColor: context.colors.onAccent.withValues(alpha: 0.4),
              height: 30,
            )
          : null,
      onTap: () => _go(AppPlace.ventas),
    );

    final profit = d.profitChange;
    final compact = !wide;
    final cards = <Widget>[
      sales,
      if (_can(Perm.profits))
        StatCard(
          compact: compact,
          title: 'Ganancia de ${DateFormat('MMMM', 'es_CO').format(DateTime.now())}',
          value: CurrencyFormatter.format(d.monthProfit),
          delta: profit == null ? null : '${profit >= 0 ? '↑' : '↓'} ${profit.abs().toStringAsFixed(0)} %',
          deltaTone: (profit ?? 0) >= 0 ? AppTone.success : AppTone.danger,
          detail: 'Ventas menos lo que te costaron',
          actionLabel: 'Ver ganancias',
          onTap: () => _go(AppPlace.reportes),
        ),
      StatCard(
        compact: compact,
        title: 'Fiados por cobrar',
        value: CurrencyFormatter.format(d.debtTotal),
        delta: d.overdueCustomers > 0 ? '${d.overdueCustomers} ${d.overdueCustomers == 1 ? 'vencido' : 'vencidos'}' : null,
        deltaTone: AppTone.warning,
        detail: d.debtCustomers == 0
            ? 'Nadie te debe'
            : '${d.debtCustomers} ${d.debtCustomers == 1 ? 'cliente' : 'clientes'}'
                '${d.overdueCustomers > 0 ? ' · ${d.overdueCustomers} con más de ${HomeRepository.overdueDays} días' : ''}',
        chart: d.debtTotal > 0 && d.overdueCustomers > 0 ? _debtBar(d) : null,
        actionLabel: d.debtCustomers > 0 ? 'Cobrar' : null,
        onTap: () => _go(AppPlace.personas),
      ),
      if (_business?.cashRegisterEnabled == true) _cashCard(compact) else _restockCard(compact),
    ];

    if (wide) return _grid(minWidth: 220, width: width, gap: AppSpace.lg, children: cards);
    // Celular: ventas de hoy a lo ancho y las demás de a dos
    final rest = cards.skip(1).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        sales,
        const SizedBox(height: AppSpace.md - 2),
        _grid(minWidth: 150, width: width, gap: AppSpace.md - 2, children: rest.length.isOdd ? rest.sublist(0, rest.length - 1) : rest),
        if (rest.length.isOdd) ...[const SizedBox(height: AppSpace.md - 2), rest.last],
      ],
    );
  }

  /// Barra de fiados: al día en azul y vencidos en naranja
  Widget _debtBar(HomeData d) {
    final c = context.colors;
    final share = (d.overdueCustomers / math.max(1, d.debtCustomers)).clamp(0.05, 1.0);
    return ExcludeSemantics(
      child: Row(
        children: [
          Expanded(flex: ((1 - share) * 100).round(), child: _bar(c.info.withValues(alpha: 0.45))),
          const SizedBox(width: 4),
          Expanded(flex: (share * 100).round(), child: _bar(c.warning)),
        ],
      ),
    );
  }

  Widget _bar(Color color) =>
      Container(height: 8, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(AppRadius.pill)));

  Widget _cashCard(bool compact) {
    final s = _cashSummary;
    if (_cash == null || s == null) {
      return StatCard(
        compact: compact,
        title: 'Efectivo en caja',
        value: 'Cerrada',
        detail: 'Ábrela para empezar a vender',
        actionLabel: 'Abrir caja',
        onTap: () => _go(AppPlace.caja),
      );
    }
    // Arqueo ciego (0.15.0): sin «Ver lo esperado en caja» no se muestra la cifra
    if (!_can(Perm.cashExpected)) {
      return StatCard(
        compact: compact,
        title: 'Caja',
        value: 'Abierta',
        detail: '${s.cashSalesCount} ${s.cashSalesCount == 1 ? 'venta' : 'ventas'} en efectivo',
        actionLabel: 'Cerrar caja',
        onTap: () => _go(AppPlace.caja),
      );
    }
    return StatCard(
      compact: compact,
      title: 'Efectivo en caja',
      value: CurrencyFormatter.format(s.expected),
      detail: 'Base ${CurrencyFormatter.format(s.openingAmount)} · ${s.cashSalesCount} '
          '${s.cashSalesCount == 1 ? 'venta' : 'ventas'} en efectivo',
      actionLabel: 'Cerrar caja',
      onTap: () => _go(AppPlace.caja),
    );
  }

  Widget _restockCard(bool compact) {
    final d = _data;
    return StatCard(
      compact: compact,
      title: 'Por reponer',
      value: '${d.restockCount} ${d.restockCount == 1 ? 'producto' : 'productos'}',
      delta: d.outOfStockCount > 0 ? '${d.outOfStockCount} ${d.outOfStockCount == 1 ? 'agotado' : 'agotados'}' : null,
      deltaTone: AppTone.danger,
      detail: d.restockCount == 0 ? 'Tienes todo con stock' : 'En el mínimo o por debajo',
      actionLabel: d.restockCount > 0 ? 'Ver en Stock' : null,
      onTap: () => _go(AppPlace.stock),
    );
  }

  /// Tarjeta blanca con título y algo a la derecha (subtítulo o enlace)
  Widget _card({required String title, String? subtitle, Widget? trailing, required List<Widget> children}) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(AppSpace.lg + 2),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppText.title(context)),
                    if (subtitle != null) Text(subtitle, style: AppText.small(context)),
                  ],
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
          const SizedBox(height: AppSpace.md),
          ...children,
        ],
      ),
    );
  }

  Widget _link(String label, VoidCallback onTap) => TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm), minimumSize: const Size(0, 36)),
        child: Text('$label ›'),
      );

  Widget _attentionCard() {
    final items = _data.attention;
    final more = items.length - _attentionShown;
    return _card(
      title: 'Necesita atención',
      subtitle: items.isEmpty ? 'Nada pendiente por ahora' : 'Lo más urgente primero',
      trailing: items.isEmpty ? null : StatusPill('${items.length}', tone: AppTone.danger),
      children: [
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpace.lg),
            child: Row(
              children: [
                Icon(Icons.check_circle_outline, color: context.colors.success),
                const SizedBox(width: AppSpace.md - 2),
                Expanded(
                  child: Text('Tienes stock, la caja al día y nadie con fiados vencidos.',
                      style: AppText.body(context, color: context.colors.inkMuted)),
                ),
              ],
            ),
          ),
        for (final item in items.take(_attentionShown)) ...[
          AttentionItemRow(item: item, onTap: () => _resolve(item)),
          const SizedBox(height: AppSpace.sm),
        ],
        if (more > 0)
          Align(
            alignment: Alignment.centerLeft,
            child: _link('Ver $more más en Stock y Clientes', () => _go(AppPlace.stock)),
          ),
      ],
    );
  }

  Widget _topCard() {
    final c = context.colors;
    final top = _data.topWeek;
    final max = top.isEmpty ? 1 : math.max(1, top.first.units);
    return _card(
      title: 'Lo más vendido',
      trailing: Text('Últimos 7 días', style: AppText.small(context)),
      children: [
        if (top.isEmpty) Text('Cuando vendas, aquí verás lo que más sale.', style: AppText.body(context, color: c.inkMuted)),
        for (var i = 0; i < top.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.md - 2),
            child: Row(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: c.surfaceMuted, shape: BoxShape.circle),
                  child: Text('${i + 1}', style: AppText.caption(context, weight: FontWeight.w700, color: c.ink)),
                ),
                const SizedBox(width: AppSpace.md - 2),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(top[i].name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.body(context, weight: FontWeight.w600)),
                      const SizedBox(height: 5),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                        child: LinearProgressIndicator(
                          value: top[i].units / max,
                          minHeight: 5,
                          backgroundColor: c.surfaceMuted,
                          valueColor: AlwaysStoppedAnimation(c.accent),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpace.md - 2),
                Text('${top[i].units} u.', style: AppText.mono(context, size: AppText.sizeSmall, color: c.inkMuted)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _activityCard() {
    final c = context.colors;
    final items = _activity;
    final list = items ?? const <ActivityEntry>[];
    return _card(
      title: 'Actividad del equipo',
      trailing: _business == null ? null : _link('Ver todo', () => ActivityScreen.open(context, _business!)),
      children: [
        if (items == null) const SkeletonBox(height: 60, radius: AppRadius.control),
        if (items != null && items.isEmpty)
          Text('Aquí verás quién vende, abre la caja o recibe mercancía.', style: AppText.body(context, color: c.inkMuted)),
        for (var i = 0; i < list.length; i++) ...[
          if (i > 0) Divider(height: AppSpace.md + 2, color: c.line),
          _activityRow(list[i]),
        ],
      ],
    );
  }

  /// Un movimiento (0.16.1): ícono por tipo, título corto, el valor a la derecha, un
  /// renglón de detalle y abajo quién y cuándo
  Widget _activityRow(ActivityEntry e) {
    final c = context.colors;
    final line = ActivityLine.of(e);
    final t = ToneColors.of(context, line.tone);
    final who = (e.actorName ?? '').trim().isNotEmpty ? e.actorName!.trim().split(' ').first : e.actorEmail.split('@').first;
    final valueColor = line.valueUp == null ? c.ink : (line.valueUp! ? c.success : c.danger);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(color: t.soft, borderRadius: BorderRadius.circular(AppRadius.control)),
          child: Icon(line.icon, size: 17, color: t.text),
        ),
        const SizedBox(width: AppSpace.md - 2),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(line.title,
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.body(context, weight: FontWeight.w600)),
                  ),
                  if (line.value != null) ...[
                    const SizedBox(width: AppSpace.sm),
                    Text(line.value!, style: AppText.amount(context, size: AppText.sizeBody, weight: FontWeight.w700, color: valueColor)),
                  ],
                ],
              ),
              if (line.detail != null)
                Text(line.detail!, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.small(context, color: c.inkMuted)),
              const SizedBox(height: 2),
              Wrap(
                spacing: AppSpace.sm,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text('$who · ${_when(e.createdAt)}', style: AppText.caption(context)),
                  if (line.tag != null) StatusPill(line.tag!, tone: AppTone.info),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _servicesCard() {
    final board = _board ?? const <WorkOrder>[];
    int count(String status) => board.where((o) => o.status == status).length;
    final delivered = count(WorkOrder.delivered);
    return _card(
      title: 'Servicios de hoy',
      trailing: _link('Abrir tablero', () => _go(AppPlace.servicios)),
      children: [
        Row(
          children: [
            Expanded(child: _serviceBox(count(WorkOrder.waiting), 'En espera', AppTone.neutral)),
            const SizedBox(width: AppSpace.sm),
            Expanded(child: _serviceBox(count(WorkOrder.inProgress), 'Atendiendo', AppTone.info)),
            const SizedBox(width: AppSpace.sm),
            Expanded(child: _serviceBox(count(WorkOrder.ready), 'Listos', AppTone.success)),
          ],
        ),
        const SizedBox(height: AppSpace.md),
        Text(
          delivered == 0 ? 'Todavía no se ha entregado nada hoy' : 'Entregados hoy: $delivered',
          style: AppText.small(context),
        ),
      ],
    );
  }

  Widget _serviceBox(int n, String label, AppTone tone) {
    final t = ToneColors.of(context, tone);
    final fg = tone == AppTone.neutral ? context.colors.ink : t.text;
    return Semantics(
      label: '$label: $n',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.all(AppSpace.md),
        decoration: BoxDecoration(color: t.soft, borderRadius: BorderRadius.circular(AppRadius.control)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$n', style: AppText.heading(context, color: fg).copyWith(fontSize: AppText.sizePage - 2)),
            Text(label, style: AppText.caption(context, color: tone == AppTone.neutral ? null : t.text)),
          ],
        ),
      ),
    );
  }

  static String _when(DateTime at) {
    final now = DateTime.now();
    final diff = now.difference(at);
    if (diff.inMinutes < 1) return 'Ahora';
    if (diff.inMinutes < 60) return 'Hace ${diff.inMinutes} min';
    if (at.year == now.year && at.month == now.month && at.day == now.day) {
      return DateFormat('h:mm a', 'es_CO').format(at);
    }
    return DateFormat('d MMM, h:mm a', 'es_CO').format(at);
  }
}

/// Aviso de vencimiento del Pro (0.15.0): 7 días antes y hasta 15 días después, con
/// «Renovar» en un toque. Solo lo ve el dueño.
class _ProExpiry extends StatefulWidget {
  final Business business;
  const _ProExpiry({required this.business});

  @override
  State<_ProExpiry> createState() => _ProExpiryState();
}

class _ProExpiryState extends State<_ProExpiry> {
  DateTime? _endedAt;

  @override
  void initState() {
    super.initState();
    ProService.instance.status.addListener(_reload);
    _reload();
  }

  @override
  void dispose() {
    ProService.instance.status.removeListener(_reload);
    super.dispose();
  }

  Future<void> _reload() async {
    final last = await ProService.lastKnown(widget.business.id);
    if (mounted) setState(() => _endedAt = last?.endedAt);
  }

  @override
  Widget build(BuildContext context) {
    final s = ProService.instance.status.value;
    final now = DateTime.now();
    final fmt = DateFormat("d 'de' MMMM", 'es_CO');
    String? title;
    String? detail;
    var tone = AppTone.warning;
    if (s.active && s.endsAt != null) {
      final days = s.endsAt!.difference(now).inHours / 24;
      if (days <= 7) {
        final n = days.ceil();
        title = n <= 1 ? 'Tu ${s.kindLabel} vence mañana' : 'Tu ${s.kindLabel} vence en $n días';
        detail = 'Vence el ${fmt.format(s.endsAt!)}. Renuévalo para no perder la tienda en línea y lo demás de Pro.';
      }
    } else if (!s.active && _endedAt != null && now.difference(_endedAt!).inDays <= 15) {
      title = 'Tu Pro venció el ${fmt.format(_endedAt!)}';
      detail = 'La tienda en línea y los recordatorios de cobro están en pausa. Al renovar vuelven solos.';
      tone = AppTone.danger;
    }
    if (title == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.md),
      child: AttentionRow(
        icon: Icons.workspace_premium_outlined,
        tone: tone,
        title: title,
        detail: detail,
        pill: 'Renovar',
        onTap: () => ProScreen.open(context, widget.business),
      ),
    );
  }
}

