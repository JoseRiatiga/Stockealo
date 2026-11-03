import 'package:flutter_test/flutter_test.dart';
import 'package:stockealo/features/pro/data/pro_admin_service.dart';
import 'package:stockealo/features/pro/data/pro_service.dart';

void main() {
  test('el estado de Wompi se traduce al de la app', () {
    expect(ProService.paymentStateFrom('APPROVED'), ProPaymentState.approved);
    expect(ProService.paymentStateFrom('DECLINED'), ProPaymentState.declined);
    expect(ProService.paymentStateFrom('VOIDED'), ProPaymentState.declined);
    expect(ProService.paymentStateFrom('ERROR'), ProPaymentState.error);
    expect(ProService.paymentStateFrom('PENDING'), ProPaymentState.pending);
    expect(ProService.paymentStateFrom(null), ProPaymentState.pending);
  });

  test('cada error al iniciar el pago tiene su mensaje', () {
    expect(ProService.checkoutErrorMessage('not_allowed'), contains('dueño'));
    expect(ProService.checkoutErrorMessage('currency_not_supported'), contains('pesos colombianos'));
    expect(ProService.checkoutErrorMessage('payments_not_configured'), contains('Nequi'));
    expect(ProService.checkoutErrorMessage('otra cosa'), contains('Inténtalo de nuevo'));
  });

  test('un pago del panel se lee del servidor con sus etiquetas', () {
    final p = AdminPayment.fromRow({
      'reference': 'STK-ABC',
      'business_name': 'Tienda Ana',
      'user_email': 'ana@x.com',
      'kind': 'business',
      'period': 'month',
      'amount_in_cents': 690000,
      'currency': 'COP',
      'status': 'APPROVED',
      'payment_method': 'NEQUI',
      'created_at': '2026-11-03T10:00:00Z',
    });
    expect(p.amount, 6900);
    expect(p.planLabel, 'Pro Negocio · Mensual');
    expect(p.statusLabel, 'Aprobado');
    expect(p.methodLabel, 'Nequi');
    expect(AdminPayment.fromRow({...{'reference': 'X', 'status': 'DECLINED'}}).statusLabel, 'Rechazado');
  });
}
