import 'package:flutter/material.dart';

import '../../../../core/design/app_dialog.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../models/work_schedule.dart';

/// LA hoja para editar un horario (del negocio o de un empleado), día por día.
/// Devuelve el horario nuevo; uno vacío ([WorkSchedule.isEmpty]) = quitarlo; null = cancelar.
class ScheduleEditor extends StatefulWidget {
  final WorkSchedule initial;
  final String removeLabel;

  const ScheduleEditor({super.key, required this.initial, required this.removeLabel});

  static Future<WorkSchedule?> show(
    BuildContext context, {
    required String title,
    String? subtitle,
    WorkSchedule? initial,
    String removeLabel = 'Quitar horario',
  }) =>
      AppSheet.show<WorkSchedule>(
        context: context,
        title: title,
        subtitle: subtitle,
        builder: (_) => ScheduleEditor(initial: initial ?? WorkSchedule.typical, removeLabel: removeLabel),
      );

  @override
  State<ScheduleEditor> createState() => _ScheduleEditorState();
}

class _ScheduleEditorState extends State<ScheduleEditor> {
  late final Map<int, ShiftTime> _days = Map.of(widget.initial.days);

  /// Para encender un día se copia el último turno usado
  ShiftTime get _lastShift => _days.isEmpty ? const ShiftTime(480, 1080) : _days.values.last;

  Future<void> _pick(int day, bool start) async {
    final shift = _days[day]!;
    final current = start ? shift.start : shift.end;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current ~/ 60 % 24, minute: current % 60),
      helpText: start ? 'Entra a las' : 'Sale a las',
    );
    if (t == null || !mounted) return;
    final m = t.hour * 60 + t.minute;
    final next = start ? ShiftTime(m, shift.end) : ShiftTime(shift.start, m);
    if (next.end <= next.start) {
      AppToast.showWarning(context, 'La hora de salida debe ser después de la de entrada.');
      return;
    }
    setState(() => _days[day] = next);
  }

  void _copyToAll(int day) {
    final shift = _days[day]!;
    setState(() {
      for (final d in _days.keys.toList()) {
        _days[d] = shift;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var d = 1; d <= 7; d++)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.xs),
            child: Row(
              children: [
                SizedBox(
                  width: 84,
                  child: CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: _days.containsKey(d),
                    onChanged: (on) => setState(() => on == true ? _days[d] = _lastShift : _days.remove(d)),
                    title: Text(WorkSchedule.dayNames[d - 1], style: AppText.body(context, weight: FontWeight.w600)),
                  ),
                ),
                Expanded(
                  child: _days.containsKey(d)
                      ? Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: AppSpace.xs,
                          children: [
                            OutlinedButton(onPressed: () => _pick(d, true), child: Text(ShiftTime.clock(_days[d]!.start))),
                            Text('a', style: AppText.small(context)),
                            OutlinedButton(onPressed: () => _pick(d, false), child: Text(ShiftTime.clock(_days[d]!.end))),
                            if (_days.length > 1)
                              IconButton(
                                tooltip: 'Usar esta hora en todos los días',
                                onPressed: () => _copyToAll(d),
                                icon: const Icon(Icons.copy_all_outlined, size: 18),
                              ),
                          ],
                        )
                      : Text('No trabaja', style: AppText.small(context, color: c.inkMuted)),
                ),
              ],
            ),
          ),
        const SizedBox(height: AppSpace.md),
        FilledButton(
          onPressed: _days.isEmpty ? null : () => Navigator.pop(context, WorkSchedule(Map.of(_days))),
          child: const Text('Guardar horario'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, const WorkSchedule({})),
          child: Text(widget.removeLabel),
        ),
      ],
    );
  }
}
