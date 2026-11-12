import 'package:flutter/material.dart';

import '../../../../core/design/status_pill.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../business/data/business_repository.dart';
import '../../../business/models/business.dart';
import '../../data/commissions_repository.dart';
import '../../data/service_board.dart';
import '../../data/services_repository.dart';
import '../../models/commission_models.dart';
import '../../models/work_schedule.dart';
import 'schedule_editor.dart';
import 'staff_section.dart';

/// Servicios › Empleados (antes «Asistencia», 0.13.1): quién vino, qué está haciendo
/// y lo que lleva hoy cada uno. Se agregan personas aquí mismo (la misma hoja de
/// Ajustes › Equipo) y se elige si cada uno puede hacer más de 2 servicios a la vez.
class EmployeesView extends StatefulWidget {
  final Business business;

  /// Dueño o administrador: agrega personas y cambia el límite de servicios
  final bool canEdit;

  /// Lleva a la pestaña Comisiones
  final VoidCallback? onOpenCommissions;

  const EmployeesView({super.key, required this.business, this.canEdit = false, this.onOpenCommissions});

  @override
  State<EmployeesView> createState() => _EmployeesViewState();
}

class _EmployeesViewState extends State<EmployeesView> {
  final _repo = ServicesRepository.instance;
  ServiceBoard? _board;
  Map<String, StaffEarnings> _today = const {};
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final id = widget.business.id;
    final board = await _repo.loadBoard(id);
    final now = DateTime.now();
    final earned = await CommissionsRepository.instance
        .earnedBetween(id, DateTime(now.year, now.month, now.day), now.add(const Duration(seconds: 1)));
    if (!mounted) return;
    setState(() {
      _board = board;
      _today = {for (final e in earned) e.staffId: e};
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } on StateError catch (e) {
      if (mounted) AppToast.showWarning(context, e.message);
    } catch (e) {
      if (mounted) AppToast.showError(context, '$e');
    } finally {
      await _load();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editGlobalSchedule(WorkSchedule? current) async {
    final picked = await ScheduleEditor.show(
      context,
      title: 'Horario del negocio',
      subtitle: 'Vale para todos los empleados que no tengan un horario propio. Fuera de turno solo se avisa.',
      initial: current,
    );
    if (picked == null || !mounted) return;
    await _run(() async {
      await BusinessRepository.instance
          .updateBusiness(id: widget.business.id, servicesSchedule: picked.isEmpty ? '' : picked.encode());
    });
  }

  Future<void> _add() async {
    if (await StaffEditor.show(context, business: widget.business)) await _load();
  }

  String _hour(DateTime? d) {
    if (d == null) return '';
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    return '$h:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? 'a. m.' : 'p. m.'}';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final board = _board;
    if (board == null) return const Center(child: CircularProgressIndicator());
    final people = board.staff.where((s) => s.isActive).toList();
    final multi = board.maxPerStaff == null;

    return ColoredBox(
      color: c.paper,
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.xs, AppSpace.lg, AppSpace.xxl),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
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
                            Text('Empleados hoy', style: AppText.title(context)),
                            Text('Marca quién vino. Solo quien llegó y tiene espacio recibe servicios.', style: AppText.small(context)),
                          ],
                        ),
                        if (widget.canEdit)
                          FilledButton.icon(
                            onPressed: _add,
                            icon: const Icon(Icons.person_add_alt_outlined, size: 18),
                            label: const Text('Agregar empleado'),
                          ),
                      ],
                    ),
                    if (widget.canEdit) ...[
                      const SizedBox(height: AppSpace.md),
                      _card(
                        child: SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          value: multi,
                          onChanged: _busy ? null : (v) => _run(() => _repo.setMultipleServices(widget.business.id, v)),
                          title: Text('Habilitar múltiples servicios', style: AppText.body(context, weight: FontWeight.w600)),
                          subtitle: Text(
                            multi
                                ? 'Cada empleado puede tener los servicios que haga falta a la vez. Úsalo si hay pocos empleados y mucha cola.'
                                : 'Cada empleado hace hasta ${ServiceBoard.defaultMax} servicios a la vez.',
                            style: AppText.small(context),
                          ),
                        ),
                      ),
                    ],
                    if (widget.canEdit || board.globalSchedule != null) ...[
                      const SizedBox(height: AppSpace.sm),
                      _card(
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.schedule_outlined),
                          title: Text('Horario del negocio', style: AppText.body(context, weight: FontWeight.w600)),
                          subtitle: Text(
                            board.globalSchedule?.describe() ?? 'Sin horario. Ponlo para saber quién llega tarde o sigue fuera de turno.',
                            style: AppText.small(context),
                          ),
                          trailing: widget.canEdit
                              ? TextButton(
                                  onPressed: _busy ? null : () => _editGlobalSchedule(board.globalSchedule),
                                  child: Text(board.globalSchedule == null ? 'Poner' : 'Cambiar'),
                                )
                              : null,
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpace.md),
                    if (people.isEmpty)
                      _card(
                        child: Text(
                          widget.canEdit
                              ? 'Aún no hay empleados. Toca «Agregar empleado» para empezar.'
                              : 'Aún no hay empleados. El dueño o un administrador los agrega aquí.',
                          style: AppText.body(context, color: c.inkMuted),
                        ),
                      ),
                    for (final s in people) ...[_person(board, s.id), const SizedBox(height: AppSpace.sm)],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _card({required Widget child}) => Material(
        color: context.colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: BorderSide(color: context.colors.line),
        ),
        child: Padding(padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.sm), child: child),
      );

  Widget _person(ServiceBoard board, String staffId) {
    final c = context.colors;
    final s = board.staffOf(staffId)!;
    final id = widget.business.id;
    final state = board.stateOf(staffId);
    final a = board.attendance[staffId];
    final active = board.activeLinesOf(staffId);
    final earned = _today[staffId];
    final now = DateTime.now();
    final schedule = board.scheduleOf(staffId);
    final todayShift = schedule?.on(now);
    final warning = board.shiftWarning(staffId, now);
    final tone = switch (state) {
      StaffState.available => AppTone.success,
      StaffState.busy => AppTone.info,
      StaffState.paused => AppTone.warning,
      _ => AppTone.neutral,
    };
    final stateText = active.isNotEmpty && state == StaffState.available
        ? 'Con ${active.length} ${active.length == 1 ? 'servicio' : 'servicios'}'
        : state.label;
    final detail = [
      if (a?.arrivedAt != null) 'Llegó ${_hour(a!.arrivedAt)}',
      if (a?.leftAt != null) 'salió ${_hour(a!.leftAt)}',
      if (active.isNotEmpty) 'en ${active.map((r) => r.order.title).join(', ')}',
    ].join(' · ');

    Widget action(String label, Future<void> Function() run) =>
        TextButton(onPressed: _busy ? null : () => _run(run), child: Text(label));

    return _card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: widget.canEdit
                        ? () async {
                            if (await StaffEditor.show(context, business: widget.business, person: s)) await _load();
                          }
                        : null,
                    child: Text(s.name, style: AppText.bodyLarge(context, weight: FontWeight.w700)),
                  ),
                ),
                StatusPill(stateText, tone: tone, dot: true),
              ],
            ),
            if (schedule != null && !schedule.isEmpty)
              Text(
                todayShift == null ? 'Hoy descansa' : 'Turno hoy: ${todayShift.label}'
                    '${WorkSchedule.decode(s.schedule) != null ? ' (propio)' : ''}',
                style: AppText.small(context),
              ),
            if (detail.isNotEmpty) Text(detail, style: AppText.small(context)),
            if (warning != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(warning, style: AppText.small(context, weight: FontWeight.w600, color: c.warning)),
              ),
            // Lo que lleva hoy: servicios cobrados y su comisión, sin cerrar la caja
            Padding(
              padding: const EdgeInsets.only(top: AppSpace.xs),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      earned == null
                          ? 'Hoy: sin servicios cobrados todavía'
                          : 'Hoy: ${earned.services} ${earned.services == 1 ? 'servicio' : 'servicios'} · '
                              'comisión ${CurrencyFormatter.format(earned.commissions)}'
                              '${earned.tips > 0 ? ' · propinas ${CurrencyFormatter.format(earned.tips)}' : ''}',
                      style: AppText.small(context, weight: FontWeight.w600, color: c.ink),
                    ),
                  ),
                  if (widget.onOpenCommissions != null && earned != null)
                    TextButton(onPressed: widget.onOpenCommissions, child: const Text('Ver en Comisiones')),
                ],
              ),
            ),
            Wrap(
              spacing: AppSpace.xs,
              children: [
                if (state == StaffState.notMarked || state == StaffState.absent || state == StaffState.left)
                  action(state == StaffState.left ? 'Volvió' : 'Llegó', () => _repo.markArrived(id, staffId)),
                if (state == StaffState.notMarked) action('No vino', () => _repo.markAbsent(id, staffId, board: board)),
                if ((state == StaffState.available || state == StaffState.paused) && active.isEmpty)
                  action(state == StaffState.paused ? 'Terminar pausa' : 'Pausa', () => _repo.togglePause(id, staffId, board: board)),
                if ((state == StaffState.available || state == StaffState.paused) && active.isEmpty)
                  action('Se va', () => _repo.markLeft(id, staffId, board: board)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
