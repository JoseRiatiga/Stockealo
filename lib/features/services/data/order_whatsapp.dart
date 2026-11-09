import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/utils/countries.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../business/models/business.dart';
import '../../customers/data/debt_reminder.dart';
import '../models/service_models.dart';

/// "Tu moto está lista": abre WhatsApp con el mensaje escrito; la persona lo envía
class OrderWhatsApp {
  static String readyMessage(WorkOrder order, Business business) {
    final type = ServiceType.of(business.serviceType);
    final who = (order.customerName ?? '').trim().isEmpty ? '' : ' ${order.customerName!.trim().split(' ').first}';
    final what = switch (type) {
      ServiceType.lavaderoMotos => 'tu moto${(order.plate ?? '').isEmpty ? '' : ' ${order.plate}'} ya está lista',
      ServiceType.taller => 'tu vehículo${(order.plate ?? '').isEmpty ? '' : ' ${order.plate}'} ya está listo',
      _ => 'tu servicio ya está listo',
    };
    return 'Hola$who, te saluda ${business.name}: $what. '
        'Total: ${CurrencyFormatter.format(order.subtotal)}. ¡Te esperamos!';
  }

  /// true si había un número y se abrió WhatsApp
  static Future<bool> sendReady(WorkOrder order, Business business) async {
    final text = readyMessage(order, business);
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
