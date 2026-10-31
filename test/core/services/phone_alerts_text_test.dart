import 'package:flutter_test/flutter_test.dart';
import 'package:stockealo/core/services/phone_alerts_service.dart';

void main() {
  test('resumen con ventas y productos por reponer', () {
    expect(
      PhoneAlertsService.summaryText(salesCount: 12, total: 350000, profit: 120000, toRestock: 3, currency: 'COP'),
      'Hoy: 12 ventas por \$350.000, ganancia \$120.000. 3 productos por reponer.',
    );
  });

  test('resumen sin ventas, en singular y sin faltantes', () {
    expect(
      PhoneAlertsService.summaryText(salesCount: 0, total: 0, profit: 0, toRestock: 1, currency: 'COP'),
      'Hoy no registraste ventas. 1 producto por reponer.',
    );
    expect(
      PhoneAlertsService.summaryText(salesCount: 1, total: 5000, profit: 2000, toRestock: 0, currency: 'COP'),
      'Hoy: 1 venta por \$5.000, ganancia \$2.000.',
    );
  });
}
