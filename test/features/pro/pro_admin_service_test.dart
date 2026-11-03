import 'package:flutter_test/flutter_test.dart';
import 'package:stockealo/features/pro/data/pro_admin_service.dart';

void main() {
  test('los códigos se leen de la fila del servidor', () {
    final code = ProCode.fromRow({
      'code': 'STK-ABCD-EFGH',
      'kind': 'global',
      'days': 30,
      'max_uses': 2,
      'uses': 2,
      'note': 'Prueba',
      'created_at': '2026-10-31T10:00:00Z',
      'redeemed_by': 'ana@correo.com, luis@correo.com',
    });
    expect(code.kindLabel, 'Pro Global');
    expect(code.durationLabel, '1 mes');
    expect(code.exhausted, isTrue);
    expect(code.redeemedBy, contains('ana@correo.com'));
  });

  test('un código sin días es permanente y sin usos no está agotado', () {
    final code = ProCode.fromRow({
      'code': 'STK-ABCD-EFGH',
      'kind': 'business',
      'days': null,
      'max_uses': 1,
      'uses': 0,
      'note': null,
      'created_at': '2026-10-31T10:00:00Z',
    });
    expect(code.kindLabel, 'Pro Negocio');
    expect(code.durationLabel, 'Permanente');
    expect(code.exhausted, isFalse);
  });

  test('cada error del servidor tiene su mensaje', () {
    expect(ProAdminService.errorMessage('admin_only'), contains('no es administradora'));
    expect(ProAdminService.errorMessage('invalid_count'), contains('1 a 50'));
    expect(ProAdminService.errorMessage('invalid_days'), contains('días'));
    expect(ProAdminService.errorMessage('otra cosa'), contains('Inténtalo de nuevo'));
  });

  test('estado de un código: sin usar, con usos, usado o vencido', () {
    final now = DateTime(2026, 11, 3);
    ProCode code({int uses = 0, int maxUses = 1, DateTime? expiresAt}) => ProCode(
          code: 'STK-AAAA-BBBB',
          kind: 'business',
          days: 30,
          maxUses: maxUses,
          uses: uses,
          note: null,
          createdAt: now,
          expiresAt: expiresAt,
        );
    expect(code().statusLabel(now), 'Sin usar');
    expect(code().canDisable(now), isTrue);
    expect(code(uses: 1, maxUses: 3).statusLabel(now), '1/3 usos');
    expect(code(uses: 1).statusLabel(now), 'Usado');
    expect(code(uses: 1).canDisable(now), isFalse);
    final expired = code(expiresAt: now.subtract(const Duration(minutes: 1)));
    expect(expired.statusLabel(now), 'Vencido');
    expect(expired.canDisable(now), isFalse);
    expect(code().shareMessage(), contains('STK-AAAA-BBBB'));
    expect(code().shareMessage(), contains('Ajustes › Stockealo Pro'));
  });

  test('resumen, tiendas, suscripciones y configuración se leen del servidor', () {
    final summary = AdminSummary.fromJson({'users_total': 3, 'users_7d': 1, 'stores_live': 2});
    expect(summary.usersTotal, 3);
    expect(summary.storesLive, 2);
    expect(summary.businessesPro, 0);

    final store = AdminStore.fromRow({'business_id': 'b1', 'business_name': 'Ana', 'slug': 'ana', 'enabled': true, 'pro': false});
    expect(store.live, isFalse);
    expect(store.statusLabel, 'Sin Pro (no se ve)');
    expect(store.url, 'https://stockealo.online/tienda/ana');

    final sub = AdminSubscription.fromRow({
      'id': 's1',
      'kind': 'business',
      'owner_email': 'ana@x.com',
      'source': 'manual',
      'ends_at': DateTime.now().add(const Duration(days: 2)).toUtc().toIso8601String(),
      'active': true,
    });
    expect(sub.sourceLabel, 'Dado a mano');
    expect(sub.endingSoon(), isTrue);

    final config = AdminConfig.fromJson({
      'settings': {'nequi_number': '300', 'nequi_name': null, 'whatsapp': '+57300'},
      'plans': [
        {'id': 'p', 'kind': 'global', 'period': 'month', 'currency': 'COP', 'price': 16900, 'active': true},
      ],
    });
    expect(config.missingPaymentData, isTrue);
    expect(config.plans.single.name, 'Pro Global · Mensual');
  });
}
