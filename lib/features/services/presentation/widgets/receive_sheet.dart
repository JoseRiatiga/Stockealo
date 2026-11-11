import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/design/content_width.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../business/models/business.dart';
import '../../data/services_repository.dart';
import '../../models/service_models.dart';

/// Recibir un trabajo: placa o serial (si la plantilla lo usa) con búsqueda en
/// vivo que completa los datos del cliente si ya vino, tipo de vehículo (que
/// define los precios), cliente y servicios. Queda en espera con su turno.
class ReceiveSheet extends StatefulWidget {
  final Business business;
  final ServiceTemplate template;

  const ReceiveSheet({super.key, required this.business, required this.template});

  static Future<WorkOrder?> show(BuildContext context, {required Business business, required ServiceTemplate template}) =>
      showModalBottomSheet<WorkOrder>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (_) => ReceiveSheet(business: business, template: template),
      );

  @override
  State<ReceiveSheet> createState() => _ReceiveSheetState();
}

class _ReceiveSheetState extends State<ReceiveSheet> {
  final _repo = ServicesRepository.instance;
  final _id = TextEditingController();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _notes = TextEditingController();
  List<ShopService> _services = const [];
  final _selected = <String>{};
  String? _kind;
  WorkOrder? _lastVisit;
  Timer? _debounce;
  bool _saving = false;

  ServiceTemplate get _t => widget.template;

  @override
  void initState() {
    super.initState();
    _repo.getServices(widget.business.id).then((list) {
      if (mounted) setState(() => _services = list);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    for (final c in [_id, _name, _phone, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Busca mientras se escribe y completa lo que falte con la última visita
  void _search(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () async {
      final text = value.trim();
      final found = text.length < 3 ? null : await _repo.lastVisit(widget.business.id, text);
      if (!mounted) return;
      setState(() {
        _lastVisit = found;
        if (found == null) return;
        if (_name.text.trim().isEmpty && found.customerName != null) _name.text = found.customerName!;
        if (_phone.text.trim().isEmpty && found.customerPhone != null) _phone.text = found.customerPhone!;
        if (_kind == null && found.vehicleKind != null) _kind = found.vehicleKind;
        if (!_t.usesIdentifier && _id.text.trim().isEmpty) _id.text = found.customerName ?? '';
      });
    });
  }

  List<ShopService> get _offered => [
        for (final s in _services)
          if (!_t.usesVehicleKinds || s.offeredFor(_kind)) s,
      ];

  double _price(ShopService s) => s.priceFor(_t.usesVehicleKinds ? _kind : null) ?? s.price;

  double get _total => _offered.where((s) => _selected.contains(s.id)).fold(0.0, (sum, s) => sum + _price(s));

  Future<void> _save() async {
    if (_t.usesVehicleKinds && _kind == null) {
      AppToast.showWarning(context, 'Elige el tipo de vehículo: de eso dependen los precios.');
      return;
    }
    final chosen = _offered.where((s) => _selected.contains(s.id)).toList();
    if (chosen.isEmpty) {
      AppToast.showWarning(context, 'Elige al menos un servicio.');
      return;
    }
    setState(() => _saving = true);
    try {
      final order = await _repo.createOrder(
        businessId: widget.business.id,
        plate: _t.usesIdentifier ? _id.text : null,
        vehicleKind: _t.usesVehicleKinds ? _kind : null,
        customerName: _name.text,
        customerPhone: _phone.text,
        notes: _notes.text,
        lines: [
          for (final s in chosen)
            WorkOrderLine(serviceId: s.id, name: s.name, price: _price(s), commissionPct: s.commissionPct),
        ],
      );
      if (mounted) Navigator.pop(context, order);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppToast.showError(context, 'No se pudo guardar: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final visits = _lastVisit;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: ContentWidth(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(AppSpace.lg, 0, AppSpace.lg, AppSpace.lg),
          children: [
            Text('Recibir ${_t.unit.toLowerCase()}', style: TextStyle(fontSize: AppText.sizeHeading, fontWeight: FontWeight.w700, color: c.ink)),
            const SizedBox(height: AppSpace.md),
            if (_t.usesIdentifier)
              TextField(
                controller: _id,
                autofocus: true,
                textCapitalization: TextCapitalization.characters,
                onChanged: _search,
                decoration: InputDecoration(
                  labelText: _t.identifierLabel,
                  hintText: _t.identifier == IdentifierKind.plate ? 'ABC12D' : null,
                  prefixIcon: const Icon(Icons.search_outlined),
                ),
              ),
            if (visits != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpace.xs),
                child: Text(
                  'Ya vino: ${visits.customerName ?? visits.title}, la última vez el '
                  '${visits.createdAt.day}/${visits.createdAt.month}. Completamos sus datos.',
                  style: TextStyle(fontSize: AppText.sizeSmall, color: c.success),
                ),
              ),
            if (_t.usesVehicleKinds) ...[
              const SizedBox(height: AppSpace.md),
              Text('Tipo de vehículo', style: TextStyle(fontSize: AppText.sizeSmall, fontWeight: FontWeight.w600, color: c.inkMuted)),
              const SizedBox(height: AppSpace.xs),
              Wrap(
                spacing: AppSpace.sm,
                children: [
                  for (final k in _t.vehicleKinds)
                    ChoiceChip(
                      label: Text(k.label),
                      selected: _kind == k.code,
                      onSelected: (_) => setState(() {
                        _kind = k.code;
                        // Lo que no se ofrece para ese tipo se quita
                        _selected.removeWhere((id) => !_services.any((s) => s.id == id && s.offeredFor(k.code)));
                      }),
                    ),
                ],
              ),
            ],
            const SizedBox(height: AppSpace.md),
            TextField(
              controller: _name,
              autofocus: !_t.usesIdentifier,
              textCapitalization: TextCapitalization.words,
              onChanged: _t.usesIdentifier ? null : _search,
              decoration: InputDecoration(labelText: _t.usesIdentifier ? 'Cliente (opcional)' : 'Cliente'),
            ),
            const SizedBox(height: AppSpace.sm),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              onChanged: _t.usesIdentifier ? null : _search,
              decoration: const InputDecoration(labelText: 'WhatsApp del cliente (opcional)', helperText: 'Para avisarle cuando esté listo'),
            ),
            const SizedBox(height: AppSpace.md),
            Text('Servicios', style: TextStyle(fontSize: AppText.sizeSmall, fontWeight: FontWeight.w600, color: c.inkMuted)),
            const SizedBox(height: AppSpace.xs),
            if (_t.usesVehicleKinds && _kind == null)
              Text('Elige el tipo de vehículo para ver los servicios y sus precios.', style: TextStyle(color: c.inkMuted))
            else if (_offered.isEmpty)
              Text('No hay servicios activos. Agrégalos en Catálogo y precios.', style: TextStyle(color: c.inkMuted))
            else
              Wrap(
                spacing: AppSpace.sm,
                runSpacing: AppSpace.sm,
                children: [
                  for (final s in _offered)
                    FilterChip(
                      label: Text('${s.name} · ${CurrencyFormatter.format(_price(s))}'),
                      selected: _selected.contains(s.id),
                      onSelected: (v) => setState(() => v ? _selected.add(s.id) : _selected.remove(s.id)),
                    ),
                ],
              ),
            const SizedBox(height: AppSpace.md),
            TextField(
              controller: _notes,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Nota (opcional)'),
            ),
            const SizedBox(height: AppSpace.lg),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving
                  ? 'Guardando...'
                  : _selected.isEmpty
                      ? 'Recibir'
                      : 'Recibir · ${CurrencyFormatter.format(_total)}'),
            ),
          ],
        ),
      ),
    );
  }
}
