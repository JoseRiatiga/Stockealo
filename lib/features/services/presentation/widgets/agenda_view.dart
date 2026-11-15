import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/design/app_dialog.dart';
import '../../../../core/design/status_pill.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../business/models/business.dart';
import '../../data/appointments_repository.dart';
import '../../data/services_repository.dart';
import '../../models/appointment.dart';
import '../../models/service_models.dart';
import '../../../../core/permissions/permissions.dart';
import '../../../../core/permissions/permission_guard.dart';

/// Servicios › Agenda (0.14.0): las citas del día por hora. Se agendan aquí o llegan
/// como reserva en línea; cuando el cliente llega, la cita pasa al tablero.
class AgendaView extends StatefulWidget {
  final Business business;

  /// Lleva al tablero (después de «Llegó»)
  final VoidCallback? onOpenBoard;

  const AgendaView({super.key, required this.business, this.onOpenBoard});

  @override
  State<AgendaView> createState() => _AgendaViewState();
}

class _AgendaViewState extends State<AgendaView> {
  final _repo = AppointmentsRepository.instance;
  DateTime _day = DateTime.now();
  List<Appointment>? _list;
  Map<String, StaffMember> _staff = const {};
  bool _busy = false;

  static final _dayFmt = DateFormat("EEEE d 'de' MMMM", 'es_CO');
  static final _hour = DateFormat('h:mm a', 'es_CO');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await _repo.forDay(widget.business.id, _day);
    final staff = await ServicesRepository.instance.getStaff(widget.business.id);
    if (!mounted) return;
    setState(() {
      _list = list;
      _staff = {for (final s in staff) s.id: s};
    });
  }

  void _move(int days) {
    setState(() {
      _day = _day.add(Duration(days: days));
      _list = null;
    });
    _load();
  }

  Future<void> _pickDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(() {
      _day = picked;
      _list = null;
    });
    _load();
  }

  Future<void> _new() async {
    final start = DateTime(_day.year, _day.month, _day.day, DateTime.now().hour + 1);
    if (await AppointmentEditor.show(context, business: widget.business, startsAt: start) == true) await _load();
  }

  Future<void> _run(Future<void> Function() action, {String? done}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (mounted && done != null) AppToast.showSuccess(context, done);
    } on StateError catch (e) {
      if (mounted) AppToast.showWarning(context, e.message);
    } finally {
      await _load();
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Recordatorio por WhatsApp con la hora de la cita
  Future<void> _remind(Appointment a) async {
    final phone = (a.customerPhone ?? '').replaceAll(RegExp(r'[^0-9]'), '');
    if (phone.isEmpty) return;
    final text = 'Hola ${a.customerName.split(' ').first}, te recordamos tu cita en ${widget.business.name} '
        'el ${_dayFmt.format(a.startsAt)} a las ${_hour.format(a.startsAt)}'
        '${a.serviceNames.isEmpty ? '' : ' (${a.serviceNames})'}. ¡Te esperamos!';
    final number = phone.length == 10 ? '57$phone' : phone;
    await launchUrl(Uri.parse('https://wa.me/$number?text=${Uri.encodeComponent(text)}'), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final list = _list;
    final isToday = DateUtils.isSameDay(_day, DateTime.now());
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
                    Row(
                      children: [
                        IconButton(tooltip: 'Día anterior', onPressed: () => _move(-1), icon: const Icon(Icons.chevron_left_outlined)),
                        Expanded(
                          child: InkWell(
                            onTap: _pickDay,
                            borderRadius: BorderRadius.circular(AppRadius.control),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
                              child: Column(
                                children: [
                                  Text(isToday ? 'Hoy' : _dayFmt.format(_day), style: AppText.title(context)),
                                  if (isToday) Text(_dayFmt.format(_day), style: AppText.small(context)),
                                ],
                              ),
                            ),
                          ),
                        ),
                        IconButton(tooltip: 'Día siguiente', onPressed: () => _move(1), icon: const Icon(Icons.chevron_right_outlined)),
                        const SizedBox(width: AppSpace.sm),
                        FilledButton.icon(
                          onPressed: _new,
                          icon: const Icon(Icons.add_outlined, size: 18),
                          label: const Text('Nueva cita'),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpace.md),
                    if (list == null)
                      const Padding(padding: EdgeInsets.all(AppSpace.xl), child: Center(child: CircularProgressIndicator()))
                    else if (list.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: AppSpace.xxl),
                        child: Column(
                          children: [
                            Icon(Icons.event_available_outlined, size: 44, color: c.inkFaint),
                            const SizedBox(height: AppSpace.sm),
                            Text('No hay citas este día.', style: AppText.body(context, color: c.inkMuted)),
                            Text('Toca «Nueva cita» para agendar una.', style: AppText.small(context)),
                          ],
                        ),
                      )
                    else
                      for (final a in list) _card(a),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _card(Appointment a) {
    final c = context.colors;
    final tone = switch (a.status) {
      Appointment.pending => AppTone.warning,
      Appointment.confirmed => AppTone.info,
      Appointment.arrived => AppTone.success,
      _ => AppTone.neutral,
    };
    final staff = a.staffId == null ? null : _staff[a.staffId]?.name;
    Widget action(String label, Future<void> Function() run, {String? done}) =>
        TextButton(onPressed: _busy ? null : () => _run(run, done: done), child: Text(label));

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: Material(
        color: c.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: BorderSide(color: a.status == Appointment.pending ? c.warning : c.line),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.md, AppSpace.sm, AppSpace.xs),
          child: Opacity(
            opacity: a.isOpen ? 1 : 0.6,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 72,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_hour.format(a.startsAt), style: AppText.body(context, weight: FontWeight.w800)),
                      Text('${a.durationMin} min', style: AppText.caption(context)),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(child: Text(a.customerName, style: AppText.bodyLarge(context, weight: FontWeight.w700))),
                          const SizedBox(width: AppSpace.xs),
                          StatusPill(a.statusLabel, tone: tone, compact: true),
                          if (a.source == Appointment.sourceOnline) ...[
                            const SizedBox(width: AppSpace.xs),
                            const StatusPill('En línea', tone: AppTone.accent, compact: true),
                          ],
                        ],
                      ),
                      Text(
                        [
                          if (a.serviceNames.isNotEmpty) a.serviceNames,
                          staff == null ? 'Cualquiera la atiende' : 'Con $staff',
                          if ((a.customerPhone ?? '').isNotEmpty) a.customerPhone!,
                        ].join(' · '),
                        style: AppText.small(context),
                      ),
                      if ((a.notes ?? '').isNotEmpty) Text(a.notes!, style: AppText.caption(context)),
                      Wrap(
                        children: [
                          if (a.status == Appointment.pending)
                            action('Confirmar', () => _repo.setStatus(a, Appointment.confirmed), done: 'Cita confirmada.'),
                          if (a.isOpen)
                            action('Llegó', () async {
                              await _repo.arrive(a);
                              widget.onOpenBoard?.call();
                            }, done: '${a.customerName} pasó al tablero.'),
                          if (a.isOpen && (a.customerPhone ?? '').isNotEmpty)
                            TextButton(onPressed: () => _remind(a), child: const Text('Recordar por WhatsApp')),
                          if (a.isOpen) action('No vino', () => _repo.setStatus(a, Appointment.noShow)),
                          if (a.isOpen) action('Cancelar', () => _repo.setStatus(a, Appointment.cancelled)),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// LA hoja para agendar una cita
class AppointmentEditor extends StatefulWidget {
  final Business business;
  final DateTime startsAt;

  const AppointmentEditor({super.key, required this.business, required this.startsAt});

  /// true si se guardó
  static Future<bool?> show(BuildContext context, {required Business business, required DateTime startsAt}) =>
      AppSidePanel.show<bool>(
        context: context,
        title: 'Nueva cita',
        subtitle: 'Cuando el cliente llegue, la pasas al tablero con «Llegó».',
        builder: (_) => AppointmentEditor(business: business, startsAt: startsAt),
      );

  @override
  State<AppointmentEditor> createState() => _AppointmentEditorState();
}

class _AppointmentEditorState extends State<AppointmentEditor> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _notes = TextEditingController();
  late DateTime _start = widget.startsAt;
  final Set<String> _services = {};
  String? _staffId;
  List<ShopService> _all = const [];
  List<StaffMember> _people = const [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadCatalog();
  }

  Future<void> _loadCatalog() async {
    final repo = ServicesRepository.instance;
    final all = await repo.getServices(widget.business.id);
    final people = (await repo.getStaff(widget.business.id)).where((s) => s.isActive).toList();
    if (mounted) {
      setState(() {
        _all = all;
        _people = people;
      });
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _notes.dispose();
    super.dispose();
  }

  int get _minutes {
    final m = _all.where((s) => _services.contains(s.id)).fold<int>(0, (t, s) => t + (s.durationMin ?? 30));
    return m == 0 ? 30 : m;
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _start,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (d != null) setState(() => _start = DateTime(d.year, d.month, d.day, _start.hour, _start.minute));
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_start));
    if (t != null) setState(() => _start = DateTime(_start.year, _start.month, _start.day, t.hour, t.minute));
  }

  Future<void> _save() async {
    if (!PermissionGuard.check(context, Perm.appointments)) return;
    final name = _name.text.trim();
    if (name.isEmpty) {
      AppToast.showWarning(context, 'Escribe el nombre del cliente.');
      return;
    }
    if (_services.isEmpty) {
      AppToast.showWarning(context, 'Elige al menos un servicio.');
      return;
    }
    final repo = AppointmentsRepository.instance;
    final base = repo.newAppointment(widget.business.id, startsAt: _start);
    final a = Appointment(
      id: base.id,
      businessId: base.businessId,
      customerName: name,
      customerPhone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
      serviceIds: _services.toList(),
      serviceNames: [for (final s in _all) if (_services.contains(s.id)) s.name].join(', '),
      staffId: _staffId,
      startsAt: _start,
      durationMin: _minutes,
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      createdAt: base.createdAt,
      updatedAt: base.updatedAt,
    );
    // Mismo empleado a la misma hora: se avisa y se decide
    final clash = await repo.conflictWith(a);
    if (clash != null && mounted) {
      final ok = await AppDialog.confirm(
        context: context,
        title: 'Se cruza con otra cita',
        message: '${clash.customerName} tiene cita a las ${DateFormat('h:mm a', 'es_CO').format(clash.startsAt)} con la misma persona. ¿La agendas igual?',
        confirmText: 'Agendar igual',
      );
      if (!ok) return;
    }
    setState(() => _saving = true);
    await repo.save(a);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _name,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Cliente'),
        ),
        const SizedBox(height: AppSpace.sm),
        TextField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(labelText: 'Celular (para recordarle)'),
        ),
        const SizedBox(height: AppSpace.md),
        Text('Servicios', style: AppText.small(context, weight: FontWeight.w700, color: c.ink)),
        const SizedBox(height: AppSpace.xs),
        if (_all.isEmpty)
          Text('Primero agrega servicios en Catálogo y precios.', style: AppText.small(context))
        else
          Wrap(
            spacing: AppSpace.xs,
            runSpacing: AppSpace.xs,
            children: [
              for (final s in _all)
                FilterChip(
                  label: Text(s.name),
                  selected: _services.contains(s.id),
                  onSelected: (v) => setState(() => v ? _services.add(s.id) : _services.remove(s.id)),
                ),
            ],
          ),
        const SizedBox(height: AppSpace.md),
        DropdownButtonFormField<String?>(
          initialValue: _staffId,
          decoration: const InputDecoration(labelText: '¿Con quién?'),
          items: [
            const DropdownMenuItem(value: null, child: Text('Cualquiera')),
            for (final p in _people) DropdownMenuItem(value: p.id, child: Text(p.name)),
          ],
          onChanged: (v) => setState(() => _staffId = v),
        ),
        const SizedBox(height: AppSpace.md),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.event_outlined, size: 18),
                label: Text(DateFormat("d 'de' MMM", 'es_CO').format(_start)),
              ),
            ),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _pickTime,
                icon: const Icon(Icons.schedule_outlined, size: 18),
                label: Text(DateFormat('h:mm a', 'es_CO').format(_start)),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpace.xs),
        Text('Dura unos $_minutes minutos', style: AppText.caption(context)),
        const SizedBox(height: AppSpace.md),
        TextField(
          controller: _notes,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Nota (opcional)'),
        ),
        const SizedBox(height: AppSpace.lg),
        FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Guardando…' : 'Agendar cita')),
      ],
    );
  }
}
