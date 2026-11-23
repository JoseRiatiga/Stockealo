import 'package:flutter_test/flutter_test.dart';
import 'package:stockealo/core/utils/business_clock.dart';
import 'package:stockealo/core/utils/currency_formatter.dart';
import 'package:stockealo/features/store/data/booking_service.dart';
import 'package:stockealo/features/store/data/online_store_service.dart';

void main() {
  tearDown(() {
    BusinessClock.use(null);
    CurrencyFormatter.useCurrency('COP');
  });

  test('una hora del negocio y su hora real, en Bogotá, Madrid y Nueva York (0.16.9)', () {
    // 3 p. m. en Bogotá = 8 p. m. UTC
    expect(BusinessClock.instantOf(DateTime(2026, 11, 22, 15), zone: 'America/Bogota'), DateTime.utc(2026, 11, 22, 20));
    expect(BusinessClock.wallOf(DateTime.utc(2026, 11, 22, 20), zone: 'America/Bogota'), DateTime(2026, 11, 22, 15));
    // Madrid en invierno: UTC+1
    expect(BusinessClock.instantOf(DateTime(2026, 12, 1, 10), zone: 'Europe/Madrid'), DateTime.utc(2026, 12, 1, 9));
    // Nueva York con horario de verano (julio, UTC-4) y sin él (diciembre, UTC-5)
    expect(BusinessClock.instantOf(DateTime(2026, 7, 1, 9), zone: 'America/New_York'), DateTime.utc(2026, 7, 1, 13));
    expect(BusinessClock.instantOf(DateTime(2026, 12, 1, 9), zone: 'America/New_York'), DateTime.utc(2026, 12, 1, 14));
    // Sin zona: la del negocio activo
    BusinessClock.use('America/Bogota');
    expect(BusinessClock.instantOf(DateTime(2026, 11, 22, 8)), DateTime.utc(2026, 11, 22, 13));
    expect(BusinessClock.wallOf(DateTime.utc(2026, 11, 22, 13)), DateTime(2026, 11, 22, 8));
  });

  test('la reserva muestra lo ocupado con la hora del negocio y guarda la hora real', () {
    final booking = PublicBooking.fromJson({
      'time_zone': 'America/Bogota',
      'services': [
        {'id': 's1', 'name': 'Corte', 'price': 20000, 'duration_min': 30},
      ],
      'staff': [],
      'busy': [
        {'staff_id': null, 'starts_at': '2026-11-23T14:00:00+00:00', 'ends_at': '2026-11-23T14:30:00+00:00'},
      ],
    });
    expect(booking.zone, 'America/Bogota');
    // Las 9 a. m. de Bogotá están ocupadas, sin importar la zona del celular de quien reserva
    expect(booking.busy.single.start, DateTime(2026, 11, 23, 9));
    final slots = booking.freeSlots(DateTime(2026, 11, 23), 30, now: DateTime(2026, 11, 22, 12));
    expect(slots, isNot(contains(DateTime(2026, 11, 23, 9))));
    expect(slots, contains(DateTime(2026, 11, 23, 9, 30)));
    expect(booking.instantOf(DateTime(2026, 11, 23, 9, 30)), DateTime.utc(2026, 11, 23, 14, 30));
  });

  test('la dirección del local: sale si existe y no está apagada', () {
    final json = {
      'slug': 'x',
      'business': {'name': 'Barbería', 'address': 'Cra. 7 # 12-34', 'time_zone': 'America/Bogota'},
      'look': {},
      'products': [],
    };
    final store = PublicStore.fromJson(json);
    expect(store.shownAddress, 'Cra. 7 # 12-34');
    expect(store.timeZone, 'America/Bogota');
    expect(PublicStore.fromJson({...json, 'look': {'address': false}}).shownAddress, isNull);
    expect(PublicStore.fromJson({...json, 'business': {'name': 'B'}}).shownAddress, isNull);
    expect(PublicStore.mapsUrl('Cra. 7 # 12-34', businessName: 'Barbería').toString(),
        'https://www.google.com/maps/search/?api=1&query=Barber%C3%ADa%2C%20Cra.%207%20%23%2012-34');
  });

  test('precios con o sin centavos según la moneda', () {
    CurrencyFormatter.useCurrency('COP');
    expect(CurrencyFormatter.noCents, isTrue);
    CurrencyFormatter.useCurrency('USD');
    expect(CurrencyFormatter.noCents, isFalse);
    CurrencyFormatter.useCurrency('MXN');
    expect(CurrencyFormatter.noCents, isFalse);
  });
}
