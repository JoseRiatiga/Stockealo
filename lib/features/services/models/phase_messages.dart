import 'dart:convert';

import '../../../core/utils/currency_formatter.dart';
import 'service_models.dart';

/// Fases del trabajo en las que se le puede escribir al cliente
enum MessagePhase {
  received('RECIBIDA', 'Recibido', 'Cuando llega y se registra'),
  inProgress('PROCESO', 'En proceso', 'Cuando alguien empieza a atenderlo'),
  ready('LISTA', 'Listo', 'Cuando todos sus servicios terminan'),
  delivered('ENTREGADA', 'Entregado', 'Después de cobrar');

  final String code;
  final String label;
  final String when;

  const MessagePhase(this.code, this.label, this.when);
}

/// Un mensaje editable de una fase
class PhaseMessage {
  final bool enabled;
  final String text;

  const PhaseMessage({required this.enabled, required this.text});

  Map<String, dynamic> toJson() => {'enabled': enabled, 'text': text};
}

/// Mensajes por fase del negocio (0.12.0). Se envían a mano por WhatsApp; cada fase
/// se puede apagar. Variables: {cliente} {placa} {unidad} {servicios} {empleado}
/// {total} {turno} {espera} {listo} {negocio}.
class PhaseMessages {
  static const variables = <String, String>{
    '{cliente}': 'Nombre del cliente',
    '{placa}': 'Placa o serial',
    '{unidad}': 'moto, carro, equipo…',
    '{servicios}': 'Servicios del trabajo',
    '{empleado}': 'Quién lo atiende',
    '{total}': 'Total a pagar',
    '{turno}': 'Número de turno',
    '{espera}': 'Espera aproximada',
    '{listo}': 'lista o listo',
    '{negocio}': 'Nombre del negocio',
  };

  final Map<MessagePhase, PhaseMessage> phases;

  const PhaseMessages(this.phases);

  /// Textos de Stockealo para cada tipo de negocio
  factory PhaseMessages.defaults(ServiceTemplate t) {
    final withId = t.usesIdentifier ? ' {placa}' : '';
    return PhaseMessages({
      MessagePhase.received: PhaseMessage(
        enabled: true,
        text: 'Hola {cliente}, en {negocio} ya recibimos tu {unidad}$withId. Servicios: {servicios}. '
            'Tu turno es el {turno}, espera aproximada {espera}. Te avisamos cuando esté {listo}.',
      ),
      MessagePhase.inProgress: PhaseMessage(
        enabled: false,
        text: 'Hola {cliente}, {empleado} ya está atendiendo tu {unidad}$withId en {negocio}.',
      ),
      MessagePhase.ready: PhaseMessage(
        enabled: true,
        text: 'Hola {cliente}, tu {unidad}$withId ya está {listo}. Total: {total}. ¡Te esperamos en {negocio}!',
      ),
      MessagePhase.delivered: const PhaseMessage(
        enabled: false,
        text: 'Gracias por venir a {negocio}, {cliente}. ¡Te esperamos pronto!',
      ),
    });
  }

  /// Los mensajes guardados en el negocio (lo que falte sale de la plantilla)
  factory PhaseMessages.of(String? raw, ServiceTemplate t) {
    final base = PhaseMessages.defaults(t);
    if (raw == null || raw.trim().isEmpty) return base;
    try {
      final map = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      return PhaseMessages({
        for (final p in MessagePhase.values)
          p: map[p.code] is Map
              ? PhaseMessage(
                  enabled: (map[p.code] as Map)['enabled'] != false,
                  text: '${(map[p.code] as Map)['text'] ?? base.phases[p]!.text}',
                )
              : base.phases[p]!,
      });
    } catch (_) {
      return base;
    }
  }

  PhaseMessages copyWith(MessagePhase phase, PhaseMessage message) => PhaseMessages({...phases, phase: message});

  String encode() => jsonEncode({for (final e in phases.entries) e.key.code: e.value.toJson()});

  /// El mensaje listo para enviar, con las variables reemplazadas
  static String render(
    String text, {
    required WorkOrder order,
    required ServiceTemplate template,
    required String businessName,
    Map<String, String> staffNames = const {},
    int? turn,
    int? waitMinutes,
  }) {
    final kind = order.vehicleKind;
    final unit = template.usesVehicleKinds && kind != null
        ? template.vehicleLabel(kind).toLowerCase()
        : (template.unit == 'Cliente' ? 'servicio' : template.unit.toLowerCase());
    final feminine = template.usesVehicleKinds && kind != null
        ? ServiceTemplate.vehicleFeminine(kind)
        : (template.unit == 'Cliente' ? false : template.feminine);
    final who = {for (final l in order.lines) ...l.staffIds}.map((id) => (staffNames[id] ?? '').split(' ').first).where((n) => n.isNotEmpty);
    final values = <String, String>{
      '{cliente}': (order.customerName ?? '').trim().split(' ').first,
      '{placa}': order.plate ?? '',
      '{unidad}': unit,
      '{servicios}': order.lines.map((l) => l.name).join(', '),
      '{empleado}': who.isEmpty ? 'nuestro equipo' : who.join(' y '),
      '{total}': CurrencyFormatter.format(order.isPaid ? order.total : order.subtotal),
      '{turno}': turn == null ? '#${order.number}' : '$turn',
      '{espera}': waitMinutes == null ? 'en un momento' : (waitMinutes <= 0 ? 'ya te atendemos' : '$waitMinutes min'),
      '{listo}': feminine ? 'lista' : 'listo',
      '{negocio}': businessName,
    };
    var out = text;
    for (final e in values.entries) {
      out = out.replaceAll(e.key, e.value);
    }
    // Sin nombre del cliente: "Hola , …" queda "Hola, …"
    return out.replaceAll(RegExp(r' +,'), ',').replaceAll(RegExp(r'  +'), ' ').replaceAll(' .', '.').trim();
  }
}
