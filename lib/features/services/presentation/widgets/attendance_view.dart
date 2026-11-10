import 'package:flutter/material.dart';

import '../../../../core/design/app_card.dart';
import '../../../../core/design/content_width.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../business/models/business.dart';
import '../../data/service_board.dart';
import '../../data/services_repository.dart';

/// Servicios › Asistencia: al empezar el día se marca quién vino. A quien no
/// vino, está en pausa o ya salió no se le puede asignar trabajo.
class AttendanceView extends StatefulWidget {
  final Business business;

  /// Lleva a Ajustes › Equipo, donde se agregan las personas
  final VoidCallback? onOpenTeam;

  const AttendanceView({super.key, required this.business, this.onOpenTeam});

  @override
  State<AttendanceView> createState() => _AttendanceViewState();
}

class _AttendanceViewState extends State<AttendanceView> {
  final _repo = ServicesRepository.instance;
  ServiceBoard? _board;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final board = await _repo.loadBoard(widget.business.id);
    if (mounted) setState(() => _board = board);
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
    final id = widget.business.id;

    return RefreshIndicator(
      onRefresh: _load,
      child: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.xs, AppSpace.lg, AppSpace.xxl),
          children: [
            Text('Hoy', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.ink)),
            Text('Marca quién vino al empezar el día. Solo quien llegó y está libre puede recibir servicios.',
                style: TextStyle(fontSize: 13, color: c.inkMuted)),
            const SizedBox(height: AppSpace.md),
            if (people.isEmpty)
              AppCard(
                onTap: widget.onOpenTeam,
                child: Row(
                  children: [
                    Expanded(
                      child: Text('Aún no hay personas para hacer los servicios. Agrégalas en Ajustes › Equipo.',
                          style: TextStyle(color: c.ink)),
                    ),
                    if (widget.onOpenTeam != null) Icon(Icons.chevron_right_rounded, color: c.inkFaint),
                  ],
                ),
              ),
            for (final s in people) ...[
              Builder(builder: (context) {
                final state = board.stateOf(s.id);
                final a = board.attendance[s.id];
                final detail = [
                  state.label,
                  if (a?.arrivedAt != null) 'llegó ${_hour(a!.arrivedAt)}',
                  if (a?.leftAt != null) 'salió ${_hour(a!.leftAt)}',
                  if (state == StaffState.busy) 'en ${board.activeLineOf(s.id)!.order.title}',
                ].join(' · ');
                return AppCard(
                  padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.md, AppSpace.sm, AppSpace.sm),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.name, style: TextStyle(fontWeight: FontWeight.w700, color: c.ink)),
                      Text(detail, style: TextStyle(fontSize: 12.5, color: c.inkMuted)),
                      const SizedBox(height: AppSpace.xs),
                      Wrap(
                        spacing: AppSpace.xs,
                        children: [
                          if (state == StaffState.notMarked || state == StaffState.absent || state == StaffState.left)
                            TextButton(
                              onPressed: _busy ? null : () => _run(() => _repo.markArrived(id, s.id)),
                              child: Text(state == StaffState.left ? 'Volvió' : 'Llegó'),
                            ),
                          if (state == StaffState.notMarked)
                            TextButton(
                              onPressed: _busy ? null : () => _run(() => _repo.markAbsent(id, s.id, board: board)),
                              child: const Text('No vino'),
                            ),
                          if (state == StaffState.available || state == StaffState.paused)
                            TextButton(
                              onPressed: _busy ? null : () => _run(() => _repo.togglePause(id, s.id, board: board)),
                              child: Text(state == StaffState.paused ? 'Terminar pausa' : 'Pausa'),
                            ),
                          if (state == StaffState.available || state == StaffState.paused)
                            TextButton(
                              onPressed: _busy ? null : () => _run(() => _repo.markLeft(id, s.id, board: board)),
                              child: const Text('Salida'),
                            ),
                        ],
                      ),
                    ],
                  ),
                );
              }),
              const SizedBox(height: AppSpace.sm),
            ],
          ],
        ),
      ),
    );
  }
}
