import 'dart:ui' show PlatformDispatcher;

/// Países donde se usa Stockealo: prefijo telefónico, moneda y largo del número local.
class Country {
  /// Código ISO de 2 letras (el que se guarda en el negocio)
  final String code;
  final String name;
  final String flag;

  /// Prefijo internacional sin "+": "57"
  final String dialCode;

  /// Moneda que se sugiere al elegir el país
  final String currency;

  /// Dígitos de un celular sin el prefijo
  final int phoneDigits;

  /// Apps de pago más usadas, para los consejos y ejemplos ("Nequi o Daviplata")
  final String paymentApps;

  const Country({
    required this.code,
    required this.name,
    required this.flag,
    required this.dialCode,
    required this.currency,
    required this.phoneDigits,
    required this.paymentApps,
  });

  /// "🇨🇴 +57"
  String get dialLabel => '$flag +$dialCode';
}

const List<Country> kCountries = [
  Country(code: 'CO', name: 'Colombia', flag: '🇨🇴', dialCode: '57', currency: 'COP', phoneDigits: 10, paymentApps: 'Nequi o Daviplata'),
  Country(code: 'MX', name: 'México', flag: '🇲🇽', dialCode: '52', currency: 'MXN', phoneDigits: 10, paymentApps: 'transferencia SPEI o Mercado Pago'),
  Country(code: 'PE', name: 'Perú', flag: '🇵🇪', dialCode: '51', currency: 'PEN', phoneDigits: 9, paymentApps: 'Yape o Plin'),
  Country(code: 'AR', name: 'Argentina', flag: '🇦🇷', dialCode: '54', currency: 'ARS', phoneDigits: 10, paymentApps: 'Mercado Pago o transferencia'),
  Country(code: 'CL', name: 'Chile', flag: '🇨🇱', dialCode: '56', currency: 'CLP', phoneDigits: 9, paymentApps: 'transferencia o MACH'),
  Country(code: 'EC', name: 'Ecuador', flag: '🇪🇨', dialCode: '593', currency: 'USD', phoneDigits: 9, paymentApps: 'DeUna o transferencia'),
  Country(code: 'US', name: 'Estados Unidos', flag: '🇺🇸', dialCode: '1', currency: 'USD', phoneDigits: 10, paymentApps: 'Zelle o Cash App'),
  Country(code: 'ES', name: 'España', flag: '🇪🇸', dialCode: '34', currency: 'EUR', phoneDigits: 9, paymentApps: 'Bizum'),
];

/// País por defecto cuando no se sabe cuál es
const Country kDefaultCountry = Country(
  code: 'CO',
  name: 'Colombia',
  flag: '🇨🇴',
  dialCode: '57',
  currency: 'COP',
  phoneDigits: 10,
  paymentApps: 'Nequi o Daviplata',
);

/// País por su código ISO; si no está en la lista, Colombia
Country countryByCode(String? code) {
  final upper = code?.toUpperCase();
  return kCountries.firstWhere((c) => c.code == upper, orElse: () => kDefaultCountry);
}

/// País sugerido para una moneda (la migración de la nube usa la misma tabla)
Country countryForCurrency(String? currency) {
  if (currency == 'USD') return countryByCode('US');
  return kCountries.firstWhere((c) => c.currency == currency, orElse: () => kDefaultCountry);
}

/// País del idioma y región del teléfono ("es_CO", "es-MX"); null si no es uno de la lista
Country? countryFromLocale(String? localeName) {
  final parts = localeName?.split(RegExp('[_-]')) ?? const [];
  if (parts.length < 2) return null;
  final code = parts[1].toUpperCase();
  for (final c in kCountries) {
    if (c.code == code) return c;
  }
  return null;
}

/// País configurado en el teléfono del usuario, o Colombia.
/// Solo se confía en la región si el teléfono está en español: muchos celulares en
/// Colombia vienen en inglés de Estados Unidos y no se debe sugerir ese país.
Country deviceCountry() {
  final locale = PlatformDispatcher.instance.locale;
  if (locale.languageCode != 'es') return kDefaultCountry;
  return countryFromLocale(locale.toString()) ?? kDefaultCountry;
}

/// Teléfono separado en país y número local, para mostrarlo en el selector de prefijo
class PhoneParts {
  final Country country;
  final String national;

  const PhoneParts(this.country, this.national);
}

/// Utilidades para guardar los teléfonos con su prefijo internacional ("+573001234567").
///
/// Los números guardados antes de la 0.9.0 no tienen prefijo: se leen como del país
/// que se indique (el del negocio), así funcionan sin migrar nada.
class PhoneNumbers {
  PhoneNumbers._();

  /// Número completo con "+" y solo dígitos, o null si está vacío o es demasiado corto.
  /// Un número sin prefijo se toma como de [country].
  static String? toE164(String? raw, {required Country country}) {
    if (raw == null) return null;
    final trimmed = raw.trim();
    var digits = trimmed.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length < 7) return null;

    if (trimmed.startsWith('+')) return '+$digits';
    if (digits.startsWith('00')) return '+${digits.substring(2)}';

    // Ya trae el prefijo del país pero sin "+" ("573001234567")
    if (digits.length == country.dialCode.length + country.phoneDigits && digits.startsWith(country.dialCode)) {
      return '+$digits';
    }
    // Número local con el 0 inicial de algunos países ("0991234567" en Ecuador)
    if (digits.length == country.phoneDigits + 1 && digits.startsWith('0')) {
      digits = digits.substring(1);
    }
    return '+${country.dialCode}$digits';
  }

  /// Separa un número guardado en país y número local. Si no trae prefijo, usa [fallback].
  static PhoneParts split(String? stored, {required Country fallback}) {
    final value = stored?.trim() ?? '';
    if (!value.startsWith('+')) {
      return PhoneParts(fallback, value.replaceAll(RegExp(r'[^0-9]'), ''));
    }
    final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
    // El prefijo más largo primero: "+593" no debe leerse como otro país
    final byLongestDial = [...kCountries]..sort((a, b) => b.dialCode.length.compareTo(a.dialCode.length));
    for (final c in byLongestDial) {
      if (digits.startsWith(c.dialCode)) {
        return PhoneParts(c, digits.substring(c.dialCode.length));
      }
    }
    return PhoneParts(fallback, digits);
  }

  /// El número local tiene el largo esperado para el país
  static bool isValidNational(String national, Country country) =>
      national.replaceAll(RegExp(r'[^0-9]'), '').length == country.phoneDigits;
}
