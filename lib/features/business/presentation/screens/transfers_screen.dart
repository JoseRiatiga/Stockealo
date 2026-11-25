import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/design/app_card.dart';
import '../../../../core/design/app_dialog.dart';
import '../../../../core/design/status_pill.dart';
import '../../../../core/permissions/permissions.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../auth/data/auth_repository.dart';
import '../../../home/navigation/app_pane.dart';
import '../../../team/data/activity_repository.dart';
import '../../../team/data/shift_lead.dart';
import '../../data/branch_repository.dart';
import '../../data/transfer_repository.dart';
import '../../models/business.dart';
import 'new_transfer_screen.dart';

/// Stock › Traslados (0.18.5, boceto aprobado el 25 nov): «Te llegan», «Enviados» e
/// «Historial» de la sede elegida. El dueño y los administradores ven todos.
class TransfersScreen extends StatefulWidget {
  final Business business;
  const TransfersScreen({super.key, required this.business});

  static Future<void> open(BuildContext context, Business business) =>
      AppPane.open(context, (_) => TransfersScreen(business: business));

  /// Puede enviar desde la sede elegida: el dueño y los administradores, y quien tenga
  /// «Ajustar stock» (la nube lo revisa igual)
  static bool canSend() =>
      Permissions.current == Permissions.owner || Permissions.current == Permissions.admin || Permissions.mine(Perm.stockAdjust);

  static bool get isManager => Permissions.current == Permissions.owner || Permissions.current == Permissions.admin;

  @override
  State<TransfersScreen> createState() => _TransfersScreenState();
}

enum _Tab { incoming, sent, history }

class _TransfersScreenState extends State<TransfersScreen> {
  final _repo = TransferRepository.instance;
  final _branches = BranchRepository.instance;
  List<StockTransfer> _all = const [];
  bool _loading = true;
  String? _error;
  _Tab _tab = _Tab.incoming;
  String? _busy;

  String? get _here => BranchRepository.active;

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
      final all = await _repo.list(widget.business.id);
      if (mounted) setState(() => _all = all);
    } catch (e) {
      if (mounted) setState(() => _error = TransferRepository.friendlyError(e));
    }
    if (mounted) setState(() => _loading = false);
  }

  List<StockTransfer> _of(_Tab tab) => switch (tab) {
        _Tab.incoming => _all.where((t) => t.toBranchId == _here && (t.inTransit || t.unverified)).toList(),
        _Tab.sent => _all.where((t) => t.fromBranchId == _here && t.inTransit).toList(),
        _Tab.history => _all.where((t) => !_of(_Tab.incoming).contains(t) && !_of(_Tab.sent).contains(t)).toList(),
      };

  Future<void> _newTransfer() async {
    final sent = await NewTransferScreen.open(context, businessId: widget.business.id, fromBranchId: _here);
    if (sent == true && mounted) {
      setState(() => _tab = _Tab.sent);
      await _load();
    }
  }

  Future<void> _receive(StockTransfer t) async {
    final done = await AppPane.open<bool>(context, (_) => ReceiveTransferScreen(transfer: t));
    if (done == true && mounted) await _load();
  }

  Future<void> _cancel(StockTransfer t) async {
    final ok = await AppDialog.confirm(
      context: context,
      title: 'Cancelar el traslado',
      message: t.units == 1
          ? 'La unidad vuelve a ${_branches.nameOf(t.fromBranchId)}.'
          : 'Las ${t.units} unidades vuelven a ${_branches.nameOf(t.fromBranchId)}.',
      confirmText: 'Cancelar el traslado',
      cancelText: 'Volver',
      destructive: true,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = t.id);
    try {
      await _repo.cancel(t);
      ActivityRepository.instance.log(
        businessId: t.businessId,
        action: ActivityAction.transferCancel,
        summary: 'Canceló el traslado de ${unitsText(t.units)} a ${_branches.nameOf(t.toBranchId)}',
        data: {'transfer_id': t.id},
      );
      if (mounted) {
        AppToast.showSuccess(
          context,
          'Traslado cancelado: ${t.units == 1 ? 'la unidad volvió' : 'las unidades volvieron'} a ${_branches.nameOf(t.fromBranchId)}.',
        );
      }
      await _load();
    } catch (e) {
      if (mounted) AppToast.showError(context, TransferRepository.friendlyError(e));
    }
    if (mounted) setState(() => _busy = null);
  }

  Future<void> _verify(StockTransfer t) async {
    setState(() => _busy = t.id);
    try {
      await _repo.verify(t);
      if (mounted) AppToast.showSuccess(context, 'Traslado verificado.');
      await _load();
    } catch (e) {
      if (mounted) AppToast.showError(context, TransferRepository.friendlyError(e));
    }
    if (mounted) setState(() => _busy = null);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final incoming = _of(_Tab.incoming);
    final sent = _of(_Tab.sent);
    final shown = _of(_tab);
    final usable = _branches.activeUsable;
    return Scaffold(
      backgroundColor: c.paper,
      appBar: AppBar(
        title: const Text('Traslados'),
        actions: [
          IconButton(tooltip: 'Actualizar', onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh_outlined)),
          if (TransfersScreen.canSend() && usable)
            Padding(
              padding: const EdgeInsets.only(right: AppSpace.md),
              child: FilledButton.icon(
                onPressed: _newTransfer,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Nuevo'),
              ),
            ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.sm, AppSpace.lg, 0),
                child: Text('${widget.business.name} · ${_branches.nameOf(_here)}', style: AppText.small(context, color: c.inkMuted)),
              ),
              SizedBox(
                height: 56,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.sm),
                  children: [
                    _chip(_Tab.incoming, 'Te llegan · ${incoming.length}'),
                    _chip(_Tab.sent, 'Enviados · ${sent.length}'),
                    _chip(_Tab.history, 'Historial'),
                  ],
                ),
              ),
              Expanded(child: _body(shown)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(_Tab tab, String label) => Padding(
        padding: const EdgeInsets.only(right: AppSpace.sm),
        child: ChoiceChip(label: Text(label), selected: _tab == tab, onSelected: (_) => setState(() => _tab = tab)),
      );

  Widget _body(List<StockTransfer> shown) {
    final c = context.colors;
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.xl),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_error!, textAlign: TextAlign.center, style: AppText.body(context, color: c.inkMuted)),
            const SizedBox(height: AppSpace.md),
            OutlinedButton(onPressed: _load, child: const Text('Reintentar')),
          ]),
        ),
      );
    }
    if (shown.isEmpty) {
      final text = switch (_tab) {
        _Tab.incoming => 'No te llega nada por ahora.',
        _Tab.sent => 'No tienes traslados en camino.',
        _Tab.history => 'Todavía no hay traslados.',
      };
      return Center(child: Text(text, style: AppText.body(context, color: c.inkMuted)));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(AppSpace.lg, 0, AppSpace.lg, AppSpace.xl),
        itemCount: shown.length,
        itemBuilder: (_, i) => _card(shown[i]),
      ),
    );
  }

  Widget _card(StockTransfer t) {
    final c = context.colors;
    final me = AuthRepository.instance.currentUser?.email.toLowerCase();
    final incoming = t.toBranchId == _here;
    final outgoing = t.fromBranchId == _here;
    final title = incoming && !outgoing
        ? 'Desde ${_branches.nameOf(t.fromBranchId)}'
        : outgoing && !incoming
            ? 'A ${_branches.nameOf(t.toBranchId)}'
            : '${_branches.nameOf(t.fromBranchId)} → ${_branches.nameOf(t.toBranchId)}';
    final (label, tone) = switch (t.status) {
      TransferStatus.inTransit => ('En camino', AppTone.warning),
      TransferStatus.unverified => ('Por verificar', AppTone.warning),
      TransferStatus.cancelled => ('Cancelado', AppTone.neutral),
      _ => t.missing > 0 ? ('Faltó ${t.missing}', AppTone.danger) : ('Recibido', AppTone.success),
    };
    final who = switch (t.status) {
      TransferStatus.inTransit => 'Envió ${t.sentByName ?? t.sentByEmail} · ${_when(t.sentAt)}',
      TransferStatus.cancelled => 'Cancelado · enviado el ${_when(t.sentAt)}',
      _ => [
          'Recibió ${t.receivedByName ?? ''}${t.receivedAsLead ? ' (encargado)' : ''} ${t.receivedUnits} de ${t.units}',
          if (t.receivedAt != null) _when(t.receivedAt!),
          if (t.verifiedByName != null) 'verificó ${t.verifiedByName}',
        ].join(' · '),
    };
    final busy = _busy == t.id;
    final canReceive = t.inTransit && incoming && _branches.activeUsable;
    final canCancel = t.inTransit && (TransfersScreen.isManager || t.sentByEmail.toLowerCase() == me);
    final canVerify = t.unverified && incoming && (TransfersScreen.isManager || ShiftLead.active);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.md),
      child: AppCard(
        onTap: canReceive ? () => _receive(t) : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(child: Text(title, style: AppText.bodyLarge(context, weight: FontWeight.w700))),
              StatusPill(label, tone: tone, compact: true),
            ]),
            const SizedBox(height: AppSpace.xs),
            Text(_summary(t), style: AppText.body(context, color: c.inkMuted)),
            Text(who, style: AppText.small(context, color: c.inkMuted)),
            if ((t.note ?? '').isNotEmpty) Text('Nota: ${t.note}', style: AppText.small(context, color: c.inkMuted)),
            if ((t.receiveNote ?? '').isNotEmpty) Text('Al recibir: ${t.receiveNote}', style: AppText.small(context, color: c.inkMuted)),
            if (canReceive || canCancel || canVerify) ...[
              const SizedBox(height: AppSpace.sm),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (canCancel && !incoming)
                    OutlinedButton(onPressed: busy ? null : () => _cancel(t), child: const Text('Cancelar')),
                  if (canVerify) FilledButton(onPressed: busy ? null : () => _verify(t), child: const Text('Verificar')),
                  if (canReceive) FilledButton(onPressed: busy ? null : () => _receive(t), child: const Text('Recibir')),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _summary(StockTransfer t) {
    if (t.lines.length == 1) return '${t.lines.first.label} · ${unitsText(t.units)}';
    return '${t.lines.length} productos · ${unitsText(t.units)}';
  }

  static String _when(DateTime d) {
    final now = DateTime.now();
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final time = '$h:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? 'a. m.' : 'p. m.'}';
    if (DateUtils.isSameDay(d, now)) return 'hoy $time';
    if (DateUtils.isSameDay(d, now.subtract(const Duration(days: 1)))) return 'ayer $time';
    return '${d.day}/${d.month} $time';
  }
}

/// Recibir un traslado: cada línea trae lo enviado y se cambia si llegó menos
class ReceiveTransferScreen extends StatefulWidget {
  final StockTransfer transfer;
  const ReceiveTransferScreen({super.key, required this.transfer});

  /// Recibe de forma definitiva: el dueño, un administrador o el encargado de turno.
  /// Si no, queda «por verificar» (la nube lo decide igual).
  static bool get receivesFinal => TransfersScreen.isManager || ShiftLead.active;

  @override
  State<ReceiveTransferScreen> createState() => _ReceiveTransferScreenState();
}

class _ReceiveTransferScreenState extends State<ReceiveTransferScreen> {
  late final Map<String, TextEditingController> _fields = {
    for (final l in widget.transfer.lines) l.id: TextEditingController(text: '${l.sent}'),
  };
  final _note = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    for (final f in _fields.values) {
      f.dispose();
    }
    _note.dispose();
    super.dispose();
  }

  int _got(TransferLine l) => (int.tryParse(_fields[l.id]!.text.trim()) ?? 0).clamp(0, l.sent);
  int get _total => widget.transfer.lines.fold(0, (s, l) => s + _got(l));
  int get _missing => widget.transfer.units - _total;
  bool get _tooMany => widget.transfer.lines.any((l) => (int.tryParse(_fields[l.id]!.text.trim()) ?? 0) > l.sent);

  Future<void> _save() async {
    final t = widget.transfer;
    if (_tooMany) {
      AppToast.showWarning(context, 'No puede llegar más de lo que se envió.');
      return;
    }
    if (_missing > 0 && _note.text.trim().isEmpty) {
      AppToast.showWarning(context, 'Escribe una nota de lo que faltó.');
      return;
    }
    setState(() => _saving = true);
    try {
      final received = {for (final l in t.lines) l.id: _got(l)};
      final done = await TransferRepository.instance.receive(t, received: received, note: _note.text.trim());
      final from = BranchRepository.instance.nameOf(t.fromBranchId);
      ActivityRepository.instance.log(
        businessId: t.businessId,
        action: ActivityAction.transferReceive,
        summary: [
          'Recibió $_total de ${unitsText(t.units)} desde $from',
          if (_missing > 0) '(faltaron $_missing)',
          if (ShiftLead.active && !TransfersScreen.isManager) 'como encargado',
          if (!done) 'por verificar',
        ].join(' '),
        data: {'transfer_id': t.id},
      );
      if (!mounted) return;
      AppToast.showSuccess(
        context,
        done
            ? 'Listo: ${unitsText(_total)} ${_total == 1 ? 'entró' : 'entraron'} al stock.'
            : 'Recibido por verificar: ya se puede vender.',
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        AppToast.showError(context, TransferRepository.friendlyError(e));
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = widget.transfer;
    final provisional = !ReceiveTransferScreen.receivesFinal;
    return Scaffold(
      backgroundColor: c.paper,
      appBar: AppBar(title: Text('Recibir desde ${BranchRepository.instance.nameOf(t.fromBranchId)}')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(AppSpace.lg),
                  children: [
                    Text('Envió ${t.sentByName ?? t.sentByEmail}. Cuenta lo que llegó; si llegó menos, cambia el número.',
                        style: AppText.body(context, color: c.inkMuted)),
                    const SizedBox(height: AppSpace.md),
                    AppCard(
                      child: Column(children: [
                        for (final l in t.lines) _line(l),
                      ]),
                    ),
                    const SizedBox(height: AppSpace.md),
                    TextField(
                      controller: _note,
                      maxLength: 500,
                      maxLines: 3,
                      decoration: InputDecoration(labelText: _missing > 0 ? 'Nota del faltante' : 'Nota (opcional)'),
                    ),
                    if (provisional)
                      Container(
                        padding: const EdgeInsets.all(AppSpace.md),
                        decoration: BoxDecoration(color: c.warningSoft, borderRadius: BorderRadius.circular(AppRadius.control)),
                        child: Text(
                          'No eres encargado de esta sede. Lo recibes de forma provisional: las unidades entran y se '
                          'pueden vender, y un administrador lo verifica después.',
                          style: AppText.small(context),
                        ),
                      ),
                  ],
                ),
              ),
              Container(
                decoration: BoxDecoration(color: c.surface, border: Border(top: BorderSide(color: c.line))),
                padding: EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.md, AppSpace.lg, AppSpace.md + MediaQuery.paddingOf(context).bottom),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(children: [
                      Expanded(child: Text('${_total == 1 ? 'Llega' : 'Llegan'} $_total de ${t.units}', style: AppText.body(context))),
                      if (_missing > 0) Text('Falta $_missing', style: AppText.body(context, weight: FontWeight.w700, color: c.danger)),
                    ]),
                    const SizedBox(height: AppSpace.sm),
                    FilledButton(
                      onPressed: _saving ? null : _save,
                      child: Text(_saving ? 'Guardando…' : provisional ? 'Recibir provisionalmente' : 'Recibir ${unitsText(_total)}'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _line(TransferLine l) {
    final c = context.colors;
    final got = int.tryParse(_fields[l.id]!.text.trim()) ?? 0;
    final short = got < l.sent;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(l.label, style: AppText.body(context, weight: FontWeight.w600)),
            Text(
              short ? 'Enviaron ${l.sent} · falta ${l.sent - got}' : 'Enviaron ${l.sent}',
              style: AppText.small(context, color: short ? c.danger : c.inkMuted),
            ),
          ]),
        ),
        SizedBox(
          width: 88,
          child: TextField(
            controller: _fields[l.id],
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            textAlign: TextAlign.center,
            decoration: const InputDecoration(labelText: 'Llegó', isDense: true),
            onChanged: (_) => setState(() {}),
          ),
        ),
      ]),
    );
  }
}
