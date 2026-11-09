import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/design/app_card.dart';
import '../../../../core/design/content_width.dart';
import '../../../../core/design/phone_field.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/utils/countries.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../business/models/business.dart';
import '../../../pro/data/pro_service.dart';
import '../../../pro/presentation/widgets/pro_upsell_sheet.dart';
import '../../data/services_repository.dart';
import '../../models/service_models.dart';

/// Servicios del catálogo y empleados, en dos pestañas
class ServicesSetupScreen extends StatefulWidget {
  final Business business;
  final int initialTab;

  const ServicesSetupScreen({super.key, required this.business, this.initialTab = 0});

  static Future<void> open(BuildContext context, {required Business business, int initialTab = 0}) =>
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ServicesSetupScreen(business: business, initialTab: initialTab),
      ));

  @override
  State<ServicesSetupScreen> createState() => _ServicesSetupScreenState();
}

class _ServicesSetupScreenState extends State<ServicesSetupScreen> {
  final _repo = ServicesRepository.instance;
  List<ShopService>? _services;
  List<StaffMember>? _staff;

  @override
  void initState() {
    super.initState();
    _load();
    ProService.instance.refresh(widget.business.id);
  }

  Future<void> _load() async {
    final services = await _repo.getServices(widget.business.id, includeInactive: true);
    final staff = await _repo.getStaff(widget.business.id, includeInactive: true);
    if (!mounted) return;
    setState(() {
      _services = services;
      _staff = staff;
    });
  }

  bool get _hasPro => ProService.instance.status.value.active;

  Future<void> _editService([ShopService? service]) async {
    final saved = await showDialog<ShopService>(
      context: context,
      builder: (_) => _ServiceDialog(
        service: service ?? _repo.newService(widget.business.id),
        isNew: service == null,
      ),
    );
    if (saved == null) return;
    await _repo.saveService(saved);
    _load();
  }

  /// Sin Pro solo caben 2 empleados activos; se ofrece Pro al pasar el límite
  Future<bool> _staffAllowed({String? exceptId}) async {
    if (await _repo.canActivateStaff(widget.business.id, hasPro: _hasPro, exceptId: exceptId)) return true;
    if (!mounted) return false;
    final result = await ProUpsellSheet.show(
      context,
      business: widget.business,
      title: 'Más de ${ServicesRepository.freeStaffLimit} empleados es de Pro',
      message: 'Sin Pro puedes tener ${ServicesRepository.freeStaffLimit} empleados activos. '
          'Con Stockealo Pro registras a todo tu equipo.',
      highlight: ProBenefit.staff,
    );
    return result == ProUpsellResult.pro;
  }

  Future<void> _editStaff([StaffMember? staff]) async {
    if (staff == null && !await _staffAllowed()) return;
    if (!mounted) return;
    final saved = await showDialog<StaffMember>(
      context: context,
      builder: (_) => _StaffDialog(
        staff: staff ?? _repo.newStaff(widget.business.id, ''),
        isNew: staff == null,
        country: countryByCode(widget.business.country),
      ),
    );
    if (saved == null) return;
    await _repo.saveStaff(saved);
    _load();
  }

  Future<void> _toggleStaff(StaffMember s) async {
    if (!s.isActive && !await _staffAllowed(exceptId: s.id)) return;
    await _repo.saveStaff(s.copyWith(isActive: !s.isActive));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return DefaultTabController(
      length: 2,
      initialIndex: widget.initialTab,
      child: Builder(builder: (context) {
        final tabs = DefaultTabController.of(context);
        return Scaffold(
          backgroundColor: c.paper,
          appBar: AppBar(
            title: const Text('Servicios y empleados'),
            bottom: const TabBar(tabs: [Tab(text: 'Servicios'), Tab(text: 'Empleados')]),
          ),
          floatingActionButton: AnimatedBuilder(
            animation: tabs,
            builder: (_, __) => FloatingActionButton.extended(
              onPressed: () => tabs.index == 0 ? _editService() : _editStaff(),
              icon: const Icon(Icons.add_rounded),
              label: Text(tabs.index == 0 ? 'Nuevo servicio' : 'Nuevo empleado'),
            ),
          ),
          body: TabBarView(children: [_servicesTab(), _staffTab()]),
        );
      }),
    );
  }

  Widget _servicesTab() {
    final c = context.colors;
    final list = _services;
    if (list == null) return const Center(child: CircularProgressIndicator());
    return ContentWidth(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.lg, AppSpace.lg, 96),
        children: [
          if (list.isEmpty)
            Padding(
              padding: const EdgeInsets.all(AppSpace.xl),
              child: Text('Agrega los servicios que ofreces, con su precio.',
                  textAlign: TextAlign.center, style: TextStyle(color: c.inkMuted)),
            ),
          for (final s in list) ...[
            AppCard(
              onTap: () => _editService(s),
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.md),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.name,
                            style: TextStyle(
                              color: s.isActive ? c.ink : c.inkFaint,
                              fontWeight: FontWeight.w600,
                              decoration: s.isActive ? null : TextDecoration.lineThrough,
                            )),
                        Text(
                          [
                            if (s.durationMin != null) '${s.durationMin} min',
                            'Comisión ${s.commissionPct.toStringAsFixed(0)} %',
                            if (!s.isActive) 'oculto',
                          ].join(' · '),
                          style: TextStyle(color: c.inkMuted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  Text(CurrencyFormatter.format(s.price), style: TextStyle(color: c.ink, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            const SizedBox(height: AppSpace.sm),
          ],
        ],
      ),
    );
  }

  Widget _staffTab() {
    final c = context.colors;
    final list = _staff;
    if (list == null) return const Center(child: CircularProgressIndicator());
    final active = list.where((s) => s.isActive).length;
    return ContentWidth(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.lg, AppSpace.lg, 96),
        children: [
          Text(
            'Las personas que hacen los servicios. No necesitan cuenta: tú eliges quién hizo cada trabajo.'
            '${_hasPro ? '' : ' Sin Pro puedes tener ${ServicesRepository.freeStaffLimit} activos ($active en uso).'}',
            style: TextStyle(color: c.inkMuted, fontSize: 12.5),
          ),
          const SizedBox(height: AppSpace.md),
          for (final s in list) ...[
            AppCard(
              onTap: () => _editStaff(s),
              padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.sm, AppSpace.sm, AppSpace.sm),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: s.isActive ? c.successSoft : c.surfaceMuted,
                    child: Text(s.initials, style: TextStyle(color: s.isActive ? c.success : c.inkFaint)),
                  ),
                  const SizedBox(width: AppSpace.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.name, style: TextStyle(color: s.isActive ? c.ink : c.inkFaint, fontWeight: FontWeight.w600)),
                        Text(
                          [
                            if ((s.phone ?? '').isNotEmpty) s.phone!,
                            s.commissionPct == null
                                ? 'Comisión del servicio'
                                : 'Comisión propia ${s.commissionPct!.toStringAsFixed(0)} %',
                          ].join(' · '),
                          style: TextStyle(color: c.inkMuted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  Switch(value: s.isActive, onChanged: (_) => _toggleStaff(s)),
                ],
              ),
            ),
            const SizedBox(height: AppSpace.sm),
          ],
        ],
      ),
    );
  }
}

class _ServiceDialog extends StatefulWidget {
  final ShopService service;
  final bool isNew;
  const _ServiceDialog({required this.service, required this.isNew});

  @override
  State<_ServiceDialog> createState() => _ServiceDialogState();
}

class _ServiceDialogState extends State<_ServiceDialog> {
  late final _name = TextEditingController(text: widget.service.name);
  late final _price = TextEditingController(text: widget.service.price > 0 ? widget.service.price.toStringAsFixed(0) : '');
  late final _minutes = TextEditingController(text: widget.service.durationMin?.toString() ?? '');
  late final _pct = TextEditingController(text: widget.service.commissionPct.toStringAsFixed(0));
  late bool _active = widget.service.isActive;

  @override
  void dispose() {
    for (final c in [_name, _price, _minutes, _pct]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _valid => _name.text.trim().isNotEmpty && (double.tryParse(_price.text.trim()) ?? 0) > 0;

  @override
  Widget build(BuildContext context) {
    final digits = [FilteringTextInputFormatter.digitsOnly];
    return AlertDialog(
      title: Text(widget.isNew ? 'Nuevo servicio' : 'Editar servicio'),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _name,
                autofocus: widget.isNew,
                textCapitalization: TextCapitalization.sentences,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(labelText: 'Nombre', hintText: 'Ej. Lavado completo'),
              ),
              const SizedBox(height: AppSpace.md),
              TextField(
                controller: _price,
                keyboardType: TextInputType.number,
                inputFormatters: digits,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(labelText: 'Precio', prefixText: '\$ '),
              ),
              const SizedBox(height: AppSpace.md),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _minutes,
                      keyboardType: TextInputType.number,
                      inputFormatters: digits,
                      decoration: const InputDecoration(labelText: 'Duración', suffixText: 'min'),
                    ),
                  ),
                  const SizedBox(width: AppSpace.md),
                  Expanded(
                    child: TextField(
                      controller: _pct,
                      keyboardType: TextInputType.number,
                      inputFormatters: digits,
                      decoration: const InputDecoration(labelText: 'Comisión', suffixText: '%'),
                    ),
                  ),
                ],
              ),
              if (!widget.isNew)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _active,
                  onChanged: (v) => setState(() => _active = v),
                  title: const Text('Disponible'),
                  subtitle: const Text('Apágalo para ocultarlo sin borrarlo'),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: !_valid
              ? null
              : () => Navigator.pop(
                    context,
                    widget.service.copyWith(
                      name: _name.text.trim(),
                      price: double.tryParse(_price.text.trim()) ?? 0,
                      durationMin: int.tryParse(_minutes.text.trim()),
                      commissionPct: (double.tryParse(_pct.text.trim()) ?? 0).clamp(0, 100).toDouble(),
                      isActive: _active,
                    ),
                  ),
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}

class _StaffDialog extends StatefulWidget {
  final StaffMember staff;
  final bool isNew;
  final Country country;
  const _StaffDialog({required this.staff, required this.isNew, required this.country});

  @override
  State<_StaffDialog> createState() => _StaffDialogState();
}

class _StaffDialogState extends State<_StaffDialog> {
  late final _name = TextEditingController(text: widget.staff.name);
  late final _document = TextEditingController(text: widget.staff.document ?? '');
  late final _pct = TextEditingController(text: widget.staff.commissionPct?.toStringAsFixed(0) ?? '');
  late PhoneValue _phone = PhoneValue(widget.staff.phone, isValid: true);

  @override
  void dispose() {
    for (final c in [_name, _document, _pct]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final valid = _name.text.trim().isNotEmpty && _phone.isValid;
    return AlertDialog(
      title: Text(widget.isNew ? 'Nuevo empleado' : 'Editar empleado'),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _name,
                autofocus: widget.isNew,
                textCapitalization: TextCapitalization.words,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(labelText: 'Nombre'),
              ),
              const SizedBox(height: AppSpace.md),
              PhoneField(
                initialValue: widget.staff.phone,
                defaultCountry: widget.country,
                label: 'WhatsApp (opcional)',
                onChanged: (v) => setState(() => _phone = v),
              ),
              const SizedBox(height: AppSpace.md),
              TextField(
                controller: _document,
                decoration: const InputDecoration(labelText: 'Documento (opcional)'),
              ),
              const SizedBox(height: AppSpace.md),
              TextField(
                controller: _pct,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Comisión propia (opcional)',
                  suffixText: '%',
                  helperText: 'Vacío: se usa la comisión de cada servicio',
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: !valid
              ? null
              : () {
                  final pct = double.tryParse(_pct.text.trim());
                  Navigator.pop(
                    context,
                    widget.staff.copyWith(
                      name: _name.text.trim(),
                      phone: _phone.e164,
                      document: _document.text.trim().isEmpty ? null : _document.text.trim(),
                      commissionPct: pct?.clamp(0, 100).toDouble(),
                      clearCommission: pct == null,
                    ),
                  );
                },
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}
