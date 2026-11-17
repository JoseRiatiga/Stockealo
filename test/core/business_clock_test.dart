import 'package:flutter_test/flutter_test.dart';
import 'package:stockealo/core/services/supabase_service.dart';
import 'package:stockealo/core/utils/business_clock.dart';
import 'package:stockealo/core/utils/countries.dart';
import 'package:stockealo/features/business/models/business.dart';

/// 0.16.6, hora del negocio (camino simple): la app toma la hora del reloj del país
/// del negocio aunque el equipo tenga otra zona.
void main() {
  DateTime wall(String zone, DateTime utc) => BusinessClock.wallAt(utc, BusinessClock.locationOf(zone)!);

  test('Bogotá, Ciudad de México, Lima y Madrid a la misma hora', () {
    final instant = DateTime.utc(2026, 11, 17, 22, 4); // 22:04 UTC
    expect(wall('America/Bogota', instant), DateTime(2026, 11, 17, 17, 4));
    expect(wall('America/Mexico_City', instant), DateTime(2026, 11, 17, 16, 4));
    expect(wall('America/Lima', instant), DateTime(2026, 11, 17, 17, 4));
    expect(wall('Europe/Madrid', instant), DateTime(2026, 11, 17, 23, 4));
  });

  test('Medianoche: una venta a las 11 p. m. en Bogotá sigue siendo de ese día', () {
    final instant = DateTime.utc(2026, 11, 18, 4, 0); // 4:00 UTC del 18
    expect(wall('America/Bogota', instant), DateTime(2026, 11, 17, 23, 0));
  });

  test('Horario de verano en Nueva York, Santiago y Madrid', () {
    // Nueva York: el 8 mar 2026 a las 2:00 pasa a 3:00 (UTC-5 → UTC-4)
    expect(wall('America/New_York', DateTime.utc(2026, 3, 8, 6, 59)), DateTime(2026, 3, 8, 1, 59));
    expect(wall('America/New_York', DateTime.utc(2026, 3, 8, 7, 0)), DateTime(2026, 3, 8, 3, 0));
    // Nueva York: el 1 nov 2026 vuelve a UTC-5
    expect(wall('America/New_York', DateTime.utc(2026, 11, 1, 5, 30)), DateTime(2026, 11, 1, 1, 30));
    expect(wall('America/New_York', DateTime.utc(2026, 11, 1, 6, 30)), DateTime(2026, 11, 1, 1, 30));
    // Madrid: el 29 mar 2026 a las 2:00 pasa a 3:00
    expect(wall('Europe/Madrid', DateTime.utc(2026, 3, 29, 1, 0)), DateTime(2026, 3, 29, 3, 0));
    // Santiago: invierno (UTC-4) y verano (UTC-3)
    expect(wall('America/Santiago', DateTime.utc(2026, 7, 1, 12)), DateTime(2026, 7, 1, 8));
    expect(wall('America/Santiago', DateTime.utc(2026, 12, 1, 12)), DateTime(2026, 12, 1, 9));
  });

  test('Sin zona usa la hora del equipo; con zona desconocida también', () {
    // Con FORCE_BUSINESS_ZONE toda zona se cambia por la forzada: no aplica
    if (const String.fromEnvironment('FORCE_BUSINESS_ZONE').isNotEmpty) return;
    BusinessClock.use(null);
    expect(appNow().difference(DateTime.now()).inSeconds.abs(), lessThan(2));
    BusinessClock.use('Marte/Olympus');
    expect(BusinessClock.zone, isNull);
    expect(appNow().difference(DateTime.now()).inSeconds.abs(), lessThan(2));
  });

  test('Con zona del negocio, appNow da la hora de allá', () {
    BusinessClock.use('Pacific/Kiritimati'); // UTC+14: casi seguro distinta a la del equipo
    final expected = wall('Pacific/Kiritimati', DateTime.now().toUtc());
    expect(appNow().difference(expected).inSeconds.abs(), lessThan(2));
    BusinessClock.use(null);
  });

  test('El rango para la nube va en el marco de la hora del reloj', () {
    expect(BusinessClock.cloudIso(DateTime(2026, 11, 17)), '2026-11-17T00:00:00.000Z');
    expect(BusinessClock.cloudIso(DateTime(2026, 11, 17, 19, 30)), '2026-11-17T19:30:00.000Z');
  });

  test('Zona del negocio: la del país o la elegida en EE. UU. y México', () {
    Business biz(String country, [String? zone]) =>
        Business(id: 'b', userId: 'u', name: 'N', country: country, timeZone: zone, createdAt: DateTime(2026));
    expect(biz('CO').zone, 'America/Bogota');
    expect(biz('US').zone, 'America/New_York');
    expect(biz('US', 'America/Los_Angeles').zone, 'America/Los_Angeles');
    expect(biz('MX').zone, 'America/Mexico_City');
    expect(biz('CO', 'America/Los_Angeles').zone, 'America/Bogota', reason: 'una zona de otro país no vale');
    for (final c in kCountries) {
      for (final (id, _) in c.timeZones) {
        expect(BusinessClock.locationOf(id), isNotNull, reason: id);
      }
    }
  });

  test('Comprobante, vendedor y descuento: solo los que tienen algo', () {
    expect(SupabaseService.receiptCloudFields({'invoice_number': '#A1', 'seller_name': 'Ana', 'discount_amount': 500}),
        {'invoice_number': '#A1', 'seller_name': 'Ana', 'discount_amount': 500});
    expect(SupabaseService.receiptCloudFields({'invoice_number': '', 'seller_name': null, 'discount_amount': 0}), isEmpty);
  });
}
