import 'package:flutter_test/flutter_test.dart';
import 'package:stockealo/core/utils/countries.dart';
import 'package:stockealo/features/customers/data/debt_reminder.dart';

void main() {
  group('normalizePhone', () {
    test('un celular local de 10 dígitos recibe el indicativo de Colombia', () {
      expect(DebtReminder.normalizePhone('300 123 4567'), '573001234567');
      expect(DebtReminder.normalizePhone('(300) 123-4567'), '573001234567');
    });

    test('respeta un número que ya viene con indicativo', () {
      expect(DebtReminder.normalizePhone('+52 55 1234 5678'), '525512345678');
      expect(DebtReminder.normalizePhone('573001234567'), '573001234567');
    });

    test('un número sin prefijo usa el país del negocio, no siempre Colombia', () {
      final mexico = countryByCode('MX');
      expect(DebtReminder.normalizePhone('55 1234 5678', country: mexico), '525512345678');
      expect(DebtReminder.normalizePhone('+57 300 123 4567', country: mexico), '573001234567');
    });

    test('descarta teléfonos vacíos o incompletos', () {
      expect(DebtReminder.normalizePhone(null), isNull);
      expect(DebtReminder.normalizePhone(''), isNull);
      expect(DebtReminder.normalizePhone('12345'), isNull);
      expect(DebtReminder.normalizePhone('6012345'), isNull);
    });
  });

  test('el mensaje incluye cliente, negocio y deuda con formato', () {
    final text = DebtReminder.message(customerName: 'Ana', debtAmount: 25000, businessName: 'Miselanea');

    expect(text, contains('Hola Ana'));
    expect(text, contains('Miselanea'));
    expect(text, contains(r'$25.000'));
  });
}
