import 'package:flutter_test/flutter_test.dart';
import 'package:stockealo/core/utils/countries.dart';

void main() {
  final colombia = countryByCode('CO');
  final mexico = countryByCode('MX');
  final ecuador = countryByCode('EC');

  group('countryByCode / countryForCurrency / countryFromLocale', () {
    test('busca por código y usa Colombia si no lo conoce', () {
      expect(countryByCode('mx').name, 'México');
      expect(countryByCode('ZZ').code, 'CO');
      expect(countryByCode(null).code, 'CO');
    });

    test('sugiere el país de cada moneda (como la migración de la nube)', () {
      expect(countryForCurrency('MXN').code, 'MX');
      expect(countryForCurrency('PEN').code, 'PE');
      expect(countryForCurrency('USD').code, 'US');
      expect(countryForCurrency('EUR').code, 'ES');
      expect(countryForCurrency('OTRA').code, 'CO');
    });

    test('lee el país del idioma del teléfono', () {
      expect(countryFromLocale('es_CO')?.code, 'CO');
      expect(countryFromLocale('es-MX')?.code, 'MX');
      expect(countryFromLocale('es'), isNull);
      expect(countryFromLocale('fr_FR'), isNull);
    });
  });

  group('PhoneNumbers.toE164', () {
    test('un número local recibe el prefijo del país', () {
      expect(PhoneNumbers.toE164('300 123 4567', country: colombia), '+573001234567');
      expect(PhoneNumbers.toE164('55 1234 5678', country: mexico), '+525512345678');
    });

    test('respeta el prefijo que ya trae el número', () {
      expect(PhoneNumbers.toE164('+52 55 1234 5678', country: colombia), '+525512345678');
      expect(PhoneNumbers.toE164('0052 55 1234 5678', country: colombia), '+525512345678');
      expect(PhoneNumbers.toE164('573001234567', country: colombia), '+573001234567');
    });

    test('quita el 0 inicial de los números locales que lo usan', () {
      expect(PhoneNumbers.toE164('099 123 4567', country: ecuador), '+593991234567');
    });

    test('vacío o demasiado corto no es un teléfono', () {
      expect(PhoneNumbers.toE164(null, country: colombia), isNull);
      expect(PhoneNumbers.toE164('  ', country: colombia), isNull);
      expect(PhoneNumbers.toE164('12345', country: colombia), isNull);
    });
  });

  group('PhoneNumbers.split', () {
    test('separa país y número local', () {
      final parts = PhoneNumbers.split('+525512345678', fallback: colombia);
      expect(parts.country.code, 'MX');
      expect(parts.national, '5512345678');
    });

    test('distingue prefijos largos (+593) de otros', () {
      expect(PhoneNumbers.split('+593991234567', fallback: colombia).country.code, 'EC');
    });

    test('un número antiguo sin prefijo queda en el país por defecto', () {
      final parts = PhoneNumbers.split('300 123 4567', fallback: colombia);
      expect(parts.country.code, 'CO');
      expect(parts.national, '3001234567');
    });

    test('valida el largo del número local', () {
      expect(PhoneNumbers.isValidNational('3001234567', colombia), isTrue);
      expect(PhoneNumbers.isValidNational('300123456', colombia), isFalse);
    });
  });
}
