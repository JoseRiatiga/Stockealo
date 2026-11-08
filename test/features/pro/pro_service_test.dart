import 'package:flutter_test/flutter_test.dart';
import 'package:stockealo/features/pro/data/pro_service.dart';

void main() {
  test('cada error del servidor tiene su mensaje', () {
    expect(ProService.redeemErrorMessage('code_not_found'), contains('no existe'));
    expect(ProService.redeemErrorMessage('ERROR: code_expired'), contains('venció'));
    expect(ProService.redeemErrorMessage('code_already_redeemed'), 'Ya canjeaste ese código.');
    expect(ProService.redeemErrorMessage('code_used'), contains('ya fue usado'));
    expect(ProService.redeemErrorMessage('owner_only'), contains('Solo el dueño'));
    expect(ProService.redeemErrorMessage('otra cosa'), contains('Inténtalo de nuevo'));
    // El negocio no existe en la nube: no decir "Solo el dueño" a quien sí es el dueño
    expect(ProService.redeemErrorMessage('not_member'), ProService.notInCloudMessage);
  });

  test('el código se limpia y recupera los guiones si no los escribieron', () {
    expect(ProService.normalizeCode(' stk-ja4y-fvfv '), 'STK-JA4Y-FVFV');
    expect(ProService.normalizeCode('STKJA4YFVFV'), 'STK-JA4Y-FVFV');
    expect(ProService.normalizeCode('stk ja4y fvfv'), 'STK-JA4Y-FVFV');
    expect(ProService.normalizeCode('OTRO-CODIGO'), 'OTRO-CODIGO');
    expect(ProService.normalizeCode('   '), '');
  });

  test('los planes se leen de la fila de Supabase', () {
    final plan = ProPlan.fromRow({
      'id': 'business_lifetime_cop',
      'kind': 'business',
      'period': 'lifetime',
      'currency': 'COP',
      'price': 39900,
      'regular_price': 69900,
      'label': 'Fundador',
    });
    expect(plan.price, 39900);
    expect(plan.regularPrice, 69900);
    expect(plan.periodLabel, 'Permanente');
    expect(plan.perLabel, 'un solo pago');
  });

  test('Pro permanente no tiene fecha de fin', () {
    const lifetime = ProStatus(active: true, kind: 'global');
    expect(lifetime.lifetime, isTrue);
    expect(lifetime.kindLabel, 'Pro Global');
    expect(ProStatus.none.lifetime, isFalse);
  });
}
