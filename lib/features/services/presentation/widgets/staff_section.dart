import 'package:flutter/material.dart';

import '../../../../core/design/app_card.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../business/models/business.dart';
import '../../data/services_repository.dart';
import '../../models/service_models.dart';
import '../../models/work_schedule.dart';
import 'schedule_editor.dart';
import '../../../../core/design/app_dialog.dart';

/// Ajustes › Equipo › Personas que hacen los servicios (Pro Servicios).
/// No necesitan cuenta en la app. La comisión es la de cada servicio.
class StaffSection extends StatefulWidget {
  final Business business;
  final bool canEdit;

  const StaffSection({super.key, required this.business, required this.canEdit});

  @override
  State<StaffSection> createState() => _StaffSectionState();
}

class _StaffSectionState extends State<StaffSection> {
  final _repo = ServicesRepository.instance;
  List<StaffMember> _staff = const [];
  Map<String, List<String>> _servicesOf = const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final staff = await _repo.getStaff(widget.business.id, includeInactive: true);
    final services = await _repo.getServices(widget.business.id);
    if (!mounted) return;
    setState(() {
      _staff = staff;
      _servicesOf = {
        for (final s in staff)
          s.id: [for (final sv in services) if (sv.staffIds.contains(s.id)) sv.name],
      };
    });
  }

  Future<void> _edit([StaffMember? person]) async {
    if (await StaffEditor.show(context, business: widget.business, person: person)) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Personas que hacen los servicios (${_staff.where((s) => s.isActive).length})',
                  style: TextStyle(fontSize: AppText.sizeBodyLarge, fontWeight: FontWeight.w700, color: c.ink)),
            ),
            if (widget.canEdit)
              TextButton.icon(
                onPressed: () => _edit(),
                icon: const Icon(Icons.person_add_alt_outlined, size: 18),
                label: const Text('Agregar'),
              ),
          ],
        ),
        Text('No necesitan cuenta en la app. Qué servicios hace cada una se elige en Servicios › Catálogo y precios.',
            style: TextStyle(fontSize: AppText.sizeSmall, color: c.inkMuted)),
        const SizedBox(height: AppSpace.sm),
        if (_staff.isEmpty)
          AppCard(
            child: Text('Aún no hay nadie. Agrega a quienes lavan, cortan o reparan para asignarles trabajo.',
                style: TextStyle(color: c.inkMuted)),
          ),
        for (final s in _staff) ...[
          AppCard(
            onTap: widget.canEdit ? () => _edit(s) : null,
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.md),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: c.surfaceMuted,
                  child: Text(s.initials, style: TextStyle(color: c.ink, fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: AppSpace.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.name,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: s.isActive ? c.ink : c.inkFaint,
                            decoration: s.isActive ? null : TextDecoration.lineThrough,
                          )),
                      Text(
                        [
                          if (!s.isActive) 'Ya no trabaja aquí',
                          if ((_servicesOf[s.id] ?? const []).isEmpty)
                            'Sin servicios asignados'
                          else
                            (_servicesOf[s.id]!).join(', '),
                          if ((s.phone ?? '').isNotEmpty) s.phone!,
                        ].join(' · '),
                        style: TextStyle(fontSize: AppText.sizeCaption, color: c.inkMuted),
                      ),
                    ],
                  ),
                ),
                if (widget.canEdit) Icon(Icons.chevron_right_outlined, color: c.inkFaint),
              ],
            ),
          ),
          const SizedBox(height: AppSpace.sm),
        ],
      ],
    );
  }
}

/// LA hoja para agregar o editar a una persona que hace los servicios. Se abre
/// desde Ajustes › Equipo y desde Servicios › Empleados (la misma, sin copias).
class StaffEditor extends StatefulWidget {
  final Business business;
  final StaffMember? person;

  const StaffEditor({super.key, required this.business, this.person});

  /// true si se guardó
  static Future<bool> show(BuildContext context, {required Business business, StaffMember? person}) async {
    final saved = await AppSheet.show<bool>(
      context: context,
      title: person == null ? 'Agregar empleado' : 'Editar empleado',
      subtitle: 'No necesita cuenta en la app. Qué servicios hace se elige en Catálogo y precios.',
      builder: (_) => StaffEditor(business: business, person: person),
    );
    return saved == true;
  }

  @override
  State<StaffEditor> createState() => _StaffEditorState();
}

class _StaffEditorState extends State<StaffEditor> {
  late final _name = TextEditingController(text: widget.person?.name ?? '');
  late final _phone = TextEditingController(text: widget.person?.phone ?? '');
  late final _document = TextEditingController(text: widget.person?.document ?? '');
  late bool _active = widget.person?.isActive ?? true;

  /// Horario propio; null = usa el del negocio
  late WorkSchedule? _schedule = WorkSchedule.decode(widget.person?.schedule);
  bool _saving = false;

  Future<void> _editSchedule() async {
    final picked = await ScheduleEditor.show(
      context,
      title: 'Horario propio',
      subtitle: 'Reemplaza al horario del negocio solo para esta persona.',
      initial: _schedule,
      removeLabel: 'Usar el horario del negocio',
    );
    if (picked != null && mounted) setState(() => _schedule = picked.isEmpty ? null : picked);
  }

  @override
  void dispose() {
    for (final c in [_name, _phone, _document]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      AppToast.showWarning(context, 'Escribe el nombre.');
      return;
    }
    setState(() => _saving = true);
    final repo = ServicesRepository.instance;
    final base = widget.person ?? repo.newStaff(widget.business.id, name);
    final phone = _phone.text.trim();
    final doc = _document.text.trim();
    await repo.saveStaff(StaffMember(
      id: base.id,
      businessId: base.businessId,
      name: name,
      phone: phone.isEmpty ? null : phone,
      document: doc.isEmpty ? null : doc,
      // La comisión propia ya no se usa: cuenta la de cada servicio
      commissionPct: null,
      isActive: _active,
      memberEmail: base.memberEmail,
      schedule: _schedule?.encode(),
      createdAt: base.createdAt,
      updatedAt: DateTime.now(),
    ));
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            autofocus: widget.person == null,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Nombre'),
          ),
          const SizedBox(height: AppSpace.sm),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Celular (opcional)'),
          ),
          const SizedBox(height: AppSpace.sm),
          TextField(
            controller: _document,
            decoration: const InputDecoration(labelText: 'Documento (opcional)'),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.schedule_outlined),
            title: const Text('Horario'),
            subtitle: Text(_schedule == null ? 'Usa el horario del negocio' : _schedule!.describe()),
            trailing: TextButton(onPressed: _editSchedule, child: Text(_schedule == null ? 'Poner uno propio' : 'Cambiar')),
          ),
          if (widget.person != null)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _active,
              onChanged: (v) => setState(() => _active = v),
              title: const Text('Trabaja aquí'),
              subtitle: const Text('Apágalo si ya no trabaja; su historial se conserva'),
            ),
          const SizedBox(height: AppSpace.md),
          FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Guardando…' : 'Guardar')),
        ],
    );
  }
}
