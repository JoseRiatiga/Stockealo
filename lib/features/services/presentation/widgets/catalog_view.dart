import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/design/app_card.dart';
import '../../../../core/design/content_width.dart';
import '../../../../core/design/primary_action_button.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../business/models/business.dart';
import '../../data/services_repository.dart';
import '../../models/service_models.dart';

/// Servicios › Catálogo y precios: cada servicio con su precio (o un precio por
/// tipo de vehículo), duración, % de comisión y quién lo hace.
class CatalogView extends StatefulWidget {
  final Business business;
  final ServiceTemplate template;

  const CatalogView({super.key, required this.business, required this.template});

  @override
  State<CatalogView> createState() => _CatalogViewState();
}

class _CatalogViewState extends State<CatalogView> {
  final _repo = ServicesRepository.instance;
  List<ShopService> _services = const [];
  List<StaffMember> _staff = const [];
  bool _loading = true;

  ServiceTemplate get _t => widget.template;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final results = await Future.wait([
      _repo.getServices(widget.business.id, includeInactive: true),
      _repo.getStaff(widget.business.id),
    ]);
    if (!mounted) return;
    setState(() {
      _services = results[0] as List<ShopService>;
      _staff = results[1] as List<StaffMember>;
      _loading = false;
    });
  }

  Future<void> _edit([ShopService? service]) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => ServiceEditorSheet(
        business: widget.business,
        template: _t,
        service: service,
        staff: _staff,
        nextOrder: _services.length,
      ),
    );
    if (saved == true) await _load();
  }

  String _priceText(ShopService s) {
    if (!_t.usesVehicleKinds || s.prices.isEmpty) return CurrencyFormatter.format(s.price);
    return [
      for (final k in _t.vehicleKinds)
        if (s.priceFor(k.code) case final p?) '${k.label} ${CurrencyFormatter.format(p)}',
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (_loading) return const Center(child: CircularProgressIndicator());
    final names = {for (final s in _staff) s.id: s.name.split(' ').first};

    return Stack(
      children: [
        ContentWidth(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.xs, AppSpace.lg, 120),
            children: [
              Text('Toca un servicio para cambiar su precio, su comisión o quién lo hace.',
                  style: TextStyle(fontSize: 13, color: c.inkMuted)),
              const SizedBox(height: AppSpace.md),
              if (_services.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpace.xxl),
                  child: Text('Aún no hay servicios. Toca «Nuevo servicio».',
                      textAlign: TextAlign.center, style: TextStyle(color: c.inkMuted)),
                ),
              for (final s in _services) ...[
                AppCard(
                  onTap: () => _edit(s),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(s.name,
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: s.isActive ? c.ink : c.inkFaint,
                                  decoration: s.isActive ? null : TextDecoration.lineThrough,
                                )),
                            Text(_priceText(s), style: TextStyle(fontSize: 12.5, color: c.ink)),
                            Text(
                              [
                                if (s.durationMin != null) '${s.durationMin} min',
                                '${s.commissionPct.toStringAsFixed(s.commissionPct % 1 == 0 ? 0 : 1)} % de comisión',
                                s.staffIds.isEmpty
                                    ? (_staff.isEmpty ? 'sin personas' : 'lo hace cualquiera')
                                    : 'lo hacen ${s.staffIds.map((id) => names[id] ?? '?').join(', ')}',
                                if (!s.isActive) 'oculto',
                              ].join(' · '),
                              style: TextStyle(fontSize: 12, color: c.inkMuted),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right_rounded, color: c.inkFaint),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpace.sm),
              ],
            ],
          ),
        ),
        Positioned(
          left: AppSpace.lg,
          bottom: MediaQuery.of(context).padding.bottom + AppSpace.lg,
          child: PrimaryActionButton(label: 'Nuevo servicio', onPressed: () => _edit()),
        ),
      ],
    );
  }
}

/// Crear o editar un servicio del catálogo
class ServiceEditorSheet extends StatefulWidget {
  final Business business;
  final ServiceTemplate template;
  final ShopService? service;
  final List<StaffMember> staff;
  final int nextOrder;

  const ServiceEditorSheet({
    super.key,
    required this.business,
    required this.template,
    required this.service,
    required this.staff,
    required this.nextOrder,
  });

  @override
  State<ServiceEditorSheet> createState() => _ServiceEditorSheetState();
}

class _ServiceEditorSheetState extends State<ServiceEditorSheet> {
  late final _name = TextEditingController(text: widget.service?.name ?? '');
  late final _price = TextEditingController(text: _num(widget.service?.price));
  late final _minutes = TextEditingController(text: widget.service?.durationMin?.toString() ?? '');
  late final _pct = TextEditingController(text: _num(widget.service?.commissionPct));
  late final Map<String, TextEditingController> _byKind = {
    for (final k in widget.template.vehicleKinds) k.code: TextEditingController(text: _num(widget.service?.prices[k.code])),
  };
  late final Set<String> _who = {...?widget.service?.staffIds};
  late bool _active = widget.service?.isActive ?? true;
  bool _saving = false;

  ServiceTemplate get _t => widget.template;

  static String _num(double? v) => v == null || v == 0 ? '' : v.toStringAsFixed(v % 1 == 0 ? 0 : 1);

  @override
  void dispose() {
    for (final c in [_name, _price, _minutes, _pct, ..._byKind.values]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      AppToast.showWarning(context, 'Escribe el nombre del servicio.');
      return;
    }
    final prices = <String, double>{
      for (final e in _byKind.entries)
        if ((double.tryParse(e.value.text.trim()) ?? 0) > 0) e.key: double.parse(e.value.text.trim()),
    };
    final single = double.tryParse(_price.text.trim()) ?? 0;
    if (_t.usesVehicleKinds ? prices.isEmpty : single <= 0) {
      AppToast.showWarning(context, _t.usesVehicleKinds ? 'Pon el precio de al menos un tipo de vehículo.' : 'Escribe el precio.');
      return;
    }
    // Todo servicio debe tener quién lo hace (si ya hay personas en el equipo)
    if (widget.staff.isNotEmpty && _who.isEmpty) {
      AppToast.showWarning(context, 'Elige al menos una persona que haga este servicio.');
      return;
    }
    final pct = (double.tryParse(_pct.text.trim()) ?? 0).clamp(0, 100).toDouble();
    final repo = ServicesRepository.instance;
    final base = widget.service ?? repo.newService(widget.business.id).copyWith(sortOrder: widget.nextOrder);
    setState(() => _saving = true);
    await repo.saveService(base.copyWith(
      name: name,
      price: _t.usesVehicleKinds ? prices.values.reduce((a, b) => a < b ? a : b) : single,
      prices: _t.usesVehicleKinds ? prices : const {},
      durationMin: int.tryParse(_minutes.text.trim()),
      commissionPct: pct,
      staffIds: _who.toList(),
      isActive: _active,
    ));
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final digits = [FilteringTextInputFormatter.digitsOnly];
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: ContentWidth(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(AppSpace.lg, 0, AppSpace.lg, AppSpace.lg),
          children: [
            Text(widget.service == null ? 'Nuevo servicio' : 'Editar servicio',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c.ink)),
            const SizedBox(height: AppSpace.md),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Nombre'),
            ),
            const SizedBox(height: AppSpace.md),
            if (_t.usesVehicleKinds) ...[
              Text('Precio por tipo de vehículo', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.inkMuted)),
              Text('Deja vacío el tipo al que no se le ofrece.', style: TextStyle(fontSize: 12, color: c.inkFaint)),
              const SizedBox(height: AppSpace.xs),
              Row(
                children: [
                  for (final k in _t.vehicleKinds) ...[
                    Expanded(
                      child: TextField(
                        controller: _byKind[k.code],
                        keyboardType: TextInputType.number,
                        inputFormatters: digits,
                        decoration: InputDecoration(labelText: k.label, prefixText: '\$ ', isDense: true),
                      ),
                    ),
                    if (k != _t.vehicleKinds.last) const SizedBox(width: AppSpace.sm),
                  ],
                ],
              ),
            ] else
              TextField(
                controller: _price,
                keyboardType: TextInputType.number,
                inputFormatters: digits,
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
                    decoration: const InputDecoration(labelText: 'Duración', suffixText: 'min', isDense: true),
                  ),
                ),
                const SizedBox(width: AppSpace.md),
                Expanded(
                  child: TextField(
                    controller: _pct,
                    keyboardType: TextInputType.number,
                    inputFormatters: digits,
                    decoration: const InputDecoration(labelText: 'Comisión', suffixText: '%', isDense: true),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.md),
            Text('Quién lo hace', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.inkMuted)),
            const SizedBox(height: AppSpace.xs),
            if (widget.staff.isEmpty)
              Text('Primero agrega a las personas en Ajustes › Equipo.', style: TextStyle(color: c.inkMuted))
            else
              Wrap(
                spacing: AppSpace.sm,
                runSpacing: AppSpace.sm,
                children: [
                  for (final s in widget.staff)
                    FilterChip(
                      label: Text(s.name),
                      selected: _who.contains(s.id),
                      onSelected: (v) => setState(() => v ? _who.add(s.id) : _who.remove(s.id)),
                    ),
                ],
              ),
            const SizedBox(height: AppSpace.sm),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _active,
              onChanged: (v) => setState(() => _active = v),
              title: const Text('Se ofrece'),
              subtitle: const Text('Apágalo para ocultarlo sin borrarlo'),
            ),
            const SizedBox(height: AppSpace.md),
            FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Guardando...' : 'Guardar')),
          ],
        ),
      ),
    );
  }
}
