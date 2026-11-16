import 'package:flutter/material.dart';
import '../../../../core/utils/clock_text.dart';
import '../../../../core/design/qty_stepper.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../../core/design/app_dialog.dart';
import '../../../../core/design/stat_card.dart';
import '../../../../core/design/status_pill.dart';
import '../../../../core/services/data_events.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../business/presentation/active_business_scope.dart';
import '../../../pro/data/pro_service.dart';
import '../../../services/data/commissions_repository.dart';
import '../../../services/data/services_repository.dart';
import '../../../services/models/service_models.dart';
import '../../data/cash_register_repository.dart';
import '../../models/cash_session.dart';
import '../widgets/open_cash.dart';
import '../../../sales/presentation/widgets/sale_document.dart';
import '../../../../core/permissions/permissions.dart';
import '../../../../core/permissions/permission_guard.dart';
import '../../../team/presentation/widgets/authorization_gate.dart';

/// Caja (lugar del menú): abrir el turno con una base, registrar entradas y
/// salidas, ver lo cobrado por forma de pago y cerrar contando el dinero (también
/// por billetes y monedas), con el resultado en grande («La caja está justa»).
/// Es el único cierre del día: con Pro Servicios suma lo de servicios.
class CashRegisterScreen extends StatefulWidget {
  final String businessId;
  final String userName;

  /// Dentro del marco de la app (lugar del menú): sin barra propia
  final bool embedded;

  /// Rol de quien usa la caja: sin «Ver lo esperado en caja» cuenta a ciegas (0.15.0)
  final String role;

  const CashRegisterScreen({
    super.key,
    required this.businessId,
    required this.userName,
    this.role = 'OWNER',
    this.embedded = false,
  });

  @override
  State<CashRegisterScreen> createState() => _CashRegisterScreenState();
}

/// El cierre de caja como tiquete: lo que entró y salió, lo esperado, lo contado
/// y el sello CAJA JUSTA, FALTAN o SOBRAN
SaleDocument cashTicket(CashSession s, CashSummary sum, [List<String> servicesLines = const []]) {
  final diff = s.difference ?? 0;
  const money = CurrencyFormatter.format;
  return SaleDocument(
    title: 'Cierre de caja',
    number: 'CAJA-${DateFormat('yyMMdd-HHmm').format(s.closedAt ?? DateTime.now())}',
    date: s.closedAt ?? DateTime.now(),
    lines: const [],
    total: s.countedAmount ?? 0,
    totalLabel: 'Contado',
    sellerName: s.closedBy ?? s.openedBy,
    before: [
      TicketRow('Abrió', '${s.openedBy} · ${clockText(s.openedAt)}'),
      TicketRow('Base', money(sum.openingAmount)),
      for (final e in sum.byMethod.entries) TicketRow(CashRegisterRepository.methodLabel(e.key), money(e.value)),
      if (sum.tipsIn > 0) TicketRow('Propinas en efectivo', money(sum.tipsIn)),
      if (sum.tipsOut > 0) TicketRow('Propinas entregadas', '-${money(sum.tipsOut)}'),
      if (sum.entries > 0) TicketRow('Entradas', money(sum.entries)),
      if (sum.exits > 0) TicketRow('Salidas', '-${money(sum.exits)}'),
      if (sum.cashPurchases > 0) TicketRow('Mercancía de contado', '-${money(sum.cashPurchases)}'),
      TicketRow('Esperado', money(s.expectedAmount ?? sum.expected), bold: true),
    ],
    after: [
      TicketRow('Diferencia', diff.abs() < 1 ? 'Ninguna' : '${diff > 0 ? '+' : '-'}${money(diff.abs())}', bold: true),
      for (final l in servicesLines) TicketRow('', l),
    ],
    notes: s.notes,
    closing: 'Cierre del turno',
    stamp: diff.abs() < 1
        ? const TicketStamp('CAJA JUSTA', tone: AppTone.success)
        : TicketStamp(diff < 0 ? 'FALTAN' : 'SOBRAN', detail: money(diff.abs()), tone: diff < 0 ? AppTone.danger : AppTone.warning),
  );
}

/// Cierre en arqueo ciego (0.15.0): solo lo contado; lo esperado y la diferencia los ve el dueño
SaleDocument blindCashTicket(CashSession s) => SaleDocument(
      title: 'Cierre de caja',
      number: 'CAJA-${DateFormat('yyMMdd-HHmm').format(s.closedAt ?? DateTime.now())}',
      date: s.closedAt ?? DateTime.now(),
      lines: const [],
      total: s.countedAmount ?? 0,
      totalLabel: 'Contado',
      sellerName: s.closedBy ?? s.openedBy,
      before: [TicketRow('Abrió', '${s.openedBy} · ${clockText(s.openedAt)}')],
      notes: s.notes,
      closing: 'Cierre del turno · arqueo ciego',
      stamp: const TicketStamp('ENTREGADA', tone: AppTone.info),
    );

/// Resultado de contar la caja: justa, faltan o sobran (con su tono)
({String text, AppTone tone}) cashResult(double diff) {
  if (diff.abs() < 1) return (text: 'La caja está justa', tone: AppTone.success);
  if (diff < 0) return (text: 'Faltan ${CurrencyFormatter.format(-diff)}', tone: AppTone.danger);
  return (text: 'Sobran ${CurrencyFormatter.format(diff)}', tone: AppTone.warning);
}

/// Diferencia del conteo contra lo esperado; null mientras no hay resultado que
/// mostrar: arqueo ciego, nada escrito o, contando por billetes, todavía en $0
/// (antes salía «Faltan» apenas se activaba el conteo)
double? countDiff({required double? counted, required double expected, required bool byDenomination, required bool blind}) {
  if (blind || counted == null) return null;
  if (byDenomination && counted <= 0) return null;
  return counted - expected;
}

class _CashRegisterScreenState extends State<CashRegisterScreen> {
  /// Arqueo ciego: cuenta la plata sin ver cuánto debería haber; el dueño ve la diferencia
  bool get _blind => !Permissions.can(widget.role, Perm.cashExpected);

  final _repo = CashRegisterRepository.instance;

  bool _loading = true;
  CashSession? _open;
  CashSummary? _summary;
  List<CashMovement> _movements = const [];
  List<CashSession> _history = const [];

  @override
  void initState() {
    super.initState();
    _load();
    DataEvents.instance.salesVersion.addListener(_load);
    DataEvents.instance.cashVersion.addListener(_load);
  }

  @override
  void dispose() {
    DataEvents.instance.salesVersion.removeListener(_load);
    DataEvents.instance.cashVersion.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final open = await _repo.getOpenSession(widget.businessId);
    final summary = open != null ? await _repo.summarize(open) : null;
    final moves = open != null ? await _repo.movements(open) : const <CashMovement>[];
    final history = await _repo.getClosedSessions(widget.businessId);
    if (!mounted) return;
    setState(() {
      _open = open;
      _summary = summary;
      _movements = moves;
      _history = history;
      _loading = false;
    });
  }

  static double? _amount(String text) {
    final clean = text.replaceAll(RegExp(r'[^0-9]'), '');
    return clean.isEmpty ? null : double.parse(clean);
  }

  String _hour(DateTime d) => clockText(d);

  Future<void> _movement(String kind) async {
    final session = _open;
    if (session == null) return;
    final reasons = kind == CashMovement.exit ? CashMovement.exitReasons : CashMovement.entryReasons;
    var reason = reasons.first;
    final amount = TextEditingController();
    final note = TextEditingController();
    final ok = await AppSheet.show<bool>(
      context: context,
      title: kind == CashMovement.exit ? 'Sacar dinero de la caja' : 'Meter dinero a la caja',
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: AppSpace.sm,
              runSpacing: AppSpace.sm,
              children: [
                for (final r in reasons)
                  ChoiceChip(
                    label: Text(CashMovement.reasons[r]!),
                    selected: reason == r,
                    showCheckmark: false,
                    onSelected: (_) => setLocal(() => reason = r),
                  ),
              ],
            ),
            const SizedBox(height: AppSpace.md),
            TextField(
              controller: amount,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: 'Valor', prefixText: '\$ '),
            ),
            const SizedBox(height: AppSpace.sm),
            TextField(
              controller: note,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Detalle (opcional)', hintText: 'Ej. almuerzo, bolsas, a Juan'),
            ),
            const SizedBox(height: AppSpace.lg),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Guardar')),
          ],
        ),
      ),
    );
    final value = _amount(amount.text);
    final detail = note.text;
    amount.dispose();
    note.dispose();
    if (ok != true || !mounted) return;
    // Sin permiso o una salida por encima del límite: pide autorización (0.15.0)
    final needs = <String>[
      if (!Permissions.mine(Perm.cashMoves)) 'Tu rol no permite registrar entradas o salidas de dinero.',
      if (kind == CashMovement.exit &&
          Permissions.myLimit(RoleLimit.cashOutMax) != null &&
          (value ?? 0) > Permissions.myLimit(RoleLimit.cashOutMax)! + 0.5)
        'La salida es de ${CurrencyFormatter.format(value ?? 0)} y tu límite es '
            '${CurrencyFormatter.format(Permissions.myLimit(RoleLimit.cashOutMax)!)}.',
    ];
    String? authId;
    if (needs.isNotEmpty) {
      authId = await AuthorizationGate.allow(
        context,
        businessId: widget.businessId,
        action: '${kind == CashMovement.exit ? 'Salida' : 'Entrada'} de caja de ${CurrencyFormatter.format(value ?? 0)}',
        reasons: needs,
        amount: value,
      );
      if (authId == null || !mounted) return;
    }
    try {
      await _repo.addMovement(
          session: session, kind: kind, reason: reason, amount: value ?? 0, note: detail, authRequestId: authId);
      await _load();
    } on StateError catch (e) {
      if (mounted) AppToast.showWarning(context, e.message);
    }
  }

  /// Con Pro Servicios: lo atendido en el turno y lo que hizo cada persona
  Future<(List<String>, Map<String, dynamic>)> _servicesDay(CashSession session) async {
    if (!ProService.instance.status.value.services) return (const <String>[], const <String, dynamic>{});
    final until = DateTime.now();
    final orders = (await ServicesRepository.instance.searchHistory(session.businessId, '', limit: 500))
        .where((o) => o.status == WorkOrder.delivered && !o.updatedAt.isBefore(session.openedAt) && !o.updatedAt.isAfter(until))
        .toList();
    final earned = await CommissionsRepository.instance.earnedBetween(session.businessId, session.openedAt, until.add(const Duration(seconds: 1)));
    final staff = {for (final s in await ServicesRepository.instance.getStaff(session.businessId, includeInactive: true)) s.id: s.name};
    final lines = [
      'Servicios: ${orders.length} ${orders.length == 1 ? 'trabajo entregado' : 'trabajos entregados'}',
      for (final e in earned)
        '${staff[e.staffId] ?? 'Persona'}: ${e.services} ${e.services == 1 ? 'servicio' : 'servicios'} · '
            'comisión ${CurrencyFormatter.format(e.commissions)}${e.tips != 0 ? ' · propinas ${CurrencyFormatter.format(e.tips)}' : ''}',
    ];
    return (
      lines,
      {
        'services_delivered': orders.length,
        'services_by_staff': {for (final e in earned) e.staffId: {'services': e.services, 'commissions': e.commissions, 'tips': e.tips}},
      },
    );
  }

  Future<void> _close() async {
    final session = _open;
    final summary = _summary;
    if (session == null || summary == null) return;
    // Su propia caja, o la de otra persona si tiene «Cerrar la caja de otros»
    final mine = session.openedBy.trim().toLowerCase() == widget.userName.trim().toLowerCase();
    if (!PermissionGuard.check(context, mine ? Perm.cashOwn : Perm.cashOthers)) return;
    final (servicesLines, servicesExtra) = await _servicesDay(session);
    if (!mounted) return;
    final closed = await AppSheet.show<CashSession>(
      context: context,
      title: 'Cerrar caja',
      subtitle: 'Cuenta el efectivo que hay en la caja.',
      builder: (_) => _CloseForm(
        session: session,
        summary: summary,
        servicesLines: servicesLines,
        servicesExtra: servicesExtra,
        blind: _blind,
      ),
    );
    if (closed == null || !mounted) return;
    await _load();
    if (!mounted) return;
    // El cierre sale como tiquete con el resultado en el sello
    final business = ActiveBusinessScope.read(context);
    final businessName = business?.name ?? 'Mi negocio';
    final finalSummary = await _repo.summarize(closed);
    if (!mounted) return;
    // Arqueo ciego: el tiquete dice lo contado, sin lo esperado ni la diferencia
    if (_blind) {
      await TicketViewer.show(
        context,
        business: business,
        businessName: businessName,
        doc: blindCashTicket(closed),
        headline: 'Caja cerrada',
        headlineTone: AppTone.info,
        subline: 'Contaste ${CurrencyFormatter.format(closed.countedAmount ?? 0)}',
        text: '$businessName\nCierre de caja\nContado: ${CurrencyFormatter.format(closed.countedAmount ?? 0)}'
            '${closed.closedBy != null ? '\nCerró: ${closed.closedBy}' : ''}',
      );
      return;
    }
    final result = cashResult(closed.difference ?? 0);
    await TicketViewer.show(
      context,
      business: business,
      businessName: businessName,
      doc: cashTicket(closed, finalSummary, servicesLines),
      headline: 'Caja cerrada',
      headlineTone: result.tone,
      subline: result.text,
      text: CashRegisterRepository.receipt(
        businessName: businessName,
        session: closed,
        summary: finalSummary,
        servicesLines: servicesLines,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final body = _loading
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(AppSpace.md + 2, AppSpace.lg, AppSpace.md + 2, AppSpace.xxl),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_open == null) _closedView() else _openView(),
                        const SizedBox(height: AppSpace.xl),
                        _history.isEmpty ? const SizedBox.shrink() : _historyCard(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
    if (widget.embedded) return ColoredBox(color: c.paper, child: body);
    return Scaffold(backgroundColor: c.paper, appBar: AppBar(title: const Text('Caja')), body: body);
  }

  Widget _card({required List<Widget> children, EdgeInsets padding = const EdgeInsets.all(AppSpace.lg + 2)}) {
    final c = context.colors;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: c.line),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
    );
  }

  Widget _closedView() {
    final t = ToneColors.of(context, AppTone.warning);
    return _card(
      children: [
        Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(color: t.soft, borderRadius: BorderRadius.circular(AppRadius.control + 2)),
              child: Icon(Icons.point_of_sale_outlined, color: t.strong),
            ),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('La caja está cerrada', style: AppText.heading(context)),
                  Text('Ábrela con el efectivo con el que empiezas, para tener con qué dar vuelto.', style: AppText.small(context)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpace.lg),
        OpenCashForm(
          businessId: widget.businessId,
          userName: widget.userName,
          onOpened: (_) {
            AppToast.showSuccess(context, 'Caja abierta');
            _load();
          },
        ),
      ],
    );
  }

  Widget _openView() {
    final c = context.colors;
    final session = _open!;
    final s = _summary!;
    final rows = <(String, double)>[
      ('Base inicial', s.openingAmount),
      ('Ventas en efectivo (${s.cashSalesCount})', s.cashSales),
      if (s.cashPayments != 0) ('Abonos de fiados en efectivo', s.cashPayments),
      if (s.tipsIn != 0) ('Propinas en efectivo', s.tipsIn),
      if (s.tipsOut != 0) ('Propinas entregadas', -s.tipsOut),
      if (s.entries != 0) ('Entradas', s.entries),
      if (s.exits != 0) ('Salidas', -s.exits),
      if (s.cashPurchases != 0) ('Mercancía de contado', -s.cashPurchases),
    ];
    final totalMethods = s.byMethod.values.fold<double>(0, (a, b) => a + b);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (session.isStale()) ...[
          AttentionRow(
            icon: Icons.point_of_sale_outlined,
            tone: AppTone.danger,
            title: 'La caja quedó abierta desde el ${DateFormat('d MMM', 'es_CO').format(session.openedAt)}',
            detail: 'Ciérrala para cuadrar ese día y abre la de hoy.',
            pill: 'Sin cerrar',
          ),
          const SizedBox(height: AppSpace.md),
        ],
        // La cifra del turno, en grande
        _card(
          children: [
            Row(
              children: [
                const StatusPill('Caja abierta', tone: AppTone.success, dot: true),
                const Spacer(),
                Text('Desde las ${_hour(session.openedAt)} · ${session.openedBy}', style: AppText.small(context)),
              ],
            ),
            const SizedBox(height: AppSpace.lg),
            if (_blind) ...[
              // Arqueo ciego (0.15.0): sin lo esperado ni el detalle que lo deja calcular
              Text('Arqueo ciego', style: AppText.title(context)),
              const SizedBox(height: AppSpace.xs),
              Text('Al cerrar, cuentas el efectivo sin ver cuánto debería haber. El dueño ve si la caja cuadró.',
                  style: AppText.small(context, color: c.inkMuted)),
            ] else ...[
              Text('Debería haber en la caja', style: AppText.body(context, weight: FontWeight.w600, color: c.inkMuted)),
              Text(CurrencyFormatter.format(s.expected), style: AppText.figure(context)),
              if (s.tipsToDeliver > 0)
                Text('De eso, ${CurrencyFormatter.format(s.tipsToDeliver)} son propinas por entregar.',
                    style: AppText.small(context, weight: FontWeight.w600, color: c.warning)),
              const SizedBox(height: AppSpace.md),
              for (final (label, value) in rows) _row(label, value),
            ],
            const SizedBox(height: AppSpace.lg),
            Wrap(
              spacing: AppSpace.sm,
              runSpacing: AppSpace.sm,
              alignment: WrapAlignment.end,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _movement(CashMovement.entry),
                  icon: const Icon(Icons.add_outlined, size: 18),
                  label: const Text('Entrada'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _movement(CashMovement.exit),
                  icon: const Icon(Icons.remove_outlined, size: 18),
                  label: const Text('Salida'),
                ),
                FilledButton.icon(
                  onPressed: _close,
                  icon: const Icon(Icons.lock_outline, size: 18),
                  label: const Text('Cerrar caja'),
                ),
              ],
            ),
          ],
        ),
        if (s.byMethod.isNotEmpty) ...[
          const SizedBox(height: AppSpace.md),
          _card(
            children: [
              Text('Cobrado por forma de pago', style: AppText.title(context)),
              const SizedBox(height: AppSpace.md),
              for (final e in s.byMethod.entries) ...[
                _row(CashRegisterRepository.methodLabel(e.key), e.value),
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpace.sm),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    child: LinearProgressIndicator(
                      value: totalMethods <= 0 ? 0 : e.value / totalMethods,
                      minHeight: 5,
                      backgroundColor: c.surfaceMuted,
                      valueColor: AlwaysStoppedAnimation(e.key == 'EFECTIVO' ? c.accent : c.inkFaint),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
        if (_movements.isNotEmpty) ...[
          const SizedBox(height: AppSpace.md),
          _card(
            children: [
              Text('Entradas y salidas', style: AppText.title(context)),
              const SizedBox(height: AppSpace.sm),
              for (final m in _movements) _row('${_hour(m.date)} · ${m.reasonLabel}${m.note == null ? '' : ' (${m.note})'}', m.signed),
            ],
          ),
        ],
      ],
    );
  }

  Widget _row(String label, double amount, {bool bold = false}) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label, style: AppText.body(context, weight: bold ? FontWeight.w700 : FontWeight.w400))),
          Text(CurrencyFormatter.format(amount),
              style: AppText.amount(context, size: AppText.sizeBody, weight: bold ? FontWeight.w700 : FontWeight.w600, color: amount < 0 ? c.danger : c.ink)),
        ],
      ),
    );
  }

  Widget _historyCard() {
    return _card(
      children: [
        Text('Cierres anteriores', style: AppText.title(context)),
        const SizedBox(height: AppSpace.md),
        for (final s in _history) ...[
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(toBeginningOfSentenceCase(DateFormat("EEEE d MMM, h:mm a", 'es_CO').format(s.closedAt!)),
                        style: AppText.body(context, weight: FontWeight.w600)),
                    Text(
                      '${_blind ? '' : 'Esperado ${CurrencyFormatter.format(s.expectedAmount ?? 0)} · '}Contado ${CurrencyFormatter.format(s.countedAmount ?? 0)}'
                      '${s.closedBy != null ? ' · ${s.closedBy}' : ''}${s.notes != null ? '\n${s.notes}' : ''}',
                      style: AppText.small(context),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpace.sm),
              if (!_blind)
                () {
                  final r = cashResult(s.difference ?? 0);
                  return StatusPill((s.difference ?? 0).abs() < 1 ? 'Justa' : r.text, tone: r.tone);
                }(),
            ],
          ),
          Divider(height: AppSpace.xl, color: context.colors.line),
        ],
      ],
    );
  }
}

/// Cierre: efectivo contado (a mano o por billetes y monedas), el resultado en
/// grande mientras se cuenta y nota obligatoria si no cuadra
class _CloseForm extends StatefulWidget {
  final CashSession session;
  final CashSummary summary;
  final List<String> servicesLines;
  final Map<String, dynamic> servicesExtra;

  /// Arqueo ciego: sin lo esperado ni el resultado
  final bool blind;

  const _CloseForm({
    required this.session,
    required this.summary,
    required this.servicesLines,
    required this.servicesExtra,
    this.blind = false,
  });

  @override
  State<_CloseForm> createState() => _CloseFormState();
}

class _CloseFormState extends State<_CloseForm> {
  final _counted = TextEditingController();
  final _notes = TextEditingController();
  final Map<int, int> _units = {};
  bool _byDenomination = false;
  bool _saving = false;

  @override
  void dispose() {
    _counted.dispose();
    _notes.dispose();
    super.dispose();
  }

  double? get _total {
    if (_byDenomination) return _units.entries.fold<double>(0, (s, e) => s + e.key * e.value);
    return _CashRegisterScreenState._amount(_counted.text);
  }

  Future<void> _save() async {
    final counted = _total;
    if (counted == null) {
      AppToast.showWarning(context, 'Escribe cuánto efectivo contaste.');
      return;
    }
    setState(() => _saving = true);
    try {
      final closed = await CashRegisterRepository.instance.closeSession(
        session: widget.session,
        countedAmount: counted,
        notes: _notes.text,
        blind: widget.blind,
        denominations: _byDenomination ? {for (final e in _units.entries) if (e.value > 0) e.key: e.value} : const {},
        extra: widget.servicesExtra,
      );
      if (mounted) Navigator.pop(context, closed);
    } on StateError catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        AppToast.showWarning(context, e.message);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        AppToast.showError(context, e.toString().replaceFirst('Exception: ', ''));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final expected = widget.summary.expected;
    final counted = _total;
    final diff = countDiff(counted: counted, expected: expected, byDenomination: _byDenomination, blind: widget.blind);
    final result = diff == null ? null : cashResult(diff);
    final t = result == null ? null : ToneColors.of(context, result.tone);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.blind)
          Text('Cuenta todo el efectivo de la caja y escribe cuánto hay.', style: AppText.body(context, color: c.inkMuted))
        else
          Row(
            children: [
              Expanded(child: Text('Debería haber', style: AppText.body(context, color: c.inkMuted))),
              Text(CurrencyFormatter.format(expected), style: AppText.amount(context, size: AppText.sizeTitle)),
            ],
          ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _byDenomination,
          onChanged: (v) => setState(() => _byDenomination = v),
          title: Text('Contar por billetes y monedas', style: AppText.body(context)),
        ),
        if (_byDenomination)
          for (final d in kCopDenominations)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Expanded(child: Text(CurrencyFormatter.format(d), style: AppText.body(context))),
                  QtyStepper(
                    value: _units[d] ?? 0,
                    label: CurrencyFormatter.format(d),
                    onRemove: (_units[d] ?? 0) == 0 ? null : () => setState(() => _units[d] = (_units[d] ?? 0) - 1),
                    onAdd: () => setState(() => _units[d] = (_units[d] ?? 0) + 1),
                  ),
                ],
              ),
            )
        else
          TextField(
            controller: _counted,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (_) => setState(() {}),
            style: AppText.heading(context),
            decoration: const InputDecoration(labelText: 'Efectivo contado', prefixText: '\$ '),
          ),
        const SizedBox(height: AppSpace.md),
        // El resultado: una franja baja a todo el ancho (0.16.3). Mientras se cuenta por
        // billetes y no hay resultado, se ve lo que llevas en gris
        AnimatedSwitcher(
          duration: AppMotion.of(context, AppMotion.quick),
          child: result == null
              ? (_byDenomination
                  ? SizedBox(
                      key: const ValueKey('counting'),
                      width: double.infinity,
                      child: Text('Llevas ${CurrencyFormatter.format(counted ?? 0)}',
                          style: AppText.body(context, color: c.inkMuted)),
                    )
                  : const SizedBox(key: ValueKey('none'), height: 0))
              : Container(
                  key: ValueKey(result.text),
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.md),
                  decoration: BoxDecoration(color: t!.soft, borderRadius: BorderRadius.circular(AppRadius.control)),
                  child: Semantics(
                    liveRegion: true,
                    child: Row(
                      children: [
                        Expanded(child: Text(result.text, style: AppText.title(context, color: t.text))),
                        if (_byDenomination && counted != null)
                          Text('Contaste ${CurrencyFormatter.format(counted)}', style: AppText.small(context, color: t.text)),
                      ],
                    ),
                  ),
                ),
        ),
        const SizedBox(height: AppSpace.md),
        TextField(
          controller: _notes,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: diff != null && diff.abs() >= 1 ? 'Nota (obligatoria: explica la diferencia)' : 'Nota (opcional)',
          ),
        ),
        if (widget.servicesLines.isNotEmpty) ...[
          const SectionLabel('SERVICIOS DEL TURNO', padding: EdgeInsets.fromLTRB(0, AppSpace.lg, 0, AppSpace.xs)),
          for (final l in widget.servicesLines) Text(l, style: AppText.small(context)),
        ],
        const SizedBox(height: AppSpace.lg),
        SizedBox(
          height: 52,
          child: FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Cerrando…' : 'Cerrar caja')),
        ),
      ],
    );
  }
}
