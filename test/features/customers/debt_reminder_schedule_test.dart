import 'package:flutter_test/flutter_test.dart';
import 'package:stockealo/core/services/phone_alerts_service.dart';
import 'package:stockealo/features/customers/data/debt_reminder_schedule.dart';

void main() {
  DebtReminderSchedule schedule({int every = 7, int hour = 9, DateTime? startsOn}) => DebtReminderSchedule(
        customerId: 'c1',
        businessId: 'b1',
        everyDays: every,
        hour: hour,
        minute: 30,
        startsOn: startsOn ?? DateTime(2026, 10, 1),
      );

  group('próximas fechas', () {
    test('si la hora de hoy no ha pasado, el primer aviso es hoy', () {
      final dates = schedule(startsOn: DateTime(2026, 10, 31)).nextOccurrences(DateTime(2026, 10, 31, 8));
      expect(dates.first, DateTime(2026, 10, 31, 9, 30));
      expect(dates[1], DateTime(2026, 11, 7, 9, 30));
      expect(dates, hasLength(4));
    });

    test('si ya pasó, salta al siguiente periodo', () {
      final dates = schedule(startsOn: DateTime(2026, 10, 31)).nextOccurrences(DateTime(2026, 10, 31, 10));
      expect(dates.first, DateTime(2026, 11, 7, 9, 30));
    });

    test('cuenta los periodos desde el día de inicio', () {
      // Del 1 de octubre, cada 7 días: 1, 8, 15, 22, 29 de octubre y 5 de noviembre
      final dates = schedule().nextOccurrences(DateTime(2026, 10, 30, 12));
      expect(dates.first, DateTime(2026, 11, 5, 9, 30));
      expect(dates.every((d) => d.isAfter(DateTime(2026, 10, 30, 12))), isTrue);
    });

    test('todos los días', () {
      final dates = schedule(every: 1).nextOccurrences(DateTime(2026, 10, 30, 12), count: 3);
      expect(dates, [DateTime(2026, 10, 31, 9, 30), DateTime(2026, 11, 1, 9, 30), DateTime(2026, 11, 2, 9, 30)]);
    });
  });

  group('guardado', () {
    test('se guarda y se lee', () {
      final s = schedule(every: 15, hour: 18);
      final back = DebtReminderSchedule.fromJson(s.toJson())!;
      expect(back.everyDays, 15);
      expect(back.hour, 18);
      expect(back.minute, 30);
      expect(back.startsOn, s.startsOn);
    });

    test('datos dañados no rompen la lista', () {
      expect(DebtReminderStore.decode('no es json'), isEmpty);
      expect(DebtReminderStore.decode('[{"customerId":"c1"}]'), isEmpty);
      expect(DebtReminderStore.decode(null), isEmpty);
    });
  });

  group('aviso', () {
    test('texto del aviso', () {
      expect(DebtReminderSchedule.notificationTitle('Ana'), 'Hoy toca cobrarle a Ana');
      expect(DebtReminderSchedule.notificationBody(5000, 'COP'), contains('WhatsApp'));
      expect(DebtReminderSchedule.frequencyText(7), 'Cada semana');
      expect(DebtReminderSchedule.frequencyText(3), 'Cada 3 días');
    });

    test('cada cliente tiene sus propios ids, lejos de los demás avisos', () {
      final a = PhoneAlertsService.debtNotificationIds('cliente-a');
      final b = PhoneAlertsService.debtNotificationIds('cliente-b');
      expect(a.toSet(), hasLength(PhoneAlertsService.debtOccurrences));
      expect(a.toSet().intersection(b.toSet()), isEmpty);
      expect(a.every((id) => id > 1 && id < 0x7fffffff), isTrue);
    });
  });
}
