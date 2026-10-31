import 'package:flutter/material.dart';

import '../../../../core/design/app_time_picker.dart';
import '../../../../core/design/primary_action_button.dart';
import '../../../../core/services/phone_alerts_service.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../data/debt_reminder_schedule.dart';
import '../../models/customer.dart';

/// Elige cada cuánto y a qué hora el celular recuerda cobrarle a un cliente
/// (Stockealo Pro). Devuelve true si se guardó o se quitó el recordatorio.
class DebtReminderScheduleSheet extends StatefulWidget {
  final Customer customer;
  final DebtReminderSchedule? current;

  const DebtReminderScheduleSheet({super.key, required this.customer, this.current});

  static Future<bool?> show(BuildContext context, {required Customer customer, DebtReminderSchedule? current}) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      backgroundColor: Colors.transparent,
      builder: (_) => DebtReminderScheduleSheet(customer: customer, current: current),
    );
  }

  @override
  State<DebtReminderScheduleSheet> createState() => _DebtReminderScheduleSheetState();
}

class _DebtReminderScheduleSheetState extends State<DebtReminderScheduleSheet> {
  late int _everyDays = widget.current?.everyDays ?? 7;
  late TimeOfDay _time = TimeOfDay(hour: widget.current?.hour ?? 9, minute: widget.current?.minute ?? 0);
  bool _saving = false;

  Future<void> _pickTime() async {
    final picked = await showAppTimePicker(context, initialTime: _time, helpText: 'Hora del aviso');
    if (picked != null) setState(() => _time = picked);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final now = DateTime.now();
    final ok = await PhoneAlertsService.instance.setDebtReminder(DebtReminderSchedule(
      customerId: widget.customer.id,
      businessId: widget.customer.businessId,
      everyDays: _everyDays,
      hour: _time.hour,
      minute: _time.minute,
      startsOn: DateTime(now.year, now.month, now.day),
    ));
    if (!mounted) return;
    setState(() => _saving = false);
    if (!ok) {
      AppToast.show(context,
          message: 'Activa las notificaciones de Stockealo en los ajustes del celular.', type: ToastType.warning);
      return;
    }
    Navigator.pop(context, true);
  }

  Future<void> _remove() async {
    await PhoneAlertsService.instance.removeDebtReminder(widget.customer.id);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.paper,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('Recordatorio de cobro',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c.ink)),
                  ),
                  IconButton(
                    tooltip: 'Cerrar',
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close_rounded, color: c.inkMuted),
                  ),
                ],
              ),
              Text(
                'Te avisamos en el celular "Hoy toca cobrarle a ${widget.customer.name}". '
                'Al tocar el aviso se abre WhatsApp con el mensaje listo: tú decides si lo envías.',
                style: TextStyle(fontSize: 13, color: c.inkMuted),
              ),
              const SizedBox(height: AppSpace.lg),
              Text('Cada cuánto', style: TextStyle(fontSize: 13, color: c.inkMuted)),
              const SizedBox(height: AppSpace.sm),
              Wrap(
                spacing: AppSpace.sm,
                runSpacing: AppSpace.sm,
                children: [
                  for (final days in DebtReminderSchedule.frequencies)
                    ChoiceChip(
                      label: Text(DebtReminderSchedule.frequencyText(days)),
                      selected: _everyDays == days,
                      onSelected: (_) => setState(() => _everyDays = days),
                    ),
                ],
              ),
              const SizedBox(height: AppSpace.lg),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.schedule_rounded, color: c.inkMuted),
                title: Text('Hora del aviso', style: TextStyle(color: c.ink)),
                trailing: Text(
                  formatAppTime(_time),
                  style: TextStyle(color: c.accent, fontWeight: FontWeight.w700, fontSize: 15),
                ),
                onTap: _pickTime,
              ),
              const SizedBox(height: AppSpace.md),
              SizedBox(
                width: double.infinity,
                child: PrimaryActionButton(
                  label: widget.current == null ? 'Activar recordatorio' : 'Guardar cambios',
                  icon: Icons.notifications_active_outlined,
                  onPressed: _saving ? null : _save,
                ),
              ),
              if (widget.current != null) ...[
                const SizedBox(height: AppSpace.sm),
                Center(
                  child: TextButton(
                    onPressed: _saving ? null : _remove,
                    style: TextButton.styleFrom(foregroundColor: c.danger),
                    child: const Text('Quitar recordatorio'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
