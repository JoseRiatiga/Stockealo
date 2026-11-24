import 'package:flutter_test/flutter_test.dart';
import 'package:stockealo/features/pro/data/pro_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

  test('«not_member» de un negocio que aún sube no es un error del estado Pro', () {
    expect(ProService.isNotMember(const PostgrestException(message: 'not_member', code: 'P0001')), isTrue);
    expect(ProService.isNotMember(const PostgrestException(message: 'otra cosa')), isFalse);
    expect(ProService.isNotMember(StateError('not_member')), isFalse);
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

  group('Pro Servicios (0.12.0)', () {
    test('cada plan tiene su nombre', () {
      expect(proKindLabel('business'), 'Pro');
      expect(proKindLabel('global'), 'Pro Global');
      expect(proKindLabel('services'), 'Pro Servicios');
      expect(proKindLabel(null), 'Pro');
      expect(const ProStatus(active: true, kind: 'services', services: true).kindLabel, 'Pro Servicios');
    });

    test('sin Pro Servicios no hay módulo Servicios', () {
      expect(ProStatus.none.services, isFalse);
      expect(const ProStatus(active: true, kind: 'global').services, isFalse);
    });

    test('precios y compra solo se ven con el interruptor encendido', () {
      expect(ProService.pricingVisible({'show_pricing': 'on'}), isTrue);
      expect(ProService.pricingVisible({'show_pricing': 'off'}), isFalse);
      // Sin el ajuste (migración sin aplicar) quedan ocultos
      expect(ProService.pricingVisible({}), isFalse);
    });

    test('el plan de Pro Servicios se lee de su fila', () {
      final plan = ProPlan.fromRow({
        'id': 'services_month_cop',
        'kind': 'services',
        'period': 'month',
        'currency': 'COP',
        'price': 40000,
      });
      expect(plan.kindLabel, 'Pro Servicios');
      expect(plan.periodLabel, 'Mensual');
    });
  });

  group('Pro y Pro Servicios a la vez (24 nov)', () {
    final services = DateTime(2026, 12, 11);
    final pro = DateTime(2027, 1, 10);

    test('se ve la fecha de Pro Servicios y el Pro que sigue', () {
      final s = ProStatus(active: true, kind: 'services', services: true, endsAt: pro, servicesEndsAt: services);
      expect(s.planEndsAt, services);
      expect(s.proAfterServices, pro);
      expect(proUntilText(s), 'Pro Servicios hasta el 11/12/2026 · después Pro hasta el 10/1/2027');
    });

    test('solo Pro Servicios: sin «después»', () {
      final s = ProStatus(active: true, kind: 'services', services: true, endsAt: services, servicesEndsAt: services);
      expect(s.proAfterServices, isNull);
      expect(proUntilText(s), 'Pro Servicios hasta el 11/12/2026');
    });

    test('solo Pro: igual que antes', () {
      final s = ProStatus(active: true, kind: 'business', endsAt: pro);
      expect(s.planEndsAt, pro);
      expect(proUntilText(s), 'Pro hasta el 10/1/2027');
    });
  });

  test('sin conexión, Pro Servicios vencido con Pro que sigue queda solo Pro (Codex, 24 nov)', () {
    final m = {
      'active': true,
      'kind': 'services',
      'ends_at': DateTime(2027, 1, 10).toIso8601String(),
      'services': true,
      'services_ends_at': DateTime(2026, 12, 11).toIso8601String(),
    };
    final before = ProService.decodeCached(m, now: DateTime(2026, 12, 1))!;
    expect(before.services, isTrue);
    final after = ProService.decodeCached(m, now: DateTime(2026, 12, 20))!;
    expect(after.services, isFalse);
    expect(after.kindLabel, 'Pro');
    expect(ProService.decodeCached(m, now: DateTime(2027, 2, 1)), isNull);
  });
}
