import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/utils/countries.dart';
import '../../business/data/business_repository.dart';
import '../../customers/data/debt_reminder.dart';
import '../models/supplier.dart';

/// Abre el chat del proveedor en WhatsApp con el texto escrito. Si no tiene
/// número usable o WhatsApp no abre, queda el menú de compartir del sistema.
class SupplierWhatsApp {
  static String? numberOf(Supplier? supplier) {
    if (supplier == null) return null;
    final country = countryByCode(BusinessRepository.instance.currentActiveBusiness?.country);
    return DebtReminder.normalizePhone(supplier.phone, country: country);
  }

  /// true si se abrió WhatsApp directo en el chat del proveedor
  static Future<bool> send(Supplier? supplier, String text, {String subject = 'Pedido'}) async {
    final number = numberOf(supplier);
    if (number != null) {
      final uri = Uri.parse('https://wa.me/$number?text=${Uri.encodeComponent(text)}');
      try {
        if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return true;
      } catch (e) {
        debugPrint('No se pudo abrir WhatsApp: $e');
      }
    }
    await Share.share(text, subject: subject);
    return false;
  }
}
