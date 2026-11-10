import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/design/app_card.dart';
import '../../../../core/design/content_width.dart';
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

/// Ventas › Caja: abrir el turno con una base, registrar entradas y salidas, ver lo
/// cobrado por forma de pago y cerrar contando el dinero (también por billetes y
/// monedas). Es el único cierre del día: con Pro Servicios suma lo de servicios.
class CashRegisterScreen extends StatefulWidget {
  final String businessId;
  final String userName;

  const CashRegisterScreen({super.key, required this.businessId, required this.userName});

  @override
  State<CashRegisterScreen> createState() => _CashRegisterScreenState();
}

class _CashRegisterScreenState extends State<CashRegisterScreen> {
  final _repo = CashRegisterRepository.instance;
  final _base = TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;
  CashSession? _open;
  CashSummary? _summary;
  List<CashMovement> _movements = const [];
  List<CashSession> _history = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _base.dispose();
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
      _isLoading = false;
    });
  }

  static double? _amount(String text) {
    final clean = text.replaceAll(RegExp(r'[^0-9]'), '');
    return clean.isEmpty ? null : double.parse(clean);
  }

  String _hour(DateTime d) => DateFormat('h:mm a', 'es_CO').format(d);

  Future<void> _openSession() async {
    setState(() => _isSaving = true);
    try {
      await _repo.openSession(businessId: widget.businessId, openingAmount: _amount(_base.text) ?? 0, openedBy: widget.userName);
      _base.clear();
      if (mounted) AppToast.showSuccess(context, 'Caja abierta');
      await _load();
    } catch (e) {
      if (mounted) AppToast.showError(context, e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _movement(String kind) async {
    final session = _open;
    if (session == null) return;
    final reasons = kind == CashMovement.exit ? CashMovement.exitReasons : CashMovement.entryReasons;
    var reason = reasons.first;
    final amount = TextEditingController();
    final note = TextEditingController();
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final c = ctx.colors;
          return Padding(
            padding: EdgeInsets.fromLTRB(AppSpace.lg, 0, AppSpace.lg, MediaQuery.of(ctx).viewInsets.bottom + AppSpace.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(kind == CashMovement.exit ? 'Sacar dinero de la caja' : 'Meter dinero a la caja',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c.ink)),
                const SizedBox(height: AppSpace.md),
                Wrap(
                  spacing: AppSpace.sm,
                  runSpacing: AppSpace.sm,
                  children: [
                    for (final r in reasons)
                      ChoiceChip(
                        label: Text(CashMovement.reasons[r]!),
                        selected: reason == r,
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
          );
        },
      ),
    );
    final value = _amount(amount.text);
    final detail = note.text;
    amount.dispose();
    note.dispose();
    if (ok != true) return;
    try {
      await _repo.addMovement(session: session, kind: kind, reason: reason, amount: value ?? 0, note: detail);
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
    final (servicesLines, servicesExtra) = await _servicesDay(session);
    if (!mounted) return;
    final closed = await showModalBottomSheet<CashSession>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _CloseSheet(session: session, summary: summary, servicesLines: servicesLines, servicesExtra: servicesExtra),
    );
    if (closed == null || !mounted) return;
    await _load();
    if (!mounted) return;
    final send = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Caja cerrada'),
        content: const Text('¿Envías el comprobante del cierre por WhatsApp?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Enviar')),
        ],
      ),
    );
    if (send == true && mounted) {
      final businessName = ActiveBusinessScope.read(context)?.name ?? 'Mi negocio';
      final finalSummary = await _repo.summarize(closed);
      await Share.share(CashRegisterRepository.receipt(
        businessName: businessName,
        session: closed,
        summary: finalSummary,
        servicesLines: servicesLines,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.paper,
      appBar: AppBar(title: const Text('Caja')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ContentWidth(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.sm, AppSpace.lg, AppSpace.xxl),
                  children: [
                    _open == null ? _openForm() : _openSessionView(),
                    const SizedBox(height: AppSpace.xl),
                    Text('Cierres anteriores', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.ink)),
                    const SizedBox(height: AppSpace.sm),
                    if (_history.isEmpty)
                      Text('Todavía no has cerrado ninguna caja.', style: TextStyle(color: c.inkMuted)),
                    for (final s in _history) ...[
                      _historyTile(s),
                      const SizedBox(height: AppSpace.sm),
                    ],
                  ],
                ),
              ),
            ),
    );
  }

  Widget _openForm() {
    final c = context.colors;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('La caja está cerrada', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: c.ink)),
          const SizedBox(height: AppSpace.xs),
          Text('Escribe el efectivo con el que empiezas el turno (la base o sencillo).',
              style: TextStyle(color: c.inkMuted, fontSize: 13)),
          const SizedBox(height: AppSpace.md),
          TextField(
            controller: _base,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'Base inicial', prefixText: '\$ '),
          ),
          const SizedBox(height: AppSpace.md),
          FilledButton.icon(
            onPressed: _isSaving ? null : _openSession,
            icon: const Icon(Icons.lock_open_rounded),
            label: const Text('Abrir caja'),
          ),
        ],
      ),
    );
  }

  Widget _openSessionView() {
    final c = context.colors;
    final session = _open!;
    final s = _summary!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (session.isStale())
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.sm),
            child: AppCard(
              color: c.warningSoft,
              child: Text(
                'La caja quedó abierta desde el ${DateFormat('d MMM', 'es_CO').format(session.openedAt)}. Ciérrala para cuadrar ese día.',
                style: TextStyle(color: c.ink),
              ),
            ),
          ),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Caja abierta', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: c.ink)),
              Text('Desde las ${_hour(session.openedAt)} · ${session.openedBy}', style: TextStyle(color: c.inkMuted, fontSize: 13)),
              Divider(height: AppSpace.xl, color: c.line),
              _row('Base inicial', s.openingAmount),
              _row('Ventas en efectivo (${s.cashSalesCount})', s.cashSales),
              if (s.cashPayments != 0) _row('Abonos de fiados en efectivo', s.cashPayments),
              if (s.tipsIn != 0) _row('Propinas en efectivo', s.tipsIn),
              if (s.tipsOut != 0) _row('Propinas entregadas', -s.tipsOut),
              if (s.entries != 0) _row('Entradas', s.entries),
              if (s.exits != 0) _row('Salidas', -s.exits),
              if (s.cashPurchases != 0) _row('Mercancía de contado', -s.cashPurchases),
              Divider(height: AppSpace.xl, color: c.line),
              _row('Debería haber en caja', s.expected, bold: true),
              if (s.tipsToDeliver > 0)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpace.xs),
                  child: Text('De eso, ${CurrencyFormatter.format(s.tipsToDeliver)} son propinas por entregar.',
                      style: TextStyle(color: c.warning, fontSize: 12.5, fontWeight: FontWeight.w600)),
                ),
              const SizedBox(height: AppSpace.md),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _movement(CashMovement.exit),
                      icon: const Icon(Icons.remove_rounded, size: 18),
                      label: const Text('Salida'),
                    ),
                  ),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _movement(CashMovement.entry),
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Entrada'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpace.sm),
              FilledButton.icon(
                onPressed: _isSaving ? null : _close,
                icon: const Icon(Icons.lock_rounded),
                label: const Text('Cerrar caja'),
              ),
            ],
          ),
        ),
        if (s.byMethod.isNotEmpty) ...[
          const SizedBox(height: AppSpace.md),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Cobrado por forma de pago', style: TextStyle(fontWeight: FontWeight.w700, color: c.ink)),
                const SizedBox(height: AppSpace.xs),
                for (final e in s.byMethod.entries) _row(CashRegisterRepository.methodLabel(e.key), e.value),
              ],
            ),
          ),
        ],
        if (_movements.isNotEmpty) ...[
          const SizedBox(height: AppSpace.md),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Entradas y salidas', style: TextStyle(fontWeight: FontWeight.w700, color: c.ink)),
                const SizedBox(height: AppSpace.xs),
                for (final m in _movements)
                  _row('${_hour(m.date)} · ${m.reasonLabel}${m.note == null ? '' : ' (${m.note})'}', m.signed),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _row(String label, double amount, {bool bold = false}) {
    final c = context.colors;
    final style = TextStyle(
      fontWeight: bold ? FontWeight.w700 : FontWeight.normal,
      fontSize: bold ? 16 : 14,
      color: amount < 0 ? c.danger : c.ink,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style.copyWith(color: c.ink))),
          Text(CurrencyFormatter.format(amount), style: style),
        ],
      ),
    );
  }

  Widget _historyTile(CashSession s) {
    final c = context.colors;
    final difference = s.difference ?? 0;
    final color = difference.abs() < 1 ? c.success : (difference > 0 ? c.warning : c.danger);
    return AppCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(DateFormat('d MMM yyyy, h:mm a', 'es_CO').format(s.closedAt!),
                    style: TextStyle(fontWeight: FontWeight.w600, color: c.ink)),
                Text(
                  'Esperado ${CurrencyFormatter.format(s.expectedAmount ?? 0)} · Contado ${CurrencyFormatter.format(s.countedAmount ?? 0)}'
                  '${s.notes != null ? '\n${s.notes}' : ''}',
                  style: TextStyle(fontSize: 12.5, color: c.inkMuted),
                ),
              ],
            ),
          ),
          Text(
            difference.abs() < 1 ? 'Cuadró' : '${difference > 0 ? '+' : '−'}${CurrencyFormatter.format(difference.abs())}',
            style: TextStyle(color: color, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

/// Cierre: efectivo contado (a mano o por billetes y monedas), diferencia en vivo
/// y nota obligatoria si no cuadra
class _CloseSheet extends StatefulWidget {
  final CashSession session;
  final CashSummary summary;
  final List<String> servicesLines;
  final Map<String, dynamic> servicesExtra;

  const _CloseSheet({required this.session, required this.summary, required this.servicesLines, required this.servicesExtra});

  @override
  State<_CloseSheet> createState() => _CloseSheetState();
}

class _CloseSheetState extends State<_CloseSheet> {
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
    final diff = counted == null ? null : counted - expected;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: ContentWidth(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(AppSpace.lg, 0, AppSpace.lg, AppSpace.lg),
          children: [
            Text('Cerrar caja', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c.ink)),
            Text('Debería haber ${CurrencyFormatter.format(expected)} en efectivo.', style: TextStyle(color: c.inkMuted)),
            const SizedBox(height: AppSpace.md),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _byDenomination,
              onChanged: (v) => setState(() => _byDenomination = v),
              title: const Text('Contar por billetes y monedas'),
            ),
            if (_byDenomination)
              for (final d in kCopDenominations)
                Row(
                  children: [
                    Expanded(child: Text(CurrencyFormatter.format(d), style: TextStyle(color: c.ink))),
                    IconButton(
                      tooltip: 'Quitar uno',
                      onPressed: (_units[d] ?? 0) == 0 ? null : () => setState(() => _units[d] = (_units[d] ?? 0) - 1),
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                    SizedBox(width: 32, child: Text('${_units[d] ?? 0}', textAlign: TextAlign.center, style: TextStyle(color: c.ink))),
                    IconButton(
                      tooltip: 'Agregar uno',
                      onPressed: () => setState(() => _units[d] = (_units[d] ?? 0) + 1),
                      icon: const Icon(Icons.add_circle_outline),
                    ),
                  ],
                )
            else
              TextField(
                controller: _counted,
                autofocus: true,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(labelText: 'Efectivo contado', prefixText: '\$ '),
              ),
            const SizedBox(height: AppSpace.md),
            if (diff != null)
              Text(
                [
                  if (_byDenomination) 'Contaste ${CurrencyFormatter.format(counted!)}.',
                  diff.abs() < 1
                      ? 'La caja cuadra.'
                      : diff > 0
                          ? 'Sobran ${CurrencyFormatter.format(diff)}.'
                          : 'Faltan ${CurrencyFormatter.format(-diff)}.',
                ].join(' '),
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: diff.abs() < 1 ? c.success : (diff > 0 ? c.warning : c.danger),
                ),
              ),
            const SizedBox(height: AppSpace.sm),
            TextField(
              controller: _notes,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: diff != null && diff.abs() >= 1 ? 'Nota (obligatoria: explica la diferencia)' : 'Nota (opcional)',
              ),
            ),
            if (widget.servicesLines.isNotEmpty) ...[
              const SizedBox(height: AppSpace.md),
              Text('Servicios del turno', style: TextStyle(fontWeight: FontWeight.w700, color: c.ink)),
              for (final l in widget.servicesLines) Text(l, style: TextStyle(fontSize: 13, color: c.inkMuted)),
            ],
            const SizedBox(height: AppSpace.lg),
            FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Cerrando...' : 'Cerrar caja')),
          ],
        ),
      ),
    );
  }
}
