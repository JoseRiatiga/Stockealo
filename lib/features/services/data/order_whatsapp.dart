import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/utils/countries.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../business/models/business.dart';
import '../../customers/data/debt_reminder.dart';
import '../models/phase_messages.dart';
import '../models/service_models.dart';

/// "Tu moto está lista", "tu equipo está listo"…: abre WhatsApp con el mensaje escrito; la persona lo envía
class OrderWhatsApp {
  static String readyMessage(WorkOrder order, Business business) {
    final t = ServiceTemplate.of(business.serviceType);
    final who = (order.customerName ?? '').trim().isEmpty ? '' : ' ${order.customerName!.trim().split(' ').first}';
    final id = (order.plate ?? '').isEmpty ? '' : ' ${order.plate}';
    final String what;
    if (t.usesVehicleKinds && order.vehicleKind != null) {
      final kind = t.vehicleLabel(order.vehicleKind).toLowerCase();
      final ready = ServiceTemplate.vehicleFeminine(order.vehicleKind) ? 'lista' : 'listo';
      what = 'tu $kind$id ya está $ready';
    } else if (t.usesIdentifier) {
      final unit = t.unit.toLowerCase();
      what = 'tu $unit$id ya está ${t.feminine ? 'lista' : 'listo'}';
    } else if (t.unit == 'Pedido') {
      what = 'tu pedido ya está listo';
    } else {
      what = 'tu servicio ya está listo';
    }
    return 'Hola$who, te saluda ${business.name}: $what. '
        'Total: ${CurrencyFormatter.format(order.subtotal)}. ¡Te esperamos!';
  }

  /// Mensaje de una fase con los textos del negocio; null si la fase está apagada
  static String? phaseText(
    MessagePhase phase,
    WorkOrder order,
    Business business, {
    Map<String, String> staffNames = const {},
    int? turn,
    int? waitMinutes,
  }) {
    final template = ServiceTemplate.of(business.serviceType);
    final m = PhaseMessages.of(business.serviceMessages, template).phases[phase]!;
    if (!m.enabled || m.text.trim().isEmpty) return null;
    return PhaseMessages.render(
      m.text,
      order: order,
      template: template,
      businessName: business.name,
      staffNames: staffNames,
      turn: turn,
      waitMinutes: waitMinutes,
    );
  }

  /// Aviso de listo: el mensaje de la fase «Listo» del negocio (o el de siempre)
  static Future<bool> sendReady(WorkOrder order, Business business, {Map<String, String> staffNames = const {}}) =>
      send(order, business, phaseText(MessagePhase.ready, order, business, staffNames: staffNames) ?? readyMessage(order, business));

  /// Abre WhatsApp con el texto; sin número, se comparte. true si se abrió WhatsApp.
  static Future<bool> send(WorkOrder order, Business business, String text) async {
    final number = DebtReminder.normalizePhone(order.customerPhone, country: countryByCode(business.country));
    if (number != null) {
      try {
        final uri = Uri.parse('https://wa.me/$number?text=${Uri.encodeComponent(text)}');
        if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return true;
      } catch (e) {
        debugPrint('No se pudo abrir WhatsApp: $e');
      }
    }
    await Share.share(text);
    return false;
  }
}
