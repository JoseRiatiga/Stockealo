import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/utils/countries.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../business/data/business_repository.dart';

/// Recordatorio cordial de deuda por WhatsApp.
///
/// Si el cliente tiene teléfono se abre WhatsApp directamente en su chat con el
/// mensaje escrito; si no, o si WhatsApp no se puede abrir, se usa el menú de
/// compartir del sistema para que el usuario elija la app y el contacto.
class DebtReminder {
  static String message({
    required String customerName,
    required double debtAmount,
    required String businessName,
  }) =>
      'Hola $customerName 👋 Te saluda $businessName. Esperamos que te encuentres muy bien. '
      'Te compartimos un recordatorio cordial de tu saldo pendiente de '
      '${CurrencyFormatter.format(debtAmount)} con nosotros. ¡Muchas gracias por tu preferencia!';

  /// Número para wa.me: internacional, sin "+" ni espacios; null si no es usable.
  /// Un número guardado sin prefijo se toma como del país del negocio ([country]).
  @visibleForTesting
  static String? normalizePhone(String? phone, {Country country = kDefaultCountry}) {
    final trimmed = phone?.trim() ?? '';
    final e164 = PhoneNumbers.toE164(trimmed, country: country);
    if (e164 == null) return null;
    if (trimmed.startsWith('+') || trimmed.startsWith('00')) return e164.substring(1);
    // Sin prefijo: solo se confía en un número con el largo de un celular del país
    final expectedDigits = country.dialCode.length + country.phoneDigits;
    return e164.length - 1 == expectedDigits ? e164.substring(1) : null;
  }

  static Future<void> send({
    required String customerName,
    required double debtAmount,
    required String businessName,
    String? phone,
  }) async {
    final text = message(customerName: customerName, debtAmount: debtAmount, businessName: businessName);
    final country = countryByCode(BusinessRepository.instance.currentActiveBusiness?.country);
    final number = normalizePhone(phone, country: country);
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
