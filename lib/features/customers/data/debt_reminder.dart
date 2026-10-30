import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/utils/currency_formatter.dart';

/// Recordatorio cordial de deuda por WhatsApp.
///
/// Si el cliente tiene teléfono se abre WhatsApp directamente en su chat con el
/// mensaje escrito; si no, o si WhatsApp no se puede abrir, se usa el menú de
/// compartir del sistema para que el usuario elija la app y el contacto.
class DebtReminder {
  /// Indicativo por defecto para números locales de 10 dígitos (Colombia)
  static const String defaultCountryCode = '57';

  static String message({
    required String customerName,
    required double debtAmount,
    required String businessName,
  }) =>
      'Hola $customerName 👋 Te saluda $businessName. Esperamos que te encuentres muy bien. '
      'Te compartimos un recordatorio cordial de tu saldo pendiente de '
      '${CurrencyFormatter.formatCOP(debtAmount)} con nosotros. ¡Muchas gracias por tu preferencia!';

  /// Número en formato internacional sin "+" ni espacios, o null si no es usable.
  /// Un número local de 10 dígitos recibe [defaultCountryCode].
  @visibleForTesting
  static String? normalizePhone(String? phone) {
    if (phone == null) return null;
    final hasPlus = phone.trim().startsWith('+');
    final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length < 7) return null;
    if (hasPlus || digits.length > 10) return digits;
    if (digits.length == 10) return '$defaultCountryCode$digits';
    return null;
  }

  static Future<void> send({
    required String customerName,
    required double debtAmount,
    required String businessName,
    String? phone,
  }) async {
    final text = message(customerName: customerName, debtAmount: debtAmount, businessName: businessName);
    final number = normalizePhone(phone);
    if (number != null) {
      final uri = Uri.parse('https://wa.me/$number?text=${Uri.encodeComponent(text)}');
      try {
        if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
      } catch (e) {
        debugPrint('No se pudo abrir WhatsApp: $e');
      }
    }
    await Share.share(text, subject: 'Recordatorio cordial - $businessName');
  }
}
