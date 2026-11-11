import 'package:flutter/material.dart';

import '../../../../core/design/app_card.dart';
import '../../../../core/design/primary_action_button.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../business/models/business.dart';
import '../../data/order_whatsapp.dart';
import '../../data/service_board.dart';
import '../../data/services_repository.dart';
import '../../models/phase_messages.dart';
import '../../models/service_models.dart';
import 'checkout_sheet.dart';
import 'receive_sheet.dart';
import '../../../../core/design/app_dialog.dart';

/// Servicios › Tablero: los trabajos del día por columna, cada servicio con su
/// estado y quién lo hace. Aplica las reglas de [ServiceBoard].
class ServiceBoardView extends StatefulWidget {
  final Business business;
  final ServiceTemplate template;
  final VoidCallback? onOpenAttendance;

  const ServiceBoardView({super.key, required this.business, required this.template, this.onOpenAttendance});

  @override
  State<ServiceBoardView> createState() => _ServiceBoardViewState();
}

class _ServiceBoardViewState extends State<ServiceBoardView> {
  final _repo = ServicesRepository.instance;
  ServiceBoard? _board;
  bool _busy = false;

  ServiceTemplate get _t => widget.template;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final board = await _repo.loadBoard(widget.business.id);
    if (mounted) setState(() => _board = board);
  }

  String _names(List<String> ids) =>
      ids.map((id) => _board?.staffOf(id)?.name.split(' ').first ?? 'Alguien').join(' y ');

  /// Ejecuta una acción, muestra el motivo si las reglas no la permiten y recarga
  Future<T?> _run<T>(Future<T> Function() action) async {
    if (_busy) return null;
    setState(() => _busy = true);
    try {
      return await action();
    } on StateError catch (e) {
      if (mounted) AppToast.showWarning(context, e.message);
      return null;
    } catch (e) {
      if (mounted) AppToast.showError(context, e.toString().replaceFirst('Exception: ', ''));
      return null;
    } finally {
      if (mounted) setState(() => _busy = false);
      await _load();
    }
  }

  Map<String, String> get _staffNames => {for (final s in _board?.staff ?? const <StaffMember>[]) s.id: s.name};

  /// Ofrece enviar el mensaje de la fase por WhatsApp (si está encendida y hay número)
  Future<void> _offerPhase(WorkOrder order, MessagePhase phase, {bool askEvenWithoutPhone = false}) async {
    if (!mounted) return;
    if (!askEvenWithoutPhone && (order.customerPhone ?? '').trim().isEmpty) return;
    final board = _board;
    final text = OrderWhatsApp.phaseText(
      phase,
      order,
      widget.business,
      staffNames: _staffNames,
      turn: board?.turnOf(order),
      waitMinutes: board?.estimatedWait(order),
    );
    if (text == null) {
      if (askEvenWithoutPhone) AppToast.showWarning(context, 'El mensaje «${phase.label}» está apagado en Mensajes.');
      return;
    }
    final send = await showDialog<bool>(
      context: context,
      builder: (ctx) => AppDialog(
title: '¿Le escribes por WhatsApp? · ${phase.label}',
content: Text(text),
actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Enviar')),
        ],
),
    );
    if (send == true) await OrderWhatsApp.send(order, widget.business, text);
  }

  /// Menú «Enviar mensaje»: elegir la fase
  Future<void> _chooseMessage(WorkOrder order) async {
    final enabled = [
      for (final p in MessagePhase.values)
        if (PhaseMessages.of(widget.business.serviceMessages, _t).phases[p]!.enabled) p,
    ];
    if (enabled.isEmpty) {
      AppToast.showWarning(context, 'Todos los mensajes están apagados. Enciéndelos en Servicios › Mensajes.');
      return;
    }
    final phase = await showModalBottomSheet<MessagePhase>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final p in enabled)
              ListTile(
                leading: const Icon(Icons.chat_outlined),
                title: Text(p.label),
                subtitle: Text(p.when),
                onTap: () => Navigator.pop(ctx, p),
              ),
          ],
        ),
      ),
    );
    if (phase != null) await _offerPhase(order, phase, askEvenWithoutPhone: true);
  }

  Future<void> _receive() async {
    final saved = await ReceiveSheet.show(context, business: widget.business, template: _t);
    if (saved != null) {
      await _load();
      await _offerPhase(saved, MessagePhase.received);
    }
  }

  Future<void> _start(WorkOrder order, int index) async {
    final board = _board;
    if (board == null) return;
    final chosen = await _pickStaff(order, index, board);
    if (chosen == null || chosen.isEmpty) return;
    final updated = await _run(() => _repo.startLine(order, index, chosen, board: board));
    // El primer servicio que empieza: mensaje «En proceso»
    if (updated != null && order.status == WorkOrder.waiting && !order.lines.any((l) => !l.isPending)) {
      await _offerPhase(updated, MessagePhase.inProgress);
    }
  }

  Future<void> _finish(WorkOrder order, int index) async {
    final freed = order.lines[index].staffIds;
    final updated = await _run(() => _repo.finishLine(order, index));
    if (updated == null || !mounted) return;
    if (updated.status == WorkOrder.ready) await _offerReadyMessage(updated);
    // Quien terminó queda libre: se le sugiere lo siguiente de la cola
    for (final id in freed) {
      final board = _board;
      final next = board?.suggestionFor(id);
      if (board == null || next == null || !mounted) continue;
      final line = next.order.lines[next.index];
      final turn = board.turnOf(next.order);
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AppDialog(
title: '${board.staffOf(id)?.name ?? 'Alguien'} quedó libre',
content: Text('¿Empieza ${line.name} de ${next.order.title}${turn == null ? '' : ' (turno $turn)'}?'),
actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Ahora no')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Empezar')),
          ],
),
      );
      if (go == true) await _run(() => _repo.startLine(next.order, next.index, [id], board: board));
    }
  }

  Future<void> _offerReadyMessage(WorkOrder order) async {
    if ((order.customerPhone ?? '').trim().isEmpty) {
      AppToast.showSuccess(context, '${order.title} está ${_t.readyLabel.toLowerCase()} para cobrar.');
      return;
    }
    await _offerPhase(order, MessagePhase.ready);
  }

  Future<void> _revert(WorkOrder order) async {
    final board = _board;
    if (board == null) return;
    final candidates = [
      for (var i = 0; i < order.lines.length; i++)
        if (!order.lines[i].isPending) i,
    ];
    if (candidates.isEmpty) {
      AppToast.showWarning(context, 'Ningún servicio ha empezado todavía.');
      return;
    }
    var index = candidates.last;
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AppDialog(
title: 'Retroceder un servicio',
content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RadioGroup<int>(
                groupValue: index,
                onChanged: (v) => setLocal(() => index = v ?? index),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final i in candidates)
                      RadioListTile<int>(
                        contentPadding: EdgeInsets.zero,
                        value: i,
                        title: Text(order.lines[i].name),
                        subtitle: Text(order.lines[i].isDone ? 'Vuelve a En proceso' : 'Vuelve a Pendiente'),
                      ),
                  ],
                ),
              ),
              TextField(
                controller: note,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Motivo (queda en la actividad)'),
              ),
            ],
          ),
actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Retroceder')),
          ],
),
      ),
    );
    final text = note.text;
    note.dispose();
    if (ok == true) await _run(() => _repo.revertLine(order, index, board: board, note: text));
  }

  Future<void> _cancel(WorkOrder order) async {
    if (order.lines.any((l) => l.isInProgress)) {
      AppToast.showWarning(context, 'Hay un servicio en proceso: termínalo o retrocédelo primero.');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AppDialog(
title: '¿Cancelar ${order.title}?',
content: const Text('Sale del tablero sin cobrar nada.'),
actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Volver')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Cancelar trabajo')),
        ],
),
    );
    if (ok == true) await _run(() => _repo.cancel(order));
  }

  Future<void> _checkout(WorkOrder order) async {
    final paid = await CheckoutSheet.show(
      context,
      order: order,
      business: widget.business,
      staffNames: {for (final s in _board?.staff ?? const <StaffMember>[]) s.id: s.name},
    );
    if (paid == true) {
      await _load();
      if (mounted) AppToast.showSuccess(context, 'Cobrado. ${order.title} se entregó.');
      final delivered = await _repo.getOrder(order.id);
      if (delivered != null) await _offerPhase(delivered, MessagePhase.delivered);
    }
  }

  /// Elegir quién hace el servicio: solo quienes vinieron, están libres y lo hacen
  Future<List<String>?> _pickStaff(WorkOrder order, int index, ServiceBoard board) async {
    final eligible = board.eligibleFor(order, index);
    final line = order.lines[index];
    if (eligible.isEmpty) {
      final reasons = [
        for (final s in board.staff.where((s) => s.isActive))
          if (board.whyNotStart(order, index, s.id) case final why?) why,
      ];
      await showDialog<void>(
        context: context,
        builder: (ctx) => AppDialog(
title: 'Nadie libre para este servicio',
content: Text(
            reasons.isEmpty
                ? 'Agrega a las personas que hacen los servicios en Ajustes › Equipo.'
                : '${line.name} queda en cola y se le sugiere a quien se libere primero.\n\n${reasons.join('\n')}',
          ),
actions: [
            if (widget.onOpenAttendance != null)
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  widget.onOpenAttendance!();
                },
                child: const Text('Ir a Asistencia'),
              ),
            FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Entendido')),
          ],
),
      );
      return null;
    }
    final selected = <String>{if (eligible.length == 1) eligible.first.id};
    return showModalBottomSheet<List<String>>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final c = ctx.colors;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(AppSpace.lg, 0, AppSpace.lg, AppSpace.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('¿Quién hace ${line.name}?', style: TextStyle(fontSize: AppText.sizeTitle, fontWeight: FontWeight.w700, color: c.ink)),
                  Text('Solo aparecen quienes vinieron, están libres y hacen este servicio.',
                      style: TextStyle(fontSize: AppText.sizeSmall, color: c.inkMuted)),
                  const SizedBox(height: AppSpace.sm),
                  for (final s in eligible)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: selected.contains(s.id),
                      onChanged: (v) => setLocal(() => v == true ? selected.add(s.id) : selected.remove(s.id)),
                      title: Text(s.name),
                    ),
                  const SizedBox(height: AppSpace.sm),
                  FilledButton(
                    onPressed: selected.isEmpty ? null : () => Navigator.pop(ctx, selected.toList()),
                    child: const Text('Empezar'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final board = _board;
    if (board == null) return const Center(child: CircularProgressIndicator());

    final open = board.orders.where((o) => o.isOpen).toList();
    final waiting = open.where((o) => o.status == WorkOrder.waiting).toList();
    final working = open.where((o) => o.status == WorkOrder.inProgress).toList();
    final ready = open.where((o) => o.status == WorkOrder.ready).toList();
    final deliveredToday = board.orders.where((o) => o.status == WorkOrder.delivered).length;
    final noneMarked = board.staff.isNotEmpty && board.attendance.isEmpty;

    final columns = [
      (_t.waitingLabel, waiting),
      (_t.inProgress, working),
      ('${_t.readyLabel}s para cobrar', ready),
    ];

    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: _load,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 900;
              return ListView(
                padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.xs, AppSpace.lg, 120),
                children: [
                  _staffStrip(board),
                  if (noneMarked) ...[
                    const SizedBox(height: AppSpace.sm),
                    AppCard(
                      color: c.warningSoft,
                      onTap: widget.onOpenAttendance,
                      child: Row(
                        children: [
                          Icon(Icons.how_to_reg_outlined, color: c.warning),
                          const SizedBox(width: AppSpace.md),
                          Expanded(
                            child: Text('Marca quién vino hoy en Asistencia: sin eso nadie puede empezar servicios.',
                                style: TextStyle(color: c.ink)),
                          ),
                          Icon(Icons.chevron_right_outlined, color: c.inkFaint),
                        ],
                      ),
                    ),
                  ],
                  if (board.queueBlocked) ...[
                    const SizedBox(height: AppSpace.sm),
                    AppCard(
                      color: c.infoSoft,
                      child: Text(
                        '${board.queue.length} ${board.queue.length == 1 ? 'servicio espera' : 'servicios esperan'} en cola: '
                        'se le sugieren a quien se libere primero.',
                        style: TextStyle(color: c.ink),
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpace.md),
                  if (open.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: AppSpace.xxl),
                      child: Column(
                        children: [
                          Icon(Icons.view_kanban_outlined, size: 48, color: c.inkFaint),
                          const SizedBox(height: AppSpace.md),
                          Text('No hay ${_t.unitPlural.toLowerCase()} en el tablero',
                              style: TextStyle(color: c.ink, fontWeight: FontWeight.w600, fontSize: AppText.sizeBodyLarge)),
                          const SizedBox(height: AppSpace.xs),
                          Text('Toca «Recibir» cuando llegue un cliente.', style: TextStyle(color: c.inkMuted)),
                          if (deliveredToday > 0) ...[
                            const SizedBox(height: AppSpace.sm),
                            Text('Hoy se entregaron $deliveredToday.', style: TextStyle(color: c.inkMuted)),
                          ],
                        ],
                      ),
                    )
                  else if (wide)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final (title, list) in columns)
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs),
                              child: _column(board, title, list),
                            ),
                          ),
                      ],
                    )
                  else
                    for (final (title, list) in columns)
                      if (list.isNotEmpty) Padding(
                        padding: const EdgeInsets.only(bottom: AppSpace.md),
                        child: _column(board, title, list),
                      ),
                  if (open.isNotEmpty && deliveredToday > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpace.sm),
                      child: Text('Hoy se entregaron $deliveredToday. Míralos en Historial.',
                          style: TextStyle(color: c.inkMuted, fontSize: AppText.sizeSmall)),
                    ),
                ],
              );
            },
          ),
        ),
        Positioned(
          left: AppSpace.lg,
          bottom: MediaQuery.of(context).padding.bottom + AppSpace.lg,
          child: PrimaryActionButton(label: 'Recibir', onPressed: _busy ? null : _receive),
        ),
      ],
    );
  }

  Widget _staffStrip(ServiceBoard board) {
    final c = context.colors;
    final people = board.staff.where((s) => s.isActive).toList();
    if (people.isEmpty) {
      return AppCard(
        color: c.warningSoft,
        child: Text('Aún no hay personas para hacer los servicios. Agrégalas en Ajustes › Equipo.',
            style: TextStyle(color: c.ink)),
      );
    }
    return Wrap(
      spacing: AppSpace.sm,
      runSpacing: AppSpace.sm,
      children: [
        for (final s in people)
          Builder(builder: (context) {
            final state = board.stateOf(s.id);
            final (fg, bg) = switch (state) {
              StaffState.available => (c.success, c.successSoft),
              StaffState.busy => (c.info, c.infoSoft),
              StaffState.paused => (c.warning, c.warningSoft),
              _ => (c.inkMuted, c.surfaceMuted),
            };
            final active = board.activeLineOf(s.id);
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(AppRadius.pill)),
              child: Text(
                '${s.name.split(' ').first} · ${state.label}'
                '${active == null ? '' : ' (${active.order.title})'}',
                style: TextStyle(fontSize: AppText.sizeSmall, fontWeight: FontWeight.w600, color: fg),
              ),
            );
          }),
      ],
    );
  }

  Widget _column(ServiceBoard board, String title, List<WorkOrder> orders) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpace.xs, 0, 0, AppSpace.sm),
          child: Text('${title.toUpperCase()} · ${orders.length}',
              style: TextStyle(fontSize: AppText.sizeCaption, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: c.inkFaint)),
        ),
        for (final o in orders) ...[
          _orderCard(board, o),
          const SizedBox(height: AppSpace.sm),
        ],
      ],
    );
  }

  Widget _orderCard(ServiceBoard board, WorkOrder o) {
    final c = context.colors;
    final turn = o.status == WorkOrder.inProgress ? null : board.turnOf(o);
    final wait = turn == null ? null : board.estimatedWait(o);
    final minutes = DateTime.now().difference(o.since).inMinutes;
    final subtitle = [
      if (o.vehicleKind != null) _t.vehicleLabel(o.vehicleKind),
      if ((o.customerName ?? '').isNotEmpty && o.title != o.customerName) o.customerName!,
      o.statusLabelFor(_t),
      if (turn != null) wait == null ? 'turno $turn' : 'turno $turn, unos $wait min',
      minutes < 1 ? 'ahora' : 'hace $minutes min',
    ].join(' · ');

    return AppCard(
      padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.md, AppSpace.xs, AppSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(o.title, style: TextStyle(fontSize: AppText.sizeTitle, fontWeight: FontWeight.w700, color: c.ink)),
                    Text(subtitle, style: TextStyle(fontSize: AppText.sizeCaption, color: c.inkMuted)),
                  ],
                ),
              ),
              Text(CurrencyFormatter.format(o.subtotal), style: TextStyle(fontWeight: FontWeight.w700, color: c.ink)),
              PopupMenuButton<String>(
                tooltip: 'Más opciones',
                onSelected: (v) => switch (v) {
                  'revert' => _revert(o),
                  'cancel' => _cancel(o),
                  'message' => _chooseMessage(o),
                  _ => null,
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'revert', child: Text('Retroceder un servicio')),
                  const PopupMenuItem(value: 'message', child: Text('Enviar mensaje por WhatsApp')),
                  const PopupMenuItem(value: 'cancel', child: Text('Cancelar trabajo')),
                ],
              ),
            ],
          ),
          const SizedBox(height: AppSpace.xs),
          for (var i = 0; i < o.lines.length; i++) _lineRow(board, o, i),
          if (o.status == WorkOrder.ready)
            Padding(
              padding: const EdgeInsets.only(top: AppSpace.sm, right: AppSpace.md),
              child: FilledButton.icon(
                onPressed: _busy ? null : () => _checkout(o),
                icon: const Icon(Icons.payments_outlined, size: 18),
                label: Text('Cobrar ${CurrencyFormatter.format(o.subtotal)}'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _lineRow(ServiceBoard board, WorkOrder o, int i) {
    final c = context.colors;
    final l = o.lines[i];
    final delay = board.delayOf(l, DateTime.now());
    final (icon, color, status) = switch (l.status) {
      WorkOrderLine.inProgress => (Icons.timelapse_outlined, c.info, '${_t.inProgress} · ${_names(l.staffIds)}'),
      WorkOrderLine.done => (Icons.check_circle_outlined, c.success, 'Terminado · ${_names(l.staffIds)}'),
      _ => (Icons.radio_button_unchecked_outlined, c.inkFaint, 'Pendiente'),
    };
    return Padding(
      padding: const EdgeInsets.only(right: AppSpace.sm),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.name, style: TextStyle(fontSize: AppText.sizeBody, color: c.ink, fontWeight: FontWeight.w600)),
                Text(status, style: TextStyle(fontSize: AppText.sizeCaption, color: c.inkMuted)),
                if (delay != null)
                  Text('Demorado: lleva $delay min más de lo estimado',
                      style: TextStyle(fontSize: AppText.sizeCaption, fontWeight: FontWeight.w600, color: c.danger)),
              ],
            ),
          ),
          if (l.isPending)
            TextButton(onPressed: _busy ? null : () => _start(o, i), child: const Text('Empezar'))
          else if (l.isInProgress)
            TextButton(onPressed: _busy ? null : () => _finish(o, i), child: const Text('Terminar')),
        ],
      ),
    );
  }
}
