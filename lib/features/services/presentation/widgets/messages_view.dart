import 'package:flutter/material.dart';

import '../../../../core/design/app_card.dart';
import '../../../../core/design/content_width.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../business/data/business_repository.dart';
import '../../../business/models/business.dart';
import '../../models/phase_messages.dart';
import '../../models/service_models.dart';

/// Servicios › Mensajes por fase: el texto de WhatsApp de cada fase (Recibido, En
/// proceso, Listo, Entregado), con variables y vista previa. Cada fase se apaga.
class MessagesView extends StatefulWidget {
  final Business business;
  final ServiceTemplate template;

  const MessagesView({super.key, required this.business, required this.template});

  @override
  State<MessagesView> createState() => _MessagesViewState();
}

class _MessagesViewState extends State<MessagesView> {
  late PhaseMessages _messages = PhaseMessages.of(widget.business.serviceMessages, widget.template);
  late final Map<MessagePhase, TextEditingController> _text = {
    for (final e in _messages.phases.entries) e.key: TextEditingController(text: e.value.text),
  };
  bool _dirty = false;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in _text.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// Un trabajo de ejemplo para la vista previa
  WorkOrder get _sample {
    final now = DateTime.now();
    final t = widget.template;
    final example = t.examples.isEmpty ? 'Servicio' : t.examples.first.name;
    return WorkOrder(
      id: 'muestra',
      businessId: widget.business.id,
      number: '3',
      plate: t.identifier == IdentifierKind.plate ? 'ABC12D' : (t.identifier == IdentifierKind.serial ? 'SN4821' : null),
      vehicleKind: t.usesVehicleKinds ? t.vehicleKinds.first.code : null,
      customerName: 'Carlos Pérez',
      lines: [WorkOrderLine(serviceId: 'x', name: example, price: 15000, staffIds: const ['juan'])],
      createdAt: now,
      updatedAt: now,
    );
  }

  void _update(MessagePhase phase, {bool? enabled, String? text}) {
    final current = _messages.phases[phase]!;
    setState(() {
      _messages = _messages.copyWith(
        phase,
        PhaseMessage(enabled: enabled ?? current.enabled, text: text ?? current.text),
      );
      _dirty = true;
    });
  }

  void _insert(MessagePhase phase, String variable) {
    final c = _text[phase]!;
    final pos = c.selection.isValid ? c.selection.start : c.text.length;
    final text = c.text.replaceRange(pos, c.selection.isValid ? c.selection.end : pos, variable);
    c.value = TextEditingValue(text: text, selection: TextSelection.collapsed(offset: pos + variable.length));
    _update(phase, text: text);
  }

  void _restore(MessagePhase phase) {
    final base = PhaseMessages.defaults(widget.template).phases[phase]!;
    _text[phase]!.text = base.text;
    _update(phase, text: base.text);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await BusinessRepository.instance.updateBusiness(id: widget.business.id, serviceMessages: _messages.encode());
      if (!mounted) return;
      setState(() => _dirty = false);
      AppToast.showSuccess(context, 'Mensajes guardados');
    } catch (e) {
      if (mounted) AppToast.showError(context, 'No se pudieron guardar: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final sample = _sample;
    return ContentWidth(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.xs, AppSpace.lg, AppSpace.xxl),
        children: [
          Text('Se envían a mano por WhatsApp desde el tablero. Apaga los que no quieras usar.',
              style: TextStyle(fontSize: 13, color: c.inkMuted)),
          const SizedBox(height: AppSpace.md),
          for (final phase in MessagePhase.values) ...[
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _messages.phases[phase]!.enabled,
                    onChanged: (v) => _update(phase, enabled: v),
                    title: Text(phase.label, style: TextStyle(fontWeight: FontWeight.w700, color: c.ink)),
                    subtitle: Text(phase.when, style: TextStyle(fontSize: 12.5, color: c.inkMuted)),
                  ),
                  if (_messages.phases[phase]!.enabled) ...[
                    TextField(
                      controller: _text[phase],
                      minLines: 2,
                      maxLines: 5,
                      maxLength: 500,
                      textCapitalization: TextCapitalization.sentences,
                      onChanged: (v) => _update(phase, text: v),
                    ),
                    Wrap(
                      spacing: AppSpace.xs,
                      runSpacing: AppSpace.xs,
                      children: [
                        for (final v in PhaseMessages.variables.entries)
                          if (v.key != '{placa}' || widget.template.usesIdentifier)
                            ActionChip(
                              label: Text(v.key, style: const TextStyle(fontSize: 12)),
                              tooltip: v.value,
                              visualDensity: VisualDensity.compact,
                              onPressed: () => _insert(phase, v.key),
                            ),
                      ],
                    ),
                    const SizedBox(height: AppSpace.sm),
                    Container(
                      padding: const EdgeInsets.all(AppSpace.sm),
                      decoration: BoxDecoration(color: c.successSoft, borderRadius: BorderRadius.circular(AppRadius.control)),
                      child: Text(
                        PhaseMessages.render(
                          _messages.phases[phase]!.text,
                          order: sample,
                          template: widget.template,
                          businessName: widget.business.name,
                          staffNames: const {'juan': 'Juan'},
                          turn: 3,
                          waitMinutes: 25,
                        ),
                        style: TextStyle(fontSize: 13, color: c.ink),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(onPressed: () => _restore(phase), child: const Text('Volver al texto de Stockealo')),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppSpace.sm),
          ],
          const SizedBox(height: AppSpace.sm),
          FilledButton(
            onPressed: !_dirty || _saving ? null : _save,
            child: Text(_saving ? 'Guardando…' : (_dirty ? 'Guardar mensajes' : 'Guardado')),
          ),
        ],
      ),
    );
  }
}
